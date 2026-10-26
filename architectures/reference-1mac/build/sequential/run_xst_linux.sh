#!/bin/bash
set -u
cd "$(dirname "$0")" || exit 1
echo "=== XST synthesis: sequential_1mac ==="
if ! command -v xst >/dev/null 2>&1; then
  echo "ERROR: xst was not found in PATH. Run this inside the Xilinx ISE 14.7 Linux VM terminal."
  echo "The official Windows 10/11 package build ISE tools inside an Oracle Linux VM."
  exit 127
fi
xst -ifn sequential_1mac.xst -ofn sequential_1mac.syr
rc=$?
echo "XST exit code: $rc"
echo "Inspect sequential_1mac.syr and sequential_1mac.ngc. Verify the top and part in the report."
exit "$rc"
