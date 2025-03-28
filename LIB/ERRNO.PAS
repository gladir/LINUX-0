{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit errno;

INTERFACE

Const
  EPERM = 1;              { OpÇration non permise }
  ENOENT = 2;             { Aucun fichier ou rÇpertoire de ce type }
  ESRCH = 3;              { Aucun processus de ce type }
  EINTR = 4;              { Appel systäme interrompu }
  EIO = 5;                { Erreur d'entrÇe/sortie }
  ENXIO = 6;              { Aucun pÇriphÇrique ou adresse de ce type }
  E2BIG = 7;              { Liste d'arguments trop longue }
  ENOEXEC = 8;            { Erreur de format d'exÇcution }
  EBADF = 9;              { Mauvais numÇro de fichier }
  ECHILD = 10;            { Aucun processus enfant }
  EAGAIN = 11;            { RÇessayer }
  ENOMEM = 12;            { MÇmoire insuffisante }
  EACCES = 13;            { Permission refusÇe }
  EFAULT = 14;            { Mauvaise adresse }
  ENOTBLK = 15;           { PÇriphÇrique bloc requis }
  EBUSY = 16;             { PÇriphÇrique ou ressource occupÇ }
  EEXIST = 17;            { Fichier existant }
  EXDEV = 18;             { Lien inter-disque non permis }
  ENODEV = 19;            { Aucun pÇriphÇrique de ce type }
  ENOTDIR = 20;           { N'est pas un rÇpertoire }
  EISDIR = 21;            { Est un rÇpertoire }
  EINVAL = 22;            { Argument invalide }
  ENFILE = 23;            { Table des fichiers pleine }
  EMFILE = 24;            { Trop de fichiers ouverts }
  ENOTTY = 25;            { N'est pas un terminal }
  ETXTBSY = 26;           { Fichier texte occupÇ }
  EFBIG = 27;             { Fichier trop grand }
  ENOSPC = 28;            { Plus d'espace disponible sur le pÇriphÇrique }
  ESPIPE = 29;            { Positionnement de fichier illÇgal }
  EROFS = 30;             { Systäme de fichiers en lecture seule }
  EMLINK = 31;            { Trop de liens }
  EPIPE = 32;             { Tube brisÇ }
  EDOM = 33;              { Argument mathÇmatique hors domaine }
  ERANGE = 34;            { RÇsultat mathÇmatique non reprÇsentable }
  EDEADLK = 35;           { Un interblocage de ressource surviendrait }
  ENAMETOOLONG = 36;      { Nom de fichier trop long }
  ENOLCK = 37;            { Aucun verrou d'enregistrement disponible }
  ENOSYS = 38;            { Fonction non implÇmentÇe }
  ENOTEMPTY = 39;         { RÇpertoire non vide }
  ELOOP = 40;             { Trop de liens symboliques rencontrÇs }
  EWOULDBLOCK = 41;       { L'opÇration bloquerait }
  ENOMSG = 42;            { Aucun message du type souhaitÇ }
  EIDRM = 43;             { Identificateur supprimÇ }
  ECHRNG = 44;            { NumÇro de canal hors limite }
  EL2NSYNC = 45;          { Niveau 2 non synchronisÇ }
  EL3HLT = 46;            { Niveau 3 arràtÇ }
  EL3RST = 47;            { RÇinitialisation de niveau 3 }
  ELNRNG = 48;            { NumÇro de liaison hors limite }
  EUNATCH = 49;           { Pilote de protocole non attachÇ }
  ENOCSI = 50;            { Aucune structure CSI disponible }
  EL2HLT = 51;            { Niveau 2 arràtÇ }
  EBADE = 52;             { êchange invalide }
  EBADR = 53;             { Descripteur de requàte invalide }
  EXFULL = 54;            { êchange plein }
  ENOANO = 55;            { Aucun anode }
  EBADRQC = 56;           { Code de requàte invalide }
  EBADSLT = 57;           { Emplacement invalide }
  EDEADLOCK = 58;         { Erreur d'interblocage de verrouillage de fichier }
  EBFONT = 59;            { Format de fichier de police invalide }
  ENOSTR = 60;            { PÇriphÇrique non stream }
  ENODATA = 61;           { Aucune donnÇe disponible }
  ETIME = 62;             { Minuteur expirÇ }
  ENOSR = 63;             { Ressources de flux insuffisantes }
  ENONET = 64;            { Machine hors rÇseau }
  ENOPKG = 65;            { Package non installÇ }
  EREMOTE = 66;           { Objet distant }
  ENOLINK = 67;           { Lien rompu }
  EADV = 68;              { Erreur de publicitÇ }
  ESRMNT = 69;            { Erreur de montage sÇcurisÇ }
  ECOMM = 70;             { Erreur de communication lors de l'envoi }
  EPROTO = 71;            { Erreur de protocole }
  EMULTIHOP = 72;         { Tentative de multi-saut }
  EDOTDOT = 73;           { Erreur spÇcifique RFS }
  EBADMSG = 74;           { Message de donnÇes invalide }
  EOVERFLOW = 75;         { Valeur trop grande pour le type de donnÇes dÇfini }
  ENOTUNIQ = 76;          { Nom non unique sur le rÇseau }
  EBADFD = 77;            { Descripteur de fichier dans un Çtat invalide }
  EREMCHG = 78;           { Adresse distante modifiÇe }
  ELIBACC = 79;           { Impossible d'accÇder Ö une bibliothäque partagÇe nÇcessaire }
  ELIBBAD = 80;           { Accäs Ö une bibliothäque partagÇe corrompue }
  ELIBSCN = 81;           { Section .lib dans a.out corrompue }
  ELIBMAX = 82;           { Trop de bibliothäques partagÇes liÇes }
  ELIBEXEC = 83;          { Impossible d'exÇcuter une bibliothäque partagÇe directement }
  EILSEQ = 84;            { SÇquence d'octets illÇgale }
  ESTRPIPE = 86;          { Erreur de pipe sur flux }
  EUSERS = 87;            { Trop d'utilisateurs }
  ENOTSOCK = 88;          { OpÇration sur socket appliquÇe Ö un non-socket }
  EDESTADDRREQ = 89;      { Adresse de destination requise }
  EMSGSIZE = 90;          { Message trop long }
  EPROTOTYPE = 91;        { Mauvais type de protocole pour le socket }
  ENOPROTOOPT = 92;       { Protocole non disponible }
  EPROTONOSUPPORT = 93;   { Protocole non supportÇ }
  ESOCKTNOSUPPORT = 94;   { Type de socket non supportÇ }
  EOPNOTSUPP = 95;        { OpÇration non supportÇe sur le point de transport }
  EPFNOSUPPORT = 96;      { Famille de protocole non supportÇe }
  EAFNOSUPPORT = 97;      { Famille d'adresses non supportÇe par le protocole }
  EADDRINUSE = 98;        { Adresse dÇjÖ utilisÇe }
  EADDRNOTAVAIL = 99;     { Impossible d'attribuer l'adresse demandÇe }
  ENETDOWN = 100;         { RÇseau hors service }
  ENETUNREACH = 101;      { RÇseau inaccessible }
  ENETRESET = 102;        { RÇseau a interrompu la connexion Ö cause d'une rÇinitialisation }
  ECONNABORTED = 103;     { Abandon de connexion causÇ par un logiciel }
  ECONNRESET = 104;       { Connexion rÇinitialisÇe par le pair }
  ENOBUFS = 105;          { Pas d'espace de mÇmoire tampon disponible }
  EISCONN = 106;          { Point de transport dÇjÖ connectÇ }
  ENOTCONN = 107;         { Point de transport non connectÇ }
  ESHUTDOWN = 108;        { Impossible d'envoyer apräs arràt du point de transport }
  ETOOMANYREFS = 109;     { Trop de rÇfÇrences : impossible de fusionner }
  ETIMEDOUT = 110;        { DÇlai de connexion dÇpassÇ }
  ECONNREFUSED = 111;     { Connexion refusÇe }
  EHOSTDOWN = 112;        { Hìte hors service }
  EHOSTUNREACH = 113;     { Pas de route vers l'hìte }
  EALREADY = 114;         { OpÇration dÇjÖ en cours }
  EINPROGRESS = 115;      { OpÇration en cours }
  ESTALE = 116;           { Descripteur de fichier obsoläte }
  EUCLEAN = 117;          { Structure nÇcessitant un nettoyage }
  ENOTNAM = 118;          { Pas un fichier de type nommÇ XENIX }
  ENAVAIL = 119;          { Pas de sÇmaphores XENIX disponibles }
  EISNAM = 120;           { Est un fichier de type nommÇ }
  EREMOTEIO = 121;        { Erreur d'entrÇe/sortie distante }
  EDQUOT = 122;           { Quota dÇpassÇ }
  ENOMEDIUM = 123;        { Aucun support trouvÇ }
  EMEDIUMTYPE = 124;      { Mauvais type de support }
  ECANCELED = 125;        { OpÇration annulÇe }
  ENOKEY = 126;           { Clef requise non disponible }
  EKEYEXPIRED = 127;      { Clef expirÇe }
  EKEYREVOKED = 128;      { Clef rÇvoquÇe }
  EKEYREJECTED = 129;     { Clef rejetÇe par le service }
  EOWNERDEAD = 130;       { PropriÇtaire dÇcÇdÇ }
  ENOTRECOVERABLE = 131;  { êtat non rÇcupÇrable }
  ERFKILL = 132;          { OpÇration impossible en raison d'un RF-kill }
  EHWPOISON = 133;        { Page mÇmoire corrompue par une erreur matÇrielle }

  ERESTARTSYS = 512;      { L'appel systäme interrompu devrait àtre relancÇ }
  ERESTARTNOINTR = 513;   { L'appel systäme interrompu ne doit pas àtre relancÇ }

IMPLEMENTATION

END.