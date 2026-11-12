# Reference model, coverage — Skills

Read for target=ref (writing or reviewing an IP's reference model and
coverage). The testbench has NO checker-rule classes: the checker compares
the DUT with the reference model, runs the doc timing checks, and records
each result in the scoreboard. Worked
example: `fw_ip/axi4s_buffer/axi4s_buffer_1_0/` (`model/axi4s_buffer_1_0_reference/`,
`testbench/cocotb_testbench_axi4s_buffer_1_0_shared/`).

Two checks per IP, both from the design doc:

| check | how | proves |
|---|---|---|
| HDL vs reference | checker compares DUT transactions with the reference model's (spec order, spec tolerance) | RTL computes the right values |
| HDL vs doc timing | checker `check_<property>()` every cycle for protocol/flag sentences, plus latency and throughput measuring tests, from `<ip>_interface.py` `doc_timing()` | RTL meets the doc's timing |

---

## 1. Independence: the spec only

- **Rule:** the reference model and coverage are written from the
  design doc (interface, behaviour, numeric spec, reset policy) only. Do not
  read the IP's `hdl/`, its testbench (except your own files), or synthesis
  results. Pipeline tables and register names are not
  spec: do not model them.
- **Anti-pattern:** an axi4s_buffer_1_0 "reference" model that "mirrors
  the RTL read-issue condition" (committed-beat gate, capture FIFO
  indices). A model that copies the implementation passes with the same
  bug as the RTL.
- **Check:** grep the reference for RTL signal names (`r_*`, `s_*`, `C_*`).
  Each hit is an error unless it is a port name.

## 2. WHAT, not WHEN

- **Rule:** predict the output transactions (values, order, count), not
  cycles. No pipeline delays, no cycle counters in the reference. Timing
  claims of the spec (latency, throughput, flag timing) are numbers in
  `<ip>_interface.py` `doc_timing(generics)`, checked by the testbench's
  timing checks and measuring tests (#5).
- The spec's own arithmetic IS modelled (rounding mode, saturation, word
  lengths, accumulator wrap) when the doc defines it; then compare exactly.

## 3. Pick the transaction and the matching policy from the spec

- One transaction type per interface (`AxisBeat`, a packet, a config write,
  an output sample). The test's stimulus feeds the reference (`tbm.send`);
  output monitors produce the observed ones; the checker compares them.
- Output order per port (stated in the reference docstring; the checker
  pairs transactions that way):
  - `"in_order"` when the spec guarantees order (FIFO, NCO samples);
  - `("per_stream", key)` when order is guaranteed only within a stream
    (TID, (src, dst) in a crossbar);
  - `("keyed", key)` when the spec gives no order (match by a payload key).
- Never use a looser policy than the spec allows, and say which doc section
  gives the order.

## 4. Tolerance only from the spec, with its derivation

- Exact compare by default. A tolerance (approximation IPs: NCO, CORDIC,
  filters) is derived from word lengths in the doc (e.g. phase truncation
  `A*2*pi/2^ADDR_BITS + 1 LSB`), stated in the reference docstring with the
  doc section, and applied in the checker's compare. Never widen a tolerance to make a test pass.
- Reuse `design_doc/verify_<ip>_math.py` numbers when it exists.

## 5. No checker-rule classes

- **Rule:** the testbench has no rule files or rule classes. Every check is
  a plain method of the checker: DUT transactions vs the reference model
  (`compare_<group>()`), and one `check_<property>()` per doc protocol/flag
  sentence (TVALID hold, payload stable while stalled, a flag's cycle),
  citing the doc section. Latency and throughput are measuring tests. The
  doc's numbers go in `<ip>_interface.py` `doc_timing(generics)`; no
  bounded don't-cares or carve-outs.
- **Anti-pattern:** axi4s_buffer_1_0 (2026-10-30..11-05): eight rule
  classes with bounded don't-cares and spec-gap carve-outs; the user found
  them noisy and asked for queues -> checker -> scoreboard only.

## 6. Reset semantics

- State in the reference what the spec says reset discards; the testbench
  manager drops those expected transactions at the first reset edge. Data
  accepted before reset and delivered after it is a bug the checker must
  catch.

## 7. Coverage from the spec, not from the tests

- Bins for every spec feature: each generic mode value, each flag
  transition, full/empty/almost thresholds, max backpressure, back-to-back,
  gaps, TLAST/sideband values, reset in idle/active/full. Each bin cites the
  doc line. Coverage holes fail the test (`Coverage.final`).

## 8. Sub-IPs

- Default: compose child REFERENCE models (`load_reference("<child_ip>")`).
  Error budgets add.
- Never this IP's own HDL. A mismatch that traces into a child is a
  finding against the child IP.

## 9. Disagreement triage (the doc decides)

| failing check | likely | next |
|---|---|---|
| HDL vs reference | RTL bug, or reference wrong | work the failing input by hand from the doc |
| HDL vs doc timing | RTL timing bug, or a wrong `doc_timing()` number | cite the doc sentence/number |
| both, everywhere | testbench wiring (driver timing, queue pairing) | check the testbench before blaming the RTL |
| doc gives no answer | spec ambiguous | fix the doc first (spec gap -> user) |

- Change the reference only with a cited doc section. "Fixed the model to
  agree" without a citation is an error. Example (2026-10-29): a quick NCO
  reference was one increment late; nco_1_0's doc convention (sample k at
  `start + (k+1)*inc`) showed the reference was wrong, not the RTL.

## 10. Self-test the reference

- `tests/test_reference.py` (pure pytest): 3-10 hand-worked examples taken
  from the doc (inputs -> expected outputs, including a reset and a corner),
  so a wrong reference fails before it meets the RTL.

## 11. Latency belongs to the timing checks, not the reference

- **Rule:** when a sim plan asks for a "bit- and latency-accurate model",
  the latency part is the doc's numbers in `doc_timing()`, checked by the
  timing checks and latency tests. The reference stays transaction level.
- **Anti-pattern:** a cycle-by-cycle prediction of the outputs on the
  reference side (a "spec cycle model"). Under backpressure the exact cycles
  depend on the implementation, so it fails on correct RTL or gets tuned to
  DUT traces. axi4s_buffer_1_0 pilot (2026-10-30): failed 126/126 runs while
  every transaction compare was clean.

## 12. Degenerate coverage bins for narrow fields

- Rule: derive pattern bins (all_zero/all_ones/alternating/other) from the
  field width; for a 1-bit field use the degenerate form (all_zero={0},
  all_ones={1}) and drop alternating/other.
- Anti-pattern: one generic 4-bin predicate for all widths — for 1-bit fields
  'other' (and 'alternating') is unreachable, silently creating a permanent
  unfillable strict-coverage hole (e.g. a 1-bit TUSER that can never close).
- axi4s_buffer_1_0, 2026-10-30.

## 13. Record the release-cycle output assumption

- Rule: the reset-grace convention covers reset ASSERTION only. The model's
  output assumption on the release cycle (rst_n deasserting) — e.g. registered
  vs combinational S_TREADY — must be recorded as an explicit spec gap with
  its doc rationale; the timing checks use that reading and the user
  decides the gap.
- Anti-pattern: an unrecorded release-cycle assumption that contradicts the
  sim plan's formula evaluated literally — every reset-release test
  (te_002, er_002, reset-during campaigns) false-fails against an RTL that
  implements the formula combinationally.
- axi4s_buffer_1_0, 2026-10-30.

## 14. Feedback to the reference owner: doc sections, never DUT traces

- **Rule:** when a reference/checker problem goes back to
  `verification_architect`, send the failing compare, the test, and the doc
  sections in question. Do NOT send DUT waveforms/traces, and never
  ask it to "match the DUT". It fixes the reference from the doc or reports
  the doc as ambiguous (spec gap -> user).
- **Anti-pattern:** axi4s_buffer_1_0 pilot (2026-10-30): the lead pasted
  cycle-level DUT evidence; the architect then reported "0 cycles of
  divergence against the DUT", i.e. the reference had been fitted to the RTL.

## 15. Classify reset scenarios by the pre-reset observable state

- **Rule:** coverage bins that record "what was happening when reset
  asserted" must be classified by the pre-reset OBSERVABLE state (e.g.
  occupancy > 0, S activity) — not by the previous-cycle value of a
  reset-gated output. A gated output (M_TVALID under a reset gate) is 0 in
  the pre-reset cycle of many legitimate reset-during-activity cases, so a
  bin keyed on it is never hit and the DUT never exercises that reset
  context.
- **Anti-pattern:** a `reset_during.m_valid` bin keyed on the previous
  cycle's gated M_TVALID — the DUT backpressure-reset test holds the capture
  non-empty (the state that matters for the reset-gate bug class) while the
  bin stays uncovered in every HDL run. axi4s_buffer_1_0 tb review,
  2026-10-30 (B-003).

## 16. Coverage bins for value-mapping IPs (code converters, encoders)

- Per input: zero, all ones, MSB only, LSB only, 0101..., 1010..., every bit
  position set (walking one) and every bit position clear (walking zero).
- Per output: every bit seen 0 and seen 1.
- Per step between consecutive inputs: +1, a carry across a low, a middle and
  the top bit, the wrap max -> 0, and a jump that is not +1.
- Bins that depend on the width are built in `__init__` from `generics`.
  Every bin must be reachable in EVERY generic set: for G_WIDTH = 1 "MSB
  only" and "LSB only" are the same value and "middle bit" does not exist,
  so merge or leave out those bins for that width (#12) and say so in the
  bin's comment. A bin no test can hit fails the gate.
