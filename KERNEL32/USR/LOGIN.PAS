{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/login de KERNEL32 : verifie le nom et le mot de passe
   dans /etc/passwd (nom:mot de passe:uid:gid:commentaire:repertoire:
   interpreteur) et /etc/shadow (nom:mot de passe code:...), puis ouvre la
   session : proprietaire du terminal, groupe et utilisateur (setgid,
   setuid), repertoire de connexion, /etc/motd, environnement (HOME, SHELL,
   USER, LOGNAME, PATH, plus LANGUAGE et TERM s'ils existent) et
   interpreteur de connexion ("-sh"). Un champ de mot de passe vide n'en
   demande pas ; * ou ! au debut le verrouille. Si le champ de /etc/passwd
   vaut x, le mot de passe code est celui de /etc/shadow.
   Mot de passe code (login, passwd, mkpasswd) : 13 caracteres, le sel de
   2 caracteres puis 11 caracteres de l'alphabet ./0-9A-Za-z, calcules par
   la fonction SysCrypt (comme KERNEL16UNIX).
   Usage : login [nom]
   Messages selon LANGUAGE (FR, EN, GR, SP, IT).
}

Program Login;

Const
  M : Array[1..6, 1..5] Of PChar = (
    ('Mot de passe : ', 'Password: ', 'Passwort: ', 'Contrasena: ',
     'Password: '),
    ('Connexion refusee', 'Login incorrect', 'Anmeldung fehlgeschlagen',
     'Acceso denegado', 'Accesso negato'),
    ('Pas de repertoire % : connexion dans /',
     'No directory %: logging in with home=/',
     'Kein Verzeichnis %: Anmeldung in /',
     'No hay directorio %: entrando en /',
     'Nessuna directory %: accesso in /'),
    ('login : setuid impossible : ', 'login: setuid failed: ',
     'login: setuid fehlgeschlagen: ', 'login: setuid ha fallado: ',
     'login: setuid fallito: '),
    ('Usage : login [nom]', 'Usage: login [name]', 'Aufruf: login [Name]',
     'Uso: login [nombre]', 'Uso: login [nome]'),
    ('Ouvre une session (nom et mot de passe de /etc/passwd).',
     'Open a session (name and password from /etc/passwd).',
     'Oeffnet eine Sitzung (Name und Passwort aus /etc/passwd).',
     'Abre una sesion (nombre y contrasena de /etc/passwd).',
     'Apre una sessione (nome e password da /etc/passwd).'));

Var
  Name, Pw, S, Base, LangName, Term, Path : String;
  P : TSysPasswd;
  Found : Boolean;
  Tries, K : LongInt;

Function Msg(Id : LongInt) : String;
Var Q : PChar; X : String;
Begin
  Q := M[Id, SysLang];
  X := '';
  While Q^ <> #0 Do
  Begin
    X := X + Q^;
    Inc(Q);
  End;
  Msg := X;
End;

{ champ N (1 = nom) d'une ligne de fichier a deux points }
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

{ mot de passe code de Name dans /etc/shadow ; Faux si pas de ligne }
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

{ lecture d'un mot de passe sans echo }
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

Function ReadName : String;
Var S : String; C : Char; N : LongInt;
Begin
  SysPut(1, 'login: ');
  S := '';
  Repeat
    N := SysRead(0, C, 1);
    If N <= 0 Then SysExit(1);
    If C = #10 Then Break;
    If (C > ' ') And (Length(S) < 31) Then S := S + C;
  Until False;
  ReadName := S;
End;

Procedure Motd;
Var Fd, N : LongInt; B : Array[0..255] Of Char;
Begin
  Fd := SysOpen('/etc/motd', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  Repeat
    N := SysRead(Fd, B, 256);
    If N > 0 Then SysWrite(1, B, N);
  Until N <= 0;
  SysClose(Fd);
End;

BEGIN
  SysSigAction(SIGINT, SIG_IGN, 0);
  SysSigAction(SIGQUIT, SIG_IGN, 0);
  If SysArgCount > 1 Then Name := SysArgStr(1) Else Name := '';
  If (Name = '/?') Or (Name = '-h') Or (Name = '--help') Then
  Begin
    SysPut(1, Msg(5) + #10 + Msg(6) + #10);
    SysExit(0);
  End;
  LangName := SysGetEnv('LANGUAGE');
  Term := SysGetEnv('TERM');
  Tries := 0;
  Repeat
    While Name = '' Do Name := ReadName;
    Found := SysGetPwNam(Name, P);
    Pw := '';
    If Found Then
    Begin
      Pw := P.Pw;
      If (Pw = 'x') And Not ShadowOf(Name, Pw) Then Pw := '*';
    End;
    If Found And (Pw = '') Then
      S := ''
    Else
    Begin
      S := ReadPass(Msg(1));
      If Found Then
      Begin
        If (Pw <> '') And ((Pw[1] = '*') Or (Pw[1] = '!')) Then
          Found := False
        Else If SysCrypt(S, Copy(Pw, 1, 2)) <> Pw Then
          Found := False;
      End;
    End;
    If Not Found Then
    Begin
      SysSleep(2);
      SysPut(1, Msg(2) + #10);
      Inc(Tries);
      If Tries >= 5 Then SysExit(1);
      Name := '';
    End;
  Until Found;
  If P.Home = '' Then P.Home := '/';
  If P.Shell = '' Then P.Shell := '/bin/sh';
  { le terminal appartient a l'utilisateur }
  If SysIsATty(0) Then
  Begin
    SysFChown(0, P.Uid, P.Gid);
    SysFChmod(0, $190);
  End;
  If SysChdir(P.Home) < 0 Then
  Begin
    S := Msg(3);
    K := Pos('%', S);
    SysPut(1, Copy(S, 1, K - 1) + P.Home + Copy(S, K + 1, 255) + #10);
    P.Home := '/';
    SysChdir('/');
  End;
  If (SysSetGid(P.Gid) < 0) Or (SysSetUid(P.Uid) < 0) Then
  Begin
    SysPut(1, Msg(4) + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  Motd;
  K := Length(P.Shell);
  While (K > 0) And (P.Shell[K] <> '/') Do Dec(K);
  Base := Copy(P.Shell, K + 1, 255);
  If P.Uid = 0 Then Path := '/sbin:/bin:/usr/sbin:/usr/bin'
  Else Path := '/bin:/usr/bin';
  SysSigAction(SIGINT, SIG_DFL, 0);
  SysSigAction(SIGQUIT, SIG_DFL, 0);
  SysArgReset;
  SysArgAdd('-' + Base);
  SysEnvAdd('HOME=' + P.Home);
  SysEnvAdd('SHELL=' + P.Shell);
  SysEnvAdd('USER=' + Name);
  SysEnvAdd('LOGNAME=' + Name);
  SysEnvAdd('PATH=' + Path);
  If LangName <> '' Then SysEnvAdd('LANGUAGE=' + LangName);
  If Term <> '' Then SysEnvAdd('TERM=' + Term);
  SysArgExec(P.Shell);
  SysPut(1, 'login: ' + P.Shell + ': ' + SysErrorText(SysErrno) + #10);
  SysExit(1);
END.
