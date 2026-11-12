# Testbench Quality — Review Skills

A testbench is only useful if it can FAIL. Most weak testbenches pass with a
broken DUT because they check too little, check against a copy of the RTL,
or never reach the scenario named in the test.

`hdl_reviewer` (target=tb) does every item. `cocotb_tb_architect` writes
to it.

---

## 1. A test that checks nothing must fail

- **Rule:** The scoreboard tracks how many comparisons the checker made and
  how many expected items are still waiting. At the end of each test:
  `assert n_checked > 0` and `assert pending == 0` (or the documented
  in-flight count). Also fail on unexpected outputs (output valid when
  nothing was expected).
- **Anti-pattern:** a scoreboard that only raises on mismatch. If the DUT
  never asserts valid, zero compares happen and the test passes.
- The guard must live INSIDE every shared result object too, not only in
  per-suite scoreboards: a shared pass/fail result must require
  `compares > 0` in addition to no mismatches, so a test that passes an
  empty input list cannot report pass. (nco_2_0, 2026-10-28)

## 2. No silent skips

- **Rule:** A test that does not apply to a generic set must be reported as
  SKIPPED, not PASS. cocotb 2.x has no runtime skip exception: decide at
  import time with `@cocotb.test(skip=not applies(Generics.from_env()))`
  (generics come from `VCST_GENERIC_*` env vars, known at import), or do not
  add that generic set to the test in `run_vcst.py`. Never `return` early
  with a log message.
- Caveat: in the vcst/VUnit flow, cocotb 2.x's `RegressionMode.TESTCASE`
  (the `COCOTB_TESTCASE` env var, set per test by the runner) bypasses
  `skip=True` — an import-time-skipped test that the runner requests by
  exact name executes its body and reports PASS with zero checks. Either
  filter tests per configuration in the runner, or document the no-op
  early-return in the test AND in the simulation plan, and state that the
  full matrix is the canonical flow. (nco_2_0, 2026-10-28)
- **Check:** grep tests for `return` before the first check. Count how many
  tests are effectively empty per generic set.

## 3. The reference must be independent of the RTL

- **Rule:** The expected values come from the spec (design doc, math), not
  from re-coding the RTL's internal steps. In the `fw_py_tools.tb` flow they
  come from the reference model (`reference_model_skills.md`), written by
  `verification_architect` from the doc only. A model that copies RTL
  stages also copies RTL bugs, and the compare then proves nothing.
- Every IP needs at least one spec-level check that does not use the model:
  ideal math (numpy FFT, `cos(theta)`, exact integer sum), conservation
  (every beat in comes out once, in order), or a documented invariant.
- Do not trust a docstring that says "independent" or "from the spec":
  check it. If the model has per-stage state like the RTL, compare which
  stage each operand comes from against the SPEC; a model whose stages mix
  operands exactly like the RTL is a copy.
- Spec-level checks must also cover transitions (config/mode change,
  reset, frame start/end, flag edges), not only steady state after a
  "settle" wait — transitions are where copied bugs hide.
- **Claim -> check table:** for every "never"/"always"/"atomic"/"no
  glitch"/"no mixed" claim in the doc, name the check that would FAIL if
  the claim were broken, AT the transition (e.g. on every output after a
  config change, assert the output equals the old-config OR the new-config
  result, never a mix). "Model-exact compare" does NOT count as that check:
  if the model breaks the claim the same way, it still passes. No such
  check = error.
- A model "matching the doc's pipeline table" is not enough: the doc can
  contradict itself (a stage table vs a "never mixed" sentence). If the
  model has per-stage state, make the stage table (rtl_correctness #3) for
  the MODEL: an output built from operands of two different transactions
  breaks the "never mixed" claim, whatever the stage table says.
- **Anti-pattern:** a model that recomputes the RTL's internal registers one
  by one (same names, same stage mixing), so any RTL mistake is copied; a
  model delay line whose depth was tuned until tests passed. Any "calibrated", "fudge" or "+1 to match" comment in
  a model is a finding.

## 4. Exact compare; no tolerance or latency slack unless the spec has it

- **Rule:** Bit-accurate designs are compared exactly, every cycle, every
  output. Tolerances (`±1 LSB`), latency windows (`±2 cycles`), or masking
  outputs when valid=0 need a design-doc reason, cited in a comment.

## 5. Drivers: one compliant user, one abusive user

- **Rule:** At least one test drives the DUT the way a correct integrator
  would: it obeys the DUT's own outputs (ready, full, empty, wait, busy)
  CYCLE BY CYCLE and asserts no error flag ever fires and no data is lost.
  Separate tests ignore the flags on purpose and check error/overflow flags.
- **Anti-pattern:** "compliant" tests that gate on the MODEL's count or on
  random choice instead of the DUT's flag. Then a late or wrong DUT flag is
  never seen.

## 6. Coverage matrix: generics × modes × ports

- **Rule:** Write the matrix and check each cell has a test in some
  generic set:
  - each integer generic: smallest legal, default, largest, plus
    non-power-of-two and odd where legal; 1 and 2 where legal;
  - each boolean/enum generic: every value;
  - each runtime mode input (inverse, order, schedule, mode select,
    config words): every value, and a change while data is flowing;
  - each output port, including status/error flags, is checked by value.
- A test named after a scenario must PROVE it reached it (e.g. count cycles
  where full=1 and write=1 and read=1, and assert the count > 0).
- **Anti-pattern:** 18 generic sets but only 4 tests, none of which flip the
  runtime mode ports; a "collision at full" test where the collision never
  happens.

## 7. Every documented number has a measuring test

- **Rule:** Latency: send one isolated item, measure cycles to output, assert
  equal to the doc value for each generic set. Throughput: drive valid=1 and
  ready=1 continuously for >= 100 items, assert items/cycles equals the doc
  rate for EVERY generic set (rate often drops only at large generics).
  Ordering, frame length, gain: measure and assert.

## 8. Stimulus that finds bugs

- Random valid AND random ready/wait at the same time, plus long bursts and
  long idles. Back-to-back with no gaps.
- Reset asserted mid-stream (idle, mid-burst, while output is stalled) and
  traffic after it.
- Config/mode change mid-stream without waiting for a "settle" time; check
  outputs on the change cycle.
- Data corners: 0, -1, max positive, most negative, alternating bits,
  single-bit walks; for DSP, full-scale tones and impulses.
- Seeds printed in the log; enough items to fill and empty every buffer
  several times.

## 9. Check every cycle, check idle

- **Rule:** Compare outputs every cycle (or every handshake), not just at a
  few sample points at the end. Check that valid stays low when nothing was
  sent and after the last item drains.

- X/Z on outputs: vcst runs cocotb with `COCOTB_RESOLVE_X=ZEROS`, so
  `int(sig.value)` silently turns X into 0. Checks that must catch X (RAM
  init, reset, undriven bits) test `sig.value.is_resolvable` first.

## 10. Build files list the matrix

- `run_vcst.py` has one named generic set per matrix row from
  item 6, and the generic set name says what it covers
  (`d5_nonpow2`, `regstat_true`). A generic that is in the RTL but never
  set in any configuration is a coverage gap.

## 11. Once-per-clock latency test, per mode

- **Rule:** for every latency mode, drive one input change and check that
  each output changes exactly ONCE per clock period, exactly `LATENCY`
  cycles later. Sample on the rising edge AND check that nothing changes on
  the falling edge. Steady-state value checks cannot see double-edge
  registers (`rtl_correctness_skills.md#12`): nco_2_0's coder smoke tests
  passed with every register clocking on both edges. (2026-10-28)

## 12. Decode outputs exactly once

- **Rule:** the testbench documents whether each compared output is RAW
  (port bit pattern) or DECODED. Compare raw to raw where the reference
  gives raw values, and decode once (one helper) for spec-level math. nco_2_0 lost hours to tests decoding
  one's-complement outputs twice. (2026-10-28)

## 13. Mode-branch references must not compare a run to itself

- **Rule:** when a test gains a per-mode branch (e.g. on
  `Generics.from_env().G_REG_PHASE_INC`), verify the branch's reference is
  NOT derived from the same run being compared — comparing
  `_model().run(seq)` against itself is tautological and can never fail, so
  the sub-check the test is named for is silently not exercised in the new
  mode. A documented degeneration must state exactly which sub-check is
  vacuous, and a mode-unaware helper (a `tone()` that drives EN with the
  data pin at 0 in combinational mode) is a trap for the next test: make the
  helper mode-aware or build the reference inline from the mode-specific
  stimulus. (nco_2_0, 2026-10-29)

## 14. Quantify "long idles" in the stimulus mix

- **Rule:** the "long bursts and long idles" requirement needs a floor: at
  least one scenario (or a documented margin) idles for >= 4x the pipeline
  depth with data queued or recently drained, so free-running pipeline leaks
  (spurious M_TVALID after drain) have a window to surface in an HDL run.
  A uniform post-drain margin on every test (e.g.
  50 cycles) can satisfy the margin clause if stated in the plan.
- **Anti-pattern:** a stimulus mix whose maximum gap is a few cycles with no
  stated drain margin, where the only long-idle coverage is an incidental
  side effect of the test harness. axi4s_buffer_1_0 tb review, 2026-10-30.

## 15. Testbench structure (user rules, axi4s_buffer_1_0 pilot, 2026-11-05/06)

- **Rule:** per-IP plain classes in their own files (`<ip>_driver.py`,
  `_monitor.py`, `_models.py`, `_checker.py`, `_scoreboard.py`,
  `_coverage.py`, `_config.py`, `_stimulus_generator.py`, `_tb_manager.py`)
  wired with `cocotb.queue.Queue`. Only bus protocol classes are shared.
- **Port ownership:** the driver owns the DUT input side (slave bus ports,
  input pin groups, reset); the monitor owns the output side, including the
  TREADY of each DUT master port it monitors. A driver driving TREADY, or a
  monitor watching an input port, is wrong (user: "that is under the
  monitor's perview").
- **Loops:** one explicit `async def` loop per interface group (`await
  RisingEdge`, read the group's named pins, `await queue.put`), all started
  by the tb manager's `start()`.
- **Readable:** full descriptive names; no `_h`, no pin-dump dataclass, no
  name->path dicts; KISS, no base classes, no checker rules.
- **Anti-pattern:** a monitor with a shared "read every pin" sampler;
  driver and monitor each holding both sides of the DUT; parts that call
  `cocotb.start_soon` on themselves.

## 16. Generic sets: the doc range, nothing that explodes

- **Rule:** for each integer generic: the doc minimum and minimum + 1, an
  odd value, the default, a power of two and that power of two + 1, and the
  doc maximum (no maximum in the doc: one value >= 64, so 32/64-bit
  assumptions break). Keep every set the simulation plan lists.
- A set may not cost far more than the others: exhaustive stimulus or a
  table of 2^N entries only for N <= 16. (nco_1_0 Nemotron run, 2026-11-07:
  an added `G_ADDR_BITS = 32` set built a 2^32-entry table and ran out of
  memory, and 3 of the 4 original sets were dropped.)

## 17. Exhaustive where small, structured where wide

- **Rule:** when a set's input space is <= 2^16 values, one test sends EVERY
  input value (ascending, then a shuffled order from `tbm.rng`).
- Wider sets: corners (0, all ones, MSB only, LSB only, 0101..., 1010...,
  all ones except the MSB, max/2, max/2 + 1), a walking one and a walking
  zero across EVERY bit, ascending runs across every carry boundary
  (`...0111 -> ...1000` for each bit, and `max -> 0`), and >= 1000 random
  values from `tbm.rng`.
- Every test runs in every generic set. A test that needs a minimum width
  is skipped per #2 for the narrow sets, never silently shortened.

## 18. Toggle coverage of every port bit

- **Rule:** every bit of every IP port goes 0 -> 1 and 1 -> 0 in some test
  (the walking-one and walking-zero sweeps of #17 do this). The toggle
  numbers of the code-coverage report must be 100 % on the IP's ports; each
  hole is listed with the test that should reach it. (nco_1_0 57.9 % and
  nco_2_0 82.8 % toggle passed the gate unnoticed, 2026-11.)

## 19. Doc invariants are checks of their own

- **Rule:** every property the doc states gets an assertion computed from the
  DUT outputs with plain math, NOT from the reference model, e.g. for a code
  converter: consecutive inputs give outputs that differ in exactly one bit
  (also `max -> 0`), the map is one-to-one (an exhaustive set yields 2^N
  distinct outputs), decode(encode(x)) == x with the inverse written from
  the doc formula, the MSB passes through. This is the spec-level check of
  #3 for logic IPs: a reference and a DUT built from the same wrong reading
  of the doc both pass the model compare, not the invariant.

## 20. Files and imports

- **Rule:** write only the files the task lists, at the listed paths;
  `git status --short` shows nothing at the IP root or in another IP.
  (nco_1_0 Nemotron run: interface and coverage copied to the IP root.)
- Modules of the shared tb dir import each other by plain name
  (`from grey_encoder_1_0_interface import ...`), never relative
  (`from .grey_encoder_1_0_interface import ...`), and never a module that
  does not exist. Run `python -c "import <module>"` for every file you wrote.
  (nco_1_0 Nemotron run: 6 of 9 new modules did not import.)

## 21. Tests use the per-IP files only

- **Rule:** tests build `<Ip>_TbManager` and use the per-IP parts. They
  never import helpers from other IPs' testbenches. (nco_1_0 Nemotron run:
  tests left on another testbench's helpers.)

## 22. Compare from the first defined sample, then every sample

- **Rule:** before the first driven input (and, for clocked IPs, until the
  startup reset has reached the DUT) the RTL's outputs are undefined.
  Compares and timing checks start at the first sample produced by a driven
  input (clocked: after the startup reset). Every later sample is checked;
  never skip one to pass. (nco_2_0, 2026-11-11: every table-only test
  failed at cycle 2 because the per-cycle compare began before the reset
  reached the RTL.)
