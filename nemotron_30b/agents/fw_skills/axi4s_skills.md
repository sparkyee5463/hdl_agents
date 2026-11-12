# AXI4-Stream (AXI4S) — HDL Review Skills

Common things to check when reviewing HDL that implements or interfaces with
AXI4-Stream. **Add a new numbered entry here every time a new AXI4S issue is
found in review, so the same mistake is not made again.** Each entry should
state the rule, the anti-pattern, and (when relevant) the concrete example that
motivated it.

The `hdl_reviewer` subagent applies this checklist to the VHDL that
`rtl_coder` writes. Keep entries short, concrete, and checkable.

---

## 1. Explicit `TVALID` / `TREADY` top-level ports (protocol visibility)

- **Rule:** Every AXI4-Stream interface must expose `TVALID` and `TREADY` as
  **explicit, individually-named, top-level ports**. A reviewer and any
  integrator must be able to see the `TVALID`/`TREADY` handshake directly in
  the port map.
- **Rule:** The handshake is: a transfer occurs on a clock edge when **both**
  `TVALID` and `TREADY` are high. `TVALID` is driven by the source (master),
  `TREADY` by the sink (slave). `TREADY` must not combinationally depend on
  `TVALID` (no combinational loop); it may depend on backpressure/stall inputs
  and reset.
- **Anti-pattern (found in `axi4s_to_generic_intf_1_0` v1):** the AXI4S input
  was a single record port `I_S_AXIS : t_axi4s_m2s` (from `axi4s_pkg`) and the
  ready was a separate flat port `O_M_AXIS_TREADY`. This **buried `TVALID`
  inside the record**, so there was no visible top-level `TVALID` signal and the
  two sides of the bus used inconsistent naming (record vs flat). The protocol
  handshake was non-obvious and easy to get wrong.
- **Fix:** flatten the record into explicit ports with one consistent prefix,
  e.g. `S_AXI4S_TVALID`, `S_AXI4S_TREADY`, `S_AXI4S_DATA`, `S_AXI4S_TSTRB`,
  `S_AXI4S_TLAST`. The delivered-beat indicator must be exactly
  `TVALID AND TREADY`.
- **Allowed form:** the DATA payload MAY be one `t_axi4s` record port
  (`S_AXI4S_DATA`: tdata/tkeep/tstrb/tuser/tid/tdest/tlast) as long as
  `S_AXI4S_TVALID` and `S_AXI4S_TREADY` are separate flat ports beside it.

## 2. Consistent signal naming per bus

- **Rule:** All signals on one bus share a consistent prefix/scheme (e.g.
  `S_AXI4S_*` for an AXI4-Stream slave port group). Do **not** mix a record
  name (`I_S_AXIS`) with flat signal names (`O_M_AXIS_TREADY`) for the same bus.
- **Rule:** Follow the project port convention: generics `G_*`, inputs `I_*`
  (or the bus-prefixed form), outputs `O_*`. Backpressure/stall inputs use a
  clear name (e.g. `I_WAIT`) and are placed logically in the port map.
- **Rule (prefix follows the port's OWN direction, not the driver's perspective):**
  for a shared internal net driven by one entity and consumed by another (e.g. a
  reader's read-enable *output* wired to a datapath's read-enable *input*),
  prefix each port by ITS OWN declared direction — the driver's port is `O_*`
  and the consumer's port is `I_*`, even though both bind the same signal. Do
  NOT name the consumer's input `O_*` just because the driving output is `O_*`.
  (Motivating example, found in the `fft_core_1_0` naming-compliance rename:
  `fft_datapath.vhd` `I_RD_EN/I_RD_BANK/I_RD_ADDR` are `in` ports fed by
  `fft_output_reader`'s `O_RD_EN/O_RD_BANK/O_RD_ADDR` outputs via `fft_core`
  `s_rd_*` nets — the datapath ports must be `I_*`, not `O_*`.)

## 3. Handshake / backpressure correctness

- **Rule:** The valid/delivered indicator on the output side must be exactly
  `TVALID AND TREADY` (use `axi4s_pkg.axi4s_beat(tvalid, tready)` where the
  helper is available). Never derive "delivered" from `TVALID` alone.
- **Rule:** While `TREADY = '0'` the source holds `TDATA`/`TSTRB`/`TLAST`
  stable (standard AXI4S). The testbench driver must model this (hold the beat,
  do not advance, until accepted).
- **Rule:** `TREADY` deasserts during reset; no beat is accepted or delivered
  while in reset.
- **Rule:** `TLAST` marks the end of a frame/packet and must be carried through
  to the output (e.g. a `done`/`dn` output) aligned to the same beat.

## 4. Data / sideband handling

- **Rule:** State explicitly which sidebands (`TKEEP`, `TUSER`, `TDEST`, `TID`)
  are forwarded vs accepted-but-ignored. Do not silently drop a sideband that a
  downstream consumer needs; if unused, document it in the header.
- **Rule:** Byte strobe semantics: `TSTRB` (per-byte write strobe) vs `TKEEP`
  (per-byte valid, contiguous from LSB). Be explicit about which one the output
  strobe reflects.

## 5. Latency / pipeline alignment

- **Rule:** If the adapter adds pipeline stages, the valid sideband must be
  aligned to the data through the **exact same latency**, and the latency must
  be stated in the design doc and matched by the testbench model.
- **Rule:** For a 0-latency (combinational) adapter, document that `O_*` payload
  is valid only in the same cycle as the handshake, and that the outputs are (or
  are not) reset — state the consumer contract.

## 6. Reset-gate a valid output driven from unreset hold state

- **Rule:** If a `TVALID` (or any protocol-visible valid) is driven from
  unreset datapath/hold state (e.g. a capture/skid buffer that is not cleared
  by reset), it MUST be combinationally gated by reset:
  `TVALID <= (I_RST_N = '1') and hold_nonzero`.
- **Anti-pattern (found in `axi4s_buffer_1_0` debug):** the capture buffer was
  unreset (correct for a datapath), but `M_TVALID` was not reset-gated. A beat
  held in the buffer at the moment a mid-stream reset is asserted would
  handshake with `M_TREADY` on the first reset cycle and be "delivered" while
  the occupancy count IS reset — the beat vanishes from the accounting and is
  lost.
- **Fix:** gate every protocol-visible output that reflects unreset state with
  reset, so the interface is fully quiesced during reset (motivating example:
  `axi4s_buffer_1_0.vhd` — `M_AXI4S_TVALID <= to_sl(I_RST_N = '1' and
  s_cap_cnt > 0)`).

## 7. Free-running output pipelines do NOT hold data between valid pulses

- **Rule:** A free-running output pipeline (e.g. `dual_port_ram_1_0`
  `O_DOUT_B` with `G_REG_STAGES > 0`) shifts every cycle; the payload is valid
  ONLY while the latency-accurate enable (`O_DOUT_EN_B`) is high. Sample the
  payload only on the EN pulse. If the downstream must hold a beat during
  backpressure, add a capture/skid buffer downstream — never assume the
  pipeline holds.
- **Anti-pattern (found in `axi4s_buffer_1_0` v1):** the 2-entry skid design
  assumed the RAM output "holds" between reads. With `G_REG_STAGES = 1` the
  output register is free-running, so the second in-flight beat clobbered the
  held beat under M backpressure — beats were silently dropped
  (`test_random_mixed` lost 1 of 64 beats, `O_COUNT` stuck +1).
- **Fix:** sample `O_DOUT_B` only when `O_DOUT_EN_B = '1'` and insert into a
  bounded capture buffer sized for the pipeline depth (motivating example:
  `axi4s_buffer_1_0.vhd` — 3-entry `s_cap` + committed-beat read gate).
- **Related trap:** a concurrent assertion comparing a direct register with a
  register's combinational output copy (e.g. `s_cap_cnt` vs a buffered
  `O_DOUT_EN_B`) false-trips on the one-delta skew at the clock edge. Write
  such overflow guards as CLOCKED assertions inside `rising_edge`, sampling the
  same pre-edge values the consuming process samples.

---

## How to use this file

- `rtl_coder`: write AXI4S HDL to satisfy every entry above.
- `hdl_reviewer`: check the VHDL against every entry; cite the entry number for
  each finding.
- When a **new** AXI4S issue is found (in review or debug), append a new numbered
  entry here with the rule + the anti-pattern + the motivating example, so it is
  caught automatically next time.
