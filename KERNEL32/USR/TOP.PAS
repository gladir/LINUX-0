{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: top et vmstat (nom lu dans argv[0]) : etat du systeme lu dans
      /proc. top [-b] [-n N] [-d s] (q pour quitter) ; vmstat [delai
      [nombre]].
}

Program TOP;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  MaxP = 200;

Var
  Prog : String;
  Buf : Array[0..4095] Of Char;
  BufN : LongInt;
  Pids, Ticks0, Ticks1 : Array[1..MaxP] Of LongInt;
  NP : LongInt;
  Cpu0U, Cpu0I, Cpu1U, Cpu1I : LongInt;

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

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function Z2(V : LongInt) : String;
Begin
  If V < 10 Then Z2 := '0' + NumS(V) Else Z2 := NumS(V);
End;

Function Pad(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := ' ' + R;
  Pad := R;
End;

Function PadL(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := R + ' ';
  PadL := Copy(R, 1, N);
End;

Procedure LoadFile(Const F : String);
Var Fd : LongInt;
Begin
  BufN := 0;
  Fd := SysOpen(F, 0, 0);
  If Fd < 0 Then Exit;
  BufN := SysRead(Fd, Buf, 4095);
  If BufN < 0 Then BufN := 0;
  Buf[BufN] := #0;
  SysClose(Fd);
End;

{ valeur apres "Cle:" dans Buf (texte) }
Function KeyVal(Const Key : String) : String;
Var I, K, J : LongInt; R : String; Ok : Boolean;
Begin
  KeyVal := '';
  I := 0;
  While I < BufN Do
  Begin
    Ok := True;
    For K := 1 To Length(Key) Do
      If (I + K - 1 >= BufN) Or (Buf[I + K - 1] <> Key[K]) Then Ok := False;
    If Ok And (Buf[I + Length(Key)] = ':') Then
    Begin
      J := I + Length(Key) + 1;
      While (J < BufN) And ((Buf[J] = ' ') Or (Buf[J] = #9)) Do Inc(J);
      R := '';
      While (J < BufN) And (Buf[J] <> #10) Do
      Begin
        R := R + Buf[J];
        Inc(J);
      End;
      KeyVal := R;
      Exit;
    End;
    While (I < BufN) And (Buf[I] <> #10) Do Inc(I);
    Inc(I);
  End;
End;

Function FirstNum(Const S : String) : LongInt;
Var K, V : LongInt;
Begin
  V := 0;
  K := 1;
  While (K <= Length(S)) And ((S[K] < '0') Or (S[K] > '9')) Do Inc(K);
  While (K <= Length(S)) And (S[K] >= '0') And (S[K] <= '9') Do
  Begin
    V := V * 10 + Ord(S[K]) - 48;
    Inc(K);
  End;
  FirstNum := V;
End;

{ n-ieme nombre d'une ligne de /proc/stat ("cpu  a b c ...") }
Function NthNum(Const Line : String; N : LongInt) : LongInt;
Var K, I, V : LongInt;
Begin
  I := 0;
  K := 1;
  While K <= Length(Line) Do
  Begin
    While (K <= Length(Line)) And ((Line[K] < '0') Or (Line[K] > '9')) Do
      Inc(K);
    If K > Length(Line) Then Break;
    V := 0;
    While (K <= Length(Line)) And (Line[K] >= '0') And
          (Line[K] <= '9') Do
    Begin
      V := V * 10 + Ord(Line[K]) - 48;
      Inc(K);
    End;
    Inc(I);
    If I = N Then
    Begin
      NthNum := V;
      Exit;
    End;
  End;
  NthNum := 0;
End;

Procedure CpuTimes(Var U, I : LongInt);
Var L : String; K : LongInt;
Begin
  LoadFile('/proc/stat');
  L := '';
  K := 0;
  While (K < BufN) And (Buf[K] <> #10) Do
  Begin
    L := L + Buf[K];
    Inc(K);
  End;
  U := NthNum(L, 1) + NthNum(L, 2) + NthNum(L, 3);
  I := NthNum(L, 4);
End;

Function ProcTicks(Pid : LongInt) : LongInt;
Var K, I, Fld : LongInt; V : LongInt;
Begin
  ProcTicks := 0;
  LoadFile('/proc/' + NumS(Pid) + '/stat');
  If BufN = 0 Then Exit;
  K := 0;
  While (K < BufN) And (Buf[K] <> ')') Do Inc(K);
  Fld := 2;
  V := 0;
  While K < BufN Do
  Begin
    While (K < BufN) And (Buf[K] = ' ') Do Inc(K);
    If K >= BufN Then Break;
    Inc(Fld);
    I := 0;
    While (K < BufN) And (Buf[K] <> ' ') And (Buf[K] <> #10) Do
    Begin
      If (Fld = 14) Or (Fld = 15) Then
        If (Buf[K] >= '0') And (Buf[K] <= '9') Then
          I := I * 10 + Ord(Buf[K]) - 48;
      Inc(K);
    End;
    If (Fld = 14) Or (Fld = 15) Then V := V + I;
    If Fld > 15 Then Break;
  End;
  ProcTicks := V;
End;

Procedure ListPids;
Var D, Ino, V, E : LongInt; Nm : String;
Begin
  NP := 0;
  D := SysOpenDir('/proc');
  If D < 0 Then Exit;
  While SysReadDir(D, Nm, Ino) Do
  Begin
    Val(Nm, V, E);
    If (E = 0) And (V > 0) And (NP < MaxP) Then
    Begin
      Inc(NP);
      Pids[NP] := V;
    End;
  End;
  SysCloseDir(D);
End;

Procedure MemInfo(Var Tot, Free1, Cached : LongInt);
Begin
  LoadFile('/proc/meminfo');
  Tot := FirstNum(KeyVal('MemTotal'));
  Free1 := FirstNum(KeyVal('MemFree'));
  Cached := FirstNum(KeyVal('Cached'));
End;

Procedure Header(Pct1U, Pct1I : LongInt);
Var Tot, Fr, Ca, Up, K : LongInt; S, Ld : String; Run, Slp, T : LongInt;
    St : String; Fd : LongInt;
Begin
  LoadFile('/proc/uptime');
  Up := FirstNum(Copy(PS(@Buf[0]), 1, 20));
  LoadFile('/proc/loadavg');
  Ld := '';
  For K := 0 To 13 Do
    If K < BufN Then Ld := Ld + Buf[K];
  S := 'top - ' + Z2((SysTime Mod 86400) Div 3600) + ':' +
       Z2((SysTime Mod 3600) Div 60) + ':' + Z2(SysTime Mod 60) +
       ' up ' + NumS(Up Div 60) + ' min,  load average: ' + Ld;
  SysPut(1, S + #10);
  Run := 0;
  Slp := 0;
  For K := 1 To NP Do
  Begin
    LoadFile('/proc/' + NumS(Pids[K]) + '/status');
    St := KeyVal('State');
    If (St <> '') And (St[1] = 'R') Then Inc(Run) Else Inc(Slp);
  End;
  SysPut(1, 'Tasks: ' + NumS(NP) + ' total, ' + NumS(Run) + ' running, ' +
         NumS(Slp) + ' sleeping' + #10);
  T := Pct1U + Pct1I;
  If T = 0 Then T := 1;
  SysPut(1, '%Cpu(s): ' + NumS((Pct1U * 100) Div T) + '.0 us, ' +
         NumS((Pct1I * 100) Div T) + '.0 id' + #10);
  MemInfo(Tot, Fr, Ca);
  SysPut(1, 'KiB Mem : ' + Pad(NumS(Tot), 8) + ' total, ' +
         Pad(NumS(Fr), 8) + ' free, ' + Pad(NumS(Tot - Fr - Ca), 8) +
         ' used, ' + Pad(NumS(Ca), 8) + ' buff/cache' + #10 + #10);
End;

Procedure Snapshot(Delay : LongInt; First : Boolean);
Var K, J, Mx, T, Dt, Pu, Pi, Tmp : LongInt;
    Order : Array[1..MaxP] Of LongInt;
    Pct, Rss, Vsz, E : LongInt; Name, St, Uid : String; Pw : TSysPasswd;
    Cpu : LongInt;
Begin
  ListPids;
  CpuTimes(Cpu0U, Cpu0I);
  For K := 1 To NP Do Ticks0[K] := ProcTicks(Pids[K]);
  SysSleep(Delay);
  CpuTimes(Cpu1U, Cpu1I);
  For K := 1 To NP Do Ticks1[K] := ProcTicks(Pids[K]);
  Pu := Cpu1U - Cpu0U;
  Pi := Cpu1I - Cpu0I;
  Dt := Pu + Pi;
  If Dt <= 0 Then Dt := 1;
  Header(Pu, Pi);
  For K := 1 To NP Do Order[K] := K;
  For K := 1 To NP - 1 Do
    For J := K + 1 To NP Do
      If Ticks1[Order[J]] - Ticks0[Order[J]] >
         Ticks1[Order[K]] - Ticks0[Order[K]] Then
      Begin
        Tmp := Order[K];
        Order[K] := Order[J];
        Order[J] := Tmp;
      End;
  SysPut(1, '  PID USER      VIRT    RES S  %CPU TIME COMMAND' + #10);
  For K := 1 To NP Do
  Begin
    J := Order[K];
    LoadFile('/proc/' + NumS(Pids[J]) + '/status');
    Name := KeyVal('Name');
    St := KeyVal('State');
    If St = '' Then St := '?';
    Rss := FirstNum(KeyVal('VmRSS'));
    Vsz := FirstNum(KeyVal('VmSize'));
    Uid := KeyVal('Uid');
    Val(Copy(Uid, 1, Pos(#9, Uid + #9) - 1), E, Tmp);
    If SysGetPwUid(E, Pw) Then Uid := Pw.Name Else Uid := NumS(E);
    Cpu := ((Ticks1[J] - Ticks0[J]) * 100) Div Dt;
    SysPut(1, Pad(NumS(Pids[J]), 5) + ' ' + PadL(Uid, 8) + Pad(NumS(Vsz), 7) +
           Pad(NumS(Rss), 7) + ' ' + St[1] + Pad(NumS(Cpu), 5) + '.0 ' +
           Pad(NumS(Ticks1[J] Div 100), 4) + ' ' + Name + #10);
  End;
End;

Procedure DoTop;
Var I, N, D, K : LongInt; A : String; Batch : Boolean; Cnt : LongInt;
    Ch : Char; Old, Raw : TSysTermios; Tty : Boolean; Ev : LongInt;
Begin
  Batch := False;
  N := 0;
  D := 2;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-b' Then Batch := True
    Else If A = '-n' Then
    Begin
      Inc(I);
      Val(SysArgStr(I), N, K);
    End
    Else If A = '-d' Then
    Begin
      Inc(I);
      Val(SysArgStr(I), D, K);
      If D < 1 Then D := 1;
    End
    Else Batch := Batch;
    Inc(I);
  End;
  If Not SysIsATty(1) Then Batch := True;
  If Batch And (N = 0) And (Not SysIsATty(1)) Then N := 1;
  Cnt := 0;
  While True Do
  Begin
    If Not Batch Then SysPut(1, #27 + '[H' + #27 + '[2J');
    Snapshot(D, Cnt = 0);
    Inc(Cnt);
    If (N > 0) And (Cnt >= N) Then Break;
  End;
End;

Procedure DoVmstat;
Var Dl, Cnt, I, K, Tot, Fr, Ca, U0, I0, U1, I1, T : LongInt; A : String;
    Bl : LongInt;
Begin
  Dl := 0;
  Cnt := 1;
  If SysArgCount > 1 Then Val(SysArgStr(1), Dl, K);
  If SysArgCount > 2 Then Val(SysArgStr(2), Cnt, K)
  Else If Dl > 0 Then Cnt := 1000000;
  SysPut(1, 'procs -----------memory---------- ---swap-- -----io---- ' +
         '-system-- ------cpu-----' + #10);
  SysPut(1, ' r  b   swpd   free   buff  cache   si   so    bi    bo   in' +
         '   cs us sy id wa st' + #10);
  CpuTimes(U0, I0);
  For I := 1 To Cnt Do
  Begin
    If I > 1 Then SysSleep(Dl);
    CpuTimes(U1, I1);
    MemInfo(Tot, Fr, Ca);
    T := (U1 - U0) + (I1 - I0);
    If T <= 0 Then T := 1;
    If I = 1 Then
    Begin
      LoadFile('/proc/stat');
      T := (U1 + I1);
      If T <= 0 Then T := 1;
      SysPut(1, ' 1  0      0 ' + Pad(NumS(Fr), 6) + Pad('0', 7) +
        Pad(NumS(Ca), 7) + '    0    0     0     0    0    0 ' +
        Pad(NumS((U1 * 100) Div T), 2) + ' 0 ' + Pad(NumS((I1 * 100) Div T),
        2) + '  0  0' + #10);
    End
    Else
      SysPut(1, ' 1  0      0 ' + Pad(NumS(Fr), 6) + Pad('0', 7) +
        Pad(NumS(Ca), 7) + '    0    0     0     0    0    0 ' +
        Pad(NumS(((U1 - U0) * 100) Div T), 2) + ' 0 ' +
        Pad(NumS(((I1 - I0) * 100) Div T), 2) + '  0  0' + #10);
    U0 := U1;
    I0 := I1;
  End;
End;

Var K : LongInt;
Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 255);
  If Prog = 'vmstat' Then DoVmstat Else DoTop;
  SysExit(0);
End.
