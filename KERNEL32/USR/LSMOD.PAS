{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/lsmod, insmod, rmmod : modules du noyau (lsmod :
      /proc/modules ; insmod fichier.ko [param=val...] : init_module(2) ;
      rmmod nom : delete_module(2)).
}

Program LSMOD;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');

Function PS(P : PChar) : String;
Var X : String;
Begin
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  PS := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(UsageW[SysLang]) + Syn + #10);
  SysExit(1);
End;

Procedure Warn(Const What : String);
Begin
  SysPut(2, 'lsmod: ' + What + ': ' + SysErrorText(SysErrno) + #10);
End;

Function BaseOf(Const P : String) : String;
Var K, L : LongInt;
Begin
  L := Length(P);
  While (L > 1) And (P[L] = '/') Do Dec(L);
  K := L;
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  BaseOf := Copy(P, K + 1, L - K);
End;

Function IsDir(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  IsDir := (SysStat(P, St) = 0) And ((St.Mode And $F000) = $4000);
End;

{ ligne de /proc/modules "nom taille usage deps etat adresse" -> format de
  lsmod : nom sur 19 colonnes, taille sur 8, usage, dependants }
Procedure ShowMod(Const L : String);
Var
  F : Array[1..6] Of String;
  K, N, P : LongInt;
  R : String;
Begin
  For K := 1 To 6 Do F[K] := '';
  N := 1;
  For P := 1 To Length(L) Do
    If L[P] = ' ' Then
    Begin
      If (F[N] <> '') And (N < 6) Then Inc(N);
    End
    Else F[N] := F[N] + L[P];
  R := F[1];
  While Length(R) < 19 Do R := R + ' ';
  R := R + ' ';
  For K := 1 To 8 - Length(F[2]) Do R := R + ' ';
  R := R + F[2] + '  ' + F[3];
  If (F[4] <> '') And (F[4] <> '-') Then R := R + ' ' + F[4];
  SysPut(1, R + #10);
End;

Var
  Fd, N, I, Rc : LongInt;
  A, L, Params : String;
  P : ^Byte;
  B : Array[0..16383] Of Byte;
  Mode : LongInt;
  Ofs, Tot : LongInt;
BEGIN
  Mode := 1;
  A := SysArgStr(0);
  If Pos('insmod', A) > 0 Then Mode := 2
  Else If Pos('rmmod', A) > 0 Then Mode := 3;
  Rc := 0;
  If Mode = 1 Then
  Begin
    SysPut(1, 'Module                  Size  Used by' + #10);
    Fd := SysOpen('/proc/modules', O_RDONLY, 0);
    If Fd < 0 Then SysExit(0);
    While SysReadLine(Fd, L) Do ShowMod(L);
    SysClose(Fd);
    SysExit(0);
  End;
  If SysArgCount < 2 Then Usage('insmod file.ko [param=value...] | rmmod name');
  If Mode = 3 Then
  Begin
    For I := 1 To SysArgCount - 1 Do
    Begin
      A := SysArgStr(I);
      If Copy(A, 1, 1) <> '-' Then
        { delete_module(name, flags = O_NONBLOCK) }
        If LnxRes(LnxSys3(129, LnxZ(A), $800, 0)) < 0 Then
        Begin
          Warn(A);
          Rc := 1;
        End;
    End;
    SysExit(Rc);
  End;
  { insmod : lire le fichier entier dans le tas
    (init_module(image, len, params)) }
  Fd := SysOpen(SysArgStr(1), O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    Warn(SysArgStr(1));
    SysExit(1);
  End;
  Tot := SysLSeek(Fd, 0, SEEK_END);
  SysLSeek(Fd, 0, SEEK_SET);
  If Tot <= 0 Then
  Begin
    Warn(SysArgStr(1));
    SysExit(1);
  End;
  Ofs := HeapAlloc(1, 0, Tot + 8);
  N := 0;
  While N < Tot Do
  Begin
    I := LnxSys3(3, Fd, Ofs + N, Tot - N);
    If I <= 0 Then Break;
    N := N + I;
  End;
  SysClose(Fd);
  Params := '';
  For I := 2 To SysArgCount - 1 Do Params := Params + SysArgStr(I) + ' ';
  If LnxRes(LnxSys3(128, Ofs, N, LnxZ(Params))) < 0 Then
  Begin
    Warn(SysArgStr(1));
    SysExit(1);
  End;
END.
