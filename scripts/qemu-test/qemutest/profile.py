"""What a test profile is: configs/cameras-testing/<name>/qemu-test.json.

    {"soc": "t31x", "caps": ["wired", "wifi"], "net": "tap"}

soc   key into config.SOC_MACHINES
caps  what the camera has: "wired" (an uplink), "wifi" (a radio)
net   default backend: "tap" for the full lab, "slirp" for port forwards
"""
import glob
import json
import os

from .config import PROFILES_DIR, REPO_ROOT


class Profile:
    def __init__(self, name, soc, caps, net):
        self.name = name
        self.soc = soc
        self.caps = set(caps)
        self.net = net

    @property
    def mode(self):
        """The modality, for the report and the checks that still key on it."""
        if "wired" in self.caps:
            return "ethwifi" if "wifi" in self.caps else "eth"
        return "wifi"

    def defaults(self):
        """The flags a plain run gets, per backend (what run.sh used to add):
        slirp runs bridge the guest and test from the host, tap runs have
        the lab for that."""
        return {"host_tests": self.net == "slirp",
                "playwright": True, "reboot_test": True}


def load(name, profiles_dir=PROFILES_DIR):
    path = os.path.join(profiles_dir, name, "qemu-test.json")
    with open(path) as f:
        d = json.load(f)
    return Profile(name, d["soc"], d.get("caps", []), d.get("net", "slirp"))


def newest_image(name, repo_root=REPO_ROOT):
    """Newest built image for the profile under output/."""
    # Two fixed levels (output/<branch>/<profile>-<suffix>/images/); a
    # recursive walk of a buildroot output tree takes minutes.
    hits = glob.glob(os.path.join(repo_root, "output", "*", f"{name}-*",
                                  "images", f"thingino-{name}.bin"))
    return max(hits, key=os.path.getmtime) if hits else None


def host_qemu(image):
    """The buildroot host QEMU built beside the image, if there is one."""
    out_dir = os.path.dirname(os.path.dirname(image))
    q = os.path.join(out_dir, "host", "bin", "qemu-system-mipsel")
    return q if os.access(q, os.X_OK) else None
