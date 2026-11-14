{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/mount : monte un systeme de fichiers (mount [-t type]
      [-o options] source cible) ; sans argument, affiche /proc/mounts.
}

Program Mount;

Const
  M : Array[1..2, 1..5] Of PChar = (
    ('Usage : mount [-t type] [-o options] source cible',
      'Usage: mount [-t type] [-o options] source target',
     'Aufruf: mount [-t Typ] [-o Optionen] Quelle Ziel',
       'Uso: mount [-t tipo] [-o opciones] origen destino',
     'Uso: mount [-t tipo] [-o opzioni] origine destinazione'),
    ('mount : ', 'mount: ', 'mount: ', 'mount: ', 'mount: '));

Var I, Fl, Cnt, N : LongInt; A, Typ, Opt, Src,
  Dst : String; B : Array[0..255] Of Char;

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
  Typ := ''; Opt := ''; Src := ''; Dst := ''; Cnt := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-t') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Typ := SysArgStr(I);
    End
    Else If (A = '-o') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Opt := SysArgStr(I);
    End
    Else If A = '-r' Then Opt := Opt + ',ro'
    Else If (A = '-h') Or (A = '--help') Then
    Begin
      SysPut(1, Msg(1) + #10);
      SysExit(0);
    End
    Else
    Begin
      Inc(Cnt);
      If Cnt = 1 Then Src := A Else Dst := A;
    End;
    Inc(I);
  End;
  If Cnt = 0 Then
  Begin
    I := SysOpen('/proc/mounts', O_RDONLY, 0);
    If I >= 0 Then
    Begin
      Repeat
        N := SysRead(I, B, 256);
        If N > 0 Then SysWrite(1, B, N);
      Until N <= 0;
    End;
    SysExit(0);
  End;
  If Cnt = 1 Then
  Begin
    Dst := Src;
    Src := 'none';
  End;
  Fl := 0;
  If Pos('remount', Opt) > 0 Then Fl := Fl Or MS_REMOUNT;
  If Pos('ro', Opt) > 0 Then Fl := Fl Or MS_RDONLY;
  If Typ = '' Then Typ := 'ext2';
  If SysMount(Src, Dst, Typ, Fl) < 0 Then
  Begin
    SysPut(2, Msg(2) + Dst + ' : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
END.
