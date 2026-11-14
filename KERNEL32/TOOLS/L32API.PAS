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
    R := LnxSys3(114, Pid, LongInt(@LnxTmp), 0);   { wait4 }
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

Type
  TUtsName = Record
    SysName  : String[64];
    NodeName : String[64];
    Release  : String[64];
    Version  : String[64];
    Machine  : String[64];
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
  SysFork := LnxSys3(2, 0, 0, 0);
End;

Function SysRead(Fd : LongInt; Var Buf; Count : LongInt) : LongInt;
Begin
  SysRead := LnxSys3(3, Fd, LongInt(@Buf), Count);
End;

Function SysWrite(Fd : LongInt; Var Buf; Count : LongInt) : LongInt;
Begin
  SysWrite := LnxSys3(4, Fd, LongInt(@Buf), Count);
End;

Function SysOpen(Path : LongInt; Flags, Mode : LongInt) : LongInt;
Begin
  SysOpen := LnxSys3(5, Path, Flags, Mode);
End;

Function SysClose(Fd : LongInt) : LongInt;
Begin
  SysClose := LnxSys3(6, Fd, 0, 0);
End;

Function SysWaitPid(Pid : LongInt; Var Status : LongInt; Options : LongInt)
    : LongInt;
Begin
  SysWaitPid := LnxSys3(114, Pid, LongInt(@Status), Options);
End;

Function SysExecve(Path, Argv, Envp : LongInt) : LongInt;
Begin
  SysExecve := LnxSys3(11, Path, Argv, Envp);
End;

Function SysPipe(Var Fds : LongInt) : LongInt;
Begin
  SysPipe := LnxSys3(42, LongInt(@Fds), 0, 0);
End;

Function SysDup(Fd : LongInt) : LongInt;
Begin
  SysDup := LnxSys3(41, Fd, 0, 0);
End;

Function SysDup2(Fd, Fd2 : LongInt) : LongInt;
Begin
  SysDup2 := LnxSys3(63, Fd, Fd2, 0);
End;

Function SysKill(Pid, Sig : LongInt) : LongInt;
Begin
  SysKill := LnxSys3(37, Pid, Sig, 0);
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
  SysGetUid := LnxSys3(24, 0, 0, 0);
End;

Function SysChdir(Path : LongInt) : LongInt;
Begin
  SysChdir := LnxSys3(12, Path, 0, 0);
End;

Function SysLSeek(Fd, Offset, Whence : LongInt) : LongInt;
Begin
  SysLSeek := LnxSys3(19, Fd, Offset, Whence);
End;

Function SysIoctl(Fd, Request : LongInt; Var Arg) : LongInt;
Begin
  SysIoctl := LnxSys3(54, Fd, Request, LongInt(@Arg));
End;

Function SysTime : LongInt;
Begin
  SysTime := LnxSys3(13, 0, 0, 0);
End;

Function SysSigaction(Sig, Act, OldAct : LongInt) : LongInt;
Begin
  SysSigaction := LnxSys3(67, Sig, Act, OldAct);
End;

Function SysSignal(Sig, Handler : LongInt) : LongInt;
Begin
  SysSignal := LnxSys3(48, Sig, Handler, 0);
End;

Function SysSync : LongInt;
Begin
  SysSync := LnxSys3(36, 0, 0, 0);
End;

Function SysReboot(Magic1, Magic2, Cmd : LongInt) : LongInt;
Begin
  SysReboot := LnxSys3(88, Magic1, Magic2, Cmd);
End;

{ nom d'un champ ASCIIZ de la structure new_utsname (6 champs de 65 octets) }
Procedure LnxUtsField(Base : LongInt; Var S : String);
Var K : LongInt;
Begin
  K := 0;
  While (Mem[0:Base + K] <> 0) And (K < 64) Do
  Begin
    S[K + 1] := Chr(Mem[0:Base + K]);
    Inc(K);
  End;
  S[0] := Chr(K);
End;

Function SysUname(Var U : TUtsName) : LongInt;
Var R, B : LongInt;
Begin
  B := HeapAlloc(1, 8, 512);
  R := LnxSys3(122, B, 0, 0);
  If R >= 0 Then
  Begin
    LnxUtsField(B, U.SysName);
    LnxUtsField(B + 65, U.NodeName);
    LnxUtsField(B + 130, U.Release);
    LnxUtsField(B + 195, U.Version);
    LnxUtsField(B + 260, U.Machine);
  End;
  HeapFree(1, 0, B);
  SysUname := R;
End;
