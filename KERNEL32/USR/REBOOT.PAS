{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/reboot : redemarre le systeme (signal SIGTERM a init, ou directement avec -f).
}

Program REBOOT;

Const
  M : Array[1..2, 1..5] Of PChar = (
    ('Usage : reboot [-f]', 'Usage: reboot [-f]', 'Aufruf: reboot [-f]', 'Uso: reboot [-f]',
     'Uso: reboot [-f]'),
    ('-f : sans prevenir init (synchronise puis agit directement)',
     '-f: do not signal init (sync, then act directly)',
     '-f: init nicht benachrichtigen (sync, dann direkt ausfuehren)',
     '-f: sin avisar a init (sincroniza y actua directamente)',
     '-f: senza avvisare init (sincronizza e agisce subito)'));

Var A : String; I : LongInt; Force : Boolean;

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

BEGIN
  Force := False;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If A = '-f' Then Force := True
    Else
    Begin
      SysPut(2, Msg(1) + #10 + Msg(2) + #10);
      SysExit(1);
    End;
  End;
  If Force Then
  Begin
    SysSync;
    If SysReboot(LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, LINUX_REBOOT_RESTART) < 0 Then;
  End
  Else If SysKill(1, SIGTERM) < 0 Then
  Begin
    SysPut(2, 'reboot: ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
END.
