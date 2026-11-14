{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3K)
  @description: Noyau de test TK2 : assembleur natif 386 (GDT, IDT, LTR,
    interruptions logicielles INT 80h, exception #PF avec code d'erreur,
    CR2, INVLPG), symboles Pascal dans les blocs asm, pagination en haute
    memoire.
}

Program TK2;

{ Compilation : LPC -3K TK2.PAS ; sortie attendue : TK2.OUT }

Const
  Com1    = $3F8;
  SelCode = $08;
  SelData = $10;
  Zero    = 0;

Type
  TDescPtr = Record
    Limit : Word;
    Base  : LongInt;
  End;

Var
  BootMem  : Array[0..12287] Of LongInt;   { zone d'amorce }
  Gdt      : Array[0..5] Of LongInt;       { null, code, donnees }
  Idt      : Array[0..511] Of LongInt;     { 256 portes }
  GdtPtr   : TDescPtr;
  IdtPtr   : TDescPtr;
  Compteur : LongInt;
  CodeErr  : LongInt;
  AdrFaute : LongInt;
  TablePages : Array[0..2047] Of LongInt;  { pour la page de l'essai #PF }
  Pd       : LongInt;                      { adresse physique du repertoire }

{ Amorce physique : voir TK1 }
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
  While (Port[Com1 + 5] And $20) = 0 Do ;
  Port[Com1] := C;
End;

Procedure Ecrire(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do Serie(Ord(S[K]));
End;

Procedure EcrireHexa(V : LongInt);
Var K : LongInt; D : LongInt;
Begin
  For K := 7 DownTo 0 Do
  Begin
    D := (V Shr (K * 4)) And 15;
    If D < 10 Then Serie(48 + D) Else Serie(55 + D);
  End;
End;

{ Descripteur de segment plat 4 Go }
Procedure Segment(N, Acces : LongInt);
Begin
  Gdt[N * 2] := $0000FFFF;
  Gdt[N * 2 + 1] := $00CF0000 Or (Acces Shl 8);
End;

{ INT 80h : incremente le compteur de EAX (lu dans la trame) }
Procedure Int80; Interrupt;
Begin
  Compteur := Compteur + 1;
  asm
    mov eax, [ebp+32]     { EAX empile par PUSHAD }
    add Compteur, eax
  end;
End;

{ #PF : code d'erreur sur la pile ; cree le repertoire (PDE) et la page
  fautifs, puis INVLPG ; l'instruction fautive est ensuite reexecutee }
Procedure Faute14; InterruptErr;
Var Fa, Pt : LongInt;
Begin
  asm
    mov eax, cr2
    mov Fa, eax
    mov eax, [ebp+36]     { code d'erreur }
    mov CodeErr, eax
  end;
  AdrFaute := Fa;
  { table de pages (physique, alignee sur 4 Ko) }
  Pt := (LongInt(@TablePages) - LongInt($C0000000) + 4095) And LongInt($FFFFF000);
  MemL[0:Pd + LongInt($C0000000) + (Fa Shr 22) * 4] := Pt Or 3;
  MemL[0:Pt + LongInt($C0000000) + ((Fa Shr 12) And 1023) * 4] :=
    ($00800000 + (Fa And $003FF000)) Or 3;
  asm
    mov eax, cr2
    invlpg [eax]
  end;
End;

Procedure PortePorte(N, Adresse, Type_ : LongInt);
Begin
  Idt[N * 2] := (SelCode Shl 16) Or (Adresse And $FFFF);
  Idt[N * 2 + 1] := (Adresse And $FFFF0000) Or $8E00;
  If Type_ <> 0 Then Idt[N * 2 + 1] := Idt[N * 2 + 1] Or $6000;  { DPL 3 }
End;

Begin
  { GDT : nulle, code 08h, donnees 10h }
  Gdt[0] := 0; Gdt[1] := 0;
  Segment(1, $9A);
  Segment(2, $92);
  GdtPtr.Limit := 23;
  GdtPtr.Base := LongInt(@Gdt);
  asm
    lgdt [GdtPtr]
    mov ax, SelData
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    jmp SelCode:@suite
  @suite:
  end;
  Ecrire('GDT OK'#13#10);
  { IDT : INT 80h (DPL 3) et #PF }
  PortePorte($80, LongInt(@Int80), 1);
  PortePorte(14, LongInt(@Faute14), 0);
  IdtPtr.Limit := 2047;
  IdtPtr.Base := LongInt(@Idt);
  asm
    lidt [IdtPtr]
  end;
  Compteur := 0;
  asm
    mov eax, 5
    int 80h
    mov eax, 2
    int 80h
  end;
  Ecrire('INT80 compteur=');
  EcrireHexa(Compteur);
  Ecrire(#13#10);
  { CR3 : repertoire des pages de l'amorce }
  Pd := 0;
  asm
    mov eax, cr3
    mov Pd, eax
  end;
  Ecrire('CR3 aligne=');
  If (Pd And $FFF) = 0 Then Ecrire('oui') Else Ecrire('non');
  Ecrire(#13#10);
  { acces a une page absente : #PF, correction, reprise }
  MemL[0:LongInt($C1000000)] := $12345678;
  Ecrire('PF code=');
  EcrireHexa(CodeErr);
  Ecrire(' cr2=');
  EcrireHexa(AdrFaute);
  Ecrire(' valeur=');
  EcrireHexa(MemL[0:LongInt($C1000000)]);
  Ecrire(' phys=');
  EcrireHexa(MemL[0:$00800000]);
  Ecrire(#13#10);
  Ecrire('FIN'#13#10);
  Port[$F4] := 0;
  asm
    cli
    hlt
  end;
End.
