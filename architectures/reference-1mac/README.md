# Sequential 1-MAC reference architecture

This branch preserves a sequential 1-MAC design and associated source lists for reference/cycle-count comparison. Its tool constraints and historical results are not directly comparable with the four-way 16.5 ns table.

## Archived result and evidence

Use the branch-specific project and source lists. Review the selected device, clock constraint, and output reports before comparing this reference with another branch.

Primary evidence: `project/reference-1mac.xise`. These results are historical tool outputs and were not freshly generated during repository curation. Read the reports and transcripts for the exact run configuration.

## Running this branch

- Open the branch-specific project in `project/` using Xilinx ISE 14.7, or use the supplied scripts in `build/` from an ISE Command Prompt.
- Run branch-specific modelsim `.do` scripts from this branch's root when present.
- Preserve the archived reports and write new outputs to a separate location.
- See [`../../docs/reproduction.md`](../../docs/reproduction.md) for general guidance and limitations.
