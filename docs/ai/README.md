# Archived design notes

These are historical notes and proposals, kept for context. They are not
maintained documentation, and some reference files that never landed.

| File | Status |
|------|--------|
| `INGENIC_SOC_MODEL_IMPLEMENTATION.md` | Partially implemented: `BR2_INGENIC_SOC_MODEL` is live; the database lookup was replaced by `soc/<vendor>/*.mk`. |
| `README_SOC_DATABASE.md` | Proposal only. The `scripts/` database files were never committed. |
| `SOC_DATABASE_SUMMARY.md` | Proposal only. |
| `IMPLEMENTATION_GUIDE.md` | Proposal only. |
| `MOSQUITTO_TLS_FIX_NOTES.md` | Historical patch note for the mbedTLS backend. |
| `FIX_XBURST_ILLEGAL_INSTRUCTION.md` | Historical toolchain note. |

Current SoC configuration: `Config.soc.in` maps the model string to
`BR2_SOC_FAMILY`; `thingino.mk` includes `soc/<vendor>/*.mk`, which sets
`SOC_FAMILY`, `SOC_ARCH`, `SOC_RAM_MB`, and the U-Boot board and binary.
