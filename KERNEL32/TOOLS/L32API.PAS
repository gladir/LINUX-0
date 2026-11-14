{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: Couche systeme Linux i386 des programmes compiles avec
    LPC -3X : fonctions de style Win32 appelees par le runtime Pascal
    (WriteFile, CreateFileA, FindFirstFileA...) realisees par des appels
    systeme Linux (INT 80h). Ce source est integre dans LPC32.PAS par
    MKAPI.PAS (ne pas le compiler seul) et insere au debut des
    declarations de chaque programme -3X.
}

{ Convention du compilateur : les parametres sont des LongInt (les pointeurs
  sont des adresses lineaires) ; le compilateur relie chaque fonction a la
  fonction Pascal du meme nom (couche API) ; une API non ecrite ici appelle
  ApiMissing. }

Const
  LnxEPERM = 1;
  LnxENOENT = 2;

Var
  LnxArgc    : LongInt;       { nombre d'arguments (argv[0] compris) }
  LnxArgv    : LongInt;       { adresse du tableau argv }
  LnxEnvp    : LongInt;       { adresse du tableau envp }
  LnxErrno   : LongInt;       { derniere erreur (GetLastError) }
  LnxHeapLo  : LongInt;       { debut du tas (brk initial) }
  LnxHeapTop : LongInt;       { fin courante du tas }
  LnxFree    : LongInt;       { liste des blocs libres }
  LnxCmdLine : Array[0..1023] Of Char;
  LnxCmdDone : LongInt;
  LnxEnvBlk  : LongInt;       { bloc d'environnement style Win32 }
  LnxStat    : Array[0..31] Of LongInt;   { struct stat (128 octets) }
  LnxTmp     : Array[0..15] Of LongInt;

{ ---------- appels systeme ---------- }

Function LnxSys3(N, A, B, C : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    push ebx
    mov eax, N
    mov ebx, A
    mov ecx, B
    mov edx, C
    int 80h
    pop ebx
    mov R, eax
  end;
  LnxSys3 := R;
End;

Function LnxSys6(N, A, B, C, D, E, F : LongInt) : LongInt;
Var R : LongInt;
Begin
  asm
    push ebx
    push esi
    push edi
    push ebp
    mov eax, N
    mov ebx, A
    mov ecx, B
    mov edx, C
    mov esi, D
    mov edi, E
    mov ebp, F
    int 80h
    pop ebp
    pop edi
    pop esi
    pop ebx
    mov R, eax
  end;
  LnxSys6 := R;
End;

{ errno Linux -> code d'erreur Win32 (celui que le runtime traduit en
  IOResult de Turbo Pascal) }
Function LnxWinErr(E : LongInt) : LongInt;
Begin
  Case E Of
    2  : LnxWinErr := 2;       { ENOENT }
    20 : LnxWinErr := 3;       { ENOTDIR }
    1, 13, 21, 26 : LnxWinErr := 5;   { EPERM EACCES EISDIR ETXTBSY }
    9  : LnxWinErr := 6;       { EBADF }
    12 : LnxWinErr := 8;       { ENOMEM }
    24, 23 : LnxWinErr := 4;   { EMFILE ENFILE }
    17 : LnxWinErr := 80;      { EEXIST }
    22 : LnxWinErr := 87;      { EINVAL }
    28 : LnxWinErr := 112;     { ENOSPC }
    39 : LnxWinErr := 145;     { ENOTEMPTY }
    30 : LnxWinErr := 19;      { EROFS }
    18 : LnxWinErr := 17;      { EXDEV }
    36 : LnxWinErr := 206;     { ENAMETOOLONG }
  Else
    LnxWinErr := 31;
  End;
End;

{ resultat d'appel systeme -> valeur Win32 (erreur : memorise le code) }
Function LnxCheck(R : LongInt) : LongInt;
Begin
  If (R < 0) And (R > -4096) Then
  Begin
    LnxErrno := LnxWinErr(-R);
    LnxCheck := -1;
  End
  Else LnxCheck := R;
End;

{ copie / remplissage d'octets (adresses lineaires) }
Procedure LnxMove(Src, Dst, N : LongInt);
Begin
  asm
    push esi
    push edi
    mov esi, Src
    mov edi, Dst
    mov ecx, N
    cld
    rep movsb
    pop edi
    pop esi
  end;
End;

Procedure LnxFill(Dst, N, B : LongInt);
Begin
  asm
    push edi
    mov edi, Dst
    mov ecx, N
    mov eax, B
    cld
    rep stosb
    pop edi
  end;
End;

{ chemins : les programmes ecrits pour DOS emploient \ comme separateur ;
  copie dans un tampon tournant avec \ remplace par / }
Var
  LnxPathBuf : Array[0..4095] Of Byte;
  LnxPathNo  : LongInt;

Function LnxPath(P : LongInt) : LongInt;
Var Dst, K, C : LongInt;
Begin
  If P = 0 Then
  Begin
    LnxPath := 0;
    Exit;
  End;
  Dst := LongInt(@LnxPathBuf) + (LnxPathNo And 3) * 1024;
  Inc(LnxPathNo);
  K := 0;
  While K < 1022 Do
  Begin
    C := Mem[0:P + K];
    If C = 92 Then C := 47;
    Mem[0:Dst + K] := C;
    If C = 0 Then Break;
    Inc(K);
  End;
  Mem[0:Dst + K] := 0;
  LnxPath := Dst;
End;

{ ---------- processus ---------- }

Procedure LnxRawOff; Forward;

Procedure ExitProcess(Code : LongInt);
Begin
  LnxRawOff;
  LnxSys3(252, Code, 0, 0);
  LnxSys3(1, Code, 0, 0);
End;

Procedure LnxInitTail; Forward;

Procedure LnxStart; Boot;
Begin
  asm
    cld
    mov eax, [esp]
    mov LnxArgc, eax
    lea ebx, [esp+4]
    mov LnxArgv, ebx
    lea ecx, [ebx+eax*4+4]
    mov LnxEnvp, ecx
    and esp, 0FFFFFFF0h
    xor ebp, ebp
    call LnxInitTail
    call Main
    mov eax, 1
    xor ebx, ebx
    int 80h
  end;
End;

Procedure ApiMissing(Name : LongInt);
Var K : LongInt; C : Char;
Begin
  LnxSys3(4, 2, LongInt(@LnxTmp), 0);
  K := 0;
  While Mem[0:Name + K] <> 0 Do Inc(K);
  LnxSys3(4, 2, Name, K);
  LnxTmp[0] := $0A2E;       { ".\n" }
  LnxSys3(4, 2, LongInt(@LnxTmp), 2);
  ExitProcess(255);
End;

Function GetLastError : LongInt;
Begin
  GetLastError := LnxErrno;
End;

Function GetVersion : LongInt;
Begin
  GetVersion := $0A000000;
End;

Function SetUnhandledExceptionFilter(F : LongInt) : LongInt;
Begin
  SetUnhandledExceptionFilter := 0;
End;

Function GetStdHandle(N : LongInt) : LongInt;
Begin
  Case N Of
    -10 : GetStdHandle := 0;
    -11 : GetStdHandle := 1;
    -12 : GetStdHandle := 2;
  Else
    GetStdHandle := -1;
  End;
End;

Function SetStdHandle(N, H : LongInt) : LongInt;
Begin
  SetStdHandle := 1;
  If (N = -11) And (H <> 1) Then LnxSys3(63, H, 1, 0);
  If (N = -10) And (H <> 0) Then LnxSys3(63, H, 0, 0);
  If (N = -12) And (H <> 2) Then LnxSys3(63, H, 2, 0);
End;

{ ---------- tas (brk) ---------- }
{ Bloc : [taille (4)] [suivant libre (4)] puis les donnees ; l'adresse
  rendue est celle des donnees. }

Function LnxGrow(Bytes : LongInt) : LongInt;
Var Cur, Want, R : LongInt;
Begin
  LnxGrow := 0;
  If LnxHeapLo = 0 Then
  Begin
    LnxHeapLo := LnxSys3(45, 0, 0, 0);
    LnxHeapTop := LnxHeapLo;
  End;
  Cur := LnxHeapTop;
  Want := Cur + Bytes;
  R := LnxSys3(45, Want, 0, 0);
  If R < Want Then Exit;
  LnxHeapTop := Want;
  LnxGrow := Cur;
End;

Function GetProcessHeap : LongInt;
Begin
  GetProcessHeap := 1;
End;

Function HeapAlloc(Heap, Flags, Size : LongInt) : LongInt;
Var
  Need, P, Prev, Sz, A : LongInt;
Begin
  HeapAlloc := 0;
  If Size < 0 Then Exit;
  Need := (Size + 7) And LongInt($FFFFFFF8);
  If Need < 8 Then Need := 8;
  { premier bloc libre assez grand }
  Prev := 0;
  P := LnxFree;
  While P <> 0 Do
  Begin
    Sz := MemL[0:P];
    If Sz >= Need Then
    Begin
      If Prev = 0 Then LnxFree := MemL[0:P + 4]
      Else MemL[0:Prev + 4] := MemL[0:P + 4];
      A := P + 8;
      If (Flags And 8) <> 0 Then LnxFill(A, Sz, 0);
      HeapAlloc := A;
      Exit;
    End;
    Prev := P;
    P := MemL[0:P + 4];
  End;
  P := LnxGrow(Need + 8);
  If P = 0 Then Exit;
  MemL[0:P] := Need;
  A := P + 8;
  If (Flags And 8) <> 0 Then LnxFill(A, Need, 0);
  HeapAlloc := A;
End;

Function HeapFree(Heap, Flags, A : LongInt) : LongInt;
Var P : LongInt;
Begin
  HeapFree := 1;
  If A = 0 Then Exit;
  P := A - 8;
  MemL[0:P + 4] := LnxFree;
  LnxFree := P;
End;

Function HeapSize(Heap, Flags, A : LongInt) : LongInt;
Begin
  If A = 0 Then HeapSize := 0 Else HeapSize := MemL[0:A - 8];
End;

{ ---------- fichiers ---------- }

Function CloseHandle(H : LongInt) : LongInt;
Begin
  If H < 3 Then
  Begin
    CloseHandle := 1;
    Exit;
  End;
  If LnxCheck(LnxSys3(6, H, 0, 0)) < 0 Then CloseHandle := 0 Else
      CloseHandle := 1;
End;

{ Access : 80000000h lecture, 40000000h ecriture ; Disp : 1 CREATE_NEW,
  2 CREATE_ALWAYS, 3 OPEN_EXISTING, 4 OPEN_ALWAYS, 5 TRUNCATE_EXISTING }
Function CreateFileA(PName, Access, Share, Sec, Disp, Flags, Templ : LongInt)
    : LongInt;
Var Fl, R : LongInt;
Begin
  If (Access And $40000000) <> 0 Then
  Begin
    If (Access And LongInt($80000000)) <> 0 Then Fl := 2 Else Fl := 1;
  End
  Else Fl := 0;
  Case Disp Of
    1 : Fl := Fl Or $C0;       { O_CREAT | O_EXCL }
    2 : Fl := Fl Or $240;      { O_CREAT | O_TRUNC }
    4 : Fl := Fl Or $40;       { O_CREAT }
    5 : Fl := Fl Or $200;      { O_TRUNC }
  End;
  R := LnxCheck(LnxSys3(5, LnxPath(PName), Fl, $1B6));
  CreateFileA := R;
End;

Function ReadFile(H, Buf, N, PRead, Ovl : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := LnxCheck(LnxSys3(3, H, Buf, N));
  If R < 0 Then
  Begin
    ReadFile := 0;
    If PRead <> 0 Then MemL[0:PRead] := 0;
    Exit;
  End;
  If PRead <> 0 Then MemL[0:PRead] := R;
  ReadFile := 1;
End;

Procedure LnxTrack(Buf, N : LongInt); Forward;

Function WriteFile(H, Buf, N, PWritten, Ovl : LongInt) : LongInt;
Var R, Done : LongInt;
Begin
  If (H = 1) Or (H = 2) Then LnxTrack(Buf, N);
  Done := 0;
  While Done < N Do
  Begin
    R := LnxSys3(4, H, Buf + Done, N - Done);
    If R <= 0 Then
    Begin
      If R < 0 Then LnxErrno := LnxWinErr(-R);
      If PWritten <> 0 Then MemL[0:PWritten] := Done;
      WriteFile := 0;
      Exit;
    End;
    Done := Done + R;
  End;
  If PWritten <> 0 Then MemL[0:PWritten] := Done;
  WriteFile := 1;
End;

Function WriteConsoleA(H, Buf, N, PWritten, Res : LongInt) : LongInt;
Begin
  WriteConsoleA := WriteFile(H, Buf, N, PWritten, 0);
End;

Function SetFilePointer(H, Dist, PHigh, Method : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := LnxSys3(19, H, Dist, Method);
  If (R < 0) And (R > -4096) Then
  Begin
    LnxErrno := LnxWinErr(-R);
    SetFilePointer := -1;
  End
  Else SetFilePointer := R;
End;

Function GetFileSize(H, PHigh : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := LnxSys3(108, H, LongInt(@LnxStat), 0);
  If R < 0 Then GetFileSize := -1 Else GetFileSize := LnxStat[5];
End;

{ ---------- ligne de commande et environnement ---------- }

Function GetCommandLineA : LongInt;
Var I, J, K, A, Len : LongInt; Q : Boolean;
Begin
  If LnxCmdDone = 0 Then
  Begin
    LnxCmdDone := 1;
    K := 0;
    For I := 0 To LnxArgc - 1 Do
    Begin
      A := MemL[0:LnxArgv + I * 4];
      Q := False;
      Len := 0;
      While Mem[0:A + Len] <> 0 Do
      Begin
        If (Mem[0:A + Len] = 32) Or (Mem[0:A + Len] = 9) Then Q := True;
        Inc(Len);
      End;
      If (Len = 0) Then Q := True;
      If K + Len + 4 >= 1023 Then Break;
      If I > 0 Then Begin LnxCmdLine[K] := ' '; Inc(K); End;
      If Q Then Begin LnxCmdLine[K] := '"'; Inc(K); End;
      For J := 0 To Len - 1 Do
      Begin
        LnxCmdLine[K] := Chr(Mem[0:A + J]);
        Inc(K);
      End;
      If Q Then Begin LnxCmdLine[K] := '"'; Inc(K); End;
    End;
    LnxCmdLine[K] := #0;
  End;
  GetCommandLineA := LongInt(@LnxCmdLine);
End;

Function GetEnvironmentStringsA : LongInt;
Var I, K, A, P, Total : LongInt;
Begin
  If LnxEnvBlk = 0 Then
  Begin
    Total := 2;
    I := 0;
    While MemL[0:LnxEnvp + I * 4] <> 0 Do
    Begin
      A := MemL[0:LnxEnvp + I * 4];
      K := 0;
      While Mem[0:A + K] <> 0 Do Inc(K);
      Total := Total + K + 1;
      Inc(I);
    End;
    LnxEnvBlk := HeapAlloc(1, 8, Total);
    P := LnxEnvBlk;
    I := 0;
    While MemL[0:LnxEnvp + I * 4] <> 0 Do
    Begin
      A := MemL[0:LnxEnvp + I * 4];
      K := 0;
      While Mem[0:A + K] <> 0 Do
      Begin
        Mem[0:P] := Mem[0:A + K];
        Inc(P); Inc(K);
      End;
      Mem[0:P] := 0;
      Inc(P);
      Inc(I);
    End;
    Mem[0:P] := 0;
  End;
  GetEnvironmentStringsA := LnxEnvBlk;
End;

Function GetEnvironmentVariableA(Name, Buf, Size : LongInt) : LongInt;
Var I, A, K, L : LongInt; Ok : Boolean;
Begin
  GetEnvironmentVariableA := 0;
  L := 0;
  While Mem[0:Name + L] <> 0 Do Inc(L);
  I := 0;
  While MemL[0:LnxEnvp + I * 4] <> 0 Do
  Begin
    A := MemL[0:LnxEnvp + I * 4];
    Ok := True;
    For K := 0 To L - 1 Do
      If Mem[0:A + K] <> Mem[0:Name + K] Then Ok := False;
    If Ok And (Mem[0:A + L] = 61) Then
    Begin
      A := A + L + 1;
      K := 0;
      While Mem[0:A + K] <> 0 Do Inc(K);
      If K + 1 <= Size Then
      Begin
        LnxMove(A, Buf, K + 1);
        GetEnvironmentVariableA := K;
      End
      Else GetEnvironmentVariableA := K + 1;
      Exit;
    End;
    Inc(I);
  End;
End;

{ ---------- chaines ASCIIZ (adresses lineaires) ---------- }

Function LnxLen(P : LongInt) : LongInt;
Var K : LongInt;
Begin
  K := 0;
  While Mem[0:P + K] <> 0 Do Inc(K);
  LnxLen := K;
End;

Procedure LnxCopyZ(Dst, Src : LongInt);
Begin
  LnxMove(Src, Dst, LnxLen(Src) + 1);
End;

Function lstrlenA(P : LongInt) : LongInt;
Begin
  lstrlenA := LnxLen(P);
End;

Function lstrcpyA(Dst, Src : LongInt) : LongInt;
Begin
  LnxCopyZ(Dst, Src);
  lstrcpyA := Dst;
End;

Function lstrcatA(Dst, Src : LongInt) : LongInt;
Begin
  LnxCopyZ(Dst + LnxLen(Dst), Src);
  lstrcatA := Dst;
End;

Function LnxUp(C : LongInt) : LongInt;
Begin
  If (C >= 97) And (C <= 122) Then LnxUp := C - 32 Else LnxUp := C;
End;

Function lstrcmpA(A, B : LongInt) : LongInt;
Var K, X, Y : LongInt;
Begin
  K := 0;
  Repeat
    X := Mem[0:A + K];
    Y := Mem[0:B + K];
    Inc(K);
  Until (X <> Y) Or (X = 0);
  lstrcmpA := X - Y;
End;

Function lstrcmpiA(A, B : LongInt) : LongInt;
Var K, X, Y : LongInt;
Begin
  K := 0;
  Repeat
    X := LnxUp(Mem[0:A + K]);
    Y := LnxUp(Mem[0:B + K]);
    Inc(K);
  Until (X <> Y) Or (X = 0);
  lstrcmpiA := X - Y;
End;

{ ---------- date et heure ---------- }

{ jours depuis 1970 -> annee, mois, jour (calendrier gregorien) }
Procedure LnxCivil(Days : LongInt; Var Y, M, D : LongInt);
Var Z, Era, Doe, Yoe, Doy, Mp : LongInt;
Begin
  Z := Days + 719468;
  If Z >= 0 Then Era := Z Div 146097 Else Era := (Z - 146096) Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  D := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then M := Mp + 3 Else M := Mp - 9;
  If M <= 2 Then Inc(Y);
End;

Function LnxDaysFromCivil(Y, M, D : LongInt) : LongInt;
Var Era, Yoe, Doy, Doe : LongInt;
Begin
  If M <= 2 Then Dec(Y);
  If Y >= 0 Then Era := Y Div 400 Else Era := (Y - 399) Div 400;
  Yoe := Y - Era * 400;
  If M > 2 Then Doy := (153 * (M - 3) + 2) Div 5 + D - 1
  Else Doy := (153 * (M + 9) + 2) Div 5 + D - 1;
  Doe := Yoe * 365 + Yoe Div 4 - Yoe Div 100 + Doy;
  LnxDaysFromCivil := Era * 146097 + Doe - 719468;
End;

{ secondes Unix -> date et heure DOS (UTC) }
Function LnxToDos(T : LongInt) : LongInt;
Var Days, Secs, Y, M, D : LongInt;
Begin
  If T < 0 Then T := 0;
  Days := T Div 86400;
  Secs := T Mod 86400;
  LnxCivil(Days, Y, M, D);
  If Y < 1980 Then
  Begin
    Y := 1980; M := 1; D := 1; Secs := 0;
  End;
  LnxToDos := (((Y - 1980) Shl 9) Or (M Shl 5) Or D) Shl 16 Or
    ((Secs Div 3600) Shl 11) Or (((Secs Mod 3600) Div 60) Shl 5)
        Or ((Secs Mod 60) Div 2);
End;

Function LnxFromDos(V : LongInt) : LongInt;
Var Dd, Tt : LongInt;
Begin
  Dd := (V Shr 16) And $FFFF;
  Tt := V And $FFFF;
  LnxFromDos := LnxDaysFromCivil(((Dd Shr 9) And 127) + 1980, (Dd Shr 5)
      And 15, Dd And 31) * 86400 +
    ((Tt Shr 11) And 31) * 3600 + ((Tt Shr 5) And 63) * 60 + (Tt And 31) * 2;
End;

Procedure GetLocalTime(P : LongInt);
Var Sec, Usec, Days, Y, M, D, Secs : LongInt;
Begin
  LnxSys3(78, LongInt(@LnxTmp), 0, 0);
  Sec := LnxTmp[0];
  Usec := LnxTmp[1];
  Days := Sec Div 86400;
  Secs := Sec Mod 86400;
  LnxCivil(Days, Y, M, D);
  MemW[0:P] := Y;
  MemW[0:P + 2] := M;
  MemW[0:P + 4] := (Days + 4) Mod 7;
  MemW[0:P + 6] := D;
  MemW[0:P + 8] := Secs Div 3600;
  MemW[0:P + 10] := (Secs Mod 3600) Div 60;
  MemW[0:P + 12] := Secs Mod 60;
  MemW[0:P + 14] := Usec Div 1000;
End;

Function SetLocalTime(P : LongInt) : LongInt;
Var T : LongInt;
Begin
  T := LnxDaysFromCivil(MemW[0:P], MemW[0:P + 2], MemW[0:P + 6]) * 86400 +
       MemW[0:P + 8] * 3600 + MemW[0:P + 10] * 60 + MemW[0:P + 12];
  LnxTmp[0] := T;
  LnxTmp[1] := 0;
  If LnxCheck(LnxSys3(79, LongInt(@LnxTmp), 0, 0)) < 0 Then SetLocalTime := 0
  Else SetLocalTime := 1;
End;

Function GetTickCount : LongInt;
Begin
  LnxSys3(78, LongInt(@LnxTmp), 0, 0);
  GetTickCount := LnxTmp[0] * 1000 + LnxTmp[1] Div 1000;
End;

Procedure Sleep(Ms : LongInt);
Begin
  LnxTmp[2] := Ms Div 1000;
  LnxTmp[3] := (Ms Mod 1000) * 1000000;
  LnxSys3(162, LongInt(@LnxTmp[2]), 0, 0);
End;

Function FileTimeToLocalFileTime(Src, Dst : LongInt) : LongInt;
Begin
  MemL[0:Dst] := MemL[0:Src];
  MemL[0:Dst + 4] := MemL[0:Src + 4];
  FileTimeToLocalFileTime := 1;
End;

Function LocalFileTimeToFileTime(Src, Dst : LongInt) : LongInt;
Begin
  MemL[0:Dst] := MemL[0:Src];
  MemL[0:Dst + 4] := MemL[0:Src + 4];
  LocalFileTimeToFileTime := 1;
End;

{ FILETIME : mot bas = date et heure DOS, mot haut = signature }
Function FileTimeToDosDateTime(Ft, PDate, PTime : LongInt) : LongInt;
Var T : LongInt;
Begin
  T := MemL[0:Ft];
  MemW[0:PDate] := (T Shr 16) And $FFFF;
  MemW[0:PTime] := T And $FFFF;
  FileTimeToDosDateTime := 1;
End;

Function DosDateTimeToFileTime(DDate, DTime, Ft : LongInt) : LongInt;
Begin
  MemL[0:Ft] := ((DDate And $FFFF) Shl 16) Or (DTime And $FFFF);
  MemL[0:Ft + 4] := $5432534F;
  DosDateTimeToFileTime := 1;
End;

{ ---------- fichiers (suite) ---------- }

Function SetEndOfFile(H : LongInt) : LongInt;
Var Pos : LongInt;
Begin
  Pos := LnxSys3(19, H, 0, 1);
  If (Pos >= 0) And (LnxCheck(LnxSys3(93, H, Pos, 0)) >= 0)
      Then SetEndOfFile := 1
  Else SetEndOfFile := 0;
End;

Function FlushFileBuffers(H : LongInt) : LongInt;
Begin
  LnxSys3(118, H, 0, 0);
  FlushFileBuffers := 1;
End;

Function GetFileTime(H, PCreate, PAccess, PWrite : LongInt) : LongInt;
Var T : LongInt;
Begin
  GetFileTime := 0;
  If LnxCheck(LnxSys3(108, H, LongInt(@LnxStat), 0)) < 0 Then Exit;
  T := LnxToDos(LnxStat[10]);
  If PWrite <> 0 Then DosDateTimeToFileTime(T Shr 16, T, PWrite);
  If PCreate <> 0 Then DosDateTimeToFileTime(T Shr 16, T, PCreate);
  If PAccess <> 0 Then DosDateTimeToFileTime(T Shr 16, T, PAccess);
  GetFileTime := 1;
End;

Function SetFileTime(H, PCreate, PAccess, PWrite : LongInt) : LongInt;
Begin
  SetFileTime := 0;
  If PWrite = 0 Then Exit;
  LnxTmp[4] := LnxFromDos(MemL[0:PWrite]);   { acces }
  LnxTmp[5] := 0;
  LnxTmp[6] := LnxTmp[4];                    { modification }
  LnxTmp[7] := 0;
  If LnxCheck(LnxSys3(320, H, 0, LongInt(@LnxTmp[4]))) >= 0 Then
      SetFileTime := 1;
End;

Function LnxAttrOf(Mode : LongInt) : LongInt;
Var A : LongInt;
Begin
  A := 0;
  If (Mode And $F000) = $4000 Then A := $10 Else A := $20;
  If (Mode And $80) = 0 Then A := A Or 1;
  LnxAttrOf := A;
End;

Function GetFileAttributesA(PName : LongInt) : LongInt;
Begin
  If LnxCheck(LnxSys3(106, LnxPath(PName), LongInt(@LnxStat), 0)) < 0 Then
    GetFileAttributesA := -1
  Else
    GetFileAttributesA := LnxAttrOf(MemW[0:LongInt(@LnxStat) + 8]);
End;

Function SetFileAttributesA(PName, Attr : LongInt) : LongInt;
Var Mode : LongInt;
Begin
  SetFileAttributesA := 0;
  If LnxCheck(LnxSys3(106, LnxPath(PName), LongInt(@LnxStat), 0)) < 0 Then Exit;
  Mode := MemW[0:LongInt(@LnxStat) + 8] And $FFF;
  If (Attr And 1) <> 0 Then Mode := Mode And (Not $92) Else Mode := Mode Or $80;
  If LnxCheck(LnxSys3(15, LnxPath(PName), Mode, 0)) >= 0 Then
      SetFileAttributesA := 1;
End;

Function DeleteFileA(PName : LongInt) : LongInt;
Begin
  If LnxCheck(LnxSys3(10, LnxPath(PName), 0, 0)) < 0 Then DeleteFileA := 0 Else
      DeleteFileA := 1;
End;

Function MoveFileA(PSrc, PDst : LongInt) : LongInt;
Begin
  If LnxCheck(LnxSys3(38, LnxPath(PSrc), LnxPath(PDst), 0)) < 0 Then
      MoveFileA := 0 Else MoveFileA := 1;
End;

Function CreateDirectoryA(PName, Sec : LongInt) : LongInt;
Begin
  If LnxCheck(LnxSys3(39, LnxPath(PName), $1FF, 0)) < 0 Then
      CreateDirectoryA := 0
  Else CreateDirectoryA := 1;
End;

Function RemoveDirectoryA(PName : LongInt) : LongInt;
Begin
  If LnxCheck(LnxSys3(40, LnxPath(PName), 0, 0)) < 0 Then RemoveDirectoryA := 0
  Else RemoveDirectoryA := 1;
End;

Function SetCurrentDirectoryA(PName : LongInt) : LongInt;
Begin
  If LnxCheck(LnxSys3(12, LnxPath(PName), 0, 0)) < 0 Then
      SetCurrentDirectoryA := 0
  Else SetCurrentDirectoryA := 1;
End;

Function GetCurrentDirectoryA(N, Buf : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := LnxSys3(183, Buf, N, 0);
  If R <= 0 Then
  Begin
    LnxErrno := 3;
    GetCurrentDirectoryA := 0;
  End
  Else GetCurrentDirectoryA := R - 1;
End;

{ chemin absolu normalise (. et .. resolus) }
Function GetFullPathNameA(PName, N, Buf, PFile : LongInt) : LongInt;
Var
  Tmp, Out, I, J, L, Start : LongInt;
  C : LongInt;
Begin
  PName := LnxPath(PName);
  Tmp := HeapAlloc(1, 0, 2048);
  If Tmp = 0 Then
  Begin
    GetFullPathNameA := 0;
    Exit;
  End;
  Out := Tmp + 1024;
  If Mem[0:PName] = 47 Then
  Begin
    Mem[0:Tmp] := 0;
  End
  Else
  Begin
    If LnxSys3(183, Tmp, 1000, 0) <= 0 Then Mem[0:Tmp] := 0;
  End;
  L := LnxLen(Tmp);
  Mem[0:Tmp + L] := 47;
  LnxCopyZ(Tmp + L + 1, PName);
  { normaliser Tmp -> Out }
  J := 0;
  I := 0;
  While Mem[0:Tmp + I] <> 0 Do
  Begin
    { composant }
    While Mem[0:Tmp + I] = 47 Do Inc(I);
    Start := I;
    While (Mem[0:Tmp + I] <> 0) And (Mem[0:Tmp + I] <> 47) Do Inc(I);
    L := I - Start;
    If L = 0 Then Break;
    If (L = 1) And (Mem[0:Tmp + Start] = 46) Then Continue;
    If (L = 2) And (Mem[0:Tmp + Start] = 46) And (Mem[0:Tmp + Start + 1] = 46)
        Then
    Begin
      While (J > 0) And (Mem[0:Out + J - 1] <> 47) Do Dec(J);
      If J > 0 Then Dec(J);
      Continue;
    End;
    Mem[0:Out + J] := 47;
    Inc(J);
    LnxMove(Tmp + Start, Out + J, L);
    J := J + L;
  End;
  If J = 0 Then
  Begin
    Mem[0:Out] := 47;
    J := 1;
  End;
  Mem[0:Out + J] := 0;
  If J + 1 > N Then
  Begin
    GetFullPathNameA := J + 1;
    HeapFree(1, 0, Tmp);
    Exit;
  End;
  LnxMove(Out, Buf, J + 1);
  If PFile <> 0 Then
  Begin
    C := J;
    While (C > 0) And (Mem[0:Buf + C - 1] <> 47) Do Dec(C);
    MemL[0:PFile] := Buf + C;
  End;
  HeapFree(1, 0, Tmp);
  GetFullPathNameA := J;
End;

Function GetDiskFreeSpaceA(PRoot, PSpc, PBps, PFree, PTotal : LongInt)
    : LongInt;
Var Bsize : LongInt;
Begin
  GetDiskFreeSpaceA := 0;
  LnxTmp[0] := 47;
  If LnxCheck(LnxSys3(99, LongInt(@LnxTmp), LongInt(@LnxStat), 0)) < 0 Then
      Exit;
  Bsize := LnxStat[1];
  If Bsize < 512 Then Bsize := 512;
  If PSpc <> 0 Then MemL[0:PSpc] := Bsize Div 512;
  If PBps <> 0 Then MemL[0:PBps] := 512;
  If PFree <> 0 Then MemL[0:PFree] := LnxStat[4];
  If PTotal <> 0 Then MemL[0:PTotal] := LnxStat[2];
  GetDiskFreeSpaceA := 1;
End;

{ ---------- recherche de fichiers (FindFirstFile...) ---------- }

Const
  LnxMaxFind = 32;

Var
  LnxFindFd  : Array[0..LnxMaxFind - 1] Of LongInt;
  LnxFindBuf : Array[0..LnxMaxFind - 1] Of LongInt;
  LnxFindPos : Array[0..LnxMaxFind - 1] Of LongInt;
  LnxFindLen : Array[0..LnxMaxFind - 1] Of LongInt;
  LnxFindPat : Array[0..LnxMaxFind - 1] Of LongInt;
  LnxFindDir : Array[0..LnxMaxFind - 1] Of LongInt;

{ filtre de nom avec ? et * (2 passes recursives) }
Function LnxMatch(Pat, Nm : LongInt) : Boolean;
Var P, N : LongInt;
Begin
  LnxMatch := False;
  While True Do
  Begin
    P := Mem[0:Pat];
    N := Mem[0:Nm];
    If P = 0 Then
    Begin
      LnxMatch := (N = 0);
      Exit;
    End;
    If P = 42 Then
    Begin
      Inc(Pat);
      If Mem[0:Pat] = 0 Then
      Begin
        LnxMatch := True;
        Exit;
      End;
      While True Do
      Begin
        If LnxMatch(Pat, Nm) Then
        Begin
          LnxMatch := True;
          Exit;
        End;
        If Mem[0:Nm] = 0 Then Exit;
        Inc(Nm);
      End;
    End;
    If N = 0 Then Exit;
    If (P <> 63) And (P <> N) Then Exit;
    Inc(Pat);
    Inc(Nm);
  End;
End;

Procedure LnxFillFind(F, P, Ent : LongInt);
Var Full, Dir, L, Nl : LongInt; T : LongInt;
Begin
  Dir := LnxFindDir[F];
  Nl := LnxLen(Ent + 10);
  Full := HeapAlloc(1, 0, LnxLen(Dir) + Nl + 4);
  LnxCopyZ(Full, Dir);
  L := LnxLen(Full);
  If (L > 0) And (Mem[0:Full + L - 1] <> 47) Then
  Begin
    Mem[0:Full + L] := 47;
    Inc(L);
  End;
  LnxCopyZ(Full + L, Ent + 10);
  LnxFill(P, 320, 0);
  If LnxSys3(107, Full, LongInt(@LnxStat), 0) >= 0 Then
  Begin
    MemL[0:P] := LnxAttrOf(MemW[0:LongInt(@LnxStat) + 8]);
    MemL[0:P + 32] := LnxStat[5];
    T := LnxToDos(LnxStat[10]);
    DosDateTimeToFileTime(T Shr 16, T, P + 4);
    DosDateTimeToFileTime(T Shr 16, T, P + 12);
    DosDateTimeToFileTime(T Shr 16, T, P + 20);
  End
  Else MemL[0:P] := $20;
  If Nl > 259 Then Nl := 259;
  LnxMove(Ent + 10, P + 44, Nl);
  Mem[0:P + 44 + Nl] := 0;
  If Nl > 13 Then Nl := 13;
  LnxMove(Ent + 10, P + 304, Nl);
  Mem[0:P + 304 + Nl] := 0;
  HeapFree(1, 0, Full);
End;

{ entree suivante correspondant au filtre ; 1 trouvee, 0 fin }
Function LnxFindStep(F, P : LongInt) : LongInt;
Var Ent, Rec : LongInt;
Begin
  LnxFindStep := 0;
  While True Do
  Begin
    If LnxFindPos[F] >= LnxFindLen[F] Then
    Begin
      Rec := LnxSys3(141, LnxFindFd[F], LnxFindBuf[F], 2048);
      If Rec <= 0 Then Exit;
      LnxFindLen[F] := Rec;
      LnxFindPos[F] := 0;
    End;
    Ent := LnxFindBuf[F] + LnxFindPos[F];
    LnxFindPos[F] := LnxFindPos[F] + MemW[0:Ent + 8];
    If LnxMatch(LnxFindPat[F], Ent + 10) Then
    Begin
      LnxFillFind(F, P, Ent);
      LnxFindStep := 1;
      Exit;
    End;
  End;
End;

Function FindFirstFileA(PName, P : LongInt) : LongInt;
Var F, L, Cut, Tmp : LongInt;
Begin
  FindFirstFileA := -1;
  PName := LnxPath(PName);
  F := 0;
  While (F < LnxMaxFind) And (LnxFindFd[F] <> 0) Do Inc(F);
  If F >= LnxMaxFind Then
  Begin
    LnxErrno := 4;
    Exit;
  End;
  L := LnxLen(PName);
  Cut := L;
  While (Cut > 0) And (Mem[0:PName + Cut - 1] <> 47) Do Dec(Cut);
  Tmp := HeapAlloc(1, 0, L + 8);
  If Cut = 0 Then
  Begin
    Mem[0:Tmp] := 46;
    Mem[0:Tmp + 1] := 0;
  End
  Else
  Begin
    LnxMove(PName, Tmp, Cut);
    If Cut > 1 Then Mem[0:Tmp + Cut - 1] := 0 Else Mem[0:Tmp + Cut] := 0;
  End;
  LnxFindDir[F] := Tmp;
  LnxFindPat[F] := HeapAlloc(1, 0, L - Cut + 2);
  LnxCopyZ(LnxFindPat[F], PName + Cut);
  { *.* : tous les fichiers }
  If (LnxLen(LnxFindPat[F]) = 3) And (Mem[0:LnxFindPat[F]] = 42) And
     (Mem[0:LnxFindPat[F] + 1] = 46) And (Mem[0:LnxFindPat[F] + 2] = 42) Then
    Mem[0:LnxFindPat[F] + 1] := 0;
  { ouvrir le repertoire (O_RDONLY | O_DIRECTORY) }
  LnxFindFd[F] := LnxCheck(LnxSys3(5, Tmp, $10000, 0));
  If LnxFindFd[F] < 0 Then
  Begin
    LnxFindFd[F] := 0;
    HeapFree(1, 0, Tmp);
    HeapFree(1, 0, LnxFindPat[F]);
    Exit;
  End;
  LnxFindBuf[F] := HeapAlloc(1, 0, 2048);
  LnxFindPos[F] := 0;
  LnxFindLen[F] := 0;
  If LnxFindStep(F, P) = 0 Then
  Begin
    LnxErrno := 2;
    LnxSys3(6, LnxFindFd[F], 0, 0);
    LnxFindFd[F] := 0;
    Exit;
  End;
  FindFirstFileA := F + 1;
End;

Function FindNextFileA(H, P : LongInt) : LongInt;
Begin
  FindNextFileA := 0;
  If (H < 1) Or (H > LnxMaxFind) Then Exit;
  If LnxFindFd[H - 1] = 0 Then Exit;
  If LnxFindStep(H - 1, P) = 0 Then LnxErrno := 18
  Else FindNextFileA := 1;
End;

Function FindClose(H : LongInt) : LongInt;
Begin
  FindClose := 0;
  If (H < 1) Or (H > LnxMaxFind) Then Exit;
  If LnxFindFd[H - 1] = 0 Then Exit;
  LnxSys3(6, LnxFindFd[H - 1], 0, 0);
  LnxFindFd[H - 1] := 0;
  HeapFree(1, 0, LnxFindBuf[H - 1]);
  HeapFree(1, 0, LnxFindPat[H - 1]);
  HeapFree(1, 0, LnxFindDir[H - 1]);
  FindClose := 1;
End;

{ ---------- processus ---------- }

Var
  LnxExit : Array[0..63] Of LongInt;    { code de sortie des processus lances }
  LnxPid  : Array[0..63] Of LongInt;

{ execve de Prog avec les arguments de la ligne de commande Cmd ;
  recherche dans PATH si Prog ne contient pas de / }
Procedure LnxExec(Prog, Cmd : LongInt);
Var
  Argv, N, I, Q, Start, L, Path, PL, K, Cand : LongInt;
  Ch : LongInt;
Begin
  Argv := HeapAlloc(1, 8, 4 * 64);
  N := 0;
  I := 0;
  While Mem[0:Cmd + I] <> 0 Do
  Begin
    While (Mem[0:Cmd + I] = 32) Or (Mem[0:Cmd + I] = 9) Do Inc(I);
    If Mem[0:Cmd + I] = 0 Then Break;
    Q := 0;
    If Mem[0:Cmd + I] = 34 Then
    Begin
      Q := 1;
      Inc(I);
    End;
    Start := I;
    While True Do
    Begin
      Ch := Mem[0:Cmd + I];
      If Ch = 0 Then Break;
      If (Q = 1) And (Ch = 34) Then Break;
      If (Q = 0) And ((Ch = 32) Or (Ch = 9)) Then Break;
      Inc(I);
    End;
    L := I - Start;
    K := HeapAlloc(1, 0, L + 1);
    LnxMove(Cmd + Start, K, L);
    Mem[0:K + L] := 0;
    If N < 62 Then
    Begin
      MemL[0:Argv + N * 4] := K;
      Inc(N);
    End;
    If Mem[0:Cmd + I] = 34 Then Inc(I);
  End;
  MemL[0:Argv + N * 4] := 0;
  { programme }
  Path := 0;
  If LnxLen(Prog) > 0 Then
  Begin
    K := 0;
    L := LnxLen(Prog);
    I := 0;
    While I < L Do
    Begin
      If Mem[0:Prog + I] = 47 Then K := 1;
      Inc(I);
    End;
    If K = 1 Then
      LnxSys3(11, Prog, Argv, LnxEnvp)
    Else
    Begin
      { PATH }
      I := 0;
      While MemL[0:LnxEnvp + I * 4] <> 0 Do
      Begin
        K := MemL[0:LnxEnvp + I * 4];
        If (Mem[0:K] = 80) And (Mem[0:K + 1] = 65) And (Mem[0:K + 2] = 84) And
           (Mem[0:K + 3] = 72) And (Mem[0:K + 4] = 61) Then Path := K + 5;
        Inc(I);
      End;
      Cand := HeapAlloc(1, 0, 4096);
      If Path = 0 Then
      Begin
        LnxCopyZ(Cand, Prog);
        LnxSys3(11, Cand, Argv, LnxEnvp);
      End
      Else
      Begin
        I := 0;
        While True Do
        Begin
          PL := 0;
          While (Mem[0:Path + I + PL] <> 0) And (Mem[0:Path + I + PL] <> 58)
              Do Inc(PL);
          If PL > 0 Then
          Begin
            LnxMove(Path + I, Cand, PL);
            Mem[0:Cand + PL] := 47;
            LnxCopyZ(Cand + PL + 1, Prog);
            LnxSys3(11, Cand, Argv, LnxEnvp);
          End;
          I := I + PL;
          If Mem[0:Path + I] = 0 Then Break;
          Inc(I);
        End;
      End;
    End;
  End;
  LnxSys3(1, 127, 0, 0);
End;

Function CreateProcessA(App, Cmd, PAttr, TAttr, Inherit, Flags, Env, Dir,
    SInfo, PInfo : LongInt) : LongInt;
Var Pid, Prog, L, I, S : LongInt;
Begin
  CreateProcessA := 0;
  Pid := LnxCheck(LnxSys3(2, 0, 0, 0));
  If Pid < 0 Then Exit;
  If Pid = 0 Then
  Begin
    If Dir <> 0 Then LnxSys3(12, Dir, 0, 0);
    If App <> 0 Then Prog := App
    Else
    Begin
      { premier mot de la ligne de commande }
      L := LnxLen(Cmd);
      Prog := HeapAlloc(1, 0, L + 2);
      LnxCopyZ(Prog, Cmd);
      I := 0;
      S := 0;
      If Mem[0:Prog] = 34 Then
      Begin
        S := 1;
        I := 1;
        While (Mem[0:Prog + I] <> 0) And (Mem[0:Prog + I] <> 34) Do Inc(I);
        Mem[0:Prog + I] := 0;
      End
      Else
      Begin
        While (Mem[0:Prog + I] <> 0) And (Mem[0:Prog + I] <> 32) Do Inc(I);
        Mem[0:Prog + I] := 0;
      End;
      Prog := Prog + S;
    End;
    LnxExec(Prog, Cmd);
  End;
  { parent : memoriser le processus }
  I := 0;
  While (I < 63) And (LnxPid[I] <> 0) Do Inc(I);
  LnxPid[I] := Pid;
  LnxExit[I] := 259;
  If PInfo <> 0 Then
  Begin
    MemL[0:PInfo] := $1000 + I;
    MemL[0:PInfo + 4] := $2000 + I;
    MemL[0:PInfo + 8] := Pid;
    MemL[0:PInfo + 12] := 0;
  End;
  CreateProcessA := 1;
End;

Function WaitForSingleObject(H, Ms : LongInt) : LongInt;
Var I, R, Pid : LongInt;
Begin
  WaitForSingleObject := 0;
  I := H - $1000;
  If (I < 0) Or (I > 63) Or (LnxPid[I] = 0) Then Exit;
  Pid := LnxPid[I];
  If LnxExit[I] = 259 Then
  Begin
    R := LnxSys6(114, Pid, LongInt(@LnxTmp), 0, 0, 0, 0);   { wait4 }
    If R >= 0 Then
    Begin
      If (LnxTmp[0] And $7F) = 0 Then LnxExit[I] := (LnxTmp[0] Shr 8) And $FF
      Else LnxExit[I] := 128 + (LnxTmp[0] And $7F);
    End
    Else LnxExit[I] := 255;
  End;
End;

Function GetExitCodeProcess(H, PCode : LongInt) : LongInt;
Var I : LongInt;
Begin
  GetExitCodeProcess := 0;
  I := H - $1000;
  If (I < 0) Or (I > 63) Or (LnxPid[I] = 0) Then Exit;
  If PCode <> 0 Then MemL[0:PCode] := LnxExit[I];
  GetExitCodeProcess := 1;
End;

Function SetEnvironmentVariableA(Name, Value : LongInt) : LongInt;
Begin
  SetEnvironmentVariableA := 0;
End;

Function GetModuleFileNameA(Module, Buf, Size : LongInt) : LongInt;
Var L : LongInt;
Begin
  L := LnxLen(MemL[0:LnxArgv]);
  If L + 1 > Size Then L := Size - 1;
  LnxMove(MemL[0:LnxArgv], Buf, L);
  Mem[0:Buf + L] := 0;
  GetModuleFileNameA := L;
End;

Function GetCurrentProcessId : LongInt;
Begin
  GetCurrentProcessId := LnxSys3(20, 0, 0, 0);
End;

Function GetCurrentThreadId : LongInt;
Begin
  GetCurrentThreadId := LnxSys3(20, 0, 0, 0);
End;

Function Beep(Freq, Dur : LongInt) : LongInt;
Begin
  LnxTmp[0] := 7;
  LnxSys3(4, 1, LongInt(@LnxTmp), 1);
  Beep := 1;
End;

{ ---------- console (terminal ANSI) ---------- }

Var
  LnxCols    : LongInt;
  LnxRows    : LongInt;
  LnxCurX    : LongInt;
  LnxCurY    : LongInt;
  LnxAttr    : LongInt;
  LnxConInit : LongInt;
  LnxTty     : LongInt;        { 1 si la sortie standard est un terminal }
  LnxRaw     : LongInt;        { 1 si le terminal est en mode brut }
  LnxTermSv  : Array[0..8] Of LongInt;   { termios d'origine (36 octets) }
  LnxTermNw  : Array[0..8] Of LongInt;
  LnxKeyBuf  : Array[0..15] Of LongInt;  { octets lus, en attente }
  LnxKeyN    : LongInt;
  LnxOutBuf  : Array[0..63] Of LongInt;

Procedure LnxConInitialize;
Begin
  If LnxConInit <> 0 Then Exit;
  LnxConInit := 1;
  LnxCols := 80;
  LnxRows := 25;
  LnxAttr := 7;
  { terminal ? TCGETS sur la sortie standard }
  If LnxSys3(54, 1, $5401, LongInt(@LnxTermNw)) >= 0 Then
  Begin
    LnxTty := 1;
    { TIOCGWINSZ : lignes, colonnes (mots) }
    If LnxSys3(54, 1, $5413, LongInt(@LnxTmp[8])) >= 0 Then
    Begin
      If MemW[0:LongInt(@LnxTmp[8])] > 0 Then
          LnxRows := MemW[0:LongInt(@LnxTmp[8])];
      If MemW[0:LongInt(@LnxTmp[8]) + 2] > 0 Then
          LnxCols := MemW[0:LongInt(@LnxTmp[8]) + 2];
    End;
  End;
End;

{ ecrire une chaine ASCIIZ de commande sur le terminal }
Procedure LnxEsc(S : LongInt);
Begin
  LnxSys3(4, 1, S, LnxLen(S));
End;

Procedure LnxPutNum(Var Pos : LongInt; V : LongInt);
Var D : LongInt; Started : Boolean;
Begin
  If V = 0 Then
  Begin
    Mem[0:LongInt(@LnxOutBuf) + Pos] := 48;
    Inc(Pos);
    Exit;
  End;
  Started := False;
  D := 10000;
  While D > 0 Do
  Begin
    If (V Div D > 0) Or Started Then
    Begin
      Mem[0:LongInt(@LnxOutBuf) + Pos] := 48 + (V Div D) Mod 10;
      Inc(Pos);
      Started := True;
    End;
    D := D Div 10;
  End;
End;

Procedure LnxGoto(X, Y : LongInt);
Var P : LongInt;
Begin
  If LnxTty = 0 Then Exit;
  P := 0;
  Mem[0:LongInt(@LnxOutBuf)] := 27;
  Mem[0:LongInt(@LnxOutBuf) + 1] := 91;
  P := 2;
  LnxPutNum(P, Y + 1);
  Mem[0:LongInt(@LnxOutBuf) + P] := 59;
  Inc(P);
  LnxPutNum(P, X + 1);
  Mem[0:LongInt(@LnxOutBuf) + P] := 72;
  Inc(P);
  LnxSys3(4, 1, LongInt(@LnxOutBuf), P);
End;

{ attribut DOS (fond*16 + premier plan) -> sequence SGR ANSI }
Procedure LnxSetColor(Attr : LongInt);
Const
  Ansi : Array[0..7] Of Byte = (0, 4, 2, 6, 1, 5, 3, 7);
Var P, Fg, Bg : LongInt;
Begin
  If LnxTty = 0 Then Exit;
  Fg := Ansi[Attr And 7];
  Bg := Ansi[(Attr Shr 4) And 7];
  Mem[0:LongInt(@LnxOutBuf)] := 27;
  Mem[0:LongInt(@LnxOutBuf) + 1] := 91;
  P := 2;
  Mem[0:LongInt(@LnxOutBuf) + P] := 48;       { 0 : reinitialisation }
  Inc(P);
  If (Attr And 8) <> 0 Then
  Begin
    Mem[0:LongInt(@LnxOutBuf) + P] := 59;
    Mem[0:LongInt(@LnxOutBuf) + P + 1] := 49;     { 1 : brillant }
    P := P + 2;
  End;
  If (Attr And $80) <> 0 Then
  Begin
    Mem[0:LongInt(@LnxOutBuf) + P] := 59;
    Mem[0:LongInt(@LnxOutBuf) + P + 1] := 53;     { 5 : clignotant }
    P := P + 2;
  End;
  Mem[0:LongInt(@LnxOutBuf) + P] := 59;
  Inc(P);
  LnxPutNum(P, 30 + Fg);
  Mem[0:LongInt(@LnxOutBuf) + P] := 59;
  Inc(P);
  LnxPutNum(P, 40 + Bg);
  Mem[0:LongInt(@LnxOutBuf) + P] := 109;
  Inc(P);
  LnxSys3(4, 1, LongInt(@LnxOutBuf), P);
End;

Function SetConsoleTextAttribute(H, Attr : LongInt) : LongInt;
Begin
  LnxConInitialize;
  LnxAttr := Attr And $FF;
  LnxSetColor(LnxAttr);
  SetConsoleTextAttribute := 1;
End;

Function SetConsoleCursorPosition(H, Coord : LongInt) : LongInt;
Begin
  LnxConInitialize;
  LnxCurX := Coord And $FFFF;
  LnxCurY := (Coord Shr 16) And $FFFF;
  If LnxCurX >= LnxCols Then LnxCurX := LnxCols - 1;
  If LnxCurY >= LnxRows Then LnxCurY := LnxRows - 1;
  LnxGoto(LnxCurX, LnxCurY);
  SetConsoleCursorPosition := 1;
End;

Function GetConsoleScreenBufferInfo(H, P : LongInt) : LongInt;
Begin
  LnxConInitialize;
  MemW[0:P] := LnxCols;
  MemW[0:P + 2] := LnxRows;
  MemW[0:P + 4] := LnxCurX;
  MemW[0:P + 6] := LnxCurY;
  MemW[0:P + 8] := LnxAttr;
  MemW[0:P + 10] := 0;
  MemW[0:P + 12] := 0;
  MemW[0:P + 14] := LnxCols - 1;
  MemW[0:P + 16] := LnxRows - 1;
  MemW[0:P + 18] := LnxCols;
  MemW[0:P + 20] := LnxRows;
  GetConsoleScreenBufferInfo := 1;
End;

Function SetConsoleScreenBufferSize(H, Size : LongInt) : LongInt;
Begin
  SetConsoleScreenBufferSize := 1;
End;

{ suivi du curseur pour le texte ecrit sur la console }
Procedure LnxTrack(Buf, N : LongInt);
Var I, C : LongInt;
Begin
  LnxConInitialize;
  If LnxTty = 0 Then Exit;
  I := 0;
  While I < N Do
  Begin
    C := Mem[0:Buf + I];
    If C = 27 Then
    Begin
      { sequence d'echappement : ignoree (le curseur reste approximatif) }
      Inc(I);
      If (I < N) And (Mem[0:Buf + I] = 91) Then
      Begin
        Inc(I);
        While (I < N) And ((Mem[0:Buf + I] < 64) Or (Mem[0:Buf + I] > 126))
            Do Inc(I);
      End;
    End
    Else If C = 10 Then
    Begin
      If LnxCurY < LnxRows - 1 Then Inc(LnxCurY);
      LnxCurX := 0;
    End
    Else If C = 13 Then LnxCurX := 0
    Else If C = 8 Then
    Begin
      If LnxCurX > 0 Then Dec(LnxCurX);
    End
    Else If C = 9 Then LnxCurX := (LnxCurX + 8) And (Not 7)
    Else If C >= 32 Then Inc(LnxCurX);
    If LnxCurX >= LnxCols Then
    Begin
      LnxCurX := 0;
      If LnxCurY < LnxRows - 1 Then Inc(LnxCurY);
    End;
    Inc(I);
  End;
End;

Function FillConsoleOutputCharacterA(H, Ch, Len, Coord, PWritten : LongInt)
    : LongInt;
Var X, Y, I, SvX, SvY, N : LongInt;
Begin
  LnxConInitialize;
  If PWritten <> 0 Then MemL[0:PWritten] := Len;
  FillConsoleOutputCharacterA := 1;
  If LnxTty = 0 Then Exit;
  X := Coord And $FFFF;
  Y := (Coord Shr 16) And $FFFF;
  SvX := LnxCurX;
  SvY := LnxCurY;
  { effacement de tout l'ecran ou de la fin de l'ecran }
  If ((Ch And $FF) = 32) And (Y * LnxCols + X + Len >= LnxCols * LnxRows)
      And (Len >= LnxCols) Then
  Begin
    LnxGoto(X, Y);
    If (X = 0) And (Y = 0) Then LnxEsc(LongInt(PChar(#27'[2J')))
    Else LnxEsc(LongInt(PChar(#27'[J')));
    LnxGoto(SvX, SvY);
    Exit;
  End;
  LnxGoto(X, Y);
  I := 0;
  While I < Len Do
  Begin
    N := Len - I;
    If N > 64 Then N := 64;
    LnxFill(LongInt(@LnxOutBuf), N, Ch And $FF);
    LnxSys3(4, 1, LongInt(@LnxOutBuf), N);
    I := I + N;
  End;
  LnxGoto(SvX, SvY);
End;

Function FillConsoleOutputAttribute(H, Attr, Len, Coord, PWritten : LongInt)
    : LongInt;
Begin
  If PWritten <> 0 Then MemL[0:PWritten] := Len;
  FillConsoleOutputAttribute := 1;
End;

Function WriteConsoleOutputAttribute(H, PAttr, Len, Coord, PWritten : LongInt)
    : LongInt;
Begin
  If PWritten <> 0 Then MemL[0:PWritten] := Len;
  WriteConsoleOutputAttribute := 1;
End;

{ defilement d'un rectangle : seuls les cas courants (defilement vers le
  haut ou le bas de toute la largeur) sont rendus par le terminal }
Function ScrollConsoleScreenBufferA(H, PRect, PClip, Dest, PFill : LongInt)
    : LongInt;
Var T, B, DY, N, P : LongInt;
Begin
  LnxConInitialize;
  ScrollConsoleScreenBufferA := 1;
  If LnxTty = 0 Then Exit;
  T := MemW[0:PRect + 2];
  B := MemW[0:PRect + 6];
  DY := (Dest Shr 16) And $FFFF;
  If B >= LnxRows Then B := LnxRows - 1;
  { region de defilement T..B }
  P := 0;
  Mem[0:LongInt(@LnxOutBuf)] := 27;
  Mem[0:LongInt(@LnxOutBuf) + 1] := 91;
  P := 2;
  LnxPutNum(P, T + 1);
  Mem[0:LongInt(@LnxOutBuf) + P] := 59;
  Inc(P);
  LnxPutNum(P, B + 1);
  Mem[0:LongInt(@LnxOutBuf) + P] := 114;
  Inc(P);
  LnxSys3(4, 1, LongInt(@LnxOutBuf), P);
  If DY < T Then N := T - DY Else N := DY - T;
  LnxGoto(0, B);
  If DY < T Then
  Begin
    { vers le haut : N fois "linefeed" en bas de la region }
    While N > 0 Do
    Begin
      LnxTmp[0] := 10;
      LnxSys3(4, 1, LongInt(@LnxTmp), 1);
      Dec(N);
    End;
  End
  Else
  Begin
    LnxGoto(0, T);
    While N > 0 Do
    Begin
      LnxEsc(LongInt(PChar(#27'M')));
      Dec(N);
    End;
  End;
  LnxEsc(LongInt(PChar(#27'[r')));
  LnxGoto(LnxCurX, LnxCurY);
End;

{ ----- entree (clavier) ----- }

Procedure LnxRawOn;
Begin
  LnxConInitialize;
  If LnxRaw <> 0 Then Exit;
  If LnxSys3(54, 0, $5401, LongInt(@LnxTermSv)) < 0 Then Exit;
  LnxMove(LongInt(@LnxTermSv), LongInt(@LnxTermNw), 36);
  { c_lflag (offset 12) : ni ICANON ni ECHO ; c_cc[VMIN] = 1, c_cc[VTIME] = 0 }
  LnxTermNw[3] := LnxTermNw[3] And (Not 10);
  Mem[0:LongInt(@LnxTermNw) + 17 + 6] := 1;
  Mem[0:LongInt(@LnxTermNw) + 17 + 5] := 0;
  LnxSys3(54, 0, $5402, LongInt(@LnxTermNw));
  LnxRaw := 1;
End;

Procedure LnxRawOff;
Begin
  If LnxRaw = 0 Then Exit;
  LnxSys3(54, 0, $5402, LongInt(@LnxTermSv));
  LnxRaw := 0;
End;

Function GetConsoleMode(H, PMode : LongInt) : LongInt;
Begin
  If PMode <> 0 Then MemL[0:PMode] := 7;
  GetConsoleMode := 1;
End;

Function SetConsoleMode(H, Mode : LongInt) : LongInt;
Begin
  SetConsoleMode := 1;
End;

{ nombre d'octets disponibles sur l'entree standard }
Function LnxAvail : LongInt;
Begin
  LnxTmp[0] := 0;
  If LnxSys3(54, 0, $541B, LongInt(@LnxTmp)) < 0 Then LnxAvail := 0
  Else LnxAvail := LnxTmp[0];
End;

Function LnxGetByte : LongInt;
Var R : LongInt;
Begin
  R := LnxSys3(3, 0, LongInt(@LnxTmp[4]), 1);
  If R <= 0 Then LnxGetByte := -1
  Else LnxGetByte := Mem[0:LongInt(@LnxTmp[4])];
End;

{ lit une touche : resultat = (code de balayage * 256) + ascii, ou -1 }
Function LnxReadKey : LongInt;
Var C, C2, C3, Sc, Ch : LongInt;
Begin
  LnxReadKey := -1;
  C := LnxGetByte;
  If C < 0 Then Exit;
  If C = 27 Then
  Begin
    If LnxAvail = 0 Then
    Begin
      LnxReadKey := $011B;
      Exit;
    End;
    C2 := LnxGetByte;
    If (C2 = 91) Or (C2 = 79) Then
    Begin
      C3 := LnxGetByte;
      Sc := 0;
      Case C3 Of
        65 : Sc := $48;      { haut }
        66 : Sc := $50;      { bas }
        67 : Sc := $4D;      { droite }
        68 : Sc := $4B;      { gauche }
        72 : Sc := $47;      { debut }
        70 : Sc := $4F;      { fin }
        80 : Sc := $3B;      { F1 }
        81 : Sc := $3C;
        82 : Sc := $3D;
        83 : Sc := $3E;
        49, 50, 51, 52, 53, 54 :
          Begin
            C2 := LnxGetByte;     { chiffre ou ~ }
            If C2 = 126 Then
            Begin
              Case C3 Of
                49 : Sc := $47;
                50 : Sc := $52;
                51 : Sc := $53;
                52 : Sc := $4F;
                53 : Sc := $49;
                54 : Sc := $51;
              End;
            End
            Else
            Begin
              { F5.. : ESC [ 1 5 ~ etc. }
              Ch := LnxGetByte;
              C := (C3 - 48) * 10 + (C2 - 48);
              Case C Of
                15 : Sc := $3F; 17 : Sc := $40; 18 : Sc := $41; 19 : Sc := $42;
                20 : Sc := $43; 21 : Sc := $44;
              End;
            End;
          End;
      End;
      LnxReadKey := Sc Shl 8;
      Exit;
    End;
    LnxReadKey := $011B;
    Exit;
  End;
  Sc := 0;
  If C = 13 Then Sc := $1C
  Else If C = 10 Then
  Begin
    C := 13;
    Sc := $1C;
  End
  Else If C = 127 Then
  Begin
    C := 8;
    Sc := $0E;
  End
  Else If C = 9 Then Sc := $0F
  Else If C = 32 Then Sc := $39;
  LnxReadKey := (Sc Shl 8) Or C;
End;

Function LnxVirtKey(K : LongInt) : LongInt;
Var Sc, Ch : LongInt;
Begin
  Sc := (K Shr 8) And $FF;
  Ch := K And $FF;
  Case Sc Of
    $48 : LnxVirtKey := $26; $50 : LnxVirtKey := $28; $4B : LnxVirtKey := $25;
    $4D : LnxVirtKey := $27; $47 : LnxVirtKey := $24; $4F : LnxVirtKey := $23;
    $49 : LnxVirtKey := $21; $51 : LnxVirtKey := $22; $52 : LnxVirtKey := $2D;
    $53 : LnxVirtKey := $2E; $1C : LnxVirtKey := $0D; $01 : LnxVirtKey := $1B;
    $0E : LnxVirtKey := $08; $0F : LnxVirtKey := $09; $39 : LnxVirtKey := $20;
    $3B..$44 : LnxVirtKey := $70 + Sc - $3B;
  Else
    If (Ch >= 97) And (Ch <= 122) Then LnxVirtKey := Ch - 32
    Else LnxVirtKey := Ch;
  End;
End;

Procedure LnxKeyRecord(P, K : LongInt);
Begin
  LnxFill(P, 20, 0);
  MemW[0:P] := 1;
  MemL[0:P + 4] := 1;
  MemW[0:P + 8] := 1;
  MemW[0:P + 10] := LnxVirtKey(K);
  MemW[0:P + 12] := (K Shr 8) And $FF;
  Mem[0:P + 14] := K And $FF;
  MemL[0:P + 16] := 0;
End;

Var
  LnxPending : LongInt;     { touche lue par PeekConsoleInput, ou -1 }

Function GetNumberOfConsoleInputEvents(H, PCount : LongInt) : LongInt;
Begin
  LnxRawOn;
  If (LnxPending >= 0) Or (LnxAvail > 0) Then MemL[0:PCount] := 1
  Else MemL[0:PCount] := 0;
  GetNumberOfConsoleInputEvents := 1;
End;

Function PeekConsoleInputA(H, P, N, PRead : LongInt) : LongInt;
Begin
  LnxRawOn;
  If (LnxPending < 0) And (LnxAvail > 0) Then LnxPending := LnxReadKey;
  If (LnxPending >= 0) And (N > 0) Then
  Begin
    LnxKeyRecord(P, LnxPending);
    MemL[0:PRead] := 1;
  End
  Else MemL[0:PRead] := 0;
  PeekConsoleInputA := 1;
End;

Function ReadConsoleInputA(H, P, N, PRead : LongInt) : LongInt;
Var K : LongInt;
Begin
  LnxRawOn;
  If LnxPending >= 0 Then
  Begin
    K := LnxPending;
    LnxPending := -1;
  End
  Else
  Begin
    K := LnxReadKey;
    If K < 0 Then
    Begin
      { fin de fichier sur l'entree : touche Ctrl-Z }
      K := $2C1A;
    End;
  End;
  LnxKeyRecord(P, K);
  MemL[0:PRead] := 1;
  ReadConsoleInputA := 1;
End;

Function FlushConsoleInputBuffer(H : LongInt) : LongInt;
Begin
  LnxPending := -1;
  While LnxAvail > 0 Do LnxGetByte;
  FlushConsoleInputBuffer := 1;
End;

Function ReadConsoleA(H, Buf, N, PRead, Ctl : LongInt) : LongInt;
Begin
  ReadConsoleA := ReadFile(H, Buf, N, PRead, 0);
End;

{ ---------- compatibilite DOS : PrefixSeg, Lst ---------- }

Var
  PrefixSeg  : LongInt;       { Ptr(PrefixSeg, 80h)
      : queue de la ligne de commande }
  LnxTail    : Array[0..319] Of Byte;
  Lst        : Text;

{ queue de la ligne de commande au format du PSP : longueur, puis le texte
  commencant par un espace }
Procedure LnxInitTail;
Var A, I, J, K, L, N : LongInt;
Begin
  A := (LongInt(@LnxTail) + 15) And LongInt($FFFFFFF0);
  PrefixSeg := (A - $80) Shr 4;
  Mem[0:A] := 0;
  N := 0;
  For I := 1 To LnxArgc - 1 Do
  Begin
    K := MemL[0:LnxArgv + I * 4];
    L := LnxLen(K);
    If N + L + 2 > 126 Then Break;
    Mem[0:A + 1 + N] := 32;
    Inc(N);
    For J := 0 To L - 1 Do
    Begin
      Mem[0:A + 1 + N] := Mem[0:K + J];
      Inc(N);
    End;
  End;
  Mem[0:A] := N;
  Mem[0:A + 1 + N] := 13;
End;

{ ---------- interface systeme Linux (unite Unix des programmes) ---------- }
{ Les fonctions Sys* rendent la valeur de l'appel systeme, ou -1 avec le
  code d'erreur Linux dans SysErrno (comme la libc). SysCall rend le
  resultat brut (-errno). Les chemins sont des chaines Pascal (separateur /,
  rien n'est converti). }

Const
  O_RDONLY = 0;  O_WRONLY = 1;  O_RDWR = 2;     O_CREAT = $40;
  O_EXCL = $80;  O_NOCTTY = $100; O_TRUNC = $200; O_APPEND = $400;
  O_NONBLOCK = $800; O_DIRECTORY = $10000;
  SEEK_SET = 0;  SEEK_CUR = 1;  SEEK_END = 2;
  SIGHUP = 1;  SIGINT = 2;  SIGQUIT = 3;  SIGILL = 4;  SIGABRT = 6;
  SIGBUS = 7;  SIGFPE = 8;  SIGKILL = 9;  SIGUSR1 = 10;  SIGSEGV = 11;
  SIGUSR2 = 12;  SIGPIPE = 13;  SIGALRM = 14;  SIGTERM = 15;
  SIGCHLD = 17;  SIGCONT = 18;  SIGSTOP = 19;  SIGTSTP = 20;
  SIGTTIN = 21;  SIGTTOU = 22;
  SIG_DFL = 0;  SIG_IGN = 1;
  SA_RESTART = $10000000;
  WNOHANG = 1;  WUNTRACED = 2;
  TCGETS = $5401;  TCSETS = $5402;  TCSETSW = $5403;  TCSETSF = $5404;
  TIOCSCTTY = $540E;  TIOCGPGRP = $540F;  TIOCSPGRP = $5410;
  TIOCGWINSZ = $5413;  TIOCNOTTY = $5422;  FIONREAD = $541B;
  { termios : c_iflag }
  TTY_ICRNL = $100;  TTY_IXON = $400;  TTY_INLCR = $40;  TTY_ISTRIP = $20;
  { c_oflag }
  TTY_OPOST = 1;  TTY_ONLCR = 4;
  { c_lflag }
  TTY_ISIG = 1;  TTY_ICANON = 2;  TTY_ECHO = 8;  TTY_ECHOE = $10;
  TTY_ECHOK = $20;  TTY_ECHONL = $40;  TTY_IEXTEN = $8000;
  { indices de c_cc }
  TTY_VINTR = 0;  TTY_VQUIT = 1;  TTY_VERASE = 2;  TTY_VKILL = 3;
  TTY_VEOF = 4;  TTY_VTIME = 5;  TTY_VMIN = 6;  TTY_VSUSP = 10;
  { reboot }
  LINUX_REBOOT_MAGIC1 = $FEE1DEAD;
  LINUX_REBOOT_MAGIC2 = 672274793;
  LINUX_REBOOT_RESTART = $01234567;
  LINUX_REBOOT_HALT = $CDEF0123;
  LINUX_REBOOT_POWER_OFF = $4321FEDC;
  { modes de fichiers }
  S_IFMT = $F000;  S_IFDIR = $4000;  S_IFREG = $8000;  S_IFLNK = $A000;
  S_IFCHR = $2000;  S_IFBLK = $6000;  S_IFIFO = $1000;
  MS_RDONLY = 1;  MS_REMOUNT = 32;

Type
  TUtsName = Record
    SysName  : String[64];
    NodeName : String[64];
    Release  : String[64];
    Version  : String[64];
    Machine  : String[64];
  End;

  { struct stat de Linux i386 (stat, lstat, fstat : 64 octets) }
  TSysStat = Record
    Dev : Word;  Pad1 : Word;  Ino : LongInt;
    Mode, NLink, Uid, Gid, RDev, Pad2 : Word;
    Size, BlkSize, Blocks, ATime, Pad3, MTime, Pad4, CTime, Pad5,
    Res1, Res2 : LongInt;
  End;

  { struct termios de Linux i386 (36 octets) }
  TSysTermios = Record
    IFlag, OFlag, CFlag, LFlag : LongInt;
    Line : Byte;
    CC : Array[0..18] Of Byte;
  End;

  TSysWinSize = Record
    Row, Col, XPix, YPix : Word;
  End;

  { rt_sigaction du noyau }
  TSysSigAct = Record
    Handler, Flags, Restorer, MaskLo, MaskHi : LongInt;
  End;

  TSysPasswd = Record
    Name : String[32];
    Pw : String[16];
    Uid, Gid : LongInt;
    Gecos : String[64];
    Home : String[64];
    Shell : String[64];
  End;

Var
  SysErrno : LongInt;                 { derniere erreur Linux (positive) }
  LnxZBuf  : Array[0..1279] Of Char;  { chaines ASCIIZ temporaires }
  LnxZNo   : LongInt;
  LnxStBuf : Array[0..15] Of LongInt;
  LnxLangV : LongInt;                 { langue : 0 inconnue, 1..5 }
  LnxDirFd  : Array[0..15] Of LongInt;
  LnxDirBuf : Array[0..15] Of LongInt;
  LnxDirPos : Array[0..15] Of LongInt;
  LnxDirLen : Array[0..15] Of LongInt;

{ resultat brut -> valeur libc (erreur : -1 et SysErrno) }
Function LnxRes(R : LongInt) : LongInt;
Begin
  If (R < 0) And (R > -4096) Then
  Begin
    SysErrno := -R;
    LnxRes := -1;
  End
  Else LnxRes := R;
End;

{ chaine Pascal -> ASCIIZ dans un tampon tournant (5 chaines vivantes) }
Function LnxZ(Const S : String) : LongInt;
Var P, K, N : LongInt;
Begin
  P := LongInt(@LnxZBuf) + (LnxZNo Mod 5) * 256;
  Inc(LnxZNo);
  N := Length(S);
  For K := 1 To N Do Mem[0:P + K - 1] := Ord(S[K]);
  Mem[0:P + N] := 0;
  LnxZ := P;
End;

{ ASCIIZ (adresse) -> chaine Pascal }
Function SysZStr(P : LongInt) : String;
Var K : LongInt; S : String;
Begin
  K := 0;
  While (Mem[0:P + K] <> 0) And (K < 255) Do
  Begin
    S[K + 1] := Chr(Mem[0:P + K]);
    Inc(K);
  End;
  S[0] := Chr(K);
  SysZStr := S;
End;

{ copie d'une chaine Pascal dans le tas en ASCIIZ (adresse, jamais liberee) }
Function SysNewZ(Const S : String) : LongInt;
Var P, K, N : LongInt;
Begin
  N := Length(S);
  P := HeapAlloc(1, 0, N + 1);
  For K := 1 To N Do Mem[0:P + K - 1] := Ord(S[K]);
  Mem[0:P + N] := 0;
  SysNewZ := P;
End;

Function SysCall(N, A, B, C, D, E : LongInt) : LongInt;
Begin
  SysCall := LnxSys6(N, A, B, C, D, E, 0);
End;

Function SysExit(Status : LongInt) : LongInt;
Begin
  LnxRawOff;
  SysExit := LnxSys3(252, Status, 0, 0);
End;

Function SysFork : LongInt;
Begin
  SysFork := LnxRes(LnxSys3(2, 0, 0, 0));
End;

Function SysRead(Fd : LongInt; Var Buf; Count : LongInt) : LongInt;
Begin
  SysRead := LnxRes(LnxSys3(3, Fd, LongInt(@Buf), Count));
End;

Function SysWrite(Fd : LongInt; Var Buf; Count : LongInt) : LongInt;
Begin
  SysWrite := LnxRes(LnxSys3(4, Fd, LongInt(@Buf), Count));
End;

{ ecrit une chaine Pascal sur Fd (ecritures partielles reprises) }
Function SysPut(Fd : LongInt; Const S : String) : LongInt;
Var Done, R, N : LongInt;
Begin
  N := Length(S);
  Done := 0;
  SysPut := 0;
  While Done < N Do
  Begin
    R := LnxSys3(4, Fd, LongInt(@S) + 1 + Done, N - Done);
    If R <= 0 Then
    Begin
      SysPut := LnxRes(R);
      Exit;
    End;
    Done := Done + R;
  End;
  SysPut := N;
End;

Function SysOpen(Const Path : String; Flags, Mode : LongInt) : LongInt;
Begin
  SysOpen := LnxRes(LnxSys3(5, LnxZ(Path), Flags, Mode));
End;

Function SysCreat(Const Path : String; Mode : LongInt) : LongInt;
Begin
  SysCreat := LnxRes(LnxSys3(5, LnxZ(Path), $241, Mode));
End;

Function SysClose(Fd : LongInt) : LongInt;
Begin
  SysClose := LnxRes(LnxSys3(6, Fd, 0, 0));
End;

Function SysWaitPid(Pid : LongInt; Var Status : LongInt; Options : LongInt)
    : LongInt;
Begin
  SysWaitPid := LnxRes(LnxSys6(114, Pid, LongInt(@Status), Options, 0, 0, 0));
End;

{ interpretation de l'etat rendu par wait }
Function SysWIfExited(St : LongInt) : Boolean;
Begin
  SysWIfExited := (St And $7F) = 0;
End;

Function SysWExitStatus(St : LongInt) : LongInt;
Begin
  SysWExitStatus := (St Shr 8) And $FF;
End;

Function SysWIfSignaled(St : LongInt) : Boolean;
Begin
  SysWIfSignaled := ((St And $7F) <> 0) And ((St And $7F) <> $7F);
End;

Function SysWTermSig(St : LongInt) : LongInt;
Begin
  SysWTermSig := St And $7F;
End;

Function SysWIfStopped(St : LongInt) : Boolean;
Begin
  SysWIfStopped := (St And $FF) = $7F;
End;

Function SysWStopSig(St : LongInt) : LongInt;
Begin
  SysWStopSig := (St Shr 8) And $FF;
End;

Function SysExecve(Const Path : String; Argv, Envp : LongInt) : LongInt;
Begin
  SysExecve := LnxRes(LnxSys3(11, LnxZ(Path), Argv, Envp));
End;

Function SysPipe(Var Fds : LongInt) : LongInt;
Begin
  SysPipe := LnxRes(LnxSys3(42, LongInt(@Fds), 0, 0));
End;

Function SysDup(Fd : LongInt) : LongInt;
Begin
  SysDup := LnxRes(LnxSys3(41, Fd, 0, 0));
End;

Function SysDup2(Fd, Fd2 : LongInt) : LongInt;
Begin
  SysDup2 := LnxRes(LnxSys3(63, Fd, Fd2, 0));
End;

Function SysFcntl(Fd, Cmd, Arg : LongInt) : LongInt;
Begin
  SysFcntl := LnxRes(LnxSys3(55, Fd, Cmd, Arg));
End;

Function SysKill(Pid, Sig : LongInt) : LongInt;
Begin
  SysKill := LnxRes(LnxSys3(37, Pid, Sig, 0));
End;

Function SysGetPid : LongInt;
Begin
  SysGetPid := LnxSys3(20, 0, 0, 0);
End;

Function SysGetPPid : LongInt;
Begin
  SysGetPPid := LnxSys3(64, 0, 0, 0);
End;

Function SysGetUid : LongInt;
Begin
  SysGetUid := LnxSys3(199, 0, 0, 0) And $FFFF;
End;

Function SysGetGid : LongInt;
Begin
  SysGetGid := LnxSys3(200, 0, 0, 0) And $FFFF;
End;

Function SysGetEUid : LongInt;
Begin
  SysGetEUid := LnxSys3(201, 0, 0, 0) And $FFFF;
End;

Function SysGetEGid : LongInt;
Begin
  SysGetEGid := LnxSys3(202, 0, 0, 0) And $FFFF;
End;

Function SysSetUid(Uid : LongInt) : LongInt;
Begin
  SysSetUid := LnxRes(LnxSys3(213, Uid, 0, 0));
End;

Function SysSetGid(Gid : LongInt) : LongInt;
Begin
  SysSetGid := LnxRes(LnxSys3(214, Gid, 0, 0));
End;

Function SysSetSid : LongInt;
Begin
  SysSetSid := LnxRes(LnxSys3(66, 0, 0, 0));
End;

Function SysSetPgid(Pid, Pgid : LongInt) : LongInt;
Begin
  SysSetPgid := LnxRes(LnxSys3(57, Pid, Pgid, 0));
End;

Function SysGetPgrp : LongInt;
Begin
  SysGetPgrp := LnxSys3(65, 0, 0, 0);
End;

Function SysGetPgid(Pid : LongInt) : LongInt;
Begin
  SysGetPgid := LnxRes(LnxSys3(132, Pid, 0, 0));
End;

Function SysGetSid(Pid : LongInt) : LongInt;
Begin
  SysGetSid := LnxRes(LnxSys3(147, Pid, 0, 0));
End;

Function SysChdir(Const Path : String) : LongInt;
Begin
  SysChdir := LnxRes(LnxSys3(12, LnxZ(Path), 0, 0));
End;

Function SysChroot(Const Path : String) : LongInt;
Begin
  SysChroot := LnxRes(LnxSys3(61, LnxZ(Path), 0, 0));
End;

Function SysGetCwd : String;
Var R : LongInt; S : String;
Begin
  R := LnxSys3(183, LongInt(@LnxZBuf), 255, 0);
  If R <= 0 Then S := '' Else S := SysZStr(LongInt(@LnxZBuf));
  SysGetCwd := S;
End;

Function SysLSeek(Fd, Offset, Whence : LongInt) : LongInt;
Begin
  SysLSeek := LnxRes(LnxSys3(19, Fd, Offset, Whence));
End;

Function SysIoctl(Fd, Request : LongInt; Var Arg) : LongInt;
Begin
  SysIoctl := LnxRes(LnxSys3(54, Fd, Request, LongInt(@Arg)));
End;

Function SysIoctlL(Fd, Request, Arg : LongInt) : LongInt;
Begin
  SysIoctlL := LnxRes(LnxSys3(54, Fd, Request, Arg));
End;

Function SysTime : LongInt;
Begin
  SysTime := LnxSys3(13, 0, 0, 0);
End;

Function SysSync : LongInt;
Begin
  SysSync := LnxSys3(36, 0, 0, 0);
End;

Function SysReboot(Magic1, Magic2, Cmd : LongInt) : LongInt;
Begin
  SysReboot := LnxRes(LnxSys6(88, Magic1, Magic2, Cmd, 0, 0, 0));
End;

Function SysUmask(Mask : LongInt) : LongInt;
Begin
  SysUmask := LnxSys3(60, Mask, 0, 0);
End;

Function SysAlarm(Seconds : LongInt) : LongInt;
Begin
  SysAlarm := LnxSys3(27, Seconds, 0, 0);
End;

Function SysPause : LongInt;
Begin
  SysPause := LnxRes(LnxSys3(29, 0, 0, 0));
End;

Function SysSleep(Seconds : LongInt) : LongInt;
Begin
  LnxTmp[2] := Seconds;
  LnxTmp[3] := 0;
  SysSleep := LnxRes(LnxSys3(162, LongInt(@LnxTmp[2]), 0, 0));
End;

{ sigaction : gestionnaire = adresse de procedure (Procedure(Sig:LongInt))
  ou SIG_DFL / SIG_IGN ; rend l'ancien gestionnaire }
Function SysSigAction(Sig, Handler, Flags : LongInt) : LongInt;
Var A, O : TSysSigAct; R : LongInt;
Begin
  A.Handler := Handler;
  A.Flags := Flags;
  A.Restorer := 0;
  A.MaskLo := 0;
  A.MaskHi := 0;
  R := LnxSys6(174, Sig, LongInt(@A), LongInt(@O), 8, 0, 0);
  If R < 0 Then SysSigAction := LnxRes(R) Else SysSigAction := O.Handler;
End;

Function SysSignal(Sig, Handler : LongInt) : LongInt;
Begin
  SysSignal := SysSigAction(Sig, Handler, SA_RESTART);
End;

{ blocage des signaux : How 0 bloquer, 1 debloquer, 2 remplacer }
Function SysSigProcMask(How, SetLo : LongInt; Var Old : LongInt) : LongInt;
Var S : Array[0..1] Of LongInt; O : Array[0..1] Of LongInt; R : LongInt;
Begin
  S[0] := SetLo;
  S[1] := 0;
  R := LnxSys6(175, How, LongInt(@S), LongInt(@O), 8, 0, 0);
  Old := O[0];
  SysSigProcMask := LnxRes(R);
End;

Function SysUnlink(Const Path : String) : LongInt;
Begin
  SysUnlink := LnxRes(LnxSys3(10, LnxZ(Path), 0, 0));
End;

Function SysLink(Const Old, New : String) : LongInt;
Begin
  SysLink := LnxRes(LnxSys3(9, LnxZ(Old), LnxZ(New), 0));
End;

Function SysSymlink(Const Target, Path : String) : LongInt;
Begin
  SysSymlink := LnxRes(LnxSys3(83, LnxZ(Target), LnxZ(Path), 0));
End;

Function SysReadlink(Const Path : String) : String;
Var R : LongInt; S : String;
Begin
  S := '';
  R := LnxSys3(85, LnxZ(Path), LongInt(@LnxZBuf) + 1280 - 256, 255);
  If R > 0 Then
  Begin
    Mem[0:LongInt(@LnxZBuf) + 1280 - 256 + R] := 0;
    S := SysZStr(LongInt(@LnxZBuf) + 1280 - 256);
  End;
  SysReadlink := S;
End;

Function SysRename(Const Old, New : String) : LongInt;
Begin
  SysRename := LnxRes(LnxSys3(38, LnxZ(Old), LnxZ(New), 0));
End;

Function SysMkdir(Const Path : String; Mode : LongInt) : LongInt;
Begin
  SysMkdir := LnxRes(LnxSys3(39, LnxZ(Path), Mode, 0));
End;

Function SysRmdir(Const Path : String) : LongInt;
Begin
  SysRmdir := LnxRes(LnxSys3(40, LnxZ(Path), 0, 0));
End;

Function SysChmod(Const Path : String; Mode : LongInt) : LongInt;
Begin
  SysChmod := LnxRes(LnxSys3(15, LnxZ(Path), Mode, 0));
End;

Function SysChown(Const Path : String; Uid, Gid : LongInt) : LongInt;
Begin
  SysChown := LnxRes(LnxSys3(212, LnxZ(Path), Uid, Gid));
End;

Function SysFChown(Fd, Uid, Gid : LongInt) : LongInt;
Begin
  SysFChown := LnxRes(LnxSys3(207, Fd, Uid, Gid));
End;

Function SysFChmod(Fd, Mode : LongInt) : LongInt;
Begin
  SysFChmod := LnxRes(LnxSys3(94, Fd, Mode, 0));
End;

Function SysAccess(Const Path : String; Mode : LongInt) : LongInt;
Begin
  SysAccess := LnxRes(LnxSys3(33, LnxZ(Path), Mode, 0));
End;

Function SysMknod(Const Path : String; Mode, Dev : LongInt) : LongInt;
Begin
  SysMknod := LnxRes(LnxSys3(14, LnxZ(Path), Mode, Dev));
End;

Function SysTruncate(Const Path : String; Len : LongInt) : LongInt;
Begin
  SysTruncate := LnxRes(LnxSys3(92, LnxZ(Path), Len, 0));
End;

Function SysStat(Const Path : String; Var St : TSysStat) : LongInt;
Begin
  SysStat := LnxRes(LnxSys3(106, LnxZ(Path), LongInt(@St), 0));
End;

Function SysLStat(Const Path : String; Var St : TSysStat) : LongInt;
Begin
  SysLStat := LnxRes(LnxSys3(107, LnxZ(Path), LongInt(@St), 0));
End;

Function SysFStat(Fd : LongInt; Var St : TSysStat) : LongInt;
Begin
  SysFStat := LnxRes(LnxSys3(108, Fd, LongInt(@St), 0));
End;

Function SysMount(Const Src, Target, FsType : String; Flags : LongInt)
    : LongInt;
Begin
  SysMount := LnxRes(LnxSys6(21, LnxZ(Src), LnxZ(Target), LnxZ(FsType),
                             Flags, 0, 0));
End;

Function SysUmount(Const Target : String) : LongInt;
Begin
  SysUmount := LnxRes(LnxSys3(22, LnxZ(Target), 0, 0));
End;

{ repertoires : SysOpenDir rend un identificateur (0..15) ou -1 }
Function SysOpenDir(Const Path : String) : LongInt;
Var D, Fd : LongInt;
Begin
  SysOpenDir := -1;
  D := 0;
  While (D < 16) And (LnxDirBuf[D] <> 0) Do Inc(D);
  If D >= 16 Then
  Begin
    SysErrno := 24;
    Exit;
  End;
  Fd := LnxRes(LnxSys3(5, LnxZ(Path), $10000, 0));
  If Fd < 0 Then Exit;
  LnxDirFd[D] := Fd;
  LnxDirBuf[D] := HeapAlloc(1, 0, 2048);
  LnxDirPos[D] := 0;
  LnxDirLen[D] := 0;
  SysOpenDir := D;
End;

{ entree suivante (nom, numero d'inode) ; Faux a la fin }
Function SysReadDir(D : LongInt; Var Name : String; Var Ino : LongInt)
    : Boolean;
Var E, R, L : LongInt;
Begin
  SysReadDir := False;
  If (D < 0) Or (D > 15) Or (LnxDirBuf[D] = 0) Then Exit;
  While True Do
  Begin
    If LnxDirPos[D] >= LnxDirLen[D] Then
    Begin
      R := LnxSys3(141, LnxDirFd[D], LnxDirBuf[D], 2048);
      If R <= 0 Then Exit;
      LnxDirLen[D] := R;
      LnxDirPos[D] := 0;
    End;
    E := LnxDirBuf[D] + LnxDirPos[D];
    LnxDirPos[D] := LnxDirPos[D] + MemW[0:E + 8];
    If MemL[0:E] <> 0 Then
    Begin
      Ino := MemL[0:E];
      Name := SysZStr(E + 10);
      SysReadDir := True;
      Exit;
    End;
  End;
End;

Procedure SysCloseDir(D : LongInt);
Begin
  If (D < 0) Or (D > 15) Or (LnxDirBuf[D] = 0) Then Exit;
  LnxSys3(6, LnxDirFd[D], 0, 0);
  HeapFree(1, 0, LnxDirBuf[D]);
  LnxDirBuf[D] := 0;
End;

{ terminaux }
Function SysTcGetAttr(Fd : LongInt; Var T : TSysTermios) : LongInt;
Begin
  SysTcGetAttr := LnxRes(LnxSys3(54, Fd, TCGETS, LongInt(@T)));
End;

Function SysTcSetAttr(Fd, Action : LongInt; Var T : TSysTermios) : LongInt;
Begin
  SysTcSetAttr := LnxRes(LnxSys3(54, Fd, TCSETS + Action, LongInt(@T)));
End;

Function SysIsATty(Fd : LongInt) : Boolean;
Var T : TSysTermios;
Begin
  SysIsATty := LnxSys3(54, Fd, TCGETS, LongInt(@T)) >= 0;
End;

Function SysTcGetPgrp(Fd : LongInt) : LongInt;
Var P : LongInt;
Begin
  If LnxRes(LnxSys3(54, Fd, TIOCGPGRP, LongInt(@P))) < 0 Then
    SysTcGetPgrp := -1
  Else SysTcGetPgrp := P;
End;

Function SysTcSetPgrp(Fd, Pgrp : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := Pgrp;
  SysTcSetPgrp := LnxRes(LnxSys3(54, Fd, TIOCSPGRP, LongInt(@P)));
End;

Function SysGetWinSize(Fd : LongInt; Var W : TSysWinSize) : LongInt;
Begin
  SysGetWinSize := LnxRes(LnxSys3(54, Fd, TIOCGWINSZ, LongInt(@W)));
End;

Function SysUname(Var U : TUtsName) : LongInt;
Var R, B : LongInt;
Begin
  B := HeapAlloc(1, 8, 512);
  R := LnxSys3(122, B, 0, 0);
  If R >= 0 Then
  Begin
    U.SysName := SysZStr(B);
    U.NodeName := SysZStr(B + 65);
    U.Release := SysZStr(B + 130);
    U.Version := SysZStr(B + 195);
    U.Machine := SysZStr(B + 260);
  End;
  HeapFree(1, 0, B);
  SysUname := LnxRes(R);
End;

{ environnement : valeur de la variable Name, ou '' }
Function SysGetEnv(Const Name : String) : String;
Var I, A, K, L : LongInt; Ok : Boolean;
Begin
  SysGetEnv := '';
  L := Length(Name);
  I := 0;
  While MemL[0:LnxEnvp + I * 4] <> 0 Do
  Begin
    A := MemL[0:LnxEnvp + I * 4];
    Ok := True;
    K := 0;
    While Ok And (K < L) Do
    Begin
      If Mem[0:A + K] <> Ord(Name[K + 1]) Then Ok := False;
      Inc(K);
    End;
    If Ok And (Mem[0:A + L] = 61) Then
    Begin
      SysGetEnv := SysZStr(A + L + 1);
      Exit;
    End;
    Inc(I);
  End;
End;

Function SysEnvCount : LongInt;
Var I : LongInt;
Begin
  I := 0;
  While MemL[0:LnxEnvp + I * 4] <> 0 Do Inc(I);
  SysEnvCount := I;
End;

Function SysEnvStr(I : LongInt) : String;
Begin
  If (I < 0) Or (I >= SysEnvCount) Then SysEnvStr := ''
  Else SysEnvStr := SysZStr(MemL[0:LnxEnvp + I * 4]);
End;

{ arguments : adresse de argv, nombre, chaine n }
Function SysArgv : LongInt;
Begin
  SysArgv := LnxArgv;
End;

Function SysEnvp : LongInt;
Begin
  SysEnvp := LnxEnvp;
End;

Function SysArgCount : LongInt;
Begin
  SysArgCount := LnxArgc;
End;

Function SysArgStr(I : LongInt) : String;
Begin
  If (I < 0) Or (I >= LnxArgc) Then SysArgStr := ''
  Else SysArgStr := SysZStr(MemL[0:LnxArgv + I * 4]);
End;

{ construction de argv / envp pour SysArgExec }
Var
  LnxXArg : Array[0..127] Of LongInt;
  LnxXEnv : Array[0..127] Of LongInt;
  LnxXArgN, LnxXEnvN : LongInt;

Procedure SysArgReset;
Begin
  LnxXArgN := 0;
  LnxXEnvN := 0;
End;

Procedure SysArgAdd(Const S : String);
Begin
  If LnxXArgN < 126 Then
  Begin
    LnxXArg[LnxXArgN] := SysNewZ(S);
    Inc(LnxXArgN);
  End;
End;

Procedure SysEnvAdd(Const S : String);
Begin
  If LnxXEnvN < 126 Then
  Begin
    LnxXEnv[LnxXEnvN] := SysNewZ(S);
    Inc(LnxXEnvN);
  End;
End;

Procedure SysEnvInherit;
Var I : LongInt;
Begin
  I := 0;
  While (MemL[0:LnxEnvp + I * 4] <> 0) And (LnxXEnvN < 126) Do
  Begin
    LnxXEnv[LnxXEnvN] := MemL[0:LnxEnvp + I * 4];
    Inc(LnxXEnvN);
    Inc(I);
  End;
End;

Function SysArgExec(Const Path : String) : LongInt;
Begin
  LnxXArg[LnxXArgN] := 0;
  LnxXEnv[LnxXEnvN] := 0;
  SysArgExec := SysExecve(Path, LongInt(@LnxXArg), LongInt(@LnxXEnv));
End;

{ ---------- langue et messages d'erreur ---------- }

{ langue d'une valeur de LANGUAGE : 1 francais (defaut), 2 EN, 3 GR, 4 SP,
  5 IT }
Function SysLangOf(Const V : String) : LongInt;
Var A, B : Char;
Begin
  SysLangOf := 1;
  If Length(V) < 2 Then Exit;
  A := UpCase(V[1]);
  B := UpCase(V[2]);
  If (A = 'E') And (B = 'N') Then SysLangOf := 2
  Else If (A = 'G') And (B = 'R') Then SysLangOf := 3
  Else If (A = 'D') And (B = 'E') Then SysLangOf := 3
  Else If (A = 'S') And (B = 'P') Then SysLangOf := 4
  Else If (A = 'E') And (B = 'S') Then SysLangOf := 4
  Else If (A = 'I') And (B = 'T') Then SysLangOf := 5;
End;

Function SysLang : LongInt;
Begin
  If LnxLangV = 0 Then LnxLangV := SysLangOf(SysGetEnv('LANGUAGE'));
  SysLang := LnxLangV;
End;

Procedure SysSetLang(L : LongInt);
Begin
  LnxLangV := L;
End;

{ texte d'une erreur Linux dans la langue courante }
Function SysErrorText(E : LongInt) : String;
Var L : LongInt; S : String;
Begin
  L := SysLang;
  Case E Of
    1 : Case L Of
          1 : S := 'Operation non permise';
          2 : S := 'Operation not permitted';
          3 : S := 'Operation nicht erlaubt';
          4 : S := 'Operacion no permitida';
          5 : S := 'Operazione non permessa';
        End;
    2 : Case L Of
          1 : S := 'Fichier ou repertoire inexistant';
          2 : S := 'No such file or directory';
          3 : S := 'Datei oder Verzeichnis nicht gefunden';
          4 : S := 'No existe el fichero o directorio';
          5 : S := 'File o directory inesistente';
        End;
    3 : Case L Of
          1 : S := 'Processus inexistant';
          2 : S := 'No such process';
          3 : S := 'Prozess nicht gefunden';
          4 : S := 'No existe el proceso';
          5 : S := 'Processo inesistente';
        End;
    4 : Case L Of
          1 : S := 'Appel systeme interrompu';
          2 : S := 'Interrupted system call';
          3 : S := 'Systemaufruf unterbrochen';
          4 : S := 'Llamada al sistema interrumpida';
          5 : S := 'Chiamata di sistema interrotta';
        End;
    5 : Case L Of
          1 : S := 'Erreur d''entree/sortie';
          2 : S := 'Input/output error';
          3 : S := 'Ein-/Ausgabefehler';
          4 : S := 'Error de entrada/salida';
          5 : S := 'Errore di ingresso/uscita';
        End;
    8 : Case L Of
          1 : S := 'Format d''executable invalide';
          2 : S := 'Exec format error';
          3 : S := 'Ausfuehrungsformat ungueltig';
          4 : S := 'Formato de ejecutable no valido';
          5 : S := 'Formato eseguibile non valido';
        End;
    9 : Case L Of
          1 : S := 'Descripteur de fichier invalide';
          2 : S := 'Bad file descriptor';
          3 : S := 'Ungueltiger Dateideskriptor';
          4 : S := 'Descriptor de fichero erroneo';
          5 : S := 'Descrittore di file non valido';
        End;
    10 : Case L Of
          1 : S := 'Pas de processus fils';
          2 : S := 'No child processes';
          3 : S := 'Keine Kindprozesse';
          4 : S := 'No hay procesos hijos';
          5 : S := 'Nessun processo figlio';
        End;
    11 : Case L Of
          1 : S := 'Ressource temporairement indisponible';
          2 : S := 'Resource temporarily unavailable';
          3 : S := 'Ressource voruebergehend nicht verfuegbar';
          4 : S := 'Recurso no disponible temporalmente';
          5 : S := 'Risorsa temporaneamente non disponibile';
        End;
    12 : Case L Of
          1 : S := 'Memoire insuffisante';
          2 : S := 'Out of memory';
          3 : S := 'Nicht genug Speicher';
          4 : S := 'Memoria agotada';
          5 : S := 'Memoria esaurita';
        End;
    13 : Case L Of
          1 : S := 'Permission refusee';
          2 : S := 'Permission denied';
          3 : S := 'Zugriff verweigert';
          4 : S := 'Permiso denegado';
          5 : S := 'Permesso negato';
        End;
    16 : Case L Of
          1 : S := 'Peripherique ou ressource occupe';
          2 : S := 'Device or resource busy';
          3 : S := 'Geraet oder Ressource belegt';
          4 : S := 'Dispositivo o recurso ocupado';
          5 : S := 'Dispositivo o risorsa occupata';
        End;
    17 : Case L Of
          1 : S := 'Le fichier existe deja';
          2 : S := 'File exists';
          3 : S := 'Datei existiert bereits';
          4 : S := 'El fichero ya existe';
          5 : S := 'Il file esiste gia''';
        End;
    18 : Case L Of
          1 : S := 'Lien entre peripheriques invalide';
          2 : S := 'Invalid cross-device link';
          3 : S := 'Ungueltiger Link ueber Geraete';
          4 : S := 'Enlace entre dispositivos no valido';
          5 : S := 'Collegamento tra dispositivi non valido';
        End;
    19 : Case L Of
          1 : S := 'Peripherique inexistant';
          2 : S := 'No such device';
          3 : S := 'Geraet nicht gefunden';
          4 : S := 'No existe el dispositivo';
          5 : S := 'Dispositivo inesistente';
        End;
    20 : Case L Of
          1 : S := 'Ce n''est pas un repertoire';
          2 : S := 'Not a directory';
          3 : S := 'Kein Verzeichnis';
          4 : S := 'No es un directorio';
          5 : S := 'Non e'' una directory';
        End;
    21 : Case L Of
          1 : S := 'C''est un repertoire';
          2 : S := 'Is a directory';
          3 : S := 'Ist ein Verzeichnis';
          4 : S := 'Es un directorio';
          5 : S := 'E'' una directory';
        End;
    22 : Case L Of
          1 : S := 'Argument invalide';
          2 : S := 'Invalid argument';
          3 : S := 'Ungueltiges Argument';
          4 : S := 'Argumento no valido';
          5 : S := 'Argomento non valido';
        End;
    24 : Case L Of
          1 : S := 'Trop de fichiers ouverts';
          2 : S := 'Too many open files';
          3 : S := 'Zu viele offene Dateien';
          4 : S := 'Demasiados ficheros abiertos';
          5 : S := 'Troppi file aperti';
        End;
    25 : Case L Of
          1 : S := 'Ce n''est pas un terminal';
          2 : S := 'Not a tty';
          3 : S := 'Kein Terminal';
          4 : S := 'No es un terminal';
          5 : S := 'Non e'' un terminale';
        End;
    26 : Case L Of
          1 : S := 'Fichier executable en cours d''utilisation';
          2 : S := 'Text file busy';
          3 : S := 'Programmdatei belegt';
          4 : S := 'Fichero de texto ocupado';
          5 : S := 'File di testo occupato';
        End;
    27 : Case L Of
          1 : S := 'Fichier trop grand';
          2 : S := 'File too large';
          3 : S := 'Datei zu gross';
          4 : S := 'Fichero demasiado grande';
          5 : S := 'File troppo grande';
        End;
    28 : Case L Of
          1 : S := 'Plus de place sur le peripherique';
          2 : S := 'No space left on device';
          3 : S := 'Kein Speicherplatz mehr auf dem Geraet';
          4 : S := 'No queda espacio en el dispositivo';
          5 : S := 'Spazio esaurito sul dispositivo';
        End;
    29 : Case L Of
          1 : S := 'Positionnement impossible';
          2 : S := 'Illegal seek';
          3 : S := 'Ungueltiges Positionieren';
          4 : S := 'Posicionamiento ilegal';
          5 : S := 'Posizionamento non valido';
        End;
    30 : Case L Of
          1 : S := 'Systeme de fichiers en lecture seule';
          2 : S := 'Read-only file system';
          3 : S := 'Dateisystem ist schreibgeschuetzt';
          4 : S := 'Sistema de ficheros de solo lectura';
          5 : S := 'File system di sola lettura';
        End;
    31 : Case L Of
          1 : S := 'Trop de liens';
          2 : S := 'Too many links';
          3 : S := 'Zu viele Links';
          4 : S := 'Demasiados enlaces';
          5 : S := 'Troppi collegamenti';
        End;
    32 : Case L Of
          1 : S := 'Tube casse';
          2 : S := 'Broken pipe';
          3 : S := 'Unterbrochene Pipe';
          4 : S := 'Tuberia rota';
          5 : S := 'Pipe interrotta';
        End;
    36 : Case L Of
          1 : S := 'Nom de fichier trop long';
          2 : S := 'File name too long';
          3 : S := 'Dateiname zu lang';
          4 : S := 'Nombre de fichero demasiado largo';
          5 : S := 'Nome di file troppo lungo';
        End;
    38 : Case L Of
          1 : S := 'Fonction non implantee';
          2 : S := 'Function not implemented';
          3 : S := 'Funktion nicht implementiert';
          4 : S := 'Funcion no implementada';
          5 : S := 'Funzione non implementata';
        End;
    39 : Case L Of
          1 : S := 'Le repertoire n''est pas vide';
          2 : S := 'Directory not empty';
          3 : S := 'Verzeichnis nicht leer';
          4 : S := 'El directorio no esta vacio';
          5 : S := 'La directory non e'' vuota';
        End;
    40 : Case L Of
          1 : S := 'Trop de liens symboliques';
          2 : S := 'Too many levels of symbolic links';
          3 : S := 'Zu viele symbolische Links';
          4 : S := 'Demasiados enlaces simbolicos';
          5 : S := 'Troppi collegamenti simbolici';
        End;
  Else
    Begin
      Str(E, S);
      S := 'Error ' + S;
    End;
  End;
  SysErrorText := S;
End;

{ ---------- noms de comptes : /etc/passwd ---------- }

{ ligne de /etc/passwd -> enregistrement }
Function LnxPwField(Const L : String; N : LongInt) : String;
Var I, K, Cur : LongInt; S : String;
Begin
  Cur := 1;
  K := 1;
  S := '';
  For I := 1 To Length(L) Do
  Begin
    If L[I] = ':' Then
    Begin
      If Cur = N Then Break;
      Inc(Cur);
      S := '';
    End
    Else If Cur = N Then S := S + L[I];
  End;
  LnxPwField := S;
End;

Function LnxToNum(Const S : String) : LongInt;
Var K, V : LongInt;
Begin
  V := 0;
  K := 1;
  While (K <= Length(S)) And (S[K] >= '0') And (S[K] <= '9') Do
  Begin
    V := V * 10 + Ord(S[K]) - 48;
    Inc(K);
  End;
  LnxToNum := V;
End;

Function SysReadLine(Fd : LongInt; Var S : String) : Boolean;
{ ligne suivante de Fd (lecture octet par octet) ; Faux a la fin }
Var C : LongInt; N : LongInt;
Begin
  S := '';
  SysReadLine := False;
  While True Do
  Begin
    N := LnxSys3(3, Fd, LongInt(@LnxTmp[12]), 1);
    If N <= 0 Then Exit;
    SysReadLine := True;
    C := Mem[0:LongInt(@LnxTmp[12])];
    If C = 10 Then Exit;
    If Length(S) < 255 Then S := S + Chr(C);
  End;
End;

Function SysGetPw(Const Name : String; ByUid : Boolean; Uid : LongInt;
    Var P : TSysPasswd) : Boolean;
Var Fd : LongInt; L : String;
Begin
  SysGetPw := False;
  Fd := LnxSys3(5, LnxZ('/etc/passwd'), 0, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
  Begin
    If (L = '') Or (L[1] = '#') Then Continue;
    If ((Not ByUid) And (LnxPwField(L, 1) = Name)) Or
       (ByUid And (LnxToNum(LnxPwField(L, 3)) = Uid)) Then
    Begin
      P.Name := LnxPwField(L, 1);
      P.Pw := LnxPwField(L, 2);
      P.Uid := LnxToNum(LnxPwField(L, 3));
      P.Gid := LnxToNum(LnxPwField(L, 4));
      P.Gecos := LnxPwField(L, 5);
      P.Home := LnxPwField(L, 6);
      P.Shell := LnxPwField(L, 7);
      SysGetPw := True;
      Break;
    End;
  End;
  LnxSys3(6, Fd, 0, 0);
End;

Function SysGetPwNam(Const Name : String; Var P : TSysPasswd) : Boolean;
Begin
  SysGetPwNam := SysGetPw(Name, False, 0, P);
End;

Function SysGetPwUid(Uid : LongInt; Var P : TSysPasswd) : Boolean;
Begin
  SysGetPwUid := SysGetPw('', True, Uid, P);
End;

{ nom du groupe de numero Gid (/etc/group) ; '' si absent }
Function SysGroupName(Gid : LongInt) : String;
Var Fd : LongInt; L : String;
Begin
  SysGroupName := '';
  Fd := LnxSys3(5, LnxZ('/etc/group'), 0, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
    If (L <> '') And (LnxToNum(LnxPwField(L, 3)) = Gid) Then
    Begin
      SysGroupName := LnxPwField(L, 1);
      Break;
    End;
  LnxSys3(6, Fd, 0, 0);
End;

{ mot de passe code (format V7 de LINUX-0, 13 caracteres : sel de 2 + 11) }
Function SysCrypt(Const Pw, Salt : String) : String;
Const Ch : String[64] =
  './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
Var
  A, B, C, D, X, R, K, Bit, V, W : LongInt;
  S, T : String;
Begin
  T := Salt + '..';
  T := Copy(T, 1, 2);
  S := T + Pw;
  A := $6A09; B := $BB67; C := $3C6E; D := $A54F;
  For R := 1 To 32 Do
    For K := 1 To Length(S) Do
    Begin
      X := Ord(S[K]);
      A := ((A Xor X) * 31421 + 1) And $FFFF;
      B := ((B Xor A) * 31421 + X) And $FFFF;
      C := ((C Xor B) * 31421 + 7) And $FFFF;
      D := ((D Xor C) * 31421 + A) And $FFFF;
    End;
  Bit := 0;
  For K := 1 To 11 Do
  Begin
    V := 0;
    For R := 1 To 6 Do
    Begin
      If Bit >= 64 Then W := 0
      Else
      Begin
        Case Bit Div 16 Of
          0 : W := A;
          1 : W := B;
          2 : W := C;
        Else W := D;
        End;
        W := (W Shr (15 - Bit Mod 16)) And 1;
      End;
      V := V * 2 + W;
      Inc(Bit);
    End;
    T := T + Ch[V + 1];
  End;
  SysCrypt := T;
End;
