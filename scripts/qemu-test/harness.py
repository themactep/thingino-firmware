#!/usr/bin/env -S python3 -u
"""Entry point for the QEMU firmware test suite; see qemutest/driver.py."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from qemutest.driver import main  # noqa: E402

if __name__ == "__main__":
    main()
