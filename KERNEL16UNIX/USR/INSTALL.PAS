{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: Programme d'installation de LINUX-0 (/bin/install) : installe
   le systeme sur un disque dur, a partir des disquettes d'installation ou
   du CD-ROM. Il n'y a qu'un type d'installation, UFS seul :
    1. choix du disque dur (pas celui d'ou le systeme a demarre) et de la
       langue du systeme installe;
    2. table des partitions (MBR, code /mdec/mbr), alignees sur les
       cylindres du BIOS : partition 1 UFS1 active (type A5h), amorcee
       directement (amorce /mdec/ufsboot dans ses 8 premiers Ko, noyau
       /unix), et partition 2 de va-et-vient de 4 Mo (type 82h);
    3. creation du systeme de fichiers UFS1 (comme newfs);
    4. copie du noyau, puis extraction des volumes tar de la distribution
       (disquettes 2, 3, ... lues directement sur /dev/fd0, ou fichiers
       /dist/volN.tar du CD-ROM), avec modes, proprietaires et dates;
    5. si la langue choisie n'est pas le francais, /etc/profile du systeme
       installe recoit "LANGUAGE=XX; export LANGUAGE".
   Messages en cinq langues, selon la variable d'environnement LANGUAGE :
   francais (defaut), EN anglais, GR allemand, SP espagnol, IT italien.
   Sur la disquette ou le CD d'installation, l'utilisateur "install" a ce
   programme pour interpreteur de connexion.
   Usage : install
}

Program Install;

{$M 8192,0,0}
{$I-}

Const
 { UFS1 : memes parametres que makefs -t ffs -o version=1 }
 FSIZE=1024; BSIZE=8192; FRAG=8; INOPB=64;
 SBLKNO=16; CBLKNO=24; IBLKNO=32;
 MAXFPG=32768;            { fragments par groupe de cylindres au plus }
 SWAPMB=4; MINUFSMB=8;
 DIOCGINFO=$6401; DIOCRESCAN=$6402; DIOCINVAL=$6403;
 NLANG=5;
 { numeros des messages }
 M_TITLE=1; M_ABORTED=2; M_YESNO=3; M_SEEK=4; M_WRITESEC=5; M_NODISK=6;
 M_DISKS=7; M_D1=8; M_D2=9; M_WHICHDISK=10; M_BADCHOICE=11; M_TYPE=12;
 M_TOOSMALL=13; M_PARTS=14; M_PARTUFS=15; M_PARTSWAP=16; M_RESCAN=17;
 M_BUSY=18; M_MKFS=19; M_MKFSEND=20; M_TOOBIG=21; M_CGBIG=22; M_NOTVOL=23;
 M_VOLUME=24; M_DONE=25; M_INCOMPLETE=26; M_INSERT=27; M_BADVOLFILE=28;
 M_NOTDISK=29; M_ROOTONLY=30; M_SRCCD=31; M_SRCFD=32; M_BADMBR=33;
 M_BADBOOT=34; M_NOKERNEL=35; M_WARN=36; M_CONTINUE=37; M_CANCEL=38;
 M_MOUNT=39; M_COPYK=40; M_INSTDONE=41; M_REMOVECD=42; M_REMOVEFD=43;
 M_LOGIN=44; M_REBOOT=45; M_REINSERT=46; M_LANGQ=47; M_LANGINFO=48;
 M_PROFILE=49; M_SMALLUFS=50;
 NMSG=50;

 { messages : colonnes FR, EN, GR (allemand), SP (espagnol), IT }
 Tab: Array[1..NMSG,1..NLANG] Of PChar = (
  ('Installation de LINUX-0 sur un disque dur',
   'LINUX-0 installation on a hard disk',
   'Installation von LINUX-0 auf einer Festplatte',
   'Instalacion de LINUX-0 en un disco duro',
   'Installazione di LINUX-0 su un disco fisso'),
  ('Installation abandonnee.', 'Installation aborted.',
   'Installation abgebrochen.', 'Instalacion abandonada.',
   'Installazione annullata.'),
  ('(oui/non)', '(yes/no)', '(ja/nein)', '(si/no)', '(si/no)'),
  ('positionnement : %1', 'seek: %1', 'Positionierung: %1',
   'posicionamiento: %1', 'posizionamento: %1'),
  ('ecriture du secteur %1 : %2', 'write of sector %1: %2',
   'Schreiben des Sektors %1: %2', 'escritura del sector %1: %2',
   'scrittura del settore %1: %2'),
  ('aucun disque dur disponible', 'no hard disk available',
   'keine Festplatte verfuegbar', 'ningun disco duro disponible',
   'nessun disco fisso disponibile'),
  ('Disques durs :', 'Hard disks:', 'Festplatten:', 'Discos duros:',
   'Dischi fissi:'),
  ('  %1) /dev/%2 : %3 Mo (%4 cylindres, ',
   '  %1) /dev/%2: %3 MB (%4 cylinders, ',
   '  %1) /dev/%2: %3 MB (%4 Zylinder, ',
   '  %1) /dev/%2: %3 MB (%4 cilindros, ',
   '  %1) /dev/%2: %3 MB (%4 cilindri, '),
  ('%1 tetes, %2 secteurs par piste)', '%1 heads, %2 sectors per track)',
   '%1 Koepfe, %2 Sektoren pro Spur)', '%1 cabezas, %2 sectores por pista)',
   '%1 testine, %2 settori per traccia)'),
  ('Disque ou installer LINUX-0 [1] : ', 'Disk to install LINUX-0 on [1]: ',
   'Festplatte fuer LINUX-0 [1]: ', 'Disco donde instalar LINUX-0 [1]: ',
   'Disco su cui installare LINUX-0 [1]: '),
  ('choix invalide', 'invalid choice', 'ungueltige Auswahl',
   'opcion no valida', 'scelta non valida'),
  ('Type d''installation : UFS seul (amorce et racine UFS1, va-et-vient)',
   'Installation type: UFS only (UFS1 boot and root, swap)',
   'Installationsart: nur UFS (UFS1-Start und -Wurzel, Auslagerung)',
   'Tipo de instalacion: solo UFS (arranque y raiz UFS1, intercambio)',
   'Tipo di installazione: solo UFS (avvio e radice UFS1, swap)'),
  ('disque trop petit (au moins %1 Mo)', 'disk too small (at least %1 MB)',
   'Festplatte zu klein (mindestens %1 MB)',
   'disco demasiado pequeno (al menos %1 MB)',
   'disco troppo piccolo (almeno %1 MB)'),
  ('Partitions :', 'Partitions:', 'Partitionen:', 'Particiones:',
   'Partizioni:'),
  ('  /dev/%1%2 : UFS1, amorce et racine, %3 Mo',
   '  /dev/%1%2: UFS1, boot and root, %3 MB',
   '  /dev/%1%2: UFS1, Start und Wurzel, %3 MB',
   '  /dev/%1%2: UFS1, arranque y raiz, %3 MB',
   '  /dev/%1%2: UFS1, avvio e radice, %3 MB'),
  ('  /dev/%1%2 : va-et-vient, %3 Mo', '  /dev/%1%2: swap, %3 MB',
   '  /dev/%1%2: Auslagerung, %3 MB', '  /dev/%1%2: intercambio, %3 MB',
   '  /dev/%1%2: swap, %3 MB'),
  ('relecture de la table des partitions : %1',
   're-reading the partition table: %1',
   'erneutes Lesen der Partitionstabelle: %1',
   'relectura de la tabla de particiones: %1',
   'rilettura della tabella delle partizioni: %1'),
  ('%1 (/dev/%2) est occupe : %3', '%1 (/dev/%2) is busy: %3',
   '%1 (/dev/%2) ist belegt: %3', '%1 (/dev/%2) esta ocupado: %3',
   '%1 (/dev/%2) e occupato: %3'),
  ('Creation du systeme de fichiers UFS1 sur /dev/%1...',
   'Creating the UFS1 file system on /dev/%1...',
   'Anlegen des UFS1-Dateisystems auf /dev/%1...',
   'Creacion del sistema de archivos UFS1 en /dev/%1...',
   'Creazione del file system UFS1 su /dev/%1...'),
  (' %1 groupe(s), %2 inodes, %3 Ko libres',
   ' %1 group(s), %2 inodes, %3 KB free',
   ' %1 Gruppe(n), %2 Inodes, %3 KB frei',
   ' %1 grupo(s), %2 inodos, %3 KB libres',
   ' %1 gruppo/i, %2 inode, %3 KB liberi'),
  ('partition trop grande', 'partition too large', 'Partition zu gross',
   'particion demasiado grande', 'partizione troppo grande'),
  ('groupe de cylindres trop grand', 'cylinder group too large',
   'Zylindergruppe zu gross', 'grupo de cilindros demasiado grande',
   'gruppo di cilindri troppo grande'),
  ('C''est le volume %1, pas le volume %2.',
   'This is volume %1, not volume %2.', 'Das ist Datentraeger %1, nicht %2.',
   'Es el volumen %1, no el volumen %2.', 'E il volume %1, non il volume %2.'),
  ('Volume %1/%2 ', 'Volume %1/%2 ', 'Datentraeger %1/%2 ', 'Volumen %1/%2 ',
   'Volume %1/%2 '),
  (' termine', ' done', ' fertig', ' terminado', ' terminato'),
  ('volume %1 incomplet', 'volume %1 incomplete',
   'Datentraeger %1 unvollstaendig', 'volumen %1 incompleto',
   'volume %1 incompleto'),
  ('Inserez la disquette %1 et appuyez sur Entree. ',
   'Insert diskette %1 and press Enter. ',
   'Diskette %1 einlegen und Eingabetaste druecken. ',
   'Inserte el disquete %1 y pulse Intro. ',
   'Inserire il dischetto %1 e premere Invio. '),
  ('/dist/vol%1.tar invalide', '/dist/vol%1.tar is invalid',
   '/dist/vol%1.tar ist ungueltig', '/dist/vol%1.tar no es valido',
   '/dist/vol%1.tar non valido'),
  ('Ce n''est pas la disquette %1 de LINUX-0.',
   'This is not LINUX-0 diskette %1.', 'Das ist nicht LINUX-0-Diskette %1.',
   'No es el disquete %1 de LINUX-0.', 'Non e il dischetto %1 di LINUX-0.'),
  ('reserve au super-utilisateur', 'reserved to the superuser',
   'nur fuer den Superuser', 'reservado al superusuario',
   'riservato al superutente'),
  ('Source : CD-ROM (/dist)', 'Source: CD-ROM (/dist)',
   'Quelle: CD-ROM (/dist)', 'Origen: CD-ROM (/dist)',
   'Sorgente: CD-ROM (/dist)'),
  ('Source : disquettes d''installation (/dev/fd0)',
   'Source: installation diskettes (/dev/fd0)',
   'Quelle: Installationsdisketten (/dev/fd0)',
   'Origen: disquetes de instalacion (/dev/fd0)',
   'Sorgente: dischetti di installazione (/dev/fd0)'),
  ('/mdec/mbr invalide', '/mdec/mbr is invalid', '/mdec/mbr ist ungueltig',
   '/mdec/mbr no es valido', '/mdec/mbr non valido'),
  ('/mdec/ufsboot invalide', '/mdec/ufsboot is invalid',
   '/mdec/ufsboot ist ungueltig', '/mdec/ufsboot no es valido',
   '/mdec/ufsboot non valido'),
  ('/unix (noyau) introuvable', '/unix (kernel) not found',
   '/unix (Kernel) nicht gefunden', '/unix (nucleo) no encontrado',
   '/unix (kernel) non trovato'),
  ('ATTENTION : tout le contenu de /dev/%1 sera efface.',
   'WARNING: everything on /dev/%1 will be erased.',
   'ACHTUNG: der gesamte Inhalt von /dev/%1 wird geloescht.',
   'ATENCION: se borrara todo el contenido de /dev/%1.',
   'ATTENZIONE: tutto il contenuto di /dev/%1 sara cancellato.'),
  ('Continuer ?', 'Continue?', 'Fortfahren?', 'Continuar?', 'Continuare?'),
  ('annulee par l''utilisateur', 'cancelled by the user',
   'vom Benutzer abgebrochen', 'cancelada por el usuario',
   'annullata dall''utente'),
  ('montage de /dev/%1 : %2', 'mounting /dev/%1: %2',
   'Einhaengen von /dev/%1: %2', 'montaje de /dev/%1: %2',
   'montaggio di /dev/%1: %2'),
  ('Copie du noyau...', 'Copying the kernel...', 'Kopieren des Kernels...',
   'Copia del nucleo...', 'Copia del kernel...'),
  ('Installation terminee : %1 fichiers, %2 repertoires.',
   'Installation finished: %1 files, %2 directories.',
   'Installation beendet: %1 Dateien, %2 Verzeichnisse.',
   'Instalacion terminada: %1 archivos, %2 directorios.',
   'Installazione terminata: %1 file, %2 directory.'),
  ('Retirez le CD-ROM; LINUX-0 demarrera du disque dur.',
   'Remove the CD-ROM; LINUX-0 will boot from the hard disk.',
   'CD-ROM entfernen; LINUX-0 startet von der Festplatte.',
   'Retire el CD-ROM; LINUX-0 arrancara desde el disco duro.',
   'Rimuovere il CD-ROM; LINUX-0 si avviera dal disco fisso.'),
  ('Retirez la disquette; LINUX-0 demarrera du disque dur.',
   'Remove the diskette; LINUX-0 will boot from the hard disk.',
   'Diskette entfernen; LINUX-0 startet von der Festplatte.',
   'Retire el disquete; LINUX-0 arrancara desde el disco duro.',
   'Rimuovere il dischetto; LINUX-0 si avviera dal disco fisso.'),
  ('Connexion : root (sans mot de passe) ou invite (mot de passe invite).',
   'Login: root (no password) or invite (password invite).',
   'Anmeldung: root (ohne Passwort) oder invite (Passwort invite).',
   'Acceso: root (sin contrasena) o invite (contrasena invite).',
   'Accesso: root (senza password) o invite (password invite).'),
  ('Redemarrer maintenant ?', 'Reboot now?', 'Jetzt neu starten?',
   'Reiniciar ahora?', 'Riavviare ora?'),
  ('Remettez la disquette 1 et appuyez sur Entree. ',
   'Put diskette 1 back and press Enter. ',
   'Diskette 1 wieder einlegen und Eingabetaste druecken. ',
   'Vuelva a poner el disquete 1 y pulse Intro. ',
   'Rimettere il dischetto 1 e premere Invio. '),
  ('Langue du systeme installe (FR, EN, GR, SP, IT) [%1] : ',
   'Language of the installed system (FR, EN, GR, SP, IT) [%1]: ',
   'Sprache des installierten Systems (FR, EN, GR, SP, IT) [%1]: ',
   'Idioma del sistema instalado (FR, EN, GR, SP, IT) [%1]: ',
   'Lingua del sistema installato (FR, EN, GR, SP, IT) [%1]: '),
  ('Langue du systeme installe : %1', 'Language of the installed system: %1',
   'Sprache des installierten Systems: %1',
   'Idioma del sistema instalado: %1', 'Lingua del sistema installato: %1'),
  ('ecriture de /etc/profile : %1', 'writing /etc/profile: %1',
   'Schreiben von /etc/profile: %1', 'escritura de /etc/profile: %1',
   'scrittura di /etc/profile: %1'),
  ('disque trop petit', 'disk too small', 'Festplatte zu klein',
   'disco demasiado pequeno', 'disco troppo piccolo'));

Type
 TDiskInfo=Record
  Sectors: Longint;
  Heads, Spt, Cyls: Word;
  Start: Longint;
  PType, Bios: Byte;
 End;

Var
 Big: Array[0..8191] Of Byte;        { bloc de travail (groupe, superbloc) }
 Zero: Array[0..8191] Of Byte;
 Sec: Array[0..511] Of Byte;
 MbrCode: Array[0..511] Of Byte;
 UfsBoot: Array[0..8191] Of Byte;     { /mdec/ufsboot, lu avant d'effacer }
 UfsStart, UfsSize, SwapStart, SwapSize: Longint;
 CsTab: Array[0..1023] Of Byte;      { resume des groupes (64 groupes au plus) }
 Disk: String[7];                    { disque choisi : hda, hdb }
 Info: TDiskInfo;
 FromCD: Boolean;
 Lang, TLang: Integer;              { langue de l'installateur, du systeme }
 Now: Longint;
 Files,Dirs: Longint;
 { lecture d'un volume tar par blocs }
 VolFd: Integer;
 RBuf: Array[0..8191] Of Byte;
 RLen,RPos: Integer;

{ --- messages et langue -------------------------------------------------- }

Function PcStr(P: PChar): String;
Var S: String;
Begin
 S:='';
 While P^<>#0 Do Begin S:=S+P^; Inc(P) End;
 PcStr:=S;
End;

Function GetEnvVar(Name: String): String;
{ valeur de la variable d'environnement Name ('' si elle n'existe pas) }
Var I: Integer; S: String;
Begin
 GetEnvVar:='';
 For I:=0 To EnvCount-1 Do Begin
  S:=EnvStr(I);
  If Copy(S,1,Length(Name)+1)=Name+'=' Then Begin
   GetEnvVar:=Copy(S,Length(Name)+2,255); Exit;
  End;
 End;
End;

Function UpStr(S: String): String;
Var I: Integer;
Begin
 For I:=1 To Length(S) Do S[I]:=UpCase(S[I]);
 UpStr:=S;
End;

Function LangOf(V: String): Integer;
{ numero de la langue V : FR 1, EN 2, GR 3 (DE), SP 4 (ES), IT 5; 0 si
  inconnue }
Begin
 V:=Copy(UpStr(V),1,2);
 LangOf:=0;
 If V='FR' Then LangOf:=1
 Else If V='EN' Then LangOf:=2
 Else If (V='GR') Or (V='DE') Then LangOf:=3
 Else If (V='SP') Or (V='ES') Then LangOf:=4
 Else If V='IT' Then LangOf:=5;
End;

Function LangCode(L: Integer): String;
Begin
 LangCode:=Copy('FRENGRSPIT',2*L-1,2);
End;

Function LangTitle(L: Integer): String;
Begin
 Case L Of
  2: LangTitle:='English';
  3: LangTitle:='Deutsch';
  4: LangTitle:='Espanol';
  5: LangTitle:='Italiano';
  Else LangTitle:='Francais';
 End;
End;

Function Fmt(Id: Integer; A, B, C, D: String): String;
{ message Id dans la langue courante; %1 a %4 sont remplaces par A a D }
Var S, R: String; I: Integer;
Begin
 S:=PcStr(Tab[Id,Lang]);
 R:=''; I:=1;
 While I<=Length(S) Do Begin
  If (S[I]='%') And (I<Length(S)) And (S[I+1]>='1') And (S[I+1]<='4') Then Begin
   Case S[I+1] Of
    '1': R:=R+A;
    '2': R:=R+B;
    '3': R:=R+C;
    Else R:=R+D;
   End;
   Inc(I,2);
  End Else Begin R:=R+S[I]; Inc(I) End;
 End;
 Fmt:=R;
End;

Function Msg(Id: Integer): String;
Begin
 Msg:=Fmt(Id,'','','','');
End;

{ --- utilitaires ----------------------------------------------------- }

Function IStr(L: Longint): String;
Var S: String;
Begin
 Str(L,S); IStr:=S;
End;

Procedure Fatal(S: String);
Begin
 WriteLn;
 WriteLn('install : ',S);
 WriteLn(Msg(M_ABORTED));
 SysSync;
 Halt(1);
End;

Function Ask(Prompt: String): String;
Var S: String; C: Char; N: Integer;
Begin
 Write(Prompt);
 S:='';
 Repeat
  N:=SysRead(0,C,1);
  If N<=0 Then Halt(1);
  If C=#10 Then Break;
  If Length(S)<80 Then S:=S+C;
 Until False;
 While (S<>'')And(S[1]=' ') Do Delete(S,1,1);
 While (S<>'')And(S[Length(S)]=' ') Do Delete(S,Length(S),1);
 Ask:=S;
End;

Function Yes(Prompt: String): Boolean;
{ oui/non dans les cinq langues : oui o yes y ja j si s / non n no nein }
Var S: String;
Begin
 Repeat
  S:=UpStr(Ask(Prompt+' '+Msg(M_YESNO)+' '));
  If (S='OUI')Or(S='O')Or(S='YES')Or(S='Y')Or(S='JA')Or(S='J')Or
    (S='SI')Or(S='S') Then Begin Yes:=True; Exit End;
 Until (S='NON')Or(S='N')Or(S='NO')Or(S='NEIN');
 Yes:=False;
End;

Procedure PutW(Var B; O: Word; W: Word);
Begin
 MemW[Seg(B):Ofs(B)+O]:=W;
End;

Procedure PutL(Var B; O: Word; L: Longint);
Begin
 PutW(B,O,Word(L)); PutW(B,O+2,Word(L Shr 16));
End;

Procedure WriteAt(Fd: Integer; Sector: Longint; Var Buf; Count: Word);
{ Count octets a partir du secteur Sector du peripherique Fd }
Begin
 If SysLSeek(Fd,Sector*512,SEEK_SET)<0 Then
  Fatal(Fmt(M_SEEK,SysErrorText(Errno),'','',''));
 If SysWrite(Fd,Buf,Count)<>Count Then
  Fatal(Fmt(M_WRITESEC,IStr(Sector),SysErrorText(Errno),'',''));
End;

Procedure ZeroSectors(Fd: Integer; Sector, Count: Longint);
Var N: Longint;
Begin
 While Count>0 Do Begin
  If Count>16 Then N:=16 Else N:=Count;
  WriteAt(Fd,Sector,Zero,N*512);
  Inc(Sector,N); Dec(Count,N);
 End;
End;

Function LoadFile(Path: String; Var Buf; Max: Word): Integer;
Var Fd,N: Integer;
Begin
 Fd:=SysOpen(Path,O_RDONLY,0);
 If Fd<0 Then Fatal(Path+' : '+SysErrorText(Errno));
 N:=SysRead(Fd,Buf,Max);
 SysClose(Fd);
 LoadFile:=N;
End;

Function OpenDev(Name: String): Integer;
Var Fd: Integer;
Begin
 Fd:=SysOpen('/dev/'+Name,O_RDWR,0);
 If Fd<0 Then Fatal('/dev/'+Name+' : '+SysErrorText(Errno));
 OpenDev:=Fd;
End;

{ --- 1. choix du disque et de la langue ----------------------------- }

Procedure ChooseDisk;
Var
 Names: Array[1..4] Of String[7];
 Infos: Array[1..4] Of TDiskInfo;
 N,K,Fd,E: Integer; M: TMountInfo; RootDev,S: String; L: Char;
Begin
 RootDev:='';
 If SysMountInfo(1,M) Then RootDev:=M.Special;
 N:=0;
 For L:='a' To 'b' Do Begin
  S:='hd'+L;
  If Copy(RootDev,1,3)=S Then Continue;   { disque d'amorce (CD-ROM emule) }
  Fd:=SysOpen('/dev/'+S,O_RDONLY,0);
  If Fd<0 Then Continue;
  If SysIoctl(Fd,DIOCGINFO,Infos[N+1])=0 Then Begin
   Inc(N); Names[N]:=S;
  End;
  SysClose(Fd);
 End;
 If N=0 Then Fatal(Msg(M_NODISK));
 WriteLn(Msg(M_DISKS));
 For K:=1 To N Do With Infos[K] Do
  WriteLn(Fmt(M_D1,IStr(K),Names[K],IStr(Sectors Div 2048),IStr(Cyls)),
    Fmt(M_D2,IStr(Heads),IStr(Spt),'',''));
 K:=1;
 If N>1 Then Begin
  S:=Ask(Msg(M_WHICHDISK));
  If S<>'' Then Val(S,K,E);
  If (K<1)Or(K>N) Then Fatal(Msg(M_BADCHOICE));
 End;
 Disk:=Names[K]; Info:=Infos[K];
End;

Procedure ChooseLanguage;
{ langue du systeme installe : celle de l'installateur par defaut }
Var S: String;
Begin
 TLang:=Lang;
 S:=Ask(Fmt(M_LANGQ,LangCode(Lang),'','',''));
 If S<>'' Then Begin
  TLang:=LangOf(S);
  If TLang=0 Then Fatal(Msg(M_BADCHOICE));
 End;
 WriteLn(Fmt(M_LANGINFO,LangTitle(TLang),'','',''));
End;

{ --- 2. partitions ----------------------------------------------------- }

Procedure CHS(LBA: Longint; O: Word);
Var C,H,S: Longint;
Begin
 C:=LBA Div (Longint(Info.Heads)*Info.Spt);
 H:=(LBA Div Info.Spt) Mod Info.Heads;
 S:=LBA Mod Info.Spt+1;
 If C>1023 Then Begin C:=1023; H:=Info.Heads-1; S:=Info.Spt End;
 Sec[O]:=H; Sec[O+1]:=S Or ((C Shr 2) And $C0); Sec[O+2]:=C And 255;
End;

Procedure Entry(N: Integer; Boot: Boolean; Typ: Byte; Start, Size: Longint);
Var O: Word;
Begin
 O:=446+N*16;
 If Boot Then Sec[O]:=$80 Else Sec[O]:=0;
 CHS(Start,O+1); Sec[O+4]:=Typ; CHS(Start+Size-1,O+5);
 PutL(Sec,O+8,Start); PutL(Sec,O+12,Size);
End;

Procedure Partition;
{ partition 1 : UFS1 active; partition 2 : va-et-vient (si la place le
  permet) }
Var Cyl,Cyls,SwapCyl: Longint; Fd: Integer;
Begin
 Cyl:=Longint(Info.Heads)*Info.Spt;
 Cyls:=Info.Cyls; If Cyls>1024 Then Cyls:=1024;   { limite du BIOS (CHS) }
 SwapCyl:=(Longint(SWAPMB)*2048+Cyl-1) Div Cyl;
 If (Cyls-SwapCyl)*Cyl<Longint(MINUFSMB)*2048 Then SwapCyl:=0;
 { la premiere partition commence a la piste 1 (piste 0 : le MBR) }
 UfsStart:=Info.Spt;
 SwapSize:=SwapCyl*Cyl; SwapStart:=(Cyls-SwapCyl)*Cyl;
 UfsSize:=SwapStart-UfsStart;
 If UfsSize<Longint(MINUFSMB)*2048 Then
  Fatal(Fmt(M_TOOSMALL,IStr(MINUFSMB+SWAPMB),'','',''));
 WriteLn(Msg(M_PARTS));
 Fd:=OpenDev(Disk);
 Move(MbrCode,Sec,446);
 FillChar(Sec[446],64,0);
 WriteLn(Fmt(M_PARTUFS,Disk,'1',IStr(UfsSize Div 2048),''));
 Entry(0,True,$A5,UfsStart,UfsSize);
 If SwapSize>0 Then Begin
  WriteLn(Fmt(M_PARTSWAP,Disk,'2',IStr(SwapSize Div 2048),''));
  Entry(1,False,$82,SwapStart,SwapSize);
 End;
 Sec[510]:=$55; Sec[511]:=$AA;
 WriteAt(Fd,0,Sec,512);
 SysSync;
 If SysIoctl(Fd,DIOCRESCAN,Sec)<0 Then
  Fatal(Fmt(M_RESCAN,SysErrorText(Errno),'','',''));
 SysClose(Fd);
End;

Procedure Release;
{ demonte ce qui viendrait du disque cible }
Var I: Integer; M: TMountInfo;
Begin
 For I:=8 DownTo 2 Do
  If SysMountInfo(I,M) Then
   If Copy(M.Special,1,Length(Disk))=Disk Then
    If SysUmount(M.Dir)<0 Then
     Fatal(Fmt(M_BUSY,M.Dir,M.Special,SysErrorText(Errno),''));
End;

{ --- 3. UFS1 (newfs) ------------------------------------------------------ }

Procedure SetBit(Var B; O: Word; N: Longint);
Var P: Word;
Begin
 P:=Ofs(B)+O+Word(N Div 8);
 Mem[Seg(B):P]:=Mem[Seg(B):P] Or (1 Shl (N Mod 8));
End;

Function GetBit(Var B; O: Word; N: Longint): Boolean;
Begin
 GetBit:=Mem[Seg(B):Ofs(B)+O+Word(N Div 8)] And (1 Shl (N Mod 8))<>0;
End;

Procedure NewFs;
{ systeme de fichiers UFS1 vide sur /dev/<disque>1 : superbloc (et copies),
  groupes de cylindres (cartes des inodes, des fragments et des grappes,
  resumes), tables d'inodes, repertoire racine (inode 2) }
Var
 Fd,C,K,Run: Integer;
 Frags,Fpg,Ipg,Ncg,Dblk,CsSize,CsFrags,Root,Base,Ndblk,B,F: Longint;
 OIused,OFree,OClsum,OClus,ONext,CgSize: Word;
 Nb,Nf,Ni,Nd,Tot0,Tot1,Tot2,Tot3,Dsize: Longint;
 M,L: Integer;
 FrSum: Array[0..8] Of Longint;
 ClSum: Array[0..8] Of Longint;
Begin
 Write(Fmt(M_MKFS,Disk+'1','','',''));
 Frags:=UfsSize Div 2; Frags:=Frags-Frags Mod FRAG;
 If Frags<=MAXFPG Then Begin Ncg:=1; Fpg:=Frags End
 Else Begin
  Fpg:=MAXFPG; Ncg:=(Frags+Fpg-1) Div Fpg;
 End;
 { un inode pour 8 Ko, par blocs d'inodes }
 Ipg:=(Fpg*FSIZE Div 8192+INOPB-1) Div INOPB*INOPB;
 Dblk:=IBLKNO+(Ipg Div INOPB)*FRAG;
 { dernier groupe trop petit : abandonne }
 If (Ncg>1)And(Frags-(Ncg-1)*Fpg<Dblk+64) Then Begin
  Dec(Ncg); Frags:=Ncg*Fpg;
 End;
 If Ncg>64 Then Fatal(Msg(M_TOOBIG));
 CsSize:=((Ncg*16+FSIZE-1) Div FSIZE)*FSIZE; CsFrags:=CsSize Div FSIZE;
 Root:=Dblk+CsFrags;
 OIused:=174; OFree:=OIused+Ipg Div 8;
 OClsum:=((OFree+Fpg Div 8+3) Div 4)*4-4;
 OClus:=OClsum+9*4;
 ONext:=OClus+(Fpg Div FRAG+7) Div 8;
 CgSize:=((ONext+FSIZE-1) Div FSIZE)*FSIZE;
 If CgSize>BSIZE Then Fatal(Msg(M_CGBIG));
 Fd:=OpenDev(Disk+'1');
 FillChar(CsTab,SizeOf(CsTab),0);
 Tot0:=0; Tot1:=0; Tot2:=0; Tot3:=0;
 For C:=0 To Ncg-1 Do Begin
  Base:=C*Fpg;
  Ndblk:=Frags-Base; If Ndblk>Fpg Then Ndblk:=Fpg;
  FillChar(Big,SizeOf(Big),0);
  PutL(Big,4,$090255); PutL(Big,8,Now); PutL(Big,12,C);
  PutW(Big,16,1); PutW(Big,18,Ipg); PutL(Big,20,Ndblk);
  PutL(Big,44,Dblk);
  PutL(Big,84,168); PutL(Big,88,172); PutL(Big,92,OIused); PutL(Big,96,OFree);
  PutL(Big,100,ONext); PutL(Big,104,OClsum); PutL(Big,108,OClus);
  PutL(Big,112,Ndblk Div FRAG);
  { inodes 0, 1 (reserves) et 2 (racine) }
  If C=0 Then Begin
   SetBit(Big,OIused,0); SetBit(Big,OIused,1); SetBit(Big,OIused,2);
  End;
  { fragments libres : tout sauf les metadonnees du groupe (et, dans le
    groupe 0, le resume des groupes et le bloc de la racine) }
  For F:=0 To Ndblk-1 Do
   If (F>=Dblk) And Not ((C=0) And (F<=Root)) Then SetBit(Big,OFree,F);
  Nb:=0; Nf:=0; Run:=0;
  For K:=0 To 8 Do Begin FrSum[K]:=0; ClSum[K]:=0 End;
  For B:=0 To Ndblk Div FRAG-1 Do Begin
   M:=0;
   For K:=0 To FRAG-1 Do If GetBit(Big,OFree,B*FRAG+K) Then M:=M Or (1 Shl K);
   If M=255 Then Begin
    Inc(Nb); SetBit(Big,OClus,B); Inc(Run);
   End Else Begin
    If Run>0 Then Begin If Run>8 Then Run:=8; Inc(ClSum[Run]); Run:=0 End;
    L:=0;
    For K:=0 To FRAG Do
     If (K<FRAG) And (M And (1 Shl K)<>0) Then Inc(L)
     Else Begin
      If L>0 Then Begin Inc(FrSum[L]); Inc(Nf,L) End;
      L:=0;
     End;
   End;
  End;
  If Run>0 Then Begin If Run>8 Then Run:=8; Inc(ClSum[Run]) End;
  For K:=1 To 7 Do PutL(Big,52+K*4,FrSum[K]);
  For K:=1 To 8 Do PutL(Big,OClsum+K*4,ClSum[K]);
  If C=0 Then Nd:=1 Else Nd:=0;
  If C=0 Then Ni:=Ipg-3 Else Ni:=Ipg;
  PutL(Big,24,Nd); PutL(Big,28,Nb); PutL(Big,32,Ni); PutL(Big,36,Nf);
  PutL(CsTab,C*16,Nd); PutL(CsTab,C*16+4,Nb); PutL(CsTab,C*16+8,Ni);
  PutL(CsTab,C*16+12,Nf);
  Inc(Tot0,Nd); Inc(Tot1,Nb); Inc(Tot2,Ni); Inc(Tot3,Nf);
  WriteAt(Fd,(Base+CBLKNO)*2,Big,CgSize);
  { table des inodes a zero }
  ZeroSectors(Fd,(Base+IBLKNO)*2,(Dblk-IBLKNO)*2);
  Write('.');
 End;
 { resume des groupes }
 WriteAt(Fd,Dblk*2,CsTab,CsSize);
 { inode 2 : la racine }
 FillChar(Big,512,0);
 PutW(Big,2*128,$41ED); PutW(Big,2*128+2,2); PutL(Big,2*128+8,512);
 PutL(Big,2*128+16,Now); PutL(Big,2*128+24,Now); PutL(Big,2*128+32,Now);
 PutL(Big,2*128+40,Root); PutL(Big,2*128+104,2);
 PutL(Big,2*128+108,Now Xor $5A5A);
 WriteAt(Fd,IBLKNO*2,Big,512);
 { repertoire racine : "." et ".." }
 FillChar(Big,FSIZE,0);
 PutL(Big,0,2); PutW(Big,4,12); Big[6]:=4; Big[7]:=1; Big[8]:=Ord('.');
 PutL(Big,12,2); PutW(Big,16,500); Big[18]:=4; Big[19]:=2;
 Big[20]:=Ord('.'); Big[21]:=Ord('.');
 WriteAt(Fd,Root*2,Big,FSIZE);
 { superbloc }
 Dsize:=Frags-Ncg*Dblk-CsFrags;
 FillChar(Big,2048,0);
 PutL(Big,8,SBLKNO); PutL(Big,12,CBLKNO); PutL(Big,16,IBLKNO);
 PutL(Big,20,Dblk);
 PutL(Big,24,0); PutL(Big,28,-1); PutL(Big,32,Now); PutL(Big,36,Frags);
 PutL(Big,40,Dsize); PutL(Big,44,Ncg); PutL(Big,48,BSIZE); PutL(Big,52,FSIZE);
 PutL(Big,56,FRAG); PutL(Big,60,5); PutL(Big,68,60); PutL(Big,72,-BSIZE);
 PutL(Big,76,-FSIZE); PutL(Big,80,13); PutL(Big,84,10); PutL(Big,88,8);
 PutL(Big,92,2048); PutL(Big,96,3); PutL(Big,100,1); PutL(Big,104,2048);
 PutL(Big,116,BSIZE Div 4); PutL(Big,120,INOPB); PutL(Big,124,2);
 PutL(Big,132,Fpg*2); PutL(Big,136,1);
 PutL(Big,144,Now); PutL(Big,148,Now Xor $1D2E3F);
 PutL(Big,152,Dblk); PutL(Big,156,CsSize); PutL(Big,160,CgSize);
 PutL(Big,168,Fpg*2); PutL(Big,172,Fpg*2); PutL(Big,176,Ncg); PutL(Big,180,1);
 PutL(Big,184,Ipg); PutL(Big,188,Fpg);
 PutL(Big,192,Tot0); PutL(Big,196,Tot1); PutL(Big,200,Tot2); PutL(Big,204,Tot3);
 Big[209]:=1; Big[211]:=$80;           { propre; FS_FLAGS_UPDATED }
 PutL(Big,860,BSIZE); PutL(Big,1000,8192);
 PutL(Big,1008,Tot0); PutL(Big,1016,Tot1); PutL(Big,1024,Tot2);
 PutL(Big,1032,Tot3);
 PutL(Big,1072,Now); PutL(Big,1080,Frags); PutL(Big,1088,Dsize);
 PutL(Big,1096,Dblk);
 PutL(Big,1196,16384); PutL(Big,1200,64); PutL(Big,1316,8); PutL(Big,1320,60);
 PutL(Big,1324,2); PutL(Big,1328,16875519); PutL(Big,1332,16392);
 PutL(Big,1336,BSIZE-1); PutL(Big,1344,FSIZE-1);
 PutL(Big,1356,1); PutL(Big,1360,1); PutL(Big,1372,$011954);
 WriteAt(Fd,16,Big,2048);
 For C:=0 To Ncg-1 Do WriteAt(Fd,(Longint(C)*Fpg+SBLKNO)*2,Big,2048);
 { zone d'amorce (8 premiers Ko) : UFSBOOT, qui charge /unix }
 Move(UfsBoot,Big,8192);
 PutL(Big,$1C,UfsStart); Big[$24]:=$80;
 WriteAt(Fd,0,Big,8192);
 SysClose(Fd);
 SysSync;
 WriteLn(Fmt(M_MKFSEND,IStr(Ncg),IStr(Ipg*Ncg),IStr(Tot1*BSIZE Div 1024),''));
End;

{ --- 4. copie ---------------------------------------------------------- }

Procedure CopyFile(Src, Dst: String; Mode: Word);
Var I,O,N: Integer;
Begin
 I:=SysOpen(Src,O_RDONLY,0);
 If I<0 Then Fatal(Src+' : '+SysErrorText(Errno));
 O:=SysCreat(Dst,Mode);
 If O<0 Then Fatal(Dst+' : '+SysErrorText(Errno));
 Repeat
  N:=SysRead(I,RBuf,SizeOf(RBuf));
  If N>0 Then If SysWrite(O,RBuf,N)<>N Then
   Fatal(Dst+' : '+SysErrorText(Errno));
 Until N<=0;
 SysClose(I); SysClose(O);
End;

Function ReadBlock(Var Blk): Boolean;
{ bloc de 512 octets suivant du volume }
Begin
 ReadBlock:=False;
 If RPos>=RLen Then Begin
  RLen:=SysRead(VolFd,RBuf,SizeOf(RBuf));
  If RLen<512 Then Exit;
  RPos:=0;
 End;
 Move(RBuf[RPos],Blk,512); Inc(RPos,512);
 ReadBlock:=True;
End;

Function Octal(O, Len: Integer): Longint;
Var L: Longint; K: Integer;
Begin
 L:=0;
 For K:=O To O+Len-1 Do
  If Chr(Sec[K]) In ['0'..'7'] Then L:=L*8+Sec[K]-48;
 Octal:=L;
End;

Function Extract(Num: Integer; Var Last: Integer): Boolean;
{ extrait le volume tar ouvert sur VolFd dans /mnt; Last : dernier volume }
Var
 Name: String; K,Fd,E: Integer; Size,Left: Longint; Mode,Uid,Gid: Word;
 MTime: Longint; Typ: Char; N: Word;
 Lab: Array[0..511] Of Byte;
Begin
 Extract:=False; RLen:=0; RPos:=0;
 { etiquette "LINUX-0 numero total" }
 If Not ReadBlock(Sec) Then Exit;
 Name:=''; K:=0;
 While (K<100)And(Sec[K]<>0) Do Begin Name:=Name+Chr(Sec[K]); Inc(K) End;
 If Name<>'VOLUME' Then Exit;
 If Not ReadBlock(Lab) Then Exit;
 Name:=''; K:=0;
 While (K<40)And(Lab[K]>=32) Do Begin Name:=Name+Chr(Lab[K]); Inc(K) End;
 If Copy(Name,1,8)<>'LINUX-0 ' Then Exit;
 Delete(Name,1,8);
 Val(Copy(Name,1,Pos(' ',Name)-1),K,E);
 If K<>Num Then Begin
  WriteLn(Fmt(M_NOTVOL,IStr(K),IStr(Num),'',''));
  Exit;
 End;
 Val(Copy(Name,Pos(' ',Name)+1,10),Last,E);
 Write(Fmt(M_VOLUME,IStr(Num),IStr(Last),'',''));
 Repeat
  If Not ReadBlock(Sec) Then Fatal(Fmt(M_INCOMPLETE,IStr(Num),'','',''));
  If Sec[0]=0 Then Break;
  Name:=''; K:=0;
  While (K<100)And(Sec[K]<>0) Do Begin Name:=Name+Chr(Sec[K]); Inc(K) End;
  While (Name<>'')And(Name[Length(Name)]='/') Do Delete(Name,Length(Name),1);
  If Copy(Name,1,2)='./' Then Delete(Name,1,2);
  Mode:=Octal(100,8); Uid:=Octal(108,8); Gid:=Octal(116,8);
  Size:=Octal(124,12); MTime:=Octal(136,12); Typ:=Chr(Sec[156]);
  Name:='/mnt/'+Name;
  If Typ='5' Then Begin
   SysMkdir(Name,$1FF);
   SysChown(Name,Uid,Gid); SysChmod(Name,Mode);
   Inc(Dirs);
  End Else Begin
   Fd:=SysCreat(Name,$180);
   If Fd<0 Then Fatal(Name+' : '+SysErrorText(Errno));
   Left:=Size;
   While Left>0 Do Begin
    If Not ReadBlock(Sec) Then Fatal(Fmt(M_INCOMPLETE,IStr(Num),'','',''));
    If Left>512 Then N:=512 Else N:=Left;
    If SysWrite(Fd,Sec,N)<>N Then Fatal(Name+' : '+SysErrorText(Errno));
    Dec(Left,N);
   End;
   SysClose(Fd);
   SysChown(Name,Uid,Gid); SysChmod(Name,Mode);
   SysUtime(Name,MTime,MTime);
   Inc(Files);
   If Files Mod 4=0 Then Write('.');
  End;
 Until False;
 WriteLn(Msg(M_DONE));
 Extract:=True;
End;

Procedure WriteProfile;
{ langue du systeme installe : "LANGUAGE=XX; export LANGUAGE" dans
  /etc/profile (rien si francais, la langue par defaut) }
Var Fd: Integer; S: String;
Begin
 If TLang=1 Then Exit;
 S:='LANGUAGE='+LangCode(TLang)+'; export LANGUAGE'+#10;
 Fd:=SysOpen('/mnt/etc/profile',O_WRONLY Or O_CREAT Or O_APPEND,$1A4);
 If Fd<0 Then Fatal(Fmt(M_PROFILE,SysErrorText(Errno),'','',''));
 If SysWrite(Fd,S[1],Length(S))<>Length(S) Then
  Fatal(Fmt(M_PROFILE,SysErrorText(Errno),'','',''));
 SysClose(Fd);
End;

Procedure Volumes;
Var Num,Last: Integer; S: String;
Begin
 Num:=2; Last:=2;
 Repeat
  If FromCD Then Begin
   Str(Num,S);
   VolFd:=SysOpen('/dist/vol'+S+'.tar',O_RDONLY,0);
   If VolFd<0 Then Fatal('/dist/vol'+S+'.tar : '+SysErrorText(Errno));
   If Not Extract(Num,Last) Then Fatal(Fmt(M_BADVOLFILE,S,'','',''));
   SysClose(VolFd);
  End Else Begin
   WriteLn;
   Ask(Fmt(M_INSERT,IStr(Num),'','',''));
   VolFd:=SysOpen('/dev/fd0',O_RDONLY,0);
   If VolFd<0 Then Fatal('/dev/fd0 : '+SysErrorText(Errno));
   { nouvelle disquette : le cache du lecteur est oublie }
   SysIoctl(VolFd,DIOCINVAL,Sec);
   If Not Extract(Num,Last) Then Begin
    WriteLn(Fmt(M_NOTDISK,IStr(Num),'','',''));
    SysClose(VolFd);
    Continue;
   End;
   SysClose(VolFd);
  End;
  Inc(Num);
 Until Num>Last;
End;

{ --- programme principal ------------------------------------------------ }

Var
 St: TStat;

BEGIN
 Now:=SysTime;
 FillChar(Zero,SizeOf(Zero),0);
 Lang:=LangOf(GetEnvVar('LANGUAGE'));
 If Lang=0 Then Lang:=1;
 WriteLn;
 WriteLn(Msg(M_TITLE));
 WriteLn('========================================');
 If GetEUid<>0 Then Fatal(Msg(M_ROOTONLY));
 FromCD:=(SysStat('/dist',St)=0)And(St.Mode And S_IFMT=S_IFDIR);
 If FromCD Then WriteLn(Msg(M_SRCCD)) Else WriteLn(Msg(M_SRCFD));
 If LoadFile('/mdec/mbr',MbrCode,512)<>512 Then Fatal(Msg(M_BADMBR));
 If LoadFile('/mdec/ufsboot',UfsBoot,8192)<>8192 Then Fatal(Msg(M_BADBOOT));
 If SysStat('/unix',St)<0 Then Fatal(Msg(M_NOKERNEL));
 WriteLn;
 ChooseDisk;
 WriteLn;
 WriteLn(Msg(M_TYPE));
 WriteLn;
 ChooseLanguage;
 WriteLn;
 WriteLn(Fmt(M_WARN,Disk,'','',''));
 If Not Yes(Msg(M_CONTINUE)) Then Fatal(Msg(M_CANCEL));
 WriteLn;
 Release;
 Partition;
 NewFs;
 { montage du nouveau systeme sur /mnt, puis copie du noyau }
 If SysMount('/dev/'+Disk+'1','/mnt',FS_UFS)<0 Then
  Fatal(Fmt(M_MOUNT,Disk+'1',SysErrorText(Errno),'',''));
 Write(Msg(M_COPYK));
 CopyFile('/unix','/mnt/unix',$1A4);
 WriteLn(' /unix');
 Files:=0; Dirs:=0;
 Volumes;
 WriteProfile;
 SysSync;
 SysUmount('/mnt');
 SysSync;
 WriteLn;
 WriteLn(Fmt(M_INSTDONE,IStr(Files),IStr(Dirs),'',''));
 If FromCD Then WriteLn(Msg(M_REMOVECD)) Else WriteLn(Msg(M_REMOVEFD));
 WriteLn(Msg(M_LOGIN));
 If Yes(Msg(M_REBOOT)) Then SysReboot;
 If Not FromCD Then Begin
  Ask(Msg(M_REINSERT));
  VolFd:=SysOpen('/dev/fd0',O_RDONLY,0);
  If VolFd>=0 Then Begin SysIoctl(VolFd,DIOCINVAL,Sec); SysClose(VolFd) End;
 End;
END.
