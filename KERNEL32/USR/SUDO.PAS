{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: sudo et visudo (un seul programme, le nom lu dans argv[0]).
    sudo [-u utilisateur] [-g groupe] [-n] [-k] [-i] [-s] [-l [-U nom]]
         [-v] [commande [arguments]]
      Lit /etc/sudoers : lignes "qui hote = (runas) [NOPASSWD:] commandes",
      qui = utilisateur, %groupe ou ALL ; hote = ALL ; commandes = ALL ou
      chemins separes par des virgules (arguments eventuels, * admis) ;
      "Defaults !authenticate", "Defaults timestamp_timeout=N" ; alias
      User_Alias, Cmnd_Alias, Runas_Alias non geres (lignes ignorees).
      Le mot de passe de l'appelant est demande (sauf NOPASSWD ou
      !authenticate) ; root passe sans mot de passe. Le programme doit etre
      setuid root pour un utilisateur ordinaire.
    visudo [-c] [-f fichier] : verifie la syntaxe (-c) ou edite le fichier
      avec $EDITOR (defaut vi) puis le verifie ; refuse un fichier invalide.
    Variable SUDOERS : fichier a la place de /etc/sudoers (root seulement).
    Messages en cinq langues (LANGUAGE).
}

Program Sudo;

Const
  MAXRULE = 64;
  M : Array[1..8, 1..5] Of PChar = (
    ('Usage : sudo [-u utilisateur] [-nkisvl] [commande [arguments]]',
     'Usage: sudo [-u user] [-nkisvl] [command [arguments]]',
     'Aufruf: sudo [-u Benutzer] [-nkisvl] [Befehl [Argumente]]',
     'Uso: sudo [-u usuario] [-nkisvl] [orden [argumentos]]',
     'Uso: sudo [-u utente] [-nkisvl] [comando [argomenti]]'),
    ('n''est pas dans le fichier sudoers. Incident signale.',
     'is not in the sudoers file. This incident will be reported.',
     'steht nicht in der sudoers-Datei.',
     'no esta en el fichero sudoers.',
     'non e'' nel file sudoers.'),
    ('echec de l''authentification', 'authentication failure',
     'Authentifizierung fehlgeschlagen', 'fallo de autenticacion',
     'autenticazione fallita'),
    ('doit etre setuid root', 'must be setuid root',
     'muss setuid root sein', 'debe ser setuid root',
     'deve essere setuid root'),
    ('syntaxe correcte', 'parsed OK', 'Syntax in Ordnung',
     'sintaxis correcta', 'sintassi corretta'),
    ('erreur de syntaxe ligne ', 'syntax error near line ',
     'Syntaxfehler in Zeile ', 'error de sintaxis en la linea ',
     'errore di sintassi alla riga '),
    ('commande introuvable', 'command not found', 'Befehl nicht gefunden',
     'orden no encontrada', 'comando non trovato'),
    ('Privileges autorises pour ', 'User may run the following commands for ',
     'Erlaubte Befehle fuer ', 'Puede ejecutar las siguientes ordenes para ',
     'Comandi consentiti per '));

Type
  TRule = Record
    Who : String;             { nom, %groupe ou ALL }
    Runas : String;           { ALL ou nom }
    Cmds : String;            { liste brute }
    NoPass : Boolean;
  End;

Var
  Rules : Array[1..MAXRULE] Of TRule;
  NRules : LongInt;
  NoAuth : Boolean;
  Prog : String;
  SynLine : LongInt;

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

Function Trim(Const S : String) : String;
Var A, B : LongInt;
Begin
  A := 1;
  B := Length(S);
  While (A <= B) And (S[A] In [' ', #9]) Do Inc(A);
  While (B >= A) And (S[B] In [' ', #9]) Do Dec(B);
  Trim := Copy(S, A, B - A + 1);
End;

{ lit un fichier sudoers ; rend le numero de la ligne fautive (0 : correct) }
Function Parse(Const Path : String) : LongInt;
Var Fd, N, K, E : LongInt; L, Who, Rest, Run : String; Np : Boolean;
Begin
  Parse := 0;
  NRules := 0;
  NoAuth := False;
  Fd := SysOpen(Path, O_RDONLY, 0);
  If Fd < 0 Then
  Begin
    Parse := -1;
    Exit;
  End;
  N := 0;
  While SysReadLine(Fd, L) Do
  Begin
    Inc(N);
    K := Pos('#', L);
    If K > 0 Then L := Copy(L, 1, K - 1);
    L := Trim(L);
    If L = '' Then Continue;
    If Copy(L, 1, 8) = 'Defaults' Then
    Begin
      If Pos('!authenticate', L) > 0 Then NoAuth := True;
      Continue;
    End;
    If (Copy(L, 1, 10) = 'User_Alias') Or (Copy(L, 1, 10) = 'Cmnd_Alias') Or
       (Copy(L, 1, 12) = 'Runas_Alias') Or (Copy(L, 1, 10) = 'Host_Alias') Or
       (Copy(L, 1, 8) = '#include') Or (Copy(L, 1, 8) = '@include') Then
      Continue;
    E := Pos('=', L);
    If E = 0 Then
    Begin
      Parse := N;
      SysClose(Fd);
      Exit;
    End;
    Who := Trim(Copy(L, 1, E - 1));
    Rest := Trim(Copy(L, E + 1, 500));
    K := Pos(' ', Who);
    If K = 0 Then K := Pos(#9, Who);
    If K = 0 Then
    Begin
      Parse := N;
      SysClose(Fd);
      Exit;
    End;
    Who := Copy(Who, 1, K - 1);
    Run := 'root';
    If (Rest <> '') And (Rest[1] = '(') Then
    Begin
      K := Pos(')', Rest);
      If K = 0 Then
      Begin
        Parse := N;
        SysClose(Fd);
        Exit;
      End;
      Run := Trim(Copy(Rest, 2, K - 2));
      If Pos(':', Run) > 0 Then Run := Copy(Run, 1, Pos(':', Run) - 1);
      Rest := Trim(Copy(Rest, K + 1, 500));
    End;
    Np := False;
    If Copy(Rest, 1, 9) = 'NOPASSWD:' Then
    Begin
      Np := True;
      Rest := Trim(Copy(Rest, 10, 500));
    End
    Else If Copy(Rest, 1, 7) = 'PASSWD:' Then Rest := Trim(Copy(Rest, 8, 500));
    If Rest = '' Then
    Begin
      Parse := N;
      SysClose(Fd);
      Exit;
    End;
    If NRules < MAXRULE Then
    Begin
      Inc(NRules);
      Rules[NRules].Who := Who;
      Rules[NRules].Runas := Run;
      Rules[NRules].Cmds := Rest;
      Rules[NRules].NoPass := Np;
    End;
  End;
  SysClose(Fd);
End;

Function InGroup(Const User, Grp : String) : Boolean;
Var Fd : LongInt; L, Mem, G : String; K : LongInt;
Begin
  InGroup := False;
  Fd := SysOpen('/etc/group', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
  Begin
    K := Pos(':', L);
    If Copy(L, 1, K - 1) <> Grp Then Continue;
    Mem := Copy(L, 1, 400);
    { 4e champ }
    Delete(Mem, 1, K);
    Delete(Mem, 1, Pos(':', Mem));
    Delete(Mem, 1, Pos(':', Mem));
    Mem := Mem + ',';
    While Mem <> '' Do
    Begin
      K := Pos(',', Mem);
      G := Copy(Mem, 1, K - 1);
      If G = User Then InGroup := True;
      Mem := Copy(Mem, K + 1, 400);
    End;
  End;
  SysClose(Fd);
End;

{ motif simple : * remplace une suite quelconque }
Function Glob(Const P, T : String; PI, TI : LongInt) : Boolean;
Var K : LongInt;
Begin
  While PI <= Length(P) Do
  Begin
    If P[PI] = '*' Then
    Begin
      For K := TI To Length(T) + 1 Do
        If Glob(P, T, PI + 1, K) Then
        Begin
          Glob := True;
          Exit;
        End;
      Glob := False;
      Exit;
    End;
    If (TI > Length(T)) Or (P[PI] <> T[TI]) Then
    Begin
      Glob := False;
      Exit;
    End;
    Inc(PI);
    Inc(TI);
  End;
  Glob := TI > Length(T);
End;

Function CmdAllowed(Const List, Cmd : String) : Boolean;
Var L, It : String; K : LongInt;
Begin
  CmdAllowed := False;
  L := List + ',';
  While L <> '' Do
  Begin
    K := Pos(',', L);
    It := Trim(Copy(L, 1, K - 1));
    L := Copy(L, K + 1, 500);
    If It = 'ALL' Then
    Begin
      CmdAllowed := True;
      Exit;
    End;
    If (It <> '') And (Glob(It, Cmd, 1, 1) Or Glob(It + ' *', Cmd, 1, 1)) Then
    Begin
      CmdAllowed := True;
      Exit;
    End;
  End;
End;

{ regle applicable : rend son numero (0 : aucune) }
Function Find(Const User, Target, Cmd : String) : LongInt;
Var I : LongInt; Ok : Boolean;
Begin
  Find := 0;
  For I := NRules DownTo 1 Do
  Begin
    Ok := (Rules[I].Who = 'ALL') Or (Rules[I].Who = User);
    If (Not Ok) And (Rules[I].Who <> '') And (Rules[I].Who[1] = '%') Then
      Ok := InGroup(User, Copy(Rules[I].Who, 2, 60));
    If Not Ok Then Continue;
    If (Rules[I].Runas <> 'ALL') And (Rules[I].Runas <> Target) Then Continue;
    If Not CmdAllowed(Rules[I].Cmds, Cmd) Then Continue;
    Find := I;
    Exit;
  End;
End;

Function Field(L : String; N : LongInt) : String;
Var K : LongInt;
Begin
  For K := 2 To N Do
  Begin
    If Pos(':', L) = 0 Then
    Begin
      Field := '';
      Exit;
    End;
    Delete(L, 1, Pos(':', L));
  End;
  If Pos(':', L) > 0 Then L := Copy(L, 1, Pos(':', L) - 1);
  Field := L;
End;

Function ShadowOf(Const N : String; Var H : String) : Boolean;
Var Fd : LongInt; L : String;
Begin
  ShadowOf := False;
  Fd := SysOpen('/etc/shadow', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
    If Field(L, 1) = N Then
    Begin
      H := Field(L, 2);
      ShadowOf := True;
      Break;
    End;
  SysClose(Fd);
End;

Function ReadPass(Const Prompt : String) : String;
Var T, Old : TSysTermios; S : String; C : Char; N : LongInt; Tty : Boolean;
Begin
  SysPut(2, Prompt);
  Tty := SysTcGetAttr(0, Old) = 0;
  If Tty Then
  Begin
    T := Old;
    T.LFlag := T.LFlag And Not TTY_ECHO;
    SysTcSetAttr(0, 1, T);
  End;
  S := '';
  Repeat
    N := SysRead(0, C, 1);
    If (N <= 0) Or (C = #10) Then Break;
    If Length(S) < 64 Then S := S + C;
  Until False;
  If Tty Then SysTcSetAttr(0, 1, Old);
  C := #10;
  SysWrite(2, C, 1);
  ReadPass := S;
End;

Function UserName(Uid : LongInt) : String;
Var P : TSysPasswd;
Begin
  If SysGetPwUid(Uid, P) Then UserName := P.Name Else UserName := NumS(Uid);
End;

Function FindExe(Const Name : String) : String;
Var Path, Dir : String; K : LongInt;
Begin
  FindExe := Name;
  If Pos('/', Name) > 0 Then Exit;
  Path := '/sbin:/bin:/usr/sbin:/usr/bin';
  While Path <> '' Do
  Begin
    K := Pos(':', Path);
    If K = 0 Then
    Begin
      Dir := Path;
      Path := '';
    End
    Else
    Begin
      Dir := Copy(Path, 1, K - 1);
      Path := Copy(Path, K + 1, 255);
    End;
    If SysAccess(Dir + '/' + Name, 1) = 0 Then
    Begin
      FindExe := Dir + '/' + Name;
      Exit;
    End;
  End;
End;

Procedure RunSudo;
Var I, K, Ru, R : LongInt; A, Target, Cmd, Who, H, Pw, Full : String;
    OptN, OptL, OptI, OptS : Boolean; P, Pt : TSysPasswd; Ask : String;
    Sh : String; First : LongInt; ListUser, Sf : String;
Begin
  Target := 'root';
  OptN := False; OptL := False; OptI := False; OptS := False;
  ListUser := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (Length(A) < 2) Or (A[1] <> '-') Then Break;
    If A = '--' Then
    Begin
      Inc(I);
      Break;
    End;
    If (A = '-u') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Target := SysArgStr(I);
    End
    Else If (A = '-U') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      ListUser := SysArgStr(I);
    End
    Else If (A = '-g') And (I + 1 < SysArgCount) Then Inc(I)
    Else
      For K := 2 To Length(A) Do
        Case A[K] Of
          'n' : OptN := True;
          'l' : OptL := True;
          'i' : OptI := True;
          's' : OptS := True;
          'k', 'v', 'K', 'S', 'H', 'E', 'b' : ;
        Else
          Begin
            SysPut(2, Msg(1) + #10);
            SysExit(1);
          End;
        End;
    Inc(I);
  End;
  First := I;
  Ru := SysGetUid;
  If ListUser <> '' Then Who := ListUser Else Who := UserName(Ru);
  Sf := '/etc/sudoers';
  If (SysGetUid = 0) And (SysGetEnv('SUDOERS') <> '') Then
    Sf := SysGetEnv('SUDOERS');
  If Parse(Sf) < 0 Then
  Begin
    SysPut(2, 'sudo: ' + Sf + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  If OptL Then
  Begin
    SysPut(1, Msg(8) + Who + ':' + #10);
    For K := 1 To NRules Do
      If (Rules[K].Who = 'ALL') Or (Rules[K].Who = Who) Or
         ((Rules[K].Who[1] = '%') And InGroup(Who, Copy(Rules[K].Who, 2, 60)))
      Then
      Begin
        If Rules[K].NoPass Then H := 'NOPASSWD: ' Else H := '';
        SysPut(1, '    (' + Rules[K].Runas + ') ' + H + Rules[K].Cmds + #10);
      End;
    SysExit(0);
  End;
  Cmd := '';
  If First < SysArgCount Then Cmd := SysArgStr(First);
  If (OptI Or OptS) And (Cmd = '') Then Cmd := 'ALL';
  If Cmd = '' Then
  Begin
    SysPut(2, Msg(1) + #10);
    SysExit(1);
  End;
  Full := '';
  For K := First To SysArgCount - 1 Do
  Begin
    If K > First Then Full := Full + ' ';
    Full := Full + SysArgStr(K);
  End;
  If Not SysGetPwNam(Target, Pt) Then
  Begin
    SysPut(2, 'sudo: unknown user ' + Target + #10);
    SysExit(1);
  End;
  If Ru <> 0 Then
  Begin
    If SysGetEUid <> 0 Then
    Begin
      SysPut(2, 'sudo: ' + Msg(4) + #10);
      SysExit(1);
    End;
    K := Find(Who, Target, FindExe(Cmd) + Copy(Full, Length(Cmd) + 1, 400));
    If (K = 0) And (OptI Or OptS) Then K := Find(Who, Target, 'ALL');
    If K = 0 Then
    Begin
      SysPut(2, Who + ' ' + Msg(2) + #10);
      SysExit(1);
    End;
    If (Not Rules[K].NoPass) And (Not NoAuth) Then
    Begin
      If OptN Then
      Begin
        SysPut(2, 'sudo: a password is required' + #10);
        SysExit(1);
      End;
      If Not SysGetPwNam(Who, P) Then SysExit(1);
      If Not ShadowOf(Who, H) Then H := '*';
      Pw := ReadPass('[sudo] password for ' + Who + ': ');
      If (H = '*') Or (H = '!') Or (H = '') Or
         (SysCrypt(Pw, Copy(H, 1, 2)) <> H) Then
      Begin
        SysPut(2, 'sudo: ' + Msg(3) + #10);
        SysExit(1);
      End;
    End;
  End;
  { identite cible }
  If (SysSetGid(Pt.Gid) < 0) Or (SysSetUid(Pt.Uid) < 0) Then
  Begin
    SysPut(2, 'sudo: setuid: ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  SysArgReset;
  If OptI Or OptS Then
  Begin
    Sh := Pt.Shell;
    If Sh = '' Then Sh := '/bin/sh';
    If OptI Then SysArgAdd('-' + Copy(Sh, Pos('/bin/', Sh) + 5, 40))
    Else SysArgAdd(Sh);
    If First < SysArgCount Then
    Begin
      SysArgAdd('-c');
      SysArgAdd(Full);
    End;
    Cmd := Sh;
  End
  Else
    For K := First To SysArgCount - 1 Do SysArgAdd(SysArgStr(K));
  SysEnvInherit;
  SysEnvAdd('SUDO_USER=' + Who);
  SysEnvAdd('SUDO_UID=' + NumS(Ru));
  If OptI Then
  Begin
    SysEnvAdd('HOME=' + Pt.Home);
    SysChdir(Pt.Home);
  End;
  R := SysArgExec(FindExe(Cmd));
  SysPut(2, 'sudo: ' + Cmd + ': ' + SysErrorText(SysErrno) + #10);
  SysExit(127);
End;

Procedure RunVisudo;
Var I, R, Pid, St : LongInt; A, F, Ed : String; CheckOnly : Boolean;
Begin
  F := '/etc/sudoers';
  CheckOnly := False;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-c' Then CheckOnly := True
    Else If (A = '-f') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      F := SysArgStr(I);
    End;
    Inc(I);
  End;
  If Not CheckOnly Then
  Begin
    Ed := SysGetEnv('EDITOR');
    If Ed = '' Then Ed := SysGetEnv('VISUAL');
    If Ed = '' Then Ed := 'vi';
    Pid := SysFork;
    If Pid = 0 Then
    Begin
      SysArgReset;
      SysArgAdd(Ed);
      SysArgAdd(F);
      SysEnvInherit;
      SysArgExec(FindExe(Ed));
      SysExit(127);
    End;
    SysWaitPid(Pid, St, 0);
  End;
  R := Parse(F);
  If R < 0 Then
  Begin
    SysPut(2, 'visudo: ' + F + ': ' + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  If R > 0 Then
  Begin
    SysPut(2, 'visudo: ' + Msg(6) + NumS(R) + #10);
    SysExit(1);
  End;
  SysPut(1, F + ': ' + Msg(5) + #10);
End;

BEGIN
  Prog := SysArgStr(0);
  While Pos('/', Prog) > 0 Do Prog := Copy(Prog, Pos('/', Prog) + 1, 255);
  If Prog = 'visudo' Then RunVisudo Else RunSudo;
  SysExit(0);
END.
