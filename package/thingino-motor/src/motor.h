// SPDX-License-Identifier: GPL-2.0+
/*
 * (c) 2015 Ingenic Semiconductor Co.,Ltd
 * (c) 2024 thingino
 */

#ifndef __MOTOR_H__
#define __MOTOR_H__

#include <linux/wait.h>
#include <linux/spinlock.h>
#include <linux/seq_file.h>
#include <linux/proc_fs.h>
#include <jz_proc.h>

/*
 * PAN is X axis and TILT is Y axis;
 * Zero is the left-bottom point.
 * Origin point is cross point of horizontal midpoint and vertical midpoint.
 */

/*#define PLATFORM_HAS_PAN_MOTOR 1*/
/*#define PLATFORM_HAS_TILT_MOTOR 1*/

enum jz_motor_cnt {
	PAN_MOTOR,
	TILT_MOTOR,
	NUMBER_OF_MOTORS,
};

/* ioctl cmd */
#define MOTOR_STOP			0x1
#define MOTOR_RESET			0x2
#define MOTOR_MOVE			0x3
#define MOTOR_GET_STATUS	0x4
#define MOTOR_SPEED			0x5
#define MOTOR_GOBACK		0x6
#define MOTOR_CRUISE		0x7
#define MOTOR_GET_MAXSTEPS	0x8

/* motor speed, beats per second */
#define MOTOR_MAX_SPEED		2000
#define MOTOR_DEF_SPEED		900
#define MOTOR_MIN_SPEED		1

enum motor_status {
	MOTOR_IS_STOP,
	MOTOR_IS_RUNNING,
};

struct motor_message {
	int x;
	int y;
	enum motor_status status;
	int speed;
	unsigned int x_max_steps;
	unsigned int y_max_steps;
};

struct motors_steps{
	int x;
	int y;
};

struct motor_reset_data {
	unsigned int x_max_steps;
	unsigned int y_max_steps;
	unsigned int x_cur_step;
	unsigned int y_cur_step;
};

enum motor_direction {
	MOTOR_MOVE_LEFT_DOWN = -1,
	MOTOR_MOVE_STOP,
	MOTOR_MOVE_RIGHT_UP,
};

struct motor_platform_data {
	const char name[32];
	int motor_switch_gpio;

	int motor_st1_gpio;
	int motor_st2_gpio;
	int motor_st3_gpio;
	int motor_st4_gpio;
};

enum motor_ops_state {
	MOTOR_OPS_NORMAL,
	MOTOR_OPS_CRUISE,
	MOTOR_OPS_RESET,
	MOTOR_OPS_STOP,
};

struct motor_driver {
	struct motor_platform_data *pdata;
	int max_pos_irq;
	int min_pos_irq;
	int max_steps;
	int cur_steps;
	int total_steps;
	char reset_min_pos;
	char reset_max_pos;
	enum motor_direction move_dir;
	enum motor_ops_state state;
	struct completion reset_completion;

	struct timer_list min_timer;
	struct timer_list max_timer;

	/* debug parameters */
	unsigned int max_pos_irq_cnt;
	unsigned int min_pos_irq_cnt;
};

struct motor_move {
	struct motors_steps one;
	short times;
};

struct motor_device {
	struct platform_device *pdev;
	const struct mfd_cell *cell;
	struct device	 *dev;
	struct miscdevice misc_dev;
	struct motor_driver motors[NUMBER_OF_MOTORS];
	char *skip_mode;
	unsigned int counter;
	struct completion stop_completion;
	unsigned int wait_stop;
#if defined(CONFIG_SOC_T40) || defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_KERNEL_5)
	struct ingenic_tcu_chn *tcu;
#else
	struct jz_tcu_chn *tcu;
#endif
	int tcu_speed;

	struct mutex dev_mutex;
	spinlock_t slock;

	enum motor_ops_state dev_state;
	struct motor_message msg;
	struct motor_move dst_move;
	struct motor_move cur_move;

	int run_step_irq;
	int flag;

	/* debug parameters */
	struct proc_dir_entry *proc;
};

#endif // __MOTOR_H__
