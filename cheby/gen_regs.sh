#!/bin/sh
# run from mega_138k_test/cheby/
# generates verilog and c headers from all peripheral YAMLs
# outputs: ../src/*_regs.v  ../../gowin_cortexm1_fw/cheby/*.h

set -e

FW_CHEBY=../../gowin_cortexm1_fw/cheby
RTL_SRC=../src

# individual peripheral register files
for yaml in sysinfo_regs.yaml gpio_regs.yaml multiflex_regs.yaml sfp_regs.yaml; do
  name=$(basename "$yaml" .yaml)
  echo "generating $name..."
  cheby --hdl verilog --gen-hdl "$RTL_SRC/${name}.v" --input "$yaml"
  cheby --gen-c "$FW_CHEBY/${name}.h" --input "$yaml"
done

# top-level soc map (C header only -- no RTL needed)
echo "generating soc_regs..."
cheby --gen-c "$FW_CHEBY/soc_regs.h" --input soc_regs.yaml

echo "done"
