{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/rm : supprime des fichiers (-r -R recursif, -f sans erreur, -i demande, -v bavard).
}

Program Rm;

Const
  M : Array[1..3, 1..5] Of PChar = (
    ('Usage : rm [-rfiv] fichier...', 'Usage: rm [-rfiv] file...', 'Aufruf: rm [-rfiv] Datei...',
     'Uso: rm [-rfiv] fichero...', 'Uso: rm [-rfiv] file...'),
    ('rm : impossible de supprimer ', 'rm: cannot remove ', 'rm: kann nicht entfernt werden: ',
     'rm: no se puede eliminar ', 'rm: impossibile rimuovere '),
    ('supprimer ', 'remove ', 'entfernen ', 'eliminar ', 'rimuovere '));

Var I, Rc, N, Cnt : LongInt; A : String; Rec, Force, Inter, Verb, NoOpt : Boolean;

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

Function Ask(Const P : String) : Boolean;
Var C : Char; R : Char;
Begin
  SysPut(2, Msg(3) + P + '? ');
  R := 'n';
  If SysRead(0, C, 1) = 1 Then
  Begin
    R := C;
    While (C <> #10) And (SysRead(0, C, 1) = 1) Do;
  End;
  Ask := UpCase(R) In ['Y', 'O', 'J', 'S'];
End;

Procedure Err(Const P : String; E : LongInt);
Begin
  SysPut(2, Msg(2) + #39 + P + #39 + ' : ' + SysErrorText(E) + #10);
  Rc := 1;
End;

Procedure Remove(Const P : String);
Var St : TSysStat; D, Ino, K, C : LongInt; Nm : String; L : Array[0..199] Of String;
Begin
  If SysLStat(P, St) < 0 Then
  Begin
    If Not Force Then Err(P, SysErrno);
    Exit;
  End;
  If (St.Mode And S_IFMT) = S_IFDIR Then
  Begin
    If Not Rec Then
    Begin
      Err(P, 21);
      Exit;
    End;
    D := SysOpenDir(P);
    If D >= 0 Then
    Begin
      C := 0;
      While SysReadDir(D, Nm, Ino) Do
        If (Nm <> '.') And (Nm <> '..') And (C < 200) Then
        Begin
          L[C] := Nm;
          Inc(C);
        End;
      SysCloseDir(D);
      For K := 0 To C - 1 Do Remove(P + '/' + L[K]);
    End;
    If Inter And Not Ask(P) Then Exit;
    If SysRmdir(P) < 0 Then Err(P, SysErrno)
    Else If Verb Then SysPut(1, P + #10);
    Exit;
  End;
  If Inter And Not Ask(P) Then Exit;
  If SysUnlink(P) < 0 Then
  Begin
    If Not Force Then Err(P, SysErrno);
  End
  Else If Verb Then SysPut(1, P + #10);
End;

BEGIN
  Rec := False; Force := False; Inter := False; Verb := False;
  NoOpt := False;
  Rc := 0;
  Cnt := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (Not NoOpt) And (A = '--') Then NoOpt := True
    Else If (Not NoOpt) And (A = '--help') Then
    Begin
      SysPut(1, Msg(1) + #10);
      SysExit(0);
    End
    Else If (Not NoOpt) And (Length(A) > 1) And (A[1] = '-') Then
    Begin
      For N := 2 To Length(A) Do
        Case A[N] Of
          'r', 'R' : Rec := True;
          'f' : Force := True;
          'i' : Inter := True;
          'v' : Verb := True;
        End;
    End
    Else
    Begin
      Inc(Cnt);
      Remove(A);
    End;
  End;
  If (Cnt = 0) And Not Force Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(1);
  End;
  SysExit(Rc);
END.
