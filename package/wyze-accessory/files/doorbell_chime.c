/*
* Control the Wyze Doorbell V1's wireless chime!
* Supporting playing various sounds, volume, repeat, and pairing.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// Convert a hexadecimal ASCII character to its ASCII value
unsigned char hex_char_to_ascii(char c) {
	return (unsigned char)c;
}

// Convert each pair of hexadecimal ASCII characters to their corresponding ASCII values
void convert_mac_to_ascii(const char *mac, char *mac_ascii) {
	size_t j = 0;
	for (size_t i = 0; i < strlen(mac); i++) {
		if (mac[i] == ':') {
			continue;
		}
		unsigned char high = hex_char_to_ascii(mac[i]);
		unsigned char low = hex_char_to_ascii(mac[i + 1]);
		j += sprintf(mac_ascii + j, "\\x%02X", high);
		j += sprintf(mac_ascii + j, "\\x%02X", low);
		i++;  // Skip the next character, as it is part of the current hex byte
	}
}

// Calculate checksum for the packet
unsigned short calculate_checksum(const unsigned char *cmd, int length) {
	unsigned short sum = 0;
	for (int i = 0; i < length; i++) {
		sum += cmd[i];
	}
	return sum;
}

// Map sound names to their corresponding IDs
int get_sound_id(const char *sound_name) {
	if (strcmp(sound_name, "SPACE_WAVE") == 0) return 1;
	if (strcmp(sound_name, "WIND_CHIME") == 0) return 2;
	if (strcmp(sound_name, "CURIOSITY") == 0) return 3;
	if (strcmp(sound_name, "SURPRISE") == 0) return 4;
	if (strcmp(sound_name, "CHEERFUL") == 0) return 5;
	if (strcmp(sound_name, "DOORBELL_1") == 0) return 6;
	if (strcmp(sound_name, "DOORBELL_2") == 0) return 7;
	if (strcmp(sound_name, "DOORBELL_3") == 0) return 8;
	if (strcmp(sound_name, "DOORBELL_4") == 0) return 9;
	if (strcmp(sound_name, "BIRD_CHIRP") == 0) return 10;
	if (strcmp(sound_name, "DOG_BARK_1") == 0) return 11;
	if (strcmp(sound_name, "DOG_BARK_2") == 0) return 12;
	if (strcmp(sound_name, "DOOR_CLOSE") == 0) return 13;
	if (strcmp(sound_name, "DOOR_OPEN") == 0) return 14;
	if (strcmp(sound_name, "SIMPLE_1") == 0) return 15;
	if (strcmp(sound_name, "SIMPLE_2") == 0) return 16;
	if (strcmp(sound_name, "SIMPLE_3") == 0) return 17;
	if (strcmp(sound_name, "SIMPLE_4") == 0) return 18;
	if (strcmp(sound_name, "INTRUDER") == 0) return 19;
	return -1;  // Return -1 if no valid sound name is found
}

// Check if the string is a number
int is_number(const char *str) {
	for (int i = 0; str[i] != '\0'; i++) {
		if (!isdigit(str[i])) {
			return 0;
		}
	}
	return 1;
}

// Convert volume percentage to a suitable value for the command
unsigned char convert_volume_to_value(int volume) {
	if (volume < 1) volume = 1;
	if (volume > 100) volume = 100;
	return (unsigned char)(volume * 0xFF / 100);  // Scale 1-100 to 0x01-0xFF
}

void send_verify_result(const char *mac_ascii, int debug_mode) {
	unsigned char cmd[20] = {0xAA, 0x55, 0x53, 0x0D, 0x23};  // Header and CMD
	size_t cmd_len = 5;

	// Convert the MAC address into the command
	for (size_t i = 0; i < strlen(mac_ascii); i += 4) {
		unsigned char byte;
		sscanf(mac_ascii + i + 2, "%02hhX", &byte);  // Convert the hex string to a byte
		cmd[cmd_len++] = byte;
	}

	// Add the pairing payload
	cmd[cmd_len++] = 0xFF;  // Part of the pairing payload
	cmd[cmd_len++] = 0x04;  // Part of the pairing payload

	// Calculate the checksum
	unsigned short checksum = calculate_checksum(cmd, cmd_len);
	cmd[cmd_len++] = (checksum >> 8) & 0xFF;  // Checksum high byte
	cmd[cmd_len++] = checksum & 0xFF;  // Checksum low byte

	// Print the command in debug mode
	if (debug_mode) {
		printf("Debug Mode: Pairing command to be sent to /dev/ttyS0: ");
		for (size_t i = 0; i < cmd_len; i++) {
			printf("\\x%02X", cmd[i]);
		}
		printf("\n");
	}

	// Open /dev/ttyS0 for writing
	FILE *serial_port = fopen("/dev/ttyS0", "wb");
	if (serial_port == NULL) {
		perror("Error opening /dev/ttyS0");
		exit(EXIT_FAILURE);
	}

	// Write the command to the serial port
	fwrite(cmd, sizeof(unsigned char), cmd_len, serial_port);

	// Close the serial port
	fclose(serial_port);

	printf("Pairing command sent to /dev/ttyS0\n");
}

int main(int argc, char *argv[]) {
	int debug_mode = 0;
	int pairing_mode = 0;

	// Check if the -d or -p flag is present
	while (argc > 1 && (strcmp(argv[1], "-d") == 0 || strcmp(argv[1], "-p") == 0)) {
		if (strcmp(argv[1], "-d") == 0) {
			debug_mode = 1;
		}
		if (strcmp(argv[1], "-p") == 0) {
			pairing_mode = 1;
		}
		argv++;
		argc--;
	}

	if (pairing_mode && argc != 2) {
		fprintf(stderr, "Usage: %s [-d] -p <MAC_ADDRESS>\n", argv[0]);
		return EXIT_FAILURE;
	}

	if (!pairing_mode && (argc < 4 || argc > 5)) {
		fprintf(stderr, "Usage: %s [-d] [-p] <MAC_ADDRESS> <SOUND_NAME_OR_NUMBER> <VOLUME> [REPEAT]\n", argv[0]);
		return EXIT_FAILURE;
	}

	const char *mac = argv[1];
	char mac_ascii[50] = {0};  // Enough space for the converted MAC, no segfaults
	convert_mac_to_ascii(mac, mac_ascii);

	// Pairing mode operation
	if (pairing_mode) {
		send_verify_result(mac_ascii, debug_mode);
		return EXIT_SUCCESS;
	}

	// Sound command operation (existing functionality)
	const char *sound_arg = argv[2];
	const char *volume_arg = argv[3];
	const char *repeat_arg = (argc == 5) ? argv[4] : "1";  // Default repeat value is 1

	// Validate MAC address format
	if (strlen(mac) != 11 || mac[2] != ':' || mac[5] != ':' || mac[8] != ':') {
		fprintf(stderr, "Invalid MAC address format. Use XX:XX:XX:XX\n");
		return EXIT_FAILURE;
	}

	// Get sound ID
	int sound_id;
	if (is_number(sound_arg)) {
		sound_id = atoi(sound_arg);
		if (sound_id < 0 || sound_id > 19) {
			fprintf(stderr, "Invalid sound number. Must be between 0 and 19.\n");
			return EXIT_FAILURE;
		}
	} else {
		sound_id = get_sound_id(sound_arg);
		if (sound_id == -1) {
			fprintf(stderr, "Invalid sound name. Use one of the predefined sound names.\n");
			return EXIT_FAILURE;
		}
	}

	// Validate and convert volume
	if (!is_number(volume_arg)) {
		fprintf(stderr, "Invalid volume. Must be a number between 0 and 100.\n");
		return EXIT_FAILURE;
	}
	int volume = atoi(volume_arg);
	if (volume < 0 || volume > 100) {
		fprintf(stderr, "Invalid volume. Must be between 0 and 100.\n");
		return EXIT_FAILURE;
	}
	unsigned char volume_value = convert_volume_to_value(volume);

	// Validate and convert repeat count
	if (!is_number(repeat_arg)) {
		fprintf(stderr, "Invalid repeat count. Must be a number.\n");
		return EXIT_FAILURE;
	}
	int repeat_count = atoi(repeat_arg);
	if (repeat_count < 1 || repeat_count > 255) {
		fprintf(stderr, "Invalid repeat count. Must be between 1 and 255.\n");
		return EXIT_FAILURE;
	}

	// Prepare the command packet (leave space for checksum at the end)
	unsigned char cmd[20] = {0xAA, 0x55, 0x53, 0x0E, 0x70};  // Header and CMD
	size_t cmd_len = 5;

	// Convert the MAC address into the command
	for (size_t i = 0; i < strlen(mac_ascii); i += 4) {
		unsigned char byte;
		sscanf(mac_ascii + i + 2, "%02hhX", &byte);  // Convert the hex string to a byte
		cmd[cmd_len++] = byte;
	}

	// Add SOUND ID, REPEAT, and VOLUME
	cmd[cmd_len++] = sound_id;  // SOUND ID based on the provided argument
	cmd[cmd_len++] = (unsigned char)repeat_count;  // REPEAT based on the provided argument
	cmd[cmd_len++] = volume_value;  // VOLUME based on the provided argument

	// Calculate the checksum
	unsigned short checksum = calculate_checksum(cmd, cmd_len);
	cmd[cmd_len++] = (checksum >> 8) & 0xFF;  // Checksum high byte
	cmd[cmd_len++] = checksum & 0xFF;  // Checksum low byte

	// Print the command in debug mode
	if (debug_mode) {
		printf("Debug Mode: Command to be sent to /dev/ttyS0: ");
		for (size_t i = 0; i < cmd_len; i++) {
			printf("\\x%02X", cmd[i]);
		}
		printf("\n");
	}

	// Open /dev/ttyS0 for writing
	FILE *serial_port = fopen("/dev/ttyS0", "wb");
	if (serial_port == NULL) {
		perror("Error opening /dev/ttyS0");
		return EXIT_FAILURE;
	}

	// Write the command to the serial port
	fwrite(cmd, sizeof(unsigned char), cmd_len, serial_port);

	// Close the serial port
	fclose(serial_port);

	printf("Command sent to /dev/ttyS0\n");

	return EXIT_SUCCESS;
}
