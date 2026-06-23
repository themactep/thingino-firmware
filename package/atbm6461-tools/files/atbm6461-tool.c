#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define RTOS_TIMEOUT_SHORT_MS 3000
#define RTOS_TIMEOUT_WIFI_MS  5000

#define CMD_WIFI_CONNECT          2
#define CMD_PIR_ENABLE            9
#define CMD_PIR_DISABLE           10
#define CMD_SET_DETECT_RANGE      13
#define CMD_WDT_ENABLE            18
#define CMD_WDT_DISABLE           19
#define CMD_GET_BATTERY_STATUS    26
#define CMD_GET_BATTERY_VOLTAGE   27
#define CMD_VERSION               36
#define CMD_FACTORY_RESET         52
#define CMD_SET_RTC_MODE          59
#define CMD_GET_BAT_INC_INTERVAL  68
#define CMD_SET_BAT_INC_INTERVAL  69
#define CMD_BLE_START             70
#define CMD_BLE_STOP              71
#define CMD_SET_PIR_TYPE          81

int rtos_cmd_init(void);
int rtos_cmd_send(int cmd_id, void *in_data, int in_len,
		  void *out_data, int *out_len, int timeout_ms);
int rtos_cmd_master_poweroff(void);
int rtos_cmd_mcu_upgrade(char *file_name);

struct wifi_connect_payload {
	int mode;
	char ssid[36];
	char password[68];
};

static const char *progname(const char *path)
{
	const char *slash = strrchr(path, '/');

	return slash ? slash + 1 : path;
}

static void usage(const char *prog)
{
	printf("Usage:\n");
	printf("  %s [options 1] [options 2] [..]\n", prog);
	printf("supported options:\n");
	printf("  --version\n");
	printf("  --wifi_connect [=<ssid>:<password>]\n");
	printf("  --master_poweroff\n");
	printf("  --wifi_master_poweroff\n");
	printf("  --factory_reset\n");
	printf("  --pir_enable\n");
	printf("  --pir_disable\n");
	printf("  --wdt_enable\n");
	printf("  --wdt_disable\n");
	printf("  --ble_start\n");
	printf("  --ble_stop\n");
	printf("  --get_battery_status\n");
	printf("  --get_battery_voltage\n");
	printf("  --get_bat_inc_interval\n");
	printf("  --set_bat_inc_interval=[inc_inr]\n");
	printf("  --set_detect_range=[threshold]\n");
	printf("  --set_pir_type=[type]\n");
	printf("  --set_rtc_mode=[mode]\n");
	printf("  --upgrade_fw [=<file_path>]\n");
}

static int send_no_payload(int cmd_id)
{
	int ret;

	ret = rtos_cmd_send(cmd_id, NULL, 0, NULL, NULL,
			    RTOS_TIMEOUT_SHORT_MS);
	return ret < 0 ? -1 : 0;
}

static int send_int_payload(int cmd_id, int value)
{
	int ret;

	ret = rtos_cmd_send(cmd_id, &value, sizeof(value), NULL, NULL,
			    RTOS_TIMEOUT_SHORT_MS);
	return ret < 0 ? -1 : 0;
}

static int get_int_payload(int cmd_id, int *value)
{
	int out_len = sizeof(*value);
	int ret;

	*value = 0;
	ret = rtos_cmd_send(cmd_id, NULL, 0, value, &out_len,
			    RTOS_TIMEOUT_SHORT_MS);
	return ret < 0 ? -1 : 0;
}

static int show_version(void)
{
	char version[256];
	int out_len = sizeof(version);
	int ret;

	memset(version, 0, sizeof(version));
	ret = rtos_cmd_send(CMD_VERSION, NULL, 0, version, &out_len,
			    RTOS_TIMEOUT_SHORT_MS);
	if (ret < 0) {
		puts("get version failed");
		return -1;
	}

	version[sizeof(version) - 1] = '\0';
	printf("info: ATBM6461 FW Version: %s\n", version);
	return 0;
}

static int wifi_connect(const char *arg)
{
	struct wifi_connect_payload payload;
	const char *sep;
	size_t ssid_len;
	const char *password;
	int ret;

	if (!arg) {
		puts("parameter error.");
		return -1;
	}

	sep = strchr(arg, ':');
	if (!sep) {
		puts("parameter error.");
		return -1;
	}

	ssid_len = (size_t)(sep - arg);
	password = sep + 1;

	if (ssid_len == 0 || ssid_len >= sizeof(payload.ssid) ||
	    strlen(password) >= sizeof(payload.password)) {
		puts("parameter error.");
		return -1;
	}

	memset(&payload, 0, sizeof(payload));
	payload.mode = 1;
	memcpy(payload.ssid, arg, ssid_len);
	strcpy(payload.password, password);

	printf("connect wifi ssid:%s\n", payload.ssid);

	ret = rtos_cmd_send(CMD_WIFI_CONNECT, &payload, sizeof(payload),
			    NULL, NULL, RTOS_TIMEOUT_WIFI_MS);
	if (ret < 0) {
		puts("connect wifi failed");
		return -1;
	}

	return 0;
}

static int get_battery_status(void)
{
	int status[3];
	int out_len = sizeof(status);
	int ret;

	memset(status, 0, sizeof(status));
	ret = rtos_cmd_send(CMD_GET_BATTERY_STATUS, NULL, 0, status, &out_len,
			    RTOS_TIMEOUT_SHORT_MS);
	if (ret < 0) {
		puts("get_battery_status failed");
		return -1;
	}

	printf("battery: voltage=%d capacity=%d charge_status=%d\n",
	       status[1], status[0], status[2]);
	return 0;
}

static int get_named_int(int cmd_id, const char *fail_msg, const char *fmt)
{
	int value;

	if (get_int_payload(cmd_id, &value) < 0) {
		puts(fail_msg);
		return -1;
	}

	printf(fmt, value);
	return 0;
}

static int set_named_int(int cmd_id, const char *fmt, const char *arg)
{
	char *end;
	long value;

	if (!arg) {
		puts("parameter error.");
		return -1;
	}

	errno = 0;
	value = strtol(arg, &end, 10);
	if (errno || end == arg || *end != '\0' ||
	    value < -2147483647L - 1L || value > 2147483647L) {
		puts("parameter error.");
		return -1;
	}

	printf(fmt, (int)value);
	return send_int_payload(cmd_id, (int)value);
}

static int upgrade_firmware(const char *path)
{
	if (!path) {
		puts("parameter error.");
		return -1;
	}

	printf("upgrade_fw: %s\n", path);
	system("killall app_wdt");
	system("killall ajcloud");
	system("killall lp_mgr");
	sleep(1);

	return rtos_cmd_mcu_upgrade((char *)path);
}

static int battery_probe(void)
{
	int ret = 0;

	ret |= get_battery_status();
	ret |= get_named_int(CMD_GET_BATTERY_VOLTAGE,
			     "get_battery_voltage failed",
			     "battery voltage = %d\n");
	ret |= get_named_int(CMD_GET_BAT_INC_INTERVAL,
			     "get_bat_inc_interval failed",
			     "battery inc_interval = %d\n");
	return ret ? -1 : 0;
}

static int take_arg(int argc, char **argv, int *index, const char **value)
{
	if (*value)
		return 0;

	if (*index + 1 >= argc || strncmp(argv[*index + 1], "--", 2) == 0)
		return -1;

	*value = argv[++*index];
	return 0;
}

static int handle_option(int argc, char **argv, int *index)
{
	char *name = argv[*index];
	const char *value = NULL;
	char *eq;

	if (strncmp(name, "--", 2) != 0)
		return -2;

	name += 2;
	eq = strchr(name, '=');
	if (eq) {
		*eq = '\0';
		value = eq + 1;
	}

	if (strcmp(name, "version") == 0)
		return show_version();
	if (strcmp(name, "wifi_connect") == 0) {
		if (take_arg(argc, argv, index, &value) < 0)
			return wifi_connect(NULL);
		return wifi_connect(value);
	}
	if (strcmp(name, "master_poweroff") == 0 ||
	    strcmp(name, "wifi_master_poweroff") == 0)
		return rtos_cmd_master_poweroff();
	if (strcmp(name, "factory_reset") == 0) {
		if (send_no_payload(CMD_FACTORY_RESET) < 0)
			return -1;
		return rtos_cmd_master_poweroff();
	}
	if (strcmp(name, "pir_enable") == 0)
		return send_no_payload(CMD_PIR_ENABLE);
	if (strcmp(name, "pir_disable") == 0)
		return send_no_payload(CMD_PIR_DISABLE);
	if (strcmp(name, "wdt_enable") == 0)
		return send_no_payload(CMD_WDT_ENABLE);
	if (strcmp(name, "wdt_disable") == 0)
		return send_no_payload(CMD_WDT_DISABLE);
	if (strcmp(name, "ble_start") == 0)
		return send_no_payload(CMD_BLE_START);
	if (strcmp(name, "ble_stop") == 0)
		return send_no_payload(CMD_BLE_STOP);
	if (strcmp(name, "get_battery_status") == 0)
		return get_battery_status();
	if (strcmp(name, "get_battery_voltage") == 0)
		return get_named_int(CMD_GET_BATTERY_VOLTAGE,
				     "get_battery_voltage failed",
				     "battery voltage = %d\n");
	if (strcmp(name, "get_bat_inc_interval") == 0)
		return get_named_int(CMD_GET_BAT_INC_INTERVAL,
				     "get_bat_inc_interval failed",
				     "battery inc_interval = %d\n");
	if (strcmp(name, "set_bat_inc_interval") == 0) {
		if (take_arg(argc, argv, index, &value) < 0)
			return set_named_int(CMD_SET_BAT_INC_INTERVAL,
					     "set_bat_inc_interval: %d\n",
					     NULL);
		return set_named_int(CMD_SET_BAT_INC_INTERVAL,
				     "set_bat_inc_interval: %d\n", value);
	}
	if (strcmp(name, "set_detect_range") == 0) {
		if (take_arg(argc, argv, index, &value) < 0)
			return set_named_int(CMD_SET_DETECT_RANGE,
					     "set_detect_range: %d\n", NULL);
		return set_named_int(CMD_SET_DETECT_RANGE,
				     "set_detect_range: %d\n", value);
	}
	if (strcmp(name, "set_rtc_mode") == 0) {
		if (take_arg(argc, argv, index, &value) < 0)
			return set_named_int(CMD_SET_RTC_MODE,
					     "set_rtc_mode: %d\n", NULL);
		return set_named_int(CMD_SET_RTC_MODE,
				     "set_rtc_mode: %d\n", value);
	}
	if (strcmp(name, "set_pir_type") == 0) {
		if (take_arg(argc, argv, index, &value) < 0)
			return set_named_int(CMD_SET_PIR_TYPE,
					     "set_pir_type: %d\n", NULL);
		return set_named_int(CMD_SET_PIR_TYPE,
				     "set_pir_type: %d\n", value);
	}
	if (strcmp(name, "upgrade_fw") == 0) {
		if (take_arg(argc, argv, index, &value) < 0)
			return upgrade_firmware(NULL);
		return upgrade_firmware(value);
	}

	return -2;
}

int main(int argc, char **argv)
{
	const char *prog = progname(argv[0]);
	int ret = 0;
	int i;

	rtos_cmd_init();

	if (strcmp(prog, "atbm6461-battery") == 0 ||
	    strcmp(prog, "atbm6461-battery-probe") == 0)
		return battery_probe() < 0 ? 1 : 0;

	if (argc == 1) {
		usage(prog);
		return 0;
	}

	for (i = 1; i < argc; ++i) {
		int opt_ret = handle_option(argc, argv, &i);

		if (opt_ret == -2) {
			usage(prog);
			return 1;
		}
		if (opt_ret < 0)
			ret = 1;
	}

	return ret;
}
