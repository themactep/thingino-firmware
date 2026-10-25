#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "atbm_tool.h"

int main(int argc, char *argv[])
{
	char command[CMD_LINE_LEN];
	struct sockaddr_un ser_un;
	int tmp_argc = 1;
	int socket_fd = 0;
	int ret = 0;
	int i = 0;

	if (argc <= 1)
	{
		printf("atbm_iot_cli need at least 1 argument\n"
			   "refer to atbm_iot_supplicant command use(help) or input 'quit' to exit cli and supplicant process.\n");
		return -1;
	}

	memset(command, 0, sizeof(command));
	sprintf(command, "%s", argv[tmp_argc++]);

	while (tmp_argc < argc)
	{	
		sprintf(command, "%s %s", command, argv[tmp_argc++]);
	}

	socket_fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (socket_fd <= 0)
	{
		printf("open socket err\n");
		return -1;
	}

	memset(&ser_un, 0, sizeof(ser_un));  
    ser_un.sun_family = AF_UNIX;  
	strcpy(ser_un.sun_path, SER_SOCKET_PATH);

	ret = connect(socket_fd, (struct sockaddr *)&ser_un, sizeof(struct sockaddr_un));  
	if(ret < 0)  
	{  
		printf("connect err\n");
		return -1; 
	}

	write(socket_fd, command, strlen(command)+1);
	read(socket_fd, command, sizeof(command));
	if (strcmp(command, "OK"))
	{
		printf("send cmd err\n");
		return -1;
	}

	return 0;
}
