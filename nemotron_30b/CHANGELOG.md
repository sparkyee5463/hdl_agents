# Changelog — nemotron_30b

## 2.0.0 — 2026-11-12

Breaking: the digital twin and the legacy-IP flow are removed.

- Removed the twin (`model/<ip>_model/`, `fw_skills/twin_model_skills.md`,
  `tests/test_on_twin.py`, `conftest.py`, reviewer `target=twin`, commit type
  `twin`).
- Timing is now checked against the design doc: `verification_architect`
  writes `doc_timing(generics)` in `<ip>_interface.py`; the checker has one
  `check_<property>()` per doc protocol/flag sentence; latency and
  throughput tests measure against those numbers.
- The design doc's simulation plan has a timing contract (numbers with doc
  sections) instead of a twin contract.
- Removed the legacy pre-vcst Makefile IP flow, porting rules for old
  testbenches, and the related permission rules.

## 1.0.0 — 2026-11-11

First published version.

- `fw_lead` primary agent and 17 subagents, `fw_skills/` checklists and
  `NEMOTRON_NOTES.md`.
- Combinational-IP recipe (I_CLK-only wrapper, LATENCY 0).
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
