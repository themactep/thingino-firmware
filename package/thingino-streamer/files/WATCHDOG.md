# Streamer Watchdog

The streamer watchdog (`S94streamer-watchdog`) is a robust process monitor that automatically restarts the streamer service when it dies or becomes unresponsive.

## Features

- **Process Monitoring**: Monitors the streamer process using multiple methods (PID file, process name, lock file)
- **Limited Restart Attempts**: Configurable maximum number of restart attempts to prevent infinite restart loops
- **Cooldown Period**: After reaching max restart attempts, waits for a cooldown period before resetting the counter
- **State Persistence**: Maintains restart count and timing information across watchdog restarts
- **Graceful Service Management**: Uses the standard service management system for starting/stopping streamer
- **Configurable**: All timing and limits can be configured via configuration file

## Configuration

The watchdog can be configured by editing `/etc/default/streamer-watchdog`:

```bash
# Enable/disable the watchdog
ENABLED=true

# Check interval in seconds (how often to check if streamer is running)
CHECK_INTERVAL=10

# Restart delay in seconds (minimum time between restart attempts)
RESTART_DELAY=5

# Maximum number of restart attempts before giving up
MAX_RESTART_ATTEMPTS=5

# Cooldown period in seconds (time to wait before resetting restart counter)
RESTART_COOLDOWN=300
```

## Usage

```bash
# Start the watchdog
service start streamer-watchdog

# Stop the watchdog
service stop streamer-watchdog

# Restart the watchdog
service restart streamer-watchdog

# Check watchdog status
service status streamer-watchdog
```

## How It Works

1. **Process Detection**: The watchdog checks if the streamer process is running using:
   - Service PID file (`/run/streamer.pid`)
   - Process name lookup (`pidof streamer`)
   - Lock file validation (`/run/streamer.lock`)

2. **Restart Logic**: When the streamer process is not running:
   - Checks if restart attempts are within limits
   - Respects restart delay between attempts
   - Gracefully stops any remaining processes
   - Cleans up stale PID and lock files
   - Starts the streamer service
   - Verifies the service started successfully

3. **Failure Handling**: If max restart attempts are reached:
   - Stops attempting restarts
   - Waits for the cooldown period
   - Resets the restart counter after cooldown
   - Resumes monitoring

## State Management

The watchdog maintains state in `/run/streamer-watchdog.state` including:
- Current restart count
- Last restart timestamp
- Watchdog start time

This allows the watchdog to maintain restart limits even if the watchdog itself is restarted.

## Integration

The watchdog is designed to run before the streamer service (S94 vs S95) and integrates with the thingino service management system using the standard `/usr/share/common` functions.

## Differences from Old Stream Watchdog

The new process watchdog (`S94streamer-watchdog`) replaces the old stream watchdog (`S97stream-watchdog`) with these improvements:

- **Process vs Stream Monitoring**: Monitors the actual streamer process instead of testing RTSP streams
- **Better Performance**: No network overhead from RTSP testing
- **More Reliable**: Direct process monitoring is more accurate than stream testing
- **Faster Response**: Detects process failures immediately instead of waiting for stream timeouts
- **Proper Integration**: Uses standard thingino service management functions
- **State Persistence**: Maintains restart history across watchdog restarts
