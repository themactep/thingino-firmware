#!/bin/sh

ulimit -s 256

echo 1 > /proc/sys/vm/overcommit_memory
echo 5 > /proc/sys/vm/dirty_background_ratio 
echo 10 >  /proc/sys/vm/dirty_ratio 
echo 50 > /proc/sys/vm/dirty_writeback_centisecs 
echo 100 > /proc/sys/vm/dirty_expire_centisecs 
echo 10000 > /proc/sys/vm/vfs_cache_pressure
echo 1 > /proc/sys/kernel/panic_on_oops

/app/jz/load.sh

cp /app/bin/daemon /tmp/
chmod +x /tmp/daemon
/tmp/daemon @ipc
