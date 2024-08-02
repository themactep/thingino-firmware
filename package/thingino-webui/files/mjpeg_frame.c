/*
 * Write a single MJPEG frame, open the file and getting its size atomically.
 * This assumes that any process updating the file will do so via renaming a
 * temporary file (rather than writing to the file directly).
 *
 * argv[1] is the name of the file
 * argv[2] if provided, write this as boundary for use in a MJPEG stream
 *
 * Returns success if the entire file was sent, and failure otherwise.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#define CRLF "\r\n"

static char buf[65536];

int
main(int ac, char *av[])
{
    if (ac <= 1) {
        fprintf(stderr, "Usage: %s filename.jpeg [frame_boundary]\n", av[0]);
        return EXIT_FAILURE;
    }
    char *jpeg = av[1];
    char *boundary = ac > 2 ? av[2] : NULL;
    int jpegfd = open(jpeg, O_RDONLY);
    struct stat st;
    fstat(jpegfd, &st);
    if (boundary != NULL)
        printf("--%s" CRLF, boundary);
    printf("Content-Type: image/jpeg" CRLF);
    printf("Content-Length: %jd" CRLF CRLF, (intmax_t) st.st_size);
    fflush(stdout);
    int bread;
    while ((bread = read(jpegfd, buf, sizeof buf)) > 0) {
        int bwritten = write(1, buf, bread);
        if (bwritten != bread)
            return EXIT_FAILURE;
    }
    return bread == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
