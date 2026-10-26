# 4-MAC architecture with a replicated input-buffer address register

This experiment adds an independent synchronous register for the input-buffer read address, separate from the scheduler address register. It changes address/control routing rather than adding an arithmetic pipeline stage.

## Archived result and evidence

15.104 ns minimum period; +1.396 ns setup slack; 19-cycle compute window; 994 slices, 853 FFs, 1419 LUT4s, 6 MULT18X18. Archived equivalence/regression transcripts and XST/MAP/PAR/TRACE reports are included. The XST report records 45 warnings that should be reviewed before drawing conclusions.

Primary evidence: `reports/ise/pipe_fanout_verbose.twr`. These results are historical tool outputs and were not freshly generated during repository curation. Read the reports and transcripts for the exact run configuration.

## Running this branch

- Open the branch-specific project in `project/` using Xilinx ISE 14.7, or use the supplied scripts in `build/` from an ISE Command Prompt.
- Run branch-specific modelsim `.do` scripts from this branch's root when present.
- Preserve the archived reports and write new outputs to a separate location.
- See [`../../docs/reproduction.md`](../../docs/reproduction.md) for general guidance and limitations.
