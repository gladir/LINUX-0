{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: Programme de test UX3 : langage Pascal (imbrication, tas,
    chaines, ensembles, enregistrements, procedures imbriquees et
    recursives) et appels systeme directs (fork, pipe, waitpid).
}

Program UX3;

Type
  PNoeud = ^TNoeud;
  TNoeud = Record
    V : LongInt;
    Suiv : PNoeud;
  End;

Var
  Racine : PNoeud;
  Fds : Array[0..1] Of LongInt;
  Pid, St, K : LongInt;
  Buf : Array[0..15] Of Char;
  Somme : LongInt;

Procedure Ajoute(V : LongInt);
Var N : PNoeud;
Begin
  GetMem(N, SizeOf(TNoeud));
  N^.V := V;
  N^.Suiv := Racine;
  Racine := N;
End;

Function Profondeur(N : Integer) : Integer;
  Function Aide(K : Integer) : Integer;
  Begin
    If K = 0 Then Aide := 0 Else Aide := 1 + Profondeur(K - 1);
  End;
Begin
  Profondeur := Aide(N);
End;

Procedure Externe(X : Integer);
Var Local : Integer;
  Procedure Interne(Y : Integer);
  Begin
    Local := Local + X * Y;
  End;
Begin
  Local := 0;
  Interne(2);
  Interne(3);
  Somme := Local;
End;

Begin
  Racine := Nil;
  For K := 1 To 100 Do Ajoute(K);
  Somme := 0;
  While Racine <> Nil Do
  Begin
    Somme := Somme + Racine^.V;
    Racine := Racine^.Suiv;
  End;
  WriteLn('somme=', Somme);
  WriteLn('prof=', Profondeur(50));
  Externe(4);
  WriteLn('imbrique=', Somme);
  WriteLn(Copy('Linux-0 en Pascal', 12, 6), '|', UpCase('x'), '|', Length('abc'));
  If SysPipe(Fds[0]) = 0 Then
  Begin
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      Buf[0] := 'o'; Buf[1] := 'k'; Buf[2] := #10;
      SysWrite(Fds[1], Buf, 3);
      SysExit(7);
    End;
    K := SysRead(Fds[0], Buf, 3);
    SysWaitPid(Pid, St, 0);
    WriteLn('enfant: ', Buf[0], Buf[1], ' lus=', K, ' statut=', (St Shr 8) And $FF);
  End;
End.
