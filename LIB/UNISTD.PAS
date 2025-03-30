{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit UniStd;

INTERFACE

Const
 _CS_PATH=1;
 _CS_POSIX_V6_ILP32_OFF32_CFLAGS=2;
 _CS_POSIX_V6_ILP32_OFF32_LDFLAGS=3;
 _CS_POSIX_V6_ILP32_OFF32_LIBS=4;
 _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS=5;
 _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS=6;
 _CS_POSIX_V6_ILP32_OFFBIG_LIBS=7;
 _CS_POSIX_V6_LP64_OFF64_CFLAGS=8;
 _CS_POSIX_V6_LP64_OFF64_LDFLAGS=9;
 _CS_POSIX_V6_LP64_OFF64_LIBS=10;
 _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS=11;
 _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS=12;
 _CS_POSIX_V6_LPBIG_OFFBIG_LIBS=13;
 _CS_POSIX_V6_WIDTH_RESTRICTED_ENVS=14;

 _SC_ARG_MAX = 1;                    { Nombre maximal d'arguments pour une commande }
 _SC_CHILD_MAX = 2;                  { Nombre maximal de processus enfants pour un processus }
 _SC_CLK_TCK = 3;                    { Nombre de ticks par seconde (pour les calculs de temps CPU) }
 _SC_NGROUPS_MAX = 4;                { Nombre maximal de groupes d'utilisateurs auxquels un utilisateur peut appartenir }
 _SC_OPEN_MAX = 5;                   { Nombre maximal de fichiers ouverts simultan‚ment }
 _SC_STREAM_MAX = 6;                 { Nombre maximal de flux ouverts simultan‚ment }
 _SC_TZNAME_MAX = 7;                 { Longueur maximale du nom de fuseau horaire }
 _SC_JOB_CONTROL = 8;                { Supporte-t-il le contr“le des tƒches POSIX ? }
 _SC_SAVED_IDS = 9;                  { Supporte-t-il les identifiants enregistr‚s POSIX ? }
 _SC_VERSION = 10;                   { Version de POSIX support‚e }
 _SC_CHARCLASS_NAME_MAX = 11;        { Longueur maximale d'un nom de classe de
                                       caractŠre dans une sp‚cification de locale ‚tendue }
 _SC_REALTIME_SIGNALS = 12;          { Supporte-t-il les signaux temps r‚el POSIX ? }
 _SC_PRIORITY_SCHEDULING = 13;       { Supporte-t-il l'ordonnancement prioritaire POSIX ? }
 _SC_TIMERS = 14;                    { Supporte-t-il les minuteries POSIX ? }
 _SC_ASYNCHRONOUS_IO = 15;           { Supporte-t-il les entr‚es/sorties asynchrones POSIX ? }
 _SC_PRIORITIZED_IO = 16;            { Supporte-t-il les entr‚es/sorties prioris‚es POSIX ? }
 _SC_SYNCHRONIZED_IO = 17;           { Supporte-t-il les entr‚es/sorties synchronis‚es POSIX ? }
 _SC_FSYNC = 18;                     { Supporte-t-il l'op‚ration fsync POSIX ? }
 _SC_MAPPED_FILES = 19;              { Supporte-t-il les fichiers mapp‚s en m‚moire POSIX ? }
 _SC_MEMLOCK = 20;                   { Supporte-t-il le verrouillage de m‚moire POSIX ? }
 _SC_MEMLOCK_RANGE = 21;             { Plage maximale de m‚moire pouvant ˆtre verrouill‚e en m‚moire }
 _SC_MEMORY_PROTECTION = 22;         { Supporte-t-il la protection de la m‚moire ? }
 _SC_MESSAGE_PASSING = 23;           { Supporte-t-il le passage de messages entre processus ? }
 _SC_SEMAPHORES = 24;                { Supporte-t-il les s‚maphores POSIX ? }
 _SC_SHARED_MEMORY_OBJECTS = 25;     { Supporte-t-il les objets de m‚moire partag‚e POSIX ? }
 _SC_AIO_LISTIO_MAX = 26;            { Nombre maximal d'op‚rations de lecture/‚criture
                                       asynchrones possibles en une seule op‚ration }
 _SC_AIO_MAX = 27;                   { Nombre maximal d'op‚rations d'entr‚e/sortie asynchrones possibles simultan‚ment }
 _SC_AIO_PRIO_DELTA_MAX = 28;        { Variation maximale de priorit‚ pour les op‚rations d'entr‚e/sortie asynchrones }
 _SC_DELAYTIMER_MAX = 29;            { Temps maximal pour les minuteries de d‚lai POSIX }
 _SC_MQ_OPEN_MAX = 30;               { Nombre maximal de files de messages ouvertes simultan‚ment }
 _SC_MQ_PRIO_MAX = 31;               { Priorit‚ maximale des files de messages POSIX }
 _SC_RTSIG_MAX = 32;                 { Nombre maximal de signaux r‚els POSIX }
 _SC_SEM_NSEMS_MAX = 33;             { Nombre maximal de s‚maphores distincts pouvant ˆtre utilis‚s }
 _SC_SEM_VALUE_MAX = 34;             { Valeur maximale d'un s‚maphore POSIX }
 _SC_SIGQUEUE_MAX = 35;              { Nombre maximal de signaux en file d'attente POSIX }
 _SC_TIMER_MAX = 36;                 { Nombre maximal de minuteries POSIX pouvant ˆtre cr‚‚es }
 _SC_PII = 37;                       { Supporte-t-il l'interface PII (Pluggable Interface Integration) ? }
 _SC_PII_XTI = 38;                   { Supporte-t-il l'interface PII pour XTI (X/Open Transport Interface) ? }
 _SC_PII_SOCKET = 39;                { Supporte-t-il l'interface PII pour les sockets ? }
 _SC_PII_INTERNET = 40;              { Supporte-t-il l'interface PII pour Internet ? }
 _SC_PII_OSI = 41;                   { Supporte-t-il l'interface PII pour OSI (Open Systems Interconnection) ? }
 _SC_SELECT = 42;                    { Supporte-t-il l'API select pour la gestion des descripteurs de fichiers ? }
 _SC_UIO_MAXIOV = 43;                { Nombre maximal d'‚l‚ments dans un vecteur d'entr‚e/sortie (iov) }
 _SC_PII_INTERNET_STREAM = 44;       { Supporte-t-il l'interface PII pour les flux Internet (TCP) ? }
 _SC_PII_INTERNET_DGRAM = 45;        { Supporte-t-il l'interface PII pour les datagrammes Internet (UDP) ? }
 _SC_PII_OSI_COTS = 46;              { Supporte-t-il l'interface PII pour COTS (Commercial Off-The-Shelf) en OSI ? }
 _SC_PII_OSI_CLTS = 47;              { Supporte-t-il l'interface PII pour CLTS (Connectionless Transport Service) en OSI ? }
 _SC_PII_OSI_M = 48;                 { Supporte-t-il l'interface PII pour M (Management) en OSI ? }
 _SC_T_IOV_MAX = 49;                 { Nombre maximal de vecteurs d'entr‚e/sortie dans une op‚ration POSIX }
 _SC_THREADS = 50;                   { Supporte-t-il la gestion des threads POSIX ? }
 _SC_THREAD_SAFE_FUNCTIONS = 51;     { Supporte-t-il les fonctions s–res pour les processus l‚gers ? }
 _SC_GETGR_R_SIZE_MAX = 52;          { Taille maximale des structures de groupe retourn‚es par getgr_r }
 _SC_GETPW_R_SIZE_MAX = 53;          { Taille maximale des structures de mot de passe retourn‚es par getpw_r }
 _SC_LOGIN_NAME_MAX = 54;            { Longueur maximale du nom de connexion utilisateur }
 _SC_TTY_NAME_MAX = 55;              { Longueur maximale du nom du terminal (tty) }
 _SC_THREAD_DESTRUCTOR_ITERATIONS=56;{ Nombre maximal d'it‚rations pour les destructeurs de processus l‚gers }
 _SC_THREAD_KEYS_MAX = 57;           { Nombre maximal de cl‚s de thread disponibles }
 _SC_THREAD_STACK_MIN = 58;          { Taille minimale de la pile pour chaque thread }
 _SC_THREAD_THREADS_MAX = 59;        { Nombre maximal de threads pouvant ˆtre cr‚‚s }
 _SC_THREAD_ATTR_STACKADDR = 60;     { Supporte-t-il l'attribut de pile de thread pour une adresse sp‚cifique ? }
 _SC_THREAD_ATTR_STACKSIZE = 61;     { Taille maximale de la pile attribu‚e aux threads }
 _SC_THREAD_PRIORITY_SCHEDULING = 62;{ Supporte-t-il la planification des threads selon leur priorit‚ ? }
 _SC_THREAD_PRIO_INHERIT = 63;       { Les threads h‚ritent-ils de la priorit‚ du thread parent ? }
 _SC_THREAD_PRIO_PROTECT = 64;       { Les threads sont-ils prot‚g‚s contre l'inversion de priorit‚ ? }
 _SC_THREAD_PROCESS_SHARED = 65;     { Les attributs de thread peuvent-ils ˆtre partag‚s entre diff‚rents processus ? }
 _SC_2_C_DEV = 66;                   { Supporte-t-il le d‚veloppement d'applications C conforme … la norme 2 ? }
 _SC_2_FORT_DEV = 67;                { Supporte-t-il le d‚veloppement d'applications Fortran conforme … la norme 2 ? }
 _SC_2_FORT_RUN = 68;                { Supporte-t-il l'ex‚cution d'applications Fortran conforme … la norme 2 ? }
 _SC_2_LOCALEDEF = 69;               { Supporte-t-il la d‚finition de locale conforme … la norme 2 ? }
 _SC_2_SW_DEV = 70;                  { Supporte-t-il le d‚veloppement de logiciels conforme … la norme 2 ? }
 _SC_BC_BASE_MAX = 71;               { Nombre maximal de symboles de base autoris‚s dans l'outil bc }
 _SC_BC_DIM_MAX = 72;                { Nombre maximal d'‚l‚ments dans un vecteur dans l'outil bc }
 _SC_BC_SCALE_MAX = 73;              { Nombre maximal de chiffres dans un calcul bc }
 _SC_BC_STRING_MAX = 74;             { Longueur maximale des chaŒnes utilis‚es dans l'outil bc }
 _SC_COLL_WEIGHTS_MAX = 75;          { Nombre maximal de poids de collation dans la gestion des locales }
 _SC_EXPR_NEST_MAX = 76;             { Profondeur maximale des expressions dans l'outil bc }
 _SC_LINE_MAX = 77;                  { Longueur maximale d'une ligne dans l'outil bc ou dans les commandes de l'interpr‚teur }
 _SC_EQUIV_CLASS_MAX = 78;           { Nombre maximal de classes ‚quivalentes dans une collation locale }
 _SC_HOST_NAME_MAX = 79;             { Longueur maximale du nom d'h“te du systŠme }
 _SC_2_VERSION = 80;                 { Version de la norme 2 support‚e par le systŠme }
 _SC_PAGESIZE = 81;                  { Taille de la page m‚moire du systŠme }
 _SC_NPROCESSORS_CONF = 82;          { Nombre de processeurs configur‚s dans le systŠme }
 _SC_NPROCESSORS_ONLN = 83;          { Nombre de processeurs actuellement en ligne et utilisables }
 _SC_PHYS_PAGES = 84;                { Nombre de pages m‚moire physiques totales sur le systŠme }
 _SC_AVPHYS_PAGES = 85;              { Nombre de pages m‚moire physiques disponibles pour les processus }
 _SC_ATEXIT_MAX = 86;                { Nombre maximal d'entr‚es dans la table d'ex‚cution des
                                       fonctions de terminaison (atexit) }
 _SC_XOPEN_VERSION = 87;             { Version du standard X/Open support‚e par le systŠme }
 _SC_XOPEN_XCU_VERSION = 88;         { Version du sous-systŠme XCU de X/Open support‚e }
 _SC_XOPEN_UNIX = 89;                { Supporte-t-il la norme X/Open UNIX ? }
 _SC_XOPEN_REALTIME = 90;            { Supporte-t-il les fonctionnalit‚s X/Open en temps r‚el ? }
 _SC_XOPEN_REALTIME_THREADS = 91;    { Supporte-t-il les fonctionnalit‚s X/Open li‚es aux threads en temps r‚el ? }
 _SC_XOPEN_LEGACY = 92;              { Supporte-t-il les fonctionnalit‚s X/Open h‚rit‚es ? }
 _SC_XOPEN_CRYPT = 93;               { Supporte-t-il les fonctionnalit‚s X/Open pour le cryptage ? }
 _SC_XOPEN_ENH_I18N = 94;            { Supporte-t-il les extensions X/Open pour l'internationalisation am‚lior‚e ? }
 _SC_XOPEN_SHM = 95;                 { Supporte-t-il le partage de m‚moire X/Open ? }
 _SC_XOPEN_XPG2 = 96;                { Supporte-t-il la version 2 de X/Open Portability Guide (XPG) ? }
 _SC_XOPEN_XPG3 = 97;                { Supporte-t-il la version 3 de X/Open Portability Guide (XPG) ? }
 _SC_XOPEN_XPG4 = 98;                { Supporte-t-il la version 4 de X/Open Portability Guide (XPG) ? }
 _SC_CHAR_BIT = 99;                  { Nombre de bits dans un caractŠre (g‚n‚ralement 8) }
 _SC_CHAR_MAX = 100;                 { Valeur maximale d'un caractŠre sign‚ ou non sign‚ }
 _SC_CHAR_MIN = 101;                 { Valeur minimale d'un caractŠre sign‚ ou non sign‚ }
 _SC_INT_MAX = 102;                  { Valeur maximale d'un entier sign‚ }
 _SC_INT_MIN = 103;                  { Valeur minimale d'un entier sign‚ }
 _SC_LONG_BIT = 104;                 { Nombre de bits dans un long (g‚n‚ralement 32 ou 64) }
 _SC_WORD_BIT = 105;                 { Nombre de bits dans un mot (g‚n‚ralement 16 ou 32) }
 _SC_MB_LEN_MAX = 106;               { Longueur maximale d'un caractŠre multioctet }
 _SC_NZERO = 107;                    { Valeur indiquant l'origine des valeurs n‚gatives en
                                       systŠmes o— z‚ro n'est pas utilis‚ pour signifier "faux" }
 _SC_SSIZE_MAX = 108;                { Valeur maximale d'un ssize_t (souvent utilis‚e pour
                                       repr‚senter des tailles ou des indices) }
 _SC_SCHAR_MAX = 109;                { Valeur maximale d'un caractŠre sign‚ }
 _SC_SCHAR_MIN = 110;                { Valeur minimale d'un caractŠre sign‚ }
 _SC_SHRT_MAX = 111;                 { Valeur maximale d'un entier court sign‚ }
 _SC_SHRT_MIN = 112;                 { Valeur minimale d'un entier court sign‚ }
 _SC_UCHAR_MAX = 113;                { Valeur maximale d'un caractŠre non sign‚ }
 _SC_UINT_MAX = 114;                 { Valeur maximale d'un entier non sign‚ }
 _SC_ULONG_MAX = 115;                { Valeur maximale d'un long non sign‚ }
 _SC_USHRT_MAX = 116;                { Valeur maximale d'un entier court non sign‚ }
 _SC_NL_ARGMAX = 117;                { Nombre maximal d'arguments accept‚s par les
                                       commandes de traitement des messages multilingues }
 _SC_NL_LANGMAX = 118;               { Longueur maximale d'une chaŒne de langue pour la localisation }
 _SC_NL_MSGMAX = 119;                { Nombre maximal de messages dans un ensemble de messages localis‚s }
 _SC_NL_NMAX = 120;                  { Longueur maximale d'un nom de cat‚gorie dans les messages localis‚s }
 _SC_NL_SETMAX = 121;                { Nombre maximal de groupes de messages dans les messages localis‚s }
 _SC_NL_TEXTMAX = 122;               { Longueur maximale d'un texte dans les messages localis‚s }

Type
 size_t=Word;

Function  chdir(Const Path:PChar):Integer;
Function  chown(path:PChar;owner,group:Integer):Integer;
Function  confstr(name:Integer;Buf:PChar;Len:size_t):size_t;
Function  ftruncate(fildes:Integer;Length:Longint):Integer;
Function  getcwd(buf:PChar;size:Integer):PChar;
Function  geteuid:Integer;
Function  getlogin:PChar;
Function  getwd(buf:PChar):PChar;
Function  isatty(desc:Integer):Integer;
Function  realpath(path:PChar;resolved_path:PChar):PChar;
Function  rmdir(path:PChar):Integer;
Procedure sleep(seconds:Integer);
Procedure swab(Const from,to_:Pointer;n:Integer);
Function  sysconf(Name:Integer):LongInt;

IMPLEMENTATION

Uses
 {$IFDEF LINUX}
  BaseUnix,
 {$ELSE}
  {$IFDEF WINDOWS}
   Windows,
  {$ENDIF}
 {$ENDIF}
 Crt,DOS,Strings;

Const
 ARG_MAX=4096;
 CHILD_MAX=25;
 OPEN_MAX={$IFDEF FPC}255{$ELSE}15{$ENDIF};
 PAGESIZE=4096;
 CLK_TCK=100;
 HOST_NAME_MAX=255;
 POSIX_VERSION=199009;

Procedure CopyStrToPChar(Const Src:String;Dest:PChar;maxLen:size_t);
Var
 i:Integer;
Begin
 i:=1;
 While (i<=Length(src))and(i<maxLen)do Begin
  Dest[i-1]:=src[i];
  Inc(i);
 End;
 Dest[i-1]:=#0;
End;

Function chdir(Const Path:PChar):Integer;
Var
 strPath:String;
Begin
 strPath:=StrPas(path);
 {$I-} System.ChDir(strPath); {$I+}
 If IOResult<>0 Then ChDir:=-1
                Else ChDir:=0;
End;

Function chown(path:PChar;owner,group:Integer):Integer;
Var
 filePath:string;
 attr:Word;
Begin
 filePath:=StrPas(path);
 GetFAttr(filePath,attr);
 If DosError<>0 Then Begin
  chown:=-1;
  Exit;
 End;
 Attr:=Attr and not ReadOnly;
 SetFAttr(filePath,attr);
 If DosError=0 Then chown:=0
               Else chown:=-1;
End;

Function confstr(name:Integer;Buf:PChar;Len:size_t):size_t;
Var
 Value:String;
Begin
 Case Name of
  _CS_PATH: value := GetEnv('PATH');
  _CS_POSIX_V6_ILP32_OFF32_CFLAGS: Value:='-m32';
  _CS_POSIX_V6_ILP32_OFF32_LDFLAGS: Value:='-m32';
  _CS_POSIX_V6_ILP32_OFF32_LIBS: Value:='-lc';
  _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS: Value:='-m32 -D_LARGEFILE64_SOURCE';
  _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS: Value:='-m32';
  _CS_POSIX_V6_ILP32_OFFBIG_LIBS: Value:='-lc';
  _CS_POSIX_V6_LP64_OFF64_CFLAGS: Value:='-m64';
  _CS_POSIX_V6_LP64_OFF64_LDFLAGS: Value:='-m64';
  _CS_POSIX_V6_LP64_OFF64_LIBS: Value:='-lc';
  _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS: Value:='-m64 -D_LARGEFILE64_SOURCE';
  _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS: Value:='-m64';
  _CS_POSIX_V6_LPBIG_OFFBIG_LIBS: Value:='-lc';
  _CS_POSIX_V6_WIDTH_RESTRICTED_ENVS: Value:=':';
  Else Value:='';
 End;
 If Buf<>NIL Then Begin
  CopyStrToPChar(value,Buf,len);
  ConfStr:=Length(value);
 End
  else
 ConfStr:=Length(value)+1;
End;

Function ftruncate(fildes:Integer;Length:Longint):Integer;
Var
 FileRecVar:File;
Begin
 Assign(FileRecVar,'');
 FileRec(FileRecVar).Handle:=fildes;
 {$I-}Reset(FileRecVar);{$I+}
 If IOResult=0 Then Begin
  Seek(FileRecVar,length);
  Truncate(FileRecVar);
  Ftruncate:=0;
 End
  else
 ftruncate:=-1;
End;

Function getcwd(buf:PChar;size:Integer):PChar;
Var
 Path:String;
Begin
 GetDir(0,Path);
 If(Length(Path)+1<=Size)Then StrPCopy(buf,Path)
                         Else StrPCopy(buf,'Erreur: Tampon trop petit');
 getcwd:=buf;
End;

Function geteuid:Integer;Begin
 {$IFDEF LINUX}
  geteuid:=fpGetEUID;
 {$ELSE}
  {$IFDEF WINDOWS}
   geteuid:=GetCurrentProcessId;
  {$ELSE}
   geteuid:=1001; { UID fictif }
  {$ENDIF}
 {$ENDIF}
End;

Function getlogin:PChar;
Var
 UserName:String;
 CUserName:Array[0..255]of Char;
Begin
 UserName:=GetEnv('USER');
 If UserName=''Then UserName:=GetEnv('LOGNAME');
 If UserName=''Then UserName:=GetEnv('USERNAME');
 If UserName=''Then UserName:='Utilisateur inconnu';
 StrPCopy(CUserName,UserName);
 getlogin:=StrNew(CUserName);
End;

Function getwd(buf:PChar):PChar;
Var
  Dir:String;
Begin
 GetDir(0,Dir);
 StrPCopy(buf,Dir);
 getwd:=buf;
End;

Function get_current_working_dir_name:PChar;
Var
 Dir:String;
 buf:Array[0..255]of Char;
Begin
 GetDir(0,Dir);
 StrPCopy(buf,Dir);
 get_current_working_dir_name:=buf;
End;

Function isatty(desc:Integer):Integer;Begin
 If desc in [0,1,2]Then isatty:=1
                   Else isatty:=0;
End;

Function realpath(path:PChar;resolved_path:PChar):PChar;begin
 StrPCopy(resolved_path,FExpand(StrPas(path)));
 realpath:=resolved_path;
End;

Function rmdir(path:PChar):Integer;
Var
 dirPath:String;
Begin
 dirPath := StrPas(path);
 {$I-}System.RmDir(dirPath);{$I+}
 If DosError=0 Then rmdir:=0
               Else rmdir:=-1;
End;

Procedure sleep(seconds:Integer);Begin
 Delay(seconds*1000);
End;

Procedure swab(Const from,to_:Pointer;n:Integer);
Type
 ArrayByte=Array[0..32000]of Byte;
 PByte=^ArrayByte;
Var
 i:Integer;
 fromByte,toByte:PByte;
Begin
 fromByte:=from;
 toByte:=to_;
 For i:=0 to (n shr 1)-1 do Begin
  toByte^[0]:=fromByte^[2*i+1];
  toByte^[1]:=fromByte^[2*i];
  {$IFDEF FPC}
   fromByte:=fromByte+2;
   toByte:=toByte+2;
  {$ELSE}
   fromByte:=Ptr(Seg(fromByte),Ofs(fromByte) + 2);
   toByte:=Ptr(Seg(toByte),Ofs(toByte) + 2);
  {$ENDIF}
 End;
End;

Function sysconf(Name:Integer):LongInt;Begin
 Case Name of
  _SC_ARG_MAX:sysconf:=ARG_MAX;
  _SC_CHILD_MAX:sysconf:=CHILD_MAX;
  _SC_OPEN_MAX:sysconf:=OPEN_MAX;
  _SC_PAGESIZE:sysconf:=PAGESIZE;
  _SC_CLK_TCK:sysconf:=CLK_TCK;
  _SC_HOST_NAME_MAX:sysconf:=HOST_NAME_MAX;
  _SC_VERSION:sysconf:=POSIX_VERSION;
  Else sysconf := -1; { Non pris en charge }
 End;
End;

END.