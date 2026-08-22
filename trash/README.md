# Trash

Files moved here instead of being deleted, per project policy:
prefer rename/relocate over irreversible deletion.

## Contents

### prudynt-t/
Day/Night algorithm source files (`DayNightAlgo.hpp`, `DayNightWorker.cpp/.hpp`)
and a libschrift build patch, previously part of the prudynt streamer source
tree.  Moved here when daynight logic was refactored.  Safe to delete once
the new daynight implementation has been validated across all camera models
(currently in `overrides/prudynt-t/` or `package/prudynt-t/`).

### thingino-daynightd/
Standalone daynight daemon (`config-daynightd.cgi`).  Replaced by integrated
daynight handling in the streamer.  Safe to delete.

### scripts/
Empty.  Was a staging area for scripts being reworked.  Can be removed.
