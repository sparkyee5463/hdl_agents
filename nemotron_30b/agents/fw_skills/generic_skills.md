# Generics / working widths — HDL Review Skills

Common things to check when reviewing HDL whose package functions or datapath
widths are derived from generics. **Add a new numbered entry here every time a
new issue is found in review, so the same mistake is not made again.** Each
entry should state the rule, the anti-pattern, and (when relevant) the
concrete example that motivated it.

The `hdl_reviewer` subagent applies this checklist to the VHDL that
`rtl_coder` writes. Keep entries short, concrete, and checkable.

First used: `phase_shifter_1_0` review (2026-10-10).

---

## 1. Every generic feeding a working-width expression must be covered by an elaboration assert

- **Rule:** When a generic sizes a package function's internal working width
  (e.g. a sign-extended product/quotient width `W` in a degrees-to-phase-word
  converter), the top-level elaboration assert block MUST constrain that
  generic so the working width never overflows for any legal generic set.
  Derive the requirement from the algorithm (largest intermediate operand
  width) and assert it with `severity failure`.
- **Anti-pattern:** an unconstrained generic that silently truncates
  intermediate results (`to_signed(x, W)` with W too small is
  implementation-defined truncation — no error, wrong value). Comments
  claiming a width "fits for every legal generic set" must match the actual
  assert set.
- **Check:** for each function that computes a width from generics, list the
  widest intermediate operand, and verify an assert (or a documented
  derivation + assert) covers it.
- **Example (found in `phase_shifter_1_0` review, 2026-10-10):**
  `f_deg_to_phase` working width `W = G_NCO_PHASE_WIDTH + G_PHASE_INT_BITS +
  G_PHASE_FRAC_BITS` sized off `G_NCO_PHASE_WIDTH`, but no assert covered
  `G_NCO_PHASE_WIDTH`. For `G_NCO_PHASE_WIDTH=2, G_PHASE_INT_BITS=1,
  G_PHASE_FRAC_BITS=12` (all other asserts passing) `to_signed(360*2**F, W)`
   overflows and the phase word is silently wrong. Fix: assert
   `G_NCO_PHASE_WIDTH + G_PHASE_INT_BITS >= 8` (denominator 360*2^F needs
   F+9 bits of W; |v_num+v_adj| needs INT+P >= 8).

---

## 2. A boolean *mode* generic that adds datapath fabric needs conditional asserts on the OTHER generics, mirrored in the twin

- **Rule:** When a boolean generic selects between datapaths and the `true`
  branch adds fabric (e.g. DSP48E2 multipliers) whose operand widths depend on
  OTHER generics, the top-level elaboration assert block MUST carry the
  conditional constraints that only apply when the mode is on (assert them as
  `mode = true => <width/legality condition>`, `severity failure`). The
  digital-twin `validate()` MUST mirror the same conditional constraints so an
  illegal generic set is rejected at simulation setup, not mid-run.
- **Anti-pattern:** a mode generic that is asserted only for its own type
  (boolean, so nothing to check) while the fabric it enables is left
  unconstrained — the design elaborates and the twin runs, then the DSP
  operand silently overflows / the residue is too short for the correction to
  be defined. The constraint is "ad hoc" (in a comment only) instead of an
  assert + twin rule.
- **Check:** for each boolean mode generic, list the fabric its `true` branch
  adds and every other generic that sizes that fabric; verify each has a
  conditional elaboration assert AND a matching twin `validate()` rule.
- **Example (found in `nco_2_0` design stage, 2026-10-27):**
  `G_TAYLOR_CORRECTION : boolean := true` adds 2 DSP48E2 whose A input is the
  table magnitude (`G_SINE_BITS-1` bits, must fit the 25-bit DSP A port) and
  whose correction is only defined for a residue of
  R = `G_PHASE_WIDTH - G_ADDR_BITS - 2` >= 2 bits. The constraints
  `G_TAYLOR_CORRECTION = true => G_PHASE_WIDTH >= G_ADDR_BITS + 4` and
  `= true => G_SINE_BITS <= 26` were specified ad hoc; they are now elaboration
  asserts (design doc §2.4 rows 5–6) and twin `validate()` rules.

---

## 3. Every value of every mode generic is simulated

- **Rule:** each value of each boolean/enum generic (and each optional
  register-stage generic, e.g. `G_REG_PHASE_INC`) has at least one named
  generic set in `run_vcst.py`, with lockstep + latency tests passing. The
  simulation plan may not defer one without the user's written OK, recorded
  in `STATE.md`.
- **Anti-pattern:** nco_2_0's plan deferred `G_REG_PHASE_INC=false` to a
  "follow-up"; the twin reviewer flagged it and the lead accepted the
  deferral, shipping an approved mode with zero simulation. (2026-10-28)
