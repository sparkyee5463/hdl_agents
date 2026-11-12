# hdl_agents

OpenCode agent sets for firmware HDL work (VHDL-2008 RTL, cocotb/UVM-style
testbenches, reference models, synthesis). Each directory is one agent set tuned
for one model and versioned on its own.

| Directory | Model | Version |
|---|---|---|
| [`nemotron_30b/`](nemotron_30b/) | Nemotron 3.5 Lightning 30B-A3B (llama.cpp, local) | see `nemotron_30b/VERSION` |

Releases are tagged `<set>-v<MAJOR>.<MINOR>.<PATCH>`, e.g. `nemotron_30b-v1.0.0`.
