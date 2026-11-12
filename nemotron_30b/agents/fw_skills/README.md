# fw_skills index

Read ALWAYS, by target:

| target | files |
|---|---|
| rtl (write or review VHDL) | `rtl_correctness_skills.md`, `vhdl_style_skills.md`, `generic_skills.md` |
| tb (write or review a testbench) | `testbench_skills.md` |
| ref (write or review a reference model, checkers, coverage) | `reference_model_skills.md`, `testbench_skills.md` |

Read ALSO when the design has... (saves context: skip the rest)

| file | read when the design has... |
|---|---|
| `axi4s_skills.md` | any AXI4-Stream port or valid/ready handshake |
| `fifo_skills.md` | a FIFO, ring buffer, or full/empty/count flags |
| `ram_skills.md` | a writable memory (RAM, register file, FIFO storage) |
| `rom_skills.md` | a ROM, LUT, sine/twiddle table |
| `dsp_fixed_point_skills.md` | multiply, accumulate, round, scale, sin/cos, coefficients, any DSP48 use |

When a review finds a new issue, append a numbered entry to the matching file
(rule, anti-pattern, motivating IP + date). Keep entries general (the bug
CLASS), short, and checkable.

Tools that enforce some items deterministically: `fw-check-vhdl` runs nvc
analysis plus lint `CLK001` (clocked process without `rising_edge`,
`rtl_correctness_skills.md#12`). Run it on every RTL file you write or review.
