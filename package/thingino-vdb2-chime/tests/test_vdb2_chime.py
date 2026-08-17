#!/usr/bin/env python3

import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


PACKAGE_DIR = Path(__file__).resolve().parents[1]
CHIME = PACKAGE_DIR / "files" / "vdb2-chime"
INIT_SCRIPT = PACKAGE_DIR / "files" / "S14vdb2-chime"


class Vdb2ChimeTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.temp = Path(self.temporary_directory.name)
        self.config = self.temp / "thingino.json"
        self.state = self.temp / "gpio-state.json"
        self.log = self.temp / "operations.log"
        self.pad_state = self.temp / "pad-state"
        self.pull_down_state = self.temp / "pull-down-state"
        self.pad_log = self.temp / "pad-operations.log"
        self.devmem = self.temp / "devmem"
        self.jct = self.temp / "jct"
        self.gpio = self.temp / "gpio"
        self.usleep = self.temp / "usleep"
        self.sysfs = self.temp / "sysfs"

        self.config.write_text(
            json.dumps(
                {
                    "mechanical_chime": {
                        "stage1_gpio": 59,
                        "stage2_gpio": 52,
                        "trigger_gpio": 53,
                        "sense_gpio": 51,
                        "pulse_ms": 200,
                        "max_pulse_ms": 1000,
                        "arm_ms": 1500,
                        "settle_ms": 30,
                        "release_ms": 1000,
                    }
                }
            ),
            encoding="ascii",
        )
        self.set_state({"51": 1, "53": 0, "52": 0, "59": 0})
        self.pad_state.write_text("0x60084800\n", encoding="ascii")
        self.pull_down_state.write_text("0x80000400\n", encoding="ascii")
        self.make_tool(
            self.devmem,
            """
            #!/usr/bin/env python3
            import os
            from pathlib import Path
            import sys

            arguments = sys.argv[1:]
            with open(os.environ["CHIME_TEST_PAD_LOG"], "a", encoding="ascii") as log_file:
                log_file.write(" ".join(arguments) + "\\n")

            address = int(arguments[0], 0)
            pull_up_path = Path(os.environ["CHIME_TEST_PAD_STATE"])
            pull_down_path = Path(os.environ["CHIME_TEST_PULL_DOWN_STATE"])
            state_path = pull_down_path if address in (0x10011120, 0x10011128) else pull_up_path

            if len(arguments) == 3:
                value = int(arguments[2], 0)
                if address in (0x10011118, 0x10011128):
                    current = int(state_path.read_text(encoding="ascii"), 0)
                    value = current & ~value
                state_path.write_text(f"0x{value:08x}\\n", encoding="ascii")
            else:
                print(state_path.read_text(encoding="ascii").strip())
            """,
        )
        self.make_tool(
            self.jct,
            """
            #!/usr/bin/env python3
            import json
            import sys

            with open(sys.argv[1], encoding="ascii") as config_file:
                value = json.load(config_file)
            for component in sys.argv[3].split("."):
                value = value[component]
            print(json.dumps(value))
            """,
        )
        self.make_tool(
            self.gpio,
            """
            #!/usr/bin/env python3
            import json
            import os
            import sys

            state_path = os.environ["CHIME_TEST_STATE"]
            log_path = os.environ["CHIME_TEST_LOG"]
            operation = " ".join(sys.argv[1:])
            with open(log_path, "a", encoding="ascii") as log_file:
                log_file.write("gpio " + operation + "\\n")
            with open(state_path, encoding="ascii") as state_file:
                state = json.load(state_file)
            if sys.argv[1] == "read":
                override_key = "CHIME_TEST_READ_" + sys.argv[2]
                if override_key in os.environ:
                    print(os.environ[override_key])
                else:
                    print(state.get(sys.argv[2], 0))
            elif sys.argv[1] == "set":
                if operation == os.environ.get("CHIME_TEST_FAIL"):
                    sys.exit(1)
                state[sys.argv[2]] = int(sys.argv[3])
                with open(state_path, "w", encoding="ascii") as state_file:
                    json.dump(state, state_file)
            elif sys.argv[1] == "input":
                pass
            """,
        )
        self.make_tool(
            self.usleep,
            """
            #!/bin/sh
            printf 'sleep %s\\n' "$1" >>"$CHIME_TEST_LOG"
            if [ "${CHIME_TEST_SIGNAL_AT:-}" = "$1" ]; then
                kill -TERM "$PPID"
            fi
            """,
        )

    def tearDown(self):
        self.temporary_directory.cleanup()

    @staticmethod
    def make_tool(path, content):
        path.write_text(textwrap.dedent(content).lstrip(), encoding="ascii")
        path.chmod(0o755)

    def set_state(self, state):
        self.state.write_text(json.dumps(state), encoding="ascii")

    def run_chime(self, *arguments, extra_env=None):
        environment = os.environ.copy()
        environment.update(
            {
                "VDB2_CHIME_CONFIG": str(self.config),
                "VDB2_CHIME_DEVMEM": str(self.devmem),
                "VDB2_CHIME_GPIO": str(self.gpio),
                "VDB2_CHIME_JCT": str(self.jct),
                "VDB2_CHIME_USLEEP": str(self.usleep),
                "VDB2_CHIME_SYSFS": str(self.sysfs),
                "VDB2_CHIME_RUN_DIR": str(self.temp),
                "CHIME_TEST_STATE": str(self.state),
                "CHIME_TEST_LOG": str(self.log),
                "CHIME_TEST_PAD_LOG": str(self.pad_log),
                "CHIME_TEST_PAD_STATE": str(self.pad_state),
                "CHIME_TEST_PULL_DOWN_STATE": str(self.pull_down_state),
            }
        )
        if extra_env:
            environment.update(extra_env)
        return subprocess.run(
            ["sh", str(CHIME), *arguments],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def operations(self):
        if not self.log.exists():
            return []
        return self.log.read_text(encoding="ascii").splitlines()

    def pad_operations(self):
        if not self.pad_log.exists():
            return []
        return self.pad_log.read_text(encoding="ascii").splitlines()

    @staticmethod
    def stock_pad_operations():
        return [
            "0x10011110 32 0x6e094800",
            "0x10011110 32",
            "0x10011118 32 0x08380000",
            "0x10011128 32 0x08380000",
            "0x10011110 32",
            "0x10011120 32",
        ]

    def create_exported_sysfs_pins(self, state):
        for pin, value in state.items():
            pin_dir = self.sysfs / f"gpio{pin}"
            pin_dir.mkdir(parents=True)
            (pin_dir / "value").write_text(f"{value}\n", encoding="ascii")
            direction = "in" if pin == 51 else "out"
            (pin_dir / "direction").write_text(direction, encoding="ascii")

    def test_ring_matches_recovered_sequence(self):
        result = self.run_chime("ring")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pad_operations(), self.stock_pad_operations())
        self.assertEqual(
            self.operations(),
            [
                "gpio read 53",
                "gpio set 59 0",
                "gpio read 59",
                "gpio set 52 0",
                "gpio read 52",
                "gpio set 53 0",
                "gpio read 53",
                "gpio input 51",
                "gpio read 51",
                "sleep 1500000",
                "gpio set 59 1",
                "gpio read 59",
                "sleep 30000",
                "gpio set 52 1",
                "gpio read 52",
                "sleep 30000",
                "gpio set 53 1",
                "gpio read 53",
                "sleep 200000",
                "gpio set 53 0",
                "gpio read 53",
                "sleep 1000000",
                "gpio set 52 0",
                "gpio read 52",
                "sleep 30000",
                "gpio set 59 0",
                "gpio read 59",
            ],
        )

    def test_ring_uses_direct_sysfs_for_initialized_pins(self):
        self.create_exported_sysfs_pins({51: 1, 53: 0, 52: 0, 59: 0})

        result = self.run_chime("ring")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.operations(),
            [
                "sleep 1500000",
                "sleep 30000",
                "sleep 30000",
                "sleep 200000",
                "sleep 1000000",
                "sleep 30000",
            ],
        )
        for pin in (59, 52, 53):
            value = (self.sysfs / f"gpio{pin}" / "value").read_text(
                encoding="ascii"
            )
            self.assertEqual(value, "0")
        self.assertEqual(
            (self.sysfs / "gpio51" / "direction").read_text(encoding="ascii"),
            "in",
        )

    def test_low_sense_refuses_to_energize_outputs(self):
        self.set_state({"51": 0, "53": 0, "52": 0, "59": 0})

        result = self.run_chime("ring")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to energize", result.stderr)
        self.assertEqual(
            self.operations(),
            [
                "gpio read 53",
                "gpio set 59 0",
                "gpio read 59",
                "gpio set 52 0",
                "gpio read 52",
                "gpio set 53 0",
                "gpio read 53",
                "gpio input 51",
                "gpio read 51",
                "sleep 100000",
                "gpio read 51",
            ],
        )

    def test_init_sets_every_output_low_without_release_delays(self):
        self.set_state({"51": 1, "53": 1, "52": 1, "59": 1})

        result = self.run_chime("init")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pad_operations(), self.stock_pad_operations())
        self.assertEqual(
            self.operations(),
            [
                "gpio set 59 0",
                "gpio read 59",
                "gpio set 52 0",
                "gpio read 52",
                "gpio set 53 0",
                "gpio read 53",
                "gpio input 51",
            ],
        )
        state = json.loads(self.state.read_text(encoding="ascii"))
        self.assertEqual({state[str(pin)] for pin in (59, 52, 53)}, {0})

    def test_init_attempts_every_output_after_a_failure(self):
        result = self.run_chime(
            "init", extra_env={"CHIME_TEST_FAIL": "set 59 0"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.operations(),
            [
                "gpio set 59 0",
                "gpio set 52 0",
                "gpio read 52",
                "gpio set 53 0",
                "gpio read 53",
            ],
        )

    def test_invalid_sense_read_is_not_treated_as_ready(self):
        result = self.run_chime(
            "ring", extra_env={"CHIME_TEST_READ_51": ""}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("returned an invalid level", result.stderr)
        self.assertEqual(
            self.operations(),
            [
                "gpio read 53",
                "gpio set 59 0",
                "gpio read 59",
                "gpio set 52 0",
                "gpio read 52",
                "gpio set 53 0",
                "gpio read 53",
                "gpio input 51",
                "gpio read 51",
            ],
        )

    def test_output_readback_mismatch_fails_initialization(self):
        result = self.run_chime(
            "init", extra_env={"CHIME_TEST_READ_59": "1"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("GPIO 59 read back 1 after writing 0", result.stderr)
        self.assertEqual(
            self.operations(),
            [
                "gpio set 59 0",
                "gpio read 59",
                "gpio set 52 0",
                "gpio read 52",
                "gpio set 53 0",
                "gpio read 53",
            ],
        )

    def test_boot_script_runs_low_state_initialization(self):
        invocation_log = self.temp / "init-invocation.log"
        fake_chime = self.temp / "fake-vdb2-chime"
        self.make_tool(
            fake_chime,
            """
            #!/bin/sh
            printf '%s\\n' "$*" >"$CHIME_INIT_TEST_LOG"
            """,
        )
        environment = os.environ.copy()
        environment.update(
            {
                "VDB2_CHIME_BIN": str(fake_chime),
                "CHIME_INIT_TEST_LOG": str(invocation_log),
            }
        )

        result = subprocess.run(
            ["sh", str(INIT_SCRIPT), "start"],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(invocation_log.read_text(encoding="ascii"), "init\n")

    def test_duration_above_configured_limit_is_rejected(self):
        result = self.run_chime("ring", "1001")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("between 1 and 1000", result.stderr)
        self.assertEqual(self.operations(), [])

    def test_status_identifies_gpio51_as_energy_ready(self):
        result = self.run_chime("status")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("energy_ready gpio 51: 1", result.stdout)
        self.assertEqual(self.pad_operations(), [])

    def test_pad_register_readback_mismatch_refuses_gpio_access(self):
        result = self.run_chime(
            "ring", extra_env={"CHIME_TEST_PAD_STATE": "/dev/null"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pull-up register read back", result.stderr)
        self.assertEqual(self.operations(), [])

    def test_output_failure_runs_emergency_shutdown(self):
        result = self.run_chime(
            "ring", extra_env={"CHIME_TEST_FAIL": "set 53 1"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("forcing the chime outputs off", result.stderr)
        self.assertEqual(
            self.operations()[-8:],
            [
                "gpio set 53 0",
                "gpio read 53",
                "sleep 1000000",
                "gpio set 52 0",
                "gpio read 52",
                "sleep 30000",
                "gpio set 59 0",
                "gpio read 59",
            ],
        )

    def test_shutdown_attempts_every_output_after_a_failure(self):
        result = self.run_chime(
            "off", extra_env={"CHIME_TEST_FAIL": "set 53 0"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.operations(),
            [
                "gpio set 53 0",
                "sleep 1000000",
                "gpio set 52 0",
                "gpio read 52",
                "sleep 30000",
                "gpio set 59 0",
                "gpio read 59",
            ],
        )

    def test_signal_stops_ring_and_runs_emergency_shutdown(self):
        result = self.run_chime(
            "ring", extra_env={"CHIME_TEST_SIGNAL_AT": "200000"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("forcing the chime outputs off", result.stderr)
        self.assertEqual(
            self.operations()[-8:],
            [
                "gpio set 53 0",
                "gpio read 53",
                "sleep 1000000",
                "gpio set 52 0",
                "gpio read 52",
                "sleep 30000",
                "gpio set 59 0",
                "gpio read 59",
            ],
        )
        state = json.loads(self.state.read_text(encoding="ascii"))
        self.assertEqual({state[str(pin)] for pin in (59, 52, 53)}, {0})


if __name__ == "__main__":
    unittest.main()
