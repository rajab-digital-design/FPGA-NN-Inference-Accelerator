# 4-MAC architecture with pipelined output layer

This branch adds registered stages around the output-layer operand selection, multiplication, and accumulation path.

## Archived result and evidence

16.084 ns minimum period; +0.416 ns setup slack; 19-cycle compute window; 986 slices, 849 FFs, 1406 LUT4s, 6 MULT18X18. The archived report meets the 16.5 ns internal timing constraint.

Primary evidence: `reports/historical/pipe_verbose.twr`. These results are historical tool outputs and were not freshly generated during repository curation. Read the reports and transcripts for the exact run configuration.

## Running this branch

- Open the branch-specific project in `project/` using Xilinx ISE 14.7, or use the supplied scripts in `build/` from an ISE Command Prompt.
- Run branch-specific modelsim `.do` scripts from this branch's root when present.
- Preserve the archived reports and write new outputs to a separate location.
- See [`../../docs/reproduction.md`](../../docs/reproduction.md) for general guidance and limitations.
