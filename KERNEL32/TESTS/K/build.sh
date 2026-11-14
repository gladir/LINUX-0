#!/bin/sh
# Compile les programmes de test (ELF i386 statiques) dans $1 (defaut : ./out)
cd "$(dirname "$0")"
OUT="${1:-out}"
mkdir -p "$OUT"
for f in hello forkwait pipetest sigtest mmaptest dirtest ttytest schedtest init; do
  gcc -m32 -static -nostdlib -ffreestanding -fno-pic -fno-pie -no-pie -Os -fno-stack-protector \
      -fno-asynchronous-unwind-tables -fno-builtin -Wall -Wno-unused-function -Wl,--build-id=none \
      -Wl,-z,noseparate-code -Wl,-z,norelro -o "$OUT/$f" "$f.c" || exit 1
done
ls -l "$OUT"
