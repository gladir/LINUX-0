{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/tar : archives ustar (tar c|x|t [v] [z] [f archive] [-C
      dir] [fichier...]) ; z passe par gzip.
}

Program TAR;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');

Function PS(P : PChar) : String;
Var X : String;
Begin
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  PS := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(UsageW[SysLang]) + Syn + #10);
  SysExit(1);
End;

Procedure Warn(Const What : String);
Begin
  SysPut(2, 'tar: ' + What + ': ' + SysErrorText(SysErrno) + #10);
End;

Function BaseOf(Const P : String) : String;
Var K, L : LongInt;
Begin
  L := Length(P);
  While (L > 1) And (P[L] = '/') Do Dec(L);
  K := L;
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  BaseOf := Copy(P, K + 1, L - K);
End;

Function IsDir(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  IsDir := (SysStat(P, St) = 0) And ((St.Mode And $F000) = $4000);
End;

Var
  Fd, Gz, Rc : LongInt;
  Verbose, Zip : Boolean;
  Blk : Array[0..511] Of Byte;
  Names : Array[1..64] Of String;
  NN : LongInt;
  Mode1 : Char;
  Arch, Dir1 : String;

Procedure PutStr(Off, Len : LongInt; Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Len Do
    If K <= Length(S) Then Blk[Off + K - 1] := Ord(S[K]) Else Blk[Off + K - 1]
      := 0;
End;

Procedure PutOct(Off, Len, V : LongInt);
Var K : LongInt;
Begin
  If V < 0 Then V := 0;
  For K := Len - 2 DownTo 0 Do
  Begin
    Blk[Off + K] := 48 + (V And 7);
    V := V Shr 3;
  End;
  Blk[Off + Len - 1] := 0;
End;

Function GetOct(Off, Len : LongInt) : LongInt;
Var K, V : LongInt;
Begin
  V := 0;
  For K := 0 To Len - 1 Do
  Begin
    If (Blk[Off + K] < 48) Or (Blk[Off + K] > 55) Then
    Begin
      If V > 0 Then Break;
      If Blk[Off + K] = 0 Then Break;
    End
    Else V := V * 8 + Blk[Off + K] - 48;
  End;
  GetOct := V;
End;

Function GetStr(Off, Len : LongInt) : String;
Var K : LongInt; S : String;
Begin
  S := '';
  For K := 0 To Len - 1 Do
  Begin
    If Blk[Off + K] = 0 Then Break;
    S := S + Chr(Blk[Off + K]);
  End;
  GetStr := S;
End;

Function ReadFull(F : LongInt; Var B; N : LongInt) : LongInt;
Var Tot, R : LongInt; P : ^Byte;
Begin
  Tot := 0;
  While Tot < N Do
  Begin
    P := Pointer(LongInt(@B) + Tot);
    R := SysRead(F, P^, N - Tot);
    If R <= 0 Then Break;
    Tot := Tot + R;
  End;
  ReadFull := Tot;
End;

Function WriteFull(F : LongInt; Var B; N : LongInt) : LongInt;
Var Tot, R : LongInt; P : ^Byte;
Begin
  Tot := 0;
  While Tot < N Do
  Begin
    P := Pointer(LongInt(@B) + Tot);
    R := SysWrite(F, P^, N - Tot);
    If R <= 0 Then Break;
    Tot := Tot + R;
  End;
  WriteFull := Tot;
End;

Function FindExe(Const Name : String) : String;
Var Path, D1 : String; K : LongInt;
Begin
  FindExe := Name;
  Path := SysGetEnv('PATH');
  If Path = '' Then Path := '/bin:/usr/bin:/sbin:/usr/sbin';
  While Path <> '' Do
  Begin
    K := Pos(':', Path);
    If K = 0 Then
    Begin
      D1 := Path;
      Path := '';
    End
    Else
    Begin
      D1 := Copy(Path, 1, K - 1);
      Path := Copy(Path, K + 1, 255);
    End;
    If SysAccess(D1 + '/' + Name, 1) = 0 Then
    Begin
      FindExe := D1 + '/' + Name;
      Exit;
    End;
  End;
End;

{ filtre gzip : cree le processus, rend le descripteur a utiliser }
Function StartGzip(Compress : Boolean; Target : LongInt) : LongInt;
Var P : Array[0..1] Of LongInt; Pid : LongInt;
Begin
  SysPipe(P[0]);
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd('gzip');
    If Compress Then
    Begin
      SysArgAdd('-c');
      SysDup2(P[0], 0);
      SysDup2(Target, 1);
    End
    Else
    Begin
      SysArgAdd('-dc');
      SysDup2(Target, 0);
      SysDup2(P[1], 1);
    End;
    SysClose(P[0]);
    SysClose(P[1]);
    SysEnvInherit;
    SysArgExec(FindExe('gzip'));
    SysExit(127);
  End;
  If Compress Then
  Begin
    SysClose(P[0]);
    StartGzip := P[1];
  End
  Else
  Begin
    SysClose(P[1]);
    StartGzip := P[0];
  End;
End;

Procedure Header(Const Name : String; Const St : TSysStat; Typ : Char;
    Const Link : String; Size : LongInt);
Var K, Sum, Sp : LongInt; Pre, Nm : String; P : TSysPasswd;
Begin
  FillChar(Blk, 512, 0);
  Nm := Name;
  Pre := '';
  If Length(Nm) > 100 Then
  Begin
    Sp := 0;
    For K := 1 To Length(Nm) Do
      If (Nm[K] = '/') And (K <= 155) And (Length(Nm) - K <= 100) Then Sp := K;
    If Sp > 0 Then
    Begin
      Pre := Copy(Nm, 1, Sp - 1);
      Nm := Copy(Nm, Sp + 1, 100);
    End
    Else Nm := Copy(Nm, 1, 100);
  End;
  PutStr(0, 100, Nm);
  PutOct(100, 8, St.Mode And $FFF);
  PutOct(108, 8, St.Uid);
  PutOct(116, 8, St.Gid);
  PutOct(124, 12, Size);
  PutOct(136, 12, St.MTime);
  Blk[156] := Ord(Typ);
  PutStr(157, 100, Link);
  PutStr(257, 6, 'ustar');
  Blk[263] := 48;
  Blk[264] := 48;
  If SysGetPwUid(St.Uid, P) Then PutStr(265, 32, P.Name);
  PutStr(297, 32, SysGroupName(St.Gid));
  PutStr(345, 155, Pre);
  For K := 148 To 155 Do Blk[K] := 32;
  Sum := 0;
  For K := 0 To 511 Do Sum := Sum + Blk[K];
  For K := 5 DownTo 0 Do
  Begin
    Blk[148 + K] := 48 + (Sum And 7);
    Sum := Sum Shr 3;
  End;
  Blk[154] := 0;
  Blk[155] := 32;
  WriteFull(Gz, Blk, 512);
End;

Procedure AddPath(Path, Name : String);
Var St : TSysStat; F, N, D, Ino, T : LongInt; Nm, Lk : String;
Begin
  If SysLStat(Path, St) < 0 Then
  Begin
    Warn(Path);
    Rc := 1;
    Exit;
  End;
  While (Length(Name) > 1) And (Name[Length(Name)] = '/') Do
    Name := Copy(Name, 1, Length(Name) - 1);
  If (Name <> '') And (Name[1] = '/') Then Name := Copy(Name, 2, 500);
  T := St.Mode And $F000;
  If Verbose Then SysPut(2, Name + #10);
  If T = $4000 Then
  Begin
    Header(Name + '/', St, '5', '', 0);
    D := SysOpenDir(Path);
    If D >= 0 Then
    Begin
      While SysReadDir(D, Nm, Ino) Do
        If (Nm <> '.') And (Nm <> '..') Then
          AddPath(Path + '/' + Nm, Name + '/' + Nm);
      SysCloseDir(D);
    End;
  End
  Else If T = $A000 Then
  Begin
    Lk := SysReadlink(Path);
    Header(Name, St, '2', Lk, 0);
  End
  Else If T = $8000 Then
  Begin
    F := SysOpen(Path, O_RDONLY, 0);
    If F < 0 Then
    Begin
      Warn(Path);
      Rc := 1;
      Exit;
    End;
    Header(Name, St, '0', '', St.Size);
    Repeat
      FillChar(Blk, 512, 0);
      N := ReadFull(F, Blk, 512);
      If N > 0 Then WriteFull(Gz, Blk, 512);
    Until N < 512;
    SysClose(F);
  End;
End;

Procedure MakeDirs(Const Path : String);
Var K : LongInt;
Begin
  For K := 2 To Length(Path) Do
    If Path[K] = '/' Then SysMkdir(Copy(Path, 1, K - 1), 493);
End;

Procedure Extract(DoList : Boolean);
Var N, Size, Left, T, Mode, F, Uid, Gid, MT, K : LongInt;
    Name, Pre, Lk : String; Ok : Boolean; Z : Boolean;
    TB : Array[0..1] Of LongInt; ZP : LongInt;
Begin
  While True Do
  Begin
    N := ReadFull(Gz, Blk, 512);
    If N < 512 Then Break;
    Z := True;
    For K := 0 To 511 Do If Blk[K] <> 0 Then Z := False;
    If Z Then Break;
    Name := GetStr(0, 100);
    Pre := GetStr(345, 155);
    If Pre <> '' Then Name := Pre + '/' + Name;
    Size := GetOct(124, 12);
    Mode := GetOct(100, 8);
    Uid := GetOct(108, 8);
    Gid := GetOct(116, 8);
    MT := GetOct(136, 12);
    T := Blk[156];
    Lk := GetStr(157, 100);
    Left := Size;
    If (T = 0) Then T := 48;
    While (Name <> '') And (Name[1] = '/') Do Name := Copy(Name, 2, 500);
    If DoList Then
    Begin
      If Verbose Then
        SysPut(1, NumS(Mode) + ' ' + NumS(Uid) + '/' + NumS(Gid) + ' ' +
          NumS(Size) + ' ' + Name + #10)
      Else SysPut(1, Name + #10);
    End
    Else If Name <> '' Then
    Begin
      If Verbose Then SysPut(2, Name + #10);
      If Dir1 <> '' Then Name := Dir1 + '/' + Name;
      MakeDirs(Name);
      If T = 53 Then
      Begin
        SysMkdir(Name, Mode And $FFF);
        SysChmod(Name, Mode And $FFF);
        SysChown(Name, Uid, Gid);
      End
      Else If T = 50 Then
      Begin
        SysUnlink(Name);
        SysSymlink(Lk, Name);
      End
      Else If T = 49 Then
      Begin
        SysUnlink(Name);
        SysLink(Lk, Name);
      End
      Else If T = 48 Then
      Begin
        F := SysOpen(Name, O_WRONLY Or O_CREAT Or O_TRUNC, 384);
        If F < 0 Then Begin Warn(Name); Rc := 1; End;
        While Left > 0 Do
        Begin
          N := ReadFull(Gz, Blk, 512);
          If N < 512 Then Break;
          If Left < 512 Then K := Left Else K := 512;
          If F >= 0 Then WriteFull(F, Blk, K);
          Left := Left - K;
        End;
        If F >= 0 Then
        Begin
          SysClose(F);
          SysChmod(Name, Mode And $FFF);
          SysChown(Name, Uid, Gid);
          LnxTmp[4] := MT;
          LnxTmp[5] := MT;
          SysCall(30, SysNewZ(Name), LongInt(@LnxTmp[4]), 0, 0, 0);
        End;
        Left := 0;
      End;
    End;
    { sauter les donnees restantes }
    While Left > 0 Do
    Begin
      N := ReadFull(Gz, Blk, 512);
      If N < 512 Then Break;
      Left := Left - 512;
    End;
  End;
End;

Var
  I, K : LongInt;
  A : String;
  NextF, NextC : Boolean;

BEGIN
  Mode1 := ' ';
  Verbose := False;
  Zip := False;
  Arch := '-';
  Dir1 := '';
  NN := 0;
  Rc := 0;
  NextF := False;
  NextC := False;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If NextF Then
    Begin
      Arch := A;
      NextF := False;
    End
    Else If NextC Then
    Begin
      Dir1 := A;
      NextC := False;
    End
    Else If (Mode1 = ' ') And (Length(A) > 0) Then
    Begin
      If A[1] = '-' Then A := Copy(A, 2, 40);
      For K := 1 To Length(A) Do
        Case A[K] Of
          'c', 'x', 't' : Mode1 := A[K];
          'v' : Verbose := True;
          'z' : Zip := True;
          'f' : NextF := True;
        Else Usage('tar c|x|t[vz][f archive] [-C dir] [file...]');
        End;
    End
    Else If A = '-C' Then NextC := True
    Else If (A = '-z') Then Zip := True
    Else If (A = '-v') Then Verbose := True
    Else If (A = '-f') Then NextF := True
    Else If NN < 64 Then
    Begin
      Inc(NN);
      Names[NN] := A;
    End;
  End;
  If Mode1 = ' ' Then Usage('tar c|x|t[vz][f archive] [-C dir] [file...]');
  If Mode1 = 'c' Then
  Begin
    If Arch = '-' Then Fd := 1 Else Fd := SysCreat(Arch, 420);
    If Fd < 0 Then
    Begin
      Warn(Arch);
      SysExit(2);
    End;
    Gz := Fd;
    If Zip Then Gz := StartGzip(True, Fd);
    If Dir1 <> '' Then SysChdir(Dir1);
    For I := 1 To NN Do AddPath(Names[I], Names[I]);
    FillChar(Blk, 512, 0);
    WriteFull(Gz, Blk, 512);
    WriteFull(Gz, Blk, 512);
    If Zip Then
    Begin
      SysClose(Gz);
      SysWaitPid(-1, K, 0);
    End;
  End
  Else
  Begin
    If Arch = '-' Then Fd := 0 Else Fd := SysOpen(Arch, O_RDONLY, 0);
    If Fd < 0 Then
    Begin
      Warn(Arch);
      SysExit(2);
    End;
    Gz := Fd;
    If Zip Then Gz := StartGzip(False, Fd);
    Extract(Mode1 = 't');
    If Zip Then SysWaitPid(-1, K, 0);
  End;
  SysExit(Rc);
END.
