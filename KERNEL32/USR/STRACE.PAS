{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: strace : trace les appels systeme et les signaux d'un
   programme avec ptrace(2) (noms i386, arguments decodes).
   strace [-f] [-c] [-q] [-T] [-s N] [-o fichier] [-e expr] [-p pid]...
          [commande [args...]]
   -f suit les fils (fork, vfork, clone) ; -c : tableau recapitulatif au lieu
   de la trace ; -e trace=a,b | trace=!a,b | trace=%file|%process|%network|
   %signal|%desc|%memory|%ipc ; -s N : taille maximale des chaines (32) ;
   -T : duree de chaque appel ; -o fichier : sortie dans un fichier. }

Program Strace;

{$I STRACE.INC}

Const
  MaxP = 64;
  PtTraceMe = 0;
  PtPeekData = 2;
  PtCont = 7;
  PtGetRegs = 12;
  PtAttach = 16;
  PtDetach = 17;
  PtSyscall = 24;
  PtSetOptions = $4200;
  PtGetEventMsg = $4201;
  PtGetSigInfo = $4202;
  WAll = $40000000;
  SigNames : Array[1..31] Of PChar = (
    'HUP', 'INT', 'QUIT', 'ILL', 'TRAP', 'ABRT', 'BUS', 'FPE', 'KILL',
    'USR1', 'SEGV', 'USR2', 'PIPE', 'ALRM', 'TERM', 'STKFLT', 'CHLD',
    'CONT', 'STOP', 'TSTP', 'TTIN', 'TTOU', 'URG', 'XCPU', 'XFSZ',
    'VTALRM', 'PROF', 'WINCH', 'IO', 'PWR', 'SYS');

Var
  OutFd : LongInt;
  Follow, CountOnly, Quiet, TimeEach : Boolean;
  StrSz : LongInt;
  Filt : Array[0..ScMax] Of Boolean;
  FiltOn, FiltNeg : Boolean;
  OBuf : Array[0..4095] Of Byte;
  OLen : LongInt;
  Rg : Array[0..16] Of LongInt;
  { etat par processus suivi }
  TP : Array[0..MaxP - 1] Of LongInt;
  TIn, TFresh, TSkip : Array[0..MaxP - 1] Of Boolean;
  TNr, TT0 : Array[0..MaxP - 1] Of LongInt;
  TV : Array[0..MaxP * 6 - 1] Of LongInt;
  TArg : Array[0..MaxP * 6 - 1] Of String;
  { compteurs pour -c }
  CCnt, CErr, CTim : Array[0..ScMax] Of LongInt;
  TBase : LongInt;
  FirstPid, FirstStatus, Seen : LongInt;

Procedure Flush;
Begin
  If OLen > 0 Then SysWrite(OutFd, OBuf[0], OLen);
  OLen := 0;
End;

Procedure Emit(Const S : String);
Var K : LongInt;
Begin
  If OLen + Length(S) > 4000 Then Flush;
  For K := 1 To Length(S) Do
  Begin
    OBuf[OLen] := Ord(S[K]);
    Inc(OLen);
  End;
End;

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

Function Hex(V : LongInt) : String;
Var I, D : LongInt; S : String; Z : Boolean;
Begin
  S := '';
  Z := True;
  For I := 7 DownTo 0 Do
  Begin
    D := (V Shr (I * 4)) And 15;
    If (D <> 0) Or (Not Z) Or (I = 0) Then
    Begin
      Z := False;
      If D < 10 Then S := S + Chr(48 + D) Else S := S + Chr(87 + D);
    End;
  End;
  Hex := '0x' + S;
End;

Function Oct(V : LongInt) : String;
Var S : String; I : LongInt;
Begin
  If V = 0 Then
  Begin
    Oct := '0';
    Exit;
  End;
  S := '';
  For I := 10 DownTo 0 Do
    If (S <> '') Or (((V Shr (I * 3)) And 7) <> 0) Then
      S := S + Chr(48 + ((V Shr (I * 3)) And 7));
  Oct := '0' + S;
End;

Function Pad(Const S : String; N : LongInt) : String;
Var R : String;
Begin
  R := S;
  While Length(R) < N Do R := ' ' + R;
  Pad := R;
End;

Function NowUs : LongInt;
Begin
  LnxSys3(78, LongInt(@LnxTmp), 0, 0);
  NowUs := (LnxTmp[0] - TBase) * 1000000 + LnxTmp[1];
End;

{ --- noms --- }

Function WordOf(Const S : String; N : LongInt) : String;
Var I, K, B : LongInt;
Begin
  WordOf := '';
  I := 1;
  For K := 1 To N Do
  Begin
    While (I <= Length(S)) And (S[I] = ' ') Do Inc(I);
    B := I;
    While (I <= Length(S)) And (S[I] <> ' ') Do Inc(I);
    If K = N Then WordOf := Copy(S, B, I - B);
  End;
End;

Function ScName(N : LongInt) : String;
Var R : String;
Begin
  R := '';
  If (N >= 0) And (N <= ScMax) Then R := WordOf(PS(ScNames[N]), 1);
  If R = '' Then R := 'syscall_' + NumS(N);
  ScName := R;
End;

Function ScSpec(N : LongInt) : String;
Var S : String; K : LongInt;
Begin
  ScSpec := '?';
  If (N < 0) Or (N > ScMax) Then Exit;
  S := PS(ScNames[N]);
  K := Pos(' ', S);
  If K = 0 Then Exit;
  S := Copy(S, K + 1, 100);
  If S = '-' Then S := '';
  ScSpec := S;
End;

Function SigName(S : LongInt) : String;
Begin
  If (S >= 1) And (S <= 31) Then SigName := 'SIG' + PS(SigNames[S])
  Else If S = 0 Then SigName := '0'
  Else SigName := 'SIGRT_' + NumS(S - 32);
End;

Function ErrName(E : LongInt) : String;
Var R : String;
Begin
  R := '';
  If (E >= 1) And (E <= ErrMax) Then R := PS(ErrNames[E]);
  If R = '' Then R := '?';
  ErrName := R;
End;

{ --- memoire du tracee --- }

Function PeekW(Pid, Addr : LongInt; Var V : LongInt) : Boolean;
Begin
  V := 0;
  PeekW := SysCall(26, PtPeekData, Pid, Addr, LongInt(@V), 0) >= 0;
End;

{ lit N octets (N <= 200) ; Got = nombre lu }
Function ReadMem(Pid, Addr, N : LongInt; Var Got : LongInt) : String;
Var A, W, K, Off, B : LongInt; S : String;
Begin
  S := '';
  Got := 0;
  A := Addr And (Not 3);
  Off := Addr - A;
  K := 0;
  While K < N Do
  Begin
    If Not PeekW(Pid, A, W) Then Break;
    B := Off;
    While (B < 4) And (K < N) Do
    Begin
      S := S + Chr((W Shr (B * 8)) And 255);
      Inc(K);
      Inc(B);
    End;
    Off := 0;
    A := A + 4;
  End;
  Got := Length(S);
  ReadMem := S;
End;

{ chaine ASCIIZ (au plus StrSz octets) ; Trunc si plus longue }
Function ReadCStr(Pid, Addr, Lim : LongInt; Var Trunc, Bad : Boolean)
  : String;
Var A, W, B : LongInt; S : String; C : Byte; Fin : Boolean;
Begin
  S := '';
  Trunc := False;
  Bad := False;
  A := Addr And (Not 3);
  B := Addr - A;
  Fin := False;
  While Not Fin Do
  Begin
    If Not PeekW(Pid, A, W) Then
    Begin
      Bad := (S = '');
      Break;
    End;
    While B < 4 Do
    Begin
      C := (W Shr (B * 8)) And 255;
      If C = 0 Then
      Begin
        Fin := True;
        Break;
      End;
      If Length(S) >= Lim Then
      Begin
        Trunc := True;
        Fin := True;
        Break;
      End;
      S := S + Chr(C);
      Inc(B);
    End;
    B := 0;
    A := A + 4;
  End;
  ReadCStr := S;
End;

Function Quote(Const S : String; Trunc : Boolean) : String;
Var K : LongInt; C : Byte; R, D : String;
Begin
  R := '"';
  For K := 1 To Length(S) Do
  Begin
    If Length(R) > 235 Then
    Begin
      Trunc := True;
      Break;
    End;
    C := Ord(S[K]);
    If C = 10 Then R := R + '\n'
    Else If C = 9 Then R := R + '\t'
    Else If C = 13 Then R := R + '\r'
    Else If C = 34 Then R := R + '\"'
    Else If C = 92 Then R := R + '\\'
    Else If (C >= 32) And (C < 127) Then R := R + Chr(C)
    Else
    Begin
      D := Chr(48 + (C Shr 6)) + Chr(48 + ((C Shr 3) And 7)) +
           Chr(48 + (C And 7));
      If Not ((K < Length(S)) And (S[K + 1] >= '0') And
              (S[K + 1] <= '9')) Then
      Begin
        While (Length(D) > 1) And (D[1] = '0') Do Delete(D, 1, 1);
      End;
      R := R + '\' + D;
    End;
  End;
  R := R + '"';
  If Trunc Then R := R + '...';
  Quote := R;
End;

{ --- decodage des drapeaux --- }

Function OFlags(V : LongInt) : String;
Var S : String;
Procedure Add(M : LongInt; Const N : String);
Begin
  If (V And M) = M Then S := S + '|' + N;
End;
Begin
  Case V And 3 Of
    0 : S := 'O_RDONLY';
    1 : S := 'O_WRONLY';
    2 : S := 'O_RDWR';
  Else
    S := 'O_ACCMODE';
  End;
  Add($40, 'O_CREAT');
  Add($80, 'O_EXCL');
  Add($100, 'O_NOCTTY');
  Add($200, 'O_TRUNC');
  Add($400, 'O_APPEND');
  Add($800, 'O_NONBLOCK');
  If (V And $101000) = $101000 Then S := S + '|O_SYNC'
  Else Add($1000, 'O_DSYNC');
  Add($2000, 'O_ASYNC');
  Add($4000, 'O_DIRECT');
  Add($8000, 'O_LARGEFILE');
  Add($10000, 'O_DIRECTORY');
  Add($20000, 'O_NOFOLLOW');
  Add($40000, 'O_NOATIME');
  Add($80000, 'O_CLOEXEC');
  Add($200000, 'O_PATH');
  OFlags := S;
End;

Function ProtS(V : LongInt) : String;
Var S : String;
Begin
  If V = 0 Then
  Begin
    ProtS := 'PROT_NONE';
    Exit;
  End;
  S := '';
  If (V And 1) <> 0 Then S := S + '|PROT_READ';
  If (V And 2) <> 0 Then S := S + '|PROT_WRITE';
  If (V And 4) <> 0 Then S := S + '|PROT_EXEC';
  Delete(S, 1, 1);
  ProtS := S;
End;

Function MapS(V : LongInt) : String;
Var S : String;
Procedure Add(M : LongInt; Const N : String);
Begin
  If (V And M) <> 0 Then S := S + '|' + N;
End;
Begin
  S := '';
  If (V And 3) = 1 Then S := '|MAP_SHARED'
  Else If (V And 3) = 2 Then S := '|MAP_PRIVATE';
  Add($10, 'MAP_FIXED');
  Add($20, 'MAP_ANONYMOUS');
  Add($100, 'MAP_GROWSDOWN');
  Add($800, 'MAP_DENYWRITE');
  Add($4000, 'MAP_NORESERVE');
  Add($8000, 'MAP_POPULATE');
  Add($20000, 'MAP_STACK');
  If S = '' Then S := '|0';
  Delete(S, 1, 1);
  MapS := S;
End;

Function AccS(V : LongInt) : String;
Var S : String;
Begin
  If V = 0 Then
  Begin
    AccS := 'F_OK';
    Exit;
  End;
  S := '';
  If (V And 4) <> 0 Then S := S + '|R_OK';
  If (V And 2) <> 0 Then S := S + '|W_OK';
  If (V And 1) <> 0 Then S := S + '|X_OK';
  Delete(S, 1, 1);
  AccS := S;
End;

Function WaitOptS(V : LongInt) : String;
Var S : String;
Begin
  If V = 0 Then
  Begin
    WaitOptS := '0';
    Exit;
  End;
  S := '';
  If (V And 1) <> 0 Then S := S + '|WNOHANG';
  If (V And 2) <> 0 Then S := S + '|WUNTRACED';
  If (V And 8) <> 0 Then S := S + '|WCONTINUED';
  If (V And WAll) <> 0 Then S := S + '|__WALL';
  Delete(S, 1, 1);
  WaitOptS := S;
End;

Function DomS(V : LongInt) : String;
Begin
  Case V Of
    1 : DomS := 'AF_UNIX';
    2 : DomS := 'AF_INET';
    10 : DomS := 'AF_INET6';
    16 : DomS := 'AF_NETLINK';
    17 : DomS := 'AF_PACKET';
  Else
    DomS := NumS(V);
  End;
End;

Function SockTypeS(V : LongInt) : String;
Var S : String;
Begin
  Case V And $F Of
    1 : S := 'SOCK_STREAM';
    2 : S := 'SOCK_DGRAM';
    3 : S := 'SOCK_RAW';
  Else
    S := NumS(V And $F);
  End;
  If (V And $800) <> 0 Then S := S + '|SOCK_NONBLOCK';
  If (V And $80000) <> 0 Then S := S + '|SOCK_CLOEXEC';
  SockTypeS := S;
End;

Function ModeS(M : LongInt) : String;
Var S : String;
Begin
  Case M And $F000 Of
    $8000 : S := 'S_IFREG';
    $4000 : S := 'S_IFDIR';
    $A000 : S := 'S_IFLNK';
    $2000 : S := 'S_IFCHR';
    $6000 : S := 'S_IFBLK';
    $1000 : S := 'S_IFIFO';
    $C000 : S := 'S_IFSOCK';
  Else
    S := '0';
  End;
  ModeS := S + '|' + Oct(M And $FFF);
End;

{ --- arguments --- }

Function ArgvS(Pid, Addr : LongInt) : String;
Var S : String; K, P : LongInt; Tr, Bd : Boolean; T : String;
Begin
  If Addr = 0 Then
  Begin
    ArgvS := 'NULL';
    Exit;
  End;
  S := '[';
  K := 0;
  While K < 24 Do
  Begin
    If (Not PeekW(Pid, Addr + K * 4, P)) Or (P = 0) Then Break;
    If K > 0 Then S := S + ', ';
    T := ReadCStr(Pid, P, StrSz, Tr, Bd);
    If Length(S) > 190 Then
    Begin
      S := S + '...';
      K := 99;
      Break;
    End;
    S := S + Quote(T, Tr);
    Inc(K);
  End;
  If K = 24 Then S := S + ', ...';
  ArgvS := S + ']';
End;

Function EnvpS(Pid, Addr : LongInt) : String;
Var K, P : LongInt;
Begin
  If Addr = 0 Then
  Begin
    EnvpS := 'NULL';
    Exit;
  End;
  K := 0;
  While (K < 4000) And PeekW(Pid, Addr + K * 4, P) And (P <> 0) Do Inc(K);
  EnvpS := Hex(Addr) + ' /* ' + NumS(K) + ' vars */';
End;

Function PtrS(V : LongInt) : String;
Begin
  If V = 0 Then PtrS := 'NULL' Else PtrS := Hex(V);
End;

Function StrArg(Pid, V : LongInt) : String;
Var Tr, Bd : Boolean; T : String;
Begin
  If V = 0 Then
  Begin
    StrArg := 'NULL';
    Exit;
  End;
  T := ReadCStr(Pid, V, 100, Tr, Bd);
  If Bd Then StrArg := Hex(V) Else StrArg := Quote(T, Tr);
End;

Function BufArg(Pid, V, N : LongInt) : String;
Var G, L : LongInt; T : String; Tr : Boolean;
Begin
  If V = 0 Then
  Begin
    BufArg := 'NULL';
    Exit;
  End;
  If N < 0 Then N := 0;
  L := N;
  Tr := False;
  If L > StrSz Then
  Begin
    L := StrSz;
    Tr := True;
  End;
  If L > 60 Then
  Begin
    L := 60;
    Tr := True;
  End;
  T := ReadMem(Pid, V, L, G);
  If (G = 0) And (N > 0) Then BufArg := Hex(V)
  Else BufArg := Quote(T, Tr);
End;

Function StatArg(Pid, V, Nr : LongInt) : String;
Var B : String; G, M, Sz : LongInt;
Begin
  If V = 0 Then
  Begin
    StatArg := 'NULL';
    Exit;
  End;
  B := ReadMem(Pid, V, 64, G);
  If G < 64 Then
  Begin
    StatArg := Hex(V);
    Exit;
  End;
  If (Nr = 106) Or (Nr = 107) Or (Nr = 108) Then
  Begin
    M := Ord(B[9]) + Ord(B[10]) * 256;
    Sz := Ord(B[21]) + Ord(B[22]) * 256 + Ord(B[23]) * 65536 +
          Ord(B[24]) * 16777216;
  End
  Else
  Begin
    M := Ord(B[17]) + Ord(B[18]) * 256 + Ord(B[19]) * 65536;
    Sz := Ord(B[45]) + Ord(B[46]) * 256 + Ord(B[47]) * 65536 +
          Ord(B[48]) * 16777216;
  End;
  StatArg := '{st_mode=' + ModeS(M) + ', st_size=' + NumS(Sz) + ', ...}';
End;

Function WaitSt(St : LongInt) : String;
Begin
  If (St And $7F) = 0 Then
    WaitSt := '{WIFEXITED(s) && WEXITSTATUS(s) == ' + NumS((St Shr 8) And
              255) + '}'
  Else If (St And $FF) = $7F Then
    WaitSt := '{WIFSTOPPED(s) && WSTOPSIG(s) == ' + SigName((St Shr 8) And
              255) + '}'
  Else
    WaitSt := '{WIFSIGNALED(s) && WTERMSIG(s) == ' + SigName(St And $7F) + '}';
End;

{ lettre de format C, valeur V : texte a l entree (vide pour les sorties) }
Function InArg(C : Char; V, Pid, Nr, Next : LongInt) : String;
Begin
  Case C Of
    'd' : InArg := NumS(V);
    'x' : InArg := Hex(V);
    'p' : InArg := PtrS(V);
    'f' : InArg := NumS(V);
    's' : InArg := StrArg(Pid, V);
    'o' : InArg := OFlags(V);
    'm' : InArg := Oct(V);
    'g' : InArg := SigName(V);
    'a' : InArg := ArgvS(Pid, V);
    'e' : InArg := EnvpS(Pid, V);
    'W' : InArg := WaitOptS(V);
    'r' : InArg := ProtS(V);
    'M' : InArg := MapS(V);
    'A' : InArg := AccS(V);
    'D' : InArg := DomS(V);
    'K' : InArg := SockTypeS(V);
    'b' : InArg := BufArg(Pid, V, Next);
    'y' : If V = -100 Then InArg := 'AT_FDCWD' Else InArg := NumS(V);
    'l' : Case V Of
            0 : InArg := 'SEEK_SET';
            1 : InArg := 'SEEK_CUR';
            2 : InArg := 'SEEK_END';
          Else
            InArg := NumS(V);
          End;
  Else
    InArg := '';
  End;
End;

Function OutArg(C : Char; V, Pid, Nr, Ret, Next : LongInt) : String;
Var T, P2 : LongInt; Tr, Bd : Boolean; S : String;
Begin
  OutArg := PtrS(V);
  If V = 0 Then Exit;
  If (Ret < 0) And (C <> 'w') Then Exit;
  Case C Of
    'B' : OutArg := BufArg(Pid, V, Ret);
    'k' : OutArg := StatArg(Pid, V, Nr);
    'w' : If (Ret > 0) And PeekW(Pid, V, T) Then OutArg := '[' + WaitSt(T) +
            ']';
    'P' : If PeekW(Pid, V, T) And PeekW(Pid, V + 4, P2) Then
            OutArg := '[' + NumS(T) + ', ' + NumS(P2) + ']';
    'T' : Begin
            S := ReadCStr(Pid, V, 100, Tr, Bd);
            OutArg := Quote(S, Tr);
          End;
  End;
End;

Function IsOut(C : Char) : Boolean;
Begin
  IsOut := (C = 'B') Or (C = 'k') Or (C = 'w') Or (C = 'P') Or (C = 'T');
End;

Function ArgCount(Const Sp : String) : LongInt;
Var K, N : LongInt;
Begin
  N := 0;
  For K := 1 To Length(Sp) Do
    If Sp[K] <> ' ' Then Inc(N);
  ArgCount := N;
End;

Function LetterAt(Const Sp : String; I : LongInt) : Char;
Var K, N : LongInt;
Begin
  LetterAt := '?';
  N := 0;
  For K := 1 To Length(Sp) Do
    If Sp[K] <> ' ' Then
    Begin
      If N = I Then
      Begin
        LetterAt := Sp[K];
        Exit;
      End;
      Inc(N);
    End;
End;

Function ArgReg(I : LongInt) : LongInt;
Begin
  ArgReg := Rg[I];
End;

{ --- filtre --- }

Function InList(Const Nm, L : String) : Boolean;
Begin
  InList := Pos(' ' + Nm + ' ', ' ' + L + ' ') > 0;
End;

Function ClassHas(Const Cls : String; N : LongInt) : Boolean;
Var Nm, Sp : String;
Begin
  Nm := ScName(N);
  Sp := ScSpec(N);
  ClassHas := False;
  If Cls = 'file' Then
    ClassHas := (Copy(Sp, 1, 1) = 's') Or (Copy(Sp, 1, 3) = 'y s') Or
                InList(Nm, 'execve chdir chroot getcwd')
  Else If Cls = 'desc' Then
    ClassHas := (Copy(Sp, 1, 1) = 'f') Or
      InList(Nm, 'open openat creat pipe pipe2 socket socketpair accept ' +
             'accept4 poll select _newselect epoll_create1 eventfd2')
  Else If Cls = 'process' Then
    ClassHas := InList(Nm, 'fork vfork clone clone3 execve exit ' +
      'exit_group wait4 waitpid waitid kill tkill tgkill ptrace prctl ' +
      'set_tid_address')
  Else If Cls = 'network' Then
    ClassHas := InList(Nm, 'socket bind connect listen accept accept4 ' +
      'sendto recvfrom sendmsg recvmsg shutdown getsockopt setsockopt ' +
      'getsockname getpeername socketpair socketcall send recv')
  Else If Cls = 'signal' Then
    ClassHas := InList(Nm, 'rt_sigaction rt_sigprocmask rt_sigsuspend ' +
      'rt_sigreturn rt_sigpending rt_sigtimedwait sigaction signal ' +
      'sigprocmask sigreturn sigsuspend sigaltstack sigpending kill ' +
      'tkill tgkill pause')
  Else If Cls = 'memory' Then
    ClassHas := InList(Nm, 'mmap mmap2 munmap mprotect mremap brk ' +
      'madvise mlock munlock msync mincore mlockall munlockall')
  Else If Cls = 'ipc' Then
    ClassHas := InList(Nm, 'ipc shmget shmat shmdt shmctl semget semop ' +
      'semctl msgget msgsnd msgrcv msgctl');
End;

Function Traced(N : LongInt) : Boolean;
Begin
  If (N < 0) Or (N > ScMax) Then
  Begin
    Traced := Not FiltOn;
    Exit;
  End;
  If Not FiltOn Then Traced := True
  Else If FiltNeg Then Traced := Not Filt[N]
  Else Traced := Filt[N];
End;

Procedure AddFilter(Const Nm : String);
Var K : LongInt; Cls : String;
Begin
  If Copy(Nm, 1, 1) = '%' Then
  Begin
    Cls := Copy(Nm, 2, 20);
    For K := 0 To ScMax Do
      If ClassHas(Cls, K) Then Filt[K] := True;
    Exit;
  End;
  For K := 0 To ScMax Do
    If ScName(K) = Nm Then Filt[K] := True;
  If (Nm = 'file') Or (Nm = 'desc') Or (Nm = 'process') Or
     (Nm = 'network') Or (Nm = 'signal') Or (Nm = 'memory') Or
     (Nm = 'ipc') Then
    For K := 0 To ScMax Do
      If ClassHas(Nm, K) Then Filt[K] := True;
End;

Procedure ParseExpr(Const E0 : String);
Var E, Item : String; K : LongInt;
Begin
  E := E0;
  K := Pos('=', E);
  If K > 0 Then
  Begin
    Item := Copy(E, 1, K - 1);
    If (Item <> 'trace') And (Item <> 't') Then Exit;
    E := Copy(E, K + 1, 250);
  End;
  FiltOn := True;
  If Copy(E, 1, 1) = '!' Then
  Begin
    FiltNeg := True;
    Delete(E, 1, 1);
  End;
  While E <> '' Do
  Begin
    K := Pos(',', E);
    If K = 0 Then
    Begin
      Item := E;
      E := '';
    End
    Else
    Begin
      Item := Copy(E, 1, K - 1);
      E := Copy(E, K + 1, 250);
    End;
    If Copy(Item, 1, 1) = '!' Then Delete(Item, 1, 1);
    If Item = 'all' Then
    Begin
      FiltOn := False;
      Exit;
    End;
    AddFilter(Item);
  End;
End;

{ --- processus suivis --- }

Function Slot(Pid : LongInt) : LongInt;
Var K : LongInt;
Begin
  For K := 0 To MaxP - 1 Do
    If TP[K] = Pid Then
    Begin
      Slot := K;
      Exit;
    End;
  Slot := -1;
End;

Function NewSlot(Pid : LongInt) : LongInt;
Var K : LongInt;
Begin
  NewSlot := -1;
  For K := 0 To MaxP - 1 Do
    If TP[K] = 0 Then
    Begin
      TP[K] := Pid;
      TIn[K] := True;
      TFresh[K] := True;
      TSkip[K] := False;
      TNr[K] := -1;
      Inc(Seen);
      NewSlot := K;
      Exit;
    End;
End;

Function Alive : LongInt;
Var K, N : LongInt;
Begin
  N := 0;
  For K := 0 To MaxP - 1 Do
    If TP[K] <> 0 Then Inc(N);
  Alive := N;
End;

Procedure Pfx(Pid : LongInt);
Begin
  If Follow Then
    If OutFd = 2 Then Emit('[pid ' + Pad(NumS(Pid), 5) + '] ')
    Else Emit(NumS(Pid) + ' ');
End;

Procedure Ptr(Req, Pid, Addr, Data : LongInt);
Begin
  SysCall(26, Req, Pid, Addr, Data, 0);
End;

{ entree dans un appel systeme }
Procedure SysEntry(S : LongInt);
Var Nr, I, N : LongInt; Sp : String; C : Char;
Begin
  Nr := Rg[11];
  If TSkip[S] Then
    If Nr = 11 Then TSkip[S] := False
    Else
    Begin
      TNr[S] := -1;
      Exit;
    End;
  TNr[S] := Nr;
  If CountOnly Then TT0[S] := NowUs;
  If TimeEach Then TT0[S] := NowUs;
  Sp := ScSpec(Nr);
  N := ArgCount(Sp);
  For I := 0 To 5 Do TV[S * 6 + I] := Rg[I];
  If Sp = '?' Then
  Begin
    N := 6;
    While (N > 0) And (Rg[N - 1] = 0) Do Dec(N);
  End;
  For I := 0 To N - 1 Do
  Begin
    C := LetterAt(Sp, I);
    If Sp = '?' Then C := 'x';
    If IsOut(C) Then TArg[S * 6 + I] := ''
    Else
      TArg[S * 6 + I] := InArg(C, Rg[I], TP[S], Nr, Rg[I + 1]);
  End;
  { appels qui ne reviennent pas : on les imprime tout de suite }
  If (ScName(Nr) = 'exit_group') Or (ScName(Nr) = 'exit') Then
  Begin
    If Traced(Nr) And (Not CountOnly) Then
    Begin
      Pfx(TP[S]);
      Emit(ScName(Nr) + '(' + TArg[S * 6] + ') = ?' + #10);
      Flush;
    End;
    TNr[S] := -1;
  End;
End;

Function IsPtrRet(Const Nm : String) : Boolean;
Begin
  IsPtrRet := (Nm = 'mmap') Or (Nm = 'mmap2') Or (Nm = 'brk') Or
              (Nm = 'mremap') Or (Nm = 'shmat');
End;

Procedure SysExitStop(S : LongInt);
Var Nr, I, N, Ret, T1 : LongInt; Sp, Nm, L : String; C : Char; Err : Boolean;
Begin
  Nr := TNr[S];
  If Nr < 0 Then Exit;
  Ret := Rg[6];
  Err := (Ret < 0) And (Ret > -4096);
  If CountOnly Then
  Begin
    If (Nr >= 0) And (Nr <= ScMax) Then
    Begin
      Inc(CCnt[Nr]);
      If Err Then Inc(CErr[Nr]);
      CTim[Nr] := CTim[Nr] + (NowUs - TT0[S]);
    End;
    Exit;
  End;
  If Not Traced(Nr) Then Exit;
  Nm := ScName(Nr);
  Sp := ScSpec(Nr);
  N := ArgCount(Sp);
  If Sp = '?' Then
  Begin
    N := 6;
    While (N > 0) And (TV[S * 6 + N - 1] = 0) Do Dec(N);
  End;
  Pfx(TP[S]);
  Emit(Nm + '(');
  For I := 0 To N - 1 Do
  Begin
    C := LetterAt(Sp, I);
    If (C = 'm') And (I > 0) And (LetterAt(Sp, I - 1) = 'o') And
       ((TV[S * 6 + I - 1] And $40) = 0) Then Break;
    If I > 0 Then Emit(', ');
    If (Sp <> '?') And IsOut(C) Then
      Emit(OutArg(C, TV[S * 6 + I], TP[S], Nr, Ret, TV[S * 6 + I + 1]))
    Else Emit(TArg[S * 6 + I]);
  End;
  Emit(') = ');
  If (Ret <= -512) And (Ret >= -516) Then Emit('? ERESTARTSYS')
  Else If Err Then
    Emit('-1 ' + ErrName(-Ret) + ' (' + SysErrorText(-Ret) + ')')
  Else If IsPtrRet(Nm) Then Emit(Hex(Ret))
  Else Emit(NumS(Ret));
  If TimeEach Then
  Begin
    T1 := NowUs - TT0[S];
    Emit(' <0.' + Copy(NumS(1000000 + T1), 2, 6) + '>');
  End;
  Emit(#10);
  Flush;
End;

Function CodeName(Sig, Code : LongInt) : String;
Begin
  CodeName := NumS(Code);
  If Code = 0 Then CodeName := 'SI_USER'
  Else If Code = -1 Then CodeName := 'SI_QUEUE'
  Else If Code = -2 Then CodeName := 'SI_TIMER'
  Else If Code = -6 Then CodeName := 'SI_TKILL'
  Else If Code = $80 Then CodeName := 'SI_KERNEL'
  Else If Sig = 17 Then
  Begin
    Case Code Of
      1 : CodeName := 'CLD_EXITED';
      2 : CodeName := 'CLD_KILLED';
      3 : CodeName := 'CLD_DUMPED';
      4 : CodeName := 'CLD_TRAPPED';
      5 : CodeName := 'CLD_STOPPED';
      6 : CodeName := 'CLD_CONTINUED';
    End;
  End
  Else If (Sig = 11) Or (Sig = 7) Then
  Begin
    If Code = 1 Then CodeName := 'SEGV_MAPERR'
    Else If Code = 2 Then CodeName := 'SEGV_ACCERR';
  End;
End;

Procedure ShowSignal(Pid, Sig : LongInt);
Var SI : Array[0..31] Of LongInt; S, Cd : LongInt; L : String;
Begin
  For S := 0 To 31 Do SI[S] := 0;
  S := SysCall(26, PtGetSigInfo, Pid, 0, LongInt(@SI), 0);
  If CountOnly Then Exit;
  Pfx(Pid);
  Cd := SI[2];
  L := '--- ' + SigName(Sig) + ' {si_signo=' + SigName(Sig) + ', si_code=' +
       CodeName(Sig, Cd);
  If S < 0 Then L := L + '}'
  Else If Sig = 17 Then
    L := L + ', si_pid=' + NumS(SI[3]) + ', si_uid=' + NumS(SI[4]) +
         ', si_status=' + NumS(SI[5]) + ', si_utime=' + NumS(SI[6]) +
         ', si_stime=' + NumS(SI[7]) + '}'
  Else If (Sig = 11) Or (Sig = 7) Or (Sig = 4) Or (Sig = 8) Then
    L := L + ', si_addr=' + PtrS(SI[3]) + '}'
  Else If Cd <= 0 Then
    L := L + ', si_pid=' + NumS(SI[3]) + ', si_uid=' + NumS(SI[4]) + '}'
  Else L := L + '}';
  Emit(L + ' ---' + #10);
  Flush;
End;

Procedure Summary;
Var K, Tot, Cn, Ce : LongInt; Pc, Us : LongInt; L : String;
Begin
  Tot := 0;
  Cn := 0;
  Ce := 0;
  For K := 0 To ScMax Do
  Begin
    Tot := Tot + CTim[K];
    Cn := Cn + CCnt[K];
    Ce := Ce + CErr[K];
  End;
  If Cn = 0 Then Exit;
  Emit('% time     seconds  usecs/call     calls    errors syscall' + #10);
  Emit('------ ----------- ----------- --------- --------- ' +
       '----------------' + #10);
  For K := 0 To ScMax Do
    If CCnt[K] > 0 Then
    Begin
      If Tot > 0 Then Pc := (CTim[K] * 100) Div Tot Else Pc := 0;
      Us := CTim[K] Div CCnt[K];
      L := Pad(NumS(Pc) + '.' + Copy(NumS(100 + ((CTim[K] * 10000) Div
           (Tot + 1)) Mod 100), 2, 2), 6) + ' ' +
           Pad(NumS(CTim[K] Div 1000000) + '.' + Copy(NumS(1000000 +
           CTim[K] Mod 1000000), 2, 6), 11) + ' ' + Pad(NumS(Us), 11) + ' ' +
           Pad(NumS(CCnt[K]), 9) + ' ';
      If CErr[K] > 0 Then L := L + Pad(NumS(CErr[K]), 9) + ' '
      Else L := L + '          ';
      Emit(L + ScName(K) + #10);
    End;
  Emit('------ ----------- ----------- --------- --------- ' +
       '----------------' + #10);
  Emit(Pad('100.00', 6) + ' ' + Pad(NumS(Tot Div 1000000) + '.' +
       Copy(NumS(1000000 + Tot Mod 1000000), 2, 6), 11) + ' ' +
       Pad('', 11) + ' ' + Pad(NumS(Cn), 9) + ' ' + Pad(NumS(Ce), 9) +
       ' total' + #10);
  Flush;
End;

Procedure SetOpts(Pid : LongInt);
Var O : LongInt;
Begin
  O := 1 Or $10 Or $100000;
  If Follow Then O := O Or 2 Or 4 Or 8;
  Ptr(PtSetOptions, Pid, 0, O);
End;

Function FindExe(Const Name : String) : String;
Var Path, Dir : String; K : LongInt;
Begin
  FindExe := Name;
  If Pos('/', Name) > 0 Then Exit;
  Path := SysGetEnv('PATH');
  If Path = '' Then Path := '/bin:/usr/bin:/sbin:/usr/sbin';
  While Path <> '' Do
  Begin
    K := Pos(':', Path);
    If K = 0 Then
    Begin
      Dir := Path;
      Path := '';
    End
    Else
    Begin
      Dir := Copy(Path, 1, K - 1);
      Path := Copy(Path, K + 1, 255);
    End;
    If SysAccess(Dir + '/' + Name, 1) = 0 Then
    Begin
      FindExe := Dir + '/' + Name;
      Exit;
    End;
  End;
End;

Procedure Die(Const S : String);
Begin
  SysPut(2, 'strace: ' + S + #10);
  SysExit(1);
End;

Procedure Usage;
Begin
  SysPut(2, 'Usage: strace [-fcqT] [-s N] [-o file] [-e expr] ' +
         '[-p pid]... [command [args...]]' + #10);
  SysExit(1);
End;

Var
  I, J, K, Pid, St, S, Sig, Ev, NAtt, Ex : LongInt;
  A, Val : String;
  Cmd : LongInt;
  Att : Array[0..15] Of LongInt;
  Path : String;
  Msg : LongInt;
  C : Char;
  Info : Array[0..15] Of LongInt;
Begin
  OutFd := 2;
  OLen := 0;
  StrSz := 32;
  Follow := False;
  CountOnly := False;
  Quiet := False;
  TimeEach := False;
  FiltOn := False;
  FiltNeg := False;
  NAtt := 0;
  Seen := 0;
  FirstPid := 0;
  FirstStatus := 0;
  For I := 0 To MaxP - 1 Do TP[I] := 0;
  LnxSys3(78, LongInt(@LnxTmp), 0, 0);
  TBase := LnxTmp[0];
  For I := 0 To ScMax Do
  Begin
    Filt[I] := False;
    CCnt[I] := 0;
    CErr[I] := 0;
    CTim[I] := 0;
  End;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (Length(A) < 2) Or (A[1] <> '-') Then Break;
    If A = '--' Then
    Begin
      Inc(I);
      Break;
    End;
    J := 2;
    While J <= Length(A) Do
    Begin
      C := A[J];
      Inc(J);
      If (C = 'o') Or (C = 'e') Or (C = 's') Or (C = 'p') Then
      Begin
        If J <= Length(A) Then Val := Copy(A, J, 255)
        Else
        Begin
          Inc(I);
          If I >= SysArgCount Then Usage;
          Val := SysArgStr(I);
        End;
        J := Length(A) + 1;
        If C = 'o' Then
        Begin
          OutFd := SysOpen(Val, $241, 420);
          If OutFd < 0 Then Die(Val + ': ' + SysErrorText(SysErrno));
        End
        Else If C = 'e' Then ParseExpr(Val)
        Else If C = 's' Then
        Begin
          StrSz := 0;
          For K := 1 To Length(Val) Do
            StrSz := StrSz * 10 + Ord(Val[K]) - 48;
          If StrSz > 100 Then StrSz := 100;
        End
        Else
        Begin
          If NAtt < 16 Then
          Begin
            Att[NAtt] := 0;
            For K := 1 To Length(Val) Do
              Att[NAtt] := Att[NAtt] * 10 + Ord(Val[K]) - 48;
            Inc(NAtt);
          End;
        End;
      End
      Else If (C = 'f') Then Follow := True
      Else If C = 'c' Then CountOnly := True
      Else If C = 'q' Then Quiet := True
      Else If C = 'T' Then TimeEach := True
      Else If (C = 'v') Or (C = 'x') Or (C = 'i') Or (C = 'y') Or
              (C = 'F') Then
      Begin
      End
      Else If C = 'h' Then Usage
      Else Usage;
    End;
    Inc(I);
  End;
  If (I >= SysArgCount) And (NAtt = 0) Then Usage;
  If I < SysArgCount Then
  Begin
    Path := FindExe(SysArgStr(I));
    If SysAccess(Path, 1) <> 0 Then
      Die('Cannot find executable ''' + SysArgStr(I) + '''');
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      Ptr(PtTraceMe, 0, 0, 0);
      SysKill(SysGetPid, 19);
      SysArgReset;
      For K := I To SysArgCount - 1 Do SysArgAdd(SysArgStr(K));
      LnxXArg[LnxXArgN] := 0;
      SysExecve(Path, LongInt(@LnxXArg), SysEnvp);
      SysPut(2, 'strace: ' + Path + ': ' + SysErrorText(SysErrno) + #10);
      SysExit(127);
    End;
    SysWaitPid(Pid, St, WAll);
    S := NewSlot(Pid);
    TFresh[S] := False;
    TIn[S] := False;
    FirstPid := Pid;
    TSkip[S] := True;
    SetOpts(Pid);
    Ptr(PtSyscall, Pid, 0, 0);
  End;
  For K := 0 To NAtt - 1 Do
  Begin
    If SysCall(26, PtAttach, Att[K], 0, 0, 0) < 0 Then
    Begin
      SysPut(2, 'strace: attach: ptrace(PTRACE_ATTACH, ' + NumS(Att[K]) +
             '): ' + SysErrorText(SysErrno) + #10);
      Continue;
    End;
    SysWaitPid(Att[K], St, WAll);
    S := NewSlot(Att[K]);
    TFresh[S] := False;
    TIn[S] := False;
    SetOpts(Att[K]);
    If Not Quiet Then
    Begin
      Emit('strace: Process ' + NumS(Att[K]) + ' attached' + #10);
      Flush;
    End;
    Ptr(PtSyscall, Att[K], 0, 0);
  End;
  While Alive > 0 Do
  Begin
    Pid := SysWaitPid(-1, St, WAll);
    If Pid < 0 Then Break;
    S := Slot(Pid);
    If S < 0 Then
    Begin
      S := NewSlot(Pid);
      If S < 0 Then Continue;
    End;
    If (St And $7F) = 0 Then
    Begin
      If (Pid = FirstPid) Then FirstStatus := St;
      If (Not CountOnly) And (Not Quiet) Then
      Begin
        Pfx(Pid);
        Emit('+++ exited with ' + NumS((St Shr 8) And 255) + ' +++' + #10);
        Flush;
      End;
      TP[S] := 0;
      Continue;
    End;
    If (St And $FF) <> $7F Then
    Begin
      If (Pid = FirstPid) Then FirstStatus := St;
      If (Not CountOnly) And (Not Quiet) Then
      Begin
        Pfx(Pid);
        Emit('+++ killed by ' + SigName(St And $7F));
        If (St And $80) <> 0 Then Emit(' (core dumped)');
        Emit(' +++' + #10);
        Flush;
      End;
      TP[S] := 0;
      Continue;
    End;
    Sig := (St Shr 8) And 255;
    Ev := (St Shr 16) And 255;
    If Sig = (5 Or $80) Then
    Begin
      SysCall(26, PtGetRegs, Pid, 0, LongInt(@Rg), 0);
      For I := 0 To 15 Do Info[I] := 0;
      If SysCall(26, $420E, Pid, 64, LongInt(@Info), 0) > 0 Then
      Begin
        If (Info[0] And 255) = 1 Then TIn[S] := False;
        If (Info[0] And 255) = 2 Then TIn[S] := True;
      End;
      If Not TIn[S] Then
      Begin
        TIn[S] := True;
        SysEntry(S);
      End
      Else
      Begin
        TIn[S] := False;
        SysExitStop(S);
      End;
      Ptr(PtSyscall, Pid, 0, 0);
    End
    Else If (Sig = 5) And (Ev <> 0) Then
    Begin
      If (Ev = 1) Or (Ev = 2) Or (Ev = 3) Then
      Begin
        SysCall(26, PtGetEventMsg, Pid, 0, LongInt(@Msg), 0);
        If Slot(Msg) < 0 Then NewSlot(Msg);
      End;
      Ptr(PtSyscall, Pid, 0, 0);
    End
    Else If (Sig = 19) And TFresh[S] Then
    Begin
      TFresh[S] := False;
      Ptr(PtSyscall, Pid, 0, 0);
    End
    Else
    Begin
      TFresh[S] := False;
      ShowSignal(Pid, Sig);
      Ptr(PtSyscall, Pid, 0, Sig);
    End;
  End;
  If CountOnly Then Summary;
  Flush;
  If FirstPid <> 0 Then
  Begin
    If (FirstStatus And $7F) = 0 Then SysExit((FirstStatus Shr 8) And 255);
    SysSignal(FirstStatus And $7F, 0);
    SysKill(SysGetPid, FirstStatus And $7F);
    SysExit(128 + (FirstStatus And $7F));
  End;
  SysExit(0);
End.
