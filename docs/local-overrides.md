# Working with Local Package Overrides

Buildroot's **override** mechanism lets you replace a package's downloaded source
with a local directory on your machine. This is the standard way to develop or
patch a package without touching the Buildroot internals.

The `scripts/manage-package-overrides.sh` helper automates the whole workflow.

---

## How it works

When a package has an override, Buildroot reads its source from the directory you
specify instead of downloading the upstream tarball or cloning the upstream repo.
The mapping lives in `local.mk`:

```
EXFAT_NOFUSE_OVERRIDE_SRCDIR = $(BR2_EXTERNAL)/overrides/exfat-nofuse
```

During a build, Buildroot uses `rsync` to copy that directory into the build tree,
so you can edit files in `overrides/<package>/`, run `make <package>-rebuild`, and
see your changes without a full rebuild.

---

## Quick-start: set up an override

### 1. Find the package name

```sh
./scripts/manage-package-overrides.sh -l          # list all packages
./scripts/manage-package-overrides.sh -l thingino-*  # filter by pattern
```

### 2. Clone and register an override (interactive)

```sh
./scripts/manage-package-overrides.sh <package-name>
```

The script reads the package's `.mk` file, shows you the upstream URL and pinned
version, then asks:

- **Fork this GitHub repo before cloning?** – say `y` if this is a foreign
  (third-party) repo you may want to send changes back to.  The script forks it
  under your GitHub account, clones the fork, and adds the original as `upstream`.
- **Download/clone this package?** – say `y` to proceed.

The clone lands in `overrides/<package>/` and the entry is written to `local.mk`.

#### Auto mode (no prompts)

```sh
./scripts/manage-package-overrides.sh -a <pattern>   # clone without asking
./scripts/manage-package-overrides.sh -a -f <pattern> # also fork automatically
```

---

## Making and building changes

```sh
# edit source files
vim overrides/exfat-nofuse/exfat.c

# rebuild just that package
make exfat-nofuse-rebuild

# rebuild and re-generate the firmware image
make exfat-nofuse-rebuild all
```

---

## Contributing changes back

When you cloned via a fork (`-f`), the repo is pre-configured for the full
fork → branch → PR workflow:

| Remote | Points to |
|--------|-----------|
| `origin` | Your fork on GitHub |
| `upstream` | The original repo |

A local branch named `local-<short-hash>` was created at the pinned commit, so
you are never in a detached HEAD state.

```sh
cd overrides/exfat-nofuse

# commit your work
git add -p
git commit -m "fix: description of the change"

# push to your fork
git push origin local-01c30ad...

# open a pull request against the original repo
gh pr create --repo dorimanx/exfat-nofuse --base master \
  --title "fix: description" --body "Details..."
```

---

## Managing existing overrides

| Task | Command |
|------|---------|
| List all overrides and their paths | `./scripts/manage-package-overrides.sh -l` |
| Temporarily disable (comment out) | `./scripts/manage-package-overrides.sh -d <package>` |
| Re-enable a disabled override | `./scripts/manage-package-overrides.sh -e <package>` |
| Pull latest changes in an override | `./scripts/manage-package-overrides.sh -u <package>` |
| Update all overrides at once | `./scripts/manage-package-overrides.sh -u --all` |
| Remove an override entry | `./scripts/manage-package-overrides.sh -r <package>` |
| Remove all override entries | `./scripts/manage-package-overrides.sh --clean` |

Disabling an override comments out the `local.mk` line so Buildroot falls back to
the upstream source, without losing the local clone.

---

## Directory layout

```
firmware/
├── local.mk                     ← override mappings (git-ignored, machine-local)
├── overrides/                   ← git-ignored; holds your local clones
│   └── exfat-nofuse/            ← working clone (origin = fork, upstream = original)
└── scripts/
    └── manage-package-overrides.sh
```

Both `local.mk` and `overrides/` are git-ignored, so your local development setup
never pollutes the firmware repository.
