{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal)
  @description: Cree les images disque amorcables de LINUX-0 (KERNEL16) :
                disquettes FAT12 (LINUX144A.IMG, LINUX144B.IMG...), disque
                dur FAT16 avec MBR et CD-ROM ISO 9660 amorcable (El Torito).
}

Program MAKEDISK;

{ Programme autonome : il formate les images, installe le secteur de boot
  MS-DOS 6.22 generique (qui cherche IO.SYS et MSDOS.SYS comme deux premieres
  entrees de la racine et charge IO.SYS de facon contigue), ecrit les FAT, les
  repertoires et copie lui-meme tous les fichiers. IO.SYS, MSDOS.SYS puis les
  autres fichiers sont toujours alloues en premier et de facon contigue.

  Entrees :
    SYSTEM  dossier du systeme (IO.SYS, MSDOS.SYS, CONFIG.SYS...), copie a la
            racine et toujours place sur la premiere disquette ;
    CMDS    dossier des commandes (*.EXE...), copiees dans \BIN ;
    ADD     fichiers, masques ou dossiers additionnels (src=destination) ;
    DIR     dossiers vides a creer ;
    BOOT    fichiers (masques permis) qui doivent etre sur la 1ere disquette.
  Ces informations viennent de la ligne de commande et/ou d'un manifeste
  (/INF:IMAGE.INF), dont les chemins relatifs sont relatifs au manifeste.

  Sorties :
    <NAME>144A.IMG, <NAME>144B.IMG... disquettes (repartition automatique),
    <NAME>HD.IMG   disque dur (option /HD:Mo),
    <NAME>.ISO     CD-ROM amorcable (option /ISO).

  Codes de retour : 0 = bon, 1 = parametres, 2 = fichiers d'entree,
  3 = erreur d'entree/sortie, 4 = les fichiers ne tiennent pas. }

{$M 16384,0,655360}
{$R-,S-,I-,V-}

Uses DOS;

Const
 MaxEnt=500;
 MaxDir=32;
 MaxDisk=26;
 MaxAdd=40;
 MaxBoot=40;
 MaxMk=24;
 MaxKid=1000;
 IsoSec=2048;
 CopySize=32768;
 {$IFDEF UNIX}
 HSep='/';
 AllMask='*';
 {$ELSE}
 HSep='\';
 AllMask='*.*';
 {$ENDIF}
 MsdosSys='; MSDOS.SYS - Linux-0'#13#10;

Const
 M_h00=0;
 M_h01=1;
 M_h02=2;
 M_h03=3;
 M_h04=4;
 M_h05=5;
 M_h06=6;
 M_h07=7;
 M_h08=8;
 M_h09=9;
 M_h10=10;
 M_h11=11;
 M_h12=12;
 M_h13=13;
 M_h14=14;
 M_h15=15;
 M_h16=16;
 M_h17=17;
 M_h18=18;
 M_h19=19;
 M_h20=20;
 M_h21=21;
 M_h22=22;
 M_h23=23;
 M_h24=24;
 M_eUnkOpt=25;
 M_eBadVal=26;
 M_eInf=27;
 M_eNoSys=28;
 M_eNoIo=29;
 M_eNoCmd=30;
 M_wNoMatch=31;
 M_wName83=32;
 M_wSkip=33;
 M_eTooMany=34;
 M_eTooDirs=35;
 M_wTooBig=36;
 M_eBootFit=37;
 M_eManyDisks=38;
 M_eCreate=39;
 M_eRead=40;
 M_eWrite=41;
 M_eFat=42;
 M_eHdSize=43;
 M_eFloppy=44;
 M_eDate=45;
 M_eIsoFl=46;
 M_eDirBig=47;
 M_eHdFit=48;
 M_eSrcSize=49;
 M_iFat=50;
 M_iMade=51;
 M_iIso=52;
 M_iTotal=53;
 M_iCopy=54;
 MsgCount=55;

{ Table des messages : FR, EN, GR, SP, IT }
Const
 MsgTab:Array[0..MsgCount-1,0..4]of String[74]=(
  (
   'MAKEDISK : cree les images disque amorcables de LINUX-0 (KERNEL16).',
   'MAKEDISK: builds the bootable disk images of LINUX-0 (KERNEL16).',
   'MAKEDISK: erzeugt die bootfaehigen Disk-Images von LINUX-0 (KERNEL16).',
   'MAKEDISK: crea las imagenes de disco arrancables de LINUX-0 (KERNEL16).',
   'MAKEDISK: crea le immagini disco avviabili di LINUX-0 (KERNEL16).'
  ),
  (
   '',
   '',
   '',
   '',
   ''
  ),
  (
   'Syntaxe : MAKEDISK [/INF:fichier] [options]',
   'Syntax: MAKEDISK [/INF:file] [options]',
   'Syntax: MAKEDISK [/INF:datei] [Optionen]',
   'Sintaxis: MAKEDISK [/INF:archivo] [opciones]',
   'Sintassi: MAKEDISK [/INF:file] [opzioni]'
  ),
  (
   '',
   '',
   '',
   '',
   ''
  ),
  (
   ' /INF:fichier    Manifeste : lignes "MOT valeur" (voir IMAGE.INF).',
   ' /INF:file       Manifest: lines "KEY value" (see IMAGE.INF).',
   ' /INF:datei      Manifest: Zeilen "WORT Wert" (siehe IMAGE.INF).',
   ' /INF:archivo    Manifiesto: lineas "PALABRA valor" (ver IMAGE.INF).',
   ' /INF:file       Manifesto: righe "PAROLA valore" (vedi IMAGE.INF).'
  ),
  (
   ' /SYSTEM:dossier IO.SYS, MSDOS.SYS, CONFIG.SYS... a la racine (SYSTEM).',
   ' /SYSTEM:dir     IO.SYS, MSDOS.SYS, CONFIG.SYS... at the root (SYSTEM).',
   ' /SYSTEM:ordner  IO.SYS, MSDOS.SYS, CONFIG.SYS... im Stamm (SYSTEM).',
   ' /SYSTEM:dir     IO.SYS, MSDOS.SYS, CONFIG.SYS... en la raiz (SYSTEM).',
   ' /SYSTEM:dir     IO.SYS, MSDOS.SYS, CONFIG.SYS... nella radice (SYSTEM).'
  ),
  (
   ' /CMDS:dossier   Commandes copiees dans \BIN (defaut BIN16).',
   ' /CMDS:dir       Commands copied into \BIN (default BIN16).',
   ' /CMDS:ordner    Befehle, kopiert nach \BIN (Standard BIN16).',
   ' /CMDS:dir       Comandos copiados en \BIN (por defecto BIN16).',
   ' /CMDS:dir       Comandi copiati in \BIN (predefinito BIN16).'
  ),
  (
   ' /MASK:m1,m2     Masques des commandes (defaut *.EXE,*.COM,*.BAT).',
   ' /MASK:m1,m2     Command masks (default *.EXE,*.COM,*.BAT).',
   ' /MASK:m1,m2     Masken der Befehle (Standard *.EXE,*.COM,*.BAT).',
   ' /MASK:m1,m2     Mascaras de comandos (por defecto *.EXE,*.COM,*.BAT).',
   ' /MASK:m1,m2     Maschere dei comandi (predefinito *.EXE,*.COM,*.BAT).'
  ),
  (
   ' /ADD:src=dest   Ajoute un fichier, un masque ou un dossier (repetable).',
   ' /ADD:src=dest   Adds a file, a mask or a folder (repeatable).',
   ' /ADD:src=ziel   Fuegt Datei, Maske oder Ordner hinzu (wiederholbar).',
   ' /ADD:src=dest   Anade archivo, mascara o carpeta (repetible).',
   ' /ADD:src=dest   Aggiunge file, maschera o cartella (ripetibile).'
  ),
  (
   ' /DIR:chemin     Cree un dossier vide dans l''image (repetable).',
   ' /DIR:path       Creates an empty folder in the image (repeatable).',
   ' /DIR:pfad       Erzeugt einen leeren Ordner im Image (wiederholbar).',
   ' /DIR:ruta       Crea una carpeta vacia en la imagen (repetible).',
   ' /DIR:percorso   Crea una cartella vuota nell''immagine (ripetibile).'
  ),
  (
   ' /BOOT:chemin    Fichiers obligatoires sur la 1ere disquette (repetable).',
   ' /BOOT:path      Files required on the 1st floppy (repeatable).',
   ' /BOOT:pfad      Dateien, die auf Diskette 1 sein muessen (wiederholbar).',
   ' /BOOT:ruta      Archivos obligatorios en el 1er disquete (repetible).',
   ' /BOOT:percorso  File obbligatori sul 1o dischetto (ripetibile).'
  ),
  (
   ' /NAME:nom       Prefixe des images (defaut LINUX : LINUX144A.IMG).',
   ' /NAME:name      Image name prefix (default LINUX: LINUX144A.IMG).',
   ' /NAME:name      Praefix der Images (Standard LINUX: LINUX144A.IMG).',
   ' /NAME:nombre    Prefijo de las imagenes (defecto LINUX: LINUX144A.IMG).',
   ' /NAME:nome      Prefisso delle immagini (predef. LINUX: LINUX144A.IMG).'
  ),
  (
   ' /OUT:dossier    Dossier des images creees (defaut : dossier courant).',
   ' /OUT:dir        Folder of the created images (default: current folder).',
   ' /OUT:ordner     Ordner der erzeugten Images (Standard: aktueller Ordner).',
   ' /OUT:dir        Carpeta de las imagenes creadas (defecto: la actual).',
   ' /OUT:dir        Cartella delle immagini create (predef.: corrente).'
  ),
  (
   ' /FREE:Ko       Espace libre reserve sur chaque disquette (defaut 0).',
   ' /FREE:KB        Free space kept on each floppy (default 0).',
   ' /FREE:KB        Freier Platz auf jeder Diskette (Standard 0).',
   ' /FREE:KB        Espacio libre reservado en cada disquete (defecto 0).',
   ' /FREE:KB        Spazio libero riservato su ogni dischetto (predef. 0).'
  ),
  (
   ' /FLOPPY:Ko      160, 180, 320, 360, 720, 1200, 1440 (defaut) ou 2880.',
   ' /FLOPPY:KB      160, 180, 320, 360, 720, 1200, 1440 (default) or 2880.',
   ' /FLOPPY:KB      160, 180, 320, 360, 720, 1200, 1440 (Standard), 2880.',
   ' /FLOPPY:KB      160, 180, 320, 360, 720, 1200, 1440 (defecto) o 2880.',
   ' /FLOPPY:KB      160, 180, 320, 360, 720, 1200, 1440 (predef.) o 2880.'
  ),
  (
   ' /HD:Mo          Cree aussi un disque dur MBR + FAT16 (1 a 1000, def. 32).',
   ' /HD:MB          Also builds a hard disk MBR + FAT16 (1 to 1000, def. 32).',
   ' /HD:MB          Erzeugt auch Festplatte MBR + FAT16 (1-1000, Std. 32).',
   ' /HD:MB          Crea tambien disco duro MBR + FAT16 (1 a 1000, def 32).',
   ' /HD:MB          Crea anche un disco fisso MBR + FAT16 (1-1000, pred. 32).'
  ),
  (
   ' /ISO[:nom]      Cree aussi un CD-ROM ISO 9660 amorcable (El Torito).',
   ' /ISO[:name]     Also builds a bootable ISO 9660 CD-ROM (El Torito).',
   ' /ISO[:name]     Erzeugt auch eine bootfaehige ISO-9660-CD (El Torito).',
   ' /ISO[:nombre]   Crea tambien un CD-ROM ISO 9660 arrancable (El Torito).',
   ' /ISO[:nome]     Crea anche un CD-ROM ISO 9660 avviabile (El Torito).'
  ),
  (
   ' /FAT12, /FAT16  Force le type de FAT du disque dur.',
   ' /FAT12, /FAT16  Forces the FAT type of the hard disk.',
   ' /FAT12, /FAT16  Erzwingt den FAT-Typ der Festplatte.',
   ' /FAT12, /FAT16  Fuerza el tipo de FAT del disco duro.',
   ' /FAT12, /FAT16  Forza il tipo di FAT del disco fisso.'
  ),
  (
   ' /LABEL:nom      Nom de volume (defaut LINUX).',
   ' /LABEL:name     Volume label (default LINUX).',
   ' /LABEL:name     Datentraegername (Standard LINUX).',
   ' /LABEL:nombre   Etiqueta de volumen (defecto LINUX).',
   ' /LABEL:nome     Etichetta del volume (predef. LINUX).'
  ),
  (
   ' /DATE:AAAA-MM-JJ Date fixe des fichiers (images reproductibles).',
   ' /DATE:YYYY-MM-DD Fixed file date (reproducible images).',
   ' /DATE:JJJJ-MM-TT Festes Dateidatum (reproduzierbare Images).',
   ' /DATE:AAAA-MM-DD Fecha fija de los archivos (imagenes reproducibles).',
   ' /DATE:AAAA-MM-GG Data fissa dei file (immagini riproducibili).'
  ),
  (
   ' /V              Affiche chaque fichier copie.',
   ' /V              Shows each copied file.',
   ' /V              Zeigt jede kopierte Datei an.',
   ' /V              Muestra cada archivo copiado.',
   ' /V              Mostra ogni file copiato.'
  ),
  (
   ' @fichier        Lit des options dans un fichier (une par ligne).',
   ' @file           Reads options from a file (one per line).',
   ' @datei          Liest Optionen aus einer Datei (eine pro Zeile).',
   ' @archivo        Lee opciones de un archivo (una por linea).',
   ' @file           Legge le opzioni da un file (una per riga).'
  ),
  (
   '',
   '',
   '',
   '',
   ''
  ),
  (
   'Langue : variable LANGUAGE = FR (defaut), EN, GR, SP ou IT.',
   'Language: variable LANGUAGE = FR (default), EN, GR, SP or IT.',
   'Sprache: Variable LANGUAGE = FR (Standard), EN, GR, SP oder IT.',
   'Idioma: variable LANGUAGE = FR (defecto), EN, GR, SP o IT.',
   'Lingua: variabile LANGUAGE = FR (predef.), EN, GR, SP o IT.'
  ),
  (
   'Exemple : MAKEDISK /INF:IMAGE.INF /HD:32 /ISO',
   'Example: MAKEDISK /INF:IMAGE.INF /HD:32 /ISO',
   'Beispiel: MAKEDISK /INF:IMAGE.INF /HD:32 /ISO',
   'Ejemplo: MAKEDISK /INF:IMAGE.INF /HD:32 /ISO',
   'Esempio: MAKEDISK /INF:IMAGE.INF /HD:32 /ISO'
  ),
  (
   'Option inconnue : %1',
   'Unknown option: %1',
   'Unbekannte Option: %1',
   'Opcion desconocida: %1',
   'Opzione sconosciuta: %1'
  ),
  (
   'Valeur invalide : %1',
   'Invalid value: %1',
   'Ungueltiger Wert: %1',
   'Valor no valido: %1',
   'Valore non valido: %1'
  ),
  (
   'Manifeste introuvable : %1',
   'Manifest not found: %1',
   'Manifest nicht gefunden: %1',
   'Manifiesto no encontrado: %1',
   'Manifesto non trovato: %1'
  ),
  (
   'Dossier systeme introuvable : %1',
   'System folder not found: %1',
   'Systemordner nicht gefunden: %1',
   'Carpeta del sistema no encontrada: %1',
   'Cartella di sistema non trovata: %1'
  ),
  (
   'IO.SYS introuvable dans %1',
   'IO.SYS not found in %1',
   'IO.SYS nicht gefunden in %1',
   'IO.SYS no encontrado en %1',
   'IO.SYS non trovato in %1'
  ),
  (
   'Dossier des commandes introuvable : %1',
   'Commands folder not found: %1',
   'Befehlsordner nicht gefunden: %1',
   'Carpeta de comandos no encontrada: %1',
   'Cartella dei comandi non trovata: %1'
  ),
  (
   'Avertissement : rien ne correspond a %1',
   'Warning: nothing matches %1',
   'Warnung: nichts passt zu %1',
   'Aviso: nada coincide con %1',
   'Avviso: nulla corrisponde a %1'
  ),
  (
   'Avertissement : nom 8.3 : %1 devient %2',
   'Warning: 8.3 name: %1 becomes %2',
   'Warnung: 8.3-Name: %1 wird %2',
   'Aviso: nombre 8.3: %1 pasa a %2',
   'Avviso: nome 8.3: %1 diventa %2'
  ),
  (
   'Avertissement : nom ignore : %1',
   'Warning: name ignored: %1',
   'Warnung: Name ignoriert: %1',
   'Aviso: nombre ignorado: %1',
   'Avviso: nome ignorato: %1'
  ),
  (
   'Trop de fichiers (maximum %1)',
   'Too many files (maximum %1)',
   'Zu viele Dateien (maximal %1)',
   'Demasiados archivos (maximo %1)',
   'Troppi file (massimo %1)'
  ),
  (
   'Trop de dossiers (maximum %1)',
   'Too many folders (maximum %1)',
   'Zu viele Ordner (maximal %1)',
   'Demasiadas carpetas (maximo %1)',
   'Troppe cartelle (massimo %1)'
  ),
  (
   'Avertissement : %1 trop gros pour une disquette, ignore',
   'Warning: %1 is too big for a floppy, skipped',
   'Warnung: %1 ist fuer eine Diskette zu gross, uebersprungen',
   'Aviso: %1 es demasiado grande para un disquete, omitido',
   'Avviso: %1 troppo grande per un dischetto, saltato'
  ),
  (
   'Les fichiers systeme et /BOOT ne tiennent pas sur la disquette A',
   'System and /BOOT files do not fit on floppy A',
   'System- und /BOOT-Dateien passen nicht auf Diskette A',
   'Los archivos del sistema y /BOOT no caben en el disquete A',
   'I file di sistema e /BOOT non entrano nel dischetto A'
  ),
  (
   'Trop de disquettes (maximum %1)',
   'Too many floppies (maximum %1)',
   'Zu viele Disketten (maximal %1)',
   'Demasiados disquetes (maximo %1)',
   'Troppi dischetti (massimo %1)'
  ),
  (
   'Creation impossible : %1',
   'Cannot create: %1',
   'Erstellen unmoeglich: %1',
   'No se puede crear: %1',
   'Impossibile creare: %1'
  ),
  (
   'Lecture impossible : %1',
   'Cannot read: %1',
   'Lesen unmoeglich: %1',
   'No se puede leer: %1',
   'Impossibile leggere: %1'
  ),
  (
   'Erreur d''ecriture : %1',
   'Write error: %1',
   'Schreibfehler: %1',
   'Error de escritura: %1',
   'Errore di scrittura: %1'
  ),
  (
   'Ce type de FAT est impossible pour cette taille',
   'This FAT type is impossible for this size',
   'Dieser FAT-Typ ist fuer diese Groesse unmoeglich',
   'Este tipo de FAT es imposible para este tamano',
   'Questo tipo di FAT e impossibile per questa dimensione'
  ),
  (
   'Taille de disque dur invalide (1 a 1000 Mo) : %1',
   'Invalid hard disk size (1 to 1000 MB): %1',
   'Ungueltige Festplattengroesse (1 bis 1000 MB): %1',
   'Tamano de disco duro no valido (1 a 1000 MB): %1',
   'Dimensione disco fisso non valida (da 1 a 1000 MB): %1'
  ),
  (
   'Taille de disquette non prise en charge : %1',
   'Unsupported floppy size: %1',
   'Disketten-Groesse nicht unterstuetzt: %1',
   'Tamano de disquete no admitido: %1',
   'Dimensione del dischetto non supportata: %1'
  ),
  (
   'Date invalide (AAAA-MM-JJ, 1980-2099) : %1',
   'Invalid date (YYYY-MM-DD, 1980-2099): %1',
   'Ungueltiges Datum (JJJJ-MM-TT, 1980-2099): %1',
   'Fecha no valida (AAAA-MM-DD, 1980-2099): %1',
   'Data non valida (AAAA-MM-GG, 1980-2099): %1'
  ),
  (
   'ISO : la disquette doit etre de 1200, 1440 ou 2880 Ko',
   'ISO: the floppy must be 1200, 1440 or 2880 KB',
   'ISO: die Diskette muss 1200, 1440 oder 2880 KB gross sein',
   'ISO: el disquete debe ser de 1200, 1440 o 2880 KB',
   'ISO: il dischetto deve essere da 1200, 1440 o 2880 KB'
  ),
  (
   'Dossier trop grand : %1',
   'Folder too big: %1',
   'Ordner zu gross: %1',
   'Carpeta demasiado grande: %1',
   'Cartella troppo grande: %1'
  ),
  (
   'Les fichiers ne tiennent pas dans l''image (%1 Mo)',
   'The files do not fit in the image (%1 MB)',
   'Die Dateien passen nicht in das Image (%1 MB)',
   'Los archivos no caben en la imagen (%1 MB)',
   'I file non entrano nell''immagine (%1 MB)'
  ),
  (
   'Taille du fichier modifiee pendant la copie : %1',
   'File size changed during the copy: %1',
   'Dateigroesse waehrend des Kopierens geaendert: %1',
   'Tamano del archivo modificado durante la copia: %1',
   'Dimensione del file cambiata durante la copia: %1'
  ),
  (
   'Formatage FAT%1 : %2 secteurs, %3 clusters de %4 secteur(s)',
   'Format FAT%1: %2 sectors, %3 clusters of %4 sector(s)',
   'Formatierung FAT%1: %2 Sektoren, %3 Cluster zu %4 Sektor(en)',
   'Formato FAT%1: %2 sectores, %3 clusteres de %4 sector(es)',
   'Formattazione FAT%1: %2 settori, %3 cluster da %4 settore/i'
  ),
  (
   'Image creee : %1 (%2 fichiers, %3 Ko libres)',
   'Image created: %1 (%2 files, %3 KB free)',
   'Image erstellt: %1 (%2 Dateien, %3 KB frei)',
   'Imagen creada: %1 (%2 archivos, %3 KB libres)',
   'Immagine creata: %1 (%2 file, %3 KB liberi)'
  ),
  (
   'CD-ROM cree : %1 (%2 fichiers, %3 Ko)',
   'CD-ROM created: %1 (%2 files, %3 KB)',
   'CD-ROM erstellt: %1 (%2 Dateien, %3 KB)',
   'CD-ROM creado: %1 (%2 archivos, %3 KB)',
   'CD-ROM creato: %1 (%2 file, %3 KB)'
  ),
  (
   'Fichiers : %1 (%2 Ko), dossiers : %3',
   'Files: %1 (%2 KB), folders: %3',
   'Dateien: %1 (%2 KB), Ordner: %3',
   'Archivos: %1 (%2 KB), carpetas: %3',
   'File: %1 (%2 KB), cartelle: %3'
  ),
  (
   '  %1 -> %2',
   '  %1 -> %2',
   '  %1 -> %2',
   '  %1 -> %2',
   '  %1 -> %2'
  )
 );


Type
 TBytes=Array[0..65519]of Byte;
 PBytes=^TBytes;
 TEnt=Record
  Src:String[127];       { chemin source ('' = MSDOS.SYS genere) }
  N11:String[11];        { nom 8.3 sur 11 caracteres }
  DIdx:Byte;             { dossier de destination }
  Attr:Byte;
  Sys:Byte;              { 1 = IO.SYS, 2 = MSDOS.SYS }
  Boot:Boolean;          { obligatoirement sur la premiere disquette }
  Size:LongInt;
  Disk:Integer;          { -1 a placer, -2 trop gros, 0.. disquette }
  Clu:Word;              { premier cluster pendant la construction }
  Lba:LongInt;           { secteur ISO }
 End;
 PEnt=^TEnt;
 TDirRec=Record
  N11:String[11];
  Parent:Byte;
  Keep:Boolean;          { dossier cree meme vide }
  Path:String[63];       { chemin dans l'image, '' pour la racine }
  Used:Boolean;
  Cnt:Word;              { nombre d'entrees dans ce dossier }
  Clu:Word;
  NClu:Word;
  Lba:LongInt;
  ISize:LongInt;
  PtNum:Word;
 End;
 TCntRow=Array[0..MaxDir]of Word;
 TPresRow=Array[0..MaxDir]of Boolean;
 TKids=Array[0..MaxKid-1]of Integer;
 PKids=^TKids;
 TGeom=Record
  Bits:Byte;             { 12 ou 16 }
  Spc:Byte;
  Root:Word;
  Spf:Word;
  Media:Byte;
  Spt:Word;
  Heads:Word;
  Total:LongInt;         { secteurs du volume }
  Hidden:LongInt;        { debut de la partition (disque dur) }
  ImgSecs:LongInt;       { secteurs de l'image }
  Clusters:LongInt;
  Drive:Byte;
 End;

Var
 Lang:Integer;
 SysDir,CmdDir,OutDir,BaseName,VolLabel,BinDir,Masks,IsoName,BaseDir:String;
 FloppyKB,HardMB,FreeKB:Word;
 DoHard,DoIso,Verbose:Boolean;
 ForceBits:Byte;
 AddSrc,AddDst:Array[1..MaxAdd]of String[100];
 AddCnt:Integer;
 BootPat:Array[1..MaxBoot]of String[63];
 BootCnt:Integer;
 MkList:Array[1..MaxMk]of String[63];
 MkCnt:Integer;
 Yr,Mo,Dy,Hr,Mi,Sc:Word;
 DDate,DTime:Word;
 Ents:Array[1..MaxEnt]of PEnt;
 EntCnt:Integer;
 Dirs:Array[0..MaxDir]of TDirRec;
 DirCnt:Integer;
 KidP:Array[0..MaxDir]of PKids;
 KidN:Array[0..MaxDir]of Word;
 FG:TGeom;
 DCnt:Array[0..MaxDisk-1]of TCntRow;
 DPres:Array[0..MaxDisk-1]of TPresRow;
 DiskCnt:Integer;
 DUse:Array[0..MaxDisk-1]of LongInt;
 Img:File;
 ZBuf,CBuf:PBytes;
 Sec:Array[0..IsoSec-1]of Byte;
 InfDepth:Integer;

{ ---- Messages ---- }

Function UpStr(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do
  If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 UpStr:=S;
End;

Function NumStr(N:LongInt):String;
Var
 S:String;
Begin
 Str(N,S);
 NumStr:=S;
End;

Procedure InitLang;
Var
 S:String;
Begin
 Lang:=0;
 S:=UpStr(GetEnv('LANGUAGE'));
 S:=Copy(S,1,2);
 If S='EN'Then Lang:=1
  Else If(S='GR')or(S='DE')Then Lang:=2
  Else If(S='SP')or(S='ES')Then Lang:=3
  Else If S='IT'Then Lang:=4;
End;

Function Msg(Id:Integer):String;
Begin
 Msg:=MsgTab[Id,Lang];
End;

Function Fmt(Id:Integer;Const A,B,C,D:String):String;
Var
 S,R:String;
 I:Integer;
Begin
 S:=Msg(Id);
 R:='';
 I:=1;
 While I<=Length(S)do Begin
  If(S[I]='%')and(I<Length(S))and(S[I+1]in['1'..'4'])Then Begin
   Case S[I+1]of
    '1':R:=R+A;
    '2':R:=R+B;
    '3':R:=R+C;
    '4':R:=R+D;
   End;
   Inc(I,2);
  End
  Else Begin
   R:=R+S[I];
   Inc(I);
  End;
 End;
 Fmt:=R;
End;

Procedure Say(Id:Integer;Const A,B,C,D:String);Begin
 WriteLn(Fmt(Id,A,B,C,D));
End;

Procedure Die(Code:Integer;Id:Integer;Const A:String);Begin
 WriteLn(Fmt(Id,A,'','',''));
 Halt(Code);
End;

Procedure Help;
Var
 I:Integer;
Begin
 For I:=M_H00 to M_H00+25-1 do WriteLn(Msg(I));
End;

{ ---- Chemins et noms ---- }

Function NormPath(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do
  If(S[I]='/')or(S[I]='\')Then S[I]:=HSep;
 NormPath:=S;
End;

Function IsAbs(Const S:String):Boolean;Begin
 IsAbs:=(S<>'')and((S[1]=HSep)or((Length(S)>1)and(S[2]=':')));
End;

Function WithSep(S:String):String;Begin
 If(S<>'')and(S[Length(S)]<>HSep)and(S[Length(S)]<>':')Then S:=S+HSep;
 WithSep:=S;
End;

{ Chemin d'un parametre : relatif au manifeste s'il en vient }
Function Resolve(Const S:String):String;
Var
 P:String;
Begin
 P:=NormPath(S);
 If(BaseDir<>'')and(P<>'')and(Not IsAbs(P))Then P:=BaseDir+P;
 Resolve:=P;
End;

Function DirPart(Const S:String):String;
Var
 I:Integer;
Begin
 I:=Length(S);
 While(I>0)and(S[I]<>HSep)and(S[I]<>':')do Dec(I);
 DirPart:=Copy(S,1,I);
End;

Function FileFound(Const Name:String):Boolean;
Var
 SR:SearchRec;
Begin
 FindFirst(Name,AnyFile,SR);
 FileFound:=DosError=0;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
End;

Function IsFolder(S:String):Boolean;
Var
 SR:SearchRec;
Begin
 While(Length(S)>1)and(S[Length(S)]=HSep)do Dec(S[0]);
 FindFirst(S,AnyFile,SR);
 IsFolder:=(DosError=0)and((SR.Attr and Directory)<>0);
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
End;

Function WildMatch(Const P,S:String;PI,SI:Integer):Boolean;
Var
 K:Integer;
Begin
 While(PI<=Length(P))and(P[PI]<>'*')do Begin
  If SI>Length(S)Then Begin
   WildMatch:=False;
   Exit;
  End;
  If(P[PI]<>'?')and(P[PI]<>S[SI])Then Begin
   WildMatch:=False;
   Exit;
  End;
  Inc(PI);
  Inc(SI);
 End;
 If PI>Length(P)Then WildMatch:=SI>Length(S)
 Else Begin
  WildMatch:=False;
  For K:=SI to Length(S)+1 do
   If WildMatch(P,S,PI+1,K)Then Begin
    WildMatch:=True;
    Exit;
   End;
 End;
End;

{ Un masque (ou plusieurs separes par des virgules) correspond-il ? }
Function MatchAny(Const List,Name:String):Boolean;
Var
 L,M:String;
 P:Integer;
 R:Boolean;
Begin
 R:=False;
 L:=UpStr(List);
 While(L<>'')and(Not R)do Begin
  P:=Pos(',',L);
  If P=0 Then Begin
   M:=L;
   L:='';
  End
  Else Begin
   M:=Copy(L,1,P-1);
   L:=Copy(L,P+1,255);
  End;
  If M='*.*' Then M:='*';
  If(M<>'')and WildMatch(M,UpStr(Name),1,1)Then R:=True;
 End;
 MatchAny:=R;
End;

Function ValidCh(C:Char):Boolean;Begin
 ValidCh:=(C in['A'..'Z','0'..'9'])or(C in['!','#','$','%','&','''','(',
          ')','-','@','^','_','`','{','}','~']);
End;

{ Nom 8.3 sur 11 caracteres ; Chg = le nom a du etre modifie }
Function Make83(Const Orig:String;Var N11:String;Var Chg:Boolean):Boolean;
Var
 U,B,E:String;
 P,I:Integer;
Begin
 U:=UpStr(Orig);
 P:=0;
 For I:=1 to Length(U)do
  If U[I]='.' Then P:=I;
 If P=0 Then Begin
  B:=U;
  E:='';
 End
 Else Begin
  B:=Copy(U,1,P-1);
  E:=Copy(U,P+1,255);
 End;
 Chg:=False;
 For I:=Length(B)downto 1 do
  If Not ValidCh(B[I])Then Begin
   Chg:=True;
   If B[I]=' ' Then Delete(B,I,1)Else B[I]:='_';
  End;
 For I:=Length(E)downto 1 do
  If Not ValidCh(E[I])Then Begin
   Chg:=True;
   If E[I]=' ' Then Delete(E,I,1)Else E[I]:='_';
  End;
 If Length(B)>8 Then Begin
  B:=Copy(B,1,8);
  Chg:=True;
 End;
 If Length(E)>3 Then Begin
  E:=Copy(E,1,3);
  Chg:=True;
 End;
 If B='' Then Begin
  Make83:=False;
  Exit;
 End;
 While Length(B)<8 do B:=B+' ';
 While Length(E)<3 do E:=E+' ';
 N11:=B+E;
 Make83:=True;
End;

{ NOM EXT sur 11 caracteres -> NOM.EXT }
Function DispName(Const N:String):String;
Var
 B,E:String;
Begin
 B:=Copy(N,1,8);
 E:=Copy(N,9,3);
 While(B<>'')and(B[Length(B)]=' ')do Dec(B[0]);
 While(E<>'')and(E[Length(E)]=' ')do Dec(E[0]);
 If E<>'' Then DispName:=B+'.'+E Else DispName:=B;
End;

{ ---- Liste des fichiers et des dossiers ---- }

Function FindEnt(D:Integer;Const N11:String):Integer;
Var
 I:Integer;
Begin
 FindEnt:=0;
 For I:=1 to EntCnt do
  If(Ents[I]^.DIdx=D)and(Ents[I]^.N11=N11)Then FindEnt:=I;
End;

Function FindDir(Par:Integer;Const N11:String):Integer;
Var
 I:Integer;
Begin
 FindDir:=-1;
 For I:=1 to DirCnt-1 do
  If(Dirs[I].Parent=Par)and(Dirs[I].N11=N11)Then FindDir:=I;
End;

{ Sous-dossier de Par (cree au besoin) ; -1 si impossible }
Function SubDir(Par:Integer;Const Orig:String):Integer;
Var
 N11:String;
 Chg:Boolean;
 D:Integer;
Begin
 SubDir:=-1;
 If Not Make83(Orig,N11,Chg)Then Begin
  Say(M_wSkip,Orig,'','','');
  Exit;
 End;
 D:=FindDir(Par,N11);
 If D<0 Then Begin
  If DirCnt>MaxDir Then Begin
   Say(M_eTooDirs,NumStr(MaxDir),'','','');
   Halt(2);
  End;
  D:=DirCnt;
  Inc(DirCnt);
  FillChar(Dirs[D],SizeOf(Dirs[D]),0);
  Dirs[D].N11:=N11;
  Dirs[D].Parent:=Par;
  Dirs[D].Path:=Dirs[Par].Path+'\'+DispName(N11);
 End;
 SubDir:=D;
End;

{ Dossier correspondant a un chemin de l'image (\USR\BIN) }
Function DirFromPath(S:String):Integer;
Var
 D,P:Integer;
 C:String;
Begin
 D:=0;
 S:=UpStr(S);
 For P:=1 to Length(S)do
  If S[P]='/' Then S[P]:='\';
 While(D>=0)and(S<>'')do Begin
  P:=Pos('\',S);
  If P=0 Then Begin
   C:=S;
   S:='';
  End
  Else Begin
   C:=Copy(S,1,P-1);
   S:=Copy(S,P+1,255);
  End;
  If C<>'' Then D:=SubDir(D,C);
 End;
 DirFromPath:=D;
End;

{ Ajoute (ou remplace) un fichier ; retourne son numero ou 0 }
Function AddFile(Const Src,Orig:String;D:Integer;Size:LongInt):Integer;
Var
 N11,T,A:String;
 Chg:Boolean;
 E,K:Integer;
Begin
 AddFile:=0;
 If Not Make83(Orig,N11,Chg)Then Begin
  Say(M_wSkip,Orig,'','','');
  Exit;
 End;
 If FindDir(D,N11)>=0 Then Begin
  Say(M_wSkip,Orig,'','','');
  Exit;
 End;
 E:=FindEnt(D,N11);
 If(E>0)and Chg Then Begin
  { collision de noms tronques : suffixe ~N }
  K:=1;
  Repeat
   A:=NumStr(K);
   T:=Copy(N11,1,7-Length(A))+'~'+A;
   While Length(T)<8 do T:=T+' ';
   T:=T+Copy(N11,9,3);
   Inc(K);
  Until(FindEnt(D,T)=0)or(K>9);
  If FindEnt(D,T)<>0 Then Begin
   Say(M_wSkip,Orig,'','','');
   Exit;
  End;
  N11:=T;
  E:=0;
 End;
 If Chg Then
  Say(M_wName83,Orig,DispName(N11),'','');
 If E=0 Then Begin
  If EntCnt>=MaxEnt Then Begin
   Say(M_eTooMany,NumStr(MaxEnt),'','','');
   Halt(2);
  End;
  Inc(EntCnt);
  E:=EntCnt;
  New(Ents[E]);
  FillChar(Ents[E]^,SizeOf(TEnt),0);
  Ents[E]^.N11:=N11;
  Ents[E]^.DIdx:=D;
  Ents[E]^.Attr:=$20;
  Ents[E]^.Disk:=-1;
 End;
 Ents[E]^.Src:=Src;
 Ents[E]^.Size:=Size;
 AddFile:=E;
End;

{ Copie recursivement (ou non) un dossier source dans le dossier D de
  l'image ; Msk = masques ; retourne le nombre de fichiers ajoutes }
Function AddTree(Const SrcDir:String;D:Integer;Const Msk:String;
                 Recurse,Forced:Boolean):Integer;
Var
 SR:SearchRec;
 Cnt,E,Sub:Integer;
Begin
 Cnt:=0;
 FindFirst(WithSep(SrcDir)+AllMask,AnyFile,SR);
 While DosError=0 do Begin
  If(SR.Name<>'')and(SR.Name[1]<>'.')Then Begin
   If(SR.Attr and Directory)<>0 Then Begin
    If Recurse Then Begin
     Sub:=SubDir(D,SR.Name);
     If Sub>=0 Then
      Cnt:=Cnt+AddTree(WithSep(SrcDir)+SR.Name,Sub,Msk,True,Forced);
    End;
   End
   Else If(SR.Attr and VolumeID)=0 Then
    If(Msk='')or MatchAny(Msk,SR.Name)Then Begin
     E:=AddFile(WithSep(SrcDir)+SR.Name,SR.Name,D,SR.Size);
     If E>0 Then Begin
      If Forced Then Ents[E]^.Boot:=True;
      Inc(Cnt);
     End;
    End;
  End;
  FindNext(SR);
 End;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
 AddTree:=Cnt;
End;

{ /ADD:source=destination }
Procedure DoAdd(Const SrcIn,DstIn:String);
Var
 Src,Dst,Nm,Msk,Dp:String;
 SR:SearchRec;
 D,E,I,Cnt:Integer;
 AsDir:Boolean;
Begin
 Src:=NormPath(SrcIn);
 Dst:=UpStr(DstIn);
 For I:=1 to Length(Dst)do
  If Dst[I]='/' Then Dst[I]:='\';
 AsDir:=(Dst='')or(Dst[Length(Dst)]='\');
 Cnt:=0;
 Nm:=Src;
 Dp:=DirPart(Src);
 Nm:=Copy(Src,Length(Dp)+1,255);
 If(Pos('*',Nm)>0)or(Pos('?',Nm)>0)Then Begin
  D:=DirFromPath(Dst);
  If D>=0 Then Cnt:=AddTree(Dp,D,Nm,False,False);
 End
 Else If IsFolder(Src)Then Begin
  D:=DirFromPath(Dst);
  If D>=0 Then Cnt:=AddTree(Src,D,'',True,False);
 End
 Else Begin
  FindFirst(Src,AnyFile,SR);
  If DosError=0 Then Begin
   If AsDir Then Begin
    D:=DirFromPath(Dst);
    Msk:=Nm;
   End
   Else Begin
    I:=Length(Dst);
    While(I>0)and(Dst[I]<>'\')do Dec(I);
    D:=DirFromPath(Copy(Dst,1,I));
    Msk:=Copy(Dst,I+1,255);
   End;
   If D>=0 Then Begin
    E:=AddFile(Src,Msk,D,SR.Size);
    If E>0 Then Cnt:=1;
   End;
  End;
  {$IFDEF FPC}
  FindClose(SR);
  {$ENDIF}
 End;
 If Cnt=0 Then Say(M_wNoMatch,SrcIn,'','','');
End;

{ Tri des entrees par dossier puis par nom }
Function EntKey(E:Integer):String;Begin
 EntKey:=Dirs[Ents[E]^.DIdx].Path+'\'+Ents[E]^.N11;
End;

Procedure SortEnts;
Var
 I,J:Integer;
 T:PEnt;
Begin
 For I:=2 to EntCnt do Begin
  T:=Ents[I];
  J:=I-1;
  While(J>=1)and(EntKey(J)>Dirs[T^.DIdx].Path+'\'+T^.N11)do Begin
   Ents[J+1]:=Ents[J];
   Dec(J);
  End;
  Ents[J+1]:=T;
 End;
End;

Function EntPath(E:Integer):String;Begin
 EntPath:=Dirs[Ents[E]^.DIdx].Path+'\'+DispName(Ents[E]^.N11);
End;

{ ---- Geometrie ---- }

Function ClustersOf(Size:LongInt;Cb:LongInt):LongInt;Begin
 ClustersOf:=(Size+Cb-1)div Cb;
End;

Function FloppyGeom(KB:Word;Var G:TGeom):Boolean;
Var
 Rs:LongInt;
Begin
 FloppyGeom:=True;
 FillChar(G,SizeOf(G),0);
 G.Bits:=12;
 Case KB of
  160:Begin G.Media:=$FE;G.Heads:=1;G.Spt:=8;G.Total:=320;G.Spc:=1;
       G.Root:=64;G.Spf:=1;End;
  180:Begin G.Media:=$FC;G.Heads:=1;G.Spt:=9;G.Total:=360;G.Spc:=1;
       G.Root:=64;G.Spf:=2;End;
  320:Begin G.Media:=$FF;G.Heads:=2;G.Spt:=8;G.Total:=640;G.Spc:=2;
       G.Root:=112;G.Spf:=1;End;
  360:Begin G.Media:=$FD;G.Heads:=2;G.Spt:=9;G.Total:=720;G.Spc:=2;
       G.Root:=112;G.Spf:=2;End;
  720:Begin G.Media:=$F9;G.Heads:=2;G.Spt:=9;G.Total:=1440;G.Spc:=2;
       G.Root:=112;G.Spf:=3;End;
  1200:Begin G.Media:=$F9;G.Heads:=2;G.Spt:=15;G.Total:=2400;G.Spc:=1;
       G.Root:=224;G.Spf:=7;End;
  1440:Begin G.Media:=$F0;G.Heads:=2;G.Spt:=18;G.Total:=2880;G.Spc:=1;
       G.Root:=224;G.Spf:=9;End;
  2880:Begin G.Media:=$F0;G.Heads:=2;G.Spt:=36;G.Total:=5760;G.Spc:=2;
       G.Root:=240;G.Spf:=9;End;
 Else
  FloppyGeom:=False;
  Exit;
 End;
 Rs:=(LongInt(G.Root)*32+511)div 512;
 G.ImgSecs:=G.Total;
 G.Clusters:=(G.Total-1-2*LongInt(G.Spf)-Rs)div G.Spc;
 G.Drive:=0;
End;

Function FatSecs(Bits:Byte;Clusters:LongInt):LongInt;
Var
 B:LongInt;
Begin
 If Bits=12 Then B:=((Clusters+2)*3+1)div 2
  Else B:=(Clusters+2)*2;
 FatSecs:=(B+511)div 512;
End;

{ Disposition FAT d'un volume de T secteurs ; False si impossible }
Function Layout(Bits:Byte;Var G:TGeom):Boolean;
Var
 Spc,Spf,Rs,Cl,MaxCl:LongInt;
 Ok:Boolean;
Begin
 Layout:=False;
 Rs:=(LongInt(G.Root)*32+511)div 512;
 If Bits=12 Then MaxCl:=4084 Else MaxCl:=32700;
 Spc:=1;
 Ok:=False;
 While(Spc<=64)and(Not Ok)do Begin
  Spf:=1;
  While(Spf<1024)and(FatSecs(Bits,(G.Total-1-Rs-2*Spf)div Spc)>Spf)do
   Inc(Spf);
  Cl:=(G.Total-1-Rs-2*Spf)div Spc;
  If Cl<=MaxCl Then Ok:=True
   Else Spc:=Spc*2;
 End;
 If(Not Ok)or(Cl<1)Then Exit;
 If(Bits=16)and(Cl<4085)Then Exit;
 G.Bits:=Bits;
 G.Spc:=Spc;
 G.Spf:=Spf;
 G.Clusters:=Cl;
 Layout:=True;
End;

Function HardGeom(MB:Word;Force:Byte;Var G:TGeom):Boolean;
Var
 Cyls:LongInt;
 H:Word;
Begin
 HardGeom:=False;
 FillChar(G,SizeOf(G),0);
 G.ImgSecs:=LongInt(MB)*2048;
 G.Spt:=63;
 H:=16;
 Cyls:=G.ImgSecs div(LongInt(H)*63);
 While(Cyls>1024)and(H<128)do Begin
  H:=H*2;
  Cyls:=G.ImgSecs div(LongInt(H)*63);
 End;
 G.Heads:=H;
 G.Hidden:=63;
 G.Total:=Cyls*H*63-63;
 G.Root:=512;
 G.Media:=$F8;
 G.Drive:=$80;
 If Force=12 Then HardGeom:=Layout(12,G)
 Else If Force=16 Then HardGeom:=Layout(16,G)
 Else Begin
  HardGeom:=Layout(16,G);
  If G.Bits=0 Then HardGeom:=Layout(12,G);
 End;
End;

{ ---- Ecriture de l'image ---- }

Function ImgPut(Ps:LongInt;Var Buf;N:Word):Boolean;
Var
 W:Word;
Begin
 ImgPut:=False;
 Seek(Img,Ps);
 If IOResult<>0 Then Exit;
 BlockWrite(Img,Buf,N,W);
 ImgPut:=(IOResult=0)and(W=N);
End;

Function ZeroFill(Bytes:LongInt):Boolean;
Var
 N:Word;
 W:Word;
Begin
 ZeroFill:=False;
 While Bytes>0 do Begin
  If Bytes>CopySize Then N:=CopySize Else N:=Word(Bytes);
  BlockWrite(Img,ZBuf^,N,W);
  If(IOResult<>0)or(W<>N)Then Exit;
  Bytes:=Bytes-N;
 End;
 ZeroFill:=True;
End;

{ Copie le fichier E a la position Ps de l'image (ou de l'ISO) }
Function CopyIn(E:Integer;Ps:LongInt):Boolean;
Var
 F:File;
 Got:Word;
 Done:LongInt;
 Ok:Boolean;
 Ph:String;
Begin
 CopyIn:=False;
 If Ents[E]^.Src='' Then Begin
  Ph:=MsdosSys;
  Move(Ph[1],CBuf^,Length(Ph));
  If Not ImgPut(Ps,CBuf^,Length(Ph))Then Begin
   Say(M_eWrite,'MSDOS.SYS','','','');
   Exit;
  End;
  CopyIn:=True;
  Exit;
 End;
 Assign(F,Ents[E]^.Src);
 FileMode:=0;
 Reset(F,1);
 If IOResult<>0 Then Begin
  Say(M_eRead,Ents[E]^.Src,'','','');
  Exit;
 End;
 Done:=0;
 Ok:=True;
 Repeat
  BlockRead(F,CBuf^,CopySize,Got);
  If IOResult<>0 Then Begin
   Say(M_eRead,Ents[E]^.Src,'','','');
   Ok:=False;
   Got:=0;
  End
  Else If Got>0 Then Begin
   If Not ImgPut(Ps+Done,CBuf^,Got)Then Begin
    Say(M_eWrite,Ents[E]^.Src,'','','');
    Ok:=False;
    Got:=0;
   End;
   Done:=Done+Got;
  End;
 Until Got=0;
 Close(F);
 If IOResult<>0 Then Ok:=False;
 If Ok and(Done<>Ents[E]^.Size)Then Begin
  Say(M_eSrcSize,Ents[E]^.Src,'','','');
  Ok:=False;
 End;
 CopyIn:=Ok;
End;

{ ---- Choix des fichiers d'une image et dossiers utilises ---- }

{ Sel >= 0 : disquette Sel ; Sel = -1 : tous les fichiers }
Function Matches(E,Sel:Integer):Boolean;Begin
 If Sel<0 Then Matches:=True
  Else Matches:=Ents[E]^.Disk=Sel;
End;

Procedure MarkUsed(D:Integer);Begin
 While(D<>0)and(Not Dirs[D].Used)do Begin
  Dirs[D].Used:=True;
  Inc(Dirs[Dirs[D].Parent].Cnt);
  D:=Dirs[D].Parent;
 End;
End;

Procedure ComputeUsed(Sel:Integer);
Var
 I:Integer;
Begin
 For I:=0 to DirCnt-1 do Begin
  Dirs[I].Used:=False;
  Dirs[I].Cnt:=0;
  Dirs[I].Clu:=0;
  Dirs[I].NClu:=0;
 End;
 For I:=1 to EntCnt do
  If Matches(I,Sel)Then Begin
   Inc(Dirs[Ents[I]^.DIdx].Cnt);
   MarkUsed(Ents[I]^.DIdx);
  End;
 If Sel<=0 Then
  For I:=1 to DirCnt-1 do
   If Dirs[I].Keep Then MarkUsed(I);
End;

Function KidKey(K:Integer):String;Begin
 If K>0 Then KidKey:=Ents[K]^.N11
  Else KidKey:=Dirs[-K].N11;
End;

{ Contenu trie de chaque dossier utilise : K>0 fichier, K<0 sous-dossier }
Procedure BuildKids(Sel:Integer);
Var
 X,I,J,K:Integer;
 Key:String;
Begin
 For X:=0 to DirCnt-1 do Begin
  If KidP[X]=Nil Then New(KidP[X]);
  KidN[X]:=0;
  If(X=0)or Dirs[X].Used Then Begin
   For I:=1 to EntCnt do
    If Matches(I,Sel)and(Ents[I]^.DIdx=X)Then Begin
     If KidN[X]>=MaxKid Then Die(2,M_eDirBig,Dirs[X].Path);
     KidP[X]^[KidN[X]]:=I;
     Inc(KidN[X]);
    End;
   For I:=1 to DirCnt-1 do
    If Dirs[I].Used and(Dirs[I].Parent=X)Then Begin
     If KidN[X]>=MaxKid Then Die(2,M_eDirBig,Dirs[X].Path);
     KidP[X]^[KidN[X]]:=-I;
     Inc(KidN[X]);
    End;
   For I:=1 to KidN[X]-1 do Begin
    K:=KidP[X]^[I];
    Key:=KidKey(K);
    J:=I-1;
    While(J>=0)and(KidKey(KidP[X]^[J])>Key)do Begin
     KidP[X]^[J+1]:=KidP[X]^[J];
     Dec(J);
    End;
    KidP[X]^[J+1]:=K;
   End;
  End;
 End;
End;

{ ---- FAT ---- }

Var
 Fat:PBytes;

Procedure SetFat(N:Word;V:Word);
Var
 I:LongInt;
Begin
 If FG.Bits=12 Then Begin
  I:=LongInt(N)+LongInt(N)shr 1;
  If(N and 1)=0 Then Begin
   Fat^[I]:=Byte(V and $FF);
   Fat^[I+1]:=(Fat^[I+1]and $F0)or Byte((V shr 8)and $0F);
  End
  Else Begin
   Fat^[I]:=(Fat^[I]and $0F)or Byte((V and $0F)shl 4);
   Fat^[I+1]:=Byte((V shr 4)and $FF);
  End;
 End
 Else Begin
  I:=LongInt(N)*2;
  Fat^[I]:=Byte(V and $FF);
  Fat^[I+1]:=Byte(V shr 8);
 End;
End;

Procedure Chain(First:Word;N:LongInt);
Var
 C:Word;
 Eoc:Word;
Begin
 If FG.Bits=12 Then Eoc:=$FFF Else Eoc:=$FFFF;
 C:=First;
 While N>1 do Begin
  SetFat(C,C+1);
  Inc(C);
  Dec(N);
 End;
 If N=1 Then SetFat(C,Eoc);
End;

{ Mise a zero d'un tampon (FillChar est evite : certains compilateurs
  traitent mal les longueurs superieures a 32767) }
Procedure ZeroMem(Var B;N:Word);
Var
 I:Word;
Begin
 I:=0;
 While I<N do Begin
  TBytes(B)[I]:=0;
  Inc(I);
 End;
End;

Procedure PutW(Var B;O:Word;V:Word);Begin
 TBytes(B)[O]:=Byte(V and $FF);
 TBytes(B)[O+1]:=Byte(V shr 8);
End;

Procedure PutL(Var B;O:Word;V:LongInt);Begin
 PutW(B,O,Word(V and $FFFF));
 PutW(B,O+2,Word((V shr 16)and $FFFF));
End;

Procedure ClearBytes(Var B;O,N:Word);
Var
 I:Word;
Begin
 For I:=O to O+N-1 do TBytes(B)[I]:=0;
End;

Procedure PutName(Var B;O:Word;Const S:String;Len:Word);
Var
 I:Word;
Begin
 For I:=0 to Len-1 do
  If I<Length(S)Then TBytes(B)[O+I]:=Ord(S[I+1])
   Else TBytes(B)[O+I]:=32;
End;

{ Entree de repertoire FAT de 32 octets }
Procedure PutEntry(Var B;O:Word;Const N11:String;Attr:Byte;Clu:Word;
                   Size:LongInt);
Begin
 ClearBytes(B,O,32);
 PutName(B,O,N11,11);
 TBytes(B)[O+11]:=Attr;
 PutW(B,O+22,DTime);
 PutW(B,O+24,DDate);
 PutW(B,O+26,Clu);
 PutL(B,O+28,Size);
End;

{ Secteur de boot MS-DOS 6.22 generique (cherche IO.SYS et MSDOS.SYS comme
  deux premieres entrees de la racine, charge IO.SYS contigu en 0070:0000) }
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

Procedure MakeBoot(Var B;Serial:LongInt;Const Lbl:String);
Var
 FS:String[8];
Begin
 Move(BootCode,B,512);
 PutName(B,3,'MSDOS5.0',8);
 PutW(B,11,512);
 TBytes(B)[13]:=FG.Spc;
 PutW(B,14,1);
 TBytes(B)[16]:=2;
 PutW(B,17,FG.Root);
 If FG.Total<65536 Then PutW(B,19,Word(FG.Total))Else PutW(B,19,0);
 TBytes(B)[21]:=FG.Media;
 PutW(B,22,FG.Spf);
 PutW(B,24,FG.Spt);
 PutW(B,26,FG.Heads);
 PutL(B,28,FG.Hidden);
 If FG.Total<65536 Then PutL(B,32,0)Else PutL(B,32,FG.Total);
 TBytes(B)[36]:=FG.Drive;
 TBytes(B)[37]:=0;
 TBytes(B)[38]:=$29;
 PutL(B,39,Serial);
 PutName(B,43,Lbl,11);
 If FG.Bits=12 Then FS:='FAT12' Else FS:='FAT16';
 PutName(B,54,FS,8);
 TBytes(B)[510]:=$55;
 TBytes(B)[511]:=$AA;
End;

{ Secteur CHS d'une partition : octets tete, secteur+cyl haut, cyl bas }
Procedure PutChs(Var B;O:Word;Lba:LongInt);
Var
 C,H,S:LongInt;
Begin
 C:=Lba div(LongInt(FG.Heads)*FG.Spt);
 H:=(Lba div FG.Spt)mod FG.Heads;
 S:=Lba mod FG.Spt+1;
 If C>1023 Then Begin
  C:=1023;
  H:=FG.Heads-1;
  S:=FG.Spt;
 End;
 TBytes(B)[O]:=Byte(H);
 TBytes(B)[O+1]:=Byte(S or((C shr 8)shl 6));
 TBytes(B)[O+2]:=Byte(C and $FF);
End;

Function ClBytes:LongInt;Begin
 ClBytes:=LongInt(FG.Spc)*512;
End;

Function SizeKB(N:LongInt):LongInt;Begin
 SizeKB:=(N+1023)div 1024;
End;

{ Construit l'image FAT : Sel = disquette (>=0) ou -1 pour tout ; Disk
  designe le numero de disquette pour l'etiquette }
Function BuildFat(Sel:Integer;Const FName:String;Disk:Integer;
                  Var NFiles:Integer;Var FreeKB:LongInt):Boolean;
Var
 I,J,K,X,Pass,Idx:Integer;
 Next,Cb,FatBytes,VolOfs,Ps,N:LongInt;
 Nc:Word;
 Serial:LongInt;
 Lbl:String;
 Rb:PBytes;
 Db:Array[0..MaxDir]of PBytes;
 Ok:Boolean;
Begin
 BuildFat:=False;
 NFiles:=0;
 Cb:=ClBytes;
 ComputeUsed(Sel);
 BuildKids(Sel);
 { allocation : IO.SYS, MSDOS.SYS, dossiers, puis les autres fichiers }
 Next:=2;
 For Pass:=1 to 2 do
  For I:=1 to EntCnt do
   If Matches(I,Sel)and(Ents[I]^.Sys=Pass)Then Begin
    Ents[I]^.Clu:=Next;
    Next:=Next+ClustersOf(Ents[I]^.Size,Cb);
   End;
 For X:=1 to DirCnt-1 do
  If Dirs[X].Used Then Begin
   Dirs[X].NClu:=Word(ClustersOf((LongInt(Dirs[X].Cnt)+2)*32,Cb));
   If LongInt(Dirs[X].NClu)*Cb>65000 Then Die(2,M_eDirBig,Dirs[X].Path);
   Dirs[X].Clu:=Word(Next);
   Next:=Next+Dirs[X].NClu;
  End;
 For I:=1 to EntCnt do
  If Matches(I,Sel)Then Begin
   Inc(NFiles);
   If Ents[I]^.Sys=0 Then Begin
    If Ents[I]^.Size>0 Then Ents[I]^.Clu:=Word(Next)Else Ents[I]^.Clu:=0;
    Next:=Next+ClustersOf(Ents[I]^.Size,Cb);
   End;
  End;
 If Next-2>FG.Clusters Then Begin
  Say(M_eHdFit,NumStr(FG.ImgSecs div 2048),'','','');
  Halt(4);
 End;
 If Dirs[0].Cnt+1>FG.Root Then Begin
  Say(M_eDirBig,'\','','','');
  Halt(4);
 End;
 If Verbose Then
  Say(M_iFat,NumStr(FG.Bits),NumStr(FG.Total),NumStr(FG.Clusters),
      NumStr(FG.Spc));
 { FAT en memoire }
 If FG.Bits=12 Then FatBytes:=((FG.Clusters+2)*3+1)div 2
  Else FatBytes:=(FG.Clusters+2)*2;
 GetMem(Fat,Word(FatBytes+4));
 ZeroMem(Fat^,Word(FatBytes+4));
 Fat^[0]:=FG.Media;
 Fat^[1]:=$FF;
 Fat^[2]:=$FF;
 If FG.Bits=16 Then Fat^[3]:=$FF;
 For I:=1 to EntCnt do
  If Matches(I,Sel)and(Ents[I]^.Size>0)Then
   Chain(Ents[I]^.Clu,ClustersOf(Ents[I]^.Size,Cb));
 For X:=1 to DirCnt-1 do
  If Dirs[X].Used Then Chain(Dirs[X].Clu,Dirs[X].NClu);
 { repertoires }
 Lbl:=VolLabel;
 If Disk>0 Then Begin
  If Length(Lbl)>9 Then Lbl:=Copy(Lbl,1,9);
  Lbl:=Lbl+'_'+Chr(65+Disk);
 End;
 N:=LongInt(FG.Root)*32;
 GetMem(Rb,Word(N));
 ZeroMem(Rb^,Word(N));
 Db[0]:=Rb;
 For X:=1 to DirCnt-1 do
  If Dirs[X].Used Then Begin
   N:=LongInt(Dirs[X].NClu)*Cb;
   GetMem(Db[X],Word(N));
   ZeroMem(Db[X]^,Word(N));
  End
  Else Db[X]:=Nil;
 For X:=0 to DirCnt-1 do
  If(X=0)or Dirs[X].Used Then Begin
   Idx:=0;
   If X=0 Then Begin
    For Pass:=1 to 2 do
     For I:=1 to EntCnt do
      If Matches(I,Sel)and(Ents[I]^.Sys=Pass)Then Begin
       PutEntry(Db[0]^,Word(Idx)*32,Ents[I]^.N11,Ents[I]^.Attr,Ents[I]^.Clu,
                Ents[I]^.Size);
       Inc(Idx);
      End;
    If Lbl<>'' Then Begin
     PutEntry(Db[0]^,Word(Idx)*32,Lbl,$08,0,0);
     Inc(Idx);
    End;
   End
   Else Begin
    PutEntry(Db[X]^,0,'.          ',$10,Dirs[X].Clu,0);
    If Dirs[X].Parent=0 Then Nc:=0 Else Nc:=Dirs[Dirs[X].Parent].Clu;
    PutEntry(Db[X]^,32,'..         ',$10,Nc,0);
    Idx:=2;
   End;
   For K:=0 to KidN[X]-1 do Begin
    J:=KidP[X]^[K];
    If J>0 Then Begin
     If Ents[J]^.Sys=0 Then Begin
      PutEntry(Db[X]^,Word(Idx)*32,Ents[J]^.N11,Ents[J]^.Attr,Ents[J]^.Clu,
               Ents[J]^.Size);
      Inc(Idx);
     End;
    End
    Else Begin
     PutEntry(Db[X]^,Word(Idx)*32,Dirs[-J].N11,$10,Dirs[-J].Clu,0);
     Inc(Idx);
    End;
   End;
  End;
 { fichier image }
 Ok:=False;
 Assign(Img,FName);
 Rewrite(Img,1);
 If IOResult<>0 Then Say(M_eCreate,FName,'','','')
 Else If Not ZeroFill(FG.ImgSecs*512)Then Say(M_eWrite,FName,'','','')
 Else Begin
  Ok:=True;
  VolOfs:=FG.Hidden*512;
  Serial:=(LongInt(DDate)shl 16)xor LongInt(DTime)xor(LongInt(Disk)*$1111);
  If FG.Hidden>0 Then Begin
   FillChar(Sec,512,0);
   Move(MbrCode,Sec,SizeOf(MbrCode));
   Sec[$1BE]:=$80;
   PutChs(Sec,$1BF,FG.Hidden);
   If FG.Bits=12 Then Sec[$1C2]:=$01
    Else If FG.Total<65536 Then Sec[$1C2]:=$04
    Else Sec[$1C2]:=$06;
   PutChs(Sec,$1C3,FG.Hidden+FG.Total-1);
   PutL(Sec,$1C6,FG.Hidden);
   PutL(Sec,$1CA,FG.Total);
   Sec[510]:=$55;
   Sec[511]:=$AA;
   Ok:=ImgPut(0,Sec,512);
  End;
  MakeBoot(Sec,Serial,Lbl);
  If Ok Then Ok:=ImgPut(VolOfs,Sec,512);
  For I:=0 to 1 do
   If Ok Then
    Ok:=ImgPut(VolOfs+(1+LongInt(I)*FG.Spf)*512,Fat^,Word(FatBytes));
  Ps:=VolOfs+(1+2*LongInt(FG.Spf))*512;
  If Ok Then Ok:=ImgPut(Ps,Db[0]^,Word(LongInt(FG.Root)*32));
  Ps:=Ps+((LongInt(FG.Root)*32+511)div 512)*512;
  For X:=1 to DirCnt-1 do
   If Ok and Dirs[X].Used Then
    Ok:=ImgPut(Ps+(LongInt(Dirs[X].Clu)-2)*Cb,Db[X]^,
               Word(LongInt(Dirs[X].NClu)*Cb));
  For I:=1 to EntCnt do
   If Ok and Matches(I,Sel)Then Begin
    If Verbose Then Say(M_iCopy,EntPath(I),FName,'','');
    If Ents[I]^.Size>0 Then
     Ok:=CopyIn(I,Ps+(LongInt(Ents[I]^.Clu)-2)*Cb);
   End;
  Close(Img);
  If IOResult<>0 Then Ok:=False;
 End;
 { liberation dans l'ordre inverse de l'allocation }
 For X:=DirCnt-1 downto 1 do
  If Db[X]<>Nil Then FreeMem(Db[X],Word(LongInt(Dirs[X].NClu)*Cb));
 FreeMem(Rb,Word(LongInt(FG.Root)*32));
 FreeMem(Fat,Word(FatBytes+4));
 FreeKB:=(FG.Clusters-(Next-2))*Cb div 1024;
 BuildFat:=Ok;
End;

{ ---- Repartition sur les disquettes ---- }

Procedure MarkDirDisk(D,X:Integer);Begin
 While(X<>0)and(Not DPres[D][X])do Begin
  DPres[D][X]:=True;
  Inc(DCnt[D][Dirs[X].Parent]);
  X:=Dirs[X].Parent;
 End;
End;

Procedure AddToDisk(D,E:Integer);Begin
 DUse[D]:=DUse[D]+ClustersOf(Ents[E]^.Size,ClBytes);
 Inc(DCnt[D][Ents[E]^.DIdx]);
 MarkDirDisk(D,Ents[E]^.DIdx);
End;

Function DiskFits(D:Integer):Boolean;
Var
 X:Integer;
 Cl,Rsv:LongInt;
Begin
 Rsv:=ClustersOf(LongInt(FreeKB)*1024,ClBytes);
 Cl:=DUse[D]+Rsv;
 For X:=1 to DirCnt-1 do
  If DPres[D][X]Then
   Cl:=Cl+ClustersOf((LongInt(DCnt[D][X])+2)*32,ClBytes);
 DiskFits:=(Cl<=FG.Clusters)and(DCnt[D][0]+1<=FG.Root);
End;

Function TryPlace(D,E:Integer):Boolean;
Var
 SC:TCntRow;
 SP:TPresRow;
 SU:LongInt;
Begin
 SC:=DCnt[D];
 SP:=DPres[D];
 SU:=DUse[D];
 AddToDisk(D,E);
 If DiskFits(D)Then Begin
  Ents[E]^.Disk:=D;
  TryPlace:=True;
 End
 Else Begin
  DCnt[D]:=SC;
  DPres[D]:=SP;
  DUse[D]:=SU;
  TryPlace:=False;
 End;
End;

Procedure Pack;
Var
 I,D,Pass,X:Integer;
 Placed:Boolean;
Begin
 FillChar(DCnt,SizeOf(DCnt),0);
 FillChar(DPres,SizeOf(DPres),0);
 FillChar(DUse,SizeOf(DUse),0);
 DiskCnt:=1;
 For Pass:=1 to 2 do
  For I:=1 to EntCnt do
   If Ents[I]^.Sys=Pass Then Begin
    AddToDisk(0,I);
    Ents[I]^.Disk:=0;
   End;
 For X:=1 to DirCnt-1 do
  If Dirs[X].Keep Then MarkDirDisk(0,X);
 If Not DiskFits(0)Then Die(4,M_eBootFit,'');
 For I:=1 to EntCnt do
  If Ents[I]^.Boot and(Ents[I]^.Sys=0)Then
   If Not TryPlace(0,I)Then Die(4,M_eBootFit,EntPath(I));
 For I:=1 to EntCnt do
  If(Ents[I]^.Disk=-1)Then Begin
   Placed:=False;
   For D:=0 to DiskCnt-1 do
    If(Not Placed)and TryPlace(D,I)Then Placed:=True;
   If Not Placed Then Begin
    If DiskCnt>=MaxDisk Then Die(4,M_eManyDisks,NumStr(MaxDisk));
    If TryPlace(DiskCnt,I)Then Begin
     Inc(DiskCnt);
    End
    Else Begin
     Say(M_wTooBig,EntPath(I),'','','');
     Ents[I]^.Disk:=-2;
    End;
   End;
  End;
End;

{ ---- ISO 9660 + El Torito ---- }

Procedure PutLE32(Var B;O:Word;V:LongInt);Begin
 PutL(B,O,V);
End;

Procedure PutBE32(Var B;O:Word;V:LongInt);Begin
 TBytes(B)[O]:=Byte((V shr 24)and $FF);
 TBytes(B)[O+1]:=Byte((V shr 16)and $FF);
 TBytes(B)[O+2]:=Byte((V shr 8)and $FF);
 TBytes(B)[O+3]:=Byte(V and $FF);
End;

Procedure PutBoth32(Var B;O:Word;V:LongInt);Begin
 PutLE32(B,O,V);
 PutBE32(B,O+4,V);
End;

Procedure PutBoth16(Var B;O:Word;V:Word);Begin
 TBytes(B)[O]:=Byte(V and $FF);
 TBytes(B)[O+1]:=Byte(V shr 8);
 TBytes(B)[O+2]:=Byte(V shr 8);
 TBytes(B)[O+3]:=Byte(V and $FF);
End;

Function ZeroPad(N:Word;Len:Integer):String;
Var
 S:String;
Begin
 S:=NumStr(N);
 While Length(S)<Len do S:='0'+S;
 ZeroPad:=S;
End;

Procedure PutDate(Var B;O:Word);
Var
 S:String;
 I:Integer;
Begin
 S:=ZeroPad(Yr,4)+ZeroPad(Mo,2)+ZeroPad(Dy,2)+ZeroPad(Hr,2)+
    ZeroPad(Mi,2)+ZeroPad(Sc,2)+'00';
 For I:=1 to 16 do TBytes(B)[O+I-1]:=Ord(S[I]);
 TBytes(B)[O+16]:=0;
End;

Function RecLen(Const Id:String):Word;
Var
 L:Word;
Begin
 L:=33+Length(Id);
 If L and 1<>0 Then Inc(L);
 RecLen:=L;
End;

Function PutDirRec(Var B;O:Word;Extent,Size:LongInt;Flags:Byte;
                   Const Id:String):Word;
Var
 L,I:Word;
Begin
 L:=RecLen(Id);
 ClearBytes(B,O,L);
 TBytes(B)[O]:=Byte(L);
 PutBoth32(B,O+2,Extent);
 PutBoth32(B,O+10,Size);
 TBytes(B)[O+18]:=Byte(Yr-1900);
 TBytes(B)[O+19]:=Byte(Mo);
 TBytes(B)[O+20]:=Byte(Dy);
 TBytes(B)[O+21]:=Byte(Hr);
 TBytes(B)[O+22]:=Byte(Mi);
 TBytes(B)[O+23]:=Byte(Sc);
 TBytes(B)[O+25]:=Flags;
 PutBoth16(B,O+28,1);
 TBytes(B)[O+32]:=Length(Id);
 For I:=1 to Length(Id)do TBytes(B)[O+32+I]:=Ord(Id[I]);
 PutDirRec:=L;
End;

Function IsoCh(C:Char):Char;Begin
 If C in['A'..'Z','0'..'9','_']Then IsoCh:=C Else IsoCh:='_';
End;

{ Identifiant ISO 9660 niveau 1 d'une entree FAT (K>0 fichier, K<0 dossier) }
Function IsoId(K:Integer):String;
Var
 N,B,E:String;
 I:Integer;
Begin
 If K>0 Then N:=Ents[K]^.N11 Else N:=Dirs[-K].N11;
 B:=Copy(N,1,8);
 E:=Copy(N,9,3);
 While(B<>'')and(B[Length(B)]=' ')do Dec(B[0]);
 While(E<>'')and(E[Length(E)]=' ')do Dec(E[0]);
 For I:=1 to Length(B)do B[I]:=IsoCh(B[I]);
 For I:=1 to Length(E)do E[I]:=IsoCh(E[I]);
 If K<0 Then Begin
  If E<>'' Then B:=B+E;
  IsoId:=B;
 End
 Else IsoId:=B+'.'+E+';1';
End;

Procedure PutText(Var B;O:Word;Const S:String;Len:Word);Begin
 PutName(B,O,S,Len);
End;

Function WriteSec:Boolean;
Var
 W:Word;
Begin
 BlockWrite(Img,Sec,IsoSec,W);
 WriteSec:=(IOResult=0)and(W=IsoSec);
End;

Function BuildIso(Const FName,BootImg:String;BootKB:Word;
                  Var NFiles:Integer;Var TotalKB:LongInt):Boolean;
Var
 I,J,K,X,Bi,Pa:Integer;
 Pt:Array[1..MaxDir+1]of Byte;
 PtN:Integer;
 Db:Array[0..MaxDir]of PBytes;
 Ps,Cur,CatLba,Total,Sum,PtSize:LongInt;
 Q,Pass2:Integer;
 Pw:Word;
 Nm:String[16];
 L:Word;
 Ok:Boolean;
 W:Word;
 Sr:SearchRec;
 Media:Byte;
Begin
 BuildIso:=False;
 NFiles:=0;
 { image de boot = premiere disquette, presente aussi dans le CD }
 FindFirst(BootImg,AnyFile,Sr);
 If DosError<>0 Then Begin
  Say(M_eRead,BootImg,'','','');
  Exit;
 End;
 Bi:=AddFile(BootImg,'BOOT.IMG',0,Sr.Size);
 {$IFDEF FPC}
 FindClose(Sr);
 {$ENDIF}
 If Bi=0 Then Exit;
 ComputeUsed(-1);
 BuildKids(-1);
 { ordre des dossiers : largeur d'abord (table des chemins) }
 Pt[1]:=0;
 PtN:=1;
 Dirs[0].PtNum:=1;
 I:=1;
 While I<=PtN do Begin
  X:=Pt[I];
  For K:=0 to KidN[X]-1 do
   If KidP[X]^[K]<0 Then Begin
    Inc(PtN);
    Pt[PtN]:=-KidP[X]^[K];
    Dirs[Pt[PtN]].PtNum:=PtN;
   End;
  Inc(I);
 End;
 { taille des repertoires, puis adresses }
 Cur:=21;
 For I:=1 to PtN do Begin
  X:=Pt[I];
  Ps:=68;
  For K:=0 to KidN[X]-1 do Begin
   L:=RecLen(IsoId(KidP[X]^[K]));
   If(Ps mod IsoSec)+L>IsoSec Then Ps:=(Ps div IsoSec+1)*IsoSec;
   Ps:=Ps+L;
  End;
  Dirs[X].ISize:=((Ps+IsoSec-1)div IsoSec)*IsoSec;
  If Dirs[X].ISize>65000 Then Die(2,M_eDirBig,Dirs[X].Path);
  Dirs[X].Lba:=Cur;
  Cur:=Cur+Dirs[X].ISize div IsoSec;
 End;
 CatLba:=Cur;
 Inc(Cur);
 For I:=1 to PtN do Begin
  X:=Pt[I];
  For K:=0 to KidN[X]-1 do
   If KidP[X]^[K]>0 Then Begin
    J:=KidP[X]^[K];
    Ents[J]^.Lba:=Cur;
    Cur:=Cur+(Ents[J]^.Size+IsoSec-1)div IsoSec;
    Inc(NFiles);
   End;
 End;
 Total:=Cur;
 { tampons des repertoires }
 For I:=1 to PtN do Begin
  X:=Pt[I];
  GetMem(Db[X],Word(Dirs[X].ISize));
  ZeroMem(Db[X]^,Word(Dirs[X].ISize));
  If X=0 Then Pa:=0 Else Pa:=Dirs[X].Parent;
  Ps:=PutDirRec(Db[X]^,0,Dirs[X].Lba,Dirs[X].ISize,2,#0);
  Ps:=Ps+PutDirRec(Db[X]^,Word(Ps),Dirs[Pa].Lba,Dirs[Pa].ISize,2,#1);
  For K:=0 to KidN[X]-1 do Begin
   J:=KidP[X]^[K];
   L:=RecLen(IsoId(J));
   If(Ps mod IsoSec)+L>IsoSec Then Ps:=(Ps div IsoSec+1)*IsoSec;
   If J>0 Then
    Ps:=Ps+PutDirRec(Db[X]^,Word(Ps),Ents[J]^.Lba,Ents[J]^.Size,0,
                       IsoId(J))
   Else
    Ps:=Ps+PutDirRec(Db[X]^,Word(Ps),Dirs[-J].Lba,Dirs[-J].ISize,2,
                       IsoId(J));
  End;
 End;
 Ok:=False;
 Assign(Img,FName);
 Rewrite(Img,1);
 If IOResult<>0 Then Begin
  Say(M_eCreate,FName,'','','');
  Exit;
 End;
 Ok:=True;
 { secteurs 0..15 : zone systeme }
 FillChar(Sec,IsoSec,0);
 For I:=0 to 15 do
  If Ok Then Ok:=WriteSec;
 { table des chemins : taille }
 PtSize:=0;
 For I:=1 to PtN do Begin
  X:=Pt[I];
  If X=0 Then L:=1 Else L:=Length(IsoId(-X));
  PtSize:=PtSize+8+L+(L and 1);
 End;
 { 16 : descripteur de volume primaire }
 FillChar(Sec,IsoSec,0);
 Sec[0]:=1;
 PutText(Sec,1,'CD001',5);
 Sec[6]:=1;
 PutText(Sec,8,'LINUX_0',32);
 PutText(Sec,40,VolLabel,32);
 PutBoth32(Sec,80,Total);
 PutBoth16(Sec,120,1);
 PutBoth16(Sec,124,1);
 PutBoth16(Sec,128,IsoSec);
 PutBoth32(Sec,132,PtSize);
 PutLE32(Sec,140,19);
 PutBE32(Sec,148,20);
 L:=PutDirRec(Sec,156,Dirs[0].Lba,Dirs[0].ISize,2,#0);
 PutText(Sec,190,'',128);
 PutText(Sec,318,'',128);
 PutText(Sec,446,'',128);
 PutText(Sec,574,'MAKEDISK LINUX-0',128);
 PutText(Sec,702,'',37);
 PutText(Sec,739,'',37);
 PutText(Sec,776,'',37);
 PutDate(Sec,813);
 PutDate(Sec,830);
 For I:=0 to 15 do Sec[847+I]:=Ord('0');
 For I:=0 to 15 do Sec[864+I]:=Ord('0');
 Sec[881]:=1;
 If Ok Then Ok:=WriteSec;
 { 17 : enregistrement de boot El Torito }
 FillChar(Sec,IsoSec,0);
 PutText(Sec,1,'CD001',5);
 Sec[6]:=1;
 PutText(Sec,7,'EL TORITO SPECIFICATION',23);
 PutLE32(Sec,71,CatLba);
 If Ok Then Ok:=WriteSec;
 { 18 : fin des descripteurs }
 FillChar(Sec,IsoSec,0);
 Sec[0]:=255;
 PutText(Sec,1,'CD001',5);
 Sec[6]:=1;
 If Ok Then Ok:=WriteSec;
 { 19, 20 : tables des chemins (petite-extremite puis grande-extremite) }
 For Pass2:=0 to 1 do Begin
  FillChar(Sec,IsoSec,0);
  Pw:=0;
  For I:=1 to PtN do Begin
   X:=Pt[I];
   If X=0 Then Begin
    L:=1;
    Pa:=1;
   End
   Else Begin
    L:=Length(IsoId(-X));
    Pa:=Dirs[Dirs[X].Parent].PtNum;
   End;
   Sec[Pw]:=Byte(L);
   If Pass2=0 Then Begin
    PutLE32(Sec,Pw+2,Dirs[X].Lba);
    PutW(Sec,Pw+6,Word(Pa));
   End
   Else Begin
    PutBE32(Sec,Pw+2,Dirs[X].Lba);
    Sec[Pw+6]:=Byte(Pa shr 8);
    Sec[Pw+7]:=Byte(Pa and $FF);
   End;
   If X<>0 Then Begin
    Nm:=IsoId(-X);
    For Q:=1 to L do Sec[Pw+7+Q]:=Ord(Nm[Q]);
   End;
   Pw:=Pw+8+L+(L and 1);
  End;
  If Ok Then Ok:=WriteSec;
 End;
 { repertoires }
 For I:=1 to PtN do
  If Ok Then Begin
   X:=Pt[I];
   BlockWrite(Img,Db[X]^,Word(Dirs[X].ISize),W);
   Ok:=(IOResult=0)and(W=Word(Dirs[X].ISize));
  End;
 { catalogue de boot : entree de validation puis entree initiale }
 FillChar(Sec,IsoSec,0);
 Sec[0]:=1;
 PutText(Sec,4,'LINUX-0',7);
 Sec[30]:=$55;
 Sec[31]:=$AA;
 Sum:=0;
 For I:=0 to 15 do Sum:=Sum+Sec[I*2]+LongInt(Sec[I*2+1])*256;
 Sum:=(65536-(Sum mod 65536))mod 65536;
 Sec[28]:=Byte(Sum and $FF);
 Sec[29]:=Byte(Sum shr 8);
 Case BootKB of
  1200:Media:=1;
  2880:Media:=3;
 Else Media:=2;
 End;
 Sec[32]:=$88;
 Sec[33]:=Media;
 Sec[38]:=1;
 PutLE32(Sec,40,Ents[Bi]^.Lba);
 If Ok Then Ok:=WriteSec;
 { donnees des fichiers }
 For I:=1 to PtN do
  For K:=0 to KidN[Pt[I]]-1 do
   If Ok and(KidP[Pt[I]]^[K]>0)Then Begin
    J:=KidP[Pt[I]]^[K];
    If Verbose Then Say(M_iCopy,EntPath(J),FName,'','');
    Ps:=FilePos(Img);
    If Ents[J]^.Size>0 Then Begin
     Ok:=CopyIn(J,Ps);
     If Ok Then Begin
      Seek(Img,Ps+Ents[J]^.Size);
      Ok:=ZeroFill((IsoSec-(Ents[J]^.Size mod IsoSec))mod IsoSec);
     End;
    End;
   End;
 Close(Img);
 If IOResult<>0 Then Ok:=False;
 For I:=PtN downto 1 do
  FreeMem(Db[Pt[I]],Word(Dirs[Pt[I]].ISize));
 TotalKB:=Total*2;
 BuildIso:=Ok;
End;

{ ---- Options ---- }

Function ToWord(Const S:String;Var V:Word):Boolean;
Var
 L:LongInt;
 Code:Integer;
Begin
 Val(S,L,Code);
 ToWord:=(Code=0)and(L>=0)and(L<=65535);
 If(Code=0)and(L>=0)and(L<=65535)Then V:=Word(L);
End;

Function ParseDate(Const S:String):Boolean;
Var
 Y,M,D:Word;
 A,B,C:String;
Begin
 ParseDate:=False;
 A:=Copy(S,1,4);
 B:=Copy(S,6,2);
 C:=Copy(S,9,2);
 If(Length(S)<>10)or(S[5]<>'-')or(S[8]<>'-')Then Exit;
 If Not(ToWord(A,Y)and ToWord(B,M)and ToWord(C,D))Then Exit;
 If(Y<1980)or(Y>2099)or(M<1)or(M>12)or(D<1)or(D>31)Then Exit;
 Yr:=Y;
 Mo:=M;
 Dy:=D;
 Hr:=0;
 Mi:=0;
 Sc:=0;
 ParseDate:=True;
End;

Function CleanLabel(Const S:String):String;
Var
 R:String;
 I:Integer;
 U:String;
Begin
 R:='';
 U:=UpStr(S);
 For I:=1 to Length(U)do
  If(ValidCh(U[I])or(U[I]=' '))and(Length(R)<11)Then R:=R+U[I];
 CleanLabel:=R;
End;

Procedure Bad(Const S:String);Begin
 Die(1,M_eBadVal,S);
End;

Procedure LoadInf(Const Name:String);Forward;

{ Une option, avec ou sans '/' initial. Retourne False si inconnue }
Function Option(S:String):Boolean;
Var
 K,V:String;
 P,I:Integer;
Begin
 Option:=True;
 If(S<>'')and((S[1]='/')or(S[1]='-'))Then Delete(S,1,1);
 P:=Pos(':',S);
 If P=0 Then Begin
  K:=UpStr(S);
  V:='';
 End
 Else Begin
  K:=UpStr(Copy(S,1,P-1));
  V:=Copy(S,P+1,255);
 End;
 If K='INF' Then LoadInf(V)
 Else If K='SYSTEM' Then SysDir:=Resolve(V)
 Else If K='CMDS' Then CmdDir:=Resolve(V)
 Else If K='MASK' Then Masks:=V
 Else If K='BINDIR' Then BinDir:=UpStr(V)
 Else If K='OUT' Then OutDir:=Resolve(V)
 Else If K='NAME' Then BaseName:=UpStr(V)
 Else If K='LABEL' Then VolLabel:=CleanLabel(V)
 Else If K='ADD' Then Begin
  P:=Pos('=',V);
  If P=0 Then Bad(V);
  If AddCnt>=MaxAdd Then Die(1,M_eTooMany,NumStr(MaxAdd));
  Inc(AddCnt);
  AddSrc[AddCnt]:=Resolve(Copy(V,1,P-1));
  AddDst[AddCnt]:=Copy(V,P+1,255);
 End
 Else If K='DIR' Then Begin
  If MkCnt>=MaxMk Then Die(1,M_eTooMany,NumStr(MaxMk));
  Inc(MkCnt);
  MkList[MkCnt]:=V;
 End
 Else If K='BOOT' Then Begin
  If BootCnt>=MaxBoot Then Die(1,M_eTooMany,NumStr(MaxBoot));
  Inc(BootCnt);
  V:=UpStr(V);
  For I:=1 to Length(V)do
   If V[I]='/' Then V[I]:='\';
  If(V<>'')and(V[1]<>'\')Then V:='\'+V;
  BootPat[BootCnt]:=V;
 End
 Else If K='FREE' Then Begin
  If Not ToWord(V,FreeKB)Then Bad(V);
 End
 Else If K='FLOPPY' Then Begin
  If Not ToWord(V,FloppyKB)Then Bad(V);
 End
 Else If K='HD' Then Begin
  DoHard:=True;
  HardMB:=32;
  If V<>'' Then
   If(Not ToWord(V,HardMB))or(HardMB<1)or(HardMB>1000)Then
    Die(1,M_eHdSize,V);
 End
 Else If K='ISO' Then Begin
  DoIso:=True;
  If V<>'' Then IsoName:=Resolve(V);
 End
 Else If K='FAT12' Then ForceBits:=12
 Else If K='FAT16' Then ForceBits:=16
 Else If K='DATE' Then Begin
  If Not ParseDate(V)Then Die(1,M_eDate,V);
 End
 Else If K='V' Then Verbose:=True
 Else Option:=False;
End;

{ Lit un fichier texte en entier ; retourne les lignes une par une }
{ Une ligne du manifeste ou du fichier de parametres }
Procedure DoLine(L:String;IsInf:Boolean);
Var
 K,V:String;
 P:Integer;
Begin
 While(L<>'')and(L[Length(L)]in[' ',#9])do Dec(L[0]);
 While(L<>'')and(L[1]in[' ',#9])do Delete(L,1,1);
 If(L='')or(L[1]=';')or(L[1]='#')Then Exit;
 If IsInf and(L[1]<>'/')and(L[1]<>'-')Then Begin
  { ligne "MOT valeur" -> option MOT:valeur }
  P:=Pos(' ',L);
  If P=0 Then P:=Pos(#9,L);
  If P=0 Then Begin
   K:=L;
   V:='';
  End
  Else Begin
   K:=Copy(L,1,P-1);
   V:=Copy(L,P+1,255);
   While(V<>'')and(V[1]in[' ',#9])do Delete(V,1,1);
  End;
  If UpStr(K)='ADD' Then Begin
   P:=Pos(' ',V);
   If P>0 Then Begin
    L:=Copy(V,P+1,255);
    V:=Copy(V,1,P-1)+'='+L;
    While Pos(' ',V)>0 do Delete(V,Pos(' ',V),1);
   End;
  End
  Else If UpStr(K)='CMDS' Then Begin
   P:=Pos(' ',V);
   If P>0 Then Begin
    If Not Option('MASK:'+Copy(V,P+1,255))Then Bad(L);
    V:=Copy(V,1,P-1);
   End;
  End;
  L:=K+':'+V;
 End;
 If Not Option(L)Then Die(1,M_eUnkOpt,L);
End;

{ Lit un fichier texte (fins de ligne CR, LF ou CR LF) par petits blocs }
Procedure ReadLines(Const Name:String;IsInf:Boolean);
Var
 F:File;
 Blk:Array[0..255]of Byte;
 Got,I:Word;
 L:String;
Begin
 Assign(F,Name);
 FileMode:=0;
 Reset(F,1);
 If IOResult<>0 Then Begin
  If IsInf Then Die(2,M_eInf,Name);
  Die(2,M_eRead,Name);
 End;
 L:='';
 Repeat
  BlockRead(F,Blk,256,Got);
  If IOResult<>0 Then Got:=0;
  For I:=1 to Got do
   If(Blk[I-1]=10)or(Blk[I-1]=13)Then Begin
    DoLine(L,IsInf);
    L:='';
   End
   Else If Length(L)<250 Then L:=L+Chr(Blk[I-1]);
 Until Got=0;
 Close(F);
 If IOResult<>0 Then;
 DoLine(L,IsInf);
End;

Procedure LoadInf(Const Name:String);
Var
 Old,Nm:String;
Begin
 If InfDepth>0 Then Die(1,M_eBadVal,Name);
 Nm:=Resolve(Name);
 Old:=BaseDir;
 BaseDir:=DirPart(Nm);
 Inc(InfDepth);
 ReadLines(Nm,True);
 Dec(InfDepth);
 BaseDir:=Old;
End;

Procedure ReadArgs;
Var
 I:Integer;
 S:String;
Begin
 For I:=1 to ParamCount do Begin
  S:=ParamStr(I);
  If(S<>'')and(S[1]='@')Then ReadLines(Copy(S,2,255),False)
  Else If Not Option(S)Then Die(1,M_eUnkOpt,S);
 End;
End;

{ Nom de fichier : sous DOS, le nom est limite a 8 caracteres }
Function FitName(Const Base,Tail:String):String;
Var
 B:String;
Begin
 B:=Base;
 {$IFNDEF UNIX}
 If Length(B)+Length(Tail)>8 Then B:=Copy(B,1,8-Length(Tail));
 {$ENDIF}
 FitName:=B+Tail;
End;

Function ImageName(K:Integer):String;
Var
 C:String;
Begin
 Case FloppyKB of
  1200:C:='120';
  1440:C:='144';
  2880:C:='288';
 Else C:=NumStr(FloppyKB);
 End;
 ImageName:=OutDir+FitName(BaseName,C+Chr(65+K))+'.IMG';
End;

Procedure MarkBoot;
Var
 I,J:Integer;
 Found:Boolean;
Begin
 { sans /BOOT : le shell \BIN\SH.EXE est impose sur la 1ere disquette }
 If BootCnt=0 Then
  For I:=1 to EntCnt do
   If WildMatch('\BIN\SH.EXE',UpStr(EntPath(I)),1,1)Then
    Ents[I]^.Boot:=True;
 For J:=1 to BootCnt do Begin
  Found:=False;
  For I:=1 to EntCnt do
   If WildMatch(BootPat[J],UpStr(EntPath(I)),1,1)Then Begin
    Ents[I]^.Boot:=True;
    Found:=True;
   End;
  If Not Found Then Say(M_wNoMatch,BootPat[J],'','','');
 End;
End;

Procedure Main;
Var
 I,K,Nf:Integer;
 Free,Kb:LongInt;
 Dw:Word;
 E:Integer;
 Nm:String;
Begin
 If(ParamCount=0)or(ParamStr(1)='/?')or(ParamStr(1)='-?')or
   (ParamStr(1)='-h')or(ParamStr(1)='--help')Then Begin
  Help;
  Halt(0);
 End;
 ReadArgs;
 { date et heure }
 If Yr=0 Then Begin
  GetDate(Yr,Mo,Dy,Dw);
  GetTime(Hr,Mi,Sc,Dw);
 End;
 DDate:=Word((LongInt(Yr-1980)shl 9)or(LongInt(Mo)shl 5)or Dy);
 DTime:=Word((LongInt(Hr)shl 11)or(LongInt(Mi)shl 5)or(Sc div 2));
 If Not FloppyGeom(FloppyKB,FG)Then Die(1,M_eFloppy,NumStr(FloppyKB));
 If(ForceBits=16)and(Not DoHard)Then Die(1,M_eFat,'');
 If DoIso and(FloppyKB<>1200)and(FloppyKB<>1440)and(FloppyKB<>2880)Then
  Die(1,M_eIsoFl,'');
 If OutDir<>'' Then Begin
  OutDir:=WithSep(OutDir);
  MkDir(Copy(OutDir,1,Length(OutDir)-1));
  If IOResult<>0 Then;
 End;
 GetMem(ZBuf,CopySize);
 ZeroMem(ZBuf^,CopySize);
 GetMem(CBuf,CopySize);
 { dossier racine et \BIN }
 DirCnt:=1;
 FillChar(Dirs[0],SizeOf(Dirs[0]),0);
 { systeme }
 If Not IsFolder(SysDir)Then Die(2,M_eNoSys,SysDir);
 If AddTree(SysDir,0,'',True,True)=0 Then Die(2,M_eNoIo,SysDir);
 E:=FindEnt(0,'IO      SYS');
 If E=0 Then Die(2,M_eNoIo,SysDir);
 Ents[E]^.Sys:=1;
 Ents[E]^.Attr:=$27;
 E:=FindEnt(0,'MSDOS   SYS');
 If E=0 Then Begin
  E:=AddFile('','MSDOS.SYS',0,Length(MsdosSys));
  Ents[E]^.Boot:=True;
 End;
 Ents[E]^.Sys:=2;
 Ents[E]^.Attr:=$27;
 { commandes }
 If CmdDir<>'' Then Begin
  If Not IsFolder(CmdDir)Then Die(2,M_eNoCmd,CmdDir);
  K:=DirFromPath(BinDir);
  If AddTree(CmdDir,K,Masks,False,False)=0 Then
   Say(M_wNoMatch,CmdDir,'','','');
 End;
 For I:=1 to AddCnt do DoAdd(AddSrc[I],AddDst[I]);
 For I:=1 to MkCnt do Begin
  K:=DirFromPath(MkList[I]);
  If K>0 Then Dirs[K].Keep:=True;
 End;
 SortEnts;
 MarkBoot;
 { disquettes }
 Pack;
 Kb:=0;
 For I:=1 to EntCnt do Kb:=Kb+SizeKB(Ents[I]^.Size);
 Say(M_iTotal,NumStr(EntCnt),NumStr(Kb),NumStr(DirCnt-1),'');
 For K:=0 to DiskCnt-1 do Begin
  If Not BuildFat(K,ImageName(K),K,Nf,Free)Then Halt(3);
  Say(M_iMade,ImageName(K),NumStr(Nf),NumStr(Free),'');
 End;
 For K:=DiskCnt to MaxDisk-1 do
  If FileFound(ImageName(K))Then Begin
   Assign(Img,ImageName(K));
   Erase(Img);
   If IOResult<>0 Then;
  End;
 { disque dur }
 If DoHard Then Begin
  If Not HardGeom(HardMB,ForceBits,FG)Then Die(1,M_eFat,'');
  Nm:=OutDir+FitName(BaseName,'HD')+'.IMG';
  If Not BuildFat(-1,Nm,0,Nf,Free)Then Halt(3);
  Say(M_iMade,Nm,NumStr(Nf),NumStr(Free),'');
 End;
 { CD-ROM }
 If DoIso Then Begin
  If IsoName='' Then IsoName:=OutDir+FitName(BaseName,'')+'.ISO'
  Else If DirPart(IsoName)='' Then IsoName:=OutDir+IsoName;
  If Not BuildIso(IsoName,ImageName(0),FloppyKB,Nf,Kb)Then Halt(3);
  Say(M_iIso,IsoName,NumStr(Nf),NumStr(Kb),'');
 End;
End;

BEGIN
 InitLang;
 SysDir:='SYSTEM';
 CmdDir:='BIN16';
 OutDir:='';
 BaseName:='LINUX';
 VolLabel:='LINUX';
 BinDir:='BIN';
 Masks:='*.EXE,*.COM,*.BAT';
 IsoName:='';
 BaseDir:='';
 FloppyKB:=1440;
 FreeKB:=0;
 HardMB:=32;
 DoHard:=False;
 DoIso:=False;
 Verbose:=False;
 ForceBits:=0;
 AddCnt:=0;
 BootCnt:=0;
 MkCnt:=0;
 Yr:=0;
 EntCnt:=0;
 DirCnt:=1;
 InfDepth:=0;
 FillChar(KidP,SizeOf(KidP),0);
 Main;
END.
