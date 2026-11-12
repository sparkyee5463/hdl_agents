# VHDL Coding Style — HDL Review Skills

Project coding standard for all synthesizable VHDL-2008. `rtl_coder` writes to
it; `hdl_reviewer` checks every numbered item. Add a numbered entry when a
new style issue is found in review.

---

## 1. Names

- Generics `G_*`, inputs `I_*`, outputs `O_*`, constants `C_*`,
  registers `r_*`, combinational signals `s_*`, types `t_*`, functions `f_*`,
  processes `p_*`, instances `u_*`. Pipeline stages suffixed `_s0`, `_s1`, ...
- Port prefix follows the port's OWN direction (see `axi4s_skills.md#2`).
- Clock `I_CLK`; reset `I_RST_N` (active-low, synchronous) unless the design
  doc says otherwise.

## 2. Reset style

- Normal logic first; a dedicated `if I_RST_N = '0' then ... end if;` at the
  BOTTOM of the `rising_edge` block. Do not wrap all logic in
  `if reset ... else ...`.
  ```vhdl
  if rising_edge(I_CLK) then
    if I_EN = '1' then r_q <= I_D; end if;   -- normal logic
    if I_RST_N = '0' then r_q <= C_RST; end if;  -- reset last
  end if;
  ```
- Reset only control/protocol/architectural state (valid, counters, FSMs,
  accumulators that define behaviour). Do NOT reset datapath registers,
  BRAM/ROM read data, or DSP pipeline registers: it blocks BRAM/DSP register
  absorption and grows the reset tree.
- Anti-pattern (found in `nco_1_0`): reset on LUT address and output data
  registers; reset as the top-priority `if/else`.

## 3. Elaboration asserts

- Every legality constraint between generics gets an `assert ... severity
  failure` in the architecture (e.g. `G_PHASE_WIDTH >= G_ADDR_BITS`). See
  `generic_skills.md#1` for working-width overflow.
- Anti-pattern (found in `nco_1_0`): `G_PHASE_WIDTH < G_ADDR_BITS` elaborates
  and produces a negative slice; only `G_ADDR_BITS >= 2` is asserted.

## 4. Latency constant = register count

- A `C_*_LATENCY` constant must equal the number of registers from input to
  output, and the header comment must list those registers.
- Anti-pattern (found in `nco_1_0`): `C_PIPELINE_LATENCY = 3` is used as the
  sideband pipe depth, but the real latency is 4 (3 pipe stages + output
  register); the design doc says 3, the testbench used 5.

## 5. Types and arithmetic

- `numeric_std` only; explicit `resize`, `signed`/`unsigned` conversions.
- No `std_logic_arith`/`std_logic_unsigned`.
- Rounding/saturation done with documented helpers (round mode named in a
  comment), never by implicit truncation.
- `ieee.math_real` only in elaboration-time constant functions
  (`rom_skills.md#1`).

## 6. Synthesizability

- No latches (every combinational output assigned on all paths), no `after`,
  no `wait` in RTL, no combinational loops, no shared variables.
- Memories: ROM as a `constant` with a style attribute (`rom_skills.md#2`);
  RAM as a signal array written in one clocked process.

## 7. File header

- Every entity file starts with: purpose, generics/ports summary, latency
  (with register list), reset policy, dependencies.
