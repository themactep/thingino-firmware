/*
 * Write a MJPEG stream as new images become available under /tmp/snapshot.jpg
 * 
 * This uses Linux's inotify API, ensuring that no CPU time is used to poll for
 * changes on the file and that a new image is immediately processed.
 *
 * We assume that the process updating the snapshot file will do so via renaming a
 * temporary file (rather than writing to the file directly).
 *
 * argv[1] is the name of the file, defaults to `/tmp/snapshot.jpg`
 *
 * @author godmar@gmail.com
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/inotify.h>
#include <libgen.h>
#include <poll.h>

#define CRLF "\r\n"

const char *http_response = 
    "HTTP/1.1 200 OK" CRLF
    "Content-Type: multipart/x-mixed-replace; boundary=frame" CRLF
    "Cache-Control: no-cache" CRLF
    "Pragma: no-cache" CRLF
    "Connection: close" CRLF
    CRLF    // end of headers
;

enum exit_code {
    CLIENT_DISCONNECTED,
    UNEXPECTED_ERROR,
    FRAME_SERVED_SUCCESSFULLY
};

static char buf[65536];

static int
serve_one_frame(const char *jpegfilename)
{
    char *boundary = "frame";
    int jpegfd = open(jpegfilename, O_RDONLY);
    int rc = UNEXPECTED_ERROR;
    if (jpegfd == -1)
        return rc;

    struct stat st;
    if (fstat(jpegfd, &st) == -1) {
        rc = UNEXPECTED_ERROR;
        goto out;
    }
    // assume printf will buffer here
    printf("--%s" CRLF, boundary);
    printf("Content-Type: image/jpeg" CRLF);
    printf("Content-Length: %jd" CRLF CRLF, (intmax_t) st.st_size);
    if (fflush(stdout) != 0) {
        rc = CLIENT_DISCONNECTED;
        goto out;
    }
    int bread;
    while ((bread = read(jpegfd, buf, sizeof buf)) > 0) {
        int bwritten = write(1, buf, bread);
        if (bwritten != bread) {
            rc = CLIENT_DISCONNECTED;
            goto out;
        }
    }
    rc = bread == 0 ? FRAME_SERVED_SUCCESSFULLY : UNEXPECTED_ERROR;
out:
    close(jpegfd);
    return rc;
}

int
main(int ac, char *av[])
{
    if (ac > 1 && !strcmp(av[1], "-h")) {
        fprintf(stderr, "Usage: %s [filename.jpg=/tmp/snapshot.jpg]\n", av[0]);
        return EXIT_FAILURE;
    }
    const char *jpegfilename = ac > 1 ? av[1] : "/tmp/snapshot.jpg";
    char *jpegdirname = strdup(dirname(strdup(jpegfilename)));
    char *jpegbasename = strdup(basename(strdup(jpegfilename)));
    write(STDOUT_FILENO, http_response, strlen(http_response));
    int ifd = inotify_init();
    if (ifd < 0) {
        perror("inotify_init");
        return EXIT_FAILURE;
    }
    int wd = inotify_add_watch(ifd, jpegdirname, IN_CREATE | IN_MOVED_TO);
    if (wd == -1) {
        perror("inotify_add_watch");
        return EXIT_FAILURE;
    }

    enum exit_code rc;
nextframe:
    while ((rc = serve_one_frame(jpegfilename)) == FRAME_SERVED_SUCCESSFULLY) {
        for (int j = 0; j < 1000; j++) {
            char ibuf[1024];
            int bread = read(ifd, ibuf, sizeof ibuf);
            if (bread < 0) {
                perror("read on inotify fd");
                return EXIT_FAILURE;
            }

            for (int i = 0; i < bread; ) {
                struct inotify_event *event = (struct inotify_event *) &ibuf[i];
                if (event->len > 0 && ((event->mask & IN_CREATE) || (event->mask & IN_MOVED_TO))) {
                    if (strcmp(event->name, jpegbasename) == 0) {
                        goto nextframe;
                    }
                }
                i += sizeof(struct inotify_event) + event->len;
            }
        }
        // as a safety measure, if there were 1000 inotify events in the /tmp directory,
        // but none related to the file we're watching for, exit here.
        return EXIT_FAILURE;
    }
    return rc != UNEXPECTED_ERROR ? EXIT_SUCCESS : EXIT_FAILURE;
}
