# TFTP Server for Thingino Firmware

A containerized TFTP server for serving compiled firmware images from your build host.

## Quick Start

### 1. Install Container Runtime

Install Podman (recommended) or Docker:

```bash
# Ubuntu/Debian
sudo apt-get install podman

# Fedora/RHEL
sudo dnf install podman

# Arch Linux
sudo pacman -S podman

# macOS
brew install podman

# Windows: Install Docker Desktop or Podman Desktop
```

### 2. Start the Server

```bash
# Default port 69 (automatically uses sudo)
make tftpd-start

# Custom port (no sudo needed)
TFTP_PORT=6969 make tftpd-start
```

**Note:** Port 69 requires root privileges. The Makefile automatically runs with `sudo` when using port 69.

The server automatically serves from `./tftproot/` directory, where compiled images are copied during the build process.

### 3. Build and Serve

```bash
# Build your firmware
make

# Images are automatically:
# 1. Built in output-*/images/
# 2. Copied to tftproot/ for easy TFTP access
# 3. Available at: tftp://<your-ip>:6969/thingino-<camera>.bin
```

### 4. Manage the Server

```bash
make tftpd-status    # Check if running
make tftpd-logs      # View server logs
make tftpd-stop      # Stop server
make tftpd-restart   # Restart server
```

## Configuration

Set these environment variables before running `make tftpd-start`:

| Variable | Default | Description |
|----------|---------|-------------|
| `TFTP_PORT` | 69 | Server port (use >1024 for unprivileged) |
| `TFTP_ROOT` | ./tftproot | Directory to serve files from |
| `TFTP_BIND` | 0.0.0.0 | Bind address |
| `TFTP_CONTAINER_IMAGE` | docker.io/pghalliday/tftp:latest | Container image to use |

**Examples:**

```bash
# Port 69 (default, uses sudo automatically)
make tftpd-start

# Custom port (no sudo)
TFTP_PORT=6969 make tftpd-start

# Use custom TFTP root directory
TFTP_ROOT=/path/to/files TFTP_PORT=6969 make tftpd-start

# Bind to specific IP
TFTP_BIND=192.168.1.100 make tftpd-start

# Use different container image
TFTP_CONTAINER_IMAGE=docker.io/jumanjiman/tftp:latest make tftpd-start
```

## How It Works

When you build firmware with `make`:

1. **Images are built** in `output-*/images/` directories
2. **Images are copied** to `./tftproot/` directory with simple names
3. **TFTP server serves** from `./tftproot/` for easy access

This means you can access firmware with simple paths like:
- `tftp://<ip>/thingino-camera.bin` ✅ **Easy!**
- Instead of: `tftp://<ip>/output-stable/long-camera-name/images/thingino-long-camera-name.bin` ❌ Complex

## Accessing Firmware Images

### From Camera (U-Boot)

```
setenv serverip <build-host-ip>
setenv ipaddr <camera-ip>
tftp 0x80600000 thingino-<camera>.bin
sf probe 0
sf erase 0x0 0x400000
sf write 0x80600000 0x0 ${filesize}
```

**Note:** Files are in the TFTP root, no subdirectories needed!

### From Camera (Linux)

```bash
tftp -g -r thingino-<camera>.bin <build-host-ip>
```

### Available Files

After building, these files are in `./tftproot/`:

```
thingino-<camera>.bin              # Full firmware image
thingino-<camera>-update.bin       # Update image (no bootloader)
thingino-<camera>.bin.sha256sum    # Full image checksum
thingino-<camera>-update.bin.sha256sum  # Update image checksum
```

## Direct Script Usage

You can bypass make and use the script directly:

```bash
# All commands
scripts/tftpd-server.sh start
scripts/tftpd-server.sh stop 
scripts/tftpd-server.sh restart
scripts/tftpd-server.sh status
scripts/tftpd-server.sh logs
scripts/tftpd-server.sh help

# With options
TFTP_PORT=6969 scripts/tftpd-server.sh start
scripts/tftpd-server.sh start -p 6969 -r /path/to/files
```

## Troubleshooting

### Container Runtime Not Found

```bash
# Install Podman
sudo apt-get install podman  # Ubuntu/Debian
sudo dnf install podman      # Fedora/RHEL
sudo pacman -S podman        # Arch Linux
brew install podman          # macOS

# Or install Docker from https://docs.docker.com/engine/install/
```

### Port 69 Permission Issues

Port 69 requires root privileges. The Makefile handles this automatically:

```bash
# Automatically uses sudo for port 69
make tftpd-start

# Or manually with sudo
sudo scripts/tftpd-server.sh start
```

For unprivileged operation, use a custom port:
```bash
TFTP_PORT=6969 make tftpd-start
```

**Note:** Most U-Boot versions only support port 69 (hardcoded). Use port 69 for maximum compatibility with cameras.

### Server Won't Start

Check logs for errors:
```bash
make tftpd-logs
```

Force remove stale container:
```bash
podman rm -f thingino-tftpd
# or
docker rm -f thingino-tftpd
```

### File Not Found

- Verify file exists: `ls output-stable/*/images/*.bin`
- Check path is relative to `TFTP_ROOT`
- View logs: `make tftpd-logs`

### Firewall Blocking

Allow TFTP through firewall:
```bash
# UFW
sudo ufw allow 6969/udp

# firewalld
sudo firewall-cmd --add-port=6969/udp --permanent
sudo firewall-cmd --reload

# iptables
sudo iptables -A INPUT -p udp --dport 6969 -j ACCEPT
```

## Technical Details

**Container:**
- Name: `thingino-tftpd`
- Default Image: `docker.io/pghalliday/tftp:latest`
- Mount: `./tftproot` → `/var/tftpboot` (read-only)
- State File: `/tmp/thingino-tftpd.state`

**Build Integration:**
- Images automatically copied to `./tftproot/` during `make pack`
- Directory created automatically when starting TFTP server
- Simple filenames in root (no subdirectories)
- Works with old U-Boot that doesn't support TFTP subdirectories

**Features:**
- ✅ Platform independent (Linux, macOS, Windows/WSL2)
- ✅ No host package installation required
- ✅ Auto-detects Podman or Docker
- ✅ Auto-pulls container image on first run
- ✅ Read-only mount for security
- ✅ Works with rootless Podman/Docker
- ✅ Simple flat directory structure for compatibility

## Security

⚠️ **Important:**
- TFTP has **NO authentication** - use only on trusted networks
- Server mounts files as **read-only** (container cannot modify them)
- Runs in isolated container namespace
- For production, use SFTP or HTTPS instead

## Integration with Build Workflow

### Development Workflow

```bash
# Start server once (uses sudo for port 69)
make tftpd-start

# Build firmware (server keeps running)
make CAMERA=camera1
make CAMERA=camera2

# Images automatically available via TFTP on port 69

# Stop when done
make tftpd-stop
```

### CI/CD Integration

```bash
# In your CI pipeline (use custom port if no sudo)
TFTP_PORT=6969 make tftpd-start
make all
# Images served for testing/deployment
make tftpd-stop
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make tftpd-start` | Start TFTP server |
| `make tftpd-stop` | Stop TFTP server |
| `make tftpd-restart` | Restart TFTP server |
| `make tftpd-status` | Show server status |
| `make tftpd-logs` | Show server logs |

## Need Help?

Run the help command:
```bash
scripts/tftpd-server.sh help
```
