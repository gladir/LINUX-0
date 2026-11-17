{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/swapon, /sbin/swapoff : active ou desactive une zone
      d echange (swapon [-s] dev ; swapoff dev).
}

Program SWAPON;

{$I FSPROBE.INC}

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
  SysPut(2, 'swapon: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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

Function Field(Const S : String; N : LongInt) : String;
Var K, F, A : LongInt;
Begin
  F := 0;
  K := 1;
  Field := '';
  While K <= Length(S) Do
  Begin
    While (K <= Length(S)) And (S[K] In [' ', #9]) Do Inc(K);
    If K > Length(S) Then Break;
    A := K;
    While (K <= Length(S)) And Not (S[K] In [' ', #9]) Do Inc(K);
    Inc(F);
    If F = N Then
    Begin
      Field := Copy(S, A, K - A);
      Exit;
    End;
  End;
End;

{ nom de peripherique d'apres UUID=... ou LABEL=... }
Function ByTag(Const Spec : String) : String;
Var F : LongInt; L, Nm, Typ, Lbl, Uuid : String;
Begin
  ByTag := Spec;
  If (Copy(Spec, 1, 5) <> 'UUID=') And (Copy(Spec, 1, 6) <> 'LABEL=') Then
    Exit;
  F := SysOpen('/proc/partitions', O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    Nm := Field(L, 4);
    If (Nm = '') Or (Nm = 'name') Then Continue;
    Probe('/dev/' + Nm, Typ, Lbl, Uuid);
    If (Copy(Spec, 1, 5) = 'UUID=') And (Uuid = Copy(Spec, 6, 80)) Then
      ByTag := '/dev/' + Nm;
    If (Copy(Spec, 1, 6) = 'LABEL=') And (Lbl = Copy(Spec, 7, 80)) Then
      ByTag := '/dev/' + Nm;
  End;
  SysClose(F);
End;

Function Active(Const Dev : String) : Boolean;
Var F : LongInt; L : String;
Begin
  Active := False;
  F := SysOpen('/proc/swaps', O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
    If Field(L, 1) = Dev Then Active := True;
  SysClose(F);
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := 0;
  ToNum := V;
End;

Function OptPrio(Const O : String) : LongInt;
Var K : LongInt;
Begin
  OptPrio := -1;
  K := Pos('pri=', O);
  If K > 0 Then OptPrio := ToNum(Copy(O, K + 4, 6));
End;

Var
  Off, Show, All, Verb : Boolean;
  I, R, Rc, Prio, Fl : LongInt;
  A, Dv : String;
  Fd : LongInt;
  L : String;
BEGIN
  Off := Pos('swapoff', SysArgStr(0)) > 0;
  Show := False;
  All := False;
  Verb := False;
  Prio := -1;
  Rc := 0;
  If (SysArgCount > 1) And ((SysArgStr(1) = '-s') Or
     (SysArgStr(1) = '--summary')) Then
    Show := True;
  If Show Or (SysArgCount < 2) Then
  Begin
    Fd := SysOpen('/proc/swaps', O_RDONLY, 0);
    If Fd < 0 Then
    Begin
      Warn('/proc/swaps');
      SysExit(1);
    End;
    While SysReadLine(Fd, L) Do SysPut(1, L + #10);
    SysClose(Fd);
    SysExit(0);
  End;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-a') Or (A = '--all') Then All := True
    Else If (A = '-v') Or (A = '--verbose') Then Verb := True
    Else If (A = '-p') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Prio := ToNum(SysArgStr(I));
    End
    Else If (A = '-d') Or (A = '-e') Or (A = '-f') Then
    Else
    Begin
      Dv := ByTag(A);
      If Off Then R := LnxRes(LnxSys3(115, LnxZ(Dv), 0, 0))
      Else
      Begin
        Fl := 0;
        If Prio >= 0 Then Fl := $8000 Or (Prio And $7FFF);
        R := LnxRes(LnxSys3(87, LnxZ(Dv), Fl, 0));
      End;
      If R < 0 Then
      Begin
        Warn(A);
        Rc := 1;
      End
      Else If Verb Then SysPut(1, 'swapon: ' + Dv + #10);
    End;
    Inc(I);
  End;
  If All Then
  Begin
    { /etc/fstab : entrees de type swap (sauf noauto), ou, pour swapoff -a,
      tout ce qui est actif }
    If Off Then
    Begin
      Fd := SysOpen('/proc/swaps', O_RDONLY, 0);
      If Fd >= 0 Then
      Begin
        While SysReadLine(Fd, L) Do
        Begin
          Dv := Field(L, 1);
          If (Dv = '') Or (Dv = 'Filename') Then Continue;
          If LnxSys3(115, LnxZ(Dv), 0, 0) < 0 Then Rc := 1;
        End;
        SysClose(Fd);
      End;
      SysExit(Rc);
    End;
    Fd := SysOpen('/etc/fstab', O_RDONLY, 0);
    If Fd >= 0 Then
    Begin
      While SysReadLine(Fd, L) Do
      Begin
        If (Field(L, 1) = '') Or (Field(L, 1)[1] = '#') Then Continue;
        If Field(L, 3) <> 'swap' Then Continue;
        If Pos('noauto', Field(L, 4)) > 0 Then Continue;
        Dv := ByTag(Field(L, 1));
        If Active(Dv) Then Continue;
        Fl := 0;
        R := OptPrio(Field(L, 4));
        If R >= 0 Then Fl := $8000 Or (R And $7FFF);
        If LnxRes(LnxSys3(87, LnxZ(Dv), Fl, 0)) < 0 Then
        Begin
          Warn(Dv);
          Rc := 1;
        End
        Else If Verb Then SysPut(1, 'swapon: ' + Dv + #10);
      End;
      SysClose(Fd);
    End;
  End;
  SysExit(Rc);
END.
