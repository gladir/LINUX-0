{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit errno;

INTERFACE

Const
  EPERM = 1;              { Op�ration non permise }
  ENOENT = 2;             { Aucun fichier ou r�pertoire de ce type }
  ESRCH = 3;              { Aucun processus de ce type }
  EINTR = 4;              { Appel syst�me interrompu }
  EIO = 5;                { Erreur d'entr�e/sortie }
  ENXIO = 6;              { Aucun p�riph�rique ou adresse de ce type }
  E2BIG = 7;              { Liste d'arguments trop longue }
  ENOEXEC = 8;            { Erreur de format d'ex�cution }
  EBADF = 9;              { Mauvais num�ro de fichier }
  ECHILD = 10;            { Aucun processus enfant }
  EAGAIN = 11;            { R�essayer }
  ENOMEM = 12;            { M�moire insuffisante }
  EACCES = 13;            { Permission refus�e }
  EFAULT = 14;            { Mauvaise adresse }
  ENOTBLK = 15;           { P�riph�rique bloc requis }
  EBUSY = 16;             { P�riph�rique ou ressource occup� }
  EEXIST = 17;            { Fichier existant }
  EXDEV = 18;             { Lien inter-disque non permis }
  ENODEV = 19;            { Aucun p�riph�rique de ce type }
  ENOTDIR = 20;           { N'est pas un r�pertoire }
  EISDIR = 21;            { Est un r�pertoire }
  EINVAL = 22;            { Argument invalide }
  ENFILE = 23;            { Table des fichiers pleine }
  EMFILE = 24;            { Trop de fichiers ouverts }
  ENOTTY = 25;            { N'est pas un terminal }
  ETXTBSY = 26;           { Fichier texte occup� }
  EFBIG = 27;             { Fichier trop grand }
  ENOSPC = 28;            { Plus d'espace disponible sur le p�riph�rique }
  ESPIPE = 29;            { Positionnement de fichier ill�gal }
  EROFS = 30;             { Syst�me de fichiers en lecture seule }
  EMLINK = 31;            { Trop de liens }
  EPIPE = 32;             { Tube bris� }
  EDOM = 33;              { Argument math�matique hors domaine }
  ERANGE = 34;            { R�sultat math�matique non repr�sentable }
  EDEADLK = 35;           { Un interblocage de ressource surviendrait }
  ENAMETOOLONG = 36;      { Nom de fichier trop long }
  ENOLCK = 37;            { Aucun verrou d'enregistrement disponible }
  ENOSYS = 38;            { Fonction non impl�ment�e }
  ENOTEMPTY = 39;         { R�pertoire non vide }
  ELOOP = 40;             { Trop de liens symboliques rencontr�s }
  EWOULDBLOCK = 41;       { L'op�ration bloquerait }
  ENOMSG = 42;            { Aucun message du type souhait� }
  EIDRM = 43;             { Identificateur supprim� }
  ECHRNG = 44;            { Num�ro de canal hors limite }
  EL2NSYNC = 45;          { Niveau 2 non synchronis� }
  EL3HLT = 46;            { Niveau 3 arr�t� }
  EL3RST = 47;            { R�initialisation de niveau 3 }
  ELNRNG = 48;            { Num�ro de liaison hors limite }
  EUNATCH = 49;           { Pilote de protocole non attach� }
  ENOCSI = 50;            { Aucune structure CSI disponible }
  EL2HLT = 51;            { Niveau 2 arr�t� }
  EBADE = 52;             { �change invalide }
  EBADR = 53;             { Descripteur de requ�te invalide }
  EXFULL = 54;            { �change plein }
  ENOANO = 55;            { Aucun anode }
  EBADRQC = 56;           { Code de requ�te invalide }
  EBADSLT = 57;           { Emplacement invalide }
  EDEADLOCK = 58;         { Erreur d'interblocage de verrouillage de fichier }
  EBFONT = 59;            { Format de fichier de police invalide }
  ENOSTR = 60;            { P�riph�rique non stream }
  ENODATA = 61;           { Aucune donn�e disponible }
  ETIME = 62;             { Minuteur expir� }
  ENOSR = 63;             { Ressources de flux insuffisantes }
  ENONET = 64;            { Machine hors r�seau }
  ENOPKG = 65;            { Package non install� }
  EREMOTE = 66;           { Objet distant }
  ENOLINK = 67;           { Lien rompu }
  EADV = 68;              { Erreur de publicit� }
  ESRMNT = 69;            { Erreur de montage s�curis� }
  ECOMM = 70;             { Erreur de communication lors de l'envoi }
  EPROTO = 71;            { Erreur de protocole }
  EMULTIHOP = 72;         { Tentative de multi-saut }
  EDOTDOT = 73;           { Erreur sp�cifique RFS }
  EBADMSG = 74;           { Message de donn�es invalide }
  EOVERFLOW = 75;         { Valeur trop grande pour le type de donn�es d�fini }
  ENOTUNIQ = 76;          { Nom non unique sur le r�seau }
  EBADFD = 77;            { Descripteur de fichier dans un �tat invalide }
  EREMCHG = 78;           { Adresse distante modifi�e }
  ELIBACC = 79;           { Impossible d'acc�der � une biblioth�que partag�e n�cessaire }
  ELIBBAD = 80;           { Acc�s � une biblioth�que partag�e corrompue }
  ELIBSCN = 81;           { Section .lib dans a.out corrompue }
  ELIBMAX = 82;           { Trop de biblioth�ques partag�es li�es }
  ELIBEXEC = 83;          { Impossible d'ex�cuter une biblioth�que partag�e directement }
  EILSEQ = 84;            { S�quence d'octets ill�gale }
  ESTRPIPE = 86;          { Erreur de pipe sur flux }
  EUSERS = 87;            { Trop d'utilisateurs }
  ENOTSOCK = 88;          { Op�ration sur socket appliqu�e � un non-socket }
  EDESTADDRREQ = 89;      { Adresse de destination requise }
  EMSGSIZE = 90;          { Message trop long }
  EPROTOTYPE = 91;        { Mauvais type de protocole pour le socket }
  ENOPROTOOPT = 92;       { Protocole non disponible }
  EPROTONOSUPPORT = 93;   { Protocole non support� }
  ESOCKTNOSUPPORT = 94;   { Type de socket non support� }
  EOPNOTSUPP = 95;        { Op�ration non support�e sur le point de transport }
  EPFNOSUPPORT = 96;      { Famille de protocole non support�e }
  EAFNOSUPPORT = 97;      { Famille d'adresses non support�e par le protocole }
  EADDRINUSE = 98;        { Adresse d�j� utilis�e }
  EADDRNOTAVAIL = 99;     { Impossible d'attribuer l'adresse demand�e }
  ENETDOWN = 100;         { R�seau hors service }
  ENETUNREACH = 101;      { R�seau inaccessible }
  ENETRESET = 102;        { R�seau a interrompu la connexion � cause d'une r�initialisation }
  ECONNABORTED = 103;     { Abandon de connexion caus� par un logiciel }
  ECONNRESET = 104;       { Connexion r�initialis�e par le pair }
  ENOBUFS = 105;          { Pas d'espace de m�moire tampon disponible }
  EISCONN = 106;          { Point de transport d�j� connect� }
  ENOTCONN = 107;         { Point de transport non connect� }
  ESHUTDOWN = 108;        { Impossible d'envoyer apr�s arr�t du point de transport }
  ETOOMANYREFS = 109;     { Trop de r�f�rences : impossible de fusionner }
  ETIMEDOUT = 110;        { D�lai de connexion d�pass� }
  ECONNREFUSED = 111;     { Connexion refus�e }
  EHOSTDOWN = 112;        { H�te hors service }
  EHOSTUNREACH = 113;     { Pas de route vers l'h�te }
  EALREADY = 114;         { Op�ration d�j� en cours }
  EINPROGRESS = 115;      { Op�ration en cours }
  ESTALE = 116;           { Descripteur de fichier obsol�te }
  EUCLEAN = 117;          { Structure n�cessitant un nettoyage }
  ENOTNAM = 118;          { Pas un fichier de type nomm� XENIX }
  ENAVAIL = 119;          { Pas de s�maphores XENIX disponibles }
  EISNAM = 120;           { Est un fichier de type nomm� }
  EREMOTEIO = 121;        { Erreur d'entr�e/sortie distante }
  EDQUOT = 122;           { Quota d�pass� }
  ENOMEDIUM = 123;        { Aucun support trouv� }
  EMEDIUMTYPE = 124;      { Mauvais type de support }
  ECANCELED = 125;        { Op�ration annul�e }
  ENOKEY = 126;           { Clef requise non disponible }
  EKEYEXPIRED = 127;      { Clef expir�e }
  EKEYREVOKED = 128;      { Clef r�voqu�e }
  EKEYREJECTED = 129;     { Clef rejet�e par le service }
  EOWNERDEAD = 130;       { Propri�taire d�c�d� }
  ENOTRECOVERABLE = 131;  { �tat non r�cup�rable }
  ERFKILL = 132;          { Op�ration impossible en raison d'un RF-kill }
  EHWPOISON = 133;        { Page m�moire corrompue par une erreur mat�rielle }

  ERESTARTSYS = 512;      { L'appel syst�me interrompu devrait �tre relanc� }
  ERESTARTNOINTR = 513;   { L'appel syst�me interrompu ne doit pas �tre relanc� }

IMPLEMENTATION

END.