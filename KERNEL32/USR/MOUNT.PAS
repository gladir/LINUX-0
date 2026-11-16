{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/mount : monte un systeme de fichiers.
    mount                       affiche les montages (/proc/mounts)
    mount [-t type] [-o options] source cible
    mount cible | source        (entree de /etc/fstab)
    mount -a [-t type] [-O types] monte tout /etc/fstab (sauf noauto, swap,
                                ce qui est deja monte)
    mount -L nom | -U uuid cible    source retrouvee par nom ou UUID
    mount --bind|-B, --rbind|-R, --move|-M, --make-private|shared|slave|
      unbindable
  Options (-o) : ro rw remount bind rbind move nosuid suid nodev dev noexec
    exec sync async dirsync noatime atime nodiratime diratime relatime
    norelatime strictatime lazytime mand silent loop loop=/dev/loopN
    offset=N sizelimit=N defaults auto noauto user nouser _netdev nofail
    x-... ; les autres (data=ordered, noload, errors=...) vont au noyau.
    Un fichier ordinaire (ou -o loop) est monte par /dev/loopN (autoclear).
    Sans -t : type lu dans le superbloc, sinon essai des types de
    /proc/filesystems. -v bavard, -f simulation, -n -s -w ignores, -r = -o ro.
  Messages en cinq langues (LANGUAGE).
}

Program Mount;

{$I FSPROBE.INC}

Const
  MAXTAB = 64;
  MS_NOSUID = 2; MS_NODEV = 4; MS_NOEXEC = 8; MS_SYNCHRONOUS = 16;
  MS_MANDLOCK = 64; MS_DIRSYNC = 128; MS_NOATIME = 1024;
  MS_NODIRATIME = 2048; MS_BIND = 4096; MS_MOVE = 8192; MS_REC = 16384;
  MS_SILENT = 32768; MS_UNBINDABLE = 131072; MS_PRIVATE = 262144;
  MS_SLAVE = 524288; MS_SHARED = 1048576; MS_RELATIME = 2097152;
  MS_STRICTATIME = 16777216; MS_LAZYTIME = 33554432;
  LOOP_SET_FD = $4C00; LOOP_CLR_FD = $4C01; LOOP_SET_STATUS64 = $4C04;
  LOOP_GET_STATUS64 = $4C05; LOOP_CTL_GET_FREE = $4C82;
  M : Array[1..10, 1..5] Of PChar = (
    ('Usage : mount [-a] [-t type] [-o options] [source] [cible]',
     'Usage: mount [-a] [-t type] [-o options] [source] [target]',
     'Aufruf: mount [-a] [-t Typ] [-o Optionen] [Quelle] [Ziel]',
     'Uso: mount [-a] [-t tipo] [-o opciones] [origen] [destino]',
     'Uso: mount [-a] [-t tipo] [-o opzioni] [origine] [destinazione]'),
    ('mount : ', 'mount: ', 'mount: ', 'mount: ', 'mount: '),
    ('le point de montage n''existe pas', 'mount point does not exist',
     'Einhaengepunkt existiert nicht', 'el punto de montaje no existe',
     'il punto di mount non esiste'),
    ('le peripherique n''existe pas', 'special device does not exist',
     'Geraet existiert nicht', 'el dispositivo no existe',
     'il dispositivo non esiste'),
    ('type de systeme de fichiers inconnu : ',
     'unknown filesystem type ', 'unbekannter Dateisystemtyp ',
     'tipo de sistema de ficheros desconocido ',
     'tipo di file system sconosciuto '),
    ('introuvable dans /etc/fstab', 'can''t find in /etc/fstab',
     'nicht in /etc/fstab gefunden', 'no se encuentra en /etc/fstab',
     'non trovato in /etc/fstab'),
    ('deja monte ou occupe', 'already mounted or mount point busy',
     'bereits eingehaengt oder belegt', 'ya montado u ocupado',
     'gia'' montato o occupato'),
    ('type incorrect, option ou superbloc errone',
     'wrong fs type, bad option, bad superblock',
     'falscher Typ, Option oder Superblock', 'tipo, opcion o superbloque mal',
     'tipo, opzione o superblocco errati'),
    ('aucun peripherique pour ', 'no device found for ',
     'kein Geraet fuer ', 'ningun dispositivo para ',
     'nessun dispositivo per '),
    ('monte sur', 'mounted on', 'eingehaengt auf', 'montado en',
     'montato su'));

Type
  TTab = Record
    Src, Dir, Typ, Opt : String;
  End;

Var
  Tab : Array[0..MAXTAB - 1] Of TTab;
  NTab : LongInt;
  Cur : Array[0..MAXTAB - 1] Of TTab;
  NCur : LongInt;
  OptT, OptO, OptX, Verbose, Fake, DoAll, Ro_, Rw_ : String;
  Verb, FakeF, AllF : Boolean;
  Pos1, Pos2 : String;
  NPos : LongInt;
  Cmd, LblW, UuidW : String;
  FsList : String;
  Flags0 : LongInt;
  Rc : LongInt;

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

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
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

Procedure Die(Const S : String; Code : LongInt);
Begin
  SysPut(2, Msg(2) + S + #10);
  SysExit(Code);
End;

Procedure LoadTab(Const Path : String; Var T : Array Of TTab; Var N : LongInt);
Var F : LongInt; L : String;
Begin
  N := 0;
  F := SysOpen(Path, O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    If (Field(L, 1) = '') Or (Field(L, 1)[1] = '#') Then Continue;
    If N > High(T) Then Break;
    T[N].Src := Unesc(Field(L, 1));
    T[N].Dir := Unesc(Field(L, 2));
    T[N].Typ := Field(L, 3);
    T[N].Opt := Field(L, 4);
    If T[N].Opt = '' Then T[N].Opt := 'defaults';
    Inc(N);
  End;
  SysClose(F);
End;

{ ---------- options de montage ---------- }

Function HasOpt(Const L, T : String) : Boolean;
Var K, J : LongInt;
Begin
  HasOpt := False;
  K := 1;
  While K <= Length(L) + 1 Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    If Copy(L, K, J - K) = T Then HasOpt := True;
    K := J + 1;
  End;
End;

Function OptVal(Const L, T : String) : String;
Var K, J : LongInt; S : String;
Begin
  OptVal := '';
  K := 1;
  While K <= Length(L) + 1 Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    S := Copy(L, K, J - K);
    If Copy(S, 1, Length(T) + 1) = T + '=' Then
      OptVal := Copy(S, Length(T) + 2, 200);
    K := J + 1;
  End;
End;

Procedure SetBit(Var F : LongInt; B : LongInt; On : Boolean);
Begin
  If On Then F := F Or B Else F := F And Not B;
End;

{ analyse "a,b=c,..." : Flags modifies, Data = options pour le noyau,
  Loop : -o loop, Lo* : parametres du peripherique de boucle }
Procedure ParseOptions(Const L : String; Var Flags : LongInt; Var Data : String;
    Var Loop : Boolean; Var LoopDev : String; Var LoOff, LoLim : LongInt);
Var K, J : LongInt; S : String;
Begin
  K := 1;
  While K <= Length(L) + 1 Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    S := Copy(L, K, J - K);
    K := J + 1;
    If S = '' Then Continue;
    If S = 'ro' Then SetBit(Flags, 1, True)
    Else If S = 'rw' Then SetBit(Flags, 1, False)
    Else If S = 'remount' Then SetBit(Flags, MS_REMOUNT, True)
    Else If S = 'bind' Then SetBit(Flags, MS_BIND, True)
    Else If S = 'rbind' Then SetBit(Flags, MS_BIND Or MS_REC, True)
    Else If S = 'move' Then SetBit(Flags, MS_MOVE, True)
    Else If S = 'nosuid' Then SetBit(Flags, MS_NOSUID, True)
    Else If S = 'suid' Then SetBit(Flags, MS_NOSUID, False)
    Else If S = 'nodev' Then SetBit(Flags, MS_NODEV, True)
    Else If S = 'dev' Then SetBit(Flags, MS_NODEV, False)
    Else If S = 'noexec' Then SetBit(Flags, MS_NOEXEC, True)
    Else If S = 'exec' Then SetBit(Flags, MS_NOEXEC, False)
    Else If S = 'sync' Then SetBit(Flags, MS_SYNCHRONOUS, True)
    Else If S = 'async' Then SetBit(Flags, MS_SYNCHRONOUS, False)
    Else If S = 'dirsync' Then SetBit(Flags, MS_DIRSYNC, True)
    Else If S = 'noatime' Then SetBit(Flags, MS_NOATIME, True)
    Else If S = 'atime' Then SetBit(Flags, MS_NOATIME, False)
    Else If S = 'nodiratime' Then SetBit(Flags, MS_NODIRATIME, True)
    Else If S = 'diratime' Then SetBit(Flags, MS_NODIRATIME, False)
    Else If S = 'relatime' Then SetBit(Flags, MS_RELATIME, True)
    Else If S = 'norelatime' Then SetBit(Flags, MS_RELATIME, False)
    Else If S = 'strictatime' Then SetBit(Flags, MS_STRICTATIME, True)
    Else If S = 'lazytime' Then SetBit(Flags, MS_LAZYTIME, True)
    Else If S = 'mand' Then SetBit(Flags, MS_MANDLOCK, True)
    Else If S = 'nomand' Then SetBit(Flags, MS_MANDLOCK, False)
    Else If S = 'silent' Then SetBit(Flags, MS_SILENT, True)
    Else If S = 'loud' Then SetBit(Flags, MS_SILENT, False)
    Else If S = 'loop' Then Loop := True
    Else If Copy(S, 1, 5) = 'loop=' Then
    Begin
      Loop := True;
      LoopDev := Copy(S, 6, 100);
    End
    Else If Copy(S, 1, 7) = 'offset=' Then LoOff := ToNum(Copy(S, 8, 20))
    Else If Copy(S, 1, 10) = 'sizelimit=' Then LoLim := ToNum(Copy(S, 11, 20))
    Else If (S = 'defaults') Or (S = 'auto') Or (S = 'noauto') Or
            (S = 'user') Or (S = 'nouser') Or (S = 'users') Or
            (S = 'owner') Or (S = 'group') Or (S = '_netdev') Or
            (S = 'nofail') Or (S = 'sloppy') Or (Copy(S, 1, 2) = 'x-') Or
            (Copy(S, 1, 8) = 'comment=') Then
    Else
    Begin
      If Data <> '' Then Data := Data + ',';
      Data := Data + S;
    End;
  End;
End;

{ ---------- peripherique de boucle ---------- }

Type
  TLoopInfo = Record
    Device, Inode, RDevice, Offset, SizeLimit : Array[0..1] Of LongInt;
    Number, EncType, EncKeySize, Flags : LongInt;
    FileName : Array[0..63] Of Byte;
    CryptName : Array[0..63] Of Byte;
    EncKey : Array[0..31] Of Byte;
    Init : Array[0..3] Of LongInt;
  End;

Function FreeLoop : String;
Var Ctl, K, Fd : LongInt; Li : TLoopInfo;
Begin
  FreeLoop := '';
  Ctl := SysOpen('/dev/loop-control', O_RDWR, 0);
  If Ctl >= 0 Then
  Begin
    K := SysIoctlL(Ctl, LOOP_CTL_GET_FREE, 0);
    SysClose(Ctl);
    If K >= 0 Then
    Begin
      FreeLoop := '/dev/loop' + NumS(K);
      Exit;
    End;
  End;
  For K := 0 To 15 Do
  Begin
    Fd := SysOpen('/dev/loop' + NumS(K), O_RDONLY, 0);
    If Fd < 0 Then Continue;
    FillChar(Li, SizeOf(Li), 0);
    If SysIoctl(Fd, LOOP_GET_STATUS64, Li) < 0 Then
    Begin
      SysClose(Fd);
      FreeLoop := '/dev/loop' + NumS(K);
      Exit;
    End;
    SysClose(Fd);
  End;
End;

{ associe File a un peripherique de boucle ; rend son nom ('' : echec) }
Function SetupLoop(Const FileN, WantDev : String; LoOff, LoLim : LongInt;
    RdOnly : Boolean) : String;
Var Dev : String; Fd, Lf, K : LongInt; Li : TLoopInfo;
Begin
  SetupLoop := '';
  Dev := WantDev;
  If Dev = '' Then Dev := FreeLoop;
  If Dev = '' Then Exit;
  Fd := SysOpen(Dev, O_RDWR, 0);
  If Fd < 0 Then Fd := SysOpen(Dev, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  If RdOnly Then Lf := SysOpen(FileN, O_RDONLY, 0)
  Else
  Begin
    Lf := SysOpen(FileN, O_RDWR, 0);
    If Lf < 0 Then
    Begin
      Lf := SysOpen(FileN, O_RDONLY, 0);
      RdOnly := True;
    End;
  End;
  If Lf < 0 Then
  Begin
    SysClose(Fd);
    Exit;
  End;
  If SysIoctlL(Fd, LOOP_SET_FD, Lf) < 0 Then
  Begin
    SysClose(Lf);
    SysClose(Fd);
    Exit;
  End;
  FillChar(Li, SizeOf(Li), 0);
  Li.Offset[0] := LoOff;
  Li.SizeLimit[0] := LoLim;
  Li.Flags := 4;                     { LO_FLAGS_AUTOCLEAR }
  If RdOnly Then Li.Flags := Li.Flags Or 1;
  For K := 1 To Length(FileN) Do
    If K <= 63 Then Li.FileName[K - 1] := Ord(FileN[K]);
  SysIoctl(Fd, LOOP_SET_STATUS64, Li);
  SysClose(Lf);
  SysClose(Fd);
  SetupLoop := Dev;
End;

{ peripheriques de boucle mis en place par mount : /var/run/mount.loops }
Procedure RecordLoop(Const Dev : String);
Var Fd : LongInt;
Begin
  Fd := SysOpen('/var/run/mount.loops', O_WRONLY Or O_CREAT Or O_APPEND, 420);
  If Fd < 0 Then Exit;
  SysPut(Fd, Dev + #10);
  SysClose(Fd);
End;

Procedure FreeLoopDev(Const Dev : String);
Var Fd : LongInt;
Begin
  Fd := SysOpen(Dev, O_RDONLY, 0);
  If Fd < 0 Then Exit;
  SysIoctlL(Fd, LOOP_CLR_FD, 0);
  SysClose(Fd);
End;

{ ---------- recherche d'une source par nom ou UUID ---------- }

Function FindByTag(Const Kind, Val_ : String) : String;
Var F : LongInt; L, Nm, Typ, Lbl, Uuid : String; V2 : String;
Begin
  FindByTag := '';
  F := SysOpen('/proc/partitions', O_RDONLY, 0);
  If F < 0 Then Exit;
  V2 := Val_;
  While SysReadLine(F, L) Do
  Begin
    Nm := Field(L, 4);
    If (Nm = '') Or (Nm = 'name') Then Continue;
    Probe('/dev/' + Nm, Typ, Lbl, Uuid);
    If (Kind = 'LABEL') And (Lbl = V2) Then FindByTag := '/dev/' + Nm;
    If (Kind = 'UUID') And (Uuid = V2) Then FindByTag := '/dev/' + Nm;
    If FindByTag <> '' Then Break;
  End;
  SysClose(F);
End;

Function ResolveSrc(Const S : String) : String;
Var P : LongInt; R : String;
Begin
  ResolveSrc := S;
  If Copy(S, 1, 5) = 'UUID=' Then R := FindByTag('UUID', Copy(S, 6, 100))
  Else If Copy(S, 1, 6) = 'LABEL=' Then R := FindByTag('LABEL', Copy(S, 7, 100))
  Else If Copy(S, 1, 18) = '/dev/disk/by-uuid/' Then
    R := FindByTag('UUID', Copy(S, 19, 100))
  Else If Copy(S, 1, 19) = '/dev/disk/by-label/' Then
    R := FindByTag('LABEL', Copy(S, 20, 100))
  Else Exit;
  If R = '' Then
  Begin
    P := Pos('=', S);
    Die(Msg(9) + S, 32);
  End;
  ResolveSrc := R;
End;

{ ---------- montage ---------- }

Function IsMounted(Const Dir : String) : Boolean;
Var K : LongInt;
Begin
  IsMounted := False;
  For K := 0 To NCur - 1 Do
    If Cur[K].Dir = Dir Then IsMounted := True;
End;

Function CurOptions(Const Dir : String) : String;
Var K : LongInt;
Begin
  CurOptions := '';
  For K := 0 To NCur - 1 Do
    If Cur[K].Dir = Dir Then CurOptions := Cur[K].Opt;
End;

Function TryMount(Const Src, Dir, Typ : String; Flags : LongInt;
    Const Data : String) : LongInt;
Var P : LongInt;
Begin
  P := 0;
  If Data <> '' Then P := LnxZ(Data);
  TryMount := LnxSys6(21, LnxZ(Src), LnxZ(Dir), LnxZ(Typ), Flags, P, 0);
End;

{ monte ; rend 0 ou un code d'erreur (errno positif) }
Function DoMount(SrcIn, Dir, Typ, Optl : String; Verb_ : Boolean) : LongInt;
Var Flags, LoOff, LoLim, R, K : LongInt; Data, LoopDev, Src, T, Lb : String;
    Loop, Auto : Boolean; St : TSysStat; Tl : String; Rem : String;
    Lbl, Uuid, Found : String; Tried : String;
Begin
  Flags := 0;
  Data := '';
  Loop := False;
  LoopDev := '';
  LoOff := 0;
  LoLim := 0;
  Src := ResolveSrc(SrcIn);
  { remontage : conserve les options courantes }
  If HasOpt(Optl, 'remount') Then
  Begin
    Rem := CurOptions(Dir);
    ParseOptions(Rem, Flags, Data, Loop, LoopDev, LoOff, LoLim);
    Data := '';
    Loop := False;
  End;
  ParseOptions(Optl, Flags, Data, Loop, LoopDev, LoOff, LoLim);
  If FakeF Then
  Begin
    DoMount := 0;
    Exit;
  End;
  If SysStat(Dir, St) < 0 Then
  Begin
    SysPut(2, Msg(2) + Dir + ': ' + Msg(3) + '.' + #10);
    DoMount := 2;
    Exit;
  End;
  If (Flags And (MS_BIND Or MS_MOVE Or MS_REMOUNT)) <> 0 Then
  Begin
    If Typ = '' Then T := 'none' Else T := Typ;
    R := TryMount(Src, Dir, T, Flags, Data);
    If R < 0 Then
    Begin
      DoMount := -R;
      Exit;
    End;
    DoMount := 0;
    Exit;
  End;
  Auto := False;
  { source = fichier ordinaire : peripherique de boucle }
  If (Typ <> 'proc') And (Typ <> 'tmpfs') And (Typ <> 'sysfs') And
     (Src <> '') And (Src[1] = '/') And (SysStat(Src, St) = 0) Then
    If ((St.Mode And $F000) = $8000) Or Loop Then
    Begin
      LoopDev := SetupLoop(Src, LoopDev, LoOff, LoLim,
                           (Flags And 1) <> 0);
      If LoopDev = '' Then
      Begin
        DoMount := 22;
        Exit;
      End;
      Src := LoopDev;
      Auto := True;
      RecordLoop(LoopDev);
    End;
  If Typ = '' Then
  Begin
    { type lu dans le superbloc, sinon essai de chaque type }
    Probe(Src, T, Lbl, Uuid);
    If (T = 'swap') Or (T = '') Then T := '';
    If T <> '' Then
    Begin
      R := TryMount(Src, Dir, T, Flags, Data);
      If R >= 0 Then
      Begin
        DoMount := 0;
        Exit;
      End;
      K := -R;
      If Auto Then FreeLoopDev(LoopDev);
      DoMount := K;
      Exit;
    End;
    Found := '';
    FsList := 'ext4,ext3,ext2,vfat,iso9660,minix,cramfs,romfs';
    K := 1;
    While K <= Length(FsList) + 1 Do
    Begin
      Tl := '';
      While (K <= Length(FsList)) And (FsList[K] <> ',') Do
      Begin
        Tl := Tl + FsList[K];
        Inc(K);
      End;
      Inc(K);
      If Tl = '' Then Continue;
      R := TryMount(Src, Dir, Tl, Flags, Data);
      If R >= 0 Then
      Begin
        DoMount := 0;
        Exit;
      End;
      If R <> -22 Then Found := NumS(-R);
    End;
    If Auto Then FreeLoopDev(LoopDev);
    DoMount := 22;
    Exit;
  End;
  { liste de types : ext4,ext3 }
  K := 1;
  R := -22;
  Tried := Typ;
  While K <= Length(Tried) + 1 Do
  Begin
    Tl := '';
    While (K <= Length(Tried)) And (Tried[K] <> ',') Do
    Begin
      Tl := Tl + Tried[K];
      Inc(K);
    End;
    Inc(K);
    If Tl = '' Then Continue;
    R := TryMount(Src, Dir, Tl, Flags, Data);
    If R >= 0 Then
    Begin
      DoMount := 0;
      Exit;
    End;
  End;
  If Auto Then FreeLoopDev(LoopDev);
  DoMount := -R;
End;

Procedure Report(Const Src, Dir, Typ : String; Code : LongInt);
Begin
  If Code = 0 Then Exit;
  SysPut(2, Msg(2) + Dir + ': ');
  If Code = 16 Then SysPut(2, Msg(7))
  Else If Code = 22 Then SysPut(2, Msg(8) + ' ' + Src)
  Else If Code = 19 Then SysPut(2, Msg(5) + Typ)
  Else If Code = 2 Then SysPut(2, Msg(4))
  Else SysPut(2, SysErrorText(Code));
  SysPut(2, '.' + #10);
End;

Procedure ShowMounts;
Var K : LongInt;
Begin
  For K := 0 To NCur - 1 Do
  Begin
    If (OptT <> '') And Not HasOpt(OptT, Cur[K].Typ) Then Continue;
    SysPut(1, Cur[K].Src + ' on ' + Cur[K].Dir + ' type ' + Cur[K].Typ +
           ' (' + Cur[K].Opt + ')' + #10);
  End;
End;

Procedure MountAll;
Var K, C : LongInt;
Begin
  For K := 0 To NTab - 1 Do
  Begin
    If Tab[K].Typ = 'swap' Then Continue;
    If Tab[K].Typ = 'ignore' Then Continue;
    If HasOpt(Tab[K].Opt, 'noauto') Then Continue;
    If (OptT <> '') And Not HasOpt(OptT, Tab[K].Typ) Then Continue;
    If (OptX <> '') And HasOpt(OptX, Tab[K].Typ) Then Continue;
    If IsMounted(Tab[K].Dir) Then Continue;
    C := DoMount(Tab[K].Src, Tab[K].Dir, Tab[K].Typ, Tab[K].Opt, Verb);
    If C <> 0 Then
    Begin
      If Not HasOpt(Tab[K].Opt, 'nofail') Then Rc := 32;
      Report(Tab[K].Src, Tab[K].Dir, Tab[K].Typ, C);
    End
    Else If Verb Then
      SysPut(1, 'mount: ' + Tab[K].Src + ' ' + Msg(10) + ' ' + Tab[K].Dir +
             '.' + #10);
  End;
End;

Var
  I, K, C, NP : LongInt;
  A, Typ, Opts, Src, Dir : String;
  Pos_ : Array[1..4] Of String;
  Found : Boolean;

BEGIN
  OptT := ''; OptO := ''; OptX := ''; LblW := ''; UuidW := '';
  Verb := False; FakeF := False; AllF := False;
  NP := 0;
  Rc := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-t') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      OptT := SysArgStr(I);
    End
    Else If (A = '-o') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      If OptO <> '' Then OptO := OptO + ',';
      OptO := OptO + SysArgStr(I);
    End
    Else If (A = '-O') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      OptX := SysArgStr(I);
    End
    Else If (A = '-L') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      LblW := SysArgStr(I);
    End
    Else If (A = '-U') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      UuidW := SysArgStr(I);
    End
    Else If (A = '-T') And (I + 1 < SysArgCount) Then Inc(I)
    Else If (A = '-h') Or (A = '--help') Or (A = '/?') Then
    Begin
      SysPut(1, Msg(1) + #10);
      SysExit(0);
    End
    Else If (A = '-a') Or (A = '--all') Then AllF := True
    Else If (A = '-v') Or (A = '--verbose') Then Verb := True
    Else If (A = '-f') Or (A = '--fake') Then FakeF := True
    Else If (A = '-r') Or (A = '--read-only') Then
    Begin
      If OptO <> '' Then OptO := OptO + ',';
      OptO := OptO + 'ro';
    End
    Else If (A = '-w') Or (A = '--rw') Or (A = '--read-write') Then
    Begin
      If OptO <> '' Then OptO := OptO + ',';
      OptO := OptO + 'rw';
    End
    Else If (A = '-B') Or (A = '--bind') Then OptO := OptO + ',bind'
    Else If (A = '-R') Or (A = '--rbind') Then OptO := OptO + ',rbind'
    Else If (A = '-M') Or (A = '--move') Then OptO := OptO + ',move'
    Else If A = '--make-private' Then OptO := OptO + ',make-private'
    Else If (A = '-n') Or (A = '-s') Or (A = '-i') Or (A = '-l') Or
            (A = '--no-mtab') Or (A = '--sloppy') Then
    Else If (Length(A) > 1) And (A[1] = '-') And (A[2] <> '-') Then
    Begin
      { options groupees : -vf, -ro ... }
      For K := 2 To Length(A) Do
        Case A[K] Of
          'a' : AllF := True;
          'v' : Verb := True;
          'f' : FakeF := True;
          'r' : OptO := OptO + ',ro';
          'w' : OptO := OptO + ',rw';
          'n', 's', 'i', 'l' : ;
        End;
    End
    Else
    Begin
      Inc(NP);
      If NP <= 4 Then Pos_[NP] := A;
    End;
    Inc(I);
  End;
  While (OptO <> '') And (OptO[1] = ',') Do OptO := Copy(OptO, 2, 255);
  LoadTab('/proc/mounts', Cur, NCur);
  LoadTab('/etc/fstab', Tab, NTab);
  If AllF Then
  Begin
    MountAll;
    SysExit(Rc);
  End;
  If (NP = 0) And (LblW = '') And (UuidW = '') Then
  Begin
    ShowMounts;
    SysExit(0);
  End;
  Src := '';
  Dir := '';
  Typ := OptT;
  Opts := OptO;
  If LblW <> '' Then
  Begin
    Src := FindByTag('LABEL', LblW);
    If Src = '' Then Die(Msg(9) + 'LABEL=' + LblW, 32);
    If NP > 0 Then Dir := Pos_[1];
  End
  Else If UuidW <> '' Then
  Begin
    Src := FindByTag('UUID', UuidW);
    If Src = '' Then Die(Msg(9) + 'UUID=' + UuidW, 32);
    If NP > 0 Then Dir := Pos_[1];
  End
  Else If NP = 1 Then
  Begin
    { une seule valeur : entree de /etc/fstab (cible ou source) }
    Found := False;
    For K := 0 To NTab - 1 Do
      If (Tab[K].Dir = Pos_[1]) Or (Tab[K].Src = Pos_[1]) Then
      Begin
        Found := True;
        Src := Tab[K].Src;
        Dir := Tab[K].Dir;
        If Typ = '' Then Typ := Tab[K].Typ;
        If Opts <> '' Then Opts := Tab[K].Opt + ',' + Opts
        Else Opts := Tab[K].Opt;
        Break;
      End;
    If Not Found Then
      For K := 0 To NCur - 1 Do
        If (Cur[K].Dir = Pos_[1]) Or (Cur[K].Src = Pos_[1]) Then
        Begin
          { deja monte : remontage, liaison... d'un point existant }
          Found := True;
          Src := Cur[K].Src;
          Dir := Cur[K].Dir;
          If Typ = '' Then Typ := Cur[K].Typ;
        End;
    If Not Found Then
    Begin
      SysPut(2, Msg(2) + Pos_[1] + ': ' + Msg(6) + '.' + #10);
      SysExit(1);
    End;
  End
  Else
  Begin
    Src := Pos_[1];
    Dir := Pos_[2];
  End;
  If (Dir = '') Then Dir := Pos_[1];
  If HasOpt(Opts, 'make-private') Then
  Begin
    C := TryMount('none', Dir, 'none', MS_PRIVATE, '');
    If C < 0 Then Die(Dir + ': ' + SysErrorText(-C), 1);
    SysExit(0);
  End;
  C := DoMount(Src, Dir, Typ, Opts, Verb);
  If C <> 0 Then
  Begin
    Report(Src, Dir, Typ, C);
    SysExit(32);
  End;
  If Verb Then SysPut(1, 'mount: ' + Src + ' ' + Msg(10) + ' ' + Dir + '.' +
                      #10);
END.
