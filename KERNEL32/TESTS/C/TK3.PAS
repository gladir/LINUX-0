{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3K)
  @description: Noyau de test TK3 : couverture du langage (types, tableaux,
    enregistrements, chaines, ensembles, pointeurs, types procedures,
    procedures imbriquees, case, boucles, with, GetMem/New).
}

Program TK3;

{ Compilation : LPC -3K TK3.PAS ; sortie attendue : TK3.OUT }

Const
  Com1 = $3F8;
  Max  = 10;
  Nom  = 'LINUX';

Type
  TOctets = Array[0..15] Of Byte;
  TPoint = Record
    X, Y : LongInt;
  End;
  PNoeud = ^TNoeud;
  TNoeud = Record
    Valeur : LongInt;
    Suivant : PNoeud;
  End;
  TCouleur = (Rouge, Vert, Bleu);
  TEns = Set Of 0..31;
  TFonc = Function(A, B : LongInt) : LongInt;
  TOps = Record
    Calcul : TFonc;
    Code   : Word;
  End;

Var
  BootMem : Array[0..12287] Of LongInt;
  Tas     : Array[0..16383] Of LongInt;
  TasPtr  : LongInt;
  Tab     : Array[1..Max] Of LongInt;
  Oct     : TOctets;
  P1, P2  : TPoint;
  Liste   : PNoeud;
  Ens     : TEns;
  Ops     : TOps;
  Mot     : Word;
  Entier  : Integer;
  Grand   : LongInt;
  Couleur : TCouleur;
  Texte   : String;
  Total   : LongInt;

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

{ Couche d'allocation fournie au runtime (GetMem, New...) }
Function HeapAlloc(H, Flags, Taille : LongInt) : LongInt;
Begin
  HeapAlloc := LongInt(@Tas) + TasPtr;
  TasPtr := TasPtr + ((Taille + 15) And LongInt($FFFFFFF0));
End;

Function HeapFree(H, Flags, Ptr : LongInt) : LongInt;
Begin
  HeapFree := 1;
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

Procedure Nombre(V : LongInt);
Var Buf : String;
Begin
  Str(V, Buf);
  Ecrire(Buf);
End;

Procedure Ligne;
Begin
  Serie(13); Serie(10);
End;

Function Somme(A, B : LongInt) : LongInt;
Begin
  Somme := A + B;
End;

Function Fact(N : LongInt) : LongInt;
Begin
  If N <= 1 Then Fact := 1 Else Fact := N * Fact(N - 1);
End;

Procedure Echange(Var A, B : LongInt);
Var T : LongInt;
Begin
  T := A; A := B; B := T;
End;

Procedure Imbrique(N : LongInt);
  Procedure Interne(K : LongInt);
  Begin
    Total := Total + K * N;
  End;
Begin
  Interne(2);
  Interne(3);
End;

Procedure Ajoute(V : LongInt);
Var N : PNoeud;
Begin
  New(N);
  N^.Valeur := V;
  N^.Suivant := Liste;
  Liste := N;
End;

Var
  I, J : LongInt;
  C    : Char;
  N    : PNoeud;
  Mem2 : Pointer;

Begin
  TasPtr := 0;
  Ecrire('tableaux:');
  For I := 1 To Max Do Tab[I] := I * I;
  Total := 0;
  For I := 1 To Max Do Total := Total + Tab[I];
  Nombre(Total); Ligne;
  Ecrire('records:');
  P1.X := 3; P1.Y := 4;
  P2 := P1;
  P2.X := P2.X + P1.Y;
  Nombre(P2.X * 100 + P2.Y); Ligne;
  Ecrire('with:');
  With P1 Do Begin X := 10; Y := 20 End;
  Nombre(P1.X + P1.Y); Ligne;
  Ecrire('chaines:');
  Texte := Nom + '-' + Copy('0123456789', 3, 4);
  Ecrire(Texte); Serie(Ord(' ')); Nombre(Length(Texte)); Serie(Ord(' '));
  Nombre(Pos('-', Texte)); Ligne;
  Ecrire('case:');
  For I := 0 To 6 Do
    Case I Of
      0 : Serie(Ord('a'));
      1, 2 : Serie(Ord('b'));
      3..5 : Serie(Ord('c'));
    Else Serie(Ord('z'));
    End;
  Ligne;
  Ecrire('boucles:');
  I := 0; J := 0;
  While I < 5 Do Begin J := J + I; Inc(I) End;
  Repeat J := J + 100; Dec(I) Until I <= 2;
  For I := 10 DownTo 8 Do J := J + I;
  Nombre(J); Ligne;
  Ecrire('ensembles:');
  Ens := [1, 5, 9] + [31];
  If 5 In Ens Then Serie(Ord('Y')) Else Serie(Ord('N'));
  If 6 In Ens Then Serie(Ord('Y')) Else Serie(Ord('N'));
  If 31 In Ens Then Serie(Ord('Y')) Else Serie(Ord('N'));
  Ligne;
  Ecrire('pointeurs:');
  Liste := Nil;
  For I := 1 To 4 Do Ajoute(I * 11);
  N := Liste; J := 0;
  While N <> Nil Do Begin J := J * 10 + N^.Valeur Div 11; N := N^.Suivant End;
  Nombre(J); Ligne;
  GetMem(Mem2, 64);
  Ecrire('getmem:');
  If Mem2 <> Nil Then Ecrire('ok') Else Ecrire('nul');
  Ligne;
  Ecrire('proc:');
  Ops.Calcul := Somme;
  Ops.Code := 7;
  Nombre(Ops.Calcul(20, 22)); Serie(Ord(' ')); Nombre(Fact(10)); Ligne;
  Ecrire('var:');
  I := 5; J := 9;
  Echange(I, J);
  Nombre(I * 10 + J); Ligne;
  Ecrire('imbrique:');
  Total := 0;
  Imbrique(10);
  Nombre(Total); Ligne;
  Ecrire('types:');
  Mot := 65535; Mot := Mot + 2;
  Entier := 32767; Entier := Entier + 1;
  Grand := 2147483647; Grand := Grand + 1;
  Nombre(Mot); Serie(Ord(' ')); Nombre(Entier); Serie(Ord(' ')); Nombre(Grand); Ligne;
  Ecrire('enum:');
  Couleur := Vert;
  Nombre(Ord(Couleur)); Couleur := Succ(Couleur); Nombre(Ord(Couleur)); Ligne;
  Ecrire('octets:');
  FillChar(Oct, SizeOf(Oct), 7);
  Oct[3] := 200;
  Nombre(Oct[2] + Oct[3]); Serie(Ord(' ')); Nombre(SizeOf(Oct)); Ligne;
  Ecrire('shift:');
  Nombre((1 Shl 20) Or (LongInt($80000000) Shr 31)); Serie(Ord(' '));
  Nombre(-7 Div 2); Serie(Ord(' ')); Nombre(-7 Mod 3); Ligne;
  Ecrire('fin'); Ligne;
  Port[$F4] := 0;
  asm
    cli
    hlt
  end;
End.
