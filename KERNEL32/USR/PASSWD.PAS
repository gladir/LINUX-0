{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/passwd : change le mot de passe d'un compte. Usage :
   passwd [nom]. L'utilisateur change son propre mot de passe (l'ancien est
   demande) ; root peut changer celui de n'importe quel compte. Le mot de
   passe code (SysCrypt, 13 caracteres) est ecrit dans /etc/shadow (ou, sans
   ce fichier, dans le champ 2 de /etc/passwd) par un fichier temporaire
   renomme. Messages en 5 langues (LANGUAGE).
}

Program Passwd;

Const
  M : Array[1..9, 1..5] Of PChar = (
    ('Ancien mot de passe : ', 'Old password: ', 'Altes Passwort: ',
     'Contrasena anterior: ', 'Vecchia password: '),
    ('Nouveau mot de passe : ', 'New password: ', 'Neues Passwort: ',
     'Contrasena nueva: ', 'Nuova password: '),
    ('Confirmez : ', 'Retype new password: ', 'Wiederholen: ',
     'Repita la contrasena: ', 'Ripeti la password: '),
    ('Les mots de passe different', 'Passwords do not match',
     'Passwoerter stimmen nicht ueberein', 'Las contrasenas no coinciden',
     'Le password non coincidono'),
    ('Mot de passe incorrect', 'Incorrect password', 'Falsches Passwort',
     'Contrasena incorrecta', 'Password errata'),
    ('Mot de passe modifie', 'Password updated', 'Passwort geaendert',
     'Contrasena actualizada', 'Password aggiornata'),
    ('passwd : compte inconnu : ', 'passwd: unknown user: ',
     'passwd: unbekannter Benutzer: ', 'passwd: usuario desconocido: ',
     'passwd: utente sconosciuto: '),
    ('passwd : seul root peut changer le mot de passe de ',
     'passwd: only root can change the password of ',
     'passwd: nur root darf das Passwort aendern von ',
     'passwd: solo root puede cambiar la contrasena de ',
     'passwd: solo root puo cambiare la password di '),
    ('passwd : ecriture impossible : ', 'passwd: cannot write: ',
     'passwd: Schreiben nicht moeglich: ', 'passwd: no se puede escribir: ',
     'passwd: impossibile scrivere: '));

Var
  Name, Old, New1, New2, Cur, Path, Tmp, L : String;
  P : TSysPasswd;
  Me, Fd, K : LongInt;
  Found : Boolean;

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

Function ReadPass(Const Prompt : String) : String;
Var T, O : TSysTermios; S : String; C : Char; N : LongInt; Tty : Boolean;
Begin
  SysPut(2, Prompt);
  Tty := SysTcGetAttr(0, O) = 0;
  If Tty Then
  Begin
    T := O;
    T.LFlag := T.LFlag And Not TTY_ECHO;
    SysTcSetAttr(0, 1, T);
  End;
  S := '';
  Repeat
    N := SysRead(0, C, 1);
    If (N <= 0) Or (C = #10) Then Break;
    If Length(S) < 64 Then S := S + C;
  Until False;
  If Tty Then SysTcSetAttr(0, 1, O);
  C := #10;
  SysWrite(2, C, 1);
  ReadPass := S;
End;

{ recopie Path en remplacant le champ 2 de la ligne de Name par Hash }
Function Rewrite(Const File1, Who, Hash : String) : Boolean;
Var Fi, Fo, K : LongInt; Line : String; Done : Boolean;
Begin
  Rewrite := False;
  Tmp := File1 + '.tmp';
  Fi := SysOpen(File1, O_RDONLY, 0);
  If Fi < 0 Then Exit;
  Fo := SysOpen(Tmp, O_WRONLY Or O_CREAT Or O_TRUNC, 384);
  If Fo < 0 Then
  Begin
    SysClose(Fi);
    Exit;
  End;
  Done := False;
  While SysReadLine(Fi, Line) Do
  Begin
    If Field(Line, 1) = Who Then
    Begin
      K := Pos(':', Line);
      Delete(Line, 1, K);
      K := Pos(':', Line);
      Line := Who + ':' + Hash + Copy(Line, K, 255);
      Done := True;
    End;
    SysPut(Fo, Line + #10);
  End;
  SysClose(Fi);
  SysClose(Fo);
  If Done And (SysRename(Tmp, File1) >= 0) Then Rewrite := True
  Else SysUnlink(Tmp);
End;

BEGIN
  Me := SysGetUid;
  If SysArgCount > 1 Then Name := SysArgStr(1)
  Else If SysGetPwUid(Me, P) Then Name := P.Name
  Else Name := '';
  If Not SysGetPwNam(Name, P) Then
  Begin
    SysPut(2, Msg(7) + Name + #10);
    SysExit(1);
  End;
  If (Me <> 0) And (P.Uid <> Me) Then
  Begin
    SysPut(2, Msg(8) + Name + #10);
    SysExit(1);
  End;
  { fichier des mots de passe codes et valeur actuelle }
  Path := '/etc/passwd';
  Cur := P.Pw;
  Fd := SysOpen('/etc/shadow', O_RDONLY, 0);
  If Fd >= 0 Then
  Begin
    Path := '/etc/shadow';
    Cur := '';
    While SysReadLine(Fd, L) Do
      If Field(L, 1) = Name Then Cur := Field(L, 2);
    SysClose(Fd);
  End;
  If (Me <> 0) And (Cur <> '') Then
  Begin
    Old := ReadPass(Msg(1));
    If SysCrypt(Old, Copy(Cur, 1, 2)) <> Cur Then
    Begin
      SysPut(2, Msg(5) + #10);
      SysExit(1);
    End;
  End;
  New1 := ReadPass(Msg(2));
  New2 := ReadPass(Msg(3));
  If New1 <> New2 Then
  Begin
    SysPut(2, Msg(4) + #10);
    SysExit(1);
  End;
  If New1 = '' Then Cur := ''
  Else
  Begin
    K := SysTime + SysGetPid;
    Cur := SysCrypt(New1, Chr(97 + K Mod 26) + Chr(97 + (K Div 26) Mod 26));
  End;
  If Not Rewrite(Path, Name, Cur) Then
  Begin
    SysPut(2, Msg(9) + SysErrorText(SysErrno) + #10);
    SysExit(1);
  End;
  SysPut(1, Msg(6) + #10);
END.
