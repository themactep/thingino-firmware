// SPDX-License-Identifier: GPL-2.0+
/*
 * motor.c - Ingenic motor driver
 * (c) 2015 Ingenic Semiconductor Co.,Ltd
 * (c) 2025 Thingino Project
 */

#include <linux/clk.h>
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/file.h>
#include <linux/fs.h>
#include <linux/gpio.h>
#include <linux/interrupt.h>
#include <linux/kthread.h>
#include <linux/list.h>
#include <linux/mempolicy.h>
#include <linux/mfd/core.h>
#include <linux/miscdevice.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pwm.h>
#include <linux/sched.h>
#include <linux/time.h>

#if defined(CONFIG_SOC_T40)
#include <dt-bindings/interrupt-controller/t40-irq.h>
#endif
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
#include <linux/mfd/ingenic-tcu.h>
#else
#include <linux/mfd/jz_tcu.h>
#include <mach/platform.h>
#include <soc/irq.h>
#endif

#include "tcu_alloc.h"

#define MOTOR_MAX_TCU 8
static char *motor_tcu_channels;
module_param_named(tcu_channels, motor_tcu_channels, charp, 0644);
MODULE_PARM_DESC(tcu_channels, "Comma-separated TCU channels for motor (e.g., 2 or 2,3)");

static int motor_bind_channel = 2; /* first channel parsed; used for binding */
static void motor_parse_channels(void)
{
	if (motor_tcu_channels && *motor_tcu_channels) {
		char *str = kstrdup(motor_tcu_channels, GFP_KERNEL);
		char *p = str, *tok;
		if (!str)
			return;
		while ((tok = strsep(&p, ",")) != NULL) {
			unsigned long v;
			if (!kstrtoul(tok, 0, &v) && v < MOTOR_MAX_TCU) {
				motor_bind_channel = (int)v; /* pick first valid for binding */
				break;
			}
		}
		kfree(str);
	}
}

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
static struct of_device_id motor_match_dynamic[2];
static char motor_match_str[32];
#endif

static char motor_driver_name[16] = "tcu_chn2";

#include <soc/base.h>
#include <soc/extal.h>
#include <soc/gpio.h>

#include <asm/io.h>
#include <asm/irq.h>
#include <asm/uaccess.h>
#include <asm/cacheflush.h>

#include "motor.h"

#define JZ_MOTOR_DRIVER_VERSION "H20171204a"

#define HMOTOR2VMOTORRATIO 1

static unsigned int hmotor2vmotor = 1;
module_param(hmotor2vmotor, int, S_IRUGO);
MODULE_PARM_DESC(hmotor2vmotor, "Pan/tilt speed ratio");

/*
 * Motors GPIOs
 */

/* Pan motor */

int hst1 = -1;
module_param(hst1, int, S_IRUGO);
MODULE_PARM_DESC(hst1, "Pan motor Phase A pin");

int hst2 = -1;
module_param(hst2, int, S_IRUGO);
MODULE_PARM_DESC(hst2, "Pan motor Phase B pin");

int hst3 = -1;
module_param(hst3, int, S_IRUGO);
MODULE_PARM_DESC(hst3, "Pan motor Phase C pin");

int hst4 = -1;
module_param(hst4, int, S_IRUGO);
MODULE_PARM_DESC(hst4, "Pan motor Phase D pin");

/* Tilt motor */

int vst1 = -1;
module_param(vst1, int, S_IRUGO);
MODULE_PARM_DESC(vst1, "Tilt motor Phase A pin");

int vst2 = -1;
module_param(vst2, int, S_IRUGO);
MODULE_PARM_DESC(vst2, "Tilt motor Phase B pin");

int vst3 = -1;
module_param(vst3, int, S_IRUGO);
MODULE_PARM_DESC(vst3, "Tilt motor Phase C pin");

int vst4 = -1;
module_param(vst4, int, S_IRUGO);
MODULE_PARM_DESC(vst4, "Tilt motor Phase D pin");

/*
 * Motors GPIOs for direction control
 */

int motor_switch_gpio = -1;
module_param(motor_switch_gpio, int, S_IRUGO);
MODULE_PARM_DESC(motor_switch_gpio, "Motor switching GPIO");

int invert_gpio_dir = 0;
module_param(invert_gpio_dir, int, S_IRUGO);
MODULE_PARM_DESC(invert_gpio_dir, "Invert motor GPIO values. Default: 0 (no)");

// invert_direction_polarity allows the user to invert the output polarity of the direction GPIO.
// Set to 0 for normal polarity (default), or 1 to invert the direction GPIO output.
int invert_direction_polarity = 1;
module_param(invert_direction_polarity, int, S_IRUGO);
MODULE_PARM_DESC(invert_direction_polarity, "0: normal polarity, 1: invert motor_switch_gpio output");

/*
 * Motors motion parameters
 *
 *  0 - motor lower physical motion limit
 *  (axis)min - motor start point
 *  (axis)max - motor stop point
 *  (axis)maxstep - motor upper physical motion limit
 *
 *   0 ---- hmin --------------- hmax ---- hmaxstep
 */

/* Pan motor */

static unsigned int hmaxstep = -1;
module_param(hmaxstep, int, S_IRUGO);
MODULE_PARM_DESC(hmaxstep, "The max steps of pan motor");

int hmin = -1;
module_param(hmin, int, S_IRUGO);
MODULE_PARM_DESC(hmin, "Pan motor start point GPIO");

int hmax = -1;
module_param(hmax, int, S_IRUGO);
MODULE_PARM_DESC(hmax, "Pan motor stop point GPIO");

/* Tilt motor */

static unsigned int vmaxstep = -1;
module_param(vmaxstep, int, S_IRUGO);
MODULE_PARM_DESC(vmaxstep, "The max steps of tilt motor");

int vmin = -1;
module_param(vmin, int, S_IRUGO);
MODULE_PARM_DESC(vmin, "Tilt motor start point GPIO");

int vmax = -1;
module_param(vmax, int, S_IRUGO);
MODULE_PARM_DESC(vmax, "Tilt motor stop point GPIO");

struct motor_platform_data motors_pdata[NUMBER_OF_MOTORS] = {
	{
		.name = "Pan motor",
		.motor_st1_gpio = -1,
		.motor_st2_gpio = -1,
		.motor_st3_gpio = -1,
		.motor_st4_gpio = -1,
		.motor_switch_gpio = -1,
	},
	{
		.name = "Tilt motor",
		.motor_st1_gpio = -1,
		.motor_st2_gpio = -1,
		.motor_st3_gpio = -1,
		.motor_st4_gpio = -1,
	},
};

static unsigned char step_8[8] = {
	0x08,
	0x0c,
	0x04,
	0x06,
	0x02,
	0x03,
	0x01,
	0x09
};

static char skip_move_mode[4][4] = {
	{2, 0, 0, 0},
	{3, 2, 0, 0},
	{4, 3, 2, 0},
	{4, 3, 2, 1}
};

// motor_set_direction sets the direction GPIO based on the move_direction value.
// If invert_direction_polarity is set, the output is inverted.
static void motor_set_direction(struct motor_device *mdev, int move_direction)
{
	if (motor_switch_gpio != -1) {
		int gpio_value = (move_direction == MOTOR_MOVE_RIGHT_UP) ? 1 : 0;
		if (invert_direction_polarity) {
			gpio_value = !gpio_value;
		}
		gpio_set_value(motor_switch_gpio, gpio_value);
	}
}

// motor_power_off disables all motor GPIO pins to cut power
// When gpio_invert=true (invert_gpio_dir=1): set to HIGH (1) to cut power
// When gpio_invert=false (invert_gpio_dir=0): set to LOW (0) to cut power
static void motor_power_off(struct motor_device *mdev)
{
	int index;
	int value;
	struct motor_driver *motor = NULL;

	/* Power-off state depends on inversion setting */
	/* invert_gpio_dir=1 (true): LOW=energize, HIGH=cut -> value=1 */
	/* invert_gpio_dir=0 (false): HIGH=energize, LOW=cut -> value=0 */
	value = (invert_gpio_dir & 0x1);

	for (index = 0; index < NUMBER_OF_MOTORS; index++) {
		motor = &mdev->motors[index];

		if (motor->pdata->motor_st1_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st1_gpio, value);
		if (motor->pdata->motor_st2_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st2_gpio, value);
		if (motor->pdata->motor_st3_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st3_gpio, value);
		if (motor->pdata->motor_st4_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st4_gpio, value);
	}
}

// motor_power_on re-enables motor GPIO pins as outputs
// Called before motor movement to energize the coils
static void motor_power_on(struct motor_device *mdev)
{
	int index;
	int value;
	struct motor_driver *motor = NULL;

	value = ((0 ^ invert_gpio_dir) & 0x1);

	for (index = 0; index < NUMBER_OF_MOTORS; index++) {
		motor = &mdev->motors[index];

		if (motor->pdata->motor_st1_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st1_gpio, value);
		if (motor->pdata->motor_st2_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st2_gpio, value);
		if (motor->pdata->motor_st3_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st3_gpio, value);
		if (motor->pdata->motor_st4_gpio != -1)
			gpio_direction_output(motor->pdata->motor_st4_gpio, value);
	}
}

static void motor_set_default(struct motor_device *mdev)
{
	int index;
	struct motor_driver *motor = NULL;
	mdev->dev_state = MOTOR_OPS_STOP;

	for (index = 0; index < NUMBER_OF_MOTORS; index++) {
		motor = &mdev->motors[index];
		motor->state = MOTOR_OPS_STOP;
	}

	/* Cut power to motor coils */
	motor_power_off(mdev);

	return;
}

static void motor_move_step(struct motor_device *mdev, int index)
{
	int step;
	int value;

	struct motor_driver *motor = NULL;

	motor = &mdev->motors[index];
	/*
	 * Called from jz_timer_interrupt(). Use gpio_set_value(), never
	 * gpio_direction_output(): the latter takes the pinctrl mutex and
	 * would sleep in atomic context (BUG at kernel/locking/mutex.c).
	 * Directions are established in motor_power_on/off at move start.
	 */
	if (motor->state != MOTOR_OPS_STOP) {
		step = motor->cur_steps % 8;
		step = step < 0 ? step + 8 : step;

	        value = (step_8[step] ^ 0xff);

		motor_set_direction(mdev, (index == PAN_MOTOR) ? MOTOR_MOVE_RIGHT_UP : MOTOR_MOVE_LEFT_DOWN);

		if (motor->pdata->motor_st1_gpio != -1)
			gpio_set_value(motor->pdata->motor_st1_gpio, value & 0x8);
		if (motor->pdata->motor_st2_gpio != -1)
			gpio_set_value(motor->pdata->motor_st2_gpio, value & 0x4);
		if (motor->pdata->motor_st3_gpio != -1)
			gpio_set_value(motor->pdata->motor_st3_gpio, value & 0x2);
		if (motor->pdata->motor_st4_gpio != -1)
			gpio_set_value(motor->pdata->motor_st4_gpio, value & 0x1);
	} else {
		value = ((0 ^ invert_gpio_dir) & 0x1);

		if (motor->pdata->motor_st1_gpio != -1)
			gpio_set_value(motor->pdata->motor_st1_gpio, value);
		if (motor->pdata->motor_st2_gpio != -1)
			gpio_set_value(motor->pdata->motor_st2_gpio, value);
		if (motor->pdata->motor_st3_gpio != -1)
			gpio_set_value(motor->pdata->motor_st3_gpio, value);
		if (motor->pdata->motor_st4_gpio != -1)
			gpio_set_value(motor->pdata->motor_st4_gpio, value);
	}

	if (motor->state == MOTOR_OPS_RESET) {
		motor->total_steps++;
	}

	return;
}

static void move_to_min_pose_ops(struct motor_driver *motor)
{
	if (motor->state == MOTOR_OPS_RESET) {
		if (motor->move_dir == MOTOR_MOVE_LEFT_DOWN) {
			motor->state = MOTOR_OPS_STOP;
		}
	} else {
		motor->move_dir = MOTOR_MOVE_RIGHT_UP;
	}

	motor->cur_steps = 0;
}

static void move_to_max_pose_ops(struct motor_driver *motor, int index)
{
	if (motor->state == MOTOR_OPS_RESET) {
		motor->state = MOTOR_OPS_STOP;
		if (index == PAN_MOTOR)
			motor->max_steps = hmaxstep;
		else
			motor->max_steps = vmaxstep;
		complete(&motor->reset_completion);
		motor->move_dir = MOTOR_MOVE_LEFT_DOWN;
	} else if (motor->state == MOTOR_OPS_NORMAL) {
		if (motor->move_dir == MOTOR_MOVE_RIGHT_UP)
			motor->state = MOTOR_OPS_STOP;
	} else {
		motor->move_dir = MOTOR_MOVE_LEFT_DOWN;
	}

	motor->cur_steps = motor->max_steps;
}

static inline void calc_slow_mode(struct motor_device *mdev, unsigned int steps)
{
	int index;

	index = steps / 10;
	index = index > 3 ? 3 : index;
	mdev->skip_mode = skip_move_mode[index];
}

/* return: 1 --> move, 0 --> don't move */
static inline int whether_move_func(struct motor_device *mdev, unsigned int remainder)
{
	if (remainder == 0)
		return 0;

	remainder = remainder / 10;
	remainder = remainder > 3 ? 3: remainder;

	if (mdev->counter % mdev->skip_mode[remainder] == 0)
		return 1;

	return 0;
}

static irqreturn_t jz_timer_interrupt(int irq, void *dev_id)
{
	struct motor_device *mdev = dev_id;
	struct motor_move *dst = &mdev->dst_move;
	struct motor_move *cur = &mdev->cur_move;
	struct motor_driver *motors = mdev->motors;

	if (motors[PAN_MOTOR].state == MOTOR_OPS_STOP && motors[TILT_MOTOR].state == MOTOR_OPS_STOP) {
		mdev->dev_state = MOTOR_OPS_STOP;

		motor_move_step(mdev, PAN_MOTOR);
		motor_move_step(mdev, TILT_MOTOR);

		if (mdev->wait_stop) {
			mdev->wait_stop = 0;
			complete(&mdev->stop_completion);
		}

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
		ingenic_tcu_counter_stop(mdev->tcu);
#else
		jz_tcu_disable_counter(mdev->tcu);
#endif

		return IRQ_HANDLED;
	}

	if (motors[PAN_MOTOR].cur_steps <= 0)
		move_to_min_pose_ops(&motors[PAN_MOTOR]);

	if (motors[PAN_MOTOR].cur_steps >= motors[PAN_MOTOR].max_steps)
		move_to_max_pose_ops(&motors[PAN_MOTOR],PAN_MOTOR);

	if (motors[TILT_MOTOR].cur_steps <= 0)
		move_to_min_pose_ops(&motors[TILT_MOTOR]);

	if (motors[TILT_MOTOR].cur_steps >= motors[TILT_MOTOR].max_steps)
		move_to_max_pose_ops(&motors[TILT_MOTOR],TILT_MOTOR);

	if (mdev->dev_state == MOTOR_OPS_CRUISE) {
		mdev->counter++;
		motors[PAN_MOTOR].cur_steps += motors[PAN_MOTOR].move_dir;
		if (mdev->counter % hmotor2vmotor == 0)
			motors[TILT_MOTOR].cur_steps += motors[TILT_MOTOR].move_dir;
		motor_move_step(mdev, PAN_MOTOR);
		motor_move_step(mdev, TILT_MOTOR);
	} else if (mdev->dev_state == MOTOR_OPS_RESET) {
		if (motors[PAN_MOTOR].state != MOTOR_OPS_STOP) {
			motors[PAN_MOTOR].cur_steps += motors[PAN_MOTOR].move_dir;
			motor_move_step(mdev, PAN_MOTOR);
			cur->one.x++;
		}
		if (motors[TILT_MOTOR].state != MOTOR_OPS_STOP) {
			motors[TILT_MOTOR].cur_steps += motors[TILT_MOTOR].move_dir;
			motor_move_step(mdev, TILT_MOTOR);
			cur->one.y++;
		}
	} else {
		mdev->counter++;

		if (cur->one.x < dst->one.x && motors[PAN_MOTOR].state != MOTOR_OPS_STOP) {
			if (whether_move_func(mdev, dst->one.x - cur->one.x)) {
				motors[PAN_MOTOR].cur_steps += motors[PAN_MOTOR].move_dir;
				motor_move_step(mdev, PAN_MOTOR);
				cur->one.x++;
			}
		} else {
			motors[PAN_MOTOR].state = MOTOR_OPS_STOP;
		}

		if (cur->one.y < dst->one.y && motors[TILT_MOTOR].state != MOTOR_OPS_STOP) {
			if (mdev->counter % hmotor2vmotor == 0) {
				motors[TILT_MOTOR].cur_steps += motors[TILT_MOTOR].move_dir;
				cur->one.y++;
				motor_move_step(mdev, TILT_MOTOR);
			}
		} else {
			motors[TILT_MOTOR].state = MOTOR_OPS_STOP;
		}
	}

	return IRQ_HANDLED;
}

static long motor_ops_move(struct motor_device *mdev, int x, int y)
{
	struct motor_driver *motors = mdev->motors;

	unsigned long flags;

	int x_dir = MOTOR_MOVE_STOP;
	int y_dir = MOTOR_MOVE_STOP;

	int x1 = 0;
	int y1 = 0;

	/* check x value */
	if (x > 0) {
		if (motors[PAN_MOTOR].cur_steps >= motors[PAN_MOTOR].max_steps)
			x = 0;
	} else {
		if (motors[PAN_MOTOR].cur_steps <= 0)
			x = 0;
	}

	/* check y value */
	if (y > 0) {
		if (motors[TILT_MOTOR].cur_steps >= motors[TILT_MOTOR].max_steps)
			y = 0;
	} else {
		if (motors[TILT_MOTOR].cur_steps <= 0)
			y = 0;
	}

	x_dir = x > 0 ? MOTOR_MOVE_RIGHT_UP : MOTOR_MOVE_LEFT_DOWN;
	y_dir = y > 0 ? MOTOR_MOVE_RIGHT_UP : MOTOR_MOVE_LEFT_DOWN;

	x1 = x < 0 ? 0 - x : x;
	y1 = y < 0 ? 0 - y : y;

	if ((x1 + y1) == 0) {
		return 0;
	}

	/* Enable motor GPIO outputs before movement */
	motor_power_on(mdev);

	mutex_lock(&mdev->dev_mutex);
	spin_lock_irqsave(&mdev->slock, flags);

	calc_slow_mode(mdev, x1);

	mdev->counter = 0;
	mdev->dev_state = MOTOR_OPS_NORMAL;
	mdev->dst_move.one.x = x1;
	mdev->dst_move.one.y = y1;
	mdev->cur_move.one.x = 0;
	mdev->cur_move.one.y = 0;

	motors[PAN_MOTOR].state = MOTOR_OPS_NORMAL;
	motors[PAN_MOTOR].move_dir = x_dir;

	motors[TILT_MOTOR].state = MOTOR_OPS_NORMAL;
	motors[TILT_MOTOR].move_dir = y_dir;

	spin_unlock_irqrestore(&mdev->slock, flags);

	mutex_unlock(&mdev->dev_mutex);

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	ingenic_tcu_counter_begin(mdev->tcu);
#else
	jz_tcu_enable_counter(mdev->tcu);
#endif

	return 0;
}

static void motor_ops_stop(struct motor_device *mdev)
{
	long ret;
	unsigned long flags;
	unsigned int remainder;

	struct motor_driver *motors = mdev->motors;
	struct motor_move *dst = &mdev->dst_move;
	struct motor_move *cur = &mdev->cur_move;

	ret = 0;
	remainder = 0;

	if (mdev->dev_state == MOTOR_OPS_STOP)
		return;

	mutex_lock(&mdev->dev_mutex);
	spin_lock_irqsave(&mdev->slock, flags);

	if (mdev->dev_state == MOTOR_OPS_NORMAL) {
		remainder = dst->one.x - cur->one.x;
		if (remainder > 30) {
			dst->one.x = 29;
			cur->one.x = 0;
		}
		remainder = dst->one.y - cur->one.y;
		if (remainder > 8) {
			dst->one.y = 6;
			cur->one.y = 0;
		}
	}

	if (mdev->dev_state == MOTOR_OPS_CRUISE) {
		mdev->dev_state = MOTOR_OPS_NORMAL;
		motors[PAN_MOTOR].state = MOTOR_OPS_NORMAL;
		motors[TILT_MOTOR].state = MOTOR_OPS_NORMAL;
		dst->one.x = 0;
		cur->one.x = 0;
		dst->one.y = 0;
		cur->one.y = 0;
	}

	mdev->counter = 0;
	mdev->wait_stop = 1;
	spin_unlock_irqrestore(&mdev->slock, flags);
	mutex_unlock(&mdev->dev_mutex);
	do {
		ret = wait_for_completion_interruptible_timeout(&mdev->stop_completion, msecs_to_jiffies(15000));
		if (ret == 0) {
			ret = -ETIMEDOUT;
			break;
		}
	} while (ret == -ERESTARTSYS);
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	ingenic_tcu_counter_stop(mdev->tcu);
#else
	jz_tcu_disable_counter(mdev->tcu);
#endif
	/*mdev->dev_state = MOTOR_OPS_STOP;*/
	/*motors[PAN_MOTOR].state = MOTOR_OPS_STOP;*/
	/*motors[TILT_MOTOR].state = MOTOR_OPS_STOP;*/
	motor_set_default(mdev);

	return;
}

static long motor_ops_goback(struct motor_device *mdev)
{
	struct motor_driver *motors = mdev->motors;

	int sx, sy;
	int cx, cy;

	sx = motors[PAN_MOTOR].max_steps >> 1;
	sy = motors[TILT_MOTOR].max_steps >> 1;
	cx = motors[PAN_MOTOR].cur_steps;
	cy = motors[TILT_MOTOR].cur_steps;

	return motor_ops_move(mdev, sx-cx, sy-cy);
}

static long motor_ops_cruise(struct motor_device *mdev)
{
	struct motor_driver *motors = mdev->motors;

	unsigned long flags;

	motor_ops_goback(mdev);

	/* Enable motor GPIO outputs before cruise */
	motor_power_on(mdev);

	mutex_lock(&mdev->dev_mutex);
	spin_lock_irqsave(&mdev->slock, flags);

	mdev->dev_state = MOTOR_OPS_CRUISE;
	motors[PAN_MOTOR].state = MOTOR_OPS_CRUISE;
	motors[TILT_MOTOR].state = MOTOR_OPS_CRUISE;

	spin_unlock_irqrestore(&mdev->slock, flags);
	mutex_unlock(&mdev->dev_mutex);

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	ingenic_tcu_counter_begin(mdev->tcu);
#else
	jz_tcu_enable_counter(mdev->tcu);
#endif

	return 0;
}

static void motor_get_message(struct motor_device *mdev, struct motor_message *msg)
{
	struct motor_driver *motors = mdev->motors;

	msg->x = motors[PAN_MOTOR].cur_steps;
	msg->y = motors[TILT_MOTOR].cur_steps;
	msg->speed = mdev->tcu_speed;

	if (mdev->dev_state == MOTOR_OPS_STOP)
		msg->status = MOTOR_IS_STOP;
	else
		msg->status = MOTOR_IS_RUNNING;

	/* This is not standard, return the max_steps of each motor */
	msg->x_max_steps = motors[PAN_MOTOR].max_steps;
	msg->y_max_steps = motors[TILT_MOTOR].max_steps;

	return;
}

static inline int motor_ops_reset_check_params(struct motor_reset_data *rdata)
{
	if (rdata->x_max_steps == 0 || rdata->y_max_steps == 0) {
		return -1;
	}

	if (rdata->x_max_steps < rdata->x_cur_step || rdata->x_max_steps < rdata->x_cur_step) {
		return -1;
	}

	return 0;
}

static long motor_ops_reset(struct motor_device *mdev, struct motor_reset_data *rdata)
{
	unsigned long flags;
	int index;
	long ret = 0;
	int times = 0;
	struct motor_message msg;

	if (mdev == NULL || rdata == NULL) {
		printk("ERROR: the parameters of %s is wrong!!\n", __func__);
		return -EPERM;
	}

	if (motor_ops_reset_check_params(rdata) == 0) {
		/* app set max steps and current pos */
		mutex_lock(&mdev->dev_mutex);
		spin_lock_irqsave(&mdev->slock, flags);

		mdev->motors[PAN_MOTOR].max_steps = rdata->x_max_steps;
		mdev->motors[PAN_MOTOR].cur_steps = rdata->x_cur_step;
		mdev->motors[TILT_MOTOR].max_steps = rdata->y_max_steps;
		mdev->motors[TILT_MOTOR].cur_steps = rdata->y_cur_step;

		spin_unlock_irqrestore(&mdev->slock, flags);
		mutex_unlock(&mdev->dev_mutex);
	} else {
		/* driver calculate max steps. */
		/* Enable motor GPIO outputs before reset/homing */
		motor_power_on(mdev);

		mutex_lock(&mdev->dev_mutex);
		spin_lock_irqsave(&mdev->slock, flags);

		for (index = 0; index < NUMBER_OF_MOTORS; index++) {
			struct motor_driver *drv = &mdev->motors[index];
			int half = drv->max_steps > 0 ? drv->max_steps / 2 : 0;
			drv->move_dir = MOTOR_MOVE_RIGHT_UP;
			drv->state = MOTOR_OPS_RESET;
			drv->cur_steps = half > 0 ? half : 0;
		}
		mdev->dst_move.one.x = mdev->motors[PAN_MOTOR].max_steps;
		mdev->dst_move.one.y = mdev->motors[TILT_MOTOR].max_steps;
		mdev->dst_move.times = 1;
		mdev->cur_move.one.x = 0;
		mdev->cur_move.one.y = 0;
		mdev->cur_move.times = 0;
		mdev->dev_state = MOTOR_OPS_RESET;

		spin_unlock_irqrestore(&mdev->slock, flags);
		mutex_unlock(&mdev->dev_mutex);
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
		ingenic_tcu_counter_begin(mdev->tcu);
#else
		jz_tcu_enable_counter(mdev->tcu);
#endif

		for (index = 0; index < NUMBER_OF_MOTORS; index++) {
			do {
				ret = wait_for_completion_interruptible_timeout(&mdev->motors[index].reset_completion, msecs_to_jiffies(150000));
				if (ret == 0) {
					ret = -ETIMEDOUT;
					goto exit;
				}
			} while (ret == -ERESTARTSYS);
		}
	}
	/*
	 * At this point we have swept both axes to their mechanical limits.
	 * Run a reverse move back to the origin so max step counts reflect
	 * the total travel range, then finish at center via motor_ops_goback().
	 */
	ret = motor_ops_move(mdev,
			     -mdev->motors[PAN_MOTOR].cur_steps,
			     -mdev->motors[TILT_MOTOR].cur_steps);

	do {
		msleep(10);
		motor_get_message(mdev, &msg);
		times++;
		if (times > 1000) {
			printk("ERROR:wait motor timeout %s%d\n", __func__, __LINE__);
			ret = -ETIMEDOUT;
			goto exit;
		}
	} while (msg.status == MOTOR_IS_RUNNING);

	/* Finish reset with the fixture sitting at logical center. */
	ret = motor_ops_goback(mdev);
	if (ret)
		goto exit;
	times = 0;
	do {
		msleep(10);
		motor_get_message(mdev, &msg);
		times++;
		if (times > 1000) {
			printk("ERROR:wait motor timeout %s%d\n", __func__, __LINE__);
			ret = -ETIMEDOUT;
			goto exit;
		}
	} while (msg.status == MOTOR_IS_RUNNING);

	ret = 0;

	/* sync data */
	rdata->x_max_steps = mdev->motors[PAN_MOTOR].max_steps;
	rdata->x_cur_step = mdev->motors[PAN_MOTOR].cur_steps;
	rdata->y_max_steps = mdev->motors[TILT_MOTOR].max_steps;
	rdata->y_cur_step = mdev->motors[TILT_MOTOR].cur_steps;

exit:
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	ingenic_tcu_counter_stop(mdev->tcu);
#else
	jz_tcu_disable_counter(mdev->tcu);
#endif
	msleep(10);
	motor_set_default(mdev);

	return ret;
}

static int motor_speed(struct motor_device *mdev, int speed)
{
	__asm__("ssnop");
	if ((speed < MOTOR_MIN_SPEED) || (speed > MOTOR_MAX_SPEED)) {
		dev_err(mdev->dev, "Invalid speed: %d. Accepted range is %d - %d.\n",
			speed, MOTOR_MIN_SPEED, MOTOR_MAX_SPEED);
		return -1;
	}
	__asm__("ssnop");

	mdev->tcu_speed = speed;

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	ingenic_tcu_set_period(mdev->tcu->cib.id, (24000000 / 64 / mdev->tcu_speed));
#else
	jz_tcu_set_period(mdev->tcu, (24000000 / 64 / mdev->tcu_speed));
#endif

	return 0;
}

static int motor_open(struct inode *inode, struct file *file)
{
	int ret = 0;

	struct miscdevice *dev = file->private_data;
	struct motor_device *mdev = container_of(dev, struct motor_device, misc_dev);

	if (mdev->flag) {
		ret = -EBUSY;
		dev_err(mdev->dev, "Failed to open motor driver: device is currently in use.\n");
	} else {
		mdev->flag = 1;
	}

	return ret;
}

static int motor_release(struct inode *inode, struct file *file)
{
	struct miscdevice *dev = file->private_data;
	struct motor_device *mdev = container_of(dev, struct motor_device, misc_dev);
	motor_ops_stop(mdev);
	mdev->flag = 0;
	return 0;
}

static long motor_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	struct miscdevice *dev = filp->private_data;
	struct motor_device *mdev = container_of(dev, struct motor_device, misc_dev);
	long ret = 0;

	if (mdev->flag == 0) {
		dev_err(mdev->dev, "Please open /dev/motor before issuing commands.\n");
		return -EPERM;
	}

	switch (cmd) {
		case MOTOR_STOP:
			motor_ops_stop(mdev);
			break;
		case MOTOR_RESET:
			{
				struct motor_reset_data rdata;
				if (arg == 0) {
					ret = -EPERM;
					break;
				}
				if (copy_from_user(&rdata, (void __user *)arg, sizeof(rdata))) {
					dev_err(mdev->dev, "[%s][%d] copy from user error\n", __func__, __LINE__);
					return -EFAULT;
				}
				ret = motor_ops_reset(mdev, &rdata);
				if (!ret) {
					if (copy_to_user((void __user *)arg, &rdata, sizeof(rdata))) {
						dev_err(mdev->dev, "[%s][%d] copy to user error\n", __func__, __LINE__);
						return -EFAULT;
					}
				}
				break;
			}
		case MOTOR_MOVE:
			{
				struct motors_steps dst;
				if (copy_from_user(&dst, (void __user *)arg, sizeof(struct motors_steps))) {
					dev_err(mdev->dev, "[%s][%d] copy from user error\n", __func__, __LINE__);
					return -EFAULT;
				}
				ret = motor_ops_move(mdev, dst.x, dst.y);
			}
			break;
		case MOTOR_GET_STATUS:
			{
				struct motor_message msg;

				motor_get_message(mdev, &msg);
				if (copy_to_user((void __user *)arg, &msg, sizeof(struct motor_message))) {
					dev_err(mdev->dev, "[%s][%d] copy to user error\n", __func__, __LINE__);
					return -EFAULT;
				}
			}
			break;
		case MOTOR_SPEED:
			{
				int speed;

				if (copy_from_user(&speed, (void __user *)arg, sizeof(int))) {
					dev_err(mdev->dev, "[%s][%d] copy to user error\n", __func__, __LINE__);
					return -EFAULT;
				}

				motor_speed(mdev, speed);
			}
			break;
		case MOTOR_GOBACK:
			ret = motor_ops_goback(mdev);
			break;
		case MOTOR_CRUISE:
			ret = motor_ops_cruise(mdev);
			break;
		default:
			return -EINVAL;
	}

	return ret;
}

static struct file_operations motor_fops = {
	.open = motor_open,
	.release = motor_release,
	.unlocked_ioctl = motor_ioctl,
};

static int motor_info_show(struct seq_file *m, void *v)
{
	struct motor_device *mdev = (struct motor_device *)(m->private);
	struct motor_message msg;
	int index = 0;

	seq_printf(m, "The version of Motor driver is %s\n", JZ_MOTOR_DRIVER_VERSION);
	seq_printf(m, "Motor driver is %s\n", mdev->flag ? "opened" : "closed");
	seq_printf(m, "The max speed is %d and the min speed is %d\n", MOTOR_MAX_SPEED, MOTOR_MIN_SPEED);

	motor_get_message(mdev, &msg);

	seq_printf(m, "The status of motor is %s\n", msg.status ? "running" : "stop");
	seq_printf(m, "The pos of motor is (%d, %d)\n", msg.x, msg.y);
	seq_printf(m, "The speed of motor is %d\n", msg.speed);

	for (index = 0; index < NUMBER_OF_MOTORS; index++) {
		seq_printf(m, "## %s ##\n", mdev->motors[index].pdata->name);
		seq_printf(m, "max steps %d\n", mdev->motors[index].max_steps);
		seq_printf(m, "motor direction %d\n", mdev->motors[index].move_dir);
		seq_printf(m, "motor state %d (normal; cruise; reset)\n", mdev->motors[index].state);
		seq_printf(m, "the irq's counter of max pos is %d\n", mdev->motors[index].max_pos_irq_cnt);
		seq_printf(m, "the irq's counter of min pos is %d\n", mdev->motors[index].min_pos_irq_cnt);
		seq_printf(m, "GPIOs: ST1 %d, ST2 %d, ST3 %d, ST4 %d, hmax %d, vmax %d\n",
				mdev->motors[index].pdata->motor_st1_gpio,
				mdev->motors[index].pdata->motor_st2_gpio,
				mdev->motors[index].pdata->motor_st3_gpio,
				mdev->motors[index].pdata->motor_st4_gpio,
				hmaxstep,
				vmaxstep);
	}

	return 0;
}

static int motor_info_open(struct inode *inode, struct file *file)
{
	return single_open_size(file, motor_info_show, PDE_DATA(inode), 1024);
}

static const struct proc_ops motor_info_fops = {
	.proc_read = seq_read,
	.proc_open = motor_info_open,
	.proc_lseek = seq_lseek,
	.proc_release = single_release,
};

static int motor_probe(struct platform_device *pdev)
{
	int i, ret = 0;
	struct motor_device *mdev;
	struct motor_driver *motor = NULL;
	struct proc_dir_entry *proc;
	mdev = devm_kzalloc(&pdev->dev, sizeof(struct motor_device), GFP_KERNEL);
	if (!mdev) {
		ret = -ENOENT;
		dev_err(&pdev->dev, "Failed to allocate memory for motor device.\n");
		goto error_devm_kzalloc;
	}

	mdev->cell = mfd_get_cell(pdev);
	if (!mdev->cell) {
		ret = -ENOENT;
		dev_err(&pdev->dev, "Failed to retrieve MFD cell for motor device.\n");
		goto error_devm_kzalloc;
	}

	mdev->dev = &pdev->dev;

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	mdev->tcu = (struct ingenic_tcu_chn *)mdev->cell->platform_data;
#else
	mdev->tcu = (struct jz_tcu_chn *)mdev->cell->platform_data;
#endif
	/* Claim TCU channel ownership to avoid conflicts */
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	{
		int ch = mdev->tcu->cib.id;
		ret = tcu_alloc_claim(ch, "motor");
		if (ret) {
			const char *own = tcu_alloc_owner(ch);
			dev_err(&pdev->dev, "TCU ch%d busy (owner=%s), motor refusing to bind: %d\n", ch, own ? own : "unknown", ret);
			goto error_devm_kzalloc;
		}
	}
#else
	{
		int ch = mdev->tcu->index;
		ret = tcu_alloc_claim(ch, "motor");
		if (ret) {
			const char *own = tcu_alloc_owner(ch);
			dev_err(&pdev->dev, "TCU ch%d busy (owner=%s), motor refusing to bind: %d\n", ch, own ? own : "unknown", ret);
			goto error_devm_kzalloc;
		}
	}
#endif

	mdev->tcu->irq_type = FULL_IRQ_MODE;
	mdev->tcu->clk_src = TCU_CLKSRC_EXT;
	mdev->tcu_speed = MOTOR_DEF_SPEED;
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	mdev->tcu->is_pwm = 0;
	mdev->tcu->cib.func = TRACKBALL_FUNC;
	mdev->tcu->clk_div = TCU_PRESCALE_64;
	ingenic_tcu_config(mdev->tcu);
	ingenic_tcu_set_period(mdev->tcu->cib.id, (24000000 / 64 / mdev->tcu_speed));
//	ingenic_tcu_counter_begin(mdev->tcu);
#else
	mdev->tcu->prescale = TCU_PRESCALE_64;
	jz_tcu_config_chn(mdev->tcu);
	jz_tcu_set_period(mdev->tcu, (24000000 / 64 / mdev->tcu_speed));
	jz_tcu_start_counter(mdev->tcu);
#endif
	mutex_init(&mdev->dev_mutex);
	spin_lock_init(&mdev->slock);

	platform_set_drvdata(pdev, mdev);

	/* copy module parameters to the motors struct */
	motors_pdata[0].motor_st1_gpio = hst1;
	motors_pdata[0].motor_st2_gpio = hst2;
	motors_pdata[0].motor_st3_gpio = hst3;
	motors_pdata[0].motor_st4_gpio = hst4;

	motors_pdata[1].motor_st1_gpio = vst1;
	motors_pdata[1].motor_st2_gpio = vst2;
	motors_pdata[1].motor_st3_gpio = vst3;
	motors_pdata[1].motor_st4_gpio = vst4;

	motors_pdata[0].motor_switch_gpio = motor_switch_gpio;

	if (invert_gpio_dir != 0) invert_gpio_dir = 1;

	if (motors_pdata[0].motor_switch_gpio != -1) {
		gpio_request(motors_pdata[0].motor_switch_gpio, "motor_switch_gpio");
		/* Direction is set once here; the step IRQ only writes its value. */
		gpio_direction_output(motors_pdata[0].motor_switch_gpio, 0);
	}

	for (i = 0; i < NUMBER_OF_MOTORS; i++) {
		motor = &(mdev->motors[i]);
		motor->pdata = &motors_pdata[i];
		motor->move_dir = MOTOR_MOVE_STOP;

		dev_info(&pdev->dev, "'%s' GPIOs: ST1 %d, ST2 %d, ST3 %d, ST4 %d, hmax %d, vmax %d\n",
			motor->pdata->name,
			motor->pdata->motor_st1_gpio,
			motor->pdata->motor_st2_gpio,
			motor->pdata->motor_st3_gpio,
			motor->pdata->motor_st4_gpio,
			hmaxstep,
			vmaxstep
		);

		init_completion(&motor->reset_completion);

		if (motor->pdata->motor_st1_gpio != -1)
			gpio_request(motor->pdata->motor_st1_gpio, "motor_st1_gpio");
		if (motor->pdata->motor_st2_gpio != -1)
			gpio_request(motor->pdata->motor_st2_gpio, "motor_st2_gpio");
		if (motor->pdata->motor_st3_gpio != -1)
			gpio_request(motor->pdata->motor_st3_gpio, "motor_st3_gpio");
		if (motor->pdata->motor_st4_gpio != -1)
			gpio_request(motor->pdata->motor_st4_gpio, "motor_st4_gpio");
	}

	mdev->motors[PAN_MOTOR].max_steps = hmaxstep + 100;
	mdev->motors[TILT_MOTOR].max_steps = vmaxstep + 30;

	/*
	 * Seed the logical position at mid travel so the very first
	 * MOTORS_MOVE request can safely step in the negative direction.
	 * Otherwise the guard in motor_ops_move() treats cur_steps == 0 as
	 * already at the minimum stop and clamps any backward motion, which
	 * prevents the initial two-way homing sweep from ever starting.
	 */
	if (mdev->motors[PAN_MOTOR].max_steps > 0) {
		int half = mdev->motors[PAN_MOTOR].max_steps / 2;
		mdev->motors[PAN_MOTOR].cur_steps = half > 0 ? half : 1;
	}
	if (mdev->motors[TILT_MOTOR].max_steps > 0) {
		int half = mdev->motors[TILT_MOTOR].max_steps / 2;
		mdev->motors[TILT_MOTOR].cur_steps = half > 0 ? half : 1;
	}

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	ingenic_tcu_channel_to_virq(mdev->tcu);
	mdev->run_step_irq = mdev->tcu->virq[0];
#else
	mdev->run_step_irq = platform_get_irq(pdev,0);
#endif
	if (mdev->run_step_irq < 0) {
		ret = mdev->run_step_irq;
		dev_err(&pdev->dev, "Failed to get platform irq: %d\n", ret);
		goto error_get_irq;
	}

	ret = request_irq(mdev->run_step_irq, jz_timer_interrupt, 0,
				"jz_timer_interrupt", mdev);
	if (ret) {
		dev_err(&pdev->dev, "Failed to run request_irq() !\n");
		goto error_request_irq;
	}

	init_completion(&mdev->stop_completion);

	mdev->wait_stop = 0;
	mdev->misc_dev.minor = MISC_DYNAMIC_MINOR;
	mdev->misc_dev.name = "motor";
	mdev->misc_dev.fops = &motor_fops;

	ret = misc_register(&mdev->misc_dev);
	if (ret < 0) {
		ret = -ENOENT;
		dev_err(&pdev->dev, "misc_register failed\n");
		goto error_misc_register;
	}

	/* debug info */
	proc = jz_proc_mkdir("motor");
	if (!proc) {
		mdev->proc = NULL;
		printk("create motor_info failed!\n");
	} else {
		mdev->proc = proc;
	}
	proc_create_data("motor_info", S_IRUGO, proc, &motor_info_fops, (void *)mdev);

	motor_set_default(mdev);
	mdev->flag = 0;
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	ingenic_tcu_counter_begin(mdev->tcu);
#endif
	return 0;

error_misc_register:
	free_irq(mdev->run_step_irq, mdev);
error_request_irq:
error_get_irq:
	for (i = 0; i < NUMBER_OF_MOTORS; i++) {
		motor = &(mdev->motors[i]);
		if (motor->pdata == NULL)
			continue;

		if (motor->pdata->motor_switch_gpio != -1)
			gpio_free(motor->pdata->motor_switch_gpio);

		if (motor->pdata->motor_st1_gpio != -1)
			gpio_free(motor->pdata->motor_st1_gpio);
		if (motor->pdata->motor_st2_gpio != -1)
			gpio_free(motor->pdata->motor_st2_gpio);
		if (motor->pdata->motor_st3_gpio != -1)
			gpio_free(motor->pdata->motor_st3_gpio);
		if (motor->pdata->motor_st4_gpio != -1)
			gpio_free(motor->pdata->motor_st4_gpio);

		motor->pdata = 0;
		motor->min_pos_irq = 0;
		motor->max_pos_irq = 0;
	}
error_devm_kzalloc:
	return ret;
}

static int motor_remove(struct platform_device *pdev)
{
	int i;
	struct motor_device *mdev = platform_get_drvdata(pdev);
	struct motor_driver *motor = NULL;

#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	int ch = mdev->tcu->cib.id;
	ingenic_tcu_counter_stop(mdev->tcu);
#else
	int ch = mdev->tcu->index;
	jz_tcu_disable_counter(mdev->tcu);
	jz_tcu_stop_counter(mdev->tcu);
#endif
	/* Release ownership */
	tcu_alloc_release(ch, "motor");

	mutex_destroy(&mdev->dev_mutex);

	free_irq(mdev->run_step_irq, mdev);
	for (i = 0; i < NUMBER_OF_MOTORS; i++) {
		motor = &(mdev->motors[i]);
		if (motor->pdata == NULL)
			continue;

		if (motor->pdata->motor_switch_gpio != -1)
			gpio_free(motor->pdata->motor_switch_gpio);

		if (motor->pdata->motor_st1_gpio != -1)
			gpio_free(motor->pdata->motor_st1_gpio);
		if (motor->pdata->motor_st2_gpio != -1)
			gpio_free(motor->pdata->motor_st2_gpio);
		if (motor->pdata->motor_st3_gpio != -1)
			gpio_free(motor->pdata->motor_st3_gpio);
		if (motor->pdata->motor_st4_gpio != -1)
			gpio_free(motor->pdata->motor_st4_gpio);

		motor->pdata = 0;
		motor->min_pos_irq = 0;
		motor->max_pos_irq = 0;
		motor->min_pos_irq_cnt = 0;
		motor->max_pos_irq_cnt = 0;
	}

	if (mdev->proc)
		proc_remove(mdev->proc);

	misc_deregister(&mdev->misc_dev);

	return 0;
}

static struct platform_driver motor_driver = {
	.probe = motor_probe,
	.remove = motor_remove,
	.driver = {
		.name = motor_driver_name,
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
		.of_match_table = motor_match_dynamic,
#endif
		.owner = THIS_MODULE,
	}
};

static int __init motor_init(void)
{
	/* Parse CSV channels and configure dynamic binding name based on first channel */
	motor_parse_channels();
	snprintf(motor_driver_name, sizeof(motor_driver_name), "tcu_chn%d", motor_bind_channel);
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	snprintf(motor_match_str, sizeof(motor_match_str), "ingenic,tcu_chn%d", motor_bind_channel);
	/* Populate of_match table at runtime (static storage). compatible is a
	 * char array on the 4.4.94 kernels, so copy rather than assign. */
	memset(motor_match_dynamic, 0, sizeof(motor_match_dynamic));
	strncpy(motor_match_dynamic[0].compatible, motor_match_str,
		sizeof(motor_match_dynamic[0].compatible) - 1);
#endif
	return platform_driver_register(&motor_driver);
}

static void __exit motor_exit(void)
{
	platform_driver_unregister(&motor_driver);
}

module_init(motor_init);
module_exit(motor_exit);

MODULE_LICENSE("GPL");
