{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/mkdir : cree des repertoires (-p : avec les parents,
      -m mode).
}

Program Mkdir;

Const
  M : Array[1..2, 1..5] Of PChar = (
    ('Usage : mkdir [-p] [-m mode] repertoire...',
      'Usage: mkdir [-p] [-m mode] directory...',
     'Aufruf: mkdir [-p] [-m Modus] Verzeichnis...',
       'Uso: mkdir [-p] [-m modo] directorio...',
     'Uso: mkdir [-p] [-m modo] directory...'),
    ('mkdir : impossible de creer ', 'mkdir: cannot create directory ',
     'mkdir: Verzeichnis kann nicht erstellt werden: ',
       'mkdir: no se puede crear el directorio ',
     'mkdir: impossibile creare la directory '));

Var I, Mode, Rc, X, Dirs : LongInt; A : String; Parents : Boolean;

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

Function Make(P : String) : Boolean;
Var K : LongInt;
Begin
  Make := True;
  If Parents Then
  Begin
    For K := 2 To Length(P) Do
      If P[K] = '/' Then SysMkdir(Copy(P, 1, K - 1), Mode);
    If SysMkdir(P, Mode) >= 0 Then Exit;
    If SysErrno = 17 Then Exit;
  End
  Else If SysMkdir(P, Mode) >= 0 Then Exit;
  SysPut(2, Msg(2) + #39 + P + #39 + ' : ' + SysErrorText(SysErrno) + #10);
  Make := False;
End;

BEGIN
  Parents := False;
  Mode := $1FF;
  Dirs := 0;
  Rc := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-p' Then Parents := True
    Else If (A = '-m') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Mode := 0;
      A := SysArgStr(I);
      For X := 1 To Length(A) Do Mode := Mode * 8 + Ord(A[X]) - 48;
    End
    Else If (A = '-h') Or (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, Msg(1) + #10);
      SysExit(0);
    End
    Else
    Begin
      Inc(Dirs);
      If Not Make(A) Then Rc := 1;
    End;
    Inc(I);
  End;
  If Dirs = 0 Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(1);
  End;
  SysExit(Rc);
END.
