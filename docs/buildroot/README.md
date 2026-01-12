# Buildroot Documentation

This directory contains documentation for Thingino's Buildroot external tree.

## Contents

### Docker/Podman Build Environment

Containerized build environment for reproducible builds across all systems.

- **[Docker Build Environment](docker-build-environment.md)** - Complete guide to building in containers
- **[Docker Quick Reference](docker-quick-reference.md)** - Quick command reference for container builds

### Package Override Management

Tools and workflows for managing local package source code overrides during development.

- **[Package Override Management](package-override-management.md)** - Complete guide to using the `manage-package-overrides.sh` script
- **[Quick Reference](package-override-quick-reference.md)** - Quick command reference for package override management

### Official Buildroot Documentation

- **[manual.pdf](manual.pdf)** - Official Buildroot manual (PDF format)
- **[manual.text](manual.text)** - Official Buildroot manual (text format)

## Quick Links

### Docker/Container Builds

- [Quick Start - Container Build](docker-build-environment.md#quick-start)
- [One-line build](docker-quick-reference.md#one-line-build)
- [Troubleshooting containers](docker-build-environment.md#troubleshooting)

### Package Development

- [Setting up package overrides](package-override-management.md#1-setting-up-package-overrides)
- [Updating package sources](package-override-management.md#4-updating-package-sources)
- [Enabling/disabling overrides](package-override-management.md#3-enabling-and-disabling-overrides)
- [Quick reference commands](package-override-quick-reference.md)

### Scripts

- **Container build**: `docker-build.sh`
- **Package overrides**: `scripts/manage-package-overrides.sh`

## See Also

- [Thingino Documentation](../thingino/)
- [Official Buildroot Documentation](https://buildroot.org/docs.html)
