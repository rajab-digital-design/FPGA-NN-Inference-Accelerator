# Fixed-point reference: signed Q8.8

The software reference model uses a signed 16-bit Q8.8 representation with a scale factor of 256.

## Quantization

For a real-valued input or parameter `x`:

```text
q = round_matlab(x * 256)
real_value = q / 256
```

The recomputation script implements MATLAB rounding semantics (nearest integer, ties away from zero).

## Multiply and accumulate

For each input/weight pair, the model multiplies their signed integer representations and arithmetic-shifts the product right by eight bits before adding it to the accumulator:

```text
product_q = (input_q * weight_q) >>> 8
accumulator = bias_q + sum(product_q)
```

The hidden layer applies ReLU to the accumulated value, then transfers activations through a signed 16-bit representation to the output layer. The software script separately checks the hidden accumulator against a signed 20-bit range and checks whether ReLU outputs fit in signed 16 bits for the stored 240-sample set.

These notes describe the included numerical reference calculation. Confirm widths, casts, saturation/wrap behavior, and exact shift points against the RTL in the specific architecture branch before changing arithmetic or claiming bit-exact hardware equivalence.
