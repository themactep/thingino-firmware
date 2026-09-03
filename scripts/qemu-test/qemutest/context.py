"""The run context handed to every suite."""



class Ctx:
    """Everything a suite may need, in one place.

    Suites take just this and read what they use, so adding a suite never
    means threading another positional argument through main(). Suites
    that discover something (an address, a browser result) assign it back
    onto the context for later suites to require.
    """

    def __init__(self, guest, ser, res, args, report_dir, meta):
        self.guest = guest
        self.ser = ser
        self.res = res
        self.args = args
        self.report_dir = report_dir
        self.meta = meta
        self.mode = args.mode
        self.caps = set(args.caps)          # what the profile declares it is
        self.lab = None
        self.qmp = None
        self.guest_v4 = None
        self.guest_v6 = None
        self.playwright_ok = False

    def has(self, capability):
        return {
            "wired": "wired" in self.caps,
            "nowired": "wired" not in self.caps,
            "wifi": "wifi" in self.caps,
            "lab": self.lab is not None,
            "nolab": self.lab is None,
            "qmp": self.qmp is not None,
            "v4": self.guest_v4 is not None,
            "host": self.args.host_tests,
            "pw": self.args.playwright,
            "pw_ok": self.playwright_ok,
            "reboot": self.args.reboot_test,
        }[capability]
