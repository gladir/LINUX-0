{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/su : change d identite (su [-] [utilisateur] [-c commande]) ; root est dispense de mot de passe.
}

Program SU;

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
  SysPut(2, 'su: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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

Function Field(L : String; N : LongInt) : String;
Var K : LongInt;
Begin
  For K := 2 To N Do
  Begin
    If Pos(':', L) = 0 Then
    Begin
      Field := '';
      Exit;
    End;
    Delete(L, 1, Pos(':', L));
  End;
  If Pos(':', L) > 0 Then L := Copy(L, 1, Pos(':', L) - 1);
  Field := L;
End;

Function ShadowOf(Const N : String; Var H : String) : Boolean;
Var Fd : LongInt; L : String;
Begin
  ShadowOf := False;
  Fd := SysOpen('/etc/shadow', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
    If Field(L, 1) = N Then
    Begin
      H := Field(L, 2);
      ShadowOf := True;
      Break;
    End;
  SysClose(Fd);
End;

Function ReadPass(Const Prompt : String) : String;
Var T, Old : TSysTermios; S : String; C : Char; N : LongInt; Tty : Boolean;
Begin
  SysPut(2, Prompt);
  Tty := SysTcGetAttr(0, Old) = 0;
  If Tty Then
  Begin
    T := Old;
    T.LFlag := T.LFlag And Not TTY_ECHO;
    SysTcSetAttr(0, 1, T);
  End;
  S := '';
  Repeat
    N := SysRead(0, C, 1);
    If (N <= 0) Or (C = #10) Then Break;
    If Length(S) < 64 Then S := S + C;
  Until False;
  If Tty Then SysTcSetAttr(0, 1, Old);
  C := #10;
  SysWrite(2, C, 1);
  ReadPass := S;
End;

Var
  Name, A, Cmd, H, Pw : String;
  Login1 : Boolean;
  I : LongInt;
  P : TSysPasswd;

BEGIN
  Name := 'root';
  Login1 := False;
  Cmd := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-') Or (A = '-l') Then Login1 := True
    Else If (A = '-c') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Cmd := SysArgStr(I);
    End
    Else Name := A;
    Inc(I);
  End;
  If Not SysGetPwNam(Name, P) Then
  Begin
    SysPut(2, 'su: user ' + Name + ' does not exist' + #10);
    SysExit(1);
  End;
  If SysGetUid <> 0 Then
  Begin
    If Not ShadowOf(Name, H) Then H := '*';
    If H <> '' Then
    Begin
      Pw := ReadPass('Password: ');
      If (H = '*') Or (H = '!') Or (SysCrypt(Pw, Copy(H, 1, 2)) <> H) Then
      Begin
        SysPut(2, 'su: Authentication failure' + #10);
        SysExit(1);
      End;
    End;
  End;
  If (SysSetGid(P.Gid) < 0) Or (SysSetUid(P.Uid) < 0) Then
  Begin
    Warn('setuid');
    SysExit(1);
  End;
  SysArgReset;
  If Login1 Then SysArgAdd('-' + BaseOf(P.Shell)) Else SysArgAdd(BaseOf(P.Shell));
  If Cmd <> '' Then
  Begin
    SysArgAdd('-c');
    SysArgAdd(Cmd);
  End;
  If Login1 Then
  Begin
    SysEnvAdd('HOME=' + P.Home);
    SysEnvAdd('SHELL=' + P.Shell);
    SysEnvAdd('USER=' + Name);
    SysEnvAdd('LOGNAME=' + Name);
    SysEnvAdd('PATH=/sbin:/bin:/usr/sbin:/usr/bin');
    SysChdir(P.Home);
  End
  Else SysEnvInherit;
  SysArgExec(P.Shell);
  Warn(P.Shell);
  SysExit(1);
END.
