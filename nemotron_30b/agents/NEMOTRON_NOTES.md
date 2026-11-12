# Notes for every agent (Nemotron runs)

These rules come from reviewed Nemotron runs. Each one was broken at least
once. They apply to the lead and to every subagent, on top of your own prompt.

## 1. Ending your turn
- When your work is done, your LAST message is your final answer (the JSON
  your prompt asks for, or the final report) and it contains NO tool call.
- Never call `true`, `echo "done"`, or any other tool after writing your
  final answer. A tool call means "I am not finished", and you will loop.
- If you see that you already wrote your final answer, STOP: send it once
  more with no tool call. (run1, 2026-11-06: the verification architect
  repeated its final report + `true` 20 times and never returned.)

## 2. The lead delegates, it does not read
- Do not read the files a subagent will read (design doc, sim plan, the
  worked example) before calling it. Give it paths; it reads them.
- After a subagent returns, check its files exist (`ls`), run the one
  command it gives you, and commit. Do not re-do its work.
- The lead never writes IP files (reference, tests, testbench, docs) itself,
  not with the edit tool and not with `cat > file` in bash. Only STATE.md
  and skills entries. If a subagent failed or returned nothing, call it
  again with what went wrong. (run1, 2026-11-06: the lead wrote the
  reference model itself after the verification architect looped.)

- A subagent's "fixed" is a claim, not a result. For each finding, run one
  command that exercises the fix (e.g. call the fixed function) before you
  accept it. (run5, 2026-11-06: "F6 fixed" was reported, but
  `Generics.from_env()` still had no `@classmethod` and crashed on the
  first call; the self-test never called it.)
- A first-round review that finds nothing on a new reference model is not a
  pass: Nemotron reviewers rubber-stamp. (run4: the reviewer passed a
  reference with no accumulator, no Taylor mode and constant flags.)

## 3. Python and paths
- Run Python only as `source tools/eda_env.sh && python ...` (or
  `hdl_env/bin/python`). Never bare `python3` with `PYTHONPATH=` or
  `sys.path.insert` hacks.
- Testbench tests live in `testbench/cocotb_testbench_<ip_name>_shared/tests/`,
  never `testbench/tests/`. Check the path before every write.

## 4. A denied read or write is denied on purpose
- A refused write (edit/write tool) means the file is not yours. Never write
  it another way (bash heredoc, `cat >`, `tee`, `sed -i`, `python -c`).
- If a read is refused, or your prompt forbids a file (hdl/, testbench
  files that are not yours), do NOT get the same content another way: no
  `cat`, no `python -c "import ..."`, no `dir()`, no grep in it. Work from
  what you may read.

## 5. Readable code
- Every name is a word or words: `phase_width`, `address_bits`,
  `magnitude`, `full_scale`, `input_transaction`. Never `pw`, `a`, `s`,
  `fm`, `inp`, `g`, `_g`, `b`, `exp`. Loop indices (`index`) are fine.
- No port-name constant tables (`PORT_I_CLK = "i_clk"`): read pins by name.

## 6. Reference models (verification_architect)
- Model the doc's BEHAVIOUR, never the RTL's structure: no pipeline
  registers, delay lines or cycle counters in the reference. But when the
  doc gives the exact bit-level arithmetic of an output (a fixed-point
  formula, a truncation, a rounding rule, a constant), that arithmetic IS
  the spec: implement it exactly and cite the doc section, even if the doc
  explains it with hardware words (e.g. nco_2_0 §4.6 `bcoef >> 7`). Never
  replace a stated formula with an "ideal" one.
- Every input pin's effect in the doc must be in the reference (state
  updates such as an accumulator, a loaded register, a sync reset). The
  reference takes the INPUT transaction, never an internal value as an
  argument.
- Outputs that follow input flags (EN/ST/DN, valid, last) are computed from
  the input transaction. Never return a constant 1 for them.
- Encoded outputs: the encoded value is the FULL port width, sign bit
  included. Write the encode as one small function and test it on a
  negative value (sign bit set) and a positive one.
- Exact compare unless the doc gives a tolerance for THAT port. A
  spectral-quality number (SNR, SFDR, max error) is a spec-level test, not
  a tolerance on the bit-exact compare.

## 7. Self-tests (`tests/test_reference.py`)
- Every expected number is worked by hand from a doc formula, with the
  doc section in a comment. Never copy the model's own output into the
  test.
- Cover all four quadrants / both signs, a reset, and each mode generic.
- Run it and paste the pass line. A test that passes on your first try,
  for a model you just wrote, needs one extra negative check: change one
  expected value and confirm the test fails, then change it back.

## 8. Coverage bins
- A bin is a predicate on a value you sample: `"zero": lambda increment:
  increment == 0`. `lambda value: value` is not a bin.
- Scenario results (SNR, SFDR, "full period observed") are tests, not bins.
- Every bin must be reachable by some test; list which test reaches it.

## 9. Protected files and failing tests (cocotb_tb_architect)
- Files your task says are done (reference model, interface, coverage,
  RTL, design doc) are NOT yours. If a test fails, the bug is
  in the files YOU wrote. Never change a protected file, not with the edit
  tool and not with `sed`/`python3 -c`/`cat >` in bash. (tb run A,
  2026-11-07: the architect "fixed" the graded reference to hide its own
  checker bug.)

## 10. cocotb loops
- A per-edge loop (driver, monitor) awaits ONLY the clock edge.
  Inside it use `queue.get_nowait()` after checking `queue.empty()`; an
  `await queue.get()` there stops the loop on the first empty cycle.
- A consumer loop (checker) awaits ONLY its queues, never the clock too:
  two clocks in one loop drift out of step.
- Every input, reset included, goes through the driver's queue so the
  checker sees it. Never write a DUT pin from a test or the tb manager.
- The reference model is called exactly once per driven input, for every
  input (reset ones too): skipping one makes its state drift.

## 11. Never switch off a check to make a test pass (cocotb_tb_architect)
- If a compare fails, the fix is never to skip it, `pass` it, count a pass
  when there was nothing to compare, or accept "0 compares". (tb run A2,
  2026-11-07: the checker skipped every reference compare and counted
  passes with no data; the report blamed a "structural mismatch" that did
  not exist.)
- A test that passes with 0 compares is not a pass. Print
  `scoreboard.report()` and read the counts: compares >= inputs - flushed.
- A file the task says to keep (e.g. `generic_sets.py`) or does not list
  (e.g. `tb_cocotb.py`) is not yours: do not touch it.
- Every name you use is imported: run
  `source tools/eda_env.sh && python -c "import <module>"` in the tb dir for
  each file you write. (A2: `RisingEdge` and `read` were used unimported,
  hidden only because that code had never run.)
- When the prompt gives a design, re-read it after each file and check every
  bullet. Where the prompt gives code, copy it.

## 12. Paste outputs, never summaries of them
- The final report pastes the LAST line of each check command exactly as
  printed. Never write "static checks pass" or "N of M pass" in place of the
  output. (tb run B1, 2026-11-07: the lead reported static checks as
  passing; they failed on two lines, and one test file did not even import.)

## 13. Assertions check exact values
- Never weaken an assertion to make it pass: no range checks
  (`-fs <= v <= fs`), `len(...) > 0`, `count >= N` or "values exist" in place
  of exact values, bounds, cycles or sets the doc gives. Never return a
  made-up limit (`err_bound()` returning 1000) and never wrap assertions in
  `try/except: pass`. (tb run B2, 2026-11-07: every one of these, in 11
  tests; the report called the result "scenario assertions added".)
- The reviewer's fault check corrupts what the assertions read; a test that
  still passes under the corruption is rejected.

## 14. Acceptance commands decide "done"
- When your prompt gives an acceptance command (e.g.
  `source tools/eda_env.sh && python fw_ip/<base>/<ip>/work/tb_checks.py`),
  you are done only when its last line says ALL ... PASS. Paste that line.
  A FAIL line names what to fix: fix your files, never the check.
- A DUT-fault check (the DUT's outputs are inverted on purpose) fails a test
  only if the test compares the DUT outputs. A test that still passes under
  the fault compares nothing: make it compare, do not delete it.

## 15. One consumer per queue; the harness is not the suspect
- Every `cocotb.queue.Queue` has exactly ONE loop that `get()`s from it. Two
  loops reading the monitor's queue (a compare loop and a coverage loop) each
  see half the samples: half the compares then fail. Sample coverage in the
  same loop that compares. (grey_encoder run5: 25 of 50 compares failed this
  way, and the report blamed the shared scheduler.)
- The expected value of a sample comes from the input the DRIVER drove for
  it (`driver.driven_inputs`), not from what a test queued with `send()`.
- The shared framework (`fw_py_tools.tb`, cocotb, vcst) is tested and used by
  every IP. When a run fails, the bug is in your files: print the first
  3 mismatches (input, expected, got) and find the off-by-one or the shared
  queue. Never report "harness synchronization issue" without a 10-line
  reproduction that uses no file of yours.
