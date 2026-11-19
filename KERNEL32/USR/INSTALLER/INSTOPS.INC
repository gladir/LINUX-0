{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: INSTOPS.INC : operations d'installation : journal, lancement
      de commandes (mkfs, mkswap), repertoires, ecriture de fichiers,
      extraction de l'archive tar du systeme (/cdrom/system.tar) avec
      progression reelle. Inclure apres DISKS.INC. Le programme principal
      definit OpUiHook.
}

Const
  LOGPATH = '/var/log/install.log';

Var
  OpLogFd : LongInt;
  OpErr : String;
  OpBytes, OpTotalBytes, OpLastPm, OpNFiles : LongInt;
  OpTzEnv : String;           { TZ transmis aux programmes lances }
  OpElapsed : LongInt;        { secondes ecoulees de la commande en cours }
  OpTimeout : LongInt;        { secondes sans nouvelle sortie : commande tuee }
  OpHung : Boolean;           { la derniere commande a ete interrompue }
  OpHungProg : String;
  OpTailL : Array[0..11] Of String[100];   { dernieres lignes du journal }
  OpTailN : LongInt;
  OpStage, OpSub : String;
  { progression exposee par mkfs (fichier K32_PROGRESS : phase permille
    groupe groupes) et par l'extraction (nom courant) }
  OpPh, OpPm, OpGrp, OpNGrp : LongInt;     { OpPm < 0 : pas de compteur }
  OpCur : String;             { entree de l'archive en cours d'extraction }
  OpLastBeat : LongInt;       { dernier battement de l'interface (ms) }
  TestMkfs : String;          { preseed testmkfs : remplace mkfs (essais) }
  OpSlow : String;            { preseed mkfsslow : ms par ecriture (essais) }

{ mise a jour de l'interface : message (ou '') et progression des fichiers
  (millieme, -1 : inchangee) ; definie par le programme principal }
Procedure OpUiHook(Const S : String; Permille : LongInt); Forward;

{ lit le fichier de progression de mkfs : "phase permille groupe groupes" ;
  rend Vrai si son contenu a change depuis le dernier appel }
Var OpProgLast : String;

Function OpReadProg : Boolean;
Var F, N, I, K, V, E : LongInt; B : Array[0..63] Of Byte; S, T : String;
    Vals : Array[0..3] Of LongInt;
Begin
  OpReadProg := False;
  F := SysOpen('/tmp/k32-progress', O_RDONLY, 0);
  If F < 0 Then Exit;
  N := SysRead(F, B, 63);
  SysClose(F);
  If N <= 0 Then Exit;
  S := '';
  For I := 0 To N - 1 Do
    If B[I] >= 32 Then S := S + Chr(B[I]);
  If S = OpProgLast Then Exit;
  OpProgLast := S;
  OpReadProg := True;
  { quatre entiers separes par des espaces }
  K := 0;
  T := '';
  For I := 0 To 3 Do Vals[I] := 0;
  For I := 1 To Length(S) + 1 Do
    If (I > Length(S)) Or (S[I] = ' ') Then
    Begin
      If (T <> '') And (K < 4) Then
      Begin
        Val(T, V, E);
        If E = 0 Then Vals[K] := V;
        Inc(K);
      End;
      T := '';
    End
    Else T := T + S[I];
  If K >= 2 Then
  Begin
    OpPh := Vals[0];
    OpPm := Vals[1];
    OpGrp := Vals[2];
    OpNGrp := Vals[3];
  End;
End;

Function OpNum2(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  If Length(S) < 2 Then S := '0' + S;
  OpNum2 := S;
End;

{ marqueur pour les essais : /dev/console si k32setup.verbose }
Var OpMarkFd : LongInt;

Procedure OpMark(Const S : String);
Var L : String;
Begin
  If OpMarkFd < 0 Then Exit;
  L := 'K32SETUP: ' + UiAscii(S) + #13#10;
  SysWrite(OpMarkFd, L[1], Length(L));
End;

Procedure OpLogOpen;
Begin
  SysMkdir('/var', 493);
  SysMkdir('/var/log', 493);
  OpLogFd := SysOpen(LOGPATH, O_WRONLY Or O_CREAT Or O_APPEND, 420);
End;

{ une ligne du journal /var/log/install.log et de l'ecran }
Procedure OpLog(Const S : String);
Var T : LongInt; L : String;
Begin
  T := SysTime Mod 86400;
  L := OpNum2(T Div 3600) + ':' + OpNum2((T Mod 3600) Div 60) + ':' +
       OpNum2(T Mod 60) + ' ' + UiAscii(S) + #10;
  If OpLogFd >= 0 Then SysWrite(OpLogFd, L[1], Length(L));
  OpMark(S);
  OpUiHook(S, -1);
End;

Function OpFileExists(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  OpFileExists := SysStat(P, St) = 0;
End;

{ mkdir -p }
Procedure OpMkdirP(Const Path : String; Mode : LongInt);
Var I : LongInt; P : String;
Begin
  I := 2;
  While I <= Length(Path) + 1 Do
  Begin
    If (I > Length(Path)) Or (Path[I] = '/') Then
    Begin
      P := Copy(Path, 1, I - 1);
      If Not OpFileExists(P) Then SysMkdir(P, Mode);
    End;
    Inc(I);
  End;
End;

Function OpDirOf(Const P : String) : String;
Var I : LongInt;
Begin
  I := Length(P);
  While (I > 0) And (P[I] <> '/') Do Dec(I);
  If I <= 1 Then OpDirOf := '/' Else OpDirOf := Copy(P, 1, I - 1);
End;

{ ecrit (ou ajoute) un fichier de texte (octets tels quels) }
Function OpWriteFile(Const Path, Data : String; Mode : LongInt;
  Append : Boolean) : Boolean;
Var Fd, Fl : LongInt;
Begin
  OpWriteFile := False;
  OpMkdirP(OpDirOf(Path), 493);
  Fl := O_WRONLY Or O_CREAT;
  If Append Then Fl := Fl Or O_APPEND Else Fl := Fl Or O_TRUNC;
  Fd := SysOpen(Path, Fl, Mode);
  If Fd < 0 Then
  Begin
    OpErr := Path + ' : ' + SysErrorText(SysErrno);
    Exit;
  End;
  If Length(Data) > 0 Then
    If SysWrite(Fd, Data[1], Length(Data)) <> Length(Data) Then
    Begin
      OpErr := Path + ' : ' + SysErrorText(SysErrno);
      SysClose(Fd);
      Exit;
    End;
  SysClose(Fd);
  SysChmod(Path, Mode);
  OpWriteFile := True;
End;

{ contenu d'un petit fichier (255 octets au plus), '' s'il est absent }
Function OpReadSmall(Const Path : String) : String;
Var Fd, N : LongInt; Buf : Array[0..255] Of Byte; S : String; I : LongInt;
Begin
  OpReadSmall := '';
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  N := SysRead(Fd, Buf, 255);
  SysClose(Fd);
  S := '';
  For I := 0 To N - 1 Do S := S + Chr(Buf[I]);
  OpReadSmall := S;
End;

{ copie de fichier ; Mode < 0 : conserve celui de la source }
Function OpCopyFile(Const Src, Dst : String; Mode : LongInt) : Boolean;
Var Fi, Fo, N : LongInt; Buf : Array[0..16383] Of Byte; St : TSysStat;
Begin
  OpCopyFile := False;
  Fi := SysOpen(Src, O_RDONLY, 0);
  If Fi < 0 Then
  Begin
    OpErr := Src + ' : ' + SysErrorText(SysErrno);
    Exit;
  End;
  If Mode < 0 Then
  Begin
    Mode := 420;
    If SysStat(Src, St) = 0 Then Mode := St.Mode And $FFF;
  End;
  OpMkdirP(OpDirOf(Dst), 493);
  Fo := SysOpen(Dst, O_WRONLY Or O_CREAT Or O_TRUNC, Mode);
  If Fo < 0 Then
  Begin
    OpErr := Dst + ' : ' + SysErrorText(SysErrno);
    SysClose(Fi);
    Exit;
  End;
  Repeat
    N := SysRead(Fi, Buf, 16384);
    If N > 0 Then
      If SysWrite(Fo, Buf, N) <> N Then
      Begin
        OpErr := Dst + ' : ' + SysErrorText(SysErrno);
        SysClose(Fi);
        SysClose(Fo);
        Exit;
      End;
  Until N <= 0;
  SysClose(Fi);
  SysClose(Fo);
  SysChmod(Dst, Mode);
  OpCopyFile := True;
End;

{ lance un programme (arguments separes par des espaces) ; sortie dans le
  journal ; rend le code de sortie (127 : lancement impossible) }
Function OpExec(Const Prog, Args : String) : LongInt;
Var Pid, St, I, S, T0, LastGrow, LastSz, W2, Now_, Dm : LongInt; W : String;
    Sta : TSysStat;
Begin
  SysArgReset;
  W := Prog;
  I := Length(W);
  While (I > 0) And (W[I] <> '/') Do Dec(I);
  SysArgAdd(Copy(W, I + 1, 100));
  I := 1;
  While I <= Length(Args) Do
  Begin
    While (I <= Length(Args)) And (Args[I] = ' ') Do Inc(I);
    S := I;
    While (I <= Length(Args)) And (Args[I] <> ' ') Do Inc(I);
    If I > S Then SysArgAdd(Copy(Args, S, I - S));
  End;
  SysEnvInherit;
  If OpTzEnv <> '' Then SysEnvAdd('TZ=' + OpTzEnv);
  SysEnvAdd('K32_PROGRESS=/tmp/k32-progress');
  If OpSlow <> '' Then SysEnvAdd('K32_MKFS_SLOW=' + OpSlow);
  SysUnlink('/tmp/k32-progress');
  OpProgLast := '';
  OpPm := -1;
  OpPh := 0;
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    If OpLogFd >= 0 Then
    Begin
      SysDup2(OpLogFd, 1);
      SysDup2(OpLogFd, 2);
    End;
    SysArgExec(Prog);
    SysExit(127);
  End;
  If Pid < 0 Then
  Begin
    OpExec := 127;
    Exit;
  End;
  St := 0;
  T0 := SysTime;
  LastGrow := T0;
  LastSz := -1;
  OpHung := False;
  OpElapsed := 0;
  While True Do
  Begin
    W2 := SysWaitPid(Pid, St, 1);
    If (W2 = Pid) Or (W2 < 0) Then Break;
    SysPoll(LongInt(@Dm), 0, 100);
    Now_ := SysTime;
    { une commande dont le compteur avance n'est pas bloquee }
    If OpReadProg Then LastGrow := Now_;
    OpElapsed := Now_ - T0;
    If OpLogFd >= 0 Then
      If SysFStat(OpLogFd, Sta) = 0 Then
        If Sta.Size <> LastSz Then
        Begin
          LastSz := Sta.Size;
          LastGrow := Now_;
        End;
    OpUiHook('', -2);
    If (OpTimeout > 0) And (Now_ - LastGrow > OpTimeout) Then
    Begin
      SysKill(Pid, 9);
      SysWaitPid(Pid, St, 0);
      OpHung := True;
      OpHungProg := Prog;
      OpExec := 125;
      Exit;
    End;
  End;
  OpPm := -1;
  If SysWIfExited(St) Then OpExec := SysWExitStatus(St)
  Else OpExec := 126;
End;

{ les N dernieres lignes (au plus 12) du journal dans OpTailL }
Procedure OpTailLog(N : LongInt);
Var Fd, Sz, Rd, I : LongInt; B : Array[0..4095] Of Byte; L : String;
    All : Array[0..63] Of String[100]; Cnt : LongInt; St : TSysStat;
Begin
  OpTailN := 0;
  Fd := SysOpen(LOGPATH, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Sz := 0;
  If SysFStat(Fd, St) = 0 Then Sz := St.Size;
  If Sz > 4000 Then SysLSeek(Fd, Sz - 4000, 0);
  Rd := SysRead(Fd, B, 4096);
  SysClose(Fd);
  If Rd < 0 Then Exit;
  Cnt := 0;
  L := '';
  For I := 0 To Rd - 1 Do
  Begin
    If B[I] = 10 Then
    Begin
      If (Cnt < 64) And (L <> '') Then
      Begin
        All[Cnt] := L;
        Inc(Cnt);
      End;
      L := '';
    End
    Else If B[I] <> 13 Then
      If Length(L) < 100 Then L := L + Chr(B[I]);
  End;
  If (L <> '') And (Cnt < 64) Then
  Begin
    All[Cnt] := L;
    Inc(Cnt);
  End;
  If N > 12 Then N := 12;
  I := Cnt - N;
  If I < 0 Then I := 0;
  While I < Cnt Do
  Begin
    OpTailL[OpTailN] := All[I];
    Inc(OpTailN);
    Inc(I);
  End;
End;

{ ---- extraction du tar du systeme ---- }

Function OpReadFull(Fd : LongInt; Var Buf; N : LongInt) : LongInt;
Var Got, R, A : LongInt;
Begin
  Got := 0;
  A := LongInt(@Buf);
  While Got < N Do
  Begin
    R := LnxSys3(3, Fd, A + Got, N - Got);
    If R <= 0 Then Break;
    Got := Got + R;
  End;
  OpReadFull := Got;
End;

Function OpHStr(Var H : Array Of Byte; Off, Len : LongInt) : String;
Var S : String; I : LongInt;
Begin
  S := '';
  I := 0;
  While (I < Len) And (H[Off + I] <> 0) Do
  Begin
    S := S + Chr(H[Off + I]);
    Inc(I);
  End;
  OpHStr := S;
End;

Function OpHOct(Var H : Array Of Byte; Off, Len : LongInt) : LongInt;
Var V, I : LongInt;
Begin
  V := 0;
  For I := 0 To Len - 1 Do
    If (H[Off + I] >= 48) And (H[Off + I] <= 55) Then
      V := V * 8 + H[Off + I] - 48
    Else If (H[Off + I] <> 32) And (V > 0) Then Break;
  OpHOct := V;
End;

Procedure OpTick(Delta : LongInt);
Var Pm, Tn : LongInt;
Begin
  OpBytes := OpBytes + Delta;
  { battement de l'interface (chrono, indicateur d'activite) au moins 4 fois
    par seconde meme sans nouveau pourcent }
  Tn := GetTickCount;
  If (Tn - OpLastBeat > 250) Or (Tn - OpLastBeat < 0) Then
  Begin
    OpLastBeat := Tn;
    OpUiHook('', -2);
  End;
  If OpTotalBytes > 0 Then
  Begin
    Pm := OpBytes Div (OpTotalBytes Div 1000 + 1);
    If Pm > 1000 Then Pm := 1000;
    If Pm <> OpLastPm Then
    Begin
      OpLastPm := Pm;
      OpUiHook('', Pm);
    End;
  End;
End;

{ extrait l'archive TarPath sous Dest ; False en cas d'erreur (OpErr) }
Function OpExtract(Const TarPath, Dest : String) : Boolean;
Var
  Fd, Out, Sz, Left, Chunk, I, Mode, Uid, Gid, Mt : LongInt;
  Hdr : Array[0..511] Of Byte;
  Buf : Array[0..32767] Of Byte;
  Name, LongName, Link, Full : String;
  Typ : Byte;
  St : TSysStat;
  Tms : Array[0..1] Of LongInt;
  Zero : Boolean;
  NFiles : LongInt;
Begin
  OpExtract := False;
  Fd := SysOpen(TarPath, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    OpErr := TarPath + ' : ' + SysErrorText(SysErrno);
    Exit;
  End;
  If SysStat(TarPath, St) = 0 Then OpTotalBytes := St.Size Else
    OpTotalBytes := 0;
  OpBytes := 0;
  OpLastPm := -1;
  LongName := '';
  NFiles := 0;
  While True Do
  Begin
    If OpReadFull(Fd, Hdr, 512) <> 512 Then Break;
    OpTick(512);
    Zero := True;
    For I := 0 To 511 Do
      If Hdr[I] <> 0 Then
      Begin
        Zero := False;
        Break;
      End;
    If Zero Then Break;
    Typ := Hdr[156];
    Sz := OpHOct(Hdr, 124, 12);
    Mode := OpHOct(Hdr, 100, 8);
    Uid := OpHOct(Hdr, 108, 8);
    Gid := OpHOct(Hdr, 116, 8);
    Mt := OpHOct(Hdr, 136, 12);
    If (Typ = Ord('L')) Or (Typ = Ord('x')) Or (Typ = Ord('g')) Then
    Begin
      { nom long GNU ou en-tete etendu : lire (et jeter) les donnees }
      Left := Sz;
      Name := '';
      While Left > 0 Do
      Begin
        Chunk := 512;
        If OpReadFull(Fd, Buf, Chunk) <> Chunk Then Break;
        OpTick(Chunk);
        If (Typ = Ord('L')) And (Length(Name) < 200) Then
          For I := 0 To 511 Do
            If (Buf[I] <> 0) And (Length(Name) < 250) Then
              Name := Name + Chr(Buf[I]);
        Left := Left - 512;
      End;
      If Typ = Ord('L') Then LongName := Name;
      Continue;
    End;
    Name := OpHStr(Hdr, 0, 100);
    If (Hdr[345] <> 0) And (Hdr[257] = 117) Then
      Name := OpHStr(Hdr, 345, 155) + '/' + Name;
    If LongName <> '' Then
    Begin
      Name := LongName;
      LongName := '';
    End;
    If Copy(Name, 1, 2) = './' Then Name := Copy(Name, 3, 250);
    While (Length(Name) > 0) And (Name[Length(Name)] = '/') Do
      Delete(Name, Length(Name), 1);
    Full := Dest + '/' + Name;
    OpCur := '/' + Name;
    Link := OpHStr(Hdr, 157, 100);
    If Name = '' Then
    Begin
      { racine de l'archive : rien a creer }
      Left := Sz;
    End
    Else If Typ = Ord('5') Then
    Begin
      OpMkdirP(Full, 493);
      SysChmod(Full, Mode And $FFF);
      SysChown(Full, Uid, Gid);
      Left := 0;
    End
    Else If Typ = Ord('2') Then
    Begin
      OpMkdirP(OpDirOf(Full), 493);
      SysUnlink(Full);
      If SysSymlink(Link, Full) < 0 Then
      Begin
        OpErr := Full + ' : ' + SysErrorText(SysErrno);
        SysClose(Fd);
        Exit;
      End;
      Left := 0;
    End
    Else If Typ = Ord('1') Then
    Begin
      OpMkdirP(OpDirOf(Full), 493);
      SysUnlink(Full);
      If SysLink(Dest + '/' + Link, Full) < 0 Then
        OpLog('lien dur ignore : ' + Name);
      Left := 0;
    End
    Else If (Typ = 0) Or (Typ = Ord('0')) Or (Typ = Ord('7')) Then
    Begin
      OpMkdirP(OpDirOf(Full), 493);
      Out := SysOpen(Full, O_WRONLY Or O_CREAT Or O_TRUNC, Mode And $1FF);
      If Out < 0 Then
      Begin
        OpErr := Full + ' : ' + SysErrorText(SysErrno);
        SysClose(Fd);
        Exit;
      End;
      Left := Sz;
      While Left > 0 Do
      Begin
        Chunk := Left;
        If Chunk > 32768 Then Chunk := 32768;
        If OpReadFull(Fd, Buf, Chunk) <> Chunk Then
        Begin
          OpErr := TarPath + ' : lecture';
          SysClose(Out);
          SysClose(Fd);
          Exit;
        End;
        If SysWrite(Out, Buf, Chunk) <> Chunk Then
        Begin
          OpErr := Full + ' : ' + SysErrorText(SysErrno);
          SysClose(Out);
          SysClose(Fd);
          Exit;
        End;
        OpTick(Chunk);
        Left := Left - Chunk;
      End;
      SysClose(Out);
      SysChmod(Full, Mode And $FFF);
      SysChown(Full, Uid, Gid);
      Tms[0] := Mt; Tms[1] := Mt;
      LnxSys3(30, LnxZ(Full), LongInt(@Tms), 0);
      Left := 0;
      Inc(NFiles);
      { le bloc final est complete a 512 octets }
      Left := (512 - Sz Mod 512) Mod 512;
      If Left > 0 Then
      Begin
        OpReadFull(Fd, Buf, Left);
        OpTick(Left);
      End;
      Left := 0;
    End
    Else Left := 0;
    { donnees d'une entree ignoree (nom vide, type inconnu) }
    If (Left = 0) And (Typ <> 0) And (Typ <> Ord('0')) And (Typ <> Ord('7')) And
       (Sz > 0) And (Typ <> Ord('5')) Then
      Left := (Sz + 511) Div 512 * 512;
    While Left > 0 Do
    Begin
      Chunk := Left;
      If Chunk > 32768 Then Chunk := 32768;
      If OpReadFull(Fd, Buf, Chunk) <> Chunk Then Break;
      OpTick(Chunk);
      Left := Left - Chunk;
    End;
  End;
  SysClose(Fd);
  OpUiHook('', 1000);
  OpNFiles := NFiles;
  OpExtract := True;
End;
