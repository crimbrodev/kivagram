#!/bin/sh
# kivagram build: склейка lib/tg.k + модулей lib/tg_*.k (алфавит, LC_ALL=C) + исходника, компиляция kivac, линковка kivaa.
# Usage: ./build.sh <file.k> <out>
set -eu

if [ $# -ne 2 ]; then
    echo "usage: ./build.sh <file.k> <out>" >&2
    exit 2
fi

SRC=$1
OUT=$2
KIVA_TC=${KIVA_TC:-/tmp/opencode/kivac-pr}
LIBDIR="$(dirname "$0")/lib"
MODS=$(ls "$LIBDIR"/tg_*.k 2>/dev/null | LC_ALL=C sort || true)

if [ ! -f "$SRC" ]; then
    echo "error: no such file: $SRC" >&2
    exit 2
fi
if [ ! -x "$KIVA_TC/kivac" ] || [ ! -x "$KIVA_TC/kivaa" ]; then
    echo "error: toolchain not found in $KIVA_TC (need kivac and kivaa); build it or set KIVA_TC" >&2
    exit 2
fi

# склейка в уникальный на сборку файл — параллельные build.sh не дерутся за общий build.k
GLUE="$OUT".glue.k
cat "$LIBDIR/tg.k" $MODS "$SRC" > "$GLUE"
"$KIVA_TC/kivac" "$GLUE" "$OUT.ir"
rm -f "$GLUE"
"$KIVA_TC/kivaa" "$OUT.ir" "$OUT"
# kivaa возвращает exit 0 даже при ошибках nasm/cc/ld — истина в бинарнике
if [ ! -x "$OUT" ]; then
    echo "error: build failed (no binary at $OUT)" >&2
    exit 1
fi
