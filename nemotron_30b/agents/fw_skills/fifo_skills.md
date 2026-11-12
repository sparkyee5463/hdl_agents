# FIFO — HDL Review Skills

Common things to check when reviewing HDL that implements or interfaces with a
register-based FIFO. **Add a new numbered entry here every time a new FIFO
issue is found in review, so the same mistake is not made again.** Each entry
should state the rule, the anti-pattern, and (when relevant) the concrete
example that motivated it.

The `hdl_reviewer` subagent applies this checklist to the VHDL that
`rtl_coder` writes. Keep entries short, concrete, and checkable.

First used: `phase_shifter_1_0` review (2026-10-10).

---

## 1. Storage sized to next power of two for non-power-of-2 depths

- **Rule:** When a FIFO's write/read pointers free-run modulo
  `2**clog2(G_DEPTH)` and storage is indexed by the pointer's low
  `clog2(G_DEPTH)` bits, the storage array MUST be declared
  `0 to 2**clog2(G_DEPTH) - 1` (next power of two >= G_DEPTH), not
  `0 to G_DEPTH - 1`. Logical depth is then bounded by a full/occupancy
  gate, and the extra slots simply serve as ring addresses.
- **Anti-pattern:** declaring storage `0 to G_DEPTH - 1` while addressing it
  with low pointer bits. For any non-power-of-2 depth (3, 5, 6, 7, 9, 10,
  11, 12, ...) the low bits take values in `[G_DEPTH, 2**clog2(G_DEPTH)-1]`
  and writes go out of range — a fatal simulation abort (and an X-propagation
  / undefined-behavior risk in synthesis).
- **Check:** grep the storage declaration and the pointer-to-address
  mapping; if depth is not constrained to a power of two, storage range must
  be `2**clog2(G_DEPTH) - 1`.
- **Example (found in `phase_shifter_1_0` review, 2026-10-10):** local FIFO
  with default `G_FIFO_DEPTH = 6`; 6 writes (fill), 1 read, 1 write =>
  `** Fatal: index 6 outside of NATURAL range 0 to 5`. The top-level
  occupancy gate did NOT prevent it: it bounds *logical* occupancy, but the
  free-running pointer still visits address 6.

## 2. Full flag: MSB-differs test is power-of-2-only

- **Rule:** The classic full flag (write pointer MSB differs from read
  pointer MSB, low bits equal) is only correct when storage is exactly
  `2**clog2(G_DEPTH)` AND G_DEPTH is a power of two. For non-power-of-2
  depths, derive full from an explicit distance test, e.g.
  `r_rw = r_rr + to_unsigned(G_DEPTH, C_PTR_W)` (mod `2**C_PTR_W`), which is
  correct for all depths and algebraically identical to the MSB test for
  power-of-2 depths.
- **Anti-pattern:** reusing the MSB-differs full test with a non-power-of-2
  depth — it fires too late (only at `2**clog2(G_DEPTH)` items, unreachable
  under an occupancy gate) or not at all, and silently misreports.
- **Check:** if G_DEPTH is not power-of-2, the full flag must be a
  distance/occupancy comparison, or be documented as power-of-2-only AND
  unused.
- **Example (found in `phase_shifter_1_0` review, 2026-10-10):** MSB-differs
  full flag read '0' with 6 valid entries in a depth-6 FIFO.

## 3. FWFT prefetch from a synchronous RAM must be in-flight gated

- **Rule:** If a first-word-fall-through FIFO is built on a synchronous-read
  RAM using a prefetch/shadow architecture, the prefetch request MUST be
  gated by “no prefetch already in flight” (for a 1-cycle RAM read,
  `not <ram_dout_en>`). Otherwise a second read of the same or next address can
  be issued before the first read result has been committed.
- **Anti-pattern:** asserting prefetch whenever `not out_valid and count > 0`
  (or a similar condition that remains true during the prefetch arrival cycle).
  The duplicate arrival can outrank the consume in the shadow update priority
  chain, redeliver the head word, desynchronize `valid`/`count`, and eventually
  re-deliver stale RAM words at drain.
- **Check:** for every FWFT prefetch path, verify that at most one RAM read is
  outstanding, and that the shadow/output update priority cannot mask a consume
  with a duplicate arrival. If this cannot be made obvious, prefer a
  combinational head-read storage array or an explicit multi-stage output
  pipeline.
- **Example (found in `fifo_1_0` review, 2026-10-20):** an early dp_ram-based
  FWFT design re-issued the prefetch while the previous prefetch was still in
  flight; the duplicate arrival masked the consume and every word was
  redelivered under rate-1 back-to-back reads. The final `fifo_1_0` design
  avoids the problem by using a local combinational head-read array for FWFT
  mode.

## 4. Registered status reset values must match the count=0 combinational values

- **Rule:** When status outputs are optionally registered, every registered
  status reset/initial value MUST equal the corresponding combinational status
  value at `count = 0` for all legal generic sets. This includes corner
  thresholds such as `G_ALMOST_FULL_OFFSET = G_DEPTH`.
- **Anti-pattern:** hard-coding `r_almost_full` reset to `'0'` while
  `almost_full_comb` is `'1'` at `count = 0` when
  `G_ALMOST_FULL_OFFSET >= G_DEPTH`. The registered output then lags the
  combinational condition for one cycle after reset release.
- **Check:** for each registered status flag, compare its reset/initial value
  to the combinational expression evaluated at `count = 0` across the legal
  generic range.
- **Example (found in `fifo_1_0` review, 2026-10-20):**
  `r_almost_full` reset to `to_sl(G_ALMOST_FULL_OFFSET >= G_DEPTH)` so the
  registered and combinational `O_ALMOST_FULL` values agree at reset release.

## 5. Integrator side: occupancy-gated reuse requires explicit no-overflow / no-underflow proofs

- **Rule:** When a top level reuses a FIFO block (e.g. `fifo_1_0`) but gates
  flow on its OWN occupancy counter instead of the FIFO's `O_FULL`/`O_EMPTY`
  flags — leaving `O_FULL`/`O_OVERFLOW`/`O_UNDERFLOW` open — the design MUST
  document and prove both:
  1. **No overflow:** at any qualified write edge, the FIFO's live occupancy
     (its own internal count) is `< G_DEPTH`. Typical argument: top-level
     occupancy `r_occ` (accepted-not-consumed, spanning pipeline + FIFO) is
     bounded by `G_DEPTH`, and at a write edge at least one in-flight sample
     is still in the pipeline, so FIFO occupancy = `r_occ - in_pipeline <=
     G_DEPTH - 1` — the FIFO's `full` can never coincide with a qualified
     write.
  2. **No underflow:** the consume/`I_RD_EN` signal is gated by the FIFO's
     not-empty condition (or by an equivalent flag that can never be `'1'`
     when the FIFO is empty), so a read can never fire on an empty FIFO.
- **Anti-pattern:** leaving `O_FULL`/`O_OVERFLOW` open on the assumption that
  "the occupancy counter is roughly the same thing", with no argument that the
  FIFO's *internal* count is bounded differently from the top-level counter.
  The two counts differ by exactly the in-flight pipeline terms; a proof that
  only bounds the top-level counter is insufficient.
- **Check:** for the write path, evaluate FIFO-internal occupancy at every
  possible qualified-write edge (express it as `r_occ - P` where `P` is the
  minimum in-pipeline count) and confirm it is `< G_DEPTH`; for the read path,
  confirm the consume is `and`-gated by not-empty (or an equivalent safe
  flag).
- **Example (found in `frequency_shifter_1_0` review, 2026-10-21):** the top
  level drives `fifo_1_0` FWFT with `I_WR_EN = s_cm_o_en` and `I_RD_EN = s_o_en`
  and leaves all status/error ports open; `r_occ <= r_occ + s_accept - s_o_en`
  is bounded by `G_FIFO_DEPTH` and the write only fires when a sample has just
  left the CM (P >= 1), so FIFO occupancy at write edges is <= G_FIFO_DEPTH - 1;
  `s_o_en = not empty and not I_WAIT` kills underflow. Both proofs recorded in
  the design doc section 4.4.
