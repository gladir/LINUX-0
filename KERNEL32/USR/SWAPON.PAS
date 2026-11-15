{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/swapon, /sbin/swapoff : active ou desactive une zone
      d echange (swapon [-s] dev ; swapoff dev).
}

Program SWAPON;

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

Var
  Off, Show : Boolean;
  I, R, Rc : LongInt;
  A : String;
  Fd : LongInt;
  L : String;
BEGIN
  Off := Pos('swapoff', SysArgStr(0)) > 0;
  Show := False;
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
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If Off Then R := LnxRes(LnxSys3(115, LnxZ(A), 0, 0))
    Else R := LnxRes(LnxSys3(87, LnxZ(A), 0, 0));
    If R < 0 Then
    Begin
      Warn(A);
      Rc := 1;
    End;
  End;
  SysExit(Rc);
END.
