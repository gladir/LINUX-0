{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program ACLOCAL;

Uses DOS;

Type
 TOption=Set of (OptDryRun, OptForce, OptHelp, OptInstall, OptOutput, OptPrint, OptVerbose, OptVersion);

Var
 Language:(_French,_English,_Germany,_Italian,_Spain,_Albanian,_Portuguese,_Swedish,_Danish,_Japanese);
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
    _Albanian:WriteLn('Duke lexuar configure.ac');
    _Portuguese:WriteLn('Lendo configure.ac');
    _Swedish:WriteLn('LÑser configure.ac');
    _Danish:WriteLn('Laeser configure.ac');
    _Japanese:WriteLn('configure.ac o yonde imasu');
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
     _Albanian:WriteLn('Duke lexuar configure.in');
     _Portuguese:WriteLn('Lendo configure.in');
     _Swedish:WriteLn('LÑser configure.in');
     _Danish:WriteLn('Laeser configure.in');
     _Japanese:WriteLn('configure.in o yonde imasu');
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
   _Albanian:WriteLn('aclocal: configure.ac ose configure.in nuk u gjet');
   _Portuguese:WriteLn('aclocal: configure.ac ou configure.in nao encontrado');
   _Swedish:WriteLn('aclocal: configure.ac eller configure.in inte funnen');
   _Danish:WriteLn('aclocal: configure.ac eller configure.in ikke fundet');
   _Japanese:WriteLn('aclocal: configure.ac matawa configure.in ga mitsukarimasen');
   Else WriteLn('aclocal: configure.ac ou configure.in non trouvÇ');
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
    _Albanian:WriteLn('aclocal: nuk mund tâ krijoj ',OutputFile);
    _Portuguese:WriteLn('aclocal: nao Ç possivel criar ',OutputFile);
    _Swedish:WriteLn('aclocal: kan inte skapa ',OutputFile);
    _Danish:WriteLn('aclocal: kan ikke oprette ',OutputFile);
    _Japanese:WriteLn('aclocal: ',OutputFile,' o sakusei dekimasen');
    Else WriteLn('aclocal: impossible de crÇer ',OutputFile);
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
      _Albanian:WriteLn('U gjet makro autoconf: ',CurrLine);
      _Portuguese:WriteLn('Encontrada macro autoconf: ',CurrLine);
      _Swedish:WriteLn('Hittade autoconf-makro: ',CurrLine);
      _Danish:WriteLn('Fundet autoconf-makro: ',CurrLine);
      _Japanese:WriteLn('autoconf makuro ga mitsukatta: ',CurrLine);
      Else WriteLn('Macro autoconf trouvÇe: ',CurrLine);
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
   _Albanian:WriteLn('aclocal: duke shkruar ',OutputFile);
   _Portuguese:WriteLn('aclocal: escrevendo ',OutputFile);
   _Swedish:WriteLn('aclocal: skriver ',OutputFile);
   _Danish:WriteLn('aclocal: skriver ',OutputFile);
   _Japanese:WriteLn('aclocal: ',OutputFile,' o kaite imasu');
   Else WriteLn('aclocal: Çcriture de ',OutputFile);
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
  If StrToUpper(Copy(TmpLanguage,1,2))='SP'Then Language:=_Spain Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='SQ')or
    (StrToUpper(Copy(TmpLanguage,1,3))='ALB')Then Language:=_Albanian Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='PT')or
    (StrToUpper(Copy(TmpLanguage,1,3))='PRT')Then Language:=_Portuguese Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='SE')or
    (StrToUpper(Copy(TmpLanguage,1,3))='SWE')Then Language:=_Swedish Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='DK')or
    (StrToUpper(Copy(TmpLanguage,1,3))='DNK')Then Language:=_Danish Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='JP')or
    (StrToUpper(Copy(TmpLanguage,1,3))='JPN')Then Language:=_Japanese;
 End;
 Options:=[];
 OutputFile:='aclocal.m4';
 AcLocalDir:='';
 SystemDir:='/usr/share/aclocal';
 ParseParameters;
 If OptHelp in Options Then Begin
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
    WriteLn('  -I DIR               agregar directorio a lista de busqueda para archivos .m4');
    WriteLn('      --install        copiar archivos de terceros al primer directorio -I');
    WriteLn('      --dry-run        simular, pero no actualizar realmente ningun archivo');
    WriteLn('      --force          actualizar siempre archivo de salida');
    WriteLn('      --output=ARCHIVO poner salida en ARCHIVO (predeterminado aclocal.m4)');
    WriteLn('      --print-ac-dir   imprimir directorio que contiene archivos .m4 del sistema');
    WriteLn('      --verbose        imprimir lo que se esta haciendo');
    WriteLn('      --version        imprimir numero de version y salir');
    WriteLn('      --help           mostrar este texto de ayuda');
   End;
   _Albanian:Begin
    WriteLn('ACLOCAL : Gjeneron aclocal.m4 duke skanuar configure.ac ose configure.in');
    WriteLn;
    WriteLn('Pârdorimi: aclocal [OPSIONI]...');
    WriteLn;
    WriteLn('  -I DIR               shto direktori nâ listân e kârkimit pâr skedarâ .m4');
    WriteLn('      --install        kopjo skedarâ tâ palâve tâ treta nâ direktorinâ e parâ -I');
    WriteLn('      --dry-run        pretendo, por nâ fakt nuk pârditâso asnjâ skedar');
    WriteLn('      --force          pârditâso gjithmonâ skedarin e daljes');
    WriteLn('      --output=SKEDARI vendos daljen nâ SKEDAR (parazgjedhje aclocal.m4)');
    WriteLn('      --print-ac-dir   shtyp direktorinâ qâ pârmban skedarâ .m4 tâ sistemit');
    WriteLn('      --verbose        shtyp atâ qâ po bâhet');
    WriteLn('      --version        shtyp numrin e versionit dhe dil');
    WriteLn('      --help           trego kâtâ tekst ndihmâse');
   End;
   _Portuguese:Begin
    WriteLn('ACLOCAL : Gera aclocal.m4 escaneando configure.ac ou configure.in');
    WriteLn;
    WriteLn('Uso: aclocal [OPÄAO]...');
    WriteLn;
    WriteLn('  -I DIR               adicionar diret¢rio Ö lista de busca para arquivos .m4');
    WriteLn('      --install        copiar arquivos de terceiros para o primeiro diret¢rio -I');
    WriteLn('      --dry-run        fingir, mas nao atualizar realmente nenhum arquivo');
    WriteLn('      --force          sempre atualizar arquivo de saida');
    WriteLn('      --output=ARQUIVO colocar saida em ARQUIVO (padrao aclocal.m4)');
    WriteLn('      --print-ac-dir   imprimir diret¢rio contendo arquivos .m4 do sistema');
    WriteLn('      --verbose        imprimir o que est† sendo feito');
    WriteLn('      --version        imprimir n£mero da versao e sair');
    WriteLn('      --help           mostrar este texto de ajuda');
   End;
   _Swedish:Begin
    WriteLn('ACLOCAL : Generera aclocal.m4 genom att skanna configure.ac eller configure.in');
    WriteLn;
    WriteLn('AnvÑndning: aclocal [ALTERNATIV]...');
    WriteLn;
    WriteLn('  -I KATALOG          lÑgg till katalog till sîklistan fîr .m4-filer');
    WriteLn('      --install       kopiera tredjepartsfiler till fîrsta -I-katalogen');
    WriteLn('      --dry-run       lÜtsas att, men uppdatera inte verkligen nÜgon fil');
    WriteLn('      --force         uppdatera alltid utdatafilen');
    WriteLn('      --output=FIL    lÑgg utdata i FIL (standard aclocal.m4)');
    WriteLn('      --print-ac-dir  skriv ut katalog som innehÜller systemîvergripande .m4-filer');
    WriteLn('      --verbose       skriv ut vad som gîrs');
    WriteLn('      --version       skriv ut versionsnummer och avsluta');
    WriteLn('      --help          visa denna hjÑlptext');
   End;
   _Danish:Begin
    WriteLn('ACLOCAL : Generer aclocal.m4 ved at scanne configure.ac eller configure.in');
    WriteLn;
    WriteLn('Brug: aclocal [MULIGHED]...');
    WriteLn;
    WriteLn('  -I MAPPE            tilfoj mappe til sogelisten for .m4-filer');
    WriteLn('      --install       kopier tredjepartsfiler til den forste -I-mappe');
    WriteLn('      --dry-run       foregiv at, men opdater ikke faktisk nogen fil');
    WriteLn('      --force         opdater altid outputfilen');
    WriteLn('      --output=FIL    laeg output i FIL (standard aclocal.m4)');
    WriteLn('      --print-ac-dir  udskriv mappe indeholdende systemomfattende .m4-filer');
    WriteLn('      --verbose       udskriv hvad der bliver gjort');
    WriteLn('      --version       udskriv versionsnummer og afslut');
    WriteLn('      --help          vis denne hjaelpetekst');
   End;
   _Japanese:Begin
    WriteLn('ACLOCAL : configure.ac matawa configure.in o sukyan shite aclocal.m4 o seisei');
    WriteLn;
    WriteLn('Shiyoho: aclocal [OPUSHON]...');
    WriteLn;
    WriteLn('  -I DIREKTORƒ™        .m4 fairu no kensaku risuto ni direktori o tsuika');
    WriteLn('      --install       sadopati fairu o saisho no -I direktori ni kopi');
    WriteLn('      --dry-run       furi o suru ga, jissai ni wa fairu o koshin shinai');
    WriteLn('      --force         tsuneni shutsuryoku fairu o koshin');
    WriteLn('      --output=FAIRU  shutsuryoku o FAIRU ni oku (hyojun aclocal.m4)');
    WriteLn('      --print-ac-dir  shisutemu zenpan no .m4 fairu o fukumu direktori o insatsu');
    WriteLn('      --verbose       nani ga okonawa rete iru ka o insatsu');
    WriteLn('      --version       bajon bango o insatsu shite shuryo');
    WriteLn('      --help          kono herupu tekisuto o hyoji');
   End;
   Else Begin
    WriteLn('ACLOCAL : Cette commande permet de gÇnÇrer aclocal.m4 en analysant configure.ac ou configure.in.');
    WriteLn;
    WriteLn('Syntaxe : aclocal [OPTION]...');
    WriteLn;
    WriteLn('  -I REP               ajouter le rÇpertoire Ö la liste de recherche pour des fichiers .m4');
    WriteLn('      --install        copier les fichiers tiers vers le premier rÇpertoire -I');
    WriteLn('      --dry-run        simuler, mais ne pas mettre Ö jour de fichier');
    WriteLn('      --force          toujours mettre Ö jour le fichier de sortie');
    WriteLn('      --output=FICHIER mettre la sortie dans FICHIER (defaut aclocal.m4)');
    WriteLn('      --print-ac-dir   afficher le rÇpertoire contenant les fichiers .m4 systäme');
    WriteLn('      --verbose        afficher ce qui est fait');
    WriteLn('      --version        afficher le numÇro de version et quitter');
    WriteLn('      --help           afficher ce texte d''aide');
   End;
  End;
 End
  Else
 If OptVersion in Options Then Begin
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
   _Albanian:Begin
    WriteLn('aclocal 1.0 - Klon Pascal i coreutils, linux, unix ose corail');
    WriteLn('Licencâ MIT');
    WriteLn;
    WriteLn('Shkruar nga Sylvain Maltais');
   End;
   _Portuguese:Begin
    WriteLn('aclocal 1.0 - Clone Pascal de coreutils, linux, unix ou corail');
    WriteLn('Licenáa MIT');
    WriteLn;
    WriteLn('Escrito por Sylvain Maltais');
   End;
   _Swedish:Begin
    WriteLn('aclocal 1.0 - Pascal-klon av coreutils, linux, unix eller corail');
    WriteLn('MIT-licens');
    WriteLn;
    WriteLn('Skriven av Sylvain Maltais');
   End;
   _Danish:Begin
    WriteLn('aclocal 1.0 - Pascal-klon af coreutils, linux, unix eller corail');
    WriteLn('MIT-licens');
    WriteLn;
    WriteLn('Skrevet af Sylvain Maltais');
   End;
   _Japanese:Begin
    WriteLn('aclocal 1.0 - coreutils, linux, unix matawa corail no Pascal kur≈çn');
    WriteLn('MIT raisensu');
    WriteLn;
    WriteLn('Sylvain Maltais ni yotte kakareta');
   End;
   Else Begin
    WriteLn('aclocal 1.0 - Clone Pascal de coreutils, linux, unix ou corail');
    WriteLn('Licence MIT');
    WriteLn;
    WriteLn('êcrit par Sylvain Maltais');
   End;
  End;
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