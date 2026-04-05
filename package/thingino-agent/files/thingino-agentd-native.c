#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define AGENT_CONFIG "/etc/thingino.json"
#define AGENT_DOCROOT "/var/www"
#define AGENT_API_PREFIX "/api/v1"
#define AGENTCTL_PATH "/usr/sbin/thingino-agentctl"
#define REQUEST_BUFFER_SIZE 32768
#define BODY_LIMIT 65536

struct http_request {
    int client_fd;
    char method[16];
    char path[512];
    char query[512];
    char authorization[512];
    char script_name[512];
    char path_info[512];
    char *body;
    size_t content_length;
};

static volatile sig_atomic_t keep_running = 1;

static void handle_signal(int sig)
{
    (void)sig;
    keep_running = 0;
}

static void trim_trailing(char *text)
{
    size_t len;

    if (text == NULL) {
        return;
    }
    len = strlen(text);
    while (len > 0 && (text[len - 1] == '\n' || text[len - 1] == '\r')) {
        text[len - 1] = '\0';
        len--;
    }
}

static void strip_wrapping_quotes(char *text)
{
    size_t len;

    if (text == NULL) {
        return;
    }
    len = strlen(text);
    if (len >= 2 && text[0] == '"' && text[len - 1] == '"') {
        memmove(text, text + 1, len - 2);
        text[len - 2] = '\0';
    }
}

static int read_config_value(const char *key, char *buffer, size_t buffer_size, int strip_quotes)
{
    char command[256];
    FILE *pipe;

    buffer[0] = '\0';
    snprintf(command, sizeof(command), "jct %s get %s 2>/dev/null", AGENT_CONFIG, key);
    pipe = popen(command, "r");
    if (pipe == NULL) {
        return -1;
    }
    if (fgets(buffer, (int)buffer_size, pipe) == NULL) {
        pclose(pipe);
        buffer[0] = '\0';
        return -1;
    }
    pclose(pipe);
    trim_trailing(buffer);
    if (strip_quotes) {
        strip_wrapping_quotes(buffer);
    }
    return 0;
}

static int read_json_file_value(const char *file_path, const char *key, char *buffer, size_t buffer_size, int strip_quotes)
{
    char command[512];
    FILE *pipe;

    buffer[0] = '\0';
    snprintf(command, sizeof(command), "jct %s get %s 2>/dev/null", file_path, key);
    pipe = popen(command, "r");
    if (pipe == NULL) {
        return -1;
    }
    if (fgets(buffer, (int)buffer_size, pipe) == NULL) {
        pclose(pipe);
        buffer[0] = '\0';
        return -1;
    }
    pclose(pipe);
    trim_trailing(buffer);
    if (strip_quotes) {
        strip_wrapping_quotes(buffer);
    }
    return 0;
}

static int fd_write_all(int fd, const void *data, size_t data_len)
{
    const char *cursor = (const char *)data;

    while (data_len > 0) {
        ssize_t written = write(fd, cursor, data_len);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        cursor += written;
        data_len -= (size_t)written;
    }
    return 0;
}

static int send_response(int fd, int status, const char *status_text,
    const char *content_type, const void *body, size_t body_len)
{
    char header[256];
    int header_len;

    header_len = snprintf(header, sizeof(header),
        "HTTP/1.1 %d %s\r\n"
        "Connection: close\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "\r\n",
        status, status_text, content_type, body_len);
    if (header_len < 0 || (size_t)header_len >= sizeof(header)) {
        return -1;
    }
    if (fd_write_all(fd, header, (size_t)header_len) != 0) {
        return -1;
    }
    if (body_len > 0 && fd_write_all(fd, body, body_len) != 0) {
        return -1;
    }
    return 0;
}

static int send_json_error(int fd, int status, const char *status_text, const char *message)
{
    char body[512];
    int body_len;

    body_len = snprintf(body, sizeof(body),
        "{\"status\":\"error\",\"error\":{\"code\":\"http_%d\",\"message\":\"%s\"}}\n",
        status, message);
    if (body_len < 0) {
        return -1;
    }
    return send_response(fd, status, status_text, "application/json", body, (size_t)body_len);
}

static int capture_command(char *const argv[], const char *stdin_path, char **output, size_t *output_len)
{
    int pipe_fd[2];
    pid_t pid;
    char *buffer = NULL;
    size_t used = 0;
    size_t capacity = 0;
    int status = 0;

    if (pipe(pipe_fd) != 0) {
        return -1;
    }
    pid = fork();
    if (pid < 0) {
        close(pipe_fd[0]);
        close(pipe_fd[1]);
        return -1;
    }
    if (pid == 0) {
        int input_fd;

        close(pipe_fd[0]);
        dup2(pipe_fd[1], STDOUT_FILENO);
        dup2(pipe_fd[1], STDERR_FILENO);
        close(pipe_fd[1]);
        if (stdin_path != NULL) {
            input_fd = open(stdin_path, O_RDONLY);
            if (input_fd >= 0) {
                dup2(input_fd, STDIN_FILENO);
                close(input_fd);
            }
        }
        execv(argv[0], argv);
        _exit(127);
    }
    close(pipe_fd[1]);
    for (;;) {
        char chunk[4096];
        ssize_t bytes_read = read(pipe_fd[0], chunk, sizeof(chunk));

        if (bytes_read == 0) {
            break;
        }
        if (bytes_read < 0) {
            if (errno == EINTR) {
                continue;
            }
            free(buffer);
            close(pipe_fd[0]);
            waitpid(pid, &status, 0);
            return -1;
        }
        if (used + (size_t)bytes_read + 1 > capacity) {
            size_t new_capacity = capacity == 0 ? 8192 : capacity * 2;
            while (new_capacity < used + (size_t)bytes_read + 1) {
                new_capacity *= 2;
            }
            buffer = realloc(buffer, new_capacity);
            if (buffer == NULL) {
                close(pipe_fd[0]);
                waitpid(pid, &status, 0);
                return -1;
            }
            capacity = new_capacity;
        }
        memcpy(buffer + used, chunk, (size_t)bytes_read);
        used += (size_t)bytes_read;
    }
    close(pipe_fd[0]);
    waitpid(pid, &status, 0);
    if (buffer == NULL) {
        buffer = calloc(1, 1);
        if (buffer == NULL) {
            return -1;
        }
    }
    buffer[used] = '\0';
    *output = buffer;
    *output_len = used;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static int stream_command(int fd, char *const argv[])
{
    int pipe_fd[2];
    pid_t pid;
    int status = 0;

    if (pipe(pipe_fd) != 0) {
        return -1;
    }
    pid = fork();
    if (pid < 0) {
        close(pipe_fd[0]);
        close(pipe_fd[1]);
        return -1;
    }
    if (pid == 0) {
        close(pipe_fd[0]);
        dup2(pipe_fd[1], STDOUT_FILENO);
        dup2(pipe_fd[1], STDERR_FILENO);
        close(pipe_fd[1]);
        execv(argv[0], argv);
        _exit(127);
    }
    close(pipe_fd[1]);
    for (;;) {
        char chunk[4096];
        ssize_t bytes_read = read(pipe_fd[0], chunk, sizeof(chunk));

        if (bytes_read == 0) {
            break;
        }
        if (bytes_read < 0) {
            if (errno == EINTR) {
                continue;
            }
            close(pipe_fd[0]);
            waitpid(pid, &status, 0);
            return -1;
        }
        if (fd_write_all(fd, chunk, (size_t)bytes_read) != 0) {
            close(pipe_fd[0]);
            waitpid(pid, &status, 0);
            return -1;
        }
    }
    close(pipe_fd[0]);
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static const char *find_header_value(const char *headers, const char *name)
{
    size_t name_len = strlen(name);
    const char *line = headers;

    while (line != NULL && *line != '\0') {
        const char *line_end = strstr(line, "\r\n");
        if (line_end == NULL) {
            line_end = line + strlen(line);
        }
        if (strncasecmp(line, name, name_len) == 0 && line[name_len] == ':') {
            line += name_len + 1;
            while (*line == ' ' || *line == '\t') {
                line++;
            }
            return line;
        }
        if (*line_end == '\0') {
            break;
        }
        line = line_end + 2;
    }
    return NULL;
}

static int forward_script(struct http_request *request, const char *script_path)
{
    int stdin_pipe[2];
    int stdout_pipe[2];
    pid_t pid;
    char header_buffer[8192];
    size_t header_len = 0;
    int headers_done = 0;
    int child_status = 0;
    int status_code = 200;
    char status_text[64] = "OK";
    char content_type[128] = "application/octet-stream";

    if (pipe(stdin_pipe) != 0 || pipe(stdout_pipe) != 0) {
        return send_json_error(request->client_fd, 500, "Internal Server Error", "pipe failed");
    }
    pid = fork();
    if (pid < 0) {
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        return send_json_error(request->client_fd, 500, "Internal Server Error", "fork failed");
    }
    if (pid == 0) {
        close(stdin_pipe[1]);
        close(stdout_pipe[0]);
        dup2(stdin_pipe[0], STDIN_FILENO);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stdout_pipe[1], STDERR_FILENO);
        close(stdin_pipe[0]);
        close(stdout_pipe[1]);
        setenv("REQUEST_METHOD", request->method, 1);
        setenv("QUERY_STRING", request->query, 1);
        setenv("SCRIPT_NAME", request->script_name, 1);
        setenv("PATH_INFO", request->path_info, 1);
        if (request->authorization[0] != '\0') {
            setenv("HTTP_AUTHORIZATION", request->authorization, 1);
        }
        if (request->content_length > 0) {
            char length[32];
            snprintf(length, sizeof(length), "%zu", request->content_length);
            setenv("CONTENT_LENGTH", length, 1);
        }
        execl(script_path, script_path, (char *)NULL);
        _exit(127);
    }
    close(stdin_pipe[0]);
    close(stdout_pipe[1]);
    if (request->body != NULL && request->content_length > 0) {
        fd_write_all(stdin_pipe[1], request->body, request->content_length);
    }
    close(stdin_pipe[1]);

    for (;;) {
        char chunk[4096];
        ssize_t bytes_read = read(stdout_pipe[0], chunk, sizeof(chunk));

        if (bytes_read == 0) {
            break;
        }
        if (bytes_read < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        if (!headers_done) {
            size_t copy_len = (size_t)bytes_read;
            if (header_len + copy_len > sizeof(header_buffer) - 1) {
                copy_len = sizeof(header_buffer) - 1 - header_len;
            }
            memcpy(header_buffer + header_len, chunk, copy_len);
            header_len += copy_len;
            header_buffer[header_len] = '\0';
            {
                char *header_end = strstr(header_buffer, "\r\n\r\n");
                if (header_end != NULL) {
                    const char *status_header = find_header_value(header_buffer, "Status");
                    const char *type_header = find_header_value(header_buffer, "Content-Type");
                    char response_header[256];
                    int response_len;
                    const char *body_start;
                    size_t body_len;

                    if (status_header != NULL) {
                        sscanf(status_header, "%d %63[^\r\n]", &status_code, status_text);
                    }
                    if (type_header != NULL) {
                        sscanf(type_header, "%127[^\r\n]", content_type);
                    }
                    response_len = snprintf(response_header, sizeof(response_header),
                        "HTTP/1.1 %d %s\r\nConnection: close\r\nContent-Type: %s\r\n\r\n",
                        status_code, status_text, content_type);
                    fd_write_all(request->client_fd, response_header, (size_t)response_len);
                    body_start = header_end + 4;
                    body_len = header_len - (size_t)(body_start - header_buffer);
                    if (body_len > 0) {
                        fd_write_all(request->client_fd, body_start, body_len);
                    }
                    headers_done = 1;
                }
            }
        } else {
            fd_write_all(request->client_fd, chunk, (size_t)bytes_read);
        }
    }
    close(stdout_pipe[0]);
    waitpid(pid, &child_status, 0);
    if (!headers_done) {
        return send_json_error(request->client_fd, 500, "Internal Server Error", "invalid script response");
    }
    return 0;
}

static int require_token(const struct http_request *request)
{
    char token[256];

    if (read_config_value("agent.token", token, sizeof(token), 1) != 0 || token[0] == '\0') {
        return 0;
    }
    if (strncmp(request->authorization, "Bearer ", 7) != 0) {
        return -1;
    }
    return strcmp(request->authorization + 7, token) == 0 ? 0 : -1;
}

static int execute_agentctl_json(int client_fd, char *const argv[], const char *stdin_path)
{
    char *output = NULL;
    size_t output_len = 0;
    int command_status = capture_command(argv, stdin_path, &output, &output_len);
    int response_status;

    if (command_status != 0) {
        free(output);
        return send_json_error(client_fd, 500, "Internal Server Error", "thingino-agentctl failed");
    }
    response_status = send_response(client_fd, 200, "OK", "application/json", output, output_len);
    free(output);
    return response_status;
}

static int write_request_body_file(const struct http_request *request, char *temp_path, size_t temp_path_size)
{
    int temp_fd;

    snprintf(temp_path, temp_path_size, "/tmp/thingino-agent-body.XXXXXX");
    temp_fd = mkstemp(temp_path);
    if (temp_fd < 0) {
        return -1;
    }
    if (request->content_length > 0 && fd_write_all(temp_fd, request->body, request->content_length) != 0) {
        close(temp_fd);
        unlink(temp_path);
        return -1;
    }
    close(temp_fd);
    return 0;
}

static const char *query_param_value(const struct http_request *request, const char *key)
{
    static char value[256];
    size_t key_len = strlen(key);
    const char *cursor = request->query;

    value[0] = '\0';
    while (cursor != NULL && *cursor != '\0') {
        const char *ampersand = strchr(cursor, '&');
        size_t field_len = ampersand == NULL ? strlen(cursor) : (size_t)(ampersand - cursor);

        if (field_len > key_len + 1 && strncmp(cursor, key, key_len) == 0 && cursor[key_len] == '=') {
            size_t value_len = field_len - key_len - 1;
            if (value_len >= sizeof(value)) {
                value_len = sizeof(value) - 1;
            }
            memcpy(value, cursor + key_len + 1, value_len);
            value[value_len] = '\0';
            return value;
        }
        if (ampersand == NULL) {
            break;
        }
        cursor = ampersand + 1;
    }
    return NULL;
}

static int execute_agentctl_binary(int client_fd, char *const argv[], const char *content_type)
{
    char *output = NULL;
    size_t output_len = 0;
    int command_status = capture_command(argv, NULL, &output, &output_len);
    int response_status;

    if (command_status != 0) {
        free(output);
        return send_json_error(client_fd, 500, "Internal Server Error", "thingino-agentctl failed");
    }
    response_status = send_response(client_fd, 200, "OK", content_type, output, output_len);
    free(output);
    return response_status;
}

static int handle_direct_route(struct http_request *request)
{
    char *argv[6] = {0};
    char temp_path[64];
    const char *relative = request->path + strlen(AGENT_API_PREFIX);
    const char *setting_path;
    const char *resource_path;
    const char *stream_id;
    char enabled[64];
    char channel[64];
    char mode[64];
    char duration[64];
    char path[256];

    if (require_token(request) != 0) {
        return send_json_error(request->client_fd, 401, "Unauthorized", "Unauthorized");
    }

    argv[0] = (char *)AGENTCTL_PATH;
    if (strcmp(relative, "/device") == 0 && strcmp(request->method, "GET") == 0) {
        argv[1] = "device";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/health") == 0 && strcmp(request->method, "GET") == 0) {
        argv[1] = "health";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/state") == 0 && strcmp(request->method, "GET") == 0) {
        argv[1] = "state";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strncmp(relative, "/capabilities", 13) == 0 && strcmp(request->method, "GET") == 0) {
        argv[1] = "capabilities";
        if (relative[13] == '/' && relative[14] != '\0') {
            argv[2] = (char *)(relative + 14);
        }
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strncmp(relative, "/config", 7) == 0) {
        if ((relative[7] == '\0' || strcmp(relative + 7, "/") == 0) && strcmp(request->method, "GET") == 0) {
            argv[1] = "config";
            return execute_agentctl_json(request->client_fd, argv, NULL);
        }
        if (strcmp(relative + 7, "/schema") == 0 && strcmp(request->method, "GET") == 0) {
            argv[1] = "schema";
            return execute_agentctl_json(request->client_fd, argv, NULL);
        }
        if ((relative[7] == '\0' || strcmp(relative + 7, "/") == 0) && strcmp(request->method, "PATCH") == 0) {
            if (write_request_body_file(request, temp_path, sizeof(temp_path)) != 0) {
                return send_json_error(request->client_fd, 500, "Internal Server Error", "write body failed");
            }
            argv[1] = "apply-config";
            argv[2] = temp_path;
            resource_path = execute_agentctl_json(request->client_fd, argv, temp_path) == 0 ? "" : NULL;
            unlink(temp_path);
            return resource_path != NULL ? 0 : -1;
        }
    }
    if (strncmp(relative, "/runtime/", 9) == 0 && strcmp(request->method, "GET") == 0) {
        argv[1] = "runtime";
        argv[2] = (char *)(relative + 9);
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strncmp(relative, "/settings/", 10) == 0) {
        setting_path = relative + 10;
        if (strcmp(request->method, "GET") == 0) {
            argv[1] = "get-setting";
            argv[2] = (char *)setting_path;
            return execute_agentctl_json(request->client_fd, argv, NULL);
        }
        if (strcmp(request->method, "PATCH") == 0) {
            if (write_request_body_file(request, temp_path, sizeof(temp_path)) != 0) {
                return send_json_error(request->client_fd, 500, "Internal Server Error", "write body failed");
            }
            argv[1] = "set-setting";
            argv[2] = (char *)setting_path;
            argv[3] = temp_path;
            resource_path = execute_agentctl_json(request->client_fd, argv, temp_path) == 0 ? "" : NULL;
            unlink(temp_path);
            return resource_path != NULL ? 0 : -1;
        }
    }
    if (strcmp(relative, "/actions/reboot") == 0 && strcmp(request->method, "POST") == 0) {
        argv[1] = "reboot";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/actions/privacy") == 0 && strcmp(request->method, "POST") == 0) {
        if (write_request_body_file(request, temp_path, sizeof(temp_path)) != 0) {
            return send_json_error(request->client_fd, 500, "Internal Server Error", "write body failed");
        }
        if (read_json_file_value(temp_path, "enabled", enabled, sizeof(enabled), 0) != 0) {
            unlink(temp_path);
            return send_json_error(request->client_fd, 400, "Bad Request", "privacy.enabled must be true or false");
        }
        if (read_json_file_value(temp_path, "channel", channel, sizeof(channel), 1) != 0 || channel[0] == '\0') {
            strncpy(channel, "all", sizeof(channel) - 1);
            channel[sizeof(channel) - 1] = '\0';
        }
        argv[1] = "privacy";
        if (strcmp(enabled, "true") == 0 || strcmp(enabled, "1") == 0 || strcmp(enabled, "on") == 0 || strcmp(enabled, "yes") == 0) {
            argv[2] = "on";
        } else if (strcmp(enabled, "false") == 0 || strcmp(enabled, "0") == 0 || strcmp(enabled, "off") == 0 || strcmp(enabled, "no") == 0) {
            argv[2] = "off";
        } else {
            unlink(temp_path);
            return send_json_error(request->client_fd, 400, "Bad Request", "privacy.enabled must be true or false");
        }
        argv[3] = channel;
        resource_path = execute_agentctl_json(request->client_fd, argv, NULL) == 0 ? "" : NULL;
        unlink(temp_path);
        return resource_path != NULL ? 0 : -1;
    }
    if (strcmp(relative, "/actions/daynight") == 0 && strcmp(request->method, "POST") == 0) {
        if (write_request_body_file(request, temp_path, sizeof(temp_path)) != 0) {
            return send_json_error(request->client_fd, 500, "Internal Server Error", "write body failed");
        }
        if (read_json_file_value(temp_path, "mode", mode, sizeof(mode), 1) != 0) {
            unlink(temp_path);
            return send_json_error(request->client_fd, 400, "Bad Request", "daynight.mode must be auto, day, or night");
        }
        unlink(temp_path);
        if (strcmp(mode, "auto") != 0 && strcmp(mode, "day") != 0 && strcmp(mode, "night") != 0) {
            return send_json_error(request->client_fd, 400, "Bad Request", "daynight.mode must be auto, day, or night");
        }
        argv[1] = "daynight";
        argv[2] = mode;
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/actions/record") == 0 && strcmp(request->method, "POST") == 0) {
        if (write_request_body_file(request, temp_path, sizeof(temp_path)) != 0) {
            return send_json_error(request->client_fd, 500, "Internal Server Error", "write body failed");
        }
        if (read_json_file_value(temp_path, "duration_seconds", duration, sizeof(duration), 0) != 0 || duration[0] == '\0') {
            strncpy(duration, "10", sizeof(duration) - 1);
            duration[sizeof(duration) - 1] = '\0';
        }
        stream_id = NULL;
        if (read_json_file_value(temp_path, "stream_id", enabled, sizeof(enabled), 0) == 0 && enabled[0] != '\0') {
            stream_id = enabled;
        }
        if (stream_id == NULL) {
            stream_id = "0";
        }
        if (read_json_file_value(temp_path, "path", path, sizeof(path), 1) != 0) {
            path[0] = '\0';
        }
        unlink(temp_path);
        if (strspn(duration, "0123456789") != strlen(duration)) {
            return send_json_error(request->client_fd, 400, "Bad Request", "record.duration_seconds must be an integer");
        }
        if (strspn(stream_id, "0123456789") != strlen(stream_id)) {
            return send_json_error(request->client_fd, 400, "Bad Request", "record.stream_id must be an integer");
        }
        argv[1] = "record";
        argv[2] = duration;
        argv[3] = (char *)stream_id;
        if (path[0] != '\0') {
            argv[4] = path;
        }
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/actions/services/streaming/start") == 0 && strcmp(request->method, "POST") == 0) {
        argv[1] = "service";
        argv[2] = "streaming";
        argv[3] = "start";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/actions/services/streaming/stop") == 0 && strcmp(request->method, "POST") == 0) {
        argv[1] = "service";
        argv[2] = "streaming";
        argv[3] = "stop";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/actions/services/streaming/restart") == 0 && strcmp(request->method, "POST") == 0) {
        argv[1] = "service";
        argv[2] = "streaming";
        argv[3] = "restart";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strcmp(relative, "/actions/streamer/restart") == 0 && strcmp(request->method, "POST") == 0) {
        argv[1] = "restart-streamer";
        return execute_agentctl_json(request->client_fd, argv, NULL);
    }
    if (strncmp(relative, "/actions/send2/", 15) == 0 && strcmp(request->method, "POST") == 0) {
        const char *send2_rest = relative + 15;
        const char *slash = strchr(send2_rest, '/');
        if (slash != NULL) {
            size_t svc_len = (size_t)(slash - send2_rest);
            if (svc_len > 0 && svc_len < 64) {
                static char svc_buf[64];
                memcpy(svc_buf, send2_rest, svc_len);
                svc_buf[svc_len] = '\0';
                argv[1] = "send2-test";
                argv[2] = svc_buf;
                argv[3] = (char *)(slash + 1);
                return execute_agentctl_json(request->client_fd, argv, NULL);
            }
        }
    }
    if (strcmp(relative, "/actions/snapshot") == 0 && strcmp(request->method, "POST") == 0) {
        stream_id = query_param_value(request, "stream_id");
        argv[1] = "snapshot";
        argv[2] = (char *)(stream_id == NULL || *stream_id == '\0' ? "0" : stream_id);
        return execute_agentctl_binary(request->client_fd, argv, "image/jpeg");
    }
    if (strcmp(relative, "/events") == 0 && strcmp(request->method, "GET") == 0) {
        static const char header[] =
            "HTTP/1.1 200 OK\r\n"
            "Connection: close\r\n"
            "Content-Type: text/event-stream\r\n"
            "Cache-Control: no-cache\r\n"
            "\r\n";

        argv[1] = "events";
        if (fd_write_all(request->client_fd, header, sizeof(header) - 1) != 0) {
            return -1;
        }
        return stream_command(request->client_fd, argv);
    }
    return 1;
}

static int handle_request(struct http_request *request)
{
    int direct_status;

    direct_status = handle_direct_route(request);
    if (direct_status <= 0) {
        return direct_status;
    }
    if (strncmp(request->path, AGENT_API_PREFIX, strlen(AGENT_API_PREFIX)) != 0) {
        return send_json_error(request->client_fd, 404, "Not Found", "Not Found");
    }
    return send_json_error(request->client_fd, 404, "Not Found", "Not Found");
}

static int parse_request(int client_fd, struct http_request *request)
{
    char buffer[REQUEST_BUFFER_SIZE + 1];
    ssize_t bytes_read;
    char *header_end;
    char *line;
    char *query_mark;
    size_t header_size;
    size_t body_in_buffer;

    memset(request, 0, sizeof(*request));
    request->client_fd = client_fd;
    bytes_read = recv(client_fd, buffer, REQUEST_BUFFER_SIZE, 0);
    if (bytes_read <= 0) {
        return -1;
    }
    buffer[bytes_read] = '\0';
    header_end = strstr(buffer, "\r\n\r\n");
    if (header_end == NULL) {
        return -1;
    }
    header_size = (size_t)(header_end - buffer) + 4;
    body_in_buffer = (size_t)bytes_read - header_size;

    line = strtok(buffer, "\r\n");
    if (line == NULL || sscanf(line, "%15s %511s", request->method, request->path) != 2) {
        return -1;
    }
    query_mark = strchr(request->path, '?');
    if (query_mark != NULL) {
        strncpy(request->query, query_mark + 1, sizeof(request->query) - 1);
        *query_mark = '\0';
    }
    strncpy(request->script_name, request->path, sizeof(request->script_name) - 1);
    line = strtok(NULL, "\r\n");
    while (line != NULL) {
        if (strncasecmp(line, "Authorization:", 14) == 0) {
            const char *value = line + 14;
            while (*value == ' ' || *value == '\t') {
                value++;
            }
            strncpy(request->authorization, value, sizeof(request->authorization) - 1);
        } else if (strncasecmp(line, "Content-Length:", 15) == 0) {
            request->content_length = (size_t)strtoul(line + 15, NULL, 10);
        }
        line = strtok(NULL, "\r\n");
    }
    if (request->content_length > BODY_LIMIT) {
        return -2;
    }
    if (request->content_length > 0) {
        request->body = calloc(1, request->content_length + 1);
        if (request->body == NULL) {
            return -1;
        }
        if (body_in_buffer > 0) {
            memcpy(request->body, header_end + 4,
                body_in_buffer > request->content_length ? request->content_length : body_in_buffer);
        }
        while (body_in_buffer < request->content_length) {
            bytes_read = recv(client_fd, request->body + body_in_buffer,
                request->content_length - body_in_buffer, 0);
            if (bytes_read <= 0) {
                free(request->body);
                request->body = NULL;
                return -1;
            }
            body_in_buffer += (size_t)bytes_read;
        }
    }
    return 0;
}

static void free_request(struct http_request *request)
{
    free(request->body);
    request->body = NULL;
}

static int serve_client(int client_fd)
{
    struct http_request request;
    int parse_status;
    int status;

    parse_status = parse_request(client_fd, &request);
    if (parse_status == -2) {
        return send_json_error(client_fd, 413, "Payload Too Large", "Payload Too Large");
    }
    if (parse_status != 0) {
        return send_json_error(client_fd, 400, "Bad Request", "Bad Request");
    }
    status = handle_request(&request);
    free_request(&request);
    return status;
}

int main(int argc, char **argv)
{
    int listen_fd;
    int opt = 1;
    int port = 1998;
    const char *listen_addr = "127.0.0.1";
    struct sockaddr_in addr;
    int index;

    for (index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--listen") == 0 && index + 1 < argc) {
            listen_addr = argv[++index];
        } else if (strcmp(argv[index], "--port") == 0 && index + 1 < argc) {
            port = atoi(argv[++index]);
        }
    }

    signal(SIGTERM, handle_signal);
    signal(SIGINT, handle_signal);
    signal(SIGCHLD, SIG_IGN);

    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        perror("socket");
        return 1;
    }
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((unsigned short)port);
    if (inet_pton(AF_INET, listen_addr, &addr.sin_addr) != 1) {
        fprintf(stderr, "invalid listen address: %s\n", listen_addr);
        close(listen_fd);
        return 1;
    }
    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        perror("bind");
        close(listen_fd);
        return 1;
    }
    if (listen(listen_fd, 8) != 0) {
        perror("listen");
        close(listen_fd);
        return 1;
    }

    while (keep_running) {
        int client_fd = accept(listen_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("accept");
            break;
        }
        if (fork() == 0) {
            close(listen_fd);
            serve_client(client_fd);
            close(client_fd);
            _exit(0);
        }
        close(client_fd);
    }

    close(listen_fd);
    return 0;
}
