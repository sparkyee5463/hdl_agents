# RAM — Review Skills

Read when the design has a writable memory (single/dual port RAM, register
file, FIFO storage). ROM rules are in `rom_skills.md`.

---

## 1. One write process, init in the declaration

- **Rule:** The memory array is written by exactly ONE clocked process
  (per port pair in true dual port: one process per port only when the
  memory is a protected shared variable the tool supports — prefer one
  process). Initial contents come from the declaration:
  `signal mem : t_ram := f_init(G_INIT_FILE);`.
- **Anti-pattern:** a separate process that loads the init file into the
  same signal. That is a second driver: every bit where the drivers differ
  resolves to 'X' and reads return X, even after writes.
- Init-file generics need a test that loads a file and reads it back.

## 2. Inferrable templates

- No `shared variable` without `protected` type, no runtime-selected
  write mode ports, no reset on the array or on BRAM read data registers.
  Check the synthesis report actually shows BRAM/URAM/LUTRAM as intended.

## 3. Read-during-write and collisions

- **Rule:** For same-port and cross-port same-address access, the doc says
  which value is read (old, new, or undefined) and the RTL implements it
  without depending on process execution order. Two processes writing the
  same address on the same cycle: say which wins or that it is illegal.
- Test: same-address read/write on the same cycle on both ports.

## 4. Address range

- Depth not a power of two: addresses >= depth must be impossible or
  checked (`fifo_skills.md#1`).
