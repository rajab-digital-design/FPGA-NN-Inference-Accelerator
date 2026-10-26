# 4-MAC baseline with sequential output layer

The hidden layer uses four parallel MAC lanes. The output layer uses the sequential MAC implementation. This is the baseline branch for the four-way comparison.

## Archived result and evidence

17.432 ns minimum period; -0.932 ns setup slack; 17-cycle compute window; 967 slices, 782 FFs, 1377 LUT4s, 6 MULT18X18. It does not meet the archived 16.5 ns internal timing constraint.

Primary evidence: `reports/historical/parallel_4mac_base.twr`. These results are historical tool outputs and were not freshly generated during repository curation. Read the reports and transcripts for the exact run configuration.

## Running this branch

- Open the branch-specific project in `project/` using Xilinx ISE 14.7, or use the supplied scripts in `build/` from an ISE Command Prompt.
- Run branch-specific modelsim `.do` scripts from this branch's root when present.
- Preserve the archived reports and write new outputs to a separate location.
- See [`../../docs/reproduction.md`](../../docs/reproduction.md) for general guidance and limitations.
