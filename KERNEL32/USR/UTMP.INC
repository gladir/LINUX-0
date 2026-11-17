{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: enregistrements utmp/wtmp Linux i386 (struct utmp, 384
      octets) partages par login, init et who/w/last par la directive
      include de UTMP.INC. Fichiers : /var/run/utmp et /var/log/wtmp.
}

Const
  UtSize = 384;
  UtBoot = 2;
  UtInit = 5;
  UtLogin = 6;
  UtUser = 7;
  UtDead = 8;

Type
  TUtmp = Record
    Typ : Word;
    Pad : Word;
    Pid : LongInt;
    Line : Array[0..31] Of Char;
    Id : Array[0..3] Of Char;
    User : Array[0..31] Of Char;
    Host : Array[0..255] Of Char;
    Exit1 : LongInt;
    Session : LongInt;
    Sec, USec : LongInt;
    Addr : Array[0..3] Of LongInt;
    Unused : Array[0..19] Of Char;
  End;

Procedure UtFill(Var U : TUtmp; Typ, Pid : LongInt;
                 Const Line, User, Host : String);
Var K : LongInt;
Begin
  FillChar(U, UtSize, 0);
  U.Typ := Typ;
  U.Pid := Pid;
  For K := 1 To Length(Line) Do
    If K <= 31 Then U.Line[K - 1] := Line[K];
  For K := 1 To Length(User) Do
    If K <= 31 Then U.User[K - 1] := User[K];
  For K := 1 To Length(Host) Do
    If K <= 255 Then U.Host[K - 1] := Host[K];
  For K := 1 To 4 Do
    If Length(Line) - 4 + K >= 1 Then U.Id[K - 1] := Line[Length(Line) - 4 + K];
  U.Sec := SysTime;
End;

{ ajoute un enregistrement a la fin de Fn }
Procedure UtAppend(Const Fn : String; Var U : TUtmp);
Var Fd : LongInt;
Begin
  Fd := SysOpen(Fn, $441, 420);
  If Fd < 0 Then Exit;
  SysWrite(Fd, U, UtSize);
  SysClose(Fd);
End;

{ utmp : remplace l'enregistrement de la meme ligne ou ajoute }
Procedure UtPutUtmp(Var U : TUtmp);
Var Fd, N, Pos0 : LongInt; T : TUtmp; Found : Boolean; L1, L2 : String;
    K : LongInt;
Begin
  Fd := SysOpen('/var/run/utmp', 2, 0);
  If Fd < 0 Then Fd := SysOpen('/var/run/utmp', $42, 420);
  If Fd < 0 Then Exit;
  Pos0 := 0;
  Found := False;
  While SysRead(Fd, T, UtSize) = UtSize Do
  Begin
    If (T.Typ = UtUser) Or (T.Typ = UtDead) Or (T.Typ = UtLogin) Or
       (T.Typ = UtInit) Then
    Begin
      Found := True;
      For K := 0 To 31 Do
        If T.Line[K] <> U.Line[K] Then Found := False;
      If (U.Line[0] = #0) Then Found := False;
      If Found Then Break;
    End;
    Pos0 := Pos0 + UtSize;
  End;
  If Found Then SysLSeek(Fd, Pos0, 0) Else SysLSeek(Fd, 0, 2);
  SysWrite(Fd, U, UtSize);
  SysClose(Fd);
End;

{ connexion : utmp + wtmp }
Procedure UtLogon(Pid : LongInt; Const Line, User, Host : String);
Var U : TUtmp;
Begin
  UtFill(U, UtUser, Pid, Line, User, Host);
  UtPutUtmp(U);
  UtAppend('/var/log/wtmp', U);
End;

{ deconnexion du processus Pid : DEAD_PROCESS dans utmp et wtmp }
Procedure UtLogoff(Pid : LongInt);
Var Fd, Pos0 : LongInt; T, D : TUtmp;
Begin
  Fd := SysOpen('/var/run/utmp', 2, 0);
  If Fd < 0 Then Exit;
  Pos0 := 0;
  While SysRead(Fd, T, UtSize) = UtSize Do
  Begin
    If (T.Typ = UtUser) And (T.Pid = Pid) Then
    Begin
      D := T;
      FillChar(D.User, 32, 0);
      FillChar(D.Host, 256, 0);
      D.Typ := UtDead;
      D.Sec := SysTime;
      SysLSeek(Fd, Pos0, 0);
      SysWrite(Fd, D, UtSize);
      UtAppend('/var/log/wtmp', D);
      Break;
    End;
    Pos0 := Pos0 + UtSize;
  End;
  SysClose(Fd);
End;

Function UtLineS(Const U : TUtmp) : String;
Var K : LongInt; R : String;
Begin
  R := '';
  K := 0;
  While (K < 32) And (U.Line[K] <> #0) Do
  Begin
    R := R + U.Line[K];
    Inc(K);
  End;
  UtLineS := R;
End;

Function UtUserS(Const U : TUtmp) : String;
Var K : LongInt; R : String;
Begin
  R := '';
  K := 0;
  While (K < 32) And (U.User[K] <> #0) Do
  Begin
    R := R + U.User[K];
    Inc(K);
  End;
  UtUserS := R;
End;

Function UtHostS(Const U : TUtmp) : String;
Var K : LongInt; R : String;
Begin
  R := '';
  K := 0;
  While (K < 100) And (U.Host[K] <> #0) Do
  Begin
    R := R + U.Host[K];
    Inc(K);
  End;
  UtHostS := R;
End;
