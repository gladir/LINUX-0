{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/install : installe KERNEL32 sur un disque dur IDE.
   Le systeme en cours d'execution (la racine /, par exemple amorce depuis un
   autre disque, un CD ou une image) sert de source. L'installateur :
     1. partitionne le disque cible (MBR, une partition Linux 83h active
        commencant au secteur 2048),
     2. y cree un systeme de fichiers ext2 (par defaut blocs de 1 Ko, inodes
        de 128 octets, groupes de 8*bloc blocs, revision 1, fonctions
        filetype et sparse_super : l'equivalent de mke2fs -t ext2 -b 1024
        -I 128 -O none,filetype,sparse_super ; -b 2048|4096 et -I 256 admis)
        ecrit directement sur le peripherique,
     3. y copie l'arborescence de / (sans le contenu de /proc, /sys, /dev,
        /tmp, /mnt) avec modes, proprietaires, dates, liens symboliques et
        fichiers speciaux ; /etc/profile recoit la langue choisie
        (LANGUAGE=XX),
     4. installe le MBR et le chargeur stage2 (52 secteurs apres le MBR) tires
        de /usr/share/boot/MBR.BIN et STAGE2.BIN.
   Usage : install [-d disque] [-l langue] [-s Mo] [-r racine] [-b taille]
           [-I inode] [-N inodes] [-t type] [-O fonctions] [-J size=Mo]
           [-L nom] [-m pct] [-j] [-y] [-q]
           (mkfs.ext2, mkfs.ext3, mkfs.ext4, mke2fs : memes options)
     -t  ext2 (defaut), ext3 (journal jbd2, dir_index) ou ext4 (journal,
         extents, flex_bg, uninit_bg, huge_file, dir_nlink, extra_isize,
         inodes de 256 octets par defaut) ; -O  liste de fonctions ajoutees
         ou retirees (^nom) : extents, flex_bg, 64bit, metadata_csum,
         uninit_bg, dir_index, has_journal, huge_file, dir_nlink, extra_isize,
         large_file, ext_attr, none ; -J size=Mo : taille du journal ;
         -j : journal (ext3) ; -L : nom du volume ; -m : blocs reserves (%)
     -d  disque cible (defaut : demande ; ex. /dev/hdb)
     -l  langue du systeme installe : FR, EN, GR (allemand), SP, IT
     -s  taille de la partition en Mo (defaut : tout le disque)
     -b  taille des blocs : 1024 (defaut), 2048, 4096 ; -I  taille d'inode :
         128 (defaut) ou 256 ; -N  nombre total d'inodes (defaut : un par
         4 blocs de groupe ; arrondi a un bloc de table par groupe)
     -r  racine source (defaut /) ; -y  ne rien demander (essais automatiques)
       -q  silencieux
   Messages en cinq langues (LANGUAGE ou choix au debut).
}

Program Install;

Const
  MAXGRP = 256;
  MAXBLK = 8388608;           { 8 M blocs : 2 Go en 1 Ko, 32 Go en 4 Ko }
  MAXDIRENT = 4000;
  MAXEXT = 8192;
  M : Array[1..18, 1..5] Of PChar = (
    ('Installation de LINUX-0 KERNEL32', 'LINUX-0 KERNEL32 installation',
     'Installation von LINUX-0 KERNEL32', 'Instalacion de LINUX-0 KERNEL32',
     'Installazione di LINUX-0 KERNEL32'),
    ('Langue : 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [1] : ',
     'Language: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [2]: ',
     'Sprache: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [3]: ',
     'Idioma: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [4]: ',
     'Lingua: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [5]: '),
    ('Disque cible (par exemple /dev/hdb) : ',
      'Target disk (for example /dev/hdb): ',
     'Zieldatentraeger (zum Beispiel /dev/hdb): ',
       'Disco de destino (por ejemplo /dev/hdb): ',
     'Disco di destinazione (per esempio /dev/hdb): '),
    ('TOUT le contenu du disque sera efface. Continuer (oui/non) ? ',
     'ALL data on the disk will be erased. Continue (yes/no)? ',
     'ALLE Daten auf dem Datentraeger werden geloescht. Fortfahren (ja/nein)? ',
     'TODO el contenido del disco se borrara. Continuar (si/no)? ',
     'TUTTI i dati del disco saranno cancellati. Continuare (si/no)? '),
    ('Annule.', 'Cancelled.', 'Abgebrochen.', 'Cancelado.', 'Annullato.'),
    ('Partitionnement et amorce...', 'Partitioning...', 'Partitionierung...',
     'Particionando...', 'Partizionamento...'),
    ('Creation du systeme de fichiers ext2...',
      'Creating the ext2 file system...',
     'Erstelle das ext2-Dateisystem...',
       'Creando el sistema de ficheros ext2...',
     'Creazione del file system ext2...'),
    ('Copie du systeme...', 'Copying the system...', 'Kopiere das System...',
     'Copiando el sistema...', 'Copia del sistema...'),
    ('Installation du chargeur d''amorce...', 'Installing the boot loader...',
     'Installiere den Bootlader...', 'Instalando el cargador de arranque...',
     'Installazione del boot loader...'),
    ('Installation terminee. Retirez le support d''installation et redemarrez.',
     'Installation complete. Remove the installation media and reboot.',
     'Installation abgeschlossen. Medium entfernen und neu starten.',
     'Instalacion terminada. Retire el medio de instalacion y reinicie.',
     'Installazione completata. Rimuovere il supporto e riavviare.'),
    ('Erreur : ', 'Error: ', 'Fehler: ', 'Error: ', 'Errore: '),
    ('disque inaccessible ou trop petit', 'disk not accessible or too small',
     'Datentraeger nicht zugreifbar oder zu klein',
       'disco inaccesible o demasiado pequeno',
     'disco inaccessibile o troppo piccolo'),
    ('plus de place sur le disque cible', 'target disk is full',
     'Zieldatentraeger ist voll', 'el disco de destino esta lleno',
     'il disco di destinazione e'' pieno'),
    ('Usage : install [-d disque] [-l FR|EN|GR|SP|IT] [-s Mo] [-y] [-q]',
     'Usage: install [-d disk] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]',
     'Aufruf: install [-d Platte] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]',
     'Uso: install [-d disco] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]',
     'Uso: install [-d disco] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]'),
    ('Fichiers copies : ', 'Files copied: ', 'Kopierte Dateien: ',
      'Ficheros copiados: ',
     'File copiati: '),
    ('MBR.BIN ou STAGE2.BIN introuvable dans /usr/share/boot',
      'MBR.BIN or STAGE2.BIN not found in /usr/share/boot',
     'MBR.BIN oder STAGE2.BIN fehlt in /usr/share/boot',
       'No se encuentra MBR.BIN o STAGE2.BIN en /usr/share/boot',
     'MBR.BIN o STAGE2.BIN non trovato in /usr/share/boot'),
    ('Systeme de fichiers ext2 cree.', 'ext2 file system created.',
     'ext2-Dateisystem erstellt.', 'Sistema de ficheros ext2 creado.',
     'File system ext2 creato.'),
    ('Option inconnue ou fonction non geree : ',
     'Unknown option or unsupported feature: ',
     'Unbekannte Option oder Funktion: ',
     'Opcion desconocida o funcion no soportada: ',
     'Opzione sconosciuta o funzione non supportata: '));
  LangCode : Array[1..5] Of String[2] = ('FR', 'EN', 'GR', 'SP', 'IT');

Type
  TBlk15 = Array[0..14] Of LongInt;
  TDirEnt = Record
    Name : String[63];
    Ino : LongInt;
    Typ : LongInt;
  End;
  PDirEnts = ^TDirEnts;
  TDirEnts = Array[0..MAXDIRENT - 1] Of TDirEnt;

Var
  Fd : LongInt;                        { peripherique cible }
  PartStart : LongInt;                 { secteur de debut de la partition }
  NBlocks, NGroups, GdtBlocks : LongInt;
  { geometrie : -b (1024, 2048, 4096), -I (128, 256), -N (nombre d'inodes) }
  BS, LogBs, BPG, IPG, ISZ, ITB, FirstData, WantInodes : LongInt;
  BlkBm : Array[0..MAXBLK Div 8 - 1] Of Byte;
  InoBm : Array[0..1048575] Of Byte;   { jusqu'a 8 M inodes }
  GrpFreeBlk, GrpFreeIno, GrpDirs : Array[0..MAXGRP - 1] Of LongInt;
  GrpBBm, GrpIBm, GrpITab : Array[0..MAXGRP - 1] Of LongInt;
  FreeBlocks, FreeInodes : LongInt;
  Cursor : LongInt;                    { prochain bloc a essayer }
  NextIno : LongInt;
  Buf : Array[0..4095] Of Byte;
  Zero : Array[0..4095] Of Byte;
  { ecritures groupees (1 Mo) : tampon de zeros, de relecture et du journal }
  ZBuf, RBuf, JBuf : Array[0..1048575] Of Byte;
  { progression : fichier K32_PROGRESS (phase permille groupe groupes) }
  ProgPath : String;
  ProgT, WDone, WTot, ProgPh, SlowMs : LongInt;
  Now : LongInt;
  Quiet, Yes : Boolean;
  Lang : LongInt;
  Copied : LongInt;
  NewLang, SrcRoot : String;
  Fail : Boolean;
  { type de systeme de fichiers et fonctions (-t, -O) }
  FsName : String;
  FsType : LongInt;                    { 2, 3 ou 4 }
  FeatSparse, FeatFiletype, FeatJournal, FeatDirIdx, FeatExtAttr : Boolean;
  FeatExtents, FeatFlex, Feat64, FeatMcsum, FeatGdtCsum : Boolean;
  FeatHuge, FeatDirNlink, FeatExtra, FeatLarge : Boolean;
  FlexSz, LogFlex, DescSz : LongInt;   { groupes par groupe flex, taille d'un
                                         descripteur de groupe }
  JrnBlocks, JrnMb, ResPct : LongInt;
  VolName : String;
  GotInode, GotFeat : Boolean;
  FsUuid : Array[0..15] Of Byte;
  CsumSeed : LongInt;
  FsCrcTab : Array[0..255] Of LongInt;
  Crc16Tab : Array[0..255] Of LongInt;
  GrpFlags, GrpUnused : Array[0..MAXGRP - 1] Of LongInt;
  GrpZeroed : Array[0..MAXGRP - 1] Of Boolean;   { table d'inodes mise a zero }
  GrpBCsum, GrpICsum : Array[0..MAXGRP - 1] Of LongInt;
  { extents du fichier en cours }
  ExtLog, ExtPhys, ExtLen : Array[0..MAXEXT - 1] Of LongInt;
  ExtN : LongInt;
  FFlags : LongInt;                    { i_flags du fichier en cours }
  JrnInode : TBlk15;
  JrnSize : LongInt;

Function Msg(Id : LongInt) : String;
Var P : PChar; X : String; K : LongInt;
Begin
  P := M[Id, Lang];
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  If FsName <> 'ext2' Then
  Begin
    K := Pos('ext2', X);
    While K > 0 Do
    Begin
      X := Copy(X, 1, K - 1) + FsName + Copy(X, K + 4, 255);
      K := Pos('ext2', X);
    End;
  End;
  Msg := X;
End;

Procedure Say(Const S : String);
Begin
  If Not Quiet Then SysPut(1, S + #10);
End;

Procedure Die(Const S : String);
Begin
  SysPut(2, Msg(11) + S + #10);
  SysExit(1);
End;

{ ---------- acces au peripherique ---------- }

Procedure WriteAt(Off : LongInt; Addr, Len : LongInt);
Var R, Done : LongInt;
Begin
  If SysLSeek(Fd, Off, SEEK_SET) < 0 Then Die('lseek');
  Done := 0;
  While Done < Len Do
  Begin
    R := LnxSys3(4, Fd, Addr + Done, Len - Done);
    If R <= 0 Then Die('write ' + SysErrorText(-R));
    Done := Done + R;
  End;
End;

{ Ecriture a l'octet Rem du secteur Sect (512 octets) : decalage de 64 bits
  par llseek, necessaire au-dela de 2 Gio (partitions de plus de 2 Go) }
Procedure WriteAtS(Sect, Rem, Addr, Len : LongInt);
Var R, Done : LongInt; Res : Array[0..1] Of LongInt;
Begin
  If SysLLSeek(Fd, (Sect Shr 23) And $1FF, (Sect Shl 9) Or Rem,
     LongInt(@Res[0]), SEEK_SET) < 0 Then Die('lseek');
  Done := 0;
  While Done < Len Do
  Begin
    R := LnxSys3(4, Fd, Addr + Done, Len - Done);
    If R <= 0 Then Die('write ' + SysErrorText(-R));
    Done := Done + R;
  End;
End;

Procedure WriteBlk(Blk : LongInt; Addr : LongInt);
Begin
  WriteAtS(PartStart + Blk * (BS Div 512), 0, Addr, BS);
End;

{ lecture a l'octet 0 du secteur Sect : rend le nombre d'octets lus }
Function ReadAtS(Sect, Addr, Len : LongInt) : LongInt;
Var R, Done : LongInt; Res : Array[0..1] Of LongInt;
Begin
  ReadAtS := 0;
  If SysLLSeek(Fd, (Sect Shr 23) And $1FF, Sect Shl 9, LongInt(@Res[0]),
     SEEK_SET) < 0 Then Exit;
  Done := 0;
  While Done < Len Do
  Begin
    R := LnxSys3(3, Fd, Addr + Done, Len - Done);
    If R <= 0 Then Break;
    Done := Done + R;
  End;
  ReadAtS := Done;
End;

Function AllZero(Addr, Len : LongInt) : Boolean;
Var I : LongInt;
Begin
  AllZero := False;
  For I := 0 To (Len Div 4) - 1 Do
    If MemL[0:Addr + I * 4] <> 0 Then Exit;
  AllZero := True;
End;

{ progression : une ligne "phase permille groupe groupes" ecrite (au plus
  6 fois par seconde) dans le fichier K32_PROGRESS que l'installateur lit }
Procedure ProgPut(Ph, G : LongInt; Force : Boolean);
Var T, Pm, F : LongInt; L, A, B, C : String;
Begin
  If ProgPath = '' Then Exit;
  T := GetTickCount;
  If (Not Force) And (Abs(T - ProgT) < 150) Then Exit;
  ProgT := T;
  Pm := 0;
  If WTot > 0 Then
    If WTot < 2000000 Then Pm := (WDone * 1000) Div WTot
    Else Pm := WDone Div (WTot Div 1000);
  If Pm > 1000 Then Pm := 1000;
  Str(Ph, L);
  Str(Pm, A);
  Str(G, B);
  Str(NGroups, C);
  L := L + ' ' + A + ' ' + B + ' ' + C + #10;
  F := SysOpen(ProgPath, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If F < 0 Then Exit;
  SysWrite(F, L[1], Length(L));
  SysClose(F);
End;

{ ecrit Cnt blocs depuis Addr ; un tampon de zeros n'est ecrit que si la
  zone n'est pas deja a zero (disque neuf : aucune ecriture) }
Procedure WriteBlocks(Blk, Cnt, Addr : LongInt);
Var Len, Sect : LongInt;
Begin
  { essais : K32_MKFS_SLOW=ms ralentit chaque ecriture groupee (operation
    longue reproductible pour les essais de progression) }
  If SlowMs > 0 Then Sleep(SlowMs);
  Len := Cnt * BS;
  Sect := PartStart + Blk * (BS Div 512);
  If AllZero(Addr, Len) Then
    If ReadAtS(Sect, LongInt(@RBuf), Len) = Len Then
      If AllZero(LongInt(@RBuf), Len) Then Exit;
  WriteAtS(Sect, 0, Addr, Len);
End;

Procedure PutB(Addr, Off, V : LongInt);
Var P : ^Byte;
Begin
  P := Pointer(Addr + Off);
  P^ := V And $FF;
End;

Procedure PutD(Addr, Off, V : LongInt);
Begin
  PutB(Addr, Off, V);
  PutB(Addr, Off + 1, V Shr 8);
  PutB(Addr, Off + 2, V Shr 16);
  PutB(Addr, Off + 3, V Shr 24);
End;

Procedure PutW(Addr, Off, V : LongInt);
Begin
  PutB(Addr, Off, V);
  PutB(Addr, Off + 1, V Shr 8);
End;

{ ---------- sommes de controle : crc32c (metadata_csum), crc16 ---------- }

Procedure FsCrcInit;
Var I, J, C, D : LongInt;
Begin
  For I := 0 To 255 Do
  Begin
    C := I;
    D := I;
    For J := 1 To 8 Do
    Begin
      If (C And 1) <> 0 Then C := (C Shr 1) Xor $82F63B78
      Else C := C Shr 1;
      If (D And 1) <> 0 Then D := (D Shr 1) Xor $A001
      Else D := D Shr 1;
    End;
    FsCrcTab[I] := C;
    Crc16Tab[I] := D;
  End;
End;

Function FsCrc32c(Crc : LongInt; Addr, Len : LongInt) : LongInt;
Var P : ^Byte; K : LongInt;
Begin
  For K := 0 To Len - 1 Do
  Begin
    P := Pointer(Addr + K);
    Crc := FsCrcTab[(Crc Xor P^) And $FF] Xor (Crc Shr 8);
  End;
  FsCrc32c := Crc;
End;

Function FsCrc16(Crc : LongInt; Addr, Len : LongInt) : LongInt;
Var P : ^Byte; K : LongInt;
Begin
  Crc := Crc And $FFFF;
  For K := 0 To Len - 1 Do
  Begin
    P := Pointer(Addr + K);
    Crc := Crc16Tab[(Crc Xor P^) And $FF] Xor (Crc Shr 8);
  End;
  FsCrc16 := Crc And $FFFF;
End;

{ crc32c(graine, numero d'inode, generation 0, donnees) : inodes, blocs de
  repertoire, blocs d'extents }
Function InoCsum(Ino, Addr, Len : LongInt) : LongInt;
Var T : Array[0..1] Of LongInt; C : LongInt;
Begin
  T[0] := Ino;
  T[1] := 0;
  C := FsCrc32c(CsumSeed, LongInt(@T[0]), 4);
  C := FsCrc32c(C, LongInt(@T[1]), 4);
  InoCsum := FsCrc32c(C, Addr, Len);
End;

{ identifiant du volume : /dev/urandom, sinon derive de l'heure }
Procedure MakeUuid;
Var F, N, K : LongInt;
Begin
  FillChar(FsUuid, 16, 0);
  F := SysOpen('/dev/urandom', O_RDONLY, 0);
  N := 0;
  If F >= 0 Then
  Begin
    N := LnxSys3(3, F, LongInt(@FsUuid), 16);
    SysClose(F);
  End;
  If N < 16 Then
    For K := 0 To 15 Do FsUuid[K] := ((Now Shr (K And 3)) + K * 17 + 5) And $FF;
  FsUuid[6] := (FsUuid[6] And $0F) Or $40;
  FsUuid[8] := (FsUuid[8] And $3F) Or $80;
End;

{ ---------- geometrie et allocation ---------- }

Function GroupBase(G : LongInt) : LongInt;
Begin
  GroupBase := FirstData + G * BPG;
End;

Function IsPow(G, B : LongInt) : Boolean;
Var V : LongInt;
Begin
  V := 1;
  While V < G Do V := V * B;
  IsPow := V = G;
End;

Function HasBackup(G : LongInt) : Boolean;
Begin
  HasBackup := (Not FeatSparse) Or (G = 0) Or (G = 1) Or IsPow(G, 3) Or
               IsPow(G, 5) Or IsPow(G, 7);
End;

Procedure SetBlkBit(B : LongInt);
Begin
  BlkBm[B Shr 3] := BlkBm[B Shr 3] Or (1 Shl (B And 7));
End;

Function GetBlkBit(B : LongInt) : Boolean;
Begin
  GetBlkBit := (BlkBm[B Shr 3] And (1 Shl (B And 7))) <> 0;
End;

Procedure SetInoBit(I : LongInt);
Begin
  InoBm[I Shr 3] := InoBm[I Shr 3] Or (1 Shl (I And 7));
End;

Var
  MetaIn : Array[0..MAXGRP - 1] Of LongInt;   { blocs de structure d'autres
                                                groupes dans le groupe }

Procedure MarkMeta(B : LongInt);
Begin
  SetBlkBit(B);
  Inc(MetaIn[(B - FirstData) Div BPG]);
End;

Function GrpOverhead(G : LongInt) : LongInt;
Begin
  If HasBackup(G) Then GrpOverhead := 1 + GdtBlocks
  Else GrpOverhead := 0;
End;

{ calcule la disposition des groupes ; marque les blocs de structure }
Procedure Layout;
Var G, Base, B, Last, K, G0, N, Again, S0, Free : LongInt;
Begin
  Repeat
    Again := 0;
    NGroups := (NBlocks - FirstData + BPG - 1) Div BPG;
    { inodes par groupe : BPG / 4 (1 Ko : 2048), ou -N ; multiple d'un bloc de
      table }
    IPG := BPG Div 4;
    If WantInodes > 0 Then
    Begin
      IPG := (WantInodes + NGroups - 1) Div NGroups;
      K := BS Div ISZ;
      IPG := ((IPG + K - 1) Div K) * K;
      If IPG < K Then IPG := K;
      If IPG > BS * 8 Then IPG := BS * 8;
    End;
    ITB := IPG * ISZ Div BS;
    GdtBlocks := (NGroups * DescSz + BS - 1) Div BS;
    { groupe flex : au plus 16 groupes dont les tables tiennent dans la
      premiere moitie du premier groupe }
    FlexSz := 1;
    LogFlex := 0;
    If FeatFlex Then
    Begin
      FlexSz := 16;
      LogFlex := 4;
      While (FlexSz > 1) And (FlexSz * (2 + ITB) + 1 + GdtBlocks > BPG Div 2) Do
      Begin
        FlexSz := FlexSz Div 2;
        Dec(LogFlex);
      End;
    End;
    { dernier groupe trop petit pour ses propres structures : abandonne }
    Last := NBlocks - GroupBase(NGroups - 1);
    K := GrpOverhead(NGroups - 1) + 40;
    If FlexSz = 1 Then K := K + 2 + ITB;
    If (NGroups > 1) And (Last < K) Then
    Begin
      NBlocks := NBlocks - Last;
      Again := 1;
    End;
  Until Again = 0;
  If NGroups > MAXGRP Then Die('trop de groupes / too many groups');
  FreeBlocks := 0;
  FreeInodes := NGroups * IPG - 10;
  FillChar(BlkBm, SizeOf(BlkBm), 0);
  FillChar(InoBm, SizeOf(InoBm), 0);
  FillChar(MetaIn, SizeOf(MetaIn), 0);
  For G := 0 To NGroups - 1 Do
  Begin
    Base := GroupBase(G);
    For K := 0 To GrpOverhead(G) - 1 Do SetBlkBit(Base + K);
    If FlexSz = 1 Then
    Begin
      B := Base + GrpOverhead(G);
      GrpBBm[G] := B;
      GrpIBm[G] := B + 1;
      GrpITab[G] := B + 2;
    End
    Else
    Begin
      G0 := (G Div FlexSz) * FlexSz;
      N := NGroups - G0;
      If N > FlexSz Then N := FlexSz;
      S0 := GroupBase(G0) + GrpOverhead(G0);
      GrpBBm[G] := S0 + (G - G0);
      GrpIBm[G] := S0 + N + (G - G0);
      GrpITab[G] := S0 + 2 * N + (G - G0) * ITB;
    End;
    MarkMeta(GrpBBm[G]);
    MarkMeta(GrpIBm[G]);
    For K := 0 To ITB - 1 Do MarkMeta(GrpITab[G] + K);
  End;
  For G := 0 To NGroups - 1 Do
  Begin
    Base := GroupBase(G);
    Last := Base + BPG - 1;
    If Last > NBlocks - 1 Then Last := NBlocks - 1;
    { blocs au-dela de la fin du systeme de fichiers : occupes }
    For K := Last + 1 To Base + BPG - 1 Do SetBlkBit(K);
    Free := 0;
    For K := Base To Last Do
      If Not GetBlkBit(K) Then Inc(Free);
    GrpFreeBlk[G] := Free;
    GrpFreeIno[G] := IPG;
    GrpDirs[G] := 0;
    FreeBlocks := FreeBlocks + Free;
  End;
  { inodes reserves 1..10 }
  For K := 1 To 10 Do SetInoBit(K - 1);
  GrpFreeIno[0] := IPG - 10;
  NextIno := 12;
  Cursor := FirstData;
End;

Function AllocBlock : LongInt;
Var B, G : LongInt;
Begin
  B := Cursor;
  While (B < NBlocks) And GetBlkBit(B) Do Inc(B);
  If B >= NBlocks Then
  Begin
    SysPut(2, Msg(11) + Msg(13) + #10);
    Fail := True;
    SysExit(1);
  End;
  SetBlkBit(B);
  Cursor := B + 1;
  G := (B - FirstData) Div BPG;
  Dec(GrpFreeBlk[G]);
  Dec(FreeBlocks);
  AllocBlock := B;
End;

Function AllocInode(IsDir : Boolean) : LongInt;
Var I, G : LongInt;
Begin
  I := NextIno;
  Inc(NextIno);
  SetInoBit(I - 1);
  G := (I - 1) Div IPG;
  Dec(GrpFreeIno[G]);
  Dec(FreeInodes);
  If IsDir Then Inc(GrpDirs[G]);
  AllocInode := I;
End;

{ ---------- ecriture d'un inode ---------- }

Procedure PutInode(Ino : LongInt; Mode, Uid, Gid, Size, ATime, CTime, MTime,
    Links, Sectors, Flags : LongInt; Var Blocks : TBlk15);
Var Off, G, Idx, K, C, A : LongInt; I128 : Array[0..255] Of Byte;
Begin
  FillChar(I128, SizeOf(I128), 0);
  A := LongInt(@I128);
  PutW(A, 0, Mode);
  PutW(A, 2, Uid);
  PutD(A, 4, Size);
  PutD(A, 8, ATime);
  PutD(A, 12, CTime);
  PutD(A, 16, MTime);
  PutW(A, 24, Gid);
  PutW(A, 26, Links);
  PutD(A, 28, Sectors);
  PutD(A, 32, Flags);
  For K := 0 To 14 Do PutD(A, 40 + K * 4, Blocks[K]);
  If (ISZ > 128) And FeatExtra Then
  Begin
    PutW(A, 128, 32);              { i_extra_isize }
    PutD(A, 144, Now);             { i_crtime }
  End;
  If FeatMcsum Then
  Begin
    C := InoCsum(Ino, A, ISZ);
    PutW(A, 124, C And $FFFF);
    If (ISZ > 128) And FeatExtra Then PutW(A, 130, C Shr 16);
  End;
  G := (Ino - 1) Div IPG;
  Idx := (Ino - 1) Mod IPG;
  WriteAtS(PartStart + GrpITab[G] * (BS Div 512) + (Idx * ISZ) Div 512,
      (Idx * ISZ) Mod 512, A, ISZ);
End;

{ ---------- ecriture de donnees : blocs directs et indirects ---------- }

Var
  FBlocks : TBlk15;          { i_block du fichier en cours }
  FNBlk : LongInt;           { nombre de blocs de donnees ecrits }
  FSect : LongInt;           { secteurs de 512 octets (indirects compris) }
  Ind1 : LongInt;            { bloc d'indirection simple courant }
  Ind2 : LongInt;            { bloc de double indirection }
  Ind1Buf, Ind2Buf : Array[0..4095] Of Byte;
  Ind1Cnt, Ind2Cnt : LongInt;

Procedure FileBegin;
Var K : LongInt;
Begin
  For K := 0 To 14 Do FBlocks[K] := 0;
  FFlags := 0;
  ExtN := 0;
  FNBlk := 0;
  FSect := 0;
  Ind1 := 0;
  Ind2 := 0;
  Ind1Cnt := 0;
  Ind2Cnt := 0;
End;

Procedure FlushInd1;
Begin
  If Ind1 <> 0 Then
  Begin
    WriteBlk(Ind1, LongInt(@Ind1Buf));
  End;
End;

{ ajoute le bloc B (deja ecrit) a la suite des blocs du fichier }
Procedure FileAddBlock(B : LongInt);
Var N : LongInt;
Begin
  N := FNBlk;
  Inc(FNBlk);
  Inc(FSect, BS Div 512);
  If FeatExtents Then
  Begin
    { extents : on prolonge le dernier si le bloc est contigu }
    If (ExtN > 0) And (ExtPhys[ExtN - 1] + ExtLen[ExtN - 1] = B) And
       (ExtLen[ExtN - 1] < 32768) Then
      Inc(ExtLen[ExtN - 1])
    Else
    Begin
      If ExtN >= MAXEXT Then Die('fichier trop fragmente / too fragmented');
      ExtLog[ExtN] := N;
      ExtPhys[ExtN] := B;
      ExtLen[ExtN] := 1;
      Inc(ExtN);
    End;
    Exit;
  End;
  If N < 12 Then
  Begin
    FBlocks[N] := B;
    Exit;
  End;
  N := N - 12;
  If N < BS Div 4 Then
  Begin
    If N = 0 Then
    Begin
      FBlocks[12] := AllocBlock;
      Inc(FSect, BS Div 512);
      FillChar(Ind1Buf, BS, 0);
    End;
    PutD(LongInt(@Ind1Buf), N * 4, B);
    WriteBlk(FBlocks[12], LongInt(@Ind1Buf));
    Exit;
  End;
  N := N - BS Div 4;
  { double indirection : N / (BS/4) selectionne l'indirect }
  If N = 0 Then
  Begin
    FBlocks[13] := AllocBlock;
    Inc(FSect, BS Div 512);
    FillChar(Ind2Buf, BS, 0);
    Ind1 := 0;
  End;
  If N Mod (BS Div 4) = 0 Then
  Begin
    If Ind1 <> 0 Then WriteBlk(Ind1, LongInt(@Ind1Buf));
    Ind1 := AllocBlock;
    Inc(FSect, BS Div 512);
    FillChar(Ind1Buf, BS, 0);
    PutD(LongInt(@Ind2Buf), (N Div (BS Div 4)) * 4, Ind1);
    WriteBlk(FBlocks[13], LongInt(@Ind2Buf));
  End;
  PutD(LongInt(@Ind1Buf), (N Mod (BS Div 4)) * 4, B);
  WriteBlk(Ind1, LongInt(@Ind1Buf));
End;

{ ecrit l'en-tete d'un noeud d'extents a l'adresse A }
Procedure ExtHeader(A, Entries, MaxEnt, Depth : LongInt);
Begin
  PutW(A, 0, $F30A);
  PutW(A, 2, Entries);
  PutW(A, 4, MaxEnt);
  PutW(A, 6, Depth);
  PutD(A, 8, 0);
End;

{ termine le fichier : en mode extents, construit l'arbre dans i_block
  (au plus 4 extents, sinon 4 feuilles) ; Ino sert a la somme de controle }
Procedure FileEnd(Ino : LongInt);
Var K, J, A, LeafMax, NL, Cnt, Blk, Lb : LongInt;
    Lf : Array[0..4095] Of Byte;
Begin
  If Not FeatExtents Then Exit;
  FFlags := $80000;
  FillChar(FBlocks, SizeOf(FBlocks), 0);
  A := LongInt(@FBlocks);
  If ExtN <= 4 Then
  Begin
    ExtHeader(A, ExtN, 4, 0);
    For K := 0 To ExtN - 1 Do
    Begin
      PutD(A, 12 + K * 12, ExtLog[K]);
      PutW(A, 16 + K * 12, ExtLen[K]);
      PutW(A, 18 + K * 12, 0);
      PutD(A, 20 + K * 12, ExtPhys[K]);
    End;
    Exit;
  End;
  LeafMax := (BS - 12) Div 12;
  NL := (ExtN + LeafMax - 1) Div LeafMax;
  If NL > 4 Then Die('fichier trop fragmente / too fragmented');
  ExtHeader(A, NL, 4, 1);
  K := 0;
  For J := 0 To NL - 1 Do
  Begin
    Cnt := ExtN - K;
    If Cnt > LeafMax Then Cnt := LeafMax;
    Lb := LongInt(@Lf);
    FillChar(Lf, BS, 0);
    ExtHeader(Lb, Cnt, LeafMax, 0);
    For Blk := 0 To Cnt - 1 Do
    Begin
      PutD(Lb, 12 + Blk * 12, ExtLog[K + Blk]);
      PutW(Lb, 16 + Blk * 12, ExtLen[K + Blk]);
      PutW(Lb, 18 + Blk * 12, 0);
      PutD(Lb, 20 + Blk * 12, ExtPhys[K + Blk]);
    End;
    If FeatMcsum Then
      PutD(Lb, 12 + LeafMax * 12, InoCsum(Ino, Lb, 12 + LeafMax * 12));
    Blk := AllocBlock;
    Inc(FSect, BS Div 512);
    WriteBlk(Blk, Lb);
    PutD(A, 12 + J * 12, ExtLog[K]);
    PutD(A, 16 + J * 12, Blk);
    PutD(A, 20 + J * 12, 0);
    K := K + Cnt;
  End;
End;

{ ---------- repertoires ---------- }

Function DirBlockCount(Ents : PDirEnts; N : LongInt) : LongInt;
Var K, Used, Cnt, Need : LongInt;
Begin
  Cnt := 1;
  Used := 12 + 12;                  { . et .. }
  For K := 0 To N - 1 Do
  Begin
    Need := (8 + Length(Ents^[K].Name) + 3) And Not 3;
    If Used + Need > BS Then
    Begin
      Inc(Cnt);
      Used := 0;
    End;
    Used := Used + Need;
  End;
  DirBlockCount := Cnt;
End;

Procedure EmitDirent(Addr, Off, Ino, RecLen, NameLen,
  Typ : LongInt; Const Name : String);
Var K : LongInt;
Begin
  PutD(Addr, Off, Ino);
  PutW(Addr, Off + 4, RecLen);
  PutB(Addr, Off + 6, NameLen);
  PutB(Addr, Off + 7, Typ);
  For K := 1 To NameLen Do PutB(Addr, Off + 7 + K, Ord(Name[K]));
End;

{ ferme un bloc de repertoire : le dernier enregistrement s'etend jusqu'a Cap ;
  avec metadata_csum, un enregistrement final de 12 octets porte la somme }
Procedure CloseDirBlock(Ino, LastOff, Cap : LongInt);
Begin
  PutW(LongInt(@Buf), LastOff + 4, Cap - LastOff);
  If FeatMcsum Then
  Begin
    PutD(LongInt(@Buf), Cap, 0);
    PutW(LongInt(@Buf), Cap + 4, 12);
    PutB(LongInt(@Buf), Cap + 6, 0);
    PutB(LongInt(@Buf), Cap + 7, $DE);
    PutD(LongInt(@Buf), Cap + 8, InoCsum(Ino, LongInt(@Buf), Cap));
  End;
End;

{ ecrit le repertoire Ino (parent Par) avec ses entrees ; rend les blocs }
Procedure WriteDir(Ino, Par : LongInt; Ents : PDirEnts; N : LongInt;
    Mode, Uid, Gid, ATime, CTime, MTime,
      SubDirs : LongInt; MinBlocks : LongInt);
Var K, Off, LastOff, Need, Blk, NB, Cap : LongInt;
Begin
  FileBegin;
  Cap := BS;
  If FeatMcsum Then Cap := BS - 12;
  FillChar(Buf, BS, 0);
  Off := 0;
  EmitDirent(LongInt(@Buf), 0, Ino, 12, 1, 2, '.');
  EmitDirent(LongInt(@Buf), 12, Par, 12, 2, 2, '..');
  Off := 24;
  LastOff := 12;
  NB := 0;
  For K := 0 To N - 1 Do
  Begin
    Need := (8 + Length(Ents^[K].Name) + 3) And Not 3;
    If Off + Need > Cap Then
    Begin
      CloseDirBlock(Ino, LastOff, Cap);
      Blk := AllocBlock;
      WriteBlk(Blk, LongInt(@Buf));
      FileAddBlock(Blk);
      Inc(NB);
      FillChar(Buf, BS, 0);
      Off := 0;
    End;
    EmitDirent(LongInt(@Buf), Off, Ents^[K].Ino, Need, Length(Ents^[K].Name),
               Ents^[K].Typ, Ents^[K].Name);
    LastOff := Off;
    Off := Off + Need;
  End;
  { dernier bloc }
  If Off = 24 Then LastOff := 12;
  CloseDirBlock(Ino, LastOff, Cap);
  Blk := AllocBlock;
  WriteBlk(Blk, LongInt(@Buf));
  FileAddBlock(Blk);
  Inc(NB);
  { blocs vides supplementaires (lost+found) }
  While NB < MinBlocks Do
  Begin
    FillChar(Buf, BS, 0);
    CloseDirBlock(Ino, 0, Cap);
    Blk := AllocBlock;
    WriteBlk(Blk, LongInt(@Buf));
    FileAddBlock(Blk);
    Inc(NB);
  End;
  FileEnd(Ino);
  PutInode(Ino, $4000 Or (Mode And $FFF), Uid, Gid, NB * BS, ATime, CTime,
    MTime, 2 + SubDirs, FSect, FFlags, FBlocks);
End;

{ ---------- copie de l'arborescence ---------- }

Function TypeOf(Mode : LongInt) : LongInt;
Begin
  Case Mode And $F000 Of
    $8000 : TypeOf := 1;
    $4000 : TypeOf := 2;
    $2000 : TypeOf := 3;
    $6000 : TypeOf := 4;
    $1000 : TypeOf := 5;
    $C000 : TypeOf := 6;
    $A000 : TypeOf := 7;
  Else TypeOf := 1;
  End;
End;

Function Skip(Const P : String) : Boolean;
Begin
  Skip := (P = '/lost+found') Or (P = '/proc') Or (P = '/sys') Or (P = '/dev')
          Or (P = '/tmp') Or (P = '/mnt') Or (P = '/var/tmp');
End;

Procedure CopyFileData(Const Src : String; Var St : TSysStat; Ino : LongInt);
Var In1, N, Blk,
  Total : LongInt; Chunk : Array[0..4095] Of Byte; Blocks : TBlk15;
Begin
  FileBegin;
  In1 := SysOpen(Src, O_RDONLY, 0);
  Total := 0;
  If In1 >= 0 Then
  Begin
    While True Do
    Begin
      N := LnxSys3(3, In1, LongInt(@Chunk), BS);
      If N = -4 Then Continue;
      If N <= 0 Then Break;
      If N < BS Then FillChar(Chunk[N], BS - N, 0);
      { ne pas stocker un bloc entierement nul (fichier creux) : on le stocke
        quand meme pour rester simple }
      Blk := AllocBlock;
      WriteBlk(Blk, LongInt(@Chunk));
      FileAddBlock(Blk);
      Total := Total + N;
    End;
    SysClose(In1);
  End;
  FileEnd(Ino);
  Blocks := FBlocks;
  PutInode(Ino, St.Mode, St.Uid, St.Gid, Total, St.ATime, St.MTime, St.MTime,
           1, FSect, FFlags, Blocks);
End;

Procedure CopyProfile(Ino : LongInt; Var St : TSysStat);
{ /etc/profile avec LANGUAGE=XX }
Var In1, K : LongInt; L, Out1 : String; Text : String; Have : Boolean;
    Chunk : Array[0..4095] Of Byte; Blk, Len : LongInt;
Begin
  Text := '';
  Have := False;
  In1 := SysOpen(SrcRoot + '/etc/profile', O_RDONLY, 0);
  If In1 >= 0 Then
  Begin
    While SysReadLine(In1, L) Do
    Begin
      If Copy(L, 1, 9) = 'LANGUAGE=' Then
      Begin
        L := 'LANGUAGE=' + NewLang;
        Have := True;
      End;
      If Length(Text) + Length(L) + 1 < 900 Then Text := Text + L + #10;
    End;
    SysClose(In1);
  End;
  If Not Have Then Text := 'LANGUAGE=' + NewLang + #10 + 'export LANGUAGE' +
    #10 + Text;
  FileBegin;
  FillChar(Chunk, BS, 0);
  Len := Length(Text);
  For K := 1 To Len Do Chunk[K - 1] := Ord(Text[K]);
  Blk := AllocBlock;
  WriteBlk(Blk, LongInt(@Chunk));
  FileAddBlock(Blk);
  FileEnd(Ino);
  PutInode(Ino, St.Mode, St.Uid, St.Gid, Len, St.ATime, St.MTime, St.MTime, 1,
           FSect, FFlags, FBlocks);
End;

{ copie le repertoire Src (chemin absolu sur la source) ; Rel : chemin
  relatif a la racine pour les exclusions ; rend le numero d'inode }
Function CopyDir(Src, Rel : String; Ino, Par : LongInt;
    Var St : TSysStat) : LongInt;
Var
  D, Ino2, K, Cnt, Sub, MinB : LongInt;
  Name : String;
  Ents : PDirEnts;
  S2 : TSysStat;
  Full, Child, Link : String;
  Blocks : TBlk15;
  P : LongInt;
Begin
  GetMem(Ents, SizeOf(TDirEnts));
  Cnt := 0;
  Sub := 0;
  If Not (Skip(Rel) And (Rel <> '')) Then
  Begin
    D := SysOpenDir(Src);
    If D >= 0 Then
    Begin
      While SysReadDir(D, Name, P) Do
      Begin
        If (Name = '.') Or (Name = '..') Then Continue;
        If Cnt >= MAXDIRENT Then Break;
        If Src[Length(Src)] = '/' Then Full := Src + Name Else Full := Src +
          '/' + Name;
        Child := Full;
        If Rel = '' Then Link := '/' + Name Else Link := Rel + '/' + Name;
        If SysLStat(Full, S2) < 0 Then Continue;
        If (Link = '/lost+found') Then Continue;
        Ents^[Cnt].Name := Name;
        Ents^[Cnt].Typ := TypeOf(S2.Mode);
        If (S2.Mode And $F000) = $4000 Then
        Begin
          Ino2 := AllocInode(True);
          Ents^[Cnt].Ino := Ino2;
          CopyDir(Full, Link, Ino2, Ino, S2);
          Inc(Sub);
        End
        Else
        Begin
          Ino2 := AllocInode(False);
          Ents^[Cnt].Ino := Ino2;
          Inc(Copied);
          Case S2.Mode And $F000 Of
            $8000 :
              If Link = '/etc/profile' Then CopyProfile(Ino2, S2)
              Else CopyFileData(Full, S2, Ino2);
            $A000 :
              Begin
                Link := SysReadlink(Full);
                FileBegin;
                FillChar(Blocks, SizeOf(Blocks), 0);
                If Length(Link) < 60 Then
                Begin
                  For K := 1 To Length(Link) Do
                    PutB(LongInt(@Blocks), K - 1, Ord(Link[K]));
                  PutInode(Ino2, S2.Mode, S2.Uid, S2.Gid, Length(Link),
                    S2.ATime,
                           S2.MTime, S2.MTime, 1, 0, 0, Blocks);
                End
                Else
                Begin
                  FillChar(Buf, BS, 0);
                  For K := 1 To Length(Link) Do Buf[K - 1] := Ord(Link[K]);
                  K := AllocBlock;
                  WriteBlk(K, LongInt(@Buf));
                  FileAddBlock(K);
                  FileEnd(Ino2);
                  Blocks := FBlocks;
                  PutInode(Ino2, S2.Mode, S2.Uid, S2.Gid, Length(Link),
                    S2.ATime,
                           S2.MTime, S2.MTime, 1, FSect, FFlags, Blocks);
                End;
              End;
          Else
            Begin
              { peripherique, tube : numero dans i_block[0] }
              FillChar(Blocks, SizeOf(Blocks), 0);
              Blocks[0] := S2.RDev;
              PutInode(Ino2, S2.Mode, S2.Uid, S2.Gid, 0, S2.ATime, S2.MTime,
                       S2.MTime, 1, 0, 0, Blocks);
            End;
          End;
        End;
        Inc(Cnt);
      End;
      SysCloseDir(D);
    End;
  End;
  If Rel = '' Then
  Begin
    { racine : lost+found en premier }
    For K := Cnt DownTo 1 Do Ents^[K] := Ents^[K - 1];
    Ents^[0].Name := 'lost+found';
    Ents^[0].Ino := 11;
    Ents^[0].Typ := 2;
    Inc(Cnt);
    Inc(Sub);
  End;
  WriteDir(Ino, Par, Ents, Cnt, St.Mode, St.Uid, St.Gid, St.ATime, St.CTime,
           St.MTime, Sub, 0);
  FreeMem(Ents, SizeOf(TDirEnts));
  CopyDir := Ino;
End;

{ ---------- structures du systeme de fichiers ---------- }

Function CompatBits : LongInt;
Var V : LongInt;
Begin
  V := 0;
  If FeatJournal Then V := V Or $4;
  If FeatExtAttr Then V := V Or $8;
  If FeatDirIdx Then V := V Or $20;
  CompatBits := V;
End;

Function IncompatBits : LongInt;
Var V : LongInt;
Begin
  V := 0;
  If FeatFiletype Then V := V Or $2;
  If FeatExtents Then V := V Or $40;
  If Feat64 Then V := V Or $80;
  If FlexSz > 1 Then V := V Or $200;
  IncompatBits := V;
End;

Function RoCompatBits : LongInt;
Var V : LongInt;
Begin
  V := 0;
  If FeatSparse Then V := V Or $1;
  If FeatLarge Then V := V Or $2;
  If FeatHuge Then V := V Or $8;
  If FeatGdtCsum Then V := V Or $10;
  If FeatDirNlink Then V := V Or $20;
  If FeatExtra Then V := V Or $40;
  If FeatMcsum Then V := V Or $400;
  RoCompatBits := V;
End;

Procedure WriteSuper(G : LongInt);
Var Sb : Array[0..4095] Of Byte; K : LongInt; Base : LongInt; SbA : LongInt;
    Rsv, A : LongInt;
Begin
  FillChar(Sb, BS, 0);
  SbA := LongInt(@Sb);
  A := SbA;
  If (G = 0) And (BS > 1024) Then SbA := SbA + 1024;
  Rsv := NBlocks Div 100 * ResPct;
  PutD(SbA, 0, NGroups * IPG);
  PutD(SbA, 4, NBlocks);
  PutD(SbA, 8, Rsv);
  PutD(SbA, 12, FreeBlocks);
  PutD(SbA, 16, FreeInodes);
  PutD(SbA, 20, FirstData);
  PutD(SbA, 24, LogBs - 10);
  PutD(SbA, 28, LogBs - 10);
  PutD(SbA, 32, BPG);
  PutD(SbA, 36, BPG);
  PutD(SbA, 40, IPG);
  PutD(SbA, 44, 0);
  PutD(SbA, 48, Now);
  PutW(SbA, 52, 0);
  PutW(SbA, 54, $FFFF);
  PutW(SbA, 56, $EF53);
  PutW(SbA, 58, 1);
  PutW(SbA, 60, 1);
  PutW(SbA, 62, 0);
  PutD(SbA, 64, Now);
  PutD(SbA, 68, 0);
  PutD(SbA, 72, 0);
  PutD(SbA, 76, 1);
  PutW(SbA, 80, 0);
  PutW(SbA, 82, 0);
  PutD(SbA, 84, 11);
  PutW(SbA, 88, ISZ);
  PutW(SbA, 90, G);
  PutD(SbA, 92, CompatBits);
  PutD(SbA, 96, IncompatBits);
  PutD(SbA, 100, RoCompatBits);
  For K := 0 To 15 Do PutB(SbA, 104 + K, FsUuid[K]);
  For K := 1 To Length(VolName) Do PutB(SbA, 119 + K, Ord(VolName[K]));
  If FeatJournal Then
  Begin
    PutD(SbA, 224, 8);                       { s_journal_inum }
    PutB(SbA, 253, 1);                       { s_jnl_backup_type }
    For K := 0 To 14 Do PutD(SbA, 268 + K * 4, JrnInode[K]);
    PutD(SbA, 268 + 60, 0);                  { i_size_high }
    PutD(SbA, 268 + 64, JrnSize);            { i_size }
  End;
  If FeatDirIdx Then
  Begin
    For K := 0 To 15 Do PutB(SbA, 236 + K, FsUuid[(K + 5) And 15] Xor $5A);
    PutB(SbA, 252, 1);                       { half_md4 }
    PutD(SbA, 352, 1);                       { s_flags : signed hash }
  End;
  If Feat64 Then PutW(SbA, 254, DescSz);
  If FeatExtra Then
  Begin
    PutW(SbA, 348, 32);                      { s_min_extra_isize }
    PutW(SbA, 350, 32);                      { s_want_extra_isize }
  End;
  If FlexSz > 1 Then PutB(SbA, 372, LogFlex);
  If FeatMcsum Then
  Begin
    PutB(SbA, 373, 1);                       { crc32c }
    PutD(SbA, 1020, FsCrc32c(-1, SbA, 1020));
  End;
  Base := GroupBase(G);
  WriteBlk(Base, A);
End;

{ somme de controle d'un descripteur de groupe (crc16 ou crc32c) }
Procedure GdCsum(G, Addr : LongInt);
Var C, Gn : LongInt;
Begin
  If Not (FeatMcsum Or FeatGdtCsum) Then Exit;
  PutW(Addr, G * DescSz + 30, 0);
  Gn := G;
  If FeatMcsum Then
  Begin
    C := FsCrc32c(CsumSeed, LongInt(@Gn), 4);
    C := FsCrc32c(C, Addr + G * DescSz, DescSz) And $FFFF;
  End
  Else
  Begin
    C := FsCrc16(-1, LongInt(@FsUuid), 16);
    C := FsCrc16(C, LongInt(@Gn), 4);
    C := FsCrc16(C, Addr + G * DescSz, 30);
    If DescSz > 32 Then C := FsCrc16(C, Addr + G * DescSz + 32, DescSz - 32);
  End;
  PutW(Addr, G * DescSz + 30, C);
End;

Procedure WriteMeta;
Var G, K, B, Used, Hi, Ov, Last, Gb, Lo : LongInt;
    Gd : Array[0..4095] Of Byte; Bb : Array[0..4095] Of Byte;
    Gdt : Array[0..16383] Of Byte; Bcs, Ics : LongInt;
Begin
  FillChar(Gdt, SizeOf(Gdt), 0);
  For G := 0 To NGroups - 1 Do
  Begin
    Gb := GroupBase(G);
    { bitmap des blocs : bits du groupe (le debut du groupe est un
      multiple de 8 + 1 : on recopie bit a bit) }
    FillChar(Bb, BS, 0);
    For K := 0 To BPG - 1 Do
      If GetBlkBit(Gb + K) Then Bb[K Shr 3] := Bb[K Shr 3] Or (1 Shl
        (K And 7));
    Bcs := FsCrc32c(CsumSeed, LongInt(@Bb), BPG Div 8);
    WriteBlk(GrpBBm[G], LongInt(@Bb));
    FillChar(Bb, BS, 0);
    Used := 0;
    Hi := 0;
    For K := 0 To IPG - 1 Do
      If (InoBm[(G * IPG + K) Shr 3] And (1 Shl ((G * IPG + K) And 7))) <> 0
        Then
      Begin
        Bb[K Shr 3] := Bb[K Shr 3] Or (1 Shl (K And 7));
        Inc(Used);
        Hi := K + 1;
      End;
    Ics := FsCrc32c(CsumSeed, LongInt(@Bb), IPG Div 8);
    For K := IPG To BPG - 1 Do Bb[K Shr 3] := Bb[K Shr 3] Or (1 Shl (K And 7));
    WriteBlk(GrpIBm[G], LongInt(@Bb));
    { indicateurs de groupe (uninit_bg / metadata_csum) }
    GrpFlags[G] := 0;
    GrpUnused[G] := 0;
    If FeatMcsum Or FeatGdtCsum Then
    Begin
      { ITABLE_ZEROED seulement si la table a ete mise a zero (sinon
        initialisation paresseuse : le groupe est INODE_UNINIT) }
      If GrpZeroed[G] Then GrpFlags[G] := 4 Else GrpFlags[G] := 0;
      GrpUnused[G] := IPG - Hi;
      If ((Used = 0) And (G > 0)) Or Not GrpZeroed[G] Then
        GrpFlags[G] := GrpFlags[G] Or 1;
      If (G > 0) And (G < NGroups - 1) Then
      Begin
        Ov := GrpOverhead(G);
        If FlexSz = 1 Then Ov := Ov + 2 + ITB;
        Last := BPG - GrpFreeBlk[G];
        If Last = Ov Then GrpFlags[G] := GrpFlags[G] Or 2;
      End;
    End;
    Lo := G * DescSz;
    PutD(LongInt(@Gdt), Lo, GrpBBm[G]);
    PutD(LongInt(@Gdt), Lo + 4, GrpIBm[G]);
    PutD(LongInt(@Gdt), Lo + 8, GrpITab[G]);
    PutW(LongInt(@Gdt), Lo + 12, GrpFreeBlk[G]);
    PutW(LongInt(@Gdt), Lo + 14, GrpFreeIno[G]);
    PutW(LongInt(@Gdt), Lo + 16, GrpDirs[G]);
    PutW(LongInt(@Gdt), Lo + 18, GrpFlags[G]);
    If FeatMcsum Then
    Begin
      PutW(LongInt(@Gdt), Lo + 24, Bcs And $FFFF);
      PutW(LongInt(@Gdt), Lo + 26, Ics And $FFFF);
      If DescSz >= 64 Then
      Begin
        PutW(LongInt(@Gdt), Lo + 56, Bcs Shr 16);
        PutW(LongInt(@Gdt), Lo + 58, Ics Shr 16);
      End;
    End;
    PutW(LongInt(@Gdt), Lo + 28, GrpUnused[G]);
    GdCsum(G, LongInt(@Gdt));
    WDone := WDone + 2;
    ProgPut(3, G + 1, False);
  End;
  For G := 0 To NGroups - 1 Do
    If HasBackup(G) Then
    Begin
      WriteSuper(G);
      For K := 0 To GdtBlocks - 1 Do
      Begin
        Move(Gdt[K * BS], Gd, BS);
        WriteBlk(GroupBase(G) + 1 + K, LongInt(@Gd));
      End;
    End;
  WDone := WTot;
  ProgPut(3, NGroups, True);
End;

{ ---------- mke2fs : zone des inodes a zero, lost+found ---------- }

Function DefaultJournal : LongInt; Forward;

Procedure FormatFs;
Var G, K, N, Cb, Ej, Nz : LongInt; Lazy : Boolean;
Begin
  FillChar(ZBuf, SizeOf(ZBuf), 0);
  Cb := 1048576 Div BS;
  Ej := 0;
  If FeatJournal Then
    If JrnMb > 0 Then Ej := JrnMb * (1048576 Div BS)
    Else Ej := DefaultJournal;
  { uninit_bg / metadata_csum : initialisation paresseuse des tables
    d'inodes (comme lazy_itable_init de mke2fs) : seul le groupe 0, qui
    porte les inodes reserves, est mis a zero ; les autres groupes sont
    marques INODE_UNINIT sans ITABLE_ZEROED (le noyau n'y lit jamais un inode
    libre, e2fsck ignore les groupes INODE_UNINIT) }
  Lazy := FeatGdtCsum Or FeatMcsum;
  Nz := NGroups;
  If Lazy Then Nz := 1;
  ProgPath := SysGetEnv('K32_PROGRESS');
  Val(SysGetEnv('K32_MKFS_SLOW'), SlowMs, K);
  If K <> 0 Then SlowMs := 0;
  WDone := 0;
  WTot := Nz * ITB + Ej + NGroups * 2 + 1;
  ProgPut(1, 0, True);
  For G := 0 To NGroups - 1 Do
  Begin
    GrpZeroed[G] := (Not Lazy) Or (G = 0);
    If GrpZeroed[G] Then
    Begin
      K := 0;
      While K < ITB Do
      Begin
        N := ITB - K;
        If N > Cb Then N := Cb;
        WriteBlocks(GrpITab[G] + K, N, LongInt(@ZBuf));
        K := K + N;
        WDone := WDone + N;
        ProgPut(1, G + 1, False);
      End;
    End;
  End;
End;

Procedure MakeLostFound;
Var Ents : PDirEnts; Blocks : TBlk15;
Begin
  GetMem(Ents, SizeOf(TDirEnts));
  { inode 11 reserve pour lost+found : allouer explicitement }
  SetInoBit(10);
  Dec(GrpFreeIno[0]);
  Dec(FreeInodes);
  Inc(GrpDirs[0]);
  WriteDir(11, 2, Ents, 0, $1C0, 0, 0, Now, Now, Now, 0, 12);
  FreeMem(Ents, SizeOf(TDirEnts));
End;

{ ---------- journal jbd2 : inode 8 ---------- }

Procedure PutBE(Addr, Off, V : LongInt);
Begin
  PutB(Addr, Off, V Shr 24);
  PutB(Addr, Off + 1, V Shr 16);
  PutB(Addr, Off + 2, V Shr 8);
  PutB(Addr, Off + 3, V);
End;

{ taille par defaut en blocs (comme mke2fs) }
Function DefaultJournal : LongInt;
Begin
  If NBlocks < 2048 Then DefaultJournal := 0
  Else If NBlocks < 32768 Then DefaultJournal := 1024
  Else If NBlocks < 262144 Then DefaultJournal := 4096
  Else If NBlocks < 524288 Then DefaultJournal := 8192
  Else If NBlocks < 4194304 Then DefaultJournal := 16384
  Else DefaultJournal := 32768;
End;

Procedure MakeJournal;
Var K, Q, Blk, A, Js, Jc, Cb : LongInt;
Begin
  FileBegin;
  Cb := 1048576 Div BS;
  Js := 0;
  Jc := 0;
  For K := 0 To JrnBlocks - 1 Do
  Begin
    Blk := AllocBlock;
    { blocs consecutifs : un tampon de 1 Mo ecrit d'un coup }
    If (Jc > 0) And ((Blk <> Js + Jc) Or (Jc >= Cb)) Then
    Begin
      WriteBlocks(Js, Jc, LongInt(@JBuf));
      Jc := 0;
    End;
    If Jc = 0 Then Js := Blk;
    A := LongInt(@JBuf) + Jc * BS;
    FillChar(JBuf[Jc * BS], BS, 0);
    If K = 0 Then
    Begin
      PutBE(A, 0, $C03B3998);
      PutBE(A, 4, 4);                 { superbloc v2 }
      PutBE(A, 12, BS);
      PutBE(A, 16, JrnBlocks);
      PutBE(A, 20, 1);                { s_first }
      PutBE(A, 24, 1);                { s_sequence }
      PutBE(A, 28, 0);                { s_start : journal propre }
      For Q := 0 To 15 Do PutB(A, 48 + Q, FsUuid[Q]);
      PutBE(A, 64, 1);                { s_nr_users }
    End;
    Inc(Jc);
    FileAddBlock(Blk);
    Inc(WDone);
    ProgPut(2, 0, False);
  End;
  If Jc > 0 Then WriteBlocks(Js, Jc, LongInt(@JBuf));
  FileEnd(8);
  PutInode(8, $8180, 0, 0, JrnBlocks * BS, Now, Now, Now, 1, FSect, FFlags,
           FBlocks);
  JrnInode := FBlocks;
  JrnSize := JrnBlocks * BS;
End;

{ ---------- partitionnement et amorce ---------- }

Procedure ChsBytes(Lba : LongInt; Addr, Off : LongInt);
Var C, H, S : LongInt;
Begin
  C := Lba Div (255 * 63);
  H := (Lba Div 63) Mod 255;
  S := Lba Mod 63 + 1;
  If C > 1023 Then
  Begin
    C := 1023;
    H := 254;
    S := 63;
  End;
  PutB(Addr, Off, H);
  PutB(Addr, Off + 1, S Or ((C Shr 8) Shl 6));
  PutB(Addr, Off + 2, C);
End;

Procedure InstallBoot(TotalSectors : LongInt);
Var Mbr : Array[0..511] Of Byte; F, N, K,
  Ns2 : LongInt; St2 : Array[0..65535] Of Byte;
    Len : LongInt;
Begin
  FillChar(Mbr, 512, 0);
  F := SysOpen(SrcRoot + '/usr/share/boot/MBR.BIN', O_RDONLY, 0);
  If F < 0 Then Die(Msg(16));
  N := LnxSys3(3, F, LongInt(@Mbr), 512);
  SysClose(F);
  F := SysOpen(SrcRoot + '/usr/share/boot/STAGE2.BIN', O_RDONLY, 0);
  If F < 0 Then Die(Msg(16));
  Len := 0;
  Repeat
    N := LnxSys3(3, F, LongInt(@St2) + Len, 65536 - Len);
    If N > 0 Then Len := Len + N;
  Until N <= 0;
  SysClose(F);
  Ns2 := (Len + 511) Div 512;
  If Ns2 + 1 > PartStart Then Die(Msg(16));
  { MBR : parametres du chargeur (LBA 1, N secteurs), table, signature }
  PutD(LongInt(@Mbr), 3, 1);
  PutW(LongInt(@Mbr), 7, Ns2);
  FillChar(Mbr[446], 66, 0);
  PutB(LongInt(@Mbr), 446, $80);
  ChsBytes(PartStart, LongInt(@Mbr), 447);
  PutB(LongInt(@Mbr), 450, $83);
  ChsBytes(TotalSectors - 1, LongInt(@Mbr), 451);
  PutD(LongInt(@Mbr), 454, PartStart);
  PutD(LongInt(@Mbr), 458, TotalSectors - PartStart);
  PutB(LongInt(@Mbr), 510, $55);
  PutB(LongInt(@Mbr), 511, $AA);
  WriteAt(0, LongInt(@Mbr), 512);
  WriteAt(512, LongInt(@St2), Ns2 * 512);
End;

{ taille du disque en secteurs de 512 octets }
Function DiskSectors : LongInt;
Var S : LongInt; E : LongInt;
Begin
  S := 0;
  If SysIoctl(Fd, $1260, S) < 0 Then S := 0;
  If S <= 0 Then
  Begin
    E := SysLSeek(Fd, 0, SEEK_END);
    If E > 0 Then S := E Div 512;
  End;
  DiskSectors := S;
End;

Function Ask(Const Prompt : String) : String;
Var S : String; C : Char; N : LongInt;
Begin
  SysPut(1, Prompt);
  S := '';
  Repeat
    N := SysRead(0, C, 1);
    If (N <= 0) Or (C = #10) Then Break;
    If Length(S) < 60 Then S := S + C;
  Until False;
  Ask := S;
End;

{ ---------- type de systeme de fichiers et fonctions (-t, -O) ---------- }

Procedure SetType(T : LongInt);
Begin
  FsType := T;
  FeatSparse := True;
  FeatFiletype := True;
  FeatJournal := T >= 3;
  FeatDirIdx := T >= 3;
  FeatExtAttr := T >= 3;
  FeatLarge := T >= 3;
  FeatExtents := T >= 4;
  FeatFlex := T >= 4;
  FeatGdtCsum := T >= 4;
  FeatHuge := T >= 4;
  FeatDirNlink := T >= 4;
  FeatExtra := T >= 4;
  FeatMcsum := False;
  Feat64 := False;
  If T = 3 Then FsName := 'ext3'
  Else If T = 4 Then FsName := 'ext4'
  Else FsName := 'ext2';
End;

Procedure SetFeature(Const Nm : String; On : Boolean);
Begin
  If Nm = 'sparse_super' Then FeatSparse := On
  Else If Nm = 'filetype' Then FeatFiletype := On
  Else If Nm = 'has_journal' Then FeatJournal := On
  Else If Nm = 'dir_index' Then FeatDirIdx := On
  Else If Nm = 'ext_attr' Then FeatExtAttr := On
  Else If Nm = 'large_file' Then FeatLarge := On
  Else If (Nm = 'extents') Or (Nm = 'extent') Then FeatExtents := On
  Else If Nm = 'flex_bg' Then FeatFlex := On
  Else If Nm = '64bit' Then Feat64 := On
  Else If Nm = 'metadata_csum' Then FeatMcsum := On
  Else If (Nm = 'uninit_bg') Or (Nm = 'gdt_csum') Then FeatGdtCsum := On
  Else If Nm = 'huge_file' Then FeatHuge := On
  Else If Nm = 'dir_nlink' Then FeatDirNlink := On
  Else If Nm = 'extra_isize' Then FeatExtra := On
  Else If (Nm = 'resize_inode') Or (Nm = 'none') Then
  Else Die(Msg(18) + Nm);
End;

{ -O liste : "a,b,^c" ; "none" efface tout }
Procedure ApplyFeatures(Const L : String);
Var K, J : LongInt; Nm : String; On : Boolean;
Begin
  K := 1;
  While K <= Length(L) Do
  Begin
    J := K;
    While (J <= Length(L)) And (L[J] <> ',') Do Inc(J);
    Nm := Copy(L, K, J - K);
    On := True;
    If (Nm <> '') And ((Nm[1] = '^') Or (Nm[1] = '-')) Then
    Begin
      On := False;
      Nm := Copy(Nm, 2, 60);
    End
    Else If (Nm <> '') And (Nm[1] = '+') Then Nm := Copy(Nm, 2, 60);
    If Nm = 'none' Then
    Begin
      FeatSparse := False; FeatFiletype := False; FeatJournal := False;
      FeatDirIdx := False; FeatExtAttr := False; FeatLarge := False;
      FeatExtents := False; FeatFlex := False; FeatGdtCsum := False;
      FeatHuge := False; FeatDirNlink := False; FeatExtra := False;
      FeatMcsum := False; Feat64 := False;
    End
    Else If Nm <> '' Then SetFeature(Nm, On);
    K := J + 1;
  End;
End;

{ cree le journal (inode 8) si la fonction has_journal est demandee }
Procedure SetupJournal;
Begin
  If Not FeatJournal Then Exit;
  If JrnMb > 0 Then JrnBlocks := JrnMb * (1048576 Div BS)
  Else JrnBlocks := DefaultJournal;
  If JrnBlocks = 0 Then
  Begin
    FeatJournal := False;
    Exit;
  End;
  If JrnBlocks < 1024 Then Die('-J size : journal trop petit / too small');
  If JrnBlocks > FreeBlocks Div 2 Then Die(Msg(13));
  If JrnBlocks > 12 + BS Div 4 + (BS Div 4) * (BS Div 4) Then
    Die('-J size : trop grand / too large');
  MakeJournal;
End;

Var
  Dev, A, S, FeatList : String;
  I, K2, Mb, Sectors, PartSectors, Root : LongInt;
  St : TSysStat;
  Ents : PDirEnts;
  MkfsOnly : Boolean;
  WantType : LongInt;
  ArgV : Array[0..63] Of String;
  NArgs : LongInt;

BEGIN
  Now := SysTime;
  FsCrcInit;
  FsName := 'ext2';
  FeatList := '';
  VolName := 'LINUX0';
  ResPct := 0;
  JrnMb := 0;
  GotInode := False;
  WantType := 2;
  Dev := '';
  NewLang := '';
  SrcRoot := '';
  BS := 1024;
  ISZ := 128;
  WantInodes := 0;
  A := SysArgStr(0);
  MkfsOnly := (Pos('mkfs', A) > 0) Or (Pos('mke2fs', A) > 0);
  If Pos('ext3', A) > 0 Then WantType := 3;
  If Pos('ext4', A) > 0 Then WantType := 4;
  Mb := 0;
  Quiet := False;
  Yes := False;
  Lang := SysLang;
  { arguments : "-b1024" est decoupe en "-b" "1024" }
  NArgs := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (NArgs < 62) And (Length(A) > 2) And (A[1] = '-') And
       (A[2] In ['b', 'I', 'N', 't', 'O', 'J', 'L', 'm', 'd', 's', 'l', 'r'])
    Then
    Begin
      ArgV[NArgs + 1] := Copy(A, 1, 2);
      ArgV[NArgs + 2] := Copy(A, 3, 200);
      NArgs := NArgs + 2;
    End
    Else If NArgs < 63 Then
    Begin
      Inc(NArgs);
      ArgV[NArgs] := A;
    End;
  End;
  Inc(NArgs);
  I := 1;
  While I < NArgs Do
  Begin
    A := ArgV[I];
    If (A = '-d') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      Dev := ArgV[I];
    End
    Else If (A = '-l') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      NewLang := ArgV[I];
      For K2 := 1 To Length(NewLang) Do NewLang[K2] := UpCase(NewLang[K2]);
    End
    Else If (A = '-s') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      Val(ArgV[I], Mb, Sectors);
    End
    Else If (A = '-r') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      SrcRoot := ArgV[I];
      While (Length(SrcRoot) > 0) And (SrcRoot[Length(SrcRoot)] = '/') Do
        Delete(SrcRoot, Length(SrcRoot), 1);
    End
    Else If (A = '-b') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      Val(ArgV[I], BS, K2);
      If (BS <> 1024) And (BS <> 2048) And (BS <> 4096) Then
        Die('-b : 1024, 2048 ou 4096');
    End
    Else If (A = '-I') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      Val(ArgV[I], ISZ, K2);
      GotInode := True;
      If (ISZ <> 128) And (ISZ <> 256) Then Die('-I : 128 ou 256');
    End
    Else If (A = '-N') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      Val(ArgV[I], WantInodes, K2);
    End
    Else If (A = '-t') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      A := ArgV[I];
      If A = 'ext2' Then WantType := 2
      Else If A = 'ext3' Then WantType := 3
      Else If A = 'ext4' Then WantType := 4
      Else Die(Msg(18) + A);
    End
    Else If (A = '-O') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      If FeatList <> '' Then FeatList := FeatList + ',';
      FeatList := FeatList + ArgV[I];
    End
    Else If (A = '-J') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      A := ArgV[I];
      If Copy(A, 1, 5) = 'size=' Then Val(Copy(A, 6, 10), JrnMb, K2)
      Else Die(Msg(18) + A);
      If JrnMb < 1 Then Die(Msg(18) + A);
      If WantType < 3 Then WantType := 3;
    End
    Else If A = '-j' Then
    Begin
      If WantType < 3 Then WantType := 3;
    End
    Else If (A = '-L') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      VolName := Copy(ArgV[I], 1, 16);
    End
    Else If (A = '-m') And (I + 1 < NArgs) Then
    Begin
      Inc(I);
      Val(ArgV[I], ResPct, K2);
      If (ResPct < 0) Or (ResPct > 50) Then Die('-m : 0..50');
    End
    Else If A = '-y' Then Yes := True
    Else If A = '-q' Then Quiet := True
    Else If MkfsOnly And (A <> '') And (A[1] <> '-') Then Dev := A
    Else
    Begin
      SysPut(1, Msg(14) + #10);
      SysExit(1);
    End;
    Inc(I);
  End;
  If MkfsOnly Then Yes := True;
  SetType(WantType);
  If (WantType = 4) And Not GotInode Then ISZ := 256;
  If FeatList <> '' Then ApplyFeatures(FeatList);
  { coherence des fonctions }
  If FeatMcsum Then FeatGdtCsum := False;
  If Feat64 And Not FeatExtents Then Die(Msg(18) + '64bit/extents');
  If FeatExtra And (ISZ < 256) Then FeatExtra := False;
  DescSz := 32;
  If Feat64 Then DescSz := 64;
  FsType := 2;
  If FeatJournal Then FsType := 3;
  If FeatExtents Then FsType := 4;
  If FsType = 2 Then FsName := 'ext2'
  Else If FsType = 3 Then FsName := 'ext3'
  Else FsName := 'ext4';
  MakeUuid;
  CsumSeed := FsCrc32c(-1, LongInt(@FsUuid), 16);
  LogBs := 10;
  While (1 Shl LogBs) < BS Do Inc(LogBs);
  BPG := BS * 8;
  FirstData := 0;
  If BS = 1024 Then FirstData := 1;
  If NewLang = '' Then
  Begin
    If Yes Then NewLang := LangCode[Lang]
    Else
    Begin
      S := Ask(Msg(2));
      If (S <> '') And (S[1] In ['1'..'5']) Then Lang := Ord(S[1]) - 48;
      NewLang := LangCode[Lang];
    End;
  End;
  Lang := SysLangOf(NewLang);
  SysSetLang(Lang);
  If Not MkfsOnly Then Say(Msg(1));
  If Dev = '' Then Dev := Ask(Msg(3));
  If Not Yes Then
  Begin
    S := Ask(Msg(4));
    If Not ((S <> '') And (UpCase(S[1]) In ['O', 'Y', 'J', 'S'])) Then
    Begin
      Say(Msg(5));
      SysExit(1);
    End;
  End;
  Fd := SysOpen(Dev, O_RDWR, 0);
  If Fd < 0 Then Die(Dev + ' : ' + SysErrorText(SysErrno));
  If MkfsOnly Then
  Begin
    { mkfs.ext2 : formate tout le peripherique (ou -s Mo) sans partition }
    Sectors := DiskSectors;
    If Mb > 0 Then
      If Mb * 2048 < Sectors Then Sectors := Mb * 2048;
    If Sectors > MAXGRP * 8 * (BS Div 512) * BS Then
      Sectors := MAXGRP * 8 * (BS Div 512) * BS;
    PartStart := 0;
    NBlocks := Sectors Div (BS Div 512);
    If NBlocks < 400 Then Die(Msg(12));
    Layout;
    FormatFs;
    SetInoBit(1);
    Inc(GrpDirs[0]);
    MakeLostFound;
    GetMem(Ents, SizeOf(TDirEnts));
    Ents^[0].Name := 'lost+found';
    Ents^[0].Ino := 11;
    Ents^[0].Typ := 2;
    WriteDir(2, 2, Ents, 1, $1ED, 0, 0, Now, Now, Now, 1, 0);
    SetupJournal;
    WriteMeta;
    SysSync;
    SysClose(Fd);
    Say(Msg(17));
    SysExit(0);
  End;
  Sectors := DiskSectors;
  If Mb > 0 Then
    If Mb * 2048 < Sectors Then Sectors := Mb * 2048;
  If Sectors < 4096 + 2048 Then Die(Msg(12));
  If Sectors > MAXGRP * 8 * (BS Div 512) * BS Then
    Sectors := MAXGRP * 8 * (BS Div 512) * BS;
  PartStart := 2048;
  PartSectors := Sectors - PartStart;
  NBlocks := PartSectors Div (BS Div 512);
  If NBlocks > MAXBLK - 8 Then NBlocks := MAXBLK - 8;
  Say(Msg(6));
  InstallBoot(Sectors);
  Say(Msg(7));
  Layout;
  FormatFs;
  Say(Msg(8));
  Copied := 0;
  If SysStat(SrcRoot + '/', St) < 0 Then Die('stat /');
  Root := 2;
  SetInoBit(1);
  { l'inode 2 (racine) fait partie des 10 reserves ; lost+found = 11 }
  Inc(GrpDirs[0]);
  MakeLostFound;
  SetupJournal;
  A := SrcRoot + '/';
  CopyDir(A, '', Root, Root, St);
  WriteMeta;
  SysSync;
  SysClose(Fd);
  Str(Copied, A);
  Say(Msg(15) + A);
  Say(Msg(10));
END.
