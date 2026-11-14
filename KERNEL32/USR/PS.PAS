{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/ps : liste des processus (lit /proc/N/status et /proc/N/cmdline).
}

Program Ps;

Const
  M : Array[1..1, 1..5] Of PChar = (
    ('ps : /proc inaccessible', 'ps: cannot read /proc', 'ps: /proc nicht lesbar',
     'ps: no se puede leer /proc', 'ps: /proc non leggibile'));
  Hdr : Array[1..5] Of PChar = (
    '  PID  PPID UTIL ET TAILLE COMMANDE', '  PID  PPID USER  S   SIZE COMMAND',
    '  PID  PPID USER  S  GROESSE BEFEHL', '  PID  PPID USER  S TAMANO ORDEN',
    '  PID  PPID UTENTE S DIM COMANDO');

Var D, Ino, Pid, C : LongInt; Name : String; All : Boolean; Uid : LongInt;

Function Msg(Id : LongInt) : String;
Var P : PChar; X : String;
Begin
  P := M[Id, SysLang];
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  Msg := X;
End;

Function Num(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  Num := S;
End;

Function Trim(S : String) : String;
Begin
  While (S <> '') And (S[1] <= ' ') Do Delete(S, 1, 1);
  While (S <> '') And (S[Length(S)] <= ' ') Do Delete(S, Length(S), 1);
  Trim := S;
End;

Function Pad(S : String; N : LongInt) : String;
Begin
  While Length(S) < N Do S := ' ' + S;
  Pad := S;
End;

Function Field(Var L : String; Const K : String) : Boolean;
Begin
  Field := Copy(L, 1, Length(K)) = K;
End;

Procedure Show(Pid : LongInt);
Var Fd, Ppid, U, Sz, N, X : LongInt; L, Nm, St, Cmd, Num, P2 : String;
    Q : TSysPasswd; B : Array[0..255] Of Char; K : LongInt;
Begin
  Fd := SysOpen('/proc/' + Num(Pid) + '/status', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Nm := ''; St := '?'; Ppid := 0; U := 0; Sz := 0;
  While SysReadLine(Fd, L) Do
  Begin
    If Field(L, 'Name:') Then Nm := Trim(Copy(L, 6, 80))
    Else If Field(L, 'State:') Then St := Copy(Trim(Copy(L, 7, 20)), 1, 1)
    Else If Field(L, 'PPid:') Then Val(Trim(Copy(L, 6, 20)), Ppid, X)
    Else If Field(L, 'Uid:') Then Val(Trim(Copy(L, 5, 20)), U, X)
    Else If Field(L, 'VmSize:') Then
    Begin
      P2 := Trim(Copy(L, 8, 20));
      K := Pos(' ', P2);
      If K > 0 Then P2 := Copy(P2, 1, K - 1);
      Val(P2, Sz, X);
    End;
  End;
  SysClose(Fd);
  If (Not All) And (U <> Uid) Then Exit;
  Cmd := '';
  Fd := SysOpen('/proc/' + Num(Pid) + '/cmdline', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    N := SysRead(Fd, B, 255);
    SysClose(Fd);
    For K := 0 To N - 1 Do
      If B[K] = #0 Then Cmd := Cmd + ' ' Else Cmd := Cmd + B[K];
  End;
  If Cmd = '' Then Cmd := '[' + Nm + ']';
  If SysGetPwUid(U, Q) Then Nm := Q.Name Else Str(U, Nm);
  Nm := Copy(Nm + '        ', 1, 8);
  SysPut(1, Pad(Num(Pid), 5) + ' ' + Pad(Num(Ppid), 5) + ' ' + Nm + ' ' + St
         + ' ' + Pad(Num(Sz), 6) + ' ' + Cmd + #10);
End;

BEGIN
  All := False;
  Uid := SysGetUid;
  If (SysArgCount > 1) And ((SysArgStr(1) = '-e') Or (SysArgStr(1) = '-A') Or
     (SysArgStr(1) = 'aux') Or (SysArgStr(1) = '-ef') Or (SysArgStr(1) = 'ax')) Then
    All := True;
  D := SysOpenDir('/proc');
  If D < 0 Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(1);
  End;
  SysPut(1, Hdr[SysLang] + #10);
  While SysReadDir(D, Name, Ino) Do
  Begin
    Val(Name, Pid, C);
    If (C = 0) And (Pid > 0) Then Show(Pid);
  End;
  SysCloseDir(D);
END.
