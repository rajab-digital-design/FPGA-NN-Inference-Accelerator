# 4-MAC architecture with One-Hot input-buffer selection

This experiment changes the four-input buffer read-selection logic to decoded one-hot control and parallel mask/OR logic. A fallback path is retained for other input counts.

## Archived result and evidence

16.355 ns minimum period; +0.145 ns setup slack; 19-cycle compute window; 1019 slices, 911 FFs, 1410 LUT4s, 6 MULT18X18. Archived buffer-equivalence and full-network regression transcripts are included. The timing is slower than the Pipeline variant.

Primary evidence: `reports/ise/pipe_onehot_verbose.twr`. These results are historical tool outputs and were not freshly generated during repository curation. Read the reports and transcripts for the exact run configuration.

## Running this branch

- Open the branch-specific project in `project/` using Xilinx ISE 14.7, or use the supplied scripts in `build/` from an ISE Command Prompt.
- Run branch-specific modelsim `.do` scripts from this branch's root when present.
- Preserve the archived reports and write new outputs to a separate location.
- See [`../../docs/reproduction.md`](../../docs/reproduction.md) for general guidance and limitations.
