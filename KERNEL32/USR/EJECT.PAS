{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: eject : ejecte (ou, avec -t, ferme) le plateau d'un lecteur
   de CD-ROM. eject [-t] [-v] [peripherique ...]. Sans peripherique : tous
   les lecteurs usuels (/dev/sr0, /dev/sr1, /dev/hdc, /dev/hdd, /dev/hdb).
   La porte est d'abord deverrouillee (CDROM_LOCKDOOR 0) puis CDROMEJECT
   (ou CDROMCLOSETRAY). Code de sortie : 0 si un lecteur a obeit, 1 sinon.
   Avec -v, le resultat de chaque ioctl est affiche. }

Program Eject;

Const
  CDROMEJECT = $5309;
  CDROMCLOSETRAY = $5319;
  CDROM_LOCKDOOR = $5329;

Var
  Close, Verbose : Boolean;
  Done : LongInt;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Procedure DoOne(Const Dev : String);
Var Fd, R : LongInt;
Begin
  Fd := SysOpen(Dev, O_RDONLY Or $800, 0);
  If Fd < 0 Then
  Begin
    If Verbose Then SysPut(1, Dev + ' : ouverture impossible (' +
                           NumS(SysErrno) + ')' + #10);
    Exit;
  End;
  R := SysIoctlL(Fd, CDROM_LOCKDOOR, 0);
  If Verbose Then SysPut(1, Dev + ' : deverrouillage ' + NumS(R) + #10);
  If Close Then R := SysIoctlL(Fd, CDROMCLOSETRAY, 0)
  Else R := SysIoctlL(Fd, CDROMEJECT, 0);
  If Verbose Then SysPut(1, Dev + ' : ' + NumS(R) + #10);
  If R >= 0 Then Inc(Done);
  SysClose(Fd);
End;

Const
  Defs : Array[0..4] Of String[10] = ('/dev/sr0', '/dev/sr1', '/dev/hdc',
    '/dev/hdd', '/dev/hdb');

Var
  I, N : LongInt;
  A : String;

BEGIN
  Close := False;
  Verbose := False;
  Done := 0;
  N := 0;
  For I := 1 To ParamCount Do
  Begin
    A := ParamStr(I);
    If A = '-t' Then Close := True
    Else If A = '-v' Then Verbose := True
    Else If (A = '-h') Or (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, 'usage : eject [-t] [-v] [peripherique ...]' + #10);
      SysExit(0);
    End
    Else
    Begin
      DoOne(A);
      Inc(N);
    End;
  End;
  If N = 0 Then
    For I := 0 To 4 Do DoOne(Defs[I]);
  If Done > 0 Then SysExit(0) Else SysExit(1);
END.
