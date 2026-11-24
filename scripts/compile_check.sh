#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# compile_check.sh <uvm_src_dir> [bench|all] : compile-check benches with slang
# (no simulation) against the UVM 1.2 source, clean and with every `ifdef.
#
# One-time setup:
#   python3 -m venv .venv && .venv/bin/pip install pyslang
#   download uvm-1.2.tar.gz from accellera.org and extract it;
#   pass its uvm-1.2/src folder as <uvm_src_dir>.
# ----------------------------------------------------------------------------
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UVM="${1:?usage: $0 <uvm_src_dir> [bench|all]}"
WHICH="${2:-all}"
PY="${PYTHON:-$ROOT/.venv/bin/python}"
[[ "$WHICH" == all ]] && BENCHES=(apb axi uart spi i2c) || BENCHES=("$WHICH")

fail=0
for b in "${BENCHES[@]}"; do
  "$ROOT/scripts/make_edap.sh" "$b" >/dev/null
  for def in "" $(grep -ho '`ifdef [A-Z_0-9]*' "$ROOT/$b"/rtl/*.sv "$ROOT/$b"/tb/*.sv | awk '{print $2}' | sort -u); do
    out=$("$PY" -I "$ROOT/scripts/slang_check.py" "$UVM" "$ROOT/edap/$b" ${def:+-D $def} 2>&1)
    res=$(grep RESULT <<<"$out")
    echo "$b ${def:-(clean)}: $res"
    if ! grep -q "RESULT: OK" <<<"$out"; then
      fail=1
      grep -A3 "error:" <<<"$out" | head -40
    fi
  done
done
exit $fail
