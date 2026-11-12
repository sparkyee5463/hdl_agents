# DSP / Fixed-Point — Review Skills

Read when the design multiplies, accumulates, rounds, scales, or uses
sin/cos/coefficient tables (NCO, mixers, filters, FFT, complex multiply).

---

## 1. Write the Q format of every port and product

- **Rule:** Header states Q format (e.g. Q1.15 signed) of each data port.
  For each multiply, product format is Q(m1+m2).(n1+n2) with a+b bits; for
  complex multiply the sum of two products needs one more bit. The output
  slice must be chosen from that format, and stated.
- **Check:** feed full-scale (0x7FFF ≈ 1.0) times full-scale on paper: the
  output must be ≈ full scale. 0.5 × 0.5 must give 0.25 in the OUTPUT
  format. If it gives 0.0625, two bits of headroom are being thrown away.

## 2. Rounding and bias

- **Rule:** Name the rounding of every bit drop: truncate (floor, -0.5 LSB
  mean error), round-half-up, round-half-away, convergent. Truncation in a
  loop or accumulator adds DC; say why it is acceptable or round.
- Model and RTL must use the same mode (`math_real.round` is half-away;
  Python `round()` is half-even).

## 3. Overflow: wrap vs saturate

- **Rule:** For each narrowing step say whether overflow can happen for
  legal inputs. If yes: saturate (documented, asymmetric limits noted) or
  document wrap. Gain-compensation and |I+jQ| > 1 cases are the usual
  surprises.

## 4. Tables (sin/cos/twiddle)

- 1.0 is not representable in signed Qx.(w-1): it clamps to 2^(w-1)-1.
  Document the error and its sign. Check quadrant/symmetry folding at the
  boundaries (0°, 90°, 180°, 270°, last table entry), and the sign
  convention (W = cos - j·sin vs cos + j·sin) against the doc.

## 5. Coefficient / config updates are atomic

- **Rule:** A coefficient set used together (cos and sin, real and imag,
  table value and interpolation fraction) must switch on the same cycle.
  Trace one change through every pipeline stage (`rtl_correctness_skills.md#3`).

## 6. Time base vs sample base

- **Rule:** Oscillators/NCOs advance per clock or per sample (enable).
  With a gappy enable or downstream stall, per-clock advance changes the
  frequency seen by the samples. The doc must say which, and the testbench
  must test a gappy enable.

## 7. Spec-level test

- Every DSP block gets one test against ideal float math (numpy) with an
  SNR or max-error bound derived from the word lengths, in addition to
  bit-exact lockstep against the twin (`testbench_skills.md#3`).
- The design stage writes `design_doc/verify_<ip>_math.py` that computes
  the claimed spec numbers per mode from the algorithm as specified; the
  doc quotes its output and the testbench reuses it. A numeric check in
  nco_2_0 design found a real bug (the Taylor cross-term needs the quadrant
  sign) that paper review had missed. (nco_2_0, 2026-10-27)

## 8. DSP48E2 facts (UltraScale/UltraScale+, UG579). Do not state these from memory

| item | value |
|---|---|
| multiplier | 27 x 18 signed (A or A+D pre-adder: 27 bit, B: 18 bit) |
| ports | A 30, B 18, C 48, D 27, P 48 bits |
| registers (in order) | AREG/BREG (0-2), DREG, ADREG, MREG, PREG (0/1 each) |
| MREG vs PREG | SUCCESSIVE stages: A/B reg -> multiply -> MREG -> ALU -> PREG. With MREG=0 the multiplier is combinational into PREG |
| resets | RSTA/RSTB/RSTC/RSTD/RSTM/RSTP are all SYNCHRONOUS |
| full-speed pipeline | AREG=BREG=1, MREG=1, PREG=1 (latency 3 from A/B port) |

- A coefficient wider than 18 bits does not fit B: swap it onto A (27 bit)
  or shift it (and state the precision lost). (nco_2_0: B was assumed 25
  bits, which forced `bcoef >> 7` late in RTL, 2026-10-28.)

## 9. Infer DSPs; do not instantiate primitives

- **Rule:** write multipliers in numeric_std (`r_p <= r_a * r_b + r_c;`)
  with registers shaped like the DSP stages (input reg, product reg, output
  reg), no reset or a SYNCHRONOUS reset on those registers (an async reset
  stops Vivado absorbing them into the DSP). Optional
  `attribute use_dsp : string; ... "yes"`.
- **Anti-pattern:** `entity unisim.DSP48E2` instances. In nco_2_0 this cost
  hours of nvc unisim setup (a 97k-line VCOMPONENTS package, a global
  `~/.nvc` install), an entity-only stub for Vivado project-less OOC, a twin
  that has to mirror vendor semantics, and blocked the Yosys/OpenROAD flow.
  Instantiate only with a written reason in the design doc (e.g. cascade or
  pattern detect inference cannot reach), behind a generic, with a plain
  VHDL fallback. (nco_2_0, 2026-10-28)

## 10. Pipeline every multiplier; latency follows timing, not the reverse

- **Rule:** a multiply between two registers runs through the DSP stages
  (#8). Do not put a combinational multiply/add between a BRAM output
  register and an output port to keep latency low, and do not rate that
  timing risk "low". A mode generic that adds a multiplier may add latency:
  derive `C_*_LATENCY` from the generic and size sidebands from it.
- **Example:** nco_2_0's first design put an unregistered DSP multiply-add
  after the BRAM register (latency kept at 2) at 300 MHz. (2026-10-27)

## 11. Phase-limited vs amplitude-limited SFDR (NCO / DDS)

- Phase truncation to P table-address bits limits SFDR to about 6.02*P dB
  (quarter-wave: P = address bits + 2). Amplitude bits beyond that buy
  nothing unless a phase-correction term (first-order Taylor) or dithering
  is added. Quantisation of A amplitude bits gives about 6.02*A + 1.76 dB SNR.
  The design must say which limit dominates in each mode and size the
  table to it.

## 12. Bit-invert negation with a half-step table

- With a half-LSB-offset table (`sin((i+0.5)*pi/2/N)`), the negative half
  can be produced by bit inversion (one's complement, `not x`) instead of
  `-x`: `not x = -x - 1`, which is two's-complement negation with a constant
  -0.5 LSB offset that is symmetric for the half-step table. No adder and
  no special decoder. Document that the output is one's complement and that
  the twin outputs the raw pattern. (nco_2_0, 2026-10-27)
