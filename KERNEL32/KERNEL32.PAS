{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3K)
  @description: Noyau LINUX-0 KERNEL32 : noyau Linux 32 bits (80386, mode
                protege) ecrit en Pascal, ABI Linux i386 (INT 80h).
}

Program KERNEL32;

{ Compilation : LPC -3K KERNEL32.PAS   (produit un ELF32 multiboot)

  KERNEL32 est un noyau Linux 32 bits ecrit en un seul fichier, par parties
  numerotees, a la maniere de OS2KRNL. Il est charge physiquement a 00100000h
  (1 Mo) par un chargeur multiboot (GRUB, QEMU -kernel, ou le chargeur ext2
  de LINUX-0) et execute en C0100000h (modele Linux : 3 Go utilisateur,
  1 Go noyau, memoire physique mappee en C0000000h). Il execute des
  programmes Linux i386 (ELF32 statiques) par INT 80h, avec les numeros
  d'appels systeme EXACTS de Linux et des resultats -errno.

  Parties :

    Partie 1  - En-tete multiboot, amorce (pagination), constantes, types
    Partie 2  - Utilitaires : memoire, chaines, nombres, erreurs (errno)
    Partie 3  - Console VGA texte, port serie COM1, journal du noyau (dmesg)
    Partie 4  - Processeur : GDT, TSS, IDT, gabarits d'interruption,
                exceptions, PIC 8259
    Partie 5  - Minuterie PIT (100 Hz), horloge CMOS, heure du systeme
    Partie 6  - Multiboot : ligne de commande, carte memoire E820
    Partie 7  - Memoire physique (buddy), tas du noyau (kmalloc)
    Partie 8  - Pagination, espaces d'adressage, VMA, fautes de page, CoW,
                brk, mmap, munmap, mprotect
    Partie 9  - Taches, ordonnanceur, sommeil/reveil, fork, exit, wait
    Partie 10 - Signaux POSIX, minuteries (alarm, setitimer, nanosleep)
    Partie 11 - Couche bloc : cache de tampons, ramdisk, disque IDE/ATA
    Partie 12 - VFS : inodes, dentries, fichiers, chemins, montages
    Partie 13 - tmpfs/ramfs, devfs en memoire, tubes (pipe, fifo)
    Partie 14 - Terminaux : N_TTY, consoles virtuelles, clavier, ttyS0
    Partie 15 - Chargeur ELF (execve), pile utilisateur (argc/argv/auxv)
    Partie 16 - Appels systeme (INT 80h, table Linux i386)
    Partie 17 - Programmes embarques, init, programme principal

  UNAME : sysname LINUX-0, nodename linux0, release KERNEL32, version 0.1,
  machine i386.

  Carte memoire :
    physique  00000000-000FFFFF  BIOS, VGA (non utilise par l'allocateur)
              00100000-...       image du noyau puis tableaux du noyau
              ...                pages libres (allocateur buddy)
    virtuelle 00000000-BFFFFFFF  espace utilisateur (par processus)
              C0000000-FFFFFFFF  noyau : memoire physique mappee (<=896 Mo)

  Regles du noyau : le noyau n'est pas preemptif ; les interruptions sont
  masquees (IF=0) pendant tout le code du noyau, sauf dans la boucle
  d'attente (HLT). Les gestionnaires d'IRQ ne font que des operations
  courtes (tampons, reveils). Un processus ne perd le processeur que par
  Schedule (sommeil) ou au retour en mode utilisateur (fin de tranche). }

{$R-,S-,I-}

{ ==================================================================== }
{ Partie 1 - En-tete multiboot, amorce, constantes, types              }
{ ==================================================================== }

Const
  KVersion      = '0.1';
  KBase         = $C0000000;     { adresse virtuelle de la memoire physique }
  KImageBase    = $00100000;     { adresse physique du noyau }
  UserTop       = $C0000000;     { fin de l'espace utilisateur }
  PageSize      = 4096;
  MaxPhysMb     = 896;           { memoire physique mappee au plus }
  VideoBase     = $C00B8000;     { VGA texte (memoire physique B8000h) }
  ScrCols       = 80;
  ScrRows       = 25;
  Com1          = $3F8;

  { Selecteurs }
  SelKCode      = $08;
  SelKData      = $10;
  SelUCode      = $1B;
  SelUData      = $23;
  SelTss        = $28;
  SelTls0       = $33;           { 1re entree TLS (GDT 6), DPL 3 }

  { Pagination }
  PgPresent     = $001;
  PgWrite       = $002;
  PgUser        = $004;
  PgAccessed    = $020;
  PgDirty       = $040;

Var
  { Zone des tables de pages d'amorce (alignee a 4 Ko par KStart) et pile
    d'amorce : placees ici, avant tout, pour que KStart les voie }
  BootTabs   : Array[0..28671] Of Byte;
  BootStack  : Array[0..16383] Of Byte;

{ En-tete multiboot (drapeaux 3 : alignement des modules, info memoire).
  Le noyau est un ELF : pas de champs d'adresse. Checksum = -(magic+flags). }
Procedure MbHeader; Assembler;
Begin
  asm
    dd $1BADB002
    dd 3
    dd -464367621
  end;
End;

Procedure KMain; Forward;

{ Point d'entree PHYSIQUE (la pagination est coupee, EAX = 2BADB002h,
  EBX = adresse physique de la structure multiboot). Code independant de
  la position : construit des tables de pages qui mappent les 16 premiers
  Mo en 00000000h et en C0000000h, active la pagination (PG et WP) et saute
  en haute memoire. Les registres du chargeur sont gardes en 6F0h/6F4h. }
Procedure KStart; Assembler;
Begin
  asm
    cli
    cld
    cmp eax,$2BADB002
    jne @nomb
    mov edi,1776
    mov [edi],eax
    mov [edi+4],ebx
  @nomb:
    call @n
  @n:
    pop esi
    lea edi,[@n]
    sub edi,esi
    lea ebx,[BootTabs]
    sub ebx,edi
    add ebx,4095
    and ebx,0FFFFF000h
    mov edi,ebx
    mov ecx,5120
    xor eax,eax
    rep stosd
    lea edi,[ebx+4096]
    mov eax,3
    mov ecx,4096
  @l1:
    mov [edi],eax
    add eax,4096
    add edi,4
    dec ecx
    jnz @l1
    lea eax,[ebx+4099]
    mov ecx,4
    mov edi,ebx
  @l2:
    mov [edi],eax
    mov [edi+3072],eax
    add eax,4096
    add edi,4
    dec ecx
    jnz @l2
    mov cr3,ebx
    mov eax,cr0
    or eax,80010000h
    mov cr0,eax
    lea eax,[@high]
    jmp eax
  @high:
    lea esp,[BootStack]
    add esp,16384
    and esp,0FFFFFFF0h
    xor ebp,ebp
    call KMain
  @hang:
    hlt
    jmp @hang
  end;
End;

{ ==================================================================== }
{ Partie 2 - Utilitaires : memoire, chaines, nombres, erreurs         }
{ ==================================================================== }

Const
  { Codes d'erreur Linux (errno) }
  EPERM = 1;   ENOENT = 2;   ESRCH = 3;    EINTR = 4;    EIO = 5;
  ENXIO = 6;   E2BIG = 7;    ENOEXEC = 8;  EBADF = 9;    ECHILD = 10;
  EAGAIN = 11; ENOMEM = 12;  EACCES = 13;  EFAULT = 14;  ENOTBLK = 15;
  EBUSY = 16;  EEXIST = 17;  EXDEV = 18;   ENODEV = 19;  ENOTDIR = 20;
  EISDIR = 21; EINVAL = 22;  ENFILE = 23;  EMFILE = 24;  ENOTTY = 25;
  ETXTBSY = 26; EFBIG = 27;  ENOSPC = 28;  ESPIPE = 29;  EROFS = 30;
  EMLINK = 31; EPIPE = 32;   EDOM = 33;    ERANGE = 34;  EDEADLK = 35;
  ENAMETOOLONG = 36; ENOLCK = 37; ELIBBAD = 80; ENOSYS = 38; ENOTEMPTY = 39; ELOOP = 40;
  ENOTSOCK = 88; EAFNOSUPPORT = 97; ERESTARTSYS = 512;

Type
  { Cadre empile par le gabarit d'interruption (voir partie 4) }
  PFrame = ^TFrame;
  TFrame = Record
    Gs, Fs, Es, Ds         : LongInt;
    Edi, Esi, Ebp, EspD    : LongInt;
    Ebx, Edx, Ecx, Eax     : LongInt;
    Vec, Err               : LongInt;
    Eip, Cs, Eflags        : LongInt;
    UserEsp, Ss            : LongInt;
  End;

Const
  HexDigits : String[16] = '0123456789ABCDEF';

{ Comparaisons non signees d'adresses }
Function ULt(A, B : LongInt) : Boolean;
Begin
  ULt := (A Xor LongInt($80000000)) < (B Xor LongInt($80000000));
End;

Function ULe(A, B : LongInt) : Boolean;
Begin
  ULe := (A Xor LongInt($80000000)) <= (B Xor LongInt($80000000));
End;

Function UMin(A, B : LongInt) : LongInt;
Begin
  If ULt(A, B) Then UMin := A Else UMin := B;
End;

Function Min(A, B : LongInt) : LongInt;
Begin
  If A < B Then Min := A Else Min := B;
End;

Function Max(A, B : LongInt) : LongInt;
Begin
  If A > B Then Max := A Else Max := B;
End;

{ Copier N octets de Src a Dst (adresses lineaires, zones qui se recouvrent
  admises) }
Procedure MemCopy(Dst, Src, N : LongInt);
Begin
  If N <= 0 Then Exit;
  asm
    push esi
    push edi
    mov esi,Src
    mov edi,Dst
    mov ecx,N
    cld
    cmp esi,edi
    jae @fwd
    add esi,ecx
    add edi,ecx
    dec esi
    dec edi
    std
    rep movsb
    cld
    jmp @done
  @fwd:
    mov edx,ecx
    shr ecx,2
    rep movsd
    mov ecx,edx
    and ecx,3
    rep movsb
  @done:
    pop edi
    pop esi
  end;
End;

{ Remplir N octets a partir de Dst avec l'octet B }
Procedure MemFill(Dst, B, N : LongInt);
Begin
  If N <= 0 Then Exit;
  asm
    push edi
    mov edi,Dst
    mov ecx,N
    mov eax,B
    cld
    rep stosb
    pop edi
  end;
End;

{ Mettre a zero une page (adresse virtuelle alignee) }
Procedure ZeroPage(A : LongInt);
Begin
  asm
    push edi
    mov edi,A
    mov ecx,1024
    xor eax,eax
    cld
    rep stosd
    pop edi
  end;
End;

{ Comparer N octets : 0 si egaux }
Function MemCmp(A, B, N : LongInt) : LongInt;
Var I : LongInt;
Begin
  MemCmp := 0;
  For I := 0 To N - 1 Do
    If Mem[0:A + I] <> Mem[0:B + I] Then
    Begin
      MemCmp := Mem[0:A + I] - Mem[0:B + I];
      Exit;
    End;
End;

{ Longueur d'une chaine ASCIIZ }
Function StrLen0(A : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 0;
  While Mem[0:A + N] <> 0 Do Inc(N);
  StrLen0 := N;
End;

{ Chaine ASCIIZ (adresse lineaire) -> chaine Pascal (255 car. au plus) }
Function PStr(A : LongInt) : String;
Var S : String; N : LongInt;
Begin
  S := '';
  N := 0;
  If A <> 0 Then
    While (Mem[0:A + N] <> 0) And (N < 255) Do
    Begin
      S := S + Chr(Mem[0:A + N]);
      Inc(N);
    End;
  PStr := S;
End;

{ Chaine Pascal -> ASCIIZ a l'adresse A (au plus Max octets, zero compris) }
Procedure PutPStr(A : LongInt; Const S : String; Max : LongInt);
Var I, L : LongInt;
Begin
  L := Length(S);
  If L > Max - 1 Then L := Max - 1;
  For I := 1 To L Do Mem[0:A + I - 1] := Ord(S[I]);
  Mem[0:A + L] := 0;
End;

Function IntStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IntStr := S;
End;

{ Entier non signe en decimal }
Function UStr(V : LongInt) : String;
Var S : String; D : LongInt;
Begin
  If V >= 0 Then
  Begin
    UStr := IntStr(V);
    Exit;
  End;
  { V >= 2^31 : diviser par 10 sans signe }
  D := ((V Shr 1) Div 5);
  S := IntStr(D) + IntStr(V - D * 10);
  UStr := S;
End;

Function HexStr(V : LongInt; Digits : LongInt) : String;
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 1 To Digits Do
  Begin
    S := HexDigits[(V And 15) + 1] + S;
    V := V Shr 4;
  End;
  HexStr := S;
End;

{ Valeur decimale d'une chaine (0 si invalide) }
Function StrVal(Const S : String) : LongInt;
Var I, V, Sg : LongInt;
Begin
  V := 0; Sg := 1; I := 1;
  If (Length(S) > 0) And (S[1] = '-') Then
  Begin
    Sg := -1; I := 2;
  End;
  While (I <= Length(S)) And (S[I] >= '0') And (S[I] <= '9') Do
  Begin
    V := V * 10 + (Ord(S[I]) - 48);
    Inc(I);
  End;
  StrVal := V * Sg;
End;

Function UpStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do
    If (S[I] >= 'a') And (S[I] <= 'z') Then S[I] := Chr(Ord(S[I]) - 32);
  UpStr := S;
End;

Function StrBegins(Const S, P : String) : Boolean;
Begin
  StrBegins := (Length(S) >= Length(P)) And (Copy(S, 1, Length(P)) = P);
End;

{ Position d'un caractere dans une chaine (0 si absent) }
Function CharPos(C : Char; Const S : String) : LongInt;
Var I : LongInt;
Begin
  CharPos := 0;
  For I := 1 To Length(S) Do
    If S[I] = C Then
    Begin
      CharPos := I;
      Exit;
    End;
End;

{ Conversion adresse physique <-> adresse virtuelle du noyau }
Function P2V(P : LongInt) : LongInt;
Begin
  P2V := P + LongInt(KBase);
End;

Function V2P(V : LongInt) : LongInt;
Begin
  V2P := V - LongInt(KBase);
End;

{ Arrondis de pages }
Function PageUp(A : LongInt) : LongInt;
Begin
  PageUp := (A + 4095) And LongInt($FFFFF000);
End;

Function PageDown(A : LongInt) : LongInt;
Begin
  PageDown := A And LongInt($FFFFF000);
End;

{ Operations atomiques sur les bits d'un mot (le noyau n'est pas
  preemptif : pas besoin de LOCK) }
Function BitTest(V, B : LongInt) : Boolean;
Begin
  BitTest := ((V Shr B) And 1) <> 0;
End;

{ ---- Appels indirects : les tables d'operations (VFS, peripheriques) sont
  des tableaux d'adresses de procedures ; CallN empile N arguments (de gauche
  a droite, l'appelant nettoie) puis appelle l'adresse Fn ---- }

Function Call0(Fn : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    mov eax,Fn
    call eax
    mov R,eax
  end;
  Call0 := R;
End;

Function Call1(Fn, A : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    mov eax,A
    push eax
    mov eax,Fn
    call eax
    add esp,4
    mov R,eax
  end;
  Call1 := R;
End;

Function Call2(Fn, A, B : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    mov eax,A
    push eax
    mov eax,B
    push eax
    mov eax,Fn
    call eax
    add esp,8
    mov R,eax
  end;
  Call2 := R;
End;

Function Call3(Fn, A, B, C : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    mov eax,A
    push eax
    mov eax,B
    push eax
    mov eax,C
    push eax
    mov eax,Fn
    call eax
    add esp,12
    mov R,eax
  end;
  Call3 := R;
End;

Function Call4(Fn, A, B, C, D : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    mov eax,A
    push eax
    mov eax,B
    push eax
    mov eax,C
    push eax
    mov eax,D
    push eax
    mov eax,Fn
    call eax
    add esp,16
    mov R,eax
  end;
  Call4 := R;
End;

Function Call5(Fn, A, B, C, D, E : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    mov eax,A
    push eax
    mov eax,B
    push eax
    mov eax,C
    push eax
    mov eax,D
    push eax
    mov eax,E
    push eax
    mov eax,Fn
    call eax
    add esp,20
    mov R,eax
  end;
  Call5 := R;
End;

Function Call6(Fn, A, B, C, D, E, G : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    mov eax,A
    push eax
    mov eax,B
    push eax
    mov eax,C
    push eax
    mov eax,D
    push eax
    mov eax,E
    push eax
    mov eax,G
    push eax
    mov eax,Fn
    call eax
    add esp,24
    mov R,eax
  end;
  Call6 := R;
End;

{ ==================================================================== }
{ Partie 3 - Console VGA texte, port serie COM1, journal du noyau     }
{ ==================================================================== }

Const
  NVc         = 4;              { consoles virtuelles tty1..tty4 }
  LogSize     = 16384;          { journal du noyau (dmesg) : tampon circulaire }
  DefAttr     = $07;

Var
  { Journal du noyau }
  LogBuf      : Array[0..LogSize - 1] Of Byte;
  LogHead     : LongInt;        { prochain octet ecrit (modulo LogSize) }
  LogCount    : LongInt;        { octets valides (<= LogSize) }
  LogToVc     : Boolean;        { copie des messages sur la console 0 }
  SerialOk    : Boolean;

  { Consoles virtuelles : ecran logique de 80x25 mots (car + attribut) }
  VcBuf       : Array[0..NVc * 2000 - 1] Of Word;
  VcRow, VcCol, VcAttr, VcState, VcNPar, VcSavRow, VcSavCol,
  VcSavAttr, VcBold, VcRev, VcCurOn : Array[0..NVc - 1] Of LongInt;
  VcPar       : Array[0..NVc * 8 - 1] Of LongInt;
  ActiveVc    : LongInt;        { console affichee }

Procedure SerialInit;
Begin
  Port[Com1 + 1] := $00;          { pas d'interruption }
  Port[Com1 + 3] := $80;          { DLAB }
  Port[Com1 + 0] := $01;          { 115200 bauds }
  Port[Com1 + 1] := $00;
  Port[Com1 + 3] := $03;          { 8N1 }
  Port[Com1 + 2] := $C7;          { FIFO }
  Port[Com1 + 4] := $0B;          { DTR, RTS, OUT2 }
  SerialOk := Port[Com1 + 5] <> $FF;
End;

Procedure SerialPut(C : LongInt);
Var N : LongInt;
Begin
  If Not SerialOk Then Exit;
  N := 0;
  While ((Port[Com1 + 5] And $20) = 0) And (N < 50000) Do Inc(N);
  Port[Com1] := C;
End;

{ ---- Console VGA ---- }

Procedure VgaCursor;
Var P : LongInt;
Begin
  P := VcRow[ActiveVc] * ScrCols + VcCol[ActiveVc];
  If VcCurOn[ActiveVc] = 0 Then P := 2000 + 40;
  Port[$3D4] := $0F; Port[$3D5] := P And $FF;
  Port[$3D4] := $0E; Port[$3D5] := (P Shr 8) And $FF;
End;

{ Ecrire une cellule (caractere + attribut) dans la console Vc }
Procedure VcCell(Vc, Idx, W : LongInt);
Begin
  VcBuf[Vc * 2000 + Idx] := W;
  If Vc = ActiveVc Then MemW[0:VideoBase + Idx * 2] := W;
End;

Procedure VcClearRange(Vc, A, B : LongInt);
Var I : LongInt;
Begin
  For I := A To B Do VcCell(Vc, I, (DefAttr Shl 8) Or $20);
End;

Procedure VcScroll(Vc : LongInt);
Var I : LongInt;
Begin
  For I := 0 To 2000 - ScrCols - 1 Do
    VcBuf[Vc * 2000 + I] := VcBuf[Vc * 2000 + I + ScrCols];
  For I := 2000 - ScrCols To 1999 Do
    VcBuf[Vc * 2000 + I] := (DefAttr Shl 8) Or $20;
  If Vc = ActiveVc Then
    MemCopy(VideoBase, LongInt(@VcBuf[Vc * 2000]), 4000);
End;

{ Afficher la console Vc a l'ecran (changement de console) }
Procedure VcShow(Vc : LongInt);
Begin
  ActiveVc := Vc;
  MemCopy(VideoBase, LongInt(@VcBuf[Vc * 2000]), 4000);
  VgaCursor;
End;

Procedure VcLineFeed(Vc : LongInt);
Begin
  Inc(VcRow[Vc]);
  If VcRow[Vc] >= ScrRows Then
  Begin
    VcScroll(Vc);
    VcRow[Vc] := ScrRows - 1;
  End;
End;

Function VcColor(N : LongInt) : LongInt;
Begin
  { ordre ANSI (noir, rouge, vert, jaune, bleu, magenta, cyan, blanc) -> VGA }
  Case N Of
    0 : VcColor := 0;  1 : VcColor := 4;  2 : VcColor := 2;  3 : VcColor := 6;
    4 : VcColor := 1;  5 : VcColor := 5;  6 : VcColor := 3;  7 : VcColor := 7;
  Else
    VcColor := 7;
  End;
End;

{ Sequence CSI terminee par F : executer }
Procedure VcCsi(Vc : LongInt; F : LongInt);
Var P0, P1, I, A, B, N : LongInt;
Begin
  P0 := VcPar[Vc * 8]; P1 := VcPar[Vc * 8 + 1];
  Case Chr(F) Of
    'A' : Begin If P0 = 0 Then P0 := 1; Dec(VcRow[Vc], P0); If VcRow[Vc] < 0
        Then VcRow[Vc] := 0; End;
    'B' : Begin If P0 = 0 Then P0 := 1; Inc(VcRow[Vc], P0);
        If VcRow[Vc] > ScrRows - 1 Then VcRow[Vc] := ScrRows - 1; End;
    'C' : Begin If P0 = 0 Then P0 := 1; Inc(VcCol[Vc], P0);
        If VcCol[Vc] > ScrCols - 1 Then VcCol[Vc] := ScrCols - 1; End;
    'D' : Begin If P0 = 0 Then P0 := 1; Dec(VcCol[Vc], P0); If VcCol[Vc] < 0
        Then VcCol[Vc] := 0; End;
    'E' : Begin If P0 = 0 Then P0 := 1; Inc(VcRow[Vc], P0);
        If VcRow[Vc] > ScrRows - 1 Then VcRow[Vc] := ScrRows - 1;
        VcCol[Vc] := 0; End;
    'F' : Begin If P0 = 0 Then P0 := 1; Dec(VcRow[Vc], P0); If VcRow[Vc] < 0
        Then VcRow[Vc] := 0; VcCol[Vc] := 0; End;
    'G', '`' : Begin If P0 > 0 Then Dec(P0); VcCol[Vc] := Min(P0, ScrCols - 1);
        End;
    'd' : Begin If P0 > 0 Then Dec(P0); VcRow[Vc] := Min(P0, ScrRows - 1); End;
    'H', 'f' :
      Begin
        If P0 > 0 Then Dec(P0);
        If P1 > 0 Then Dec(P1);
        VcRow[Vc] := Min(P0, ScrRows - 1);
        VcCol[Vc] := Min(P1, ScrCols - 1);
      End;
    'J' :
      Begin
        A := VcRow[Vc] * ScrCols + VcCol[Vc];
        If P0 = 0 Then VcClearRange(Vc, A, 1999)
        Else If P0 = 1 Then VcClearRange(Vc, 0, A)
        Else VcClearRange(Vc, 0, 1999);
      End;
    'K' :
      Begin
        A := VcRow[Vc] * ScrCols;
        If P0 = 0 Then VcClearRange(Vc, A + VcCol[Vc], A + ScrCols - 1)
        Else If P0 = 1 Then VcClearRange(Vc, A, A + VcCol[Vc])
        Else VcClearRange(Vc, A, A + ScrCols - 1);
      End;
    'L' :
      Begin
        If P0 = 0 Then P0 := 1;
        For N := 1 To P0 Do
        Begin
          For I := 1999 DownTo (VcRow[Vc] + 1) * ScrCols Do
            VcCell(Vc, I, VcBuf[Vc * 2000 + I - ScrCols]);
          VcClearRange(Vc, VcRow[Vc] * ScrCols, VcRow[Vc] * ScrCols + ScrCols
              - 1);
        End;
      End;
    'M' :
      Begin
        If P0 = 0 Then P0 := 1;
        For N := 1 To P0 Do
        Begin
          For I := VcRow[Vc] * ScrCols To 1999 - ScrCols Do
            VcCell(Vc, I, VcBuf[Vc * 2000 + I + ScrCols]);
          VcClearRange(Vc, 2000 - ScrCols, 1999);
        End;
      End;
    '@' :
      Begin
        If P0 = 0 Then P0 := 1;
        A := VcRow[Vc] * ScrCols;
        For I := A + ScrCols - 1 DownTo A + VcCol[Vc] + P0 Do
          VcCell(Vc, I, VcBuf[Vc * 2000 + I - P0]);
        VcClearRange(Vc, A + VcCol[Vc], Min(A + VcCol[Vc] + P0 - 1, A + ScrCols
            - 1));
      End;
    'P' :
      Begin
        If P0 = 0 Then P0 := 1;
        A := VcRow[Vc] * ScrCols;
        For I := A + VcCol[Vc] To A + ScrCols - 1 - P0 Do
          VcCell(Vc, I, VcBuf[Vc * 2000 + I + P0]);
        VcClearRange(Vc, Max(A + VcCol[Vc], A + ScrCols - P0), A + ScrCols - 1);
      End;
    'X' :
      Begin
        If P0 = 0 Then P0 := 1;
        A := VcRow[Vc] * ScrCols + VcCol[Vc];
        VcClearRange(Vc, A, Min(A + P0 - 1, VcRow[Vc] * ScrCols + ScrCols - 1));
      End;
    's' : Begin VcSavRow[Vc] := VcRow[Vc]; VcSavCol[Vc] := VcCol[Vc]; End;
    'u' : Begin VcRow[Vc] := VcSavRow[Vc]; VcCol[Vc] := VcSavCol[Vc]; End;
    'm' :
      Begin
        If VcNPar[Vc] = 0 Then VcNPar[Vc] := 1;
        For I := 0 To VcNPar[Vc] - 1 Do
        Begin
          N := VcPar[Vc * 8 + I];
          If N = 0 Then
          Begin
            VcAttr[Vc] := DefAttr; VcBold[Vc] := 0; VcRev[Vc] := 0;
          End
          Else If N = 1 Then VcBold[Vc] := 1
          Else If N = 22 Then VcBold[Vc] := 0
          Else If N = 7 Then VcRev[Vc] := 1
          Else If N = 27 Then VcRev[Vc] := 0
          Else If (N >= 30) And (N <= 37) Then
            VcAttr[Vc] := (VcAttr[Vc] And $F8) Or VcColor(N - 30)
          Else If N = 39 Then VcAttr[Vc] := (VcAttr[Vc] And $F8) Or 7
          Else If (N >= 40) And (N <= 47) Then
            VcAttr[Vc] := (VcAttr[Vc] And $8F) Or (VcColor(N - 40) Shl 4)
          Else If N = 49 Then VcAttr[Vc] := VcAttr[Vc] And $8F
          Else If (N >= 90) And (N <= 97) Then
            VcAttr[Vc] := (VcAttr[Vc] And $F0) Or VcColor(N - 90) Or 8;
        End;
      End;
    'h', 'l' :
      Begin
        If (VcState[Vc] = 4) And (P0 = 25) Then
          If F = Ord('h') Then VcCurOn[Vc] := 1 Else VcCurOn[Vc] := 0;
      End;
  End;
End;

{ Afficher un caractere sur la console virtuelle Vc }
Procedure VcPutc(Vc, C : LongInt);
Var A : LongInt;
Begin
  C := C And $FF;
  Case VcState[Vc] Of
    1 : { apres ESC }
      Begin
        VcState[Vc] := 0;
        If C = Ord('[') Then
        Begin
          VcState[Vc] := 2; VcNPar[Vc] := 0;
          For A := 0 To 7 Do VcPar[Vc * 8 + A] := 0;
        End
        Else If C = Ord('c') Then
        Begin
          VcAttr[Vc] := DefAttr; VcBold[Vc] := 0; VcRev[Vc] := 0;
          VcClearRange(Vc, 0, 1999); VcRow[Vc] := 0; VcCol[Vc] := 0;
        End
        Else If C = Ord('7') Then
        Begin
          VcSavRow[Vc] := VcRow[Vc]; VcSavCol[Vc] := VcCol[Vc];
        End
        Else If C = Ord('8') Then
        Begin
          VcRow[Vc] := VcSavRow[Vc]; VcCol[Vc] := VcSavCol[Vc];
        End
        Else If C = Ord('M') Then
        Begin
          If VcRow[Vc] > 0 Then Dec(VcRow[Vc]);
        End
        Else If C = Ord('D') Then VcLineFeed(Vc);
      End;
    2, 4 : { dans CSI : parametres }
      Begin
        If (C >= 48) And (C <= 57) Then
        Begin
          If VcNPar[Vc] = 0 Then VcNPar[Vc] := 1;
          A := Vc * 8 + VcNPar[Vc] - 1;
          VcPar[A] := VcPar[A] * 10 + (C - 48);
        End
        Else If C = Ord(';') Then
        Begin
          If VcNPar[Vc] = 0 Then VcNPar[Vc] := 1;
          If VcNPar[Vc] < 8 Then Inc(VcNPar[Vc]);
        End
        Else If C = Ord('?') Then VcState[Vc] := 4
        Else If (C >= 64) And (C <= 126) Then
        Begin
          If VcNPar[Vc] = 0 Then VcNPar[Vc] := 1;
          VcCsi(Vc, C);
          VcState[Vc] := 0;
        End
        Else If C < 32 Then
          VcState[Vc] := 0;
      End;
  Else
    Begin
      Case C Of
        27 : VcState[Vc] := 1;
        13 : VcCol[Vc] := 0;
        10, 11, 12 : VcLineFeed(Vc);
        8  : If VcCol[Vc] > 0 Then Dec(VcCol[Vc]);
        9  : Begin
               VcCol[Vc] := (VcCol[Vc] + 8) And Not 7;
               If VcCol[Vc] >= ScrCols Then VcCol[Vc] := ScrCols - 1;
             End;
        7  : ;
        0, 14, 15, 24, 26, 127 : ;
      Else
        Begin
          If VcCol[Vc] >= ScrCols Then
          Begin
            VcCol[Vc] := 0;
            VcLineFeed(Vc);
          End;
          A := VcAttr[Vc];
          If VcBold[Vc] <> 0 Then A := A Or 8;
          If VcRev[Vc] <> 0 Then A := ((A And $0F) Shl 4) Or ((A Shr 4)
              And $0F);
          VcCell(Vc, VcRow[Vc] * ScrCols + VcCol[Vc], (A Shl 8) Or C);
          Inc(VcCol[Vc]);
        End;
      End;
    End;
  End;
  If Vc = ActiveVc Then VgaCursor;
End;

Procedure InitVcons;
Var V : LongInt;
Begin
  For V := 0 To NVc - 1 Do
  Begin
    VcAttr[V] := DefAttr; VcRow[V] := 0; VcCol[V] := 0; VcState[V] := 0;
    VcBold[V] := 0; VcRev[V] := 0; VcCurOn[V] := 1;
    VcClearRange(V, 0, 1999);
  End;
  ActiveVc := 0;
  VgaCursor;
End;

{ ---- Journal du noyau ---- }

Procedure KPutc(C : LongInt);
Begin
  LogBuf[LogHead] := C;
  LogHead := (LogHead + 1) Mod LogSize;
  If LogCount < LogSize Then Inc(LogCount);
  If C = 10 Then SerialPut(13);
  SerialPut(C);
  If LogToVc Then
  Begin
    If C = 10 Then VcPutc(0, 13);
    VcPutc(0, C);
  End;
End;

Procedure KPrint(Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do KPutc(Ord(S[I]));
End;

Procedure KLog(Const S : String);
Begin
  KPrint(S);
  KPutc(10);
End;

{ Octet I (0 = le plus ancien) du journal }
Function LogByte(I : LongInt) : LongInt;
Begin
  LogByte := LogBuf[(LogHead - LogCount + I + LogSize * 2) Mod LogSize];
End;

{ ==================================================================== }
{ Partie 4 - Processeur : GDT, TSS, IDT, gabarits d'interruption, PIC }
{ ==================================================================== }

Const
  VecSyscall    = $80;
  IsrSlot       = 12;           { taille d'un gabarit d'entree }
  IsrCommonOfs  = 640;          { decalage du code commun dans IsrCode }

Type
  TGate = Record
    OfsLo  : Word;
    Sel    : Word;
    Flags  : Word;
    OfsHi  : Word;
  End;

  TDescPtr = Record
    Limit  : Word;
    Base   : LongInt;
  End;

Var
  Gdt        : Array[0..31] Of LongInt;      { 16 descripteurs }
  GdtPtr     : TDescPtr;
  Idt        : Array[0..255] Of TGate;
  IdtPtr     : TDescPtr;
  Tss        : Array[0..31] Of LongInt;
  IsrCode    : Array[0..1023] Of Byte;       { gabarits generes }
  CodePos    : LongInt;
  IsrCommon  : LongInt;                      { adresse du code commun }
  RetTrapAdr : LongInt;                      { retour d'interruption (iretd) }
  IrqMask    : LongInt;                      { IRQ masquees : bit = 1 }

Const
  ExcNames : Array[0..19] Of String[24] = (
    'Division par zero', 'Debogage', 'NMI', 'Point d''arret',
    'Debordement', 'Hors limites', 'Instruction invalide',
    'Coprocesseur absent', 'Double faute', 'Depassement coproc.',
    'TSS invalide', 'Segment absent', 'Faute de pile',
    'Protection generale', 'Faute de page', 'Reserve',
    'Erreur virgule flott.', 'Alignement', 'Verification machine',
    'Exception SIMD');

Procedure KPanic(Const Msg : String); Forward;
Procedure KTrap(F : LongInt); Forward;

Procedure SetGdt(N, Lo, Hi : LongInt);
Begin
  Gdt[N * 2] := Lo;
  Gdt[N * 2 + 1] := Hi;
End;

Procedure SetGate(N, Addr, Dpl : LongInt);
Begin
  Idt[N].OfsLo := Addr And $FFFF;
  Idt[N].Sel := SelKCode;
  Idt[N].Flags := $8E00 Or (Dpl Shl 13);   { porte d'interruption 32 bits }
  Idt[N].OfsHi := (Addr Shr 16) And $FFFF;
End;

{ ---- Generation des gabarits d'interruption (octets machine) ---- }

Procedure Eb(B : LongInt);
Begin
  IsrCode[CodePos] := B And $FF;
  Inc(CodePos);
End;

Procedure Ed(D : LongInt);
Begin
  Eb(D); Eb(D Shr 8); Eb(D Shr 16); Eb(D Shr 24);
End;

Function HasErrCode(V : LongInt) : Boolean;
Begin
  HasErrCode := (V = 8) Or ((V >= 10) And (V <= 14)) Or (V = 17);
End;

{ Gabarit du vecteur V : empile (code d'erreur factice), le numero du
  vecteur, puis saute au code commun }
Procedure GenStub(V, Slot : LongInt);
Begin
  CodePos := Slot * IsrSlot;
  If Not HasErrCode(V) Then
  Begin
    Eb($6A); Eb($00);                   { push 0 }
  End;
  Eb($68); Ed(V);                       { push V }
  Eb($E9);                              { jmp commun }
  Ed(IsrCommon - (LongInt(@IsrCode[0]) + CodePos + 4));
  While CodePos < (Slot + 1) * IsrSlot Do Eb($90);
End;

{ Code commun : sauvegarde des registres, appel de KTrap(frame), retour }
Procedure GenCommon;
Begin
  CodePos := IsrCommonOfs;
  IsrCommon := LongInt(@IsrCode[0]) + IsrCommonOfs;
  Eb($60);                              { pushad }
  Eb($1E);                              { push ds }
  Eb($06);                              { push es }
  Eb($0F); Eb($A0);                     { push fs }
  Eb($0F); Eb($A8);                     { push gs }
  Eb($66); Eb($B8); Eb($10); Eb($00);   { mov ax,10h }
  Eb($8E); Eb($D8);                     { mov ds,ax }
  Eb($8E); Eb($C0);                     { mov es,ax }
  Eb($8E); Eb($E0);                     { mov fs,ax }
  Eb($8E); Eb($E8);                     { mov gs,ax }
  Eb($FC);                              { cld }
  Eb($54);                              { push esp }
  Eb($B8); Ed(LongInt(@KTrap));         { mov eax,KTrap }
  Eb($FF); Eb($D0);                     { call eax }
  Eb($83); Eb($C4); Eb($04);            { add esp,4 }
  RetTrapAdr := LongInt(@IsrCode[0]) + CodePos;
  Eb($0F); Eb($A9);                     { pop gs }
  Eb($0F); Eb($A1);                     { pop fs }
  Eb($07);                              { pop es }
  Eb($1F);                              { pop ds }
  Eb($61);                              { popad }
  Eb($83); Eb($C4); Eb($08);            { add esp,8 }
  Eb($CF);                              { iretd }
End;

Procedure InitGdt;
Var Base : LongInt;
Begin
  MemFill(LongInt(@Gdt[0]), 0, SizeOf(Gdt));
  SetGdt(1, $0000FFFF, $00CF9A00);        { 08h code noyau }
  SetGdt(2, $0000FFFF, $00CF9200);        { 10h donnees noyau }
  SetGdt(3, $0000FFFF, $00CFFA00);        { 18h code utilisateur (1Bh) }
  SetGdt(4, $0000FFFF, $00CFF200);        { 20h donnees utilisateur (23h) }
  MemFill(LongInt(@Tss[0]), 0, SizeOf(Tss));
  Tss[1] := LongInt(@BootStack[0]) + 16384;   { ESP0 (change a chaque tache) }
  Tss[2] := SelKData;                         { SS0 }
  Tss[25] := (104 Shl 16);                    { pas de table d'E/S }
  Base := LongInt(@Tss[0]);
  SetGdt(5, ((Base And $FFFF) Shl 16) Or 103,
         (Base And LongInt($FF000000)) Or $8900 Or ((Base Shr 16) And $FF));
  GdtPtr.Limit := 16 * 8 - 1;
  GdtPtr.Base := LongInt(@Gdt[0]);
  asm
    lgdt GdtPtr
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov fs,ax
    mov gs,ax
    mov ss,ax
    mov eax,28h
    ltr ax
  end;
End;

{ Programmer les deux 8259A : IRQ 0-7 -> 20h-27h, IRQ 8-15 -> 28h-2Fh }
Procedure InitPic;
Begin
  Port[$20] := $11; Port[$A0] := $11;
  Port[$21] := $20; Port[$A1] := $28;
  Port[$21] := $04; Port[$A1] := $02;
  Port[$21] := $01; Port[$A1] := $01;
  IrqMask := $FFFB;                  { tout masque sauf la cascade }
  Port[$21] := IrqMask And $FF;
  Port[$A1] := (IrqMask Shr 8) And $FF;
End;

Procedure IrqEnable(N : LongInt);
Begin
  IrqMask := IrqMask And Not (1 Shl N);
  If N < 8 Then Port[$21] := IrqMask And $FF
  Else Port[$A1] := (IrqMask Shr 8) And $FF;
End;

Procedure IrqDisable(N : LongInt);
Begin
  IrqMask := IrqMask Or (1 Shl N);
  If N < 8 Then Port[$21] := IrqMask And $FF
  Else Port[$A1] := (IrqMask Shr 8) And $FF;
End;

Procedure IrqAck(N : LongInt);
Begin
  If N >= 8 Then Port[$A0] := $20;
  Port[$20] := $20;
End;

Procedure InitIdt;
Var I : LongInt;
Begin
  GenCommon;
  For I := 0 To 47 Do
  Begin
    GenStub(I, I);
    SetGate(I, LongInt(@IsrCode[0]) + I * IsrSlot, 0);
  End;
  GenStub(VecSyscall, 48);
  SetGate(VecSyscall, LongInt(@IsrCode[0]) + 48 * IsrSlot, 3);
  { les autres vecteurs ne sont pas utilises (faute de protection generale) }
  IdtPtr.Limit := 256 * 8 - 1;
  IdtPtr.Base := LongInt(@Idt[0]);
  asm
    lidt IdtPtr
  end;
End;

{ Regler la pile du noyau pour les entrees depuis le mode utilisateur }
Procedure SetKernelStack(Top : LongInt);
Begin
  Tss[1] := Top;
End;

{ Ecran de debogage d'une exception : registres sur la console et le port
  serie (le journal). }
Procedure DumpFrame(F : PFrame; CR2 : LongInt);
Var Nm : String;
Begin
  If F^.Vec <= 19 Then Nm := ExcNames[F^.Vec] Else Nm := 'Exception';
  KLog('*** ' + Nm + ' (vecteur ' + IntStr(F^.Vec) + ') code=' +
       HexStr(F^.Err, 8) + ' CR2=' + HexStr(CR2, 8));
  KLog('EIP=' + HexStr(F^.Eip, 8) + ' CS=' + HexStr(F^.Cs, 4) +
       ' EFLAGS=' + HexStr(F^.Eflags, 8));
  KLog('EAX=' + HexStr(F^.Eax, 8) + ' EBX=' + HexStr(F^.Ebx, 8) +
       ' ECX=' + HexStr(F^.Ecx, 8) + ' EDX=' + HexStr(F^.Edx, 8));
  KLog('ESI=' + HexStr(F^.Esi, 8) + ' EDI=' + HexStr(F^.Edi, 8) +
       ' EBP=' + HexStr(F^.Ebp, 8) + ' ESP=' + HexStr(F^.UserEsp, 8));
End;

{ Trace des appels (chaine des cadres EBP) pour le debogage }
Procedure Backtrace(Ebp : LongInt);
Var I, Ret : LongInt; S : String;
Begin
  S := 'Trace :';
  For I := 0 To 9 Do
  Begin
    If ULt(Ebp, LongInt($C0000000)) Or Not ULt(Ebp, LongInt($FFFFF000))
        Then Break;
    Ret := MemL[0:Ebp + 4];
    S := S + ' ' + HexStr(Ret, 8);
    Ebp := MemL[0:Ebp];
    If Ebp = 0 Then Break;
  End;
  KLog(S);
End;

Function ReadCr2 : LongInt;
Var V : LongInt;
Begin
  asm
    mov eax,cr2
    mov V,eax
  end;
  ReadCr2 := V;
End;

Function ReadCr3 : LongInt;
Var V : LongInt;
Begin
  asm
    mov eax,cr3
    mov V,eax
  end;
  ReadCr3 := V;
End;

Procedure WriteCr3(V : LongInt);
Begin
  asm
    mov eax,V
    mov cr3,eax
  end;
End;

Procedure FlushTlb;
Begin
  asm
    mov eax,cr3
    mov cr3,eax
  end;
End;

Procedure CpuHalt;
Begin
  asm
    cli
  @h:
    hlt
    jmp @h
  end;
End;

Procedure KPanic(Const Msg : String);
Begin
  asm
    cli
  end;
  LogToVc := True;
  KLog('');
  KLog('NOYAU : panique : ' + Msg);
  CpuHalt;
End;

{ ==================================================================== }
{ Partie 5 - Minuterie PIT, horloge CMOS, heure du systeme            }
{ ==================================================================== }

Const
  HZ          = 100;            { frequence des ticks }
  PitDivisor  = 11932;          { 1193182 / 11932 = 100,0 Hz }

Var
  Jiffies     : LongInt;        { ticks depuis le demarrage }
  BootTime    : LongInt;        { heure Unix au demarrage (horloge CMOS) }
  TimeOffset  : LongInt;        { correction settimeofday (secondes) }

Procedure InitPit;
Begin
  Port[$43] := $36;
  Port[$40] := PitDivisor And $FF;
  Port[$40] := PitDivisor Shr 8;
End;

Function CmosRead(R : LongInt) : LongInt;
Begin
  Port[$70] := R;
  CmosRead := Port[$71];
End;

Function Bcd(V : LongInt) : LongInt;
Begin
  If (CmosRead($0B) And 4) <> 0 Then Bcd := V
  Else Bcd := (V Shr 4) * 10 + (V And 15);
End;

{ Nombre de jours depuis le 1er janvier 1970 (calendrier gregorien) }
Function DaysFromCivil(Y, M, D : LongInt) : LongInt;
Var Era, Yoe, Doy, Doe : LongInt;
Begin
  If M <= 2 Then Dec(Y);
  Era := Y Div 400;
  Yoe := Y - Era * 400;
  If M > 2 Then Doy := (153 * (M - 3) + 2) Div 5 + D - 1
  Else Doy := (153 * (M + 9) + 2) Div 5 + D - 1;
  Doe := Yoe * 365 + Yoe Div 4 - Yoe Div 100 + Doy;
  DaysFromCivil := Era * 146097 + Doe - 719468;
End;

{ Lire l'horloge temps reel : secondes depuis 1970 }
Function ReadRtc : LongInt;
Var N, Sec, Mn, Hr, Dy, Mo, Yr, Cen : LongInt;
Begin
  N := 0;
  While ((CmosRead($0A) And $80) <> 0) And (N < 100000) Do Inc(N);
  Sec := Bcd(CmosRead($00));
  Mn := Bcd(CmosRead($02));
  Hr := Bcd(CmosRead($04) And $7F);
  Dy := Bcd(CmosRead($07));
  Mo := Bcd(CmosRead($08));
  Yr := Bcd(CmosRead($09));
  Cen := Bcd(CmosRead($32));
  If (Cen < 19) Or (Cen > 30) Then Cen := 20;
  Yr := Yr + Cen * 100;
  ReadRtc := DaysFromCivil(Yr, Mo, Dy) * 86400 + Hr * 3600 + Mn * 60 + Sec;
End;

{ Heure Unix courante en secondes }
Function XTime : LongInt;
Begin
  XTime := BootTime + TimeOffset + Jiffies Div HZ;
End;

{ Microsecondes de la seconde courante (resolution 10 ms) }
Function XUsec : LongInt;
Begin
  XUsec := (Jiffies Mod HZ) * (1000000 Div HZ);
End;

Procedure InitTime;
Begin
  Jiffies := 0;
  TimeOffset := 0;
  BootTime := ReadRtc;
  InitPit;
  IrqEnable(0);
End;

{ ==================================================================== }
{ Partie 6 - Multiboot : ligne de commande, carte memoire E820         }
{ ==================================================================== }

Const
  MaxE820 = 64;

Var
  MbMagic, MbInfo  : LongInt;
  MbFlags          : LongInt;
  MemLowKb, MemUpKb : LongInt;
  CmdLine          : String;
  NE820            : LongInt;
  E820Base, E820Len, E820Type : Array[0..MaxE820 - 1] Of LongInt;
  RamTopPhys       : LongInt;      { fin de la memoire utilisable (<= 896 Mo) }
  KeymapName       : String[8];
  RootDev          : String[63];
  InitPath         : String[63];
  UnameRel         : String[63];   { release de uname (KERNEL32 par defaut) }
  BootQuiet        : Boolean;
  KDebug           : Boolean;      { debug : journal des fautes et appels }
  ConsoleSerial    : Boolean;      { console=ttyS0 : /dev/console = port serie }

{ Copier la structure multiboot (laissee par KStart en 6F0h/6F4h) }
Procedure ParseMultiboot;
Var Mm, Len, Pos, Sz, I : LongInt;
Begin
  MbMagic := MemL[0:P2V($6F0)];
  MbInfo := MemL[0:P2V($6F4)];
  CmdLine := '';
  NE820 := 0;
  MemLowKb := 640; MemUpKb := 0;
  If MbMagic <> LongInt($2BADB002) Then
  Begin
    { amorce non multiboot : 15 Mo supposes, ligne de commande vide }
    MemUpKb := 15 * 1024;
    Exit;
  End;
  MbFlags := MemL[0:P2V(MbInfo)];
  If (MbFlags And 1) <> 0 Then
  Begin
    MemLowKb := MemL[0:P2V(MbInfo + 4)];
    MemUpKb := MemL[0:P2V(MbInfo + 8)];
  End;
  If (MbFlags And 4) <> 0 Then
    CmdLine := PStr(P2V(MemL[0:P2V(MbInfo + 16)]));
  If (MbFlags And 64) <> 0 Then
  Begin
    Len := MemL[0:P2V(MbInfo + 44)];
    Mm := MemL[0:P2V(MbInfo + 48)];
    Pos := 0;
    While (Pos < Len) And (NE820 < MaxE820) Do
    Begin
      Sz := MemL[0:P2V(Mm + Pos)];
      If Sz < 20 Then Break;
      E820Base[NE820] := MemL[0:P2V(Mm + Pos + 4)];
      If MemL[0:P2V(Mm + Pos + 8)] <> 0
          Then E820Base[NE820] := LongInt($7FFFFFFF);
      E820Len[NE820] := MemL[0:P2V(Mm + Pos + 12)];
      If MemL[0:P2V(Mm + Pos + 16)] <> 0
          Then E820Len[NE820] := LongInt($7FFFFFFF);
      E820Type[NE820] := MemL[0:P2V(Mm + Pos + 20)];
      Inc(NE820);
      Pos := Pos + Sz + 4;
    End;
  End;
  If NE820 = 0 Then
  Begin
    E820Base[0] := $100000;
    E820Len[0] := MemUpKb * 1024;
    E820Type[0] := 1;
    NE820 := 1;
  End;
  I := 0;
End;

{ Valeur d'un parametre "cle=valeur" de la ligne de commande ('' si absent) }
Function CmdGet(Const Key : String) : String;
Var I, J : LongInt; Tok, Pre : String;
Begin
  CmdGet := '';
  Pre := Key + '=';
  I := 1;
  While I <= Length(CmdLine) Do
  Begin
    While (I <= Length(CmdLine)) And (CmdLine[I] = ' ') Do Inc(I);
    J := I;
    While (J <= Length(CmdLine)) And (CmdLine[J] <> ' ') Do Inc(J);
    Tok := Copy(CmdLine, I, J - I);
    If (Length(Tok) > Length(Key)) And (Copy(Tok, 1, Length(Pre)) = Pre) Then
    Begin
      CmdGet := Copy(Tok, Length(Key) + 2, 255);
      Exit;
    End;
    I := J;
  End;
End;

{ Parametre sans valeur present ? }
Function CmdHas(Const Key : String) : Boolean;
Var I, J : LongInt; Tok : String;
Begin
  CmdHas := False;
  I := 1;
  While I <= Length(CmdLine) Do
  Begin
    While (I <= Length(CmdLine)) And (CmdLine[I] = ' ') Do Inc(I);
    J := I;
    While (J <= Length(CmdLine)) And (CmdLine[J] <> ' ') Do Inc(J);
    Tok := Copy(CmdLine, I, J - I);
    If Tok = Key Then
    Begin
      CmdHas := True;
      Exit;
    End;
    I := J;
  End;
End;

{ Memoire physique : calculer RamTopPhys (haut de la plus grande zone libre
  qui commence a 1 Mo), bornee a 896 Mo et par mem= }
Procedure ComputeRam;
Var I, Top, Lim, E : LongInt; V : String;
Begin
  Top := 0;
  For I := 0 To NE820 - 1 Do
    If (E820Type[I] = 1) And (E820Base[I] <= $100000) Then
    Begin
      E := E820Base[I] + E820Len[I];
      If (E < 0) Or (E > MaxPhysMb * 1024 * 1024) Then E := MaxPhysMb * 1024
          * 1024;
      If E > Top Then Top := E;
    End;
  If Top = 0 Then Top := $100000 + MemUpKb * 1024;
  V := CmdGet('mem');
  If V <> '' Then
  Begin
    Lim := StrVal(V);
    If (V[Length(V)] = 'M') Or (V[Length(V)] = 'm') Then Lim := Lim * 1024
        * 1024
    Else If (V[Length(V)] = 'K') Or (V[Length(V)] = 'k') Then Lim := Lim * 1024;
    If (Lim >= 4 * 1024 * 1024) And (Lim < Top) Then Top := Lim;
  End;
  RamTopPhys := PageDown(Top);
End;

Procedure ParseCmdline;
Begin
  KeymapName := CmdGet('keymap');
  If KeymapName = '' Then KeymapName := 'us';
  RootDev := CmdGet('root');
  InitPath := CmdGet('init');
  UnameRel := CmdGet('uname_release');
  If UnameRel = '' Then
    If CmdHas('uname26') Then UnameRel := '2.6.32' Else UnameRel := 'KERNEL32';
  BootQuiet := CmdHas('quiet');
  KDebug := CmdHas('debug');
  ConsoleSerial := Copy(CmdGet('console'), 1, 5) = 'ttyS0';
End;

{ ==================================================================== }
{ Partie 7 - Memoire physique (buddy), tas du noyau (kmalloc)         }
{ ==================================================================== }

Const
  MaxOrder    = 10;             { blocs de 4 Ko a 4 Mo }
  NClasses    = 7;              { classes de kmalloc : 32 a 2048 octets }
  KMagic      = $4B4D454D;      { 'KMEM' }

Function KernelEnd : LongInt; Forward;
    { fin de l'image (voir la derniere partie) }

Var
  FreeHead    : Array[0..MaxOrder] Of LongInt;
  FreeCnt     : Array[0..MaxOrder] Of LongInt;
  PgFlagsV    : LongInt;        { adresse virtuelle du tableau des drapeaux }
  PgRefV      : LongInt;        { compteurs de references des pages (mots) }
  NPages      : LongInt;        { pages physiques gerees (0 .. RamTop) }
  FreePagesCnt, TotalFreePages : LongInt;
  EarlyPtr    : LongInt;        { allocation d'amorce (adresse physique) }
  KernelEndPhys : LongInt;
  MasterPd    : LongInt;        { repertoire de pages du noyau (virtuel) }
  MasterPdPhys : LongInt;
  ClassFree   : Array[0..NClasses - 1] Of LongInt;
  KHeapBytes  : LongInt;        { statistiques }
  SlabPages   : LongInt;

{ Allocation d'amorce : pages consecutives mises a zero (adresse virtuelle) }
Function EarlyAlloc(Bytes : LongInt) : LongInt;
Var A : LongInt;
Begin
  A := EarlyPtr;
  EarlyPtr := PageUp(EarlyPtr + Bytes);
  MemFill(P2V(A), 0, EarlyPtr - A);
  EarlyAlloc := P2V(A);
End;

Function PgFlag(Pfn : LongInt) : LongInt;
Begin
  PgFlag := Mem[0:PgFlagsV + Pfn];
End;

Procedure SetPgFlag(Pfn, V : LongInt);
Begin
  Mem[0:PgFlagsV + Pfn] := V;
End;

Function PageRef(Addr : LongInt) : LongInt;
Begin
  PageRef := MemW[0:PgRefV + (V2P(Addr) Shr 12) * 2];
End;

Procedure SetPageRef(Addr, V : LongInt);
Begin
  MemW[0:PgRefV + (V2P(Addr) Shr 12) * 2] := V;
End;

Procedure FreeListAdd(Order, Addr : LongInt);
Var H : LongInt;
Begin
  H := FreeHead[Order];
  MemL[0:Addr] := H;
  MemL[0:Addr + 4] := 0;
  If H <> 0 Then MemL[0:H + 4] := Addr;
  FreeHead[Order] := Addr;
  SetPgFlag(V2P(Addr) Shr 12, $80 Or Order);
  Inc(FreeCnt[Order]);
End;

Procedure FreeListDel(Order, Addr : LongInt);
Var N, P : LongInt;
Begin
  N := MemL[0:Addr];
  P := MemL[0:Addr + 4];
  If P <> 0 Then MemL[0:P] := N Else FreeHead[Order] := N;
  If N <> 0 Then MemL[0:N + 4] := P;
  SetPgFlag(V2P(Addr) Shr 12, 0);
  Dec(FreeCnt[Order]);
End;

{ Allouer 2^Order pages contigues : adresse virtuelle du noyau, ou 0 }
Function AllocPages(Order : LongInt) : LongInt;
Var O, A : LongInt;
Begin
  O := Order;
  While (O <= MaxOrder) And (FreeHead[O] = 0) Do Inc(O);
  If O > MaxOrder Then
  Begin
    AllocPages := 0;
    Exit;
  End;
  A := FreeHead[O];
  FreeListDel(O, A);
  While O > Order Do
  Begin
    Dec(O);
    FreeListAdd(O, A + (PageSize Shl O));
  End;
  SetPageRef(A, 1);
  FreePagesCnt := FreePagesCnt - (1 Shl Order);
  AllocPages := A;
End;

Procedure FreePages(Addr, Order : LongInt);
Var Pfn, Bud : LongInt;
Begin
  Pfn := V2P(Addr) Shr 12;
  SetPageRef(Addr, 0);
  FreePagesCnt := FreePagesCnt + (1 Shl Order);
  While Order < MaxOrder Do
  Begin
    Bud := Pfn Xor (1 Shl Order);
    If Bud >= NPages Then Break;
    If PgFlag(Bud) <> ($80 Or Order) Then Break;
    FreeListDel(Order, P2V(Bud Shl 12));
    If Bud < Pfn Then Pfn := Bud;
    Inc(Order);
  End;
  FreeListAdd(Order, P2V(Pfn Shl 12));
End;

{ Page unique remise a zero (donnees utilisateur, tables de pages) }
Function AllocZeroPage : LongInt;
Var A : LongInt;
Begin
  A := AllocPages(0);
  If A <> 0 Then ZeroPage(A);
  AllocZeroPage := A;
End;

{ Ordre minimal pour contenir N octets }
Function OrderFor(N : LongInt) : LongInt;
Var O : LongInt;
Begin
  O := 0;
  While (PageSize Shl O) < N Do Inc(O);
  OrderFor := O;
End;

{ Construire la carte memoire du noyau : tous les octets physiques de 0 a
  RamTop sont mappes en C0000000h + adresse ; remplace les tables d'amorce }
Procedure InitDirectMap;
Var NPt, K, J, Pt : LongInt;
Begin
  NPt := (RamTopPhys + $3FFFFF) Shr 22;
  MasterPd := EarlyAlloc(4096);
  MasterPdPhys := V2P(MasterPd);
  For K := 0 To NPt - 1 Do
  Begin
    Pt := EarlyAlloc(4096);
    MemL[0:MasterPd + (768 + K) * 4] := V2P(Pt) Or 3;
    For J := 0 To 1023 Do
      MemL[0:Pt + J * 4] := ((K Shl 22) + (J Shl 12)) Or 3;
  End;
  { les tables du noyau commun couvrent aussi les PDE hautes restantes :
    allouees a la demande a la creation d'un processus (copie des PDE) }
End;

{ Initialiser le gestionnaire de pages ; a appeler apres ComputeRam }
Procedure InitMemory;
Var I, P, Lo, Hi, O : LongInt;
Begin
  KernelEndPhys := PageUp(V2P(KernelEnd) + 4096);
  EarlyPtr := KernelEndPhys;
  NPages := RamTopPhys Shr 12;
  PgFlagsV := EarlyAlloc(NPages);
  PgRefV := EarlyAlloc(NPages * 2);
  InitDirectMap;
  WriteCr3(MasterPdPhys);
  For I := 0 To MaxOrder Do
  Begin
    FreeHead[I] := 0; FreeCnt[I] := 0;
  End;
  FreePagesCnt := 0;
  For I := 0 To NE820 - 1 Do
    If E820Type[I] = 1 Then
    Begin
      Lo := PageUp(E820Base[I]);
      If Lo < EarlyPtr Then Lo := EarlyPtr;
      Hi := E820Base[I] + E820Len[I];
      If (Hi < 0) Or (Hi > RamTopPhys) Then Hi := RamTopPhys;
      Hi := PageDown(Hi);
      P := Lo Shr 12;
      Hi := Hi Shr 12;
      While P < Hi Do
      Begin
        O := MaxOrder;
        While (O > 0) And (((P And ((1 Shl O) - 1)) <> 0) Or (P + (1
            Shl O) > Hi)) Do Dec(O);
        FreeListAdd(O, P2V(P Shl 12));
        FreePagesCnt := FreePagesCnt + (1 Shl O);
        P := P + (1 Shl O);
      End;
    End;
  TotalFreePages := FreePagesCnt;
End;

{ ---- kmalloc / kfree : classes de 32 a 2048 octets (en-tete de 8 octets),
  au-dela des blocs de pages ---- }

Function ClassOf(Size : LongInt) : LongInt;
Var C, S : LongInt;
Begin
  C := 0;
  S := 32;
  While (S - 8 < Size) And (C < NClasses) Do
  Begin
    S := S Shl 1;
    Inc(C);
  End;
  ClassOf := C;
End;

Function KMalloc(Size : LongInt) : LongInt;
Var C, A, S, N, I, Blk : LongInt;
Begin
  KMalloc := 0;
  If Size <= 0 Then Size := 1;
  C := ClassOf(Size);
  If C >= NClasses Then
  Begin
    { gros bloc : pages }
    C := OrderFor(Size + 8);
    If C > MaxOrder Then Exit;
    A := AllocPages(C);
    If A = 0 Then Exit;
    MemL[0:A] := 100 + C;
    MemL[0:A + 4] := KMagic;
    KHeapBytes := KHeapBytes + (PageSize Shl C);
    KMalloc := A + 8;
    Exit;
  End;
  If ClassFree[C] = 0 Then
  Begin
    A := AllocPages(0);
    If A = 0 Then Exit;
    Inc(SlabPages);
    S := 32 Shl C;
    N := PageSize Div S;
    For I := N - 1 DownTo 0 Do
    Begin
      Blk := A + I * S;
      MemL[0:Blk] := ClassFree[C];
      MemL[0:Blk + 4] := KMagic;
      ClassFree[C] := Blk;
    End;
  End;
  A := ClassFree[C];
  ClassFree[C] := MemL[0:A];
  MemL[0:A] := C;
  MemL[0:A + 4] := KMagic;
  KHeapBytes := KHeapBytes + (32 Shl C);
  KMalloc := A + 8;
End;

Function KMallocZ(Size : LongInt) : LongInt;
Var A : LongInt;
Begin
  A := KMalloc(Size);
  If A <> 0 Then MemFill(A, 0, Size);
  KMallocZ := A;
End;

Procedure KFree(P : LongInt);
Var A, C : LongInt;
Begin
  If P = 0 Then Exit;
  A := P - 8;
  If MemL[0:A + 4] <> KMagic Then
    KPanic('kfree : bloc corrompu ' + HexStr(P, 8));
  C := MemL[0:A];
  MemL[0:A + 4] := 0;
  If C >= 100 Then
  Begin
    KHeapBytes := KHeapBytes - (PageSize Shl (C - 100));
    FreePages(A, C - 100);
  End
  Else
  Begin
    KHeapBytes := KHeapBytes - (32 Shl C);
    MemL[0:A] := ClassFree[C];
    MemL[0:A + 4] := KMagic;
    ClassFree[C] := A;
  End;
End;

{ ==================================================================== }
{ Partie 8 - Pagination, espaces d'adressage, VMA, fautes de page     }
{ ==================================================================== }

Const
  PROT_READ = 1; PROT_WRITE = 2; PROT_EXEC = 4;
  MAP_SHARED = $01; MAP_PRIVATE = $02; MAP_FIXED = $10; MAP_ANONYMOUS = $20;
  MAP_GROWSDOWN = $100;
  VmStack          = $10000;        { VMA de pile (croit vers le bas) }
  VmHeap           = $20000;
  TaskUnmappedBase = $40000000;
  DefStackLimit    = 8 * 1024 * 1024;
  StackReserve     = 16 * 1024 * 1024;   { zone laissee a la pile }

Type
  PVma = ^TVma;
  TVma = Record
    Start, Fin   : LongInt;      { [Start, Fin) }
    Prot, Flags  : LongInt;
    Ino          : LongInt;      { inode du fichier mappe (0 : anonyme) }
    Off          : LongInt;      { decalage dans le fichier de Start }
    FLen         : LongInt;      { octets du fichier mappes (le reste est nul) }
    Next         : PVma;
  End;

  PMm = ^TMm;
  TMm = Record
    Pgd, PgdPhys : LongInt;      { repertoire de pages (virtuel, physique) }
    Vma          : PVma;         { liste triee par adresse }
    Count        : LongInt;      { references (clone avec CLONE_VM) }
    StartCode, EndCode, StartData, EndData : LongInt;
    StartBrk, Brk, StartStack    : LongInt;
    ArgStart, ArgEnd, EnvStart, EnvEnd : LongInt;
    MmapBase     : LongInt;
    Rss, TotalVm : LongInt;      { pages }
    StackLimit   : LongInt;      { octets }
    DataLimit    : LongInt;
  End;

Var
  CurMm        : PMm;            { espace d'adressage courant }
  FaultsTotal  : LongInt;        { statistiques }

{ ---- Procedures anticipees (VFS, taches) ---- }
Function InodeRef(I : LongInt) : LongInt; Forward;
Procedure InodePut(I : LongInt); Forward;
Function InodeReadAt(I, Buf, Pos, Cnt : LongInt) : LongInt; Forward;

{ ---- Comptage des references de pages ---- }

Procedure PageGet(Addr : LongInt);
Begin
  SetPageRef(Addr, PageRef(Addr) + 1);
End;

Procedure PagePut(Addr : LongInt);
Var R : LongInt;
Begin
  R := PageRef(Addr) - 1;
  If R <= 0 Then FreePages(Addr, 0)
  Else SetPageRef(Addr, R);
End;

{ ---- Repertoires et tables de pages ---- }

Function PgdNew : LongInt;
Var P, I : LongInt;
Begin
  P := AllocZeroPage;
  If P <> 0 Then
    For I := 768 To 1023 Do
      MemL[0:P + I * 4] := MemL[0:MasterPd + I * 4];
  PgdNew := P;
End;

{ Adresse virtuelle du PTE de Va (0 si absent et Create faux) }
Function PtePtr(Mm : PMm; Va : LongInt; Create : Boolean) : LongInt;
Var Pdi, Pde, Pt : LongInt;
Begin
  Pdi := (Va Shr 22) And 1023;
  Pde := MemL[0:Mm^.Pgd + Pdi * 4];
  If (Pde And 1) = 0 Then
  Begin
    If Not Create Then
    Begin
      PtePtr := 0;
      Exit;
    End;
    Pt := AllocZeroPage;
    If Pt = 0 Then
    Begin
      PtePtr := 0;
      Exit;
    End;
    MemL[0:Mm^.Pgd + Pdi * 4] := V2P(Pt) Or 7;
  End
  Else
    Pt := P2V(Pde And LongInt($FFFFF000));
  PtePtr := Pt + ((Va Shr 12) And 1023) * 4;
End;

Function MmNew : PMm;
Var Mm : PMm;
Begin
  MmNew := Nil;
  Mm := Pointer(KMallocZ(SizeOf(TMm)));
  If Mm = Nil Then Exit;
  Mm^.Pgd := PgdNew;
  If Mm^.Pgd = 0 Then
  Begin
    KFree(LongInt(Mm));
    Exit;
  End;
  Mm^.PgdPhys := V2P(Mm^.Pgd);
  Mm^.Count := 1;
  Mm^.MmapBase := TaskUnmappedBase;
  Mm^.StackLimit := DefStackLimit;
  MmNew := Mm;
End;

{ ---- VMA ---- }

Function FindVma(Mm : PMm; Addr : LongInt) : PVma;
Var V : PVma;
Begin
  V := Mm^.Vma;
  While V <> Nil Do
  Begin
    If ULt(Addr, V^.Fin) Then
    Begin
      If ULe(V^.Start, Addr) Then FindVma := V Else FindVma := Nil;
      Exit;
    End;
    V := V^.Next;
  End;
  FindVma := Nil;
End;

{ Premiere VMA dont la fin est apres Addr (pour la pile et mmap) }
Function FindVmaAfter(Mm : PMm; Addr : LongInt) : PVma;
Var V : PVma;
Begin
  V := Mm^.Vma;
  While V <> Nil Do
  Begin
    If ULt(Addr, V^.Fin) Then
    Begin
      FindVmaAfter := V;
      Exit;
    End;
    V := V^.Next;
  End;
  FindVmaAfter := Nil;
End;

Procedure VmaInsert(Mm : PMm; V : PVma);
Var P, Q : PVma;
Begin
  P := Mm^.Vma;
  Q := Nil;
  While (P <> Nil) And ULt(P^.Start, V^.Start) Do
  Begin
    Q := P;
    P := P^.Next;
  End;
  V^.Next := P;
  If Q = Nil Then Mm^.Vma := V Else Q^.Next := V;
  Mm^.TotalVm := Mm^.TotalVm + ((V^.Fin - V^.Start) Shr 12);
End;

Function VmaNew(Start, Fin, Prot, Flags : LongInt) : PVma;
Var V : PVma;
Begin
  V := Pointer(KMallocZ(SizeOf(TVma)));
  If V <> Nil Then
  Begin
    V^.Start := Start; V^.Fin := Fin; V^.Prot := Prot; V^.Flags := Flags;
  End;
  VmaNew := V;
End;

{ Drapeaux d'un PTE pour une VMA }
Function PteFlags(Prot : LongInt; Writable : Boolean) : LongInt;
Begin
  PteFlags := PgPresent Or PgUser Or PgAccessed;
  If Writable And ((Prot And PROT_WRITE) <> 0) Then
    PteFlags := PteFlags Or PgWrite Or PgDirty;
End;

{ Demander une page libre pour l'utilisateur ; 0 si memoire epuisee }
Function UserPage : LongInt;
Begin
  UserPage := AllocZeroPage;
End;

{ Defaire les mappages [A, B) (pages presentes) }
Procedure MmUnmapPages(Mm : PMm; A, B : LongInt);
Var Va, P, Pte : LongInt;
Begin
  Va := PageDown(A);
  While ULt(Va, B) Do
  Begin
    P := PtePtr(Mm, Va, False);
    If P = 0 Then
      Va := (Va + $400000) And LongInt($FFC00000)
    Else
    Begin
      Pte := MemL[0:P];
      If (Pte And 1) <> 0 Then
      Begin
        PagePut(P2V(Pte And LongInt($FFFFF000)));
        MemL[0:P] := 0;
        Dec(Mm^.Rss);
      End;
      Va := Va + PageSize;
    End;
    If Va = 0 Then Break;
  End;
  FlushTlb;
End;

{ Liberer toutes les tables de pages utilisateur vides... et le repertoire }
Procedure MmFreeTables(Mm : PMm);
Var I, Pde : LongInt;
Begin
  For I := 0 To 767 Do
  Begin
    Pde := MemL[0:Mm^.Pgd + I * 4];
    If (Pde And 1) <> 0 Then
    Begin
      FreePages(P2V(Pde And LongInt($FFFFF000)), 0);
      MemL[0:Mm^.Pgd + I * 4] := 0;
    End;
  End;
End;

Procedure VmaFree(V : PVma);
Begin
  If V^.Ino <> 0 Then InodePut(V^.Ino);
  KFree(LongInt(V));
End;

{ Liberer un espace d'adressage (dernier utilisateur) }
Procedure MmRelease(Mm : PMm);
Var V, N : PVma;
Begin
  Dec(Mm^.Count);
  If Mm^.Count > 0 Then Exit;
  V := Mm^.Vma;
  While V <> Nil Do
  Begin
    N := V^.Next;
    MmUnmapPages(Mm, V^.Start, V^.Fin);
    VmaFree(V);
    V := N;
  End;
  Mm^.Vma := Nil;
  MmFreeTables(Mm);
  FreePages(Mm^.Pgd, 0);
  KFree(LongInt(Mm));
End;

{ ---- Fautes de page ---- }

{ Resoudre une faute a l'adresse Addr. Retour : 0 resolue, 1 SEGV_MAPERR,
  2 SEGV_ACCERR, 3 plus de memoire }
Function MmFault(Mm : PMm; Addr : LongInt; Write : Boolean;
    Esp : LongInt) : LongInt;
Var V, Nx : PVma; P, Pte, Pg, New, Pos, N, Page : LongInt;
Begin
  Inc(FaultsTotal);
  MmFault := 1;
  If Not ULt(Addr, UserTop) Then Exit;
  V := FindVma(Mm, Addr);
  If V = Nil Then
  Begin
    { croissance de la pile }
    Nx := FindVmaAfter(Mm, Addr);
    If (Nx = Nil) Or ((Nx^.Flags And VmStack) = 0) Then Exit;
    If (Esp <> 0) And ULt(Addr + 65536 + 128, Esp) Then Exit;
    If (Nx^.Fin - PageDown(Addr)) > Mm^.StackLimit Then Exit;
    P := 0;
    { ne pas rejoindre la VMA precedente }
    If (Mm^.Vma <> Nx) Then
    Begin
      V := Mm^.Vma;
      While (V <> Nil) And (V^.Next <> Nx) Do V := V^.Next;
      If (V <> Nil) And ULt(PageDown(Addr), V^.Fin) Then Exit;
    End;
    Mm^.TotalVm := Mm^.TotalVm + ((Nx^.Start - PageDown(Addr)) Shr 12);
    Nx^.Start := PageDown(Addr);
    If (Nx^.Ino <> 0) Then Nx^.Off := 0;
    V := Nx;
  End;
  If Write And ((V^.Prot And PROT_WRITE) = 0) Then
  Begin
    MmFault := 2;
    Exit;
  End;
  If (V^.Prot And (PROT_READ Or PROT_EXEC Or PROT_WRITE)) = 0 Then
  Begin
    MmFault := 2;
    Exit;
  End;
  Page := PageDown(Addr);
  P := PtePtr(Mm, Page, True);
  If P = 0 Then
  Begin
    MmFault := 3;
    Exit;
  End;
  Pte := MemL[0:P];
  If (Pte And 1) <> 0 Then
  Begin
    If Write And ((Pte And PgWrite) = 0) Then
    Begin
      Pg := P2V(Pte And LongInt($FFFFF000));
      If (PageRef(Pg) = 1) Or ((V^.Flags And MAP_SHARED) <> 0) Then
        MemL[0:P] := Pte Or PgWrite Or PgDirty Or PgAccessed
      Else
      Begin
        New := AllocPages(0);
        If New = 0 Then
        Begin
          MmFault := 3;
          Exit;
        End;
        MemCopy(New, Pg, PageSize);
        MemL[0:P] := V2P(New) Or (Pte And $FFF) Or PgWrite Or PgDirty;
        PagePut(Pg);
      End;
    End;
    FlushTlb;
    MmFault := 0;
    Exit;
  End;
  { page absente : la creer }
  New := AllocZeroPage;
  If New = 0 Then
  Begin
    MmFault := 3;
    Exit;
  End;
  If V^.Ino <> 0 Then
  Begin
    Pos := Page - V^.Start;
    N := V^.FLen - Pos;
    If N > PageSize Then N := PageSize;
    If N > 0 Then InodeReadAt(V^.Ino, New, V^.Off + Pos, N);
  End;
  MemL[0:P] := V2P(New) Or PteFlags(V^.Prot, True);
  Inc(Mm^.Rss);
  FlushTlb;
  MmFault := 0;
End;

{ Verifier (et rendre presentes) les pages [Addr, Addr+Len) pour le noyau }
Function EnsureUser(Addr, Len : LongInt; Write : Boolean) : Boolean;
Var A, E, P, Pte : LongInt;
Begin
  EnsureUser := False;
  If Len <= 0 Then
  Begin
    EnsureUser := True;
    Exit;
  End;
  E := Addr + Len;
  If ULt(E, Addr) Or ULt(UserTop, E) Then Exit;
  A := PageDown(Addr);
  While ULt(A, E) Do
  Begin
    P := PtePtr(CurMm, A, False);
    If P <> 0 Then Pte := MemL[0:P] Else Pte := 0;
    If ((Pte And 1) = 0) Or (Write And ((Pte And PgWrite) = 0)) Then
      If MmFault(CurMm, A, Write, 0) <> 0 Then Exit;
    A := A + PageSize;
  End;
  EnsureUser := True;
End;

{ Copies entre le noyau et l'utilisateur : 0 ou -EFAULT }
Function CopyFromUser(Dst, Src, N : LongInt) : LongInt;
Begin
  If Not EnsureUser(Src, N, False) Then
  Begin
    CopyFromUser := -EFAULT;
    Exit;
  End;
  MemCopy(Dst, Src, N);
  CopyFromUser := 0;
End;

Function CopyToUser(Dst, Src, N : LongInt) : LongInt;
Begin
  If Not EnsureUser(Dst, N, True) Then
  Begin
    CopyToUser := -EFAULT;
    Exit;
  End;
  MemCopy(Dst, Src, N);
  CopyToUser := 0;
End;

{ Ecrire un mot de 32 bits a une adresse utilisateur }
Function PutUserL(Addr, V : LongInt) : LongInt;
Begin
  If Not EnsureUser(Addr, 4, True) Then
  Begin
    PutUserL := -EFAULT;
    Exit;
  End;
  MemL[0:Addr] := V;
  PutUserL := 0;
End;

Function GetUserL(Addr : LongInt; Var V : LongInt) : LongInt;
Begin
  If Not EnsureUser(Addr, 4, False) Then
  Begin
    GetUserL := -EFAULT;
    Exit;
  End;
  V := MemL[0:Addr];
  GetUserL := 0;
End;

{ Chaine ASCIIZ utilisateur -> chaine Pascal : 0, -EFAULT ou -ENAMETOOLONG }
Function GetUserStr(Addr : LongInt; Var S : String) : LongInt;
Var N, C : LongInt;
Begin
  S := '';
  GetUserStr := -EFAULT;
  If Addr = 0 Then Exit;
  N := 0;
  While True Do
  Begin
    If (N = 0) Or (((Addr + N) And $FFF) = 0) Then
      If Not EnsureUser(Addr + N, 1, False) Then Exit;
    C := Mem[0:Addr + N];
    If C = 0 Then Break;
    If N >= 255 Then
    Begin
      GetUserStr := -ENAMETOOLONG;
      Exit;
    End;
    S := S + Chr(C);
    Inc(N);
  End;
  GetUserStr := 0;
End;

{ ---- Operations sur les zones ---- }

{ Couper la VMA V en At : V devient [Start, At), la nouvelle [At, Fin) }
Function VmaSplit(Mm : PMm; V : PVma; At : LongInt) : PVma;
Var W : PVma;
Begin
  W := VmaNew(At, V^.Fin, V^.Prot, V^.Flags);
  VmaSplit := W;
  If W = Nil Then Exit;
  W^.Ino := V^.Ino;
  If W^.Ino <> 0 Then
  Begin
    InodeRef(W^.Ino);
    W^.Off := V^.Off + (At - V^.Start);
    W^.FLen := V^.FLen - (At - V^.Start);
    If W^.FLen < 0 Then W^.FLen := 0;
    If V^.FLen > At - V^.Start Then V^.FLen := At - V^.Start;
  End;
  V^.Fin := At;
  W^.Next := V^.Next;
  V^.Next := W;
End;

{ Supprimer les mappages [A, B) : decoupe les VMA, libere les pages }
Function MmUnmap(Mm : PMm; A, B : LongInt) : LongInt;
Var V, N, Q, W : PVma;
Begin
  MmUnmap := 0;
  V := Mm^.Vma;
  Q := Nil;
  While V <> Nil Do
  Begin
    N := V^.Next;
    If ULe(B, V^.Start) Then Break;
    If ULe(V^.Fin, A) Then
    Begin
      Q := V;
      V := N;
      Continue;
    End;
    { chevauchement }
    If ULt(V^.Start, A) Then
    Begin
      { garder la partie gauche, traiter le reste }
      W := VmaSplit(Mm, V, A);
      If W = Nil Then
      Begin
        MmUnmap := -ENOMEM;
        Exit;
      End;
      Q := V;
      V := W;
      N := V^.Next;
    End;
    If ULt(B, V^.Fin) Then
    Begin
      W := VmaSplit(Mm, V, B);
      If W = Nil Then
      Begin
        MmUnmap := -ENOMEM;
        Exit;
      End;
      N := W;
    End;
    { V est entierement dans [A, B) }
    MmUnmapPages(Mm, V^.Start, V^.Fin);
    Mm^.TotalVm := Mm^.TotalVm - ((V^.Fin - V^.Start) Shr 12);
    If Q = Nil Then Mm^.Vma := N Else Q^.Next := N;
    VmaFree(V);
    V := N;
  End;
End;

{ Changer la protection de [A, B) }
Function MmProtect(Mm : PMm; A, B, Prot : LongInt) : LongInt;
Var V, W : PVma; Va, P, Pte : LongInt;
Begin
  MmProtect := 0;
  V := Mm^.Vma;
  While V <> Nil Do
  Begin
    If ULe(B, V^.Start) Then Break;
    If ULt(A, V^.Fin) Then
    Begin
      If ULt(V^.Start, A) Then
      Begin
        W := VmaSplit(Mm, V, A);
        If W = Nil Then
        Begin
          MmProtect := -ENOMEM;
          Exit;
        End;
        V := W;
      End;
      If ULt(B, V^.Fin) Then
      Begin
        W := VmaSplit(Mm, V, B);
        If W = Nil Then
        Begin
          MmProtect := -ENOMEM;
          Exit;
        End;
      End;
      V^.Prot := Prot;
      Va := V^.Start;
      While ULt(Va, V^.Fin) Do
      Begin
        P := PtePtr(Mm, Va, False);
        If P <> 0 Then
        Begin
          Pte := MemL[0:P];
          If (Pte And 1) <> 0 Then
            If (Prot And PROT_WRITE) = 0 Then MemL[0:P] := Pte And Not PgWrite;
        End;
        Va := Va + PageSize;
      End;
    End;
    V := V^.Next;
  End;
  FlushTlb;
End;

{ Chercher Len octets libres a partir de MmapBase }
Function FindFreeArea(Mm : PMm; Len : LongInt) : LongInt;
Var A : LongInt; V : PVma; Limit : LongInt;
Begin
  Limit := UserTop - StackReserve;
  A := Mm^.MmapBase;
  V := Mm^.Vma;
  While V <> Nil Do
  Begin
    If ULe(V^.Fin, A) Then V := V^.Next
    Else If ULe(A + Len, V^.Start) Then Break
    Else
    Begin
      A := V^.Fin;
      V := V^.Next;
    End;
  End;
  If ULt(Limit, A + Len) Or ULt(A + Len, A) Then FindFreeArea := 0
  Else FindFreeArea := A;
End;

{ mmap : Ino/Off pour un fichier (Ino = 0 si anonyme). Retourne l'adresse
  ou -errno }
Function MmMap(Mm : PMm; Addr, Len, Prot, Flags, Ino, Off,
    FSize : LongInt) : LongInt;
Var V, NV : PVma; A, R : LongInt;
Begin
  If Len <= 0 Then
  Begin
    MmMap := -EINVAL;
    Exit;
  End;
  Len := PageUp(Len);
  If (Flags And MAP_FIXED) <> 0 Then
  Begin
    If ((Addr And $FFF) <> 0) Or Not ULt(Addr, UserTop) Or ULt(UserTop, Addr
        + Len) Then
    Begin
      MmMap := -EINVAL;
      Exit;
    End;
    R := MmUnmap(Mm, Addr, Addr + Len);
    If R < 0 Then
    Begin
      MmMap := R;
      Exit;
    End;
    A := Addr;
  End
  Else
  Begin
    A := 0;
    If (Addr <> 0) And ((Addr And $FFF) = 0) And ULt(Addr + Len, UserTop) And
       ULe(Mm^.MmapBase, Addr) Then
    Begin
      NV := FindVmaAfter(Mm, Addr);
      If (NV = Nil) Or ULe(Addr + Len, NV^.Start) Then A := Addr;
    End;
    If A = 0 Then A := FindFreeArea(Mm, Len);
    If A = 0 Then
    Begin
      MmMap := -ENOMEM;
      Exit;
    End;
  End;
  V := VmaNew(A, A + Len, Prot, Flags);
  If V = Nil Then
  Begin
    MmMap := -ENOMEM;
    Exit;
  End;
  If Ino <> 0 Then
  Begin
    V^.Ino := InodeRef(Ino);
    V^.Off := Off;
    V^.FLen := FSize;
  End;
  VmaInsert(Mm, V);
  MmMap := A;
End;

{ brk : retourne la nouvelle fin du tas (ou l'ancienne si refus) }
Function MmBrk(Mm : PMm; NewBrk : LongInt) : LongInt;
Var V : PVma; OldEnd, NewEnd : LongInt;
Begin
  MmBrk := Mm^.Brk;
  If ULt(NewBrk, Mm^.StartBrk) Then Exit;
  If ULt(Mm^.StartBrk + Mm^.DataLimit, NewBrk) And (Mm^.DataLimit <> 0)
      Then Exit;
  If ULt(TaskUnmappedBase - 1, NewBrk) Then Exit;
  NewEnd := PageUp(NewBrk);
  OldEnd := PageUp(Mm^.Brk);
  If NewEnd = OldEnd Then
  Begin
    Mm^.Brk := NewBrk;
    MmBrk := NewBrk;
    Exit;
  End;
  V := FindVma(Mm, Mm^.StartBrk);
  If ULt(NewEnd, OldEnd) Then
  Begin
    { reduire }
    MmUnmap(Mm, NewEnd, OldEnd);
  End
  Else
  Begin
    { agrandir : ne pas heurter une autre VMA }
    V := FindVmaAfter(Mm, OldEnd);
    If (V <> Nil) And ULt(V^.Start, NewEnd) Then Exit;
    If (V <> Nil) And (V^.Start = OldEnd) And (V^.Flags = (MAP_PRIVATE
        Or MAP_ANONYMOUS Or VmHeap)) Then
    Begin
      Mm^.TotalVm := Mm^.TotalVm + ((NewEnd - V^.Start) Shr 12);
    End;
    V := VmaNew(OldEnd, NewEnd, PROT_READ Or PROT_WRITE, MAP_PRIVATE
        Or MAP_ANONYMOUS Or VmHeap);
    If V = Nil Then Exit;
    VmaInsert(Mm, V);
  End;
  Mm^.Brk := NewBrk;
  MmBrk := NewBrk;
End;

{ Dupliquer un espace d'adressage pour fork (copie sur ecriture) }
Function MmDup(Old : PMm) : PMm;
Var New : PMm; V, W, Last : PVma; Va, P, Q, Pte, Pg : LongInt;
Begin
  MmDup := Nil;
  New := MmNew;
  If New = Nil Then Exit;
  New^.StartCode := Old^.StartCode; New^.EndCode := Old^.EndCode;
  New^.StartData := Old^.StartData; New^.EndData := Old^.EndData;
  New^.StartBrk := Old^.StartBrk; New^.Brk := Old^.Brk;
  New^.StartStack := Old^.StartStack;
  New^.ArgStart := Old^.ArgStart; New^.ArgEnd := Old^.ArgEnd;
  New^.EnvStart := Old^.EnvStart; New^.EnvEnd := Old^.EnvEnd;
  New^.MmapBase := Old^.MmapBase;
  New^.StackLimit := Old^.StackLimit;
  New^.DataLimit := Old^.DataLimit;
  Last := Nil;
  V := Old^.Vma;
  While V <> Nil Do
  Begin
    W := VmaNew(V^.Start, V^.Fin, V^.Prot, V^.Flags);
    If W = Nil Then
    Begin
      MmRelease(New);
      Exit;
    End;
    If V^.Ino <> 0 Then
    Begin
      W^.Ino := InodeRef(V^.Ino);
      W^.Off := V^.Off;
      W^.FLen := V^.FLen;
    End;
    If Last = Nil Then New^.Vma := W Else Last^.Next := W;
    Last := W;
    New^.TotalVm := New^.TotalVm + ((W^.Fin - W^.Start) Shr 12);
    { copier les pages presentes }
    Va := V^.Start;
    While ULt(Va, V^.Fin) Do
    Begin
      P := PtePtr(Old, Va, False);
      If P = 0 Then
        Va := (Va + $400000) And LongInt($FFC00000)
      Else
      Begin
        Pte := MemL[0:P];
        If (Pte And 1) <> 0 Then
        Begin
          Q := PtePtr(New, Va, True);
          If Q = 0 Then
          Begin
            MmRelease(New);
            Exit;
          End;
          Pg := P2V(Pte And LongInt($FFFFF000));
          If ((V^.Flags And MAP_SHARED) = 0) And ((Pte And PgWrite) <> 0) Then
          Begin
            Pte := Pte And Not PgWrite;
            MemL[0:P] := Pte;
          End;
          MemL[0:Q] := Pte;
          PageGet(Pg);
          Inc(New^.Rss);
        End;
        Va := Va + PageSize;
      End;
      If Va = 0 Then Break;
    End;
    V := V^.Next;
  End;
  FlushTlb;
  MmDup := New;
End;

{ ==================================================================== }
{ Partie 9 - Taches, ordonnanceur, sommeil/reveil, fork, exit, wait   }
{ ==================================================================== }

Const
  MaxTasks     = 256;
  MaxFd        = 256;
  KStackOrder  = 2;              { pile du noyau : 4 pages = 16 Ko }
  KStackSize   = 16384;
  StackMagic   = $5AFE57AC;

  { Etats }
  TsFree       = 0;
  TsRunnable   = 1;              { pret (ou en cours d'execution) }
  TsSleeping   = 3;              { sommeil interruptible }
  TsSleepUn    = 4;              { sommeil non interruptible }
  TsZombie     = 5;
  TsStopped    = 6;

  { Raisons de reveil }
  WakeNormal   = 0;
  WakeTimeout  = 1;
  WakeSignal   = 2;

  { clone() }
  CLONE_VM = $100; CLONE_FS = $200; CLONE_FILES = $400; CLONE_SIGHAND = $800;
  CLONE_VFORK = $4000; CLONE_PARENT = $8000; CLONE_THREAD = $10000;
  CLONE_SETTLS = $80000; CLONE_PARENT_SETTID = $100000;
  CLONE_CHILD_CLEARTID = $200000; CLONE_CHILD_SETTID = $1000000;

  { Signaux Linux i386 }
  SIGHUP = 1; SIGINT = 2; SIGQUIT = 3; SIGILL = 4; SIGTRAP = 5; SIGABRT = 6;
  SIGBUS = 7; SIGFPE = 8; SIGKILL = 9; SIGUSR1 = 10; SIGSEGV = 11;
  SIGUSR2 = 12; SIGPIPE = 13; SIGALRM = 14; SIGTERM = 15; SIGSTKFLT = 16;
  SIGCHLD = 17; SIGCONT = 18; SIGSTOP = 19; SIGTSTP = 20; SIGTTIN = 21;
  SIGTTOU = 22; SIGURG = 23; SIGXCPU = 24; SIGXFSZ = 25; SIGVTALRM = 26;
  SIGPROF = 27; SIGWINCH = 28; SIGIO = 29; SIGPWR = 30; SIGSYS = 31;

  { limites (RLIMIT_*) }
  RLIM_CPU = 0; RLIM_FSIZE = 1; RLIM_DATA = 2; RLIM_STACK = 3; RLIM_CORE = 4;
  RLIM_RSS = 5; RLIM_NPROC = 6; RLIM_NOFILE = 7; RLIM_MEMLOCK = 8; RLIM_AS = 9;
  RLIM_INFINITY = $7FFFFFFF;

Type
  PFiles = ^TFiles;
  TFiles = Record
    Count     : LongInt;
    Fd        : Array[0..255] Of LongInt;
        { MaxFd ; adresses de TFile }
    CloseExec : Array[0..255] Of Byte;
  End;

  PFsStruct = ^TFsStruct;
  TFsStruct = Record
    Count, Umask : LongInt;
    Root, Pwd    : LongInt;                         { adresses de TDentry }
  End;

  PSigHand = ^TSigHand;
  TSigHand = Record
    Count     : LongInt;
    Handler   : Array[0..64] Of LongInt;            { SIG_DFL=0, SIG_IGN=1 }
    Flags     : Array[0..64] Of LongInt;
    Restorer  : Array[0..64] Of LongInt;
    MaskLo    : Array[0..64] Of LongInt;
    MaskHi    : Array[0..64] Of LongInt;
  End;

  PTask = ^TTask;
  TTask = Record
    State, Pid, Tgid   : LongInt;
    Parent             : PTask;
    Pgid, Sid          : LongInt;
    Uid, Euid, Suid, Fsuid, Gid, Egid, Sgid, Fsgid : LongInt;
    NGroups            : LongInt;
    Groups             : Array[0..15] Of LongInt;
    KStack, KEsp       : LongInt;                   { pile du noyau }
    Frame              : LongInt;
        { cadre utilisateur courant }
    Mm                 : PMm;
    Files              : PFiles;
    Fs                 : PFsStruct;
    Sig                : PSigHand;
    Nice, Counter, Policy, RtPrio : LongInt;
    WaitChan, WakeAt, WakeReason  : LongInt;
    ExitCode, ExitSignal          : LongInt;
    Pend, Blk, Save    : Array[0..1] Of LongInt;
        { signaux (32 bits bas, haut) }
    HasSaved           : LongInt;
    AlarmAt, ItInterval           : LongInt;        { ITIMER_REAL (jiffies) }
    ItVirt, ItVirtInt, ItProf, ItProfInt : LongInt;
    Utime, Stime, Cutime, Cstime  : LongInt;
    StartTime          : LongInt;
    Tty                : LongInt;
        { terminal de controle (-1) }
    Comm               : Array[0..15] Of Byte;
    Tls                : Array[0..5] Of LongInt;
    RlimCur, RlimMax   : Array[0..15] Of LongInt;
    ClearTid, Flags    : LongInt;
    ThreadFn           : LongInt;                   { thread noyau }
    VforkParent        : PTask;
    SigSender          : Array[0..64] Of LongInt;   { pid de l'emetteur }
    SigStk             : Array[0..2] Of LongInt;    { sigaltstack }
    ReapPending        : LongInt;
    Fpu                : Array[0..131] Of LongInt;  { FXSAVE (512, aligne 16) ou FNSAVE }
  End;

Var
  Tasks        : Array[0..MaxTasks - 1] Of TTask;
  Cur          : PTask;                             { tache courante }
  IdleTask     : PTask;
  NextPid      : LongInt;
  NeedResched  : Boolean;
  NrTasks      : LongInt;
  NrSwitches   : LongInt;
  InitTask     : PTask;
  RetTrapEntry : LongInt;
  TickUser     : Boolean;

{ ---- Procedures anticipees ---- }
Procedure FilePut(F : LongInt); Forward;
Procedure FileGet(F : LongInt); Forward;
Procedure DentryPut(D : LongInt); Forward;
Procedure DentryGet(D : LongInt); Forward;
Procedure SendSig(T : PTask; Sig : LongInt); Forward;
Procedure SendSigPgrp(Pgrp, Sig : LongInt); Forward;
Procedure TtyDisassociate(T : PTask); Forward;
Procedure TimerSignals; Forward;
Function SigPendingUnblocked(T : PTask) : Boolean; Forward;
Procedure HandleSignals(F : PFrame); Forward;
Procedure SignalsExitCleanup(T : PTask); Forward;

Function PidTask(Pid : LongInt) : PTask;
Var I : LongInt;
Begin
  PidTask := Nil;
  If Pid <= 0 Then Exit;
  For I := 0 To MaxTasks - 1 Do
    If (Tasks[I].State <> TsFree) And (Tasks[I].Pid = Pid) Then
    Begin
      PidTask := @Tasks[I];
      Exit;
    End;
End;

{ ---- Changement de contexte ---- }

{ Sauve les registres, range ESP dans [OldEspPtr], charge NewEsp et restaure
  les registres de la nouvelle tache (voir la pile initiale de NewTask) }
Procedure SwitchStack(OldEspPtr, NewEsp : LongInt);
Begin
  asm
    mov ecx,OldEspPtr
    mov edx,NewEsp
    pushad
    mov [ecx],esp
    mov esp,edx
    popad
  end;
End;

{ Etat de l'unite flottante. Avec FXSR (CPUID 1, EDX bit 24 : x87, MMX et
  SSE) : FXSAVE/FXRSTOR de 512 octets alignes sur 16 (l'adresse donnee est
  arrondie) ; sinon FNSAVE/FRSTOR de 108 octets. CR4.OSFXSR et OSXMMEXCPT
  sont mis par FpuDetect (sans cela SSE leve #UD). }
Var
  HasFxsr    : Boolean;
  FxInitBuf  : Array[0..131] Of LongInt;   { etat initial (xmm a zero) }
  FxTmp      : Array[0..131] Of LongInt;   { tampon de passage }

Function FpuAlign(A : LongInt) : LongInt;
Begin
  FpuAlign := (A + 15) And Not 15;
End;

Procedure SaveFpu(Addr : LongInt);
Begin
  If HasFxsr Then
  Begin
    Addr := FpuAlign(Addr);
    asm
      mov eax,Addr
      db 15,174,0
    end;
  End
  Else
  Begin
    asm
      mov eax,Addr
      db 221,48
    end;
  End;
End;

Procedure LoadFpu(Addr : LongInt);
Begin
  If HasFxsr Then
  Begin
    Addr := FpuAlign(Addr);
    asm
      mov eax,Addr
      db 15,174,8
    end;
  End
  Else
  Begin
    asm
      mov eax,Addr
      db 221,32
    end;
  End;
End;

{ Etat x87 seul au format FNSAVE (108 octets, adresse utilisateur) }
Procedure FrstorAt(Addr : LongInt);
Begin
  asm
    mov eax,Addr
    db 221,32
  end;
End;

{ Etat initial : x87 reinitialise, registres xmm a zero, MXCSR = 1F80h }
Procedure InitFpu;
Begin
  If HasFxsr Then LoadFpu(LongInt(@FxInitBuf[0]))
  Else
  Begin
    asm
      db 219,227
    end;
  End;
End;

{ Detecter FXSR/SSE, les activer, preparer l'etat initial }
Procedure FpuDetect;
Var Feat, A : LongInt;
Begin
  asm
    push ebx
    mov eax,1
    cpuid
    mov Feat,edx
    pop ebx
  end;
  HasFxsr := (Feat And $1000000) <> 0;
  If HasFxsr Then
  Begin
    asm
      mov eax,cr0
      and eax,-5
      or eax,2
      mov cr0,eax
      mov eax,cr4
      or eax,1536
      mov cr4,eax
    end;
    A := FpuAlign(LongInt(@FxInitBuf[0]));
    MemFill(A, 0, 512);
    MemW[0:A] := $037F;
    MemL[0:A + 24] := $1F80;
  End;
End;

{ Image FXSAVE (512 octets) vers / depuis une adresse quelconque }
Procedure FxSaveTo(Dst : LongInt);
Begin
  SaveFpu(LongInt(@FxTmp[0]));
  MemCopy(Dst, FpuAlign(LongInt(@FxTmp[0])), 512);
End;

Procedure FxLoadFrom(Src : LongInt);
Var A : LongInt;
Begin
  A := FpuAlign(LongInt(@FxTmp[0]));
  MemCopy(A, Src, 512);
  MemL[0:A + 24] := MemL[0:A + 24] And $FFBF;
  LoadFpu(LongInt(@FxTmp[0]));
End;

Procedure LoadTls(T : PTask);
Var I : LongInt;
Begin
  For I := 0 To 5 Do Gdt[12 + I] := T^.Tls[I];
End;

Function Goodness(T : PTask) : LongInt;
Begin
  If T^.Policy <> 0 Then Goodness := 1000 + T^.RtPrio
  Else If T^.Counter <= 0 Then Goodness := 0
  Else Goodness := T^.Counter + 1;
End;

Function SliceFor(Nice : LongInt) : LongInt;
Begin
  SliceFor := (20 - Nice) Div 3 + 1;
End;

{ Choisir la tache suivante et basculer (appele avec IF = 0) }
Procedure Schedule;
Var I, Best, G, BestG : LongInt; Prev, Nx : PTask; Again : Boolean;
Begin
  NeedResched := False;
  Prev := Cur;
  If MemL[0:Prev^.KStack] <> StackMagic Then
    KPanic('pile du noyau debordee (pid ' + IntStr(Prev^.Pid) + ')');
  Repeat
    Again := False;
    Best := 0; BestG := -1;
    For I := 1 To MaxTasks - 1 Do
      If Tasks[I].State = TsRunnable Then
      Begin
        G := Goodness(@Tasks[I]);
        If G > BestG Then
        Begin
          BestG := G;
          Best := I;
        End;
      End;
    If (Best <> 0) And (BestG = 0) Then
    Begin
      { toutes les tranches sont epuisees : recalculer }
      For I := 1 To MaxTasks - 1 Do
        If Tasks[I].State <> TsFree Then
          Tasks[I].Counter := (Tasks[I].Counter Shr 1)
              + SliceFor(Tasks[I].Nice);
      Again := True;
    End;
  Until Not Again;
  If Best = 0 Then Nx := IdleTask Else Nx := @Tasks[Best];
  If Nx = Prev Then Exit;
  Inc(NrSwitches);
  Cur := Nx;
  SetKernelStack(Nx^.KStack + KStackSize);
  If Nx^.Mm <> Nil Then
  Begin
    If Nx^.Mm <> Prev^.Mm Then WriteCr3(Nx^.Mm^.PgdPhys);
    CurMm := Nx^.Mm;
  End
  Else
  Begin
    WriteCr3(MasterPdPhys);
    CurMm := Nil;
  End;
  LoadTls(Nx);
  SaveFpu(LongInt(@Prev^.Fpu[0]));
  LoadFpu(LongInt(@Nx^.Fpu[0]));
  SwitchStack(LongInt(@Prev^.KEsp), Nx^.KEsp);
End;

{ ---- Sommeil et reveil ---- }

{ Endormir la tache courante sur Chan. Timeout en ticks (0 : aucun).
  Retourne WakeNormal, WakeTimeout ou WakeSignal. }
Function SleepOn(Chan, Timeout : LongInt; Intr : Boolean) : LongInt;
Begin
  If Intr And SigPendingUnblocked(Cur) Then
  Begin
    SleepOn := WakeSignal;
    Exit;
  End;
  Cur^.WaitChan := Chan;
  If Timeout > 0 Then Cur^.WakeAt := Jiffies + Timeout Else Cur^.WakeAt := 0;
  Cur^.WakeReason := WakeNormal;
  If Intr Then Cur^.State := TsSleeping Else Cur^.State := TsSleepUn;
  Schedule;
  Cur^.WakeAt := 0;
  Cur^.WaitChan := 0;
  SleepOn := Cur^.WakeReason;
End;

Procedure WakeTask(T : PTask; Reason : LongInt);
Begin
  If (T^.State = TsSleeping) Or (T^.State = TsSleepUn) Then
  Begin
    T^.State := TsRunnable;
    T^.WakeReason := Reason;
    T^.WakeAt := 0;
  End;
End;

Procedure WakeUp(Chan : LongInt);
Var I : LongInt;
Begin
  For I := 0 To MaxTasks - 1 Do
    If ((Tasks[I].State = TsSleeping) Or (Tasks[I].State = TsSleepUn)) And
       (Tasks[I].WaitChan = Chan) Then
      WakeTask(@Tasks[I], WakeNormal);
End;

{ Ceder le processeur }
Procedure Yield;
Begin
  If Cur <> IdleTask Then Cur^.Counter := 0;
  Schedule;
End;

{ Dormir au moins Ticks ticks (interruptible) : retourne 0 ou WakeSignal }
Function SleepTicks(Ticks : LongInt) : LongInt;
Var T0, R : LongInt;
Begin
  T0 := Jiffies;
  If Ticks <= 0 Then
  Begin
    Yield;
    SleepTicks := 0;
    Exit;
  End;
  R := SleepOn(0, Ticks, True);
  If R = WakeTimeout Then SleepTicks := 0 Else SleepTicks := R;
End;

{ Tick de la minuterie (appele par l'IRQ 0) }
Procedure TimerTick(FromUser : Boolean);
Var I : LongInt;
Begin
  Inc(Jiffies);
  TickUser := FromUser;
  For I := 1 To MaxTasks - 1 Do
    If ((Tasks[I].State = TsSleeping) Or (Tasks[I].State = TsSleepUn)) And
       (Tasks[I].WakeAt <> 0) And (Jiffies - Tasks[I].WakeAt >= 0) Then
      WakeTask(@Tasks[I], WakeTimeout);
  TimerSignals;
  If Cur <> IdleTask Then
  Begin
    If FromUser Then Inc(Cur^.Utime) Else Inc(Cur^.Stime);
    Dec(Cur^.Counter);
    If Cur^.Counter <= 0 Then NeedResched := True;
  End;
  { l'inactivite n'a pas de tranche : tout reveil est pris en compte }
  If Cur = IdleTask Then NeedResched := True;
End;

{ ---- Creation de taches ---- }

Function AllocPid : LongInt;
Var P, I : LongInt; Ok : Boolean;
Begin
  Repeat
    Inc(NextPid);
    If NextPid > 32767 Then NextPid := 2;
    P := NextPid;
    Ok := True;
    For I := 0 To MaxTasks - 1 Do
      If (Tasks[I].State <> TsFree) And ((Tasks[I].Pid = P) Or (Tasks[I].Pgid
          = P) Or (Tasks[I].Sid = P)) Then
        Ok := False;
  Until Ok;
  AllocPid := P;
End;

Function NewTaskSlot : PTask;
Var I : LongInt;
Begin
  NewTaskSlot := Nil;
  For I := 1 To MaxTasks - 1 Do
    If Tasks[I].State = TsFree Then
    Begin
      NewTaskSlot := @Tasks[I];
      Exit;
    End;
End;

{ Pile initiale d'une nouvelle tache : au premier Schedule, SwitchStack
  "revient" a l'adresse Entry avec ESP = Top (voir SwitchStack) }
Procedure PrepareStack(T : PTask; Entry, Top : LongInt);
Var Fp, P, I : LongInt;
Begin
  { Top : sommet de la pile restant disponible apres le retour }
  Fp := Top - 8;
  MemL[0:Fp] := 0;                 { EBP sauve }
  MemL[0:Fp + 4] := Entry;         { adresse de retour }
  P := Fp - 32;
      { bloc PUSHAD : EDI ESI EBP ESP EBX EDX ECX EAX }
  For I := 0 To 7 Do MemL[0:P + I * 4] := 0;
  MemL[0:P + 8] := Fp;             { EBP }
  T^.KEsp := P;
End;

{ Debut d'un thread noyau }
Procedure ThreadEntry;
Var Fn : LongInt;
Begin
  Fn := Cur^.ThreadFn;
  Call0(Fn);
  { le thread revient : l'arreter }
  Cur^.State := TsSleepUn;
  Schedule;
End;

{ Creer un thread noyau (processus sans espace utilisateur) }
Function KernelThread(Fn : LongInt) : PTask;
Var T : PTask;
Begin
  KernelThread := Nil;
  T := NewTaskSlot;
  If T = Nil Then Exit;
  MemCopy(LongInt(T), LongInt(Cur), SizeOf(TTask));
  T^.State := TsSleepUn;
  T^.Pid := AllocPid;
  T^.Tgid := T^.Pid;
  T^.Parent := Cur;
  T^.KStack := AllocPages(KStackOrder);
  If T^.KStack = 0 Then
  Begin
    T^.State := TsFree;
    Exit;
  End;
  MemL[0:T^.KStack] := StackMagic;
  T^.ThreadFn := Fn;
  T^.Mm := Nil;
  T^.Files := Nil; T^.Fs := Nil; T^.Sig := Nil;
  T^.Pend[0] := 0; T^.Pend[1] := 0;
  T^.Counter := SliceFor(0);
  PrepareStack(T, LongInt(@ThreadEntry), T^.KStack + KStackSize - 256);
  Inc(NrTasks);
  KernelThread := T;
End;

Procedure InitTaskStruct(T : PTask);
Var I : LongInt;
Begin
  T^.Nice := 0;
  T^.Counter := SliceFor(0);
  For I := 0 To 15 Do
  Begin
    T^.RlimCur[I] := RLIM_INFINITY; T^.RlimMax[I] := RLIM_INFINITY;
  End;
  T^.RlimCur[RLIM_STACK] := DefStackLimit;
  T^.RlimCur[RLIM_NOFILE] := MaxFd; T^.RlimMax[RLIM_NOFILE] := MaxFd;
  T^.RlimCur[RLIM_CORE] := 0;
  T^.Tty := -1;
End;

Function FilesNew : PFiles;
Var F : PFiles;
Begin
  F := Pointer(KMallocZ(SizeOf(TFiles)));
  If F <> Nil Then F^.Count := 1;
  FilesNew := F;
End;

Function FsNew : PFsStruct;
Var F : PFsStruct;
Begin
  F := Pointer(KMallocZ(SizeOf(TFsStruct)));
  If F <> Nil Then
  Begin
    F^.Count := 1;
    F^.Umask := 18;
  End;
  FsNew := F;
End;

Function SigNew : PSigHand;
Var S : PSigHand;
Begin
  S := Pointer(KMallocZ(SizeOf(TSigHand)));
  If S <> Nil Then S^.Count := 1;
  SigNew := S;
End;

Function FilesDup(Old : PFiles) : PFiles;
Var N : PFiles; I : LongInt;
Begin
  N := FilesNew;
  FilesDup := N;
  If N = Nil Then Exit;
  For I := 0 To MaxFd - 1 Do
  Begin
    N^.Fd[I] := Old^.Fd[I];
    N^.CloseExec[I] := Old^.CloseExec[I];
    If N^.Fd[I] <> 0 Then FileGet(N^.Fd[I]);
  End;
End;

Procedure FilesRelease(F : PFiles);
Var I : LongInt;
Begin
  Dec(F^.Count);
  If F^.Count > 0 Then Exit;
  For I := 0 To MaxFd - 1 Do
    If F^.Fd[I] <> 0 Then
    Begin
      FilePut(F^.Fd[I]);
      F^.Fd[I] := 0;
    End;
  KFree(LongInt(F));
End;

Function FsDup(Old : PFsStruct) : PFsStruct;
Var N : PFsStruct;
Begin
  N := FsNew;
  FsDup := N;
  If N = Nil Then Exit;
  N^.Umask := Old^.Umask;
  N^.Root := Old^.Root; N^.Pwd := Old^.Pwd;
  If N^.Root <> 0 Then DentryGet(N^.Root);
  If N^.Pwd <> 0 Then DentryGet(N^.Pwd);
End;

Procedure FsRelease(F : PFsStruct);
Begin
  Dec(F^.Count);
  If F^.Count > 0 Then Exit;
  If F^.Root <> 0 Then DentryPut(F^.Root);
  If F^.Pwd <> 0 Then DentryPut(F^.Pwd);
  KFree(LongInt(F));
End;

Function SigDup(Old : PSigHand) : PSigHand;
Var N : PSigHand;
Begin
  N := SigNew;
  SigDup := N;
  If N = Nil Then Exit;
  MemCopy(LongInt(N), LongInt(Old), SizeOf(TSigHand));
  N^.Count := 1;
End;

Procedure SigRelease(S : PSigHand);
Begin
  Dec(S^.Count);
  If S^.Count <= 0 Then KFree(LongInt(S));
End;

{ fork / clone : retourne le pid du fils ou -errno ; Frame = cadre du parent }
Function DoClone(Flags, NewSp : LongInt; Fr : PFrame) : LongInt;
Var T : PTask; ChildFr : PFrame; Top, FrAddr : LongInt;
Begin
  DoClone := -EAGAIN;
  T := NewTaskSlot;
  If T = Nil Then Exit;
  SaveFpu(LongInt(@Cur^.Fpu[0]));
  LoadFpu(LongInt(@Cur^.Fpu[0]));
  MemCopy(LongInt(T), LongInt(Cur), SizeOf(TTask));
  MemCopy(FpuAlign(LongInt(@T^.Fpu[0])), FpuAlign(LongInt(@Cur^.Fpu[0])), 512);
  T^.State := TsSleepUn;                 { pas encore ordonnable }
  T^.KStack := AllocPages(KStackOrder);
  If T^.KStack = 0 Then
  Begin
    T^.State := TsFree;
    DoClone := -ENOMEM;
    Exit;
  End;
  MemL[0:T^.KStack] := StackMagic;
  T^.Pid := AllocPid;
  If (Flags And CLONE_THREAD) <> 0 Then T^.Tgid := Cur^.Tgid
      Else T^.Tgid := T^.Pid;
  If (Flags And CLONE_PARENT) <> 0 Then T^.Parent := Cur^.Parent
      Else T^.Parent := Cur;
  T^.Pend[0] := 0; T^.Pend[1] := 0;
  T^.HasSaved := 0;
  T^.AlarmAt := 0; T^.ItInterval := 0; T^.ItVirt := 0; T^.ItProf := 0;
  T^.Utime := 0; T^.Stime := 0; T^.Cutime := 0; T^.Cstime := 0;
  T^.StartTime := Jiffies;
  T^.ExitCode := 0;
  T^.ExitSignal := Flags And $FF;
  T^.ClearTid := 0;
  T^.ThreadFn := 0;
  T^.VforkParent := Nil;
  T^.WaitChan := 0; T^.WakeAt := 0;
  T^.Counter := (Cur^.Counter + 1) Shr 1;
  Cur^.Counter := Cur^.Counter Shr 1;
  { espace d'adressage }
  If (Flags And CLONE_VM) <> 0 Then
  Begin
    T^.Mm := Cur^.Mm;
    Inc(T^.Mm^.Count);
  End
  Else
  Begin
    T^.Mm := MmDup(Cur^.Mm);
    If T^.Mm = Nil Then
    Begin
      FreePages(T^.KStack, KStackOrder);
      T^.State := TsFree;
      DoClone := -ENOMEM;
      Exit;
    End;
  End;
  If (Flags And CLONE_FILES) <> 0 Then
  Begin
    T^.Files := Cur^.Files;
    Inc(T^.Files^.Count);
  End
  Else T^.Files := FilesDup(Cur^.Files);
  If (Flags And CLONE_FS) <> 0 Then
  Begin
    T^.Fs := Cur^.Fs;
    Inc(T^.Fs^.Count);
  End
  Else T^.Fs := FsDup(Cur^.Fs);
  If (Flags And CLONE_SIGHAND) <> 0 Then
  Begin
    T^.Sig := Cur^.Sig;
    Inc(T^.Sig^.Count);
  End
  Else T^.Sig := SigDup(Cur^.Sig);
  If (T^.Files = Nil) Or (T^.Fs = Nil) Or (T^.Sig = Nil) Then
  Begin
    DoClone := -ENOMEM;
    Exit;
  End;
  { cadre du fils : copie du cadre du parent, EAX = 0 }
  Top := T^.KStack + KStackSize;
  FrAddr := Top - SizeOf(TFrame);
  MemCopy(FrAddr, LongInt(Fr), SizeOf(TFrame));
  ChildFr := Pointer(FrAddr);
  ChildFr^.Eax := 0;
  If NewSp <> 0 Then ChildFr^.UserEsp := NewSp;
  T^.Frame := FrAddr;
  If (Flags And CLONE_SETTLS) <> 0 Then
  Begin
    { l'appelant a prepare Tls[0..1] dans Cur : copie deja faite }
  End;
  PrepareStack(T, RetTrapEntry, FrAddr);
  Inc(NrTasks);
  If (Flags And CLONE_VFORK) <> 0 Then T^.VforkParent := Cur;
  T^.State := TsRunnable;
  If (Flags And CLONE_VFORK) <> 0 Then
  Begin
    { le pere attend l'exec ou la fin du fils }
    While T^.VforkParent <> Nil Do SleepOn(LongInt(T), 0, False);
  End;
  DoClone := T^.Pid;
End;

{ ---- Fin de processus et attente ---- }

Procedure ReleaseVfork(T : PTask);
Begin
  If T^.VforkParent <> Nil Then
  Begin
    WakeUp(LongInt(T));
    T^.VforkParent := Nil;
  End;
End;

{ Terminer la tache courante ; Code au format wait (status) }
Procedure DoExit(Code : LongInt);
Var I : LongInt; T, P : PTask; Orphan : Boolean;
Begin
  T := Cur;
  { le dernier fil d'un groupe de tgid est le leader : terminaison du groupe
    non geree par exit(), voir exit_group }
  SignalsExitCleanup(T);
  If T^.ClearTid <> 0 Then
  Begin
    If EnsureUser(T^.ClearTid, 4, True) Then MemL[0:T^.ClearTid] := 0;
    WakeUp(T^.ClearTid);
  End;
  If T^.Files <> Nil Then FilesRelease(T^.Files);
  T^.Files := Nil;
  If T^.Fs <> Nil Then FsRelease(T^.Fs);
  T^.Fs := Nil;
  If T^.Sig <> Nil Then SigRelease(T^.Sig);
  T^.Sig := Nil;
  If T^.Mm <> Nil Then
  Begin
    CurMm := Nil;
    WriteCr3(MasterPdPhys);
    MmRelease(T^.Mm);
    T^.Mm := Nil;
  End;
  If (T^.Sid = T^.Pid) Then TtyDisassociate(T);
  ReleaseVfork(T);
  { orphelins : reparentes a init }
  For I := 1 To MaxTasks - 1 Do
    If (Tasks[I].State <> TsFree) And (Tasks[I].Parent = T) Then
    Begin
      Tasks[I].Parent := InitTask;
      If Tasks[I].State = TsZombie Then WakeUp(LongInt(InitTask));
      If Tasks[I].ExitSignal = 0 Then Tasks[I].ExitSignal := SIGCHLD;
    End;
  T^.ExitCode := Code;
  T^.State := TsZombie;
  P := T^.Parent;
  If (P <> Nil) And (T^.Tgid = T^.Pid) Then
  Begin
    If T^.ExitSignal <> 0 Then SendSig(P, T^.ExitSignal);
    WakeUp(LongInt(P));
  End
  Else If P <> Nil Then WakeUp(LongInt(P));
  If InitTask <> Nil Then WakeUp(LongInt(InitTask));
  Schedule;
  KPanic('DoExit : tache zombie reordonnancee');
End;

{ Liberer une tache zombie }
Procedure ReapTask(T : PTask);
Begin
  FreePages(T^.KStack, KStackOrder);
  T^.State := TsFree;
  T^.Pid := 0;
  Dec(NrTasks);
End;

{ wait4 : retourne le pid, 0 (WNOHANG) ou -errno ; Status/Ru : adresses
  utilisateur (0 si absentes) }
Function DoWait4(Pid, Status, Options, Ru : LongInt) : LongInt;
Var I, Found, R : LongInt; T : PTask; Match : Boolean; St : LongInt;
Begin
  While True Do
  Begin
    Found := 0;
    For I := 1 To MaxTasks - 1 Do
    Begin
      T := @Tasks[I];
      If (T^.State <> TsFree) And (T^.Parent = Cur) And (T <> Cur) Then
      Begin
        Match := False;
        If Pid > 0 Then Match := T^.Pid = Pid
        Else If Pid = -1 Then Match := True
        Else If Pid = 0 Then Match := T^.Pgid = Cur^.Pgid
        Else Match := T^.Pgid = -Pid;
        If (Options And $20000000) <> 0 Then Match := True;   { __WALL }
        If Match Then
        Begin
          Inc(Found);
          If T^.State = TsZombie Then
          Begin
            St := T^.ExitCode;
            If Status <> 0 Then
            Begin
              R := PutUserL(Status, St);
              If R < 0 Then
              Begin
                DoWait4 := R;
                Exit;
              End;
            End;
            Cur^.Cutime := Cur^.Cutime + T^.Utime + T^.Cutime;
            Cur^.Cstime := Cur^.Cstime + T^.Stime + T^.Cstime;
            If Ru <> 0 Then
              If EnsureUser(Ru, 72, True) Then
              Begin
                MemFill(Ru, 0, 72);
                MemL[0:Ru] := (T^.Utime + T^.Cutime) Div HZ;
                MemL[0:Ru + 4] := ((T^.Utime + T^.Cutime) Mod HZ) * 10000;
                MemL[0:Ru + 8] := (T^.Stime + T^.Cstime) Div HZ;
                MemL[0:Ru + 12] := ((T^.Stime + T^.Cstime) Mod HZ) * 10000;
              End;
            R := T^.Pid;
            ReapTask(T);
            DoWait4 := R;
            Exit;
          End
          Else If (T^.State = TsStopped) And ((Options And 2) <> 0)
              And (T^.ReapPending <> 0) Then
          Begin
            { fils arrete (WUNTRACED) }
            T^.ReapPending := 0;
            If Status <> 0 Then
            Begin
              R := PutUserL(Status, (T^.ExitCode Shl 8) Or $7F);
              If R < 0 Then
              Begin
                DoWait4 := R;
                Exit;
              End;
            End;
            DoWait4 := T^.Pid;
            Exit;
          End;
        End;
      End;
    End;
    If Found = 0 Then
    Begin
      DoWait4 := -ECHILD;
      Exit;
    End;
    If (Options And 1) <> 0 Then
    Begin
      DoWait4 := 0;
      Exit;
    End;
    If SleepOn(LongInt(Cur), 0, True) = WakeSignal Then
    Begin
      DoWait4 := -ERESTARTSYS;
      Exit;
    End;
  End;
End;

{ Initialiser la table des taches : la tache 0 (inactive) est le thread
  d'amorce }
Procedure InitTasks;
Var I : LongInt;
Begin
  MemFill(LongInt(@Tasks[0]), 0, SizeOf(Tasks));
  IdleTask := @Tasks[0];
  Cur := IdleTask;
  CurMm := Nil;
  IdleTask^.State := TsRunnable;
  IdleTask^.Pid := 0;
  IdleTask^.Tgid := 0;
  IdleTask^.KStack := LongInt(@BootStack[0]);
  InitTaskStruct(IdleTask);
  MemL[0:IdleTask^.KStack] := StackMagic;
  NextPid := 1;
  NrTasks := 1;
  RetTrapEntry := RetTrapAdr;
  For I := 0 To 5 Do Gdt[12 + I] := 0;
End;

{ ==================================================================== }
{ Partie 10 - Signaux POSIX, minuteries                                }
{ ==================================================================== }

Const
  SIG_DFL = 0;
  SIG_IGN = 1;
  SA_NOCLDSTOP = $1; SA_NOCLDWAIT = $2; SA_SIGINFO = $4; SA_ONSTACK = $08000000;
  SA_RESTART = $10000000; SA_NODEFER = $40000000; SA_RESETHAND = $80000000;
  SA_RESTORER = $04000000;
  SIG_BLOCK = 0; SIG_UNBLOCK = 1; SIG_SETMASK = 2;
  { taille de la trame de signal : sigcontext = 88 octets }
  SigCtxSize  = 88;
  UnblockableLo = $00050100;     { SIGKILL (bit 8) et SIGSTOP (bit 18) }

Function SigLoBit(Sig : LongInt) : LongInt;
Begin
  If Sig <= 32 Then SigLoBit := 1 Shl (Sig - 1) Else SigLoBit := 0;
End;

Function SigHiBit(Sig : LongInt) : LongInt;
Begin
  If Sig > 32 Then SigHiBit := 1 Shl (Sig - 33) Else SigHiBit := 0;
End;

Function SigPendingUnblocked(T : PTask) : Boolean;
Begin
  SigPendingUnblocked := ((T^.Pend[0] And Not T^.Blk[0]) <> 0) Or
                         ((T^.Pend[1] And Not T^.Blk[1]) <> 0);
End;

{ Action par defaut : 0 ignorer, 1 terminer, 2 core, 3 arreter, 4 continuer }
Function DefaultAction(Sig : LongInt) : LongInt;
Begin
  Case Sig Of
    SIGCHLD, SIGURG, SIGWINCH : DefaultAction := 0;
    SIGCONT : DefaultAction := 4;
    SIGSTOP, SIGTSTP, SIGTTIN, SIGTTOU : DefaultAction := 3;
    SIGQUIT, SIGILL, SIGTRAP, SIGABRT, SIGBUS, SIGFPE, SIGSEGV, SIGXCPU,
    SIGXFSZ, SIGSYS : DefaultAction := 2;
  Else
    DefaultAction := 1;
  End;
End;

{ Envoyer le signal Sig a la tache T }
Procedure SendSig(T : PTask; Sig : LongInt);
Var H : LongInt;
Begin
  If (T = Nil) Or (Sig <= 0) Or (Sig > 64) Then Exit;
  If (T^.State = TsFree) Or (T^.State = TsZombie) Then Exit;
  If T^.Sig <> Nil Then H := T^.Sig^.Handler[Sig] Else H := SIG_DFL;
  If Sig = SIGCONT Then
  Begin
    { effacer les arrets en attente ; reprendre }
    T^.Pend[0] := T^.Pend[0] And Not (SigLoBit(SIGSTOP) Or SigLoBit(SIGTSTP)
        Or SigLoBit(SIGTTIN) Or SigLoBit(SIGTTOU));
    If T^.State = TsStopped Then
    Begin
      T^.State := TsRunnable;
      T^.WakeReason := WakeSignal;
    End;
  End
  Else If (Sig = SIGSTOP) Or (Sig = SIGTSTP) Or (Sig = SIGTTIN) Or (Sig
      = SIGTTOU) Then
    T^.Pend[0] := T^.Pend[0] And Not SigLoBit(SIGCONT);
  { signal ignore : le jeter (sauf KILL et STOP) }
  If (Sig <> SIGKILL) And (Sig <> SIGSTOP) Then
  Begin
    If H = SIG_IGN Then Exit;
    If (H = SIG_DFL) And (DefaultAction(Sig) = 0) Then Exit;
  End;
  If (T^.Pid = 1) And (H = SIG_DFL) And (Sig <> SIGKILL) And (Sig <> SIGSTOP)
      Then Exit;
  T^.Pend[0] := T^.Pend[0] Or SigLoBit(Sig);
  T^.Pend[1] := T^.Pend[1] Or SigHiBit(Sig);
  T^.SigSender[Sig] := Cur^.Pid;
  If (T^.State = TsSleeping) Then
  Begin
    If (Sig = SIGKILL) Or SigPendingUnblocked(T) Then WakeTask(T, WakeSignal);
  End
  Else If (T^.State = TsStopped) And (Sig = SIGKILL) Then
  Begin
    T^.State := TsRunnable;
    T^.WakeReason := WakeSignal;
  End;
End;

{ Signal synchrone (faute) : impose l'action par defaut s'il est masque ou
  ignore pour eviter de reboucler }
Procedure ForceSig(T : PTask; Sig : LongInt);
Begin
  If T^.Sig <> Nil Then
    If (T^.Sig^.Handler[Sig] = SIG_IGN) Or ((T^.Blk[0] And SigLoBit(Sig))
        <> 0) Then
      T^.Sig^.Handler[Sig] := SIG_DFL;
  T^.Blk[0] := T^.Blk[0] And Not SigLoBit(Sig);
  T^.Pend[0] := T^.Pend[0] Or SigLoBit(Sig);
  T^.Pend[1] := T^.Pend[1] Or SigHiBit(Sig);
  T^.SigSender[Sig] := 0;
End;

Procedure SendSigPgrp(Pgrp, Sig : LongInt);
Var I : LongInt;
Begin
  If Pgrp <= 0 Then Exit;
  For I := 1 To MaxTasks - 1 Do
    If (Tasks[I].State <> TsFree) And (Tasks[I].Pgid = Pgrp)
        Then SendSig(@Tasks[I], Sig);
End;

Procedure SignalsExitCleanup(T : PTask);
Begin
  T^.Pend[0] := 0; T^.Pend[1] := 0;
  T^.AlarmAt := 0;
End;

{ Minuteries d'intervalle : appele a chaque tick }
Procedure TimerSignals;
Var I : LongInt; T : PTask;
Begin
  For I := 1 To MaxTasks - 1 Do
  Begin
    T := @Tasks[I];
    If (T^.State <> TsFree) And (T^.State <> TsZombie) Then
    Begin
      If (T^.AlarmAt <> 0) And (Jiffies - T^.AlarmAt >= 0) Then
      Begin
        SendSig(T, SIGALRM);
        If T^.ItInterval > 0 Then T^.AlarmAt := Jiffies + T^.ItInterval
        Else T^.AlarmAt := 0;
      End;
    End;
  End;
  If (Cur <> IdleTask) Then
  Begin
    If TickUser And (Cur^.ItVirt > 0) Then
    Begin
      Dec(Cur^.ItVirt);
      If Cur^.ItVirt = 0 Then
      Begin
        SendSig(Cur, SIGVTALRM);
        Cur^.ItVirt := Cur^.ItVirtInt;
      End;
    End;
    If Cur^.ItProf > 0 Then
    Begin
      Dec(Cur^.ItProf);
      If Cur^.ItProf = 0 Then
      Begin
        SendSig(Cur, SIGPROF);
        Cur^.ItProf := Cur^.ItProfInt;
      End;
    End;
  End;
End;

{ Prendre le prochain signal en attente non masque (0 si aucun) }
Function DequeueSignal(T : PTask) : LongInt;
Var Lo, Hi, I : LongInt;
Begin
  DequeueSignal := 0;
  Lo := T^.Pend[0] And Not (T^.Blk[0] And Not UnblockableLo);
  Hi := T^.Pend[1] And Not T^.Blk[1];
  If (Lo = 0) And (Hi = 0) Then Exit;
  For I := 1 To 64 Do
    If ((I <= 32) And ((Lo And SigLoBit(I)) <> 0)) Or ((I > 32) And ((Hi
        And SigHiBit(I)) <> 0)) Then
    Begin
      T^.Pend[0] := T^.Pend[0] And Not SigLoBit(I);
      T^.Pend[1] := T^.Pend[1] And Not SigHiBit(I);
      DequeueSignal := I;
      Exit;
    End;
End;

{ ---- Construction du cadre de signal sur la pile utilisateur ---- }

Procedure PutSigContext(Ctx : LongInt; F : PFrame; OldMask : LongInt;
    Cr2 : LongInt);
Begin
  MemL[0:Ctx + 0] := F^.Gs;   MemL[0:Ctx + 4] := F^.Fs;
  MemL[0:Ctx + 8] := F^.Es;   MemL[0:Ctx + 12] := F^.Ds;
  MemL[0:Ctx + 16] := F^.Edi; MemL[0:Ctx + 20] := F^.Esi;
  MemL[0:Ctx + 24] := F^.Ebp; MemL[0:Ctx + 28] := F^.UserEsp;
  MemL[0:Ctx + 32] := F^.Ebx; MemL[0:Ctx + 36] := F^.Edx;
  MemL[0:Ctx + 40] := F^.Ecx; MemL[0:Ctx + 44] := F^.Eax;
  MemL[0:Ctx + 48] := F^.Vec; MemL[0:Ctx + 52] := F^.Err;
  MemL[0:Ctx + 56] := F^.Eip; MemL[0:Ctx + 60] := F^.Cs;
  MemL[0:Ctx + 64] := F^.Eflags; MemL[0:Ctx + 68] := F^.UserEsp;
  MemL[0:Ctx + 72] := F^.Ss;  MemL[0:Ctx + 76] := 0;
  MemL[0:Ctx + 80] := OldMask; MemL[0:Ctx + 84] := Cr2;
End;

{ Installer le gestionnaire du signal Sig (le cadre F est modifie) ;
  retourne False si la pile est inutilisable (SIGSEGV fatal).
  Trame RT (SA_SIGINFO) : +0 pretcode +4 sig +8 pinfo +12 puc +16 siginfo(128)
  +144 ucontext (flags, link, stack(12), sigcontext(88) en +164, sigmask(8) en
  +252) +260 etat x87 (112) +372 retcode(8) : 380 octets.
  Trame ancienne : +0 pretcode +4 sig +8 sigcontext(88) +96 extramask
  +100 etat x87 (112) +212 retcode(8) : 220 octets. }
Function SetupFrame(F : PFrame; Sig : LongInt) : Boolean;
Var Sg : PSigHand; Sp, Fr, H, Fl, Rest, Sc, Fpu, Size : LongInt; Rt : Boolean;
Begin
  SetupFrame := False;
  Sg := Cur^.Sig;
  H := Sg^.Handler[Sig];
  Fl := Sg^.Flags[Sig];
  Rt := (Fl And SA_SIGINFO) <> 0;
  Sp := F^.UserEsp;
  If ((Fl And SA_ONSTACK) <> 0) And (Cur^.SigStk[1] = 0) And (Cur^.SigStk[2]
      <> 0) Then
    Sp := Cur^.SigStk[0] + Cur^.SigStk[2];
  If Rt Then Size := 380 Else Size := 220;
  If HasFxsr Then Size := Size + 512;
  Fr := ((Sp - Size) And Not 15) - 4;
  If Not EnsureUser(Fr, Sp - Fr, True) Then Exit;
  MemFill(Fr, 0, Sp - Fr);
  MemL[0:Fr + 4] := Sig;
  If Rt Then
  Begin
    MemL[0:Fr + 8] := Fr + 16;                 { pinfo }
    MemL[0:Fr + 12] := Fr + 144;               { puc }
    MemL[0:Fr + 16] := Sig;                    { si_signo }
    MemL[0:Fr + 28] := Cur^.SigSender[Sig];    { si_pid }
    MemL[0:Fr + 152] := Cur^.SigStk[0];
    MemL[0:Fr + 156] := Cur^.SigStk[1];
    MemL[0:Fr + 160] := Cur^.SigStk[2];
    Sc := Fr + 164;
    Fpu := Fr + 260;
    Rest := Fr + 372;
    If HasFxsr Then Rest := Rest + 512;
    MemL[0:Fr + 252] := Cur^.Blk[0];
    MemL[0:Fr + 256] := Cur^.Blk[1];
  End
  Else
  Begin
    Sc := Fr + 8;
    MemL[0:Fr + 96] := Cur^.Blk[1];            { extramask }
    Fpu := Fr + 100;
    Rest := Fr + 212;
    If HasFxsr Then Rest := Rest + 512;
  End;
  PutSigContext(Sc, F, Cur^.Blk[0], 0);
  MemL[0:Sc + 76] := Fpu;
  If HasFxsr Then
  Begin
    FxSaveTo(Fpu + 112);
    MemW[0:Fpu + 110] := 0;                 { magic : etat FXSR present }
  End
  Else
  Begin
    SaveFpu(Fpu);
    LoadFpu(Fpu);
  End;
  InitFpu;
  If (Fl And SA_RESTORER) <> 0 Then MemL[0:Fr] := Sg^.Restorer[Sig]
  Else
  Begin
    MemL[0:Fr] := Rest;
    If Rt Then
    Begin
      Mem[0:Rest] := $B8; MemL[0:Rest + 1] := 173;       { mov eax,173 }
      Mem[0:Rest + 5] := $CD; Mem[0:Rest + 6] := $80;    { int 80h }
    End
    Else
    Begin
      Mem[0:Rest] := $58;                                { pop eax }
      Mem[0:Rest + 1] := $B8; MemL[0:Rest + 2] := 119;   { mov eax,119 }
      Mem[0:Rest + 6] := $CD; Mem[0:Rest + 7] := $80;    { int 80h }
    End;
  End;
  If KDebug Then KLog('setupframe fr=' + HexStr(Fr, 8) + ' sc=' + HexStr(Sc, 8)
      + ' eip=' + HexStr(F^.Eip, 8) + ' h=' + HexStr(H, 8) + ' rt='
      + IntStr(Ord(Rt)) + ' rest=' + HexStr(MemL[0:Fr], 8));
  { registres au debut du gestionnaire }
  F^.UserEsp := Fr;
  F^.Eip := H;
  F^.Eflags := F^.Eflags And Not $100;
  F^.Eax := Sig;
  If Rt Then
  Begin
    F^.Edx := Fr + 16;
    F^.Ecx := Fr + 144;
  End
  Else
  Begin
    F^.Edx := 0; F^.Ecx := 0;
  End;
  F^.Cs := SelUCode; F^.Ds := SelUData; F^.Es := SelUData;
  F^.Ss := SelUData;
  { masque pendant l'execution du gestionnaire }
  Cur^.Blk[0] := Cur^.Blk[0] Or Sg^.MaskLo[Sig];
  Cur^.Blk[1] := Cur^.Blk[1] Or Sg^.MaskHi[Sig];
  If (Fl And SA_NODEFER) = 0 Then
  Begin
    Cur^.Blk[0] := Cur^.Blk[0] Or SigLoBit(Sig);
    Cur^.Blk[1] := Cur^.Blk[1] Or SigHiBit(Sig);
  End;
  Cur^.Blk[0] := Cur^.Blk[0] And Not UnblockableLo;
  If (Fl And SA_RESETHAND) <> 0 Then
  Begin
    Sg^.Handler[Sig] := SIG_DFL;
    Sg^.Flags[Sig] := Sg^.Flags[Sig] And Not SA_SIGINFO;
  End;
  SetupFrame := True;
End;

{ Fin de processus tue par un signal }
Procedure DieBySignal(Sig : LongInt; Core : Boolean);
Var C : LongInt;
Begin
  C := Sig;
  If Core Then C := C Or $80;
  If (Sig = SIGSEGV) Or (Sig = SIGILL) Or (Sig = SIGBUS) Or (Sig = SIGFPE) Then
    KLog('pid ' + IntStr(Cur^.Pid) + ' tue par le signal ' + IntStr(Sig));
  DoExit(C);
End;

{ Remise des signaux au retour en mode utilisateur ; F = cadre utilisateur }
Procedure HandleSignals(F : PFrame);
Var Sig, H, Act, Fl : LongInt; Restart : Boolean;
Begin
  If Cur^.Sig = Nil Then Exit;
  While True Do
  Begin
    Sig := DequeueSignal(Cur);
    If Sig = 0 Then Break;
    H := Cur^.Sig^.Handler[Sig];
    Fl := Cur^.Sig^.Flags[Sig];
    Act := -1;
    If H = SIG_IGN Then Continue;
    If H = SIG_DFL Then
    Begin
      Act := DefaultAction(Sig);
      If Cur^.Pid = 1 Then
      Begin
        If (Sig = SIGSEGV) Or (Sig = SIGILL) Or (Sig = SIGBUS)
            Or (Sig = SIGFPE) Then
          KPanic('Attempted to kill init ! (signal ' + IntStr(Sig) + ')');
        Continue;
      End;
      Case Act Of
        0, 4 : Continue;
        1 : DieBySignal(Sig, False);
        2 : DieBySignal(Sig, True);
        3 :
          Begin
            Cur^.State := TsStopped;
            Cur^.ExitCode := Sig;
            Cur^.ReapPending := 1;
            If Cur^.Parent <> Nil Then
            Begin
              SendSig(Cur^.Parent, SIGCHLD);
              WakeUp(LongInt(Cur^.Parent));
            End;
            Schedule;
            Continue;
          End;
      End;
    End;
    { gestionnaire utilisateur : reprise d'appel systeme ? }
    If (F^.Vec = VecSyscall) And (F^.Eax = -ERESTARTSYS) Then
    Begin
      If (Fl And SA_RESTART) <> 0 Then
      Begin
        F^.Eax := F^.Err;
        F^.Eip := F^.Eip - 2;
      End
      Else F^.Eax := -EINTR;
    End;
    If Not SetupFrame(F, Sig) Then
    Begin
      Cur^.Sig^.Handler[Sig] := SIG_DFL;
      DieBySignal(SIGSEGV, True);
    End;
    Exit;
  End;
  { aucun gestionnaire : reprise silencieuse d'un appel interrompu }
  If (F^.Vec = VecSyscall) And (F^.Eax = -ERESTARTSYS) Then
  Begin
    F^.Eax := F^.Err;
    F^.Eip := F^.Eip - 2;
  End;
End;

{ sigreturn / rt_sigreturn : retourne la valeur de EAX restauree }
Function DoSigreturn(F : PFrame; Rt : Boolean) : LongInt;
Var Sg, Fl, Fp : LongInt;
Begin
  If Rt Then Sg := F^.UserEsp - 4 + 164 Else Sg := F^.UserEsp;
  If Not EnsureUser(Sg, SigCtxSize, False) Then
  Begin
    DieBySignal(SIGSEGV, False);
    DoSigreturn := 0;
    Exit;
  End;
  F^.Gs := MemL[0:Sg] And $FFFF; F^.Fs := MemL[0:Sg + 4] And $FFFF;
  F^.Es := SelUData; F^.Ds := SelUData;
  F^.Edi := MemL[0:Sg + 16]; F^.Esi := MemL[0:Sg + 20];
  F^.Ebp := MemL[0:Sg + 24]; F^.UserEsp := MemL[0:Sg + 28];
  F^.Ebx := MemL[0:Sg + 32]; F^.Edx := MemL[0:Sg + 36];
  F^.Ecx := MemL[0:Sg + 40]; F^.Eax := MemL[0:Sg + 44];
  F^.Eip := MemL[0:Sg + 56];
  If KDebug Then KLog('sigreturn sg=' + HexStr(Sg, 8) + ' eip='
      + HexStr(F^.Eip, 8) + ' esp=' + HexStr(F^.UserEsp, 8) + ' usp0='
      + HexStr(F^.UserEsp, 8));
  Fl := MemL[0:Sg + 64];
  F^.Eflags := (Fl And $0DD5) Or $202;
  F^.Cs := SelUCode; F^.Ss := SelUData;
  If Rt Then
  Begin
    Cur^.Blk[0] := MemL[0:Sg + 88] And Not UnblockableLo;
    Cur^.Blk[1] := MemL[0:Sg + 92];
  End
  Else
  Begin
    Cur^.Blk[0] := MemL[0:Sg + 80] And Not UnblockableLo;
    Cur^.Blk[1] := MemL[0:Sg + SigCtxSize];
  End;
  Fp := MemL[0:Sg + 76];
  If Fp <> 0 Then
  Begin
    If HasFxsr And EnsureUser(Fp, 624, False) And (MemW[0:Fp + 110] = 0) Then
      FxLoadFrom(Fp + 112)
    Else If EnsureUser(Fp, 108, False) Then FrstorAt(Fp);
  End;
  DoSigreturn := F^.Eax;
End;

{ ==================================================================== }
{ Partie 11 - Couche bloc : cache de tampons, ramdisk, disque IDE/ATA }
{ ==================================================================== }

Const
  MajRam      = 1;              { /dev/ram0..3 }
  MajIde0     = 3;              { /dev/hda, hdb (partitions 1..63) }
  MajIde1     = 22;             { /dev/hdc, hdd }
  BufHash     = 256;
  BufMaxCount = 2048;           { tampons au plus }
  BvValid     = 1;
  BvDirty     = 2;
  RamMaxKb    = 4096;

Type
  PBuf = ^TBuf;
  TBuf = Record
    Dev, Block, Size : LongInt;
    Count, Flags     : LongInt;
    Data             : LongInt;
    HNext, Next      : PBuf;
    Age              : LongInt;
  End;

Var
  BufTab      : Array[0..BufHash - 1] Of PBuf;
  BufAll      : PBuf;
  BufCount    : LongInt;
  RamBase     : LongInt;        { ramdisk : adresse virtuelle du disque }
  RamSectors  : LongInt;
  RamSizeKb   : LongInt;
  DiskPresent : Array[0..3] Of Boolean;
  DiskSectors : Array[0..3] Of LongInt;
  DiskModel   : Array[0..159] Of Byte;
  PartStart   : Array[0..63] Of LongInt;
  PartSize    : Array[0..63] Of LongInt;
  IdeIdBuf    : Array[0..255] Of Word;
  BlkReads, BlkWrites : LongInt;

{ ---- Ramdisk ---- }

Procedure RamInit;
Var O : LongInt;
Begin
  RamBase := 0;
  RamSectors := 0;
  If RamSizeKb <= 0 Then RamSizeKb := 2048;
  If RamSizeKb > RamMaxKb Then RamSizeKb := RamMaxKb;
  O := OrderFor(RamSizeKb * 1024);
  RamBase := AllocPages(O);
  If RamBase = 0 Then
  Begin
    RamSizeKb := RamSizeKb Div 4;
    O := OrderFor(RamSizeKb * 1024);
    RamBase := AllocPages(O);
  End;
  If RamBase <> 0 Then
  Begin
    MemFill(RamBase, 0, RamSizeKb * 1024);
    RamSectors := RamSizeKb * 2;
  End;
End;

{ ---- Disque IDE : acces PIO, 28 bits ---- }

Function IdeBase(D : LongInt) : LongInt;
Begin
  If D < 2 Then IdeBase := $1F0 Else IdeBase := $170;
End;

Function IdeCtl(D : LongInt) : LongInt;
Begin
  If D < 2 Then IdeCtl := $3F6 Else IdeCtl := $376;
End;

{ Attendre que (statut And Mask) = Val ; retourne le statut ou -1 }
Function IdeWait(Base, Mask, Val : LongInt) : LongInt;
Var N, S : LongInt;
Begin
  N := 0;
  While N < 400000 Do
  Begin
    S := Port[Base + 7];
    If (S And Mask) = Val Then
    Begin
      IdeWait := S;
      Exit;
    End;
    Inc(N);
  End;
  IdeWait := -1;
End;

Procedure InWords(P, Buf, Words : LongInt);
Begin
  asm
    push edi
    mov edx,P
    mov edi,Buf
    mov ecx,Words
    cld
    rep insw
    pop edi
  end;
End;

Procedure OutWords(P, Buf, Words : LongInt);
Begin
  asm
    push esi
    mov edx,P
    mov esi,Buf
    mov ecx,Words
    cld
    rep outsw
    pop esi
  end;
End;

Procedure IdeSelect(D, Lba, Count : LongInt);
Var B : LongInt;
Begin
  B := IdeBase(D);
  Port[B + 6] := $E0 Or ((D And 1) Shl 4) Or ((Lba Shr 24) And $0F);
  Port[B + 2] := Count And $FF;
  Port[B + 3] := Lba And $FF;
  Port[B + 4] := (Lba Shr 8) And $FF;
  Port[B + 5] := (Lba Shr 16) And $FF;
End;

Function IdeReadSectors(D, Lba, Count, Buf : LongInt) : LongInt;
Var B, S, I : LongInt;
Begin
  B := IdeBase(D);
  IdeReadSectors := -EIO;
  For I := 0 To Count - 1 Do
  Begin
    If IdeWait(B, $80, 0) < 0 Then Exit;
    IdeSelect(D, Lba + I, 1);
    Port[B + 7] := $20;
    S := IdeWait(B, $88, $08);
    If (S < 0) Or ((S And $21) <> 0) Then Exit;
    InWords(B, Buf + I * 512, 256);
  End;
  IdeReadSectors := 0;
End;

Function IdeWriteSectors(D, Lba, Count, Buf : LongInt) : LongInt;
Var B, S, I : LongInt;
Begin
  B := IdeBase(D);
  IdeWriteSectors := -EIO;
  For I := 0 To Count - 1 Do
  Begin
    If IdeWait(B, $80, 0) < 0 Then Exit;
    IdeSelect(D, Lba + I, 1);
    Port[B + 7] := $30;
    S := IdeWait(B, $88, $08);
    If (S < 0) Or ((S And $21) <> 0) Then Exit;
    OutWords(B, Buf + I * 512, 256);
    If IdeWait(B, $80, 0) < 0 Then Exit;
  End;
  Port[B + 7] := $E7;                  { vider le cache }
  IdeWait(B, $80, 0);
  IdeWriteSectors := 0;
End;

{ Identifier le lecteur D (0 hda, 1 hdb, 2 hdc, 3 hdd) }
Procedure IdeProbe(D : LongInt);
Var B, S, I, W : LongInt;
Begin
  DiskPresent[D] := False;
  B := IdeBase(D);
  Port[IdeCtl(D)] := $02;                 { pas d'interruption }
  Port[B + 6] := $A0 Or ((D And 1) Shl 4);
  { laisser le temps au lecteur de repondre }
  For I := 1 To 1000 Do S := Port[B + 7];
  If (S = $FF) Or (S = 0) Then Exit;
  Port[B + 2] := 0; Port[B + 3] := 0; Port[B + 4] := 0; Port[B + 5] := 0;
  Port[B + 7] := $EC;                     { IDENTIFY }
  S := Port[B + 7];
  If S = 0 Then Exit;
  If IdeWait(B, $80, 0) < 0 Then Exit;
  If (Port[B + 4] <> 0) Or (Port[B + 5] <> 0) Then Exit;   { ATAPI/autre }
  S := IdeWait(B, $09, $08);
  If (S < 0) Or ((S And 1) <> 0) Then Exit;
  InWords(B, LongInt(@IdeIdBuf[0]), 256);
  DiskSectors[D] := IdeIdBuf[60] Or (IdeIdBuf[61] Shl 16);
  If DiskSectors[D] = 0 Then Exit;
  For I := 0 To 19 Do
  Begin
    W := IdeIdBuf[27 + I];
    DiskModel[D * 40 + I * 2] := W Shr 8;
    DiskModel[D * 40 + I * 2 + 1] := W And $FF;
  End;
  DiskPresent[D] := True;
  PartStart[D * 16] := 0;
  PartSize[D * 16] := DiskSectors[D];
End;

{ Lire la table de partitions MBR du disque D }
Procedure ReadPartitions(D : LongInt);
Var Buf, I, T, N, Next, Base, Lba, Ext, Cnt : LongInt;
Begin
  Buf := AllocPages(0);
  If Buf = 0 Then Exit;
  If IdeReadSectors(D, 0, 1, Buf) <> 0 Then
  Begin
    FreePages(Buf, 0);
    Exit;
  End;
  If MemW[0:Buf + 510] <> $AA55 Then
  Begin
    FreePages(Buf, 0);
    Exit;
  End;
  Ext := 0;
  For I := 0 To 3 Do
  Begin
    T := Mem[0:Buf + 446 + I * 16 + 4];
    If T <> 0 Then
    Begin
      PartStart[D * 16 + I + 1] := MemL[0:Buf + 446 + I * 16 + 8];
      PartSize[D * 16 + I + 1] := MemL[0:Buf + 446 + I * 16 + 12];
      If (T = 5) Or (T = $F) Or (T = $85) Then Ext := PartStart[D * 16 + I + 1];
    End;
  End;
  { partitions logiques (une chaine de tables) }
  N := 5;
  If Ext <> 0 Then
  Begin
    Base := Ext;
    Lba := Ext;
    Cnt := 0;
    While (Cnt < 12) And (N < 16) Do
    Begin
      If IdeReadSectors(D, Lba, 1, Buf) <> 0 Then Break;
      If MemW[0:Buf + 510] <> $AA55 Then Break;
      If Mem[0:Buf + 446 + 4] <> 0 Then
      Begin
        PartStart[D * 16 + N] := Lba + MemL[0:Buf + 446 + 8];
        PartSize[D * 16 + N] := MemL[0:Buf + 446 + 12];
        Inc(N);
      End;
      Next := MemL[0:Buf + 446 + 16 + 8];
      If (Mem[0:Buf + 446 + 16 + 4] = 0) Or (Next = 0) Then Break;
      Lba := Base + Next;
      Inc(Cnt);
    End;
  End;
  FreePages(Buf, 0);
End;

Procedure IdeInit;
Var D, P : LongInt;
Begin
  For D := 0 To 3 Do
  Begin
    DiskPresent[D] := False;
    For P := 0 To 15 Do
    Begin
      PartStart[D * 16 + P] := 0;
      PartSize[D * 16 + P] := 0;
    End;
  End;
  For D := 0 To 3 Do IdeProbe(D);
  For D := 0 To 3 Do
    If DiskPresent[D] Then ReadPartitions(D);
End;

{ ---- Interface des peripheriques blocs (par numero majeur) ---- }

{ Disque et partition d'un peripherique IDE : retourne le disque (0..3) ou
  -1 ; Part recoit le numero de partition (0 = disque entier) }
Function IdeDevice(Maj, Min : LongInt; Var Part : LongInt) : LongInt;
Var D : LongInt;
Begin
  IdeDevice := -1;
  If Maj = MajIde0 Then D := Min Shr 6
  Else If Maj = MajIde1 Then D := 2 + (Min Shr 6)
  Else Exit;
  Part := Min And 63;
  If Part > 15 Then Exit;
  If (D < 0) Or (D > 3) Then Exit;
  If Not DiskPresent[D] Then Exit;
  If PartSize[D * 16 + Part] = 0 Then Exit;
  IdeDevice := D;
End;

{ Taille en secteurs de 512 octets (0 si le peripherique n'existe pas) }
Function BlkSectors(Dev : LongInt) : LongInt;
Var Maj, Min, D, P : LongInt;
Begin
  Maj := (Dev Shr 8) And $FFF;
  Min := Dev And $FF;
  BlkSectors := 0;
  If Maj = MajRam Then
  Begin
    If Min = 0 Then BlkSectors := RamSectors;
    Exit;
  End;
  D := IdeDevice(Maj, Min, P);
  If D >= 0 Then BlkSectors := PartSize[D * 16 + P];
End;

Function BlkRW(Dev, Sector, Count, Buf : LongInt; Write : Boolean) : LongInt;
Var Maj, Min, D, P, Total : LongInt;
Begin
  Maj := (Dev Shr 8) And $FFF;
  Min := Dev And $FF;
  BlkRW := -ENXIO;
  Total := BlkSectors(Dev);
  If Total = 0 Then Exit;
  If (Sector < 0) Or (Sector + Count > Total) Then
  Begin
    BlkRW := -EIO;
    Exit;
  End;
  If Maj = MajRam Then
  Begin
    If Write Then MemCopy(RamBase + Sector * 512, Buf, Count * 512)
    Else MemCopy(Buf, RamBase + Sector * 512, Count * 512);
    BlkRW := 0;
    Exit;
  End;
  D := IdeDevice(Maj, Min, P);
  If D < 0 Then Exit;
  Sector := Sector + PartStart[D * 16 + P];
  If Write Then
  Begin
    Inc(BlkWrites);
    BlkRW := IdeWriteSectors(D, Sector, Count, Buf);
  End
  Else
  Begin
    Inc(BlkReads);
    BlkRW := IdeReadSectors(D, Sector, Count, Buf);
  End;
End;

{ ---- Cache de tampons ---- }

Function BufHashOf(Dev, Block : LongInt) : LongInt;
Begin
  BufHashOf := ((Dev * 31) + Block) And (BufHash - 1);
End;

Function BufFind(Dev, Block, Size : LongInt) : PBuf;
Var B : PBuf;
Begin
  B := BufTab[BufHashOf(Dev, Block)];
  While B <> Nil Do
  Begin
    If (B^.Dev = Dev) And (B^.Block = Block) And (B^.Size = Size) Then
    Begin
      BufFind := B;
      Exit;
    End;
    B := B^.HNext;
  End;
  BufFind := Nil;
End;

Function BufWrite(B : PBuf) : LongInt;
Var R : LongInt;
Begin
  R := BlkRW(B^.Dev, (B^.Block * B^.Size) Div 512, B^.Size Div 512, B^.Data,
      True);
  If R = 0 Then B^.Flags := B^.Flags And Not BvDirty;
  BufWrite := R;
End;

Procedure BufFree(B : PBuf);
Var P, Q : PBuf; H : LongInt;
Begin
  H := BufHashOf(B^.Dev, B^.Block);
  P := BufTab[H]; Q := Nil;
  While (P <> Nil) And (P <> B) Do
  Begin
    Q := P;
    P := P^.HNext;
  End;
  If P = B Then
    If Q = Nil Then BufTab[H] := B^.HNext Else Q^.HNext := B^.HNext;
  P := BufAll; Q := Nil;
  While (P <> Nil) And (P <> B) Do
  Begin
    Q := P;
    P := P^.Next;
  End;
  If P = B Then
    If Q = Nil Then BufAll := B^.Next Else Q^.Next := B^.Next;
  If B^.Size >= 2048 Then FreePages(B^.Data, 0) Else KFree(B^.Data);
  KFree(LongInt(B));
  Dec(BufCount);
End;

{ Recuperer de la place : liberer les tampons non utilises les plus anciens }
Procedure BufShrink;
Var B, N : PBuf; Limit : LongInt;
Begin
  Limit := Jiffies - 6000;
  B := BufAll;
  While (B <> Nil) And (BufCount > BufMaxCount - 64) Do
  Begin
    N := B^.Next;
    If (B^.Count = 0) And (B^.Age - Limit < 0) Then
    Begin
      If (B^.Flags And BvDirty) <> 0 Then BufWrite(B);
      BufFree(B);
    End;
    B := N;
  End;
  B := BufAll;
  While (B <> Nil) And (BufCount > BufMaxCount - 64) Do
  Begin
    N := B^.Next;
    If B^.Count = 0 Then
    Begin
      If (B^.Flags And BvDirty) <> 0 Then BufWrite(B);
      BufFree(B);
    End;
    B := N;
  End;
End;

{ Tampon du bloc (sans lecture) ; Count est incremente }
Function BGetBlk(Dev, Block, Size : LongInt) : PBuf;
Var B : PBuf; H : LongInt;
Begin
  B := BufFind(Dev, Block, Size);
  If B <> Nil Then
  Begin
    Inc(B^.Count);
    B^.Age := Jiffies;
    BGetBlk := B;
    Exit;
  End;
  If BufCount >= BufMaxCount Then BufShrink;
  B := Pointer(KMallocZ(SizeOf(TBuf)));
  BGetBlk := Nil;
  If B = Nil Then Exit;
  If Size >= 2048 Then B^.Data := AllocPages(0) Else B^.Data := KMalloc(Size);
  If B^.Data = 0 Then
  Begin
    KFree(LongInt(B));
    Exit;
  End;
  B^.Dev := Dev; B^.Block := Block; B^.Size := Size;
  B^.Count := 1; B^.Flags := 0; B^.Age := Jiffies;
  H := BufHashOf(Dev, Block);
  B^.HNext := BufTab[H];
  BufTab[H] := B;
  B^.Next := BufAll;
  BufAll := B;
  Inc(BufCount);
  BGetBlk := B;
End;

{ Tampon valide du bloc (lu au besoin) ; Nil en cas d'erreur d'E/S }
Function BRead(Dev, Block, Size : LongInt) : PBuf;
Var B : PBuf;
Begin
  B := BGetBlk(Dev, Block, Size);
  BRead := B;
  If B = Nil Then Exit;
  If (B^.Flags And BvValid) = 0 Then
  Begin
    If BlkRW(Dev, (Block * Size) Div 512, Size Div 512, B^.Data, False)
        <> 0 Then
    Begin
      Dec(B^.Count);
      BufFree(B);
      BRead := Nil;
      Exit;
    End;
    B^.Flags := B^.Flags Or BvValid;
  End;
End;

Procedure BDirty(B : PBuf);
Begin
  B^.Flags := B^.Flags Or BvDirty Or BvValid;
End;

Procedure BRelease(B : PBuf);
Begin
  If B^.Count > 0 Then Dec(B^.Count);
End;

{ Ecrire tous les tampons modifies (Dev = 0 : tous) }
Procedure BSync(Dev : LongInt);
Var B : PBuf;
Begin
  B := BufAll;
  While B <> Nil Do
  Begin
    If ((B^.Flags And BvDirty) <> 0) And ((Dev = 0) Or (B^.Dev = Dev))
        Then BufWrite(B);
    B := B^.Next;
  End;
End;

{ Invalider les tampons d'un peripherique (apres umount) }
Procedure BInvalidate(Dev : LongInt);
Var B, N : PBuf;
Begin
  B := BufAll;
  While B <> Nil Do
  Begin
    N := B^.Next;
    If (B^.Dev = Dev) And (B^.Count = 0) Then
    Begin
      If (B^.Flags And BvDirty) <> 0 Then BufWrite(B);
      BufFree(B);
    End;
    B := N;
  End;
End;

Function BDirtyCount : LongInt;
Var B : PBuf; N : LongInt;
Begin
  N := 0;
  B := BufAll;
  While B <> Nil Do
  Begin
    If (B^.Flags And BvDirty) <> 0 Then Inc(N);
    B := B^.Next;
  End;
  BDirtyCount := N;
End;

{ Fil d'ecriture differee : ecrit les tampons modifies toutes les 5 s }
Procedure BdFlushThread;
Begin
  While True Do
  Begin
    SleepTicks(5 * HZ);
    If BDirtyCount > 0 Then BSync(0);
  End;
End;

Procedure InitBlock;
Var I : LongInt;
Begin
  For I := 0 To BufHash - 1 Do BufTab[I] := Nil;
  BufAll := Nil;
  BufCount := 0;
  RamInit;
  IdeInit;
End;

{ ==================================================================== }
{ Partie 12 - VFS : inodes, dentries, fichiers, chemins, montages      }
{ ==================================================================== }

Const
  S_IFMT = $F000; S_IFSOCK = $C000; S_IFLNK = $A000; S_IFREG = $8000;
  S_IFBLK = $6000; S_IFDIR = $4000; S_IFCHR = $2000; S_IFIFO = $1000;
  S_ISUID = $800; S_ISGID = $400; S_ISVTX = $200;

  O_ACCMODE = 3; O_RDONLY = 0; O_WRONLY = 1; O_RDWR = 2;
  O_CREAT = $40; O_EXCL = $80; O_NOCTTY = $100; O_TRUNC = $200;
  O_APPEND = $400; O_NONBLOCK = $800; O_SYNC = $1000; O_DIRECTORY = $10000;
  O_NOFOLLOW = $20000; O_LARGEFILE = $8000; O_CLOEXEC = $80000;

  MS_RDONLY = 1; MS_REMOUNT = 32; MS_BIND = 4096;

  { Operations sur les inodes (indices dans la table d'adresses) }
  IoLookup = 0; IoCreate = 1; IoMkdir = 2; IoMknod = 3; IoUnlink = 4;
  IoRmdir = 5; IoRename = 6; IoLink = 7; IoSymlink = 8; IoReadlink = 9;
  IoTruncate = 10; IoSetattr = 11;
  { Operations sur les fichiers ouverts }
  FoRead = 0; FoWrite = 1; FoReaddir = 2; FoIoctl = 3; FoPoll = 4;
  FoOpen = 5; FoRelease = 6; FoLlseek = 7; FoFsync = 8;
  { Operations sur les superblocs }
  SoReadInode = 0; SoPutInode = 1; SoWriteInode = 2; SoStatfs = 3;
  SoSync = 4; SoUmount = 5; SoClearInode = 6; SoRemount = 7;

  MaxSupers   = 16;
  MaxFsTypes  = 8;
  DentHash    = 512;
  MaxSymlinks = 8;
  InoHash     = 256;
  MAY_EXEC = 1; MAY_WRITE = 2; MAY_READ = 4;
  POLLIN = 1; POLLOUT = 4; POLLERR = 8; POLLHUP = 16; POLLNVAL = 32;
  DT_UNKNOWN = 0; DT_FIFO = 1; DT_CHR = 2; DT_DIR = 4; DT_BLK = 6;
  DT_REG = 8; DT_LNK = 10;

Type
  PSuper  = ^TSuper;
  PInode  = ^TInode;
  PDentry = ^TDentry;
  PFile   = ^TFile;

  TSuper = Record
    Dev, FsType, Flags, BlockSize : LongInt;
    Root, Covered : PDentry;
        { racine du systeme monte, point de montage }
    SOps          : LongInt;
    Priv, Priv2   : LongInt;
    RefTotal      : LongInt;        { references de dentries }
    DevName       : LongInt;        { adresse d'une chaine Pascal }
    Used          : LongInt;
    NextIno       : LongInt;
    Pinned        : LongInt;        { inodes epingles (tmpfs) }
  End;

  TInode = Record
    Sb              : PSuper;
    Ino, Mode, Nlink, Uid, Gid : LongInt;
    Size, Atime, Mtime, Ctime  : LongInt;
    Rdev, Blocks, Count, Dev   : LongInt;
    IOps, FOps      : LongInt;
    Priv, Priv2     : LongInt;
    Next            : PInode;
    HNext           : PInode;
    Pipe            : LongInt;
    Dirty           : LongInt;
  End;

  TDentry = Record
    Parent, Next    : PDentry;     { Next : chaine de hachage }
    Inode           : PInode;
    Sb              : PSuper;
    NamePtr         : LongInt;
    Count, NChild   : LongInt;
    Mounted         : PSuper;
    Bind            : PDentry;     { point de montage : racine du bind mount }
    BindMp          : PDentry;     { racine d'un bind mount : son point de montage }
    Hashed          : LongInt;
    AllNext         : PDentry;
  End;

  TFile = Record
    Dentry          : PDentry;
    Inode           : PInode;
    Pos, Flags, Mode, Count : LongInt;
    FOps            : LongInt;
    Priv            : LongInt;
    Owner           : LongInt;     { pid pour F_SETOWN }
  End;

Var
  Supers      : Array[0..MaxSupers - 1] Of PSuper;
  FsNames     : Array[0..MaxFsTypes - 1] Of String;
  FsMount     : Array[0..MaxFsTypes - 1] Of LongInt;
      { adresses des fonctions de montage }
  NFsTypes    : LongInt;
  DentTab     : Array[0..DentHash - 1] Of PDentry;
  DentAll     : PDentry;
  DentCount   : LongInt;
  InodeAll    : PInode;
  InodeTab    : Array[0..InoHash - 1] Of PInode;
  InodeCount  : LongInt;
  FileCount   : LongInt;
  RootDentry  : PDentry;
  NextAnonDev : LongInt;
  LinkDepth   : LongInt;
  BindCount   : LongInt;       { bind mounts crees (alias de dentries) }
  ChrOps      : Array[0..255] Of LongInt;
      { tables FoXxx par majeur }
  TmpIOps, TmpFOps, TmpDirFOps, TmpLnkIOps : Array[0..15] Of LongInt;
  BlkFOpsAddr, PipeFOpsAddr : LongInt;

Function InodeRef(I : LongInt) : LongInt;
Var P : PInode;
Begin
  P := Pointer(I);
  Inc(P^.Count);
  InodeRef := I;
End;

Function GetOp(Tab, K : LongInt) : LongInt;
Begin
  If Tab = 0 Then GetOp := 0 Else GetOp := MemL[0:Tab + K * 4];
End;

Function NowSec : LongInt;
Begin
  NowSec := XTime;
End;

{ ---- Superblocs ---- }

Function SuperNew(FsType : LongInt) : PSuper;
Var S : PSuper; I : LongInt;
Begin
  SuperNew := Nil;
  For I := 0 To MaxSupers - 1 Do
    If Supers[I] = Nil Then
    Begin
      S := Pointer(KMallocZ(SizeOf(TSuper)));
      If S = Nil Then Exit;
      S^.FsType := FsType;
      S^.Dev := 0;
      S^.BlockSize := 1024;
      S^.NextIno := 1;
      Supers[I] := S;
      SuperNew := S;
      Exit;
    End;
End;

{ ---- Inodes ---- }

Function InoHashOf(Sb : PSuper; Ino : LongInt) : LongInt;
Begin
  InoHashOf := (LongInt(Sb) Shr 4 + Ino * 7) And (InoHash - 1);
End;

{ Nouvel inode (compteur 1) ; non lie a un repertoire }
Function NewInode(Sb : PSuper; Mode : LongInt) : PInode;
Var I : PInode; H : LongInt;
Begin
  I := Pointer(KMallocZ(SizeOf(TInode)));
  NewInode := I;
  If I = Nil Then Exit;
  I^.Sb := Sb;
  I^.Ino := Sb^.NextIno;
  Inc(Sb^.NextIno);
  I^.Mode := Mode;
  I^.Nlink := 1;
  I^.Count := 1;
  I^.Dev := Sb^.Dev;
  I^.Uid := Cur^.Fsuid; I^.Gid := Cur^.Fsgid;
  I^.Atime := NowSec; I^.Mtime := I^.Atime; I^.Ctime := I^.Atime;
  I^.Next := InodeAll;
  InodeAll := I;
  H := InoHashOf(Sb, I^.Ino);
  I^.HNext := InodeTab[H];
  InodeTab[H] := I;
  Inc(InodeCount);
  { sticky : heritage du groupe non gere }
End;

Procedure InodeUnlinkList(I : PInode);
Var P, Q : PInode; H : LongInt;
Begin
  H := InoHashOf(I^.Sb, I^.Ino);
  P := InodeTab[H]; Q := Nil;
  While (P <> Nil) And (P <> I) Do
  Begin
    Q := P;
    P := P^.HNext;
  End;
  If P = I Then
    If Q = Nil Then InodeTab[H] := I^.HNext Else Q^.HNext := I^.HNext;
  P := InodeAll; Q := Nil;
  While (P <> Nil) And (P <> I) Do
  Begin
    Q := P;
    P := P^.Next;
  End;
  If P = I Then
    If Q = Nil Then InodeAll := I^.Next Else Q^.Next := I^.Next;
End;

{ Liberer un inode du cache (ecrit s'il est modifie, libere ses donnees
  privees par SoClearInode) }
Procedure InodeFreeOne(P : PInode);
Var Fn : LongInt;
Begin
  If P^.Dirty <> 0 Then
  Begin
    Fn := GetOp(P^.Sb^.SOps, SoWriteInode);
    If Fn <> 0 Then Call1(Fn, LongInt(P));
    P^.Dirty := 0;
  End;
  Fn := GetOp(P^.Sb^.SOps, SoClearInode);
  If Fn <> 0 Then Call1(Fn, LongInt(P));
  InodeUnlinkList(P);
  Dec(InodeCount);
  KFree(LongInt(P));
End;

{ Trop d'inodes en cache : liberer ceux des systemes de fichiers sur disque
  qui ne sont plus utilises (compteur 0) }
Procedure InodeShrink;
Var P, N : PInode;
Begin
  P := InodeAll;
  While (P <> Nil) And (InodeCount > 2000) Do
  Begin
    N := P^.Next;
    If (P^.Count = 0) And (P^.Nlink > 0)
        And (GetOp(P^.Sb^.SOps, SoClearInode) <> 0) Then InodeFreeOne(P);
    P := N;
  End;
End;

{ Inode (Sb, Ino) : en cache, ou lu par SoReadInode (compteur incremente) }
Function IGet(Sb : PSuper; Ino : LongInt) : PInode;
Var I : PInode; Fn : LongInt;
Begin
  I := InodeTab[InoHashOf(Sb, Ino)];
  While I <> Nil Do
  Begin
    If (I^.Sb = Sb) And (I^.Ino = Ino) Then
    Begin
      Inc(I^.Count);
      IGet := I;
      Exit;
    End;
    I := I^.HNext;
  End;
  IGet := Nil;
  Fn := GetOp(Sb^.SOps, SoReadInode);
  If Fn = 0 Then Exit;
  If InodeCount > 3000 Then InodeShrink;
  I := Pointer(KMallocZ(SizeOf(TInode)));
  If I = Nil Then Exit;
  I^.Sb := Sb; I^.Ino := Ino; I^.Count := 1; I^.Dev := Sb^.Dev;
  If Call1(Fn, LongInt(I)) <> 0 Then
  Begin
    KFree(LongInt(I));
    Exit;
  End;
  I^.Next := InodeAll;
  InodeAll := I;
  I^.HNext := InodeTab[InoHashOf(Sb, Ino)];
  InodeTab[InoHashOf(Sb, Ino)] := I;
  Inc(InodeCount);
  IGet := I;
End;

Procedure InodePut(I : LongInt);
Var P : PInode; Fn : LongInt;
Begin
  If I = 0 Then Exit;
  P := Pointer(I);
  Dec(P^.Count);
  If P^.Count > 0 Then Exit;
  If P^.Nlink <= 0 Then
  Begin
    Fn := GetOp(P^.Sb^.SOps, SoPutInode);
    If Fn <> 0 Then Call1(Fn, LongInt(P));
    InodeUnlinkList(P);
    Dec(InodeCount);
    KFree(LongInt(P));
  End
  Else If P^.Dirty <> 0 Then
  Begin
    Fn := GetOp(P^.Sb^.SOps, SoWriteInode);
    If Fn <> 0 Then Call1(Fn, LongInt(P));
    P^.Dirty := 0;
  End;
End;

Procedure IMarkDirty(I : PInode);
Var Fn : LongInt;
Begin
  I^.Dirty := 1;
  Fn := GetOp(I^.Sb^.SOps, SoWriteInode);
  If Fn <> 0 Then
  Begin
    Call1(Fn, LongInt(I));
    I^.Dirty := 0;
  End;
End;

{ Lecture d'un fichier par le noyau (exec, mappages) : octets lus ou -errno }
Function InodeReadAt(I, Buf, Pos, Cnt : LongInt) : LongInt;
Var F : TFile; Ino : PInode; Fn : LongInt;
Begin
  Ino := Pointer(I);
  Fn := GetOp(Ino^.FOps, FoRead);
  If Fn = 0 Then
  Begin
    InodeReadAt := -EINVAL;
    Exit;
  End;
  MemFill(LongInt(@F), 0, SizeOf(TFile));
  F.Inode := Ino;
  F.Pos := Pos;
  F.FOps := Ino^.FOps;
  F.Count := 1;
  InodeReadAt := Call3(Fn, LongInt(@F), Buf, Cnt);
End;

{ ---- Dentries ---- }

Function DName(D : PDentry) : String;
Var S : String; N, I : LongInt;
Begin
  S := '';
  If D^.NamePtr <> 0 Then
  Begin
    N := Mem[0:D^.NamePtr];
    For I := 1 To N Do S := S + Chr(Mem[0:D^.NamePtr + I]);
  End;
  DName := S;
End;

Function NameHash(Parent : PDentry; Const Nm : String) : LongInt;
Var H, I : LongInt;
Begin
  H := LongInt(Parent) Shr 4;
  For I := 1 To Length(Nm) Do H := H * 31 + Ord(Nm[I]);
  NameHash := (H And $7FFFFFFF) Mod DentHash;
End;

Procedure DentryGet(D : LongInt);
Var P : PDentry;
Begin
  If D = 0 Then Exit;
  P := Pointer(D);
  Inc(P^.Count);
  Inc(P^.Sb^.RefTotal);
End;

Procedure DentryUnhash(D : PDentry);
Var H : LongInt; P, Q : PDentry; Nm : String;
Begin
  If D^.Hashed = 0 Then Exit;
  Nm := DName(D);
  H := NameHash(D^.Parent, Nm);
  P := DentTab[H]; Q := Nil;
  While (P <> Nil) And (P <> D) Do
  Begin
    Q := P;
    P := P^.Next;
  End;
  If P = D Then
    If Q = Nil Then DentTab[H] := D^.Next Else Q^.Next := D^.Next;
  D^.Hashed := 0;
End;

Procedure DentryFree(D : PDentry);
Var P, Q : PDentry;
Begin
  DentryUnhash(D);
  P := DentAll; Q := Nil;
  While (P <> Nil) And (P <> D) Do
  Begin
    Q := P;
    P := P^.AllNext;
  End;
  If P = D Then
    If Q = Nil Then DentAll := D^.AllNext Else Q^.AllNext := D^.AllNext;
  If D^.Parent <> Nil Then Dec(D^.Parent^.NChild);
  If D^.NamePtr <> 0 Then KFree(D^.NamePtr);
  If D^.Inode <> Nil Then InodePut(LongInt(D^.Inode));
  Dec(DentCount);
  KFree(LongInt(D));
End;

Procedure DentryPut(D : LongInt);
Var P : PDentry; Par : PDentry;
Begin
  If D = 0 Then Exit;
  P := Pointer(D);
  Dec(P^.Count);
  Dec(P^.Sb^.RefTotal);
  If (P^.Count <= 0) And ((P^.Hashed = 0) Or (P^.Inode = Nil)) And (P^.NChild
      = 0) And (P^.Mounted = Nil) And (P^.Bind = Nil) Then
  Begin
    Par := P^.Parent;
    DentryFree(P);
  End;
End;

{ Nouveau dentry (compteur 1) pour Name sous Parent, avec l'inode (reference
  reprise) }
Function DentryNew(Parent : PDentry; Const Name : String; I : PInode;
    Sb : PSuper) : PDentry;
Var D : PDentry; H : LongInt; Nm : String;
Begin
  DentryNew := Nil;
  D := Pointer(KMallocZ(SizeOf(TDentry)));
  If D = Nil Then Exit;
  Nm := Name;
  D^.NamePtr := KMalloc(Length(Nm) + 1);
  If D^.NamePtr = 0 Then
  Begin
    KFree(LongInt(D));
    Exit;
  End;
  MemCopy(D^.NamePtr, LongInt(@Nm), Length(Nm) + 1);
  D^.Parent := Parent;
  D^.Inode := I;
  D^.Sb := Sb;
  D^.Count := 1;
  Inc(Sb^.RefTotal);
  D^.AllNext := DentAll;
  DentAll := D;
  Inc(DentCount);
  If Parent <> Nil Then
  Begin
    Inc(Parent^.NChild);
    H := NameHash(Parent, Nm);
    D^.Next := DentTab[H];
    DentTab[H] := D;
    D^.Hashed := 1;
  End;
  DentryNew := D;
End;

Function DentryFind(Parent : PDentry; Const Name : String) : PDentry;
Var D : PDentry; N : String;
Begin
  D := DentTab[NameHash(Parent, Name)];
  While D <> Nil Do
  Begin
    If D^.Parent = Parent Then
    Begin
      N := DName(D);
      If N = Name Then
      Begin
        DentryFind := D;
        Exit;
      End;
    End;
    D := D^.Next;
  End;
  DentryFind := Nil;
End;

{ Liberer des dentries inutilises (feuilles sans reference) quand ils
  deviennent trop nombreux }
Procedure DentryShrink;
Var D, N : PDentry; Pass : LongInt;
Begin
  For Pass := 1 To 3 Do
  Begin
    D := DentAll;
    While D <> Nil Do
    Begin
      N := D^.AllNext;
      If (D^.Count = 0) And (D^.NChild = 0) And (D^.Mounted = Nil)
         And (D^.Bind = Nil) And
         (D^.Sb^.Root <> D) Then DentryFree(D);
      D := N;
    End;
    If DentCount < 1500 Then Exit;
  End;
End;

{ ---- Permissions ---- }

Function InGroup(G : LongInt) : Boolean;
Var I : LongInt;
Begin
  InGroup := True;
  If G = Cur^.Fsgid Then Exit;
  For I := 0 To Cur^.NGroups - 1 Do
    If Cur^.Groups[I] = G Then Exit;
  InGroup := False;
End;

{ Controle d'acces Unix : 0 ou -EACCES ; Mask : 4 lecture, 2 ecriture, 1 exec }
Function InodePerm(I : PInode; Mask : LongInt) : LongInt;
Var M : LongInt;
Begin
  InodePerm := 0;
  If Cur^.Fsuid = 0 Then
  Begin
    If (Mask And MAY_EXEC) <> 0 Then
      If ((I^.Mode And S_IFMT) <> S_IFDIR) And ((I^.Mode And $49) = 0) Then
        InodePerm := -EACCES;
    Exit;
  End;
  If I^.Uid = Cur^.Fsuid Then M := (I^.Mode Shr 6) And 7
  Else If InGroup(I^.Gid) Then M := (I^.Mode Shr 3) And 7
  Else M := I^.Mode And 7;
  If (Mask And M) <> Mask Then InodePerm := -EACCES;
End;

Function IsDir(I : PInode) : Boolean;
Begin
  IsDir := (I^.Mode And S_IFMT) = S_IFDIR;
End;

{ ---- Recherche dans un repertoire (avec cache de dentries) ---- }

{ Chercher Name dans le repertoire Dir : dentry (compteur +1) ou erreur }
Function DLookup(Dir : PDentry; Const Name : String;
    Var Res : PDentry) : LongInt;
Var D : PDentry; Fn, R : LongInt; Nm : String; I : PInode;
Begin
  Res := Nil;
  D := DentryFind(Dir, Name);
  If D <> Nil Then
  Begin
    DentryGet(LongInt(D));
    Res := D;
    DLookup := 0;
    Exit;
  End;
  Fn := GetOp(Dir^.Inode^.IOps, IoLookup);
  If Fn = 0 Then
  Begin
    DLookup := -ENOENT;
    Exit;
  End;
  Nm := Name;
  I := Nil;
  R := Call3(Fn, LongInt(Dir^.Inode), LongInt(@Nm), LongInt(@I));
  If R <> 0 Then
  Begin
    DLookup := R;
    Exit;
  End;
  If DentCount > 2000 Then DentryShrink;
  D := DentryNew(Dir, Nm, I, Dir^.Sb);
  If D = Nil Then
  Begin
    InodePut(LongInt(I));
    DLookup := -ENOMEM;
    Exit;
  End;
  Res := D;
  DLookup := 0;
End;

{ Descendre dans un point de montage }
Function CrossMounts(D : PDentry) : PDentry;
Var N : PDentry;
Begin
  While (D^.Mounted <> Nil) Or (D^.Bind <> Nil) Do
  Begin
    If D^.Mounted <> Nil Then N := D^.Mounted^.Root Else N := D^.Bind;
    DentryGet(LongInt(N));
    DentryPut(LongInt(D));
    D := N;
  End;
  CrossMounts := D;
End;

{ Lire la cible d'un lien symbolique }
Function ReadLinkTarget(I : PInode; Var S : String) : LongInt;
Var Fn, N, K : LongInt; Buf : Array[0..259] Of Byte;
Begin
  S := '';
  Fn := GetOp(I^.IOps, IoReadlink);
  If Fn = 0 Then
  Begin
    ReadLinkTarget := -EINVAL;
    Exit;
  End;
  N := Call3(Fn, LongInt(I), LongInt(@Buf[0]), 255);
  If N < 0 Then
  Begin
    ReadLinkTarget := N;
    Exit;
  End;
  For K := 0 To N - 1 Do S := S + Chr(Buf[K]);
  ReadLinkTarget := 0;
End;

Function WalkFrom(Start : PDentry; Const Path : String; Follow : Boolean;
    Var Res : PDentry) : LongInt; Forward;

{ Resoudre un composant qui est un lien symbolique : D (reference reprise),
  Dir = repertoire contenant le lien. Retourne la cible dans Res }
Function FollowLink(Dir, D : PDentry; Var Res : PDentry) : LongInt;
Var Tgt : String; R : LongInt; Base : PDentry;
Begin
  If LinkDepth >= MaxSymlinks Then
  Begin
    DentryPut(LongInt(D));
    Res := Nil;
    FollowLink := -ELOOP;
    Exit;
  End;
  Inc(LinkDepth);
  R := ReadLinkTarget(D^.Inode, Tgt);
  DentryPut(LongInt(D));
  If R <> 0 Then
  Begin
    Dec(LinkDepth);
    Res := Nil;
    FollowLink := R;
    Exit;
  End;
  If (Length(Tgt) > 0) And (Tgt[1] = '/') Then Base := Cur^.Fs^.Root
      Else Base := Dir;
  R := WalkFrom(Base, Tgt, True, Res);
  Dec(LinkDepth);
  FollowLink := R;
End;

{ Resoudre Path a partir de Start (ou de la racine si Path commence par /).
  Follow : suivre un lien en dernier composant. Res : dentry (+1). }
Function WalkFrom(Start : PDentry; Const Path : String; Follow : Boolean;
    Var Res : PDentry) : LongInt;
Var CurD, Child, Nx : PDentry; I, J, N : LongInt; Nm : String; R : LongInt;
    Last, TrailSlash : Boolean; RootD : PDentry;
Begin
  Res := Nil;
  RootD := Cur^.Fs^.Root;
  CurD := Start;
  If (Length(Path) > 0) And (Path[1] = '/') Then CurD := RootD;
  DentryGet(LongInt(CurD));
  N := Length(Path);
  I := 1;
  While I <= N Do
  Begin
    While (I <= N) And (Path[I] = '/') Do Inc(I);
    If I > N Then Break;
    J := I;
    While (J <= N) And (Path[J] <> '/') Do Inc(J);
    Nm := Copy(Path, I, J - I);
    I := J;
    TrailSlash := False;
    While (J <= N) And (Path[J] = '/') Do Inc(J);
    Last := J > N;
    If Last And (J > I) Then TrailSlash := True;
    I := J;
    If Length(Nm) > 255 Then
    Begin
      DentryPut(LongInt(CurD));
      WalkFrom := -ENAMETOOLONG;
      Exit;
    End;
    If Nm = '.' Then Continue;
    If Not IsDir(CurD^.Inode) Then
    Begin
      DentryPut(LongInt(CurD));
      WalkFrom := -ENOTDIR;
      Exit;
    End;
    R := InodePerm(CurD^.Inode, MAY_EXEC);
    If R <> 0 Then
    Begin
      DentryPut(LongInt(CurD));
      WalkFrom := R;
      Exit;
    End;
    If Nm = '..' Then
    Begin
      If CurD <> RootD Then
      Begin
        While (CurD^.Sb^.Root = CurD) And (CurD^.Sb^.Covered <> Nil) And (CurD
            <> RootD) Do
        Begin
          Nx := CurD^.Sb^.Covered;
          DentryGet(LongInt(Nx));
          DentryPut(LongInt(CurD));
          CurD := Nx;
        End;
        If (CurD^.Parent <> Nil) And (CurD <> RootD) Then
        Begin
          Nx := CurD^.Parent;
          DentryGet(LongInt(Nx));
          DentryPut(LongInt(CurD));
          CurD := Nx;
        End;
      End;
      Continue;
    End;
    R := DLookup(CurD, Nm, Child);
    If R <> 0 Then
    Begin
      DentryPut(LongInt(CurD));
      WalkFrom := R;
      Exit;
    End;
    Child := CrossMounts(Child);
    If ((Child^.Inode^.Mode And S_IFMT) = S_IFLNK) And ((Not Last) Or Follow
        Or TrailSlash) Then
    Begin
      R := FollowLink(CurD, Child, Nx);
      If R <> 0 Then
      Begin
        DentryPut(LongInt(CurD));
        WalkFrom := R;
        Exit;
      End;
      Child := Nx;
    End;
    DentryPut(LongInt(CurD));
    CurD := Child;
    If TrailSlash And (Not IsDir(CurD^.Inode)) Then
    Begin
      DentryPut(LongInt(CurD));
      WalkFrom := -ENOTDIR;
      Exit;
    End;
  End;
  Res := CurD;
  WalkFrom := 0;
End;

{ Resoudre un chemin du processus courant }
Function PathWalk(Const Path : String; Follow : Boolean;
    Var Res : PDentry) : LongInt;
Begin
  If Path = '' Then
  Begin
    Res := Nil;
    PathWalk := -ENOENT;
    Exit;
  End;
  LinkDepth := 0;
  PathWalk := WalkFrom(Cur^.Fs^.Pwd, Path, Follow, Res);
End;

{ Resoudre le repertoire parent de Path et rendre le dernier composant ;
  Parent (+1). LastName vaut '' si le chemin est '/' }
Function WalkParent(Const Path : String; Var Parent : PDentry;
    Var LastName : String) : LongInt;
Var P : String; K, L : LongInt; Dirs : String;
Begin
  Parent := Nil;
  LastName := '';
  If Path = '' Then
  Begin
    WalkParent := -ENOENT;
    Exit;
  End;
  P := Path;
  While (Length(P) > 1) And (P[Length(P)] = '/') Do Delete(P, Length(P), 1);
  K := Length(P);
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  LastName := Copy(P, K + 1, 255);
  If K = 0 Then Dirs := '.'
  Else If K = 1 Then Dirs := '/'
  Else Dirs := Copy(P, 1, K - 1);
  If P = '/' Then
  Begin
    LastName := '';
    Dirs := '/';
  End;
  If Length(LastName) > 255 Then
  Begin
    WalkParent := -ENAMETOOLONG;
    Exit;
  End;
  LinkDepth := 0;
  L := WalkFrom(Cur^.Fs^.Pwd, Dirs, True, Parent);
  WalkParent := L;
  If L = 0 Then
    If Not IsDir(Parent^.Inode) Then
    Begin
      DentryPut(LongInt(Parent));
      Parent := Nil;
      WalkParent := -ENOTDIR;
    End;
End;

{ Chemin absolu d'un dentry (a partir de la racine du processus) }
Function DentryPath(D : PDentry) : String;
Var S, Nm : String; RootD, X : PDentry; N : LongInt;
Begin
  S := '';
  RootD := Cur^.Fs^.Root;
  X := D;
  N := 0;
  While (X <> RootD) And (N < 60) Do
  Begin
    While (X^.Sb^.Root = X) And (X^.Sb^.Covered <> Nil) And (X <> RootD)
        Do X := X^.Sb^.Covered;
    If (X = RootD) Or (X^.Parent = Nil) Then Break;
    Nm := DName(X);
    S := '/' + Nm + S;
    X := X^.Parent;
    Inc(N);
  End;
  If S = '' Then S := '/';
  DentryPath := S;
End;

{ ---- Fichiers ouverts ---- }

Function FileNew(D : PDentry; Flags : LongInt) : PFile;
Var F : PFile;
Begin
  F := Pointer(KMallocZ(SizeOf(TFile)));
  FileNew := F;
  If F = Nil Then Exit;
  F^.Dentry := D;
  F^.Inode := D^.Inode;
  F^.Flags := Flags;
  F^.Count := 1;
  F^.FOps := D^.Inode^.FOps;
  Inc(FileCount);
End;

Procedure FileGet(F : LongInt);
Var P : PFile;
Begin
  P := Pointer(F);
  Inc(P^.Count);
End;

Procedure FilePut(F : LongInt);
Var P : PFile; Fn : LongInt;
Begin
  If F = 0 Then Exit;
  P := Pointer(F);
  Dec(P^.Count);
  If P^.Count > 0 Then Exit;
  Fn := GetOp(P^.FOps, FoRelease);
  If Fn <> 0 Then Call1(Fn, F);
  If P^.Dentry <> Nil Then DentryPut(LongInt(P^.Dentry));
  Dec(FileCount);
  KFree(F);
End;

{ Descripteur : fichier ou Nil }
Function FdGet(Fd : LongInt) : PFile;
Begin
  If (Fd < 0) Or (Fd >= MaxFd) Then
  Begin
    FdGet := Nil;
    Exit;
  End;
  FdGet := Pointer(Cur^.Files^.Fd[Fd]);
End;

{ Installer F au plus petit descripteur >= Min : fd ou -EMFILE }
Function FdInstall(F : PFile; Min : LongInt; CloExec : Boolean) : LongInt;
Var I, Lim : LongInt;
Begin
  Lim := Cur^.RlimCur[RLIM_NOFILE];
  If Lim > MaxFd Then Lim := MaxFd;
  For I := Min To Lim - 1 Do
    If Cur^.Files^.Fd[I] = 0 Then
    Begin
      Cur^.Files^.Fd[I] := LongInt(F);
      If CloExec Then Cur^.Files^.CloseExec[I] := 1
          Else Cur^.Files^.CloseExec[I] := 0;
      FdInstall := I;
      Exit;
    End;
  FdInstall := -EMFILE;
End;

Function FdClose(Fd : LongInt) : LongInt;
Var F : LongInt;
Begin
  If (Fd < 0) Or (Fd >= MaxFd) Or (Cur^.Files^.Fd[Fd] = 0) Then
  Begin
    FdClose := -EBADF;
    Exit;
  End;
  F := Cur^.Files^.Fd[Fd];
  Cur^.Files^.Fd[Fd] := 0;
  Cur^.Files^.CloseExec[Fd] := 0;
  FilePut(F);
  FdClose := 0;
End;

{ ---- Operations de haut niveau ---- }

Function VfsRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var Fn : LongInt;
Begin
  If (F^.Flags And O_ACCMODE) = O_WRONLY Then
  Begin
    VfsRead := -EBADF;
    Exit;
  End;
  Fn := GetOp(F^.FOps, FoRead);
  If Fn = 0 Then
  Begin
    If IsDir(F^.Inode) Then VfsRead := -EISDIR Else VfsRead := -EINVAL;
    Exit;
  End;
  If Cnt = 0 Then
  Begin
    VfsRead := 0;
    Exit;
  End;
  VfsRead := Call3(Fn, LongInt(F), Buf, Cnt);
End;

Function VfsWrite(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var Fn : LongInt;
Begin
  If (F^.Flags And O_ACCMODE) = O_RDONLY Then
  Begin
    VfsWrite := -EBADF;
    Exit;
  End;
  Fn := GetOp(F^.FOps, FoWrite);
  If Fn = 0 Then
  Begin
    If IsDir(F^.Inode) Then VfsWrite := -EISDIR Else VfsWrite := -EINVAL;
    Exit;
  End;
  If Cnt = 0 Then
  Begin
    VfsWrite := 0;
    Exit;
  End;
  If ((F^.Flags And O_APPEND) <> 0) And ((F^.Inode^.Mode And S_IFMT)
      = S_IFREG) Then
    F^.Pos := F^.Inode^.Size;
  VfsWrite := Call3(Fn, LongInt(F), Buf, Cnt);
End;

{ Ouvrir : verifications des droits, creation, troncature }
Function VfsOpen(Const Path : String; Flags, Mode : LongInt;
    Var Res : PFile) : LongInt;
Var D, Par : PDentry; R, Acc, Fn, M : LongInt; Nm : String; I : PInode;
    F : PFile;
    Created : Boolean; Ops : LongInt;
Begin
  Res := Nil;
  Created := False;
  Acc := Flags And O_ACCMODE;
  If Acc = 3 Then
  Begin
    VfsOpen := -EINVAL;
    Exit;
  End;
  R := PathWalk(Path, (Flags And O_NOFOLLOW) = 0, D);
  If (R = -ENOENT) And ((Flags And O_CREAT) <> 0) Then
  Begin
    R := WalkParent(Path, Par, Nm);
    If R <> 0 Then
    Begin
      VfsOpen := R;
      Exit;
    End;
    If (Nm = '') Or (Nm = '.') Or (Nm = '..') Then
    Begin
      DentryPut(LongInt(Par));
      VfsOpen := -EISDIR;
      Exit;
    End;
    If (Par^.Sb^.Flags And MS_RDONLY) <> 0 Then
    Begin
      DentryPut(LongInt(Par));
      VfsOpen := -EROFS;
      Exit;
    End;
    R := InodePerm(Par^.Inode, MAY_WRITE Or MAY_EXEC);
    If R = 0 Then
    Begin
      Fn := GetOp(Par^.Inode^.IOps, IoCreate);
      If Fn = 0 Then R := -EACCES
      Else
      Begin
        I := Nil;
        M := (Mode And $FFF And Not Cur^.Fs^.Umask) Or S_IFREG;
        R := Call4(Fn, LongInt(Par^.Inode), LongInt(@Nm), M, LongInt(@I));
        If R = 0 Then
        Begin
          D := DentryNew(Par, Nm, I, Par^.Sb);
          If D = Nil Then
          Begin
            InodePut(LongInt(I));
            R := -ENOMEM;
          End
          Else Created := True;
        End;
      End;
    End;
    DentryPut(LongInt(Par));
    If R <> 0 Then
    Begin
      VfsOpen := R;
      Exit;
    End;
  End
  Else If R <> 0 Then
  Begin
    VfsOpen := R;
    Exit;
  End
  Else If ((Flags And O_CREAT) <> 0) And ((Flags And O_EXCL) <> 0) Then
  Begin
    DentryPut(LongInt(D));
    VfsOpen := -EEXIST;
    Exit;
  End;
  I := D^.Inode;
  M := I^.Mode And S_IFMT;
  R := 0;
  If M = S_IFLNK Then R := -ELOOP;
  If (M = S_IFDIR) And ((Acc <> O_RDONLY) Or ((Flags And O_TRUNC) <> 0))
      Then R := -EISDIR;
  If ((Flags And O_DIRECTORY) <> 0) And (M <> S_IFDIR) Then R := -ENOTDIR;
  If (R = 0) And Not Created Then
  Begin
    If (Acc = O_RDONLY) Or (Acc = O_RDWR) Then R := InodePerm(I, MAY_READ);
    If (R = 0) And ((Acc = O_WRONLY) Or (Acc = O_RDWR)) Then R := InodePerm(I,
        MAY_WRITE);
    If (R = 0) And ((Acc <> O_RDONLY) Or ((Flags And O_TRUNC) <> 0)) And
       ((D^.Sb^.Flags And MS_RDONLY) <> 0) And ((M = S_IFREG) Or (M = S_IFDIR))
           Then R := -EROFS;
  End;
  If R <> 0 Then
  Begin
    DentryPut(LongInt(D));
    VfsOpen := R;
    Exit;
  End;
  If ((Flags And O_TRUNC) <> 0) And (M = S_IFREG) And Not Created Then
  Begin
    Fn := GetOp(I^.IOps, IoTruncate);
    If Fn <> 0 Then
    Begin
      I^.Size := 0;
      Call2(Fn, LongInt(I), 0);
      I^.Mtime := NowSec; I^.Ctime := I^.Mtime;
      IMarkDirty(I);
    End;
  End;
  F := FileNew(D, Flags);
  If F = Nil Then
  Begin
    DentryPut(LongInt(D));
    VfsOpen := -ENFILE;
    Exit;
  End;
  { peripheriques : table d'operations par numero majeur }
  If (M = S_IFCHR) Then
  Begin
    Ops := ChrOps[(I^.Rdev Shr 8) And $FF];
    If Ops = 0 Then
    Begin
      FilePut(LongInt(F));
      VfsOpen := -ENXIO;
      Exit;
    End;
    F^.FOps := Ops;
  End;
  If (M = S_IFBLK) Then F^.FOps := BlkFOpsAddr;
  If (M = S_IFIFO) Then F^.FOps := PipeFOpsAddr;
  Fn := GetOp(F^.FOps, FoOpen);
  If Fn <> 0 Then
  Begin
    R := Call2(Fn, LongInt(I), LongInt(F));
    If R <> 0 Then
    Begin
      FilePut(LongInt(F));
      VfsOpen := R;
      Exit;
    End;
  End;
  Res := F;
  VfsOpen := 0;
End;

Function VfsLseek(F : PFile; Off, Whence : LongInt) : LongInt;
Var Fn, P : LongInt;
Begin
  Fn := GetOp(F^.FOps, FoLlseek);
  If Fn <> 0 Then
  Begin
    VfsLseek := Call3(Fn, LongInt(F), Off, Whence);
    Exit;
  End;
  If ((F^.Inode^.Mode And S_IFMT) = S_IFIFO) Or ((F^.Inode^.Mode And S_IFMT)
      = S_IFCHR) Then
  Begin
    VfsLseek := -ESPIPE;
    Exit;
  End;
  Case Whence Of
    0 : P := Off;
    1 : P := F^.Pos + Off;
    2 : P := F^.Inode^.Size + Off;
  Else
    Begin
      VfsLseek := -EINVAL;
      Exit;
    End;
  End;
  If P < 0 Then
  Begin
    VfsLseek := -EINVAL;
    Exit;
  End;
  F^.Pos := P;
  VfsLseek := P;
End;

{ Creer un repertoire, un noeud special... Kind : 0 mkdir, 1 mknod }
Function VfsCreateNode(Const Path : String; Mode, Rdev : LongInt;
    IsMkdir : Boolean) : LongInt;
Var Par, D : PDentry; Nm : String; R, Fn, M : LongInt;
Begin
  R := WalkParent(Path, Par, Nm);
  If R <> 0 Then
  Begin
    VfsCreateNode := R;
    Exit;
  End;
  If (Nm = '') Or (Nm = '.') Or (Nm = '..') Then
  Begin
    DentryPut(LongInt(Par));
    VfsCreateNode := -EEXIST;
    Exit;
  End;
  If (Par^.Sb^.Flags And MS_RDONLY) <> 0 Then
  Begin
    DentryPut(LongInt(Par));
    VfsCreateNode := -EROFS;
    Exit;
  End;
  If DLookup(Par, Nm, D) = 0 Then
  Begin
    DentryPut(LongInt(D));
    DentryPut(LongInt(Par));
    VfsCreateNode := -EEXIST;
    Exit;
  End;
  R := InodePerm(Par^.Inode, MAY_WRITE Or MAY_EXEC);
  If R = 0 Then
  Begin
    If IsMkdir Then
    Begin
      Fn := GetOp(Par^.Inode^.IOps, IoMkdir);
      M := (Mode And $FFF And Not Cur^.Fs^.Umask) Or S_IFDIR;
      If (Par^.Inode^.Mode And S_ISGID) <> 0 Then M := M Or S_ISGID;
      If Fn = 0 Then R := -EPERM Else R := Call3(Fn, LongInt(Par^.Inode),
          LongInt(@Nm), M);
    End
    Else
    Begin
      Fn := GetOp(Par^.Inode^.IOps, IoMknod);
      M := Mode;
      If (M And S_IFMT) = 0 Then M := M Or S_IFREG;
      If (M And S_IFMT) <> S_IFREG Then M := (M And Not $FFF) Or (M And $FFF
          And Not Cur^.Fs^.Umask);
      If Fn = 0 Then R := -EPERM Else R := Call4(Fn, LongInt(Par^.Inode),
          LongInt(@Nm), M, Rdev);
    End;
  End;
  DentryPut(LongInt(Par));
  VfsCreateNode := R;
End;

{ Apres une suppression ou un renommage : oublier les dentries qui nomment
  encore (DirI, Nm) par un autre chemin (bind mounts) }
Procedure DentryDropAliases(DirI : PInode; Const Nm : String; Keep : PDentry);
Var D : PDentry;
Begin
  D := DentAll;
  While D <> Nil Do
  Begin
    If (D <> Keep) And (D^.Hashed <> 0) And (D^.Parent <> Nil) Then
      If D^.Parent^.Inode = DirI Then
        If DName(D) = Nm Then DentryUnhash(D);
    D := D^.AllNext;
  End;
End;

Function StickyDenied(Dir, Victim : PInode) : Boolean;
Begin
  StickyDenied := False;
  If (Dir^.Mode And S_ISVTX) = 0 Then Exit;
  If Cur^.Fsuid = 0 Then Exit;
  If (Cur^.Fsuid = Dir^.Uid) Or (Cur^.Fsuid = Victim^.Uid) Then Exit;
  StickyDenied := True;
End;

Function VfsUnlink(Const Path : String; Rmdir : Boolean) : LongInt;
Var Par, D : PDentry; Nm : String; R, Fn : LongInt; I : PInode;
Begin
  R := WalkParent(Path, Par, Nm);
  If R <> 0 Then
  Begin
    VfsUnlink := R;
    Exit;
  End;
  If (Nm = '') Or (Nm = '.') Or (Nm = '..') Then
  Begin
    DentryPut(LongInt(Par));
    If Rmdir Then VfsUnlink := -EINVAL Else VfsUnlink := -EISDIR;
    If Nm = '' Then VfsUnlink := -EBUSY;
    Exit;
  End;
  If (Par^.Sb^.Flags And MS_RDONLY) <> 0 Then
  Begin
    DentryPut(LongInt(Par));
    VfsUnlink := -EROFS;
    Exit;
  End;
  R := DLookup(Par, Nm, D);
  If R = 0 Then
  Begin
    I := D^.Inode;
    R := InodePerm(Par^.Inode, MAY_WRITE Or MAY_EXEC);
    If (R = 0) And StickyDenied(Par^.Inode, I) Then R := -EPERM;
    If R = 0 Then
    Begin
      If Rmdir Then
      Begin
        If Not IsDir(I) Then R := -ENOTDIR
        Else If (D^.Mounted <> Nil) Or (D^.Bind <> Nil) Then R := -EBUSY
        Else If D^.NChild > 0 Then
        Begin
          { dentries enfants : decision du systeme de fichiers }
          R := 0;
        End;
        If R = 0 Then
        Begin
          Fn := GetOp(Par^.Inode^.IOps, IoRmdir);
          If Fn = 0 Then R := -EPERM Else R := Call3(Fn, LongInt(Par^.Inode),
              LongInt(@Nm), LongInt(I));
        End;
      End
      Else
      Begin
        If IsDir(I) Then R := -EISDIR
        Else
        Begin
          Fn := GetOp(Par^.Inode^.IOps, IoUnlink);
          If Fn = 0 Then R := -EPERM Else R := Call3(Fn, LongInt(Par^.Inode),
              LongInt(@Nm), LongInt(I));
        End;
      End;
    End;
    If R = 0 Then
    Begin
      DentryUnhash(D);
      If BindCount > 0 Then DentryDropAliases(Par^.Inode, Nm, D);
    End;
    DentryPut(LongInt(D));
  End;
  DentryPut(LongInt(Par));
  VfsUnlink := R;
End;

Function IsAncestor(A, D : PDentry) : Boolean;
Var X : PDentry;
Begin
  IsAncestor := False;
  X := D;
  While X <> Nil Do
  Begin
    If X = A Then
    Begin
      IsAncestor := True;
      Exit;
    End;
    X := X^.Parent;
  End;
End;

Function VfsRename(Const OldP, NewP : String) : LongInt;
Var OP, NP, Src, Dst : PDentry; ON, NN : String; R, Fn : LongInt;
    Replace : Boolean;
Begin
  R := WalkParent(OldP, OP, ON);
  If R <> 0 Then
  Begin
    VfsRename := R;
    Exit;
  End;
  R := WalkParent(NewP, NP, NN);
  If R <> 0 Then
  Begin
    DentryPut(LongInt(OP));
    VfsRename := R;
    Exit;
  End;
  VfsRename := -EINVAL;
  If (ON = '') Or (ON = '.') Or (ON = '..') Or (NN = '') Or (NN = '.') Or (NN
      = '..') Then
  Begin
    DentryPut(LongInt(OP)); DentryPut(LongInt(NP));
    Exit;
  End;
  If OP^.Sb <> NP^.Sb Then
  Begin
    DentryPut(LongInt(OP)); DentryPut(LongInt(NP));
    VfsRename := -EXDEV;
    Exit;
  End;
  If (OP^.Sb^.Flags And MS_RDONLY) <> 0 Then
  Begin
    DentryPut(LongInt(OP)); DentryPut(LongInt(NP));
    VfsRename := -EROFS;
    Exit;
  End;
  R := DLookup(OP, ON, Src);
  If R <> 0 Then
  Begin
    DentryPut(LongInt(OP)); DentryPut(LongInt(NP));
    VfsRename := R;
    Exit;
  End;
  R := InodePerm(OP^.Inode, MAY_WRITE Or MAY_EXEC);
  If R = 0 Then R := InodePerm(NP^.Inode, MAY_WRITE Or MAY_EXEC);
  If (R = 0) And StickyDenied(OP^.Inode, Src^.Inode) Then R := -EPERM;
  If (R = 0) And IsDir(Src^.Inode) And IsAncestor(Src, NP) Then R := -EINVAL;
  If (R = 0) And ((Src^.Mounted <> Nil) Or (Src^.Bind <> Nil)) Then
    R := -EBUSY;
  Dst := Nil;
  Replace := False;
  If R = 0 Then
    If DLookup(NP, NN, Dst) = 0 Then
    Begin
      Replace := True;
      If Dst = Src Then
      Begin
        DentryPut(LongInt(Dst)); DentryPut(LongInt(Src));
        DentryPut(LongInt(OP)); DentryPut(LongInt(NP));
        VfsRename := 0;
        Exit;
      End;
      If IsDir(Src^.Inode) And Not IsDir(Dst^.Inode) Then R := -ENOTDIR
      Else If (Not IsDir(Src^.Inode)) And IsDir(Dst^.Inode) Then R := -EISDIR
      Else If (Dst^.Mounted <> Nil) Or (Dst^.Bind <> Nil) Then R := -EBUSY
      Else If StickyDenied(NP^.Inode, Dst^.Inode) Then R := -EPERM;
    End;
  If R = 0 Then
  Begin
    Fn := GetOp(OP^.Inode^.IOps, IoRename);
    If Fn = 0 Then R := -EPERM
    Else R := Call5(Fn, LongInt(OP^.Inode), LongInt(@ON), LongInt(NP^.Inode),
        LongInt(@NN), 0);
  End;
  If R = 0 Then
  Begin
    If Replace Then DentryUnhash(Dst);
    { deplacer le dentry source }
    DentryUnhash(Src);
    Dec(OP^.NChild);
    Inc(NP^.NChild);
    Src^.Parent := NP;
    KFree(Src^.NamePtr);
    Src^.NamePtr := KMalloc(Length(NN) + 1);
    MemCopy(Src^.NamePtr, LongInt(@NN), Length(NN) + 1);
    Src^.Next := DentTab[NameHash(NP, NN)];
    DentTab[NameHash(NP, NN)] := Src;
    Src^.Hashed := 1;
    If BindCount > 0 Then
    Begin
      DentryDropAliases(OP^.Inode, ON, Nil);
      DentryDropAliases(NP^.Inode, NN, Src);
    End;
  End;
  If Dst <> Nil Then DentryPut(LongInt(Dst));
  DentryPut(LongInt(Src));
  DentryPut(LongInt(OP)); DentryPut(LongInt(NP));
  VfsRename := R;
End;

Function VfsLink(Const OldP, NewP : String) : LongInt;
Var Src, NP, D : PDentry; NN : String; R, Fn : LongInt;
Begin
  R := PathWalk(OldP, False, Src);
  If R <> 0 Then
  Begin
    VfsLink := R;
    Exit;
  End;
  If IsDir(Src^.Inode) Then
  Begin
    DentryPut(LongInt(Src));
    VfsLink := -EPERM;
    Exit;
  End;
  R := WalkParent(NewP, NP, NN);
  If R <> 0 Then
  Begin
    DentryPut(LongInt(Src));
    VfsLink := R;
    Exit;
  End;
  If (NN = '') Or (NN = '.') Or (NN = '..') Then R := -EEXIST
  Else If NP^.Sb <> Src^.Sb Then R := -EXDEV
  Else If (NP^.Sb^.Flags And MS_RDONLY) <> 0 Then R := -EROFS
  Else If DLookup(NP, NN, D) = 0 Then
  Begin
    DentryPut(LongInt(D));
    R := -EEXIST;
  End
  Else
  Begin
    R := InodePerm(NP^.Inode, MAY_WRITE Or MAY_EXEC);
    If R = 0 Then
    Begin
      Fn := GetOp(NP^.Inode^.IOps, IoLink);
      If Fn = 0 Then R := -EPERM Else R := Call3(Fn, LongInt(Src^.Inode),
          LongInt(NP^.Inode), LongInt(@NN));
    End;
  End;
  DentryPut(LongInt(Src));
  DentryPut(LongInt(NP));
  VfsLink := R;
End;

Function VfsSymlink(Const Target, Path : String) : LongInt;
Var Par, D : PDentry; Nm, T : String; R, Fn : LongInt;
Begin
  R := WalkParent(Path, Par, Nm);
  If R <> 0 Then
  Begin
    VfsSymlink := R;
    Exit;
  End;
  If (Nm = '') Or (Nm = '.') Or (Nm = '..') Then R := -EEXIST
  Else If (Par^.Sb^.Flags And MS_RDONLY) <> 0 Then R := -EROFS
  Else If DLookup(Par, Nm, D) = 0 Then
  Begin
    DentryPut(LongInt(D));
    R := -EEXIST;
  End
  Else
  Begin
    R := InodePerm(Par^.Inode, MAY_WRITE Or MAY_EXEC);
    If R = 0 Then
    Begin
      Fn := GetOp(Par^.Inode^.IOps, IoSymlink);
      T := Target;
      If Fn = 0 Then R := -EPERM Else R := Call3(Fn, LongInt(Par^.Inode),
          LongInt(@Nm), LongInt(@T));
    End;
  End;
  DentryPut(LongInt(Par));
  VfsSymlink := R;
End;

{ Troncature : par chemin ou par inode }
Function VfsTruncateInode(I : PInode; Size : LongInt) : LongInt;
Var Fn : LongInt;
Begin
  If Size < 0 Then
  Begin
    VfsTruncateInode := -EINVAL;
    Exit;
  End;
  If (I^.Mode And S_IFMT) <> S_IFREG Then
  Begin
    If IsDir(I) Then VfsTruncateInode := -EISDIR
        Else VfsTruncateInode := -EINVAL;
    Exit;
  End;
  If (I^.Sb^.Flags And MS_RDONLY) <> 0 Then
  Begin
    VfsTruncateInode := -EROFS;
    Exit;
  End;
  Fn := GetOp(I^.IOps, IoTruncate);
  If Fn = 0 Then
  Begin
    VfsTruncateInode := -EINVAL;
    Exit;
  End;
  I^.Size := Size;
  VfsTruncateInode := Call2(Fn, LongInt(I), Size);
  I^.Mtime := NowSec; I^.Ctime := I^.Mtime;
  IMarkDirty(I);
End;

{ Modifier les attributs : mode, proprietaire ; -1 = inchange }
Function VfsSetAttr(I : PInode; Mode, Uid, Gid : LongInt) : LongInt;
Var Fn : LongInt;
Begin
  VfsSetAttr := 0;
  If (I^.Sb^.Flags And MS_RDONLY) <> 0 Then
  Begin
    VfsSetAttr := -EROFS;
    Exit;
  End;
  If Mode <> -1 Then
  Begin
    If (Cur^.Fsuid <> 0) And (Cur^.Fsuid <> I^.Uid) Then
    Begin
      VfsSetAttr := -EPERM;
      Exit;
    End;
    Mode := Mode And $FFF;
    If (Cur^.Fsuid <> 0) And Not InGroup(I^.Gid) Then Mode := Mode
        And Not S_ISGID;
    I^.Mode := (I^.Mode And S_IFMT) Or Mode;
  End;
  If (Uid <> -1) Or (Gid <> -1) Then
  Begin
    If Cur^.Fsuid <> 0 Then
    Begin
      If (Uid <> -1) And (Uid <> I^.Uid) Then
      Begin
        VfsSetAttr := -EPERM;
        Exit;
      End;
      If (Cur^.Fsuid <> I^.Uid) Or ((Gid <> -1) And Not InGroup(Gid)) Then
      Begin
        VfsSetAttr := -EPERM;
        Exit;
      End;
    End;
    If Uid <> -1 Then I^.Uid := Uid;
    If Gid <> -1 Then I^.Gid := Gid;
    If (I^.Mode And S_IFMT) = S_IFREG Then I^.Mode := I^.Mode And Not (S_ISUID
        Or S_ISGID);
  End;
  I^.Ctime := NowSec;
  Fn := GetOp(I^.IOps, IoSetattr);
  If Fn <> 0 Then Call1(Fn, LongInt(I));
End;

{ ---- Montages ---- }

{ Liberer tous les dentries inutilises d'un systeme de fichiers (sauf sa
  racine) : les feuilles d'abord, jusqu'a ce qu'il n'en reste plus }
Procedure DentryPurgeSb(Sb : PSuper);
Var D, N : PDentry; Again : Boolean;
Begin
  Again := True;
  While Again Do
  Begin
    Again := False;
    D := DentAll;
    While D <> Nil Do
    Begin
      N := D^.AllNext;
      If (D^.Sb = Sb) And (D^.Count <= 0) And (D^.NChild = 0)
          And (D^.Mounted = Nil) And (D^.Bind = Nil) And (D <> Sb^.Root) Then
      Begin
        DentryFree(D);
        Again := True;
      End;
      D := N;
    End;
  End;
End;

{ Somme des references d'inodes d'un systeme de fichiers }
Function InodeRefsOf(Sb : PSuper) : LongInt;
Var P : PInode; N : LongInt;
Begin
  N := 0;
  P := InodeAll;
  While P <> Nil Do
  Begin
    If P^.Sb = Sb Then N := N + P^.Count;
    P := P^.Next;
  End;
  InodeRefsOf := N;
End;

{ Liberer tous les inodes d'un systeme de fichiers (apres umount) }
Procedure InodePurgeSb(Sb : PSuper);
Var P, N : PInode; Fn : LongInt;
Begin
  P := InodeAll;
  While P <> Nil Do
  Begin
    N := P^.Next;
    If P^.Sb = Sb Then
    Begin
      If GetOp(Sb^.SOps, SoClearInode) <> 0 Then InodeFreeOne(P)
      Else
      Begin
        Fn := GetOp(Sb^.SOps, SoPutInode);
        If Fn <> 0 Then Call1(Fn, LongInt(P));
        InodeUnlinkList(P);
        Dec(InodeCount);
        KFree(LongInt(P));
      End;
    End;
    P := N;
  End;
End;

Function FindFsType(Const Nm : String) : LongInt;
Var I : LongInt;
Begin
  FindFsType := -1;
  For I := 0 To NFsTypes - 1 Do
    If FsNames[I] = Nm Then
    Begin
      FindFsType := I;
      Exit;
    End;
End;

Procedure RegisterFs(Const Nm : String; Mount : LongInt);
Begin
  FsNames[NFsTypes] := Nm;
  FsMount[NFsTypes] := Mount;
  Inc(NFsTypes);
End;

Procedure SuperRelease(Sb : PSuper);
Var I : LongInt;
Begin
  For I := 0 To MaxSupers - 1 Do
    If Supers[I] = Sb Then Supers[I] := Nil;
  If Sb^.DevName <> 0 Then KFree(Sb^.DevName);
  KFree(LongInt(Sb));
End;

{ Monter Dev (nom) de type FsT sur le repertoire Dir }
Function VfsMount(Const DevName, Dir, FsT : String; Flags,
    Data : LongInt) : LongInt;
Var T, R, Fn : LongInt; Sb : PSuper; D : PDentry; Dn : String;
Begin
  T := FindFsType(FsT);
  If T < 0 Then
  Begin
    VfsMount := -ENODEV;
    Exit;
  End;
  R := PathWalk(Dir, True, D);
  If R <> 0 Then
  Begin
    VfsMount := R;
    Exit;
  End;
  If Not IsDir(D^.Inode) Then
  Begin
    DentryPut(LongInt(D));
    VfsMount := -ENOTDIR;
    Exit;
  End;
  Sb := SuperNew(T);
  If Sb = Nil Then
  Begin
    DentryPut(LongInt(D));
    VfsMount := -ENOMEM;
    Exit;
  End;
  Sb^.Flags := Flags;
  Dn := DevName;
  Sb^.DevName := KMalloc(Length(Dn) + 1);
  MemCopy(Sb^.DevName, LongInt(@Dn), Length(Dn) + 1);
  Fn := FsMount[T];
  R := Call4(Fn, LongInt(Sb), LongInt(@Dn), Flags, Data);
  If R <> 0 Then
  Begin
    SuperRelease(Sb);
    DentryPut(LongInt(D));
    VfsMount := R;
    Exit;
  End;
  Sb^.Covered := D;           { la reference de D est reprise }
  D^.Mounted := Sb;
  VfsMount := 0;
End;

{ Un dentry est-il dans le sous-arbre de Root ? }
Function DentryUnder(D, Root : PDentry) : Boolean;
Var X : PDentry; N : LongInt;
Begin
  DentryUnder := False;
  X := D;
  N := 0;
  While (X <> Nil) And (N < 200) Do
  Begin
    If X = Root Then
    Begin
      DentryUnder := True;
      Exit;
    End;
    X := X^.Parent;
    Inc(N);
  End;
End;

{ Demonter un bind mount dont C est la racine (C porte +1 du chemin) }
Function VfsUnbind(C : PDentry) : LongInt;
Var D, N, Y : PDentry; Again : Boolean;
Begin
  If C^.Count > 2 Then
  Begin
    DentryPut(LongInt(C));
    VfsUnbind := -EBUSY;
    Exit;
  End;
  Again := True;
  While Again Do
  Begin
    Again := False;
    D := DentAll;
    While D <> Nil Do
    Begin
      N := D^.AllNext;
      If (D <> C) And (D^.Count <= 0) And (D^.NChild = 0) And (D^.Mounted = Nil)
         And (D^.Bind = Nil) And DentryUnder(D, C) Then
      Begin
        DentryFree(D);
        Again := True;
      End;
      D := N;
    End;
  End;
  If C^.NChild > 0 Then
  Begin
    DentryPut(LongInt(C));
    VfsUnbind := -EBUSY;
    Exit;
  End;
  Y := C^.BindMp;
  Y^.Bind := Nil;
  C^.BindMp := Nil;
  DentryPut(LongInt(C));
  DentryPut(LongInt(C));
  DentryPut(LongInt(Y));
  VfsUnbind := 0;
End;

{ umount2 : Flags 1 = MNT_FORCE (ignore), 2 = MNT_DETACH (decroche meme
  occupe) }
Function VfsUmountD(D : PDentry; Flags : LongInt) : LongInt;
Var D2 : PDentry; R, Fn, Dev : LongInt; Sb : PSuper; Cov : PDentry;
    I : LongInt; Busy : Boolean;
Begin
  If D^.BindMp <> Nil Then
  Begin
    VfsUmountD := VfsUnbind(D);
    Exit;
  End;
  Sb := D^.Sb;
  If (Sb^.Root <> D) Or (Sb^.Covered = Nil) Then
  Begin
    DentryPut(LongInt(D));
    VfsUmountD := -EINVAL;
    Exit;
  End;
  { occupe : plus de references que celle du chemin et de la racine }
  Busy := Sb^.RefTotal > 2;
  For I := 0 To MaxSupers - 1 Do
    If (Supers[I] <> Nil) And (Supers[I]^.Covered <> Nil)
        And (Supers[I]^.Covered^.Sb = Sb) Then Busy := True;
  D2 := DentAll;
  While D2 <> Nil Do
  Begin
    If (D2^.Sb = Sb) And (D2^.Bind <> Nil) Then Busy := True;
    D2 := D2^.AllNext;
  End;
  If Busy And ((Flags And 2) = 0) Then
  Begin
    DentryPut(LongInt(D));
    VfsUmountD := -EBUSY;
    Exit;
  End;
  Dev := Sb^.Dev;
  DentryPut(LongInt(D));
  Fn := GetOp(Sb^.SOps, SoSync);
  If Fn <> 0 Then Call1(Fn, LongInt(Sb));
  If Busy Then
  Begin
    { MNT_DETACH : decrocher seulement ; le systeme reste en vie }
    Cov := Sb^.Covered;
    Cov^.Mounted := Nil;
    Sb^.Covered := Nil;
    DentryPut(LongInt(Cov));
    VfsUmountD := 0;
    Exit;
  End;
  DentryPurgeSb(Sb);
  If (GetOp(Sb^.SOps, SoClearInode) <> 0) And (InodeRefsOf(Sb) > 1) Then
  Begin
    VfsUmountD := -EBUSY;
    Exit;
  End;
  Cov := Sb^.Covered;
  Cov^.Mounted := Nil;
  Sb^.Covered := Nil;
  DentryPut(LongInt(Cov));
  { liberer la racine et les dentries du systeme }
  D := Sb^.Root;
  Sb^.Root := Nil;
  DentryPut(LongInt(D));
  InodePurgeSb(Sb);
  Fn := GetOp(Sb^.SOps, SoUmount);
  If Fn <> 0 Then Call1(Fn, LongInt(Sb));
  If Dev <> 0 Then BInvalidate(Dev);
  SuperRelease(Sb);
  VfsUmountD := 0;
End;

Function VfsUmount(Const Path : String; Flags : LongInt) : LongInt;
Var D : PDentry; R : LongInt;
Begin
  R := PathWalk(Path, (Flags And 8) = 0, D);
  If R <> 0 Then
  Begin
    VfsUmount := R;
    Exit;
  End;
  VfsUmount := VfsUmountD(D, Flags);
End;

{ mount --bind : le sous-arbre Src apparait aussi en Dst. La racine du bind
  mount est un dentry "clone" (meme inode, sans entree dans la table de
  hachage) dont le parent est celui du point de montage, ce qui fait
  fonctionner ".." et les chemins. Les montages sous Src ne suivent pas
  (pas de MS_REC). }
Function VfsBind(Const SrcP, DstP : String) : LongInt;
Var S, Y, C, Par : PDentry; R : LongInt; Nm : String;
Begin
  R := PathWalk(SrcP, True, S);
  If R <> 0 Then
  Begin
    VfsBind := R;
    Exit;
  End;
  R := PathWalk(DstP, True, Y);
  If R <> 0 Then
  Begin
    DentryPut(LongInt(S));
    VfsBind := R;
    Exit;
  End;
  If IsDir(S^.Inode) <> IsDir(Y^.Inode) Then
  Begin
    DentryPut(LongInt(S)); DentryPut(LongInt(Y));
    If IsDir(S^.Inode) Then VfsBind := -ENOTDIR Else VfsBind := -EISDIR;
    Exit;
  End;
  If (Y^.Mounted <> Nil) Or (Y^.Bind <> Nil) Then
  Begin
    { le point est deja un montage : recouvrir le dessus }
    DentryPut(LongInt(S)); DentryPut(LongInt(Y));
    VfsBind := -EBUSY;
    Exit;
  End;
  Par := Y^.Parent;
  Nm := DName(Y);
  If (Par = Nil) And (Y^.Sb^.Root = Y) And (Y^.Sb^.Covered <> Nil) Then
  Begin
    Par := Y^.Sb^.Covered^.Parent;
    Nm := DName(Y^.Sb^.Covered);
  End;
  Inc(S^.Inode^.Count);
  C := DentryNew(Par, Nm, S^.Inode, S^.Sb);
  If C = Nil Then
  Begin
    InodePut(LongInt(S^.Inode));
    DentryPut(LongInt(S)); DentryPut(LongInt(Y));
    VfsBind := -ENOMEM;
    Exit;
  End;
  DentryUnhash(C);
  Inc(BindCount);
  C^.BindMp := Y;
  Y^.Bind := C;
  DentryPut(LongInt(S));
  VfsBind := 0;
End;

{ Deplacer un montage (MS_MOVE) de Src vers Dst }
Function VfsMoveMount(Const SrcP, DstP : String) : LongInt;
Var S, Y, Old : PDentry; R : LongInt; Sb : PSuper;
Begin
  R := PathWalk(SrcP, True, S);
  If R <> 0 Then
  Begin
    VfsMoveMount := R;
    Exit;
  End;
  R := PathWalk(DstP, True, Y);
  If R <> 0 Then
  Begin
    DentryPut(LongInt(S));
    VfsMoveMount := R;
    Exit;
  End;
  If (Y^.Mounted <> Nil) Or (Y^.Bind <> Nil) Or (Not IsDir(Y^.Inode)) Then
  Begin
    DentryPut(LongInt(S)); DentryPut(LongInt(Y));
    VfsMoveMount := -EBUSY;
    Exit;
  End;
  If S^.BindMp <> Nil Then
  Begin
    Old := S^.BindMp;
    Old^.Bind := Nil;
    Y^.Bind := S;
    S^.BindMp := Y;
    DentryPut(LongInt(Old));
    DentryPut(LongInt(S));
    VfsMoveMount := 0;
    Exit;
  End;
  Sb := S^.Sb;
  If (Sb^.Root <> S) Or (Sb^.Covered = Nil) Then
  Begin
    DentryPut(LongInt(S)); DentryPut(LongInt(Y));
    VfsMoveMount := -EINVAL;
    Exit;
  End;
  Old := Sb^.Covered;
  Old^.Mounted := Nil;
  Y^.Mounted := Sb;
  Sb^.Covered := Y;
  DentryPut(LongInt(Old));
  DentryPut(LongInt(S));
  VfsMoveMount := 0;
End;

{ pivot_root(Nouv, Ancien) : Nouv (un point de montage, racine d'un systeme
  de fichiers) devient la racine ; l'ancienne racine est montee sur Ancien
  (sous Nouv). Les processus dont la racine ou le repertoire courant etait
  l'ancienne racine sont deplaces. }
Function VfsPivotRoot(Const NewP, OldP : String) : LongInt;
Var N, O, R0, Cov : PDentry; R, I : LongInt; Rs, Ns : PSuper; Fs : PFsStruct;
Begin
  R := PathWalk(NewP, True, N);
  If R <> 0 Then
  Begin
    VfsPivotRoot := R;
    Exit;
  End;
  R := PathWalk(OldP, True, O);
  If R <> 0 Then
  Begin
    DentryPut(LongInt(N));
    VfsPivotRoot := R;
    Exit;
  End;
  R0 := Cur^.Fs^.Root;
  Ns := N^.Sb;
  Rs := R0^.Sb;
  If (Not IsDir(O^.Inode)) Or (Ns^.Root <> N) Or (Ns^.Covered = Nil)
     Or (Rs^.Covered <> Nil) Or (Rs^.Root <> R0) Or (Ns = Rs)
     Or (Not DentryUnder(O, N)) Or (O^.Mounted <> Nil) Or (O^.Bind <> Nil) Then
  Begin
    DentryPut(LongInt(N)); DentryPut(LongInt(O));
    If Not IsDir(O^.Inode) Then VfsPivotRoot := -ENOTDIR
    Else VfsPivotRoot := -EINVAL;
    Exit;
  End;
  { decrocher le nouveau systeme de l'ancien arbre }
  Cov := Ns^.Covered;
  Cov^.Mounted := Nil;
  Ns^.Covered := Nil;
  DentryPut(LongInt(Cov));
  { monter l'ancienne racine sur O (la reference de O est reprise) }
  O^.Mounted := Rs;
  Rs^.Covered := O;
  RootDentry := N;
  For I := 0 To MaxTasks - 1 Do
    If Tasks[I].State <> TsFree Then
    Begin
      Fs := Tasks[I].Fs;
      If Fs <> Nil Then
      Begin
        If Fs^.Root = LongInt(R0) Then
        Begin
          DentryGet(LongInt(N));
          Fs^.Root := LongInt(N);
          DentryPut(LongInt(R0));
        End;
        If Fs^.Pwd = LongInt(R0) Then
        Begin
          DentryGet(LongInt(N));
          Fs^.Pwd := LongInt(N);
          DentryPut(LongInt(R0));
        End;
      End;
    End;
  DentryPut(LongInt(N));
  VfsPivotRoot := 0;
End;

Procedure VfsSyncAll;
Var I, Fn : LongInt;
Begin
  For I := 0 To MaxSupers - 1 Do
    If Supers[I] <> Nil Then
    Begin
      Fn := GetOp(Supers[I]^.SOps, SoSync);
      If Fn <> 0 Then Call1(Fn, LongInt(Supers[I]));
    End;
  BSync(0);
End;

{ Remontage (MS_REMOUNT) du systeme de fichiers qui contient Dir : change
  l'option lecture seule (le systeme de fichiers marque propre/sale) }
Function VfsRemount(Const Dir : String; Flags : LongInt) : LongInt;
Var D : PDentry; R, Fn : LongInt; Sb : PSuper;
Begin
  R := PathWalk(Dir, True, D);
  If R <> 0 Then
  Begin
    VfsRemount := R;
    Exit;
  End;
  Sb := D^.Sb;
  DentryPut(LongInt(D));
  Fn := GetOp(Sb^.SOps, SoRemount);
  If Fn <> 0 Then R := Call2(Fn, LongInt(Sb), Flags)
  Else
  Begin
    Sb^.Flags := (Sb^.Flags And Not MS_RDONLY) Or (Flags And MS_RDONLY);
    R := 0;
  End;
  VfsRemount := R;
End;

{ Arret du systeme : ecrire tout, puis passer en lecture seule les systemes
  de fichiers sur disque (ils sont alors marques propres) }
Procedure VfsShutdown;
Var I, Fn : LongInt; Sb : PSuper;
Begin
  VfsSyncAll;
  For I := 0 To MaxSupers - 1 Do
  Begin
    Sb := Supers[I];
    If (Sb <> Nil) And ((Sb^.Flags And MS_RDONLY) = 0) Then
    Begin
      Fn := GetOp(Sb^.SOps, SoRemount);
      If Fn <> 0 Then Call2(Fn, LongInt(Sb), Sb^.Flags Or MS_RDONLY);
    End;
  End;
  BSync(0);
End;

Procedure InitVfs;
Var I : LongInt;
Begin
  For I := 0 To DentHash - 1 Do DentTab[I] := Nil;
  For I := 0 To InoHash - 1 Do InodeTab[I] := Nil;
  For I := 0 To MaxSupers - 1 Do Supers[I] := Nil;
  For I := 0 To 255 Do ChrOps[I] := 0;
  NFsTypes := 0;
  DentAll := Nil; InodeAll := Nil;
  NextAnonDev := 1;
End;

{ ==================================================================== }
{ Partie 13 - tmpfs/ramfs, devfs en memoire, tubes, peripheriques      }
{ ==================================================================== }

Type
  PTmpEnt = ^TTmpEnt;
  TTmpEnt = Record
    Next    : PTmpEnt;
    Ino     : PInode;
    NameP   : LongInt;          { chaine Pascal }
  End;

  PPipe = ^TPipe;
  TPipe = Record
    Buf             : LongInt;
    Head, Len       : LongInt;
    Readers, Writers : LongInt;
    Wchan           : LongInt;
    WGen, RGen      : LongInt;       { ouvertures en ecriture / lecture }
  End;

Var
  PipeSb      : PSuper;
  RandState   : LongInt;
  BlkFOps, PipeFOps, MemFOps, TmpSOps : Array[0..15] Of LongInt;

{ ---- Generateur pseudo-aleatoire (xorshift) ---- }

Function RandNext : LongInt;
Var X : LongInt;
Begin
  X := RandState;
  If X = 0 Then X := $2545F491 + Jiffies;
  X := X Xor (X Shl 13);
  X := X Xor (X Shr 17);
  X := X Xor (X Shl 5);
  RandState := X;
  RandNext := X;
End;

{ ==== tmpfs ==== }

Function TmpMkInode(Sb : PSuper; Mode, Rdev : LongInt) : PInode;
Var I : PInode;
Begin
  I := NewInode(Sb, Mode);
  TmpMkInode := I;
  If I = Nil Then Exit;
  I^.Rdev := Rdev;
  I^.IOps := LongInt(@TmpIOps[0]);
  Case Mode And S_IFMT Of
    S_IFREG : I^.FOps := LongInt(@TmpFOps[0]);
    S_IFDIR :
      Begin
        I^.FOps := LongInt(@TmpDirFOps[0]);
        I^.Nlink := 2;
      End;
    S_IFLNK : I^.IOps := LongInt(@TmpLnkIOps[0]);
  End;
End;

Function TmpEntFind(Dir : PInode; Const Nm : String) : PTmpEnt;
Var E : PTmpEnt; S : String; N, K : LongInt;
Begin
  E := Pointer(Dir^.Priv);
  While E <> Nil Do
  Begin
    N := Mem[0:E^.NameP];
    If N = Length(Nm) Then
    Begin
      S := '';
      For K := 1 To N Do S := S + Chr(Mem[0:E^.NameP + K]);
      If S = Nm Then
      Begin
        TmpEntFind := E;
        Exit;
      End;
    End;
    E := E^.Next;
  End;
  TmpEntFind := Nil;
End;

{ Ajouter l'entree Nm -> I dans Dir (une reference d'inode est prise) }
Function TmpAddEnt(Dir : PInode; Const Nm : String; I : PInode) : LongInt;
Var E : PTmpEnt; N : String; Last : PTmpEnt;
Begin
  TmpAddEnt := -ENOMEM;
  E := Pointer(KMallocZ(SizeOf(TTmpEnt)));
  If E = Nil Then Exit;
  N := Nm;
  E^.NameP := KMalloc(Length(N) + 1);
  If E^.NameP = 0 Then
  Begin
    KFree(LongInt(E));
    Exit;
  End;
  MemCopy(E^.NameP, LongInt(@N), Length(N) + 1);
  E^.Ino := I;
  Inc(I^.Count);
  { en fin de liste (ordre de creation) }
  If Dir^.Priv = 0 Then Dir^.Priv := LongInt(E)
  Else
  Begin
    Last := Pointer(Dir^.Priv);
    While Last^.Next <> Nil Do Last := Last^.Next;
    Last^.Next := E;
  End;
  Dir^.Mtime := NowSec; Dir^.Ctime := Dir^.Mtime;
  Inc(Dir^.Size, 20);
  TmpAddEnt := 0;
End;

{ Retirer une entree de la liste (l'inode et sa reference ne sont pas touches) }
Procedure TmpDelEnt(Dir : PInode; E : PTmpEnt);
Var P : PTmpEnt;
Begin
  If Pointer(Dir^.Priv) = E Then Dir^.Priv := LongInt(E^.Next)
  Else
  Begin
    P := Pointer(Dir^.Priv);
    While (P <> Nil) And (P^.Next <> E) Do P := P^.Next;
    If P <> Nil Then P^.Next := E^.Next;
  End;
  KFree(E^.NameP);
  KFree(LongInt(E));
  If Dir^.Size >= 20 Then Dec(Dir^.Size, 20);
  Dir^.Mtime := NowSec; Dir^.Ctime := Dir^.Mtime;
End;

Function TmpLookup(Dir : PInode; Var Nm : String; Var Res : PInode) : LongInt;
Var E : PTmpEnt;
Begin
  E := TmpEntFind(Dir, Nm);
  If E = Nil Then
  Begin
    TmpLookup := -ENOENT;
    Exit;
  End;
  Res := E^.Ino;
  Inc(Res^.Count);
  TmpLookup := 0;
End;

Function TmpCreate(Dir : PInode; Var Nm : String; Mode : LongInt;
    Var Res : PInode) : LongInt;
Var I : PInode; R : LongInt;
Begin
  I := TmpMkInode(Dir^.Sb, Mode, 0);
  If I = Nil Then
  Begin
    TmpCreate := -ENOMEM;
    Exit;
  End;
  R := TmpAddEnt(Dir, Nm, I);
  If R <> 0 Then
  Begin
    I^.Nlink := 0;
    InodePut(LongInt(I));
    TmpCreate := R;
    Exit;
  End;
  Res := I;
  TmpCreate := 0;
End;

Function TmpMkdir(Dir : PInode; Var Nm : String; Mode : LongInt) : LongInt;
Var I : PInode; R : LongInt;
Begin
  I := TmpMkInode(Dir^.Sb, Mode, 0);
  If I = Nil Then
  Begin
    TmpMkdir := -ENOMEM;
    Exit;
  End;
  If (Dir^.Mode And S_ISGID) <> 0 Then I^.Gid := Dir^.Gid;
  I^.Priv2 := LongInt(Dir);
  R := TmpAddEnt(Dir, Nm, I);
  If R <> 0 Then
  Begin
    I^.Nlink := 0;
    InodePut(LongInt(I));
    TmpMkdir := R;
    Exit;
  End;
  Inc(Dir^.Nlink);
  InodePut(LongInt(I));                 { reference de l'appelant }
  TmpMkdir := 0;
End;

Function TmpMknod(Dir : PInode; Var Nm : String; Mode,
    Rdev : LongInt) : LongInt;
Var I : PInode; R : LongInt;
Begin
  I := TmpMkInode(Dir^.Sb, Mode, Rdev);
  If I = Nil Then
  Begin
    TmpMknod := -ENOMEM;
    Exit;
  End;
  R := TmpAddEnt(Dir, Nm, I);
  If R <> 0 Then
  Begin
    I^.Nlink := 0;
    InodePut(LongInt(I));
    TmpMknod := R;
    Exit;
  End;
  InodePut(LongInt(I));
  TmpMknod := 0;
End;

Function TmpUnlink(Dir : PInode; Var Nm : String; I : PInode) : LongInt;
Var E : PTmpEnt;
Begin
  E := TmpEntFind(Dir, Nm);
  If E = Nil Then
  Begin
    TmpUnlink := -ENOENT;
    Exit;
  End;
  TmpDelEnt(Dir, E);
  Dec(I^.Nlink);
  I^.Ctime := NowSec;
  InodePut(LongInt(I));                 { reference de l'entree }
  TmpUnlink := 0;
End;

Function TmpRmdir(Dir : PInode; Var Nm : String; I : PInode) : LongInt;
Var E : PTmpEnt;
Begin
  If I^.Priv <> 0 Then
  Begin
    TmpRmdir := -ENOTEMPTY;
    Exit;
  End;
  E := TmpEntFind(Dir, Nm);
  If E = Nil Then
  Begin
    TmpRmdir := -ENOENT;
    Exit;
  End;
  TmpDelEnt(Dir, E);
  I^.Nlink := 0;
  Dec(Dir^.Nlink);
  InodePut(LongInt(I));
  TmpRmdir := 0;
End;

Function TmpRename(OD : PInode; Var ON : String; ND : PInode; Var NN : String;
    Dummy : LongInt) : LongInt;
Var E, T : PTmpEnt; I, V : PInode; Cp : String;
Begin
  E := TmpEntFind(OD, ON);
  If E = Nil Then
  Begin
    TmpRename := -ENOENT;
    Exit;
  End;
  I := E^.Ino;
  T := TmpEntFind(ND, NN);
  If T <> Nil Then
  Begin
    V := T^.Ino;
    If IsDir(V) Then
    Begin
      If V^.Priv <> 0 Then
      Begin
        TmpRename := -ENOTEMPTY;
        Exit;
      End;
      Dec(ND^.Nlink);
      V^.Nlink := 0;
    End
    Else Dec(V^.Nlink);
    TmpDelEnt(ND, T);
    InodePut(LongInt(V));
  End;
  { deplacer : retirer de l'ancien repertoire, ajouter au nouveau }
  Cp := NN;
  If TmpAddEnt(ND, Cp, I) <> 0 Then
  Begin
    TmpRename := -ENOMEM;
    Exit;
  End;
  E := TmpEntFind(OD, ON);
  TmpDelEnt(OD, E);
  InodePut(LongInt(I));
      { l'ancienne entree liberait une reference }
  If IsDir(I) And (OD <> ND) Then
  Begin
    I^.Priv2 := LongInt(ND);
    Dec(OD^.Nlink);
    Inc(ND^.Nlink);
  End;
  I^.Ctime := NowSec;
  TmpRename := 0;
End;

Function TmpLink(Old, Dir : PInode; Var Nm : String) : LongInt;
Var R : LongInt;
Begin
  R := TmpAddEnt(Dir, Nm, Old);
  If R = 0 Then
  Begin
    Inc(Old^.Nlink);
    Old^.Ctime := NowSec;
  End;
  TmpLink := R;
End;

Function TmpSymlink(Dir : PInode; Var Nm : String; Var Tgt : String) : LongInt;
Var I : PInode; R : LongInt;
Begin
  I := TmpMkInode(Dir^.Sb, S_IFLNK Or $1FF, 0);
  If I = Nil Then
  Begin
    TmpSymlink := -ENOMEM;
    Exit;
  End;
  I^.Priv := KMalloc(Length(Tgt) + 1);
  If I^.Priv = 0 Then
  Begin
    I^.Nlink := 0;
    InodePut(LongInt(I));
    TmpSymlink := -ENOMEM;
    Exit;
  End;
  MemCopy(I^.Priv, LongInt(@Tgt), Length(Tgt) + 1);
  I^.Size := Length(Tgt);
  R := TmpAddEnt(Dir, Nm, I);
  If R <> 0 Then I^.Nlink := 0;
  InodePut(LongInt(I));
  TmpSymlink := R;
End;

Function TmpReadlink(I : PInode; Buf, Size : LongInt) : LongInt;
Var N : LongInt;
Begin
  If I^.Priv = 0 Then
  Begin
    TmpReadlink := -EINVAL;
    Exit;
  End;
  N := Mem[0:I^.Priv];
  If N > Size Then N := Size;
  MemCopy(Buf, I^.Priv + 1, N);
  TmpReadlink := N;
End;

{ Fichier ordinaire : table de pages (Priv = table, Priv2 = capacite) }
Function TmpPageSlot(I : PInode; Idx : LongInt; Create : Boolean) : LongInt;
Var NewCap, NewTab : LongInt;
Begin
  TmpPageSlot := 0;
  If Idx >= I^.Priv2 Then
  Begin
    If Not Create Then Exit;
    NewCap := I^.Priv2 * 2;
    If NewCap < 16 Then NewCap := 16;
    While NewCap <= Idx Do NewCap := NewCap * 2;
    NewTab := KMallocZ(NewCap * 4);
    If NewTab = 0 Then Exit;
    If I^.Priv <> 0 Then
    Begin
      MemCopy(NewTab, I^.Priv, I^.Priv2 * 4);
      KFree(I^.Priv);
    End;
    I^.Priv := NewTab;
    I^.Priv2 := NewCap;
  End;
  If (MemL[0:I^.Priv + Idx * 4] = 0) And Create Then
  Begin
    NewTab := AllocZeroPage;
    If NewTab = 0 Then Exit;
    MemL[0:I^.Priv + Idx * 4] := NewTab;
    Inc(I^.Blocks, 8);
  End;
  TmpPageSlot := MemL[0:I^.Priv + Idx * 4];
End;

Function TmpRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var I : PInode; N, Done, Idx, Off, Chunk, Pg : LongInt;
Begin
  I := F^.Inode;
  If F^.Pos >= I^.Size Then
  Begin
    TmpRead := 0;
    Exit;
  End;
  N := I^.Size - F^.Pos;
  If N > Cnt Then N := Cnt;
  Done := 0;
  While Done < N Do
  Begin
    Idx := F^.Pos Shr 12;
    Off := F^.Pos And $FFF;
    Chunk := PageSize - Off;
    If Chunk > N - Done Then Chunk := N - Done;
    Pg := TmpPageSlot(I, Idx, False);
    If Pg = 0 Then MemFill(Buf + Done, 0, Chunk)
    Else MemCopy(Buf + Done, Pg + Off, Chunk);
    Done := Done + Chunk;
    F^.Pos := F^.Pos + Chunk;
  End;
  I^.Atime := NowSec;
  TmpRead := Done;
End;

Function TmpWrite(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var I : PInode; Done, Idx, Off, Chunk, Pg : LongInt;
Begin
  I := F^.Inode;
  Done := 0;
  If F^.Pos + Cnt < 0 Then
  Begin
    TmpWrite := -EFBIG;
    Exit;
  End;
  While Done < Cnt Do
  Begin
    Idx := F^.Pos Shr 12;
    Off := F^.Pos And $FFF;
    Chunk := PageSize - Off;
    If Chunk > Cnt - Done Then Chunk := Cnt - Done;
    Pg := TmpPageSlot(I, Idx, True);
    If Pg = 0 Then
    Begin
      If Done = 0 Then TmpWrite := -ENOSPC Else TmpWrite := Done;
      Exit;
    End;
    MemCopy(Pg + Off, Buf + Done, Chunk);
    Done := Done + Chunk;
    F^.Pos := F^.Pos + Chunk;
    If F^.Pos > I^.Size Then I^.Size := F^.Pos;
  End;
  I^.Mtime := NowSec; I^.Ctime := I^.Mtime;
  TmpWrite := Done;
End;

Function TmpTruncate(I : PInode; Size : LongInt) : LongInt;
Var Idx, First, Pg : LongInt;
Begin
  First := (Size + 4095) Shr 12;
  If I^.Priv <> 0 Then
  Begin
    For Idx := First To I^.Priv2 - 1 Do
    Begin
      Pg := MemL[0:I^.Priv + Idx * 4];
      If Pg <> 0 Then
      Begin
        FreePages(Pg, 0);
        MemL[0:I^.Priv + Idx * 4] := 0;
        Dec(I^.Blocks, 8);
      End;
    End;
    If ((Size And $FFF) <> 0) And ((Size Shr 12) < I^.Priv2) Then
    Begin
      Pg := MemL[0:I^.Priv + (Size Shr 12) * 4];
      If Pg <> 0 Then MemFill(Pg + (Size And $FFF), 0, PageSize - (Size
          And $FFF));
    End;
  End;
  TmpTruncate := 0;
End;

Procedure TmpPutInode(I : PInode);
Var K, Pg : LongInt; E, N : PTmpEnt; Pp : PPipe;
Begin
  Case I^.Mode And S_IFMT Of
    S_IFREG :
      If I^.Priv <> 0 Then
      Begin
        For K := 0 To I^.Priv2 - 1 Do
        Begin
          Pg := MemL[0:I^.Priv + K * 4];
          If Pg <> 0 Then FreePages(Pg, 0);
        End;
        KFree(I^.Priv);
        I^.Priv := 0;
      End;
    S_IFLNK :
      Begin
        If I^.Priv <> 0 Then KFree(I^.Priv);
        I^.Priv := 0;
      End;
    S_IFDIR :
      Begin
        E := Pointer(I^.Priv);
        While E <> Nil Do
        Begin
          N := E^.Next;
          KFree(E^.NameP);
          KFree(LongInt(E));
          E := N;
        End;
        I^.Priv := 0;
      End;
  End;
  If I^.Pipe <> 0 Then
  Begin
    Pp := Pointer(I^.Pipe);
    If Pp^.Buf <> 0 Then FreePages(Pp^.Buf, 0);
    KFree(I^.Pipe);
    I^.Pipe := 0;
  End;
End;

{ Lecture d'un repertoire : une entree par appel ; F^.Pos : 0 '.', 1 '..' }
Function TmpReaddir(F : PFile; Var Ino : LongInt; Var Nm : String;
    Var DType : LongInt) : LongInt;
Var D : PInode; E : PTmpEnt; K, N, M : LongInt; P : PInode;
Begin
  D := F^.Inode;
  TmpReaddir := 1;
  If F^.Pos = 0 Then
  Begin
    Ino := D^.Ino; Nm := '.'; DType := DT_DIR;
    Inc(F^.Pos);
    Exit;
  End;
  If F^.Pos = 1 Then
  Begin
    P := Pointer(D^.Priv2);
    If P = Nil Then P := D;
    Ino := P^.Ino; Nm := '..'; DType := DT_DIR;
    Inc(F^.Pos);
    Exit;
  End;
  E := Pointer(D^.Priv);
  K := F^.Pos - 2;
  While (K > 0) And (E <> Nil) Do
  Begin
    E := E^.Next;
    Dec(K);
  End;
  If E = Nil Then
  Begin
    TmpReaddir := 0;
    Exit;
  End;
  N := Mem[0:E^.NameP];
  Nm := '';
  For M := 1 To N Do Nm := Nm + Chr(Mem[0:E^.NameP + M]);
  Ino := E^.Ino^.Ino;
  Case E^.Ino^.Mode And S_IFMT Of
    S_IFDIR : DType := DT_DIR;
    S_IFREG : DType := DT_REG;
    S_IFLNK : DType := DT_LNK;
    S_IFCHR : DType := DT_CHR;
    S_IFBLK : DType := DT_BLK;
    S_IFIFO : DType := DT_FIFO;
  Else
    DType := DT_UNKNOWN;
  End;
  Inc(F^.Pos);
End;

Function TmpMountFn(Sb : PSuper; Var DevName : String; Flags,
    Data : LongInt) : LongInt;
Var I : PInode; D : PDentry;
Begin
  TmpMountFn := -ENOMEM;
  Sb^.Dev := NextAnonDev;
  Inc(NextAnonDev);
  Sb^.SOps := LongInt(@TmpSOps[0]);
  Sb^.Pinned := 1;
  I := TmpMkInode(Sb, S_IFDIR Or $1ED, 0);          { 0755 }
  If I = Nil Then Exit;
  I^.Uid := 0; I^.Gid := 0;
  I^.Priv2 := 0;
  D := DentryNew(Nil, '', I, Sb);
  If D = Nil Then Exit;
  Sb^.Root := D;
  TmpMountFn := 0;
End;

Procedure InitTmpfs;
Begin
  RegisterFs('tmpfs', LongInt(@TmpMountFn));
  RegisterFs('ramfs', LongInt(@TmpMountFn));
  RegisterFs('devtmpfs', LongInt(@TmpMountFn));
  MemFill(LongInt(@TmpIOps[0]), 0, SizeOf(TmpIOps));
  TmpIOps[IoLookup] := LongInt(@TmpLookup);
  TmpIOps[IoCreate] := LongInt(@TmpCreate);
  TmpIOps[IoMkdir] := LongInt(@TmpMkdir);
  TmpIOps[IoMknod] := LongInt(@TmpMknod);
  TmpIOps[IoUnlink] := LongInt(@TmpUnlink);
  TmpIOps[IoRmdir] := LongInt(@TmpRmdir);
  TmpIOps[IoRename] := LongInt(@TmpRename);
  TmpIOps[IoLink] := LongInt(@TmpLink);
  TmpIOps[IoSymlink] := LongInt(@TmpSymlink);
  TmpIOps[IoTruncate] := LongInt(@TmpTruncate);
  MemFill(LongInt(@TmpLnkIOps[0]), 0, SizeOf(TmpLnkIOps));
  TmpLnkIOps[IoReadlink] := LongInt(@TmpReadlink);
  MemFill(LongInt(@TmpFOps[0]), 0, SizeOf(TmpFOps));
  TmpFOps[FoRead] := LongInt(@TmpRead);
  TmpFOps[FoWrite] := LongInt(@TmpWrite);
  MemFill(LongInt(@TmpSOps[0]), 0, SizeOf(TmpSOps));
  TmpSOps[SoPutInode] := LongInt(@TmpPutInode);
  MemFill(LongInt(@TmpDirFOps[0]), 0, SizeOf(TmpDirFOps));
  TmpDirFOps[FoReaddir] := LongInt(@TmpReaddir);
End;

{ ---- Tubes (pipe) et FIFO ---- }

Const
  PipeSize = 4096;

Function PipeOf(I : PInode) : PPipe;
Var P : PPipe;
Begin
  If I^.Pipe = 0 Then
  Begin
    P := Pointer(KMallocZ(SizeOf(TPipe)));
    If P <> Nil Then
    Begin
      P^.Buf := AllocPages(0);
      If P^.Buf = 0 Then
      Begin
        KFree(LongInt(P));
        P := Nil;
      End
      Else P^.Wchan := LongInt(P);
    End;
    I^.Pipe := LongInt(P);
  End;
  PipeOf := Pointer(I^.Pipe);
End;

Function PipeRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var P : PPipe; N, First, Chunk : LongInt;
Begin
  P := PipeOf(F^.Inode);
  While P^.Len = 0 Do
  Begin
    If P^.Writers = 0 Then
    Begin
      PipeRead := 0;
      Exit;
    End;
    If (F^.Flags And O_NONBLOCK) <> 0 Then
    Begin
      PipeRead := -EAGAIN;
      Exit;
    End;
    If SleepOn(P^.Wchan, 0, True) = WakeSignal Then
    Begin
      PipeRead := -ERESTARTSYS;
      Exit;
    End;
  End;
  N := Cnt;
  If N > P^.Len Then N := P^.Len;
  First := PipeSize - P^.Head;
  Chunk := N;
  If Chunk > First Then Chunk := First;
  MemCopy(Buf, P^.Buf + P^.Head, Chunk);
  If N > Chunk Then MemCopy(Buf + Chunk, P^.Buf, N - Chunk);
  P^.Head := (P^.Head + N) Mod PipeSize;
  Dec(P^.Len, N);
  WakeUp(P^.Wchan);
  PipeRead := N;
End;

Function PipeWrite(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var P : PPipe; Done, N, Tail, Chunk : LongInt;
Begin
  P := PipeOf(F^.Inode);
  Done := 0;
  While Done < Cnt Do
  Begin
    If P^.Readers = 0 Then
    Begin
      SendSig(Cur, SIGPIPE);
      If Done > 0 Then PipeWrite := Done Else PipeWrite := -EPIPE;
      Exit;
    End;
    N := Cnt - Done;
    If (Cnt <= PipeSize) And (PipeSize - P^.Len < N)
        Then N := 0     { ecriture atomique }
    Else If N > PipeSize - P^.Len Then N := PipeSize - P^.Len;
    If N = 0 Then
    Begin
      If (F^.Flags And O_NONBLOCK) <> 0 Then
      Begin
        If Done > 0 Then PipeWrite := Done Else PipeWrite := -EAGAIN;
        Exit;
      End;
      If SleepOn(P^.Wchan, 0, True) = WakeSignal Then
      Begin
        If Done > 0 Then PipeWrite := Done Else PipeWrite := -ERESTARTSYS;
        Exit;
      End;
    End
    Else
    Begin
      Tail := (P^.Head + P^.Len) Mod PipeSize;
      Chunk := N;
      If Chunk > PipeSize - Tail Then Chunk := PipeSize - Tail;
      MemCopy(P^.Buf + Tail, Buf + Done, Chunk);
      If N > Chunk Then MemCopy(P^.Buf, Buf + Done + Chunk, N - Chunk);
      Inc(P^.Len, N);
      Done := Done + N;
      WakeUp(P^.Wchan);
    End;
  End;
  F^.Inode^.Mtime := NowSec;
  PipeWrite := Done;
End;

{ Ouverture d'un FIFO (mknod p) ou d'un tube : comptage des extremites }
Function PipeOpen(I : PInode; F : PFile) : LongInt;
Var P : PPipe; Acc, G : LongInt;
Begin
  P := PipeOf(I);
  If P = Nil Then
  Begin
    PipeOpen := -ENOMEM;
    Exit;
  End;
  Acc := F^.Flags And O_ACCMODE;
  F^.Priv := 1;
  If Acc = O_RDONLY Then
  Begin
    Inc(P^.Readers);
    Inc(P^.RGen);
    G := P^.WGen;
    WakeUp(P^.Wchan);
    If (P^.Writers = 0) And ((F^.Flags And O_NONBLOCK) = 0) And (I^.Nlink > 0)
        And (I^.Priv2 = 0) Then
      While (P^.Writers = 0) And (P^.WGen = G) Do
        If SleepOn(P^.Wchan, 0, True) = WakeSignal Then
        Begin
          Dec(P^.Readers);
          PipeOpen := -ERESTARTSYS;
          Exit;
        End;
  End
  Else If Acc = O_WRONLY Then
  Begin
    If (P^.Readers = 0) And ((F^.Flags And O_NONBLOCK) <> 0) And (I^.Priv2
        = 0) Then
    Begin
      PipeOpen := -ENXIO;
      Exit;
    End;
    Inc(P^.Writers);
    Inc(P^.WGen);
    G := P^.RGen;
    WakeUp(P^.Wchan);
    If (P^.Readers = 0) And (I^.Priv2 = 0) Then
      While (P^.Readers = 0) And (P^.RGen = G) Do
        If SleepOn(P^.Wchan, 0, True) = WakeSignal Then
        Begin
          Dec(P^.Writers);
          PipeOpen := -ERESTARTSYS;
          Exit;
        End;
  End
  Else
  Begin
    Inc(P^.Readers);
    Inc(P^.Writers);
    WakeUp(P^.Wchan);
  End;
  PipeOpen := 0;
End;

Procedure PipeRelease(F : PFile);
Var P : PPipe; Acc : LongInt;
Begin
  P := Pointer(F^.Inode^.Pipe);
  If (P = Nil) Or (F^.Priv = 0) Then Exit;
  Acc := F^.Flags And O_ACCMODE;
  If (Acc = O_RDONLY) Or (Acc = O_RDWR) Then Dec(P^.Readers);
  If (Acc = O_WRONLY) Or (Acc = O_RDWR) Then Dec(P^.Writers);
  WakeUp(P^.Wchan);
End;

Function PipePoll(F : PFile; Ev : LongInt) : LongInt;
Var P : PPipe; R : LongInt;
Begin
  P := PipeOf(F^.Inode);
  R := 0;
  If (F^.Flags And O_ACCMODE) <> O_WRONLY Then
  Begin
    If P^.Len > 0 Then R := R Or POLLIN;
    If (P^.Writers = 0) And (P^.Len = 0) Then R := R Or POLLHUP;
  End;
  If (F^.Flags And O_ACCMODE) <> O_RDONLY Then
  Begin
    If P^.Len < PipeSize Then R := R Or POLLOUT;
    If P^.Readers = 0 Then R := R Or POLLERR;
  End;
  PipePoll := R;
End;

Function PipeIoctl(F : PFile; Cmd, Arg : LongInt) : LongInt;
Var P : PPipe;
Begin
  P := PipeOf(F^.Inode);
  If Cmd = $541B Then PipeIoctl := PutUserL(Arg, P^.Len)
  Else PipeIoctl := -ENOTTY;
End;

{ pipe() : deux descripteurs (lecture, ecriture) ; retourne 0 ou -errno }
Function MakePipe(Var F1, F2 : PFile) : LongInt;
Var I : PInode; D : PDentry; P : PPipe;
Begin
  F1 := Nil; F2 := Nil;
  MakePipe := -ENFILE;
  I := NewInode(PipeSb, S_IFIFO Or $180);
  If I = Nil Then Exit;
  I^.Priv2 := 1;                       { tube anonyme }
  I^.FOps := PipeFOpsAddr;
  P := PipeOf(I);
  If P = Nil Then
  Begin
    I^.Nlink := 0;
    InodePut(LongInt(I));
    MakePipe := -ENOMEM;
    Exit;
  End;
  D := DentryNew(Nil, '', I, PipeSb);
  If D = Nil Then
  Begin
    I^.Nlink := 0;
    InodePut(LongInt(I));
    Exit;
  End;
  F1 := FileNew(D, O_RDONLY);
  DentryGet(LongInt(D));
  F2 := FileNew(D, O_WRONLY);
  If (F1 = Nil) Or (F2 = Nil) Then
  Begin
    MakePipe := -ENFILE;
    Exit;
  End;
  F1^.Priv := 1; F2^.Priv := 1;
  P^.Readers := 1; P^.Writers := 1;
  I^.Nlink := 0;                       { disparait avec la derniere reference }
  MakePipe := 0;
End;

{ ---- Peripheriques memoire : /dev/null, zero, full, random, urandom ---- }

Function MemDevRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var Minor, I, V : LongInt;
Begin
  Minor := F^.Inode^.Rdev And $FF;
  Case Minor Of
    3 : MemDevRead := 0;
    5, 7 :
      Begin
        MemFill(Buf, 0, Cnt);
        MemDevRead := Cnt;
      End;
    8, 9 :
      Begin
        I := 0;
        While I < Cnt Do
        Begin
          V := RandNext;
          Mem[0:Buf + I] := V And $FF;
          Inc(I);
        End;
        MemDevRead := Cnt;
      End;
  Else
    MemDevRead := -ENXIO;
  End;
End;

Function MemDevWrite(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var Minor : LongInt;
Begin
  Minor := F^.Inode^.Rdev And $FF;
  Case Minor Of
    3, 5 : MemDevWrite := Cnt;
    7 : MemDevWrite := -ENOSPC;
    8, 9 : MemDevWrite := Cnt;
  Else
    MemDevWrite := -ENXIO;
  End;
End;

Function MemDevLseek(F : PFile; Off, Whence : LongInt) : LongInt;
Begin
  MemDevLseek := 0;
End;

{ ---- Peripheriques blocs (/dev/hda...) via le cache de tampons ---- }

Function BdevRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var Dev, Total, N, Done, Blk, Off, Chunk : LongInt; B : PBuf;
Begin
  Dev := F^.Inode^.Rdev;
  Total := BlkSectors(Dev) * 512;
  If Total = 0 Then
  Begin
    BdevRead := -ENXIO;
    Exit;
  End;
  If F^.Pos >= Total Then
  Begin
    BdevRead := 0;
    Exit;
  End;
  N := Total - F^.Pos;
  If N > Cnt Then N := Cnt;
  Done := 0;
  While Done < N Do
  Begin
    Blk := F^.Pos Div 1024;
    Off := F^.Pos Mod 1024;
    Chunk := 1024 - Off;
    If Chunk > N - Done Then Chunk := N - Done;
    B := BRead(Dev, Blk, 1024);
    If B = Nil Then
    Begin
      If Done = 0 Then BdevRead := -EIO Else BdevRead := Done;
      Exit;
    End;
    MemCopy(Buf + Done, B^.Data + Off, Chunk);
    BRelease(B);
    Done := Done + Chunk;
    F^.Pos := F^.Pos + Chunk;
  End;
  BdevRead := Done;
End;

Function BdevWrite(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var Dev, Total, N, Done, Blk, Off, Chunk : LongInt; B : PBuf;
Begin
  Dev := F^.Inode^.Rdev;
  Total := BlkSectors(Dev) * 512;
  If Total = 0 Then
  Begin
    BdevWrite := -ENXIO;
    Exit;
  End;
  If F^.Pos >= Total Then
  Begin
    BdevWrite := -ENOSPC;
    Exit;
  End;
  N := Total - F^.Pos;
  If N > Cnt Then N := Cnt;
  Done := 0;
  While Done < N Do
  Begin
    Blk := F^.Pos Div 1024;
    Off := F^.Pos Mod 1024;
    Chunk := 1024 - Off;
    If Chunk > N - Done Then Chunk := N - Done;
    If Chunk = 1024 Then B := BGetBlk(Dev, Blk, 1024) Else B := BRead(Dev, Blk,
        1024);
    If B = Nil Then
    Begin
      If Done = 0 Then BdevWrite := -EIO Else BdevWrite := Done;
      Exit;
    End;
    MemCopy(B^.Data + Off, Buf + Done, Chunk);
    BDirty(B);
    BRelease(B);
    Done := Done + Chunk;
    F^.Pos := F^.Pos + Chunk;
  End;
  BdevWrite := Done;
End;

Function BdevIoctl(F : PFile; Cmd, Arg : LongInt) : LongInt;
Begin
  Case Cmd Of
    $1260 : BdevIoctl := PutUserL(Arg, BlkSectors(F^.Inode^.Rdev));
        { BLKGETSIZE }
    $125E : BdevIoctl := 0;
        { BLKFLSBUF }
  Else
    BdevIoctl := -ENOTTY;
  End;
End;

Function BdevLseek(F : PFile; Off, Whence : LongInt) : LongInt;
Var P : LongInt;
Begin
  Case Whence Of
    0 : P := Off;
    1 : P := F^.Pos + Off;
    2 : P := BlkSectors(F^.Inode^.Rdev) * 512 + Off;
  Else
    P := -1;
  End;
  If P < 0 Then
  Begin
    BdevLseek := -EINVAL;
    Exit;
  End;
  F^.Pos := P;
  BdevLseek := P;
End;

Procedure InitDevices;
Begin
  PipeSb := SuperNew(0);
  PipeSb^.Dev := NextAnonDev;
  PipeSb^.SOps := LongInt(@TmpSOps[0]);
  Inc(NextAnonDev);
  MemFill(LongInt(@PipeFOps[0]), 0, SizeOf(PipeFOps));
  PipeFOps[FoRead] := LongInt(@PipeRead);
  PipeFOps[FoWrite] := LongInt(@PipeWrite);
  PipeFOps[FoOpen] := LongInt(@PipeOpen);
  PipeFOps[FoRelease] := LongInt(@PipeRelease);
  PipeFOps[FoPoll] := LongInt(@PipePoll);
  PipeFOps[FoIoctl] := LongInt(@PipeIoctl);
  PipeFOpsAddr := LongInt(@PipeFOps[0]);
  MemFill(LongInt(@MemFOps[0]), 0, SizeOf(MemFOps));
  MemFOps[FoRead] := LongInt(@MemDevRead);
  MemFOps[FoWrite] := LongInt(@MemDevWrite);
  MemFOps[FoLlseek] := LongInt(@MemDevLseek);
  ChrOps[1] := LongInt(@MemFOps[0]);
  MemFill(LongInt(@BlkFOps[0]), 0, SizeOf(BlkFOps));
  BlkFOps[FoRead] := LongInt(@BdevRead);
  BlkFOps[FoWrite] := LongInt(@BdevWrite);
  BlkFOps[FoIoctl] := LongInt(@BdevIoctl);
  BlkFOps[FoLlseek] := LongInt(@BdevLseek);
  BlkFOpsAddr := LongInt(@BlkFOps[0]);
End;

{ ==================================================================== }
{ Phase 2 - /proc : systeme de fichiers synthetique                    }
{ ==================================================================== }

Const
  ProcBufSize = 8192;
  PrNames : Array[0..10] Of String[12] = (
    '', '', 'version', 'meminfo', 'uptime', 'mounts', 'cpuinfo', 'stat',
    'loadavg', 'filesystems', 'cmdline');
  PrSelf      = 11;             { /proc/self : lien symbolique vers le pid }
  PrFirstPid  = 12;             { premiere entree "numerique" dans readdir }

Var
  ProcOps, ProcFOps, ProcDirFOps, ProcLnkOps : Array[0..15] Of LongInt;
  ProcBuf     : Array[0..ProcBufSize - 1] Of Byte;
  ProcLen     : LongInt;

Procedure PAdd(Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do
    If ProcLen < ProcBufSize Then
    Begin
      ProcBuf[ProcLen] := Ord(S[I]);
      Inc(ProcLen);
    End;
End;

Procedure PAddLn(Const S : String);
Begin
  PAdd(S);
  PAdd(#10);
End;

{ Lire Len octets de l'espace d'adressage d'une tache (adresse Va) }
Function ReadTaskMem(T : PTask; Va, Len : LongInt; Var Out : String) : LongInt;
Var N, P, Pte : LongInt;
Begin
  Out := '';
  N := 0;
  If T^.Mm = Nil Then Exit;
  While (N < Len) And (Length(Out) < 250) Do
  Begin
    P := PtePtr(T^.Mm, Va + N, False);
    If P = 0 Then Break;
    Pte := MemL[0:P];
    If (Pte And 1) = 0 Then Break;
    Out := Out + Chr(Mem[0:P2V(Pte And LongInt($FFFFF000)) + ((Va + N)
        And $FFF)]);
    Inc(N);
  End;
  ReadTaskMem := N;
End;

Function TaskStateChar(T : PTask) : String;
Begin
  Case T^.State Of
    TsRunnable : TaskStateChar := 'R';
    TsSleeping : TaskStateChar := 'S';
    TsSleepUn : TaskStateChar := 'D';
    TsZombie : TaskStateChar := 'Z';
    TsStopped : TaskStateChar := 'T';
  Else
    TaskStateChar := 'S';
  End;
End;

Function TaskComm(T : PTask) : String;
Var S : String; I : LongInt;
Begin
  S := '';
  I := 0;
  While (I < 16) And (T^.Comm[I] <> 0) Do
  Begin
    S := S + Chr(T^.Comm[I]);
    Inc(I);
  End;
  TaskComm := S;
End;

Procedure GenMounts;
Var I, K, Pass : LongInt; Sb : PSuper; Dn, Pth : String;
Begin
  For Pass := 0 To 1 Do
    For I := 0 To MaxSupers - 1 Do
    Begin
      Sb := Supers[I];
      If (Sb <> Nil) And (Sb^.Root <> Nil)
          And ((Sb^.Covered = Nil) = (Pass = 0)) Then
      Begin
        Dn := '';
        If Sb^.DevName <> 0 Then
          For K := 1 To Mem[0:Sb^.DevName] Do
            Dn := Dn + Chr(Mem[0:Sb^.DevName + K]);
        If Sb^.Covered <> Nil Then Pth := DentryPath(Sb^.Covered)
        Else Pth := '/';
        If (Sb^.Flags And MS_RDONLY) <> 0 Then
          PAddLn(Dn + ' ' + Pth + ' ' + FsNames[Sb^.FsType] + ' ro 0 0')
        Else
          PAddLn(Dn + ' ' + Pth + ' ' + FsNames[Sb^.FsType] + ' rw 0 0');
      End;
    End;
End;

Procedure GenMaps(T : PTask);
Var V : PVma; Perm, Nm : String; Ino : LongInt; Ip : PInode;
Begin
  If T^.Mm = Nil Then Exit;
  V := T^.Mm^.Vma;
  While V <> Nil Do
  Begin
    Perm := '';
    If (V^.Prot And 1) <> 0 Then Perm := Perm + 'r' Else Perm := Perm + '-';
    If (V^.Prot And 2) <> 0 Then Perm := Perm + 'w' Else Perm := Perm + '-';
    If (V^.Prot And 4) <> 0 Then Perm := Perm + 'x' Else Perm := Perm + '-';
    If (V^.Flags And MAP_SHARED) <> 0 Then Perm := Perm + 's' Else Perm := Perm
        + 'p';
    Ino := 0;
    Nm := '';
    If V^.Ino <> 0 Then
    Begin
      Ip := Pointer(V^.Ino);
      Ino := Ip^.Ino;
    End;
    If (V^.Flags And VmStack) <> 0 Then Nm := '[stack]'
    Else If (V^.Flags And VmHeap) <> 0 Then Nm := '[heap]';
    PAddLn(HexStr(V^.Start, 8) + '-' + HexStr(V^.Fin, 8) + ' ' + Perm + ' ' +
           HexStr(V^.Off, 8) + ' 00:00 ' + IntStr(Ino) + '   ' + Nm);
    V := V^.Next;
  End;
End;

{ Contenu d'un fichier de /proc : place dans ProcBuf }
Procedure ProcGenerate(Ino : LongInt);
Var Pid, Idx, I, N, Ticks, Rss, Vsz : LongInt; T : PTask; S : String;
    Tot : LongInt;
Begin
  ProcLen := 0;
  Pid := Ino Shr 8;
  Idx := Ino And 255;
  If Pid = 0 Then
  Begin
    Case Idx Of
      2 : PAddLn('Linux version ' + UnameRel + ' (LINUX-0 KERNEL32 ' + KVersion + ') #1 i386');
      3 : Begin
            PAddLn('MemTotal:     ' + IntStr(TotalFreePages * 4) + ' kB');
            PAddLn('MemFree:      ' + IntStr(FreePagesCnt * 4) + ' kB');
            PAddLn('Buffers:      ' + IntStr(BufCount) + ' kB');
            PAddLn('Cached:       0 kB');
            PAddLn('SwapTotal:    0 kB');
            PAddLn('SwapFree:     0 kB');
          End;
      4 : PAddLn(IntStr(Jiffies Div HZ) + '.' + IntStr((Jiffies Mod HZ)
          Div 10) +
                 IntStr((Jiffies Mod HZ) Mod 10) + ' ' + IntStr(Jiffies Div HZ)
                     + '.00');
      5 : GenMounts;
      6 : Begin
            PAddLn('processor       : 0');
            PAddLn('vendor_id       : LINUX-0');
            PAddLn('model name      : i386 compatible');
            PAddLn('bogomips        : 100.00');
          End;
      7 : Begin
            Tot := 0;
            For I := 1 To MaxTasks - 1 Do
              If Tasks[I].State <> TsFree Then Tot := Tot + Tasks[I].Utime;
            PAddLn('cpu  ' + IntStr(Tot) + ' 0 0 ' + IntStr(Jiffies)
                + ' 0 0 0 0');
            PAddLn('ctxt ' + IntStr(NrSwitches));
            PAddLn('btime ' + IntStr(BootTime));
            PAddLn('processes ' + IntStr(NextPid));
            PAddLn('procs_running 1');
          End;
      8 : PAddLn('0.00 0.00 0.00 1/' + IntStr(NrTasks) + ' ' + IntStr(NextPid));
      9 : For I := 0 To NFsTypes - 1 Do
            If (FsNames[I] = 'tmpfs') Or (FsNames[I] = 'ramfs') Or (FsNames[I]
                = 'devtmpfs') Or
               (FsNames[I] = 'proc') Then PAddLn('nodev' + #9 + FsNames[I])
            Else PAddLn(#9 + FsNames[I]);
      10 : PAddLn(CmdLine);
    End;
    Exit;
  End;
  T := PidTask(Pid);
  If T = Nil Then Exit;
  Case Idx Of
    1 : Begin                                       { stat }
          Rss := 0; Vsz := 0;
          If T^.Mm <> Nil Then
          Begin
            Rss := T^.Mm^.Rss; Vsz := T^.Mm^.TotalVm * 4096;
          End;
          If T^.Parent <> Nil Then N := T^.Parent^.Pid Else N := 0;
          PAddLn(IntStr(T^.Pid) + ' (' + TaskComm(T) + ') ' + TaskStateChar(T)
              + ' ' +
                 IntStr(N) + ' ' + IntStr(T^.Pgid) + ' ' + IntStr(T^.Sid)
                     + ' 0 0 0 0 0 0 0 ' +
                 IntStr(T^.Utime) + ' ' + IntStr(T^.Stime) + ' '
                     + IntStr(T^.Cutime) + ' ' +
                 IntStr(T^.Cstime) + ' ' + IntStr(20 - T^.Nice) + ' '
                     + IntStr(T^.Nice) +
                 ' 1 0 ' + IntStr(T^.StartTime) + ' ' + IntStr(Vsz) + ' '
                     + IntStr(Rss) +
                 ' 0 0 0 0 0 0 0 0 0 0 0 0 0 17 0 0 0');
        End;
    2 : Begin                                       { status }
          PAddLn('Name:   ' + TaskComm(T));
          PAddLn('State:  ' + TaskStateChar(T));
          PAddLn('Tgid:   ' + IntStr(T^.Tgid));
          PAddLn('Pid:    ' + IntStr(T^.Pid));
          If T^.Parent <> Nil Then PAddLn('PPid:   ' + IntStr(T^.Parent^.Pid))
          Else PAddLn('PPid:   0');
          PAddLn('Uid:    ' + IntStr(T^.Uid) + ' ' + IntStr(T^.Euid) + ' '
              + IntStr(T^.Suid) + ' ' + IntStr(T^.Fsuid));
          PAddLn('Gid:    ' + IntStr(T^.Gid) + ' ' + IntStr(T^.Egid) + ' '
              + IntStr(T^.Sgid) + ' ' + IntStr(T^.Fsgid));
          If T^.Mm <> Nil Then
          Begin
            PAddLn('VmSize: ' + IntStr(T^.Mm^.TotalVm * 4) + ' kB');
            PAddLn('VmRSS:  ' + IntStr(T^.Mm^.Rss * 4) + ' kB');
          End;
          PAddLn('SigPnd: ' + HexStr(T^.Pend[0], 8));
          PAddLn('SigBlk: ' + HexStr(T^.Blk[0], 8));
        End;
    3 : If (T^.Mm <> Nil) And (T^.Mm^.ArgEnd > T^.Mm^.ArgStart)
        Then   { cmdline }
        Begin
          N := T^.Mm^.ArgEnd - T^.Mm^.ArgStart;
          I := 0;
          While (I < N) And (ProcLen < ProcBufSize - 1) Do
          Begin
            ReadTaskMem(T, T^.Mm^.ArgStart + I, 1, S);
            If S = '' Then Break;
            ProcBuf[ProcLen] := Ord(S[1]);
            Inc(ProcLen);
            Inc(I);
          End;
        End;
    4 : GenMaps(T);
  End;
  Ticks := 0;
End;

Function ProcMkInode(Sb : PSuper; Ino, Mode : LongInt) : PInode;
Var I : PInode;
Begin
  Sb^.NextIno := Ino;
  I := NewInode(Sb, Mode);
  ProcMkInode := I;
  If I = Nil Then Exit;
  I^.Nlink := 0;                         { libere avec la derniere reference }
  I^.Uid := 0; I^.Gid := 0;
  If (Mode And S_IFMT) = S_IFDIR Then
  Begin
    I^.IOps := LongInt(@ProcOps[0]);
    I^.FOps := LongInt(@ProcDirFOps[0]);
  End
  Else If (Mode And S_IFMT) = S_IFLNK Then I^.IOps := LongInt(@ProcLnkOps[0])
  Else I^.FOps := LongInt(@ProcFOps[0]);
End;

Function ProcLookup(Dir : PInode; Var Nm : String; Var Res : PInode) : LongInt;
Var I, Pid, Idx : LongInt; T : PTask; Names4 : String;
Begin
  ProcLookup := -ENOENT;
  If Dir^.Ino = 1 Then
  Begin
    For I := 2 To PrSelf - 1 Do
      If PrNames[I] = Nm Then
      Begin
        Res := ProcMkInode(Dir^.Sb, I, S_IFREG Or $124);
        ProcLookup := 0;
        Exit;
      End;
    If Nm = 'self' Then
    Begin
      Res := ProcMkInode(Dir^.Sb, PrSelf, S_IFLNK Or $1FF);
      ProcLookup := 0;
      Exit;
    End;
    Pid := StrVal(Nm);
    If (Pid > 0) And (IntStr(Pid) = Nm) Then
    Begin
      T := PidTask(Pid);
      If T <> Nil Then
      Begin
        Res := ProcMkInode(Dir^.Sb, Pid * 256, S_IFDIR Or $16D);
        If Res <> Nil Then
        Begin
          Res^.Uid := T^.Uid; Res^.Gid := T^.Gid;
          ProcLookup := 0;
        End;
      End;
    End;
    Exit;
  End;
  Pid := Dir^.Ino Shr 8;
  If PidTask(Pid) = Nil Then Exit;
  Idx := 0;
  If Nm = 'stat' Then Idx := 1
  Else If Nm = 'status' Then Idx := 2
  Else If Nm = 'cmdline' Then Idx := 3
  Else If Nm = 'maps' Then Idx := 4;
  If Idx <> 0 Then
  Begin
    Res := ProcMkInode(Dir^.Sb, Pid * 256 + Idx, S_IFREG Or $124);
    ProcLookup := 0;
  End;
  Names4 := '';
End;

Function ProcReadlink(I : PInode; Buf, Size : LongInt) : LongInt;
Var S : String; N : LongInt;
Begin
  S := IntStr(Cur^.Tgid);
  N := Length(S);
  If N > Size Then N := Size;
  MemCopy(Buf, LongInt(@S) + 1, N);
  ProcReadlink := N;
End;

Function ProcRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var N : LongInt;
Begin
  ProcGenerate(F^.Inode^.Ino);
  If F^.Pos >= ProcLen Then
  Begin
    ProcRead := 0;
    Exit;
  End;
  N := ProcLen - F^.Pos;
  If N > Cnt Then N := Cnt;
  MemCopy(Buf, LongInt(@ProcBuf[0]) + F^.Pos, N);
  F^.Pos := F^.Pos + N;
  ProcRead := N;
End;

Function ProcReaddir(F : PFile; Var Ino : LongInt; Var Nm : String;
    Var DType : LongInt) : LongInt;
Var D : PInode; K, I, C : LongInt; Names : Array[0..3] Of String[8];
Begin
  D := F^.Inode;
  ProcReaddir := 1;
  If F^.Pos = 0 Then
  Begin
    Ino := D^.Ino; Nm := '.'; DType := DT_DIR;
    Inc(F^.Pos);
    Exit;
  End;
  If F^.Pos = 1 Then
  Begin
    Ino := 1; Nm := '..'; DType := DT_DIR;
    Inc(F^.Pos);
    Exit;
  End;
  K := F^.Pos - 2;
  If D^.Ino = 1 Then
  Begin
    If K < PrSelf - 2 Then
    Begin
      Nm := PrNames[K + 2]; Ino := K + 2; DType := DT_REG;
      Inc(F^.Pos);
      Exit;
    End;
    If K = PrSelf - 2 Then
    Begin
      Nm := 'self'; Ino := PrSelf; DType := DT_LNK;
      Inc(F^.Pos);
      Exit;
    End;
    C := K - (PrSelf - 1);
    For I := 1 To MaxTasks - 1 Do
      If Tasks[I].State <> TsFree Then
      Begin
        If C = 0 Then
        Begin
          Nm := IntStr(Tasks[I].Pid); Ino := Tasks[I].Pid * 256;
              DType := DT_DIR;
          Inc(F^.Pos);
          Exit;
        End;
        Dec(C);
      End;
    ProcReaddir := 0;
    Exit;
  End;
  If K < 4 Then
  Begin
    Case K Of
      0 : Nm := 'stat';
      1 : Nm := 'status';
      2 : Nm := 'cmdline';
    Else
      Nm := 'maps';
    End;
    Ino := (D^.Ino And Not 255) + K + 1; DType := DT_REG;
    Inc(F^.Pos);
    Exit;
  End;
  ProcReaddir := 0;
  Names[0] := '';
End;

Function ProcMountFn(Sb : PSuper; Var DevName : String; Flags,
    Data : LongInt) : LongInt;
Var I : PInode; D : PDentry;
Begin
  ProcMountFn := -ENOMEM;
  Sb^.Dev := NextAnonDev;
  Inc(NextAnonDev);
  Sb^.Pinned := 0;
  I := ProcMkInode(Sb, 1, S_IFDIR Or $16D);
  If I = Nil Then Exit;
  D := DentryNew(Nil, '', I, Sb);
  If D = Nil Then Exit;
  Sb^.Root := D;
  ProcMountFn := 0;
End;

Procedure InitProc;
Begin
  RegisterFs('proc', LongInt(@ProcMountFn));
  MemFill(LongInt(@ProcOps[0]), 0, SizeOf(ProcOps));
  ProcOps[IoLookup] := LongInt(@ProcLookup);
  MemFill(LongInt(@ProcLnkOps[0]), 0, SizeOf(ProcLnkOps));
  ProcLnkOps[IoReadlink] := LongInt(@ProcReadlink);
  MemFill(LongInt(@ProcFOps[0]), 0, SizeOf(ProcFOps));
  ProcFOps[FoRead] := LongInt(@ProcRead);
  MemFill(LongInt(@ProcDirFOps[0]), 0, SizeOf(ProcDirFOps));
  ProcDirFOps[FoReaddir] := LongInt(@ProcReaddir);
End;

{ ==================================================================== }
{ Partie 18 - ext2 : systeme de fichiers lecture/ecriture sur disque   }
{ ==================================================================== }
{ (placee avant la partie 14 : elle n'utilise que les parties 1 a 13)  }

{ ext2 : superbloc, descripteurs de groupes, bitmaps, inodes de 128 ou
  256 octets, revisions 0 et 1, blocs de 1, 2 ou 4 Ko, sparse_super,
  filetype, indirections simple/double/triple, repertoires lineaires,
  liens durs et symboliques (rapides et lents), fichiers speciaux.
  Ni extents, ni journal (ext3 propre : monte comme ext2 ; journal a
  rejouer : lecture seule), ni attributs etendus (le bloc d'EA d'un inode
  supprime est libere), ni meta_bg, ni 64bit, ni sommes de controle
  (lecture seule). Fichiers limites a 2 Go.
  Tous les acces passent par le cache de tampons de la partie 11 ; les
  tampons du superbloc et des descripteurs de groupes restent epingles
  (compteur > 0) pendant le montage. Le noyau n'etant jamais interrompu
  pendant ces fonctions (les lectures disque sont en attente active), il
  n'y a aucun verrou. Les modifications sont ecrites dans le cache de
  tampons ; l'ecriture sur disque est differee (bdflush, sync). }

Const
  ExMagic        = $EF53;
  ExRootIno      = 2;
  ExStValid      = 1;
  ExStError      = 2;
  ExIncFiletype  = $0002;
  ExIncRecover   = $0004;
  ExIncFlexBg    = $0200;
  ExCompatJournal = $0004;
  ExRoSparse     = $0001;
  ExRoLargeFile  = $0002;
  ExRoBtree      = $0004;
  ExRoHugeFile   = $0008;
  ExRoDirNlink   = $0020;
  ExRoExtraIsize = $0040;
  ExRoGdtCsum    = $0010;
  ExIndexFl      = $1000;
  ExMaxLinks     = 32000;
  ExMaxFileSize  = $7FFFFFFF;

Type
  PExSb = ^TExSb;
  TExSb = Record
    Dev, Bs, Ppb, FirstData, BlocksCount, InodesCount : LongInt;
    Bpg, Ipg, Groups, InodeSize, FirstIno, Rev : LongInt;
    Incompat, RoCompat, Compat : LongInt;
    GdtBlocks, GdPerBlk, Itb : LongInt;
    SbBuf         : PBuf;
    SbOff         : LongInt;
    GdBufs        : LongInt;        { tableau de PBuf (un par bloc de GDT) }
    MountState    : LongInt;        { s_state lu au montage }
    Overhead      : LongInt;        { blocs de metadonnees (statfs) }
    NoSync        : LongInt;
  End;

Var
  ExFileIOps, ExDirIOps, ExLnkIOps, ExSpecIOps : Array[0..15] Of LongInt;
  ExFileFOps, ExDirFOps, ExSOps                : Array[0..15] Of LongInt;

Function ExOf(Sb : PSuper) : PExSb;
Begin
  ExOf := Pointer(Sb^.Priv);
End;

{ Adresse du superbloc dans son tampon epingle }
Function ExSbA(E : PExSb) : LongInt;
Begin
  ExSbA := E^.SbBuf^.Data + E^.SbOff;
End;

Procedure ExSbDirty(E : PExSb);
Begin
  BDirty(E^.SbBuf);
End;

Procedure ExAddFreeBlocks(E : PExSb; Delta : LongInt);
Var A : LongInt;
Begin
  A := ExSbA(E);
  MemL[0:A + 12] := MemL[0:A + 12] + Delta;
  ExSbDirty(E);
End;

Procedure ExAddFreeInodes(E : PExSb; Delta : LongInt);
Var A : LongInt;
Begin
  A := ExSbA(E);
  MemL[0:A + 16] := MemL[0:A + 16] + Delta;
  ExSbDirty(E);
End;

{ Descripteur du groupe G (32 octets dans un tampon epingle) }
Function ExGd(E : PExSb; G : LongInt) : LongInt;
Var B : PBuf;
Begin
  B := Pointer(MemL[0:E^.GdBufs + (G Div E^.GdPerBlk) * 4]);
  ExGd := B^.Data + (G Mod E^.GdPerBlk) * 32;
End;

Procedure ExGdDirty(E : PExSb; G : LongInt);
Var B : PBuf;
Begin
  B := Pointer(MemL[0:E^.GdBufs + (G Div E^.GdPerBlk) * 4]);
  BDirty(B);
End;

{ Lire le bloc Blk (verifie qu'il est dans le systeme de fichiers) }
Function ExBRead(E : PExSb; Blk : LongInt) : PBuf;
Begin
  If (Blk < E^.FirstData) Or (Blk >= E^.BlocksCount) Then
  Begin
    KLog('ext2 : bloc ' + IntStr(Blk) + ' hors limites');
    ExBRead := Nil;
  End
  Else ExBRead := BRead(E^.Dev, Blk, E^.Bs);
End;

{ ---- Bitmaps ---- }

Function ExBitTest(Base, Bit : LongInt) : Boolean;
Begin
  ExBitTest := (Mem[0:Base + (Bit Shr 3)] And (1 Shl (Bit And 7))) <> 0;
End;

Procedure ExBitSet(Base, Bit : LongInt);
Begin
  Mem[0:Base + (Bit Shr 3)] := Mem[0:Base + (Bit Shr 3)]
      Or (1 Shl (Bit And 7));
End;

Procedure ExBitClr(Base, Bit : LongInt);
Begin
  Mem[0:Base + (Bit Shr 3)] := Mem[0:Base + (Bit Shr 3)]
      And Not (1 Shl (Bit And 7));
End;

{ Premier bit a zero dans [Start, Lim) ou -1 }
Function ExFindZero(Base, Start, Lim : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := Start;
  While I < Lim Do
  Begin
    If ((I And 7) = 0) And (I + 8 <= Lim) And (Mem[0:Base + (I Shr 3)] = $FF)
        Then I := I + 8
    Else If (Mem[0:Base + (I Shr 3)] And (1 Shl (I And 7))) = 0 Then
    Begin
      ExFindZero := I;
      Exit;
    End
    Else Inc(I);
  End;
  ExFindZero := -1;
End;

{ Nombre de blocs du groupe G }
Function ExGroupBlocks(E : PExSb; G : LongInt) : LongInt;
Begin
  If G = E^.Groups - 1 Then
    ExGroupBlocks := E^.BlocksCount - E^.FirstData - G * E^.Bpg
  Else ExGroupBlocks := E^.Bpg;
End;

{ ---- Allocation de blocs ---- }

{ Allouer un bloc le plus pres possible de Goal ; le contenu n'est pas
  initialise. 0 ou -errno }
Function ExAllocBlock(E : PExSb; Goal : LongInt; Var Blk : LongInt) : LongInt;
Var G, G0, N, Gd, Start, Lim, Bit, Free, Rsv : LongInt; B : PBuf;
    A : LongInt;
Begin
  Blk := 0;
  A := ExSbA(E);
  Free := MemL[0:A + 12];
  Rsv := MemL[0:A + 8];
  If Free <= 0 Then
  Begin
    ExAllocBlock := -ENOSPC;
    Exit;
  End;
  If (Free <= Rsv) And (Cur^.Fsuid <> 0) Then
  Begin
    ExAllocBlock := -ENOSPC;
    Exit;
  End;
  If (Goal < E^.FirstData) Or (Goal >= E^.BlocksCount) Then
    Goal := E^.FirstData;
  G0 := (Goal - E^.FirstData) Div E^.Bpg;
  For N := 0 To E^.Groups Do
  Begin
    G := (G0 + N) Mod E^.Groups;
    Gd := ExGd(E, G);
    If MemW[0:Gd + 12] > 0 Then
    Begin
      B := ExBRead(E, MemL[0:Gd]);
      If B <> Nil Then
      Begin
        Lim := ExGroupBlocks(E, G);
        If N = 0 Then Start := (Goal - E^.FirstData) Mod E^.Bpg
        Else Start := 0;
        Bit := ExFindZero(B^.Data, Start, Lim);
        If (Bit < 0) And (Start > 0) Then Bit := ExFindZero(B^.Data, 0, Lim);
        If Bit >= 0 Then
        Begin
          ExBitSet(B^.Data, Bit);
          BDirty(B);
          BRelease(B);
          MemW[0:Gd + 12] := MemW[0:Gd + 12] - 1;
          ExGdDirty(E, G);
          ExAddFreeBlocks(E, -1);
          Blk := E^.FirstData + G * E^.Bpg + Bit;
          ExAllocBlock := 0;
          Exit;
        End;
        BRelease(B);
      End;
    End;
  End;
  ExAllocBlock := -ENOSPC;
End;

Procedure ExFreeBlock(E : PExSb; Blk : LongInt);
Var G, Bit, Gd : LongInt; B : PBuf;
Begin
  If (Blk < E^.FirstData) Or (Blk >= E^.BlocksCount) Then
  Begin
    KLog('ext2 : liberation du bloc ' + IntStr(Blk) + ' hors limites');
    Exit;
  End;
  G := (Blk - E^.FirstData) Div E^.Bpg;
  Bit := (Blk - E^.FirstData) Mod E^.Bpg;
  Gd := ExGd(E, G);
  B := ExBRead(E, MemL[0:Gd]);
  If B = Nil Then Exit;
  If Not ExBitTest(B^.Data, Bit) Then
    KLog('ext2 : double liberation du bloc ' + IntStr(Blk))
  Else
  Begin
    ExBitClr(B^.Data, Bit);
    BDirty(B);
    MemW[0:Gd + 12] := MemW[0:Gd + 12] + 1;
    ExGdDirty(E, G);
    ExAddFreeBlocks(E, 1);
  End;
  BRelease(B);
End;

{ ---- Allocation d'inodes ---- }

{ Choisir le groupe d'un nouvel inode : un repertoire va dans un groupe
  peu rempli (celui qui a le plus de blocs libres parmi ceux qui ont plus
  d'inodes libres que la moyenne), les autres pres de leur repertoire }
Function ExAllocInode(E : PExSb; ParentIno : LongInt; IsDirNew : Boolean;
    Var Ino : LongInt) : LongInt;
Var G, G0, N, Gd, Best, BestFree, Ave, Tot, Bit, Fb : LongInt; B : PBuf;
Begin
  Ino := 0;
  If MemL[0:ExSbA(E) + 16] <= 0 Then
  Begin
    ExAllocInode := -ENOSPC;
    Exit;
  End;
  G0 := 0;
  If ParentIno > 0 Then G0 := (ParentIno - 1) Div E^.Ipg;
  If IsDirNew Then
  Begin
    Tot := MemL[0:ExSbA(E) + 16];
    Ave := Tot Div E^.Groups;
    Best := -1; BestFree := -1;
    For G := 0 To E^.Groups - 1 Do
    Begin
      Gd := ExGd(E, G);
      Fb := MemW[0:Gd + 12];
      If (MemW[0:Gd + 14] > 0) And (MemW[0:Gd + 14] >= Ave)
          And (Fb > BestFree) Then
      Begin
        Best := G;
        BestFree := Fb;
      End;
    End;
    If Best >= 0 Then G0 := Best;
  End;
  For N := 0 To E^.Groups - 1 Do
  Begin
    G := (G0 + N) Mod E^.Groups;
    Gd := ExGd(E, G);
    If MemW[0:Gd + 14] > 0 Then
    Begin
      B := ExBRead(E, MemL[0:Gd + 4]);
      If B <> Nil Then
      Begin
        Bit := ExFindZero(B^.Data, 0, E^.Ipg);
        If (G = 0) And (Bit >= 0) And (Bit < E^.FirstIno - 1) Then
        Begin
          { inodes reserves : sauter }
          Bit := ExFindZero(B^.Data, E^.FirstIno - 1, E^.Ipg);
        End;
        If Bit >= 0 Then
        Begin
          ExBitSet(B^.Data, Bit);
          BDirty(B);
          BRelease(B);
          MemW[0:Gd + 14] := MemW[0:Gd + 14] - 1;
          If IsDirNew Then MemW[0:Gd + 16] := MemW[0:Gd + 16] + 1;
          ExGdDirty(E, G);
          ExAddFreeInodes(E, -1);
          Ino := G * E^.Ipg + Bit + 1;
          ExAllocInode := 0;
          Exit;
        End;
        BRelease(B);
      End;
    End;
  End;
  ExAllocInode := -ENOSPC;
End;

Procedure ExFreeInode(E : PExSb; Ino : LongInt; WasDir : Boolean);
Var G, Bit, Gd : LongInt; B : PBuf;
Begin
  If (Ino < 1) Or (Ino > E^.InodesCount) Then Exit;
  G := (Ino - 1) Div E^.Ipg;
  Bit := (Ino - 1) Mod E^.Ipg;
  Gd := ExGd(E, G);
  B := ExBRead(E, MemL[0:Gd + 4]);
  If B = Nil Then Exit;
  If Not ExBitTest(B^.Data, Bit) Then
    KLog('ext2 : double liberation de l''inode ' + IntStr(Ino))
  Else
  Begin
    ExBitClr(B^.Data, Bit);
    BDirty(B);
    MemW[0:Gd + 14] := MemW[0:Gd + 14] + 1;
    If WasDir And (MemW[0:Gd + 16] > 0) Then
      MemW[0:Gd + 16] := MemW[0:Gd + 16] - 1;
    ExGdDirty(E, G);
    ExAddFreeInodes(E, 1);
  End;
  BRelease(B);
End;

{ ---- Inodes sur disque ---- }

{ Tampon contenant l'inode Ino et decalage de l'inode dans ce tampon }
Function ExInodeBuf(E : PExSb; Ino : LongInt; Var Off : LongInt) : PBuf;
Var G, Idx, Gd, Blk, Pos : LongInt;
Begin
  ExInodeBuf := Nil;
  If (Ino < 1) Or (Ino > E^.InodesCount) Then Exit;
  G := (Ino - 1) Div E^.Ipg;
  Idx := (Ino - 1) Mod E^.Ipg;
  Gd := ExGd(E, G);
  Pos := Idx * E^.InodeSize;
  Blk := MemL[0:Gd + 8] + Pos Div E^.Bs;
  Off := Pos Mod E^.Bs;
  ExInodeBuf := ExBRead(E, Blk);
End;

Procedure ExSetOps(I : PInode);
Begin
  I^.FOps := 0;
  Case I^.Mode And S_IFMT Of
    S_IFREG :
      Begin
        I^.IOps := LongInt(@ExFileIOps[0]);
        I^.FOps := LongInt(@ExFileFOps[0]);
      End;
    S_IFDIR :
      Begin
        I^.IOps := LongInt(@ExDirIOps[0]);
        I^.FOps := LongInt(@ExDirFOps[0]);
      End;
    S_IFLNK : I^.IOps := LongInt(@ExLnkIOps[0]);
  Else
    I^.IOps := LongInt(@ExSpecIOps[0]);
  End;
End;

{ Priv de l'inode = copie des 128 premiers octets de l'inode disque }
Function ExReadInode(I : PInode) : LongInt;
Var E : PExSb; B : PBuf; Off, Blob, M : LongInt;
Begin
  E := ExOf(I^.Sb);
  B := ExInodeBuf(E, I^.Ino, Off);
  If B = Nil Then
  Begin
    ExReadInode := -EIO;
    Exit;
  End;
  Blob := KMalloc(128);
  If Blob = 0 Then
  Begin
    BRelease(B);
    ExReadInode := -ENOMEM;
    Exit;
  End;
  MemCopy(Blob, B^.Data + Off, 128);
  BRelease(B);
  M := MemW[0:Blob];
  If (MemW[0:Blob + 26] = 0) Or (M = 0) Then
  Begin
    KFree(Blob);
    ExReadInode := -EIO;
    Exit;
  End;
  I^.Priv := Blob;
  I^.Mode := M;
  I^.Uid := MemW[0:Blob + 2] Or (MemW[0:Blob + 120] Shl 16);
  I^.Gid := MemW[0:Blob + 24] Or (MemW[0:Blob + 122] Shl 16);
  I^.Size := MemL[0:Blob + 4];
  If I^.Size < 0 Then I^.Size := ExMaxFileSize;
  If ((M And S_IFMT) = S_IFREG) And (MemL[0:Blob + 108] <> 0) Then
    I^.Size := ExMaxFileSize;
  I^.Atime := MemL[0:Blob + 8];
  I^.Ctime := MemL[0:Blob + 12];
  I^.Mtime := MemL[0:Blob + 16];
  I^.Nlink := MemW[0:Blob + 26];
  I^.Blocks := MemL[0:Blob + 28];
  I^.Rdev := 0;
  If ((M And S_IFMT) = S_IFCHR) Or ((M And S_IFMT) = S_IFBLK) Then
  Begin
    If MemL[0:Blob + 40] <> 0 Then I^.Rdev := MemL[0:Blob + 40] And $FFFF
    Else
      I^.Rdev := ((MemL[0:Blob + 44] And $FFF00) Shr 8) Shl 8
          Or (MemL[0:Blob + 44] And $FF);
  End;
  ExSetOps(I);
  ExReadInode := 0;
End;

{ Ecrire l'inode (champs generiques + bloc prive) dans le tampon du disque }
Function ExWriteInode(I : PInode) : LongInt;
Var E : PExSb; B : PBuf; Off, Blob : LongInt;
Begin
  ExWriteInode := 0;
  Blob := I^.Priv;
  If Blob = 0 Then Exit;
  E := ExOf(I^.Sb);
  MemW[0:Blob] := I^.Mode And $FFFF;
  MemW[0:Blob + 2] := I^.Uid And $FFFF;
  MemW[0:Blob + 120] := (I^.Uid Shr 16) And $FFFF;
  MemW[0:Blob + 24] := I^.Gid And $FFFF;
  MemW[0:Blob + 122] := (I^.Gid Shr 16) And $FFFF;
  If Not (((I^.Mode And S_IFMT) = S_IFREG) And (MemL[0:Blob + 108] <> 0)) Then
    MemL[0:Blob + 4] := I^.Size;
  MemL[0:Blob + 8] := I^.Atime;
  MemL[0:Blob + 12] := I^.Ctime;
  MemL[0:Blob + 16] := I^.Mtime;
  MemW[0:Blob + 26] := I^.Nlink;
  MemL[0:Blob + 28] := I^.Blocks;
  B := ExInodeBuf(E, I^.Ino, Off);
  If B = Nil Then
  Begin
    ExWriteInode := -EIO;
    Exit;
  End;
  MemCopy(B^.Data + Off, Blob, 128);
  BDirty(B);
  BRelease(B);
  I^.Dirty := 0;
End;

{ ---- Correspondance bloc logique -> bloc disque ---- }

{ Nombre de blocs adressables sous un pointeur de niveau L (1 : simple) }
Function ExSpan(E : PExSb; L : LongInt) : LongInt;
Var N, K : LongInt;
Begin
  N := 1;
  For K := 1 To L Do N := N * E^.Ppb;
  ExSpan := N;
End;

{ Bloc disque du bloc logique Idx de l'inode I (0 = trou). Create : allouer
  le bloc et les blocs d'indirection manquants (Goal : bloc voulu, 0 =
  automatique) ; New devient vrai si le bloc de donnees vient d'etre alloue }
Function ExBmap(I : PInode; Idx : LongInt; Create : Boolean; Goal : LongInt;
    Var Phys : LongInt; Var IsNew : Boolean) : LongInt;
Var E : PExSb; Blob, P, Depth, L, V, NB, SlotA, R, K : LongInt;
    Off : Array[0..3] Of LongInt;
    Owner, Nb2 : PBuf;
Begin
  E := ExOf(I^.Sb);
  Blob := I^.Priv;
  Phys := 0;
  IsNew := False;
  ExBmap := 0;
  If Idx < 0 Then
  Begin
    ExBmap := -EFBIG;
    Exit;
  End;
  P := E^.Ppb;
  If Idx < 12 Then
  Begin
    Depth := 1;
    Off[0] := Idx;
  End
  Else
  Begin
    Idx := Idx - 12;
    If Idx < P Then
    Begin
      Depth := 2;
      Off[0] := 12; Off[1] := Idx;
    End
    Else
    Begin
      Idx := Idx - P;
      If Idx < P * P Then
      Begin
        Depth := 3;
        Off[0] := 13; Off[1] := Idx Div P; Off[2] := Idx Mod P;
      End
      Else
      Begin
        Idx := Idx - P * P;
        If Idx >= P * P * P Then
        Begin
          ExBmap := -EFBIG;
          Exit;
        End;
        Depth := 4;
        Off[0] := 14; Off[1] := Idx Div (P * P);
        Off[2] := (Idx Div P) Mod P; Off[3] := Idx Mod P;
      End;
    End;
  End;
  SlotA := Blob + 40 + Off[0] * 4;
  Owner := Nil;
  For L := 0 To Depth - 1 Do
  Begin
    V := MemL[0:SlotA];
    If V = 0 Then
    Begin
      If Not Create Then
      Begin
        If Owner <> Nil Then BRelease(Owner);
        Exit;
      End;
      R := ExAllocBlock(E, Goal, NB);
      If R <> 0 Then
      Begin
        If Owner <> Nil Then BRelease(Owner);
        ExBmap := R;
        Exit;
      End;
      If L < Depth - 1 Then
      Begin
        Nb2 := BGetBlk(E^.Dev, NB, E^.Bs);
        If Nb2 = Nil Then
        Begin
          ExFreeBlock(E, NB);
          If Owner <> Nil Then BRelease(Owner);
          ExBmap := -ENOMEM;
          Exit;
        End;
        MemFill(Nb2^.Data, 0, E^.Bs);
        BDirty(Nb2);
        BRelease(Nb2);
      End
      Else IsNew := True;
      MemL[0:SlotA] := NB;
      If Owner <> Nil Then BDirty(Owner) Else I^.Dirty := 1;
      Inc(I^.Blocks, E^.Bs Div 512);
      V := NB;
    End;
    If L = Depth - 1 Then
    Begin
      Phys := V;
      If Owner <> Nil Then BRelease(Owner);
      Exit;
    End;
    Goal := V + 1;
    Nb2 := ExBRead(E, V);
    If Owner <> Nil Then BRelease(Owner);
    If Nb2 = Nil Then
    Begin
      ExBmap := -EIO;
      Exit;
    End;
    Owner := Nb2;
    SlotA := Owner^.Data + Off[L + 1] * 4;
  End;
  K := 0;
End;

{ Liberer sous le pointeur SlotA (dans l'inode ou dans le tampon Owner) les
  blocs de donnees d'indice logique >= NewBlocks. Level : 1 = simple.
  Base : indice logique du premier bloc de donnees couvert }
Procedure ExTruncInd(I : PInode; SlotA : LongInt; Owner : PBuf; Level,
    Base, NewBlocks : LongInt);
Var E : PExSb; V, Span, Sub, K, EBase, Cell, Val : LongInt; B : PBuf;
Begin
  E := ExOf(I^.Sb);
  V := MemL[0:SlotA];
  If V = 0 Then Exit;
  Span := ExSpan(E, Level);
  If Base + Span <= NewBlocks Then Exit;
  B := ExBRead(E, V);
  If B = Nil Then Exit;
  Sub := ExSpan(E, Level - 1);
  For K := 0 To E^.Ppb - 1 Do
  Begin
    EBase := Base + K * Sub;
    If EBase + Sub > NewBlocks Then
    Begin
      Cell := B^.Data + K * 4;
      Val := MemL[0:Cell];
      If Val <> 0 Then
      Begin
        If Level = 1 Then
        Begin
          ExFreeBlock(E, Val);
          MemL[0:Cell] := 0;
          Dec(I^.Blocks, E^.Bs Div 512);
          BDirty(B);
        End
        Else
        Begin
          ExTruncInd(I, Cell, B, Level - 1, EBase, NewBlocks);
        End;
      End;
    End;
  End;
  BRelease(B);
  If Base >= NewBlocks Then
  Begin
    ExFreeBlock(E, V);
    MemL[0:SlotA] := 0;
    Dec(I^.Blocks, E^.Bs Div 512);
    If Owner <> Nil Then BDirty(Owner) Else I^.Dirty := 1;
  End;
End;

{ Liberer tous les blocs de donnees (et d'indirection devenus inutiles)
  d'indice logique >= NewBlocks }
Procedure ExTruncBlocks(I : PInode; NewBlocks : LongInt);
Var E : PExSb; Blob, K, P : LongInt;
Begin
  E := ExOf(I^.Sb);
  Blob := I^.Priv;
  P := E^.Ppb;
  For K := NewBlocks To 11 Do
    If (K >= 0) And (MemL[0:Blob + 40 + K * 4] <> 0) Then
    Begin
      ExFreeBlock(E, MemL[0:Blob + 40 + K * 4]);
      MemL[0:Blob + 40 + K * 4] := 0;
      Dec(I^.Blocks, E^.Bs Div 512);
      I^.Dirty := 1;
    End;
  ExTruncInd(I, Blob + 40 + 12 * 4, Nil, 1, 12, NewBlocks);
  ExTruncInd(I, Blob + 40 + 13 * 4, Nil, 2, 12 + P, NewBlocks);
  ExTruncInd(I, Blob + 40 + 14 * 4, Nil, 3, 12 + P + P * P, NewBlocks);
  If I^.Blocks < 0 Then I^.Blocks := 0;
End;

{ Troncature : I^.Size contient deja la nouvelle taille (VFS) }
Function ExTruncate(I : PInode; Size : LongInt) : LongInt;
Var E : PExSb; Phys, R, Off : LongInt; B : PBuf; IsNew : Boolean;
Begin
  E := ExOf(I^.Sb);
  ExTruncBlocks(I, (Size + E^.Bs - 1) Div E^.Bs);
  Off := Size Mod E^.Bs;
  If (Off <> 0) And (Size > 0) Then
  Begin
    R := ExBmap(I, Size Div E^.Bs, False, 0, Phys, IsNew);
    If (R = 0) And (Phys <> 0) Then
    Begin
      B := ExBRead(E, Phys);
      If B <> Nil Then
      Begin
        MemFill(B^.Data + Off, 0, E^.Bs - Off);
        BDirty(B);
        BRelease(B);
      End;
    End;
  End;
  I^.Mtime := NowSec; I^.Ctime := I^.Mtime;
  ExTruncate := ExWriteInode(I);
End;

{ Supprimer l'inode (nlink = 0, plus aucune reference) : libere les blocs,
  marque dtime, libere l'inode sur disque }
Procedure ExDeleteInode(I : PInode);
Var E : PExSb; Blob, Acl : LongInt; B : PBuf; T : LongInt;
Begin
  Blob := I^.Priv;
  If Blob = 0 Then Exit;
  E := ExOf(I^.Sb);
  T := I^.Mode And S_IFMT;
  If (T = S_IFREG) Or (T = S_IFDIR) Or ((T = S_IFLNK) And (I^.Blocks > 0)) Then
  Begin
    I^.Size := 0;
    ExTruncBlocks(I, 0);
  End;
  Acl := MemL[0:Blob + 104];
  If Acl <> 0 Then
  Begin
    B := ExBRead(E, Acl);
    If B <> Nil Then
    Begin
      If MemL[0:B^.Data + 4] <= 1 Then ExFreeBlock(E, Acl)
      Else
      Begin
        MemL[0:B^.Data + 4] := MemL[0:B^.Data + 4] - 1;
        BDirty(B);
      End;
      BRelease(B);
    End;
    MemL[0:Blob + 104] := 0;
  End;
  I^.Size := 0;
  I^.Blocks := 0;
  I^.Nlink := 0;
  MemL[0:Blob + 20] := NowSec;
  I^.Dirty := 0;
  ExWriteInode(I);
  ExFreeInode(E, I^.Ino, T = S_IFDIR);
  KFree(Blob);
  I^.Priv := 0;
End;

Procedure ExClearInode(I : PInode);
Begin
  If I^.Priv <> 0 Then KFree(I^.Priv);
  I^.Priv := 0;
End;

{ ---- Repertoires ---- }

Function ExNeedLen(NameLen : LongInt) : LongInt;
Begin
  ExNeedLen := (8 + NameLen + 3) And Not 3;
End;

{ Recopier le nom de l'entree d'adresse A dans la chaine Nm }
Procedure ExEntName(A : LongInt; Var Nm : String);
Var N : LongInt;
Begin
  N := Mem[0:A + 6];
  Mem[0:LongInt(@Nm)] := N;
  MemCopy(LongInt(@Nm) + 1, A + 8, N);
End;

{ Chercher Nm dans le repertoire Dir. Retourne 0 et Ino, ou -ENOENT.
  BlkIdx, EntOff : position de l'entree ; PrevOff : decalage de l'entree
  precedente dans le meme bloc (-1 si premiere) }
Function ExDirFind(Dir : PInode; Var Nm : String; Var Ino, BlkIdx, EntOff,
    PrevOff : LongInt) : LongInt;
Var E : PExSb; K, NB, Phys, R, Off, Rec, Prev, Len : LongInt; B : PBuf;
    IsNew : Boolean; A : LongInt;
Begin
  E := ExOf(Dir^.Sb);
  Len := Length(Nm);
  NB := (Dir^.Size + E^.Bs - 1) Div E^.Bs;
  For K := 0 To NB - 1 Do
  Begin
    R := ExBmap(Dir, K, False, 0, Phys, IsNew);
    If R <> 0 Then
    Begin
      ExDirFind := R;
      Exit;
    End;
    If Phys <> 0 Then
    Begin
      B := ExBRead(E, Phys);
      If B = Nil Then
      Begin
        ExDirFind := -EIO;
        Exit;
      End;
      Off := 0;
      Prev := -1;
      While Off < E^.Bs Do
      Begin
        A := B^.Data + Off;
        Rec := MemW[0:A + 4];
        If (Rec < 8) Or ((Rec And 3) <> 0) Or (Off + Rec > E^.Bs)
            Or (8 + Mem[0:A + 6] > Rec) Then
        Begin
          KLog('ext2 : repertoire corrompu (inode ' + IntStr(Dir^.Ino) + ')');
          BRelease(B);
          ExDirFind := -EIO;
          Exit;
        End;
        If (MemL[0:A] <> 0) And (Mem[0:A + 6] = Len) Then
          If MemCmp(A + 8, LongInt(@Nm) + 1, Len) = 0 Then
          Begin
            Ino := MemL[0:A];
            BlkIdx := K;
            EntOff := Off;
            PrevOff := Prev;
            BRelease(B);
            ExDirFind := 0;
            Exit;
          End;
        Prev := Off;
        Off := Off + Rec;
      End;
      BRelease(B);
    End;
  End;
  ExDirFind := -ENOENT;
End;

Function ExLookup(Dir : PInode; Var Nm : String; Var Res : PInode) : LongInt;
Var Ino, K, EO, PO, R : LongInt; I : PInode;
Begin
  If Length(Nm) > 255 Then
  Begin
    ExLookup := -ENAMETOOLONG;
    Exit;
  End;
  R := ExDirFind(Dir, Nm, Ino, K, EO, PO);
  If R <> 0 Then
  Begin
    ExLookup := R;
    Exit;
  End;
  I := IGet(Dir^.Sb, Ino);
  If I = Nil Then
  Begin
    ExLookup := -EIO;
    Exit;
  End;
  Res := I;
  ExLookup := 0;
End;

{ Type de fichier (octet file_type) d'un mode }
Function ExFileType(Mode : LongInt) : LongInt;
Begin
  Case Mode And S_IFMT Of
    S_IFREG : ExFileType := 1;
    S_IFDIR : ExFileType := 2;
    S_IFCHR : ExFileType := 3;
    S_IFBLK : ExFileType := 4;
    S_IFIFO : ExFileType := 5;
    S_IFSOCK : ExFileType := 6;
    S_IFLNK : ExFileType := 7;
  Else
    ExFileType := 0;
  End;
End;

{ Ajouter l'entree (Nm -> Ino) dans le repertoire Dir }
Function ExDirAdd(Dir : PInode; Var Nm : String; Ino, Mode : LongInt) : LongInt;
Var E : PExSb; K, NB, Phys, R, Off, Rec, Used, Need, Len, Goal : LongInt;
    B : PBuf; IsNew : Boolean; A, N : LongInt; Ft : LongInt;
Begin
  E := ExOf(Dir^.Sb);
  Len := Length(Nm);
  If Len = 0 Then
  Begin
    ExDirAdd := -EINVAL;
    Exit;
  End;
  If Len > 255 Then
  Begin
    ExDirAdd := -ENAMETOOLONG;
    Exit;
  End;
  Need := ExNeedLen(Len);
  Ft := 0;
  If (E^.Incompat And ExIncFiletype) <> 0 Then Ft := ExFileType(Mode);
  NB := (Dir^.Size + E^.Bs - 1) Div E^.Bs;
  For K := 0 To NB - 1 Do
  Begin
    R := ExBmap(Dir, K, False, 0, Phys, IsNew);
    If (R = 0) And (Phys <> 0) Then
    Begin
      B := ExBRead(E, Phys);
      If B = Nil Then
      Begin
        ExDirAdd := -EIO;
        Exit;
      End;
      Off := 0;
      While Off < E^.Bs Do
      Begin
        A := B^.Data + Off;
        Rec := MemW[0:A + 4];
        If (Rec < 8) Or ((Rec And 3) <> 0) Or (Off + Rec > E^.Bs) Then
        Begin
          KLog('ext2 : repertoire corrompu (inode ' + IntStr(Dir^.Ino) + ')');
          BRelease(B);
          ExDirAdd := -EIO;
          Exit;
        End;
        If MemL[0:A] <> 0 Then Used := ExNeedLen(Mem[0:A + 6]) Else Used := 0;
        If Rec - Used >= Need Then
        Begin
          If Used > 0 Then
          Begin
            MemW[0:A + 4] := Used;
            N := A + Used;
            MemW[0:N + 4] := Rec - Used;
          End
          Else N := A;
          MemL[0:N] := Ino;
          Mem[0:N + 6] := Len;
          Mem[0:N + 7] := Ft;
          MemCopy(N + 8, LongInt(@Nm) + 1, Len);
          BDirty(B);
          BRelease(B);
          Dir^.Mtime := NowSec; Dir^.Ctime := Dir^.Mtime;
          MemL[0:Dir^.Priv + 32] := MemL[0:Dir^.Priv + 32] And Not ExIndexFl;
          ExWriteInode(Dir);
          ExDirAdd := 0;
          Exit;
        End;
        Off := Off + Rec;
      End;
      BRelease(B);
    End;
  End;
  { pas de place : agrandir le repertoire d'un bloc }
  Goal := 0;
  If NB > 0 Then
  Begin
    ExBmap(Dir, NB - 1, False, 0, Phys, IsNew);
    If Phys <> 0 Then Goal := Phys + 1;
  End;
  R := ExBmap(Dir, NB, True, Goal, Phys, IsNew);
  If R <> 0 Then
  Begin
    ExDirAdd := R;
    Exit;
  End;
  B := BGetBlk(E^.Dev, Phys, E^.Bs);
  If B = Nil Then
  Begin
    ExDirAdd := -ENOMEM;
    Exit;
  End;
  MemFill(B^.Data, 0, E^.Bs);
  MemL[0:B^.Data] := Ino;
  MemW[0:B^.Data + 4] := E^.Bs;
  Mem[0:B^.Data + 6] := Len;
  Mem[0:B^.Data + 7] := Ft;
  MemCopy(B^.Data + 8, LongInt(@Nm) + 1, Len);
  BDirty(B);
  BRelease(B);
  Dir^.Size := Dir^.Size + E^.Bs;
  Dir^.Mtime := NowSec; Dir^.Ctime := Dir^.Mtime;
  MemL[0:Dir^.Priv + 32] := MemL[0:Dir^.Priv + 32] And Not ExIndexFl;
  ExWriteInode(Dir);
  ExDirAdd := 0;
End;

{ Supprimer l'entree Nm du repertoire Dir (fusion avec la precedente) }
Function ExDirDel(Dir : PInode; Var Nm : String; Var Ino : LongInt) : LongInt;
Var E : PExSb; K, EO, PO, R, Phys : LongInt; B : PBuf; IsNew : Boolean;
    A : LongInt;
Begin
  E := ExOf(Dir^.Sb);
  R := ExDirFind(Dir, Nm, Ino, K, EO, PO);
  If R <> 0 Then
  Begin
    ExDirDel := R;
    Exit;
  End;
  R := ExBmap(Dir, K, False, 0, Phys, IsNew);
  If (R <> 0) Or (Phys = 0) Then
  Begin
    ExDirDel := -EIO;
    Exit;
  End;
  B := ExBRead(E, Phys);
  If B = Nil Then
  Begin
    ExDirDel := -EIO;
    Exit;
  End;
  A := B^.Data + EO;
  If PO >= 0 Then
    MemW[0:B^.Data + PO + 4] := MemW[0:B^.Data + PO + 4] + MemW[0:A + 4]
  Else MemL[0:A] := 0;
  BDirty(B);
  BRelease(B);
  Dir^.Mtime := NowSec; Dir^.Ctime := Dir^.Mtime;
  MemL[0:Dir^.Priv + 32] := MemL[0:Dir^.Priv + 32] And Not ExIndexFl;
  ExWriteInode(Dir);
  ExDirDel := 0;
End;

{ Le repertoire I est-il vide (hors . et ..) ? 0 vide, -ENOTEMPTY, ou -EIO }
Function ExDirEmpty(I : PInode) : LongInt;
Var E : PExSb; K, NB, Phys, R, Off, Rec, N : LongInt; B : PBuf;
    IsNew : Boolean; A : LongInt;
Begin
  E := ExOf(I^.Sb);
  NB := (I^.Size + E^.Bs - 1) Div E^.Bs;
  For K := 0 To NB - 1 Do
  Begin
    R := ExBmap(I, K, False, 0, Phys, IsNew);
    If R <> 0 Then
    Begin
      ExDirEmpty := R;
      Exit;
    End;
    If Phys <> 0 Then
    Begin
      B := ExBRead(E, Phys);
      If B = Nil Then
      Begin
        ExDirEmpty := -EIO;
        Exit;
      End;
      Off := 0;
      While Off < E^.Bs Do
      Begin
        A := B^.Data + Off;
        Rec := MemW[0:A + 4];
        If (Rec < 8) Or ((Rec And 3) <> 0) Or (Off + Rec > E^.Bs) Then
        Begin
          BRelease(B);
          ExDirEmpty := -EIO;
          Exit;
        End;
        If MemL[0:A] <> 0 Then
        Begin
          N := Mem[0:A + 6];
          If Not (((N = 1) And (Mem[0:A + 8] = 46)) Or
             ((N = 2) And (Mem[0:A + 8] = 46) And (Mem[0:A + 9] = 46))) Then
          Begin
            BRelease(B);
            ExDirEmpty := -ENOTEMPTY;
            Exit;
          End;
        End;
        Off := Off + Rec;
      End;
      BRelease(B);
    End;
  End;
  ExDirEmpty := 0;
End;

{ Repertoire : une entree par appel, F^.Pos = decalage en octets }
Function ExReaddir(F : PFile; Var Ino : LongInt; Var Nm : String;
    Var DType : LongInt) : LongInt;
Var D, T : PInode; E : PExSb; Pos, K, Off, Phys, R, P, Rec : LongInt;
    B : PBuf; IsNew : Boolean; A : LongInt;
Begin
  D := F^.Inode;
  E := ExOf(D^.Sb);
  ExReaddir := 0;
  While True Do
  Begin
    Pos := F^.Pos;
    If (Pos < 0) Or (Pos >= D^.Size) Then Exit;
    K := Pos Div E^.Bs;
    Off := Pos Mod E^.Bs;
    R := ExBmap(D, K, False, 0, Phys, IsNew);
    If R <> 0 Then
    Begin
      ExReaddir := R;
      Exit;
    End;
    If Phys = 0 Then F^.Pos := (K + 1) * E^.Bs
    Else
    Begin
      B := ExBRead(E, Phys);
      If B = Nil Then
      Begin
        ExReaddir := -EIO;
        Exit;
      End;
      { retrouver une frontiere d'entree >= Off }
      P := 0;
      While P < Off Do
      Begin
        Rec := MemW[0:B^.Data + P + 4];
        If (Rec < 8) Or ((Rec And 3) <> 0) Or (P + Rec > E^.Bs) Then
        Begin
          BRelease(B);
          ExReaddir := -EIO;
          Exit;
        End;
        P := P + Rec;
      End;
      While P < E^.Bs Do
      Begin
        A := B^.Data + P;
        Rec := MemW[0:A + 4];
        If (Rec < 8) Or ((Rec And 3) <> 0) Or (P + Rec > E^.Bs) Then
        Begin
          BRelease(B);
          ExReaddir := -EIO;
          Exit;
        End;
        If MemL[0:A] <> 0 Then
        Begin
          Ino := MemL[0:A];
          ExEntName(A, Nm);
          If (E^.Incompat And ExIncFiletype) <> 0 Then
          Begin
            Case Mem[0:A + 7] Of
              1 : DType := DT_REG;
              2 : DType := DT_DIR;
              3 : DType := DT_CHR;
              4 : DType := DT_BLK;
              5 : DType := DT_FIFO;
              7 : DType := DT_LNK;
              6 : DType := 12;
            Else
              DType := DT_UNKNOWN;
            End;
          End
          Else DType := DT_UNKNOWN;
          F^.Pos := K * E^.Bs + P + Rec;
          BRelease(B);
          If DType = DT_UNKNOWN Then
          Begin
            T := IGet(D^.Sb, Ino);
            If T <> Nil Then
            Begin
              Case T^.Mode And S_IFMT Of
                S_IFREG : DType := DT_REG;
                S_IFDIR : DType := DT_DIR;
                S_IFCHR : DType := DT_CHR;
                S_IFBLK : DType := DT_BLK;
                S_IFIFO : DType := DT_FIFO;
                S_IFLNK : DType := DT_LNK;
              End;
              InodePut(LongInt(T));
            End;
          End;
          ExReaddir := 1;
          Exit;
        End;
        P := P + Rec;
      End;
      BRelease(B);
      F^.Pos := (K + 1) * E^.Bs;
    End;
  End;
End;

{ ---- Creation et suppression de noeuds ---- }

{ Creer un nouvel inode de mode Mode dans le repertoire Dir (pas encore
  lie par un nom). Retourne l'inode (compteur 1) ou Nil et l'erreur }
Function ExNewNode(Dir : PInode; Mode, Rdev : LongInt;
    Var Err : LongInt) : PInode;
Var E : PExSb; Ino, R, Slot, Off, K : LongInt; I : PInode; Blob : LongInt;
    B : PBuf; IsD : Boolean;
Begin
  E := ExOf(Dir^.Sb);
  ExNewNode := Nil;
  IsD := (Mode And S_IFMT) = S_IFDIR;
  R := ExAllocInode(E, Dir^.Ino, IsD, Ino);
  If R <> 0 Then
  Begin
    Err := R;
    Exit;
  End;
  Blob := KMallocZ(128);
  If Blob = 0 Then
  Begin
    ExFreeInode(E, Ino, IsD);
    Err := -ENOMEM;
    Exit;
  End;
  Dir^.Sb^.NextIno := Ino;
  I := NewInode(Dir^.Sb, Mode);
  If I = Nil Then
  Begin
    KFree(Blob);
    ExFreeInode(E, Ino, IsD);
    Err := -ENOMEM;
    Exit;
  End;
  I^.Priv := Blob;
  I^.Rdev := Rdev;
  I^.Size := 0;
  I^.Blocks := 0;
  If IsD Then I^.Nlink := 2 Else I^.Nlink := 1;
  If (Dir^.Mode And S_ISGID) <> 0 Then
  Begin
    I^.Gid := Dir^.Gid;
    If IsD Then I^.Mode := I^.Mode Or S_ISGID;
  End;
  MemL[0:Blob + 100] := RandNext;
  If (IsD = False) And (((Mode And S_IFMT) = S_IFCHR)
      Or ((Mode And S_IFMT) = S_IFBLK)) Then
  Begin
    If ((Rdev Shr 8) < 256) And ((Rdev And $FF) < 256) Then
      MemL[0:Blob + 40] := Rdev And $FFFF
    Else MemL[0:Blob + 44] := (Rdev And $FF) Or ((Rdev Shr 8) Shl 8);
  End;
  ExSetOps(I);
  { effacer tout l'emplacement de l'inode (inodes de plus de 128 octets) }
  B := ExInodeBuf(E, Ino, Off);
  If B <> Nil Then
  Begin
    MemFill(B^.Data + Off, 0, E^.InodeSize);
    BDirty(B);
    BRelease(B);
  End;
  Slot := 0;
  K := 0;
  ExWriteInode(I);
  Err := 0;
  ExNewNode := I;
End;

{ Defaire la creation d'un inode qui n'a pas pu etre lie }
Procedure ExAbortNode(I : PInode);
Begin
  I^.Nlink := 0;
  InodePut(LongInt(I));
End;

Function ExCreate(Dir : PInode; Var Nm : String; Mode : LongInt;
    Var Res : PInode) : LongInt;
Var I : PInode; R, Err : LongInt; Ino, K, EO, PO : LongInt;
Begin
  If ExDirFind(Dir, Nm, Ino, K, EO, PO) = 0 Then
  Begin
    ExCreate := -EEXIST;
    Exit;
  End;
  I := ExNewNode(Dir, Mode, 0, Err);
  If I = Nil Then
  Begin
    ExCreate := Err;
    Exit;
  End;
  R := ExDirAdd(Dir, Nm, I^.Ino, I^.Mode);
  If R <> 0 Then
  Begin
    ExAbortNode(I);
    ExCreate := R;
    Exit;
  End;
  Res := I;
  ExCreate := 0;
End;

Function ExMknod(Dir : PInode; Var Nm : String; Mode, Rdev : LongInt) : LongInt;
Var I : PInode; R, Err : LongInt; Ino, K, EO, PO : LongInt;
Begin
  If ExDirFind(Dir, Nm, Ino, K, EO, PO) = 0 Then
  Begin
    ExMknod := -EEXIST;
    Exit;
  End;
  I := ExNewNode(Dir, Mode, Rdev, Err);
  If I = Nil Then
  Begin
    ExMknod := Err;
    Exit;
  End;
  R := ExDirAdd(Dir, Nm, I^.Ino, I^.Mode);
  If R <> 0 Then ExAbortNode(I)
  Else InodePut(LongInt(I));
  ExMknod := R;
End;

Function ExMkdir(Dir : PInode; Var Nm : String; Mode : LongInt) : LongInt;
Var E : PExSb; I : PInode; R, Err, Phys, Ft : LongInt; B : PBuf;
    IsNew : Boolean; Ino, K, EO, PO : LongInt; Dot : String;
Begin
  E := ExOf(Dir^.Sb);
  If ExDirFind(Dir, Nm, Ino, K, EO, PO) = 0 Then
  Begin
    ExMkdir := -EEXIST;
    Exit;
  End;
  If Dir^.Nlink >= ExMaxLinks Then
  Begin
    ExMkdir := -EMLINK;
    Exit;
  End;
  I := ExNewNode(Dir, Mode, 0, Err);
  If I = Nil Then
  Begin
    ExMkdir := Err;
    Exit;
  End;
  R := ExBmap(I, 0, True, 0, Phys, IsNew);
  If R <> 0 Then
  Begin
    ExAbortNode(I);
    ExMkdir := R;
    Exit;
  End;
  B := BGetBlk(E^.Dev, Phys, E^.Bs);
  If B = Nil Then
  Begin
    ExAbortNode(I);
    ExMkdir := -ENOMEM;
    Exit;
  End;
  Ft := 0;
  If (E^.Incompat And ExIncFiletype) <> 0 Then Ft := 2;
  MemFill(B^.Data, 0, E^.Bs);
  MemL[0:B^.Data] := I^.Ino;
  MemW[0:B^.Data + 4] := 12;
  Mem[0:B^.Data + 6] := 1;
  Mem[0:B^.Data + 7] := Ft;
  Mem[0:B^.Data + 8] := 46;
  MemL[0:B^.Data + 12] := Dir^.Ino;
  MemW[0:B^.Data + 16] := E^.Bs - 12;
  Mem[0:B^.Data + 18] := 2;
  Mem[0:B^.Data + 19] := Ft;
  Mem[0:B^.Data + 20] := 46;
  Mem[0:B^.Data + 21] := 46;
  BDirty(B);
  BRelease(B);
  I^.Size := E^.Bs;
  ExWriteInode(I);
  R := ExDirAdd(Dir, Nm, I^.Ino, I^.Mode);
  If R <> 0 Then
  Begin
    ExAbortNode(I);
    ExMkdir := R;
    Exit;
  End;
  Inc(Dir^.Nlink);
  ExWriteInode(Dir);
  InodePut(LongInt(I));
  Dot := '';
  ExMkdir := 0;
End;

Function ExUnlink(Dir : PInode; Var Nm : String; I : PInode) : LongInt;
Var R, Ino : LongInt;
Begin
  R := ExDirDel(Dir, Nm, Ino);
  If R <> 0 Then
  Begin
    ExUnlink := R;
    Exit;
  End;
  If I^.Nlink > 0 Then Dec(I^.Nlink);
  I^.Ctime := NowSec;
  ExWriteInode(I);
  ExUnlink := 0;
End;

Function ExRmdir(Dir : PInode; Var Nm : String; I : PInode) : LongInt;
Var R, Ino : LongInt;
Begin
  R := ExDirEmpty(I);
  If R <> 0 Then
  Begin
    ExRmdir := R;
    Exit;
  End;
  R := ExDirDel(Dir, Nm, Ino);
  If R <> 0 Then
  Begin
    ExRmdir := R;
    Exit;
  End;
  I^.Nlink := 0;
  I^.Ctime := NowSec;
  If Dir^.Nlink > 0 Then Dec(Dir^.Nlink);
  ExWriteInode(I);
  ExWriteInode(Dir);
  ExRmdir := 0;
End;

Function ExLink(Old, Dir : PInode; Var Nm : String) : LongInt;
Var R, Ino, K, EO, PO : LongInt;
Begin
  If Old^.Nlink >= ExMaxLinks Then
  Begin
    ExLink := -EMLINK;
    Exit;
  End;
  If ExDirFind(Dir, Nm, Ino, K, EO, PO) = 0 Then
  Begin
    ExLink := -EEXIST;
    Exit;
  End;
  R := ExDirAdd(Dir, Nm, Old^.Ino, Old^.Mode);
  If R <> 0 Then
  Begin
    ExLink := R;
    Exit;
  End;
  Inc(Old^.Nlink);
  Old^.Ctime := NowSec;
  ExWriteInode(Old);
  ExLink := 0;
End;

Function ExSymlink(Dir : PInode; Var Nm : String; Var Tgt : String) : LongInt;
Var E : PExSb; I : PInode; R, Err, Phys, L : LongInt; B : PBuf;
    IsNew : Boolean; Ino, K, EO, PO : LongInt;
Begin
  E := ExOf(Dir^.Sb);
  L := Length(Tgt);
  If L = 0 Then
  Begin
    ExSymlink := -ENOENT;
    Exit;
  End;
  If ExDirFind(Dir, Nm, Ino, K, EO, PO) = 0 Then
  Begin
    ExSymlink := -EEXIST;
    Exit;
  End;
  I := ExNewNode(Dir, S_IFLNK Or $1FF, 0, Err);
  If I = Nil Then
  Begin
    ExSymlink := Err;
    Exit;
  End;
  If L < 60 Then
  Begin
    MemCopy(I^.Priv + 40, LongInt(@Tgt) + 1, L);     { lien rapide }
  End
  Else
  Begin
    R := ExBmap(I, 0, True, 0, Phys, IsNew);
    If R <> 0 Then
    Begin
      ExAbortNode(I);
      ExSymlink := R;
      Exit;
    End;
    B := BGetBlk(E^.Dev, Phys, E^.Bs);
    If B = Nil Then
    Begin
      ExAbortNode(I);
      ExSymlink := -ENOMEM;
      Exit;
    End;
    MemFill(B^.Data, 0, E^.Bs);
    MemCopy(B^.Data, LongInt(@Tgt) + 1, L);
    BDirty(B);
    BRelease(B);
  End;
  I^.Size := L;
  ExWriteInode(I);
  R := ExDirAdd(Dir, Nm, I^.Ino, I^.Mode);
  If R <> 0 Then ExAbortNode(I)
  Else InodePut(LongInt(I));
  ExSymlink := R;
End;

Function ExReadlink(I : PInode; Buf, Size : LongInt) : LongInt;
Var E : PExSb; N, R, Phys : LongInt; B : PBuf; IsNew : Boolean;
Begin
  E := ExOf(I^.Sb);
  N := I^.Size;
  If N > Size Then N := Size;
  If N > 255 Then N := 255;
  If I^.Blocks = 0 Then
  Begin
    MemCopy(Buf, I^.Priv + 40, N);
    ExReadlink := N;
    Exit;
  End;
  R := ExBmap(I, 0, False, 0, Phys, IsNew);
  If (R <> 0) Or (Phys = 0) Then
  Begin
    ExReadlink := -EIO;
    Exit;
  End;
  B := ExBRead(E, Phys);
  If B = Nil Then
  Begin
    ExReadlink := -EIO;
    Exit;
  End;
  MemCopy(Buf, B^.Data, N);
  BRelease(B);
  ExReadlink := N;
End;

{ Renommer (OD, ON) en (ND, NN). Le dentry source est deplace par le VFS }
Function ExRename(OD : PInode; Var ON : String; ND : PInode; Var NN : String;
    Dummy : LongInt) : LongInt;
Var E : PExSb; Ino, K, EO, PO, R, VIno, Phys : LongInt; I, V : PInode;
    B : PBuf; IsNew : Boolean; A : LongInt; IsD : Boolean; Ft : LongInt;
Begin
  E := ExOf(OD^.Sb);
  R := ExDirFind(OD, ON, Ino, K, EO, PO);
  If R <> 0 Then
  Begin
    ExRename := R;
    Exit;
  End;
  I := IGet(OD^.Sb, Ino);
  If I = Nil Then
  Begin
    ExRename := -EIO;
    Exit;
  End;
  IsD := IsDir(I);
  V := Nil;
  If ExDirFind(ND, NN, VIno, K, EO, PO) = 0 Then
  Begin
    V := IGet(OD^.Sb, VIno);
    If V = Nil Then
    Begin
      InodePut(LongInt(I));
      ExRename := -EIO;
      Exit;
    End;
    If V = I Then
    Begin
      { deux noms du meme fichier : rien a faire }
      InodePut(LongInt(V)); InodePut(LongInt(I));
      ExRename := 0;
      Exit;
    End;
    If IsDir(V) Then
    Begin
      R := ExDirEmpty(V);
      If R <> 0 Then
      Begin
        InodePut(LongInt(V)); InodePut(LongInt(I));
        ExRename := R;
        Exit;
      End;
    End;
  End
  Else If IsD And (OD <> ND) And (ND^.Nlink >= ExMaxLinks) Then
  Begin
    InodePut(LongInt(I));
    ExRename := -EMLINK;
    Exit;
  End;
  Ft := 0;
  If (E^.Incompat And ExIncFiletype) <> 0 Then Ft := ExFileType(I^.Mode);
  If V <> Nil Then
  Begin
    { remplacer l'entree cible : pointer vers I }
    R := ExDirFind(ND, NN, VIno, K, EO, PO);
    If R = 0 Then R := ExBmap(ND, K, False, 0, Phys, IsNew);
    If (R <> 0) Or (Phys = 0) Then
    Begin
      InodePut(LongInt(V)); InodePut(LongInt(I));
      ExRename := -EIO;
      Exit;
    End;
    B := ExBRead(E, Phys);
    If B = Nil Then
    Begin
      InodePut(LongInt(V)); InodePut(LongInt(I));
      ExRename := -EIO;
      Exit;
    End;
    A := B^.Data + EO;
    MemL[0:A] := I^.Ino;
    Mem[0:A + 7] := Ft;
    BDirty(B);
    BRelease(B);
    ND^.Mtime := NowSec; ND^.Ctime := ND^.Mtime;
    ExWriteInode(ND);
    If IsDir(V) Then
    Begin
      V^.Nlink := 0;
      If ND^.Nlink > 0 Then Dec(ND^.Nlink);
    End
    Else If V^.Nlink > 0 Then Dec(V^.Nlink);
    V^.Ctime := NowSec;
    ExWriteInode(V);
    InodePut(LongInt(V));
  End
  Else
  Begin
    R := ExDirAdd(ND, NN, I^.Ino, I^.Mode);
    If R <> 0 Then
    Begin
      InodePut(LongInt(I));
      ExRename := R;
      Exit;
    End;
  End;
  { retirer l'ancienne entree }
  R := ExDirDel(OD, ON, Ino);
  If R <> 0 Then KLog('ext2 : rename : ancienne entree introuvable');
  If IsD And (OD <> ND) Then
  Begin
    { ".." du repertoire deplace }
    R := ExBmap(I, 0, False, 0, Phys, IsNew);
    If (R = 0) And (Phys <> 0) Then
    Begin
      B := ExBRead(E, Phys);
      If B <> Nil Then
      Begin
        A := B^.Data + MemW[0:B^.Data + 4];
        MemL[0:A] := ND^.Ino;
        BDirty(B);
        BRelease(B);
      End;
    End;
    If OD^.Nlink > 0 Then Dec(OD^.Nlink);
    Inc(ND^.Nlink);
    ExWriteInode(OD);
    ExWriteInode(ND);
  End
  Else If IsD And (V <> Nil) Then
  Begin
    ExWriteInode(ND);
  End;
  I^.Ctime := NowSec;
  ExWriteInode(I);
  InodePut(LongInt(I));
  ExRename := 0;
End;

{ ---- Fichiers ordinaires ---- }

Function ExRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var I : PInode; E : PExSb; N, Done, Idx, Off, Chunk, Phys, R : LongInt;
    B : PBuf; IsNew : Boolean;
Begin
  I := F^.Inode;
  E := ExOf(I^.Sb);
  If F^.Pos >= I^.Size Then
  Begin
    ExRead := 0;
    Exit;
  End;
  N := I^.Size - F^.Pos;
  If N > Cnt Then N := Cnt;
  Done := 0;
  While Done < N Do
  Begin
    Idx := F^.Pos Div E^.Bs;
    Off := F^.Pos Mod E^.Bs;
    Chunk := E^.Bs - Off;
    If Chunk > N - Done Then Chunk := N - Done;
    R := ExBmap(I, Idx, False, 0, Phys, IsNew);
    If R <> 0 Then
    Begin
      If Done = 0 Then ExRead := R Else ExRead := Done;
      Exit;
    End;
    If Phys = 0 Then MemFill(Buf + Done, 0, Chunk)
    Else
    Begin
      B := ExBRead(E, Phys);
      If B = Nil Then
      Begin
        If Done = 0 Then ExRead := -EIO Else ExRead := Done;
        Exit;
      End;
      MemCopy(Buf + Done, B^.Data + Off, Chunk);
      BRelease(B);
    End;
    Done := Done + Chunk;
    F^.Pos := F^.Pos + Chunk;
  End;
  I^.Atime := NowSec;
  ExRead := Done;
End;

Function ExWrite(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var I : PInode; E : PExSb; Done, Idx, Off, Chunk, Phys, R, Goal, Prev : LongInt;
    B : PBuf; IsNew : Boolean; Res : LongInt;
Begin
  I := F^.Inode;
  E := ExOf(I^.Sb);
  If (F^.Pos < 0) Or (F^.Pos >= ExMaxFileSize) Then
  Begin
    ExWrite := -EFBIG;
    Exit;
  End;
  If Cnt > ExMaxFileSize - F^.Pos Then Cnt := ExMaxFileSize - F^.Pos;
  If MemL[0:I^.Priv + 108] <> 0 Then
  Begin
    ExWrite := -EFBIG;
    Exit;
  End;
  Done := 0;
  Res := 0;
  While Done < Cnt Do
  Begin
    Idx := F^.Pos Div E^.Bs;
    Off := F^.Pos Mod E^.Bs;
    Chunk := E^.Bs - Off;
    If Chunk > Cnt - Done Then Chunk := Cnt - Done;
    Goal := 0;
    If Idx > 0 Then
    Begin
      ExBmap(I, Idx - 1, False, 0, Prev, IsNew);
      If Prev <> 0 Then Goal := Prev + 1;
    End;
    R := ExBmap(I, Idx, True, Goal, Phys, IsNew);
    If R <> 0 Then
    Begin
      Res := R;
      Break;
    End;
    If IsNew Then
    Begin
      B := BGetBlk(E^.Dev, Phys, E^.Bs);
      If B <> Nil Then MemFill(B^.Data, 0, E^.Bs);
    End
    Else If Chunk = E^.Bs Then B := BGetBlk(E^.Dev, Phys, E^.Bs)
    Else B := ExBRead(E, Phys);
    If B = Nil Then
    Begin
      Res := -EIO;
      Break;
    End;
    MemCopy(B^.Data + Off, Buf + Done, Chunk);
    BDirty(B);
    BRelease(B);
    Done := Done + Chunk;
    F^.Pos := F^.Pos + Chunk;
    If F^.Pos > I^.Size Then I^.Size := F^.Pos;
  End;
  If Done > 0 Then
  Begin
    I^.Mtime := NowSec; I^.Ctime := I^.Mtime;
    If (I^.Mode And (S_ISUID Or S_ISGID)) <> 0 Then
      If Cur^.Fsuid <> 0 Then I^.Mode := I^.Mode And Not (S_ISUID Or S_ISGID);
  End;
  If (Done > 0) Or (I^.Dirty <> 0) Then ExWriteInode(I);
  If Done > 0 Then ExWrite := Done Else ExWrite := Res;
End;

Function ExFsync(F : PFile) : LongInt;
Begin
  ExWriteInode(F^.Inode);
  BSync(F^.Inode^.Sb^.Dev);
  ExFsync := 0;
End;

Function ExSetattr(I : PInode) : LongInt;
Begin
  ExSetattr := ExWriteInode(I);
End;

{ ---- Montage ---- }

{ Numero de peripherique bloc d'un chemin ou d'un nom (/dev/hda1, hdb2,
  ram0) : 0 si inconnu }
Function ExResolveDev(Const Name : String) : LongInt;
Var D : PDentry; R, Dv, Mn, Part : LongInt; S : String; C : LongInt;
Begin
  ExResolveDev := 0;
  R := PathWalk(Name, True, D);
  If R = 0 Then
  Begin
    If (D^.Inode^.Mode And S_IFMT) = S_IFBLK Then Dv := D^.Inode^.Rdev
    Else Dv := 0;
    DentryPut(LongInt(D));
    ExResolveDev := Dv;
    Exit;
  End;
  S := Name;
  If Copy(S, 1, 5) = '/dev/' Then Delete(S, 1, 5);
  If S = 'ram0' Then
  Begin
    ExResolveDev := (MajRam Shl 8);
    Exit;
  End;
  If (Length(S) >= 3) And (Copy(S, 1, 2) = 'hd') Then
  Begin
    C := Ord(S[3]) - 97;
    If (C < 0) Or (C > 3) Then Exit;
    Part := 0;
    If Length(S) > 3 Then Part := StrVal(Copy(S, 4, 3));
    If (Part < 0) Or (Part > 15) Then Exit;
    If C < 2 Then Mn := C * 64 + Part Else Mn := (C - 2) * 64 + Part;
    If C < 2 Then ExResolveDev := (MajIde0 Shl 8) Or Mn
    Else ExResolveDev := (MajIde1 Shl 8) Or Mn;
  End;
End;

{ Le groupe G contient-il une copie du superbloc et des descripteurs ? }
Function ExHasSuper(E : PExSb; G : LongInt) : Boolean;
Var Pw : LongInt;
Begin
  ExHasSuper := True;
  If (E^.RoCompat And ExRoSparse) = 0 Then Exit;
  If G <= 1 Then Exit;
  If (G And 1) = 0 Then
  Begin
    ExHasSuper := False;
    Exit;
  End;
  Pw := 3;
  While Pw < G Do Pw := Pw * 3;
  If Pw = G Then Exit;
  Pw := 5;
  While Pw < G Do Pw := Pw * 5;
  If Pw = G Then Exit;
  Pw := 7;
  While Pw < G Do Pw := Pw * 7;
  If Pw = G Then Exit;
  ExHasSuper := False;
End;

Procedure ExFreeMount(E : PExSb);
Var K : LongInt; B : PBuf;
Begin
  If E^.GdBufs <> 0 Then
  Begin
    For K := 0 To E^.GdtBlocks - 1 Do
    Begin
      B := Pointer(MemL[0:E^.GdBufs + K * 4]);
      If B <> Nil Then BRelease(B);
    End;
    KFree(E^.GdBufs);
  End;
  If E^.SbBuf <> Nil Then BRelease(E^.SbBuf);
  KFree(LongInt(E));
End;

{ Marquer le systeme propre ou sale (s_state) et ecrire le superbloc }
Procedure ExSetState(E : PExSb; State : LongInt);
Var A : LongInt;
Begin
  A := ExSbA(E);
  MemW[0:A + 58] := State;
  MemL[0:A + 48] := NowSec;
  ExSbDirty(E);
End;

Function Ext2Mount(Sb : PSuper; Var DevName : String; Flags,
    Data : LongInt) : LongInt;
Var Dev, R, K, Bs, A, SbBlk, G, Gd, Bad, I2 : LongInt; B : PBuf;
    E : PExSb; Ino : PInode; D : PDentry; Opt, Tok : String; ForceRo : Boolean;
    Pos, Rsv : LongInt;
Begin
  Ext2Mount := -EINVAL;
  Dev := ExResolveDev(DevName);
  If Dev = 0 Then
  Begin
    Ext2Mount := -ENOTBLK;
    Exit;
  End;
  If BlkSectors(Dev) = 0 Then
  Begin
    Ext2Mount := -ENXIO;
    Exit;
  End;
  For K := 0 To MaxSupers - 1 Do
    If (Supers[K] <> Nil) And (Supers[K] <> Sb) And (Supers[K]^.Dev = Dev) Then
    Begin
      Ext2Mount := -EBUSY;
      Exit;
    End;
  B := BRead(Dev, 1, 1024);
  If B = Nil Then
  Begin
    Ext2Mount := -EIO;
    Exit;
  End;
  A := B^.Data;
  If MemW[0:A + 56] <> ExMagic Then
  Begin
    BRelease(B);
    Ext2Mount := -EINVAL;
    Exit;
  End;
  If MemL[0:A + 24] > 2 Then
  Begin
    KLog('ext2 : taille de bloc non geree (' + IntStr(1024 Shl MemL[0:A + 24])
        + ')');
    BRelease(B);
    Exit;
  End;
  Bs := 1024 Shl MemL[0:A + 24];
  E := Pointer(KMallocZ(SizeOf(TExSb)));
  If E = Nil Then
  Begin
    BRelease(B);
    Ext2Mount := -ENOMEM;
    Exit;
  End;
  E^.Dev := Dev;
  E^.Bs := Bs;
  E^.Ppb := Bs Div 4;
  E^.InodesCount := MemL[0:A];
  E^.BlocksCount := MemL[0:A + 4];
  E^.FirstData := MemL[0:A + 20];
  E^.Bpg := MemL[0:A + 32];
  E^.Ipg := MemL[0:A + 40];
  E^.Rev := MemL[0:A + 76];
  E^.InodeSize := 128;
  E^.FirstIno := 11;
  E^.Compat := 0; E^.Incompat := 0; E^.RoCompat := 0;
  If E^.Rev >= 1 Then
  Begin
    E^.InodeSize := MemW[0:A + 88];
    E^.FirstIno := MemL[0:A + 84];
    E^.Compat := MemL[0:A + 92];
    E^.Incompat := MemL[0:A + 96];
    E^.RoCompat := MemL[0:A + 100];
  End;
  Rsv := 0;
  If E^.Rev >= 1 Then Rsv := MemW[0:A + 206];
  E^.MountState := MemW[0:A + 58];
  BRelease(B);
  BInvalidate(Dev);
  If (E^.Bpg <= 0) Or (E^.Ipg <= 0) Or (E^.Bpg > Bs * 8) Or (E^.Ipg > Bs * 8)
     Or (E^.InodeSize < 128) Or (E^.InodeSize > Bs)
     Or ((E^.InodeSize And (E^.InodeSize - 1)) <> 0)
     Or (E^.BlocksCount <= E^.FirstData) Or (E^.FirstIno < 11) Then
  Begin
    KLog('ext2 : superbloc invalide');
    KFree(LongInt(E));
    Exit;
  End;
  If E^.BlocksCount > BlkSectors(Dev) Div (Bs Div 512) Then
  Begin
    KLog('ext2 : le systeme de fichiers depasse le peripherique');
    KFree(LongInt(E));
    Exit;
  End;
  Bad := E^.Incompat And Not (ExIncFiletype Or ExIncRecover Or ExIncFlexBg);
  If Bad <> 0 Then
  Begin
    KLog('ext2 : fonctions incompatibles non gerees ('
        + HexStr(Bad, 4) + ', ext4 : extents, 64bit...)');
    KFree(LongInt(E));
    Exit;
  End;
  ForceRo := False;
  If (E^.Incompat And ExIncRecover) <> 0 Then
  Begin
    KLog('ext2 : journal a rejouer : lecture seule');
    ForceRo := True;
  End;
  If (E^.RoCompat And Not (ExRoSparse Or ExRoLargeFile Or ExRoBtree
      Or ExRoHugeFile Or ExRoDirNlink Or ExRoExtraIsize)) <> 0 Then
  Begin
    KLog('ext2 : fonctions en lecture seule non gerees (somme de controle)'
        + ' : lecture seule');
    ForceRo := True;
  End;
  E^.Groups := (E^.BlocksCount - E^.FirstData + E^.Bpg - 1) Div E^.Bpg;
  If E^.Groups * E^.Ipg <> E^.InodesCount Then
  Begin
    KLog('ext2 : nombre d''inodes incoherent');
    KFree(LongInt(E));
    Exit;
  End;
  E^.GdPerBlk := Bs Div 32;
  E^.GdtBlocks := (E^.Groups + E^.GdPerBlk - 1) Div E^.GdPerBlk;
  E^.Itb := (E^.Ipg * E^.InodeSize + Bs - 1) Div Bs;
  { superbloc epingle }
  SbBlk := 1024 Div Bs;
  E^.SbOff := 1024 Mod Bs;
  E^.SbBuf := BRead(Dev, SbBlk, Bs);
  If E^.SbBuf = Nil Then
  Begin
    KFree(LongInt(E));
    Ext2Mount := -EIO;
    Exit;
  End;
  E^.GdBufs := KMallocZ(E^.GdtBlocks * 4);
  If E^.GdBufs = 0 Then
  Begin
    ExFreeMount(E);
    Ext2Mount := -ENOMEM;
    Exit;
  End;
  For K := 0 To E^.GdtBlocks - 1 Do
  Begin
    B := BRead(Dev, E^.FirstData + 1 + K, Bs);
    If B = Nil Then
    Begin
      ExFreeMount(E);
      Ext2Mount := -EIO;
      Exit;
    End;
    MemL[0:E^.GdBufs + K * 4] := LongInt(B);
  End;
  { verification des descripteurs ; calcul des blocs de metadonnees }
  E^.Overhead := E^.FirstData + E^.Groups * (2 + E^.Itb);
  For G := 0 To E^.Groups - 1 Do
  Begin
    Gd := ExGd(E, G);
    If (MemL[0:Gd] < E^.FirstData) Or (MemL[0:Gd] >= E^.BlocksCount)
       Or (MemL[0:Gd + 4] < E^.FirstData) Or (MemL[0:Gd + 4] >= E^.BlocksCount)
       Or (MemL[0:Gd + 8] < E^.FirstData)
       Or (MemL[0:Gd + 8] + E^.Itb > E^.BlocksCount) Then
    Begin
      KLog('ext2 : descripteur du groupe ' + IntStr(G) + ' invalide');
      ExFreeMount(E);
      Exit;
    End;
    If ExHasSuper(E, G) Then E^.Overhead := E^.Overhead + 1 + E^.GdtBlocks
        + Rsv;
  End;
  Sb^.Priv := LongInt(E);
  Sb^.Dev := Dev;
  Sb^.BlockSize := Bs;
  Sb^.SOps := LongInt(@ExSOps[0]);
  { options ("ro", "rw") }
  If Data <> 0 Then
    If GetUserStr(Data, Opt) = 0 Then
    Begin
      Pos := 1;
      While Pos <= Length(Opt) Do
      Begin
        K := Pos;
        While (K <= Length(Opt)) And (Opt[K] <> ',') Do Inc(K);
        Tok := Copy(Opt, Pos, K - Pos);
        If Tok = 'ro' Then Flags := Flags Or MS_RDONLY
        Else If Tok = 'rw' Then Flags := Flags And Not MS_RDONLY;
        Pos := K + 1;
      End;
    End;
  If ForceRo Then Flags := Flags Or MS_RDONLY;
  Sb^.Flags := Flags;
  If ForceRo Then Sb^.Used := 1 Else Sb^.Used := 0;
  Ino := IGet(Sb, ExRootIno);
  If (Ino = Nil) Or (Not IsDir(Ino)) Then
  Begin
    KLog('ext2 : inode racine illisible');
    If Ino <> Nil Then InodePut(LongInt(Ino));
    InodePurgeSb(Sb);
    ExFreeMount(E);
    Sb^.Priv := 0;
    Exit;
  End;
  D := DentryNew(Nil, '', Ino, Sb);
  If D = Nil Then
  Begin
    InodePut(LongInt(Ino));
    InodePurgeSb(Sb);
    ExFreeMount(E);
    Sb^.Priv := 0;
    Ext2Mount := -ENOMEM;
    Exit;
  End;
  Sb^.Root := D;
  If (E^.MountState And ExStValid) = 0 Then
    KLog('ext2 : ' + DevName + ' n''a pas ete demonte proprement');
  If (Flags And MS_RDONLY) = 0 Then
  Begin
    I2 := ExSbA(E);
    MemW[0:I2 + 52] := MemW[0:I2 + 52] + 1;
    ExSetState(E, E^.MountState And Not ExStValid);
    MemL[0:I2 + 44] := NowSec;
    BSync(Dev);
  End;
  Ext2Mount := 0;
End;

{ Demontage : etat propre, ecriture, liberation des tampons epingles }
Procedure Ext2Umount(Sb : PSuper);
Var E : PExSb;
Begin
  E := ExOf(Sb);
  If E = Nil Then Exit;
  If (Sb^.Flags And MS_RDONLY) = 0 Then ExSetState(E, E^.MountState);
  BSync(E^.Dev);
  ExFreeMount(E);
  Sb^.Priv := 0;
End;

Procedure Ext2Sync(Sb : PSuper);
Var E : PExSb;
Begin
  E := ExOf(Sb);
  If E = Nil Then Exit;
  If (Sb^.Flags And MS_RDONLY) = 0 Then
  Begin
    MemL[0:ExSbA(E) + 48] := NowSec;
    ExSbDirty(E);
  End;
  BSync(E^.Dev);
End;

{ Remontage (MS_REMOUNT) : bascule lecture seule / lecture-ecriture }
Function Ext2Remount(Sb : PSuper; NewFlags : LongInt) : LongInt;
Var E : PExSb; WasRo, WantRo : Boolean;
Begin
  E := ExOf(Sb);
  WasRo := (Sb^.Flags And MS_RDONLY) <> 0;
  WantRo := (NewFlags And MS_RDONLY) <> 0;
  If WasRo And (Not WantRo) Then
  Begin
    If Sb^.Used <> 0 Then
    Begin
      Ext2Remount := -EROFS;
      Exit;
    End;
    ExSetState(E, E^.MountState And Not ExStValid);
    BSync(E^.Dev);
  End
  Else If (Not WasRo) And WantRo Then
  Begin
    ExSetState(E, E^.MountState);
    BSync(E^.Dev);
  End;
  Sb^.Flags := (Sb^.Flags And Not MS_RDONLY) Or (NewFlags And MS_RDONLY);
  Ext2Remount := 0;
End;

{ statfs : Buf = bsize, blocks, bfree, bavail, files, ffree, namelen, magic }
Procedure Ext2Statfs(Sb : PSuper; Buf : LongInt);
Var E : PExSb; A, Fb, Rb : LongInt;
Begin
  E := ExOf(Sb);
  A := ExSbA(E);
  Fb := MemL[0:A + 12];
  Rb := Fb - MemL[0:A + 8];
  If Rb < 0 Then Rb := 0;
  MemL[0:Buf] := E^.Bs;
  MemL[0:Buf + 4] := E^.BlocksCount - E^.Overhead;
  MemL[0:Buf + 8] := Fb;
  MemL[0:Buf + 12] := Rb;
  MemL[0:Buf + 16] := E^.InodesCount;
  MemL[0:Buf + 20] := MemL[0:A + 16];
  MemL[0:Buf + 24] := 255;
  MemL[0:Buf + 28] := ExMagic;
End;

Procedure InitExt2;
Begin
  MemFill(LongInt(@ExFileIOps[0]), 0, SizeOf(ExFileIOps));
  ExFileIOps[IoTruncate] := LongInt(@ExTruncate);
  ExFileIOps[IoSetattr] := LongInt(@ExSetattr);
  MemFill(LongInt(@ExDirIOps[0]), 0, SizeOf(ExDirIOps));
  ExDirIOps[IoLookup] := LongInt(@ExLookup);
  ExDirIOps[IoCreate] := LongInt(@ExCreate);
  ExDirIOps[IoMkdir] := LongInt(@ExMkdir);
  ExDirIOps[IoMknod] := LongInt(@ExMknod);
  ExDirIOps[IoUnlink] := LongInt(@ExUnlink);
  ExDirIOps[IoRmdir] := LongInt(@ExRmdir);
  ExDirIOps[IoRename] := LongInt(@ExRename);
  ExDirIOps[IoLink] := LongInt(@ExLink);
  ExDirIOps[IoSymlink] := LongInt(@ExSymlink);
  ExDirIOps[IoSetattr] := LongInt(@ExSetattr);
  MemFill(LongInt(@ExLnkIOps[0]), 0, SizeOf(ExLnkIOps));
  ExLnkIOps[IoReadlink] := LongInt(@ExReadlink);
  ExLnkIOps[IoSetattr] := LongInt(@ExSetattr);
  MemFill(LongInt(@ExSpecIOps[0]), 0, SizeOf(ExSpecIOps));
  ExSpecIOps[IoSetattr] := LongInt(@ExSetattr);
  MemFill(LongInt(@ExFileFOps[0]), 0, SizeOf(ExFileFOps));
  ExFileFOps[FoRead] := LongInt(@ExRead);
  ExFileFOps[FoWrite] := LongInt(@ExWrite);
  ExFileFOps[FoFsync] := LongInt(@ExFsync);
  MemFill(LongInt(@ExDirFOps[0]), 0, SizeOf(ExDirFOps));
  ExDirFOps[FoReaddir] := LongInt(@ExReaddir);
  ExDirFOps[FoFsync] := LongInt(@ExFsync);
  MemFill(LongInt(@ExSOps[0]), 0, SizeOf(ExSOps));
  ExSOps[SoReadInode] := LongInt(@ExReadInode);
  ExSOps[SoPutInode] := LongInt(@ExDeleteInode);
  ExSOps[SoWriteInode] := LongInt(@ExWriteInode);
  ExSOps[SoStatfs] := LongInt(@Ext2Statfs);
  ExSOps[SoSync] := LongInt(@Ext2Sync);
  ExSOps[SoUmount] := LongInt(@Ext2Umount);
  ExSOps[SoClearInode] := LongInt(@ExClearInode);
  ExSOps[SoRemount] := LongInt(@Ext2Remount);
  RegisterFs('ext2', LongInt(@Ext2Mount));
  RegisterFs('ext3', LongInt(@Ext2Mount));
End;

{ ==================================================================== }
{ Partie 14 - Terminaux : N_TTY, consoles virtuelles, clavier, ttyS0  }
{ ==================================================================== }

Const
  NTtys    = 5;                  { tty1..tty4 (consoles) et ttyS0 }
  TtyBuf   = 4096;
  { drapeaux termios }
  IGNCR = $80; ICRNL = $100; INLCR = $40; IXON = $400; IXANY = $800; ISTRIP
      = $20;
  OPOST = 1; ONLCR = 4; OCRNL = 8;
  ISIG = 1; ICANON = 2; ECHO = 8; ECHOE = $10; ECHOK = $20; ECHONL = $40;
  NOFLSH = $80; TOSTOP = $100; ECHOCTL = $200; ECHOKE = $800; IEXTEN = $8000;
  VINTR = 0; VQUIT = 1; VERASE = 2; VKILL = 3; VEOF = 4; VTIME = 5; VMIN = 6;
  VSTART = 8; VSTOP = 9; VSUSP = 10; VEOL = 11; VREPRINT = 12; VWERASE = 14;
  VLNEXT = 15; VEOL2 = 16;
  EofMark = $100;
      { marqueur de fin de fichier (^D) dans le tampon }

Type
  PTty = ^TTty;
  TTty = Record
    Index, Opens         : LongInt;
    Pgrp, Session        : LongInt;
    Iflag, Oflag, Cflag, Lflag, Line : LongInt;
    Cc                   : Array[0..31] Of Byte;
    Rows, Cols           : LongInt;
    Head, Tail, Lines    : LongInt;       { tampon circulaire d'entree }
    Stopped, Lnext       : LongInt;
    Wchan                : LongInt;
    Rbuf                 : Array[0..4095] Of Word;      { TtyBuf }
  End;

Var
  Ttys         : Array[0..NTtys - 1] Of TTty;
  TtyFOps      : Array[0..15] Of LongInt;
  CtlFOps      : Array[0..15] Of LongInt;
  { clavier }
  KbdShift, KbdCtrl, KbdAlt, KbdAltGr, KbdCaps, KbdNum, KbdE0 : Boolean;
  KbdMapLo, KbdMapHi, KbdMapAlt : Array[0..127] Of Byte;
  KbdAzerty    : Boolean;
  CtrlAltDel   : Boolean;

Procedure SendSigPgrp2(Pgrp, Sig : LongInt);
Begin
  SendSigPgrp(Pgrp, Sig);
End;

Procedure TtyReset(T : PTty; Idx : LongInt);
Var I : LongInt;
Begin
  MemFill(LongInt(T), 0, SizeOf(TTty));
  T^.Index := Idx;
  T^.Iflag := ICRNL Or IXON;
  T^.Oflag := OPOST Or ONLCR;
  T^.Cflag := $4BF;
  T^.Lflag := ISIG Or ICANON Or ECHO Or ECHOE Or ECHOK Or ECHOCTL Or ECHOKE
      Or IEXTEN;
  T^.Cc[VINTR] := 3; T^.Cc[VQUIT] := 28; T^.Cc[VERASE] := 127;
      T^.Cc[VKILL] := 21;
  T^.Cc[VEOF] := 4; T^.Cc[VTIME] := 0; T^.Cc[VMIN] := 1; T^.Cc[VSTART] := 17;
  T^.Cc[VSTOP] := 19; T^.Cc[VSUSP] := 26; T^.Cc[VEOL] := 0;
      T^.Cc[VREPRINT] := 18;
  T^.Cc[VWERASE] := 23; T^.Cc[VLNEXT] := 22; T^.Cc[VEOL2] := 0;
  T^.Rows := 25; T^.Cols := 80;
  T^.Wchan := LongInt(T);
  I := 0;
End;

{ ---- Sortie ---- }

Procedure TtyPutRaw(T : PTty; C : LongInt);
Begin
  If T^.Index < NVc Then VcPutc(T^.Index, C)
  Else
  Begin
    If C = 10 Then SerialPut(13);
    SerialPut(C);
  End;
End;

{ Caractere de sortie avec traitement OPOST }
Procedure TtyOut(T : PTty; C : LongInt);
Begin
  If (T^.Oflag And OPOST) <> 0 Then
  Begin
    If (C = 10) And ((T^.Oflag And ONLCR) <> 0) Then
    Begin
      If T^.Index < NVc Then VcPutc(T^.Index, 13) Else SerialPut(13);
    End
    Else If (C = 13) And ((T^.Oflag And OCRNL) <> 0) Then C := 10;
  End;
  If T^.Index < NVc Then VcPutc(T^.Index, C)
  Else SerialPut(C);
End;

Procedure TtyEchoChar(T : PTty; C : LongInt);
Begin
  If (C < 32) And (C <> 9) And (C <> 10) And ((T^.Lflag And ECHOCTL) <> 0) Then
  Begin
    TtyOut(T, 94);
    TtyOut(T, C + 64);
  End
  Else If (C = 127) And ((T^.Lflag And ECHOCTL) <> 0) Then
  Begin
    TtyOut(T, 94);
    TtyOut(T, 63);
  End
  Else TtyOut(T, C);
End;

{ ---- Entree : discipline de ligne ---- }

Function TtyCount(T : PTty) : LongInt;
Begin
  TtyCount := (T^.Head - T^.Tail + TtyBuf) Mod TtyBuf;
End;

Procedure TtyPush(T : PTty; V : LongInt);
Begin
  If TtyCount(T) >= TtyBuf - 1 Then Exit;
  T^.Rbuf[T^.Head] := V;
  T^.Head := (T^.Head + 1) Mod TtyBuf;
End;

{ Dernier element de la ligne en cours (Head-1) est-il effacable ? }
Function LineHasData(T : PTty) : Boolean;
Var P, V : LongInt;
Begin
  LineHasData := False;
  If TtyCount(T) = 0 Then Exit;
  P := (T^.Head - 1 + TtyBuf) Mod TtyBuf;
  V := T^.Rbuf[P];
  If (V = 10) Or (V >= EofMark) Or (V = T^.Cc[VEOL]) Then Exit;
  LineHasData := True;
End;

Procedure TtyEraseOne(T : PTty);
Var P, V : LongInt;
Begin
  T^.Head := (T^.Head - 1 + TtyBuf) Mod TtyBuf;
  P := T^.Head;
  V := T^.Rbuf[P];
  If (T^.Lflag And ECHO) <> 0 Then
  Begin
    If (T^.Lflag And ECHOE) <> 0 Then
    Begin
      TtyOut(T, 8); TtyOut(T, 32); TtyOut(T, 8);
      If (V < 32) And (V <> 9) And ((T^.Lflag And ECHOCTL) <> 0) Then
      Begin
        TtyOut(T, 8); TtyOut(T, 32); TtyOut(T, 8);
      End;
    End
    Else TtyEchoChar(T, T^.Cc[VERASE]);
  End;
End;

{ Un octet recu du clavier ou de la ligne serie }
Procedure TtyInput(T : PTty; C : LongInt);
Var Sig, N : LongInt;
Begin
  C := C And $FF;
  If (T^.Iflag And ISTRIP) <> 0 Then C := C And $7F;
  If T^.Lnext <> 0 Then
  Begin
    T^.Lnext := 0;
    If (T^.Lflag And ECHO) <> 0 Then TtyEchoChar(T, C);
    TtyPush(T, C);
    WakeUp(T^.Wchan);
    Exit;
  End;
  If (C = 13) Then
  Begin
    If (T^.Iflag And IGNCR) <> 0 Then Exit;
    If (T^.Iflag And ICRNL) <> 0 Then C := 10;
  End
  Else If (C = 10) And ((T^.Iflag And INLCR) <> 0) Then C := 13;
  { signaux }
  If (T^.Lflag And ISIG) <> 0 Then
  Begin
    Sig := 0;
    If (C = T^.Cc[VINTR]) And (C <> 0) Then Sig := SIGINT
    Else If (C = T^.Cc[VQUIT]) And (C <> 0) Then Sig := SIGQUIT
    Else If (C = T^.Cc[VSUSP]) And (C <> 0) Then Sig := SIGTSTP;
    If Sig <> 0 Then
    Begin
      If (T^.Lflag And ECHO) <> 0 Then TtyEchoChar(T, C);
      If (T^.Lflag And NOFLSH) = 0 Then
      Begin
        T^.Head := T^.Tail;
        T^.Lines := 0;
      End;
      SendSigPgrp(T^.Pgrp, Sig);
      Exit;
    End;
  End;
  { controle de flux }
  If (T^.Iflag And IXON) <> 0 Then
  Begin
    If (C = T^.Cc[VSTOP]) And (C <> 0) Then
    Begin
      T^.Stopped := 1;
      Exit;
    End;
    If ((C = T^.Cc[VSTART]) And (C <> 0)) Or ((T^.Stopped <> 0) And ((T^.Iflag
        And IXANY) <> 0)) Then
    Begin
      T^.Stopped := 0;
      WakeUp(T^.Wchan);
      If C = T^.Cc[VSTART] Then Exit;
    End;
  End;
  If (T^.Lflag And ICANON) = 0 Then
  Begin
    TtyPush(T, C);
    If (T^.Lflag And ECHO) <> 0 Then TtyEchoChar(T, C);
    WakeUp(T^.Wchan);
    Exit;
  End;
  { mode canonique }
  If (T^.Lflag And IEXTEN) <> 0 Then
    If (C = T^.Cc[VLNEXT]) And (C <> 0) Then
    Begin
      T^.Lnext := 1;
      If (T^.Lflag And ECHO) <> 0 Then
      Begin
        TtyOut(T, 94); TtyOut(T, 8);
      End;
      Exit;
    End;
  If (C = T^.Cc[VERASE]) And (C <> 0) Then
  Begin
    If LineHasData(T) Then TtyEraseOne(T);
    Exit;
  End;
  If (C = T^.Cc[VKILL]) And (C <> 0) Then
  Begin
    While LineHasData(T) Do TtyEraseOne(T);
    If ((T^.Lflag And ECHO) <> 0) And ((T^.Lflag And ECHOK) <> 0)
        And ((T^.Lflag And ECHOE) = 0) Then TtyOut(T, 10);
    Exit;
  End;
  If (C = T^.Cc[VWERASE]) And (C <> 0) And ((T^.Lflag And IEXTEN) <> 0) Then
  Begin
    While LineHasData(T) And (T^.Rbuf[(T^.Head - 1 + TtyBuf) Mod TtyBuf] = 32)
        Do TtyEraseOne(T);
    While LineHasData(T) And (T^.Rbuf[(T^.Head - 1 + TtyBuf) Mod TtyBuf] <> 32)
        Do TtyEraseOne(T);
    Exit;
  End;
  If (C = T^.Cc[VEOF]) And (C <> 0) Then
  Begin
    TtyPush(T, EofMark);
    Inc(T^.Lines);
    WakeUp(T^.Wchan);
    Exit;
  End;
  If (C = 10) Or ((C = T^.Cc[VEOL]) And (C <> 0)) Or ((C = T^.Cc[VEOL2]) And (C
      <> 0)) Then
  Begin
    If ((T^.Lflag And ECHO) <> 0) Or (((T^.Lflag And ECHONL) <> 0) And (C
        = 10)) Then TtyOut(T, 10);
    TtyPush(T, C);
    Inc(T^.Lines);
    WakeUp(T^.Wchan);
    Exit;
  End;
  If (T^.Lflag And ECHO) <> 0 Then TtyEchoChar(T, C);
  TtyPush(T, C);
  N := 0;
End;

{ ---- Peripherique : ouverture, lecture, ecriture, ioctl ---- }

Function TtyOf(F : PFile) : PTty;
Begin
  If (F^.Priv <= 0) Or (F^.Priv > NTtys) Then TtyOf := Nil
  Else TtyOf := @Ttys[F^.Priv - 1];
End;

Function TtyOpenIdx(Maj, Min : LongInt) : LongInt;
Begin
  TtyOpenIdx := -1;
  If Maj = 5 Then
  Begin
    If Min = 0 Then TtyOpenIdx := Cur^.Tty
    Else If Min = 1 Then
    Begin
      If ConsoleSerial Then TtyOpenIdx := 4 Else TtyOpenIdx := ActiveVc;
    End;
    Exit;
  End;
  If Min = 0 Then TtyOpenIdx := ActiveVc
  Else If (Min >= 1) And (Min <= NVc) Then TtyOpenIdx := Min - 1
  Else If Min = 64 Then TtyOpenIdx := 4;
End;

Function TtyOpen(I : PInode; F : PFile) : LongInt;
Var Idx : LongInt; T : PTty;
Begin
  Idx := TtyOpenIdx((I^.Rdev Shr 8) And $FF, I^.Rdev And $FF);
  If (Idx < 0) Or (Idx >= NTtys) Then
  Begin
    If ((I^.Rdev Shr 8) And $FF = 5) And ((I^.Rdev And $FF) = 0)
        Then TtyOpen := -ENXIO
    Else TtyOpen := -ENXIO;
    Exit;
  End;
  T := @Ttys[Idx];
  F^.Priv := Idx + 1;
  Inc(T^.Opens);
  { terminal de controle : chef de session sans terminal }
  If ((F^.Flags And O_NOCTTY) = 0) And (Cur^.Sid = Cur^.Pid)
      And (Cur^.Tty < 0) And
     (T^.Session = 0) Then
  Begin
    Cur^.Tty := Idx;
    T^.Session := Cur^.Sid;
    T^.Pgrp := Cur^.Pgid;
  End;
  TtyOpen := 0;
End;

Procedure TtyRelease(F : PFile);
Var T : PTty;
Begin
  T := TtyOf(F);
  If T <> Nil Then Dec(T^.Opens);
End;

{ Controle de travaux pour la lecture/ecriture : 0 ou -errno }
Function TtyJobCheck(T : PTty; Sig : LongInt) : LongInt;
Begin
  TtyJobCheck := 0;
  If (Cur^.Tty <> T^.Index) Or (T^.Session <> Cur^.Sid) Then Exit;
  If (T^.Pgrp = 0) Or (T^.Pgrp = Cur^.Pgid) Then Exit;
  If (Cur^.Sig^.Handler[Sig] = SIG_IGN) Or ((Cur^.Blk[0] And SigLoBit(Sig))
      <> 0) Then
  Begin
    If Sig = SIGTTIN Then TtyJobCheck := -EIO;
    Exit;
  End;
  SendSigPgrp(Cur^.Pgid, Sig);
  TtyJobCheck := -ERESTARTSYS;
End;

Function TtyRead(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var T : PTty; N, V, R, Vmn, Vtm, Tmo, P : LongInt; Done : Boolean;
Begin
  T := TtyOf(F);
  If T = Nil Then
  Begin
    TtyRead := -EIO;
    Exit;
  End;
  R := TtyJobCheck(T, SIGTTIN);
  If R <> 0 Then
  Begin
    TtyRead := R;
    Exit;
  End;
  If (T^.Lflag And ICANON) <> 0 Then
  Begin
    { attendre une ligne complete }
    While T^.Lines = 0 Do
    Begin
      If (F^.Flags And O_NONBLOCK) <> 0 Then
      Begin
        TtyRead := -EAGAIN;
        Exit;
      End;
      If SleepOn(T^.Wchan, 0, True) = WakeSignal Then
      Begin
        TtyRead := -ERESTARTSYS;
        Exit;
      End;
    End;
    N := 0;
    Done := False;
    While (Not Done) And (N < Cnt) And (TtyCount(T) > 0) Do
    Begin
      V := T^.Rbuf[T^.Tail];
      T^.Tail := (T^.Tail + 1) Mod TtyBuf;
      If V >= EofMark Then
      Begin
        Dec(T^.Lines);
        Break;
      End;
      Mem[0:Buf + N] := V;
      Inc(N);
      If (V = 10) Or ((V = T^.Cc[VEOL]) And (V <> 0)) Or ((V = T^.Cc[VEOL2])
          And (V <> 0)) Then
      Begin
        Dec(T^.Lines);
        Done := True;
      End;
    End;
    TtyRead := N;
    Exit;
  End;
  { mode brut : VMIN / VTIME }
  Vmn := T^.Cc[VMIN];
  Vtm := T^.Cc[VTIME];
  If (F^.Flags And O_NONBLOCK) <> 0 Then
  Begin
    Vmn := 0; Vtm := 0;
  End;
  If Vmn > Cnt Then Vmn := Cnt;
  N := 0;
  While True Do
  Begin
    While (N < Cnt) And (TtyCount(T) > 0) Do
    Begin
      Mem[0:Buf + N] := T^.Rbuf[T^.Tail] And $FF;
      T^.Tail := (T^.Tail + 1) Mod TtyBuf;
      Inc(N);
    End;
    If N >= Cnt Then Break;
    If (N >= Vmn) And ((Vmn > 0) Or (N > 0) Or (Vtm = 0)) And (N > 0)
        Then Break;
    If (Vmn = 0) And (Vtm = 0) Then Break;
    If (Vmn = 0) And (N = 0) And (Vtm > 0) Then
    Begin
      { attente bornee du premier octet }
      Tmo := Vtm * (HZ Div 10);
      R := SleepOn(T^.Wchan, Tmo, True);
      If R = WakeSignal Then
      Begin
        If N = 0 Then N := -ERESTARTSYS;
        Break;
      End;
      If TtyCount(T) = 0 Then Break;
      Continue;
    End;
    If (Vmn > 0) And (Vtm > 0) And (N > 0) Then
    Begin
      R := SleepOn(T^.Wchan, Vtm * (HZ Div 10), True);
      If (R = WakeTimeout) Or (R = WakeSignal) Then Break;
      Continue;
    End;
    If (F^.Flags And O_NONBLOCK) <> 0 Then
    Begin
      If N = 0 Then N := -EAGAIN;
      Break;
    End;
    If SleepOn(T^.Wchan, 0, True) = WakeSignal Then
    Begin
      If N = 0 Then N := -ERESTARTSYS;
      Break;
    End;
  End;
  P := 0;
  TtyRead := N;
End;

Function TtyWrite(F : PFile; Buf, Cnt : LongInt) : LongInt;
Var T : PTty; I, R : LongInt;
Begin
  T := TtyOf(F);
  If T = Nil Then
  Begin
    TtyWrite := -EIO;
    Exit;
  End;
  If (T^.Lflag And TOSTOP) <> 0 Then
  Begin
    R := TtyJobCheck(T, SIGTTOU);
    If R <> 0 Then
    Begin
      If R = -EIO Then R := 0;
      If R <> 0 Then
      Begin
        TtyWrite := R;
        Exit;
      End;
    End;
  End;
  For I := 0 To Cnt - 1 Do
  Begin
    While T^.Stopped <> 0 Do
      If SleepOn(T^.Wchan, 0, True) = WakeSignal Then
      Begin
        If I > 0 Then TtyWrite := I Else TtyWrite := -ERESTARTSYS;
        Exit;
      End;
    TtyOut(T, Mem[0:Buf + I]);
  End;
  TtyWrite := Cnt;
End;

Procedure TtyFlushIn(T : PTty);
Begin
  T^.Head := T^.Tail;
  T^.Lines := 0;
End;

Function TtyIoctl(F : PFile; Cmd, Arg : LongInt) : LongInt;
Var T : PTty; I, R, V : LongInt;
Begin
  T := TtyOf(F);
  TtyIoctl := -ENOTTY;
  If T = Nil Then Exit;
  Case Cmd Of
    $5401, $5402, $5403, $5404 :   { TCGETS, TCSETS, TCSETSW, TCSETSF }
      Begin
        If Cmd = $5401 Then
        Begin
          If Not EnsureUser(Arg, 36, True) Then
          Begin
            TtyIoctl := -EFAULT;
            Exit;
          End;
          MemL[0:Arg] := T^.Iflag; MemL[0:Arg + 4] := T^.Oflag;
          MemL[0:Arg + 8] := T^.Cflag; MemL[0:Arg + 12] := T^.Lflag;
          Mem[0:Arg + 16] := T^.Line;
          For I := 0 To 18 Do Mem[0:Arg + 17 + I] := T^.Cc[I];
          TtyIoctl := 0;
        End
        Else
        Begin
          If Not EnsureUser(Arg, 36, False) Then
          Begin
            TtyIoctl := -EFAULT;
            Exit;
          End;
          If Cmd = $5404 Then TtyFlushIn(T);
          T^.Iflag := MemL[0:Arg]; T^.Oflag := MemL[0:Arg + 4];
          T^.Cflag := MemL[0:Arg + 8]; T^.Lflag := MemL[0:Arg + 12];
          T^.Line := Mem[0:Arg + 16];
          For I := 0 To 18 Do T^.Cc[I] := Mem[0:Arg + 17 + I];
          If (T^.Lflag And ICANON) = 0 Then
            If TtyCount(T) > 0 Then WakeUp(T^.Wchan);
          TtyIoctl := 0;
        End;
      End;
    $5409, $540A : TtyIoctl := 0;                { TCSBRK, TCXONC }
    $540B :                                      { TCFLSH }
      Begin
        If (Arg = 0) Or (Arg = 2) Then TtyFlushIn(T);
        TtyIoctl := 0;
      End;
    $540E :                                      { TIOCSCTTY }
      Begin
        If (Cur^.Sid = Cur^.Pid) And (Cur^.Tty < 0) And ((T^.Session = 0)
            Or (Cur^.Euid = 0)) Then
        Begin
          Cur^.Tty := T^.Index;
          T^.Session := Cur^.Sid;
          T^.Pgrp := Cur^.Pgid;
          TtyIoctl := 0;
        End
        Else TtyIoctl := -EPERM;
      End;
    $540F :                                      { TIOCGPGRP }
      TtyIoctl := PutUserL(Arg, T^.Pgrp);
    $5410 :                                      { TIOCSPGRP }
      Begin
        R := GetUserL(Arg, V);
        If R < 0 Then
        Begin
          TtyIoctl := R;
          Exit;
        End;
        If (Cur^.Tty <> T^.Index) Then
          TtyIoctl := -ENOTTY
        Else If V <= 0 Then TtyIoctl := -EINVAL
        Else
        Begin
          T^.Pgrp := V;
          TtyIoctl := 0;
        End;
      End;
    $5413 :                                      { TIOCGWINSZ }
      Begin
        If Not EnsureUser(Arg, 8, True) Then
        Begin
          TtyIoctl := -EFAULT;
          Exit;
        End;
        MemW[0:Arg] := T^.Rows; MemW[0:Arg + 2] := T^.Cols;
        MemW[0:Arg + 4] := 0; MemW[0:Arg + 6] := 0;
        TtyIoctl := 0;
      End;
    $5414 :                                      { TIOCSWINSZ }
      Begin
        If Not EnsureUser(Arg, 8, False) Then
        Begin
          TtyIoctl := -EFAULT;
          Exit;
        End;
        T^.Rows := MemW[0:Arg]; T^.Cols := MemW[0:Arg + 2];
        SendSigPgrp(T^.Pgrp, SIGWINCH);
        TtyIoctl := 0;
      End;
    $541B :                                      { FIONREAD }
      Begin
        If (T^.Lflag And ICANON) <> 0 Then V := 0 Else V := TtyCount(T);
        TtyIoctl := PutUserL(Arg, V);
      End;
    $5422 :                                      { TIOCNOTTY }
      Begin
        If Cur^.Tty = T^.Index Then Cur^.Tty := -1;
        TtyIoctl := 0;
      End;
    $5429 : TtyIoctl := PutUserL(Arg, T^.Session);   { TIOCGSID }
    $4B33 : TtyIoctl := PutUserL(Arg, 2);
        { KDGKBTYPE : clavier 101 touches }
    $4B3A, $4B3B, $4B44, $4B45 : TtyIoctl := 0;      { KDSETMODE... (ignore) }
    $5600 : TtyIoctl := PutUserL(Arg, 1);            { VT_OPENQRY }
    $5603 :                                          { VT_GETSTATE }
      Begin
        If Not EnsureUser(Arg, 6, True) Then
        Begin
          TtyIoctl := -EFAULT;
          Exit;
        End;
        MemW[0:Arg] := ActiveVc + 1; MemW[0:Arg + 2] := 0; MemW[0:Arg
            + 4] := $1F;
        TtyIoctl := 0;
      End;
    $5606 :                                          { VT_ACTIVATE }
      Begin
        If (Arg >= 1) And (Arg <= NVc) Then
        Begin
          VcShow(Arg - 1);
          TtyIoctl := 0;
        End
        Else TtyIoctl := -ENXIO;
      End;
    $5607 : TtyIoctl := 0;                           { VT_WAITACTIVE }
  End;
End;

Function TtyPoll(F : PFile; Ev : LongInt) : LongInt;
Var T : PTty; R : LongInt;
Begin
  T := TtyOf(F);
  TtyPoll := POLLNVAL;
  If T = Nil Then Exit;
  R := POLLOUT;
  If (T^.Lflag And ICANON) <> 0 Then
  Begin
    If T^.Lines > 0 Then R := R Or POLLIN;
  End
  Else If TtyCount(T) > 0 Then R := R Or POLLIN;
  TtyPoll := R;
End;

{ Fin de la session d'un chef : SIGHUP au groupe de premier plan }
Procedure TtyDisassociate(T : PTask);
Var Tt : PTty; I : LongInt;
Begin
  If (T^.Tty < 0) Or (T^.Tty >= NTtys) Then Exit;
  Tt := @Ttys[T^.Tty];
  If Tt^.Session = T^.Sid Then
  Begin
    SendSigPgrp(Tt^.Pgrp, SIGHUP);
    SendSigPgrp(Tt^.Pgrp, SIGCONT);
    Tt^.Session := 0;
    Tt^.Pgrp := 0;
    For I := 1 To MaxTasks - 1 Do
      If (Tasks[I].State <> TsFree) And (Tasks[I].Tty = T^.Tty)
          And (Tasks[I].Sid = T^.Sid) Then
        Tasks[I].Tty := -1;
  End;
  T^.Tty := -1;
End;

{ ---- Clavier PS/2 (IRQ 1) ---- }

Procedure KbdRow(Tbl : Integer; Start : LongInt; Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do
  Begin
    Case Tbl Of
      0 : KbdMapLo[Start + I - 1] := Ord(S[I]);
      1 : KbdMapHi[Start + I - 1] := Ord(S[I]);
      2 : KbdMapAlt[Start + I - 1] := Ord(S[I]);
    End;
  End;
End;

Procedure KbdInitMaps;
Begin
  MemFill(LongInt(@KbdMapLo[0]), 0, 128);
  MemFill(LongInt(@KbdMapHi[0]), 0, 128);
  MemFill(LongInt(@KbdMapAlt[0]), 0, 128);
  If KeymapName = 'fr' Then
  Begin
    KbdAzerty := True;
    KbdRow(0, 2, '&e"''(-e_ca)=');
    KbdRow(1, 2, '1234567890');
    KbdMapHi[12] := 176; KbdMapHi[13] := 43;
    KbdRow(2, 3, '~#{[|`\^@]}');
    KbdRow(0, 16, 'azertyuiop^$');
    KbdRow(1, 16, 'AZERTYUIOP~$');
    KbdRow(0, 30, 'qsdfghjklmu');
    KbdRow(1, 30, 'QSDFGHJKLM%');
    KbdRow(0, 44, 'wxcvbn,;:!');
    KbdRow(1, 44, 'WXCVBN?./~');
    { caracteres Latin-1 (codes > 127) }
    KbdMapLo[3] := 233; KbdMapLo[8] := 232; KbdMapLo[10] := 231;
        KbdMapLo[11] := 224;
    KbdMapLo[39] := 109; KbdMapLo[40] := 249; KbdMapHi[40] := 37;
    KbdMapLo[41] := 178; KbdMapHi[41] := 0; KbdMapLo[43] := 42;
        KbdMapHi[43] := 181;
    KbdMapHi[27] := 163; KbdMapLo[26] := 94; KbdMapHi[26] := 168;
    KbdMapHi[53] := 167; KbdMapLo[53] := 33; KbdMapLo[52] := 58;
        KbdMapHi[52] := 47;
    KbdMapLo[51] := 59; KbdMapHi[51] := 46; KbdMapLo[50] := 44;
        KbdMapHi[50] := 63;
    KbdMapLo[86] := 60; KbdMapHi[86] := 62;
  End
  Else
  Begin
    KbdAzerty := False;
    KbdRow(0, 2, '1234567890-=');
    KbdRow(1, 2, '!@#$%^&*()_+');
    KbdRow(0, 16, 'qwertyuiop[]');
    KbdRow(1, 16, 'QWERTYUIOP{}');
    KbdRow(0, 30, 'asdfghjkl;''`');
    KbdRow(1, 30, 'ASDFGHJKL:"~');
    KbdMapLo[43] := 92; KbdMapHi[43] := 124;
    KbdRow(0, 44, 'zxcvbnm,./');
    KbdRow(1, 44, 'ZXCVBNM<>?');
    KbdMapLo[86] := 60; KbdMapHi[86] := 62;
  End;
  KbdMapLo[14] := 127; KbdMapHi[14] := 127;
  KbdMapLo[15] := 9; KbdMapHi[15] := 9;
  KbdMapLo[28] := 13; KbdMapHi[28] := 13;
  KbdMapLo[1] := 27; KbdMapHi[1] := 27;
  KbdMapLo[57] := 32; KbdMapHi[57] := 32;
  KbdMapLo[55] := 42; KbdMapHi[55] := 42;
  KbdNum := True;
End;

Procedure KbdPutByte(C : LongInt);
Begin
  If Ttys[ActiveVc].Opens > 0 Then TtyInput(@Ttys[ActiveVc], C)
  Else TtyInput(@Ttys[ActiveVc], C);
End;

{ Latin-1 -> octets UTF-8 }
Procedure KbdPutChar(C : LongInt);
Begin
  If C < 128 Then KbdPutByte(C)
  Else
  Begin
    KbdPutByte($C0 Or (C Shr 6));
    KbdPutByte($80 Or (C And $3F));
  End;
End;

Procedure KbdPutStr(Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do KbdPutByte(Ord(S[I]));
End;

Procedure KbdIrq;
Var Sc, Code, C : LongInt; Rel : Boolean;
Begin
  Sc := Port[$60];
  If Sc = $E0 Then
  Begin
    KbdE0 := True;
    Exit;
  End;
  If Sc = $E1 Then Exit;
  Rel := (Sc And $80) <> 0;
  Code := Sc And $7F;
  If Rel Then
  Begin
    Case Code Of
      42, 54 : KbdShift := False;
      29 : KbdCtrl := False;
      56 : If KbdE0 Then KbdAltGr := False Else KbdAlt := False;
    End;
    KbdE0 := False;
    Exit;
  End;
  RandState := RandState Xor (Jiffies Shl 8) Xor Sc;
  Case Code Of
    42, 54 : Begin KbdShift := True; KbdE0 := False; Exit; End;
    29 : Begin KbdCtrl := True; KbdE0 := False; Exit; End;
    56 : Begin
           If KbdE0 And KbdAzerty Then KbdAltGr := True
           Else If KbdE0 Then KbdAltGr := True
           Else KbdAlt := True;
           KbdE0 := False;
           Exit;
         End;
    58 : Begin KbdCaps := Not KbdCaps; KbdE0 := False; Exit; End;
    69 : Begin KbdNum := Not KbdNum; KbdE0 := False; Exit; End;
  End;
  { combinaisons systeme }
  If KbdAlt And (Code >= 59) And (Code <= 58 + NVc) Then
  Begin
    VcShow(Code - 59);
    KbdE0 := False;
    Exit;
  End;
  If KbdCtrl And KbdAlt And (Code = 83) Then
  Begin
    CtrlAltDel := True;
    KbdE0 := False;
    Exit;
  End;
  { touches etendues ou du pave numerique }
  If KbdE0 Or ((Code >= 71) And (Code <= 83) And Not KbdNum) Or (Code = 83) Then
  Begin
    Case Code Of
      72 : KbdPutStr(#27'[A');
      80 : KbdPutStr(#27'[B');
      77 : KbdPutStr(#27'[C');
      75 : KbdPutStr(#27'[D');
      71 : KbdPutStr(#27'[1~');
      79 : KbdPutStr(#27'[4~');
      73 : KbdPutStr(#27'[5~');
      81 : KbdPutStr(#27'[6~');
      82 : KbdPutStr(#27'[2~');
      83 : KbdPutStr(#27'[3~');
      28 : KbdPutByte(13);
      53 : KbdPutByte(47);
    End;
    If (Not KbdE0) And (Code >= 71) And (Code <= 83) And KbdNum Then;
    KbdE0 := False;
    Exit;
  End;
  If (Code >= 71) And (Code <= 83) And KbdNum Then
  Begin
    Case Code Of
      71 : KbdPutByte(Ord('7')); 72 : KbdPutByte(Ord('8'));
          73 : KbdPutByte(Ord('9'));
      74 : KbdPutByte(Ord('-')); 75 : KbdPutByte(Ord('4'));
          76 : KbdPutByte(Ord('5'));
      77 : KbdPutByte(Ord('6')); 78 : KbdPutByte(Ord('+'));
          79 : KbdPutByte(Ord('1'));
      80 : KbdPutByte(Ord('2')); 81 : KbdPutByte(Ord('3'));
          82 : KbdPutByte(Ord('0'));
      83 : KbdPutByte(Ord('.'));
    End;
    KbdE0 := False;
    Exit;
  End;
  KbdE0 := False;
  { touches de fonction }
  If (Code >= 59) And (Code <= 68) Then
  Begin
    Case Code Of
      59 : KbdPutStr(#27'[[A'); 60 : KbdPutStr(#27'[[B');
          61 : KbdPutStr(#27'[[C');
      62 : KbdPutStr(#27'[[D'); 63 : KbdPutStr(#27'[[E');
          64 : KbdPutStr(#27'[17~');
      65 : KbdPutStr(#27'[18~'); 66 : KbdPutStr(#27'[19~');
          67 : KbdPutStr(#27'[20~');
      68 : KbdPutStr(#27'[21~');
    End;
    Exit;
  End;
  If (Code = 87) Then Begin KbdPutStr(#27'[23~'); Exit; End;
  If (Code = 88) Then Begin KbdPutStr(#27'[24~'); Exit; End;
  { caracteres }
  C := 0;
  If KbdAltGr And (KbdMapAlt[Code] <> 0) Then C := KbdMapAlt[Code]
  Else If KbdShift Then C := KbdMapHi[Code]
  Else C := KbdMapLo[Code];
  If C = 0 Then Exit;
  If KbdCaps And (Not KbdShift) And (C >= 97) And (C <= 122) Then C := C - 32
  Else If KbdCaps And KbdShift And (C >= 65) And (C <= 90) Then C := C + 32;
  If KbdCtrl Then
  Begin
    If (C >= 97) And (C <= 122) Then C := C - 96
    Else If (C >= 64) And (C <= 95) Then C := C - 64
    Else If C = 32 Then C := 0
    Else If C = 63 Then C := 127;
  End;
  If KbdAlt Then KbdPutByte(27);
  If (C = 0) And KbdCtrl Then KbdPutByte(0) Else KbdPutChar(C);
End;

{ ---- Port serie ttyS0 (IRQ 4) ---- }

Procedure SerialIrq;
Var N : LongInt;
Begin
  N := 0;
  While ((Port[Com1 + 5] And 1) <> 0) And (N < 64) Do
  Begin
    TtyInput(@Ttys[4], Port[Com1]);
    Inc(N);
  End;
End;

Procedure InitTty;
Var I : LongInt;
Begin
  For I := 0 To NTtys - 1 Do TtyReset(@Ttys[I], I);
  Ttys[4].Cols := 80;
  MemFill(LongInt(@TtyFOps[0]), 0, SizeOf(TtyFOps));
  TtyFOps[FoRead] := LongInt(@TtyRead);
  TtyFOps[FoWrite] := LongInt(@TtyWrite);
  TtyFOps[FoIoctl] := LongInt(@TtyIoctl);
  TtyFOps[FoPoll] := LongInt(@TtyPoll);
  TtyFOps[FoOpen] := LongInt(@TtyOpen);
  TtyFOps[FoRelease] := LongInt(@TtyRelease);
  ChrOps[4] := LongInt(@TtyFOps[0]);
  ChrOps[5] := LongInt(@TtyFOps[0]);
  KbdInitMaps;
  { clavier : IRQ 1 ; port serie : IRQ 4 (donnees recues) }
  While (Port[$64] And 1) <> 0 Do I := Port[$60];
  IrqEnable(1);
  If SerialOk Then
  Begin
    Port[Com1 + 1] := 1;
    IrqEnable(4);
  End;
End;

{ ==================================================================== }
{ Partie 15 - Chargeur ELF (execve), pile utilisateur                 }
{ ==================================================================== }

Const
  ArgMax      = 131072;         { arguments + environnement : 128 Ko }
  AT_NULL = 0; AT_PHDR = 3; AT_PHENT = 4; AT_PHNUM = 5; AT_PAGESZ = 6;
  AT_BASE = 7; AT_FLAGS = 8; AT_ENTRY = 9; AT_UID = 11; AT_EUID = 12;
  AT_GID = 13; AT_EGID = 14; AT_PLATFORM = 15; AT_HWCAP = 16; AT_CLKTCK = 17;
  AT_SECURE = 23; AT_RANDOM = 25; AT_EXECFN = 31;
  UserStackTop = $C0000000;

Var
  ExArgs     : LongInt;         { tampon : chaines argv puis envp }
  ExUsed     : LongInt;
  ExArgc, ExEnvc : LongInt;
  ExPath     : String;          { nom du programme (execfn) }
  ExAtBase   : LongInt;         { AT_BASE : base de l'interpreteur (0 : aucun) }

{ Ajouter une chaine a la fin du tampon ; faux si trop gros }
Function ExAdd(Const S : String) : Boolean;
Var L : LongInt;
Begin
  L := Length(S) + 1;
  ExAdd := False;
  If ExUsed + L > ArgMax Then Exit;
  PutPStr(ExArgs + ExUsed, S, L);
  ExUsed := ExUsed + L;
  ExAdd := True;
End;

{ Copier un tableau de pointeurs de chaines utilisateur : retourne -errno ou 0 }
Function ExCollect(Arr : LongInt; Var N : LongInt) : LongInt;
Var P, R : LongInt; S : String;
Begin
  N := 0;
  ExCollect := 0;
  If Arr = 0 Then Exit;
  While True Do
  Begin
    R := GetUserL(Arr + N * 4, P);
    If R < 0 Then
    Begin
      ExCollect := R;
      Exit;
    End;
    If P = 0 Then Break;
    R := GetUserStr(P, S);
    If R < 0 Then
    Begin
      If R = -ENAMETOOLONG Then R := -E2BIG;
      ExCollect := R;
      Exit;
    End;
    If Not ExAdd(S) Then
    Begin
      ExCollect := -E2BIG;
      Exit;
    End;
    Inc(N);
    If N > 8192 Then
    Begin
      ExCollect := -E2BIG;
      Exit;
    End;
  End;
End;

{ Retirer la premiere chaine (argv[0]) du tampon }
Procedure ExDropFirst;
Var L : LongInt;
Begin
  L := StrLen0(ExArgs) + 1;
  MemCopy(ExArgs, ExArgs + L, ExUsed - L);
  Dec(ExUsed, L);
  Dec(ExArgc);
End;

Function ExPrepend(Const S : String) : Boolean;
Var L : LongInt;
Begin
  L := Length(S) + 1;
  ExPrepend := False;
  If ExUsed + L > ArgMax Then Exit;
  MemCopy(ExArgs + L, ExArgs, ExUsed);
  PutPStr(ExArgs, S, L);
  Inc(ExUsed, L);
  Inc(ExArgc);
  ExPrepend := True;
End;

{ ---- Chargement ---- }

{ Etat de l'espace d'adressage apres un exec reussi }
Function ExecSetupStack(Mm : PMm; Entry, Phdr, Phnum, Phent,
    Secure : LongInt) : LongInt;
Var Strs, NStr, Total, Sp, I, P, ArgPtr, EnvPtr, AuxCount, Str0, ExecFn, Plat,
    Rnd, Len : LongInt;
    Tab : LongInt; V : PVma; Base : LongInt;
Begin
  ExecSetupStack := -ENOMEM;
  Len := Length(ExPath) + 1;
  { de haut en bas : execfn, chaines, plate-forme, aleatoire, auxv, envp,
    argv, argc }
  Sp := UserStackTop - 4;
  Sp := Sp - Len;
  ExecFn := Sp;
  Sp := Sp - ExUsed;
  Str0 := Sp;
  Sp := Sp - 8;
  Plat := Sp;
  Sp := Sp - 16;
  Rnd := Sp;
  Sp := Sp And Not 15;
  AuxCount := 18;
  Tab := (AuxCount * 2) * 4 + (ExEnvc + 1) * 4 + (ExArgc + 1) * 4 + 4;
  Sp := Sp - Tab;
  Sp := Sp And Not 15;
  { VMA de pile : jusqu'au sommet, croissance vers le bas }
  Base := PageDown(Sp - 4096);
  V := VmaNew(Base, UserStackTop, PROT_READ Or PROT_WRITE, MAP_PRIVATE
      Or MAP_ANONYMOUS Or VmStack Or MAP_GROWSDOWN);
  If V = Nil Then Exit;
  VmaInsert(Mm, V);
  Mm^.StartStack := Sp;
  If Not EnsureUser(Base, UserStackTop - Base, True) Then Exit;
  { chaines }
  PutPStr(ExecFn, ExPath, Len);
  MemCopy(Str0, ExArgs, ExUsed);
  PutPStr(Plat, 'i686', 8);
  For I := 0 To 15 Do Mem[0:Rnd + I] := RandNext And $FF;
  { tableaux }
  P := Sp;
  MemL[0:P] := ExArgc;
  P := P + 4;
  ArgPtr := Str0;
  Mm^.ArgStart := Str0;
  For I := 0 To ExArgc - 1 Do
  Begin
    MemL[0:P] := ArgPtr;
    ArgPtr := ArgPtr + StrLen0(ArgPtr) + 1;
    P := P + 4;
  End;
  MemL[0:P] := 0;
  P := P + 4;
  Mm^.ArgEnd := ArgPtr;
  Mm^.EnvStart := ArgPtr;
  For I := 0 To ExEnvc - 1 Do
  Begin
    MemL[0:P] := ArgPtr;
    ArgPtr := ArgPtr + StrLen0(ArgPtr) + 1;
    P := P + 4;
  End;
  MemL[0:P] := 0;
  P := P + 4;
  Mm^.EnvEnd := ArgPtr;
  { vecteur auxiliaire }
  MemL[0:P] := AT_PHDR; MemL[0:P + 4] := Phdr; P := P + 8;
  MemL[0:P] := AT_PHENT; MemL[0:P + 4] := Phent; P := P + 8;
  MemL[0:P] := AT_PHNUM; MemL[0:P + 4] := Phnum; P := P + 8;
  MemL[0:P] := AT_PAGESZ; MemL[0:P + 4] := 4096; P := P + 8;
  MemL[0:P] := AT_BASE; MemL[0:P + 4] := ExAtBase; P := P + 8;
  MemL[0:P] := AT_FLAGS; MemL[0:P + 4] := 0; P := P + 8;
  MemL[0:P] := AT_ENTRY; MemL[0:P + 4] := Entry; P := P + 8;
  MemL[0:P] := AT_UID; MemL[0:P + 4] := Cur^.Uid; P := P + 8;
  MemL[0:P] := AT_EUID; MemL[0:P + 4] := Cur^.Euid; P := P + 8;
  MemL[0:P] := AT_GID; MemL[0:P + 4] := Cur^.Gid; P := P + 8;
  MemL[0:P] := AT_EGID; MemL[0:P + 4] := Cur^.Egid; P := P + 8;
  MemL[0:P] := AT_PLATFORM; MemL[0:P + 4] := Plat; P := P + 8;
  MemL[0:P] := AT_HWCAP; MemL[0:P + 4] := 1; P := P + 8;
  MemL[0:P] := AT_CLKTCK; MemL[0:P + 4] := HZ; P := P + 8;
  MemL[0:P] := AT_SECURE; MemL[0:P + 4] := Secure; P := P + 8;
  MemL[0:P] := AT_RANDOM; MemL[0:P + 4] := Rnd; P := P + 8;
  MemL[0:P] := AT_EXECFN; MemL[0:P + 4] := ExecFn; P := P + 8;
  MemL[0:P] := AT_NULL; MemL[0:P + 4] := 0; P := P + 8;
  ExecSetupStack := Sp;
  Strs := 0; NStr := 0; Total := 0;
End;

{ Reinitialiser l'etat du processus pour un nouveau programme }
Procedure ExecResetState;
Var I : LongInt; F : PFiles;
Begin
  { signaux : les gestionnaires reviennent a SIG_DFL, les ignores le restent }
  If Cur^.Sig^.Count > 1 Then
  Begin
    Dec(Cur^.Sig^.Count);
    Cur^.Sig := SigDup(Cur^.Sig);
  End;
  For I := 1 To 64 Do
    If Cur^.Sig^.Handler[I] <> SIG_IGN Then
    Begin
      Cur^.Sig^.Handler[I] := SIG_DFL;
      Cur^.Sig^.Flags[I] := 0;
    End;
  Cur^.SigStk[0] := 0; Cur^.SigStk[1] := 2; Cur^.SigStk[2] := 0;
  { descripteurs close-on-exec }
  F := Cur^.Files;
  For I := 0 To MaxFd - 1 Do
    If (F^.Fd[I] <> 0) And (F^.CloseExec[I] <> 0) Then FdClose(I);
  For I := 0 To 5 Do Cur^.Tls[I] := 0;
  LoadTls(Cur);
  InitFpu;
  SaveFpu(LongInt(@Cur^.Fpu[0]));
  Cur^.ClearTid := 0;
  ReleaseVfork(Cur);
End;

Function ExecLoad(Const Path : String; Depth : LongInt) : LongInt; Forward;

{ Interpretation de "#!" : modifie le tampon d'arguments ; retourne -errno ou
  0 et le chemin de l'interpreteur dans Interp }
Function ExecScript(Ino : PInode; Const Path : String;
    Var Interp : String) : LongInt;
Var Buf : Array[0..127] Of Byte; N, I, J : LongInt; Line, Arg : String;
Begin
  N := InodeReadAt(LongInt(Ino), LongInt(@Buf[0]), 0, 127);
  If N < 3 Then
  Begin
    ExecScript := -ENOEXEC;
    Exit;
  End;
  Line := '';
  I := 2;
  While (I < N) And (Buf[I] <> 10) Do
  Begin
    Line := Line + Chr(Buf[I]);
    Inc(I);
  End;
  While (Length(Line) > 0) And ((Line[1] = ' ') Or (Line[1] = #9))
      Do Delete(Line, 1, 1);
  While (Length(Line) > 0) And ((Line[Length(Line)] = ' ')
      Or (Line[Length(Line)] = #9) Or (Line[Length(Line)] = #13))
      Do Delete(Line, Length(Line), 1);
  If Line = '' Then
  Begin
    ExecScript := -ENOEXEC;
    Exit;
  End;
  J := 1;
  While (J <= Length(Line)) And (Line[J] <> ' ') And (Line[J] <> #9) Do Inc(J);
  Interp := Copy(Line, 1, J - 1);
  Arg := Copy(Line, J + 1, 255);
  While (Length(Arg) > 0) And ((Arg[1] = ' ') Or (Arg[1] = #9)) Do Delete(Arg,
      1, 1);
  ExDropFirst;
  If Not ExPrepend(Path) Then
  Begin
    ExecScript := -E2BIG;
    Exit;
  End;
  If Arg <> '' Then
    If Not ExPrepend(Arg) Then
    Begin
      ExecScript := -E2BIG;
      Exit;
    End;
  If Not ExPrepend(Interp) Then
  Begin
    ExecScript := -E2BIG;
    Exit;
  End;
  ExecScript := 0;
End;

{ Projeter les segments PT_LOAD du fichier I (en-tetes de programme en
  Ph) a l'adresse Bias + p_vaddr. Retourne la fin du dernier segment (tas),
  l'adresse des en-tetes en memoire (HdrAddr) et les bornes du code et des
  donnees. Appele apres le point de non retour : un echec tue le processus }
Procedure ExMapSegs(I : PInode; Ph, Phnum, Phoff, Bias : LongInt; Mm : PMm;
    Var BrkOut, HdrAddr, StartCode, EndCode, StartData, EndData : LongInt);
Var K, PType, POff, PVaddr, PFilesz, PMemsz, PFlags, Prot, Start, Fin,
    FileEnd, BssEnd, FirstLoad : LongInt; V : PVma;
Begin
  BrkOut := 0;
  HdrAddr := 0;
  FirstLoad := 1;
  StartCode := 0; EndCode := 0; StartData := 0; EndData := 0;
  For K := 0 To Phnum - 1 Do
  Begin
    PType := MemL[0:Ph + K * 32];
    POff := MemL[0:Ph + K * 32 + 4];
    PVaddr := MemL[0:Ph + K * 32 + 8] + Bias;
    PFilesz := MemL[0:Ph + K * 32 + 16];
    PMemsz := MemL[0:Ph + K * 32 + 20];
    PFlags := MemL[0:Ph + K * 32 + 24];
    If PType = 1 Then
    Begin
      Prot := 0;
      If (PFlags And 4) <> 0 Then Prot := Prot Or PROT_READ;
      If (PFlags And 2) <> 0 Then Prot := Prot Or PROT_WRITE;
      If (PFlags And 1) <> 0 Then Prot := Prot Or PROT_EXEC;
      Start := PageDown(PVaddr);
      FileEnd := PVaddr + PFilesz;
      BssEnd := PVaddr + PMemsz;
      If PFilesz > 0 Then
      Begin
        Fin := PageUp(FileEnd);
        V := VmaNew(Start, Fin, Prot, MAP_PRIVATE);
        If V = Nil Then DieBySignal(SIGKILL, False);
        V^.Ino := InodeRef(LongInt(I));
        V^.Off := POff - (PVaddr - Start);
        V^.FLen := PFilesz + (PVaddr - Start);
        VmaInsert(Mm, V);
      End
      Else Fin := Start;
      If PageUp(BssEnd) > Fin Then
      Begin
        V := VmaNew(Fin, PageUp(BssEnd), Prot, MAP_PRIVATE Or MAP_ANONYMOUS);
        If V = Nil Then DieBySignal(SIGKILL, False);
        VmaInsert(Mm, V);
      End;
      If FirstLoad <> 0 Then
      Begin
        HdrAddr := PVaddr - POff + Phoff;
        FirstLoad := 0;
      End;
      If (PFlags And 1) <> 0 Then
      Begin
        StartCode := PVaddr; EndCode := FileEnd;
      End
      Else
      Begin
        If StartData = 0 Then StartData := PVaddr;
        EndData := FileEnd;
      End;
      If PageUp(BssEnd) > BrkOut Then BrkOut := PageUp(BssEnd);
    End;
  End;
End;

{ Charger le programme Path dans un nouvel espace d'adressage (les arguments
  sont dans ExArgs). Retourne 0 ou -errno. Au-dela du point de non retour,
  un echec tue le processus. }
Function ExecLoad(Const Path : String; Depth : LongInt) : LongInt;
Var D : PDentry; I : PInode; R, N, K, Phoff, Phnum, Phent, Entry, Etype,
    Machine : LongInt;
    Hdr : Array[0..63] Of Byte; Ph : LongInt; NewMm, OldMm : PMm; PType, POff,
        PVaddr, PFilesz,
    PMemsz, PFlags, Prot, Start, Fin, FileEnd, BssEnd, Brk, HdrAddr, Sp,
        Interp2 : LongInt;
    FirstLoad, Secure : LongInt; Fr : PFrame; Intp : String; Nm : String;
        V : PVma;
    EndCode, StartCode, StartData, EndData : LongInt; Perm : LongInt;
    Bias, IBias, IBrk, IHdr, ISc, IEc, ISd, IEd, MainEntry, IPh, IPhnum,
    ISpan, IMin, IMax, IEntry : LongInt;
    IntpPath : String; IDent : PDentry; IIno : PInode; IHdrB : Array[0..63] Of Byte;
Begin
  If Depth > 4 Then
  Begin
    ExecLoad := -ELOOP;
    Exit;
  End;
  R := PathWalk(Path, True, D);
  If R <> 0 Then
  Begin
    ExecLoad := R;
    Exit;
  End;
  I := D^.Inode;
  If (I^.Mode And S_IFMT) <> S_IFREG Then
  Begin
    DentryPut(LongInt(D));
    If IsDir(I) Then ExecLoad := -EACCES Else ExecLoad := -EACCES;
    Exit;
  End;
  R := InodePerm(I, MAY_EXEC);
  If (R = 0) And ((I^.Mode And $49) = 0) Then R := -EACCES;
  If R <> 0 Then
  Begin
    DentryPut(LongInt(D));
    ExecLoad := R;
    Exit;
  End;
  MemFill(LongInt(@Hdr[0]), 0, 64);
  N := InodeReadAt(LongInt(I), LongInt(@Hdr[0]), 0, 52);
  If N < 4 Then
  Begin
    DentryPut(LongInt(D));
    ExecLoad := -ENOEXEC;
    Exit;
  End;
  If (Hdr[0] = Ord('#')) And (Hdr[1] = Ord('!')) Then
  Begin
    R := ExecScript(I, Path, Intp);
    DentryPut(LongInt(D));
    If R <> 0 Then
    Begin
      ExecLoad := R;
      Exit;
    End;
    ExecLoad := ExecLoad(Intp, Depth + 1);
    Exit;
  End;
  If (N < 52) Or (MemL[0:LongInt(@Hdr[0])] <> $464C457F) Or (Hdr[4] <> 1)
      Or (Hdr[5] <> 1) Then
  Begin
    DentryPut(LongInt(D));
    ExecLoad := -ENOEXEC;
    Exit;
  End;
  Etype := MemW[0:LongInt(@Hdr[0]) + 16];
  Machine := MemW[0:LongInt(@Hdr[0]) + 18];
  Entry := MemL[0:LongInt(@Hdr[0]) + 24];
  Phoff := MemL[0:LongInt(@Hdr[0]) + 28];
  Phent := MemW[0:LongInt(@Hdr[0]) + 42];
  Phnum := MemW[0:LongInt(@Hdr[0]) + 44];
  If ((Etype <> 2) And (Etype <> 3)) Or (Machine <> 3) Or (Phent <> 32)
      Or (Phnum = 0) Or (Phnum > 64) Then
  Begin
    DentryPut(LongInt(D));
    ExecLoad := -ENOEXEC;
    Exit;
  End;
  Ph := KMalloc(Phnum * 32);
  If Ph = 0 Then
  Begin
    DentryPut(LongInt(D));
    ExecLoad := -ENOMEM;
    Exit;
  End;
  If InodeReadAt(LongInt(I), Ph, Phoff, Phnum * 32) <> Phnum * 32 Then
  Begin
    KFree(Ph);
    DentryPut(LongInt(D));
    ExecLoad := -ENOEXEC;
    Exit;
  End;
  { verifier les segments avant le point de non retour }
  For K := 0 To Phnum - 1 Do
  Begin
    PType := MemL[0:Ph + K * 32];
    If PType = 1 Then
    Begin
      PVaddr := MemL[0:Ph + K * 32 + 8];
      PFilesz := MemL[0:Ph + K * 32 + 16];
      PMemsz := MemL[0:Ph + K * 32 + 20];
      If (PFilesz > PMemsz) Or ULt(UserTop - StackReserve, PVaddr + PMemsz)
          Or ULt(PVaddr + PMemsz, PVaddr) Or
         (PVaddr < 4096) Then
      Begin
        KFree(Ph);
        DentryPut(LongInt(D));
        ExecLoad := -ENOEXEC;
        Exit;
      End;
    End;
  End;
  { biais des executables PIE (ET_DYN) et interpreteur (PT_INTERP) }
  Bias := 0;
  If Etype = 3 Then Bias := $08048000;
  IntpPath := '';
  IIno := Nil; IDent := Nil; IPh := 0; IPhnum := 0; IEntry := 0;
  For K := 0 To Phnum - 1 Do
    If MemL[0:Ph + K * 32] = 3 Then
    Begin
      POff := MemL[0:Ph + K * 32 + 4];
      PFilesz := MemL[0:Ph + K * 32 + 16];
      If (PFilesz > 1) And (PFilesz < 256) Then
      Begin
        MemFill(LongInt(@IHdrB[0]), 0, 64);
        N := InodeReadAt(LongInt(I), LongInt(@IHdrB[0]), POff, PFilesz);
        If N = PFilesz Then
          For R := 0 To PFilesz - 2 Do IntpPath := IntpPath + Chr(IHdrB[R]);
        MemFill(LongInt(@IHdrB[0]), 0, 64);
      End;
    End;
  If IntpPath <> '' Then
  Begin
    R := PathWalk(IntpPath, True, IDent);
    If R <> 0 Then
    Begin
      KFree(Ph);
      DentryPut(LongInt(D));
      ExecLoad := R;
      Exit;
    End;
    IIno := IDent^.Inode;
    If ((IIno^.Mode And S_IFMT) <> S_IFREG)
       Or (InodeReadAt(LongInt(IIno), LongInt(@IHdrB[0]), 0, 52) <> 52)
       Or (MemL[0:LongInt(@IHdrB[0])] <> $464C457F) Or (IHdrB[4] <> 1)
       Or (MemW[0:LongInt(@IHdrB[0]) + 16] <> 3)
       Or (MemW[0:LongInt(@IHdrB[0]) + 18] <> 3)
       Or (MemW[0:LongInt(@IHdrB[0]) + 42] <> 32)
       Or (MemW[0:LongInt(@IHdrB[0]) + 44] = 0)
       Or (MemW[0:LongInt(@IHdrB[0]) + 44] > 64) Then
    Begin
      DentryPut(LongInt(IDent));
      KFree(Ph);
      DentryPut(LongInt(D));
      ExecLoad := -ELIBBAD;
      Exit;
    End;
    IPhnum := MemW[0:LongInt(@IHdrB[0]) + 44];
    IEntry := MemL[0:LongInt(@IHdrB[0]) + 24];
    IPh := KMalloc(IPhnum * 32);
    If (IPh = 0) Or (InodeReadAt(LongInt(IIno), IPh,
        MemL[0:LongInt(@IHdrB[0]) + 28], IPhnum * 32) <> IPhnum * 32) Then
    Begin
      If IPh <> 0 Then KFree(IPh);
      DentryPut(LongInt(IDent));
      KFree(Ph);
      DentryPut(LongInt(D));
      ExecLoad := -ELIBBAD;
      Exit;
    End;
    { etendue de l'interpreteur }
    IMin := -1; IMax := 0;
    For K := 0 To IPhnum - 1 Do
      If MemL[0:IPh + K * 32] = 1 Then
      Begin
        PVaddr := MemL[0:IPh + K * 32 + 8];
        PMemsz := MemL[0:IPh + K * 32 + 20];
        If (IMin = -1) Or ULt(PVaddr, IMin) Then IMin := PVaddr;
        If ULt(IMax, PVaddr + PMemsz) Then IMax := PVaddr + PMemsz;
      End;
    If IMin = -1 Then IMin := 0;
    IMin := PageDown(IMin);
    ISpan := PageUp(IMax) - IMin;
  End;
  NewMm := MmNew;
  If NewMm = Nil Then
  Begin
    If IIno <> Nil Then
    Begin
      KFree(IPh);
      DentryPut(LongInt(IDent));
    End;
    KFree(Ph);
    DentryPut(LongInt(D));
    ExecLoad := -ENOMEM;
    Exit;
  End;
  { ---- point de non retour : changer d'espace d'adressage ---- }
  OldMm := Cur^.Mm;
  Cur^.Mm := NewMm;
  CurMm := NewMm;
  WriteCr3(NewMm^.PgdPhys);
  If OldMm <> Nil Then MmRelease(OldMm);
  ExecResetState;
  ExMapSegs(I, Ph, Phnum, Phoff, Bias, NewMm, Brk, HdrAddr, StartCode,
      EndCode, StartData, EndData);
  MainEntry := Entry + Bias;
  ExAtBase := 0;
  If IIno <> Nil Then
  Begin
    IBias := FindFreeArea(NewMm, ISpan);
    If IBias = 0 Then DieBySignal(SIGKILL, False);
    IBias := IBias - IMin;
    ExMapSegs(IIno, IPh, IPhnum, MemL[0:LongInt(@IHdrB[0]) + 28], IBias,
        NewMm, IBrk, IHdr, ISc, IEc, ISd, IEd);
    KFree(IPh);
    DentryPut(LongInt(IDent));
    ExAtBase := IBias;
    Entry := IBias + IEntry;
  End
  Else Entry := MainEntry;
  KFree(Ph);
  NewMm^.StartCode := StartCode; NewMm^.EndCode := EndCode;
  NewMm^.StartData := StartData; NewMm^.EndData := EndData;
  NewMm^.StartBrk := Brk; NewMm^.Brk := Brk;
  NewMm^.DataLimit := 0;
  NewMm^.StackLimit := Cur^.RlimCur[RLIM_STACK];
  { setuid / setgid }
  Secure := 0;
  If (I^.Mode And S_ISUID) <> 0 Then
  Begin
    Cur^.Euid := I^.Uid; Cur^.Fsuid := I^.Uid; Secure := 1;
  End;
  If (I^.Mode And S_ISGID) <> 0 Then
  Begin
    Cur^.Egid := I^.Gid; Cur^.Fsgid := I^.Gid; Secure := 1;
  End;
  Cur^.Suid := Cur^.Euid; Cur^.Sgid := Cur^.Egid;
  { nom du processus }
  Nm := Path;
  K := Length(Nm);
  While (K > 0) And (Nm[K] <> '/') Do Dec(K);
  Nm := Copy(Nm, K + 1, 15);
  For K := 0 To 15 Do Cur^.Comm[K] := 0;
  For K := 1 To Length(Nm) Do Cur^.Comm[K - 1] := Ord(Nm[K]);
  DentryPut(LongInt(D));
  Sp := ExecSetupStack(NewMm, MainEntry, HdrAddr, Phnum, Phent,
      Secure);
  If (Sp < 0) And (Sp > -4096) Then DieBySignal(SIGKILL, False);
  { retour en mode utilisateur au point d'entree }
  Fr := Pointer(Cur^.Frame);
  MemFill(LongInt(Fr), 0, SizeOf(TFrame));
  Fr^.Ds := SelUData; Fr^.Es := SelUData; Fr^.Ss := SelUData;
      Fr^.Cs := SelUCode;
  Fr^.Eip := Entry;
  Fr^.UserEsp := Sp;
  Fr^.Eflags := $202;
  Fr^.Vec := VecSyscall;
  ExecLoad := 0;
End;

{ execve(Path, Argv, Envp) : adresses utilisateur }
Function DoExecve(PathAddr, Argv, Envp : LongInt) : LongInt;
Var Path : String; R : LongInt;
Begin
  R := GetUserStr(PathAddr, Path);
  If R < 0 Then
  Begin
    DoExecve := R;
    Exit;
  End;
  If Path = '' Then
  Begin
    DoExecve := -ENOENT;
    Exit;
  End;
  ExArgs := KMalloc(ArgMax);
  If ExArgs = 0 Then
  Begin
    DoExecve := -ENOMEM;
    Exit;
  End;
  ExUsed := 0; ExArgc := 0; ExEnvc := 0;
  R := ExCollect(Argv, ExArgc);
  If R = 0 Then R := ExCollect(Envp, ExEnvc);
  If R <> 0 Then
  Begin
    KFree(ExArgs);
    DoExecve := R;
    Exit;
  End;
  If ExArgc = 0 Then
  Begin
    { argv vide : donner au moins argv[0] }
    ExPrepend(Path);
  End;
  ExPath := Path;
  R := ExecLoad(Path, 0);
  KFree(ExArgs);
  ExArgs := 0;
  DoExecve := R;
End;

{ execve depuis le noyau (init) : le tampon est prepare par l'appelant }
Function KernelExecve(Const Path : String; Const Args : String;
    Const Env : String) : LongInt;
Var R : LongInt;
Begin
  ExArgs := KMalloc(ArgMax);
  If ExArgs = 0 Then
  Begin
    KernelExecve := -ENOMEM;
    Exit;
  End;
  ExUsed := 0; ExArgc := 0; ExEnvc := 0;
  ExAdd(Args);
  ExArgc := 1;
  ExAdd(Env);
  ExEnvc := 1;
  ExPath := Path;
  R := ExecLoad(Path, 0);
  KFree(ExArgs);
  ExArgs := 0;
  KernelExecve := R;
End;

{ ==================================================================== }
{ Partie 16 - Appels systeme (INT 80h, ABI Linux i386)                 }
{ ==================================================================== }
{
  Numeros EXACTS de la table Linux i386 (syscall_32.tbl).
  Registres : EAX = numero ; EBX, ECX, EDX, ESI, EDI, EBP = arguments 1 a 6 ;
  retour dans EAX (valeur ou -errno). Appels realises (les autres : -ENOSYS) :

    1 exit  2 fork  3 read  4 write  5 open  6 close  7 waitpid  8 creat
    9 link  10 unlink  11 execve  12 chdir  13 time  14 mknod  15 chmod
    16 lchown  19 lseek  20 getpid  21 mount  22 umount  23 setuid  24 getuid
    26 ptrace(-EPERM)  27 alarm  29 pause  30 utime  33 access  34 nice
    36 sync  37 kill  38 rename  39 mkdir  40 rmdir  41 dup  42 pipe  43 times
    45 brk  46 setgid  47 getgid  48 signal  49 geteuid  50 getegid  52 umount2
    54 ioctl  55 fcntl  57 setpgid  60 umask  61 chroot  63 dup2  64 getppid
    65 getpgrp  66 setsid  67 sigaction  68 sgetmask  69 ssetmask  70 setreuid
    71 setregid  72 sigsuspend  73 sigpending  74 sethostname  75 setrlimit
    76 getrlimit  77 getrusage  78 gettimeofday  79 settimeofday  80 getgroups
    81 setgroups  82 select  83 symlink  85 readlink  88 reboot  90 mmap
    91 munmap  92 truncate  93 ftruncate  94 fchmod  95 fchown  96 getpriority
    97 setpriority  99 statfs  100 fstatfs  102 socketcall(-ENOSYS)  103 syslog
    104 setitimer  105 getitimer  106 stat  107 lstat  108 fstat  111 vhangup
    114 wait4  116 sysinfo  118 fsync  119 sigreturn  120 clone
    121 setdomainname
    122 uname  125 mprotect  126 sigprocmask  132 getpgid  133 fchdir
    140 _llseek  141 getdents  142 _newselect  143 flock  144 msync  145 readv
    146 writev  147 getsid  148 fdatasync  158 sched_yield  162 nanosleep
    164 setresuid  165 getresuid  168 poll  170 setresgid  171 getresgid
    172 prctl  173 rt_sigreturn  174 rt_sigaction  175 rt_sigprocmask
    176 rt_sigpending  179 rt_sigsuspend  180 pread64  181 pwrite64  182 chown
    183 getcwd  186 sigaltstack  190 vfork  191 ugetrlimit  192 mmap2
    193 truncate64  194 ftruncate64  195 stat64  196 lstat64  197 fstat64
    198-216 variantes 32 bits des appels d'identifiants  220 getdents64
    221 fcntl64  224 gettid  240 futex  243 set_thread_area  244 get_thread_area
    252 exit_group  258 set_tid_address  265 clock_gettime  266 clock_getres
    267 clock_nanosleep  268 statfs64  269 fstatfs64  270 tgkill  271 utimes
    295 openat  296 mkdirat  297 mknodat  300 fstatat64  301 unlinkat
    320 utimensat
    302 renameat  303 linkat  304 symlinkat  305 readlinkat  306 fchmodat
    307 faccessat  330 dup3  331 pipe2  340 prlimit64  355 getrandom }

Const
  MaxSys      = 400;
  AT_FDCWD    = -100;
  RdChunk     = 65536;
  KHostname   : String[64] = 'linux0';

Var
  SysFn       : Array[0..MaxSys - 1] Of LongInt;
  SysArgc     : Array[0..MaxSys - 1] Of LongInt;
  HostName    : String;
  DomainName  : String;
  SyscallCount : LongInt;

Procedure SysReg(Nr : LongInt; Fn, Argc : LongInt);
Begin
  SysFn[Nr] := Fn;
  SysArgc[Nr] := Argc;
End;

{ Identifiants 16 bits (appels anciens) : 0FFFFh signifie -1 }
Function Id16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V = $FFFF Then Id16 := -1 Else Id16 := V;
End;

{ ---- Fichiers : lecture, ecriture ---- }

Function SysRead(Fd, Buf, Cnt : LongInt) : LongInt;
Var F : PFile; Done, N, Chunk : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysRead := -EBADF;
    Exit;
  End;
  If Cnt < 0 Then
  Begin
    SysRead := -EINVAL;
    Exit;
  End;
  Done := 0;
  While Done < Cnt Do
  Begin
    Chunk := Cnt - Done;
    If Chunk > RdChunk Then Chunk := RdChunk;
    If Not EnsureUser(Buf + Done, Chunk, True) Then
    Begin
      If Done = 0 Then SysRead := -EFAULT Else SysRead := Done;
      Exit;
    End;
    N := VfsRead(F, Buf + Done, Chunk);
    If N < 0 Then
    Begin
      If Done = 0 Then SysRead := N Else SysRead := Done;
      Exit;
    End;
    Done := Done + N;
    If N < Chunk Then Break;
  End;
  SysRead := Done;
End;

Function SysWrite(Fd, Buf, Cnt : LongInt) : LongInt;
Var F : PFile; Done, N, Chunk : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysWrite := -EBADF;
    Exit;
  End;
  If Cnt < 0 Then
  Begin
    SysWrite := -EINVAL;
    Exit;
  End;
  Done := 0;
  While Done < Cnt Do
  Begin
    Chunk := Cnt - Done;
    If Chunk > RdChunk Then Chunk := RdChunk;
    If Not EnsureUser(Buf + Done, Chunk, False) Then
    Begin
      If Done = 0 Then SysWrite := -EFAULT Else SysWrite := Done;
      Exit;
    End;
    N := VfsWrite(F, Buf + Done, Chunk);
    If N < 0 Then
    Begin
      If Done = 0 Then SysWrite := N Else SysWrite := Done;
      Exit;
    End;
    Done := Done + N;
    If N < Chunk Then Break;
  End;
  SysWrite := Done;
End;

Function SysPread(Fd, Buf, Cnt, PosLo, PosHi : LongInt) : LongInt;
Var F : PFile; Old, R : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysPread := -EBADF;
    Exit;
  End;
  If ((F^.Inode^.Mode And S_IFMT) = S_IFIFO) Or ((F^.Inode^.Mode And S_IFMT)
      = S_IFCHR) Then
  Begin
    SysPread := -ESPIPE;
    Exit;
  End;
  If (Cnt > RdChunk) Then Cnt := RdChunk;
  If Not EnsureUser(Buf, Cnt, True) Then
  Begin
    SysPread := -EFAULT;
    Exit;
  End;
  Old := F^.Pos;
  F^.Pos := PosLo;
  R := VfsRead(F, Buf, Cnt);
  F^.Pos := Old;
  SysPread := R;
End;

Function SysPwrite(Fd, Buf, Cnt, PosLo, PosHi : LongInt) : LongInt;
Var F : PFile; Old, R, Fl : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysPwrite := -EBADF;
    Exit;
  End;
  If ((F^.Inode^.Mode And S_IFMT) = S_IFIFO) Or ((F^.Inode^.Mode And S_IFMT)
      = S_IFCHR) Then
  Begin
    SysPwrite := -ESPIPE;
    Exit;
  End;
  If (Cnt > RdChunk) Then Cnt := RdChunk;
  If Not EnsureUser(Buf, Cnt, False) Then
  Begin
    SysPwrite := -EFAULT;
    Exit;
  End;
  Old := F^.Pos;
  Fl := F^.Flags;
  F^.Flags := F^.Flags And Not O_APPEND;
  F^.Pos := PosLo;
  R := VfsWrite(F, Buf, Cnt);
  F^.Pos := Old;
  F^.Flags := Fl;
  SysPwrite := R;
End;

{ readv / writev : tableau d'iovec (base, longueur) }
Function SysReadv(Fd, Iov, Cnt : LongInt) : LongInt;
Var I, R, Tot, Base, Len : LongInt;
Begin
  If (Cnt < 0) Or (Cnt > 1024) Then
  Begin
    SysReadv := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(Iov, Cnt * 8, False) Then
  Begin
    SysReadv := -EFAULT;
    Exit;
  End;
  Tot := 0;
  For I := 0 To Cnt - 1 Do
  Begin
    Base := MemL[0:Iov + I * 8];
    Len := MemL[0:Iov + I * 8 + 4];
    If Len > 0 Then
    Begin
      R := SysRead(Fd, Base, Len);
      If R < 0 Then
      Begin
        If Tot = 0 Then SysReadv := R Else SysReadv := Tot;
        Exit;
      End;
      Tot := Tot + R;
      If R < Len Then Break;
    End;
  End;
  SysReadv := Tot;
End;

Function SysWritev(Fd, Iov, Cnt : LongInt) : LongInt;
Var I, R, Tot, Base, Len : LongInt;
Begin
  If (Cnt < 0) Or (Cnt > 1024) Then
  Begin
    SysWritev := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(Iov, Cnt * 8, False) Then
  Begin
    SysWritev := -EFAULT;
    Exit;
  End;
  Tot := 0;
  For I := 0 To Cnt - 1 Do
  Begin
    Base := MemL[0:Iov + I * 8];
    Len := MemL[0:Iov + I * 8 + 4];
    If Len > 0 Then
    Begin
      R := SysWrite(Fd, Base, Len);
      If R < 0 Then
      Begin
        If Tot = 0 Then SysWritev := R Else SysWritev := Tot;
        Exit;
      End;
      Tot := Tot + R;
      If R < Len Then Break;
    End;
  End;
  SysWritev := Tot;
End;

{ ---- Ouverture et descripteurs ---- }

{ Resoudre dirfd pour les appels *at : positionne temporairement le repertoire
  courant ; retourne l'ancien Pwd (a restaurer avec AtRestore) ou -errno }
Function AtEnter(Dirfd : LongInt; Const Path : String;
    Var Saved : PDentry) : LongInt;
Var F : PFile;
Begin
  Saved := Nil;
  AtEnter := 0;
  If (Dirfd = AT_FDCWD) Or ((Length(Path) > 0) And (Path[1] = '/')) Then Exit;
  F := FdGet(Dirfd);
  If F = Nil Then
  Begin
    AtEnter := -EBADF;
    Exit;
  End;
  If Not IsDir(F^.Inode) Then
  Begin
    AtEnter := -ENOTDIR;
    Exit;
  End;
  Saved := Cur^.Fs^.Pwd;
  Cur^.Fs^.Pwd := F^.Dentry;
End;

Procedure AtRestore(Saved : PDentry);
Begin
  If Saved <> Nil Then Cur^.Fs^.Pwd := Saved;
End;

Function OpenPath(Const Path : String; Flags, Mode : LongInt) : LongInt;
Var F : PFile; R : LongInt;
Begin
  R := VfsOpen(Path, Flags, Mode, F);
  If R <> 0 Then
  Begin
    OpenPath := R;
    Exit;
  End;
  R := FdInstall(F, 0, (Flags And O_CLOEXEC) <> 0);
  If R < 0 Then FilePut(LongInt(F));
  OpenPath := R;
End;

Function SysOpen(PathAddr, Flags, Mode : LongInt) : LongInt;
Var P : String; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysOpen := R;
    Exit;
  End;
  SysOpen := OpenPath(P, Flags, Mode);
End;

Function SysCreat(PathAddr, Mode : LongInt) : LongInt;
Begin
  SysCreat := SysOpen(PathAddr, O_CREAT Or O_WRONLY Or O_TRUNC, Mode);
End;

Function SysOpenat(Dirfd, PathAddr, Flags, Mode : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysOpenat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysOpenat := R;
    Exit;
  End;
  SysOpenat := OpenPath(P, Flags, Mode);
  AtRestore(Sv);
End;

Function SysClose(Fd : LongInt) : LongInt;
Begin
  SysClose := FdClose(Fd);
End;

Function SysDup(Fd : LongInt) : LongInt;
Var F : PFile; R : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysDup := -EBADF;
    Exit;
  End;
  R := FdInstall(F, 0, False);
  If R >= 0 Then FileGet(LongInt(F));
  SysDup := R;
End;

Function DupTo(Old, New, Flags : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Old);
  If F = Nil Then
  Begin
    DupTo := -EBADF;
    Exit;
  End;
  If (New < 0) Or (New >= MaxFd) Or (New >= Cur^.RlimCur[RLIM_NOFILE]) Then
  Begin
    DupTo := -EBADF;
    Exit;
  End;
  If Old = New Then
  Begin
    DupTo := New;
    Exit;
  End;
  If Cur^.Files^.Fd[New] <> 0 Then FdClose(New);
  Cur^.Files^.Fd[New] := LongInt(F);
  If (Flags And O_CLOEXEC) <> 0 Then Cur^.Files^.CloseExec[New] := 1
      Else Cur^.Files^.CloseExec[New] := 0;
  FileGet(LongInt(F));
  DupTo := New;
End;

Function SysDup2(Old, New : LongInt) : LongInt;
Begin
  SysDup2 := DupTo(Old, New, 0);
End;

Function SysDup3(Old, New, Flags : LongInt) : LongInt;
Begin
  If Old = New Then SysDup3 := -EINVAL Else SysDup3 := DupTo(Old, New, Flags);
End;

Function SysPipe2(FdsAddr, Flags : LongInt) : LongInt;
Var F1, F2 : PFile; R, A, B : LongInt;
Begin
  If Not EnsureUser(FdsAddr, 8, True) Then
  Begin
    SysPipe2 := -EFAULT;
    Exit;
  End;
  R := MakePipe(F1, F2);
  If R <> 0 Then
  Begin
    SysPipe2 := R;
    Exit;
  End;
  F1^.Flags := F1^.Flags Or (Flags And O_NONBLOCK);
  F2^.Flags := F2^.Flags Or (Flags And O_NONBLOCK);
  A := FdInstall(F1, 0, (Flags And O_CLOEXEC) <> 0);
  If A < 0 Then
  Begin
    FilePut(LongInt(F1)); FilePut(LongInt(F2));
    SysPipe2 := A;
    Exit;
  End;
  B := FdInstall(F2, 0, (Flags And O_CLOEXEC) <> 0);
  If B < 0 Then
  Begin
    FdClose(A);
    FilePut(LongInt(F2));
    SysPipe2 := B;
    Exit;
  End;
  MemL[0:FdsAddr] := A;
  MemL[0:FdsAddr + 4] := B;
  SysPipe2 := 0;
End;

Function SysPipe(FdsAddr : LongInt) : LongInt;
Begin
  SysPipe := SysPipe2(FdsAddr, 0);
End;

Function SysLseek(Fd, Off, Whence : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then SysLseek := -EBADF Else SysLseek := VfsLseek(F, Off, Whence);
End;

Function SysLlseek(Fd, Hi, Lo, ResAddr, Whence : LongInt) : LongInt;
Var F : PFile; R : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysLlseek := -EBADF;
    Exit;
  End;
  If (Hi <> 0) And (Hi <> -1) Then
  Begin
    SysLlseek := -EINVAL;
    Exit;
  End;
  R := VfsLseek(F, Lo, Whence);
  If R < 0 Then
  Begin
    SysLlseek := R;
    Exit;
  End;
  If Not EnsureUser(ResAddr, 8, True) Then
  Begin
    SysLlseek := -EFAULT;
    Exit;
  End;
  MemL[0:ResAddr] := R;
  MemL[0:ResAddr + 4] := 0;
  SysLlseek := 0;
End;

Function SysFcntl(Fd, Cmd, Arg : LongInt) : LongInt;
Var F : PFile; R : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFcntl := -EBADF;
    Exit;
  End;
  Case Cmd Of
    0, 1030 :
      Begin
        If (Arg < 0) Or (Arg >= MaxFd) Then
        Begin
          SysFcntl := -EINVAL;
          Exit;
        End;
        R := FdInstall(F, Arg, Cmd = 1030);
        If R >= 0 Then FileGet(LongInt(F));
        SysFcntl := R;
      End;
    1 : SysFcntl := Cur^.Files^.CloseExec[Fd];
    2 : Begin
          Cur^.Files^.CloseExec[Fd] := Arg And 1;
          SysFcntl := 0;
        End;
    3 : SysFcntl := F^.Flags;
    4 : Begin
          F^.Flags := (F^.Flags And Not (O_APPEND Or O_NONBLOCK)) Or (Arg
              And (O_APPEND Or O_NONBLOCK));
          SysFcntl := 0;
        End;
    5, 6, 7, 12, 13, 14 : SysFcntl := 0;      { verrous : acceptes }
    8 : Begin F^.Owner := Arg; SysFcntl := 0; End;
    9 : SysFcntl := F^.Owner;
  Else
    SysFcntl := -EINVAL;
  End;
End;

Function SysIoctl(Fd, Cmd, Arg : LongInt) : LongInt;
Var F : PFile; Fn : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysIoctl := -EBADF;
    Exit;
  End;
  Case Cmd Of
    $5451 : Begin Cur^.Files^.CloseExec[Fd] := 1; SysIoctl := 0; Exit; End;
    $5450 : Begin Cur^.Files^.CloseExec[Fd] := 0; SysIoctl := 0; Exit; End;
    $5421 :
      Begin
        If Arg <> 0 Then
        Begin
          If MemL[0:Arg] <> 0 Then F^.Flags := F^.Flags Or O_NONBLOCK
          Else F^.Flags := F^.Flags And Not O_NONBLOCK;
        End;
        SysIoctl := 0;
        Exit;
      End;
  End;
  Fn := GetOp(F^.FOps, FoIoctl);
  If Fn = 0 Then
  Begin
    If (Cmd = $541B) And ((F^.Inode^.Mode And S_IFMT) = S_IFREG)
        Then SysIoctl := PutUserL(Arg, F^.Inode^.Size - F^.Pos)
    Else SysIoctl := -ENOTTY;
    Exit;
  End;
  SysIoctl := Call3(Fn, LongInt(F), Cmd, Arg);
End;

{ ---- stat ---- }

Procedure FillStat64(I : PInode; A : LongInt);
Var Rd : LongInt;
Begin
  MemFill(A, 0, 96);
  MemL[0:A] := I^.Dev;
  MemL[0:A + 12] := I^.Ino;
  MemL[0:A + 16] := I^.Mode;
  MemL[0:A + 20] := I^.Nlink;
  MemL[0:A + 24] := I^.Uid;
  MemL[0:A + 28] := I^.Gid;
  MemL[0:A + 32] := I^.Rdev;
  MemL[0:A + 44] := I^.Size;
  MemL[0:A + 52] := 4096;
  MemL[0:A + 56] := I^.Blocks;
  If (I^.Blocks = 0) And (I^.Size > 0) Then MemL[0:A + 56] := (I^.Size + 511)
      Div 512;
  MemL[0:A + 64] := I^.Atime;
  MemL[0:A + 72] := I^.Mtime;
  MemL[0:A + 80] := I^.Ctime;
  MemL[0:A + 88] := I^.Ino;
  Rd := 0;
End;

{ ancienne structure stat (64 octets) }
Procedure FillStatOld(I : PInode; A : LongInt);
Begin
  MemFill(A, 0, 64);
  MemW[0:A] := I^.Dev;
  MemL[0:A + 4] := I^.Ino;
  MemW[0:A + 8] := I^.Mode;
  MemW[0:A + 10] := I^.Nlink;
  MemW[0:A + 12] := I^.Uid;
  MemW[0:A + 14] := I^.Gid;
  MemW[0:A + 16] := I^.Rdev;
  MemL[0:A + 20] := I^.Size;
  MemL[0:A + 24] := 4096;
  MemL[0:A + 28] := I^.Blocks;
  If (I^.Blocks = 0) And (I^.Size > 0) Then MemL[0:A + 28] := (I^.Size + 511)
      Div 512;
  MemL[0:A + 32] := I^.Atime;
  MemL[0:A + 40] := I^.Mtime;
  MemL[0:A + 48] := I^.Ctime;
End;

Function StatPath(PathAddr, Buf : LongInt; Follow, Old : Boolean) : LongInt;
Var P : String; D : PDentry; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    StatPath := R;
    Exit;
  End;
  If Not EnsureUser(Buf, 96, True) Then
  Begin
    StatPath := -EFAULT;
    Exit;
  End;
  R := PathWalk(P, Follow, D);
  If R <> 0 Then
  Begin
    StatPath := R;
    Exit;
  End;
  If Old Then FillStatOld(D^.Inode, Buf) Else FillStat64(D^.Inode, Buf);
  DentryPut(LongInt(D));
  StatPath := 0;
End;

Function SysStat64(Path, Buf : LongInt) : LongInt;
Begin
  SysStat64 := StatPath(Path, Buf, True, False);
End;

Function SysLstat64(Path, Buf : LongInt) : LongInt;
Begin
  SysLstat64 := StatPath(Path, Buf, False, False);
End;

Function SysStat(Path, Buf : LongInt) : LongInt;
Begin
  SysStat := StatPath(Path, Buf, True, True);
End;

Function SysLstat(Path, Buf : LongInt) : LongInt;
Begin
  SysLstat := StatPath(Path, Buf, False, True);
End;

Function SysFstat64(Fd, Buf : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFstat64 := -EBADF;
    Exit;
  End;
  If Not EnsureUser(Buf, 96, True) Then
  Begin
    SysFstat64 := -EFAULT;
    Exit;
  End;
  FillStat64(F^.Inode, Buf);
  SysFstat64 := 0;
End;

Function SysFstat(Fd, Buf : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFstat := -EBADF;
    Exit;
  End;
  If Not EnsureUser(Buf, 64, True) Then
  Begin
    SysFstat := -EFAULT;
    Exit;
  End;
  FillStatOld(F^.Inode, Buf);
  SysFstat := 0;
End;

Function SysFstatat64(Dirfd, PathAddr, Buf, Flags : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry; F : PFile;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysFstatat64 := R;
    Exit;
  End;
  If (P = '') And ((Flags And $1000) <> 0) Then
  Begin
    SysFstatat64 := SysFstat64(Dirfd, Buf);
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysFstatat64 := R;
    Exit;
  End;
  SysFstatat64 := StatPath(PathAddr, Buf, (Flags And $100) = 0, False);
  AtRestore(Sv);
  F := Nil;
End;

{ statfs : valeurs generiques ou propres au systeme de fichiers (SoStatfs) }
Procedure FillStatfs(Sb : PSuper; A : LongInt; Is64 : Boolean);
Var Magic, Bs, Blocks, Fre, Avail, Files, FFree, Fl, Fn : LongInt;
    St : Array[0..7] Of LongInt;
Begin
  Magic := $01021994;
  If FsNames[Sb^.FsType] = 'ramfs' Then Magic := $858458F6
  Else If FsNames[Sb^.FsType] = 'proc' Then Magic := $9FA0;
  Bs := 4096;
  Blocks := TotalFreePages;
  Fre := FreePagesCnt;
  Avail := Fre;
  Files := InodeCount + 1024;
  FFree := 1024;
  Fn := GetOp(Sb^.SOps, SoStatfs);
  If Fn <> 0 Then
  Begin
    MemFill(LongInt(@St[0]), 0, 32);
    Call2(Fn, LongInt(Sb), LongInt(@St[0]));
    Bs := St[0]; Blocks := St[1]; Fre := St[2]; Avail := St[3];
    Files := St[4]; FFree := St[5]; Magic := St[7];
  End;
  Fl := 0;
  If (Sb^.Flags And MS_RDONLY) <> 0 Then Fl := 1;
  If Is64 Then
  Begin
    MemFill(A, 0, 84);
    MemL[0:A] := Magic; MemL[0:A + 4] := Bs;
    MemL[0:A + 8] := Blocks; MemL[0:A + 16] := Fre; MemL[0:A + 24] := Avail;
    MemL[0:A + 32] := Files; MemL[0:A + 40] := FFree;
    MemL[0:A + 48] := Sb^.Dev;
    MemL[0:A + 56] := 255; MemL[0:A + 60] := Bs; MemL[0:A + 64] := Fl;
  End
  Else
  Begin
    MemFill(A, 0, 64);
    MemL[0:A] := Magic; MemL[0:A + 4] := Bs;
    MemL[0:A + 8] := Blocks; MemL[0:A + 12] := Fre; MemL[0:A + 16] := Avail;
    MemL[0:A + 20] := Files; MemL[0:A + 24] := FFree;
    MemL[0:A + 28] := Sb^.Dev;
    MemL[0:A + 36] := 255; MemL[0:A + 40] := Bs; MemL[0:A + 44] := Fl;
  End;
End;

Function SysStatfs(PathAddr, Buf : LongInt) : LongInt;
Var P : String; D : PDentry; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysStatfs := R;
    Exit;
  End;
  If Not EnsureUser(Buf, 64, True) Then
  Begin
    SysStatfs := -EFAULT;
    Exit;
  End;
  R := PathWalk(P, True, D);
  If R <> 0 Then
  Begin
    SysStatfs := R;
    Exit;
  End;
  FillStatfs(D^.Sb, Buf, False);
  DentryPut(LongInt(D));
  SysStatfs := 0;
End;

Function SysFstatfs(Fd, Buf : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFstatfs := -EBADF;
    Exit;
  End;
  If Not EnsureUser(Buf, 64, True) Then
  Begin
    SysFstatfs := -EFAULT;
    Exit;
  End;
  FillStatfs(F^.Inode^.Sb, Buf, False);
  SysFstatfs := 0;
End;

Function SysStatfs64(PathAddr, Sz, Buf : LongInt) : LongInt;
Var P : String; D : PDentry; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysStatfs64 := R;
    Exit;
  End;
  If (Sz < 84) Or Not EnsureUser(Buf, 84, True) Then
  Begin
    SysStatfs64 := -EFAULT;
    Exit;
  End;
  R := PathWalk(P, True, D);
  If R <> 0 Then
  Begin
    SysStatfs64 := R;
    Exit;
  End;
  FillStatfs(D^.Sb, Buf, True);
  DentryPut(LongInt(D));
  SysStatfs64 := 0;
End;

Function SysFstatfs64(Fd, Sz, Buf : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFstatfs64 := -EBADF;
    Exit;
  End;
  If (Sz < 84) Or Not EnsureUser(Buf, 84, True) Then
  Begin
    SysFstatfs64 := -EFAULT;
    Exit;
  End;
  FillStatfs(F^.Inode^.Sb, Buf, True);
  SysFstatfs64 := 0;
End;

{ ---- Repertoires ---- }

{ getdents (ancien format) et getdents64 }
Function DoGetdents(Fd, Buf, Cnt : LongInt; Is64 : Boolean) : LongInt;
Var F : PFile; Fn, Done, R, Ino, DType, L, Rec : LongInt; Nm : String;
    K : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    DoGetdents := -EBADF;
    Exit;
  End;
  If Not IsDir(F^.Inode) Then
  Begin
    DoGetdents := -ENOTDIR;
    Exit;
  End;
  Fn := GetOp(F^.FOps, FoReaddir);
  If Fn = 0 Then
  Begin
    DoGetdents := -ENOTDIR;
    Exit;
  End;
  If Not EnsureUser(Buf, Cnt, True) Then
  Begin
    DoGetdents := -EFAULT;
    Exit;
  End;
  Done := 0;
  While True Do
  Begin
    Ino := 0; DType := 0; Nm := '';
    L := F^.Pos;
    R := Call4(Fn, LongInt(F), LongInt(@Ino), LongInt(@Nm), LongInt(@DType));
    If R < 0 Then
    Begin
      If Done = 0 Then DoGetdents := R Else DoGetdents := Done;
      Exit;
    End;
    If R = 0 Then Break;
    If Is64 Then Rec := (19 + Length(Nm) + 1 + 7) And Not 7
    Else Rec := (10 + Length(Nm) + 1 + 1 + 3) And Not 3;
    If Done + Rec > Cnt Then
    Begin
      F^.Pos := L;                   { l'entree n'a pas tenu : la rejouer }
      If Done = 0 Then DoGetdents := -EINVAL Else DoGetdents := Done;
      Exit;
    End;
    MemFill(Buf + Done, 0, Rec);
    If Is64 Then
    Begin
      MemL[0:Buf + Done] := Ino;
      MemL[0:Buf + Done + 8] := F^.Pos;
      MemW[0:Buf + Done + 16] := Rec;
      Mem[0:Buf + Done + 18] := DType;
      For K := 1 To Length(Nm) Do Mem[0:Buf + Done + 18 + K] := Ord(Nm[K]);
    End
    Else
    Begin
      MemL[0:Buf + Done] := Ino;
      MemL[0:Buf + Done + 4] := F^.Pos;
      MemW[0:Buf + Done + 8] := Rec;
      For K := 1 To Length(Nm) Do Mem[0:Buf + Done + 9 + K] := Ord(Nm[K]);
      Mem[0:Buf + Done + Rec - 1] := DType;
    End;
    Done := Done + Rec;
  End;
  DoGetdents := Done;
End;

Function SysGetdents(Fd, Buf, Cnt : LongInt) : LongInt;
Begin
  SysGetdents := DoGetdents(Fd, Buf, Cnt, False);
End;

Function SysGetdents64(Fd, Buf, Cnt : LongInt) : LongInt;
Begin
  SysGetdents64 := DoGetdents(Fd, Buf, Cnt, True);
End;

Function SysGetcwd(Buf, Size : LongInt) : LongInt;
Var S : String;
Begin
  S := DentryPath(Cur^.Fs^.Pwd);
  If Length(S) + 1 > Size Then
  Begin
    SysGetcwd := -ERANGE;
    Exit;
  End;
  If Not EnsureUser(Buf, Length(S) + 1, True) Then
  Begin
    SysGetcwd := -EFAULT;
    Exit;
  End;
  PutPStr(Buf, S, Length(S) + 1);
  SysGetcwd := Length(S) + 1;
End;

Function SysChdir(PathAddr : LongInt) : LongInt;
Var P : String; D : PDentry; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysChdir := R;
    Exit;
  End;
  R := PathWalk(P, True, D);
  If R <> 0 Then
  Begin
    SysChdir := R;
    Exit;
  End;
  If Not IsDir(D^.Inode) Then R := -ENOTDIR
  Else R := InodePerm(D^.Inode, MAY_EXEC);
  If R <> 0 Then
  Begin
    DentryPut(LongInt(D));
    SysChdir := R;
    Exit;
  End;
  DentryPut(LongInt(Cur^.Fs^.Pwd));
  Cur^.Fs^.Pwd := D;
  SysChdir := 0;
End;

Function SysFchdir(Fd : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFchdir := -EBADF;
    Exit;
  End;
  If Not IsDir(F^.Inode) Then
  Begin
    SysFchdir := -ENOTDIR;
    Exit;
  End;
  DentryGet(LongInt(F^.Dentry));
  DentryPut(LongInt(Cur^.Fs^.Pwd));
  Cur^.Fs^.Pwd := F^.Dentry;
  SysFchdir := 0;
End;

Function SysChroot(PathAddr : LongInt) : LongInt;
Var P : String; D : PDentry; R : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysChroot := -EPERM;
    Exit;
  End;
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysChroot := R;
    Exit;
  End;
  R := PathWalk(P, True, D);
  If R <> 0 Then
  Begin
    SysChroot := R;
    Exit;
  End;
  If Not IsDir(D^.Inode) Then
  Begin
    DentryPut(LongInt(D));
    SysChroot := -ENOTDIR;
    Exit;
  End;
  DentryPut(LongInt(Cur^.Fs^.Root));
  Cur^.Fs^.Root := D;
  SysChroot := 0;
End;

Function SysMkdir(PathAddr, Mode : LongInt) : LongInt;
Var P : String; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysMkdir := R;
    Exit;
  End;
  SysMkdir := VfsCreateNode(P, Mode, 0, True);
End;

Function SysMkdirat(Dirfd, PathAddr, Mode : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysMkdirat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysMkdirat := R;
    Exit;
  End;
  SysMkdirat := VfsCreateNode(P, Mode, 0, True);
  AtRestore(Sv);
End;

Function SysRmdir(PathAddr : LongInt) : LongInt;
Var P : String; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysRmdir := R;
    Exit;
  End;
  SysRmdir := VfsUnlink(P, True);
End;

Function SysUnlink(PathAddr : LongInt) : LongInt;
Var P : String; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysUnlink := R;
    Exit;
  End;
  SysUnlink := VfsUnlink(P, False);
End;

Function SysUnlinkat(Dirfd, PathAddr, Flags : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysUnlinkat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysUnlinkat := R;
    Exit;
  End;
  SysUnlinkat := VfsUnlink(P, (Flags And $200) <> 0);
  AtRestore(Sv);
End;

Function SysMknod(PathAddr, Mode, Dev : LongInt) : LongInt;
Var P : String; R : LongInt;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysMknod := R;
    Exit;
  End;
  If ((Mode And S_IFMT) = S_IFCHR) Or ((Mode And S_IFMT) = S_IFBLK) Then
    If Cur^.Euid <> 0 Then
    Begin
      SysMknod := -EPERM;
      Exit;
    End;
  If (Mode And S_IFMT) = S_IFDIR Then
  Begin
    SysMknod := -EPERM;
    Exit;
  End;
  SysMknod := VfsCreateNode(P, Mode, Dev, False);
End;

Function SysMknodat(Dirfd, PathAddr, Mode, Dev : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathAddr, P);
  If R < 0 Then
  Begin
    SysMknodat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysMknodat := R;
    Exit;
  End;
  If ((Mode And S_IFMT) = S_IFCHR) Or ((Mode And S_IFMT) = S_IFBLK) Then
    If Cur^.Euid <> 0 Then R := -EPERM;
  If R = 0 Then R := VfsCreateNode(P, Mode, Dev, False);
  SysMknodat := R;
  AtRestore(Sv);
End;

Function SysRename(OldA, NewA : LongInt) : LongInt;
Var P, Q : String; R : LongInt;
Begin
  R := GetUserStr(OldA, P);
  If R < 0 Then
  Begin
    SysRename := R;
    Exit;
  End;
  R := GetUserStr(NewA, Q);
  If R < 0 Then
  Begin
    SysRename := R;
    Exit;
  End;
  SysRename := VfsRename(P, Q);
End;

Function SysRenameat(Od, OldA, Nd, NewA : LongInt) : LongInt;
Var P, Q : String; R : LongInt;
Begin
  R := GetUserStr(OldA, P);
  If R < 0 Then
  Begin
    SysRenameat := R;
    Exit;
  End;
  R := GetUserStr(NewA, Q);
  If R < 0 Then
  Begin
    SysRenameat := R;
    Exit;
  End;
  If ((Od <> AT_FDCWD) And (Length(P) > 0) And (P[1] <> '/')) Or
     ((Nd <> AT_FDCWD) And (Length(Q) > 0) And (Q[1] <> '/')) Then
  Begin
    SysRenameat := -ENOSYS;
    Exit;
  End;
  SysRenameat := VfsRename(P, Q);
End;

Function SysLink(OldA, NewA : LongInt) : LongInt;
Var P, Q : String; R : LongInt;
Begin
  R := GetUserStr(OldA, P);
  If R < 0 Then
  Begin
    SysLink := R;
    Exit;
  End;
  R := GetUserStr(NewA, Q);
  If R < 0 Then
  Begin
    SysLink := R;
    Exit;
  End;
  SysLink := VfsLink(P, Q);
End;

Function SysLinkat(Od, OldA, Nd, NewA, Flags : LongInt) : LongInt;
Begin
  If (Od <> AT_FDCWD) Or (Nd <> AT_FDCWD) Then SysLinkat := -ENOSYS
  Else SysLinkat := SysLink(OldA, NewA);
End;

Function SysSymlink(TgtA, PathA : LongInt) : LongInt;
Var P, Q : String; R : LongInt;
Begin
  R := GetUserStr(TgtA, P);
  If R < 0 Then
  Begin
    SysSymlink := R;
    Exit;
  End;
  R := GetUserStr(PathA, Q);
  If R < 0 Then
  Begin
    SysSymlink := R;
    Exit;
  End;
  If P = '' Then
  Begin
    SysSymlink := -ENOENT;
    Exit;
  End;
  SysSymlink := VfsSymlink(P, Q);
End;

Function SysSymlinkat(TgtA, Nd, PathA : LongInt) : LongInt;
Begin
  If Nd <> AT_FDCWD Then SysSymlinkat := -ENOSYS
  Else SysSymlinkat := SysSymlink(TgtA, PathA);
End;

Function SysReadlink(PathA, Buf, Size : LongInt) : LongInt;
Var P, T : String; D : PDentry; R, N : LongInt;
Begin
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    SysReadlink := R;
    Exit;
  End;
  If Size <= 0 Then
  Begin
    SysReadlink := -EINVAL;
    Exit;
  End;
  R := PathWalk(P, False, D);
  If R <> 0 Then
  Begin
    SysReadlink := R;
    Exit;
  End;
  If (D^.Inode^.Mode And S_IFMT) <> S_IFLNK Then
  Begin
    DentryPut(LongInt(D));
    SysReadlink := -EINVAL;
    Exit;
  End;
  R := ReadLinkTarget(D^.Inode, T);
  DentryPut(LongInt(D));
  If R <> 0 Then
  Begin
    SysReadlink := R;
    Exit;
  End;
  N := Length(T);
  If N > Size Then N := Size;
  If Not EnsureUser(Buf, N, True) Then
  Begin
    SysReadlink := -EFAULT;
    Exit;
  End;
  MemCopy(Buf, LongInt(@T) + 1, N);
  SysReadlink := N;
End;

Function SysReadlinkat(Dirfd, PathA, Buf, Size : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    SysReadlinkat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysReadlinkat := R;
    Exit;
  End;
  SysReadlinkat := SysReadlink(PathA, Buf, Size);
  AtRestore(Sv);
End;

{ ---- Attributs ---- }

Function PathInode(PathA : LongInt; Follow : Boolean;
    Var D : PDentry) : LongInt;
Var P : String; R : LongInt;
Begin
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    PathInode := R;
    Exit;
  End;
  PathInode := PathWalk(P, Follow, D);
End;

Function SysChmod(PathA, Mode : LongInt) : LongInt;
Var D : PDentry; R : LongInt;
Begin
  R := PathInode(PathA, True, D);
  If R <> 0 Then
  Begin
    SysChmod := R;
    Exit;
  End;
  R := VfsSetAttr(D^.Inode, Mode, -1, -1);
  DentryPut(LongInt(D));
  SysChmod := R;
End;

Function SysFchmod(Fd, Mode : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then SysFchmod := -EBADF
  Else SysFchmod := VfsSetAttr(F^.Inode, Mode, -1, -1);
End;

Function SysFchmodat(Dirfd, PathA, Mode : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    SysFchmodat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysFchmodat := R;
    Exit;
  End;
  SysFchmodat := SysChmod(PathA, Mode);
  AtRestore(Sv);
End;

Function DoChown(PathA, Uid, Gid : LongInt; Follow : Boolean) : LongInt;
Var D : PDentry; R : LongInt;
Begin
  R := PathInode(PathA, Follow, D);
  If R <> 0 Then
  Begin
    DoChown := R;
    Exit;
  End;
  R := VfsSetAttr(D^.Inode, -1, Uid, Gid);
  DentryPut(LongInt(D));
  DoChown := R;
End;

Function SysChown(PathA, Uid, Gid : LongInt) : LongInt;
Begin
  SysChown := DoChown(PathA, Id16(Uid), Id16(Gid), True);
End;

Function SysLchown(PathA, Uid, Gid : LongInt) : LongInt;
Begin
  SysLchown := DoChown(PathA, Id16(Uid), Id16(Gid), False);
End;

Function SysChown32(PathA, Uid, Gid : LongInt) : LongInt;
Begin
  SysChown32 := DoChown(PathA, Uid, Gid, True);
End;

Function SysLchown32(PathA, Uid, Gid : LongInt) : LongInt;
Begin
  SysLchown32 := DoChown(PathA, Uid, Gid, False);
End;

Function SysFchown(Fd, Uid, Gid : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then SysFchown := -EBADF
  Else SysFchown := VfsSetAttr(F^.Inode, -1, Id16(Uid), Id16(Gid));
End;

Function SysFchown32(Fd, Uid, Gid : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then SysFchown32 := -EBADF
  Else SysFchown32 := VfsSetAttr(F^.Inode, -1, Uid, Gid);
End;

Function SysFchownat(Dirfd, PathA, Uid, Gid, Flags : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    SysFchownat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysFchownat := R;
    Exit;
  End;
  SysFchownat := DoChown(PathA, Uid, Gid, (Flags And $100) = 0);
  AtRestore(Sv);
End;

Function SysUmask(M : LongInt) : LongInt;
Begin
  SysUmask := Cur^.Fs^.Umask;
  Cur^.Fs^.Umask := M And $1FF;
End;

Function SysTruncate(PathA, Len : LongInt) : LongInt;
Var D : PDentry; R : LongInt;
Begin
  R := PathInode(PathA, True, D);
  If R <> 0 Then
  Begin
    SysTruncate := R;
    Exit;
  End;
  R := InodePerm(D^.Inode, MAY_WRITE);
  If R = 0 Then R := VfsTruncateInode(D^.Inode, Len);
  DentryPut(LongInt(D));
  SysTruncate := R;
End;

Function SysTruncate64(PathA, Lo, Hi : LongInt) : LongInt;
Begin
  If Hi <> 0 Then SysTruncate64 := -EFBIG
      Else SysTruncate64 := SysTruncate(PathA, Lo);
End;

Function SysFtruncate(Fd, Len : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFtruncate := -EBADF;
    Exit;
  End;
  If (F^.Flags And O_ACCMODE) = O_RDONLY Then
  Begin
    SysFtruncate := -EINVAL;
    Exit;
  End;
  SysFtruncate := VfsTruncateInode(F^.Inode, Len);
End;

Function SysFtruncate64(Fd, Lo, Hi : LongInt) : LongInt;
Begin
  If Hi <> 0 Then SysFtruncate64 := -EFBIG
      Else SysFtruncate64 := SysFtruncate(Fd, Lo);
End;

Function SysAccess(PathA, Mode : LongInt) : LongInt;
Var D : PDentry; R, Fu, Fg : LongInt; M : LongInt;
Begin
  R := PathInode(PathA, True, D);
  If R <> 0 Then
  Begin
    SysAccess := R;
    Exit;
  End;
  Fu := Cur^.Fsuid; Fg := Cur^.Fsgid;
  Cur^.Fsuid := Cur^.Uid; Cur^.Fsgid := Cur^.Gid;
  M := Mode And 7;
  R := 0;
  If M <> 0 Then R := InodePerm(D^.Inode, M);
  If (R = 0) And ((M And 2) <> 0) And ((D^.Sb^.Flags And MS_RDONLY) <> 0) And
     ((D^.Inode^.Mode And S_IFMT) = S_IFREG) Then R := -EROFS;
  Cur^.Fsuid := Fu; Cur^.Fsgid := Fg;
  DentryPut(LongInt(D));
  SysAccess := R;
End;

Function SysFaccessat(Dirfd, PathA, Mode : LongInt) : LongInt;
Var P : String; R : LongInt; Sv : PDentry;
Begin
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    SysFaccessat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysFaccessat := R;
    Exit;
  End;
  SysFaccessat := SysAccess(PathA, Mode);
  AtRestore(Sv);
End;

Function DoUtime(PathA, At, Mt : LongInt; Use : Boolean) : LongInt;
Var D : PDentry; R : LongInt;
Begin
  R := PathInode(PathA, True, D);
  If R <> 0 Then
  Begin
    DoUtime := R;
    Exit;
  End;
  If Cur^.Fsuid <> 0 Then
    If Cur^.Fsuid <> D^.Inode^.Uid Then
    Begin
      If Use Then R := -EPERM Else R := InodePerm(D^.Inode, MAY_WRITE);
    End;
  If R = 0 Then
  Begin
    If Use Then
    Begin
      D^.Inode^.Atime := At; D^.Inode^.Mtime := Mt;
    End
    Else
    Begin
      D^.Inode^.Atime := NowSec; D^.Inode^.Mtime := NowSec;
    End;
    D^.Inode^.Ctime := NowSec;
    R := VfsSetAttr(D^.Inode, -1, -1, -1);
  End;
  DentryPut(LongInt(D));
  DoUtime := R;
End;

Function SysUtime(PathA, Buf : LongInt) : LongInt;
Begin
  If Buf = 0 Then SysUtime := DoUtime(PathA, 0, 0, False)
  Else If Not EnsureUser(Buf, 8, False) Then SysUtime := -EFAULT
  Else SysUtime := DoUtime(PathA, MemL[0:Buf], MemL[0:Buf + 4], True);
End;

Function SysUtimes(PathA, Buf : LongInt) : LongInt;
Begin
  If Buf = 0 Then SysUtimes := DoUtime(PathA, 0, 0, False)
  Else If Not EnsureUser(Buf, 16, False) Then SysUtimes := -EFAULT
  Else SysUtimes := DoUtime(PathA, MemL[0:Buf], MemL[0:Buf + 8], True);
End;

{ utimensat : times = 2 timespec (UTIME_NOW 3FFFFFFFh, UTIME_OMIT 3FFFFFFEh) }
Function SysUtimensat(Dirfd, PathA, Times, Flags : LongInt) : LongInt;
Var P : String; R, At, Mt : LongInt; Sv : PDentry; D : PDentry; I : PInode;
Begin
  If PathA = 0 Then
  Begin
    SysUtimensat := -EINVAL;
    Exit;
  End;
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    SysUtimensat := R;
    Exit;
  End;
  R := AtEnter(Dirfd, P, Sv);
  If R < 0 Then
  Begin
    SysUtimensat := R;
    Exit;
  End;
  R := PathWalk(P, (Flags And $100) = 0, D);
  If R = 0 Then
  Begin
    I := D^.Inode;
    At := NowSec; Mt := At;
    If Times <> 0 Then
      If EnsureUser(Times, 16, False) Then
      Begin
        If MemL[0:Times + 4] <> $3FFFFFFF Then At := MemL[0:Times];
        If MemL[0:Times + 4] = $3FFFFFFE Then At := I^.Atime;
        If MemL[0:Times + 12] <> $3FFFFFFF Then Mt := MemL[0:Times + 8];
        If MemL[0:Times + 12] = $3FFFFFFE Then Mt := I^.Mtime;
      End
      Else R := -EFAULT;
    If (R = 0) And (Cur^.Fsuid <> 0) And (Cur^.Fsuid <> I^.Uid) And (Times
        <> 0) Then R := -EPERM;
    If R = 0 Then
    Begin
      I^.Atime := At; I^.Mtime := Mt; I^.Ctime := NowSec;
      R := VfsSetAttr(I, -1, -1, -1);
    End;
    DentryPut(LongInt(D));
  End;
  AtRestore(Sv);
  SysUtimensat := R;
End;

Function SysFsync(Fd : LongInt) : LongInt;
Var F : PFile;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    SysFsync := -EBADF;
    Exit;
  End;
  BSync(0);
  SysFsync := 0;
End;

Function SysSync : LongInt;
Begin
  VfsSyncAll;
  SysSync := 0;
End;

Function SysMount(DevA, DirA, TypeA, Flags, Data : LongInt) : LongInt;
Var Dv, Dr, Tp : String; R : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysMount := -EPERM;
    Exit;
  End;
  If (Flags And LongInt($FFFF0000)) = LongInt($C0ED0000) Then
    Flags := Flags And $FFFF;
  Dv := '';
  If DevA <> 0 Then
  Begin
    R := GetUserStr(DevA, Dv);
    If R < 0 Then
    Begin
      SysMount := R;
      Exit;
    End;
  End;
  R := GetUserStr(DirA, Dr);
  If R < 0 Then
  Begin
    SysMount := R;
    Exit;
  End;
  If (Flags And MS_REMOUNT) <> 0 Then
  Begin
    SysMount := VfsRemount(Dr, Flags);
    Exit;
  End;
  If (Flags And MS_BIND) <> 0 Then
  Begin
    SysMount := VfsBind(Dv, Dr);
    Exit;
  End;
  If (Flags And 8192) <> 0 Then
  Begin
    SysMount := VfsMoveMount(Dv, Dr);
    Exit;
  End;
  If TypeA = 0 Then
  Begin
    SysMount := -EINVAL;
    Exit;
  End;
  R := GetUserStr(TypeA, Tp);
  If R < 0 Then
  Begin
    SysMount := R;
    Exit;
  End;
  SysMount := VfsMount(Dv, Dr, Tp, Flags And $FFFF, Data);
End;

Function SysUmount2(PathA, Flags : LongInt) : LongInt;
Var P : String; R : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysUmount2 := -EPERM;
    Exit;
  End;
  R := GetUserStr(PathA, P);
  If R < 0 Then
  Begin
    SysUmount2 := R;
    Exit;
  End;
  SysUmount2 := VfsUmount(P, Flags);
End;

Function SysPivotRoot(NewA, OldA : LongInt) : LongInt;
Var Np, Op : String; R : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysPivotRoot := -EPERM;
    Exit;
  End;
  R := GetUserStr(NewA, Np);
  If R < 0 Then
  Begin
    SysPivotRoot := R;
    Exit;
  End;
  R := GetUserStr(OldA, Op);
  If R < 0 Then
  Begin
    SysPivotRoot := R;
    Exit;
  End;
  SysPivotRoot := VfsPivotRoot(Np, Op);
End;

Function SysUmount(PathA : LongInt) : LongInt;
Begin
  SysUmount := SysUmount2(PathA, 0);
End;

{ ---- Processus, identifiants, groupes, sessions ---- }

Function SysExit(Code : LongInt) : LongInt;
Begin
  DoExit((Code And $FF) Shl 8);
  SysExit := 0;
End;

{ exit_group : termine tous les fils du groupe puis le processus }
Function SysExitGroup(Code : LongInt) : LongInt;
Var I : LongInt;
Begin
  For I := 1 To MaxTasks - 1 Do
    If (Tasks[I].State <> TsFree) And (Tasks[I].Tgid = Cur^.Tgid)
        And (@Tasks[I] <> Cur) And
       (Tasks[I].State <> TsZombie) Then
      SendSig(@Tasks[I], SIGKILL);
  DoExit((Code And $FF) Shl 8);
  SysExitGroup := 0;
End;

Function SysFork : LongInt;
Begin
  SysFork := DoClone(SIGCHLD, 0, Pointer(Cur^.Frame));
End;

Function SysVfork : LongInt;
Begin
  SysVfork := DoClone(SIGCHLD Or CLONE_VFORK Or CLONE_VM, 0,
      Pointer(Cur^.Frame));
End;

{ clone(flags, newsp, parent_tidptr, tls, child_tidptr) }
Function SysClone(Flags, NewSp, PTid, Tls, CTid : LongInt) : LongInt;
Var R, I : LongInt; Fr : PFrame;
Begin
  If ((Flags And CLONE_THREAD) <> 0) And ((Flags And (CLONE_VM
      Or CLONE_SIGHAND)) <> (CLONE_VM Or CLONE_SIGHAND)) Then
  Begin
    SysClone := -EINVAL;
    Exit;
  End;
  If (Flags And CLONE_SETTLS) <> 0 Then
  Begin
    If Not EnsureUser(Tls, 16, False) Then
    Begin
      SysClone := -EFAULT;
      Exit;
    End;
  End;
  R := DoClone(Flags, NewSp, Pointer(Cur^.Frame));
  If R > 0 Then
  Begin
    If (Flags And CLONE_PARENT_SETTID) <> 0 Then PutUserL(PTid, R);
    If (Flags And (CLONE_CHILD_SETTID Or CLONE_CHILD_CLEARTID)) <> 0 Then
      For I := 1 To MaxTasks - 1 Do
        If (Tasks[I].State <> TsFree) And (Tasks[I].Pid = R) Then
        Begin
          If (Flags And CLONE_CHILD_CLEARTID) <> 0
              Then Tasks[I].ClearTid := CTid;
        End;
  End;
  Fr := Nil;
  SysClone := R;
End;

Function SysExecve(PathA, Argv, Envp : LongInt) : LongInt;
Begin
  SysExecve := DoExecve(PathA, Argv, Envp);
End;

Function SysWaitpid(Pid, Status, Options : LongInt) : LongInt;
Begin
  SysWaitpid := DoWait4(Pid, Status, Options, 0);
End;

Function SysWait4(Pid, Status, Options, Ru : LongInt) : LongInt;
Begin
  SysWait4 := DoWait4(Pid, Status, Options, Ru);
End;

Function SysGetpid : LongInt;
Begin
  SysGetpid := Cur^.Tgid;
End;

Function SysGettid : LongInt;
Begin
  SysGettid := Cur^.Pid;
End;

Function SysGetppid : LongInt;
Begin
  If Cur^.Parent = Nil Then SysGetppid := 0
      Else SysGetppid := Cur^.Parent^.Tgid;
End;

Function SysGetuid : LongInt;
Begin
  SysGetuid := Cur^.Uid And $FFFF;
End;
Function SysGeteuid : LongInt;
Begin
  SysGeteuid := Cur^.Euid And $FFFF;
End;
Function SysGetgid : LongInt;
Begin
  SysGetgid := Cur^.Gid And $FFFF;
End;
Function SysGetegid : LongInt;
Begin
  SysGetegid := Cur^.Egid And $FFFF;
End;
Function SysGetuid32 : LongInt;
Begin
  SysGetuid32 := Cur^.Uid;
End;
Function SysGeteuid32 : LongInt;
Begin
  SysGeteuid32 := Cur^.Euid;
End;
Function SysGetgid32 : LongInt;
Begin
  SysGetgid32 := Cur^.Gid;
End;
Function SysGetegid32 : LongInt;
Begin
  SysGetegid32 := Cur^.Egid;
End;

Function DoSetuid(Uid : LongInt) : LongInt;
Begin
  DoSetuid := 0;
  If Uid < 0 Then
  Begin
    DoSetuid := -EINVAL;
    Exit;
  End;
  If Cur^.Euid = 0 Then
  Begin
    Cur^.Uid := Uid; Cur^.Euid := Uid; Cur^.Suid := Uid; Cur^.Fsuid := Uid;
  End
  Else If (Uid = Cur^.Uid) Or (Uid = Cur^.Suid) Then
  Begin
    Cur^.Euid := Uid; Cur^.Fsuid := Uid;
  End
  Else DoSetuid := -EPERM;
End;

Function DoSetgid(Gid : LongInt) : LongInt;
Begin
  DoSetgid := 0;
  If Gid < 0 Then
  Begin
    DoSetgid := -EINVAL;
    Exit;
  End;
  If Cur^.Euid = 0 Then
  Begin
    Cur^.Gid := Gid; Cur^.Egid := Gid; Cur^.Sgid := Gid; Cur^.Fsgid := Gid;
  End
  Else If (Gid = Cur^.Gid) Or (Gid = Cur^.Sgid) Then
  Begin
    Cur^.Egid := Gid; Cur^.Fsgid := Gid;
  End
  Else DoSetgid := -EPERM;
End;

Function SysSetuid(U : LongInt) : LongInt;
Begin
  SysSetuid := DoSetuid(Id16(U));
End;
Function SysSetgid(G : LongInt) : LongInt;
Begin
  SysSetgid := DoSetgid(Id16(G));
End;
Function SysSetuid32(U : LongInt) : LongInt;
Begin
  SysSetuid32 := DoSetuid(U);
End;
Function SysSetgid32(G : LongInt) : LongInt;
Begin
  SysSetgid32 := DoSetgid(G);
End;

Function DoSetresuid(R, E, S : LongInt) : LongInt;
Begin
  DoSetresuid := 0;
  If Cur^.Euid <> 0 Then
  Begin
    If (R <> -1) And (R <> Cur^.Uid) And (R <> Cur^.Euid) And (R <> Cur^.Suid)
        Then DoSetresuid := -EPERM;
    If (E <> -1) And (E <> Cur^.Uid) And (E <> Cur^.Euid) And (E <> Cur^.Suid)
        Then DoSetresuid := -EPERM;
    If (S <> -1) And (S <> Cur^.Uid) And (S <> Cur^.Euid) And (S <> Cur^.Suid)
        Then DoSetresuid := -EPERM;
    If DoSetresuid <> 0 Then Exit;
  End;
  If R <> -1 Then Cur^.Uid := R;
  If E <> -1 Then
  Begin
    Cur^.Euid := E; Cur^.Fsuid := E;
  End;
  If S <> -1 Then Cur^.Suid := S;
End;

Function DoSetresgid(R, E, S : LongInt) : LongInt;
Begin
  DoSetresgid := 0;
  If Cur^.Euid <> 0 Then
  Begin
    If (R <> -1) And (R <> Cur^.Gid) And (R <> Cur^.Egid) And (R <> Cur^.Sgid)
        Then DoSetresgid := -EPERM;
    If (E <> -1) And (E <> Cur^.Gid) And (E <> Cur^.Egid) And (E <> Cur^.Sgid)
        Then DoSetresgid := -EPERM;
    If (S <> -1) And (S <> Cur^.Gid) And (S <> Cur^.Egid) And (S <> Cur^.Sgid)
        Then DoSetresgid := -EPERM;
    If DoSetresgid <> 0 Then Exit;
  End;
  If R <> -1 Then Cur^.Gid := R;
  If E <> -1 Then
  Begin
    Cur^.Egid := E; Cur^.Fsgid := E;
  End;
  If S <> -1 Then Cur^.Sgid := S;
End;

Function SysSetresuid(R, E, S : LongInt) : LongInt;
Begin
  SysSetresuid := DoSetresuid(Id16(R), Id16(E), Id16(S));
End;
Function SysSetresgid(R, E, S : LongInt) : LongInt;
Begin
  SysSetresgid := DoSetresgid(Id16(R), Id16(E), Id16(S));
End;
Function SysSetresuid32(R, E, S : LongInt) : LongInt;
Begin
  SysSetresuid32 := DoSetresuid(R, E, S);
End;
Function SysSetresgid32(R, E, S : LongInt) : LongInt;
Begin
  SysSetresgid32 := DoSetresgid(R, E, S);
End;

Function SysSetreuid(R, E : LongInt) : LongInt;
Begin
  R := Id16(R); E := Id16(E);
  If E = -1 Then E := -1;
  SysSetreuid := DoSetresuid(R, E, -1);
  If (SysSetreuid = 0) And ((R <> -1) Or ((E <> -1) And (E <> Cur^.Uid)))
      Then Cur^.Suid := Cur^.Euid;
End;
Function SysSetregid(R, E : LongInt) : LongInt;
Begin
  R := Id16(R); E := Id16(E);
  SysSetregid := DoSetresgid(R, E, -1);
  If (SysSetregid = 0) And ((R <> -1) Or ((E <> -1) And (E <> Cur^.Gid)))
      Then Cur^.Sgid := Cur^.Egid;
End;
Function SysSetreuid32(R, E : LongInt) : LongInt;
Begin
  SysSetreuid32 := DoSetresuid(R, E, -1);
  If (SysSetreuid32 = 0) And ((R <> -1) Or ((E <> -1) And (E <> Cur^.Uid)))
      Then Cur^.Suid := Cur^.Euid;
End;
Function SysSetregid32(R, E : LongInt) : LongInt;
Begin
  SysSetregid32 := DoSetresgid(R, E, -1);
  If (SysSetregid32 = 0) And ((R <> -1) Or ((E <> -1) And (E <> Cur^.Gid)))
      Then Cur^.Sgid := Cur^.Egid;
End;

Function SysSetfsuid(U : LongInt) : LongInt;
Var Old : LongInt;
Begin
  Old := Cur^.Fsuid;
  If (U = Cur^.Uid) Or (U = Cur^.Euid) Or (U = Cur^.Suid) Or (U = Cur^.Fsuid)
      Or (Cur^.Euid = 0) Then
    Cur^.Fsuid := U;
  SysSetfsuid := Old;
End;
Function SysSetfsgid(G : LongInt) : LongInt;
Var Old : LongInt;
Begin
  Old := Cur^.Fsgid;
  If (G = Cur^.Gid) Or (G = Cur^.Egid) Or (G = Cur^.Sgid) Or (G = Cur^.Fsgid)
      Or (Cur^.Euid = 0) Then
    Cur^.Fsgid := G;
  SysSetfsgid := Old;
End;

Function SysGetresuid(R, E, S : LongInt) : LongInt;
Begin
  If (PutUserL(R, Cur^.Uid) < 0) Or (PutUserL(E, Cur^.Euid) < 0)
      Or (PutUserL(S, Cur^.Suid) < 0) Then SysGetresuid := -EFAULT
  Else SysGetresuid := 0;
End;
Function SysGetresgid(R, E, S : LongInt) : LongInt;
Begin
  If (PutUserL(R, Cur^.Gid) < 0) Or (PutUserL(E, Cur^.Egid) < 0)
      Or (PutUserL(S, Cur^.Sgid) < 0) Then SysGetresgid := -EFAULT
  Else SysGetresgid := 0;
End;

Function SysGetgroups32(N, List : LongInt) : LongInt;
Var I : LongInt;
Begin
  If N = 0 Then
  Begin
    SysGetgroups32 := Cur^.NGroups;
    Exit;
  End;
  If N < Cur^.NGroups Then
  Begin
    SysGetgroups32 := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(List, Cur^.NGroups * 4, True) Then
  Begin
    SysGetgroups32 := -EFAULT;
    Exit;
  End;
  For I := 0 To Cur^.NGroups - 1 Do MemL[0:List + I * 4] := Cur^.Groups[I];
  SysGetgroups32 := Cur^.NGroups;
End;

Function SysGetgroups(N, List : LongInt) : LongInt;
Var I : LongInt;
Begin
  If N = 0 Then
  Begin
    SysGetgroups := Cur^.NGroups;
    Exit;
  End;
  If N < Cur^.NGroups Then
  Begin
    SysGetgroups := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(List, Cur^.NGroups * 2, True) Then
  Begin
    SysGetgroups := -EFAULT;
    Exit;
  End;
  For I := 0 To Cur^.NGroups - 1 Do MemW[0:List + I * 2] := Cur^.Groups[I];
  SysGetgroups := Cur^.NGroups;
End;

Function SysSetgroups32(N, List : LongInt) : LongInt;
Var I : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysSetgroups32 := -EPERM;
    Exit;
  End;
  If (N < 0) Or (N > 16) Then
  Begin
    SysSetgroups32 := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(List, N * 4, False) Then
  Begin
    SysSetgroups32 := -EFAULT;
    Exit;
  End;
  For I := 0 To N - 1 Do Cur^.Groups[I] := MemL[0:List + I * 4];
  Cur^.NGroups := N;
  SysSetgroups32 := 0;
End;

Function SysSetgroups(N, List : LongInt) : LongInt;
Var I : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysSetgroups := -EPERM;
    Exit;
  End;
  If (N < 0) Or (N > 16) Then
  Begin
    SysSetgroups := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(List, N * 2, False) Then
  Begin
    SysSetgroups := -EFAULT;
    Exit;
  End;
  For I := 0 To N - 1 Do Cur^.Groups[I] := MemW[0:List + I * 2];
  Cur^.NGroups := N;
  SysSetgroups := 0;
End;

Function SysSetpgid(Pid, Pgid : LongInt) : LongInt;
Var T : PTask; I : LongInt; Ok : Boolean;
Begin
  If Pid = 0 Then Pid := Cur^.Pid;
  If Pgid = 0 Then Pgid := Pid;
  If Pgid < 0 Then
  Begin
    SysSetpgid := -EINVAL;
    Exit;
  End;
  T := PidTask(Pid);
  If T = Nil Then
  Begin
    SysSetpgid := -ESRCH;
    Exit;
  End;
  If (T <> Cur) And (T^.Parent <> Cur) Then
  Begin
    SysSetpgid := -ESRCH;
    Exit;
  End;
  If T^.Sid <> Cur^.Sid Then
  Begin
    SysSetpgid := -EPERM;
    Exit;
  End;
  If T^.Sid = T^.Pid Then
  Begin
    SysSetpgid := -EPERM;
    Exit;
  End;
  If Pgid <> T^.Pid Then
  Begin
    Ok := False;
    For I := 1 To MaxTasks - 1 Do
      If (Tasks[I].State <> TsFree) And (Tasks[I].Pgid = Pgid)
          And (Tasks[I].Sid = Cur^.Sid) Then Ok := True;
    If Not Ok Then
    Begin
      SysSetpgid := -EPERM;
      Exit;
    End;
  End;
  T^.Pgid := Pgid;
  SysSetpgid := 0;
End;

Function SysGetpgid(Pid : LongInt) : LongInt;
Var T : PTask;
Begin
  If Pid = 0 Then T := Cur Else T := PidTask(Pid);
  If T = Nil Then SysGetpgid := -ESRCH Else SysGetpgid := T^.Pgid;
End;

Function SysGetpgrp : LongInt;
Begin
  SysGetpgrp := Cur^.Pgid;
End;

Function SysGetsid(Pid : LongInt) : LongInt;
Var T : PTask;
Begin
  If Pid = 0 Then T := Cur Else T := PidTask(Pid);
  If T = Nil Then SysGetsid := -ESRCH Else SysGetsid := T^.Sid;
End;

Function SysSetsid : LongInt;
Var I : LongInt;
Begin
  For I := 1 To MaxTasks - 1 Do
    If (Tasks[I].State <> TsFree) And (Tasks[I].Pgid = Cur^.Pid) And (@Tasks[I]
        <> Cur) Then
    Begin
      SysSetsid := -EPERM;
      Exit;
    End;
  If Cur^.Pgid = Cur^.Pid Then
    If Cur^.Sid = Cur^.Pid Then
    Begin
      SysSetsid := -EPERM;
      Exit;
    End;
  Cur^.Sid := Cur^.Pid;
  Cur^.Pgid := Cur^.Pid;
  Cur^.Tty := -1;
  SysSetsid := Cur^.Pid;
End;

Function SysNice(Inc : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := Cur^.Nice + Inc;
  If N < -20 Then N := -20;
  If N > 19 Then N := 19;
  If (N < Cur^.Nice) And (Cur^.Euid <> 0) Then
  Begin
    SysNice := -EPERM;
    Exit;
  End;
  Cur^.Nice := N;
  SysNice := 0;
End;

Function SysGetpriority(Which, Who : LongInt) : LongInt;
Var T : PTask;
Begin
  If Who = 0 Then T := Cur Else T := PidTask(Who);
  If T = Nil Then SysGetpriority := -ESRCH Else SysGetpriority := 20 - T^.Nice;
End;

Function SysSetpriority(Which, Who, Prio : LongInt) : LongInt;
Var T : PTask;
Begin
  If Who = 0 Then T := Cur Else T := PidTask(Who);
  If T = Nil Then
  Begin
    SysSetpriority := -ESRCH;
    Exit;
  End;
  If Prio < -20 Then Prio := -20;
  If Prio > 19 Then Prio := 19;
  If (Cur^.Euid <> 0) And ((Prio < T^.Nice) Or ((T^.Euid <> Cur^.Euid)
      And (T^.Uid <> Cur^.Euid))) Then
  Begin
    SysSetpriority := -EPERM;
    Exit;
  End;
  T^.Nice := Prio;
  SysSetpriority := 0;
End;

Function SysSchedYield : LongInt;
Begin
  Yield;
  SysSchedYield := 0;
End;

Function SysSchedPrio(Policy : LongInt) : LongInt;
Begin
  If (Policy = 1) Or (Policy = 2) Then SysSchedPrio := 99
      Else SysSchedPrio := 0;
End;

Function SysSchedMinPrio(Policy : LongInt) : LongInt;
Begin
  If (Policy = 1) Or (Policy = 2) Then SysSchedMinPrio := 1
      Else SysSchedMinPrio := 0;
End;

{ ---- Signaux (appels) ---- }

Function SysKill(Pid, Sig : LongInt) : LongInt;
Var I, N : LongInt; T : PTask;

  Function Allowed(T : PTask) : Boolean;
  Begin
    Allowed := (Cur^.Euid = 0) Or (Cur^.Euid = T^.Uid) Or (Cur^.Euid
        = T^.Suid) Or
               (Cur^.Uid = T^.Uid) Or (Cur^.Uid = T^.Suid);
  End;

Begin
  If (Sig < 0) Or (Sig > 64) Then
  Begin
    SysKill := -EINVAL;
    Exit;
  End;
  N := 0;
  If Pid > 0 Then
  Begin
    T := Nil;
    For I := 1 To MaxTasks - 1 Do
      If (Tasks[I].State <> TsFree) And (Tasks[I].Tgid = Pid)
          And (Tasks[I].Tgid = Tasks[I].Pid) Then T := @Tasks[I];
    If T = Nil Then T := PidTask(Pid);
    If T = Nil Then
    Begin
      SysKill := -ESRCH;
      Exit;
    End;
    If Not Allowed(T) Then
    Begin
      SysKill := -EPERM;
      Exit;
    End;
    If Sig <> 0 Then SendSig(T, Sig);
    SysKill := 0;
    Exit;
  End;
  For I := 1 To MaxTasks - 1 Do
  Begin
    T := @Tasks[I];
    If (T^.State <> TsFree) And (T^.State <> TsZombie) Then
    Begin
      If ((Pid = 0) And (T^.Pgid = Cur^.Pgid)) Or ((Pid < -1) And (T^.Pgid
          = -Pid)) Or
         ((Pid = -1) And (T^.Pid > 1) And (T <> Cur)) Then
        If Allowed(T) Then
        Begin
          If Sig <> 0 Then SendSig(T, Sig);
          Inc(N);
        End;
    End;
  End;
  If N = 0 Then SysKill := -ESRCH Else SysKill := 0;
End;

Function SysTkill(Tid, Sig : LongInt) : LongInt;
Var T : PTask;
Begin
  T := PidTask(Tid);
  If T = Nil Then
  Begin
    SysTkill := -ESRCH;
    Exit;
  End;
  If (Sig < 0) Or (Sig > 64) Then
  Begin
    SysTkill := -EINVAL;
    Exit;
  End;
  If Sig <> 0 Then SendSig(T, Sig);
  SysTkill := 0;
End;

Function SysTgkill(Tgid, Tid, Sig : LongInt) : LongInt;
Begin
  SysTgkill := SysTkill(Tid, Sig);
End;

{ sigaction : Act/Oact pointent vers (handler, flags, restorer, mask) }
Function DoSigaction(Sig, Act, Oact : LongInt; Rt : Boolean) : LongInt;
Var Sg : PSigHand; H, Fl, Rs, Mlo, Mhi : LongInt;
Begin
  If (Sig < 1) Or (Sig > 64) Then
  Begin
    DoSigaction := -EINVAL;
    Exit;
  End;
  Sg := Cur^.Sig;
  If Oact <> 0 Then
  Begin
    If Not EnsureUser(Oact, 20, True) Then
    Begin
      DoSigaction := -EFAULT;
      Exit;
    End;
    If Rt Then
    Begin
      MemL[0:Oact] := Sg^.Handler[Sig]; MemL[0:Oact + 4] := Sg^.Flags[Sig];
      MemL[0:Oact + 8] := Sg^.Restorer[Sig];
      MemL[0:Oact + 12] := Sg^.MaskLo[Sig]; MemL[0:Oact
          + 16] := Sg^.MaskHi[Sig];
    End
    Else
    Begin
      MemL[0:Oact] := Sg^.Handler[Sig]; MemL[0:Oact + 4] := Sg^.MaskLo[Sig];
      MemL[0:Oact + 8] := Sg^.Flags[Sig]; MemL[0:Oact
          + 12] := Sg^.Restorer[Sig];
    End;
  End;
  If Act <> 0 Then
  Begin
    If (Sig = SIGKILL) Or (Sig = SIGSTOP) Then
    Begin
      DoSigaction := -EINVAL;
      Exit;
    End;
    If Not EnsureUser(Act, 20, False) Then
    Begin
      DoSigaction := -EFAULT;
      Exit;
    End;
    If Rt Then
    Begin
      H := MemL[0:Act]; Fl := MemL[0:Act + 4]; Rs := MemL[0:Act + 8];
      Mlo := MemL[0:Act + 12]; Mhi := MemL[0:Act + 16];
    End
    Else
    Begin
      H := MemL[0:Act]; Mlo := MemL[0:Act + 4]; Fl := MemL[0:Act + 8];
      Rs := MemL[0:Act + 12]; Mhi := 0;
    End;
    Sg^.Handler[Sig] := H; Sg^.Flags[Sig] := Fl; Sg^.Restorer[Sig] := Rs;
    Sg^.MaskLo[Sig] := Mlo And Not UnblockableLo; Sg^.MaskHi[Sig] := Mhi;
    If (H = SIG_IGN) Or ((H = SIG_DFL) And (DefaultAction(Sig) = 0) And (Sig
        <> SIGCONT)) Then
    Begin
      { jeter les signaux en attente ignores }
      Cur^.Pend[0] := Cur^.Pend[0] And Not SigLoBit(Sig);
      Cur^.Pend[1] := Cur^.Pend[1] And Not SigHiBit(Sig);
    End;
  End;
  DoSigaction := 0;
End;

Function SysSigaction(Sig, Act, Oact : LongInt) : LongInt;
Begin
  SysSigaction := DoSigaction(Sig, Act, Oact, False);
End;

Function SysRtSigaction(Sig, Act, Oact, Sz : LongInt) : LongInt;
Begin
  If Sz <> 8 Then SysRtSigaction := -EINVAL
  Else SysRtSigaction := DoSigaction(Sig, Act, Oact, True);
End;

Function SysSignal(Sig, H : LongInt) : LongInt;
Var Sg : PSigHand; Old : LongInt;
Begin
  If (Sig < 1) Or (Sig > 64) Or (Sig = SIGKILL) Or (Sig = SIGSTOP) Then
  Begin
    SysSignal := -EINVAL;
    Exit;
  End;
  Sg := Cur^.Sig;
  Old := Sg^.Handler[Sig];
  Sg^.Handler[Sig] := H;
  Sg^.Flags[Sig] := SA_RESETHAND Or SA_NODEFER;
  Sg^.MaskLo[Sig] := 0; Sg^.MaskHi[Sig] := 0;
  If H = SIG_IGN Then Cur^.Pend[0] := Cur^.Pend[0] And Not SigLoBit(Sig);
  SysSignal := Old;
End;

{ Modifier le masque : How = 0 bloquer, 1 debloquer, 2 remplacer }
Function ApplyMask(How, Lo, Hi : LongInt) : LongInt;
Begin
  ApplyMask := 0;
  Case How Of
    0 : Begin Cur^.Blk[0] := Cur^.Blk[0] Or Lo; Cur^.Blk[1] := Cur^.Blk[1]
        Or Hi; End;
    1 : Begin Cur^.Blk[0] := Cur^.Blk[0] And Not Lo; Cur^.Blk[1] := Cur^.Blk[1]
        And Not Hi; End;
    2 : Begin Cur^.Blk[0] := Lo; Cur^.Blk[1] := Hi; End;
  Else
    ApplyMask := -EINVAL;
  End;
  Cur^.Blk[0] := Cur^.Blk[0] And Not UnblockableLo;
End;

Function SysSigprocmask(How, Set_, Old : LongInt) : LongInt;
Var Lo : LongInt;
Begin
  If Old <> 0 Then
    If PutUserL(Old, Cur^.Blk[0]) < 0 Then
    Begin
      SysSigprocmask := -EFAULT;
      Exit;
    End;
  If Set_ <> 0 Then
  Begin
    If GetUserL(Set_, Lo) < 0 Then
    Begin
      SysSigprocmask := -EFAULT;
      Exit;
    End;
    SysSigprocmask := ApplyMask(How, Lo, 0);
    Exit;
  End;
  SysSigprocmask := 0;
End;

Function SysRtSigprocmask(How, Set_, Old, Sz : LongInt) : LongInt;
Var Lo, Hi : LongInt;
Begin
  If Sz <> 8 Then
  Begin
    SysRtSigprocmask := -EINVAL;
    Exit;
  End;
  If Old <> 0 Then
  Begin
    If Not EnsureUser(Old, 8, True) Then
    Begin
      SysRtSigprocmask := -EFAULT;
      Exit;
    End;
    MemL[0:Old] := Cur^.Blk[0]; MemL[0:Old + 4] := Cur^.Blk[1];
  End;
  If Set_ <> 0 Then
  Begin
    If Not EnsureUser(Set_, 8, False) Then
    Begin
      SysRtSigprocmask := -EFAULT;
      Exit;
    End;
    Lo := MemL[0:Set_]; Hi := MemL[0:Set_ + 4];
    SysRtSigprocmask := ApplyMask(How, Lo, Hi);
    Exit;
  End;
  SysRtSigprocmask := 0;
End;

Function SysSigpending(Set_ : LongInt) : LongInt;
Begin
  SysSigpending := PutUserL(Set_, Cur^.Pend[0] And Cur^.Blk[0]);
End;

Function SysRtSigpending(Set_, Sz : LongInt) : LongInt;
Begin
  If Not EnsureUser(Set_, 8, True) Then
  Begin
    SysRtSigpending := -EFAULT;
    Exit;
  End;
  MemL[0:Set_] := Cur^.Pend[0] And Cur^.Blk[0];
  MemL[0:Set_ + 4] := Cur^.Pend[1] And Cur^.Blk[1];
  SysRtSigpending := 0;
End;

{ Attendre un signal avec un masque temporaire }
Function DoSigsuspend(Lo, Hi : LongInt) : LongInt;
Begin
  Cur^.Save[0] := Cur^.Blk[0]; Cur^.Save[1] := Cur^.Blk[1];
  Cur^.HasSaved := 1;
  ApplyMask(2, Lo, Hi);
  While Not SigPendingUnblocked(Cur) Do SleepOn(0, 0, True);
  { le masque d'origine est restaure apres la remise du signal (HandleSignals) }
  DoSigsuspend := -EINTR;
End;

Function SysSigsuspend(H0, H1, Mask : LongInt) : LongInt;
Begin
  SysSigsuspend := DoSigsuspend(Mask, 0);
End;

Function SysRtSigsuspend(Set_, Sz : LongInt) : LongInt;
Begin
  If Not EnsureUser(Set_, 8, False) Then
  Begin
    SysRtSigsuspend := -EFAULT;
    Exit;
  End;
  SysRtSigsuspend := DoSigsuspend(MemL[0:Set_], MemL[0:Set_ + 4]);
End;

Function SysPause : LongInt;
Begin
  While Not SigPendingUnblocked(Cur) Do SleepOn(0, 0, True);
  SysPause := -EINTR;
End;

Function SysSgetmask : LongInt;
Begin
  SysSgetmask := Cur^.Blk[0];
End;

Function SysSsetmask(M : LongInt) : LongInt;
Begin
  SysSsetmask := Cur^.Blk[0];
  Cur^.Blk[0] := M And Not UnblockableLo;
End;

Function SysSigaltstack(Ss, Oss : LongInt) : LongInt;
Begin
  If Oss <> 0 Then
  Begin
    If Not EnsureUser(Oss, 12, True) Then
    Begin
      SysSigaltstack := -EFAULT;
      Exit;
    End;
    MemL[0:Oss] := Cur^.SigStk[0]; MemL[0:Oss + 4] := Cur^.SigStk[1];
        MemL[0:Oss + 8] := Cur^.SigStk[2];
  End;
  If Ss <> 0 Then
  Begin
    If Not EnsureUser(Ss, 12, False) Then
    Begin
      SysSigaltstack := -EFAULT;
      Exit;
    End;
    Cur^.SigStk[0] := MemL[0:Ss]; Cur^.SigStk[1] := MemL[0:Ss + 4] And 2;
        Cur^.SigStk[2] := MemL[0:Ss + 8];
  End;
  SysSigaltstack := 0;
End;

Function SysSigreturn : LongInt;
Begin
  SysSigreturn := DoSigreturn(Pointer(Cur^.Frame), False);
End;

Function SysRtSigreturn : LongInt;
Begin
  SysRtSigreturn := DoSigreturn(Pointer(Cur^.Frame), True);
End;

{ ---- Temps et minuteries ---- }

Function SysTime(TAddr : LongInt) : LongInt;
Var T : LongInt;
Begin
  T := XTime;
  If TAddr <> 0 Then
    If PutUserL(TAddr, T) < 0 Then
    Begin
      SysTime := -EFAULT;
      Exit;
    End;
  SysTime := T;
End;

Function SysStime(TAddr : LongInt) : LongInt;
Var T : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysStime := -EPERM;
    Exit;
  End;
  If GetUserL(TAddr, T) < 0 Then
  Begin
    SysStime := -EFAULT;
    Exit;
  End;
  TimeOffset := T - BootTime - Jiffies Div HZ;
  SysStime := 0;
End;

Function SysGettimeofday(Tv, Tz : LongInt) : LongInt;
Begin
  If Tv <> 0 Then
  Begin
    If Not EnsureUser(Tv, 8, True) Then
    Begin
      SysGettimeofday := -EFAULT;
      Exit;
    End;
    MemL[0:Tv] := XTime; MemL[0:Tv + 4] := XUsec;
  End;
  If Tz <> 0 Then
  Begin
    If Not EnsureUser(Tz, 8, True) Then
    Begin
      SysGettimeofday := -EFAULT;
      Exit;
    End;
    MemL[0:Tz] := 0; MemL[0:Tz + 4] := 0;
  End;
  SysGettimeofday := 0;
End;

Function SysSettimeofday(Tv, Tz : LongInt) : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysSettimeofday := -EPERM;
    Exit;
  End;
  If Tv <> 0 Then
  Begin
    If Not EnsureUser(Tv, 8, False) Then
    Begin
      SysSettimeofday := -EFAULT;
      Exit;
    End;
    TimeOffset := MemL[0:Tv] - BootTime - Jiffies Div HZ;
  End;
  SysSettimeofday := 0;
End;

Function SysClockGettime(Clk, Ts : LongInt) : LongInt;
Begin
  If Not EnsureUser(Ts, 8, True) Then
  Begin
    SysClockGettime := -EFAULT;
    Exit;
  End;
  Case Clk Of
    0, 5, 8 : Begin MemL[0:Ts] := XTime; MemL[0:Ts + 4] := XUsec * 1000; End;
    1, 4, 7 : Begin MemL[0:Ts] := Jiffies Div HZ; MemL[0:Ts + 4] := (Jiffies
        Mod HZ) * (1000000000 Div HZ); End;
    2, 3 : Begin
             MemL[0:Ts] := (Cur^.Utime + Cur^.Stime) Div HZ;
             MemL[0:Ts + 4] := ((Cur^.Utime + Cur^.Stime) Mod HZ) * (1000000000
                 Div HZ);
           End;
  Else
    Begin
      SysClockGettime := -EINVAL;
      Exit;
    End;
  End;
  SysClockGettime := 0;
End;

Function SysClockGetres(Clk, Ts : LongInt) : LongInt;
Begin
  If Ts <> 0 Then
  Begin
    If Not EnsureUser(Ts, 8, True) Then
    Begin
      SysClockGetres := -EFAULT;
      Exit;
    End;
    MemL[0:Ts] := 0; MemL[0:Ts + 4] := 1000000000 Div HZ;
  End;
  SysClockGetres := 0;
End;

Function SysTimes(Buf : LongInt) : LongInt;
Begin
  If Buf <> 0 Then
  Begin
    If Not EnsureUser(Buf, 16, True) Then
    Begin
      SysTimes := -EFAULT;
      Exit;
    End;
    MemL[0:Buf] := Cur^.Utime; MemL[0:Buf + 4] := Cur^.Stime;
    MemL[0:Buf + 8] := Cur^.Cutime; MemL[0:Buf + 12] := Cur^.Cstime;
  End;
  SysTimes := Jiffies;
End;

Function SysAlarm(Sec : LongInt) : LongInt;
Var Old : LongInt;
Begin
  Old := 0;
  If Cur^.AlarmAt <> 0 Then
  Begin
    Old := (Cur^.AlarmAt - Jiffies + HZ - 1) Div HZ;
    If Old < 0 Then Old := 0;
  End;
  Cur^.ItInterval := 0;
  If Sec = 0 Then Cur^.AlarmAt := 0 Else Cur^.AlarmAt := Jiffies + Sec * HZ;
  SysAlarm := Old;
End;

Function TvToTicks(Sec, Usec : LongInt) : LongInt;
Begin
  TvToTicks := Sec * HZ + (Usec * HZ + 999999) Div 1000000;
End;

Function SysSetitimer(Which, New, Old : LongInt) : LongInt;
Var Rem, Iv, Val : LongInt;
Begin
  If (Which < 0) Or (Which > 2) Then
  Begin
    SysSetitimer := -EINVAL;
    Exit;
  End;
  If Old <> 0 Then
  Begin
    If Not EnsureUser(Old, 16, True) Then
    Begin
      SysSetitimer := -EFAULT;
      Exit;
    End;
    MemFill(Old, 0, 16);
    Case Which Of
      0 : Begin
            If Cur^.AlarmAt <> 0 Then Rem := Cur^.AlarmAt - Jiffies
                Else Rem := 0;
            If Rem < 0 Then Rem := 0;
            MemL[0:Old] := Cur^.ItInterval Div HZ; MemL[0:Old
                + 4] := (Cur^.ItInterval Mod HZ) * 10000;
            MemL[0:Old + 8] := Rem Div HZ; MemL[0:Old + 12] := (Rem Mod HZ)
                * 10000;
          End;
      1 : Begin MemL[0:Old + 8] := Cur^.ItVirt Div HZ; MemL[0:Old
          + 12] := (Cur^.ItVirt Mod HZ) * 10000; End;
      2 : Begin MemL[0:Old + 8] := Cur^.ItProf Div HZ; MemL[0:Old
          + 12] := (Cur^.ItProf Mod HZ) * 10000; End;
    End;
  End;
  If New <> 0 Then
  Begin
    If Not EnsureUser(New, 16, False) Then
    Begin
      SysSetitimer := -EFAULT;
      Exit;
    End;
    Iv := TvToTicks(MemL[0:New], MemL[0:New + 4]);
    Val := TvToTicks(MemL[0:New + 8], MemL[0:New + 12]);
    Case Which Of
      0 : Begin
            Cur^.ItInterval := Iv;
            If Val = 0 Then Cur^.AlarmAt := 0 Else Cur^.AlarmAt := Jiffies
                + Val;
          End;
      1 : Begin Cur^.ItVirt := Val; Cur^.ItVirtInt := Iv; End;
      2 : Begin Cur^.ItProf := Val; Cur^.ItProfInt := Iv; End;
    End;
  End;
  SysSetitimer := 0;
End;

Function SysGetitimer(Which, Cv : LongInt) : LongInt;
Var Rem : LongInt;
Begin
  If Not EnsureUser(Cv, 16, True) Then
  Begin
    SysGetitimer := -EFAULT;
    Exit;
  End;
  MemFill(Cv, 0, 16);
  If Which = 0 Then
  Begin
    If Cur^.AlarmAt <> 0 Then Rem := Cur^.AlarmAt - Jiffies Else Rem := 0;
    If Rem < 0 Then Rem := 0;
    MemL[0:Cv] := Cur^.ItInterval Div HZ; MemL[0:Cv + 4] := (Cur^.ItInterval
        Mod HZ) * 10000;
    MemL[0:Cv + 8] := Rem Div HZ; MemL[0:Cv + 12] := (Rem Mod HZ) * 10000;
  End;
  SysGetitimer := 0;
End;

Function SysNanosleep(Req, Rem : LongInt) : LongInt;
Var Ticks, T0, R, Left : LongInt;
Begin
  If Not EnsureUser(Req, 8, False) Then
  Begin
    SysNanosleep := -EFAULT;
    Exit;
  End;
  If (MemL[0:Req] < 0) Or (MemL[0:Req + 4] < 0) Or (MemL[0:Req
      + 4] >= 1000000000) Then
  Begin
    SysNanosleep := -EINVAL;
    Exit;
  End;
  Ticks := MemL[0:Req] * HZ + (MemL[0:Req + 4] + (1000000000 Div HZ) - 1)
      Div (1000000000 Div HZ);
  T0 := Jiffies;
  R := SleepTicks(Ticks);
  If R = WakeSignal Then
  Begin
    If Rem <> 0 Then
      If EnsureUser(Rem, 8, True) Then
      Begin
        Left := Ticks - (Jiffies - T0);
        If Left < 0 Then Left := 0;
        MemL[0:Rem] := Left Div HZ;
        MemL[0:Rem + 4] := (Left Mod HZ) * (1000000000 Div HZ);
      End;
    SysNanosleep := -EINTR;
    Exit;
  End;
  SysNanosleep := 0;
End;

Function SysClockNanosleep(Clk, Flags, Req, Rem : LongInt) : LongInt;
Var Now : LongInt;
Begin
  If (Flags And 1) <> 0 Then
  Begin
    { temps absolu : convertir en duree }
    If Not EnsureUser(Req, 8, False) Then
    Begin
      SysClockNanosleep := -EFAULT;
      Exit;
    End;
    If Clk = 0 Then Now := XTime Else Now := Jiffies Div HZ;
    If MemL[0:Req] <= Now Then
    Begin
      SysClockNanosleep := 0;
      Exit;
    End;
    SleepTicks((MemL[0:Req] - Now) * HZ);
    SysClockNanosleep := 0;
    Exit;
  End;
  SysClockNanosleep := SysNanosleep(Req, Rem);
End;

{ ---- Memoire ---- }

Function SysBrk(Addr : LongInt) : LongInt;
Begin
  If Addr = 0 Then SysBrk := Cur^.Mm^.Brk
  Else SysBrk := MmBrk(Cur^.Mm, Addr);
End;

Function DoMmap(Addr, Len, Prot, Flags, Fd, Off : LongInt) : LongInt;
Var F : PFile; Ino, FSize, Rd : LongInt; Fl : LongInt;
Begin
  If (Len <= 0) Or ((Addr And $FFF) <> 0) And ((Flags And MAP_FIXED) <> 0) Then
  Begin
    DoMmap := -EINVAL;
    Exit;
  End;
  If ((Flags And (MAP_SHARED Or MAP_PRIVATE)) = 0) Or ((Off And $FFF) <> 0) Then
  Begin
    DoMmap := -EINVAL;
    Exit;
  End;
  Ino := 0; FSize := 0;
  If (Flags And MAP_ANONYMOUS) = 0 Then
  Begin
    F := FdGet(Fd);
    If F = Nil Then
    Begin
      DoMmap := -EBADF;
      Exit;
    End;
    If (F^.Flags And O_ACCMODE) = O_WRONLY Then
    Begin
      DoMmap := -EACCES;
      Exit;
    End;
    If ((F^.Inode^.Mode And S_IFMT) = S_IFCHR) And ((F^.Inode^.Rdev Shr 8) = 1)
        And ((F^.Inode^.Rdev And $FF) = 5) Then
      Flags := Flags Or MAP_ANONYMOUS
    Else If (F^.Inode^.Mode And S_IFMT) <> S_IFREG Then
    Begin
      DoMmap := -ENODEV;
      Exit;
    End
    Else
    Begin
      Ino := LongInt(F^.Inode);
      FSize := F^.Inode^.Size - Off;
      If FSize < 0 Then FSize := 0;
    End;
  End;
  Fl := Flags;
  If (Flags And MAP_SHARED) <> 0 Then Fl := Flags;
  DoMmap := MmMap(Cur^.Mm, Addr, Len, Prot, Fl, Ino, Off, FSize);
  Rd := 0;
End;

{ mmap (90) : ebx pointe vers six mots }
Function SysMmapOld(Args : LongInt) : LongInt;
Begin
  If Not EnsureUser(Args, 24, False) Then
  Begin
    SysMmapOld := -EFAULT;
    Exit;
  End;
  SysMmapOld := DoMmap(MemL[0:Args], MemL[0:Args + 4], MemL[0:Args + 8],
      MemL[0:Args + 12],
                       MemL[0:Args + 16], MemL[0:Args + 20]);
End;

Function SysMmap2(Addr, Len, Prot, Flags, Fd, PgOff : LongInt) : LongInt;
Begin
  SysMmap2 := DoMmap(Addr, Len, Prot, Flags, Fd, PgOff Shl 12);
End;

Function SysMunmap(Addr, Len : LongInt) : LongInt;
Begin
  If ((Addr And $FFF) <> 0) Or (Len <= 0) Or Not ULt(Addr, UserTop)
      Or ULt(UserTop, Addr + PageUp(Len)) Then
  Begin
    SysMunmap := -EINVAL;
    Exit;
  End;
  SysMunmap := MmUnmap(Cur^.Mm, Addr, Addr + PageUp(Len));
End;

Function SysMprotect(Addr, Len, Prot : LongInt) : LongInt;
Begin
  If ((Addr And $FFF) <> 0) Or (Len < 0) Then
  Begin
    SysMprotect := -EINVAL;
    Exit;
  End;
  If Len = 0 Then
  Begin
    SysMprotect := 0;
    Exit;
  End;
  SysMprotect := MmProtect(Cur^.Mm, Addr, Addr + PageUp(Len), Prot And 7);
End;

Function SysMadvise(A, L, Adv : LongInt) : LongInt;
Begin
  SysMadvise := 0;
End;

Function SysZero3(A, B, C : LongInt) : LongInt;
Begin
  SysZero3 := 0;
End;

{ mremap : reduction ou agrandissement sur place uniquement }
Function SysMremap(Old, OldLen, NewLen, Flags, NewAddr : LongInt) : LongInt;
Var V, N : PVma; OldEnd, NewEnd : LongInt;
Begin
  If ((Old And $FFF) <> 0) Or (NewLen <= 0) Then
  Begin
    SysMremap := -EINVAL;
    Exit;
  End;
  OldLen := PageUp(OldLen); NewLen := PageUp(NewLen);
  V := FindVma(Cur^.Mm, Old);
  If (V = Nil) Or (V^.Start <> Old) Or (V^.Fin <> Old + OldLen) Then
  Begin
    SysMremap := -EFAULT;
    Exit;
  End;
  If NewLen = OldLen Then
  Begin
    SysMremap := Old;
    Exit;
  End;
  If NewLen < OldLen Then
  Begin
    MmUnmap(Cur^.Mm, Old + NewLen, Old + OldLen);
    SysMremap := Old;
    Exit;
  End;
  OldEnd := Old + OldLen; NewEnd := Old + NewLen;
  N := FindVmaAfter(Cur^.Mm, OldEnd);
  If ((N = Nil) Or ULe(NewEnd, N^.Start)) And ULt(NewEnd, UserTop) And (V^.Ino
      = 0) Then
  Begin
    V^.Fin := NewEnd;
    Cur^.Mm^.TotalVm := Cur^.Mm^.TotalVm + ((NewEnd - OldEnd) Shr 12);
    SysMremap := Old;
    Exit;
  End;
  SysMremap := -ENOMEM;
End;

{ ---- Limites et ressources ---- }

Function SysGetrlimit(Res, Rl : LongInt) : LongInt;
Begin
  If (Res < 0) Or (Res > 15) Then
  Begin
    SysGetrlimit := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(Rl, 8, True) Then
  Begin
    SysGetrlimit := -EFAULT;
    Exit;
  End;
  If Cur^.RlimCur[Res] = RLIM_INFINITY Then MemL[0:Rl] := -1
      Else MemL[0:Rl] := Cur^.RlimCur[Res];
  If Cur^.RlimMax[Res] = RLIM_INFINITY Then MemL[0:Rl + 4] := -1 Else MemL[0:Rl
      + 4] := Cur^.RlimMax[Res];
  SysGetrlimit := 0;
End;

Function SetRlimit(Res, C, M : LongInt) : LongInt;
Begin
  If (Res < 0) Or (Res > 15) Then
  Begin
    SetRlimit := -EINVAL;
    Exit;
  End;
  If C = -1 Then C := RLIM_INFINITY;
  If M = -1 Then M := RLIM_INFINITY;
  If (C < 0) Or (M < 0) Then
  Begin
    SetRlimit := -EINVAL;
    Exit;
  End;
  If C > M Then
  Begin
    SetRlimit := -EINVAL;
    Exit;
  End;
  If (M > Cur^.RlimMax[Res]) And (Cur^.Euid <> 0) Then
  Begin
    SetRlimit := -EPERM;
    Exit;
  End;
  Cur^.RlimCur[Res] := C; Cur^.RlimMax[Res] := M;
  If Res = RLIM_STACK Then Cur^.Mm^.StackLimit := C;
  If Res = RLIM_DATA Then
    If C = RLIM_INFINITY Then Cur^.Mm^.DataLimit := 0
        Else Cur^.Mm^.DataLimit := C;
  SetRlimit := 0;
End;

Function SysSetrlimit(Res, Rl : LongInt) : LongInt;
Begin
  If Not EnsureUser(Rl, 8, False) Then
  Begin
    SysSetrlimit := -EFAULT;
    Exit;
  End;
  SysSetrlimit := SetRlimit(Res, MemL[0:Rl], MemL[0:Rl + 4]);
End;

Function SysPrlimit64(Pid, Res, New, Old : LongInt) : LongInt;
Var R : LongInt;
Begin
  If (Pid <> 0) And (Pid <> Cur^.Pid) Then
  Begin
    SysPrlimit64 := -ESRCH;
    Exit;
  End;
  If Old <> 0 Then
  Begin
    If (Res < 0) Or (Res > 15) Or Not EnsureUser(Old, 16, True) Then
    Begin
      SysPrlimit64 := -EINVAL;
      Exit;
    End;
    If Cur^.RlimCur[Res] = RLIM_INFINITY Then
    Begin MemL[0:Old] := -1; MemL[0:Old + 4] := -1; End
    Else Begin MemL[0:Old] := Cur^.RlimCur[Res]; MemL[0:Old + 4] := 0; End;
    If Cur^.RlimMax[Res] = RLIM_INFINITY Then
    Begin MemL[0:Old + 8] := -1; MemL[0:Old + 12] := -1; End
    Else Begin MemL[0:Old + 8] := Cur^.RlimMax[Res]; MemL[0:Old + 12] := 0; End;
  End;
  If New <> 0 Then
  Begin
    If Not EnsureUser(New, 16, False) Then
    Begin
      SysPrlimit64 := -EFAULT;
      Exit;
    End;
    R := SetRlimit(Res, MemL[0:New], MemL[0:New + 8]);
    SysPrlimit64 := R;
    Exit;
  End;
  SysPrlimit64 := 0;
End;

Function SysGetrusage(Who, Ru : LongInt) : LongInt;
Var U, S : LongInt;
Begin
  If Not EnsureUser(Ru, 72, True) Then
  Begin
    SysGetrusage := -EFAULT;
    Exit;
  End;
  MemFill(Ru, 0, 72);
  If Who = -1 Then
  Begin
    U := Cur^.Cutime; S := Cur^.Cstime;
  End
  Else
  Begin
    U := Cur^.Utime; S := Cur^.Stime;
  End;
  MemL[0:Ru] := U Div HZ; MemL[0:Ru + 4] := (U Mod HZ) * 10000;
  MemL[0:Ru + 8] := S Div HZ; MemL[0:Ru + 12] := (S Mod HZ) * 10000;
  MemL[0:Ru + 32] := Cur^.Mm^.Rss;
  SysGetrusage := 0;
End;

{ ---- Informations systeme ---- }

Procedure PutField(Base, Idx : LongInt; Const S : String);
Begin
  PutPStr(Base + Idx * 65, S, 65);
End;

Function SysUname(Buf : LongInt) : LongInt;
Begin
  If Not EnsureUser(Buf, 390, True) Then
  Begin
    SysUname := -EFAULT;
    Exit;
  End;
  MemFill(Buf, 0, 390);
  PutField(Buf, 0, 'LINUX-0');
  PutField(Buf, 1, HostName);
  PutField(Buf, 2, UnameRel);
  PutField(Buf, 3, '0.1');
  PutField(Buf, 4, 'i386');
  PutField(Buf, 5, DomainName);
  SysUname := 0;
End;

Function SysSethostname(Name, Len : LongInt) : LongInt;
Var I : LongInt; S : String;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysSethostname := -EPERM;
    Exit;
  End;
  If (Len < 0) Or (Len > 64) Then
  Begin
    SysSethostname := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(Name, Len, False) Then
  Begin
    SysSethostname := -EFAULT;
    Exit;
  End;
  S := '';
  For I := 0 To Len - 1 Do S := S + Chr(Mem[0:Name + I]);
  HostName := S;
  SysSethostname := 0;
End;

Function SysSetdomainname(Name, Len : LongInt) : LongInt;
Var I : LongInt; S : String;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysSetdomainname := -EPERM;
    Exit;
  End;
  If (Len < 0) Or (Len > 64) Then
  Begin
    SysSetdomainname := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(Name, Len, False) Then
  Begin
    SysSetdomainname := -EFAULT;
    Exit;
  End;
  S := '';
  For I := 0 To Len - 1 Do S := S + Chr(Mem[0:Name + I]);
  DomainName := S;
  SysSetdomainname := 0;
End;

Function SysSysinfo(Buf : LongInt) : LongInt;
Var N, I : LongInt;
Begin
  If Not EnsureUser(Buf, 64, True) Then
  Begin
    SysSysinfo := -EFAULT;
    Exit;
  End;
  MemFill(Buf, 0, 64);
  N := 0;
  For I := 1 To MaxTasks - 1 Do
    If Tasks[I].State <> TsFree Then Inc(N);
  MemL[0:Buf] := Jiffies Div HZ;
  MemL[0:Buf + 16] := TotalFreePages * 4096;
  MemL[0:Buf + 20] := FreePagesCnt * 4096;
  MemL[0:Buf + 28] := BufCount * 1024;
  MemW[0:Buf + 40] := N;
  MemL[0:Buf + 52] := 1;
  SysSysinfo := 0;
End;

{ syslog : lecture du journal du noyau (dmesg) }
Function SysSyslog(Typ, Buf, Len : LongInt) : LongInt;
Var I, N, Start : LongInt;
Begin
  Case Typ Of
    3, 4 :
      Begin
        If Len <= 0 Then
        Begin
          SysSyslog := -EINVAL;
          Exit;
        End;
        N := LogCount;
        Start := 0;
        If N > Len Then
        Begin
          Start := N - Len;
          N := Len;
        End;
        If Not EnsureUser(Buf, N, True) Then
        Begin
          SysSyslog := -EFAULT;
          Exit;
        End;
        For I := 0 To N - 1 Do Mem[0:Buf + I] := LogByte(Start + I);
        If Typ = 4 Then LogCount := 0;
        SysSyslog := N;
      End;
    5 : Begin LogCount := 0; SysSyslog := 0; End;
    9 : SysSyslog := LogCount;
    10 : SysSyslog := LogSize;
    0, 1, 6, 7, 8 : SysSyslog := 0;
  Else
    SysSyslog := -EINVAL;
  End;
End;

Procedure PowerOff;
Begin
  KLog('Extinction du systeme.');
  Port[$604 + 1] := $20;
  PortW[$604] := $2000;
  PortW[$B004] := $2000;
  PortW[$4004] := $3400;
  KLog('Systeme arrete. Vous pouvez eteindre l''ordinateur.');
  CpuHalt;
End;

Procedure RebootCpu;
Var N : LongInt;
Begin
  KLog('Redemarrage du systeme.');
  N := 0;
  While ((Port[$64] And 2) <> 0) And (N < 100000) Do Inc(N);
  Port[$64] := $FE;
  { en dernier recours : triple faute }
  GdtPtr.Limit := 0;
  asm
    lidt GdtPtr
    int 3
  end;
  CpuHalt;
End;

Function SysReboot(M1, M2, Cmd, Arg : LongInt) : LongInt;
Begin
  If Cur^.Euid <> 0 Then
  Begin
    SysReboot := -EPERM;
    Exit;
  End;
  If M1 <> LongInt($FEE1DEAD) Then
  Begin
    SysReboot := -EINVAL;
    Exit;
  End;
  Case Cmd Of
    $01234567, LongInt($A1B2C3D4) :
      Begin
        VfsShutdown;
        RebootCpu;
      End;
    LongInt($CDEF0123) :
      Begin
        VfsShutdown;
        KLog('Systeme arrete.');
        CpuHalt;
      End;
    $4321FEDC :
      Begin
        VfsShutdown;
        PowerOff;
      End;
    LongInt($89ABCDEF), 0 : SysReboot := 0;
  Else
    SysReboot := -EINVAL;
  End;
End;

{ prctl : noms de processus }
Function SysPrctl(Opt, A2, A3, A4, A5 : LongInt) : LongInt;
Var I : LongInt;
Begin
  If Opt = 15 Then
  Begin
    If Not EnsureUser(A2, 16, False) Then
    Begin
      SysPrctl := -EFAULT;
      Exit;
    End;
    For I := 0 To 14 Do Cur^.Comm[I] := Mem[0:A2 + I];
    Cur^.Comm[15] := 0;
    SysPrctl := 0;
  End
  Else If Opt = 16 Then
  Begin
    If Not EnsureUser(A2, 16, True) Then
    Begin
      SysPrctl := -EFAULT;
      Exit;
    End;
    For I := 0 To 15 Do Mem[0:A2 + I] := Cur^.Comm[I];
    SysPrctl := 0;
  End
  Else If (Opt = 1) Or (Opt = 3) Or (Opt = 4) Then SysPrctl := 0
  Else SysPrctl := -EINVAL;
End;

Function SysSetThreadArea(UInfo : LongInt) : LongInt;
Var Entry, Base, Limit, Flags, Lo, Hi : LongInt;
Begin
  If Not EnsureUser(UInfo, 16, True) Then
  Begin
    SysSetThreadArea := -EFAULT;
    Exit;
  End;
  Entry := MemL[0:UInfo];
  Base := MemL[0:UInfo + 4];
  Limit := MemL[0:UInfo + 8];
  Flags := MemL[0:UInfo + 12];
  If Entry = -1 Then
  Begin
    Entry := 6;
    MemL[0:UInfo] := Entry;
  End;
  If (Entry < 6) Or (Entry > 8) Then
  Begin
    SysSetThreadArea := -EINVAL;
    Exit;
  End;
  Lo := (Base Shl 16) Or (Limit And $FFFF);
  Hi := (Base And LongInt($FF000000)) Or ((Base Shr 16) And $FF) Or ((Limit
      And $F0000)) Or $00C0F300;
  If (Flags And 1) = 0 Then Hi := Hi And Not $00400000;
  If (Flags And 16) = 0 Then Hi := Hi And Not $00800000;
  If (Flags And 128) <> 0 Then
  Begin
    Lo := 0; Hi := 0;
  End;
  Cur^.Tls[(Entry - 6) * 2] := Lo;
  Cur^.Tls[(Entry - 6) * 2 + 1] := Hi;
  LoadTls(Cur);
  SysSetThreadArea := 0;
End;

Function SysGetThreadArea(UInfo : LongInt) : LongInt;
Begin
  SysGetThreadArea := -EINVAL;
End;

Function SysSetTidAddress(Addr : LongInt) : LongInt;
Begin
  Cur^.ClearTid := Addr;
  SysSetTidAddress := Cur^.Pid;
End;

{ futex : attente/reveil sur une adresse }
Function SysFutex(UAddr, Op, Val, Timeout, UAddr2 : LongInt) : LongInt;
Var Cmd, V, R, Tmo, I, N : LongInt;
Begin
  Cmd := Op And 127;
  Case Cmd Of
    0, 9 :
      Begin
        If GetUserL(UAddr, V) < 0 Then
        Begin
          SysFutex := -EFAULT;
          Exit;
        End;
        If V <> Val Then
        Begin
          SysFutex := -EAGAIN;
          Exit;
        End;
        Tmo := 0;
        If Timeout <> 0 Then
          If EnsureUser(Timeout, 8, False) Then
            Tmo := MemL[0:Timeout] * HZ + (MemL[0:Timeout + 4] Div (1000000000
                Div HZ)) + 1;
        R := SleepOn(UAddr, Tmo, True);
        If R = WakeSignal Then SysFutex := -EINTR
        Else If R = WakeTimeout Then SysFutex := -110
        Else SysFutex := 0;
      End;
    1, 10 :
      Begin
        N := 0;
        For I := 0 To MaxTasks - 1 Do
          If (N < Val) And ((Tasks[I].State = TsSleeping) Or (Tasks[I].State
              = TsSleepUn)) And (Tasks[I].WaitChan = UAddr) Then
          Begin
            WakeTask(@Tasks[I], WakeNormal);
            Inc(N);
          End;
        SysFutex := N;
      End;
  Else
    SysFutex := -ENOSYS;
  End;
End;

Function SysGetrandom(Buf, Len, Flags : LongInt) : LongInt;
Var I : LongInt;
Begin
  If Len < 0 Then
  Begin
    SysGetrandom := -EINVAL;
    Exit;
  End;
  If Len > 256 Then Len := 256;
  If Not EnsureUser(Buf, Len, True) Then
  Begin
    SysGetrandom := -EFAULT;
    Exit;
  End;
  For I := 0 To Len - 1 Do Mem[0:Buf + I] := RandNext And $FF;
  SysGetrandom := Len;
End;

Function SysVhangup : LongInt;
Begin
  SysVhangup := 0;
End;

Function SysEnosys : LongInt;
Begin
  SysEnosys := -ENOSYS;
End;

Function SysEperm : LongInt;
Begin
  SysEperm := -EPERM;
End;

{ ---- poll et select ---- }

{ Evenements prets pour un descripteur }
Function FdPollMask(Fd, Events : LongInt) : LongInt;
Var F : PFile; Fn, R : LongInt;
Begin
  F := FdGet(Fd);
  If F = Nil Then
  Begin
    FdPollMask := POLLNVAL;
    Exit;
  End;
  Fn := GetOp(F^.FOps, FoPoll);
  If Fn = 0 Then R := POLLIN Or POLLOUT
  Else R := Call2(Fn, LongInt(F), Events);
  FdPollMask := R;
End;

Function SysPoll(Fds, Nfds, Timeout : LongInt) : LongInt;
Var I, N, Rev, Ev, Fd, Deadline : LongInt;
Begin
  If (Nfds < 0) Or (Nfds > MaxFd) Then
  Begin
    SysPoll := -EINVAL;
    Exit;
  End;
  If Not EnsureUser(Fds, Nfds * 8, True) Then
  Begin
    SysPoll := -EFAULT;
    Exit;
  End;
  If Timeout < 0 Then Deadline := 0
  Else Deadline := Jiffies + (Timeout * HZ + 999) Div 1000;
  While True Do
  Begin
    N := 0;
    For I := 0 To Nfds - 1 Do
    Begin
      Fd := MemL[0:Fds + I * 8];
      Ev := MemW[0:Fds + I * 8 + 4] Or POLLERR Or POLLHUP Or POLLNVAL;
      If Fd < 0 Then Rev := 0
      Else Rev := FdPollMask(Fd, Ev) And Ev;
      MemW[0:Fds + I * 8 + 6] := Rev;
      If Rev <> 0 Then Inc(N);
    End;
    If (N > 0) Or (Timeout = 0) Then
    Begin
      SysPoll := N;
      Exit;
    End;
    If (Timeout > 0) And (Jiffies - Deadline >= 0) Then
    Begin
      SysPoll := 0;
      Exit;
    End;
    If SleepTicks(1) = WakeSignal Then
    Begin
      SysPoll := -EINTR;
      Exit;
    End;
  End;
End;

Function DoSelect(N, InA, OutA, ExA, Tv : LongInt) : LongInt;
Var Words, I, B, Cnt, Deadline, Ev, Rev, Tmo : LongInt; RIn,
    ROut : Array[0..31] Of LongInt;
    WIn, WOut : Array[0..31] Of LongInt; Forever : Boolean;
Begin
  If (N < 0) Or (N > MaxFd) Then
  Begin
    DoSelect := -EINVAL;
    Exit;
  End;
  Words := (N + 31) Div 32;
  For I := 0 To 31 Do
  Begin
    RIn[I] := 0; WIn[I] := 0; ROut[I] := 0; WOut[I] := 0;
  End;
  If InA <> 0 Then
    If EnsureUser(InA, Words * 4, True) Then
      For I := 0 To Words - 1 Do RIn[I] := MemL[0:InA + I * 4]
          Else Begin DoSelect := -EFAULT; Exit; End;
  If OutA <> 0 Then
    If EnsureUser(OutA, Words * 4, True) Then
      For I := 0 To Words - 1 Do WIn[I] := MemL[0:OutA + I * 4]
          Else Begin DoSelect := -EFAULT; Exit; End;
  If ExA <> 0 Then
    If Not EnsureUser(ExA, Words * 4, True) Then
    Begin
      DoSelect := -EFAULT;
      Exit;
    End;
  Forever := Tv = 0;
  Tmo := 0;
  If Tv <> 0 Then
  Begin
    If Not EnsureUser(Tv, 8, False) Then
    Begin
      DoSelect := -EFAULT;
      Exit;
    End;
    Tmo := TvToTicks(MemL[0:Tv], MemL[0:Tv + 4]);
  End;
  Deadline := Jiffies + Tmo;
  While True Do
  Begin
    Cnt := 0;
    For I := 0 To Words - 1 Do
    Begin
      ROut[I] := 0; WOut[I] := 0;
    End;
    For B := 0 To N - 1 Do
    Begin
      Ev := 0;
      If (RIn[B Shr 5] And (1 Shl (B And 31))) <> 0 Then Ev := Ev Or POLLIN;
      If (WIn[B Shr 5] And (1 Shl (B And 31))) <> 0 Then Ev := Ev Or POLLOUT;
      If Ev <> 0 Then
      Begin
        Rev := FdPollMask(B, Ev Or POLLERR Or POLLHUP Or POLLNVAL);
        If (Rev And POLLNVAL) <> 0 Then
        Begin
          DoSelect := -EBADF;
          Exit;
        End;
        If ((Ev And POLLIN) <> 0) And ((Rev And (POLLIN Or POLLHUP Or POLLERR))
            <> 0) Then
        Begin
          ROut[B Shr 5] := ROut[B Shr 5] Or (1 Shl (B And 31));
          Inc(Cnt);
        End;
        If ((Ev And POLLOUT) <> 0) And ((Rev And (POLLOUT Or POLLERR))
            <> 0) Then
        Begin
          WOut[B Shr 5] := WOut[B Shr 5] Or (1 Shl (B And 31));
          Inc(Cnt);
        End;
      End;
    End;
    If (Cnt > 0) Or ((Not Forever) And (Jiffies - Deadline >= 0)) Then
    Begin
      If InA <> 0 Then For I := 0 To Words - 1 Do MemL[0:InA + I
          * 4] := ROut[I];
      If OutA <> 0 Then For I := 0 To Words - 1 Do MemL[0:OutA + I
          * 4] := WOut[I];
      If ExA <> 0 Then For I := 0 To Words - 1 Do MemL[0:ExA + I * 4] := 0;
      DoSelect := Cnt;
      Exit;
    End;
    If SleepTicks(1) = WakeSignal Then
    Begin
      DoSelect := -EINTR;
      Exit;
    End;
  End;
End;

Function SysNewselect(N, InA, OutA, ExA, Tv : LongInt) : LongInt;
Begin
  SysNewselect := DoSelect(N, InA, OutA, ExA, Tv);
End;

Function SysSelectOld(Args : LongInt) : LongInt;
Begin
  If Not EnsureUser(Args, 20, False) Then
  Begin
    SysSelectOld := -EFAULT;
    Exit;
  End;
  SysSelectOld := DoSelect(MemL[0:Args], MemL[0:Args + 4], MemL[0:Args + 8],
      MemL[0:Args + 12], MemL[0:Args + 16]);
End;

{ ---- Table des appels systeme ---- }

Procedure InitSyscalls;
Var I : LongInt;
Begin
  For I := 0 To MaxSys - 1 Do
  Begin
    SysFn[I] := 0;
    SysArgc[I] := 0;
  End;
  SysReg(1, LongInt(@SysExit), 1);        SysReg(2, LongInt(@SysFork), 0);
  SysReg(3, LongInt(@SysRead), 3);        SysReg(4, LongInt(@SysWrite), 3);
  SysReg(5, LongInt(@SysOpen), 3);        SysReg(6, LongInt(@SysClose), 1);
  SysReg(7, LongInt(@SysWaitpid), 3);     SysReg(8, LongInt(@SysCreat), 2);
  SysReg(9, LongInt(@SysLink), 2);        SysReg(10, LongInt(@SysUnlink), 1);
  SysReg(11, LongInt(@SysExecve), 3);     SysReg(12, LongInt(@SysChdir), 1);
  SysReg(13, LongInt(@SysTime), 1);       SysReg(14, LongInt(@SysMknod), 3);
  SysReg(15, LongInt(@SysChmod), 2);      SysReg(16, LongInt(@SysLchown), 3);
  SysReg(19, LongInt(@SysLseek), 3);      SysReg(20, LongInt(@SysGetpid), 0);
  SysReg(21, LongInt(@SysMount), 5);      SysReg(22, LongInt(@SysUmount), 1);
  SysReg(23, LongInt(@SysSetuid), 1);     SysReg(24, LongInt(@SysGetuid), 0);
  SysReg(25, LongInt(@SysStime), 1);      SysReg(26, LongInt(@SysEperm), 0);
  SysReg(27, LongInt(@SysAlarm), 1);      SysReg(29, LongInt(@SysPause), 0);
  SysReg(30, LongInt(@SysUtime), 2);      SysReg(33, LongInt(@SysAccess), 2);
  SysReg(34, LongInt(@SysNice), 1);       SysReg(36, LongInt(@SysSync), 0);
  SysReg(37, LongInt(@SysKill), 2);       SysReg(38, LongInt(@SysRename), 2);
  SysReg(39, LongInt(@SysMkdir), 2);      SysReg(40, LongInt(@SysRmdir), 1);
  SysReg(41, LongInt(@SysDup), 1);        SysReg(42, LongInt(@SysPipe), 1);
  SysReg(43, LongInt(@SysTimes), 1);      SysReg(45, LongInt(@SysBrk), 1);
  SysReg(46, LongInt(@SysSetgid), 1);     SysReg(47, LongInt(@SysGetgid), 0);
  SysReg(48, LongInt(@SysSignal), 2);     SysReg(49, LongInt(@SysGeteuid), 0);
  SysReg(50, LongInt(@SysGetegid), 0);    SysReg(52, LongInt(@SysUmount2), 2);
  SysReg(54, LongInt(@SysIoctl), 3);      SysReg(55, LongInt(@SysFcntl), 3);
  SysReg(57, LongInt(@SysSetpgid), 2);    SysReg(60, LongInt(@SysUmask), 1);
  SysReg(61, LongInt(@SysChroot), 1);     SysReg(63, LongInt(@SysDup2), 2);
  SysReg(64, LongInt(@SysGetppid), 0);    SysReg(65, LongInt(@SysGetpgrp), 0);
  SysReg(66, LongInt(@SysSetsid), 0);     SysReg(67, LongInt(@SysSigaction), 3);
  SysReg(68, LongInt(@SysSgetmask), 0);   SysReg(69, LongInt(@SysSsetmask), 1);
  SysReg(70, LongInt(@SysSetreuid), 2);   SysReg(71, LongInt(@SysSetregid), 2);
  SysReg(72, LongInt(@SysSigsuspend), 3); SysReg(73, LongInt(@SysSigpending),
      1);
  SysReg(74, LongInt(@SysSethostname), 2); SysReg(75, LongInt(@SysSetrlimit),
      2);
  SysReg(76, LongInt(@SysGetrlimit), 2);  SysReg(77, LongInt(@SysGetrusage), 2);
  SysReg(78, LongInt(@SysGettimeofday), 2); SysReg(79,
      LongInt(@SysSettimeofday), 2);
  SysReg(80, LongInt(@SysGetgroups), 2);  SysReg(81, LongInt(@SysSetgroups), 2);
  SysReg(82, LongInt(@SysSelectOld), 1);  SysReg(83, LongInt(@SysSymlink), 2);
  SysReg(85, LongInt(@SysReadlink), 3);   SysReg(88, LongInt(@SysReboot), 4);
  SysReg(90, LongInt(@SysMmapOld), 1);    SysReg(91, LongInt(@SysMunmap), 2);
  SysReg(92, LongInt(@SysTruncate), 2);   SysReg(93, LongInt(@SysFtruncate), 2);
  SysReg(94, LongInt(@SysFchmod), 2);     SysReg(95, LongInt(@SysFchown), 3);
  SysReg(96, LongInt(@SysGetpriority), 2); SysReg(97, LongInt(@SysSetpriority),
      3);
  SysReg(99, LongInt(@SysStatfs), 2);     SysReg(100, LongInt(@SysFstatfs), 2);
  SysReg(103, LongInt(@SysSyslog), 3);    SysReg(104, LongInt(@SysSetitimer),
      3);
  SysReg(105, LongInt(@SysGetitimer), 2); SysReg(106, LongInt(@SysStat), 2);
  SysReg(107, LongInt(@SysLstat), 2);     SysReg(108, LongInt(@SysFstat), 2);
  SysReg(111, LongInt(@SysVhangup), 0);   SysReg(114, LongInt(@SysWait4), 4);
  SysReg(116, LongInt(@SysSysinfo), 1);   SysReg(118, LongInt(@SysFsync), 1);
  SysReg(119, LongInt(@SysSigreturn), 0); SysReg(120, LongInt(@SysClone), 5);
  SysReg(121, LongInt(@SysSetdomainname), 2); SysReg(122, LongInt(@SysUname),
      1);
  SysReg(125, LongInt(@SysMprotect), 3);  SysReg(126, LongInt(@SysSigprocmask),
      3);
  SysReg(132, LongInt(@SysGetpgid), 1);   SysReg(133, LongInt(@SysFchdir), 1);
  SysReg(140, LongInt(@SysLlseek), 5);    SysReg(141, LongInt(@SysGetdents), 3);
  SysReg(142, LongInt(@SysNewselect), 5); SysReg(143, LongInt(@SysZero3), 2);
  SysReg(144, LongInt(@SysZero3), 3);     SysReg(145, LongInt(@SysReadv), 3);
  SysReg(146, LongInt(@SysWritev), 3);    SysReg(147, LongInt(@SysGetsid), 1);
  SysReg(148, LongInt(@SysFsync), 1);     SysReg(150, LongInt(@SysZero3), 2);
  SysReg(151, LongInt(@SysZero3), 2);     SysReg(152, LongInt(@SysZero3), 1);
  SysReg(153, LongInt(@SysZero3), 0);     SysReg(158, LongInt(@SysSchedYield),
      0);
  SysReg(159, LongInt(@SysSchedPrio), 1); SysReg(160,
      LongInt(@SysSchedMinPrio), 1);
  SysReg(162, LongInt(@SysNanosleep), 2); SysReg(163, LongInt(@SysMremap), 5);
  SysReg(164, LongInt(@SysSetresuid), 3); SysReg(165, LongInt(@SysGetresuid),
      3);
  SysReg(168, LongInt(@SysPoll), 3);      SysReg(170, LongInt(@SysSetresgid),
      3);
  SysReg(171, LongInt(@SysGetresgid), 3); SysReg(172, LongInt(@SysPrctl), 5);
  SysReg(173, LongInt(@SysRtSigreturn), 0); SysReg(174,
      LongInt(@SysRtSigaction), 4);
  SysReg(175, LongInt(@SysRtSigprocmask), 4); SysReg(176,
      LongInt(@SysRtSigpending), 2);
  SysReg(179, LongInt(@SysRtSigsuspend), 2); SysReg(180, LongInt(@SysPread), 5);
  SysReg(181, LongInt(@SysPwrite), 5);    SysReg(182, LongInt(@SysChown), 3);
  SysReg(183, LongInt(@SysGetcwd), 2);    SysReg(186, LongInt(@SysSigaltstack),
      2);
  SysReg(190, LongInt(@SysVfork), 0);     SysReg(191, LongInt(@SysGetrlimit),
      2);
  SysReg(192, LongInt(@SysMmap2), 6);     SysReg(193, LongInt(@SysTruncate64),
      3);
  SysReg(194, LongInt(@SysFtruncate64), 3); SysReg(195, LongInt(@SysStat64), 2);
  SysReg(196, LongInt(@SysLstat64), 2);   SysReg(197, LongInt(@SysFstat64), 2);
  SysReg(198, LongInt(@SysLchown32), 3);  SysReg(199, LongInt(@SysGetuid32), 0);
  SysReg(200, LongInt(@SysGetgid32), 0);  SysReg(201, LongInt(@SysGeteuid32),
      0);
  SysReg(202, LongInt(@SysGetegid32), 0); SysReg(203, LongInt(@SysSetreuid32),
      2);
  SysReg(204, LongInt(@SysSetregid32), 2); SysReg(205,
      LongInt(@SysGetgroups32), 2);
  SysReg(206, LongInt(@SysSetgroups32), 2); SysReg(207, LongInt(@SysFchown32),
      3);
  SysReg(208, LongInt(@SysSetresuid32), 3); SysReg(209, LongInt(@SysGetresuid),
      3);
  SysReg(210, LongInt(@SysSetresgid32), 3); SysReg(211, LongInt(@SysGetresgid),
      3);
  SysReg(212, LongInt(@SysChown32), 3);   SysReg(213, LongInt(@SysSetuid32), 1);
  SysReg(214, LongInt(@SysSetgid32), 1);  SysReg(215, LongInt(@SysSetfsuid), 1);
  SysReg(216, LongInt(@SysSetfsgid), 1); SysReg(217, LongInt(@SysPivotRoot), 2);  SysReg(219, LongInt(@SysMadvise), 3);
  SysReg(220, LongInt(@SysGetdents64), 3); SysReg(221, LongInt(@SysFcntl), 3);
  SysReg(224, LongInt(@SysGettid), 0);    SysReg(238, LongInt(@SysTkill), 2);
  SysReg(240, LongInt(@SysFutex), 5);     SysReg(243,
      LongInt(@SysSetThreadArea), 1);
  SysReg(244, LongInt(@SysGetThreadArea), 1); SysReg(252,
      LongInt(@SysExitGroup), 1);
  SysReg(258, LongInt(@SysSetTidAddress), 1); SysReg(265,
      LongInt(@SysClockGettime), 2);
  SysReg(266, LongInt(@SysClockGetres), 2); SysReg(267,
      LongInt(@SysClockNanosleep), 4);
  SysReg(268, LongInt(@SysStatfs64), 3);  SysReg(269, LongInt(@SysFstatfs64),
      3);
  SysReg(270, LongInt(@SysTgkill), 3);    SysReg(271, LongInt(@SysUtimes), 2);
  SysReg(295, LongInt(@SysOpenat), 4);    SysReg(296, LongInt(@SysMkdirat), 3);
  SysReg(297, LongInt(@SysMknodat), 4);   SysReg(298, LongInt(@SysFchownat), 5);
  SysReg(300, LongInt(@SysFstatat64), 4); SysReg(301, LongInt(@SysUnlinkat), 3);
  SysReg(302, LongInt(@SysRenameat), 4);  SysReg(303, LongInt(@SysLinkat), 5);
  SysReg(304, LongInt(@SysSymlinkat), 3); SysReg(305, LongInt(@SysReadlinkat),
      4);
  SysReg(306, LongInt(@SysFchmodat), 3);  SysReg(307, LongInt(@SysFaccessat),
      3);
  SysReg(320, LongInt(@SysUtimensat), 4);
  SysReg(330, LongInt(@SysDup3), 3);      SysReg(331, LongInt(@SysPipe2), 2);
  SysReg(340, LongInt(@SysPrlimit64), 4); SysReg(355, LongInt(@SysGetrandom),
      3);
End;

{ ---- Entree INT 80h ---- }

Procedure DoSyscall(F : PFrame);
Var Nr, Fn, R : LongInt;
Begin
  Nr := F^.Eax;
  F^.Err := Nr;
  If KDebug Then KLog('sys ' + IntStr(Nr) + ' pid ' + IntStr(Cur^.Pid) + ' ('
      + HexStr(F^.Ebx, 8) + ',' + HexStr(F^.Ecx, 8) + ',' + HexStr(F^.Edx, 8)
      + ')');
  Inc(SyscallCount);
  If (Nr < 0) Or (Nr >= MaxSys) Then
    R := -ENOSYS
  Else
  Begin
    Fn := SysFn[Nr];
    If Fn = 0 Then R := -ENOSYS
    Else
      Case SysArgc[Nr] Of
        0 : R := Call0(Fn);
        1 : R := Call1(Fn, F^.Ebx);
        2 : R := Call2(Fn, F^.Ebx, F^.Ecx);
        3 : R := Call3(Fn, F^.Ebx, F^.Ecx, F^.Edx);
        4 : R := Call4(Fn, F^.Ebx, F^.Ecx, F^.Edx, F^.Esi);
        5 : R := Call5(Fn, F^.Ebx, F^.Ecx, F^.Edx, F^.Esi, F^.Edi);
      Else
        R := Call6(Fn, F^.Ebx, F^.Ecx, F^.Edx, F^.Esi, F^.Edi, F^.Ebp);
      End;
  End;
  F^.Eax := R;
End;

{ ---- Exceptions ---- }

Function ExcSignal(Vec : LongInt) : LongInt;
Begin
  Case Vec Of
    0, 16, 19 : ExcSignal := SIGFPE;
    1, 3 : ExcSignal := SIGTRAP;
    6 : ExcSignal := SIGILL;
    17 : ExcSignal := SIGBUS;
  Else
    ExcSignal := SIGSEGV;
  End;
End;

Procedure KernelOops(F : PFrame; Const Why : String);
Begin
  LogToVc := True;
  KLog('');
  KLog('Oops : ' + Why + ' (pid ' + IntStr(Cur^.Pid) + ')');
  DumpFrame(F, ReadCr2);
  Backtrace(F^.Ebp);
  KPanic('exception dans le noyau');
End;

Procedure DoException(F : PFrame);
Var V, Addr, R, Sig : LongInt; FromUser, Write : Boolean; Esp : LongInt;
Begin
  V := F^.Vec;
  FromUser := (F^.Cs And 3) = 3;
  If V = 14 Then
  Begin
    Addr := ReadCr2;
    Write := (F^.Err And 2) <> 0;
    If FromUser Then Esp := F^.UserEsp Else Esp := 0;
    If (CurMm <> Nil) And ULt(Addr, UserTop) And ((F^.Err And 1 = 0)
        Or Write) Then
      R := MmFault(CurMm, Addr, Write, Esp)
    Else If (CurMm <> Nil) And ULt(Addr, UserTop) Then R := MmFault(CurMm,
        Addr, Write, Esp)
    Else R := 1;
    If KDebug Then KLog('pf pid=' + IntStr(Cur^.Pid) + ' addr=' + HexStr(Addr,
        8) + ' err=' + HexStr(F^.Err, 2) + ' eip=' + HexStr(F^.Eip, 8) + ' -> '
        + IntStr(R));
    If R = 0 Then Exit;
    If Not FromUser Then
      KernelOops(F, 'faute de page dans le noyau a l''adresse ' + HexStr(Addr,
          8));
    If R = 3 Then
    Begin
      KLog('pid ' + IntStr(Cur^.Pid) + ' : memoire insuffisante');
      ForceSig(Cur, SIGKILL);
      Exit;
    End;
    If R = 1 Then KLog('pid ' + IntStr(Cur^.Pid) + ' segfault a '
        + HexStr(Addr, 8) + ' ip ' + HexStr(F^.Eip, 8))
    Else KLog('pid ' + IntStr(Cur^.Pid) + ' violation de protection a '
        + HexStr(Addr, 8) + ' ip ' + HexStr(F^.Eip, 8));
    ForceSig(Cur, SIGSEGV);
    Exit;
  End;
  If Not FromUser Then KernelOops(F, 'exception ' + IntStr(V));
  If V = 16 Then
  Begin
    asm
      db 219,226
    end;
  End;
  If V <> 2 Then
  Begin
    KLog('pid ' + IntStr(Cur^.Pid) + ' : exception ' + IntStr(V) + ' ip '
        + HexStr(F^.Eip, 8));
    ForceSig(Cur, ExcSignal(V));
  End;
End;

Procedure DumpTasks;
Var I : LongInt;
Begin
  KLog('--- taches (cur=' + IntStr(Cur^.Pid) + ') ---');
  For I := 0 To MaxTasks - 1 Do
    If Tasks[I].State <> TsFree Then
      KLog('  pid ' + IntStr(Tasks[I].Pid) + ' etat ' + IntStr(Tasks[I].State)
          + ' chan ' +
           HexStr(Tasks[I].WaitChan, 8) + ' cnt ' + IntStr(Tasks[I].Counter));
End;

Procedure DoIrq(N : LongInt; FromUser : Boolean);
Begin
  IrqAck(N);
  Case N Of
    0 : Begin
          TimerTick(FromUser);
          If KDebug And (Jiffies Mod 500 = 0) Then DumpTasks;
        End;
    1 : KbdIrq;
    4 : SerialIrq;
  End;
End;

Procedure ReboutDummy;
Begin
End;

{ Fin du traitement d'une entree depuis le mode utilisateur }
Procedure ReturnToUser(F : PFrame);
Begin
  If CtrlAltDel Then
  Begin
    CtrlAltDel := False;
    VfsShutdown;
    RebootCpu;
  End;
  If NeedResched Then Schedule;
  HandleSignals(F);
  While NeedResched Do
  Begin
    Schedule;
    HandleSignals(F);
  End;
End;

{ Point d'entree commun appele par le code genere (voir partie 4) }
Procedure KTrap(Fp : LongInt);
Var F : PFrame; V : LongInt; FromUser : Boolean;
Begin
  F := Pointer(Fp);
  V := F^.Vec;
  FromUser := (F^.Cs And 3) = 3;
  If FromUser Then Cur^.Frame := Fp;
  If V = VecSyscall Then DoSyscall(F)
  Else If V < 32 Then DoException(F)
  Else If V < 48 Then DoIrq(V - 32, FromUser)
  Else KernelOops(F, 'vecteur inconnu');
  If FromUser Then ReturnToUser(F);
End;

{ Sauter dans le code de retour d'interruption avec le cadre Fp }
Procedure JumpToUser(Fp : LongInt);
Begin
  asm
    mov ecx,Fp
    mov eax,RetTrapEntry
    mov esp,ecx
    jmp eax
  end;
End;

{ ==================================================================== }
{ Partie 17 - Programmes embarques, init, programme principal          }
{ ==================================================================== }

Const
  MakeDevMul = 256;

Function MkDev(Maj, Min : LongInt) : LongInt;
Begin
  MkDev := (Maj Shl 8) Or Min;
End;

{ ---- Aides noyau pour creer l'arborescence ---- }

Function KMkdir(Const P : String; Mode : LongInt) : LongInt;
Begin
  KMkdir := VfsCreateNode(P, Mode, 0, True);
End;

Function KMknod(Const P : String; Mode, Rdev : LongInt) : LongInt;
Begin
  KMknod := VfsCreateNode(P, Mode, Rdev, False);
End;

{ Creer un fichier ordinaire avec son contenu (noyau) }
Procedure KWriteFile(Const P : String; Mode, Data, Len : LongInt);
Var F : PFile; R : LongInt;
Begin
  R := VfsOpen(P, O_CREAT Or O_WRONLY Or O_TRUNC, Mode, F);
  If R <> 0 Then
  Begin
    KLog('KWriteFile ' + P + ' : erreur ' + IntStr(R));
    Exit;
  End;
  If Len > 0 Then VfsWrite(F, Data, Len);
  FilePut(LongInt(F));
End;

Procedure KWriteStr(Const P : String; Mode : LongInt; Const S : String);
Var T : String;
Begin
  T := S;
  KWriteFile(P, Mode, LongInt(@T) + 1, Length(T));
End;

Procedure MountRoot;
Var T, R : LongInt; Sb : PSuper; Dn : String;
Begin
  T := FindFsType('tmpfs');
  Sb := SuperNew(T);
  Dn := 'rootfs';
  Sb^.DevName := KMalloc(Length(Dn) + 1);
  MemCopy(Sb^.DevName, LongInt(@Dn), Length(Dn) + 1);
  R := Call4(FsMount[T], LongInt(Sb), LongInt(@Dn), 0, 0);
  If R <> 0 Then KPanic('impossible de creer la racine');
  RootDentry := Sb^.Root;
  DentryGet(LongInt(RootDentry));
  IdleTask^.Fs := FsNew;
  IdleTask^.Fs^.Root := RootDentry;
  IdleTask^.Fs^.Pwd := RootDentry;
  DentryGet(LongInt(RootDentry));
  DentryGet(LongInt(RootDentry));
  IdleTask^.Fs^.Umask := 0;
End;

Procedure MakeDevNodes;
Var I, D, P : LongInt; S : String;
Begin
  KMknod('/dev/null', S_IFCHR Or $1B6, MkDev(1, 3));
  KMknod('/dev/zero', S_IFCHR Or $1B6, MkDev(1, 5));
  KMknod('/dev/full', S_IFCHR Or $1B6, MkDev(1, 7));
  KMknod('/dev/random', S_IFCHR Or $1B6, MkDev(1, 8));
  KMknod('/dev/urandom', S_IFCHR Or $1B6, MkDev(1, 9));
  KMknod('/dev/console', S_IFCHR Or $1B6, MkDev(5, 1));
  KMknod('/dev/tty', S_IFCHR Or $1B6, MkDev(5, 0));
  KMknod('/dev/tty0', S_IFCHR Or $1B6, MkDev(4, 0));
  For I := 1 To NVc Do KMknod('/dev/tty' + IntStr(I), S_IFCHR Or $1B6, MkDev(4,
      I));
  KMknod('/dev/ttyS0', S_IFCHR Or $1B6, MkDev(4, 64));
  KMknod('/dev/ram0', S_IFBLK Or $1B0, MkDev(1, 0));
  For D := 0 To 3 Do
    If DiskPresent[D] Then
    Begin
      If D < 2 Then S := 'hd' + Chr(97 + D) Else S := 'hd' + Chr(97 + D);
      If D < 2 Then KMknod('/dev/' + S, S_IFBLK Or $1B0, MkDev(3, D * 64))
      Else KMknod('/dev/' + S, S_IFBLK Or $1B0, MkDev(22, (D - 2) * 64));
      For P := 1 To 15 Do
        If PartSize[D * 16 + P] > 0 Then
        Begin
          If D < 2 Then KMknod('/dev/' + S + IntStr(P), S_IFBLK Or $1B0,
              MkDev(3, D * 64 + P))
          Else KMknod('/dev/' + S + IntStr(P), S_IFBLK Or $1B0, MkDev(22, (D
              - 2) * 64 + P));
        End;
    End;
End;

Procedure MakeTree;
Begin
  KMkdir('/dev', $1ED); KMkdir('/proc', $1ED); KMkdir('/sys', $1ED);
  KMkdir('/tmp', $3FF); KMkdir('/mnt', $1ED); KMkdir('/root', $1C0);
  KMkdir('/home', $1ED); KMkdir('/etc', $1ED); KMkdir('/bin', $1ED);
  KMkdir('/sbin', $1ED); KMkdir('/usr', $1ED); KMkdir('/usr/bin', $1ED);
  KMkdir('/usr/sbin', $1ED); KMkdir('/var', $1ED); KMkdir('/lib', $1ED);
  KMkdir('/boot', $1ED);
  VfsMount('devfs', '/dev', 'devtmpfs', 0, 0);
  VfsMount('proc', '/proc', 'proc', 0, 0);
  MakeDevNodes;
End;

{ Programmes embarques : decodage base64 d'un tableau de chaines }
Function B64Val(C : LongInt) : LongInt;
Begin
  If (C >= 65) And (C <= 90) Then B64Val := C - 65
  Else If (C >= 97) And (C <= 122) Then B64Val := C - 97 + 26
  Else If (C >= 48) And (C <= 57) Then B64Val := C - 48 + 52
  Else If C = 43 Then B64Val := 62
  Else If C = 47 Then B64Val := 63
  Else B64Val := -1;
End;

{ BEGIN-EMBED }
{ Programmes embarques (genere par TESTS/K/MKEMBED.PY) : ELF i386 statiques
  encodes en base64, ecrits dans le tmpfs racine au demarrage. }

Const
  EmbCount = 15;
  EmbPath : Array[0..14] Of String[20] = (
    '/sbin/init',
    '/bin/hello',
    '/bin/forkwait',
    '/bin/pipetest',
    '/bin/sigtest',
    '/bin/mmaptest',
    '/bin/dirtest',
    '/bin/ttytest',
    '/bin/schedtest',
    '/bin/blktest',
    '/bin/misctest',
    '/bin/proctest',
    '/bin/stress',
    '/bin/kbdtest',
    '/bin/ext2test');
  EmbSize : Array[0..14] Of LongInt = (
    3160, 1632, 1900, 2204, 2196, 2200, 3884, 1644, 1588, 2232, 4380, 2660,
    2256, 1040, 11872);
  EmbStart : Array[0..15] Of LongInt = (
    0, 71, 108, 151, 200, 249, 298, 385, 422, 458, 508, 606, 666, 717, 741,
    1005);
  EmbData : Array[0..1004] Of String[60] = (
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAa4UECDQAAABACwAAAAAAADQAIAAC',
    'ACgABwAGAAEAAAAAAAAAAIAECACABAiYCQAAmAkAAAUAAAAAEAAAUeV0ZAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAABgAAABAAAABVuBQAAACJ5VdWU4Pk8IHskAUA',
    'AM2ASHQUuDiHBAjoHgUAALgBAAAA6bsEAAC4QgAAAM2AuFiHBAgx/zHb6P8E',
    'AACLDJ1giQQIhcl0XzHSiYwkkAEAAInIQ4mUJJQBAACNlCSQAQAAiUwkDOja',
    'BAAAica4iYcECOjFBAAAi0QkDOi8BAAAuJGHBAiF9nQXuJaHBAhH6KgEAACJ',
    '8Og8BQAAuDaHBAjolwQAAOuWuKSHBAjoiwQAAInY6B8FAAC4t4cECOh6BAAA',
    'ifjoDgUAALg2hwQI6GkEAACDfQgBfjOLRQy6vocECItABOgWBAAAicaFwHUd',
    'uCQAAADNgLhYAAAAu63e4f65aRkSKLrc/iFDzYAx0r4FAAAAu8eHBAiJ8InR',
    'zYCJxoXAeQq41YcECOlAAQAAjYwkkAEAALr/AAAAuAMAAACJ882AiUQkDLgG',
    'AAAAzYCDfCQMAH7Pi0QkDInPxoQEkAEAAAC4BwAAACnIiUQkCItEJAgB+DlE',
    'JAx+qjHAipAGiAQIOBQHdSVAg/gIde+4JAAAAM2AuFgAAAC7rd7h/rlpGRIo',
    'Mfa63P4hQ82AR+u/D4QsAwAAuA+IBAgx2+h7AwAAuAMAAAC6/wAAAI2MJJAA',
    'AADNgIXAfteAvASPAAAACsaEBJAAAAAAdQjGhASPAAAAADH2gDkAdX8xwIlE',
    'tBCF9nSyi3wkELoSiAQIifjo7AIAAIXAD4SDAAAAur6HBAiJ+OjYAgAAhcB0',
    'c7oXiAQIifjoyAIAAIXAD4SiAgAAuhyIBAiJ+Oi0AgAAhcB1c04PhF////+L',
    'XCQUuAwAAADNgIXAD4lM////uB+IBAjoyQIAAOk9////igE8IHUHQcZB/wDr',
    '84TAD4Rn////RolMtAz2Ad8PhFn///9B6/S4JAAAAM2AuFgAAAC7rd7h/rlp',
    'GRIoMfa63P4hQ82A6fP+//+6K4gECIn46DECAACFwHUfjZwkkAEAALi3AAAA',
    'ucgAAADNgInY6FACAADpTwEAALoviAQIifjoAgIAAIXAD4WMAAAATrszhwQI',
    'dASLXCQUuQAAAQAx0rgFAAAAzYCJRCQMhcB5PLgyiAQI6T3///+NhCSQAQAA',
    'jTwYjUcT6PkBAACAfxIEuTWHBAi4NocECA9EwejjAQAAD7dHEAHDOfN8zr7c',
    'AAAAi1wkDLoABAAAjYwkkAEAAInwzYCJxoXAfgQx2+uri1wkDLgGAAAA62+6',
    'PogECIn46GIBAACD/gEPlcOFwHVghNt0XDHSvgUAAACLXCQUifCJ0c2AicaF',
    'wHgJjYwkkAEAAOsKuEKIBAjpmf7//78DAAAAugACAACJ84n4zYCJx4XAfhC4',
    'BAAAALsBAAAAifrNgOvauAYAAADNgOmu/f//uk+IBAiJ+OjsAAAAhcB1M7sB',
    'AAAAOfN9IItEnBBD6BIBAAA587oQiAQIuDeHBAgPTMLo/gAAAOvcuDaHBAjp',
    'JP7//7pUiAQIifjoqQAAAIXAdSaE23Qii1wkFLgnAAAAue0BAADNgIXAD4k/',
    '/f//uFqIBAjp7v3//7ppiAQIifjocwAAAIXAdSGE23Qdi1wkFLgKAAAAzYCF',
    'wA+JDv3//7hsiAQI6b39//+NVCQQifjoiQAAAInDhcAPhO/8//+4eIgECOhs',
    'AAAAidjoAAEAALiBiAQI6Y39//8xwI1l9FteX13DuK0AAADNgDHtieCD5PBQ',
    '6DUBAABVieVWicZTMdsPtgQeD7YMGoTAdAVDOMh071spyF5dw1WJ0THSieVT',
    'icOAPBEAdANC6/e4BAAAAM2AW13DicK4AQAAAOvaVYnlV1ZTg+wsiUXUuAIA',
    'AACJVdDNgIXAdViNfdi+QIkECLkEAAAAi13U86WNVdi4CwAAAItN0M2AuuCG',
    'BAi4AgAAALt/AAAA6I3///+LVdS4AgAAAOiA////uumGBAi4AgAAAOhx////',
    'uAEAAADNgOv+icO4/////3gPjU3YuAcAAAAx0s2Ai0XYg8QsW15fXcNVieVW',
    'U4nDg+wwxkX3AIXAeQ732LkhAAAAvgoAAADrDXXyxkX2MLkgAAAA6x+FwHQR',
    'MdJJ9/aKkiKHBAiIVA3W6+uF23kGxkQN1S1JjUXWAcjoD////4PEMFteXcNV',
    'ieVTg+wIi0UIixCNSASNRJAIUFFS6Kz5//+Jw7gBAAAAzYCDxBDr/gAAAAAA',
    'AAAAAABleGVjdmU6IAAgOiBlY2hlYwoAUEFUSD0vYmluOi9zYmluOi91c3Iv',
    'YmluAEhPTUU9L3Jvb3QAVEVSTT1saW51eAAwMTIzNDU2Nzg5YWJjZGVmAC4A',
    'LwoAaW5pdDogZG9pdCBldHJlIGxlIHByb2Nlc3N1cyAxCgAKPT09IExJTlVY',
    'LTAgS0VSTkVMMzIgOiBpbml0IChiYW5jIGQnZXNzYWkpID09PQoAS1BST0c6',
    'IAAgT0sKACBGQUlMIHN0YXR1cz0AS1RFU1Q6IERPTkUgcHJvZ3M9ACBmYWls',
    'PQBwb3dlcm9mZgAvcHJvYy9jbWRsaW5lAEludGVycHJldGV1ciBkZSBjb21t',
    'YW5kZXMgKGhhbHQgcG91ciBhcnJldGVyKSA6CgBrMzJwb3dlcgAjIABoYWx0',
    'AGV4aXQAY2QAY2Q6IGVycmV1cgoAcHdkAGxzAGxzOiBlcnJldXIKAGNhdABj',
    'YXQ6IGVycmV1cgoAZWNobwBta2RpcgBta2RpcjogZXJyZXVyCgBybQBybTog',
    'ZXJyZXVyCgBbc3RhdHV0IABdCgAvYmluL2hlbGxvAC9iaW4vZm9ya3dhaXQA',
    'L2Jpbi9waXBldGVzdAAvYmluL3NpZ3Rlc3QAL2Jpbi9tbWFwdGVzdAAvYmlu',
    'L2RpcnRlc3QAL2Jpbi90dHl0ZXN0AC9iaW4vc2NoZWR0ZXN0AC9iaW4vYmxr',
    'dGVzdAAvYmluL21pc2N0ZXN0AC9iaW4vcHJvY3Rlc3QAL2Jpbi9zdHJlc3MA',
    'L2Jpbi9leHQydGVzdAAAAAAAAAAAAAAAAAAAAPOGBAgMhwQIF4cECAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAhIgECI+IBAidiAQIq4gECLiIBAjGiAQI04gECOCI',
    'BAjviAQI/IgECAqJBAgYiQQIJIkECAAAAABHQ0M6IChVYnVudHUgMTMuMy4w',
    'LTZ1YnVudHUyfjI0LjA0LjEpIDEzLjMuMAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'AQAAAAAAAAAAAAAABADx/wgAAAB4hQQIIAAAAAIAAQAPAAAAmIUECB0AAAAC',
    'AAEAFwAAALWFBAgJAAAAAgABABwAAAC+hQQIkgAAAAIAAQAgAAAAUIYECF0A',
    'AAACAAEAJQAAAGCJBAg4AAAAAQACACsAAACthgQIKQAAABIAAQAxAAAAZIUE',
    'CAAAAAAQAAEAQwAAAGuFBAgAAAAAEAABAD4AAACYmQQIAAAAABAAAgAsAAAA',
    'dIAECPAEAAASAAEASgAAAJiZBAgAAAAAEAACAFEAAACYmQQIAAAAABAAAgAA',
    'aW5pdC5jAHN0cmNtcABwdXRzX2ZkAHB1dHMAcnVuAHB1dGQAdGVzdHMAY21h',
    'aW4AX19yZXN0b3JlX3J0AF9fYnNzX3N0YXJ0AF9lZGF0YQBfZW5kAAAuc3lt',
    'dGFiAC5zdHJ0YWIALnNoc3RydGFiAC50ZXh0AC5yb2RhdGEALmNvbW1lbnQA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABsAAAAB',
    'AAAABgAAAHSABAh0AAAAYgYAAAAAAAAAAAAAAQAAAAAAAAAhAAAAAQAAAAIA',
    'AADghgQI4AYAALgCAAAAAAAAAAAAACAAAAAAAAAAKQAAAAEAAAAwAAAAAAAA',
    'AJgJAAAtAAAAAAAAAAAAAAABAAAAAQAAAAEAAAACAAAAAAAAAAAAAADICQAA',
    '8AAAAAUAAAAIAAAABAAAABAAAAAJAAAAAwAAAAAAAAAAAAAAuAoAAFYAAAAA',
    'AAAAAAAAAAEAAAAAAAAAEQAAAAMAAAAAAAAAAAAAAA4LAAAyAAAAAAAAAAAA',
    'AAABAAAAAAAAAA==',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAEoIECDQAAAAgBQAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAiAAwAAgAMAAAUAAAAAEAAAAQAAAIAD',
    'AACAkwQIgJMECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW44IIECInlVlOD5PCB7JABAACLdQiLXQzojQEAADHS',
    'hfZ+CDHSgzsAD5XCuBuDBAjolQEAALgmgwQI6GsBAACLA+hkAQAAuBmDBAjo',
    'WgEAAE5+HLgxgwQI6E0BAACLQwToRQEAALgZgwQI6DsBAACLRRAx0osAhcB0',
    'CDHSgDhQD5TCuDyDBAiNXCQK6DoBAAC4egAAAM2AuEeDBAjoCQEAAInY6AIB',
    'AAC43oIECOj4AAAAjUQkS+jvAAAAuN6CBAjo5QAAAI2EJIwAAADo2QAAALje',
    'ggQI6M8AAACNhCTNAAAA6MMAAAC43oIECOi5AAAAjYQkDgEAAOitAAAAuBmD',
    'BAjoowAAAInYulGDBAjodwAAAInDhcB1L7pZgwQIjYQkjAAAAOhgAAAAhcB1',
    'HLpigwQIjYQkDgEAADHb6EkAAACFwA+Uw+sCMduJ2rhngwQI6HQAAAC4FAAA',
    'AM2AMdJIuHODBAgPn8LoXQAAAI1l+DHAW15dw7itAAAAzYAx7Yngg+TwUOiE',
    'AAAAVYnlVonGUzHbD7YEHg+2DBqEwHQFQzjIdO9bKcheXcNVicEx0onlU4A8',
    'EQB0A0Lr97gEAAAAuwEAAADNgFtdw1WJ5VaJxrjYggQIU4nT6M3///+J8OjG',
    '////hdu40YIECLrMggQID0XC6LL///+F23QI/wWEkwQI6wb/BYCTBAhbXl3D',
    'VYnlU4PsCItFCIsQjUgEjUSQCFBRUujW/f//icO4AQAAAM2Ag8QQ6/4gT0sK',
    'ACBGQUlMCgBLVEVTVDogAEJvbmpvdXIgZGUgTElOVVgtMCBLRVJORUwzMiAo',
    'cHJvZ3JhbW1lIEVMRiBpMzg2IHN0YXRpcXVlKQoAaGVsbG8uYXJndgAgIGFy',
    'Z3ZbMF09ACAgYXJndlsxXT0AaGVsbG8uZW52cAAgIHVuYW1lOiAATElOVVgt',
    'MABLRVJORUwzMgBpMzg2AGhlbGxvLnVuYW1lAGhlbGxvLmdldHBpZABHQ0M6',
    'IChVYnVudHUgMTMuMy4wLTZ1YnVudHUyfjI0LjA0LjEpIDEzLjMuMAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAABADx/wkAAAAfggQIIAAAAAIA',
    'AQAQAAAAP4IECCAAAAACAAEAFQAAAF+CBAhEAAAAAgABABsAAACEkwQIBAAA',
    'AAEAAwAjAAAAgJMECAQAAAABAAMAKwAAAKOCBAgpAAAAEgABADEAAAALggQI',
    'AAAAABAAAQBDAAAAEoIECAAAAAAQAAEAPgAAAICTBAgAAAAAEAADACwAAACU',
    'gAQIdwEAABIAAQBKAAAAgJMECAAAAAAQAAMAUQAAAIiTBAgAAAAAEAADAABo',
    'ZWxsby5jAHN0cmNtcABwdXRzAGt0ZXN0AGt1X3Bhc3MAa3VfZmFpbABjbWFp',
    'bgBfX3Jlc3RvcmVfcnQAX19ic3Nfc3RhcnQAX2VkYXRhAF9lbmQAAC5zeW10',
    'YWIALnN0cnRhYgAuc2hzdHJ0YWIALnRleHQALnJvZGF0YQAuYnNzAC5jb21t',
    'ZW50AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'AAAbAAAAAQAAAAYAAACUgAQIlAAAADgCAAAAAAAAAAAAAAEAAAAAAAAAIQAA',
    'AAEAAAAyAAAAzIIECMwCAAC0AAAAAAAAAAAAAAABAAAAAQAAACkAAAAIAAAA',
    'AwAAAICTBAiAAwAACAAAAAAAAAAAAAAABAAAAAAAAAAuAAAAAQAAADAAAAAA',
    'AAAAgAMAAC0AAAAAAAAAAAAAAAEAAAABAAAAAQAAAAIAAAAAAAAAAAAAALAD',
    'AADgAAAABgAAAAcAAAAEAAAAEAAAAAkAAAADAAAAAAAAAAAAAACQBAAAVgAA',
    'AAAAAAAAAAAAAQAAAAAAAAARAAAAAwAAAAAAAAAAAAAA5gQAADcAAAAAAAAA',
    'AAAAAAEAAAAAAAAA',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAW4MECDQAAAAsBgAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAigBAAAoAQAAAUAAAAAEAAAAQAAAKAE',
    'AACglAQIoJQECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFWJ5VdWMfZTg+Twg+wwiXQkBL4CAAAAifDNgIXAdQ64',
    'AQAAALsHAAAAzYDr/g+fwonDvwcAAAC4CYQECA+20uiwAgAAifiNTCQEMdLN',
    'gDHSOcO4EoQECA+UwuiVAgAAi0QkBDHSJX//AAA9AAcAALgbhAQID5TC6HgC',
    'AADHRCQIKgAAAInwzYCJw4XAdR3HRCQIYwAAAItEJAgx24P4Y7gBAAAAD5XD',
    'zYDr/on4jUwkBDHSzYCLRCQIg/gqdQox0oN8JAQAD5TCuCeEBAgx2+ggAgAA',
    'ugIAAACJ0M2AhcB1DIPDCrgBAAAAzYDr/olEnCBDg/sEdeK+CgAAAL8BAAAA',
    'i1y0+I1MJBQx0rgHAAAAzYA5RLT4dQ6LRCQUD7bEOfAPRfrrAjH/RoP+DnXT',
    'ifq4MIQECL4HAAAAg8v/6LIBAACJ8I1MJAQx0s2AMdKD+Pa/AgAAALg7hAQI',
    'D5TC6JEBAACJ+M2AicOFwHULuh0AAACJ0M2A6/q4JQAAALkJAAAAzYAx0onw',
    'jUwkBM2Ai0QkBDHSg+B/g/gJuEeEBAgPlMLoTQEAAIn4zYCJw4XAdTeJ+M2A',
    'icGFwHUkMdvHRCQYgPD6AriiAAAAiVwkFI1cJBTNgLgBAAAAicvNgOv+uAEA',
    'AADNgOv+ifCNTCQEMdLNgDHSg3wkBAC4VIQECA+UwujuAAAAifjNgIXAicON',
    'fCQMdUQx0jHJuAsAAAC7YIQECIlUJByJ+olMJBCNTCQUx0QkFGCEBAjHRCQY',
    'a4QECMdEJAxwhAQIzYC4AQAAALtjAAAAzYDr/onwjUwkBDHSzYAx0oN8JAQA',
    'uHqEBAi7h4QECA+Uwuh5AAAAMcCNTCQUifqJRCQYiUQkDLgLAAAAx0QkFIWE',
    'BAjNgDHSg/j+uJSEBAgPlMLoSAAAADHAgz2glAQIAA+VwI1l9FteX13DuK0A',
    'AADNgDHtieCD5PBQ6GQAAABVicEx0onlU4A8EQB0A0Lr97gEAAAAuwEAAADN',
    'gFtdw1WJ5VaJxrgBhAQIU4nT6M3///+J8OjG////hdu4+oMECLr1gwQID0XC',
    '6LL///+F23QI/wWklAQI6wb/BaCUBAhbXl3DVYnlU4PsCItFCIsQjUgEjUSQ',
    'CFBRUuit/P//icO4AQAAAM2Ag8QQ6/4gT0sKACBGQUlMCgBLVEVTVDogAGZv',
    'cmsucGlkAHdhaXQucGlkAHdhaXQuc3RhdHVzAGZvcmsuY293AGZvcmsubXVs',
    'dGkAd2FpdC5lY2hpbGQAd2FpdC5zaWdraWxsAGZvcmsub3JwaGFuAC9iaW4v',
    'aGVsbG8AYXJnMQBQQVRIPS9iaW4AZXhlYy5oZWxsbwB4AC9iaW4vbmV4aXN0',
    'ZQBleGVjLmVub2VudABHQ0M6IChVYnVudHUgMTMuMy4wLTZ1YnVudHUyfjI0',
    'LjA0LjEpIDEzLjMuMAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAA',
    'BADx/wwAAABogwQIIAAAAAIAAQARAAAAiIMECEQAAAACAAEAFwAAAKSUBAgE',
    'AAAAAQADAB8AAACglAQIBAAAAAEAAwAnAAAAzIMECCkAAAASAAEALQAAAFSD',
    'BAgAAAAAEAABAD8AAABbgwQIAAAAABAAAQA6AAAAoJQECAAAAAAQAAMAKAAA',
    'AJSABAjAAgAAEgABAEYAAACglAQIAAAAABAAAwBNAAAAqJQECAAAAAAQAAMA',
    'AGZvcmt3YWl0LmMAcHV0cwBrdGVzdABrdV9wYXNzAGt1X2ZhaWwAY21haW4A',
    'X19yZXN0b3JlX3J0AF9fYnNzX3N0YXJ0AF9lZGF0YQBfZW5kAAAuc3ltdGFi',
    'AC5zdHJ0YWIALnNoc3RydGFiAC50ZXh0AC5yb2RhdGEALmJzcwAuY29tbWVu',
    'dAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'GwAAAAEAAAAGAAAAlIAECJQAAABhAwAAAAAAAAAAAAABAAAAAAAAACEAAAAB',
    'AAAAMgAAAPWDBAj1AwAAqwAAAAAAAAAAAAAAAQAAAAEAAAApAAAACAAAAAMA',
    'AACglAQIoAQAAAgAAAAAAAAAAAAAAAQAAAAAAAAALgAAAAEAAAAwAAAAAAAA',
    'AKAEAAAtAAAAAAAAAAAAAAABAAAAAQAAAAEAAAACAAAAAAAAAAAAAADQBAAA',
    '0AAAAAYAAAAGAAAABAAAABAAAAAJAAAAAwAAAAAAAAAAAAAAoAUAAFIAAAAA',
    'AAAAAAAAAAEAAAAAAAAAEQAAAAMAAAAAAAAAAAAAAPIFAAA3AAAAAAAAAAAA',
    'AAABAAAAAAAAAA==',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAANYQECDQAAABcBwAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAiPBQAAjwUAAAUAAAAAEAAAAQAAAJAF',
    'AACQlQQIkJUECAAAAAAMAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW4KgAAAInlV1ZTg+Twg+xwjVwkFM2AMdKFwLgQhQQI',
    'D5TC6NMDAAC4AgAAAM2AiUQkDIXAdUa+BgAAAItcJBSJ8M2AvwQAAAC6BQAA',
    'AItcJBi5HIUECIn4zYC5J4UECIn4i1wkGM2AifCLXCQYzYC4AQAAAItcJAzN',
    'gOv+i1wkGLgGAAAAzYC/AwAAAItcJBS6QAAAAI1MJDCJ+M2AjUj/icYxwIP5',
    'PncYjUQkMCnyi1wkFI0MMIn4zYAx0oXAD0jCAfAx0sZEBDAAg/gKdRW6IoUE',
    'CI1EJDDo0AIAADHShcAPlMK4LYUECOgMAwAAi1wkFLgDAAAAugoAAACNTCQw',
    'zYAx0oXAuDeFBAgPlMLo5wIAAItcJAwx0rgHAAAAjUwkEM2AuQYAAACLXCQU',
    'icjNgLgqAAAAjVwkFM2Ai1wkFInIzYC7DQAAADHAjUwkHL4IAAAAiUQkLIlE',
    'JCi4rgAAAMdEJBxihAQIx0QkIAQAAATHRCQkLoQECM2AuAQAAACLXCQYuUCF',
    'BAi6AQAAAM2AMdKD+OB1DaGQlQQIMdKD+A0PlMK4QoUECL4GAAAA6EcCAACL',
    'XCQYifDNgLgqAAAAjVwkFM2AuAIAAADNgIXAiUQkDInwdTSLXCQUzYC/AQAA',
    'ALg/AAAAi1wkGIn5zYCJ8ItcJBjNgLhNhQQI6NkBAACJ+ItcJAzNgOv+i1wk',
    'GM2AvwMAAACLXCQUjUwkMLpAAAAAifjNgDHShcCLXCQMjUwkEA9IwsZEBDAA',
    'uAcAAADNgItcJBSJ8M2Auk2FBAiNRCQwu2CFBAjoUAEAADHShcC4VoUECA+U',
    'wuiMAQAAuA4AAAC5gBEAADHSzYAx0oXAuGiFBAgPlMLobQEAALgCAAAAzYCJ',
    'RCQMhcB1Pb8FAAAAuQEAAACLVCQMifjNgLlzhQQIiUQkCIn6uAQAAACLXCQI',
    'zYCJ8ItcJAjNgLgBAAAAi1wkDM2A6/4xybgFAAAAu2CFBAiJys2AukAAAACJ',
    'w41MJDCJ+M2AMdKFwA9IwsZEBDAAifDNgLgHAAAAi1wkDI1MJBDNgLpzhQQI',
    'jUQkMLtghQQI6IMAAAAx0oXAuHmFBAgPlMLovwAAALgKAAAAzYC4KgAAAI1c',
    'JBTNgLg3AAAAi1wkFLkEAAAAugAIAADNgLoBAAAAi1wkFIn4jUwkMM2AMdKD',
    '+PW4g4UECA+Uwuh1AAAAMcCDPZSVBAgAD5XAjWX0W15fXcO4rQAAAM2AMe2J',
    '4IPk8FDokQAAAFWJ5VaJxlMx2w+2BB4PtgwahMB0BUM4yHTvWynIXl3DVYnl',
    'i0UIXaOQlQQIw1WJwTHSieVTgDwRAHQDQuv3uAQAAAC7AQAAAM2AW13DVYnl',
    'VonGuAiFBAhTidPozf///4nw6Mb///+F27gBhQQIuvyEBAgPRcLosv///4Xb',
    'dAj/BZiVBAjrBv8FlJUECFteXcNVieVTg+wIi0UIixCNSASNRJAIUFFS6Kb7',
    '//+Jw7gBAAAAzYCDxBDr/iBPSwoAIEZBSUwKAEtURVNUOiAAcGlwZS5jcmVh',
    'dGUAc2FsdXQAc2FsdXQgdHViZQBwaXBlLmRhdGEAcGlwZS5lb2YAeABwaXBl',
    'LmVwaXBlAHZpYSBkdXAyAHBpcGUuZHVwMgAvdG1wL2ZmAGZpZm8ubWtub2QA',
    'ZmlmbyEAZmlmby5kYXRhAHBpcGUuZWFnYWluAEdDQzogKFVidW50dSAxMy4z',
    'LjAtNnVidW50dTJ+MjQuMDQuMSkgMTMuMy4wAAAAAAAAAAAAAAAAAAAAAAAB',
    'AAAAAAAAAAAAAAAEAPH/DAAAAEKEBAggAAAAAgABABMAAABihAQIDQAAAAIA',
    'AQAaAAAAkJUECAQAAAABAAMAIwAAAG+EBAggAAAAAgABACgAAACPhAQIRAAA',
    'AAIAAQAuAAAAmJUECAQAAAABAAMANgAAAJSVBAgEAAAAAQADAD4AAADThAQI',
    'KQAAABIAAQBEAAAALoQECAAAAAAQAAEAVgAAADWEBAgAAAAAEAABAFEAAACQ',
    'lQQIAAAAABAAAwA/AAAAlIAECJoDAAASAAEAXQAAAI+VBAgAAAAAEAADAGQA',
    'AACclQQIAAAAABAAAwAAcGlwZXRlc3QuYwBzdHJjbXAAb25waXBlAGdvdF9w',
    'aXBlAHB1dHMAa3Rlc3QAa3VfcGFzcwBrdV9mYWlsAGNtYWluAF9fcmVzdG9y',
    'ZV9ydABfX2Jzc19zdGFydABfZWRhdGEAX2VuZAAALnN5bXRhYgAuc3RydGFi',
    'AC5zaHN0cnRhYgAudGV4dAAucm9kYXRhAC5ic3MALmNvbW1lbnQAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABsAAAABAAAABgAA',
    'AJSABAiUAAAAaAQAAAAAAAAAAAAAAQAAAAAAAAAhAAAAAQAAADIAAAD8hAQI',
    '/AQAAJMAAAAAAAAAAAAAAAEAAAABAAAAKQAAAAgAAAADAAAAkJUECJAFAAAM',
    'AAAAAAAAAAAAAAAEAAAAAAAAAC4AAAABAAAAMAAAAAAAAACPBQAALQAAAAAA',
    'AAAAAAAAAQAAAAEAAAABAAAAAgAAAAAAAAAAAAAAvAUAAAABAAAGAAAACQAA',
    'AAQAAAAQAAAACQAAAAMAAAAAAAAAAAAAALwGAABpAAAAAAAAAAAAAAABAAAA',
    'AAAAABEAAAADAAAAAAAAAAAAAAAlBwAANwAAAAAAAAAAAAAAAQAAAAAAAAA=',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAANoMECDQAAABUBwAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAjyBAAA8gQAAAUAAAAAEAAAAQAAAPQE',
    'AAD0lAQI9JQECAAAAAAcAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW6Q4MECLgKAAAAieVXVlOD5PCD7BDoSwMAALgUAAAA',
    'zYC5CgAAAInDuCUAAADNgKEElQQISHUPoQCVBAgx0oP4Cg+UwusCMdK4coQE',
    'CL+vAAAAMdu+CAAAAOjDAgAAMdKJ+I1MJAiJVCQMidrHRCQIAAIAAM2AuBQA',
    'AADNgLkKAAAAicO4JQAAAM2AoQSVBAgx0rsBAAAASLh+hAQID5TC6HwCAAAx',
    'yYn4MdKJTCQMjUwkCMdEJAgAAgAAzYChBJUECDHSg/gCuIqEBAgPlMLoTQIA',
    'ALpbgwQIuA4AAADoggIAALgbAAAAzYC4HQAAAM2AofyUBAgx0r8CAAAASLiW',
    'hAQID5TC6BYCAAC6Z4MECLgRAAAA6EsCAACJ+M2AicOFwHUJuAEAAADNgOv+',
    'vgcAAACNTCQIMdKJ8M2AofiUBAgx0oXAuKCEBAgPn8LozwEAADHSuBEAAADo',
    'BwIAALoBAAAAuAwAAADo+AEAALgUAAAAzYC5DAAAAInDuCUAAADNgLoBAAAA',
    'uKyEBAjokAEAAIn4zYCJw4XAdSMx0rgMAAAA6L4BAAC4FAAAAM2AuQwAAACJ',
    'w7glAAAAzYDr/onwjUwkCDHSzYCLRCQIMdKD4H+D+Ay4t4QECA+UwuhAAQAA',
    'ifjNgInDhcB1GLpzgwQIuAsAAADoawEAADHAowAAAAAPC4nwjUwkCDHSzYAx',
    '0oN8JAgAuMiEBAgPlMLoAAEAAIn4zYCJw4XAdRjHBRAAAAABAAAAuAEAAAC7',
    'BQAAAM2A6/6J8I1MJAgx0s2Ai0QkCDHSuzB1AACD4H+D+Au42YQECA+Uwui2',
    'AAAAuCUAAAAxyc2AMdKD+P246IQECA+UwuibAAAAMcCDPQiVBAgAD5XAjWX0',
    'W15fXcO4rQAAAM2AMe2J4IPk8FDo8gAAAFWhBJUECECJ5aMElQQIi0UIXaMA',
    'lQQIw6H8lAQIQKP8lAQIw6H4lAQIQKP4lAQIw1Wh9JQECECJ5VMx26P0lAQI',
    'ofSUBAhIuAEAAAAPlcPNgOv+VYnBMdKJ5VOAPBEAdANC6/e4BAAAALsBAAAA',
    'zYBbXcNVieVWica4aoQECFOJ0+jN////ifDoxv///4XbuGOEBAi6XoQECA9F',
    'wuiy////hdt0CP8FDJUECOsG/wUIlQQIW15dw1WJ5Va+CAAAAFOJwzHAjU3k',
    'g+wgiVXkMdKJRfSJRfC4rgAAAMdF6AQAAATHRewvgwQIzYCDxCBbXl3DVYnl',
    'U4PsCItFCIsQjUgEjUSQCFBRUuhE/P//icO4AQAAAM2Ag8QQ6/4gT0sKACBG',
    'QUlMCgBLVEVTVDogAHNpZy5oYW5kbGVyAHNpZy5ibG9ja2VkAHNpZy51bmJs',
    'b2NrAHNpZy5hbGFybQBzaWcuc2lnY2hsZABzaWcuaWdub3JlAHNpZy5kZWZh',
    'dWx0X3Rlcm0Ac2lnLnNlZ3ZfaGFuZGxlcgBzaWcuc2Vndl9mYXRhbABzaWcu',
    'ZXNyY2gAR0NDOiAoVWJ1bnR1IDEzLjMuMC02dWJ1bnR1Mn4yNC4wNC4xKSAx',
    'My4zLjAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAEAPH/CwAAAEOD',
    'BAgYAAAAAgABAA4AAAAElQQIBAAAAAEAAwASAAAAAJUECAQAAAABAAMAFwAA',
    'AFuDBAgMAAAAAgABABgAAAD8lAQIBAAAAAEAAwAdAAAAZ4MECAwAAAACAAEA',
    'HgAAAPiUBAgEAAAAAQADACMAAABzgwQIIwAAAAIAAQAkAAAA9JQECAQAAAAB',
    'AAMAKQAAAJaDBAggAAAAAgABAC4AAAC2gwQIRAAAAAIAAQA0AAAADJUECAQA',
    'AAABAAMAPAAAAAiVBAgEAAAAAQADAEQAAAD6gwQIOwAAAAIAAQBiAAAANYQE',
    'CCkAAAASAAEAaAAAAC+DBAgAAAAAEAABAHoAAAA2gwQIAAAAABAAAQB1AAAA',
    '9JQECAAAAAAQAAMAYwAAAJSABAibAgAAEgABAIEAAADylAQIAAAAABAAAwCI',
    'AAAAEJUECAAAAAAQAAMAAHNpZ3Rlc3QuYwBoMQBjbnQAbGFzdABoYWxybQBo',
    'Y2hsZABoc2VndgBwdXRzAGt0ZXN0AGt1X3Bhc3MAa3VfZmFpbABzaWduYWxf',
    'c2V0LmNvbnN0cHJvcC4wLmlzcmEuMABjbWFpbgBfX3Jlc3RvcmVfcnQAX19i',
    'c3Nfc3RhcnQAX2VkYXRhAF9lbmQAAC5zeW10YWIALnN0cnRhYgAuc2hzdHJ0',
    'YWIALnRleHQALnJvZGF0YQAuYnNzAC5jb21tZW50AAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAbAAAAAQAAAAYAAACUgAQIlAAA',
    'AMoDAAAAAAAAAAAAAAEAAAAAAAAAIQAAAAEAAAAyAAAAXoQECF4EAACUAAAA',
    'AAAAAAAAAAABAAAAAQAAACkAAAAIAAAAAwAAAPSUBAj0BAAAHAAAAAAAAAAA',
    'AAAABAAAAAAAAAAuAAAAAQAAADAAAAAAAAAA8gQAAC0AAAAAAAAAAAAAAAEA',
    'AAABAAAAAQAAAAIAAAAAAAAAAAAAACAFAABwAQAABgAAABAAAAAEAAAAEAAA',
    'AAkAAAADAAAAAAAAAAAAAACQBgAAjQAAAAAAAAAAAAAAAQAAAAAAAAARAAAA',
    'AwAAAAAAAAAAAAAAHQcAADcAAAAAAAAAAAAAAAEAAAAAAAAA',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAa4QECDQAAABYBwAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAi8BQAAvAUAAAUAAAAAEAAAAQAAALwF',
    'AAC8lQQIvJUECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFWJ5VdWU4Pk8I2EJADg/P+B7AAQAACDDCQAOcR18oPs',
    'ILotAAAAMduJ0M2AicaNmAAwAACJ0M2AMdI5w7gohQQID5TC6MoDAADGBgHG',
    'hv8vAAACigb+yHUPiob/LwAAMdI8Ag+UwusCMdK4MYUECInz6J0DAAC4LQAA',
    'AM2AMdI5xrg4hQQID5TCMfYx24PP/+h+AwAAiXQkILkAgAAAugMAAAC+IgAA',
    'ALjAAAAAVYtsJCDNgF0x0oXAiUQkDLhDhQQID5/C6EkDAAC6AQAAADHAMcmL',
    'fCQMgDw4AA9F0UA9AIAAAHXtuE2FBAjoIwMAADHAicKLfCQMBQAQAADB+gxC',
    'iJQ4APD//z0AgAAAdeO6AQAAADH2McCJ8Yt8JAxGweEMD74MOTnxD0XQg/4I',
    'dei4V4UECOjZAgAAi0QkDLkAIAAAjZgAIAAAuFsAAADNgDHShcC4X4UECA+U',
    'wuiyAgAAuAIAAADNgInHhcB1TTHbx0QkIHiEBAiNTCQgifqJXCQwuK4AAACJ',
    'XCQsuwsAAADHRCQkBAAABMdEJChkhAQIzYCLRCQMuwMAAADGgAAgAAABuAEA',
    'AADNgOv+uAcAAACJ+41MJBgx0s2AMdKDfCQYALhmhQQID5TC6DUCAACLXCQM',
    'uH0AAAC5ABAAALoBAAAAzYAx0oXAuHKFBAgPlMLoDwIAALgCAAAAzYCJx4XA',
    'dUkxybiuAAAAuwsAAACJ+olMJDCJTCQsjUwkIMdEJCB4hAQIx0QkJAQAAATH',
    'RCQoZIQECM2Ai0QkDLsDAAAAxgAJuAEAAADNgOv+uAcAAACJ+41MJBgx0s2A',
    'MdKDfCQYALh7hQQID5TC6JYBAACLXCQMuH0AAAC6AwAAALkAEAAAzYCLRCQM',
    'xgALuAIAAADNgInDhcB1EItEJAzGABa4AQAAAM2A6/64BwAAAI1MJBgx0s2A',
    'i0QkDIA4C3UKMdKDfCQYAA+UwriHhQQI6DMBAADGRCQgATHSxoQkHyADAAKK',
    'RCQg/sh1DoqEJB8gAwAx0jwCD5TCuJCFBAi7wAAAAL4iAAAAg8//6PcAAAAx',
    'wLkAAEAAugMAAACJRCQcidgx21WLbCQczYBdxgABicO6AQAAAMaA//8/AAK4',
    'm4UECOjAAAAAuFsAAAC5AABAAM2AvwUAAAAxybukhQQIifiJys2AMdKJx7kA',
    'EAAAuMAAAACJVCQcvgIAAAC6AQAAADHbVYtsJBzNgF0x0oXAfhWAeAFFdQ+A',
    'eAJMdQkx0oB4A0YPlMK4soUECOhXAAAAMcCDPbyVBAgAD5XAjWX0W15fXcO4',
    'rQAAAM2AMe2J4IPk8FDocwAAAFW4AQAAAInlUzHbzYDr/lWJwTHSieVTgDwR',
    'AHQDQuv3uAQAAAC7AQAAAM2AW13DVYnlVonGuCCFBAhTidPozf///4nw6Mb/',
    '//+F27gZhQQIuhSFBAgPRcLosv///4XbdAj/BcCVBAjrBv8FvJUECFteXcNV',
    'ieVTg+wIi0UIixCNSASNRJAIUFFS6I77//+Jw7gBAAAAzYCDxBDr/iBPSwoA',
    'IEZBSUwKAEtURVNUOiAAYnJrLmdyb3cAYnJrLnJ3AGJyay5zaHJpbmsAbW1h',
    'cC5hbm9uAG1tYXAuemVybwBtbWFwLnJ3AG11bm1hcABtdW5tYXAuaG9sZQBt',
    'cHJvdGVjdABtcHJvdGVjdC5ybwBtbWFwLmNvdwBzdGFjay5ncm93AG1tYXAu',
    'NG1iAC9iaW4vbW1hcHRlc3QAbW1hcC5maWxlAEdDQzogKFVidW50dSAxMy4z',
    'LjAtNnVidW50dTJ+MjQuMDQuMSkgMTMuMy4wAAAAAAAAAAAAAAAAAAAAAAAA',
    'AAABAAAAAAAAAAAAAAAEAPH/DAAAAHiEBAgPAAAAAgABAA8AAACHhAQIIAAA',
    'AAIAAQAUAAAAp4QECEQAAAACAAEAGgAAAMCVBAgEAAAAAQADACIAAAC8lQQI',
    'BAAAAAEAAwAqAAAA64QECCkAAAASAAEAMAAAAGSEBAgAAAAAEAABAEIAAABr',
    'hAQIAAAAABAAAQA9AAAAvJUECAAAAAAQAAMAKwAAAJSABAjQAwAAEgABAEkA',
    'AAC8lQQIAAAAABAAAwBQAAAAxJUECAAAAAAQAAMAAG1tYXB0ZXN0LmMAaHMA',
    'cHV0cwBrdGVzdABrdV9wYXNzAGt1X2ZhaWwAY21haW4AX19yZXN0b3JlX3J0',
    'AF9fYnNzX3N0YXJ0AF9lZGF0YQBfZW5kAAAuc3ltdGFiAC5zdHJ0YWIALnNo',
    'c3RydGFiAC50ZXh0AC5yb2RhdGEALmJzcwAuY29tbWVudAAAAAAAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGwAAAAEAAAAGAAAAlIAE',
    'CJQAAACABAAAAAAAAAAAAAABAAAAAAAAACEAAAABAAAAMgAAABSFBAgUBQAA',
    'qAAAAAAAAAAAAAAAAQAAAAEAAAApAAAACAAAAAMAAAC8lQQIvAUAAAgAAAAA',
    'AAAAAAAAAAQAAAAAAAAALgAAAAEAAAAwAAAAAAAAALwFAAAtAAAAAAAAAAAA',
    'AAABAAAAAQAAAAEAAAACAAAAAAAAAAAAAADsBQAA4AAAAAYAAAAHAAAABAAA',
    'ABAAAAAJAAAAAwAAAAAAAAAAAAAAzAYAAFUAAAAAAAAAAAAAAAEAAAAAAAAA',
    'EQAAAAMAAAAAAAAAAAAAACEHAAA3AAAAAAAAAAAAAAABAAAAAAAAAA==',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAnIgECDQAAADsDQAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAgwDAAAMAwAAAUAAAAAEAAAAQAAADAM',
    'AAAwnAQIMJwECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW57QEAAInlV1a+JwAAAFOJ8LsQigQIg+TwgeygAQAA',
    'zYAx0oXAuBiKBAgPlMLoyAgAAInwue0BAADNgDHSg/jvvgUAAAC4HooECA+U',
    'wrsqigQI6KMIAAC5QgIAALqkAQAAifDNgInCica/BAAAALg4igQI99KJ88Hq',
    'H+h7CAAAifi5PooECLoKAAAAzYAx0oP4CrhJigQID5TC6FsIAAC5AwAAALgT',
    'AAAAMdLNgDHSg/gDuE+KBAgPlMLoOwgAALgDAAAAjUwkdIn6zYAx0oXAD0nQ',
    'xkQUdAAx0oP4BHUTulWKBAiJyOgpBwAAMdKFwA+UwrhaigQIifPo/AcAALgG',
    'AAAAzYC4wwAAALsqigQIjUwkFM2AicKFwHUjg3wkRAB1HoN8JEAKdReLRCQk',
    'MdIl//EAAD2kgQAAD5TC6wIx0rhfigQIu2aKBAjoqwcAALlCAAAAuoABAAC4',
    'BQAAAM2AiUQkDDH2vwQAAAC6LAEAAI1EJHSJwYnzQIgZjYwkoAEAADnIde6L',
    'XCQMifiNTCR0zYBGgf4sAQAAddUx0rgTAAAAi1wkDInRzYC+AQAAADH/uiwB',
    'AACLXCQMuAMAAACNTCR0zYA9LAEAAHUZifg4RCR0dRE4hCSfAQAAuAAAAAAP',
    'RfDrAjH2R4H/LAEAAHXGifK4b4oECOj+BgAAi1wkDLhdAAAAuWQAAADNgDHS',
    'hcC4d4oECA+UwujdBgAAi1wkDLjFAAAAjUwkFM2Ai0QkQDHSg/BkC0QkRLiB',
    'igQID5TC6LQGAACLXCQMuAYAAADNgLgKAAAAu2aKBAjNgLoyigQIuBCKBAjo',
    'yAUAAEh0BDHS6ye6kYoECLgQigQI6LIFAABIdeq6kIoECLgQigQI6KAFAAAx',
    '0kgPlMK4k4oECL6cigQIuyqKBAjoTAYAALgmAAAAifHNgIXAdAQx0usouqSK',
    'BAi4EIoECOhmBQAASHXqujKKBAi4EIoECOhUBQAAMdKFwA+UwriqigQIifPo',
    'BwYAALgJAAAAubGKBAjNgDHShcC434oECLuxigQID5TC6OUFAAC4wwAAAI1M',
    'JBTNgDHSg3wkKAK4v4oECInzD5TC6MQFAAC4CgAAAM2AMdKFwHUVuCEAAAC7',
    'sYoECInRzYAx0oXAD5TCuMqKBAi7uYoECOiTBQAAuFMAAAC50YoECM2AMdKF',
    'wLj5igQIu9GKBAgPlMLocQUAALhVAAAAuiwBAACNTCR0zYCFwH8EMdLrH8ZE',
    'BHQAg/gFdfK6uYoECI1EJHToWwQAADHShcAPlMK424oECLvRigQI6CsFAAAx',
    '0rgFAAAAidHNgL4DAAAAiceNTCR0ugoAAACJ8In7zYCJxjHAhfYPScbGRAR0',
    'ALgGAAAAzYAx0oP+CnUTuj6KBAiJyOj8AwAAMdKFwA+UwrjkigQIu9GKBAjo',
    'zAQAALjEAAAAjUwkFM2Ai0QkJDHSvigAAAC7EIoECCUA8AAAPQCgAAC484oE',
    'CA+UwuiaBAAAifDNgDHSg/jZuAGLBAi7sYoECA+Uwuh/BAAAugoAAACJ0M2A',
    'u9GKBAiJ0M2AuxCKBAiJ8M2AMdKFwHURuCEAAACJ0c2AMdKD+P4PlMK4EIsE',
    'CLsWiwQI6D4EAAC4JwAAALntAQAAzYC4DAAAAM2AuLcAAAC5LAEAAI1cJHTN',
    'gDHSg/gIdRO6FosECInY6CIDAAAx0oXAD5TCuB6LBAi+BQAAALstiwQI6O0D',
    'AAC5QQAAALqAAQAAifDNgInGuAYAAACJ882AviWLBAi/IQAAADHJifiJ882A',
    'MdKFwLg1iwQIuz6LBAgPlMLorAMAALgMAAAAzYC4CgAAAInzzYC+KAAAALsW',
    'iwQIifDNgLonAAAAue0BAAC7QIsECInQzYC7R4sECInQzYC7UIsECIn4McnN',
    'gDHShcC4ZYsECLtHiwQID5TC6FEDAACJ8M2Au0CLBAiJ8M2AvgUAAAAxybts',
    'iwQIifCJys2AicaNlCSEAAAAjUQkdInBQMYBATnQdfa/AwAAALoQAAAAjUwk',
    'dInzifjNgInHuAYAAADNgDHSg/8QdRAx0opEJHQKhCSDAAAAD5TCuHaLBAi+',
    'BQAAALt/iwQI6NMCAAC5AQAAAInwMdLNgL8DAAAAiUQkDLmJiwQIi1wkDLgE',
    'AAAAifrNgDHSg/gDuI2LBAgPlMLomwIAAItcJAy4BgAAAM2AMcm7losECInw',
    'icrNgInGuhAAAACNTCR0ifiJ882Aice4BgAAAM2AMdKD/xC4o4sECA+UwuhX',
    'AgAAuq+LBAi4t4sECOiCAQAASHQEMdLrJ7q8iwQIuLeLBAjobAEAAEh16rrB',
    'iwQIuLeLBAjoWgEAADHSSA+UwrjHiwQIvgUAAAC70YsECOgGAgAAuUEAAACJ',
    '8DHSzYCJx7gGAAAAifvNgLvRiwQIifCJ0c2A99DB6B+JwrjbiwQI6NQBAAC4',
    'AgAAAM2AiceFwHUquBcAAAC76AMAAM2Au9GLBAiJ8In5ifrNgDHbg/jzuAEA',
    'AAAPlcPNgOv+jUwkELgHAAAAifsx0s2AMdKDfCQQALjqiwQIu9GLBAgPlMLo',
    'dQEAALgKAAAAzYAxyYnwu/uLBAiJys2AMdKD+P64CIwECLsPjAQID5TC6EoB',
    'AAAxyYnwicrNgDHSg/jsuByMBAi7JIwECA+UwugrAQAAifC5AQAAADHSzYAx',
    '0oP467gpjAQID5TC6A4BAAAxwIM9MJwECAAPlcCNZfRbXl9dw7itAAAAzYAx',
    '7Yngg+TwUOgqAQAAVYnlVonGUzHbD7YEHg+2DBqEwHQFQzjIdO9bKcheXcNV',
    'uQAAAQCJ5VdWU4nDuAUAAACB7BwEAACJleD7//8x0s2AMfaJheT7//+FwHho',
    'v9wAAACLneT7//+Njej7//+6AAQAAIn4zYCJx4XAfjkx242MHej7//+LleD7',
    '//+NQROJjdz7///odf///4uN3Pv//4XAuAEAAAAPRPAPt0EQAcM5+3zL66eL',
    'neT7//+4BgAAAM2A6wODzv+BxBwEAACJ8FteX13DVYnBMdKJ5VOAPBEAdANC',
    '6/e4BAAAALsBAAAAzYBbXcNVieVWica4CIoECFOJ0+jN////ifDoxv///4Xb',
    'uAGKBAi6/IkECA9Fwuiy////hdt0CP8FNJwECOsG/wUwnAQIW15dw1WJ5VOD',
    '7AiLRQiLEI1IBI1EkAhQUVLopvb//4nDuAEAAADNgIPEEOv+IE9LCgAgRkFJ',
    'TAoAS1RFU1Q6IAAvdG1wL2QxAG1rZGlyAG1rZGlyLmV4aXN0AC90bXAvZDEv',
    'Zi50eHQAY3JlYXQAMDEyMzQ1Njc4OQB3cml0ZQBsc2VlawAzNDU2AHJlYWQA',
    'c3RhdDY0AC90bXAvYmlnAGJpZ2ZpbGUAZnRydW5jYXRlAGZ0cnVuY2F0ZS5z',
    'aXplAC4uAGdldGRlbnRzAC90bXAvZDEvZy50eHQAcmVuYW1lAC90bXAvZDEv',
    'aC50eHQAbGluay5ubGluawB1bmxpbmsAL3RtcC9kMS9zAHJlYWRsaW5rAHN5',
    'bWxpbmsuZm9sbG93AGxzdGF0LnN5bWxpbmsAcm1kaXIubm90ZW1wdHkAcm1k',
    'aXIAL3RtcC9jdwBnZXRjd2QAL3RtcC9jdy9yZWwudHh0AHJlbGF0aXZlAC8A',
    'L3RtcC9hAC90bXAvYS9iAC90bXAvYS9iLy4uLy4uL2EvLi9iAGRvdGRvdAAv',
    'ZGV2L3plcm8AZGV2Lnplcm8AL2Rldi9udWxsAGFiYwBkZXYubnVsbAAvZGV2',
    'L3VyYW5kb20AZGV2LnVyYW5kb20AY29uc29sZQAvZGV2AHR0eTEAdHR5UzAA',
    'ZGV2Lm5vZGVzAC90bXAvcGVybQBwZXJtLnJvb3Rfb3BlbgBwZXJtLnVzZXJf',
    'ZGVuaWVkAC9ub25leGlzdGVudABlbm9lbnQAL2Jpbi9oZWxsby94AGVub3Rk',
    'aXIAL3RtcABlaXNkaXIAR0NDOiAoVWJ1bnR1IDEzLjMuMC02dWJ1bnR1Mn4y',
    'NC4wNC4xKSAxMy4zLjAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAA',
    'AAQA8f8LAAAAqYgECCAAAAACAAEAEgAAAMmIBAimAAAAAgABABwAAABviQQI',
    'IAAAAAIAAQAhAAAAj4kECEQAAAACAAEAJwAAADScBAgEAAAAAQADAC8AAAAw',
    'nAQIBAAAAAEAAwA3AAAA04kECCkAAAASAAEAPQAAAJWIBAgAAAAAEAABAE8A',
    'AACciAQIAAAAABAAAQBKAAAAMJwECAAAAAAQAAMAOAAAAJSABAgBCAAAEgAB',
    'AFYAAAAwnAQIAAAAABAAAwBdAAAAOJwECAAAAAAQAAMAAGRpcnRlc3QuYwBz',
    'dHJjbXAAaGFzX2VudHJ5AHB1dHMAa3Rlc3QAa3VfcGFzcwBrdV9mYWlsAGNt',
    'YWluAF9fcmVzdG9yZV9ydABfX2Jzc19zdGFydABfZWRhdGEAX2VuZAAALnN5',
    'bXRhYgAuc3RydGFiAC5zaHN0cnRhYgAudGV4dAAucm9kYXRhAC5ic3MALmNv',
    'bW1lbnQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'AAAAABsAAAABAAAABgAAAJSABAiUAAAAaAkAAAAAAAAAAAAAAQAAAAAAAAAh',
    'AAAAAQAAADIAAAD8iQQI/AkAADQCAAAAAAAAAAAAAAEAAAABAAAAKQAAAAgA',
    'AAADAAAAMJwECDAMAAAIAAAAAAAAAAAAAAAEAAAAAAAAAC4AAAABAAAAMAAA',
    'AAAAAAAwDAAALQAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAgAAAAAAAAAAAAAA',
    'YAwAAPAAAAAGAAAACAAAAAQAAAAQAAAACQAAAAMAAAAAAAAAAAAAAFANAABi',
    'AAAAAAAAAAAAAAABAAAAAAAAABEAAAADAAAAAAAAAAAAAACyDQAANwAAAAAA',
    'AAAAAAAAAQAAAAAAAAA=',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAcYIECDQAAAAsBQAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAikAwAApAMAAAUAAAAAEAAAAQAAAKQD',
    'AACkkwQIpJMECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW5AVQAAInlV1a+NgAAAFOJ8DHbg+Twg+xwjVQkKM2A',
    'MdKFwLgfgwQID5TC6NkBAACLRCQ0MdL30KgKuCqDBAgPlMLowgEAAI1UJCCJ',
    '8LkTVAAAzYAx0oXAdRVmg3wkIgCJwnQLMdJmg3wkIAAPlcK4NIMECDHb6I4B',
    'AAAxwI1UJBS5D1QAAIlEJBS4NgAAAM2AMdKFwHUKMdKDfCQUAA+fwrg+gwQI',
    'jXwkTI10JCgx2+hUAQAAuQkAAADzpY18JEy+NgAAAGbHRCRiAAGJ8In6g2Qk',
    'WPWJTCQMuQJUAADNgDHShcC4TIMECA+UwugYAQAAi1wkDInwuQFUAACJ+s2A',
    'i1QkWLhXgwQI0eqD8gGD4gHo8wAAAItcJAyJ8LkCVAAAjVQkKM2AuCoAAACN',
    'XCQYzYC5AVQAAItcJBiJ8M2AMdKD+Oe+BQAAALhfgwQID5TCu2qDBAjorgAA',
    'AItUJAy5AgAAAInwzYCJwonGuHODBAj30sHqH+iOAAAAhfZ4GrgEAAAAuX6D',
    'BAi6GAAAAInzzYC4BgAAAM2AuAQAAAC7AQAAALmXgwQIugIAAADNgDHSg/gC',
    'uJqDBAgPlMLoSAAAADHAgz2kkwQIAA+VwI1l9FteX13DuK0AAADNgDHtieCD',
    '5PBQ6GQAAABVicEx0onlU4A8EQB0A0Lr97gEAAAAuwEAAADNgFtdw1WJ5VaJ',
    'xrgXgwQIU4nT6M3///+J8OjG////hdu4EIMECLoLgwQID0XC6LL///+F23QI',
    '/wWokwQI6wb/BaSTBAhbXl3DVYnlU4PsCItFCIsQjUgEjUSQCFBRUuiX/f//',
    'icO4AQAAAM2Ag8QQ6/4gT0sKACBGQUlMCgBLVEVTVDogAHR0eS50Y2dldHMA',
    'dHR5LmNhbm9uAHR0eS53aW5zegB0dHkudGNnZXRwZ3JwAHR0eS50Y3NldHMA',
    'dHR5LnJhdwB0dHkuZW5vdHR5AC9kZXYvdHR5AHR0eS5kZXZ0dHkAW2Vjcml0',
    'dXJlIHZpYSAvZGV2L3R0eV0KAHgKAHR0eS53cml0ZQBHQ0M6IChVYnVudHUg',
    'MTMuMy4wLTZ1YnVudHUyfjI0LjA0LjEpIDEzLjMuMAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAAAQAAAAAAAAAAAAAABADx/wsAAAB+ggQIIAAAAAIAAQAQAAAAnoIE',
    'CEQAAAACAAEAFgAAAKiTBAgEAAAAAQADAB4AAACkkwQIBAAAAAEAAwAmAAAA',
    '4oIECCkAAAASAAEALAAAAGqCBAgAAAAAEAABAD4AAABxggQIAAAAABAAAQA5',
    'AAAApJMECAAAAAAQAAMAJwAAAJSABAjWAQAAEgABAEUAAACkkwQIAAAAABAA',
    'AwBMAAAArJMECAAAAAAQAAMAAHR0eXRlc3QuYwBwdXRzAGt0ZXN0AGt1X3Bh',
    'c3MAa3VfZmFpbABjbWFpbgBfX3Jlc3RvcmVfcnQAX19ic3Nfc3RhcnQAX2Vk',
    'YXRhAF9lbmQAAC5zeW10YWIALnN0cnRhYgAuc2hzdHJ0YWIALnRleHQALnJv',
    'ZGF0YQAuYnNzAC5jb21tZW50AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAbAAAAAQAAAAYAAACUgAQIlAAAAHcCAAAAAAAAAAAA',
    'AAEAAAAAAAAAIQAAAAEAAAAyAAAAC4MECAsDAACZAAAAAAAAAAAAAAABAAAA',
    'AQAAACkAAAAIAAAAAwAAAKSTBAikAwAACAAAAAAAAAAAAAAABAAAAAAAAAAu',
    'AAAAAQAAADAAAAAAAAAApAMAAC0AAAAAAAAAAAAAAAEAAAABAAAAAQAAAAIA',
    'AAAAAAAAAAAAANQDAADQAAAABgAAAAYAAAAEAAAAEAAAAAkAAAADAAAAAAAA',
    'AAAAAACkBAAAUQAAAAAAAAAAAAAAAQAAAAAAAAARAAAAAwAAAAAAAAAAAAAA',
    '9QQAADcAAAAAAAAAAAAAAAEAAAAAAAAA',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAVYIECDQAAAD0BAAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAhVAwAAVQMAAAUAAAAAEAAAAQAAAFgD',
    'AABYkwQIWJMECAAAAAAMAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW6TgAAADHJidCJ5VdWU4Pk8IPsQI1cJATNgDHAx0Qk',
    'GADC6wuNXCQUiUQkFLiiAAAAzYCNXCQMidDNgItEJBArRCQIuegDAACZi3Qk',
    'DCt0JAT3+Wn26AMAADHSAcaNhkL///+J8z3RAAAAuAODBAgPlsLodgEAALgS',
    'gwQI6EwBAACF9sZEJD0AjUwkHHkJ99u/IQAAAOsOdffGRCQ8ML8gAAAA6yeF',
    '23QZidgx0rsKAAAAT/fzipJEgwQIicOIFDnr44X2eQbGRDwbLU+NBDm+AgAA',
    'AOj0AAAAuBuDBAjo6gAAAInwzYCFwInDjUwkHHUcuwAtMQGhWJMECECjWJME',
    'CEt18rgBAAAAzYDr/onwzYCJxoXAdRy7AC0xAaFYkwQIQKNYkwQIS3XyuAEA',
    'AADNgOv+vwcAAAAx0on4zYCJ+InzzYC6AQAAALgggwQIuwUAAADolQAAALgi',
    'AAAAzYAx0oXAuCqDBAgPlMIx2+h7AAAAuCsAAADNgDHShcC4L4MECA+fwuhj',
    'AAAAuA0AAADNgDHSPQDxU2W4OoMECA+fwuhIAAAAMcCDPVyTBAgAD5XAjWX0',
    'W15fXcO4rQAAAM2AMe2J4IPk8FDoZAAAAFWJwTHSieVTgDwRAHQDQuv3uAQA',
    'AAC7AQAAAM2AW13DVYnlVonGuPuCBAhTidPozf///4nw6Mb///+F27j0ggQI',
    'uu+CBAgPRcLosv///4XbdAj/BWCTBAjrBv8FXJMECFteXcNVieVTg+wIi0UI',
    'ixCNSASNRJAIUFFS6LP9//+Jw7gBAAAAzYCDxBDr/iBPSwoAIEZBSUwKAEtU',
    'RVNUOiAAdGltZS5uYW5vc2xlZXAAICBkb3JtaSAAIG1zCgBzY2hlZC5jcHUA',
    'bmljZQB0aW1lLnRpbWVzAHRpbWUudGltZQAwMTIzNDU2Nzg5YWJjZGVmAEdD',
    'QzogKFVidW50dSAxMy4zLjAtNnVidW50dTJ+MjQuMDQuMSkgMTMuMy4wAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAQA8f8NAAAAYoIECCAAAAAC',
    'AAEAEgAAAIKCBAhEAAAAAgABABgAAABgkwQIBAAAAAEAAwAgAAAAXJMECAQA',
    'AAABAAMAKAAAAFiTBAgEAAAAAQADAC0AAADGggQIKQAAABIAAQAzAAAAToIE',
    'CAAAAAAQAAEARQAAAFWCBAgAAAAAEAABAEAAAABYkwQIAAAAABAAAwAuAAAA',
    'lIAECLoBAAASAAEATAAAAFWTBAgAAAAAEAADAFMAAABkkwQIAAAAABAAAwAA',
    'c2NoZWR0ZXN0LmMAcHV0cwBrdGVzdABrdV9wYXNzAGt1X2ZhaWwAc3BpbgBj',
    'bWFpbgBfX3Jlc3RvcmVfcnQAX19ic3Nfc3RhcnQAX2VkYXRhAF9lbmQAAC5z',
    'eW10YWIALnN0cnRhYgAuc2hzdHJ0YWIALnRleHQALnJvZGF0YQAuYnNzAC5j',
    'b21tZW50AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'AAAAGwAAAAEAAAAGAAAAlIAECJQAAABbAgAAAAAAAAAAAAABAAAAAAAAACEA',
    'AAABAAAAMgAAAO+CBAjvAgAAZgAAAAAAAAAAAAAAAQAAAAEAAAApAAAACAAA',
    'AAMAAABYkwQIWAMAAAwAAAAAAAAAAAAAAAQAAAAAAAAALgAAAAEAAAAwAAAA',
    'AAAAAFUDAAAtAAAAAAAAAAAAAAABAAAAAQAAAAEAAAACAAAAAAAAAAAAAACE',
    'AwAA4AAAAAYAAAAHAAAABAAAABAAAAAJAAAAAwAAAAAAAAAAAAAAZAQAAFgA',
    'AAAAAAAAAAAAAAEAAAAAAAAAEQAAAAMAAAAAAAAAAAAAALwEAAA3AAAAAAAA',
    'AAAAAAABAAAAAAAAAA==',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAA44MECDQAAAB4BwAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAjbBQAA2wUAAAUAAAAAEAAAAQAAANwF',
    'AADclQQI3JUECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW5AgAAADHSuAUAAACJ5VdWU7u2hAQIg+TwgewQCAAA',
    'zYCJwolEJAy4wIQECDH299LB6h/oaAMAALIHifAPr8KIRDQQRoH+AAQAAHXu',
    'vxMAAACLXCQMuYgTAAAx0on4zYC4BAAAAItcJAyNTCQQifLNgDHSPQAEAAC4',
    'zYQECA+UwugbAwAAifiLXCQMuYgTAAAx0s2AjYQkEAQAAInCjbwkEAgAAEDG',
    'AgA5+HXvi1wkDLgDAAAAugAEAACNjCQQBAAAzYAx0j0ABAAAdRyNlCQQBAAA',
    'uQAEAACNRCQQ6HoCAAAx0oXAD5TCuNuEBAjorgIAAItcJAy4BgAAAM2AMdK+',
    'BQAAALvohAQIifCJ0c2AicaFwHkPuPGEBAjoYQIAAOkPAgAAuAMAAAC6AAIA',
    'AI1MJBCJ882AMdI9AAIAAHUXgLwkDgIAAFV1DTHSgLwkDwIAAKoPlMK4HIUE',
    'CInz6D4CAAC4BgAAAM2AvyiFBAi+BQAAALkCAAAAMdKJ8In7zYCJwonGuDKF',
    'BAj30onzweof6AsCAAC4AwAAALoQAAAAjUwkEM2AMdKFwA9J0MZEFBAAg/gQ',
    'dRu5EAAAALpAhQQIjUQkEOiSAQAAiUQkDIXAdA+4UYUECOilAQAA6UoBAAC6',
    'AQAAALiDhQQI6LEBAAC4EwAAALkAEAAAi1QkDM2AMdKxA4nQD6/Bg/BaiEQU',
    'EEKB+gAEAAB167gEAAAAifONTCQQzYAx0j0ABAAAuJGFBAgPlMLoZwEAALgk',
    'AAAAzYC4BgAAAM2AMdK4BQAAAIn7idHNgInGuQAQAAC4EwAAAInzzYCNhCQQ',
    'BAAAiceJwo2MJBAIAABAxgIAOch177gDAAAAugAEAACJ842MJBAEAADNgDHS',
    'PQAEAAB1F4n6uQAEAACNRCQQ6K8AAAAx0oXAD5TCuKCFBAiJ8+jhAAAAuAYA',
    'AADNgDHSvgUAAAC7soUECInwidHNgInGuhAAAACNTCQQuAMAAACJ882AMdKF',
    'wA9J0MZEFBAAg/gQdR+5EAAAALq8hQQIjUQkEOhLAAAAhcAPlMAPtsCJRCQM',
    'i1QkDLjNhQQI6HYAAAC4BgAAAInzzYAxwIM93JUECAAPlcCNZfRbXl9dw7it',
    'AAAAzYAx7Yngg+TwUOiJAAAAVQHBieVWidZTicMPtgMPthY40HQEKdDrCENG',
    'Oct17DHAW15dw1WJwTHSieVTgDwRAHQDQuv3uAQAAAC7AQAAAM2AW13DVYnl',
    'VonGuK6EBAhTidPozf///4nw6Mb///+F27inhAQIuqKEBAgPRcLosv///4Xb',
    'dAj/BeCVBAjrBv8F3JUECFteXcNVieVTg+wIi0UIixCNSASNRJAIUFFS6AD8',
    '//+Jw7gBAAAAzYCDxBDr/iBPSwoAIEZBSUwKAEtURVNUOiAAL2Rldi9yYW0w',
    'AGJsay5yYW1fb3BlbgBibGsucmFtX3dyaXRlAGJsay5yYW1fcmVhZAAvZGV2',
    'L2hkYQAgIChwYXMgZGUgZGlzcXVlIGhkYSA6IHRlc3RzIElERSBpZ25vcmVz',
    'KQoAYmxrLmhkYV9tYnIAL2Rldi9oZGExAGJsay5oZGExX29wZW4AUEFSVElU',
    'SU9OLU9ORS4uLgAgIChwYXJ0aXRpb24gZGUgdGVzdCBhYnNlbnRlIDogZWNy',
    'aXR1cmUgaWdub3JlZSkKAGJsay5oZGExX3JlYWQAYmxrLmhkYTFfd3JpdGUA',
    'YmxrLmhkYTFfcmVhZGJhY2sAL2Rldi9oZGEyAFBBUlRJVElPTi1UV08uLi4A',
    'YmxrLmhkYTJfcmVhZABHQ0M6IChVYnVudHUgMTMuMy4wLTZ1YnVudHUyfjI0',
    'LjA0LjEpIDEzLjMuMAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAABADx',
    '/wsAAADwgwQIJQAAAAIAAQATAAAAFYQECCAAAAACAAEAGAAAADWEBAhEAAAA',
    'AgABAB4AAADglQQIBAAAAAEAAwAmAAAA3JUECAQAAAABAAMALgAAAHmEBAgp',
    'AAAAEgABADQAAADcgwQIAAAAABAAAQBGAAAA44MECAAAAAAQAAEAQQAAANyV',
    'BAgAAAAAEAADAC8AAACUgAQISAMAABIAAQBNAAAA25UECAAAAAAQAAMAVAAA',
    'AOSVBAgAAAAAEAADAABibGt0ZXN0LmMAbWVtY21wXwBwdXRzAGt0ZXN0AGt1',
    'X3Bhc3MAa3VfZmFpbABjbWFpbgBfX3Jlc3RvcmVfcnQAX19ic3Nfc3RhcnQA',
    'X2VkYXRhAF9lbmQAAC5zeW10YWIALnN0cnRhYgAuc2hzdHJ0YWIALnRleHQA',
    'LnJvZGF0YQAuYnNzAC5jb21tZW50AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAbAAAAAQAAAAYAAACUgAQIlAAAAA4EAAAAAAAA',
    'AAAAAAEAAAAAAAAAIQAAAAEAAAAyAAAAooQECKIEAAA5AQAAAAAAAAAAAAAB',
    'AAAAAQAAACkAAAAIAAAAAwAAANyVBAjcBQAACAAAAAAAAAAAAAAABAAAAAAA',
    'AAAuAAAAAQAAADAAAAAAAAAA2wUAAC0AAAAAAAAAAAAAAAEAAAABAAAAAQAA',
    'AAIAAAAAAAAAAAAAAAgGAADgAAAABgAAAAcAAAAEAAAAEAAAAAkAAAADAAAA',
    'AAAAAAAAAADoBgAAWQAAAAAAAAAAAAAAAQAAAAAAAAARAAAAAwAAAAAAAAAA',
    'AAAAQQcAADcAAAAAAAAAAAAAAAEAAAAAAAAA',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAB4sECDQAAADcDwAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAgADgAAAA4AAAUAAAAAEAAAAQAAAAAO',
    'AAAAngQIAJ4ECAAAAAAQAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW4JwAAALntAQAAieVXVlO70IsECIPk8IHsMAMAAM2A',
    'Mfa4FQAAALvXiwQIuuKLBAi50IsECIn3zYAx0oXAuNyLBAi76IsECA+Uwuhp',
    'CgAAuAUAAAC5QQAAALqkAQAAzYCJxrnxiwQIuAQAAAC6AwAAAInzzYC4BgAA',
    'AM2AvyEAAAC76IsECDHJifjNgDHShcC+FgAAALj1iwQID5TCu9CLBAjoEQoA',
    'AInwzYAx0oXAuACMBAi76IsECA+Uwuj3CQAAifgxyc2AMdKD+P64B4wECLvQ',
    'iwQID5TC6NoJAACJ8M2AMdKD+Oq4E4wECLshjAQID5TC6L8JAAC4JwAAALnt',
    'AQAAzYC4JwAAALsrjAQIzYC+BQAAALs5jAQIuUEAAAC6pAEAAInwzYCJxrlJ',
    'jAQIuAQAAAC6AgAAAInzzYC4BgAAAM2AuAIAAADNgInGhcB1Srg9AAAAuyGM',
    'BAjNgLgMAAAAu0yMBAjNgLtCjAQIifiJ8c2AuwEAAACJwoXAdROJ+LtOjAQI',
    'idHNgDHbg/j+D5XDuAEAAADNgOv+uAcAAACJ841MJAQx0s2AMdKDfCQEALhT',
    'jAQIv1qMBAgPlMK+YowECOjvCAAAulMAAACJ84n5idDNgInQifuJ8c2AMcm4',
    'BQAAAInzicrNgDHSg/jYuGqMBAgPlMLouwgAALoKAAAAidDNgInQifvNgLgq',
    'AAAAjVwkEM2Ai0QkEI1cJDC5AgAAADHSx0QkNAEAAACJRCQwi0QkFMdEJDwE',
    'AAAAiUQkOLioAAAAzYBIdRH2RCQ+BHQKZotUJDb30oPiAbh4jAQI6FEIAACL',
    'XCQUuAQAAAC5iYwECLoBAAAAzYC4qAAAALkCAAAAjVwkMDHSZsdEJDYAAM2A',
    'g/gCdQhmi1QkNoPiAbiLjAQIvqgAAAC/AQAAAOgCCAAAjVwkMInwugoAAACJ',
    '+c2AMdJIuJuMBAgPlMLo4wcAALgDAAAAi1wkEIn6jYwkMAIAAM2AujIAAABm',
    'x0QkNgAAifCJ+Y1cJDDNgDHShcC4qIwECA+UwuioBwAAjYQksAEAAInCjbwk',
    'MAIAAEDGAgA5+HXvi0wkEDH2uAEAAACNfCQYiXQkGDH20+CNWQHHRCQcIE4A',
    'AInyiYQksAEAAI2MJLABAAC4jgAAAM2AMdKFwLi2jAQID5TC6EYHAACLXCQU',
    'uAQAAAC5xYwECLoBAAAAzYCLTCQQuAEAAACJ8tPgjVkBjYwksAEAAImEJLAB',
    'AAC4jgAAAM2ASHUQi0wkEIuUJLABAADT6oPiAbjHjAQIjXwkQL7QjQQI6OYG',
    'AACNXCQQuQQAAAC4KgAAAPOlzYC+AgAAAItcJBSNTCRAuJIAAACJ8s2AMdKD',
    '+AW41IwECA+UwuisBgAAjUQkAYtcJBCJ8olEJFCNRCQMjUwkUIlEJFi4kQAA',
    'AMdEJFQCAAAAx0QkXAMAAADNgDHSg/gFdRGAfCQBYXUKMdKAfCQOZQ+Uwrjb',
    'jAQIuwUAAADoVAYAAInYuUIAAAC6gAEAALvhjAQIzYC6CgAAAInDuemMBAi4',
    'BAAAAM2AuLQAAAC+BgAAADH/ugQAAACNjCQwAgAAzYAxyYP4BHUegLwkMAIA',
    'ADZ1FLgTAAAAugEAAADNgDHJg/gKD5TBicq49IwECOjjBQAAuAYAAADNgLgK',
    'AAAAu+GMBAjNgLgpAAAAuwEAAADNgDHSg/gCicO+NwAAAA+fwrj8jAQI6KsF',
    'AACJ8DHSuQEAAADNgIXAdAQx0usiuQIAAACJ8LoBAAAAzYCJx4XAdeiJ0Ynw',
    'ifrNgDHSSA+UwrgAjQQIvjcAAADoZwUAALoKAAAAifAxyc2AMdKD+AmJxrgM',
    'jQQID5/C6EgFAAC6BgAAAInQzYCJ0InzzYAx242MJFABAAC4rgAAADHSiZwk',
    'YAEAAL4IAAAAiZwkXAEAALsOAAAAx4QkUAEAACGLBAjHhCRUAQAABAAABMeE',
    'JFgBAAAAiwQIzYC+4I0ECI18JGC5BAAAAInT86W4aAAAAI1MJGDNgDHAixUA',
    'ngQIPQDh9QV0CIP6An8DQOvrMdIx/7hoAAAAiVQkZIn7iVQkbIn6zYChAJ4E',
    'CDHSvgoAAACJ84P4ArgYjQQID5/C6IUEAAAxybhDAAAAifqJTCR0iUwkeIlM',
    'JHyNTCRwx0QkcBSLBAjNgLgUAAAAzYCJw4nxuCUAAADNgKEEngQIMdKD+Aq4',
    'Io0ECA+Uwug5BAAAuBgAAADNgIXAdAQx0usZuC8AAADNgIXAdfG4MQAAAM2A',
    'MdKFwA+UwrgwjQQIvgIAAADoAgQAAInwzYCJw4XAdTK4QgAAAM2AicG4FAAA',
    'AM2AuwEAAACJwjnIdQ64QQAAAM2AMds5wg+Vw7gBAAAAzYDr/r8HAAAAjUwk',
    'BDHSifjNgDHSg3wkBAC4NI0ECA+UwuijAwAAifDNgInGhcB1I7oXAAAAu/QB',
    'AACJ0M2AidCJ882AMdtAuAEAAAAPlcPNgOv+ifiJ841MJAQx0s2AMdKDfCQE',
    'ALg7jQQIuz8AAAAPlMLoUQMAALo8AAAAidDNgInBMcCD+RJ1D4nQicvNgIP4',
    'Pw+UwA+2wInCuEiNBAi7BwAAAOgfAwAAjUwkILhMAAAAzYAx0oF8JCD/AAAA',
    'uE6NBAgPn8KNnCSQAAAA6PYCAAC4dAAAAM2AMdKFwHUNMdKDvCSgAAAAAA+f',
    'wrhYjQQIuwEAAADozQIAAI1MJCi4CQEAAM2AMdKFwHUJi1QkKPfSweofuGCN',
    'BAi7TowECOikAgAAjYwk0AAAALhjAAAAzYAx0oXAdRyLhCTQAAAAPZQZAgEP',
    'lMI9U+8AAA+UwAnCD7bSuG6NBAi+dY0ECL8FAAAA6GACAACJ87lCAAAAifi6',
    'gAEAAM2Aice6CgAAALgEAAAAuemMBAiJ+82AuAYAAADNgLhcAAAAuQMAAACJ',
    '882AMdKFwLh9jQQID5TC6BUCAACNjCQQAQAAuGoAAADNgDHSg7wkJAEAAAN1',
    'FIuEJBgBAAAx0mYlAPBmPQCAD5TCuIaNBAiJ8+jbAQAAuAoAAADNgL4FAAAA',
    'uUIAAAC6gAEAALuPjQQIifDNgInGuAYAAACJ882AvvCNBAi5BAAAALgPAQAA',
    'u4+NBAiNvCSAAAAA86WNjCSAAAAAzYAx0oXAuJeNBAgPlMLoegEAAI2MJFAB',
    'AAC4wwAAAM2AMdKBvCSYAQAAgIQeAHUQMdKBvCSQAQAAQEIPAA+UwriejQQI',
    'u4+NBAjoPgEAALgKAAAAzYC+BQAAALtMjAQIuQAAAQAx0onwzYCJxroAAQAA',
    'uI0AAACJ842MJDACAADNgDHShcB+DjHSZoO8JDgCAAALD5fCuKuNBAiJ8+jr',
    'AAAAuAYAAADNgDHAuwAAAFC5ACAAAIPP/4lEJAi+MgAAALjAAAAAugMAAABV',
    'i2wkCM2AXTHSPQAAAFC4uI0ECA+UwuimAAAAuL4AAADNgInDhcB1DrgBAAAA',
    'uwMAAADNgOv+uAcAAAAx0o1MJATNgItEJAQx0iUA/wAAPQADAAC4w40ECA+U',
    'wuhhAAAAMcCDPQieBAgAD5XAjWX0W15fXcO4rQAAAM2AMe2J4IPk8FDofQAA',
    'AFWJ5YtFCF2jBJ4ECMOhAJ4ECECjAJ4ECMNVicEx0onlU4A8EQB0A0Lr97gE',
    'AAAAuwEAAADNgFtdw1WJ5VaJxrjIiwQIU4nT6M3///+J8OjG////hdu4wYsE',
    'CLq8iwQID0XC6LL///+F23QI/wUMngQI6wb/BQieBAhbXl3DVYnlU4PsCItF',
    'CIsQjUgEjUSQCFBRUujo9P//icO4AQAAAM2Ag8QQ6/4AACBPSwoAIEZBSUwK',
    'AEtURVNUOiAAL21udC90AG5vbmUAbW91bnQudG1wZnMAL21udC90L3gAYWJj',
    'AG1vdW50LmZpbGUAdW1vdW50AHVtb3VudC5nb25lAHVtb3VudC5laW52YWwA',
    'L3RtcC9yb290AC90bXAvcm9vdC9ldGMAL3RtcC9yb290L2V0Yy9mAGluAC8A',
    'L3RtcABjaHJvb3QAL3RtcC9sYgAvdG1wL2xhAHN5bWxpbmsuZWxvb3AAcG9s',
    'bC53cml0ZV9yZWFkeQB6AHBvbGwucmVhZF9yZWFkeQBwb2xsLnRpbWVvdXQA',
    'cG9sbC50aW1lb3V0MABzZWxlY3QudGltZW91dABxAHNlbGVjdC5yZWFkeQB3',
    'cml0ZXYAcmVhZHYAL3RtcC9wcgAwMTIzNDU2Nzg5AHByZWFkNjQAZHVwAGZj',
    'bnRsLmdldGZkAGZjbnRsLmR1cGZkAHNldGl0aW1lcgBzaWdhY3Rpb24ub2xk',
    'AGlkcwBzZXRzaWQAc2V0dWlkLmVwZXJtAHVtYXNrAGdldHJsaW1pdABzeXNp',
    'bmZvAGNsb2NrX2dldHRpbWUAc3RhdGZzAC90bXAvdHIAdHJ1bmNhdGUAc3Rh',
    'dC5vbGQAL3RtcC91dAB1dGltZXMAdXRpbWVzLm10aW1lAGdldGRlbnRzLm9s',
    'ZABtbWFwLmZpeGVkAHZmb3JrAGFiAGNkZQDJjQQIAgAAAMyNBAgDAAAAAAAA',
    'AFDDAAAAAAAAUMMAAEBCDwAAAAAAgIQeAAAAAABHQ0M6IChVYnVudHUgMTMu',
    'My4wLTZ1YnVudHUyfjI0LjA0LjEpIDEzLjMuMAAAAAAAAAAAAAAAAAAAAAAA',
    'AAAAAQAAAAAAAAAAAAAABADx/wwAAAAUiwQIDQAAAAIAAQARAAAABJ4ECAQA',
    'AAABAAMAGQAAACGLBAgMAAAAAgABABoAAAAAngQIBAAAAAEAAwAeAAAALYsE',
    'CCAAAAACAAEAIwAAAE2LBAhEAAAAAgABACkAAAAMngQIBAAAAAEAAwAxAAAA',
    'CJ4ECAQAAAABAAMAOQAAAJGLBAgpAAAAEgABAD8AAAAAiwQIAAAAABAAAQBR',
    'AAAAB4sECAAAAAAQAAEATAAAAACeBAgAAAAAEAADADoAAACUgAQIbAoAABIA',
    'AQBYAAAAAJ4ECAAAAAAQAAMAXwAAABCeBAgAAAAAEAADAABtaXNjdGVzdC5j',
    'AG9sZGgAb2xkX3NpZwBoaXR2AHB1dHMAa3Rlc3QAa3VfcGFzcwBrdV9mYWls',
    'AGNtYWluAF9fcmVzdG9yZV9ydABfX2Jzc19zdGFydABfZWRhdGEAX2VuZAAA',
    'LnN5bXRhYgAuc3RydGFiAC5zaHN0cnRhYgAudGV4dAAucm9kYXRhAC5ic3MA',
    'LmNvbW1lbnQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAbAAAAAQAAAAYAAACUgAQIlAAAACYLAAAAAAAAAAAAAAEAAAAAAAAA',
    'IQAAAAEAAAACAAAAvIsECLwLAABEAgAAAAAAAAAAAAAEAAAAAAAAACkAAAAI',
    'AAAAAwAAAACeBAgADgAAEAAAAAAAAAAAAAAABAAAAAAAAAAuAAAAAQAAADAA',
    'AAAAAAAAAA4AAC0AAAAAAAAAAAAAAAEAAAABAAAAAQAAAAIAAAAAAAAAAAAA',
    'ADAOAAAQAQAABgAAAAoAAAAEAAAAEAAAAAkAAAADAAAAAAAAAAAAAABADwAA',
    'ZAAAAAAAAAAAAAAAAQAAAAAAAAARAAAAAwAAAAAAAAAAAAAApA8AADcAAAAA',
    'AAAAAAAAAAEAAAAAAAAA',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAZIQECDQAAAAkCQAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAhiBwAAYgcAAAUAAAAAEAAAAQAAAGQH',
    'AABklwQIZJcECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFW4y4UECInlV1ZTg+TwgexgDAAAjZQkYAQAAOgTBAAA',
    'MdKFwH4YutmFBAiNhCRgBAAA6LQDAAAx0oXAD5XCuOKFBAjoNwQAAI2UJGAE',
    'AAC474UECOjaAwAAMdKFwH4vuv2FBAiNhCRgBAAA6HsDAACJwoXAdBi6B4YE',
    'CI2EJGAEAADoZAMAADHShcAPlcK4EIYECOjnAwAAjZQkYAQAALgdhgQI6IoD',
    'AAAx0oXAfhGKhCRgBAAAMdKD6DA8CQ+WwrgqhgQI6LUDAACNlCRgBAAAuDaG',
    'BAjoWAMAADHShcB+L7pDhgQIjYQkYAQAAOj5AgAAicKFwHQYui+HBAiNhCRg',
    'BAAA6OICAAAx0oXAD5XCuEyGBAjoZQMAAI2UJGAEAAC4WIYECOgIAwAAicO4',
    'FAAAAM2AhcB0CIpUJGAxyesHsjC5AQAAAIhUJGC+CgAAAIXAdA2ZQff+g8Iw',
    'iFQMX+vvjXwkEInIif6FwHQLSEeKVARgiFf/6/HGRAwQADHShdt+J7pohgQI',
    'jYQkYAQAAOhXAgAAicKFwHQQMdKKRCQQOIQkYAQAAA+UwrhzhgQI6MsCAACN',
    'lCRgBAAAuIKGBAjobgIAADHShcB+L7qUhgQIjYQkYAQAAOgPAgAAicKFwHQY',
    'uqWGBAiNhCRgBAAA6PgBAAAx0oXAD5XCuK+GBAi7xIUECOh2AgAAjUQkIInB',
    'ihNDQIhQ/4TSdfWJyI1cJBCKE0NAiFAFhNJ19Ynw6KsBAACNXAEGMcCKkMCG',
    'BAiIFANAhNJ18o2UJGAEAACJyOjfAQAAMdKD+Ah+GLrJhgQIjYQkYAQAAOh/',
    'AQAAMdKFwA+VwrjXhgQI6AICAACNlCRgBAAAuOSGBAjopQEAADHShcB+L7r0',
    'hgQIjYQkYAQAAOhGAQAAicKFwHQYuvmGBAiNhCRgBAAA6C8BAAAx0oXAD5XC',
    'uAGHBAjosgEAAI2UJGAEAAC4C4cECOhVAQAAMdKFwH4YukaGBAiNhCRgBAAA',
    '6PYAAAAx0oXAD5XCuB2HBAi7LocECOh0AQAAuQAAAQAx0rgFAAAAzYCJRCQI',
    'MfaLXCQIugAEAAC43AAAAI1MJGDNgIlEJASFwH5BMduNRCRgMdKNPBiKTBcT',
    'iEwkD4B8JA8AikwUEHQLikQkD0I4wXTk6wqEybgBAAAAD0TwD7dXEAHTOVwk',
    'BH/D66OLXCQIuAYAAADNgLg0hwQIifK7RYcECOjnAAAAMdK4BQAAAInRzYAx',
    '0oP4/rhWhwQID5TC6MoAAAAxwIM9ZJcECAAPlcCNZfRbXl9dw7itAAAAzYAx',
    '7Yngg+TwUOgWAQAAicIxwIA8AgB0A0Dr98NVicGJ0InlV1ZTg+wciVXk6N3/',
    '//+JxonIgDgAicJ0HotN5I08Bjn6dA2KGTgadANA6+ZCQevvuAEAAADrAjHA',
    'g8QcW15fXcNVieVXVlOJw7gFAAAAUYlV8DHSidHNgInHhcB4Kb4DAAAAi03w',
    'uv8HAACJ+4nwzYCJxrgGAAAAzYCF9ngHi0XwxgQwAInwWlteX13DVbm8hQQI',
    'ieVXvwQAAABWidZTuwEAAACD7ByJReS4vIUECOg3////icKJ+M2Ai0Xk6Cn/',
    '//+LTeSJwon4zYC4sIUECIX2ubWFBAgPRciJyOgK////icKJ+M2AhfZ0CP8F',
    'aJcECOsG/wVklwQIg8QcW15fXcNVieVTg+wIi0UIixCNSASNRJAIUFFS6PL6',
    '//+Jw7gBAAAAzYCDxBDr/iBPSwoAIEZBSUwKAEtURVNUOiAAL3Byb2MvAC9w',
    'cm9jL3ZlcnNpb24AS0VSTkVMMzIAcHJvYy52ZXJzaW9uAC9wcm9jL21lbWlu',
    'Zm8ATWVtVG90YWw6AE1lbUZyZWU6AHByb2MubWVtaW5mbwAvcHJvYy91cHRp',
    'bWUAcHJvYy51cHRpbWUAL3Byb2MvbW91bnRzACAvIHRtcGZzAHByb2MubW91',
    'bnRzAC9wcm9jL3NlbGYvc3RhdAAocHJvY3Rlc3QpAHByb2Muc2VsZi5zdGF0',
    'AC9wcm9jL3NlbGYvc3RhdHVzAE5hbWU6ICAgcHJvY3Rlc3QAVWlkOiAgICAw',
    'AHByb2Muc2VsZi5zdGF0dXMAL2NtZGxpbmUAL2Jpbi9wcm9jdGVzdABwcm9j',
    'LmNtZGxpbmUAL3Byb2Mvc2VsZi9tYXBzAHIteHAAW3N0YWNrXQBwcm9jLm1h',
    'cHMAL3Byb2MvZmlsZXN5c3RlbXMAcHJvYy5maWxlc3lzdGVtcwAvcHJvYwBw',
    'cm9jLnJlYWRkaXJfcGlkAC9wcm9jLzk5OTk5L3N0YXQAcHJvYy5lbm9lbnQA',
    'R0NDOiAoVWJ1bnR1IDEzLjMuMC02dWJ1bnR1Mn4yNC4wNC4xKSAxMy4zLjAA',
    'AAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAEAPH/DAAAAHGEBAgOAAAA',
    'AgABABMAAAB/hAQISAAAAAIAAQAXAAAAx4QECEwAAAACAAEAKQAAABOFBAh0',
    'AAAAAgABAC8AAABolwQIBAAAAAEAAwA3AAAAZJcECAQAAAABAAMAPwAAAIeF',
    'BAgpAAAAEgABAEUAAABdhAQIAAAAABAAAQBXAAAAZIQECAAAAAAQAAEAUgAA',
    'AGSXBAgAAAAAEAADAEAAAACUgAQIyQMAABIAAQBeAAAAYpcECAAAAAAQAAMA',
    'ZQAAAGyXBAgAAAAAEAADAABwcm9jdGVzdC5jAHN0cmxlbgBoYXMAc2x1cnAu',
    'Y29uc3Rwcm9wLjAAa3Rlc3QAa3VfcGFzcwBrdV9mYWlsAGNtYWluAF9fcmVz',
    'dG9yZV9ydABfX2Jzc19zdGFydABfZWRhdGEAX2VuZAAALnN5bXRhYgAuc3Ry',
    'dGFiAC5zaHN0cnRhYgAudGV4dAAucm9kYXRhAC5ic3MALmNvbW1lbnQAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABsAAAAB',
    'AAAABgAAAJSABAiUAAAAHAUAAAAAAAAAAAAAAQAAAAAAAAAhAAAAAQAAADIA',
    'AACwhQQIsAUAALIBAAAAAAAAAAAAAAEAAAABAAAAKQAAAAgAAAADAAAAZJcE',
    'CGQHAAAIAAAAAAAAAAAAAAAEAAAAAAAAAC4AAAABAAAAMAAAAAAAAABiBwAA',
    'LQAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAgAAAAAAAAAAAAAAkAcAAPAAAAAG',
    'AAAACAAAAAQAAAAQAAAACQAAAAMAAAAAAAAAAAAAAIAIAABqAAAAAAAAAAAA',
    'AAABAAAAAAAAABEAAAADAAAAAAAAAAAAAADqCAAANwAAAAAAAAAAAAAAAQAA',
    'AAAAAAA=',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAa4MECDQAAACQBwAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAjNBQAAzQUAAAUAAAAAEAAAAQAAANAF',
    'AADQlQQI0JUECAAAAAAIAAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAFWJ5VdWvgIAAABTifCD5PCDxIDNgIXAdCm/BwAAAInD',
    'jUwkFDHSifjNgInwzYCJw4XAdA6J+M2AifDNgInGhcB1C7gBAAAAMdvNgOv+',
    'ifiJ882A6IwCAAAx9r8CAAAAjUwkFIlEJAyJ+M2AiUQkCIXAdVy+AQAAAL8F',
    'AAAAu0yFBAiLVCQIifiJ8c2Aice4PwAAAIn7zYAxwDHSx0QkIFaFBAiNTCQg',
    'iUQkJLtWhQQIuAsAAACJVCREjVQkQMdEJEBhhQQIzYCJ8InzzYDr/nkOMdK4',
    'a4UECOjeAgAA6xqLXCQIuAcAAAAx0s2ARoH+lgAAAA+Fbv///zHSgf6WAAAA',
    'uHyFBAgPlMIx9uirAgAAifC/ZAAAAMZEJCkAjVwkIJnHRCQgL3RtcPf/ZsdE',
    'JCQvc78KAAAAg8AwiEQkJonwmff/idGZ9/+DwTC/BQAAAIhMJCiJ+LlCAAAA',
    'g8IwiFQkJ7qAAQAAzYCJx4XAeCe4BAAAALk7hQQIuhAAAACJ+82AuAYAAADN',
    'gEaB/iwBAAAPhXr///8x0oH+LAEAALiMhQQIv2QAAAAPlMK+CgAAAOgGAgAA',
    'McmJyMdEJCAvdG1wmWbHRCQkL3P3/8ZEJCkAg8AwiEQkJonImff+idOZ9/6N',
    'QzCNXCQgiEQkKInwg8IwiFQkJ82AQYH5LAEAAHW3vmQAAAC/KgAAAIn4jVwk',
    'GM2AuAQAAACLXCQcuZqFBAi6AQAAAM2AugYAAACLXCQYidDNgItcJByJ0M2A',
    'TnXL6KAAAAC7uoUECInGuJyFBAjoRgEAAItEJAzooQEAALithQQI6DMBAACJ',
    '8OiQAQAAuLWFBAjoIgEAAI1MJEC4YwAAAM2AhcB1F4F8JEBT7wAAdQ2LRCQM',
    'ugAQAAAp8OsLi0QkDLoAAQAAKfA5wri/hQQID5/CD7bS6P8AAAAxwIM90JUE',
    'CAAPlcCNZfRbXl9dw7itAAAAzYAx7Yngg+TwUOh4AQAAVTHSidGJ5Ve/BQAA',
    'AFaJ+FO7GYUECIHsAAIAAM2Ag8r/hcAPiIEAAACJx74DAAAAjY30/f//uv8B',
    'AACJ8In7zYCJxrgGAAAAzYAxwIX2D0jwicjGhDX0/f//AIoQhNJ0R4D6RnU/',
    'gHgBcnU5gHgCZXUzgHgDZXUtgHgEOnUnKciDwAWAPAEgdQNA6/cByDHSD74I',
    'QI1Z0ID7CXcOa9IKjVQK0OvrQOuzMdKBxAACAACJ0FteX13DVYnBMdKJ5VOA',
    'PBEAdANC6/e4BAAAALsBAAAAzYBbXcNVieVWica4M4UECFOJ0+jN////ifDo',
    'xv///4XbuCyFBAi6J4UECA9Fwuiy////hdt0CP8F1JUECOsG/wXQlQQIW15d',
    'w1WJ5VZTicOD7DDGRfcAhcB5DvfYuSEAAAC+CgAAAOsNdfLGRfYwuSAAAADr',
    'H4XAdBEx0kn39oqSO4UECIhUDdbr64XbeQbGRA3VLUmNRdYByOhG////g8Qw',
    'W15dw1WJ5VOD7AiLRQiLEI1IBI1EkAhQUVLoifv//4nDuAEAAADNgIPEEOv+',
    'L3Byb2MvbWVtaW5mbwAgT0sKACBGQUlMCgBLVEVTVDogADAxMjM0NTY3ODlh',
    'YmNkZWYAL2Rldi9udWxsAC9iaW4vaGVsbG8AUEFUSD0vYmluAHN0cmVzcy5m',
    'b3JrX2ZhaWwAc3RyZXNzLmZvcmtleGVjAHN0cmVzcy5jcmVhdGUAeAAgIE1l',
    'bUZyZWUgYXZhbnQ9ACBhcHJlcz0AIGtCCgAvdG1wAHN0cmVzcy5ub2xlYWsA',
    'R0NDOiAoVWJ1bnR1IDEzLjMuMC02dWJ1bnR1Mn4yNC4wNC4xKSAxMy4zLjAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAABADx/woAAAB4gwQItwAA',
    'AAIAAQASAAAAL4QECCAAAAACAAEAFwAAAE+EBAhEAAAAAgABAB0AAADUlQQI',
    'BAAAAAEAAwAlAAAA0JUECAQAAAABAAMALQAAAJOEBAhdAAAAAgABAEAAAADw',
    'hAQIKQAAABIAAQBGAAAAZIMECAAAAAAQAAEAWAAAAGuDBAgAAAAAEAABAFMA',
    'AADQlQQIAAAAABAAAwBBAAAAlIAECNACAAASAAEAXwAAAM2VBAgAAAAAEAAD',
    'AGYAAADYlQQIAAAAABAAAwAAc3RyZXNzLmMAbWVtZnJlZQBwdXRzAGt0ZXN0',
    'AGt1X3Bhc3MAa3VfZmFpbABwdXRudW0uY29uc3Rwcm9wLjAAY21haW4AX19y',
    'ZXN0b3JlX3J0AF9fYnNzX3N0YXJ0AF9lZGF0YQBfZW5kAAAuc3ltdGFiAC5z',
    'dHJ0YWIALnNoc3RydGFiAC50ZXh0AC5yb2RhdGEALmJzcwAuY29tbWVudAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAbAAAA',
    'AQAAAAYAAACUgAQIlAAAAIUEAAAAAAAAAAAAAAEAAAAAAAAAIQAAAAEAAAAy',
    'AAAAGYUECBkFAAC0AAAAAAAAAAAAAAABAAAAAQAAACkAAAAIAAAAAwAAANCV',
    'BAjQBQAACAAAAAAAAAAAAAAABAAAAAAAAAAuAAAAAQAAADAAAAAAAAAAzQUA',
    'AC0AAAAAAAAAAAAAAAEAAAABAAAAAQAAAAIAAAAAAAAAAAAAAPwFAADwAAAA',
    'BgAAAAgAAAAEAAAAEAAAAAkAAAADAAAAAAAAAAAAAADsBgAAawAAAAAAAAAA',
    'AAAAAQAAAAAAAAARAAAAAwAAAAAAAAAAAAAAVwcAADcAAAAAAAAAAAAAAAEA',
    'AAAAAAAA',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAbYEECDQAAAD4AgAAAAAAADQAIAAC',
    'ACgABwAGAAEAAAAAAAAAAIAECACABAjTAQAA0wEAAAUAAAAAEAAAUeV0ZAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAABgAAABAAAABVMdK5AgAAAInlV78FAAAAVon4',
    'U7uggQQIgeyEAAAAzYC7rYEECInGuQEAAACJvXD///+4BQAAAM2AiYVw////',
    'gLq4gQQIAHQDQuv0uAQAAAC5uIEECIudcP///82AvwMAAAC6fwAAAInzifiN',
    'jXT////NgInHMcCF/w9JxzHSicaAusOBBAgAdANC6/SLnXD///+4BAAAALnD',
    'gQQIzYCF/34NgLw1c////wqNVv90AonyuAQAAACLnXD///+NjXT////NgDHS',
    'gLrQgQQIAHQDQuv0i51w////uAQAAAC50IEECM2AgcSEAAAAMcBbXl9dw7it',
    'AAAAzYAx7Yngg+TwUOgAAAAAVYnlU4tFCIsQjUgEjUSQCFBRUuji/v//icO4',
    'AQAAAM2Ag8QM6/4vZGV2L2NvbnNvbGUAL2Rldi90dHlTMABLQkQ6IHByZXQK',
    'AEtCRDogbGlnbmU9WwBdCgBHQ0M6IChVYnVudHUgMTMuMy4wLTZ1YnVudHUy',
    'fjI0LjA0LjEpIDEzLjMuMAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAA',
    'BADx/wsAAAB6gQQIJgAAABIAAQARAAAAZoEECAAAAAAQAAEAIwAAAG2BBAgA',
    'AAAAEAABAB4AAADTkQQIAAAAABAAAgAMAAAAdIAECPIAAAASAAEAKgAAANOR',
    'BAgAAAAAEAACADEAAADUkQQIAAAAABAAAgAAa2JkdGVzdC5jAGNtYWluAF9f',
    'cmVzdG9yZV9ydABfX2Jzc19zdGFydABfZWRhdGEAX2VuZAAALnN5bXRhYgAu',
    'c3RydGFiAC5zaHN0cnRhYgAudGV4dAAucm9kYXRhAC5jb21tZW50AAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAbAAAAAQAAAAYA',
    'AAB0gAQIdAAAACwBAAAAAAAAAAAAAAEAAAAAAAAAIQAAAAEAAAAyAAAAoIEE',
    'CKABAAAzAAAAAAAAAAAAAAABAAAAAQAAACkAAAABAAAAMAAAAAAAAADTAQAA',
    'LQAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAgAAAAAAAAAAAAAAAAIAAJAAAAAF',
    'AAAAAgAAAAQAAAAQAAAACQAAAAMAAAAAAAAAAAAAAJACAAA2AAAAAAAAAAAA',
    'AAABAAAAAAAAABEAAAADAAAAAAAAAAAAAADGAgAAMgAAAAAAAAAAAAAAAQAA',
    'AAAAAAA=',
    'f0VMRgEBAQAAAAAAAAAAAAIAAwABAAAAfZwECDQAAAAgLQAAAAAAADQAIAAD',
    'ACgACAAHAAEAAAAAAAAAAIAECACABAhsKgAAbCoAAAUAAAAAEAAAAQAAAIAK',
    'AACAugQIgLoECAAAAABoIAAABgAAAAAQAABR5XRkAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAGAAAAEAAAAI1MJASD5PC4BQAAAP9x/FWJ5Vcx/1aJ+lO7IqAECFGJ',
    '+YHsKAQAAM2AhcB5B7gsoAQI60mJxrk4BAAAuBMAAACJ882AuQMAAAC6AgAA',
    'AInIjY3o/f//zYCJwbgGAAAAzYCD+QJ1EoC96P3//1N1CYC96f3//+90EbhX',
    'oAQI6BoeAAAxwOlNGwAAuBUAAAC7IqAECLmPoAQIif66iqAECM2AMdKFwImF',
    '5Pv//4mF3Pv//w+UwriUoAQI6PwdAACDveT7//8AdHSLneT7///Ghd38//8A',
    'uSEAAAD32w9IneT7//+J2L8KAAAAMdL394nOSYqSEKoECIiUKbz8//+J2onD',
    'g/oJd9yDveT7//8AeQvGhDW6/P//LY1O/o2FvPz//wHI6HUdAAC4n6AECOhr',
    'HQAAuAEAAADpmxoAAI2V6P3//7iqoAQI6A8dAAAx0oP4EHUXurmgBAiNhej9',
    '///oohoAADHShcAPlMK4yqAECL4FAAAAu9qgBAjoPR0AADHSifCJ0c2AicKJ',
    'xrjnoAQI99LB6h/oIh0AAIPsDLngkwQAMdJqAInw6J4aAACJwrj1oAQI6AMd',
    'AADHBCT//wEAuVgbAACJ8Lr//wEA6HoaAACDxBCFwHUEMdLrQ4PsDLkUAAAA',
    'uvsvAACJ8Gj7LwAA6FYaAACDxBCFwHTcg+wMuv0vBAC5CgAAAInwaP0vBADo',
    'NhoAADHSg8QQhcAPlcK4B6EECInz6JEcAAC4xQAAALmA2gQIzYAx0oE9rNoE',
    'COCTBAB1FKGQ2gQIMdIlAPAAAD0AgAAAD5TCuBmhBAiJ8+hXHAAAuAYAAADN',
    'gLgEoAQI6GQbAAAx0oP4Z7gnoQQID5TC6DQcAAC4OqEECOikGgAAhcB1BDHS',
    '6y24QaEECOiSGgAAhcB07rj1owQI6IQaAACFwHTguEqhBAjodhoAADHShcAP',
    'lMK4U6EECOjrGwAAjZXo/f//uGahBAjoexsAADHSg/gIdRe6eKEECI2F6P3/',
    '/+gOGQAAMdKFwA+UwriBoQQIvpKhBAjorhsAAInzuFUAAAC6LAEAAI2NvPz/',
    '/82AMdKD+Al1HLqvoAQIuQkAAACNhbz8///o6BgAADHShcAPlMK4oKEECLuz',
    'oQQI6GgbAAC4VQAAALosAQAAjY28/P//zYAx0oP4a3UlgL28/P//eHUcusGh',
    'BAi5BwAAAI2FIP3//+ibGAAAMdKFwA+UwrjJoQQI6CAbAACNlej9//+4kqEE',
    'COiwGgAAMdKD+BB1F7q5oAQIjYXo/f//6EMYAAAx0oXAD5TCuNyhBAi78KEE',
    'COjjGgAAuMMAAAC5gNoECM2AMdKDPZTaBAgCuP6hBAiJ8w+Uwui/GgAAuMQA',
    'AAC5gNoECM2AoZDaBAgx0iUA8AAAPQCgAAB1DDHSgz2s2gQICQ+UwrgSogQI',
    'uyWiBAjohRoAALjDAAAAuYDaBAjNgKGQ2gQIMdIlAPAAAD0AQAAAdQwx0oM9',
    'lNoECAIPlMK4M6IECL4FAAAAu0GiBAjoRhoAADHSifCJ0c2Ag/j+dRGJ8LtO',
    'ogQIzYAx0oP47A+UwrhfogQIvwUAAAC7BKAECOgUGgAAMdKJ+InRzYC+AwAA',
    'AInDugoAAACJ8I2N6P3//82Aica4BgAAAM2AMdKD/uu4a6IECLuPoAQID5TC',
    '6NYZAAC6YwAAAI2N9Pv//4nQzYCLhfj7//+Jhdj7//+J0M2Ai4UA/P//iYXQ',
    '+///idDNgIuFDPz//74nAAAAue0BAAC7gKIECImF1Pv//4nwzYAx0oXAuIei',
    'BAgPlMLodxkAAInwue0BAADNgDHSg/jvuJKiBAi7o6IECA+UwuhXGQAAucIA',
    'AAC6pAEAAIn4zYCJwonGuLCiBAj30onzweof6DQZAACD7AwxybqghgEAaAkD',
    'AACJ8Og2FwAAicK4vKIECOgSGQAAMcC5oIYBADHSiQQkifDojhYAAInCuM+i',
    'BAjo8xgAALjFAAAAuYDaBAjNgDHSg8QQgT2s2gQIoIYBAHUPMdKBPbjaBAjD',
    'AAAAD5fCuOOiBAi/BgAAAInz6LYYAACJ+M2AvgUAAAC5AQQAALujogQIMdKJ',
    '8M2AufOiBAiJw7oHAAAAuAQAAADNgIn4zYC4wwAAALujogQIuYDaBAjNgDHJ',
    'ibXk+///uAUAAACJys2AuaCGAQCJheT7//+4EwAAAIud5Pv//82AvgMAAACL',
    'neT7//+6FAAAAI2N6P3//4nwzYCJxoud5Pv//4n4zYCBPazaBAinhgEAdSOD',
    '/gd1HrrzogQIuQcAAACNhej9///oahUAADHShcAPlMLrAjHSuPuiBAi7o6IE',
    'COjmFwAAuFwAAAC5OTAAAM2AMdKFwLgHowQID5TC6MkXAAC4wwAAALmA2gQI',
    'zYC5AgAAADHSuAUAAADNgIE9rNoECDkwAACJheT7//91GYPsDLk5MAAAagDo',
    'HRUAADHSg8QQhcAPlcK4HKMECOh6FwAAuF0AAAC5UMMAAIud5Pv//82AMdKF',
    'wLgvowQID5TC6FcXAAC4EwAAALk5MAAAMdKLneT7///NgDH/vgEAAAC6F5MA',
    'ALgAIAAAi53k+///uYC6BAgp+jnCD0fQuAMAAADNgIXAfh8x0jHJgLqAugQI',
    'AA9F8UI5wnXxAdeB/xaTAAB+vOsCMfaJ8rhFowQIvogTAADo4xYAALpdAAAA',
    'i53k+///ifGJ0M2AuSgjAACJ0Iud5Pv//82AuBMAAAAx0oud5Pv//4nxzYC4',
    'AwAAALqgDwAAuYC6BAiLneT7///NgDHSPaAPAAAPlMIxyTHbOcF9DYC5gLoE',
    'CAAPRdNB6++F0nQhg+wMi4Xk+///MdK5iBMAAGoA6PATAAAx0oPEEIXAD5XC',
    'uFejBAjoTRYAAIud5Pv//7gGAAAAzYC+BQAAALkBAgAAMdK7o6IECInwzYC5',
    'gNoECInGuMMAAADNgIX2eBAx0qGs2gQICwW42gQID5TCuG+jBAiJ8+j9FQAA',
    'uAYAAADNgL4FAAAAuUIAAAC6pAEAALt7owQIifDNgL8TAAAAicOJ8THSifjN',
    'gL4EAAAAuYmjBAi6AQAAAInwzYC5IE4AAImF5Pv//zHSifjNgLmLowQIifC6',
    'AQAAAM2AuUBLTACJheD7//8x0on4zYC5jaMECInwugEAAADNgLkAAGAEiYXM',
    '+///MdKJ+M2AuY+jBAiJ8LoBAAAAzYCDveT7//8BD5TBg73g+///AQ+UwiHR',
    'g73M+///AQ+UwiHRMdJIuJGjBAgPlMIhyugrFQAAuMUAAAC5gNoECM2AMdKB',
    'PazaBAgBAGAEdQ8x0oE9uNoECMcAAAAPlsK4o6MECOj4FAAAuBMAAAC5BQAA',
    'ADHSzYC+AwAAAI2N6P3//7oBAAAAifDNgIC96P3//0G5IE4AAA+UwDHSice4',
    'EwAAAM2AugEAAACJ8I2N6P3//82AgL3o/f//QrlAS0wAD5TAMdIhx7gTAAAA',
    'zYC6AQAAAInwjY3o/f//zYCAvej9//9DuQAAYAQPlMAx0iHHuBMAAADNgLoB',
    'AAAAifCNjej9///NgDHAgL3o/f//RLnAxi0AD5TAMdIhx7gTAAAAzYC6CAAA',
    'AInwjY3o/f//zYAxwDHSgLwo6P3//wAPRfpAg/gIde+J+ri0owQI6A8UAAC4',
    'BgAAAM2AuAoAAAC7e6MECM2AMdKFwLjFowQIu9ajBAgPlMLo5hMAALonAAAA',
    'ue0BAACJ0M2AMduFwHUQidC736MECM2AMduFwA+Uw7jqowQIidrothMAADHA',
    'iYXk+///McCNvfT7//++IaoECLkuAAAA86SNvSL8//+5IgAAALtkAAAA86qN',
    'hfT7///ouRAAAInBi4Xk+///jXEDmff7uwoAAACDwDCIhA30+///i4Xk+///',
    'mff7ideZ9/uNRzC/BQAAAI2d9Pv//4iEDfb7//+J+IPCMIiUDfX7//+5QQAA',
    'ALqkAQAAxoQ19Pv//wDNgInHhcB5BDHS60K4BAAAAIn7jY30+///ifLNgLgG',
    'AAAAzYD/heT7//+BveT7//8sAQAAD4U3////uNajBAjo+REAADHSPS8BAAAP',
    'lMK4+aMECLvWowQI6MISAAC4wwAAALmA2gQIzYAx0oE9rNoECP8LAAB2DDHS',
    'gz2U2gQIAw+UwrgLpAQIMf/okBIAAIm94Pv//8eF5Pv//wEAAACNvfT7//++',
    'IaoECLkuAAAAMcDzpI29Ivz//4mNzPv//7kiAAAA86qNhfT7//+5ZAAAAOiF',
    'DwAAicOLheD7///GhB33+///AJn3+bkKAAAAg8AwiIQd9Pv//4uF4Pv//5n3',
    '+YnWmff5jUYwiIQd9vv//4nIg8IwiJQd9fv//42d9Pv//82AhcCLhcz7//8P',
    'RIXk+///g4Xg+///AoG94Pv//ywBAACJheT7//8PhU////+FwHQbuNajBAjo',
    '3xAAAD2ZAAAAD5TAD7bAiYXk+///i5Xk+///uCCkBAgx9uieEQAAibXg+///',
    'x4Xk+///AQAAADHAjb30+///vk+qBAi5CwAAAPOkjb3/+///uUUAAAC7ZAAA',
    'APOqjYX0+///6JkOAACJwYuF4Pv//8aEDff7//8Amff7uwoAAACDwDCIhA30',
    '+///i4Xg+///mff7idaZ9/uNRjC+BQAAAI2d9Pv//4iEDfb7//+J8IPCMIiU',
    'DfX7//+5QQAAALqkAQAAzYCJxoXAeAu4BgAAAInzzYDrCDHbiZ3k+///g4Xg',
    '+///AoG94Pv//ywBAAAPhUL///+DveT7//8AdBu41qMECOjbDwAAPS8BAAAP',
    'lMAPtsCJheT7//+LleT7//+4MaQECL4oAAAAu9ajBAjokhAAAInwzYAx0oP4',
    '2bhGpAQIu6qgBAgPlMLodxAAAInwzYAx0oP47LhapAQIu9+jBAgPlMLoXBAA',
    'AInwzYAx0oXAdRG4IQAAAInRzYAx0oP4/g+UwrhqpAQIu9ajBAjoMhAAALgK',
    'AAAAzYAx0oP467h4pAQIu5OkBAgPlMLoFBAAALqIpAQIuJOkBAjoSRAAALqd',
    'pAQIuKikBAjoOhAAALgmAAAAuaikBAjNgDHShcC4sqQECA+UwujZDwAAjZXo',
    '/f//uKikBAjoaQ8AADHJg/gKdS+6iKQECI2F6P3//4mN5Pv//+j2DAAAi43k',
    '+///hcB1D7ghAAAAzYAxyYP4/g+UwYnKuMakBAi+JwAAALvapAQI6H0PAACJ',
    '8LntAQAAzYC746QECInwzYC77KQECInwzYC6+qQECLgBpQQIvyYAAADokg8A',
    'AIn4uRGlBAjNgDHShcC4IKUECLsRpQQID5TC6C8PAACNlej9//+4NaUECOi/',
    'DgAAMdKD+Aa4RqUECA+UwugNDwAAugwAAACJ0M2Au16lBAiJ0M2AuLcAAAC5',
    'LAEAAI2dvPz//82Au2GlBAiJ0M2AuuOkBAiNhbz8//+72qQECOgVDAAAMdKF',
    'wLhjpQQID5TC6LoOAAC6wwAAALmA2gQIidDNgIM9lNoECAKJ0LvjpAQID5SF',
    '5Pv//82AMdKLheT7//+DPZTaBAgDu4ilBAgPlMIhwrh2pQQI6HIOAACJ8Lnt',
    'AQAAzYC7EaUECIn4uYilBAjNgDHShcB1FbghAAAAu5SlBAiJ0c2AMdKFwA+U',
    'wriipQQIv8MAAAC746QECOgsDgAAifi5gNoECM2AMdKDPZTaBAgCuL2lBAi+',
    'JgAAAA+UwugIDgAAifC51KUECM2AMdKD+Oq44KUECLv2pQQID5TC6OgNAAC4',
    'JwAAALntAQAAzYC6XaIECLgApgQIu+OkBAjoDA4AAInwufalBAjNgDHSg/jZ',
    'uAymBAi7qKQECA+UwuioDQAAifC5iKUECM2AMdKD+Ou4JqYECLuIpQQID5TC',
    '6IgNAACJ8LmopAQIzYAx0oP47LhApgQIvgkAAAAPlMK7X6YECOhjDQAAulqm',
    'BAi4X6YECOiYDQAAifC5aaYECM2AMdKFwLhzpgQID5TC6DoNAACJ+LmA2gQI',
    'zYAx0oM9lNoECAK4faYECA+UwugbDQAAuAoAAADNgLtppgQIifi5gNoECM2A',
    'jZXo/f//idjomQwAAIM9lNoECAEPlMEx0oP4BLiNpgQID5TCIcro2wwAAInw',
    'idnNgDHSg/jvuKKmBAi7gKIECA+Uwui+DAAAifC5sqYECM2AMdJAuLymBAi7',
    'yqYECA+UwuigDAAAuUIAAAC6pAEAALgFAAAAzYCD7AyJheT7//8xybowdQAA',
    'aOgDAADojQoAALgKAAAAzYAxyYuF5Pv//zHSv2MAAACJDCS5MHUAALuPoAQI',
    '6NwJAACNjfT7//+Jwon4zYC4BgAAAIu1APz//4ud5Pv//82Ag8QQhdJ0JYn4',
    'u4+gBAjNgDHSuDB1AAD3tdj7//8x0o1EBv47hQD8//8PksK43aYECLv4pgQI',
    '6PMLAAC4UwAAALnupgQIzYAx0oXAuP6mBAi77qYECA+UwujRCwAAuFUAAAC6',
    'LAEAAI2NvPz//82AMdKD+AV1HLr4pgQIuQUAAACNhbz8///oDQkAADHShcAP',
    'lMK4EKcECLsaAAAA6I0LAAAxyYnIjbX0+///mff7g8JhiJQN9Pv//0GB+ZYA',
    'AAB14r8npwQIxoWK/P//ALhTAAAAifOJ+c2AMdKFwLgxpwQIifsPlMLoQwsA',
    'ALhVAAAAuiwBAACNjbz8///NgDHSPZYAAAB1GYnyuZYAAACNhbz8///ogAgA',
    'ADHShcAPlMK4Q6cECLtmpwQI6AALAAC6WqcECLhfpwQI6DULAAC4UwAAALlr',
    'pwQIzYCNlej9//+JyOh4CgAAMdKD+AR1F7papwQIjYXo/f//6AsIAAAx0oXA',
    'D5TCuHWnBAiJ++iuCgAAugoAAACJ0M2AMcmFwHUQidC77qYECM2AMcmFwA+U',
    'wYnKuImnBAi+DgAAALudpwQI6HkKAACJ8LmkEQAAMdLNgDHShcC4p6cECLu3',
    'pwQID5TC6FgKAACJ8LmAIQAAugEFAADNgDHShcC4wacECLvQpwQID5TC6DQK',
    'AACJ8LmAYQAAugEDAADNgDHShcC+wwAAALjapwQID5TCu52nBAjoCwoAAInw',
    'uYDaBAjNgKGQ2gQIMdK7t6cECCUA8AAAPQAQAACJ8A+Uws2AoZDaBAgxySUA',
    '8AAAPQAgAAB1DjHJZoE9oNoECAEFD5TBic64wwAAALvQpwQIuYDaBAgh1s2A',
    'oZDaBAgx0iUA8AAAPQBgAAB1DjHSZoE9oNoECAEDD5TCIfK46acECLtfpwQI',
    '6H0JAAC4DwAAALmAAQAAzYAx0oXAvsMAAAC4+acECA+UwuhbCQAAifC5gNoE',
    'CM2AoZDaBAgx0iX/DwAAPYABAAC4BKgECA+Uwug0CQAAuLYAAAC50gQAALou',
    'FgAAzYAx0oXAuBSoBAgPlMLoEgkAAInwuYDaBAjNgDHSgT2Y2gQI0gQAAHUP',
    'MdKBPZzaBAguFgAAD5TCuB+oBAiNvfT7//++XKoECOjXCAAAuQQAAAC4DwEA',
    'APOljY30+///zYAx0oXAuC+oBAgPlMLosggAALjDAAAAuYDaBAjNgDHSuDuo',
    'BAiBPcjaBAgAq5BBD5TC6I0IAAC6CgAAAInQzYC7a6cECInQzYC7aaYECInQ',
    'zYC7nacECInQzYC7t6cECInQzYC70KcECInQzYC7qKQECInQzYC7lKUECInQ',
    'zYC5KAAAALuIpQQIicjNgLsApgQIidDNgLv2pQQIicjNgLvapAQIicjNgLvj',
    'pAQIicjNgLujogQIidDNgDHSjZ30+///iZXk+///McCNvfT7//++IaoECLku',
    'AAAA86SNvSL8//+5IgAAAPOqjYX0+///uWQAAADoBwUAAInGi4Xk+///xoQ1',
    '9/v//wCZ9/m5CgAAAIPAMIiENfT7//+LheT7//+Z9/mJ15n3+Y1HMIiENfb7',
    '//+JyIPCMIiUNfX7///NgP+F5Pv//4G95Pv//ywBAAAPhXH///8xwImF5Pv/',
    '/zHAjb30+///vk+qBAi5CwAAAPOkjb3/+///uUUAAADzqo2F9Pv//7lkAAAA',
    '6HAEAACJw4uF5Pv//8aEHff7//8Amff5uQoAAACDwDCIhB30+///i4Xk+///',
    'mff5idaZ9/mNRjCIhB32+///iciDwjCIlB31+///jZ30+///zYCDheT7//8C',
    'gb3k+///LAEAAA+Fav///74oAAAAu9ajBAiJ8M2AMdKFwLhMqAQIu4CiBAgP',
    'lMLoqwYAAInwzYAx0oXAuF+oBAi7j6AECA+UwuiRBgAAumMAAACNjfT7//+J',
    '0M2AMcCLvdD7//87vQD8//91FonQzYCLhdT7//87hQz8//8PlMAPtsCJwjH/',
    'uGyoBAi7IqAECOhJBgAAif64FQAAALmBqAQIuoqgBAjNgDHSg/jwuIaoBAi7',
    'BKAECA+UwugfBgAAugwAAACJ0M2AvhYAAAC7j6AECInwzYC7YaUECInBidDN',
    'gDHSg/nwuJeoBAi7xagECA+UwujmBQAAuqioBAi4tKgECOgbBgAAuCcAAAC5',
    '7QEAAM2Aus+oBAi42qgECLu5qAQI6PsFAAC4UwAAALnsqAQIzYC7BQAAALlB',
    'AAAAuqQBAACJ2Lv3qAQIzYCD7Ay5AwAAALqAGgYAicNoABAAAOiSAwAAuAYA',
    'AADNgLuPoAQIifDNgDHShcC4AakECL4BAAAAD5TCuyKgBAjoTwUAALgVAAAA',
    'uY+gBAi6iqAECM2AMdKFwLgNqQQID5TC6C0FAACNlej9//+4tKgECOi9BAAA',
    'g8QQMdKD+At1F7qoqAQIjYXo/f//6E0CAAAx0oXAD5TCuB2pBAjo8gQAAI2V',
    '6P3//7jaqAQI6IIEAAAx0oP4CnUXus+oBAiNhej9///oFQIAADHShcAPlMK4',
    'L6kECL4FAAAAu/eoBAjosAQAADHJifCJys2Ag+wMuYAaBgCJx2oDifvoJAIA',
    'AInCuECpBAjoiQQAALgGAAAAzYC4VQAAALosAQAAu+yoBAiNjbz8///NgDHS',
    'g/gLuFGpBAi7Y6kECA+UwuhUBAAAifC5QQAAALqkAQAAzYAx0oP44rhwqQQI',
    'u6qgBAgPlMLoLwQAAInwuQEAAAAx0s2AMdKD+OK4f6kECLuNqQQID5TC6A0E',
    'AAC4JwAAALntAQAAzYAx0oP44riVqQQIu6qgBAgPlMLo6gMAALgKAAAAzYAx',
    '0oP44rijqQQID5TC6NEDAAC4JgAAALmyqQQIzYAx0oP44ri6qQQIu4+gBAgP',
    'lMLorgMAAI2N9Pv//7hjAAAAzYCDxBCBvfT7//9T7wAAdSiLlfj7//+NggD8',
    '//+p//v//w+UwIH6ABAAAA+UwgnQD7bAiYXc+///i5Xc+///uMmpBAi7j6AE',
    'COhVAwAAuBYAAADNgDHShcC426kECLsioAQID5TCMfboNgMAAIn3uBUAAAC5',
    'j6AECLqKoAQIzYAx0oXAuOqpBAi796gECA+UwugNAwAAuAoAAADNgLgWAAAA',
    'u4+gBAjNgLj+qQQI6NICAAAxwIM94NoECAAPlcCNZfBZW15fXY1h/MO4rQAA',
    'AM2AMe2J4IPk8FDoUQMAAInCMcCAPAIAdANA6/fDVYnlVonGUzHbD7YEHg+2',
    'DBqEwHQFQzjIdO9bKcheXcNVAcGJ5VaJ1lOJww+2Aw+2FjjQdAQp0OsIQ0Y5',
    'y3XsMcBbXl3DVYnlV1aJ1jHSU4nDuBMAAACB7OQFAACJjRD6//+J8c2AOcZ1',
    'VzH2i5UQ+v//uNwFAACNjRj6//8p8jnCD0fQuAMAAADNgInHhcB+MItNCDHS',
    'AfGwBw+vwQDoOIQqGPr//3UZQkE5+nXqi4UQ+v//AdY5xnKyuAEAAADrAjHA',
    'gcTkBQAAW15fXcNVieVXiddWMfZTg+wIiUXwiU3si0Xsifop8jtVCA9HVQgx',
    'yY0cMLAHQQ+vwwD4Q4iBf7oECDnKde2LXfC4BAAAALmAugQIzYA5wnUNAdY5',
    '/nLBuAEAAADrAjHAWllbXl9dw1W5AAABADHSieVXVlO7BKAECIHsHAEAAImF',
    '4P7//7gFAAAAzYAx9omF5P7//4XAeGa/3AAAAIud5P7//42N6P7//7oAAQAA',
    'ifjNgInHhcB+OTHbjYwd6P7//4uV4P7//41BE4mN3P7//+hi/v//i43c/v//',
    'hcC4AQAAAA9E8A+3QRABwzn7fMvrp7gGAAAAi53k/v//zYCBxBwBAACJ8Fte',
    'X13DVbkAAAEAMdKJ5VdWU4nDuAUAAACB7KQAAADNgImFUP///4XAeEkx9o2N',
    'VP///7/cAAAAi51Q////uqAAAACJ+M2AiceFwH4TMcAPt5QFZP///0YB0Dn4',
    'fPHr04udUP///7gGAAAAzYCF/w9F9+sGi7VQ////gcSkAAAAifBbXl9dw1WJ',
    '5VaJ1jHSU4nRicO4BQAAAM2AicOFwHgiuAMAAAC6/wEAAInxzYAx0oXAD0nQ',
    'uAYAAADGBBYAzYCJ04nYW15dw1WJwYnlU7sBAAAAUuhJ/f//icK4BAAAAM2A',
    'WVtdw1WJ5VaJxrgaoAQIU4nT6M////+J8OjI////hdu4E6AECLoOoAQID0XC',
    '6LT///+F23QI/wXk2gQI6wb/BeDaBAhbXl3DVblBAgAAieVXide6pAEAAFa+',
    'BQAAAFOJw4nwg+wMzYCFwHgdicaJ+In56Mn8//+J84nCuAQAAADNgLgGAAAA',
    'zYCDxAxbXl9dw1WJ5VOD7AiLRQiLEI1IBI1EkAhQUVLonuD//4nDuAEAAADN',
    'gIPEEOv+L21udC9kaXIxACBPSwoAIEZBSUwKAEtURVNUOiAAL2Rldi9oZGEx',
    'ACAgKHBhcyBkZSAvZGV2L2hkYTEgOiB0ZXN0cyBleHQyIGlnbm9yZXMpCgAg',
    'IChwYXMgZCdleHQyIHN1ciAvZGV2L2hkYTEgOiB0ZXN0cyBleHQyIGlnbm9y',
    'ZXMpCgBleHQyAC9tbnQAZXh0Mi5tb3VudAAgPC0gbW91bnQKAC9tbnQvaGVs',
    'bG8udHh0AGhlbGxvIGZyb20gZXh0MgoAZXh0Mi5yZWFkX3NtYWxsAC9tbnQv',
    'YmlnLmJpbgBleHQyLmJpZ19vcGVuAGV4dDIuYmlnX3JlYWRfc2VxAGV4dDIu',
    'YmlnX3JlYWRfb2ZmAGV4dDIuYmlnX3N0YXQAZXh0Mi5yZWFkZGlyX2NvdW50',
    'AGYxLnR4dABmMTAwLnR4dABmMTAxLnR4dABleHQyLnJlYWRkaXJfbmFtZXMA',
    'L21udC9kaXIxL2Y1Ny50eHQAZmlsZSA1NwoAZXh0Mi5yZWFkX2luX2RpcgAv',
    'bW50L2Zhc3RsaW5rAGV4dDIucmVhZGxpbmtfZmFzdAAvbW50L3Nsb3dsaW5r',
    'AC90YXJnZXQAZXh0Mi5yZWFkbGlua19zbG93AGV4dDIuZm9sbG93X3N5bWxp',
    'bmsAL21udC9oYXJkLnR4dABleHQyLmhhcmRsaW5rX25saW5rAGV4dDIubHN0',
    'YXRfc3ltbGluawAvbW50L2VtcHR5ZGlyAGV4dDIuc3RhdF9kaXIAL21udC9u',
    'ZXhpc3RlAC9tbnQvaGVsbG8udHh0L3gAZXh0Mi5lbm9lbnQAZXh0Mi5yZWFk',
    'X2Rpcl9laXNkaXIAL21udC93AGV4dDIubWtkaXIAZXh0Mi5ta2Rpcl9leGlz',
    'dAAvbW50L3cvYS5kYXQAZXh0Mi5jcmVhdGUAZXh0Mi53cml0ZV9wYXR0ZXJu',
    'AGV4dDIud3JpdGVfcmVhZGJhY2sAZXh0Mi53cml0ZV9zaXplAEVORE1BUksA',
    'ZXh0Mi5hcHBlbmQAZXh0Mi50cnVuY2F0ZV9zaHJpbmsAZXh0Mi50cnVuY2F0',
    'ZV9zaXplAGV4dDIuZnRydW5jYXRlX2V4dGVuZABleHQyLmV4dGVuZF96ZXJv',
    'cwBleHQyLnRydW5jYXRlX3RhaWxfemVybwBleHQyLm90cnVuYwAvbW50L3cv',
    'c3BhcnNlAEEAQgBDAEQAZXh0Mi5zcGFyc2Vfd3JpdGUAZXh0Mi5zcGFyc2Vf',
    'c2l6ZQBleHQyLnNwYXJzZV9yZWFkAGV4dDIuc3BhcnNlX2ZyZWUAL21udC93',
    'L2QAL21udC93L2QvZQBleHQyLm1rZGlyX3N1YgBleHQyLmRpcl9ncm93XzMw',
    'MABleHQyLmRpcl9zaXplX2Jsb2NrcwBleHQyLnVubGlua19oYWxmAGV4dDIu',
    'ZGlyX3JldXNlX3Nsb3RzAGV4dDIucm1kaXJfbm90ZW1wdHkAZXh0Mi5ybWRp',
    'cl9maWxlAGV4dDIucm1kaXJfb2sAZXh0Mi51bmxpbmtfZGlyAGNvbnRlbnUt',
    'cjEAL21udC93L3IxAGNvbnRlbnUtcjIAL21udC93L3IyAGV4dDIucmVuYW1l',
    'X3JlcGxhY2UAZXh0Mi5yZW5hbWVfY29udGVudAAvbW50L3cveAAvbW50L3cv',
    'eQAvbW50L3cveC9zb3VzAGRlZGFucwAvbW50L3cveC9zb3VzL2YAL21udC93',
    'L3kvc291czIAZXh0Mi5yZW5hbWVfZGlyX21vdmUAL21udC93L3kvc291czIv',
    'ZgBleHQyLnJlbmFtZV9kaXJfY29udGVudAAuLgAvAGV4dDIucmVuYW1lX2Rv',
    'dGRvdABleHQyLnJlbmFtZV9ubGluawAvbW50L3cvdmlkZQAvbW50L3cvdmlk',
    'ZS9mAGV4dDIucmVuYW1lX2Rpcl9vdmVyX2VtcHR5AGV4dDIucmVuYW1lX292',
    'ZXJfbmxpbmsAL21udC93L3kvenoAZXh0Mi5yZW5hbWVfaW50b19zZWxmAC9t',
    'bnQvdy9uZQAvbW50L3cvbmUvZgBleHQyLnJlbmFtZV9vdmVyX25vdGVtcHR5',
    'AGV4dDIucmVuYW1lX2ZpbGVfb3Zlcl9kaXIAZXh0Mi5yZW5hbWVfZGlyX292',
    'ZXJfZmlsZQBsaWVuAC9tbnQvdy9sMQAvbW50L3cvbDIAZXh0Mi5saW5rAGV4',
    'dDIubGlua19ubGluawBleHQyLnVubGlua19vbmVfbGluawBleHQyLmxpbmtf',
    'ZXhpc3QAL21udC93L2RsAGV4dDIubGlua19kaXIAL21udC93L29wZW5fdW5s',
    'aW5rAGV4dDIudW5saW5rX29wZW4AL21udC93L3MxAGNpYmxlAGV4dDIuc3lt',
    'bGlua19mYXN0AGV4dDIuc3ltbGlua19mYXN0X3JlYWQAL21udC93L3MyAGV4',
    'dDIuc3ltbGlua19zbG93AGV4dDIuc3ltbGlua19zbG93X3JlYWQAcmVlbAAv',
    'bW50L3cvcmVhbAAvbW50L3cvczMAZXh0Mi5zeW1saW5rX2ZvbGxvdwBleHQy',
    'LnN5bWxpbmtfdW5saW5rAC9tbnQvdy9mZgBleHQyLm1rbm9kX2ZpZm8AL21u',
    'dC93L2NjAGV4dDIubWtub2RfY2hyAC9tbnQvdy9iYgBleHQyLm1rbm9kX2Js',
    'awBleHQyLm1rbm9kX3N0YXQAZXh0Mi5jaG1vZABleHQyLmNobW9kX3N0YXQA',
    'ZXh0Mi5jaG93bgBleHQyLmNob3duX3N0YXQAZXh0Mi51dGltZXMAZXh0Mi51',
    'dGltZXNfc3RhdABleHQyLnJtZGlyX2VtcHRpZWQAZXh0Mi5ybWRpcl93AGV4',
    'dDIuc3RhdGZzX3Jlc3RvcmVkAC90bXAAZXh0Mi5tb3VudF90d2ljZQBleHQy',
    'LnVtb3VudF9idXN5AHBlcnNpc3RhbnQKAC9tbnQvcGVyc2lzdC50eHQAL21u',
    'dC9wZGlyAGRhbnMgcGRpcgoAL21udC9wZGlyL2ZpY2hpZXIAL21udC9wbGlu',
    'awAvbW50L3BiaWcAZXh0Mi51bW91bnQAZXh0Mi5yZW1vdW50X3JvAGV4dDIu',
    'cGVyc2lzdF9maWxlAGV4dDIucGVyc2lzdF9kaXIAZXh0Mi5wZXJzaXN0X2Jp',
    'ZwBleHQyLnBlcnNpc3RfbGluawAvbW50L25vdXZlYXUAZXh0Mi5yb19jcmVh',
    'dGUAZXh0Mi5yb193cml0ZQAvbW50L3p6AGV4dDIucm9fbWtkaXIAZXh0Mi5y',
    'b191bmxpbmsAL21udC9oMgBleHQyLnJvX3JlbmFtZQBleHQyLnN0YXRmc19t',
    'YWdpYwBleHQyLnVtb3VudF9ybwBleHQyLm1vdW50X3J3X2FnYWluAEtURVNU',
    'OiBleHQyIERPTkUKADAxMjM0NTY3ODlhYmNkZWYAL21udC93L2QvdW5fbm9t',
    'X2RlX2ZpY2hpZXJfYXNzZXpfbG9uZ19udW1lcm9fAC9tbnQvdy9kL3oAAAAA',
    'ypo7AAAAAACrkEEAAAAAR0NDOiAoVWJ1bnR1IDEzLjMuMC02dWJ1bnR1Mn4y',
    'NC4wNC4xKSAxMy4zLjAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAA',
    'AAQA8f8MAAAAipwECA4AAAACAAEAEwAAAJicBAggAAAAAgABABoAAAC4nAQI',
    'JQAAAAIAAQAiAAAA3ZwECIkAAAACAAEALAAAAGadBAhiAAAAAgABADYAAACA',
    'ugQIACAAAAEAAwA7AAAAyJ0ECKQAAAACAAEATwAAAGyeBAiCAAAAAgABAGQA',
    'AADungQIQgAAAAIAAQB2AAAAMJ8ECB4AAAACAAEAewAAAE6fBAhEAAAAAgAB',
    'AIEAAADk2gQIBAAAAAEAAwCJAAAA4NoECAQAAAABAAMAkQAAAJKfBAhJAAAA',
    'AgABAJwAAACA2gQIYAAAAAEAAwCgAAAA258ECCkAAAASAAEApgAAAHacBAgA',
    'AAAAEAABALgAAAB9nAQIAAAAABAAAQCzAAAAgLoECAAAAAAQAAMAoQAAAJSA',
    'BAjiGwAAEgABAL8AAABsugQIAAAAABAAAwDGAAAA6NoECAAAAAAQAAMAAGV4',
    'dDJ0ZXN0LmMAc3RybGVuAHN0cmNtcABtZW1jbXBfAGZpbGxjaGVjawBmaWxs',
    'd3JpdGUAd2J1ZgBoYXNuYW1lLmNvbnN0cHJvcC4wAGNvdW50ZGlyLmNvbnN0',
    'cHJvcC4wAHNsdXJwLmNvbnN0cHJvcC4wAHB1dHMAa3Rlc3QAa3VfcGFzcwBr',
    'dV9mYWlsAHB1dC5pc3JhLjAAc2JfAGNtYWluAF9fcmVzdG9yZV9ydABfX2Jz',
    'c19zdGFydABfZWRhdGEAX2VuZAAALnN5bXRhYgAuc3RydGFiAC5zaHN0cnRh',
    'YgAudGV4dAAucm9kYXRhAC5ic3MALmNvbW1lbnQAAAAAAAAAAAAAAAAAAAAA',
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGwAAAAEAAAAGAAAAlIAECJQA',
    'AABwHwAAAAAAAAAAAAABAAAAAAAAACEAAAABAAAAAgAAAASgBAgEIAAAaAoA',
    'AAAAAAAAAAAABAAAAAAAAAApAAAACAAAAAMAAACAugQIgCoAAGggAAAAAAAA',
    'AAAAACAAAAAAAAAALgAAAAEAAAAwAAAAAAAAAGwqAAAtAAAAAAAAAAAAAAAB',
    'AAAAAQAAAAEAAAACAAAAAAAAAAAAAACcKgAAgAEAAAYAAAARAAAABAAAABAA',
    'AAAJAAAAAwAAAAAAAAAAAAAAHCwAAMsAAAAAAAAAAAAAAAEAAAAAAAAAEQAA',
    'AAMAAAAAAAAAAAAAAOcsAAA3AAAAAAAAAAAAAAABAAAAAAAAAA==');

{ END-EMBED }
{ Installer les programmes embarques dans le tmpfs racine }
Procedure InstallEmbedded;
Var I, L, K, N, Acc, Bits, V, Out, Buf, Line : LongInt; S : String;
Begin
  For I := 0 To EmbCount - 1 Do
  Begin
    Buf := KMalloc(EmbSize[I] + 4);
    If Buf = 0 Then Continue;
    Out := 0; Acc := 0; Bits := 0;
    For L := EmbStart[I] To EmbStart[I + 1] - 1 Do
    Begin
      S := EmbData[L];
      For K := 1 To Length(S) Do
      Begin
        V := B64Val(Ord(S[K]));
        If V >= 0 Then
        Begin
          Acc := (Acc Shl 6) Or V;
          Bits := Bits + 6;
          If Bits >= 8 Then
          Begin
            Bits := Bits - 8;
            If Out < EmbSize[I] Then
            Begin
              Mem[0:Buf + Out] := (Acc Shr Bits) And $FF;
              Inc(Out);
            End;
            Acc := Acc And ((1 Shl Bits) - 1);
          End;
        End;
      End;
    End;
    KWriteFile(EmbPath[I], $1ED, Buf, EmbSize[I]);
    KFree(Buf);
  End;
  Line := 0; N := 0;
End;

{ ---- Racine reelle : root=/dev/hdaN (ext2) ---- }

{ Creer un repertoire de point de montage, meme si le systeme de fichiers
  est monte en lecture seule (le drapeau est leve le temps de la creation) }
Procedure KMkdirForce(Sb : PSuper; Const P : String);
Var Fl : LongInt; D : PDentry;
Begin
  If PathWalk(P, True, D) = 0 Then
  Begin
    DentryPut(LongInt(D));
    Exit;
  End;
  Fl := Sb^.Flags;
  Sb^.Flags := Fl And Not MS_RDONLY;
  KMkdir(P, $1ED);
  Sb^.Flags := Fl;
End;

{ Abandonner un systeme de fichiers monte comme racine (pas de Covered) }
Procedure SbDrop(Sb : PSuper);
Var D : PDentry; Fn : LongInt;
Begin
  Fn := GetOp(Sb^.SOps, SoSync);
  If Fn <> 0 Then Call1(Fn, LongInt(Sb));
  D := Sb^.Root;
  Sb^.Root := Nil;
  DentryPurgeSb(Sb);
  DentryPut(LongInt(D));
  InodePurgeSb(Sb);
  Fn := GetOp(Sb^.SOps, SoUmount);
  If Fn <> 0 Then Call1(Fn, LongInt(Sb));
  If Sb^.Dev <> 0 Then BInvalidate(Sb^.Dev);
  SuperRelease(Sb);
End;

{ Un programme ordinaire existe-t-il a ce chemin ? }
Function IsProg(Const P : String) : Boolean;
Var D : PDentry; R : LongInt;
Begin
  IsProg := False;
  If P = '' Then Exit;
  R := PathWalk(P, True, D);
  If R <> 0 Then
  Begin
    KLog('racine : ' + P + ' : erreur ' + IntStr(-R));
    Exit;
  End;
  If (D^.Inode^.Mode And S_IFMT) = S_IFREG Then IsProg := True;
  DentryPut(LongInt(D));
End;

{ Un programme init existe-t-il (dans la racine courante du processus) ? }
Function FindInit : Boolean;
Begin
  FindInit := IsProg(InitPath) Or IsProg('/sbin/init') Or IsProg('/etc/init')
      Or IsProg('/bin/init') Or IsProg('/bin/sh');
End;

{ Monter root= comme racine : le systeme de fichiers ext2 remplace la racine
  en memoire (type pivot_root), /dev et /proc y sont remontes. Retourne
  Faux (et garde la racine en memoire) si root= est absent, illisible, ou
  si le disque ne contient aucun programme init. }
Function TryRealRoot : Boolean;
Var T, R, Fl : LongInt; Sb, OldSb : PSuper; Dn : String;
    OldRoot, OldPwd : LongInt; D : PDentry;
Begin
  TryRealRoot := False;
  If RootDev = '' Then Exit;
  T := FindFsType('ext2');
  If T < 0 Then Exit;
  Sb := SuperNew(T);
  If Sb = Nil Then Exit;
  Dn := RootDev;
  Sb^.DevName := KMalloc(Length(Dn) + 1);
  MemCopy(Sb^.DevName, LongInt(@Dn), Length(Dn) + 1);
  If CmdHas('rw') Then Fl := 0 Else Fl := MS_RDONLY;
  Sb^.Flags := Fl;
  R := Call4(FsMount[T], LongInt(Sb), LongInt(@Dn), Fl, 0);
  If R <> 0 Then
  Begin
    KLog('racine : impossible de monter ' + RootDev + ' (erreur '
        + IntStr(-R) + '), racine en memoire');
    SuperRelease(Sb);
    Exit;
  End;
  { basculer la racine du processus 0 (et celle des futurs processus) }
  OldRoot := IdleTask^.Fs^.Root;
  OldPwd := IdleTask^.Fs^.Pwd;
  DentryGet(LongInt(Sb^.Root));
  DentryGet(LongInt(Sb^.Root));
  IdleTask^.Fs^.Root := LongInt(Sb^.Root);
  IdleTask^.Fs^.Pwd := LongInt(Sb^.Root);
  If Not FindInit Then
  Begin
    KLog('racine : aucun programme init sur ' + RootDev
        + ', racine en memoire');
    IdleTask^.Fs^.Root := OldRoot;
    IdleTask^.Fs^.Pwd := OldPwd;
    DentryPut(LongInt(Sb^.Root));
    DentryPut(LongInt(Sb^.Root));
    SbDrop(Sb);
    Exit;
  End;
  { oublier l'ancienne racine en memoire (et ses montages /dev, /proc) }
  OldSb := PDentry(OldRoot)^.Sb;
  If WalkFrom(PDentry(OldRoot), 'dev', True, D) = 0 Then VfsUmountD(D, 0);
  If WalkFrom(PDentry(OldRoot), 'proc', True, D) = 0 Then VfsUmountD(D, 0);
  DentryPut(OldRoot);
  DentryPut(OldPwd);
  DentryPut(LongInt(RootDentry));
  SbDrop(OldSb);
  RootDentry := Sb^.Root;
  KMkdirForce(Sb, '/dev');
  KMkdirForce(Sb, '/proc');
  KMkdirForce(Sb, '/sys');
  VfsMount('devfs', '/dev', 'devtmpfs', 0, 0);
  VfsMount('proc', '/proc', 'proc', 0, 0);
  MakeDevNodes;
  If (Sb^.Flags And MS_RDONLY) <> 0 Then
    KLog('racine : ' + RootDev + ' montee en lecture seule')
  Else KLog('racine : ' + RootDev + ' montee en lecture-ecriture');
  TryRealRoot := True;
End;

{ Premier processus : ouvre la console, lance /sbin/init (ou init=) }
Procedure InitThread;
Var Fr, R, I : LongInt; F : PFile; P : String; Tried : Boolean;
Begin
  Cur^.Files := FilesNew;
  Cur^.Fs := FsNew;
  Cur^.Fs^.Root := RootDentry; DentryGet(LongInt(RootDentry));
  Cur^.Fs^.Pwd := RootDentry; DentryGet(LongInt(RootDentry));
  Cur^.Sig := SigNew;
  Cur^.Pgid := Cur^.Pid; Cur^.Sid := Cur^.Pid;
  Cur^.Tty := -1;
  Cur^.Frame := Cur^.KStack + KStackSize - SizeOf(TFrame);
  R := VfsOpen('/dev/console', O_RDWR, 0, F);
  If R = 0 Then
  Begin
    FdInstall(F, 0, False);
    FileGet(LongInt(F)); FdInstall(F, 1, False);
    FileGet(LongInt(F)); FdInstall(F, 2, False);
  End
  Else KLog('init : /dev/console inaccessible (' + IntStr(R) + ')');
  Tried := False;
  P := InitPath;
  If P = '' Then P := '/sbin/init';
  KLog('Lancement de ' + P);
  R := KernelExecve(P, P, 'HOME=/' + #0 + 'TERM=linux');
  If (R <> 0) And (InitPath <> '') Then
  Begin
    KLog('init : ' + P + ' introuvable (' + IntStr(R)
        + '), essai de /sbin/init');
    R := KernelExecve('/sbin/init', '/sbin/init', 'HOME=/');
  End;
  If R <> 0 Then
  Begin
    KLog('init : echec (' + IntStr(R) + ') essai de /bin/sh');
    R := KernelExecve('/bin/sh', '/bin/sh', 'HOME=/');
  End;
  If R <> 0 Then KPanic('Pas de programme init : ' + IntStr(R));
  I := 0;
  If Tried Then I := 1;
  JumpToUser(Cur^.Frame);
End;

{ Fil d'ecriture differee des tampons (bdflush) }
Procedure BdflushMain;
Begin
  BdFlushThread;
End;

Procedure PrintBanner;
Begin
  KLog('LINUX-0 KERNEL32 ' + KVersion
      + ' (i386) : noyau Linux 32 bits ecrit en Pascal');
End;

{ ==================================================================== }
{ Demarrage du noyau                                                    }
{ ==================================================================== }

Var
  KEndMark : LongInt;        { derniere variable globale : fin de l'image }

Function KernelEnd : LongInt;
Begin
  KernelEnd := LongInt(@KEndMark);
End;

Procedure KMain;
Var T : PTask; I : LongInt;
Begin
  SerialInit;
  InitVcons;
  LogToVc := True;
  PrintBanner;
  ParseMultiboot;
  ComputeRam;
  ParseCmdline;
  KLog('memoire : ' + IntStr(RamTopPhys Div 1048576)
      + ' Mo utilisables, ligne de commande : ' + CmdLine);
  InitMemory;
  KLog('pages libres : ' + IntStr(FreePagesCnt) + ' sur ' + IntStr(NPages));
  InitGdt;
  InitPic;
  InitIdt;
  InitTasks;
  InitSyscalls;
  HostName := 'linux0';
  DomainName := '(none)';
  InitTime;
  InitBlock;
  InitVfs;
  InitTmpfs;
  InitExt2;
  InitProc;
  InitDevices;
  MountRoot;
  MakeTree;
  InitTty;
  KLog('disque IDE : ' + IntStr(Ord(DiskPresent[0]) + Ord(DiskPresent[1])
      + Ord(DiskPresent[2]) + Ord(DiskPresent[3])) +
       ' lecteur(s), ramdisk ' + IntStr(RamSizeKb) + ' Ko');
  If Not TryRealRoot Then InstallEmbedded;
  FpuDetect;
  InitFpu;
  T := KernelThread(LongInt(@InitThread));
  If T = Nil Then KPanic('creation de init impossible');
  InitTask := T;
  T^.Pid := 1; T^.Tgid := 1;
  NextPid := 1;
  T^.State := TsRunnable;
  T := KernelThread(LongInt(@BdflushMain));
  If T <> Nil Then
  Begin
    T^.State := TsSleepUn;
    T^.WakeAt := 0;
    T^.State := TsRunnable;
  End;
  If BootQuiet Then LogToVc := False;
  KLog('demarrage du systeme');
  { boucle d'inactivite : la tache 0 }
  While True Do
  Begin
    Schedule;
    asm
      sti
      hlt
      cli
    end;
  End;
  I := 0;
End;

Begin
End.
