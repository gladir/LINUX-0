{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/id : identite (uid, gid,
      groupes) de l'utilisateur courant ou du compte donne.
}

Program Id;

Const
  M : Array[1..2, 1..5] Of PChar = (
    ('id : utilisateur inconnu : ', 'id: unknown user: ',
      'id: unbekannter Benutzer: ',
     'id: usuario desconocido: ', 'id: utente sconosciuto: '),
    ('Usage : id [nom]', 'Usage: id [name]', 'Aufruf: id [Name]',
      'Uso: id [nombre]',
     'Uso: id [nome]'));

Var U, G : LongInt; P : TSysPasswd; S : String;

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

Function NameOf(U : LongInt) : String;
Var Q : TSysPasswd;
Begin
  If SysGetPwUid(U, Q) Then NameOf := Q.Name Else NameOf := '';
End;

Function GName(G : LongInt) : String;
Begin
  GName := SysGroupName(G);
End;

BEGIN
  If SysArgCount > 1 Then
  Begin
    S := SysArgStr(1);
    If (S = '-h') Or (S = '--help') Or (S = '/?') Then
    Begin
      SysPut(1, Msg(2) + #10);
      SysExit(0);
    End;
    If Not SysGetPwNam(S, P) Then
    Begin
      SysPut(2, Msg(1) + S + #10);
      SysExit(1);
    End;
    U := P.Uid;
    G := P.Gid;
  End
  Else
  Begin
    U := SysGetUid;
    G := SysGetGid;
  End;
  S := 'uid=' + Num(U) + '(' + NameOf(U) + ') gid=' + Num(G) + '(' + GName(G)
    + ')';
  SysPut(1, S + #10);
END.
