"""What a test profile is: configs/cameras-testing/<name>/qemu-test.json.

    {"soc": "t31x", "caps": ["wired", "wifi"], "net": "tap"}

soc   key into config.SOC_MACHINES
caps  what the camera has: "wired" (an uplink), "wifi" (a radio),
      "usb_direct" / "usb_direct_client" (an NCM gadget, server or client)
net   default backend: "tap" for the full lab, "slirp" for port forwards
"""
import glob
import json
import os

from .config import PROFILES_DIR, output_root


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
        return "wifi" if "wifi" in self.caps else "usb"

    def defaults(self):
        """The flags a plain run gets, per backend (what run.sh used to add):
        slirp runs bridge the guest and test from the host, tap runs have
        the lab for that."""
        return {"host_tests": self.net in ("slirp", "slip"),
                "playwright": True, "reboot_test": True}


def load(name, profiles_dir=PROFILES_DIR):
    path = os.path.join(profiles_dir, name, "qemu-test.json")
    with open(path) as f:
        d = json.load(f)
    return Profile(name, d["soc"], d.get("caps", []), d.get("net", "slirp"))


def newest_image(name):
    """Newest built image for the profile under the output tree, which
    THINGINO_OUTPUT_ROOT_DIR and THINGINO_OUTPUT_DIR move as they do for
    make."""
    # <root>/<branch>/<profile>-<suffix>/images/, where the branch may
    # itself contain a slash (feature/kernel-7.1). Two fixed depths, never
    # a recursive walk: that takes minutes on a buildroot output tree.
    pats = []
    if os.environ.get("THINGINO_OUTPUT_DIR"):
        pats.append(os.path.join(os.environ["THINGINO_OUTPUT_DIR"],
                                 "images", f"thingino-{name}.bin"))
    root = output_root()
    pats += [os.path.join(root, depth, f"{name}-*", "images",
                          f"thingino-{name}.bin")
             for depth in ("*", "*/*")]
    hits = [p for pat in pats for p in glob.glob(pat)]
    return max(hits, key=os.path.getmtime) if hits else None


def host_qemu(image):
    """The buildroot host QEMU built beside the image, if there is one."""
    out_dir = os.path.dirname(os.path.dirname(image))
    q = os.path.join(out_dir, "host", "bin", "qemu-system-mipsel")
    return q if os.access(q, os.X_OK) else None
