#!/bin/sh
# Compile les programmes de test (ELF i386 statiques) dans $1 (defaut : ./out)
cd "$(dirname "$0")"
OUT="${1:-out}"
mkdir -p "$OUT"
for f in hello forkwait pipetest sigtest mmaptest dirtest ttytest schedtest blktest misctest proctest stress kbdtest ext2test ext4test jrntest ptytest mounttest socktest shmtest limtest evttest devtest mousetest nettest isotest fattest fbtest swaptest killtest idetest preempttest pstress syscalltest sigrttest ipctest mqfutextest ptracetest seccomptest xattrtest nstest bigtest proc2test looptest loopmnt smptest nltest oomtest parttest pwrtest cgtest bdtest vttest idler vboxtest usbtest aperf effects modtest init; do
  gcc -m32 -static -nostdlib -ffreestanding -fno-pic -fno-pie -no-pie -Os -fno-stack-protector \
      -fno-asynchronous-unwind-tables -fno-builtin -Wall -Wno-unused-function -Wl,--build-id=none \
      -Wl,-z,noseparate-code -Wl,-z,norelro -o "$OUT/$f" "$f.c" || exit 1
done
# modules du noyau (lpc -3M) : fichiers .ko embarques dans /bin
LPC=${LPC:-/tmp/claude-0/work/k32/bin/lpc}
for m in hello hello2 badinit unkmod irqmod; do
  cp "$m.pas" "$OUT/$m.pas"
  (cd "$OUT" && "$LPC" -3M -q "$m.pas" >/dev/null && rm -f "$m.pas") || exit 1
done
ls -l "$OUT"
