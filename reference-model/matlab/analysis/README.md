# Reproducible Q8.8 numerical analysis

`compute_analysis.py` independently recomputes the saved 4-8-1 MLP model in floating-point and signed Q8.8 arithmetic for 240 test samples. It reads `MLP_reference.mat`, writes a recomputed CSV and metrics JSON, and can compare the recomputed results with the archived CSV.

## Run

From the repository root:

```bash
python -m pip install -r reference-model/matlab/analysis/requirements-analysis.txt
python reference-model/matlab/analysis/compute_analysis.py --strict-existing-match --no-figures
```

To regenerate figures as well, omit `--no-figures` and install the optional packages in `requirements-figures.txt`.

## Scope

The script implements the arithmetic rules documented in [`../../../docs/fixed-point.md`](../../../docs/fixed-point.md). The calculation is a software reference check, not a VHDL/modelsim simulation. The archived CSV is expected to match all recomputed numeric fields. The historical 31/35-cycle throughput claims are not reproduced by this script.
