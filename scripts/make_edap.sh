#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# make_edap.sh <bench> : copy one bench into a flat folder for EDA Playground
#
#   edap/<bench>/design.sv      <- <bench>/rtl/*.sv
#   edap/<bench>/testbench.sv   <- <bench>/tb/tb_top.sv
#   edap/<bench>/*.sv           <- every other <bench>/tb file (+ common APB agent)
#
# Upload design.sv and testbench.sv into the two main tabs, then add every
# other file with "+" using the same file name. Includes use bare names, so
# the folder must stay flat.
#
# Benches: apb axi uart spi i2c   (or "all")
# ----------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCHES=(apb axi uart spi i2c)

bundle() {
  local b="$1"
  local src="$ROOT/$b"
  local out="$ROOT/edap/$b"

  if [[ ! -d "$src/tb" || ! -d "$src/rtl" ]]; then
    echo "error: no bench '$b' (expected $src/tb and $src/rtl)" >&2
    exit 1
  fi

  rm -rf "$out"
  mkdir -p "$out"

  # Design: concatenate RTL (each bench has one file today)
  cat "$src"/rtl/*.sv > "$out/design.sv"

  # Testbench top
  cp "$src/tb/tb_top.sv" "$out/testbench.sv"

  # Remaining bench files
  for f in "$src"/tb/*.sv; do
    [[ "$(basename "$f")" == "tb_top.sv" ]] && continue
    cp "$f" "$out/"
  done

  # Every bench except AXI uses the shared APB agent
  if [[ "$b" != "axi" ]]; then
    cp "$ROOT"/common/apb_agent/*.sv "$out/"
  fi

  echo "== $b -> edap/$b"
  echo "   design.sv, testbench.sv, plus $(($(ls "$out" | wc -l) - 2)) extra files:"
  ls "$out" | grep -v -e '^design.sv$' -e '^testbench.sv$' | sed 's/^/     /'
}

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <apb|axi|uart|spi|i2c|all>" >&2
  exit 1
fi

if [[ "$1" == "all" ]]; then
  for b in "${BENCHES[@]}"; do bundle "$b"; done
else
  bundle "$1"
fi
