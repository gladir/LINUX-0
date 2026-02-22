{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program USERADD;

Uses DOS;

Type
 TOption=Set of (OptCreateHome, OptSystem, OptShell, OptComment, OptUID, OptGID, OptHomeDir, OptExpire, OptInactive);

Var
 Language:(_Albanian,_French,_English,_Germany,_Italian,_Spain);
 TmpLanguage,UserName,UserComment,UserShell,UserHome:String;
 UserUID,UserGID,NextUID:Integer;
 Options:TOption;
 ExpireDate,InactiveDays:String;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

Function UserExists(UserName:String):Boolean;
Var
 FilePasswd:Text;
 I,CellPos:Integer;
 CurrLine,CurrWord:String;
 Cells:Array[0..6]of String;
Begin
 UserExists:=False;
 {$I-}Assign(FilePasswd,'/etc/passwd');
 Reset(FilePasswd);{$I+}
 If IOResult<>0 Then Exit;
 While Not EOF(FilePasswd)do Begin
  ReadLn(FilePasswd,CurrLine);
  FillChar(Cells,SizeOf(Cells),0);
  CurrWord:='';
  CellPos:=0;
  For I:=1 to Length(CurrLine) do Begin
   If CurrLine[I]=':'Then Begin
    Cells[CellPos]:=CurrWord;
    CurrWord:='';
    Inc(CellPos);
    If CellPos>5 Then Break;
   End
    Else
   CurrWord:=CurrWord+CurrLine[I];
  End;
  If CurrWord<>''Then Begin
   Cells[CellPos]:=CurrWord;
   Inc(CellPos);
  End;
  If Cells[0]=UserName Then Begin
   UserExists:=True;
   Close(FilePasswd);
   Exit;
  End;
 End;
 Close(FilePasswd);
End;

Function GetNextUID:Integer;
Var
 FilePasswd:Text;
 I,CellPos,CurrUID,MaxUID:Integer;
 CurrLine,CurrWord:String;
 Cells:Array[0..6]of String;
 Err:Word;
Begin
 MaxUID:=999;
 {$I-}Assign(FilePasswd,'/etc/passwd');
 Reset(FilePasswd);{$I+}
 If IOResult<>0 Then Begin
  GetNextUID:=1000;
  Exit;
 End;
 While Not EOF(FilePasswd)do Begin
  ReadLn(FilePasswd,CurrLine);
  FillChar(Cells,SizeOf(Cells),0);
  CurrWord:='';
  CellPos:=0;
  For I:=1 to Length(CurrLine) do Begin
   If CurrLine[I]=':'Then Begin
    Cells[CellPos]:=CurrWord;
    CurrWord:='';
    Inc(CellPos);
    If CellPos>5 Then Break;
   End
    Else
   CurrWord:=CurrWord+CurrLine[I];
  End;
  If CurrWord<>''Then Begin
   Cells[CellPos]:=CurrWord;
   Inc(CellPos);
  End;
  If Cells[2]<>''Then Begin
   Val(Cells[2],CurrUID,Err);
   If(Err=0)and(CurrUID>=1000)and(CurrUID>MaxUID)Then MaxUID:=CurrUID;
  End;
 End;
 Close(FilePasswd);
 GetNextUID:=MaxUID+1;
End;

Function AddUser:Boolean;
Var
 FilePasswd:Text;
 PasswdEntry,TempStr:String;
Begin
 AddUser:=False;
  { VÇrifier si l'utilisateur existe dÇjÖ }
 If UserExists(UserName)Then Begin
  Case Language of
   _English:WriteLn('useradd: user ''',UserName,''' already exists');
   _Germany:WriteLn('useradd: Benutzer ''',UserName,''' existiert bereits');
   _Italian:WriteLn('useradd: l''utente ''',UserName,''' esiste gia''');
   _Spain:WriteLn('useradd: el usuario ''',UserName,''' ya existe');
   _Albanian:WriteLn('useradd: pârdoruesi ''',UserName,''' ekziston tashmâ');
   Else WriteLn('useradd: l''utilisateur ''',UserName,''' existe dÇjÖ');
  End;
  Exit;
 End;
  { DÇfinir les valeurs par dÇfaut }
 If UserUID=0 Then UserUID:=GetNextUID;
 If UserGID=0 Then UserGID:=UserUID;
 If UserHome=''Then UserHome:='/home/'+UserName;
 If UserShell=''Then UserShell:='/bin/bash';
 If UserComment=''Then UserComment:=UserName;
  { Ouvrir le fichier passwd en mode ajout }
 {$I-}Assign(FilePasswd,'/etc/passwd');
 Append(FilePasswd);{$I+}
 If IOResult<>0 Then Begin
  Case Language of
   _English:WriteLn('useradd: cannot write to /etc/passwd');
   _Germany:WriteLn('useradd: kann nicht in /etc/passwd schreiben');
   _Italian:WriteLn('useradd: impossibile scrivere in /etc/passwd');
   _Spain:WriteLn('useradd: no se puede escribir en /etc/passwd');
   _Albanian:WriteLn('useradd: nuk mund tâ shkruaj nâ /etc/passwd');
   Else WriteLn('useradd: impossible d''Çcrire dans /etc/passwd');
  End;
  Exit;
 End;
  { Construire l'entrÇe passwd }
 Str(UserUID,PasswdEntry);
 PasswdEntry:=UserName+':x:'+PasswdEntry+':';
 Str(UserGID,TempStr);
 PasswdEntry:=PasswdEntry+TempStr+':'+UserComment+':'+UserHome+':'+UserShell;
 WriteLn(FilePasswd,PasswdEntry);
 Close(FilePasswd);
 AddUser:=True;
End;

Procedure CreateHomeDirectory;
Var
 DirInfo:SearchRec;
Begin
 If OptCreateHome in Options Then Begin
  FindFirst(UserHome,Directory,DirInfo);
  If DosError<>0 Then Begin
   {$I-}MkDir(UserHome);{$I+}
   If IOResult=0 Then Begin
    Case Language of
     _English:WriteLn('Created home directory: ',UserHome);
     _Germany:WriteLn('Home-Verzeichnis erstellt: ',UserHome);
     _Italian:WriteLn('Creata directory home: ',UserHome);
     _Spain:WriteLn('Directorio home creado: ',UserHome);
     _Albanian:WriteLn('U krijua direktoria home: ',UserHome);
     Else WriteLn('RÇpertoire personnel crÇÇ: ',UserHome);
    End;
   End
    Else
   Begin
    Case Language of
     _English:WriteLn('useradd: cannot create home directory ',UserHome);
     _Germany:WriteLn('useradd: kann Home-Verzeichnis ',UserHome,' nicht erstellen');
     _Italian:WriteLn('useradd: impossibile creare directory home ',UserHome);
     _Spain:WriteLn('useradd: no se puede crear directorio home ',UserHome);
     _Albanian:WriteLn('useradd: nuk mund tâ krijoj direktorinâ home ',UserHome);
     Else WriteLn('useradd: impossible de crÇer le rÇpertoire personnel ',UserHome);
    End;
   End;
  End;
 End;
End;

Procedure ParseParameters;
Var
 I:Integer;
 Param,NextParam:String;
 Err:Word;
 Value:Integer;
Begin
 Options:=[];
 For I:=1 to ParamCount do Begin
  Param:=ParamStr(I);
  If(Length(Param)>0)and(Param[1]='-')Then Begin
   If Param='-m'Then Options:=Options+[OptCreateHome]Else
   If Param='-r'Then Options:=Options+[OptSystem]Else
   If(Param='-c')and(I<ParamCount)Then Begin
    Options:=Options+[OptComment];
    UserComment:=ParamStr(I+1);
   End
    Else
   If(Param='-d')and(I<ParamCount)Then Begin
    Options:=Options+[OptHomeDir];
    UserHome:=ParamStr(I+1);
   End
    Else
   If(Param='-e')and(I<ParamCount)Then Begin
    Options:=Options+[OptExpire];
    ExpireDate:=ParamStr(I+1);
   End
    Else
   If(Param='-f')and(I<ParamCount)Then Begin
    Options:=Options+[OptInactive];
    InactiveDays:=ParamStr(I+1);
   End
    Else
   If(Param='-g')and(I<ParamCount)Then Begin
    Options:=Options+[OptGID];
    NextParam:=ParamStr(I+1);
    Val(NextParam,Value,Err);
    If Err=0 Then UserGID:=Value;
   End
    Else
   If(Param='-s')and(I<ParamCount)Then Begin
    Options:=Options+[OptShell];
    UserShell:=ParamStr(I+1);
   End
    Else
   If(Param='-u')and(I<ParamCount)Then Begin
    Options:=Options+[OptUID];
    NextParam:=ParamStr(I+1);
    Val(NextParam,Value,Err);
    If Err=0 Then UserUID:=Value;
   End;
  End
   Else
  If UserName=''Then UserName:=Param;
 End;
End;

BEGIN
 Language:=_French;
 TmpLanguage:=GetEnv('LANGUAGE');
 If TmpLanguage<>''Then Begin
  If TmpLanguage[1]='"'Then TmpLanguage:=Copy(TmpLanguage,2,255);
  If StrToUpper(Copy(TmpLanguage,1,2))='EN'Then Language:=_English Else
  If StrToUpper(Copy(TmpLanguage,1,2))='GR'Then Language:=_Germany Else
  If StrToUpper(Copy(TmpLanguage,1,2))='IT'Then Language:=_Italian Else
  If StrToUpper(Copy(TmpLanguage,1,2))='SP'Then Language:=_Spain Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='SQ')or
    (StrToUpper(Copy(TmpLanguage,1,3))='ALB')Then Language:=_Albanian;
 End;
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
 Case Language of
   _English:Begin
    WriteLn('USERADD : Add a user account to the system');
    WriteLn;
    WriteLn('Usage: useradd [options] username');
    WriteLn;
    WriteLn('  -c COMMENT      add comment for user');
    WriteLn('  -d HOME_DIR     home directory for new user');
    WriteLn('  -e EXPIRE_DATE  account expiration date (YYYY-MM-DD)');
    WriteLn('  -f INACTIVE     password expiration to account disabled');
    WriteLn('  -g GROUP        primary group for new user');
    WriteLn('  -m              create home directory');
    WriteLn('  -r              create system account');
    WriteLn('  -s SHELL        login shell for new user');
    WriteLn('  -u UID          user ID for new user');
    WriteLn('  --help          display this help');
   End;
   _Germany:Begin
    WriteLn('USERADD : Benutzerkonto zum System hinzufÅgen');
    WriteLn;
    WriteLn('Verwendung: useradd [Optionen] benutzername');
    WriteLn;
    WriteLn('  -c KOMMENTAR    Kommentar fÅr Benutzer hinzufÅgen');
    WriteLn('  -d HOME_VERZ    Home-Verzeichnis fÅr neuen Benutzer');
    WriteLn('  -e ABLAUF_DATUM Kontoablaufdatum (YYYY-MM-DD)');
    WriteLn('  -f INAKTIV      Passwort-Ablauf bis Konto deaktiviert');
    WriteLn('  -g GRUPPE       PrimÑre Gruppe fÅr neuen Benutzer');
    WriteLn('  -m              Home-Verzeichnis erstellen');
    WriteLn('  -r              System-Konto erstellen');
    WriteLn('  -s SHELL        Login-Shell fÅr neuen Benutzer');
    WriteLn('  -u UID          Benutzer-ID fÅr neuen Benutzer');
    WriteLn('  --help          diese Hilfe anzeigen');
   End;
   _Italian:Begin
    WriteLn('USERADD : Aggiunge un account utente al sistema');
    WriteLn;
    WriteLn('Uso: useradd [opzioni] nomeutente');
    WriteLn;
    WriteLn('  -c COMMENTO     aggiungi commento per utente');
    WriteLn('  -d DIR_HOME     directory home per nuovo utente');
    WriteLn('  -e DATA_SCAD    data di scadenza account (YYYY-MM-DD)');
    WriteLn('  -f INATTIVO     scadenza password per account disabilitato');
    WriteLn('  -g GRUPPO       gruppo primario per nuovo utente');
    WriteLn('  -m              crea directory home');
    WriteLn('  -r              crea account di sistema');
    WriteLn('  -s SHELL        shell di login per nuovo utente');
    WriteLn('  -u UID          ID utente per nuovo utente');
    WriteLn('  --help          mostra questo aiuto');
   End;
   _Spain:Begin
    WriteLn('USERADD : Agrega una cuenta de usuario al sistema');
    WriteLn;
    WriteLn('Uso: useradd [opciones] nombreusuario');
    WriteLn;
    WriteLn('  -c COMENTARIO   agregar comentario para usuario');
    WriteLn('  -d DIR_HOME     directorio home para nuevo usuario');
    WriteLn('  -e FECHA_EXP    fecha de expiracion de cuenta (YYYY-MM-DD)');
    WriteLn('  -f INACTIVO     expiracion de contrase§a a cuenta deshabilitada');
    WriteLn('  -g GRUPO        grupo primario para nuevo usuario');
    WriteLn('  -m              crear directorio home');
    WriteLn('  -r              crear cuenta de sistema');
    WriteLn('  -s SHELL        shell de login para nuevo usuario');
    WriteLn('  -u UID          ID de usuario para nuevo usuario');
    WriteLn('  --help          mostrar esta ayuda');
   End;
   _Albanian:Begin
    WriteLn('USERADD : Shton njâ llogari pârdoruesi nâ sistem');
    WriteLn;
    WriteLn('Pârdorimi: useradd [opsione] emripârdorues');
    WriteLn;
    WriteLn('  -c KOMENT       shto koment pâr pârdorues');
    WriteLn('  -d DIR_HOME     direktoria home pâr pâdorues tâ ri');
    WriteLn('  -e DATA_SKADON  data e skadimit tâ llogarisâ (YYYY-MM-DD)');
    WriteLn('  -f JOAKTIV      skadimi i fjalâkalimit nâ llogari tâ áaktivizuar');
    WriteLn('  -g GRUP         grupi kryesor pâr p√´rdorues tâ ri');
    WriteLn('  -m              krijo direktorinâ home');
    WriteLn('  -r              krijo llogari sistemi');
    WriteLn('  -s SHELL        shell hyrjeje pâr pârdorues tâ ri');
    WriteLn('  -u UID          ID pârdoruesi pâr pârdorues tâ ri');
    WriteLn('  --help          shfaq kâtâ ndihmâ');
   End;
   Else Begin
    WriteLn('USERADD : Cette commande permet d''ajouter un compte utilisateur au systäme');
    WriteLn;
    WriteLn('Utilisation: useradd [options] nomdutilisateur');
    WriteLn;
    WriteLn('  -c COMMENTAIRE  ajouter commentaire pour utilisateur');
    WriteLn('  -d REP_HOME     rÇpertoire personnel pour nouvel utilisateur');
    WriteLn('  -e DATE_EXP     date d''expiration du compte (YYYY-MM-DD)');
    WriteLn('  -f INACTIF      expiration mot de passe vers compte dÇsactivÇ');
    WriteLn('  -g GROUPE       groupe primaire pour nouvel utilisateur');
    WriteLn('  -m              crÇer rÇpertoire personnel');
    WriteLn('  -r              crÇer compte systäme');
    WriteLn('  -s SHELL        interprÇteur de commande de connexion pour nouvel utilisateur');
    WriteLn('  -u UID          ID utilisateur pour nouvel utilisateur');
    WriteLn('  --help          afficher cette aide');
   End;
  End;
 End
  Else
 Begin
  UserName:='';
  UserComment:='';
  UserShell:='';
  UserHome:='';
  UserUID:=0;
  UserGID:=0;
  ExpireDate:='';
  InactiveDays:='';
  ParseParameters;
  If UserName=''Then Begin
   Case Language of
    _English:WriteLn('Usage: useradd [options] username');
    _Germany:WriteLn('Verwendung: useradd [Optionen] benutzername');
    _Italian:WriteLn('Uso: useradd [opzioni] nomeutente');
    _Spain:WriteLn('Uso: useradd [opciones] nombreusuario');
    _Albanian:WriteLn('Pârdorimi: useradd [opsione] emripârdorues');
    Else WriteLn('Utilisation: useradd [options] nomdutilisateur');
   End;
   Halt(1);
  End;
  If AddUser Then Begin
   CreateHomeDirectory;
   Case Language of
    _English:WriteLn('User ',UserName,' added successfully');
    _Germany:WriteLn('Benutzer ',UserName,' erfolgreich hinzugefÅgt');
    _Italian:WriteLn('Utente ',UserName,' aggiunto con successo');
    _Spain:WriteLn('Usuario ',UserName,' agregado exitosamente');
    _Albanian:WriteLn('Pârdoruesi ',UserName,' u shtua me sukses');
    Else WriteLn('Utilisateur ',UserName,' ajoutÇ avec succäs');
   End;
  End
   Else
  Halt(1);
 End;
END.