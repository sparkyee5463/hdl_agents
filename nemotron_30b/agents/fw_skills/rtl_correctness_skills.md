# RTL Correctness — Review Skills

Style rules say how RTL looks. This file says how to prove it WORKS. Most
real bugs are here, and most of them pass the existing tests because the
tests were written by the same person (or model) who wrote the RTL.

`hdl_reviewer` (target=rtl) does EVERY item and writes the evidence the item
asks for into its worksheet. "Looks fine" is not evidence; a trace is.

---

## 1. Every claim in the header and design doc is checked against the code

- **Rule:** List each concrete claim the header comments and design doc make:
  latency, throughput ("1 beat/cycle"), ordering, "never"/"always"
  statements, flag meanings, what happens on overflow/collision/reset/config
  change. For each claim, find the lines that make it true. A claim you
  cannot tie to lines is a finding.
- **Anti-pattern:** a comment such as "write at full commits during a
  simultaneous read" or "never a mixed pair" that the code does not do.
  Wrong comments are bugs: integrators trust them.

## 2. Latency = registers on the path, counted by hand

- **Rule:** For each output, walk backwards from the port to the input port
  and list every register (`r_*`, pipeline arrays, output registers, input
  registers, RAM read registers). Latency is that count, for EACH generic
  value that adds/removes stages. Compare with `C_*_LATENCY`, header, doc
  and testbench model.
- **Anti-pattern:** a latency constant that counts the pipeline stages but
  not the input or output register; a testbench delay line "calibrated"
  until tests pass. Any mismatch is an error.

## 3. Pipeline coherence: one stage, one transaction

- **Rule:** Make a stage table: for every register, which stage it belongs to
  and which stage each operand on its right-hand side comes from. An
  expression in stage k may only read stage k-1 values of the SAME
  transaction (plus true constants). If it mixes stage k-1 and stage k-2
  values, or a live input port with a registered value, then two different
  transactions meet in one result.
- Values that "rarely change" (config words, coefficients, mode bits) are
  NOT constants. If they can change while data flows, they need the same
  stage alignment as data, or an explicit documented hold-off.
- **Anti-pattern:** `r_y_s2 <= r_a_s1 * r_b_s0` — `r_b_s0` already belongs
  to the NEXT transaction. Output is wrong for one cycle whenever b changes;
  tests that hold b constant, or wait for "settle", never see it.

## 4. Registered feedback flags must be computed from the NEXT state

- **Rule:** A flag that the other side uses to decide whether to act (full,
  empty, almost_*, ready, credit, busy) and that is registered, must be
  computed from what the state WILL be after this edge
  (`count_next = count + wr - rd`), not copied from the current-state flag.
  Copying a combinational flag into a register makes it one cycle late, and
  a user that obeys the flag will over/under-run.
- **Check:** take state = limit-1, do one accepted operation; on the next
  cycle the registered flag must already show the limit. If not, write the
  cycle-by-cycle example of a user that obeys the flag and count how many
  operations it gets in: more than the limit = overflow.
- "The write is rejected and O_OVERFLOW pulses" is still DATA LOSS when the
  interface has no per-item accept/ready back to the sender (wr_en + full,
  en + wait): the sender obeyed the flag, moved on, and the word is gone.
- A doc sentence like "registered flags lag by one cycle" does NOT make a
  late flag OK. It is only OK if the doc also tells the user exactly how to
  stay safe (e.g. "use O_ALMOST_FULL with offset >= 1") AND the flag that
  is called FULL/EMPTY/READY is not itself unsafe. Otherwise: error.
- Same rule for any "stop" signal crossing a pipeline: if the sender needs
  N cycles to react, the stop must fire N entries early (skid space).

## 5. Throughput: outstanding work must cover the loop latency

- **Rule:** If the design issues requests and receives results L cycles later
  (RAM read pipeline, prefetch, request/grant), then to sustain 1/cycle it
  must allow at least L+1 outstanding items (buffer slots, credits). Count
  the slots and the worst-case L over all generics. Fewer slots means the
  rate is slots/(L+1); compare that with the documented rate.
- Also look for forced idle cycles between transactions (arbiters,
  FSM return-to-idle states) and compare with the doc.
- **Anti-pattern:** a fixed-size buffer behind a pipeline whose depth is a
  generic: data stays correct, but the rate falls as the generic grows and
  no test measures it.

## 6. Generic corner walk: every index, every legal generic set

- **Rule:** For every `for` loop, `generate`, reduction tree, index
  expression and slice, write down its values for the corner generic sets:
  smallest legal (often 1), 2, 3, a non-power-of-two, an odd value, the
  default, and the largest. For trees/reductions with N inputs and K inputs
  per node, check that EVERY input index is consumed exactly once at every
  level and that the number of levels equals the function that sizes it.
- Pairwise logic (`2*i`, `2*i+1`) with group size other than 2, or
  `N/2` with odd N, or `N-1 downto 0` with N=0 are the usual drops.
- A generic combination that the code cannot handle must be rejected by an
  elaboration assert (`vhdl_style_skills.md#3`), not silently produce wrong
  results.
- **Anti-pattern:** only the default generic set (often power-of-two) is
  traced and tested.

## 7. One driver per signal; initial values via declaration

- **Rule:** Every signal has exactly one driving process or concurrent
  statement (std_logic resolution will silently give 'X' on conflict; NVC
  and synthesis may or may not error). Check arrays too: an "init" process
  plus a write process on the same array = two drivers.
- Memory initial contents (file or function) go in the declaration:
  `signal mem : t_ram := f_init(G_INIT_FILE);`.
- Within `if G_X generate ... else generate`, each branch may drive the
  signal; outside them it must not.

## 8. Arithmetic: widths, sign, rounding, headroom

- **Rule:** For every `+ - *` and shift: result width (sum grows 1 bit,
  N-input sum grows ceil(log2 N), product of a and b bits is a+b), sign
  extension (`resize` on signed), and which bits are kept. Write the
  fixed-point format (Qm.n) of inputs and output and check the kept slice
  matches it; full-scale input must give full-scale output, not 1/2 or 1/4.
- Rounding: truncation (`floor`) has -0.5 LSB bias; say so or round. Check
  round/saturate helpers for shift > width, shift = 0, most-negative input.
- Overflow: saturate or wrap — documented and asserted reachable/unreachable.
- See `dsp_fixed_point_skills.md` for multipliers, filters and tables.

## 9. Valid / ready / enable protocols: no loss, no duplication

- **Rule:** For each handshake input/output write a 4-row table
  (valid, ready) = 00, 01, 10, 11 and state what happens to every register.
  Check: data accepted exactly when valid AND ready; output held stable
  while valid AND NOT ready; nothing accepted during reset; a beat in flight
  at reset is either delivered or documented as dropped.
- Check enable-gated pipelines: does the pipeline advance on every clock or
  only on enable? Free-running stages do not hold data
  (`axi4s_skills.md#7`).
- Synchronous reset: on the FIRST cycle reset is low, outputs still show
  pre-reset state. A doc claim "output X during reset" is only true from the
  second reset cycle, unless outputs are gated by the reset input.
  Same for storage: a RAM write gated only by `wr_en and not full` can
  still write on that first reset cycle. Show it is blocked, or trace why
  it is harmless.
- Request/grant: what if a requester withdraws without "done"? Lockup?
- Free-running time bases (counters, NCO phase) used with gappy enables:
  is phase per clock or per sample? It must match the doc.

## 10. Every generic mode is the same function

- **Rule:** When a boolean/enum generic selects an implementation
  (registered vs combinational, BRAM vs LUT, pipelined vs not), every mode
  must produce the same outputs apart from documented latency. Trace each
  mode separately. Modes only reachable with non-default generics are the
  most likely to be broken.

## 11. Dead and half-done logic

- **Rule:** Find signals that are registered/pipelined but never read,
  ports that are accepted but ignored, generics that change nothing, and
  `-- TODO`/"not implemented" branches. Each needs a header note or removal.
  Unimplemented generic values must be rejected by an assert.

## 12. VHDL semantics traps

- numeric_std widths: `a * b` is `a'length + b'length` bits (full product,
  no resize needed); `a + b` is `max(a'length, b'length)` bits — the carry
  is LOST unless an operand is resized first. Check every `+` for growth.
- `resize(signed, smaller)` keeps the sign bit and drops MSBs below it;
  `resize(unsigned, smaller)` drops MSBs. Neither saturates.
- `integer` is only guaranteed 32-bit: `2**G_W` with G_W >= 31 overflows;
  `to_integer` of a >31-bit vector fails. Build big constants as vectors.
- `abs` / negation of the most negative value overflows.
- Comparisons between signed and unsigned of different widths: convert
  explicitly first.
- `case` on a vector needs `when others`; a combinational process must
  assign every output on every path (else latch).
- Reading a signal right after assigning it in the same process returns the
  OLD value; use a variable if the new value is needed.
- Assignment and `&` go by POSITION, left to right, not by index number:
  the leftmost element goes to the target's LEFT index. For
  `sig(0 to 2) <= a & sig(0 to 1)`, `a` lands in `sig(0)`; for
  `sig(2 downto 0) <= a & sig(2 downto 1)`, `a` lands in `sig(2)`. Check the
  declared direction before calling a shift reversed.
- A register used as an array/ROM index (`mem(to_integer(r_addr))`) with
  no reset and no declared initial value is 'U' at the first edge:
  `to_integer` warns and returns 0 in sim, index out of range in some
  tools. Give it a declared init (`:= (others => '0')`).
- `'X'`/`'U'` on outputs at power-up: say which outputs are undefined until
  the first valid.
- A `process(I_CLK)` with a sensitivity list and NO `wait` and NO
  `rising_edge` guard executes on EVERY change of I_CLK — rising AND falling
  edge: double-edge registers at 2x rate, silently mixed with rising-edge-only
  logic (unisim DSP AREG/BREG/PREG update on the rising edge only), so
  transactions from different edges meet in one result. Check EVERY clocked
  process for an explicit `if rising_edge(I_CLK) then ... end if` (or a
  trailing `wait until rising_edge(I_CLK);`); a clocked process body with
  neither is an error. (nco_2_0, 2026-10-28)
- Inactive generate branches are NOT elaborated by nvc: a generic-dependent
  STATIC slice bound that is out of range only in the inactive branch (e.g.
  `acc(PW-3 downto PW-17)` inside an `if R >= 15 generate` when PW < 17)
  passes nvc elaboration and simulation but is an elaboration/portability
  hazard on other tools. Every static slice bound must be legal for ALL legal
  generic sets, active branch or not: take the always-legal slice and derive
  the value with `resize` + `sll`/`sra` by the static shift amount.
  (nco_2_0, 2026-10-28)
