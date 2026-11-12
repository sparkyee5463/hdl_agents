# Changelog — nemotron_30b

## 1.0.0 — 2026-11-11

First published version.

- `fw_lead` primary agent and 17 subagents, `fw_skills/` checklists and
  `NEMOTRON_NOTES.md`.
- Combinational-IP recipe (I_CLK-only wrapper, LATENCY 0 twin).
- Coverage rules: widths from the design doc's range, exhaustive stimulus
  where the input space is small, every port bit toggled both ways, doc
  invariants asserted on DUT outputs.
- Lead discipline: exact paths, commits with explicit `--` paths, honours
  blocked reviews, writes no IP file itself (not even through bash).
- Reference model: generics read from the environment; loaded with
  `load_reference` only.
- Testbench wiring: one consumer per queue; expected values from driven
  inputs; the shared harness is not the first suspect.
- All paths relative (agent files to the repo root, project files to the
  project root); `NEMOTRON_NOTES.md` prepended to every prompt via `{file:}`.
- Config: per-agent edit/read/bash permissions enforcing the above.
