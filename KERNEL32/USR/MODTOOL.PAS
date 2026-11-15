{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: modinfo, modprobe, depmod (nom lu dans argv[0]) pour les
      modules .ko du noyau (lpc -3M). modinfo [-F champ] module|fichier.ko :
      section .modinfo ; modprobe [-r] module [param=val...] : cherche
      /lib/modules/NOM.ko et appelle insmod (rmmod avec -r) ; depmod : ecrit
      /lib/modules/modules.dep.
}

Program MODTOOL;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');

Type
  TB40 = Array[0..39] Of Byte;

Var
  Prog : String;

Function PS(Q : PChar) : String;
Var X : String;
Begin
  X := '';
  While Q^ <> #0 Do
  Begin
    X := X + Q^;
    Inc(Q);
  End;
  PS := X;
End;

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(UsageW[SysLang]) + Syn + #10);
  SysExit(2);
End;

Function ModPath(Const N : String) : String;
Var P : String;
Begin
  If (Pos('/', N) > 0) Or (Pos('.ko', N) > 0) Then
  Begin
    ModPath := N;
    Exit;
  End;
  P := '/lib/modules/' + N + '.ko';
  If SysAccess(P, 0) = 0 Then
  Begin
    ModPath := P;
    Exit;
  End;
  ModPath := '/lib/modules/' + N + '.ko';
End;

Function Exe(Const Path : String; A1, A2 : String; Par : Boolean) : LongInt;
Var Pid, St, I : LongInt;
Begin
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd(Path);
    SysArgAdd(A1);
    If A2 <> '' Then SysArgAdd(A2);
    If Par Then
      For I := 3 To SysArgCount - 1 Do SysArgAdd(SysArgStr(I));
    SysArgExec(Path);
    SysExit(127);
  End;
  St := 0;
  SysWaitPid(Pid, St, 0);
  If SysWIfExited(St) Then Exe := SysWExitStatus(St) Else Exe := 1;
End;

Function L4(Var B : TB40; O : LongInt) : LongInt;
Begin
  L4 := B[O] + B[O + 1] * 256 + B[O + 2] * 65536 + B[O + 3] * 16777216;
End;

Procedure DoModprobe;
Var I, K : LongInt; Remove : Boolean; A, Name : String;
Begin
  Remove := False;
  Name := '';
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (A = '-r') Or (A = '--remove') Then Remove := True
    Else If (Length(A) > 0) And (A[1] = '-') Then
    Else If Name = '' Then Name := A;
  End;
  If Name = '' Then Usage('modprobe [-r] module [param=val ...]');
  If Remove Then
  Begin
    K := Pos('.', Name);
    If K > 0 Then Name := Copy(Name, 1, K - 1);
    SysExit(Exe('/sbin/rmmod', Name, '', False));
  End;
  SysExit(Exe('/sbin/insmod', ModPath(Name), '', False));
End;

{ section .modinfo d'un fichier ELF32 : "cle=valeur" separes par des NUL }
Procedure DoModinfo;
Var
  Fd, K, N, I, J, ShOff, ShNum, ShStr, StrOff, Sz, Off, Fld : LongInt;
  H : Array[0..63] Of Byte;
  Sh : TB40;
  Buf : Array[0..4095] Of Byte;
  A, Path, Want, Nm, Line : String;
  Found : Boolean;

Begin
  Want := '';
  Path := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-F' Then
    Begin
      Inc(I);
      Want := SysArgStr(I);
    End
    Else If Copy(A, 1, 2) = '-F' Then Want := Copy(A, 3, 40)
    Else If Path = '' Then Path := A;
    Inc(I);
  End;
  If Path = '' Then Usage('modinfo [-F champ] module|fichier.ko');
  Path := ModPath(Path);
  Fd := SysOpen(Path, 0, 0);
  If Fd < 0 Then
  Begin
    SysPut(2, 'modinfo: ' + Path + ' : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  If (SysRead(Fd, H, 52) <> 52) Or (H[0] <> 127) Or (H[1] <> 69) Then
  Begin
    SysPut(2, 'modinfo: ' + Path + ' : pas un fichier ELF' + #10);
    SysExit(1);
  End;
  ShOff := H[32] + H[33] * 256 + H[34] * 65536;
  ShNum := H[48] + H[49] * 256;
  ShStr := H[50] + H[51] * 256;
  { table des noms de sections }
  SysLSeek(Fd, ShOff + ShStr * 40, 0);
  SysRead(Fd, Sh, 40);
  StrOff := L4(Sh, 16);
  Found := False;
  For K := 0 To ShNum - 1 Do
  Begin
    SysLSeek(Fd, ShOff + K * 40, 0);
    SysRead(Fd, Sh, 40);
    Nm := '';
    SysLSeek(Fd, StrOff + L4(Sh, 0), 0);
    N := SysRead(Fd, Buf, 20);
    J := 0;
    While (J < N) And (Buf[J] <> 0) Do
    Begin
      Nm := Nm + Chr(Buf[J]);
      Inc(J);
    End;
    If Nm = '.modinfo' Then
    Begin
      Found := True;
      Off := L4(Sh, 16);
      Sz := L4(Sh, 20);
      If Sz > 4000 Then Sz := 4000;
      SysLSeek(Fd, Off, 0);
      N := SysRead(Fd, Buf, Sz);
      Line := '';
      If Want = '' Then SysPut(1, 'filename:       ' + Path + #10);
      For J := 0 To N - 1 Do
        If Buf[J] = 0 Then
        Begin
          If Line <> '' Then
          Begin
            I := Pos('=', Line);
            If (Want = '') Then
              SysPut(1, Copy(Line, 1, I - 1) + ':' +
                Copy('               ', 1, 15 - I + 1) +
                Copy(Line, I + 1, 255) + #10)
            Else If Copy(Line, 1, I - 1) = Want Then
              SysPut(1, Copy(Line, I + 1, 255) + #10);
          End;
          Line := '';
        End
        Else Line := Line + Chr(Buf[J]);
    End;
  End;
  SysClose(Fd);
  If Not Found Then SysPut(2, 'modinfo: .modinfo absente' + #10);
End;

Procedure DoDepmod;
Var D, Ino, Fd : LongInt; Nm : String;
Begin
  D := SysOpenDir('/lib/modules');
  If D < 0 Then
  Begin
    SysPut(2, 'depmod: /lib/modules : ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  Fd := SysOpen('/lib/modules/modules.dep', $241, 420);
  While SysReadDir(D, Nm, Ino) Do
    If (Length(Nm) > 3) And (Copy(Nm, Length(Nm) - 2, 3) = '.ko') Then
      SysPut(Fd, '/lib/modules/' + Nm + ':' + #10);
  SysCloseDir(D);
  SysClose(Fd);
End;

Var K : LongInt;
Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 255);
  If Prog = 'modprobe' Then DoModprobe
  Else If Prog = 'depmod' Then DoDepmod
  Else DoModinfo;
  SysExit(0);
End.
