# send2train test harness

Runs `package/thingino-send2/files/send2train` against the reference collector
in `contrib/train-collector`, with stub `jct` and `prudyntctl` binaries so the
real `send2common` can run on a desktop.

```bash
sh contrib/send2train-test/run-tests.sh
```

Covered:

- the opt-in gate (no upload, no pseudonym created before consent);
- the 128-bit contributor token, its mode, and its stability across uploads;
- daily limit, spacing window, `Retry-After` handling, exponential backoff;
- frame validation (magic, size) and that a caller-supplied `-f` file survives;
- dry-run mode leaving the quota untouched;
- the exact request on the wire: only the schema header, the token, and one
  `frame` part, with no hostname or local path anywhere in it.

The collector suite itself lives in `contrib/train-collector`:

```bash
cd contrib/train-collector && python3 -m unittest -v test_collector.py
```
