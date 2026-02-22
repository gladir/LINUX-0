{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program ACLOCAL;

Uses DOS;

Type
 TOption = Set of (OptDryRun, OptForce, OptHelp, OptInstall, OptOutput, OptPrint, OptVerbose, OptVersion);

Var
 Language:(_French,_English,_Germany,_Italian,_Spain);
 TmpLanguage:String;
 Options:TOption;
 OutputFile:String;
 AcLocalDir:String;
 SystemDir:String;
 I:Integer;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

Procedure ShowVersion;Begin
 Case Language of
  _English:Begin
   WriteLn('aclocal 1.0 - Pascal clone of coreutils, linux, unix or corail');
   WriteLn('MIT License');
   WriteLn;
   WriteLn('Written by Sylvain Maltais');
  End;
  _Germany:Begin
   WriteLn('aclocal 1.0 - Pascal-Klon von coreutils, linux, unix oder corail');
   WriteLn('MIT-Lizenz');
   WriteLn;
   WriteLn('Geschrieben von Sylvain Maltais');
  End;
  _Italian:Begin
   WriteLn('aclocal 1.0 - Clone Pascal di coreutils, linux, unix o corail');
   WriteLn('Licenza MIT');
   WriteLn;
   WriteLn('Scritto da Sylvain Maltais');
  End;
  _Spain:Begin
   WriteLn('aclocal 1.0 - Clon Pascal de coreutils, linux, unix o corail');
   WriteLn('Licencia MIT');
   WriteLn;
   WriteLn('Escrito por Sylvain Maltais');
  End;
  Else Begin
   WriteLn('aclocal 1.0 - Clone Pascal de coreutils, linux, unix ou corail');
   WriteLn('Licence MIT');
   WriteLn;
   WriteLn('Écrit par Sylvain Maltais');
  End;
 End;
End;

Procedure ShowHelp;
Begin
 Case Language of
  _English:Begin
   WriteLn('ACLOCAL : Generate aclocal.m4 by scanning configure.ac or configure.in');
   WriteLn;
   WriteLn('Usage: aclocal [OPTION]...');
   WriteLn;
   WriteLn('  -I DIR              add directory to search list for .m4 files');
   WriteLn('      --install       copy third-party files to the first -I directory');
   WriteLn('      --dry-run       pretend to, but do not actually update any file');
   WriteLn('      --force         always update output file');
   WriteLn('      --output=FILE   put output in FILE (default aclocal.m4)');
   WriteLn('      --print-ac-dir  print directory containing system-wide .m4 files');
   WriteLn('      --verbose       print what is being done');
   WriteLn('      --version       print version number and exit');
   WriteLn('      --help          show this help text');
  End;
  _Germany:Begin
   WriteLn('ACLOCAL : Erzeugt aclocal.m4 durch Scannen von configure.ac oder configure.in');
   WriteLn;
   WriteLn('Verwendung: aclocal [OPTION]...');
   WriteLn;
   WriteLn('  -I VERZ             Verzeichnis zur Suchliste fuer .m4 Dateien hinzufuegen');
   WriteLn('      --install       Drittanbieter-Dateien ins erste -I Verzeichnis kopieren');
   WriteLn('      --dry-run       vorgeben, aber keine Datei tatsaechlich aktualisieren');
   WriteLn('      --force         Ausgabedatei immer aktualisieren');
   WriteLn('      --output=DATEI  Ausgabe in DATEI schreiben (Standard aclocal.m4)');
   WriteLn('      --print-ac-dir  Verzeichnis mit systemweiten .m4 Dateien ausgeben');
   WriteLn('      --verbose       ausgeben was getan wird');
   WriteLn('      --version       Versionsnummer ausgeben und beenden');
   WriteLn('      --help          diese Hilfe anzeigen');
  End;
  _Italian:Begin
   WriteLn('ACLOCAL : Genera aclocal.m4 scansionando configure.ac o configure.in');
   WriteLn;
   WriteLn('Uso: aclocal [OPZIONE]...');
   WriteLn;
   WriteLn('  -I DIR              aggiungi directory alla lista di ricerca per file .m4');
   WriteLn('      --install       copia file di terze parti nella prima directory -I');
   WriteLn('      --dry-run       finge di, ma non aggiorna realmente alcun file');
   WriteLn('      --force         aggiorna sempre il file di output');
   WriteLn('      --output=FILE   mette output in FILE (predefinito aclocal.m4)');
   WriteLn('      --print-ac-dir  stampa directory contenente file .m4 di sistema');
   WriteLn('      --verbose       stampa cosa viene fatto');
   WriteLn('      --version       stampa numero di versione ed esce');
   WriteLn('      --help          mostra questo testo di aiuto');
  End;
  _Spain:Begin
   WriteLn('ACLOCAL : Genera aclocal.m4 escaneando configure.ac o configure.in');
   WriteLn;
   WriteLn('Uso: aclocal [OPCION]...');
   WriteLn;
   WriteLn('  -I DIR              agregar directorio a lista de busqueda para archivos .m4');
   WriteLn('      --install       copiar archivos de terceros al primer directorio -I');
   WriteLn('      --dry-run       simular, pero no actualizar realmente ningun archivo');
   WriteLn('      --force         actualizar siempre archivo de salida');
   WriteLn('      --output=ARCHIVO poner salida en ARCHIVO (predeterminado aclocal.m4)');
   WriteLn('      --print-ac-dir  imprimir directorio que contiene archivos .m4 del sistema');
   WriteLn('      --verbose       imprimir lo que se esta haciendo');
   WriteLn('      --version       imprimir numero de version y salir');
   WriteLn('      --help          mostrar este texto de ayuda');
  End;
  Else Begin
   WriteLn('ACLOCAL : Generate aclocal.m4 en analysant configure.ac ou configure.in');
   WriteLn;
   WriteLn('Utilisation: aclocal [OPTION]...');
   WriteLn;
   WriteLn('  -I REP              ajouter repertoire a la liste de recherche pour fichiers .m4');
   WriteLn('      --install       copier fichiers tiers vers le premier repertoire -I');
   WriteLn('      --dry-run       simuler, mais ne pas mettre a jour de fichier');
   WriteLn('      --force         toujours mettre a jour le fichier de sortie');
   WriteLn('      --output=FICHIER mettre sortie dans FICHIER (defaut aclocal.m4)');
   WriteLn('      --print-ac-dir  afficher repertoire contenant fichiers .m4 systeme');
   WriteLn('      --verbose       afficher ce qui est fait');
   WriteLn('      --version       afficher numero de version et quitter');
   WriteLn('      --help          afficher ce texte d''aide');
  End;
 End;
End;

Procedure ProcessConfigureFile;
Var
 ConfigFile:Text;
 AcLocalFile:Text;
 CurrLine:String;
 ConfigFound:Boolean;
Begin
 ConfigFound:=False;
 
 { Rechercher configure.ac ou configure.in }
 Assign(ConfigFile,'configure.ac');
 {$I-}Reset(ConfigFile);{$I+}
 If IOResult=0Then Begin
  ConfigFound:=True;
  If OptVerbose in Options Then Begin
   Case Language of
    _English:WriteLn('Reading configure.ac');
    _Germany:WriteLn('Lese configure.ac');
    _Italian:WriteLn('Lettura configure.ac');
    _Spain:WriteLn('Leyendo configure.ac');
    Else WriteLn('Lecture de configure.ac');
   End;
  End;
 End
  Else
 Begin
  Assign(ConfigFile,'configure.in');
  {$I-}Reset(ConfigFile);{$I+}
  If IOResult=0Then Begin
   ConfigFound:=True;
   If OptVerbose in Options Then Begin
    Case Language of
     _English:WriteLn('Reading configure.in');
     _Germany:WriteLn('Lese configure.in');
     _Italian:WriteLn('Lettura configure.in');
     _Spain:WriteLn('Leyendo configure.in');
     Else WriteLn('Lecture de configure.in');
    End;
   End;
  End;
 End;
 
 If Not ConfigFound Then Begin
  Case Language of
   _English:WriteLn('aclocal: configure.ac or configure.in not found');
   _Germany:WriteLn('aclocal: configure.ac oder configure.in nicht gefunden');
   _Italian:WriteLn('aclocal: configure.ac o configure.in non trovato');
   _Spain:WriteLn('aclocal: configure.ac o configure.in no encontrado');
   Else WriteLn('aclocal: configure.ac ou configure.in non trouve');
  End;
  Halt(1);
 End;
 
 If Not(OptDryRun in Options)Then Begin
  { Creer aclocal.m4 }
  Assign(AcLocalFile,OutputFile);
  {$I-}Rewrite(AcLocalFile);{$I+}
  If IOResult<>0Then Begin
   Case Language of
    _English:WriteLn('aclocal: cannot create ',OutputFile);
    _Germany:WriteLn('aclocal: kann ',OutputFile,' nicht erstellen');
    _Italian:WriteLn('aclocal: impossibile creare ',OutputFile);
    _Spain:WriteLn('aclocal: no se puede crear ',OutputFile);
    Else WriteLn('aclocal: impossible de creer ',OutputFile);
   End;
   Close(ConfigFile);
   Halt(1);
  End;
  
  WriteLn(AcLocalFile,'# generated automatically by aclocal 1.0 -*- Autoconf -*-');
  WriteLn(AcLocalFile,'');
  WriteLn(AcLocalFile,'# Copyright (C) 2026 Sylvain Maltais (support@gladir.com)');
  WriteLn(AcLocalFile,'');
  WriteLn(AcLocalFile,'# Permission is hereby granted, free of charge, to any person obtaining');
  WriteLn(AcLocalFile,'# a copy of this software and associated documentation files (the');
  WriteLn(AcLocalFile,'# "Software"), to deal in the Software without restriction, including');
  WriteLn(AcLocalFile,'# without limitation the rights to use, copy, modify, merge, publish,');
  WriteLn(AcLocalFile,'# distribute, sublicense, and/or sell copies of the Software, and to');
  WriteLn(AcLocalFile,'# permit persons to whom the Software is furnished to do so, subject to');
  WriteLn(AcLocalFile,'# the following conditions:');
  WriteLn(AcLocalFile,'');
  WriteLn(AcLocalFile,'# The above copyright notice and this permission notice shall be');
  WriteLn(AcLocalFile,'# included in all copies or substantial portions of the Software.');
  WriteLn(AcLocalFile,'');
  WriteLn(AcLocalFile,'# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,');
  WriteLn(AcLocalFile,'# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF');
  WriteLn(AcLocalFile,'# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.');
  WriteLn(AcLocalFile,'# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY');
  WriteLn(AcLocalFile,'# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,');
  WriteLn(AcLocalFile,'# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE');
  WriteLn(AcLocalFile,'# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.');
  WriteLn(AcLocalFile,'');
  
  { Analyser le fichier configure }
  While Not EOF(ConfigFile)do Begin
   ReadLn(ConfigFile,CurrLine);
   { Ici on pourrait analyser les macros AC_* et AM_* }
   If OptVerbose in Options Then Begin
    If Pos('AC_',CurrLine)>0Then Begin
     Case Language of
      _English:WriteLn('Found autoconf macro: ',CurrLine);
      _Germany:WriteLn('Autoconf-Makro gefunden: ',CurrLine);
      _Italian:WriteLn('Trovata macro autoconf: ',CurrLine);
      _Spain:WriteLn('Encontrada macro autoconf: ',CurrLine);
      Else WriteLn('Macro autoconf trouvee: ',CurrLine);
     End;
    End;
   End;
  End;
  
  Close(AcLocalFile);
 End;
 
 Close(ConfigFile);
 
 If OptVerbose in Options Then Begin
  Case Language of
   _English:WriteLn('aclocal: writing ',OutputFile);
   _Germany:WriteLn('aclocal: schreibe ',OutputFile);
   _Italian:WriteLn('aclocal: scrittura ',OutputFile);
   _Spain:WriteLn('aclocal: escribiendo ',OutputFile);
   Else WriteLn('aclocal: ecriture de ',OutputFile);
  End;
 End;
End;

Procedure ParseParameters;
Var
 Param:String;
Begin
 For I:=1 to ParamCount do Begin
  Param:=ParamStr(I);
  If (Length(Param)>0)and(Param[1]='-')Then Begin
   If Param='--help'Then Options:=Options+[OptHelp]Else
   If Param='--version'Then Options:=Options+[OptVersion]Else
   If Param='--dry-run'Then Options:=Options+[OptDryRun]Else
   If Param='--force'Then Options:=Options+[OptForce]Else
   If Param='--install'Then Options:=Options+[OptInstall]Else
   If Param='--print-ac-dir'Then Options:=Options+[OptPrint]Else
   If Param='--verbose'Then Options:=Options+[OptVerbose]Else
   If Copy(Param,1,9)='--output='Then Begin
    Options:=Options+[OptOutput];
    OutputFile:=Copy(Param,10,255);
   End
    Else
   If Copy(Param,1,2)='-I'Then Begin
    If Length(Param)>2Then AcLocalDir:=Copy(Param,3,255)
                      Else AcLocalDir:=ParamStr(I+1);
   End;
  End;
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
  If StrToUpper(Copy(TmpLanguage,1,2))='SP'Then Language:=_Spain;
 End;
 
 Options:=[];
 OutputFile:='aclocal.m4';
 AcLocalDir:='';
 SystemDir:='/usr/share/aclocal';
 
 ParseParameters;
 
 If OptHelp in Options Then Begin
  ShowHelp;
 End
  Else
 If OptVersion in Options Then Begin
  ShowVersion;
 End
  Else
 If OptPrint in Options Then Begin
  WriteLn(SystemDir);
 End
  Else
 Begin
  ProcessConfigureFile;
 End;
END.
