Busybox
=======

### echo

We enhanced `echo` command with ANSI-256 color support.

Three new options:
 
- -c COLOR: Set foreground color (0-255)
- -b COLOR: Set background color (0-255)
- -a STATUS: Status alias shortcuts (info, ok, success, warn, warning, error, fail)
 
Examples:
  echo -c 32 "Green text"
  echo -a error "Error message"
  echo -c 255 -b 21 "White on blue"


