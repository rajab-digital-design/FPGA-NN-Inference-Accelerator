# MATLAB reference model and test data

This directory stores the software reference model for the 4–8–1 network implemented by the current reference RTL and used in the architectural comparison. It provides a common numerical basis for checking the floating-point and Q8.8 inference calculations.

Contents include weights and biases in floating-point and Q8.8 forms, test input vectors, expected values, and derived software analysis artifacts.

- `weights-and-biases/`: weights and biases in floating-point, signed-integer, and hexadecimal representations.
- `test-vectors/`: expected intermediate and output values plus test vectors.
- `model-and-scripts/`: saved MATLAB model and calculation scripts.
- `analysis/`: a Python recomputation, a 240-row CSV, metrics, and plots.

The stored 240-sample set is derived from a synthetic nonlinear target function. It is useful for checking numeric agreement with the archived model and quantized arithmetic; it is not evidence of performance on an external real-world dataset or a 240-case RTL simulation.

See [`../../docs/fixed-point.md`](../../docs/fixed-point.md), [`../../docs/architecture.md`](../../docs/architecture.md), and [`../../docs/implementation-scope.md`](../../docs/implementation-scope.md) for arithmetic, architecture, and implementation scope.
