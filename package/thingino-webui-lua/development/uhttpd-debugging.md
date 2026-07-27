# uhttpd Debugging Guide

This guide helps diagnose and fix uhttpd hanging issues, particularly SSL/TLS related problems.

## Quick Diagnosis

### Check if uhttpd is hanging
```bash
/etc/init.d/S60uhttpd-lua debug
```

### Test responsiveness
```bash
/usr/bin/uhttpd-watchdog test
```

### View current status
```bash
/etc/init.d/S60uhttpd-lua status
```

## Common Issues and Solutions

### 1. SSL Handshake Hangs

**Symptoms:**
- Process exists but HTTPS requests hang
- Process stuck in sigsetjmp() or SSL-related functions
- High CPU usage or unresponsive web interface

**Diagnosis:**
```bash
# Check process stack trace
/usr/bin/uhttpd-debug stack

# Test SSL handshake manually
/usr/bin/uhttpd-debug ssl
```

**Solutions:**
- Reduce timeout values in configuration
- Enable watchdog monitoring
- Check certificate validity
- Monitor system resources

### 2. Certificate Issues

**Symptoms:**
- SSL connection errors
- Certificate validation failures
- Browser security warnings

**Diagnosis:**
```bash
# Check certificate details
/usr/bin/uhttpd-debug ssl
```

**Solutions:**
```bash
# Regenerate certificates
rm -f /etc/ssl/certs/uhttpd.crt /etc/ssl/private/uhttpd.key
/etc/init.d/S60uhttpd-lua restart
```

### 3. Resource Exhaustion

**Symptoms:**
- Process fails to start
- Memory allocation errors
- File descriptor limits

**Diagnosis:**
```bash
# Check system resources
/usr/bin/uhttpd-debug resources
```

**Solutions:**
- Reduce max connections (-N parameter)
- Reduce concurrent requests (-n parameter)
- Check available memory and disk space

## Configuration Options

### Enable Debug Mode
Edit `/etc/default/uhttpd-lua`:
```bash
UHTTPD_DEBUG=1
```

### Enable Watchdog
```bash
UHTTPD_WATCHDOG=1
```

### Adjust Timeouts
```bash
# In /etc/default/uhttpd-lua
EXTRA_ARGS="-t 15 -T 10 -k 5"
```

## Monitoring and Watchdog

### Start Watchdog
```bash
/usr/bin/uhttpd-watchdog start
```

### Check Watchdog Status
```bash
/usr/bin/uhttpd-watchdog status
```

### View Watchdog Logs
```bash
tail -f /tmp/uhttpd-watchdog.log
```

## Advanced Debugging

### Generate Core Dump
```bash
/usr/bin/uhttpd-debug core
```

### Use GDB for Live Debugging
```bash
# On camera (if gdbserver available)
gdbserver :1234 /usr/bin/uhttpd [args]

# On development machine
mipsel-linux-gdb
(gdb) target remote camera_ip:1234
(gdb) continue
```

### Monitor with strace
```bash
# If strace is available
strace -p $(cat /var/run/uhttpd-lua.pid) -o /tmp/uhttpd.trace
```

## Log Analysis

### System Logs
```bash
# Check kernel messages
dmesg | tail -20

# Check system log if available
logread | grep uhttpd
```

### Watchdog Logs
```bash
# View recent watchdog activity
tail -20 /tmp/uhttpd-watchdog.log
```

## Recovery Procedures

### Automatic Recovery
The watchdog will automatically restart uhttpd if it detects hanging.

### Manual Recovery
```bash
# Force restart
/etc/init.d/S60uhttpd-lua restart

# Or use force restart utility
/usr/bin/uhttpd-force-restart
```

### Emergency Recovery
```bash
# Kill all uhttpd processes
pkill -9 uhttpd
rm -f /var/run/uhttpd-lua.pid
/etc/init.d/S60uhttpd-lua start
```

## Prevention

### Regular Monitoring
- Enable watchdog monitoring
- Set appropriate timeout values
- Monitor system resources

### Configuration Tuning
- Reduce connection limits for low-memory systems
- Use shorter timeouts for faster recovery
- Enable debug logging during troubleshooting

### System Maintenance
- Regular certificate renewal
- Monitor disk space and memory usage
- Keep system updated

## Troubleshooting Checklist

1. **Check process status**: Is uhttpd running?
2. **Test connectivity**: Can you connect to HTTP/HTTPS ports?
3. **Verify certificates**: Are SSL certificates valid?
4. **Check resources**: Sufficient memory and disk space?
5. **Review logs**: Any error messages in logs?
6. **Test SSL**: Does SSL handshake work?
7. **Monitor hanging**: Is process stuck in specific function?

## Getting Help

When reporting issues, include:
- Output of `/etc/init.d/S60uhttpd-lua debug`
- Watchdog logs from `/tmp/uhttpd-watchdog.log`
- System information (memory, disk, load)
- Steps to reproduce the issue
- Any recent configuration changes
