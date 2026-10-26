# Design scope and current implementation

## What the repository demonstrates

The repository is a VHDL design and comparative evaluation of a MAC-based FPGA neural-network inference datapath. The main experiment compares four four-MAC RTL variants under the same 4–8–1 MLP workload and recorded implementation constraints. The differences under study are output-layer pipelining, one-hot input-buffer read selection, and replication of the registered input-buffer read address.

## Current implementation boundary

The integrated top-level and output-layer interface are tailored to the reference 4–8–1 network. Some lower-level modules expose generics such as `NUM_INPUTS` and `NUM_NEURONS`, and selected input-selection logic has simulation evidence for multiple input counts. That does not mean arbitrary layer dimensions or topologies are supported end-to-end.

The measured timing/resource numbers apply only to the documented RTL variants, target device, constraints, and archived tool runs. They should not be generalized to different layer sizes, MAC-lane counts, arithmetic widths, or FPGA targets without new functional simulations and implementation reports.

## Possible future engineering work

Further adaptation could make network dimensions explicit throughout the top-level, scheduler, memories, neuron interfaces, and output layer; define supported address and accumulator ranges; and add parameterized regression tests for incomplete final MAC groups and boundary cases. Such changes would need fresh ModelSim and Xilinx ISE validation before broader configuration support could be claimed.
