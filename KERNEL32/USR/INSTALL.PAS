{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/install : installe KERNEL32 sur un disque dur IDE.
   Le systeme en cours d'execution (la racine /, par exemple amorce depuis un
   autre disque, un CD ou une image) sert de source. L'installateur :
     1. partitionne le disque cible (MBR, une partition Linux 83h active
        commencant au secteur 2048),
     2. y cree un systeme de fichiers ext2 (blocs de 1 Ko, inodes de 128
        octets, groupes de 8192 blocs, revision 1, fonctions filetype et
        sparse_super : l'equivalent de mke2fs -t ext2 -b 1024 -I 128
        -O none,filetype,sparse_super) ecrit directement sur le peripherique,
     3. y copie l'arborescence de / (sans le contenu de /proc, /sys, /dev,
        /tmp, /mnt) avec modes, proprietaires, dates, liens symboliques et
        fichiers speciaux ; /etc/profile recoit la langue choisie
        (LANGUAGE=XX),
     4. installe le MBR et le chargeur stage2 (52 secteurs apres le MBR) tires
        de /usr/share/boot/MBR.BIN et STAGE2.BIN.
   Usage : install [-d disque] [-l langue] [-s Mo] [-r racine] [-y] [-q]
     -d  disque cible (defaut : demande ; ex. /dev/hdb)
     -l  langue du systeme installe : FR, EN, GR (allemand), SP, IT
     -s  taille de la partition en Mo (defaut : tout le disque)
     -r  racine source (defaut /) ; -y  ne rien demander (essais automatiques)  -q  silencieux
   Messages en cinq langues (LANGUAGE ou choix au debut).
}

Program Install;

Const
  BS = 1024;
  BPG = 8192;                 { blocs par groupe }
  IPG = 2048;                 { inodes par groupe }
  ISZ = 128;
  ITB = 256;                  { blocs de la table des inodes par groupe }
  MAXGRP = 256;
  MAXBLK = 2097152;           { 2 Go }
  MAXDIRENT = 4000;
  M : Array[1..17, 1..5] Of PChar = (
    ('Installation de LINUX-0 KERNEL32', 'LINUX-0 KERNEL32 installation',
     'Installation von LINUX-0 KERNEL32', 'Instalacion de LINUX-0 KERNEL32',
     'Installazione di LINUX-0 KERNEL32'),
    ('Langue : 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [1] : ',
     'Language: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [2]: ',
     'Sprache: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [3]: ',
     'Idioma: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [4]: ',
     'Lingua: 1 Francais, 2 English, 3 Deutsch, 4 Espanol, 5 Italiano [5]: '),
    ('Disque cible (par exemple /dev/hdb) : ', 'Target disk (for example /dev/hdb): ',
     'Zieldatentraeger (zum Beispiel /dev/hdb): ', 'Disco de destino (por ejemplo /dev/hdb): ',
     'Disco di destinazione (per esempio /dev/hdb): '),
    ('TOUT le contenu du disque sera efface. Continuer (oui/non) ? ',
     'ALL data on the disk will be erased. Continue (yes/no)? ',
     'ALLE Daten auf dem Datentraeger werden geloescht. Fortfahren (ja/nein)? ',
     'TODO el contenido del disco se borrara. Continuar (si/no)? ',
     'TUTTI i dati del disco saranno cancellati. Continuare (si/no)? '),
    ('Annule.', 'Cancelled.', 'Abgebrochen.', 'Cancelado.', 'Annullato.'),
    ('Partitionnement et amorce...', 'Partitioning...', 'Partitionierung...',
     'Particionando...', 'Partizionamento...'),
    ('Creation du systeme de fichiers ext2...', 'Creating the ext2 file system...',
     'Erstelle das ext2-Dateisystem...', 'Creando el sistema de ficheros ext2...',
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
     'Datentraeger nicht zugreifbar oder zu klein', 'disco inaccesible o demasiado pequeno',
     'disco inaccessibile o troppo piccolo'),
    ('plus de place sur le disque cible', 'target disk is full',
     'Zieldatentraeger ist voll', 'el disco de destino esta lleno',
     'il disco di destinazione e'' pieno'),
    ('Usage : install [-d disque] [-l FR|EN|GR|SP|IT] [-s Mo] [-y] [-q]',
     'Usage: install [-d disk] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]',
     'Aufruf: install [-d Platte] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]',
     'Uso: install [-d disco] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]',
     'Uso: install [-d disco] [-l FR|EN|GR|SP|IT] [-s MB] [-y] [-q]'),
    ('Fichiers copies : ', 'Files copied: ', 'Kopierte Dateien: ', 'Ficheros copiados: ',
     'File copiati: '),
    ('MBR.BIN ou STAGE2.BIN introuvable dans /usr/share/boot', 'MBR.BIN or STAGE2.BIN not found in /usr/share/boot',
     'MBR.BIN oder STAGE2.BIN fehlt in /usr/share/boot', 'No se encuentra MBR.BIN o STAGE2.BIN en /usr/share/boot',
     'MBR.BIN o STAGE2.BIN non trovato in /usr/share/boot'),
    ('Systeme de fichiers ext2 cree.', 'ext2 file system created.',
     'ext2-Dateisystem erstellt.', 'Sistema de ficheros ext2 creado.',
     'File system ext2 creato.'));
  LangCode : Array[1..5] Of String[2] = ('FR', 'EN', 'GR', 'SP', 'IT');

Type
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
  BlkBm : Array[0..MAXBLK Div 8 - 1] Of Byte;
  InoBm : Array[0..MAXGRP * IPG Div 8 - 1] Of Byte;
  GrpFreeBlk, GrpFreeIno, GrpDirs : Array[0..MAXGRP - 1] Of LongInt;
  GrpBBm, GrpIBm, GrpITab : Array[0..MAXGRP - 1] Of LongInt;
  FreeBlocks, FreeInodes : LongInt;
  Cursor : LongInt;                    { prochain bloc a essayer }
  NextIno : LongInt;
  Buf : Array[0..1023] Of Byte;
  Zero : Array[0..1023] Of Byte;
  Now : LongInt;
  Quiet, Yes : Boolean;
  Lang : LongInt;
  Copied : LongInt;
  NewLang, SrcRoot : String;
  Fail : Boolean;

Function Msg(Id : LongInt) : String;
Var P : PChar; X : String;
Begin
  P := M[Id, Lang];
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
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

Procedure WriteBlk(Blk : LongInt; Addr : LongInt);
Begin
  WriteAt(PartStart * 512 + Blk * BS, Addr, BS);
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

{ ---------- geometrie et allocation ---------- }

Function GroupBase(G : LongInt) : LongInt;
Begin
  GroupBase := 1 + G * BPG;
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
  HasBackup := (G = 0) Or (G = 1) Or IsPow(G, 3) Or IsPow(G, 5) Or IsPow(G, 7);
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

{ calcule la disposition des groupes ; marque les blocs de structure }
Procedure Layout;
Var G, Base, B, Fixed, Last, K : LongInt;
Begin
  NGroups := (NBlocks - 1 + BPG - 1) Div BPG;
  GdtBlocks := (NGroups * 32 + BS - 1) Div BS;
  FreeBlocks := 0;
  FreeInodes := NGroups * IPG - 10;
  FillChar(BlkBm, SizeOf(BlkBm), 0);
  FillChar(InoBm, SizeOf(InoBm), 0);
  For G := 0 To NGroups - 1 Do
  Begin
    Base := GroupBase(G);
    B := Base;
    If HasBackup(G) Then B := B + 1 + GdtBlocks;
    GrpBBm[G] := B;
    GrpIBm[G] := B + 1;
    GrpITab[G] := B + 2;
    Fixed := B + 2 + ITB - Base;
    Last := Base + BPG - 1;
    If Last > NBlocks - 1 Then Last := NBlocks - 1;
    For K := Base To B + 2 + ITB - 1 Do SetBlkBit(K);
    { blocs au-dela de la fin du systeme de fichiers : occupes }
    For K := Last + 1 To Base + BPG - 1 Do SetBlkBit(K);
    GrpFreeBlk[G] := Last - Base + 1 - Fixed;
    GrpFreeIno[G] := IPG;
    GrpDirs[G] := 0;
    FreeBlocks := FreeBlocks + GrpFreeBlk[G];
  End;
  { inodes reserves 1..10 }
  For K := 1 To 10 Do SetInoBit(K - 1);
  GrpFreeIno[0] := IPG - 10;
  NextIno := 12;
  Cursor := GrpITab[0] + ITB;
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
  G := (B - 1) Div BPG;
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

Type
  TBlk15 = Array[0..14] Of LongInt;

Procedure PutInode(Ino : LongInt; Mode, Uid, Gid, Size, ATime, CTime, MTime,
    Links, Sectors : LongInt; Var Blocks : TBlk15);
Var Off, G, Idx, K : LongInt; I128 : Array[0..127] Of Byte;
Begin
  FillChar(I128, SizeOf(I128), 0);
  PutW(LongInt(@I128), 0, Mode);
  PutW(LongInt(@I128), 2, Uid);
  PutD(LongInt(@I128), 4, Size);
  PutD(LongInt(@I128), 8, ATime);
  PutD(LongInt(@I128), 12, CTime);
  PutD(LongInt(@I128), 16, MTime);
  PutW(LongInt(@I128), 24, Gid);
  PutW(LongInt(@I128), 26, Links);
  PutD(LongInt(@I128), 28, Sectors);
  For K := 0 To 14 Do PutD(LongInt(@I128), 40 + K * 4, Blocks[K]);
  G := (Ino - 1) Div IPG;
  Idx := (Ino - 1) Mod IPG;
  Off := PartStart * 512 + GrpITab[G] * BS + Idx * ISZ;
  WriteAt(Off, LongInt(@I128), ISZ);
End;

{ ---------- ecriture de donnees : blocs directs et indirects ---------- }

Var
  FBlocks : TBlk15;          { i_block du fichier en cours }
  FNBlk : LongInt;           { nombre de blocs de donnees ecrits }
  FSect : LongInt;           { secteurs de 512 octets (indirects compris) }
  Ind1 : LongInt;            { bloc d'indirection simple courant }
  Ind2 : LongInt;            { bloc de double indirection }
  Ind1Buf, Ind2Buf : Array[0..1023] Of Byte;
  Ind1Cnt, Ind2Cnt : LongInt;

Procedure FileBegin;
Var K : LongInt;
Begin
  For K := 0 To 14 Do FBlocks[K] := 0;
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
  Inc(FSect, 2);
  If N < 12 Then
  Begin
    FBlocks[N] := B;
    Exit;
  End;
  N := N - 12;
  If N < 256 Then
  Begin
    If N = 0 Then
    Begin
      FBlocks[12] := AllocBlock;
      Inc(FSect, 2);
      FillChar(Ind1Buf, BS, 0);
    End;
    PutD(LongInt(@Ind1Buf), N * 4, B);
    WriteBlk(FBlocks[12], LongInt(@Ind1Buf));
    Exit;
  End;
  N := N - 256;
  { double indirection : N / 256 selectionne l'indirect, N mod 256 l'element }
  If N = 0 Then
  Begin
    FBlocks[13] := AllocBlock;
    Inc(FSect, 2);
    FillChar(Ind2Buf, BS, 0);
    Ind1 := 0;
  End;
  If N Mod 256 = 0 Then
  Begin
    If Ind1 <> 0 Then WriteBlk(Ind1, LongInt(@Ind1Buf));
    Ind1 := AllocBlock;
    Inc(FSect, 2);
    FillChar(Ind1Buf, BS, 0);
    PutD(LongInt(@Ind2Buf), (N Div 256) * 4, Ind1);
    WriteBlk(FBlocks[13], LongInt(@Ind2Buf));
  End;
  PutD(LongInt(@Ind1Buf), (N Mod 256) * 4, B);
  WriteBlk(Ind1, LongInt(@Ind1Buf));
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

Procedure EmitDirent(Addr, Off, Ino, RecLen, NameLen, Typ : LongInt; Const Name : String);
Var K : LongInt;
Begin
  PutD(Addr, Off, Ino);
  PutW(Addr, Off + 4, RecLen);
  PutB(Addr, Off + 6, NameLen);
  PutB(Addr, Off + 7, Typ);
  For K := 1 To NameLen Do PutB(Addr, Off + 7 + K, Ord(Name[K]));
End;

{ ecrit le repertoire Ino (parent Par) avec ses entrees ; rend les blocs }
Procedure WriteDir(Ino, Par : LongInt; Ents : PDirEnts; N : LongInt;
    Mode, Uid, Gid, ATime, CTime, MTime, SubDirs : LongInt; MinBlocks : LongInt);
Var K, Off, LastOff, Need, Blk, NB : LongInt;
Begin
  FileBegin;
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
    If Off + Need > BS Then
    Begin
      { fermer le bloc : le dernier enregistrement s'etend jusqu'au bout }
      PutW(LongInt(@Buf), LastOff + 4, BS - LastOff);
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
  PutW(LongInt(@Buf), LastOff + 4, BS - LastOff);
  Blk := AllocBlock;
  WriteBlk(Blk, LongInt(@Buf));
  FileAddBlock(Blk);
  Inc(NB);
  { blocs vides supplementaires (lost+found) }
  While NB < MinBlocks Do
  Begin
    FillChar(Buf, BS, 0);
    PutD(LongInt(@Buf), 0, 0);
    PutW(LongInt(@Buf), 4, BS);
    Blk := AllocBlock;
    WriteBlk(Blk, LongInt(@Buf));
    FileAddBlock(Blk);
    Inc(NB);
  End;
  PutInode(Ino, $4000 Or (Mode And $FFF), Uid, Gid, NB * BS, ATime, CTime, MTime,
           2 + SubDirs, FSect, FBlocks);
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
Var In1, N, Blk, Total : LongInt; Chunk : Array[0..1023] Of Byte; Blocks : TBlk15;
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
  Blocks := FBlocks;
  PutInode(Ino, St.Mode, St.Uid, St.Gid, Total, St.ATime, St.MTime, St.MTime,
           1, FSect, Blocks);
End;

Procedure CopyProfile(Ino : LongInt; Var St : TSysStat);
{ /etc/profile avec LANGUAGE=XX }
Var In1, K : LongInt; L, Out1 : String; Text : String; Have : Boolean;
    Chunk : Array[0..1023] Of Byte; Blk, Len : LongInt;
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
  If Not Have Then Text := 'LANGUAGE=' + NewLang + #10 + 'export LANGUAGE' + #10 + Text;
  FileBegin;
  FillChar(Chunk, BS, 0);
  Len := Length(Text);
  For K := 1 To Len Do Chunk[K - 1] := Ord(Text[K]);
  Blk := AllocBlock;
  WriteBlk(Blk, LongInt(@Chunk));
  FileAddBlock(Blk);
  PutInode(Ino, St.Mode, St.Uid, St.Gid, Len, St.ATime, St.MTime, St.MTime, 1,
           FSect, FBlocks);
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
        If Src[Length(Src)] = '/' Then Full := Src + Name Else Full := Src + '/' + Name;
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
                  PutInode(Ino2, S2.Mode, S2.Uid, S2.Gid, Length(Link), S2.ATime,
                           S2.MTime, S2.MTime, 1, 0, Blocks);
                End
                Else
                Begin
                  FillChar(Buf, BS, 0);
                  For K := 1 To Length(Link) Do Buf[K - 1] := Ord(Link[K]);
                  K := AllocBlock;
                  WriteBlk(K, LongInt(@Buf));
                  FileAddBlock(K);
                  Blocks := FBlocks;
                  PutInode(Ino2, S2.Mode, S2.Uid, S2.Gid, Length(Link), S2.ATime,
                           S2.MTime, S2.MTime, 1, FSect, Blocks);
                End;
              End;
          Else
            Begin
              { peripherique, tube : numero dans i_block[0] }
              FillChar(Blocks, SizeOf(Blocks), 0);
              Blocks[0] := S2.RDev;
              PutInode(Ino2, S2.Mode, S2.Uid, S2.Gid, 0, S2.ATime, S2.MTime,
                       S2.MTime, 1, 0, Blocks);
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

Procedure WriteSuper(G : LongInt);
Var Sb : Array[0..1023] Of Byte; K : LongInt; Base : LongInt;
Begin
  FillChar(Sb, BS, 0);
  PutD(LongInt(@Sb), 0, NGroups * IPG);
  PutD(LongInt(@Sb), 4, NBlocks);
  PutD(LongInt(@Sb), 8, 0);
  PutD(LongInt(@Sb), 12, FreeBlocks);
  PutD(LongInt(@Sb), 16, FreeInodes);
  PutD(LongInt(@Sb), 20, 1);
  PutD(LongInt(@Sb), 24, 0);
  PutD(LongInt(@Sb), 28, 0);
  PutD(LongInt(@Sb), 32, BPG);
  PutD(LongInt(@Sb), 36, BPG);
  PutD(LongInt(@Sb), 40, IPG);
  PutD(LongInt(@Sb), 44, 0);
  PutD(LongInt(@Sb), 48, Now);
  PutW(LongInt(@Sb), 52, 0);
  PutW(LongInt(@Sb), 54, $FFFF);
  PutW(LongInt(@Sb), 56, $EF53);
  PutW(LongInt(@Sb), 58, 1);
  PutW(LongInt(@Sb), 60, 1);
  PutW(LongInt(@Sb), 62, 0);
  PutD(LongInt(@Sb), 64, Now);
  PutD(LongInt(@Sb), 68, 0);
  PutD(LongInt(@Sb), 72, 0);
  PutD(LongInt(@Sb), 76, 1);
  PutW(LongInt(@Sb), 80, 0);
  PutW(LongInt(@Sb), 82, 0);
  PutD(LongInt(@Sb), 84, 11);
  PutW(LongInt(@Sb), 88, ISZ);
  PutW(LongInt(@Sb), 90, G);
  PutD(LongInt(@Sb), 92, 0);
  PutD(LongInt(@Sb), 96, 2);
  PutD(LongInt(@Sb), 100, 1);
  For K := 0 To 15 Do PutB(LongInt(@Sb), 104 + K, (Now Shr (K And 3)) + K * 17);
  PutB(LongInt(@Sb), 120, Ord('L'));
  PutB(LongInt(@Sb), 121, Ord('I'));
  PutB(LongInt(@Sb), 122, Ord('N'));
  PutB(LongInt(@Sb), 123, Ord('U'));
  PutB(LongInt(@Sb), 124, Ord('X'));
  PutB(LongInt(@Sb), 125, Ord('0'));
  Base := GroupBase(G);
  WriteBlk(Base, LongInt(@Sb));
End;

Procedure WriteMeta;
Var G, K, B : LongInt; Gd : Array[0..1023] Of Byte; Bb : Array[0..1023] Of Byte;
    Gdt : Array[0..8191] Of Byte;
Begin
  FillChar(Gdt, SizeOf(Gdt), 0);
  For G := 0 To NGroups - 1 Do
  Begin
    PutD(LongInt(@Gdt), G * 32, GrpBBm[G]);
    PutD(LongInt(@Gdt), G * 32 + 4, GrpIBm[G]);
    PutD(LongInt(@Gdt), G * 32 + 8, GrpITab[G]);
    PutW(LongInt(@Gdt), G * 32 + 12, GrpFreeBlk[G]);
    PutW(LongInt(@Gdt), G * 32 + 14, GrpFreeIno[G]);
    PutW(LongInt(@Gdt), G * 32 + 16, GrpDirs[G]);
  End;
  For G := 0 To NGroups - 1 Do
  Begin
    { bitmaps }
    For K := 0 To BS - 1 Do Bb[K] := BlkBm[((GroupBase(G) Div 8)) + K];
  End;
  For G := 0 To NGroups - 1 Do
  Begin
    { bitmap des blocs : bits du groupe (le debut du groupe est un
      multiple de 8 + 1 : on recopie bit a bit) }
    FillChar(Bb, BS, 0);
    For K := 0 To BPG - 1 Do
      If GetBlkBit(GroupBase(G) + K) Then Bb[K Shr 3] := Bb[K Shr 3] Or (1 Shl (K And 7));
    WriteBlk(GrpBBm[G], LongInt(@Bb));
    FillChar(Bb, BS, 0);
    For K := 0 To IPG - 1 Do
      If (InoBm[(G * IPG + K) Shr 3] And (1 Shl ((G * IPG + K) And 7))) <> 0 Then
        Bb[K Shr 3] := Bb[K Shr 3] Or (1 Shl (K And 7));
    For K := IPG To BPG - 1 Do Bb[K Shr 3] := Bb[K Shr 3] Or (1 Shl (K And 7));
    WriteBlk(GrpIBm[G], LongInt(@Bb));
    If HasBackup(G) Then
    Begin
      WriteSuper(G);
      For K := 0 To GdtBlocks - 1 Do
      Begin
        Move(Gdt[K * BS], Gd, BS);
        WriteBlk(GroupBase(G) + 1 + K, LongInt(@Gd));
      End;
    End;
  End;
End;

{ ---------- mke2fs : zone des inodes a zero, lost+found ---------- }

Procedure FormatFs;
Var G, K : LongInt;
Begin
  FillChar(Zero, BS, 0);
  For G := 0 To NGroups - 1 Do
    For K := 0 To ITB - 1 Do WriteBlk(GrpITab[G] + K, LongInt(@Zero));
End;

Procedure MakeLostFound;
Var Ents : PDirEnts; Blocks : TBlk15;
Begin
  GetMem(Ents, SizeOf(TDirEnts));
  Inc(NextIno, 0);
  { inode 11 reserve pour lost+found : allouer explicitement }
  SetInoBit(10);
  Dec(GrpFreeIno[0]);
  Dec(FreeInodes);
  Inc(GrpDirs[0]);
  WriteDir(11, 2, Ents, 0, $1C0, 0, 0, Now, Now, Now, 0, 12);
  FreeMem(Ents, SizeOf(TDirEnts));
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
Var Mbr : Array[0..511] Of Byte; F, N, K, Ns2 : LongInt; St2 : Array[0..65535] Of Byte;
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

Var
  Dev, A, S : String;
  I, K2, Mb, Sectors, PartSectors, Root : LongInt;
  St : TSysStat;
  Ents : PDirEnts;
  MkfsOnly : Boolean;

BEGIN
  Now := SysTime;
  Dev := '';
  NewLang := '';
  SrcRoot := '';
  A := SysArgStr(0);
  MkfsOnly := Pos('mkfs', A) > 0;
  Mb := 0;
  Quiet := False;
  Yes := False;
  Lang := SysLang;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-d') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Dev := SysArgStr(I);
    End
    Else If (A = '-l') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      NewLang := SysArgStr(I);
      For K2 := 1 To Length(NewLang) Do NewLang[K2] := UpCase(NewLang[K2]);
    End
    Else If (A = '-s') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), Mb, Sectors);
    End
    Else If (A = '-r') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      SrcRoot := SysArgStr(I);
      While (Length(SrcRoot) > 0) And (SrcRoot[Length(SrcRoot)] = '/') Do
        Delete(SrcRoot, Length(SrcRoot), 1);
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
    If Sectors > 4000000 Then Sectors := 4000000;
    PartStart := 0;
    NBlocks := Sectors Div 2;
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
  If Sectors > 4000000 Then Sectors := 4000000;
  PartStart := 2048;
  PartSectors := Sectors - PartStart;
  NBlocks := PartSectors Div 2;
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
  Dec(GrpFreeIno[0], 0);
  { l'inode 2 (racine) fait partie des 10 reserves ; lost+found = 11 }
  Inc(GrpDirs[0]);
  MakeLostFound;
  A := SrcRoot + '/';
  CopyDir(A, '', Root, Root, St);
  WriteMeta;
  SysSync;
  SysClose(Fd);
  Str(Copied, A);
  Say(Msg(15) + A);
  Say(Msg(10));
END.
