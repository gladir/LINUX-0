{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3K)
  @description: Noyau de test TK1 : en-tete multiboot, entree physique,
    pagination (noyau en C0100000h), puis "LINUX-0 OK" sur COM1 et sur
    l'ecran VGA, puis HLT.
}

Program TK1;

{ Compilation : LPC -3K TK1.PAS   (produit le fichier TK1, ELF32)
  Essai : qemu-system-i386 -kernel TK1 -serial stdio -display none -m 64
  (ajouter -device isa-debug-exit,iobase=0xf4,iosize=0x04 pour que QEMU
  s'arrete de lui-meme a la fin) }

Var
  { zone d'amorce : table des pages (alignee a l'execution) et pile }
  BootMem : Array[0..12287] Of LongInt;

{ Point d'entree physique (directive Boot : ni prologue ni epilogue).
  Le chargeur multiboot a deja mis le processeur en mode protege plat,
  pagination coupee, mais ESP n'est pas defini. Ce code construit un
  repertoire de pages qui mappe 16 Mo en identite et en C0000000h, active
  la pagination, saute en haute memoire et appelle le programme principal. }
Procedure KStart; Boot;
Begin
  asm
    cli
    cld
    mov edi, offset BootMem
    sub edi, 0C0000000h
    add edi, 4095
    and edi, 0FFFFF000h
    mov ebx, edi
    mov ecx, 1024
    xor eax, eax
    rep stosd
    mov eax, 3
    mov ecx, 4096
  @fill:
    stosd
    add eax, 4096
    dec ecx
    jnz @fill
    lea eax, [ebx+4099]
    mov [ebx], eax
    mov [ebx+3072], eax
    add eax, 4096
    mov [ebx+4], eax
    mov [ebx+3076], eax
    add eax, 4096
    mov [ebx+8], eax
    mov [ebx+3080], eax
    add eax, 4096
    mov [ebx+12], eax
    mov [ebx+3084], eax
    mov cr3, ebx
    mov eax, cr0
    or eax, 80010000h
    mov cr0, eax
    mov eax, offset @haut
    jmp eax
  @haut:
    lea esp, [ebx+0C0006000h]
    xor ebp, ebp
    call Main
  end;
End;

Procedure Serie(C : LongInt);
Begin
  While (Port[$3FD] And $20) = 0 Do ;
  Port[$3F8] := C;
End;

Procedure Message(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
  Begin
    Serie(Ord(S[K]));
    Mem[0:$B8000 + (K - 1) * 2] := Ord(S[K]);
    Mem[0:$B8001 + (K - 1) * 2] := $1F;
  End;
  Serie(13);
  Serie(10);
End;

Begin
  Message('LINUX-0 OK');
  Port[$F4] := 0;                   { quitte QEMU (isa-debug-exit) }
  asm
    cli
    hlt
  end;
End.
