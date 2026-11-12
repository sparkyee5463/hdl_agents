# nemotron_30b agents

An OpenCode primary agent (`fw_lead`) plus subagents for firmware HDL IP work,
tuned for **Nemotron 3.5 Lightning 30B-A3B** served by llama.cpp.

## Layout

Paths in this file are relative to the repo root.

```
nemotron_30b/
  agents/
    fw_lead.md            primary agent: routing, git, stage checks
    NEMOTRON_NOTES.md     prepended to every agent's prompt (model-specific lessons)
    subs/*.md             subagents (architects, coder, reviewer, sim, synth, debug group)
    fw_skills/*.md        checklists the writers follow and the reviewer checks
                          (fw_skills/README.md says which file applies when)
  opencode/
    opencode.json         agent registration + per-agent permissions
    package.json
  tools/
    run_fw_lead.sh        non-interactive run with auto-continue on empty stops
```

## Paths

- Agent files are referenced relative to the repo root
  (`nemotron_30b/agents/fw_skills/...`).
- `opencode.json` loads prompts with `{file:../agents/...}`; opencode resolves
  `{file:}` relative to the config file, so this works wherever you clone
  the repo. A plain string in `"prompt"` would be used as the prompt text.
- Project paths in the prompts (`tools/eda_env.sh`, `fw_ip/...`,
  `hdl_env/bin/python`) are relative to the project root the agents run in.
- `fw_lead` has `external_directory: deny`, so clone this repo inside the
  project (e.g. `<project>/hdl_agents`) if you want the lead to append
  `fw_skills` entries.

## Install

Copy the whole `nemotron_30b/` folder. `opencode/` and `agents/` must stay
side by side: `opencode.json` loads every prompt with `{file:../agents/...}`,
and opencode stops with `bad file reference` if `agents/` isn't next to it.
Never copy `opencode.json` on its own.

Either way below, opencode reads `$XDG_CONFIG_HOME/opencode/opencode.json`.

- **Per run (recommended):** put the folder anywhere and point opencode at it:
  ```
  cp -r nemotron_30b ~/agents/nemotron_30b
  cd <project root> && XDG_CONFIG_HOME=~/agents/nemotron_30b opencode
  ```
  Your normal `~/.config/opencode` stays untouched.
- **As your global config:** copy both folders into `~/.config`
  (back up an existing `~/.config/opencode` first):
  ```
  cp -r nemotron_30b/opencode nemotron_30b/agents ~/.config/
  ```
  This gives `~/.config/opencode/opencode.json` and `~/.config/agents/`.

## Setup

1. Serve the model with llama.cpp on `http://127.0.0.1:8080/v1` (edit
   `provider.llamacpp.options.baseURL` in `opencode/opencode.json`
   otherwise). The config uses model id `nemotron-30b`, 256k context, 32k
   output.
2. Interactive, from the project root:
   `XDG_CONFIG_HOME=<path to nemotron_30b> opencode`
3. Headless:
   `PROJECT_ROOT=<project root> <path to nemotron_30b>/tools/run_fw_lead.sh logs/run1 prompt.md`
   (the launcher sets `XDG_CONFIG_HOME` to its own folder).

Check what opencode actually loaded with `opencode debug config`. A
project-level `opencode.json` in the project root is merged in too; remove or
check it if agents pick the wrong model.

## Project layout the agents expect

The prompts assume this layout under the project root (names are relative):

- `tools/eda_env.sh` puts the HDL venv (`python`, `nvc`, `fw-*` tools) on PATH.
- `fw_ip/<base_name>/<ip_name>/...` with `ip_name = <base_name>_<major>_<minor>`;
  `hdl/`, `design_doc/`, `model/<ip>_model/` (twin), `model/<ip>_reference/`,
  `testbench/cocotb_testbench_<ip>_shared/`, `testbench/vcst/`, `work/`.
- `fw_ip/fw_py_tools/` (twin library, vcst) and `fw_ip/vhdl_helper/`: shared,
  agents never edit them.
- `fw_ip/.walkthrough/fw_git.sh`: the only git entry point the lead uses
  (start / commit / merge per IP branch `ip/<ip_name>`).

## Permission design

Nemotron ignores "read only these files" and "don't write this" in a prompt,
so independence and scope are enforced in `opencode.json`:

- `fw_lead` orchestrates only: bash is an allowlist of read-only commands plus
  `fw_git.sh`, `fw-verify`, `pytest`; it may edit only `STATE.md` and
  `fw_skills/`; the built-in `general`/`explore`/`build`/`plan` agents are
  denied so it can't route around subagent permissions.
- `verification_architect` writes the reference model and coverage from the
  design doc and cannot read the RTL, twin or testbench.
- `cocotb_tb_architect` cannot edit the reference model, coverage, RTL,
  design doc or shared libraries.
- `hdl_reviewer` writes only `reviews/*`.
- Acceptance scripts in `fw_ip/<base>/<ip>/work/{ref,tb}_checks.py` (yours,
  not shipped here) are runnable but not editable by the agents.
- `*/agent_runs/*` is unreadable to every agent: keep run logs and any
  hidden graders there.

## Versioning

`VERSION` holds the semantic version of this agent set. Bump MAJOR for
changes that break the expected project layout or config, MINOR for new
agents/skills or behaviour changes, PATCH for wording fixes. Record changes in
`CHANGELOG.md` and tag `nemotron_30b-vX.Y.Z`.
