{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Cree un script pour restituer les noms de fichiers UNIX
}

Program MKMANIFEST;

{$IFDEF FPC}
 {$MODE TP}
 {$H-}
{$ENDIF}

Uses DOS;

Type
 TLanguage=(_French,_English,_Germany,_Italian,_Spain,_Albanian,
            _Portuguese,_Swedish,_Danish,_Japanese);

Const
 Descriptions:Array[TLanguage]of String[110]=(
  'Cette commande permet de fabriquer un manifeste pour restituer les noms de fichiers UNIX.',
  'Creates a manifest to restore UNIX file names.',
  'Erstellt ein Manifest zur Wiederherstellung von UNIX-Dateinamen.',
  'Crea un manifesto per ripristinare i nomi dei file UNIX.',
  'Crea un manifiesto para restaurar los nombres de archivos UNIX.',
  'Krijon nje manifest per te rikthyer emrat e skedareve UNIX.',
  'Cria um manifesto para restaurar os nomes de arquivos UNIX.',
  'Skapar ett manifest som aterstaller UNIX-filnamn.',
  'Opretter et manifest til at gendanne UNIX-filnavne.',
  'UNIX fairumei o fukugen suru manifesuto o sakusei shimasu.');
 FileHelp:Array[TLanguage]of String[110]=(
  '  files       Noms UNIX; les chemins sont retires, aucun fichier n''est lu.',
  '  files       UNIX names; paths are removed, no files are read.',
  '  files       UNIX-Namen; Pfade werden entfernt, Dateien werden nicht gelesen.',
  '  files       Nomi UNIX; i percorsi sono rimossi, nessun file viene letto.',
  '  files       Nombres UNIX; se quitan las rutas, no se leen archivos.',
  '  files       Emra UNIX; shtigjet hiqen, skedaret nuk lexohen.',
  '  files       Nomes UNIX; os caminhos sao removidos, nenhum arquivo e lido.',
  '  files       UNIX-namn; sokvagar tas bort, inga filer lases.',
  '  files       UNIX-navne; stier fjernes, ingen filer laeses.',
  '  files       UNIX mei; pasu wa torinozoki, fairu wa yomimasen.');
 OutputHelp:Array[TLanguage]of String[110]=(
  'Ecrit les commandes mv sur la sortie standard (conversion DOS 8.3 historique).',
  'Writes mv commands to standard output (historical DOS 8.3 conversion).',
  'Schreibt mv-Befehle auf die Standardausgabe (historische DOS-8.3-Umwandlung).',
  'Scrive comandi mv sullo standard output (conversione DOS 8.3 storica).',
  'Escribe comandos mv en la salida estandar (conversion DOS 8.3 historica).',
  'Shkruan komanda mv ne daljen standarde (konvertimi historik DOS 8.3).',
  'Escreve comandos mv na saida padrao (conversao DOS 8.3 historica).',
  'Skriver mv-kommandon till standardutmatningen (historisk DOS 8.3-konvertering).',
  'Skriver mv-kommandoer til standarduddata (historisk DOS 8.3-konvertering).',
  'mv komando o hyojun shutsuryoku ni kakimasu (kyushiki DOS 8.3 henkan).');
 LimitHelp:Array[TLanguage]of String[110]=(
  'Pas de noms VFAT ni de resolution des collisions; executer dans le repertoire des fichiers.',
  'No VFAT names or collision resolution; run the script in the files'' directory.',
  'Keine VFAT-Namen oder Kollisionsaufloesung; Skript im Dateiverzeichnis ausfuehren.',
  'Niente nomi VFAT o gestione collisioni; eseguire lo script nella cartella dei file.',
  'Sin nombres VFAT ni resolucion de colisiones; ejecute el script en el directorio de archivos.',
  'Pa emra VFAT ose zgjidhje perplasjesh; ekzekutoni skriptin ne dosjen e skedareve.',
  'Sem nomes VFAT ou resolucao de colisoes; execute o script no diretorio dos arquivos.',
  'Inga VFAT-namn eller kollisionslosningar; kor skriptet i filernas katalog.',
  'Ingen VFAT-navne eller kollisionsloesning; koer scriptet i filernes mappe.',
  'VFAT mei ya shototsu kaiketsu wa nashi; fairu no direkutori de jikko shite kudasai.');
 MissingError:Array[TLanguage]of String[90]=(
  'aucun nom de fichier indique', 'no file names specified',
  'keine Dateinamen angegeben', 'nessun nome di file specificato',
  'no se indicaron nombres de archivos', 'nuk jane dhene emra skedaresh',
  'nenhum nome de arquivo indicado', 'inga filnamn angivna',
  'ingen filnavne angivet', 'fairumei ga shitei sarete imasen');
 NameError:Array[TLanguage]of String[90]=(
  'nom de fichier invalide', 'invalid file name',
  'ungueltiger Dateiname', 'nome di file non valido',
  'nombre de archivo no valido', 'emer skedari i pavlefshem',
  'nome de arquivo invalido', 'ogiltigt filnamn',
  'ugyldigt filnavn', 'muko na fairumei');
 WriteError:Array[TLanguage]of String[90]=(
  'erreur d''ecriture sur la sortie standard', 'error writing standard output',
  'Fehler beim Schreiben der Standardausgabe', 'errore di scrittura sullo standard output',
  'error al escribir en la salida estandar', 'gabim shkrimi ne daljen standarde',
  'erro ao escrever na saida padrao', 'fel vid skrivning till standardutmatningen',
  'fejl ved skrivning til standarduddata', 'hyojun shutsuryoku no kakikomi era');

Var
 Language:TLanguage;
 I,FirstFile:Integer;
 Argument,Name,ShortName:String;
 Failed:Boolean;

Function StrToUpper(S:String):String;
Var
 J:Integer;
Begin
 For J:=1 to Length(S)Do
  If S[J]in['a'..'z']Then S[J]:=Chr(Ord(S[J])-32);
 StrToUpper:=S;
End;

Procedure InitLanguage;
Var
 S:String;
Begin
 S:=StrToUpper(GetEnv('LANGUAGE'));
 Language:=_French;
 If S='EN'Then Language:=_English Else
 If S='GR'Then Language:=_Germany Else
 If S='IT'Then Language:=_Italian Else
 If S='SP'Then Language:=_Spain Else
 If(S='SQ')Or(S='ALB')Then Language:=_Albanian Else
 If(S='PT')Or(S='PRT')Then Language:=_Portuguese Else
 If(S='SE')Or(S='SWE')Then Language:=_Swedish Else
 If(S='DK')Or(S='DNK')Then Language:=_Danish Else
 If(S='JP')Or(S='JPN')Then Language:=_Japanese;
End;

Procedure Err(Const S:String);
Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'mkmanifest: ',S);
 {$ELSE}
 WriteLn('mkmanifest: ',S);
 {$ENDIF}
 Failed:=True;
End;

Procedure CheckOutput;
Var
 Code:Integer;
Begin
 Code:=IOResult;
 If Code<>0Then Begin
  Err(WriteError[Language]);
  Halt(1);
 End;
End;

Procedure ShowUsage;
Begin
 WriteLn('Syntaxe / Usage: mkmanifest [files]');
End;

Procedure ShowHelp;
Begin
 WriteLn('MKMANIFEST : ',Descriptions[Language]);
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn(FileHelp[Language]);
 WriteLn('  /?, --help, -h, /h, /H');
 WriteLn('  -V, --version');
 WriteLn('  --          Fin des options / End of options');
 WriteLn;
 WriteLn(OutputHelp[Language]);
 WriteLn(LimitHelp[Language]);
 WriteLn;
 WriteLn('  mkmanifest very_long_name 2.many.dots illegal: good.c prn.dev Capital > manifest');
 WriteLn('  sh manifest');
End;

Function BaseName(Const S:String):String;
Var
 J,Start:Integer;
Begin
 Start:=1;
 For J:=1 to Length(S)Do Begin
  If S[J]='/'Then Start:=J+1;
  {$IFNDEF UNIX}
  If S[J]='\'Then Start:=J+1;
  {$ENDIF}
 End;
 {$IFNDEF UNIX}
 If(Start=1)And(Length(S)>=2)Then
  If S[2]=':'Then Start:=3;
 {$ENDIF}
 BaseName:=Copy(S,Start,255);
End;

Function DOSName(Const S:String):String;
Var
 Stem,Ext,UpperStem:String;
 J,Dot:Integer;

 Function ConvertPart(Const Part:String;Limit:Integer):String;
 Var
  K:Integer;
  R:String;
 Begin
  R:=Copy(Part,1,Limit);
  For K:=1 to Length(R)Do Begin
   If R[K]in['A'..'Z']Then R[K]:=Chr(Ord(R[K])+32);
   If(R[K]in['^','+','=','/','[',']',':','''',',','?','*',
              '\','<','>','|','"','.',' '])Or
     (Ord(R[K])<32)Or(Ord(R[K])=127)Then R[K]:='x';
  End;
  ConvertPart:=R;
 End;

Begin
 Dot:=0;
 For J:=1 to Length(S)Do If S[J]='.'Then Dot:=J;
 If Dot=0Then Begin
  Stem:=S;
  Ext:='';
 End
 Else Begin
  Stem:=Copy(S,1,Dot-1);
  Ext:=Copy(S,Dot+1,255);
 End;
 { La convention documentee ajoute x devant les anciens noms de peripheriques. }
 UpperStem:=StrToUpper(Stem);
 If(UpperStem='CON')Or(UpperStem='AUX')Or
   (UpperStem='PRN')Or(UpperStem='NUL')Or
   (UpperStem='COM1')Or(UpperStem='COM2')Or
   (UpperStem='LPT1')Or(UpperStem='LPT2')Or
   (UpperStem='LPT3')Then Stem:='x'+Stem;
 If Stem=''Then Stem:='x';
 Stem:=ConvertPart(Stem,8);
 Ext:=ConvertPart(Ext,3);
 If Ext<>''Then Stem:=Stem+'.'+Ext;
 DOSName:=Stem;
End;

Procedure WriteShellName(Const S:String);
Var
 J:Integer;
 Safe:Boolean;
Begin
 Safe:=Length(S)>0;
 For J:=1 to Length(S)Do
  If Not(S[J]in['a'..'z','A'..'Z','0'..'9','_','-','.','/',
                ':','@','%','+',',','='])Then Safe:=False;
 {$I-}
 If Safe Then Begin
  If S[1]='-'Then Write('./');
  Write(S);
 End
 Else Begin
  Write('''');
  If(Length(S)>0)Then
   If S[1]='-'Then Write('./');
  For J:=1 to Length(S)Do
   If S[J]=''''Then Write('''\''''')Else Write(S[J]);
  Write('''');
 End;
 {$I+}
 CheckOutput;
End;

Procedure WriteMove(Const Source,Target:String);
Begin
 {$I-}Write('mv ');{$I+}
 CheckOutput;
 WriteShellName(Source);
 {$I-}Write(' ');{$I+}
 CheckOutput;
 WriteShellName(Target);
 { LF seul pour que le script produit sous DOS/Windows reste utilisable sous UNIX. }
 {$I-}Write(#10);{$I+}
 CheckOutput;
End;

BEGIN
 InitLanguage;
 Failed:=False;
 FirstFile:=1;
 Argument:=ParamStr(1);
 If Argument='--'Then FirstFile:=2
 Else Begin
  If(Argument='/?')Or(Argument='--help')Or(Argument='-h')Or
    (Argument='/h')Or(Argument='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If(Argument='-V')Or(Argument='--version')Then Begin
   WriteLn('MKMANIFEST - Version 1.0-Pascal');
   Halt(0);
  End;
 End;
 If FirstFile>ParamCount Then Begin
  Err(MissingError[Language]);
  {$IFDEF FPC}
  WriteLn(StdErr,'Syntaxe / Usage: mkmanifest [files]');
  {$ELSE}
  ShowUsage;
  {$ENDIF}
  Halt(1);
 End;
 For I:=FirstFile to ParamCount Do Begin
  Name:=BaseName(ParamStr(I));
  If(Name='')Or(Name='.')Or(Name='..')Then Err(NameError[Language])
  Else Begin
   ShortName:=DOSName(Name);
   If ShortName<>Name Then WriteMove(ShortName,Name);
  End;
 End;
 {$I-}Flush(Output);{$I+}
 CheckOutput;
 If Failed Then Halt(1);
END.
