{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/rmdir : supprime des repertoires vides (-p : avec les parents).
}

Program Rmdir;

Const
  M : Array[1..2, 1..5] Of PChar = (
    ('Usage : rmdir [-p] repertoire...', 'Usage: rmdir [-p] directory...',
     'Aufruf: rmdir [-p] Verzeichnis...', 'Uso: rmdir [-p] directorio...',
     'Uso: rmdir [-p] directory...'),
    ('rmdir : impossible de supprimer ', 'rmdir: failed to remove ',
     'rmdir: kann nicht entfernt werden: ', 'rmdir: no se puede eliminar ',
     'rmdir: impossibile rimuovere '));

Var I, Rc, N, K : LongInt; A : String; Parents : Boolean;

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

BEGIN
  Parents := False;
  Rc := 0;
  N := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If A = '-p' Then Parents := True
    Else If (A = '-h') Or (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, Msg(1) + #10);
      SysExit(0);
    End
    Else
    Begin
      Inc(N);
      While A <> '' Do
      Begin
        If SysRmdir(A) < 0 Then
        Begin
          SysPut(2, Msg(2) + #39 + A + #39 + ' : ' + SysErrorText(SysErrno) + #10);
          Rc := 1;
          Break;
        End;
        If Not Parents Then Break;
        K := Length(A);
        While (K > 0) And (A[K] <> '/') Do Dec(K);
        If K <= 1 Then Break;
        A := Copy(A, 1, K - 1);
      End;
    End;
  End;
  If N = 0 Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(1);
  End;
  SysExit(Rc);
END.
