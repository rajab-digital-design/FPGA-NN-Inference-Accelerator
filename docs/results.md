# Results and interpretation

## Scope of the comparison

The metrics below compare four RTL variants using the same 4–8–1 reference MLP, target device, and stated constraints. The main engineering result is a controlled comparison of how output-layer pipelining, one-hot input selection, and address-register replication affect timing and logic-resource use. These values apply to the recorded configuration; they are not universal performance predictions for other networks or FPGA targets.

## Four-way comparison

| Variant | Minimum period | Setup slack | Compute window | Slices | FFs | LUT4 | MULT18X18 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Base | 17.432 ns | -0.932 ns | 17 cycles | 967 | 782 | 1377 | 6 |
| Pipeline | 16.084 ns | +0.416 ns | 19 cycles | 986 | 849 | 1406 | 6 |
| One-Hot | 16.355 ns | +0.145 ns | 19 cycles | 1019 | 911 | 1410 | 6 |
| Fanout / address replica | 15.104 ns | +1.396 ns | 19 cycles | 994 | 853 | 1419 | 6 |

![Minimum period](../assets/charts/01_min_clock_period.png)

The values are taken from archived Xilinx ISE reports for Spartan-3 `xc3s400-4-pq208` with a 16.5 ns internal clock constraint. They are historical results, not a fresh build from this repository.

## Main observation

The address-register-replication variant improved the minimum period from 16.084 ns to 15.104 ns relative to Pipeline:

- Absolute improvement: `16.084 - 15.104 = 0.980 ns`.
- Relative improvement: approximately `0.980 / 16.084 = 6.1%`.
- Resource delta: +8 slices, +4 FFs, +13 LUT4s, and no change in the six multiplier primitives.
- Compute window: remains 19 cycles in the recorded scenario.

The One-Hot variant did not improve timing against Pipeline in the archived implementation. It passed the internal 16.5 ns constraint but reported 16.355 ns versus 16.084 ns for Pipeline, with +33 slices and +62 FFs.

## Interpret the metrics carefully

- **Minimum period** is the tool-reported internal timing metric from the archived TRACE run; it is not a guaranteed clock on every board.
- **Setup slack** is relative to the constraints defined for that run.
- **Compute window** is a documented simulation cycle count and should not be conflated with start-to-done latency, sustained initiation interval, or measured throughput.
- The supplementary 31-cycle cached-input and 35-cycle reload intervals are retained only as historical claims because their referenced raw testbench/transcript is absent.
- There is no measured power, board-level performance, complete I/O pin assignment, or physical FPGA validation in the available evidence.
- Changing network dimensions, MAC-lane count, arithmetic width, device, constraints, or integration may change both resource and timing results. New configurations require new functional simulation and implementation reports.
