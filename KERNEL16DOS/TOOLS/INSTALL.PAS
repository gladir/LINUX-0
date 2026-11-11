{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7)
  @description: Programme d'installation de LINUX-0 (KERNEL16DOS) sur
    disque dur.
}

Program INSTALL;

{ Installe LINUX-0 16 bits sur un disque dur : partitionne (MBR + table de
  partitions), formate (FAT12 ou FAT16) et copie les composants choisis.
  Ecrans bleus plein texte (memoire video directe), en 5 langues : francais
  (defaut), anglais, allemand, italien, espagnol (variable LANGUAGE ou ecran
  des parametres ; c'est aussi la langue du systeme installe).

  Deroulement :
    1 bienvenue          2 date, heure, pays, langue
    3 nom de machine, utilisateur, HOME
    4 disque dur (BIOS 80h ou 81h), partition, conserver ou reformater
    5 type d'installation (minimale, standard, complete, personnalisee)
    6 reglages du noyau  7 recapitulatif et confirmation
    8 partitionnement, formatage, copie, \ETC\SYSCTL.D\CUSTOM.CFG et
      \ETC\PROFILE (les anciens deviennent *.OLD), secteur de boot et MBR
    9 fin : redemarrage ou retour au shell.

  Les acces au disque dur cible passent par le BIOS (INT 13h) avec un petit
  gestionnaire FAT12/FAT16 integre (FAT en memoire) : le disque 81h peut donc
  etre installe aussi. Le noyau est prevenu par INT 21h AH=70h. IO.SYS et
  MSDOS.SYS sont les deux premieres entrees de la racine, IO.SYS contigu
  depuis la grappe 2 (le secteur de boot MS-DOS 6.22 les cherche ainsi).
  Les fichiers viennent des disquettes A: ou B: (ou du CD) decrites par
  \INSTALL.INF (voir TOOLS\MAKEDISK.PAS) : DIR,chemin  /
  nn,dossier,nom,taille,composant. }

{$M 16384,0,140000}
{$R-,S-,V-}

Uses DOS;

Const
 mTitle=1; mKeyNav=2; mKeyEnter=3; mKeyQuit=4; mKeyBack=5; mKeyRetry=6; 
 mKeySkip=7; mKeyCheck=8; mKeyInstall=9; mKeyDone=10; mExitT=11; mExit1=12; 
 mExit2=13; mExit3=14; mQuit=15; mErrT=16; mErrNoDisk=17; mErrSmall=18; 
 mErrWrite=19; mErrFull=20; mErrMem=21; mErrEmpty=22; mErrBad=23; mErrSys=24; 
 mWel1=25; mWel2=26; mWelK1=27; mWelK2=28; mWelK3=29; mWelWarn=30; mHelpT=31; 
 mHelp1=32; mHelp2=33; mSetIntro=34; mSetDate=35; mSetCountry=36; 
 mSetLang=37; mSetOk=38; mSetHelp=39; mDateQ=40; mEditQ=41; mBadVal=42; 
 mWait=43; mMacIntro=44; mMacHost=45; mMacUser=46; mMacHome=47; mGoOn=48; 
 mMo=49; mKo=50; mDskIntro=51; mDskDisk=52; mDskMode=53; mDskSize=54; 
 mStNoPart=55; mStOther=56; mStNoFmt=57; mStOk=58; mStBad=59; mModeFmt=60; 
 mModeKeep=61; mSizeQ=62; mTypIntro=63; mTyp1=64; mTyp2=65; mTyp3=66; 
 mTyp4=67; mNeed=68; mFree=69; mNoRoom=70; mComp0=71; mComp1=72; mComp2=73; 
 mComp3=74; mComp4=75; mComp5=76; mComp6=77; mComp7=78; mKrnIntro=79; 
 mKrnFiles=80; mKrnBuf=81; mKrnDrv=82; mSumT=83; mSumType=84; mClus=85; 
 mSumFmt=86; mSumKeep=87; mSumGo=88; mPhPart=89; mPhFmt=90; mPhCopy=91; 
 mPhCfg=92; mPhBoot=93; mPct=94; mCopying=95; mAskDisk=96; mReadErr=97; 
 mAskFile=98; mDoneT=99; mDone1=100; mDone2=101; mSkipped=102; 

Const
 MaxEntries=300;
 MaxDirs=24;
 MaxStack=200;
 MaxMap=200;
 ChunkSize=16384;
 kEnter=13;
 kEsc=27;
 kBack=8;
 kSpace=32;
 kF1=$3B00;
 kF2=$3C00;
 kF3=$3D00;
 kF4=$3E00;
 kUp=$4800;
 kDown=$5000;
 CountryCount=10;
 GaugeW=70;
 { etats du disque dur }
 dsNoDisk=0;
 dsNoPart=1;
 dsOther=2;
 dsNoFormat=3;
 dsReady=4;
 dsDamaged=5;
 { accents CP437 : `e = e aigu... (voir Fix) }
 FixKeys='eraEcuozdAOUBn1234qxypl';
 FixCodes:Array[1..23]of Byte=(130,138,133,144,135,151,147,136,131,132,148,
  129,225,164,161,162,163,160,168,173,141,149,139);
 LangCodes:Array[0..4]of String[2]=('FR','EN','GR','IT','SP');
 CountryCodes:Array[1..CountryCount]of Word=(33,2,32,1,44,49,43,41,39,34);
 DefCountry:Array[0..4]of Integer=(1,4,6,9,10);
 SysFile:Array[1..2]of String[9]=('IO.SYS','MSDOS.SYS');
 SysN11:Array[1..2]of String[11]=('IO      SYS','MSDOS   SYS');

Type
 TSec=Array[0..511]of Byte;
 TEntry=Record
  Name:String[12];
  Size:LongInt;
  Disk,Dir,Comp:Byte;
 End;
 TFat=Array[0..65519]of Byte;
 PFat=^TFat;
 TBuf=Array[0..32767]of Byte;
 PBuf=^TBuf;

Var
 Entries:Array[1..MaxEntries]of TEntry;
 EntryCount:Integer;
 DirName:Array[0..MaxDirs]of String[40];
 DirCl:Array[0..MaxDirs]of Word;
 DirCount:Integer;
 VidSeg:Word;
 Mono:Boolean;
 Lang,CountryIdx:Integer;
 A1,A2:String;
 aNorm,aTitle,aHi,aDlg,aBar,aGauge,aBorder:Byte;
 ListItems:Array[1..CountryCount]of String[40];
 { choix de l'utilisateur }
 Host,User,Home:String;
 FilesN,BufN:Integer;
 LastDr:Char;
 InstType:Integer;
 InstMask:Word;
 DiskSel,Probed:Integer;
 ChunkLen:Word;
 CustMask:Word;
 HdCount:Integer;
 Mode:Integer;          { 0 = reformater, 1 = conserver }
 SizeSec,MaxSec:LongInt;
 DState:Integer;
 { source }
 SrcDrv:Char;
 TotalBytes,DoneBytes:LongInt;
 CurFile:String;
 PhaseId:Integer;
 Skipped:Integer;
 { disque cible }
 Unit8:Byte;
 Spt,Heads,Cyls:Word;
 HdTotal:LongInt;
 PartLBA,PartSectors:LongInt;
 Stg:^TSec;
 StgRaw:Pointer;
 { volume FAT }
 BpbSpc,BpbRes,BpbNf,BpbRoot,BpbSpf:Word;
 RootSecs:Integer;
 RootStart,DataStart,Clusters,Bpc,FreeBytes:LongInt;
 Fat16:Boolean;
 Fat:PFat;
 FatLen:Word;
 FatDirty:Boolean;
 Hint:Word;
 DBuf:TSec;
 DLba:LongInt;
 DOff:Integer;
 NowTm:LongInt;
 Seen:Array[0..4095]of Byte;
 Bad:Boolean;
 MapOld,MapNew:Array[1..MaxMap]of Word;
 MapCount:Integer;
 DStack:Array[1..MaxStack]of Word;
 DSp:Integer;
 WFirst,WLast:Word;
 WSize:LongInt;
 WFull:Boolean;
 CopyBuf:PBuf;
 TxtBuf:Array[0..1023]of Char;
 TxtLen:Integer;

{ ---------------------------------------------------------------------- }
{ Utilitaires                                                             }
{ ---------------------------------------------------------------------- }

Function UpStr(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 UpStr:=S;
End;

Function NumStr(N:LongInt):String;
Var
 S:String;
Begin
 Str(N,S);
 NumStr:=S;
End;

Function Pad2(N:Integer):String;
Begin
 If N<10 Then Pad2:='0'+NumStr(N)Else Pad2:=NumStr(N);
End;

Function PadTo(S:String;N:Integer):String;
Begin
 While Length(S)<N do S:=S+' ';
 PadTo:=S;
End;

Function LE32(Var B:TSec;O:Integer):LongInt;
Begin
 LE32:=LongInt(B[O])+LongInt(B[O+1])*256+LongInt(B[O+2])*65536+
       LongInt(B[O+3])*16777216;
End;

Procedure PutLE32(Var B:TSec;O:Integer;V:LongInt);
Begin
 B[O]:=Byte(V and $FF);B[O+1]:=Byte((V shr 8)and $FF);
 B[O+2]:=Byte((V shr 16)and $FF);B[O+3]:=Byte((V shr 24)and $FF);
End;

Function Pick(Const F,E,G,I,S:String):String;
Begin
 Case Lang of
  0:Pick:=F;
  1:Pick:=E;
  2:Pick:=G;
  3:Pick:=I;
 Else
  Pick:=S;
 End;
End;

{ Remplace `x par un caractere accentue CP437 et %1, %2 par A1, A2 }
Function Fix(Const S:String):String;
Var
 I,P:Integer;
 R:String;
Begin
 R:='';
 I:=1;
 While I<=Length(S)do Begin
  If(S[I]='`')and(I<Length(S))Then Begin
   Inc(I);
   P:=Pos(S[I],FixKeys);
   If P>0 Then R:=R+Chr(FixCodes[P])Else R:=R+S[I];
  End
  Else If(S[I]='%')and(I<Length(S))and(S[I+1]='1')Then Begin
   R:=R+A1;Inc(I);
  End
  Else If(S[I]='%')and(I<Length(S))and(S[I+1]='2')Then Begin
   R:=R+A2;Inc(I);
  End
  Else R:=R+S[I];
  Inc(I);
 End;
 Fix:=R;
End;

Function Raw(Id:Integer):String;
Begin
 Case Id of
  mTitle:Raw:=Pick(
   'Installation de LINUX-0',
   'LINUX-0 Setup',
   'LINUX-0 Setup',
   'Installazione di LINUX-0',
   'Instalaci`2n de LINUX-0');
  mKeyNav:Raw:=Pick(
   ' ENTREE=Continuer  ECHAP/F4=Retour  F1=Aide  F3=Quitter',
   ' ENTER=Continue  ESC/F4=Back  F1=Help  F3=Exit',
   ' EINGABE=Weiter  ESC/F4=Zur`Uck  F1=Hilfe  F3=Beenden',
   ' INVIO=Continua  ESC/F4=Indietro  F1=Guida  F3=Esci',
   ' INTRO=Continuar  ESC/F4=Atr`4s  F1=Ayuda  F3=Salir');
  mKeyEnter:Raw:=Pick(
   ' ENTREE=Continuer  F3=Quitter',
   ' ENTER=Continue  F3=Exit',
   ' EINGABE=Weiter  F3=Beenden',
   ' INVIO=Continua  F3=Esci',
   ' INTRO=Continuar  F3=Salir');
  mKeyQuit:Raw:=Pick(
   ' ENTREE=Quitter',
   ' ENTER=Exit',
   ' EINGABE=Beenden',
   ' INVIO=Esci',
   ' INTRO=Salir');
  mKeyBack:Raw:=Pick(
   ' ENTREE=Retour',
   ' ENTER=Return',
   ' EINGABE=Zur`Uck',
   ' INVIO=Indietro',
   ' INTRO=Volver');
  mKeyRetry:Raw:=Pick(
   ' ENTREE=R`eessayer  ECHAP/F4=Annuler',
   ' ENTER=Retry  ESC/F4=Cancel',
   ' EINGABE=Wiederholen  ESC/F4=Abbrechen',
   ' INVIO=Riprova  ESC/F4=Annulla',
   ' INTRO=Reintentar  ESC/F4=Cancelar');
  mKeySkip:Raw:=Pick(
   ' ENTREE=R`eessayer  F2=Ignorer  ECHAP/F4=Annuler',
   ' ENTER=Retry  F2=Ignore  ESC/F4=Cancel',
   ' EINGABE=Wiederholen  F2=Ignorieren  ESC/F4=Abbrechen',
   ' INVIO=Riprova  F2=Ignora  ESC/F4=Annulla',
   ' INTRO=Reintentar  F2=Ignorar  ESC/F4=Cancelar');
  mKeyCheck:Raw:=Pick(
   ' ESPACE=Cocher  ENTREE=Continuer  ECHAP/F4=Retour  F3=Quitter',
   ' SPACE=Toggle  ENTER=Continue  ESC/F4=Back  F3=Exit',
   ' LEER=Wahl  EINGABE=Weiter  ESC/F4=Zur`Uck  F3=Beenden',
   ' SPAZIO=Scegli  INVIO=Continua  ESC/F4=Indietro  F3=Esci',
   ' ESPACIO=Marcar  INTRO=Continuar  ESC/F4=Atr`4s  F3=Salir');
  mKeyInstall:Raw:=Pick(
   ' ENTREE=Installer  ECHAP/F4=Retour  F3=Quitter',
   ' ENTER=Install  ESC/F4=Back  F3=Exit',
   ' EINGABE=Installieren  ESC/F4=Zur`Uck  F3=Beenden',
   ' INVIO=Installa  ESC/F4=Indietro  F3=Esci',
   ' INTRO=Instalar  ESC/F4=Atr`4s  F3=Salir');
  mKeyDone:Raw:=Pick(
   ' ENTREE=Red`emarrer  ECHAP/F4=Shell',
   ' ENTER=Restart  ESC/F4=Shell',
   ' EINGABE=Neustart  ESC/F4=Shell',
   ' INVIO=Riavvia  ESC/F4=Shell',
   ' INTRO=Reiniciar  ESC/F4=Shell');
  mExitT:Raw:=Pick(
   ' Installation inachev`ee ',
   ' Setup is not complete ',
   ' Setup nicht abgeschlossen ',
   ' Installazione incompleta ',
   ' Instalaci`2n incompleta ');
  mExit1:Raw:=Pick(
   'L''installation de LINUX-0 n''est pas termin`ee. Si vous '+
   'quittez maintenant, vous devrez relancer INSTALL pour '+
   'installer LINUX-0.',
   'LINUX-0 Setup is not complete. If you exit now, you will '+
   'have to run INSTALL again to install LINUX-0.',
   'Das Setup von LINUX-0 ist nicht abgeschlossen. Wenn Sie '+
   'jetzt beenden, m`Ussen Sie INSTALL erneut starten.',
   'L''installazione di LINUX-0 non `r completa. Se esci ora, '+
   'dovrai eseguire di nuovo INSTALL.',
   'La instalaci`2n de LINUX-0 no ha terminado. Si sale ahora, '+
   'tendr`4 que ejecutar INSTALL de nuevo.');
  mExit2:Raw:=Pick(
   'Pour reprendre l''installation, appuyez sur ENTREE.',
   'To continue Setup, press ENTER.',
   'Zum Fortsetzen die EINGABETASTE dr`Ucken.',
   'Per riprendere l''installazione premi INVIO.',
   'Para continuar la instalaci`2n pulse INTRO.');
  mExit3:Raw:=Pick(
   'Pour quitter INSTALL, appuyez sur F3.',
   'To exit Setup, press F3.',
   'Zum Beenden F3 dr`Ucken.',
   'Per uscire premi F3.',
   'Para salir pulse F3.');
  mQuit:Raw:=Pick(
   'Pour installer LINUX-0, tapez INSTALL.',
   'To install LINUX-0, type INSTALL.',
   'Geben Sie zur Installation INSTALL ein.',
   'Per installare LINUX-0 digita INSTALL.',
   'Para instalar LINUX-0 escriba INSTALL.');
  mErrT:Raw:=Pick(
   ' Erreur ',
   ' Error ',
   ' Fehler ',
   ' Errore ',
   ' Error ');
  mErrNoDisk:Raw:=Pick(
   'Aucun disque dur n''a `et`e d`etect`e.',
   'No hard disk was detected.',
   'Es wurde keine Festplatte erkannt.',
   'Nessun disco fisso rilevato.',
   'No se ha detectado ning`3n disco duro.');
  mErrSmall:Raw:=Pick(
   'Le disque dur est trop petit (4 Mo minimum).',
   'The hard disk is too small (4 MB minimum).',
   'Die Festplatte ist zu klein (mindestens 4 MB).',
   'Il disco fisso `r troppo piccolo (minimo 4 MB).',
   'El disco duro es demasiado peque`no (m`1nimo 4 MB).');
  mErrWrite:Raw:=Pick(
   'Erreur de lecture ou d''`ecriture du disque dur.',
   'Hard disk read or write error.',
   'Lese- oder Schreibfehler der Festplatte.',
   'Errore di lettura o scrittura del disco fisso.',
   'Error de lectura o escritura del disco duro.');
  mErrFull:Raw:=Pick(
   'Espace disque insuffisant ou r`epertoire racine plein.',
   'Not enough disk space, or the root directory is full.',
   'Nicht gen`Ugend Platz oder Stammverzeichnis voll.',
   'Spazio su disco insufficiente o directory radice piena.',
   'Espacio insuficiente o directorio ra`1z lleno.');
  mErrMem:Raw:=Pick(
   'M`emoire insuffisante.',
   'Not enough memory.',
   'Nicht gen`Ugend Speicher.',
   'Memoria insufficiente.',
   'Memoria insuficiente.');
  mErrEmpty:Raw:=Pick(
   'INSTALL.INF ne liste aucun fichier (ou IO.SYS / MSDOS.SYS '+
   'manque).',
   'INSTALL.INF lists no file (or IO.SYS / MSDOS.SYS is '+
   'missing).',
   'INSTALL.INF enth`Alt keine Dateien (oder IO.SYS / MSDOS.SYS '+
   'fehlt).',
   'INSTALL.INF non elenca file (o mancano IO.SYS / MSDOS.SYS).',
   'INSTALL.INF no lista archivos (o faltan IO.SYS / MSDOS.SYS).');
  mErrBad:Raw:=Pick(
   'Une grappe d`efectueuse se trouve au d`ebut du disque.',
   'A bad cluster is at the start of the disk.',
   'Am Anfang der Festplatte liegt ein defekter Cluster.',
   'Cluster difettoso all''inizio del disco.',
   'Hay un cl`4ster defectuoso al inicio del disco.');
  mErrSys:Raw:=Pick(
   'IO.SYS n''est pas au d`ebut du volume : le disque ne '+
   'd`emarrera pas.',
   'IO.SYS is not at the start of the volume: the disk will not '+
   'boot.',
   'IO.SYS liegt nicht am Anfang des Volumes: kein Start '+
   'm`Oglich.',
   'IO.SYS non `r all''inizio del volume: il disco non si '+
   'avvier`a.',
   'IO.SYS no est`4 al inicio del volumen: el disco no '+
   'arrancar`4.');
  mWel1:Raw:=Pick(
   'Bienvenue dans l''installation de LINUX-0 (KERNEL16DOS).',
   'Welcome to the LINUX-0 (KERNEL16DOS) setup.',
   'Willkommen beim Setup von LINUX-0 (KERNEL16DOS).',
   'Benvenuti nell''installazione di LINUX-0 (KERNEL16DOS).',
   'Bienvenido a la instalaci`2n de LINUX-0 (KERNEL16DOS).');
  mWel2:Raw:=Pick(
   'Ce programme partitionne le disque dur, le formate (FAT12 '+
   'ou FAT16) et installe le syst`eme.',
   'This program partitions the hard disk, formats it (FAT12 or '+
   'FAT16) and installs the system.',
   'Dieses Programm partitioniert die Festplatte, formatiert '+
   'sie (FAT12 oder FAT16) und installiert das System.',
   'Questo programma partiziona il disco fisso, lo formatta '+
   '(FAT12 o FAT16) e installa il sistema.',
   'Este programa particiona el disco duro, lo formatea (FAT12 '+
   'o FAT16) e instala el sistema.');
  mWelK1:Raw:=Pick(
   'Pour continuer, appuyez sur ENTREE.',
   'To continue, press ENTER.',
   'Zum Fortfahren die EINGABETASTE dr`Ucken.',
   'Per continuare premi INVIO.',
   'Para continuar pulse INTRO.');
  mWelK2:Raw:=Pick(
   'Pour obtenir de l''aide, appuyez sur F1.',
   'For help, press F1.',
   'F`Ur Hilfe F1 dr`Ucken.',
   'Per la guida premi F1.',
   'Para obtener ayuda pulse F1.');
  mWelK3:Raw:=Pick(
   'Pour quitter sans installer, appuyez sur F3.',
   'To exit without installing, press F3.',
   'Zum Beenden ohne Installation F3 dr`Ucken.',
   'Per uscire senza installare premi F3.',
   'Para salir sin instalar pulse F3.');
  mWelWarn:Raw:=Pick(
   'ATTENTION : le partitionnement et le formatage d`etruisent '+
   'les donn`ees du disque dur. Sauvegardez-les d''abord.',
   'WARNING: partitioning and formatting destroy the data on '+
   'the hard disk. Back it up first.',
   'ACHTUNG: Partitionieren und Formatieren zerst`Oren die '+
   'Daten der Festplatte. Sichern Sie diese zuerst.',
   'ATTENZIONE: partizionamento e formattazione distruggono i '+
   'dati del disco fisso. Esegui prima un backup.',
   'ATENCI`2N: particionar y formatear destruyen los datos del '+
   'disco duro. Haga antes una copia de seguridad.');
  mHelpT:Raw:=Pick(
   'Aide',
   'Help',
   'Hilfe',
   'Guida',
   'Ayuda');
  mHelp1:Raw:=Pick(
   'Cette installation partitionne le disque dur (MBR et table '+
   'de partitions), le formate en FAT12 ou FAT16, puis copie '+
   'les composants choisis depuis les disquettes (ou le CD). '+
   'Fl`eches : choisir ; ENTREE : valider ; ECHAP/F4 : retour.',
   'Setup partitions the hard disk (MBR and partition table), '+
   'formats it as FAT12 or FAT16, then copies the chosen '+
   'components from the disks (or the CD). Arrows: select; '+
   'ENTER: accept; ESC/F4: back.',
   'Das Setup partitioniert die Festplatte (MBR, '+
   'Partitionstabelle), formatiert sie mit FAT12 oder FAT16 und '+
   'kopiert die gew`Ahlten Komponenten von den Disketten (oder '+
   'der CD). Pfeile: w`Ahlen; EINGABE: best`Atigen; ESC/F4: '+
   'zur`Uck.',
   'L''installazione partiziona il disco fisso (MBR e tabella '+
   'delle partizioni), lo formatta in FAT12 o FAT16 e copia i '+
   'componenti scelti dai dischi (o dal CD). Frecce: scegli; '+
   'INVIO: conferma; ESC/F4: indietro.',
   'La instalaci`2n particiona el disco duro (MBR y tabla de '+
   'particiones), lo formatea en FAT12 o FAT16 y copia los '+
   'componentes elegidos desde los discos (o el CD). Flechas: '+
   'elegir; INTRO: aceptar; ESC/F4: volver.');
  mHelp2:Raw:=Pick(
   'Disque : si la partition existante est valide, vous pouvez '+
   'conserver vos donn`ees ; sinon toutes les partitions sont '+
   'supprim`ees et le disque est format`e. Le noyau ne g`ere '+
   'que la premi`ere partition du disque 80h.',
   'Disk: if the existing partition is valid you can keep your '+
   'data; otherwise all partitions are deleted and the disk is '+
   'formatted. The kernel only handles the first partition of '+
   'disk 80h.',
   'Festplatte: Ist die vorhandene Partition g`Ultig, k`Onnen '+
   'die Daten bleiben; sonst werden alle Partitionen gel`Oscht '+
   'und die Festplatte formatiert. Der Kernel nutzt nur die '+
   'erste Partition von 80h.',
   'Disco: se la partizione esistente `r valida puoi conservare '+
   'i dati; altrimenti tutte le partizioni sono eliminate e il '+
   'disco formattato. Il kernel gestisce solo la prima '+
   'partizione del disco 80h.',
   'Disco: si la partici`2n existente es v`4lida puede '+
   'conservar los datos; si no, se eliminan todas las '+
   'particiones y se formatea. El n`3cleo solo usa la primera '+
   'partici`2n del disco 80h.');
  mSetIntro:Raw:=Pick(
   'L''installation utilisera les param`etres suivants :',
   'Setup will use the following settings:',
   'Das Setup verwendet die folgenden Einstellungen:',
   'L''installazione user`a le impostazioni seguenti:',
   'La instalaci`2n usar`4 los siguientes par`4metros:');
  mSetDate:Raw:=Pick(
   'Date et heure',
   'Date and time',
   'Datum und Uhrzeit',
   'Data e ora',
   'Fecha y hora');
  mSetCountry:Raw:=Pick(
   'Pays',
   'Country',
   'Land',
   'Paese',
   'Pa`1s');
  mSetLang:Raw:=Pick(
   'Langue',
   'Language',
   'Sprache',
   'Lingua',
   'Idioma');
  mSetOk:Raw:=Pick(
   'Les param`etres sont corrects.',
   'The settings are correct.',
   'Die Einstellungen sind korrekt.',
   'Le impostazioni sono corrette.',
   'Los par`4metros son correctos.');
  mSetHelp:Raw:=Pick(
   'Choisissez une ligne avec HAUT/BAS et appuyez sur ENTREE '+
   'pour la modifier. La langue choisie est aussi celle du '+
   'syst`eme install`e (variable LANGUAGE).',
   'Select a line with UP/DOWN and press ENTER to change it. '+
   'The chosen language is also that of the installed system '+
   '(LANGUAGE variable).',
   'W`Ahlen Sie mit HOCH/RUNTER eine Zeile und dr`Ucken Sie '+
   'EINGABE zum `Andern. Die Sprache gilt auch f`Ur das '+
   'installierte System (Variable LANGUAGE).',
   'Scegli una riga con SU/GI`u e premi INVIO per modificarla. '+
   'La lingua scelta `r anche quella del sistema installato '+
   '(variabile LANGUAGE).',
   'Elija una l`1nea con ARRIBA/ABAJO y pulse INTRO para '+
   'cambiarla. El idioma elegido es tambi`en el del sistema '+
   'instalado (variable LANGUAGE).');
  mDateQ:Raw:=Pick(
   'Date et heure (AAAA-MM-JJ HH:MM) :',
   'Date and time (YYYY-MM-DD HH:MM):',
   'Datum und Uhrzeit (JJJJ-MM-TT HH:MM):',
   'Data e ora (AAAA-MM-GG HH:MM):',
   'Fecha y hora (AAAA-MM-DD HH:MM):');
  mEditQ:Raw:=Pick(
   'Tapez la nouvelle valeur puis ENTREE :',
   'Type the new value, then ENTER:',
   'Neuen Wert eingeben, dann EINGABE:',
   'Digita il nuovo valore e premi INVIO:',
   'Escriba el nuevo valor y pulse INTRO:');
  mBadVal:Raw:=Pick(
   'Valeur incorrecte. (touche)',
   'Invalid value. (key)',
   'Ung`Ultiger Wert. (Taste)',
   'Valore non valido. (tasto)',
   'Valor no v`4lido. (tecla)');
  mWait:Raw:=Pick(
   'Analyse du disque dur...',
   'Analyzing the hard disk...',
   'Festplatte wird analysiert...',
   'Analisi del disco fisso...',
   'Analizando el disco duro...');
  mMacIntro:Raw:=Pick(
   'Nom de la machine et compte utilisateur du syst`eme '+
   'install`e :',
   'Machine name and user account of the installed system:',
   'Rechnername und Benutzerkonto des installierten Systems:',
   'Nome della macchina e utente del sistema installato:',
   'Nombre de la m`4quina y usuario del sistema instalado:');
  mMacHost:Raw:=Pick(
   'Nom de la machine',
   'Machine name',
   'Rechnername',
   'Nome macchina',
   'Nombre de m`4quina');
  mMacUser:Raw:=Pick(
   'Utilisateur',
   'User name',
   'Benutzername',
   'Utente',
   'Usuario');
  mMacHome:Raw:=Pick(
   'R`epertoire HOME',
   'HOME directory',
   'HOME-Verzeichnis',
   'Directory HOME',
   'Directorio HOME');
  mGoOn:Raw:=Pick(
   'Poursuivre l''installation',
   'Continue with Setup',
   'Mit dem Setup fortfahren',
   'Continua l''installazione',
   'Continuar la instalaci`2n');
  mMo:Raw:=Pick(
   'Mo',
   'MB',
   'MB',
   'MB',
   'MB');
  mKo:Raw:=Pick(
   'Ko',
   'KB',
   'KB',
   'KB',
   'KB');
  mDskIntro:Raw:=Pick(
   'Disque dur de destination :',
   'Destination hard disk:',
   'Ziel-Festplatte:',
   'Disco fisso di destinazione:',
   'Disco duro de destino:');
  mDskDisk:Raw:=Pick(
   'Disque dur',
   'Hard disk',
   'Festplatte',
   'Disco fisso',
   'Disco duro');
  mDskMode:Raw:=Pick(
   'Mode',
   'Mode',
   'Modus',
   'Modo',
   'Modo');
  mDskSize:Raw:=Pick(
   'Partition',
   'Partition',
   'Partition',
   'Partizione',
   'Partici`2n');
  mStNoPart:Raw:=Pick(
   'Le disque dur n''est pas partitionn`e.',
   'The hard disk is not partitioned.',
   'Die Festplatte ist nicht partitioniert.',
   'Il disco fisso non `r partizionato.',
   'El disco duro no est`4 particionado.');
  mStOther:Raw:=Pick(
   'La premi`ere partition n''est pas une partition FAT : toutes '+
   'les partitions seront supprim`ees.',
   'The first partition is not a FAT partition: all partitions '+
   'will be deleted.',
   'Die erste Partition ist keine FAT-Partition: alle '+
   'Partitionen werden gel`Oscht.',
   'La prima partizione non `r FAT: tutte le partizioni saranno '+
   'eliminate.',
   'La primera partici`2n no es FAT: se eliminar`4n todas las '+
   'particiones.');
  mStNoFmt:Raw:=Pick(
   'La partition n''est pas format`ee (ou son format n''est pas '+
   'g`er`e).',
   'The partition is not formatted (or its format is '+
   'unsupported).',
   'Die Partition ist nicht formatiert (oder nicht '+
   'unterst`Utzt).',
   'La partizione non `r formattata (o il formato non `r '+
   'supportato).',
   'La partici`2n no est`4 formateada (o su formato no es '+
   'compatible).');
  mStOk:Raw:=Pick(
   'Une partition FAT valide existe : vous pouvez conserver vos '+
   'donn`ees.',
   'A valid FAT partition exists: you can keep your data.',
   'Eine g`Ultige FAT-Partition ist vorhanden: Daten k`Onnen '+
   'erhalten bleiben.',
   'Esiste una partizione FAT valida: puoi conservare i dati.',
   'Existe una partici`2n FAT v`4lida: puede conservar sus '+
   'datos.');
  mStBad:Raw:=Pick(
   'Le syst`eme de fichiers est endommag`e : il sera reformat`e.',
   'The file system is damaged: it will be reformatted.',
   'Das Dateisystem ist besch`Adigt: es wird neu formatiert.',
   'Il file system `r danneggiato: sar`a riformattato.',
   'El sistema de archivos est`4 da`nado: se reformatear`4.');
  mModeFmt:Raw:=Pick(
   'Tout reformater (efface le disque)',
   'Reformat all (erases the disk)',
   'Alles neu formatieren (l`Oscht alles)',
   'Riformatta tutto (cancella il disco)',
   'Reformatear todo (borra el disco)');
  mModeKeep:Raw:=Pick(
   'Conserver les donn`ees',
   'Keep the existing data',
   'Daten behalten',
   'Conserva i dati',
   'Conservar los datos');
  mSizeQ:Raw:=Pick(
   'Taille de la partition en Mo (4 `a %1) :',
   'Partition size in MB (4 to %1):',
   'Partitionsgr`O`Be in MB (4 bis %1):',
   'Dimensione della partizione in MB (da 4 a %1):',
   'Tama`no de la partici`2n en MB (de 4 a %1):');
  mTypIntro:Raw:=Pick(
   'Choisissez le type d''installation :',
   'Choose the installation type:',
   'W`Ahlen Sie die Installationsart:',
   'Scegli il tipo di installazione:',
   'Elija el tipo de instalaci`2n:');
  mTyp1:Raw:=Pick(
   'Minimale',
   'Minimal',
   'Minimal',
   'Minima',
   'M`1nima');
  mTyp2:Raw:=Pick(
   'Standard',
   'Standard',
   'Standard',
   'Standard',
   'Est`4ndar');
  mTyp3:Raw:=Pick(
   'Compl`ete',
   'Complete',
   'Vollst`Andig',
   'Completa',
   'Completa');
  mTyp4:Raw:=Pick(
   'Personnalis`ee',
   'Custom',
   'Benutzerdefiniert',
   'Personalizzata',
   'Personalizada');
  mNeed:Raw:=Pick(
   'Espace n`ecessaire : %1 Ko',
   'Space required: %1 KB',
   'Ben`Otigter Platz: %1 KB',
   'Spazio necessario: %1 KB',
   'Espacio necesario: %1 KB');
  mFree:Raw:=Pick(
   'Espace libre : %1 Ko',
   'Free space: %1 KB',
   'Freier Platz: %1 KB',
   'Spazio libero: %1 KB',
   'Espacio libre: %1 KB');
  mNoRoom:Raw:=Pick(
   'Espace insuffisant : choisissez un type plus petit ou un '+
   'disque plus grand.',
   'Not enough space: choose a smaller type or a larger disk.',
   'Zu wenig Platz: kleinere Art oder gr`O`Beren Datentr`Ager '+
   'w`Ahlen.',
   'Spazio insufficiente: scegli un tipo pi`u piccolo o un '+
   'disco pi`u grande.',
   'Espacio insuficiente: elija un tipo menor o un disco mayor.');
  mComp0:Raw:=Pick(
   'Syst`eme (obligatoire)',
   'System (required)',
   'System (erforderlich)',
   'Sistema (obbligatorio)',
   'Sistema (obligatorio)');
  mComp1:Raw:=Pick(
   'Commandes de base',
   'Basic commands',
   'Grundbefehle',
   'Comandi di base',
   'Comandos b`4sicos');
  mComp2:Raw:=Pick(
   'Traitement de texte',
   'Text processing',
   'Textverarbeitung',
   'Elaborazione testi',
   'Proceso de texto');
  mComp3:Raw:=Pick(
   '`Editeurs',
   'Editors',
   'Editoren',
   'Editor',
   'Editores');
  mComp4:Raw:=Pick(
   'Archives et compression',
   'Archives and compression',
   'Archive und Kompression',
   'Archivi e compressione',
   'Archivos y compresi`2n');
  mComp5:Raw:=Pick(
   'Programmation et scripts',
   'Programming and scripts',
   'Programmierung, Skripte',
   'Programmazione e script',
   'Programaci`2n y scripts');
  mComp6:Raw:=Pick(
   'Syst`eme, utilisateurs, r`eseau',
   'System, users, network',
   'System, Benutzer, Netz',
   'Sistema, utenti, rete',
   'Sistema, usuarios, red');
  mComp7:Raw:=Pick(
   'Divers',
   'Miscellaneous',
   'Verschiedenes',
   'Varie',
   'Varios');
  mKrnIntro:Raw:=Pick(
   'R`eglages du noyau (\ETC\SYSCTL.D\CUSTOM.CFG) :',
   'Kernel settings (\ETC\SYSCTL.D\CUSTOM.CFG):',
   'Kernel-Einstellungen (\ETC\SYSCTL.D\CUSTOM.CFG):',
   'Impostazioni del kernel (\ETC\SYSCTL.D\CUSTOM.CFG):',
   'Ajustes del n`3cleo (\ETC\SYSCTL.D\CUSTOM.CFG):');
  mKrnFiles:Raw:=Pick(
   'Fichiers ouverts (fs.files, 8 `a 20)',
   'Open files (fs.files, 8 to 20)',
   'Offene Dateien (fs.files, 8 bis 20)',
   'File aperti (fs.files, da 8 a 20)',
   'Archivos abiertos (fs.files, 8 a 20)');
  mKrnBuf:Raw:=Pick(
   'Tampons (kernel.buffers, 1 `a 99)',
   'Buffers (kernel.buffers, 1 to 99)',
   'Puffer (kernel.buffers, 1 bis 99)',
   'Buffer (kernel.buffers, da 1 a 99)',
   'B`3feres (kernel.buffers, 1 a 99)');
  mKrnDrv:Raw:=Pick(
   'Dernier lecteur (kernel.lastdrive, C `a F)',
   'Last drive (kernel.lastdrive, C to F)',
   'Letztes Laufwerk (kernel.lastdrive, C-F)',
   'Ultima unit`a (kernel.lastdrive, C-F)',
   'Ultima unidad (kernel.lastdrive, C a F)');
  mSumT:Raw:=Pick(
   'R`ecapitulatif',
   'Summary',
   'Zusammenfassung',
   'Riepilogo',
   'Resumen');
  mSumType:Raw:=Pick(
   'Installation',
   'Installation',
   'Installation',
   'Installazione',
   'Instalaci`2n');
  mClus:Raw:=Pick(
   'clusters de %1 Ko',
   '%1 KB clusters',
   'Cluster zu %1 KB',
   'cluster da %1 KB',
   'clusters de %1 KB');
  mSumFmt:Raw:=Pick(
   'ATTENTION : TOUTES les partitions du disque %1 seront '+
   'supprim`ees et TOUTES les donn`ees perdues.',
   'WARNING: ALL partitions of disk %1 will be deleted and ALL '+
   'data lost.',
   'ACHTUNG: ALLE Partitionen der Festplatte %1 werden '+
   'gel`Oscht, ALLE Daten gehen verloren.',
   'ATTENZIONE: TUTTE le partizioni del disco %1 saranno '+
   'eliminate e TUTTI i dati persi.',
   'ATENCI`2N: se eliminar`4n TODAS las particiones del disco '+
   '%1 y se perder`4n TODOS los datos.');
  mSumKeep:Raw:=Pick(
   'Les donn`ees de la partition du disque %1 seront '+
   'conserv`ees ; les fichiers du syst`eme seront ajout`es ou '+
   'remplac`es.',
   'The data of the partition on disk %1 will be kept; system '+
   'files will be added or replaced.',
   'Die Daten der Partition auf Festplatte %1 bleiben erhalten; '+
   'Systemdateien werden hinzugef`Ugt oder ersetzt.',
   'I dati della partizione sul disco %1 saranno conservati; i '+
   'file di sistema saranno aggiunti o sostituiti.',
   'Se conservar`4n los datos de la partici`2n del disco %1; '+
   'los archivos del sistema se a`nadir`4n o reemplazar`4n.');
  mSumGo:Raw:=Pick(
   'Appuyez sur ENTREE pour lancer l''installation.',
   'Press ENTER to start the installation.',
   'EINGABE startet die Installation.',
   'Premi INVIO per avviare l''installazione.',
   'Pulse INTRO para iniciar la instalaci`2n.');
  mPhPart:Raw:=Pick(
   'Partitionnement du disque dur...',
   'Partitioning the hard disk...',
   'Festplatte wird partitioniert...',
   'Partizionamento del disco fisso...',
   'Particionando el disco duro...');
  mPhFmt:Raw:=Pick(
   'Formatage de la partition...',
   'Formatting the partition...',
   'Partition wird formatiert...',
   'Formattazione della partizione...',
   'Formateando la partici`2n...');
  mPhCopy:Raw:=Pick(
   'Copie des fichiers...',
   'Copying files...',
   'Dateien werden kopiert...',
   'Copia dei file...',
   'Copiando archivos...');
  mPhCfg:Raw:=Pick(
   '`Ecriture de la configuration...',
   'Writing the configuration...',
   'Konfiguration wird geschrieben...',
   'Scrittura della configurazione...',
   'Escribiendo la configuraci`2n...');
  mPhBoot:Raw:=Pick(
   'Installation du d`emarrage...',
   'Installing the boot code...',
   'Startcode wird installiert...',
   'Installazione dell''avvio...',
   'Instalando el arranque...');
  mPct:Raw:=Pick(
   '% effectu`e',
   '% complete',
   '% abgeschlossen',
   '% completato',
   '% completado');
  mCopying:Raw:=Pick(
   'Copie de',
   'Copying',
   'Kopiere',
   'Copia di',
   'Copiando');
  mAskDisk:Raw:=Pick(
   'Ins`erez le disque %1 dans le lecteur A:',
   'Insert disk %1 in drive A:',
   'Legen Sie Diskette %1 in Laufwerk A: ein',
   'Inserisci il disco %1 nel drive A:',
   'Inserte el disco %1 en la unidad A:');
  mReadErr:Raw:=Pick(
   'Erreur de lecture du fichier.',
   'File read error.',
   'Lesefehler der Datei.',
   'Errore di lettura del file.',
   'Error de lectura del archivo.');
  mAskFile:Raw:=Pick(
   'Fichier : %2',
   'File: %2',
   'Datei: %2',
   'File: %2',
   'Archivo: %2');
  mDoneT:Raw:=Pick(
   ' Installation termin`ee ',
   ' Setup complete ',
   ' Setup abgeschlossen ',
   ' Installazione completata ',
   ' Instalaci`2n completada ');
  mDone1:Raw:=Pick(
   'LINUX-0 est maintenant install`e sur le disque dur.',
   'LINUX-0 is now installed on the hard disk.',
   'LINUX-0 ist jetzt auf der Festplatte installiert.',
   'LINUX-0 `r ora installato sul disco fisso.',
   'LINUX-0 est`4 instalado en el disco duro.');
  mDone2:Raw:=Pick(
   'Retirez la disquette du lecteur A: puis appuyez sur ENTREE '+
   'pour red`emarrer, ou sur ECHAP/F4 pour revenir au shell.',
   'Remove the disk from drive A:, then press ENTER to restart, '+
   'or ESC/F4 to return to the shell.',
   'Entfernen Sie die Diskette aus Laufwerk A: und dr`Ucken Sie '+
   'EINGABE zum Neustart oder ESC f`Ur die Shell.',
   'Rimuovi il disco dal drive A: e premi INVIO per riavviare, '+
   'o ESC/F4 per tornare alla shell.',
   'Retire el disco de la unidad A: y pulse INTRO para '+
   'reiniciar o ESC/F4 para volver al shell.');
  mSkipped:Raw:=Pick(
   '%1 fichier(s) non copi`e(s).',
   '%1 file(s) not copied.',
   '%1 Datei(en) nicht kopiert.',
   '%1 file non copiati.',
   '%1 archivo(s) sin copiar.');
 Else
  Raw:='';
 End;
End;

Function Msg(Id:Integer):String;
Begin
 Msg:=Fix(Raw(Id));
End;

Const
 BootCode:Array[0..511]of Byte=(
  $EB,$3C,$90,$4D,$53,$44,$4F,$53,$35,$2E,$30,$00,$02,$40,$01,$00,
  $02,$00,$02,$00,$00,$F8,$00,$01,$3F,$00,$80,$00,$3F,$00,$00,$00,
  $41,$DC,$3F,$00,$80,$00,$29,$8A,$85,$17,$3B,$4E,$4F,$20,$4E,$41,
  $4D,$45,$20,$20,$20,$20,$46,$41,$54,$31,$36,$20,$20,$20,$FA,$33,
  $C0,$8E,$D0,$BC,$00,$7C,$16,$07,$BB,$78,$00,$36,$C5,$37,$1E,$56,
  $16,$53,$BF,$3E,$7C,$B9,$0B,$00,$FC,$F3,$A4,$06,$1F,$C6,$45,$FE,
  $0F,$8B,$0E,$18,$7C,$88,$4D,$F9,$89,$47,$02,$C7,$07,$3E,$7C,$FB,
  $CD,$13,$72,$79,$33,$C0,$39,$06,$13,$7C,$74,$08,$8B,$0E,$13,$7C,
  $89,$0E,$20,$7C,$A0,$10,$7C,$F7,$26,$16,$7C,$03,$06,$1C,$7C,$13,
  $16,$1E,$7C,$03,$06,$0E,$7C,$83,$D2,$00,$A3,$50,$7C,$89,$16,$52,
  $7C,$A3,$49,$7C,$89,$16,$4B,$7C,$B8,$20,$00,$F7,$26,$11,$7C,$8B,
  $1E,$0B,$7C,$03,$C3,$48,$F7,$F3,$01,$06,$49,$7C,$83,$16,$4B,$7C,
  $00,$BB,$00,$05,$8B,$16,$52,$7C,$A1,$50,$7C,$E8,$92,$00,$72,$1D,
  $B0,$01,$E8,$AC,$00,$72,$16,$8B,$FB,$B9,$0B,$00,$BE,$E0,$7D,$F3,
  $A6,$75,$0A,$8D,$7F,$20,$B9,$0B,$00,$F3,$A6,$74,$18,$BE,$9E,$7D,
  $E8,$5F,$00,$33,$C0,$CD,$16,$5E,$1F,$8F,$04,$8F,$44,$02,$CD,$19,
  $58,$58,$58,$EB,$E8,$8B,$47,$1A,$48,$48,$8A,$1E,$0D,$7C,$32,$FF,
  $F7,$E3,$03,$06,$49,$7C,$13,$16,$4B,$7C,$BB,$00,$07,$B9,$03,$00,
  $50,$52,$51,$E8,$3A,$00,$72,$D8,$B0,$01,$E8,$54,$00,$59,$5A,$58,
  $72,$BB,$05,$01,$00,$83,$D2,$00,$03,$1E,$0B,$7C,$E2,$E2,$8A,$2E,
  $15,$7C,$8A,$16,$24,$7C,$8B,$1E,$49,$7C,$A1,$4B,$7C,$EA,$00,$00,
  $70,$00,$AC,$0A,$C0,$74,$29,$B4,$0E,$BB,$07,$00,$CD,$10,$EB,$F2,
  $3B,$16,$18,$7C,$73,$19,$F7,$36,$18,$7C,$FE,$C2,$88,$16,$4F,$7C,
  $33,$D2,$F7,$36,$1A,$7C,$88,$16,$25,$7C,$A3,$4D,$7C,$F8,$C3,$F9,
  $C3,$B4,$02,$8B,$16,$4D,$7C,$B1,$06,$D2,$E6,$0A,$36,$4F,$7C,$8B,
  $CA,$86,$E9,$8A,$16,$24,$7C,$8A,$36,$25,$7C,$CD,$13,$C3,$0D,$0A,
  $44,$69,$73,$71,$75,$65,$20,$6E,$6F,$6E,$2D,$73,$79,$73,$74,$8A,
  $6D,$65,$2F,$65,$72,$72,$65,$75,$72,$20,$64,$69,$73,$71,$75,$65,
  $0D,$0A,$52,$65,$6D,$70,$6C,$61,$63,$65,$7A,$20,$65,$74,$20,$70,
  $72,$65,$73,$73,$65,$7A,$20,$74,$6F,$75,$63,$68,$65,$0D,$0A,$00,
  $49,$4F,$20,$20,$20,$20,$20,$20,$53,$59,$53,$4D,$53,$44,$4F,$53,
  $20,$20,$20,$53,$59,$53,$00,$00,$00,$00,$00,$00,$00,$00,$55,$AA
 );
 { Chargeur MBR : se recopie en 0000:0600, cherche la partition active,
   charge son secteur de boot en 0000:7C00 et y saute (DL = 80h) }
 MbrCode:Array[0..$4C]of Byte=(
  $FA,$33,$C0,$8E,$D0,$BC,$00,$7C,$8E,$D8,$8E,$C0,$FB,$FC,$BE,$00,
  $7C,$BF,$00,$06,$B9,$00,$01,$F3,$A5,$EA,$1E,$06,$00,$00,$BE,$BE,
  $07,$B1,$04,$80,$3C,$80,$74,$09,$83,$C6,$10,$E2,$F6,$CD,$18,$EB,
  $FE,$8B,$14,$8B,$4C,$02,$BB,$00,$7C,$B8,$01,$02,$CD,$13,$72,$EE,
  $81,$3E,$FE,$7D,$55,$AA,$75,$E5,$EA,$00,$7C,$00,$00);

{ ---------------------------------------------------------------------- }
{ Affichage direct en memoire video                                       }
{ ---------------------------------------------------------------------- }

Procedure SetTheme;
Begin
 If Mono Then Begin
  aNorm:=$07;aTitle:=$0F;aHi:=$70;aDlg:=$70;aBar:=$70;aGauge:=$70;
  aBorder:=$70;
 End
 Else Begin
  aNorm:=$1E;aTitle:=$1F;aHi:=$70;aDlg:=$30;aBar:=$70;aGauge:=$E0;
  aBorder:=$30;
 End;
End;

Procedure PutCh(X,Y:Integer;Ch:Char;A:Byte);
Var
 O:Word;
Begin
 If(X<1)or(X>80)or(Y<1)or(Y>25)Then Exit;
 O:=(Y-1)*160+(X-1)*2;
 Mem[VidSeg:O]:=Ord(Ch);
 Mem[VidSeg:O+1]:=A;
End;

Procedure PutStr(X,Y:Integer;Const S:String;A:Byte);
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do PutCh(X+I-1,Y,S[I],A);
End;

Procedure Fill(X1,Y1,X2,Y2:Integer;Ch:Char;A:Byte);
Var
 X,Y:Integer;
Begin
 For Y:=Y1 to Y2 do
  For X:=X1 to X2 do PutCh(X,Y,Ch,A);
End;

{ Cadre double trait ; l'interieur est efface }
Procedure Box(X1,Y1,X2,Y2:Integer;Dbl:Boolean;A:Byte);
Var
 X,Y:Integer;
 H,V,TL,TR,BL,BR:Char;
Begin
 If Dbl Then Begin
  H:=#205;V:=#186;TL:=#201;TR:=#187;BL:=#200;BR:=#188;
 End
 Else Begin
  H:=#196;V:=#179;TL:=#218;TR:=#191;BL:=#192;BR:=#217;
 End;
 Fill(X1,Y1,X2,Y2,' ',A);
 For X:=X1+1 to X2-1 do Begin PutCh(X,Y1,H,A);PutCh(X,Y2,H,A);End;
 For Y:=Y1+1 to Y2-1 do Begin PutCh(X1,Y,V,A);PutCh(X2,Y,V,A);End;
 PutCh(X1,Y1,TL,A);PutCh(X2,Y1,TR,A);PutCh(X1,Y2,BL,A);PutCh(X2,Y2,BR,A);
End;

{ Texte avec retour a la ligne ; retourne la prochaine ligne libre }
Function PutWrap(X,Y,W:Integer;Const S:String;A:Byte):Integer;
Var
 P,L,Cut:Integer;
 Part:String;
Begin
 P:=1;
 While P<=Length(S)do Begin
  L:=Length(S)-P+1;
  If L>W Then Begin
   Cut:=W;
   While(Cut>1)and(S[P+Cut]<>' ')do Dec(Cut);
   If Cut<=1 Then Cut:=W;
   L:=Cut;
  End;
  Part:=Copy(S,P,L);
  While(Length(Part)>0)and(Part[Length(Part)]=' ')do Dec(Part[0]);
  PutStr(X,Y,Part,A);
  Inc(Y);
  P:=P+L;
  While(P<=Length(S))and(S[P]=' ')do Inc(P);
 End;
 PutWrap:=Y;
End;

Function PutBullet(X,Y,W:Integer;Const S:String;A:Byte):Integer;
Begin
 PutCh(X,Y,#7,A);
 PutBullet:=PutWrap(X+2,Y,W-2,S,A);
End;

Procedure Clear;
Begin
 Fill(1,1,80,25,' ',aNorm);
End;

Procedure Title;
Var
 S:String;
Begin
 S:=Msg(mTitle);
 PutStr(2,2,S,aTitle);
 Fill(2,3,Length(S)+3,3,#205,aTitle);
End;

Procedure StatusBar(Const S:String);
Begin
 Fill(1,25,80,25,' ',aBar);
 PutStr(1,25,S,aBar);
End;

Procedure CursorOff;
Var
 R:Registers;
Begin
 R.AH:=1;R.CX:=$2000;Intr($10,R);
End;

Procedure CursorOn;
Var
 R:Registers;
Begin
 R.AH:=1;R.CX:=$0607;Intr($10,R);
End;

Procedure GotoXYb(X,Y:Integer);
Var
 R:Registers;
Begin
 R.AH:=2;R.BH:=0;R.DH:=Y-1;R.DL:=X-1;Intr($10,R);
End;

{ Touche normalisee : code ASCII seul pour une touche normale, AX complet
  (AL=0) pour une touche etendue : F1 = $3B00, fleche haut = $4800... }
{ F4 equivaut a ECHAP : l'onglet emulateur de DEVENV consomme ECHAP pour
  fermer l'emulation, il n'arrive jamais jusqu'au programme }
Function GetKey:Word;
Var
 R:Registers;
Begin
 R.AH:=0;
 Intr($16,R);
 If(R.AL<>0)and((R.AL<>$E0)or(R.AH=0))Then GetKey:=R.AL
 Else GetKey:=Word(R.AH)shl 8;
 If GetKey=kF4 Then GetKey:=kEsc;
End;

Procedure InitVideo;
Var
 R:Registers;
Begin
 R.AH:=$0F;Intr($10,R);
 If R.AL=7 Then Begin VidSeg:=$B000;Mono:=True;End
 Else Begin
  If R.AL<>3 Then Begin R.AH:=0;R.AL:=3;Intr($10,R);End;
  VidSeg:=$B800;
  { fond clair sans clignotement (jauge jaune) }
  R.AX:=$1003;R.BL:=0;Intr($10,R);
 End;
End;

Procedure RestoreScreen;
Var
 R:Registers;
Begin
 R.AH:=0;R.AL:=3;Intr($10,R);
 CursorOn;
End;

{ ---------------------------------------------------------------------- }
{ Boites de dialogue                                                      }
{ ---------------------------------------------------------------------- }

Procedure DlgBox(X1,Y1,X2,Y2:Integer);
Begin
 Fill(X1+1,Y2+1,X2+1,Y2+1,' ',$08);
 Fill(X2+1,Y1+1,X2+2,Y2+1,' ',$08);
 Box(X1,Y1,X2,Y2,True,aBorder);
End;

Procedure FlushFat;Forward;

Procedure QuitInstall;
Begin
 FlushFat;
 RestoreScreen;
 WriteLn(Msg(mQuit));
 Halt(1);
End;

Function ConfirmExit:Boolean;
Var
 K:Word;
 Y:Integer;
Begin
 Clear;
 Title;
 DlgBox(8,6,72,16);
 PutStr(10,6,Msg(mExitT),aDlg);
 Y:=PutWrap(11,8,58,Msg(mExit1),aDlg);
 Y:=PutBullet(12,Y+1,57,Msg(mExit2),aDlg);
 Y:=PutBullet(12,Y+1,57,Msg(mExit3),aDlg);
 StatusBar(Msg(mKeyEnter));
 Repeat
  K:=GetKey;
 Until(K=kEnter)or(K=kF3);
 ConfirmExit:=K=kF3;
End;

{ Boite d'erreur : l'installation s'arrete }
Procedure Fatal(Id:Integer);
Var
 Y:Integer;
 K:Word;
Begin
 Clear;
 Title;
 DlgBox(8,6,72,16);
 PutStr(10,6,Msg(mErrT),aDlg);
 Y:=PutWrap(11,8,58,Msg(Id),aDlg);
 StatusBar(Msg(mKeyQuit));
 Repeat
  K:=GetKey;
 Until K=kEnter;
 FlushFat;
 RestoreScreen;
 Halt(2);
End;

Procedure ShowHelp(N:Integer);
Var
 K:Word;
Begin
 Clear;
 Title;
 PutStr(4,5,Msg(mHelpT),aTitle);
 PutWrap(4,7,72,Msg(mHelp1+N),aNorm);
 StatusBar(Msg(mKeyBack));
 Repeat
  K:=GetKey;
 Until(K=kEnter)or(K=kEsc);
End;

{ F1 = aide, F3 = quitter }
Procedure Nav(K:Word;Topic:Integer);
Begin
 If K=kF1 Then ShowHelp(Topic)
 Else If K=kF3 Then Begin
  If ConfirmExit Then QuitInstall;
 End;
End;

{ Liste de choix dans une boite ; retourne l'indice (0 = annule) }
Function PickList(Const Caption:String;Count,Cur:Integer):Integer;
Var
 I,Y1,Y2:Integer;
 K:Word;
Begin
 Y1:=8;Y2:=Y1+Count+3;
 Repeat
  DlgBox(20,Y1,60,Y2);
  PutStr(22,Y1,' '+Caption+' ',aDlg);
  For I:=1 to Count do
   If I=Cur Then PutStr(23,Y1+1+I,PadTo(' '+ListItems[I],36),aHi)
   Else PutStr(23,Y1+1+I,PadTo(' '+ListItems[I],36),aDlg);
  K:=GetKey;
  If(K=kUp)and(Cur>1)Then Dec(Cur)
  Else If(K=kDown)and(Cur<Count)Then Inc(Cur)
  Else If K=kEsc Then Begin PickList:=0;Exit;End;
 Until K=kEnter;
 PickList:=Cur;
End;

{ Saisie d'une ligne dans une zone ; retourne la touche de fin }
Function EditLine(X,Y,W:Integer;Var S:String):Word;
Var
 K:Word;
 First:Boolean;
Begin
 First:=True;
 CursorOn;
 Repeat
  Fill(X,Y,X+W-1,Y,' ',aHi);
  PutStr(X,Y,S,aHi);
  GotoXYb(X+Length(S),Y);
  K:=GetKey;
  If(K>=32)and(K<256)Then Begin
   If First Then S:='';
   If Length(S)<W-1 Then S:=S+Chr(K);
  End
  Else If(K=kBack)and(Length(S)>0)Then Dec(S[0]);
  If K<256 Then First:=False;
 Until(K=kEnter)or(K=kEsc)or(K=kF1)or(K=kF3);
 CursorOff;
 EditLine:=K;
End;

{ Boite de saisie (invite = message Q) ; True si ENTREE }
Function InputBox(Q:Integer;Var S:String;W:Integer):Boolean;
Var
 K:Word;
Begin
 DlgBox(14,8,66,13);
 PutStr(17,10,Msg(Q),aDlg);
 K:=EditLine(17,11,W,S);
 If K=kF3 Then Nav(K,0);
 InputBox:=K=kEnter;
End;


{ ---------------------------------------------------------------------- }
{ INSTALL.INF                                                             }
{ ---------------------------------------------------------------------- }

Function AddDir(P:String):Integer;
Var
 I:Integer;
Begin
 P:=UpStr(P);
 While(Length(P)>1)and(P[Length(P)]='\')do Dec(P[0]);
 AddDir:=0;
 If(P='')or(P='\')Then Exit;
 For I:=1 to DirCount do
  If DirName[I]=P Then Begin AddDir:=I;Exit;End;
 If DirCount>=MaxDirs Then Exit;
 Inc(DirCount);
 DirName[DirCount]:=P;
 AddDir:=DirCount;
End;

Function SplitField(Var S:String):String;
Var
 P:Integer;
Begin
 P:=Pos(',',S);
 If P=0 Then Begin SplitField:=S;S:='';End
 Else Begin SplitField:=Copy(S,1,P-1);S:=Copy(S,P+1,255);End;
End;

Procedure ParseLine(L:String);
Var
 Fld:String;
 V:LongInt;
 Code,N:Integer;
Begin
 While(Length(L)>0)and(L[Length(L)]=' ')do Dec(L[0]);
 If L='' Then Exit;
 If UpStr(Copy(L,1,4))='DIR,' Then N:=AddDir(Copy(L,5,60))
 Else If(L[1]in['0'..'9'])and(EntryCount<MaxEntries)Then Begin
  Inc(EntryCount);
  N:=EntryCount;
  Val(SplitField(L),V,Code);
  Entries[N].Disk:=Byte(V);
  Entries[N].Dir:=AddDir(SplitField(L));
  Entries[N].Name:=UpStr(SplitField(L));
  Val(SplitField(L),V,Code);
  Entries[N].Size:=V;
  Val(SplitField(L),V,Code);
  Entries[N].Comp:=Byte(V)and 7;
 End;
End;

{ Demande le disque N (ENTREE = reessayer, F2 = ignorer, ECHAP = annuler) ;
  retourne True pour ignorer }
Function AskDisk(Id,N:Integer;CanSkip:Boolean;Const Fn:String):Boolean;
Var
 K:Word;
Begin
 AskDisk:=False;
 A1:=NumStr(N);
 A2:=Fn;
 Repeat
  DlgBox(12,7,68,14);
  PutStr(16,9,Msg(Id),aDlg);
  PutStr(16,11,Msg(mAskFile),aDlg);
  If CanSkip Then StatusBar(Msg(mKeySkip))Else StatusBar(Msg(mKeyRetry));
  K:=GetKey;
  If K=kEsc Then Begin
   If ConfirmExit Then QuitInstall;
  End
  Else If(K=kF2)and CanSkip Then Begin AskDisk:=True;Exit;End;
 Until K=kEnter;
End;

Procedure ReadInf;
Var
 F:File;
 Buf:Array[0..511]of Byte;
 L:String;
 Got,I:Word;
 C:Char;
 Found:Boolean;
Begin
 EntryCount:=0;DirCount:=0;
 Repeat
  Found:=False;
  For C:='A' to 'B' do
   If Not Found Then Begin
    Assign(F,C+':\INSTALL.INF');
    FileMode:=0;
    {$I-}Reset(F,1);{$I+}
    If IOResult=0 Then Begin Found:=True;SrcDrv:=C;End;
   End;
  FileMode:=2;
  If Not Found Then Begin
   Clear;Title;
   AskDisk(mAskDisk,1,False,'INSTALL.INF');
  End;
 Until Found;
 L:='';
 Repeat
  {$I-}BlockRead(F,Buf,512,Got);{$I+}
  If IOResult<>0 Then Got:=0;
  I:=0;
  While I<Got do Begin
   If(Buf[I]=10)or(Buf[I]=13)Then Begin ParseLine(L);L:='';End
   Else If(Buf[I]>=32)and(Length(L)<200)Then L:=L+Chr(Buf[I]);
   Inc(I);
  End;
 Until Got=0;
 ParseLine(L);
 Close(F);
 If EntryCount=0 Then Fatal(mErrEmpty);
End;

{ ---------------------------------------------------------------------- }
{ Acces disque (BIOS INT 13h)                                             }
{ ---------------------------------------------------------------------- }

Function Bios13(Fn:Byte;Lba:LongInt):Boolean;
Var
 R:Registers;
 Tries:Integer;
 Sec,Hd,Cyl:Word;
 Tk:LongInt;
Begin
 Bios13:=False;
 If(Spt=0)or(Heads=0)Then Exit;
 Sec:=Word(Lba mod Spt)+1;
 Tk:=Lba div Spt;
 Hd:=Word(Tk mod Heads);
 If Tk div Heads>1023 Then Exit;
 Cyl:=Word(Tk div Heads);
 For Tries:=1 to 3 do Begin
  R.AH:=Fn;R.AL:=1;
  R.CH:=Byte(Cyl and $FF);
  R.CL:=Byte(Sec or((Cyl shr 2)and $C0));
  R.DH:=Byte(Hd);R.DL:=Unit8;
  R.ES:=Seg(Stg^);R.BX:=Ofs(Stg^);
  Intr($13,R);
  If(R.Flags and FCarry)=0 Then Begin Bios13:=True;Exit;End;
  R.AH:=0;R.DL:=Unit8;Intr($13,R);
 End;
End;

Function RdAbs(Lba:LongInt;Var B):Boolean;
Begin
 RdAbs:=False;
 If Bios13($02,Lba)Then Begin Move(Stg^,B,512);RdAbs:=True;End;
End;

Function WrAbs(Lba:LongInt;Var B):Boolean;
Begin
 Move(B,Stg^,512);
 WrAbs:=Bios13($03,Lba);
End;

Function RdPart(L:LongInt;Var B):Boolean;
Begin
 RdPart:=RdAbs(PartLBA+L,B);
End;

Function WrPart(L:LongInt;Var B):Boolean;
Begin
 WrPart:=WrAbs(PartLBA+L,B);
End;

Function DiskGeometry(U:Byte):Boolean;
Var
 R:Registers;
Begin
 DiskGeometry:=False;
 R.AH:=8;R.DL:=U;Intr($13,R);
 If(R.Flags and FCarry)<>0 Then Exit;
 Spt:=R.CL and $3F;
 Heads:=Word(R.DH)+1;
 Cyls:=(Word(R.CL and $C0)shl 2)+R.CH+1;
 HdTotal:=LongInt(Cyls)*Heads*Spt;
 Unit8:=U;
 DiskGeometry:=(Spt<>0)and(Heads<>0);
End;

Function DiskExists(U:Byte):Boolean;
Var
 B:TSec;
Begin
 DiskExists:=DiskGeometry(U)and RdAbs(0,B);
End;

{ Le noyau relit la table de partition du disque dur (fonction interne 70h) }
Procedure KernelRefresh;
Var
 R:Registers;
Begin
 R.AH:=$70;
 Intr($21,R);
End;

{ ---------------------------------------------------------------------- }
{ Volume FAT12 / FAT16 (la FAT est chargee en memoire)                    }
{ ---------------------------------------------------------------------- }

{ BPB de la partition courante ; False si ce n'est pas un volume FAT12 ou
  FAT16 gere (FAT de 64 Ko au plus) }
Function LoadBpb:Boolean;
Var
 B:TSec;
 Tot:LongInt;
Begin
 LoadBpb:=False;
 If Not RdPart(0,B)Then Exit;
 If(B[510]<>$55)or(B[511]<>$AA)Then Exit;
 If(B[11]<>0)or(B[12]<>2)Then Exit;
 BpbSpc:=B[13];BpbRes:=B[14]+B[15]*256;BpbNf:=B[16];
 BpbRoot:=B[17]+B[18]*256;BpbSpf:=B[22]+B[23]*256;
 Tot:=B[19]+B[20]*256;
 If Tot=0 Then Tot:=LE32(B,32);
 If(BpbSpc=0)or((BpbSpc and(BpbSpc-1))<>0)or(BpbNf=0)or(BpbNf>2)or
   (BpbRes=0)or(BpbSpf=0)or(BpbRoot=0)or(B[21]<$F0)Then Exit;
 RootSecs:=(LongInt(BpbRoot)*32+511)div 512;
 RootStart:=LongInt(BpbRes)+LongInt(BpbNf)*BpbSpf;
 DataStart:=RootStart+RootSecs;
 If Tot<=DataStart Then Exit;
 Clusters:=(Tot-DataStart)div BpbSpc;
 If Clusters>32700 Then Exit;
 Fat16:=Clusters>=4085;
 If Fat16 Then FatLen:=Word((Clusters+2)*2)
 Else FatLen:=Word(((Clusters+2)*3+1)div 2);
 If LongInt(BpbSpf)*512<FatLen Then Exit;
 Bpc:=LongInt(BpbSpc)*512;
 LoadBpb:=True;
End;

Function LoadFat:Boolean;
Var
 B:TSec;
 S,O,N:LongInt;
Begin
 LoadFat:=False;
 S:=0;
 While S*512<FatLen do Begin
  If Not RdPart(BpbRes+S,B)Then Exit;
  O:=S*512;
  N:=FatLen-O;
  If N>512 Then N:=512;
  Move(B,Fat^[O],N);
  Inc(S);
 End;
 FatDirty:=False;
 Hint:=2;
 LoadFat:=True;
End;

Function WriteFat:Boolean;
Var
 B:TSec;
 K,S,O,N:LongInt;
Begin
 WriteFat:=False;
 For K:=0 to BpbNf-1 do Begin
  S:=0;
  While S*512<FatLen do Begin
   O:=S*512;
   N:=FatLen-O;
   If N>512 Then N:=512
   Else If Not RdPart(BpbRes+K*BpbSpf+S,B)Then Exit;
   Move(Fat^[O],B,N);
   If Not WrPart(BpbRes+K*BpbSpf+S,B)Then Exit;
   Inc(S);
  End;
 End;
 FatDirty:=False;
 WriteFat:=True;
End;

Procedure FlushFat;
Begin
 If FatDirty Then If WriteFat Then FatDirty:=False;
End;

Function FatGet(C:Word):Word;
Var
 O,V:Word;
Begin
 If Fat16 Then Begin
  O:=C*2;
  V:=Fat^[O]+Fat^[O+1]*256;
 End
 Else Begin
  O:=C+(C shr 1);
  V:=Fat^[O]+Fat^[O+1]*256;
  If Odd(C)Then V:=V shr 4 Else V:=V and $FFF;
 End;
 FatGet:=V;
End;

Procedure FatSet(C,V:Word);
Var
 O:Word;
Begin
 FatDirty:=True;
 If Fat16 Then Begin
  O:=C*2;
  Fat^[O]:=Byte(V and $FF);Fat^[O+1]:=Byte(V shr 8);
 End
 Else Begin
  O:=C+(C shr 1);
  If Odd(C)Then Begin
   Fat^[O]:=(Fat^[O]and $0F)or Byte((V and $0F)shl 4);
   Fat^[O+1]:=Byte(V shr 4);
  End
  Else Begin
   Fat^[O]:=Byte(V and $FF);
   Fat^[O+1]:=(Fat^[O+1]and $F0)or Byte((V shr 8)and $0F);
  End;
 End;
End;

Function IsEnd(V:Word):Boolean;
Begin
 If Fat16 Then IsEnd:=V>=$FFF7 Else IsEnd:=V>=$FF7;
End;

Function ClusLba(C:Word):LongInt;
Begin
 ClusLba:=DataStart+LongInt(C-2)*BpbSpc;
End;

{ Premiere grappe libre (marquee fin de chaine) ; 0 si le disque est plein }
Function AllocC:Word;
Var
 C,E:Word;
Begin
 AllocC:=0;
 E:=Word(Clusters+1);
 For C:=Hint to E do
  If FatGet(C)=0 Then Begin
   If Fat16 Then FatSet(C,$FFFF)Else FatSet(C,$FFF);
   Hint:=C+1;AllocC:=C;Exit;
  End;
 For C:=2 to E do
  If FatGet(C)=0 Then Begin
   If Fat16 Then FatSet(C,$FFFF)Else FatSet(C,$FFF);
   Hint:=C+1;AllocC:=C;Exit;
  End;
End;

Procedure FreeChain(C:Word);
Var
 N:Word;
 G:LongInt;
Begin
 G:=0;
 While(C>=2)and(C<=Clusters+1)and(G<=Clusters)do Begin
  N:=FatGet(C);
  FatSet(C,0);
  Inc(G);
  If IsEnd(N)Then Exit;
  C:=N;
 End;
End;

Function ZeroCluster(C:Word):Boolean;
Var
 B:TSec;
 K:Word;
Begin
 ZeroCluster:=False;
 FillChar(B,512,0);
 For K:=0 to BpbSpc-1 do
  If Not WrPart(ClusLba(C)+K,B)Then Exit;
 ZeroCluster:=True;
End;

{ ---- repertoires ---- }

{ Secteur N d'un repertoire (0 = racine) ; False au-dela de la fin }
Function DirSec(Dir:Word;N:Integer;Var Lba:LongInt):Boolean;
Var
 C:Word;
 K:Integer;
Begin
 DirSec:=False;
 If Dir=0 Then Begin
  If N>=RootSecs Then Exit;
  Lba:=RootStart+N;
 End
 Else Begin
  C:=Dir;
  For K:=1 to N div BpbSpc do Begin
   C:=FatGet(C);
   If(C<2)or IsEnd(C)Then Exit;
  End;
  Lba:=ClusLba(C)+N mod BpbSpc;
 End;
 DirSec:=True;
End;

{ Cherche un nom (11 caracteres) ; le secteur est dans DBuf (DLba, DOff) }
Function DirFind(Dir:Word;Const N11:String):Boolean;
Var
 N,I,K:Integer;
 Same:Boolean;
Begin
 DirFind:=False;
 N:=0;
 While DirSec(Dir,N,DLba)do Begin
  If Not RdPart(DLba,DBuf)Then Exit;
  For I:=0 to 15 do Begin
   If DBuf[I*32]=0 Then Exit;
   If DBuf[I*32]<>$E5 Then Begin
    Same:=True;
    For K:=0 to 10 do
     If DBuf[I*32+K]<>Ord(N11[K+1])Then Same:=False;
    If Same Then Begin DOff:=I*32;DirFind:=True;Exit;End;
   End;
  End;
  Inc(N);
 End;
End;

{ Ajoute une entree dans la premiere place libre (agrandit le repertoire) }
Function DirAdd(Dir:Word;Const N11:String;Attr:Byte;Cl:Word;Size,Tm:LongInt):
 Boolean;
Var
 N,I,K:Integer;
 Last,C:Word;
Begin
 DirAdd:=False;
 N:=0;
 Repeat
  If Not DirSec(Dir,N,DLba)Then Begin
   If Dir=0 Then Exit;
   Last:=Dir;
   While(Not IsEnd(FatGet(Last)))and(FatGet(Last)>=2)do Last:=FatGet(Last);
   C:=AllocC;
   If C=0 Then Exit;
   If Not ZeroCluster(C)Then Exit;
   FatSet(Last,C);
   If Not DirSec(Dir,N,DLba)Then Exit;
  End;
  If Not RdPart(DLba,DBuf)Then Exit;
  For I:=0 to 15 do
   If(DBuf[I*32]=0)or(DBuf[I*32]=$E5)Then Begin
    FillChar(DBuf[I*32],32,0);
    For K:=0 to 10 do DBuf[I*32+K]:=Ord(N11[K+1]);
    DBuf[I*32+11]:=Attr;
    DBuf[I*32+22]:=Byte(Tm and $FF);DBuf[I*32+23]:=Byte((Tm shr 8)and $FF);
    DBuf[I*32+24]:=Byte((Tm shr 16)and $FF);
    DBuf[I*32+25]:=Byte((Tm shr 24)and $FF);
    DBuf[I*32+26]:=Byte(Cl and $FF);DBuf[I*32+27]:=Byte(Cl shr 8);
    DBuf[I*32+28]:=Byte(Size and $FF);DBuf[I*32+29]:=Byte((Size shr 8)and $FF);
    DBuf[I*32+30]:=Byte((Size shr 16)and $FF);
    DBuf[I*32+31]:=Byte((Size shr 24)and $FF);
    DirAdd:=WrPart(DLba,DBuf);
    Exit;
   End;
  Inc(N);
 Until False;
End;

{ Supprime un fichier (libere ses grappes) }
Procedure DirDelete(Dir:Word;Const N11:String);
Begin
 If DirFind(Dir,N11)Then Begin
  FreeChain(DBuf[DOff+26]+DBuf[DOff+27]*256);
  DBuf[DOff]:=$E5;
  If WrPart(DLba,DBuf)Then;
 End;
End;

{ NOM.EXT -> 11 caracteres }
Function To11(Const S0:String):String;
Var
 P:Integer;
 R,S:String;
Begin
 S:=UpStr(S0);
 P:=Pos('.',S);
 If P=0 Then R:=PadTo(S,8)+'   '
 Else R:=PadTo(Copy(S,1,P-1),8)+PadTo(Copy(S,P+1,3),3);
 To11:=Copy(R,1,11);
End;

Procedure PutName(Var B:TSec;O:Integer;Const S:String);
Var
 K:Integer;
Begin
 For K:=0 to 10 do
  If K<Length(S)Then B[O+K]:=Ord(S[K+1])Else B[O+K]:=32;
End;

Procedure PutTxt(Var B:TSec;O:Integer;Const S:String);
Var
 K:Integer;
Begin
 For K:=1 to Length(S)do B[O+K-1]:=Ord(S[K]);
End;

{ Cree le repertoire (et ses parents) ; retourne sa grappe (0 = racine,
  $FFFF = echec) }
Function MakePath(Const P:String):Word;
Var
 Cur,C:Word;
 I,J:Integer;
 N11:String;
 B:TSec;
Begin
 MakePath:=$FFFF;
 Cur:=0;
 I:=1;
 While I<=Length(P)do Begin
  If P[I]='\' Then Inc(I)
  Else Begin
   J:=I;
   While(J<=Length(P))and(P[J]<>'\')do Inc(J);
   N11:=To11(Copy(P,I,J-I));
   I:=J;
   If DirFind(Cur,N11)Then Begin
    If(DBuf[DOff+11]and $10)=0 Then Exit;
    Cur:=DBuf[DOff+26]+DBuf[DOff+27]*256;
   End
   Else Begin
    C:=AllocC;
    If(C=0)or(Not ZeroCluster(C))Then Exit;
    FillChar(B,512,0);
    PutName(B,0,'.');B[11]:=$10;B[26]:=Byte(C and $FF);
    B[27]:=Byte(C shr 8);PutLE32(B,22,NowTm);
    PutName(B,32,'..');B[43]:=$10;B[58]:=Byte(Cur and $FF);
    B[59]:=Byte(Cur shr 8);PutLE32(B,54,NowTm);
    If Not WrPart(ClusLba(C),B)Then Exit;
    If Not DirAdd(Cur,N11,$10,C,0,NowTm)Then Exit;
    Cur:=C;
   End;
  End;
 End;
 MakePath:=Cur;
End;

{ ---- ecriture d'un fichier : WBegin, WData (par grappes entieres sauf le
  dernier bloc), WEnd ---- }

Procedure WBegin;
Begin
 WFirst:=0;WLast:=0;WSize:=0;WFull:=False;
End;

Function WData(Var Buf;Len:Word):Boolean;
Var
 Off,N:Word;
 C,K:Word;
 B:TSec;
Begin
 WData:=False;
 Off:=0;
 While Off<Len do Begin
  C:=AllocC;
  If C=0 Then Begin WFull:=True;Exit;End;
  If WFirst=0 Then WFirst:=C Else FatSet(WLast,C);
  WLast:=C;
  K:=0;
  While(Off<Len)and(K<BpbSpc)do Begin
   N:=Len-Off;
   If N>512 Then N:=512;
   FillChar(B,512,0);
   Move(PBuf(@Buf)^[Off],B,N);
   If Not WrPart(ClusLba(C)+K,B)Then Exit;
   Off:=Off+N;
   Inc(K);
  End;
 End;
 WSize:=WSize+Len;
 WData:=True;
End;

Function WEnd(Dir:Word;Const N11:String;Attr:Byte;Tm:LongInt):Boolean;
Begin
 DirDelete(Dir,N11);
 WEnd:=DirAdd(Dir,N11,Attr,WFirst,WSize,Tm);
 If Not WEnd Then Begin FreeChain(WFirst);WFull:=True;End;
End;


{ ---------------------------------------------------------------------- }
{ Verification du systeme de fichiers existant et IO.SYS en tete           }
{ ---------------------------------------------------------------------- }

Function MapLookup(C:Word):Word;
Var
 I:Integer;
Begin
 MapLookup:=0;
 For I:=1 to MapCount do
  If MapOld[I]=C Then MapLookup:=MapNew[I];
End;

{ Longueur de la chaine de Start ; les grappes vues deux fois, hors du
  volume ou en boucle marquent le volume comme endommage }
Procedure WalkChain(Start:Word;Var Len:LongInt);
Var
 C:Word;
 Bit:Byte;
Begin
 Len:=0;
 C:=Start;
 While Not Bad do Begin
  If(C<2)or(C>Clusters+1)Then Begin Bad:=True;Exit;End;
  Bit:=1 shl(C and 7);
  If(Seen[C shr 3]and Bit)<>0 Then Begin Bad:=True;Exit;End;
  Seen[C shr 3]:=Seen[C shr 3]or Bit;
  Inc(Len);
  C:=FatGet(C);
  If IsEnd(C)Then Exit;
 End;
End;

{ Un secteur de repertoire. Mode 0 : verification des chaines ; mode 1 :
  remplace les premieres grappes deplacees (MapOld -> MapNew). Les
  sous-repertoires sont empiles. }
Procedure ScanSec(Lba:LongInt;Mode:Byte;Var Stop:Boolean);
Var
 B:TSec;
 I,E:Integer;
 Cl,Nw:Word;
 Dirty:Boolean;
 Len,Sz:LongInt;
 Dir:Boolean;
Begin
 If Not RdPart(Lba,B)Then Begin Bad:=True;Stop:=True;Exit;End;
 Dirty:=False;
 For I:=0 to 15 do
  If Not Stop Then Begin
   E:=I*32;
   If B[E]=0 Then Stop:=True
   Else If(B[E]<>$E5)and(B[E+11]<>$0F)and((B[E+11]and 8)=0)Then Begin
    Cl:=B[E+26]+B[E+27]*256;
    Dir:=(B[E+11]and $10)<>0;
    If Mode=1 Then Begin
     Nw:=MapLookup(Cl);
     If Nw<>0 Then Begin
      B[E+26]:=Byte(Nw and $FF);B[E+27]:=Byte(Nw shr 8);
      Dirty:=True;Cl:=Nw;
     End;
    End
    Else If B[E]<>$2E Then Begin
     Sz:=LE32(B,E+28);
     If Dir or(Sz>0)Then Begin
      WalkChain(Cl,Len);
      If(Not Dir)and(Not Bad)and(Len<>(Sz+Bpc-1)div Bpc)Then Bad:=True;
     End;
     If Bad Then Stop:=True;
    End;
    If Dir and(B[E]<>$2E)and(Cl>=2)and(DSp<MaxStack)and(Not Stop)Then Begin
     Inc(DSp);DStack[DSp]:=Cl;
    End;
   End;
  End;
 If Dirty Then
  If Not WrPart(Lba,B)Then Bad:=True;
End;

{ Parcourt la racine et tous les sous-repertoires }
Procedure WalkDirs(Mode:Byte);
Var
 D,C:Word;
 K,Guard:Integer;
 Stop:Boolean;
Begin
 DSp:=1;DStack[1]:=0;
 While(DSp>0)and(Not Bad)do Begin
  D:=DStack[DSp];Dec(DSp);
  Stop:=False;
  If D=0 Then Begin
   For K:=0 to RootSecs-1 do
    If Not Stop Then ScanSec(RootStart+K,Mode,Stop);
  End
  Else Begin
   C:=D;Guard:=0;
   While(Not Stop)and(C>=2)and(Not IsEnd(C))and(Guard<4096)do Begin
    For K:=0 to BpbSpc-1 do
     If Not Stop Then ScanSec(ClusLba(C)+K,Mode,Stop);
    C:=FatGet(C);
    Inc(Guard);
   End;
  End;
 End;
End;

Function FsDamaged:Boolean;
Begin
 FillChar(Seen,SizeOf(Seen),0);
 Bad:=False;
 WalkDirs(0);
 FsDamaged:=Bad;
End;

Function FindFree(From:Word):Word;
Var
 C:Word;
Begin
 FindFree:=0;
 For C:=From to Word(Clusters+1)do
  If FatGet(C)=0 Then Begin FindFree:=C;Exit;End;
End;

Function CopyCluster(Src,Dst:Word):Boolean;
Var
 B:TSec;
 K:Word;
Begin
 CopyCluster:=False;
 For K:=0 to BpbSpc-1 do Begin
  If Not RdPart(ClusLba(Src)+K,B)Then Exit;
  If Not WrPart(ClusLba(Dst)+K,B)Then Exit;
 End;
 CopyCluster:=True;
End;

{ Les entrees 0 et 1 de la racine sont deplacees vers des places libres }
Function FreeRootSlots:Boolean;
Var
 M0,M:TSec;
 I,J,Sc:Integer;
 Found:Boolean;
Begin
 FreeRootSlots:=False;
 For I:=0 to 1 do Begin
  If Not RdPart(RootStart,M0)Then Exit;
  If(M0[I*32]<>0)and(M0[I*32]<>$E5)Then Begin
   Found:=False;
   For Sc:=0 to RootSecs-1 do
    If Not Found Then Begin
     If Sc>0 Then
      If Not RdPart(RootStart+Sc,M)Then Exit;
     For J:=0 to 15 do
      If(Not Found)and((Sc>0)or(J>1))Then Begin
       If Sc=0 Then Begin
        If(M0[J*32]=0)or(M0[J*32]=$E5)Then Begin
         Move(M0[I*32],M0[J*32],32);Found:=True;
        End;
       End
       Else If(M[J*32]=0)or(M[J*32]=$E5)Then Begin
        Move(M0[I*32],M[J*32],32);Found:=True;
        If Not WrPart(RootStart+Sc,M)Then Exit;
       End;
      End;
    End;
   If Not Found Then Exit;
   M0[I*32]:=$E5;
   If Not WrPart(RootStart,M0)Then Exit;
  End;
 End;
 FreeRootSlots:=True;
End;

{ Libere les entrees 0 et 1 de la racine et les premieres grappes du volume
  pour IO.SYS et MSDOS.SYS : les fichiers qui s'y trouvent sont deplaces }
Procedure PrepareSystemArea;
Var
 I:Integer;
 Need,Sz1,Sz2:LongInt;
 C,F,Nx,V,N2,From:Word;
Begin
 DirDelete(0,'IO      SYS');
 DirDelete(0,'MSDOS   SYS');
 Sz1:=0;Sz2:=0;
 For I:=1 to EntryCount do
  If Entries[I].Dir=0 Then Begin
   If Entries[I].Name='IO.SYS' Then Sz1:=Entries[I].Size;
   If Entries[I].Name='MSDOS.SYS' Then Sz2:=Entries[I].Size;
  End;
 Need:=(Sz1+Bpc-1)div Bpc+(Sz2+Bpc-1)div Bpc;
 If Not FreeRootSlots Then Fatal(mErrFull);
 MapCount:=0;
 From:=Word(Need+2);
 For C:=2 to Word(Need+1)do Begin
  Nx:=FatGet(C);
  If Nx<>0 Then Begin
   If(Nx=$FFF7)or((Not Fat16)and(Nx=$FF7))Then Fatal(mErrBad);
   F:=FindFree(From);
   If(F=0)or(MapCount>=MaxMap)Then Fatal(mErrFull);
   From:=F+1;
   If(Not CopyCluster(C,F))Then Fatal(mErrWrite);
   FatSet(F,Nx);
   Inc(MapCount);MapOld[MapCount]:=C;MapNew[MapCount]:=F;
  End;
 End;
 If MapCount=0 Then Exit;
 { les chaines FAT qui menent aux grappes deplacees }
 For C:=2 to Word(Clusters+1)do Begin
  V:=FatGet(C);
  If(V>=2)and(V<=Need+1)Then Begin
   N2:=MapLookup(V);
   If N2<>0 Then FatSet(C,N2);
  End;
 End;
 For I:=1 to MapCount do FatSet(MapOld[I],0);
 { les premieres grappes des fichiers, les entrees . et .. }
 Bad:=False;
 WalkDirs(1);
 If Bad Then Fatal(mErrWrite);
End;

{ ---------------------------------------------------------------------- }
{ Partitionnement et formatage                                            }
{ ---------------------------------------------------------------------- }

Var
 FmtSpc:Byte;
 FmtSpf:Word;
 FmtF16:Boolean;
 FmtCl:LongInt;
 KeepBpc,KeepFree:LongInt;

{ Adresse CHS d'un secteur LBA dans une entree de partition (3 octets) }
Procedure PutChs(Var B:TSec;O:Integer;Lba:LongInt);
Var
 S,H,C,Tk:LongInt;
Begin
 S:=(Lba mod Spt)+1;
 Tk:=Lba div Spt;
 H:=Tk mod Heads;
 C:=Tk div Heads;
 If C>1023 Then Begin C:=1023;H:=Heads-1;S:=Spt;End;
 B[O]:=Byte(H);
 B[O+1]:=Byte(S or((C shr 2)and $C0));
 B[O+2]:=Byte(C and $FF);
End;

{ Taille de grappe et de FAT d'une partition de Total secteurs (racine de 512
  entrees, deux FAT). FAT12 jusqu'a 4084 grappes ; FAT16 : au plus 32700
  grappes (la FAT doit tenir dans 64 Ko), au moins 2 Ko par grappe. }
Procedure CalcFormat(Total:LongInt);
Var
 I,K:Integer;
 Need:LongInt;
 Spf2:Word;
Begin
 FmtSpc:=1;FmtSpf:=1;
 For I:=0 to 6 do Begin
  FmtSpc:=1 shl I;
  FmtSpf:=1;
  For K:=1 to 8 do Begin
   FmtCl:=(Total-33-LongInt(2)*FmtSpf)div FmtSpc;
   If FmtCl>4084 Then Need:=(FmtCl+2)*2 Else Need:=((FmtCl+2)*3+1)div 2;
   Spf2:=Word((Need+511)div 512);
   If Spf2=FmtSpf Then Break;
   FmtSpf:=Spf2;
  End;
  FmtF16:=FmtCl>4084;
  If FmtCl<=4084 Then Exit;
  If(FmtSpc>=4)and(FmtCl<=32700)Then Exit;
 End;
End;

{ Table de partition : une seule partition active (entree 0) ; les autres
  partitions sont supprimees }
Function CreatePartition:Boolean;
Var
 M:TSec;
Begin
 CreatePartition:=False;
 If Not DiskGeometry(Unit8)Then Exit;
 CalcFormat(SizeSec);
 PartLBA:=Spt;PartSectors:=SizeSec;
 FillChar(M,512,0);
 Move(MbrCode,M,SizeOf(MbrCode));
 M[$1BE]:=$80;
 PutChs(M,$1BF,PartLBA);
 If Not FmtF16 Then M[$1C2]:=1
 Else If SizeSec<65536 Then M[$1C2]:=4
 Else M[$1C2]:=6;
 PutChs(M,$1C3,PartLBA+PartSectors-1);
 PutLE32(M,$1C6,PartLBA);
 PutLE32(M,$1CA,PartSectors);
 M[510]:=$55;M[511]:=$AA;
 If Not WrAbs(0,M)Then Exit;
 KernelRefresh;
 CreatePartition:=True;
End;

Procedure DrawGauge;
Var
 Pct,N:LongInt;
Begin
 If TotalBytes>0 Then Pct:=DoneBytes*100 div TotalBytes Else Pct:=100;
 If Pct>100 Then Pct:=100;
 N:=Pct*GaugeW div 100;
 PutStr(5,16,NumStr(Pct)+Msg(mPct)+'       ',aNorm);
 Fill(6,18,5+GaugeW,18,' ',aNorm);
 If N>0 Then Fill(6,18,5+N,18,' ',aGauge);
 Fill(3,20,78,20,' ',aNorm);
 If CurFile<>'' Then PutStr(5,20,Msg(mCopying)+' '+CurFile,aNorm);
End;

Procedure ProgScreen;
Begin
 Clear;
 Title;
 PutStr(8,6,Msg(PhaseId),aNorm);
 Box(4,17,5+GaugeW+1,19,False,aNorm);
 StatusBar('');
 DrawGauge;
End;

Procedure Phase(Id:Integer);
Begin
 PhaseId:=Id;
 DoneBytes:=0;
 CurFile:='';
 If Id>=mPhCfg Then Begin TotalBytes:=1;DoneBytes:=1;End;
 ProgScreen;
End;

{ Formatage rapide FAT12/FAT16 de la partition (PartLBA, SizeSec) : secteur
  de boot MS-DOS (BPB), deux FAT et racine vides }
Function FormatPartition:Boolean;
Var
 B:TSec;
 I,K:Integer;
 S,Mi,Se,Hs:Word;
Begin
 FormatPartition:=False;
 CalcFormat(SizeSec);
 Move(BootCode,B,512);
 B[11]:=0;B[12]:=2;B[13]:=FmtSpc;B[14]:=1;B[15]:=0;B[16]:=2;
 B[17]:=0;B[18]:=2;
 If SizeSec<65536 Then Begin
  B[19]:=Byte(SizeSec and $FF);B[20]:=Byte(SizeSec shr 8);
  PutLE32(B,32,0);
 End
 Else Begin
  B[19]:=0;B[20]:=0;PutLE32(B,32,SizeSec);
 End;
 B[21]:=$F8;
 B[22]:=Byte(FmtSpf and $FF);B[23]:=Byte(FmtSpf shr 8);
 B[24]:=Byte(Spt);B[25]:=0;B[26]:=Byte(Heads);B[27]:=0;
 PutLE32(B,28,PartLBA);
 B[36]:=$80;B[37]:=0;B[38]:=$29;
 GetTime(S,Mi,Se,Hs);
 B[39]:=Byte(Se);B[40]:=Byte(Hs);B[41]:=Byte(Mi);B[42]:=Byte(S);
 For K:=43 to 53 do B[K]:=32;
 B[43]:=Ord('L');B[44]:=Ord('I');B[45]:=Ord('N');B[46]:=Ord('U');
 B[47]:=Ord('X');
 If FmtF16 Then PutTxt(B,54,'FAT16   ')Else PutTxt(B,54,'FAT12   ');
 B[510]:=$55;B[511]:=$AA;
 TotalBytes:=2*LongInt(FmtSpf)+32;
 DoneBytes:=0;
 DrawGauge;
 If Not WrPart(0,B)Then Exit;
 For K:=0 to 1 do
  For I:=0 to FmtSpf-1 do Begin
   FillChar(B,512,0);
   If I=0 Then Begin
    B[0]:=$F8;B[1]:=$FF;B[2]:=$FF;
    If FmtF16 Then B[3]:=$FF;
   End;
   If Not WrPart(1+LongInt(K)*FmtSpf+I,B)Then Exit;
   Inc(DoneBytes);
   If DoneBytes mod 8=0 Then DrawGauge;
  End;
 FillChar(B,512,0);
 For I:=0 to 31 do Begin
  If Not WrPart(1+LongInt(2)*FmtSpf+I,B)Then Exit;
  Inc(DoneBytes);
 End;
 DrawGauge;
 FormatPartition:=LoadBpb;
End;

{ Taille d'une partition commencant en Spt, arrondie au cylindre superieur
  (fin de partition sur une limite de cylindre, comme FDISK) }
Function AlignSize(S:LongInt;Up:Boolean):LongInt;
Var
 Cyl:LongInt;
Begin
 Cyl:=LongInt(Spt)*Heads;
 If Up Then S:=S+Cyl-1;
 AlignSize:=((Spt+S)div Cyl)*Cyl-Spt;
End;

{ Etat du disque dur U : partition d'entree 0 valide ou non }
Procedure ProbeDisk(U:Byte);
Var
 M:TSec;
 I,Used:Integer;
 C:Word;
Begin
 DState:=dsNoDisk;Mode:=0;PartLBA:=0;PartSectors:=0;
 If Not DiskGeometry(U)Then Exit;
 If Not RdAbs(0,M)Then Exit;
 MaxSec:=HdTotal-Spt;
 If MaxSec>2048000 Then MaxSec:=AlignSize(2048000,False);
 SizeSec:=MaxSec;
 Used:=0;
 If(M[510]=$55)and(M[511]=$AA)Then
  For I:=0 to 3 do
   If M[$1BE+I*16+4]<>0 Then Inc(Used);
 If Used=0 Then DState:=dsNoPart
 Else If Not(M[$1C2]in[1,4,6,$0E])Then DState:=dsOther
 Else Begin
  PartLBA:=LE32(M,$1C6);PartSectors:=LE32(M,$1CA);
  If PartLBA=0 Then DState:=dsOther
  Else If(Not LoadBpb)or(Not LoadFat)Then DState:=dsNoFormat
  Else If FsDamaged Then DState:=dsDamaged
  Else Begin
   DState:=dsReady;Mode:=1;
   KeepBpc:=Bpc;KeepFree:=0;
   For C:=2 to Word(Clusters+1)do
    If FatGet(C)=0 Then KeepFree:=KeepFree+Bpc;
  End;
 End;
End;


{ ---------------------------------------------------------------------- }
{ Ecrans                                                                  }
{ ---------------------------------------------------------------------- }

Function CountryName(I:Integer):String;
Begin
 Case I of
  1:CountryName:='France';
  2:CountryName:='Canada';
  3:CountryName:='Belgique';
  4:CountryName:='United States';
  5:CountryName:='United Kingdom';
  6:CountryName:='Deutschland';
  7:CountryName:='Oesterreich';
  8:CountryName:='Schweiz';
  9:CountryName:='Italia';
 Else
  CountryName:='Espa`na';
 End;
 CountryName:=Fix(CountryName);
End;

Function LangName(I:Integer):String;
Begin
 Case I of
  0:LangName:='Fran`cais';
  1:LangName:='English';
  2:LangName:='Deutsch';
  3:LangName:='Italiano';
 Else
  LangName:='Espa`nol';
 End;
 LangName:=Fix(LangName);
End;

{ Ligne d'une liste de parametres }
Procedure Row(Y:Integer;Sel:Boolean;Const L,V:String;VX:Integer);
Var
 A:Byte;
Begin
 If Sel Then A:=aHi Else A:=aNorm;
 Fill(8,Y,71,Y,' ',A);
 PutStr(10,Y,L,A);
 PutStr(VX,Y,V,A);
End;

{ Message d'une ligne (valeur incorrecte...) attendant une touche }
Procedure ShowMsg(Id:Integer);
Var
 K:Word;
Begin
 DlgBox(20,9,60,13);
 PutStr(24,11,Msg(Id),aDlg);
 K:=GetKey;
End;

Function ScreenWelcome:Boolean;
Var
 K:Word;
 Y:Integer;
Begin
 ScreenWelcome:=True;
 Repeat
  Clear;
  Title;
  PutStr(8,6,Msg(mWel1),aNorm);
  Y:=PutWrap(8,8,70,Msg(mWel2),aNorm);
  Y:=PutBullet(10,Y+1,66,Msg(mWelK1),aNorm);
  Y:=PutBullet(10,Y,66,Msg(mWelK2),aNorm);
  Y:=PutBullet(10,Y,66,Msg(mWelK3),aNorm);
  Y:=PutWrap(8,Y+1,70,Msg(mWelWarn),aTitle);
  StatusBar(Msg(mKeyNav));
  K:=GetKey;
  If K=kEnter Then Exit;
  If K=kEsc Then K:=kF3;
  Nav(K,0);
 Until False;
End;

Function DateTimeStr:String;
Var
 Y,M,D,Dw,H,Mi,S,S100:Word;
Begin
 GetDate(Y,M,D,Dw);GetTime(H,Mi,S,S100);
 DateTimeStr:=NumStr(Y)+'-'+Pad2(M)+'-'+Pad2(D)+' '+Pad2(H)+':'+Pad2(Mi);
End;

Function Bcd(N:Integer):Byte;
Begin
 Bcd:=((N div 10)shl 4)or(N mod 10);
End;

{ Horloge du BIOS (INT 1Ah, valeurs BCD) : INT 21h AH=2Bh du noyau transmet
  l'annee en binaire a INT 1Ah, ce qui fausse la date }
Procedure SetClock(Y,M,D,H,Mi:Integer);
Var
 R:Registers;
Begin
 R.AH:=5;R.CH:=Bcd(Y div 100);R.CL:=Bcd(Y mod 100);
 R.DH:=Bcd(M);R.DL:=Bcd(D);
 Intr($1A,R);
 R.AH:=3;R.CH:=Bcd(H);R.CL:=Bcd(Mi);R.DH:=0;R.DL:=0;
 Intr($1A,R);
End;

{ Saisie de AAAA-MM-JJ HH:MM ; ignore silencieusement une saisie invalide }
Procedure ChangeDateTime;
Var
 S:String;
 Y,M,D,H,Mi:LongInt;
 C1,C2,C3,C4,C5:Integer;
Begin
 S:=DateTimeStr;
 If Not InputBox(mDateQ,S,20)Then Exit;
 Val(Copy(S,1,4),Y,C1);Val(Copy(S,6,2),M,C2);Val(Copy(S,9,2),D,C3);
 Val(Copy(S,12,2),H,C4);Val(Copy(S,15,2),Mi,C5);
 If(C1+C2+C3+C4+C5=0)and(M>=1)and(M<=12)and(D>=1)and(D<=31)and(H<=23)and
   (Mi<=59)and(Y>=1980)and(Y<=2099)Then
  SetClock(Y,M,D,H,Mi)
 Else ShowMsg(mBadVal);
End;

Function ScreenSettings:Boolean;
Var
 K:Word;
 Sel,I,R:Integer;
Begin
 ScreenSettings:=True;
 Sel:=4;
 Repeat
  Clear;
  Title;
  PutStr(8,6,Msg(mSetIntro),aNorm);
  Box(7,8,72,13,False,aNorm);
  Row(9,Sel=1,Msg(mSetDate),DateTimeStr,36);
  Row(10,Sel=2,Msg(mSetCountry),CountryName(CountryIdx),36);
  Row(11,Sel=3,Msg(mSetLang),LangName(Lang),36);
  Row(12,Sel=4,Msg(mSetOk),'',36);
  PutWrap(8,15,66,Msg(mSetHelp),aNorm);
  StatusBar(Msg(mKeyNav));
  K:=GetKey;
  If(K=kUp)and(Sel>1)Then Dec(Sel)
  Else If(K=kDown)and(Sel<4)Then Inc(Sel)
  Else If K=kEsc Then Begin ScreenSettings:=False;Exit;End
  Else If K=kEnter Then Begin
   Case Sel of
    1:ChangeDateTime;
    2:Begin
       For I:=1 to CountryCount do ListItems[I]:=CountryName(I);
       R:=PickList(Msg(mSetCountry),CountryCount,CountryIdx);
       If R>0 Then CountryIdx:=R;
      End;
    3:Begin
       For I:=0 to 4 do ListItems[I+1]:=LangName(I);
       R:=PickList(Msg(mSetLang),5,Lang+1);
       If R>0 Then Begin Lang:=R-1;CountryIdx:=DefCountry[Lang];End;
      End;
   Else
    Exit;
   End;
  End
  Else Nav(K,0);
 Until False;
End;

{ Nom de machine, d'utilisateur (lettres, chiffres, - _ .) }
Function ValidName(Const S:String):Boolean;
Var
 I:Integer;
Begin
 ValidName:=False;
 If(Length(S)<1)or(Length(S)>15)Then Exit;
 For I:=1 to Length(S)do
  If Not(S[I]in['A'..'Z','a'..'z','0'..'9','-','_','.'])Then Exit;
 ValidName:=True;
End;

Function ValidHome(Var S:String):Boolean;
Var
 I:Integer;
Begin
 ValidHome:=False;
 For I:=1 to Length(S)do
  If S[I]='/' Then S[I]:='\';
 If(Length(S)<1)or(S[1]<>'\')Then Exit;
 For I:=1 to Length(S)do
  If S[I]in[' ','*','?','"','<','>','|',',',';','=']Then Exit;
 ValidHome:=True;
End;

Procedure EditVal(Var V:String;Kind:Integer);
Var
 S:String;
 Ok:Boolean;
Begin
 S:=V;
 If Not InputBox(mEditQ,S,40)Then Exit;
 If Kind=3 Then Ok:=ValidHome(S)Else Ok:=ValidName(S);
 If Ok Then V:=S Else ShowMsg(mBadVal);
End;

Function ScreenMachine:Boolean;
Var
 K:Word;
 Sel:Integer;
Begin
 ScreenMachine:=True;
 Sel:=4;
 Repeat
  Clear;
  Title;
  PutStr(8,6,Msg(mMacIntro),aNorm);
  Box(7,8,72,13,False,aNorm);
  Row(9,Sel=1,Msg(mMacHost),Host,36);
  Row(10,Sel=2,Msg(mMacUser),User,36);
  Row(11,Sel=3,Msg(mMacHome),Home,36);
  Row(12,Sel=4,Msg(mGoOn),'',36);
  StatusBar(Msg(mKeyNav));
  K:=GetKey;
  If(K=kUp)and(Sel>1)Then Dec(Sel)
  Else If(K=kDown)and(Sel<4)Then Inc(Sel)
  Else If K=kEsc Then Begin ScreenMachine:=False;Exit;End
  Else If K=kEnter Then Begin
   Case Sel of
    1:EditVal(Host,1);
    2:EditVal(User,2);
    3:EditVal(Home,3);
   Else
    Exit;
   End;
  End
  Else Nav(K,0);
 Until False;
End;

{ ---- disque dur ---- }

Function DiskName:String;
Begin
 If Unit8=$80 Then DiskName:='BIOS 80h'Else DiskName:='BIOS 81h';
End;

Procedure Probe;
Begin
 DlgBox(20,9,60,13);
 PutStr(24,11,Msg(mWait),aDlg);
 ProbeDisk($7F+DiskSel);
 Probed:=DiskSel;
End;

Procedure EditSize;
Var
 S:String;
 V:LongInt;
 C:Integer;
Begin
 A1:=NumStr(MaxSec div 2048);
 S:=NumStr(SizeSec div 2048);
 If Not InputBox(mSizeQ,S,10)Then Exit;
 Val(S,V,C);
 If(C<>0)or(V<4)Then ShowMsg(mBadVal)
 Else Begin
  SizeSec:=AlignSize(V*2048,True);
  If SizeSec>MaxSec Then SizeSec:=MaxSec;
 End;
End;

Function ScreenDisk:Boolean;
Var
 K:Word;
 Sel:Integer;
 S:String;
Begin
 ScreenDisk:=True;
 Sel:=4;
 If Probed<>DiskSel Then Probe;
 Repeat
  Clear;
  Title;
  PutStr(8,6,Msg(mDskIntro),aNorm);
  Box(7,8,72,13,False,aNorm);
  Row(9,Sel=1,Msg(mDskDisk),DiskName+', '+NumStr(HdTotal div 2048)+' '+
      Msg(mMo),24);
  If Mode=1 Then S:=Msg(mModeKeep)Else S:=Msg(mModeFmt);
  Row(10,Sel=2,Msg(mDskMode),S,24);
  If Mode=1 Then S:=NumStr(PartSectors div 2048)
  Else S:=NumStr(SizeSec div 2048);
  Row(11,Sel=3,Msg(mDskSize),S+' '+Msg(mMo),24);
  Row(12,Sel=4,Msg(mGoOn),'',24);
  If DState>=dsNoPart Then PutWrap(8,15,66,Msg(mStNoPart+DState-1),aNorm);
  StatusBar(Msg(mKeyNav));
  K:=GetKey;
  If(K=kUp)and(Sel>1)Then Dec(Sel)
  Else If(K=kDown)and(Sel<4)Then Inc(Sel)
  Else If K=kEsc Then Begin ScreenDisk:=False;Exit;End
  Else If K=kEnter Then Begin
   Case Sel of
    1:If HdCount>1 Then Begin
       ListItems[1]:='BIOS 80h';ListItems[2]:='BIOS 81h';
       K:=PickList(Msg(mDskDisk),2,DiskSel);
       If(K>0)and(K<>DiskSel)Then Begin DiskSel:=K;Probe;End;
      End;
    2:If DState=dsReady Then Mode:=1-Mode;
    3:If Mode=0 Then EditSize;
   Else
    If DState=dsNoDisk Then Fatal(mErrNoDisk)
    Else If(Mode=0)and(SizeSec<8192)Then Fatal(mErrSmall)
    Else Exit;
   End;
  End
  Else Nav(K,1);
 Until False;
End;

{ ---- espace ---- }

Procedure PlanSpace;
Begin
 If Mode=1 Then Begin
  Bpc:=KeepBpc;FreeBytes:=KeepFree;
 End
 Else Begin
  CalcFormat(SizeSec);
  Bpc:=LongInt(FmtSpc)*512;
  FreeBytes:=(FmtCl-4)*Bpc;
 End;
End;

Function Gen(I:Integer):Boolean;
Begin
 Gen:=(Entries[I].Name='PROFILE')or(Entries[I].Name='CUSTOM.CFG');
End;

Function Chosen(I:Integer;Mask:Word):Boolean;
Begin
 Chosen:=((Mask shr Entries[I].Comp)and 1)<>0;
End;

Function CompSize(Mask:Word):LongInt;
Var
 I:Integer;
 T:LongInt;
Begin
 T:=0;
 For I:=1 to EntryCount do
  If Chosen(I,Mask)Then T:=T+((Entries[I].Size+Bpc-1)div Bpc)*Bpc;
 CompSize:=T;
End;

Function NeedBytes(Mask:Word):LongInt;
Var
 I,N:Integer;
Begin
 N:=0;
 For I:=1 to EntryCount do
  If Chosen(I,Mask)Then Inc(N);
 NeedBytes:=CompSize(Mask)+LongInt(DirCount+4+N div(Bpc div 32))*Bpc;
End;

Function MaskOf(T:Integer):Word;
Begin
 Case T of
  1:MaskOf:=$03;
  2:MaskOf:=$0F;
  3:MaskOf:=$FF;
 Else
  MaskOf:=CustMask or 1;
 End;
End;

Function KbStr(N:LongInt):String;
Begin
 KbStr:=NumStr((N+1023)div 1024);
End;

Procedure SpaceLines(Y:Integer;Need:LongInt);
Begin
 A1:=KbStr(Need);
 PutStr(8,Y,Msg(mNeed),aNorm);
 A1:=KbStr(FreeBytes);
 PutStr(8,Y+1,Msg(mFree),aNorm);
 If Need>FreeBytes Then PutWrap(8,Y+3,66,Msg(mNoRoom),aTitle);
End;

Function ScreenCustom:Boolean;
Var
 K:Word;
 Sel,I:Integer;
 S:String;
Begin
 ScreenCustom:=True;
 Sel:=1;
 Repeat
  Clear;
  Title;
  For I:=0 to 7 do Begin
   If(CustMask shr I)and 1<>0 Then S:='[x] 'Else S:='[ ] ';
   Row(6+I,I=Sel,S+Msg(mComp0+I),
       KbStr(CompSize(1 shl I))+' '+Msg(mKo),56);
  End;
  SpaceLines(16,NeedBytes(CustMask or 1));
  StatusBar(Msg(mKeyCheck));
  K:=GetKey;
  If(K=kUp)and(Sel>0)Then Dec(Sel)
  Else If(K=kDown)and(Sel<7)Then Inc(Sel)
  Else If(K=kSpace)and(Sel>0)Then CustMask:=CustMask xor(1 shl Sel)
  Else If K=kEsc Then Begin ScreenCustom:=False;Exit;End
  Else If K=kEnter Then Exit
  Else Nav(K,0);
 Until False;
End;

Function ScreenType:Boolean;
Var
 K:Word;
 Sel,I:Integer;
 Need:LongInt;
Begin
 ScreenType:=True;
 PlanSpace;
 Sel:=InstType;
 Repeat
  Need:=NeedBytes(MaskOf(Sel));
  Clear;
  Title;
  PutStr(8,6,Msg(mTypIntro),aNorm);
  Box(7,8,72,13,False,aNorm);
  For I:=1 to 4 do Row(8+I,Sel=I,Msg(mTyp1+I-1),'',36);
  SpaceLines(15,Need);
  StatusBar(Msg(mKeyNav));
  K:=GetKey;
  If(K=kUp)and(Sel>1)Then Dec(Sel)
  Else If(K=kDown)and(Sel<4)Then Inc(Sel)
  Else If K=kEsc Then Begin ScreenType:=False;Exit;End
  Else If K=kEnter Then Begin
   InstType:=Sel;
   If(Sel<>4)or ScreenCustom Then
    If NeedBytes(MaskOf(Sel))<=FreeBytes Then Exit;
  End
  Else Nav(K,0);
 Until False;
End;

Function ScreenKernel:Boolean;
Var
 K:Word;
 Sel,C:Integer;
 S:String;
 V:LongInt;
Begin
 ScreenKernel:=True;
 Sel:=4;
 Repeat
  Clear;
  Title;
  PutStr(8,6,Msg(mKrnIntro),aNorm);
  Box(7,8,72,13,False,aNorm);
  Row(9,Sel=1,Msg(mKrnFiles),NumStr(FilesN),64);
  Row(10,Sel=2,Msg(mKrnBuf),NumStr(BufN),64);
  Row(11,Sel=3,Msg(mKrnDrv),LastDr,64);
  Row(12,Sel=4,Msg(mGoOn),'',64);
  StatusBar(Msg(mKeyNav));
  K:=GetKey;
  If(K=kUp)and(Sel>1)Then Dec(Sel)
  Else If(K=kDown)and(Sel<4)Then Inc(Sel)
  Else If K=kEsc Then Begin ScreenKernel:=False;Exit;End
  Else If K=kEnter Then Begin
   If Sel=4 Then Exit;
   S:='';
   If InputBox(mEditQ,S,10)Then Begin
    Val(S,V,C);
    Case Sel of
     1:If(C=0)and(V>=8)and(V<=20)Then FilesN:=V Else ShowMsg(mBadVal);
     2:If(C=0)and(V>=1)and(V<=99)Then BufN:=V Else ShowMsg(mBadVal);
    Else
     If(Length(S)=1)and(UpCase(S[1])in['C'..'F'])Then LastDr:=UpCase(S[1])
     Else ShowMsg(mBadVal);
    End;
   End;
  End
  Else Nav(K,0);
 Until False;
End;

{ Recapitulatif et confirmation avant toute ecriture sur le disque }
Function ScreenSummary:Boolean;
Var
 K:Word;
 Y:Integer;
 S:String;
Begin
 ScreenSummary:=True;
 PlanSpace;
 Repeat
  Clear;
  Title;
  PutStr(8,5,Msg(mSumT),aTitle);
  PutStr(8,7,PadTo(Msg(mDskDisk),19)+DiskName+', '+NumStr(HdTotal div 2048)+
         ' '+Msg(mMo),aNorm);
  If Mode=1 Then S:=NumStr(PartSectors div 2048)
  Else S:=NumStr(SizeSec div 2048);
  S:=S+' '+Msg(mMo);
  If Mode=1 Then Begin
   If Fat16 Then S:=S+', FAT16'Else S:=S+', FAT12';
  End
  Else If FmtF16 Then S:=S+', FAT16'Else S:=S+', FAT12';
  A1:=NumStr((Bpc+1023)div 1024);
  PutStr(8,8,PadTo(Msg(mDskSize),19)+S+', '+Msg(mClus),aNorm);
  PutStr(8,9,PadTo(Msg(mSumType),19)+Msg(mTyp1+InstType-1)+', '+
         KbStr(NeedBytes(MaskOf(InstType)))+' '+Msg(mKo),aNorm);
  PutStr(8,10,PadTo(Msg(mMacHost),19)+Host+', '+User+', '+Home,aNorm);
  PutStr(8,11,PadTo(Msg(mSetLang),19)+LangName(Lang)+', '+
         CountryName(CountryIdx),aNorm);
  PutStr(8,12,PadTo('Kernel',19)+'fs.files='+NumStr(FilesN)+
         ', buffers='+NumStr(BufN)+', lastdrive='+LastDr,aNorm);
  A1:=Copy(DiskName,6,3);
  If Mode=1 Then Y:=PutWrap(8,14,66,Msg(mSumKeep),aNorm)
  Else Y:=PutWrap(8,14,66,Msg(mSumFmt),aTitle);
  PutWrap(8,Y+1,66,Msg(mSumGo),aNorm);
  StatusBar(Msg(mKeyInstall));
  K:=GetKey;
  If K=kEnter Then Exit;
  If K=kEsc Then Begin ScreenSummary:=False;Exit;End;
  Nav(K,0);
 Until False;
End;


{ ---------------------------------------------------------------------- }
{ Installation                                                            }
{ ---------------------------------------------------------------------- }

{ Chemin complet (depuis la racine) du dossier d'une entree }
Function EntryDir(I:Integer):String;
Begin
 If Entries[I].Dir=0 Then EntryDir:='\'
 Else EntryDir:=DirName[Entries[I].Dir]+'\';
End;

{ Ouvre le fichier source sur la disquette courante, puis sur l'autre
  lecteur (A: ou B:) }
Function OpenSrc(Var F:File;Const Path:String):Boolean;
Var
 C:Char;
Begin
 OpenSrc:=False;
 FileMode:=0;
 Assign(F,SrcDrv+':'+Path);
 {$I-}Reset(F,1);{$I+}
 If IOResult=0 Then OpenSrc:=True
 Else Begin
  If SrcDrv='A' Then C:='B'Else C:='A';
  Assign(F,C+':'+Path);
  {$I-}Reset(F,1);{$I+}
  If IOResult=0 Then Begin OpenSrc:=True;SrcDrv:=C;End;
 End;
 FileMode:=2;
End;

{ Copie l'entree I ; les erreurs de lecture ou de disque manquant se
  traitent par la boite Reessayer / Ignorer / Annuler }
Procedure CopyOne(I:Integer);
Var
 F:File;
 Path:String;
 N11:String;
 Tm,Pos:LongInt;
 Got,Tot:Word;
 Err:Integer;
 Dir:Word;
 Attr:Byte;
 Skip,Done:Boolean;
Begin
 Path:=EntryDir(I)+Entries[I].Name;
 CurFile:=Entries[I].Name;
 DrawGauge;
 Skip:=False;
 While(Not Skip)and(Not OpenSrc(F,Path))do Begin
  Skip:=AskDisk(mAskDisk,Entries[I].Disk,True,Path);
  ProgScreen;
 End;
 If Skip Then Begin Inc(Skipped);Exit;End;
 N11:=To11(Entries[I].Name);
 Dir:=DirCl[Entries[I].Dir];
 If(Entries[I].Dir=0)and((Entries[I].Name='IO.SYS')or
   (Entries[I].Name='MSDOS.SYS'))Then Attr:=$27 Else Attr:=$20;
 {$I-}GetFTime(F,Tm);{$I+}
 If IOResult<>0 Then Tm:=NowTm;
 WBegin;
 Pos:=0;
 Repeat
  Tot:=0;
  Repeat
   {$I-}BlockRead(F,CopyBuf^[Tot],ChunkLen-Tot,Got);{$I+}
   Err:=IOResult;
   If Err<>0 Then Begin
    Got:=1;
    If AskDisk(mReadErr,0,True,Path)Then Begin
     Skip:=True;Got:=0;Tot:=ChunkLen;
    End
    Else Begin
     {$I-}Seek(F,Pos+Tot);{$I+}
     Err:=IOResult;
    End;
    ProgScreen;
   End
   Else Tot:=Tot+Got;
  Until(Got=0)or(Tot=ChunkLen);
  If Skip Then Done:=True
  Else Begin
   If Tot>0 Then
    If Not WData(CopyBuf^,Tot)Then Begin
     FreeChain(WFirst);
     If WFull Then Fatal(mErrFull)Else Fatal(mErrWrite);
    End;
   Pos:=Pos+Tot;
   DoneBytes:=DoneBytes+Tot;
   DrawGauge;
   Done:=Tot<ChunkLen;
  End;
 Until Done;
 Close(F);
 If Pos<>Entries[I].Size Then Skip:=True;
 If Skip Then Begin FreeChain(WFirst);Inc(Skipped);End
 Else If Not WEnd(Dir,N11,Attr,Tm)Then Fatal(mErrFull);
End;

{ ECHAP ou F3 pendant la copie : demande de confirmation }
Procedure Poll;
Var
 R:Registers;
 K:Word;
Begin
 R.AH:=1;
 Intr($16,R);
 If(R.Flags and FZero)=0 Then Begin
  K:=GetKey;
  If(K=kEsc)or(K=kF3)Then Begin
   If ConfirmExit Then QuitInstall;
   ProgScreen;
  End;
 End;
End;

Procedure CopyFiles;
Var
 I,J,D,MaxD:Integer;
 C:Word;
Begin
 TotalBytes:=0;
 For I:=1 to EntryCount do
  If Chosen(I,InstMask)and(Not Gen(I))Then
   TotalBytes:=TotalBytes+Entries[I].Size;
 If TotalBytes=0 Then TotalBytes:=1;
 Phase(mPhCopy);
 ChunkLen:=Word(16384 div Bpc)*Word(Bpc);
 If ChunkLen=0 Then ChunkLen:=Word(Bpc);
 If MaxAvail<ChunkLen Then Fatal(mErrMem);
 GetMem(CopyBuf,ChunkLen);
 DirCl[0]:=0;
 { IO.SYS puis MSDOS.SYS : 2 premieres entrees de la racine, contigus }
 For J:=1 to 2 do
  For I:=1 to EntryCount do
   If(Entries[I].Dir=0)and(Entries[I].Name=SysFile[J])Then Begin
    CopyOne(I);
    Entries[I].Comp:=Entries[I].Comp or 8;
   End;
 For I:=1 to DirCount do Begin
  C:=MakePath(DirName[I]);
  If C=$FFFF Then Fatal(mErrFull);
  DirCl[I]:=C;
 End;
 { disquette par disquette : avec un seul lecteur, chaque disquette n'est
   demandee qu'une fois (les fichiers du disque 1 d'abord, deja dans A:) }
 MaxD:=1;
 For I:=1 to EntryCount do
  If Entries[I].Disk>MaxD Then MaxD:=Entries[I].Disk;
 For D:=1 to MaxD do
  For I:=1 to EntryCount do
   If(Entries[I].Disk=D)and Chosen(I,InstMask)and(Not Gen(I))and
     (Entries[I].Comp<8)Then Begin
    Poll;
    CopyOne(I);
   End;
 CurFile:='';
 DoneBytes:=TotalBytes;
 DrawGauge;
End;

{ ---- fichiers de configuration ---- }

Procedure TL(Const S:String);
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do Begin
  TxtBuf[TxtLen]:=S[I];Inc(TxtLen);
 End;
 TxtBuf[TxtLen]:=#13;TxtBuf[TxtLen+1]:=#10;
 Inc(TxtLen,2);
End;

{ \Dir\Nm devient Nm.OLD s'il existe, puis est ecrit avec le texte }
Procedure PutText(Const Path,Nm,Old:String);
Var
 Dir:Word;
Begin
 Dir:=MakePath(Path);
 If Dir=$FFFF Then Fatal(mErrFull);
 DirDelete(Dir,To11(Old));
 If DirFind(Dir,To11(Nm))Then Begin
  PutName(DBuf,DOff,To11(Old));
  If Not WrPart(DLba,DBuf)Then Fatal(mErrWrite);
 End;
 WBegin;
 If Not WData(TxtBuf,TxtLen)Then Fatal(mErrFull);
 If Not WEnd(Dir,To11(Nm),$20,NowTm)Then Fatal(mErrFull);
 TxtLen:=0;
End;

Procedure WriteConfig;
Var
 CC:String;
Begin
 Phase(mPhCfg);
 CC:=NumStr(CountryCodes[CountryIdx]);
 While Length(CC)<3 do CC:='0'+CC;
 TxtLen:=0;
 TL('# \ETC\PROFILE - LINUX-0');
 TL('# Les commandes sont dans \BIN.');
 TL('PATH=\BIN');
 TL('export PATH');
 PutText('\ETC','PROFILE','PROFILE.OLD');
 TL('# /etc/sysctl.d/custom.cfg - configuration du noyau KERNEL16DOS '+
    '(genere par INSTALL)');
 TL('fs.files = '+NumStr(FilesN));
 TL('kernel.buffers = '+NumStr(BufN));
 TL('kernel.lastdrive = '+LastDr);
 TL('kernel.country = '+CC);
 TL('kernel.shell = \BIN\SH.EXE');
 TL('env.PATH = \BIN');
 TL('env.HOME = '+Home);
 TL('env.USER = '+User);
 TL('env.HOSTNAME = '+Host);
 If Lang<>0 Then TL('env.LANGUAGE = '+LangCodes[Lang]);
 PutText('\ETC\SYSCTL.D','CUSTOM.CFG','CUSTOM.OLD');
 If Home<>'\' Then Begin
  CC:=Home;
  While(Length(CC)>1)and(CC[Length(CC)]='\')do Dec(CC[0]);
  If MakePath(CC)=$FFFF Then Fatal(mErrFull);
 End;
End;

{ ---- disque amorcable ---- }

Function WriteBootSector:Boolean;
Var
 Old,Buf:TSec;
 J:Integer;
Begin
 WriteBootSector:=False;
 If Not RdPart(0,Old)Then Exit;
 Move(BootCode,Buf,512);
 For J:=3 to 61 do Buf[J]:=Old[J];
 { geometrie du BIOS et secteurs caches : le secteur de boot s'en sert pour
   convertir les adresses en CHS }
 Buf[24]:=Byte(Spt);Buf[25]:=0;Buf[26]:=Byte(Heads);Buf[27]:=0;
 PutLE32(Buf,28,PartLBA);
 Buf[36]:=$80;
 Buf[38]:=$29;
 Buf[510]:=$55;Buf[511]:=$AA;
 WriteBootSector:=WrPart(0,Buf);
End;

{ Chargeur MBR si absent ; la partition d'entree 0 devient active }
Function WriteMbr:Boolean;
Var
 M:TSec;
 I:Integer;
 Any:Byte;
Begin
 WriteMbr:=False;
 If Not RdAbs(0,M)Then Exit;
 If(M[510]<>$55)or(M[511]<>$AA)Then Exit;
 Any:=0;
 For I:=0 to 445 do Any:=Any or M[I];
 If Any=0 Then Move(MbrCode,M,SizeOf(MbrCode));
 For I:=0 to 3 do
  If I=0 Then M[$1BE]:=$80 Else M[$1BE+I*16]:=0;
 { adresses CHS de l'entree 0 selon la geometrie actuelle du BIOS }
 PutChs(M,$1BF,PartLBA);
 PutChs(M,$1C3,PartLBA+PartSectors-1);
 WriteMbr:=WrAbs(0,M);
End;

Procedure MakeBootable;
Var
 B:TSec;
 K,N:Integer;
 S0:LongInt;
Begin
 Phase(mPhBoot);
 { IO.SYS et MSDOS.SYS : 2 premieres entrees de la racine, IO.SYS contigu
   depuis la grappe 2 }
 If Not RdPart(RootStart,B)Then Fatal(mErrWrite);
 For K:=0 to 10 do
  If(B[K]<>Ord(SysN11[1][K+1]))or(B[32+K]<>Ord(SysN11[2][K+1]))Then
   Fatal(mErrSys);
 If(B[26]+B[27]*256<>2)Then Fatal(mErrSys);
 S0:=LE32(B,28);
 N:=Integer((S0+Bpc-1)div Bpc);
 For K:=0 to N-2 do
  If FatGet(2+K)<>3+K Then Fatal(mErrSys);
 If Not WriteFat Then Fatal(mErrWrite);
 If Not WriteBootSector Then Fatal(mErrWrite);
 If Not WriteMbr Then Fatal(mErrWrite);
 KernelRefresh;
End;

Procedure DoInstall;
Var
 Y,Mo,D,Dw,H,Mi,S,S100:Word;
 DT:DateTime;
Begin
 GetDate(Y,Mo,D,Dw);GetTime(H,Mi,S,S100);
 DT.Year:=Y;DT.Month:=Mo;DT.Day:=D;DT.Hour:=H;DT.Min:=Mi;DT.Sec:=S;
 PackTime(DT,NowTm);
 InstMask:=MaskOf(InstType);
 Skipped:=0;
 Unit8:=$7F+DiskSel;
 If Not DiskGeometry(Unit8)Then Fatal(mErrNoDisk);
 If Mode=0 Then Begin
  Phase(mPhPart);
  PartLBA:=Spt;
  If Not CreatePartition Then Fatal(mErrWrite);
  Phase(mPhFmt);
  If Not FormatPartition Then Fatal(mErrWrite);
 End;
 If(Not LoadBpb)or(Not LoadFat)Then Fatal(mErrWrite);
 If Mode=1 Then PrepareSystemArea;
 CopyFiles;
 WriteConfig;
 MakeBootable;
End;

Procedure ScreenDone;
Var
 K:Word;
 Y:Integer;
 R:Registers;
Begin
 Clear;
 Title;
 DlgBox(8,6,72,16);
 PutStr(10,6,Msg(mDoneT),aDlg);
 Y:=PutWrap(11,8,58,Msg(mDone1),aDlg);
 Y:=PutWrap(11,Y+1,58,Msg(mDone2),aDlg);
 If Skipped>0 Then Begin
  A1:=NumStr(Skipped);
  PutWrap(11,Y+1,58,Msg(mSkipped),aDlg);
 End;
 StatusBar(Msg(mKeyDone));
 Repeat
  K:=GetKey;
 Until(K=kEnter)or(K=kEsc);
 RestoreScreen;
 If K=kEsc Then Halt(0);
 { demarrage a chaud puis INT 19h (rechargement du secteur de boot) }
 MemW[$40:$72]:=$1234;
 Intr($19,R);
End;

Var
 Step:Integer;
 Ok:Boolean;
 L:LongInt;
 E:String;
BEGIN
 Lang:=0;
 E:=UpStr(Copy(GetEnv('LANGUAGE'),1,2));
 If E='EN' Then Lang:=1
 Else If(E='GR')or(E='DE')Then Lang:=2
 Else If E='IT' Then Lang:=3
 Else If(E='SP')or(E='ES')Then Lang:=4;
 CountryIdx:=DefCountry[Lang];
 Host:='linux0';User:='root';Home:='\';
 FilesN:=20;BufN:=20;LastDr:='F';
 InstType:=2;CustMask:=$0F;DiskSel:=1;
 Mono:=False;
 InitVideo;
 SetTheme;
 CursorOff;
 If MemAvail<105000 Then Begin
  Fatal(mErrMem);
 End;
 GetMem(Fat,65520);
 GetMem(StgRaw,1024);
 L:=LongInt(Seg(StgRaw^))*16+Ofs(StgRaw^);
 L:=L+(512-L mod 512)mod 512;
 Stg:=Pointer((L shr 4)shl 16);
 ReadInf;
 HdCount:=0;
 If DiskExists($80)Then HdCount:=1;
 If(HdCount=1)and DiskExists($81)Then HdCount:=2;
 If HdCount=0 Then Fatal(mErrNoDisk);
 Step:=1;
 While Step<=7 do Begin
  Case Step of
   1:Ok:=ScreenWelcome;
   2:Ok:=ScreenSettings;
   3:Ok:=ScreenMachine;
   4:Ok:=ScreenDisk;
   5:Ok:=ScreenType;
   6:Ok:=ScreenKernel;
  Else
   Ok:=ScreenSummary;
  End;
  If Ok Then Inc(Step)
  Else If Step>1 Then Dec(Step);
 End;
 DoInstall;
 ScreenDone;
END.
