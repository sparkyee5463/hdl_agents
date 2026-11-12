# ROM / LUT — HDL Review Skills

Common things to check when reviewing HDL that implements or interfaces with a
read-only table (ROM, LUT, twiddle/sin-cos table, phase-to-amplitude table).
**Add a new numbered entry here every time a new ROM issue is found in review,
so the same mistake is not made again.** Each entry should state the rule, the
anti-pattern, and (when relevant) the concrete example that motivated it.

The `hdl_reviewer` subagent applies this checklist to the VHDL that
`rtl_coder` writes. Keep entries short, concrete, and checkable.

First used: `twiddle_rom_1_0` review (2026-09-10).

---

## 1. `math_real` / transcendentals only in elaboration-time constant functions

- **Rule:** `ieee.math_real` (`MATH_PI`, `sin`, `cos`, `round`, ...) and any
  other transcendental or impure operation must appear **only inside
  elaboration-time pure functions that feed a constant** (e.g. a ROM init
  function used as `constant C_ROM : t_rom := init_rom;`). Never in a process,
  a concurrent statement, a generic map, or a port-width expression.
- **Anti-pattern:** calling `sin`/`cos` in a clocked process, or using
  `math_real` to size a port (`clog2`-style integer loops, not `math_real`,
  are the legal tool for port-width expressions).
- **Check:** grep the file for `MATH_PI|sin\(|cos\(|round\(` and confirm every
  hit is inside the init function (or a function called only from the
  constant declaration). Also confirm the tool actually elaborates it:
  `nvc --std=2008 -a ... -e <top>` (NVC and Vivado handle the
  constant-function form; if a restricted flow refuses it, the documented
  fallback is a generated package with a Python-computed constant array,
  bit-identical contents, unchanged entity interface).

## 2. Storage-style attribute on the ROM constant

- **Rule:** When a `G_ROM_STYLE`-class generic exists, it must actually reach
  a storage-style attribute on the ROM storage constant (e.g.
  `attribute rom_style of C_ROM : constant is G_ROM_STYLE;`).
- **Rule (tool caveat, from `twiddle_rom_1_0` review):** the attribute name
  matters per vendor — Vivado documents `ram_style` (and `rom_style` for some
  ROM templates), while some specs mandate `rom_style`. When the spec fixes
  the attribute name, keep it, but **verify in the OOC/synthesis reports that
  the inferred memory style actually follows the generic**; if the tool
  silently ignores it, report it (add the vendor-documented alias or request
  a spec change — do not change unilaterally).
- **Anti-pattern:** the generic is declared and documented but never attached
  to any attribute, so synthesis picks a storage style at random.

## 3. Clocked read-data stage and optional free-running output register

- **Rule:** A synchronous ROM read pipeline must state its exact latency in the
  header and design doc. For Vivado BRAM/URAM ROM packing, use a clocked,
  `rd_en`-gated read-data register (`rd_data <= ROM(addr)` inside the clock
  process) as the first read stage. The read-data register holds when
  `rd_en = '0'`, which preserves the external "output holds when rd_en = 0"
  contract.
- **Rule:** An optional second output register (`G_OUT_REG = true`) may be
  free-running if the read-data register is `rd_en`-gated. Free-running is
  required when the last read of a burst must be delivered even if `rd_en`
  deasserts immediately after the final request.
- **Anti-pattern (old 1_0 bug):** gating both the read-data register and the
  optional output register with `rd_en`; the final read is captured in the
  read-data register but never passes through to the output before the output
  freezes.
- **Anti-pattern (combinational read):** `rd_data <= ROM(addr);` as a purely
  combinational read. Even a 512x36 ROM may map to LUTs in Vivado 2025.1; see
  entry 7.
- **Initializer rule:** no-reset registers that are plain logic may use
  `(others => '0')` initializers. A BRAM/URAM ROM read-data register may be left
  uninitialized if the tool/inference pattern requires it; the testbench must
  settle the DUT with a known read sequence before monitored comparisons.
- **Check:** for each latency mode, trace one address presentation and count
  edges to the output; verify the count equals the documented latency and that
  an enable-low window leaves all outputs unchanged after the read-data
  register has settled.

## 4. Asymmetric fixed-point saturation, documented and single-point

- **Rule:** For Q1.(W-1) tables, the positive rail is `2**(W-1)-1` (+1.0 is
  **not** representable) and the negative rail is `-2**(W-1)` (-1.0 **is**
  representable). Saturation must be **asymmetric** and implemented in exactly
  one place (the `real_to_slv`-class function), with the rule documented in
  the header and design doc.
- **Anti-pattern (the classic twiddle bug):** symmetric scaling by
  `2**(W-1)-1` (e.g. an NCO-style table) corrupts the exact `-1.0` sine rail;
  or no clamp at all, so entry 0 (+1.0) wraps to the most negative value and
  the first FFT stage comes out inverted — it looks like noise, not an
  obvious failure.
- **Check:** entry 0 = `(2**(W-1)-1, 0)`; entry `N/4` = `(0, -2**(W-1))`
  exactly; no other entry may sit on the positive rail unless its exact value
  rounds to one.

## 5. Power-of-two depth assert when the depth math requires it

- **Rule:** When the address width is `clog2(DEPTH)` and correct indexing
  relies on `DEPTH` being a power of two, add an elaboration
  `assert is_pow2(G_NUM_POINTS)` (or equivalent) with `severity failure`,
  plus a lower bound on the generic so the address port is non-empty
  (e.g. `G_NUM_POINTS >= 4` so `clog2(N/2) >= 1`).
- **Anti-pattern:** silent misbehavior (truncated/wrapped addresses) when a
  non-power-of-two depth is instantiated.

## 6. Vivado 2025.1: attach `rom_style` to the clocked read-data signal, not only the constant

- **Rule:** For BRAM/URAM ROM packing in Vivado 2025.1, attach the style
  attribute to the clocked read-data signal:
  `attribute rom_style of s_rd_data : signal is G_ROM_STYLE;`.
- **Anti-pattern:** attaching only to the constant array:
  `attribute rom_style of C_ROM : constant is G_ROM_STYLE;`. Vivado 2025.1
  reports `WARNING: [Synth 8-5733] ignoring attributes on constant declaration
  C_ROM`, and the generic may have no effect.
- **Check:** the OOC log has no `Synth 8-5733` for the active ROM, and the
  `ROM: Preliminary Mapping Report` / resource utilization report show the
  intended implementation (e.g. `Block RAM` / `RAMB18E2`).

## 7. Vivado BRAM ROM packing needs a clocked read-data register

- **Rule:** A ROM read that must pack into BRAM/URAM must be written as a
  clocked, enable-gated read-data register:
  ```vhdl
  process (clk)
  begin
    if rising_edge(clk) then
      if rd_en = '1' then
        s_rd_data <= C_ROM(to_integer(unsigned(rd_addr)));
      end if;
    end if;
  end process;
  ```
  `rd_en` becomes the BRAM read clock enable; `rd_addr` drives the BRAM address
  combinationally.
- **Anti-pattern:** a purely combinational read, `s_rd_data <= C_ROM(addr);`.
  Vivado 2025.1 can map even a `512 x 36` ROM to LUTs in that form, even though
  it fits one RAMB18.
- **Check:** the synthesis report maps the read-data register (e.g.
  `s_rd_data_reg`) as `Block RAM` / `RAMB18E2`, not LUTs, and the external
  latency contract is unchanged.

## 8. Do not initialize a ROM address register when BRAM/URAM packing is required

- **Rule:** If an explicit address register drives a ROM address, avoid an
  explicit initializer. Vivado 2025.1 reports
  `WARNING: [Synth 8-6040] Register <addr>_reg driving address of a ROM cannot
  be packed in BRAM/URAM because of presence of initial value.` The cleaner
  pattern is to drive the ROM address combinationally and use `rd_en` as the
  clock enable on the read-data register.
- **Anti-pattern:** `signal s_addr_q : std_logic_vector(...) := (others => '0');`
  followed by a combinational or registered read of `C_ROM(s_addr_q)`.
- **Check:** no `Synth 8-6040` in the OOC log and the ROM mapping report shows
  the intended block memory.

## 9. Free-running output register after a ROM read

- **Rule:** If `G_OUT_REG = true` must deliver the last read of a burst when
  `rd_en` deasserts immediately after the final request, the output register
  must latch the read-data register every cycle:
  `s_out <= s_rd_data;`. The read-data register can still be `rd_en`-gated so
  it holds during idle.
- **Anti-pattern:** `if rd_en then s_out <= s_rd_data; end if;` when the
  read-data register is also `rd_en`-gated; the final read is captured in
  `s_rd_data` but the output freezes one value early.
- **Check:** the Python model updates `out_q = rd_data_q` every tick when
  `out_reg` is enabled and updates `rd_data_q = rom[addr]` only when
  `rd_en` is true; latency and `rd_en` gating tests pass.

## 10. NVC single-driver rule for signal-array RAMs

- **Rule:** In NVC, a signal array used as RAM memory must have exactly one
  VHDL driver. For dual-clock/dual-port RAMs, use a single process sensitive to
  both clocks and select the correct port/clock inside the process; do not
  write variable-index elements from two separate clocked processes.
- **Anti-pattern:**
  ```vhdl
  process (clk_a)
  begin
    if rising_edge(clk_a) then mem(wa) <= da; end if;
  end process;
  process (clk_b)
  begin
    if rising_edge(clk_b) then mem(wb) <= db; end if;
  end process;
  ```
  NVC treats the two dynamic element writes as conflicting drivers.
- **Check:** `fw-check-vhdl` / `nvc -a` passes and the full cocotb matrix
  passes. The Python model should defer same-cycle writes and commit them after
  both ports tick, matching the DUT's write/read visibility rules.

## 11. Justify every stored bit

- **Rule:** before choosing a table size, remove every bit that can be
  derived: quarter-wave symmetry (sin/cos from one quadrant), magnitude
  only (sign from the phase MSBs), half-step offset (no special entries at
  0 and 90 degrees), and spend the freed bits on precision. Use the whole
  BRAM word: RAMB18E2 is 16Kx1, 8Kx2, 4Kx4, 2Kx9, 1Kx18, 512x36 (SDP), so a
  1024-entry table gets 18 bits (parity included) for free. Judge storage by
  precision per stored bit at the largest legal generics, not only by
  resource count at the default.
- **Anti-pattern:** the first nco_2_0 design kept a full 2-pi table and
  saved only FFs. (2026-10-27)

## 12. BRAM output register reset is synchronous

- UltraScale+ BRAM `RSTREG`/`RSTRAM` are SYNCHRONOUS. A BRAM read-data
  register has no reset in inferred code (`rom_skills.md#8`); if one is
  needed it must be synchronous to be absorbed.

## 13. Data applied outside the table travels with the table read

- **Rule:** a sign, quadrant flag, residue or other per-sample value
  computed from the SAME address must be delayed through exactly as many
  registers as the table read (address reg + read-data reg + output reg) so
  it meets the same sample (`rtl_correctness_skills.md#3`). Count both
  chains in the pipeline table. (nco_2_0, 2026-10-27)
