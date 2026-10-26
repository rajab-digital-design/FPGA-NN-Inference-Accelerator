# Test evidence and scope

## Functional simulation evidence

Archived ModelSim transcripts are included for the One-Hot input-buffer equivalence test, the Fanout scheduler-address equivalence test, and full-network regression scenarios. The recorded tests cover input counts such as 4, 5, 17, and 21 where relevant. Read the transcript to see the exact assertions and test scenarios.

A PASS transcript documents that its recorded assertions passed in that run. It is not a formal equivalence proof and does not imply verification of every parameterization or every possible input.

## Synthesis and implementation evidence

The four-way branches include archived Xilinx ISE reports. The headline comparison uses the same stated target device and 16.5 ns internal clock constraint. The report artifacts provide the source for the resource and timing numbers in `architecture-comparison.csv`.

Some report classes are incomplete for some variants. In particular, a textual XST `.syr` report for the One-Hot branch is not present in the repository.

## Software numerical evidence

The Python script independently recomputes all 240 software inference outputs from the saved MATLAB model and verifies all numeric fields against the archived result CSV. This test is separate from the VHDL simulation tests.

## Out of scope

The repository does not include a physical FPGA board test, measured power, complete board-level I/O constraints, or a validated bitstream-to-board demonstration. Do not claim those results unless you perform and document those experiments separately.
