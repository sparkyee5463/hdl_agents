# Digital-Twin Models — Skills

A twin is a pure-Python model that is **bit-accurate** (every output bit
equals the RTL) and **cycle-accurate** (every output on every cycle equals the
RTL). Twins are imported by testbenches AND by systems engineers who chain
them into system models, so they must not depend on cocotb or on testbench
files.

Working reference (copy its shape): `fw_ip/nco/nco_1_0/model/nco_1_0_model/model.py`
and its test `fw_ip/nco/nco_1_0/testbench/cocotb_testbench_nco_1_0_shared/tests/test_twin_lockstep.py`.
Library: `fw_py_tools/fw_py_tools/twin/` (`base.py` explains the timing rule).

---

## 1. Location and names

- Package: `fw_ip/<base_name>/<ip_name>/model/<ip_name>_model/` with
  `__init__.py` + `model.py`. The package name includes the version, so
  `nco_1_0_model` and `nco_1_1_model` can be imported together.
- `__init__.py` exports: `Model`, `Generics`, `LATENCY`, and the
  Inputs/Outputs dataclasses.
- Import from anywhere: `from fw_py_tools.twin import load_model; t = load_model("<ip_name>")`.
- **Never** `from settings_dataclass import ...` or any testbench file inside a
  twin. Only `fw_py_tools.twin`, the standard library, and other twins.

## 2. Timing rule (the only one)

- `y[n] = model.tick(x[n])`. `tick` = `comb(x)` (outputs during cycle n, no
  state change) then `clock(x)` (rising edge at end of cycle n).
- `LATENCY = L` means x[n] first affects y[n+L] = number of registers on the
  path. A D flip-flop has L = 1.
- Get L by counting registers in the RTL. NEVER pick L by trial and error
  until tests pass. If the RTL count and design doc disagree, report it.

## 3. Bit-accuracy rules

- Fields of Inputs/Outputs = VHDL port names in lower case. All values are
  Python ints; std_logic is 0/1; signed ports hold negative ints.
- Reset is an input pin (`i_rst_n`), handled inside `clock()` exactly like the
  VHDL. `reset()` = VHDL signal initialisers (power-on), not the reset branch.
- Registers the VHDL does not reset (e.g. BRAM read data) are NOT cleared by
  `i_rst_n` in the model either. Unknown power-on value -> `None`.
- In `clock()`, compute every next value from the CURRENT state first, then
  commit all of them (VHDL `<=` semantics). Never update a register and then
  read it in the same `clock()`.
- Use `fw_py_tools.twin` helpers: `to_signed`, `to_unsigned`, `saturate`,
  `bits(v, hi, lo)`, `shift_right_round(v, s, mode)`, `round_half_away`.
  `ieee.math_real.round` = `round_half_away`; Python `round()` is different.
- ROM/LUT contents: compute with the same formula and operation order as the
  VHDL init function.
- Outputs are the RTL value on EVERY cycle, including when valid/EN = 0. Use
  `None` only for values the RTL itself leaves undefined ('U'/'X').
- Outputs hold the RAW port value. If the port uses a special encoding
  (one's complement, offset binary, packed fields), give a separate
  `decode_*()` helper and say in the docstring which one the lockstep
  compares (`testbench_skills.md#12`).
- The shared library `fw_py_tools.twin` is used by every IP. Put an
  IP-specific hook in the IP's own model. Change the library only with the
  lead's OK and a regression of every IP that imports it.

## 4. Required API (subclass `CycleModel`)

| member | meaning |
|---|---|
| `Generics.from_env()` | read `VCST_GENERIC_<NAME>` via `generic_from_env`, else VHDL defaults |
| `Generics.validate()` | same rules as the VHDL elaboration asserts |
| `reset()` / `comb(x)` / `clock(x)` | see rule 2 |
| `port_spec()` | `{port: PortSpec(width, signed)}` for every in/out port |
| `snapshot_state()` | JSON dict of every register, keyed by VHDL signal name |
| `latency` / `LATENCY` | rule 2 |
| system helper(s) | e.g. NCO `tone(phase_inc, n)`: a stream-level call built ON `tick`/`run`, dropping pipeline fill, for systems engineers |

## 5. Hierarchy = composition

- If the VHDL instantiates sub-IPs that have twins, the parent twin
  subclasses `ComposedModel`, puts the child twins in `self.children` (same
  instance names as the VHDL, e.g. `u_nco`) and only writes `wire()`.
- Do NOT re-implement a child's logic inline in the parent.
- Parent `LATENCY` must equal the sum along the data path; state it as a
  formula of child latencies.

## 6. Lockstep (mandatory in every RTL test)

- In the UVM-style testbench, the IP's `<Ip>_TwinModel` ticks the twin on
  the DUT's input pins at every rising edge and the checker compares EVERY
  output, EVERY cycle, exactly, in every RTL test.
  No separate lockstep driver/monitor timing.
- Older IPs without the framework use
  `fw_py_tools.twin.cocotb_lockstep.run_lockstep(dut, model, inputs, log_path=...)`
  in `tests/test_twin_lockstep.py` (>= 2000 random cycles incl. resets,
  a latency test, one test per system helper).
- Twin vs reference: `tests/test_on_twin.py` runs every cocotb test on the
  twin (`fw_py_tools.twin.cocotb_sim.run_on_twin`, pytest, no simulator) in
  every generic set; include volume tests (>= 1000 transactions).
- No tolerance (`±1 LSB`), no masking of outputs when EN=0, no extra
  latency constants in the testbench. If exact match fails, the model or the
  RTL is wrong; find which using the design doc.
- The twin is NOT the scoreboard's reference: expected values come from the
  spec-level reference model (`reference_model_skills.md`).

## 7. Review checklist (hdl_reviewer, target=twin)

1. Package path/name per rule 1; no testbench imports.
2. `LATENCY` equals the RTL register count (cite the registers).
3. Every VHDL register appears in `snapshot_state()` and in `clock()` with the
   same reset/no-reset behaviour. Documented LOSSLESS merges are allowed:
   registers that latch the same source at the same edge with the same reset
   (e.g. a duplicated sign delay, two DSP BREGs fed by one coefficient) may be
   stored once — the merge must be called out in a comment and verified
   operand-by-operand. (nco_2_0, 2026-10-28)
4. `clock()` computes-then-commits.
5. No Python `round()`, no float math outside LUT/coefficient construction.
6. Lockstep test exists, compares exactly, runs in every generic set.
7. Composite IP uses `ComposedModel` with child twins (no inline copies).
8. Encodings with TWO bit patterns per value (one's-complement ±0: 0x7FFFF
   and 0x00000) are invisible to value-domain lockstep — both decode to 0.
   Either add an explicit raw-word assertion at the phases where the doc
   names the pattern (e.g. -0 at quadrant zero-crossings), or document the
   limitation in the twin header. (nco_2_0, 2026-10-28)

## 8. "System helper" is required where natural, not for every IP

- **Rule:** the required-API list (#4) includes system helper(s) "where
  natural": a small operation built on `run()` that a system engineer would
  chain (e.g. NCO `tone(phase_inc, n)`). For an IP with no natural
  stream-level operation (a plain FIFO/buffer), do not invent a helper just
  to tick the box — document the absence in the module docstring instead.
- **Anti-pattern:** a contrived helper (e.g. "push all and drain, dropping
  pipeline fill") added only to satisfy a checklist item; it duplicates the
  testbench's job and becomes a second source of truth. axi4s_buffer_1_0
  twin review, 2026-10-30 (T-003).

## 9. snapshot_state(): include storage, omit only provably-unobservable registers

- **Rule:** every register in the twin's own register map goes into
  `snapshot_state()` — including storage arrays (a RAM's `mem` is a
  register: `all_signals.jsonl` must be able to show FIFO/RAM contents).
  The ONLY omission allowed is a register with no observable effect (it
  drives only open/unused sub-block outputs), and that must be noted in the
  register-map comment.
- **Anti-pattern:** a register map that lists a signal but a
  `snapshot_state()` that silently drops it — the lockstep passes (the
  signal is unobservable) and the gap is invisible until someone wants the
  storage in a waveform. axi4s_buffer_1_0 twin review, 2026-10-30 (T-002,
  T-005).

## 10. Sim-only severity-failure assertions in the RTL

- **Rule:** a VHDL severity-failure assertion that guards an unreachable
  state (e.g. a capture-overflow guard) has no twin equivalent — the twin
  cannot "fail the sim". Either reproduce the guard as a Python assert in
  `clock()`/`step()` or document the divergence in the twin's docstring
  (which state, which RTL assertion, why it is unreachable).
- **Anti-pattern:** a silent skip in the twin (`if cnt < N: insert`) with no
  note — if the guarded state ever becomes reachable, the RTL fails the sim
  while the twin silently drops the beat, and the lockstep "disagreement"
  points at the wrong side. axi4s_buffer_1_0 twin review, 2026-10-30 (T-004).
