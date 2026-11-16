{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/umount : demonte un systeme de fichiers.
    umount [-flrnvd] [-t type] cible|peripherique...
    umount -a [-t type]      demonte tout (sauf /, /proc, /sys, /dev)
    -l : demontage paresseux (MNT_DETACH) ; -f : force ; -r : si le demontage
    echoue, remonte en lecture seule ; -v : bavard ; -d : libere aussi le
    peripherique de boucle ; un peripherique de boucle mis en place par
    mount (autoclear) est libere automatiquement. Messages en cinq langues.
}

Program Umount;

Const
  LOOP_CLR_FD = $4C01; LOOP_GET_STATUS64 = $4C05;
  MAXMNT = 96;
  M : Array[1..5, 1..5] Of PChar = (
    ('Usage : umount [-flrnvd] [-t type] cible...   |   umount -a',
     'Usage: umount [-flrnvd] [-t type] target...   |   umount -a',
     'Aufruf: umount [-flrnvd] [-t Typ] Ziel...   |   umount -a',
     'Uso: umount [-flrnvd] [-t tipo] destino...   |   umount -a',
     'Uso: umount [-flrnvd] [-t tipo] destinazione...   |   umount -a'),
    ('umount : ', 'umount: ', 'umount: ', 'umount: ', 'umount: '),
    ('non monte', 'not mounted', 'nicht eingehaengt', 'no esta montado',
     'non montato'),
    ('cible occupee', 'target is busy', 'Ziel ist belegt', 'destino ocupado',
     'destinazione occupata'),
    ('demonte', 'unmounted', 'ausgehaengt', 'desmontado', 'smontato'));

Type
  TMnt = Record
    Src, Dir, Typ : String;
  End;
  TLoopInfo = Record
    Device, Inode, RDevice, Offset, SizeLimit : Array[0..1] Of LongInt;
    Number, EncType, EncKeySize, Flags : LongInt;
    FileName : Array[0..63] Of Byte;
    CryptName : Array[0..63] Of Byte;
    EncKey : Array[0..31] Of Byte;
    Init : Array[0..3] Of LongInt;
  End;

Var
  Cur : Array[1..MAXMNT] Of TMnt;
  NCur : LongInt;
  Rc : LongInt;
  Lazy, Force, Rdo, Verb, DoAll, FreeLoop : Boolean;
  OptT : String;

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

Function Field(Const S : String; N : LongInt) : String;
Var K, F, A : LongInt;
Begin
  F := 0;
  K := 1;
  Field := '';
  While K <= Length(S) Do
  Begin
    While (K <= Length(S)) And (S[K] In [' ', #9]) Do Inc(K);
    If K > Length(S) Then Break;
    A := K;
    While (K <= Length(S)) And Not (S[K] In [' ', #9]) Do Inc(K);
    Inc(F);
    If F = N Then
    Begin
      Field := Copy(S, A, K - A);
      Exit;
    End;
  End;
End;

Function ToNum(Const S : String) : LongInt;
Var V, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then V := 0;
  ToNum := V;
End;

Function Unesc(Const S : String) : String;
Var R : String; K : LongInt;
Begin
  R := '';
  K := 1;
  While K <= Length(S) Do
  Begin
    If (S[K] = '\') And (K + 3 <= Length(S)) Then
    Begin
      R := R + Chr(ToNum(Copy(S, K + 1, 1)) * 64 + ToNum(Copy(S, K + 2, 1)) *
           8 + ToNum(Copy(S, K + 3, 1)));
      K := K + 3;
    End
    Else R := R + S[K];
    Inc(K);
  End;
  Unesc := R;
End;

Procedure LoadCur;
Var F : LongInt; L : String;
Begin
  NCur := 0;
  F := SysOpen('/proc/mounts', O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    If (Field(L, 1) = '') Or (NCur >= MAXMNT) Then Continue;
    Inc(NCur);
    Cur[NCur].Src := Unesc(Field(L, 1));
    Cur[NCur].Dir := Unesc(Field(L, 2));
    Cur[NCur].Typ := Field(L, 3);
  End;
  SysClose(F);
End;

Function InList(Const L, T : String) : Boolean;
Var K, J : LongInt;
Begin
  InList := False;
  K := 1;
  While K <= Length(L) + 1 Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    If Copy(L, K, J - K) = T Then InList := True;
    K := J + 1;
  End;
End;

{ le peripherique a-t-il ete mis en place par mount ? (retire l'entree) }
Var Keep : Array[1..32] Of String[40];

Function Tracked(Const Dev : String) : Boolean;
Var Fd, N, K : LongInt; L : String; Found : Boolean;
Begin
  Tracked := False;
  Found := False;
  N := 0;
  Fd := SysOpen('/var/run/mount.loops', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
    If L = Dev Then Found := True
    Else If (L <> '') And (N < 32) Then
    Begin
      Inc(N);
      Keep[N] := L;
    End;
  SysClose(Fd);
  Tracked := Found;
  If Not Found Then Exit;
  Fd := SysOpen('/var/run/mount.loops', O_WRONLY Or O_TRUNC, 0);
  If Fd < 0 Then Exit;
  For K := 1 To N Do SysPut(Fd, Keep[K] + #10);
  SysClose(Fd);
End;

{ libere un peripherique de boucle mis en place par mount (ou -d) }
Procedure LoopRelease(Const Dev : String; Always : Boolean);
Var Fd : LongInt; Li : TLoopInfo; Mine : Boolean;
Begin
  If Copy(Dev, 1, 9) <> '/dev/loop' Then Exit;
  Mine := Tracked(Dev);
  Fd := SysOpen(Dev, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  FillChar(Li, SizeOf(Li), 0);
  If SysIoctl(Fd, LOOP_GET_STATUS64, Li) = 0 Then
    If Always Or Mine Or ((Li.Flags And 4) <> 0) Then
      SysIoctlL(Fd, LOOP_CLR_FD, 0);
  SysClose(Fd);
End;

Function DoUmount(Const Target : String) : LongInt;
Var K, Idx, R : LongInt; Src, Dir : String;
Begin
  LoadCur;
  Idx := 0;
  { le dernier montage portant ce nom (cible ou source) }
  For K := 1 To NCur Do
    If (Cur[K].Dir = Target) Or (Cur[K].Src = Target) Then Idx := K;
  If Idx = 0 Then
  Begin
    { absent de /proc/mounts (liaison, montage non liste) : essai direct }
    If Lazy Then R := LnxSys3(52, LnxZ(Target), 2, 0)
    Else R := LnxSys3(22, LnxZ(Target), 0, 0);
    If R >= 0 Then
    Begin
      DoUmount := 0;
      Exit;
    End;
    SysPut(2, Msg(2) + Target + ': ' + Msg(3) + #10);
    DoUmount := 1;
    Exit;
  End;
  Src := Cur[Idx].Src;
  Dir := Cur[Idx].Dir;
  If Lazy Then R := LnxSys3(52, LnxZ(Dir), 2, 0)
  Else If Force Then R := LnxSys3(52, LnxZ(Dir), 1, 0)
  Else R := LnxSys3(22, LnxZ(Dir), 0, 0);
  If R < 0 Then
  Begin
    If (R = -16) And Rdo Then
      If LnxSys6(21, LnxZ(Src), LnxZ(Dir), LnxZ('none'), MS_REMOUNT Or 1, 0,
                0) >= 0 Then
      Begin
        DoUmount := 0;
        Exit;
      End;
    If R = -16 Then SysPut(2, Msg(2) + Dir + ': ' + Msg(4) + #10)
    Else SysPut(2, Msg(2) + Dir + ': ' + SysErrorText(-R) + #10);
    DoUmount := 32;
    Exit;
  End;
  LoopRelease(Src, FreeLoop);
  If Verb Then SysPut(1, Dir + ' ' + Msg(5) + #10);
  DoUmount := 0;
End;

Var
  I, K, C : LongInt;
  A : String;
  Any : Boolean;

BEGIN
  Rc := 0;
  Lazy := False; Force := False; Rdo := False; Verb := False; DoAll := False;
  FreeLoop := False;
  OptT := '';
  Any := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-t') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      OptT := SysArgStr(I);
    End
    Else If (A = '-h') Or (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, Msg(1) + #10);
      SysExit(0);
    End
    Else If (Length(A) > 1) And (A[1] = '-') Then
    Begin
      If A = '--all' Then A := '-a'
      Else If A = '--lazy' Then A := '-l'
      Else If A = '--force' Then A := '-f'
      Else If A = '--read-only' Then A := '-r';
      For K := 2 To Length(A) Do
        Case A[K] Of
          'a' : DoAll := True;
          'l' : Lazy := True;
          'f' : Force := True;
          'r' : Rdo := True;
          'v' : Verb := True;
          'd' : FreeLoop := True;
        End;
    End
    Else
    Begin
      Any := True;
      C := DoUmount(A);
      If C <> 0 Then Rc := C;
    End;
    Inc(I);
  End;
  If DoAll Then
  Begin
    LoadCur;
    { ordre inverse : les montages les plus recents d'abord }
    For K := NCur DownTo 1 Do
    Begin
      If (Cur[K].Dir = '/') Or (Cur[K].Dir = '/proc') Or
         (Cur[K].Dir = '/sys') Or (Cur[K].Dir = '/dev') Then Continue;
      If (OptT <> '') And Not InList(OptT, Cur[K].Typ) Then Continue;
      C := DoUmount(Cur[K].Dir);
      If C <> 0 Then Rc := C;
    End;
    SysExit(Rc);
  End;
  If Not Any Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(1);
  End;
  SysExit(Rc);
END.
