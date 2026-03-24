#!/usr/bin/env python3
"""
Save partition information to markdown file
"""

import sys
import subprocess
import argparse
from pathlib import Path


def get_mtdparts_from_uboot_env(uboot_env_path):
    """Extract mtdparts string from u-boot environment binary."""
    try:
        result = subprocess.run(
            ['strings', uboot_env_path],
            capture_output=True,
            text=True,
            check=False
        )
        for line in result.stdout.splitlines():
            if line.startswith('mtdparts'):
                return line
    except Exception:
        pass
    return "mtdparts not found"


def format_partition_table(partitions, format_type='decimal'):
    """Format partition table in decimal, hexadecimal, or kilobytes."""
    header = f"{'NAME':<7} | {'OFFSET':>8} | {'PT_SIZE':>8} | {'CONTENT':>8} | {'ALIGNED':>8} | {'END':>8} | {'LOSS':>8} |"
    lines = [header]
    line = f"--------|----------|----------|----------|----------|----------|----------|"
    lines.append(line)

    for part in partitions:
        name = part['name']
        offset = part['offset']
        pt_size = part['pt_size']
        content = part['content']
        aligned = part['aligned']
        end = offset + aligned
        loss = pt_size - aligned

        if format_type == 'hex':
            line = f"{name:<7} | {offset:8X} | {pt_size:8X} | {content:8X} | {aligned:8X} | {end:8X} | {loss:8X} |"
        elif format_type == 'kb':
            # Convert bytes to KB
            offset_kb = offset // 1024
            pt_size_kb = pt_size // 1024
            content_kb = content // 1024
            aligned_kb = aligned // 1024
            end_kb = end // 1024
            loss_kb = loss // 1024
            line = f"{name:<7} | {offset_kb:8d} | {pt_size_kb:8d} | {content_kb:8d} | {aligned_kb:8d} | {end_kb:8d} | {loss_kb:8d} |"
        else:
            line = f"{name:<7} | {offset:8d} | {pt_size:8d} | {content:8d} | {aligned:8d} | {end:8d} | {loss:8d} |"

        lines.append(line)

    return '\n'.join(lines)


def generate_mtdparts_string(
    u_boot_kb,
    ub_env_kb,
    config_kb,
    kernel_kb,
    rootfs_kb,
    extras_kb,
    extras_offset,
    upgrade_kb,
    kernel_offset,
    flash_kb,
    flash_controller="jz_sfc",
):
    """Generate MTD partitions string."""
    return (
        f"mtdparts={flash_controller}:{u_boot_kb}k(boot),{ub_env_kb}k(env),{config_kb}k(config),"
        f"{kernel_kb}k(kernel),{rootfs_kb}k(rootfs),{extras_kb}k@0x{extras_offset:x}(extras),"
        f"{upgrade_kb}k@0x{kernel_offset:x}(upgrade),"
        f"{flash_kb}k@0(all)"
    )


def main():
    parser = argparse.ArgumentParser(description='Save partition information to markdown file')
    parser.add_argument('output_file', help='Output markdown file path')
    parser.add_argument('camera', help='Camera name')
    parser.add_argument('git_branch', help='Git branch')
    parser.add_argument('git_hash', help='Git hash')
    parser.add_argument('build_date', help='Build date')
    parser.add_argument('ub_env_bin', help='U-Boot environment binary path')
    parser.add_argument('u_boot_offset', type=int)
    parser.add_argument('u_boot_partition_size', type=int)
    parser.add_argument('u_boot_bin_size', type=int)
    parser.add_argument('u_boot_bin_size_aligned', type=int)
    parser.add_argument('ub_env_offset', type=int)
    parser.add_argument('ub_env_partition_size', type=int)
    parser.add_argument('ub_env_bin_size', type=int)
    parser.add_argument('ub_env_bin_size_aligned', type=int)
    parser.add_argument('config_offset', type=int)
    parser.add_argument('config_partition_size', type=int)
    parser.add_argument('config_bin_size', type=int)
    parser.add_argument('config_bin_size_aligned', type=int)
    parser.add_argument('kernel_offset', type=int)
    parser.add_argument('kernel_partition_size', type=int)
    parser.add_argument('kernel_bin_size', type=int)
    parser.add_argument('rootfs_offset', type=int)
    parser.add_argument('rootfs_partition_size', type=int)
    parser.add_argument('rootfs_bin_size', type=int)
    parser.add_argument('extras_offset', type=int)
    parser.add_argument('extras_partition_size', type=int)
    parser.add_argument('extras_bin_size', type=int)
    parser.add_argument('extras_bin_size_aligned', type=int)
    parser.add_argument('u_boot_size_kb', type=int)
    parser.add_argument('ub_env_size_kb', type=int)
    parser.add_argument('config_size_kb', type=int)
    parser.add_argument('kernel_size_kb', type=int)
    parser.add_argument('rootfs_size_kb', type=int)
    parser.add_argument('extras_size_kb', type=int)
    parser.add_argument('upgrade_size_kb', type=int)
    parser.add_argument('flash_size_kb', type=int)
    parser.add_argument('flash_controller', nargs='?', default='jz_sfc')

    args = parser.parse_args()

    # Build partition data structure
    partitions = [
        {
            'name': 'U_BOOT',
            'offset': args.u_boot_offset,
            'pt_size': args.u_boot_partition_size,
            'content': args.u_boot_bin_size,
            'aligned': args.u_boot_bin_size_aligned,
        },
        {
            'name': 'UB_ENV',
            'offset': args.ub_env_offset,
            'pt_size': args.ub_env_partition_size,
            'content': args.ub_env_bin_size,
            'aligned': args.ub_env_bin_size_aligned,
        },
        {
            'name': 'CONFIG',
            'offset': args.config_offset,
            'pt_size': args.config_partition_size,
            'content': args.config_bin_size,
            'aligned': args.config_bin_size_aligned,
        },
        {
            'name': 'KERNEL',
            'offset': args.kernel_offset,
            'pt_size': args.kernel_partition_size,
            'content': args.kernel_bin_size,
            'aligned': args.kernel_partition_size,
        },
        {
            'name': 'ROOTFS',
            'offset': args.rootfs_offset,
            'pt_size': args.rootfs_partition_size,
            'content': args.rootfs_bin_size,
            'aligned': args.rootfs_partition_size,
        },
        {
            'name': 'EXTRAS',
            'offset': args.extras_offset,
            'pt_size': args.extras_partition_size,
            'content': args.extras_bin_size,
            'aligned': args.extras_bin_size_aligned,
        },
    ]

    # Get mtdparts from u-boot env
    uboot_env_mtdparts = get_mtdparts_from_uboot_env(args.ub_env_bin)

    # Generate mtdparts string
    generated_mtdparts = generate_mtdparts_string(
        args.u_boot_size_kb, args.ub_env_size_kb, args.config_size_kb,
        args.kernel_size_kb, args.rootfs_size_kb, args.extras_size_kb,
        args.extras_offset, args.upgrade_size_kb, args.kernel_offset,
        args.flash_size_kb, args.flash_controller
    )

    # Generate markdown content
    markdown = f"""# {args.camera}

MTD Partition Details
---------------------
- Generated: {generated_mtdparts}
- In U-Boot: {uboot_env_mtdparts}

### Bytes
{format_partition_table(partitions, 'decimal')}

### Kilobytes
{format_partition_table(partitions, 'kb')}

### Hexadecimal
{format_partition_table(partitions, 'hex')}

Build: {args.git_branch}+{args.git_hash}, {args.build_date}

"""

    # Write to file
    Path(args.output_file).write_text(markdown)
    print(f"Partition details saved to\n{args.output_file}")


if __name__ == '__main__':
    main()
