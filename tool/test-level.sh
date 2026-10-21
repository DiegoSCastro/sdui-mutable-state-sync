#!/usr/bin/env bash
# Compila o nó e roda um nível do txn-rw-register.
# O release oficial traz o jar. O clone do código-fonte exige Leiningen e não executa sozinho.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LEVEL="${1:-}"

if [[ ! "$LEVEL" =~ ^[1-4]$ ]]; then
  echo "uso: tool/test-level.sh [1|2|3|4]" >&2
  exit 1
fi

install_maelstrom() {
  local install="$ROOT/.maelstrom"
  if [[ -x "$install/maelstrom" ]]; then
    return
  fi
  echo "baixando Maelstrom v0.2.4..." >&2
  rm -rf "$install"
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/maelstrom.tar.bz2" \
    "https://github.com/jepsen-io/maelstrom/releases/download/v0.2.4/maelstrom.tar.bz2"
  tar -xjf "$tmp/maelstrom.tar.bz2" -C "$tmp"
  mv "$tmp/maelstrom" "$install"
  rm -rf "$tmp"
}

install_maelstrom

mkdir -p "$ROOT/build"
dart compile exe "$ROOT/bin/maelstrom_txn.dart" -o "$ROOT/build/maelstrom-txn"

BIN="$ROOT/build/maelstrom-txn"
MAELSTROM="$ROOT/.maelstrom/maelstrom"

common=(
  test
  -w txn-rw-register
  --bin "$BIN"
  --time-limit 20
  --rate 1000
  --concurrency 2n
)

case "$LEVEL" in
  1)
    "$MAELSTROM" "${common[@]}" \
      --node-count 1 \
      --consistency-models read-uncommitted \
      --availability total
    ;;
  2)
    "$MAELSTROM" "${common[@]}" \
      --node-count 2 \
      --consistency-models read-uncommitted
    ;;
  3)
    "$MAELSTROM" "${common[@]}" \
      --node-count 2 \
      --consistency-models read-uncommitted \
      --availability total \
      --nemesis partition
    ;;
  4)
    "$MAELSTROM" "${common[@]}" \
      --node-count 2 \
      --consistency-models read-committed \
      --availability total \
      --nemesis partition
    ;;
esac
