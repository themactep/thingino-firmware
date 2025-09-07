import json
import sys
import os
import collections.abc

def deep_merge(source, destination):
    """
    Recursively merges source dict into destination dict.
    """
    for key, value in source.items():
        if isinstance(value, collections.abc.Mapping) and key in destination and isinstance(destination[key], collections.abc.Mapping):
            destination[key] = deep_merge(value, destination[key])
        else:
            destination[key] = value
    return destination

def merge_configs(device_config_path, global_config_path):
    try:
        with open(device_config_path, 'r') as f:
            device_config = json.load(f)
    except FileNotFoundError:
        print(f"Error: Device config file not found at {device_config_path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Could not decode JSON from {device_config_path}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(global_config_path, 'r') as f:
            global_config = json.load(f)
    except FileNotFoundError:
        print(f"Error: Global config file not found at {global_config_path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Could not decode JSON from {global_config_path}", file=sys.stderr)
        sys.exit(1)

    # Perform a deep merge
    merged_config = deep_merge(device_config, global_config)

    # Write to a temporary file first
    temp_file_path = global_config_path + '.tmp'
    try:
        with open(temp_file_path, 'w') as f:
            json.dump(merged_config, f, indent=2)
    except IOError as e:
        print(f"Error: Could not write to temporary file {temp_file_path}: {e}", file=sys.stderr)
        sys.exit(1)

    # Atomically replace the original file with the temporary file
    try:
        os.rename(temp_file_path, global_config_path)
    except OSError as e:
        print(f"Error: Could not rename temporary file: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <device_config.json> <prudynt.json>", file=sys.stderr)
        sys.exit(1)

    merge_configs(sys.argv[1], sys.argv[2])
