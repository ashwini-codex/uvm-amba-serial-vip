"""Compile one EDA Playground bundle (edap/<bench>) with slang + UVM 1.2.
usage: check.py <uvm_src_dir> <bundle_dir> [extra slang args...]
"""
import sys
from pyslang.driver import Driver

uvm, bundle = sys.argv[1], sys.argv[2]
extra = " ".join(sys.argv[3:])

d = Driver()
d.addStandardArgs()
cmd = (f"slang --top tb_top -I {uvm} -I {bundle} --timescale 1ns/1ps "
       f"--suppress-warnings {uvm} --diag-abs-paths "
       f"{uvm}/uvm_pkg.sv {bundle}/design.sv {bundle}/testbench.sv {extra}")
if not d.parseCommandLine(cmd):
    sys.exit("bad command line")
if not d.processOptions():
    sys.exit("bad options")
d.parseAllSources()
ok = d.runFullCompilation(False)
print(f"RESULT: {'OK' if ok else 'FAILED'}  errors={d.diagEngine.numErrors} warnings={d.diagEngine.numWarnings}")
sys.exit(0 if ok else 1)
