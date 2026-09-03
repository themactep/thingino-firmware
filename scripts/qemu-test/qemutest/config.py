"""Machine table, host-side port assignments and where things live."""
import os

# scripts/qemu-test (the package sits one level below it) and the repo root
SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
PROFILES_DIR = os.path.join(REPO_ROOT, "configs", "cameras-testing")


SOC_MACHINES = {
    "t10":  ("ingenic-t10",  64),
    "t10n": ("ingenic-t10",  64),
    "t20":  ("ingenic-t20",  128),
    "t20x": ("ingenic-t20",  128),
    "t21":  ("ingenic-t21",  64),
    "t21n": ("ingenic-t21",  64),
    "t23":  ("ingenic-t23",  64),
    "t23n": ("ingenic-t23",  64),
    "t30":  ("ingenic-t30",  128),
    "t30x": ("ingenic-t30",  128),
    "t31":  ("ingenic-t31",  128),
    "t31x": ("ingenic-t31",  128),
    "t32":  ("ingenic-t32",  256),
    "t32nq":("ingenic-t32",  256),
    "t40":  ("ingenic-t40",  256),
    "t40nn":("ingenic-t40",  256),
    "t41":  ("ingenic-t41",  256),
    "t41nq":("ingenic-t41",  256),
    "a1":   ("ingenic-a1",   256),
    "a1n":  ("ingenic-a1",   256),
}


PORTAL_PORT = 19080


WEBUI_PORT  = 19080


SSH_FWD_PORT = 19022


SSH_OPTS = ["-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=5",
            "-o", "LogLevel=ERROR",
            "-o", "PasswordAuthentication=no",
            "-o", "BatchMode=yes"]
