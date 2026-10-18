#!/bin/sh
# kivagram build: склейка lib/tg.k + исходника, компиляция kivac, линковка kivaa.
# Usage: ./build.sh <file.k> <out>
set -eu

if [ $# -ne 2 ]; then
    echo "usage: ./build.sh <file.k> <out>" >&2
    exit 2
fi

SRC=$1
OUT=$2
KIVA_TC=${KIVA_TC:-/tmp/opencode/kivac-pr}
LIB="$(dirname "$0")/lib/tg.k"

if [ ! -f "$SRC" ]; then
    echo "error: no such file: $SRC" >&2
    exit 2
fi
if [ ! -x "$KIVA_TC/kivac" ] || [ ! -x "$KIVA_TC/kivaa" ]; then
    echo "error: toolchain not found in $KIVA_TC (need kivac and kivaa); build it or set KIVA_TC" >&2
    exit 2
fi

cat "$LIB" "$SRC" > build.k
"$KIVA_TC/kivac" build.k "$OUT.ir"
"$KIVA_TC/kivaa" "$OUT.ir" "$OUT"
# kivaa возвращает exit 0 даже при ошибках nasm/cc/ld — истина в бинарнике
if [ ! -x "$OUT" ]; then
    echo "error: build failed (no binary at $OUT)" >&2
    exit 1
fi
