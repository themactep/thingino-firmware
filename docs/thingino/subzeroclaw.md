SubZeroClaw on Thingino
=======================

SubZeroClaw is installed as a small CLI agent runtime with Thingino defaults:

- Config: `/etc/subzeroclaw/config`
- Skills: `/etc/subzeroclaw/skills/`
- Logs: `/tmp/subzeroclaw/logs/`

The package also installs a default system skill at:
`/etc/subzeroclaw/skills/system.md`

Running SubZeroClaw
-------------------

Use the full binary:

```sh
subzeroclaw "check free memory and summarize briefly"
```

Or use the short wrapper:

```sh
szc "check free memory and summarize briefly"
```

`szc` forwards command-line input to `subzeroclaw` and suppresses stderr output.

If your prompt contains quotes, quote it safely at shell level:

```sh
szc 'say "hello" and show uptime'
szc "say \"hello\" and show uptime"
```

Config file
-----------

Example keys in `/etc/subzeroclaw/config`:

```ini
api_key = "sk-or-your-openrouter-key-here"
model = "minimax/minimax-m2.5"
skills_dir = "/etc/subzeroclaw/skills"
log_dir = "/tmp/subzeroclaw/logs"
max_turns = 200
max_messages = 40
```

Adding custom skills
--------------------

Add markdown skill files to `/etc/subzeroclaw/skills/`:

```sh
cat > /etc/subzeroclaw/skills/diagnostics.md << 'EOF'
## Diagnostics Agent

You diagnose Thingino runtime issues using lightweight commands and short output.
EOF
```

Then run:

```sh
subzeroclaw "use diagnostics skill to inspect current system state"
```
