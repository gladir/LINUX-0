{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7)
  @description: SH - interpreteur de commandes (shell) du noyau KERNEL16
                de LINUX-0, dans le style de sh sous Linux. Invite PS1,
                commandes internes (cd, echo, export, test, ...), variables,
                redirections > >> < 2>, tuyaux |, && || ;, if/for/while,
                scripts .SH, globbing * ?, historique et edition de ligne.
                Messages en 5 langues (variable LANGUAGE : FR par defaut,
                EN, GR, SP, IT).
}

Program SH;

{$M 32000,0,0}

Uses Crt,DOS;

Const
 MaxArg=15;       { nombre maximal d'arguments d'une commande - 1 }
 MaxHist=50;      { taille de l'historique }
 MaxVars=24;      { variables locales (non exportees) }
 MaxAlias=12;
 MaxFrame=3;      { imbrication maximale de scripts }
 EnvMax=2048;     { taille du bloc d'environnement }
 NoH=$FFFF;       { handle invalide }

 { drapeaux d'un mot lu }
 fQuoted=1;       { guillemets presents }
 fSingle=2;       { apostrophes presentes }
 fGlob=4;         { * ou ? hors guillemets }
 fVar=8;          { expansion de variable hors guillemets }

 { separateurs }
 sepSeq=1;        { ; }
 sepAnd=2;        { && }
 sepOr=3;         { || }
 sepPipe=4;       { | }

 { mots-cles }
 kwThen=1;
 kwElif=2;
 kwElse=4;
 kwFi=8;
 kwDo=16;
 kwDone=32;
 kwOpen=128;      { if for while }

 { numeros de messages }
 mBanner=1;   mNotFound=2; mNoFile=3;   mNoDir=4;    mSyntax=5;
 mTooLong=6;  mTooMany=7;  mArgLong=8;  mCantCreate=10; mEnvFull=11;
 mIsBuiltin=13; mIsAlias=14; mIs=15;  mNumReq=17;  mEofUnexp=18;
 mTooDeep=19; mNoHome=20; mNoOldPwd=21; mBadId=22;  mExecFail=23;
 mMissArg=25; mHelpHead=26; mHelpTail=27; mNotFoundT=30; mCantMkdir=33;
 hFirst=40;       { 40.. : descriptions de l'aide }
 hCount=21;

 BuiltinCount=30;
 BuiltinNames:Array[1..BuiltinCount]of String[8]=(
  'cd','pwd','echo','export','set','unset','env','exit','logout','help',
  'history','alias','unalias','type','source','.','read','test','[','true',
  'false','mkdir','clear','ver','uname','sleep','break','continue',':','shift'
 );

 HelpSyn:Array[0..hCount-1]of String[18]=(
  'cd [rep|-|~]','pwd','echo [-n] txt','export [VAR[=val]]',
  'set / unset VAR','env','exit [n]','history','alias / unalias',
  'type nom','source f / . f','read [-p t] VAR','test / [ expr ]',
  'true / false','mkdir [-p] rep','clear','ver / uname [-a]','sleep n',
  'shift/break/cont.','if..then..fi','for..do..done'
 );

Type
 TStr12=String[12];
 TStr15=String[15];
 TStr127=String[127];
 TPath79=String[79];

 TArgs=Record
  N:Integer;
  Over:Boolean;
  A:Array[0..MaxArg]of String[127];
  NoConv:Array[0..MaxArg]of Boolean;
 End;

 TSpec=Record
  InF,OutF,ErrF:String[79];
  OutApp,ErrApp,ErrToOut,Bad:Boolean;
 End;

 TRedir=Record
  SIn,SOut,SErr,OutH,OldH:Word;
 End;

 TReader=Record
  H,Size,Pos,Len:Word;
  Buf:Array[0..127]of Byte;
 End;

 TVarRec=Record
  Name:String[15];
  Val:String[127];
 End;

 TAliasRec=Record
  Name:String[15];
  Val:String[79];
 End;

 TFrame=Record
  Cnt:Byte;
  A:Array[0..9]of String[63];
 End;

Var
 Lang:Byte;                { 0=FR 1=EN 2=GR 3=SP 4=IT }
 LastStatus:Integer;
 ExitReq:Boolean;
 BrkReq:Byte;              { 1=break 2=continue }
 CtrlC,SemiOK:Boolean;
 AliasDepth,PipeLevel,FrameTop:Byte;
 Vars:Array[1..MaxVars]of TVarRec;
 Aliases:Array[1..MaxAlias]of TAliasRec;
 Hist:Array[1..MaxHist]of String[119];
 HistN:Integer;
 Frames:Array[0..MaxFrame]of TFrame;
 EnvSeg,EnvCap:Word;
 EnvBuf:Array[0..EnvMax-1]of Byte;
 EnvLen:Integer;
 CurOutH:Word;
 ErrOut:Text;
 StdR:TReader;
 RootDrive:Char;
 TmpDir:String[63];
 Line:String;
 ZBuf:Array[0..127]of Char;

{ ---------------------------------------------------------------------
  Couche bas niveau (INT 21h). Sous Free Pascal (verification de syntaxe
  seulement) ces routines sont remplacees par des bouchons.
  --------------------------------------------------------------------- }
{$IFDEF FPC}
Type
 Registers=Record
  Case Integer of
   0:(AX,BX,CX,DX,BP,SI,DI,DS,ES,Flags:Word);
   1:(AL,AH,BL,BH,CL,CH,DL,DH:Byte);
 End;
Const
 FCarry=1;
Var
 PrefixSeg:Word;
Procedure MsDos(Var R:Registers);Begin R.Flags:=1;End;
Function SSeg:Word;Begin SSeg:=0;End;
Function SPtr:Word;Begin SPtr:=65535;End;
Function PeekB(S,O:Word):Byte;Begin PeekB:=0;End;
Function PeekW(S,O:Word):Word;Begin PeekW:=0;End;
Procedure PokeB(S,O:Word;V:Byte);Begin End;
Procedure PokeW(S,O:Word;V:Word);Begin End;
{$ELSE}
Function PeekB(S,O:Word):Byte;Begin PeekB:=Mem[S:O];End;
Function PeekW(S,O:Word):Word;Begin PeekW:=MemW[S:O];End;
Procedure PokeB(S,O:Word;V:Byte);Begin Mem[S:O]:=V;End;
Procedure PokeW(S,O:Word;V:Word);Begin MemW[S:O]:=V;End;
{$ENDIF}

{ Le premier mot d'un Text est son handle DOS }
Procedure SetTextHandle(Var F:Text;H:Word);
{$IFNDEF FPC}
Var
 HP:^Word;
{$ENDIF}
Begin
 {$IFNDEF FPC}
 HP:=@F;
 HP^:=H;
 {$ENDIF}
End;

{ INT 21h avec un nom de fichier ASCIIZ en DS:DX }
Procedure CallZ(Var R:Registers;Const Name:String);
Var
 I,L:Integer;
Begin
 L:=Length(Name);
 If L>126 Then L:=126;
 For I:=1 to L do ZBuf[I-1]:=Name[I];
 ZBuf[L]:=#0;
 {$IFNDEF FPC}
 R.DS:=Seg(ZBuf);R.DX:=Ofs(ZBuf);
 {$ENDIF}
 MsDos(R);
End;

{ Mode 0 = lecture, 1 = creation, 2 = ajout ; NoH si erreur }
Function DosFileOpen(Const Name:String;Mode:Byte):Word;
Var
 R:Registers;
 H:Word;
Begin
 DosFileOpen:=NoH;
 If Mode=0 Then R.AX:=$3D00 Else
 If Mode=1 Then Begin R.AH:=$3C;R.CX:=0;End
           Else R.AX:=$3D01;
 CallZ(R,Name);
 If(R.Flags and FCarry)<>0 Then Begin
  If Mode<>2 Then Exit;
  R.AH:=$3C;R.CX:=0;
  CallZ(R,Name);
  If(R.Flags and FCarry)<>0 Then Exit;
  DosFileOpen:=R.AX;
  Exit;
 End;
 H:=R.AX;
 If Mode=2 Then Begin
  R.AX:=$4202;R.BX:=H;R.CX:=0;R.DX:=0;
  MsDos(R);
 End;
 DosFileOpen:=H;
End;

Procedure DosFileClose(H:Word);
Var
 R:Registers;
Begin
 If H=NoH Then Exit;
 R.AH:=$3E;R.BX:=H;
 MsDos(R);
End;

Function DosDup(H:Word):Word;
Var
 R:Registers;
Begin
 R.AH:=$45;R.BX:=H;
 MsDos(R);
 If(R.Flags and FCarry)<>0 Then DosDup:=NoH
                           Else DosDup:=R.AX;
End;

Procedure DosForceDup(Src,Dst:Word);
Var
 R:Registers;
Begin
 R.AH:=$46;R.BX:=Src;R.CX:=Dst;
 MsDos(R);
End;

Function DosIsDevice(H:Word):Boolean;
Var
 R:Registers;
Begin
 R.AX:=$4400;R.BX:=H;
 MsDos(R);
 If(R.Flags and FCarry)<>0 Then DosIsDevice:=False
                           Else DosIsDevice:=(R.DX and $80)<>0;
End;

Function DosRead(H:Word;Var Buf;N:Word):Word;
Var
 R:Registers;
Begin
 R.AH:=$3F;R.BX:=H;R.CX:=N;
 {$IFNDEF FPC}
 R.DS:=Seg(Buf);R.DX:=Ofs(Buf);
 {$ENDIF}
 MsDos(R);
 If(R.Flags and FCarry)<>0 Then DosRead:=0
                           Else DosRead:=R.AX;
End;

{ ---------------------------------------------------------------------
  Chaines
  --------------------------------------------------------------------- }
Function UpStr(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do S[I]:=UpCase(S[I]);
 UpStr:=S;
End;

Function LowC(C:Char):Char;Begin
 If C in['A'..'Z']Then LowC:=Chr(Ord(C)+32)
                  Else LowC:=C;
End;

Function LoStr(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do S[I]:=LowC(S[I]);
 LoStr:=S;
End;

Function IntStr(N:LongInt):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

Function StrInt(Const S:String;Var N:LongInt):Boolean;
Var
 E:Integer;
Begin
 Val(S,N,E);
 StrInt:=(E=0)and(S<>'');
End;

Function Pad2(N:Word):String;
Begin
 If N<10 Then Pad2:='0'+IntStr(N)
         Else Pad2:=IntStr(N);
End;

Function TrimL(Const S:String):String;
Var
 I:Integer;
Begin
 I:=1;
 While(I<=Length(S))and(S[I]in[' ',#9])do Inc(I);
 TrimL:=Copy(S,I,255);
End;

Function TrimR(S:String):String;
Var
 I:Integer;
Begin
 I:=Length(S);
 While(I>0)and(S[I]in[' ',#9,#13,#10])do Dec(I);
 S[0]:=Chr(I);
 TrimR:=S;
End;

{ '/' devient '\' (separateur de chemin DOS) }
Function SlashToBack(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do If S[I]='/'Then S[I]:='\';
 SlashToBack:=S;
End;

{ Conversion d'un argument d'une commande externe : seulement s'il ressemble
  a un chemin (pas d'option -x, pas d'espace ni de signe = ) }
Function ConvArg(Const S:String):String;
Begin
 If(S='')or(S[1]='-')or(Pos('/',S)=0)or(Pos(' ',S)>0)or(Pos('=',S)>0)Then
  ConvArg:=S
 Else
  ConvArg:=SlashToBack(S);
End;

Function IsWild(Const S:String):Boolean;Begin
 IsWild:=(Pos('*',S)>0)or(Pos('?',S)>0);
End;


{ ---------------------------------------------------------------------
  Messages (FR|EN|GR|SP|IT)
  --------------------------------------------------------------------- }
Function MsgRaw(Id:Byte):String;Begin
 Case Id of
  mBanner:MsgRaw:='LINUX-0 KERNEL16 - tapez help|LINUX-0 KERNEL16 - type '+
   'help|LINUX-0 KERNEL16 - help eingeben|LINUX-0 KERNEL16 - escriba help|'+
   'LINUX-0 KERNEL16 - digitare help';
  mNotFound:MsgRaw:='commande introuvable|command not found|Befehl nicht '+
   'gefunden|orden no encontrada|comando non trovato';
  mNoFile:MsgRaw:='Fichier introuvable|No such file|Datei nicht gefunden|'+
   'Archivo no encontrado|File non trovato';
  mNoDir:MsgRaw:='Repertoire introuvable|No such directory|Verzeichnis '+
   'nicht gefunden|Directorio no encontrado|Directory non trovata';
  mSyntax:MsgRaw:='erreur de syntaxe|syntax error|Syntaxfehler|error de '+
   'sintaxis|errore di sintassi';
  mTooLong:MsgRaw:='ligne trop longue|line too long|Zeile zu lang|linea '+
   'demasiado larga|riga troppo lunga';
  mTooMany:MsgRaw:='trop d''arguments|too many arguments|zu viele '+
   'Argumente|demasiados argumentos|troppi argomenti';
  mArgLong:MsgRaw:='liste d''arguments trop longue|argument list too long|'+
   'Argumentliste zu lang|lista de argumentos demasiado larga|lista di '+
   'argomenti troppo lunga';
  mCantCreate:MsgRaw:='impossible de creer le fichier|cannot create file|'+
   'Datei kann nicht erstellt werden|no se puede crear el archivo|'+
   'impossibile creare il file';
  mEnvFull:MsgRaw:='environnement plein|environment full|Umgebung voll|'+
   'entorno lleno|ambiente pieno';
  mIsBuiltin:MsgRaw:='est une commande interne|is a shell builtin|ist ein '+
   'eingebauter Befehl|es una orden interna|e un comando interno';
  mIsAlias:MsgRaw:='est un alias de|is aliased to|ist ein Alias fuer|es un '+
   'alias de|e un alias di';
  mIs:MsgRaw:='est|is|ist|es|e';
  mNumReq:MsgRaw:='argument numerique requis|numeric argument required|'+
   'numerisches Argument erforderlich|se requiere un argumento numerico|'+
   'argomento numerico richiesto';
  mEofUnexp:MsgRaw:='fin de fichier inattendue|unexpected end of file|'+
   'unerwartetes Dateiende|fin de archivo inesperado|fine del file inattesa';
  mTooDeep:MsgRaw:='imbrication trop profonde|nesting too deep|'+
   'Verschachtelung zu tief|anidamiento demasiado profundo|annidamento '+
   'troppo profondo';
  mNoHome:MsgRaw:='HOME non defini|HOME not set|HOME nicht gesetzt|HOME no '+
   'definido|HOME non impostato';
  mNoOldPwd:MsgRaw:='OLDPWD non defini|OLDPWD not set|OLDPWD nicht gesetzt|'+
   'OLDPWD no definido|OLDPWD non impostato';
  mBadId:MsgRaw:='identifiant invalide|not a valid identifier|ungueltiger '+
   'Bezeichner|identificador no valido|identificatore non valido';
  mExecFail:MsgRaw:='echec de l''execution|execution failed|Ausfuehrung '+
   'fehlgeschlagen|fallo de ejecucion|esecuzione fallita';
  mMissArg:MsgRaw:='argument manquant|missing argument|Argument fehlt|falta '+
   'un argumento|argomento mancante';
  mHelpHead:MsgRaw:='Commandes internes (autres : programmes .EXE .COM '+
   '.SH)|Builtins (others: .EXE .COM .SH programs)|Interne Befehle '+
   '(andere: .EXE .COM .SH)|Ordenes internas (otras: .EXE .COM .SH)|'+
   'Comandi interni (altri: .EXE .COM .SH)';
  mHelpTail:MsgRaw:='Syntaxe :|Syntax:|Syntax:|Sintaxis:|Sintassi:';
  mNotFoundT:MsgRaw:='introuvable|not found|nicht gefunden|no encontrado|'+
   'non trovato';
  mCantMkdir:MsgRaw:='impossible de creer le repertoire|cannot create '+
   'directory|Verzeichnis kann nicht erstellt werden|no se puede crear el '+
   'directorio|impossibile creare la directory';
  hFirst:MsgRaw:='change de repertoire|change the working directory|'+
   'Verzeichnis wechseln|cambia de directorio|cambia directory';
  hFirst+1:MsgRaw:='affiche le repertoire courant|print the working '+
   'directory|aktuelles Verzeichnis anzeigen|muestra el directorio actual|'+
   'mostra la directory corrente';
  hFirst+2:MsgRaw:='affiche du texte|print text|Text ausgeben|muestra '+
   'texto|stampa del testo';
  hFirst+3:MsgRaw:='exporte des variables|export variables|Variablen '+
   'exportieren|exporta variables|esporta variabili';
  hFirst+4:MsgRaw:='liste ou supprime des variables|list or remove '+
   'variables|Variablen auflisten oder loeschen|lista o borra variables|'+
   'elenca o rimuove variabili';
  hFirst+5:MsgRaw:='affiche l''environnement|print the environment|Umgebung '+
   'anzeigen|muestra el entorno|mostra l''ambiente';
  hFirst+6:MsgRaw:='quitte le shell|leave the shell|Shell beenden|sale del '+
   'shell|esce dalla shell';
  hFirst+7:MsgRaw:='affiche l''historique|show command history|Befehlsverlauf '+
   'anzeigen|muestra el historial|mostra la cronologia';
  hFirst+8:MsgRaw:='definit ou supprime un alias|define or remove an alias|'+
   'Alias definieren oder loeschen|define o borra un alias|definisce o '+
   'rimuove un alias';
  hFirst+9:MsgRaw:='indique la nature d''une commande|show the kind of a '+
   'command|Art eines Befehls anzeigen|indica el tipo de una orden|indica '+
   'il tipo di un comando';
  hFirst+10:MsgRaw:='execute un script dans le shell|run a script in this '+
   'shell|Skript in dieser Shell ausfuehren|ejecuta un script en este '+
   'shell|esegue uno script in questa shell';
  hFirst+11:MsgRaw:='lit une ligne dans une variable|read a line into a '+
   'variable|Zeile in Variable lesen|lee una linea en una variable|legge '+
   'una riga in una variabile';
  hFirst+12:MsgRaw:='evalue une expression|evaluate an expression|Ausdruck '+
   'auswerten|evalua una expresion|valuta un''espressione';
  hFirst+13:MsgRaw:='codes de retour 0 et 1|exit status 0 and 1|'+
   'Rueckgabecode 0 und 1|codigos de salida 0 y 1|codici di uscita 0 e 1';
  hFirst+14:MsgRaw:='cree des repertoires|create directories|Verzeichnisse '+
   'erstellen|crea directorios|crea directory';
  hFirst+15:MsgRaw:='efface l''ecran|clear the screen|Bildschirm loeschen|'+
   'borra la pantalla|cancella lo schermo';
  hFirst+16:MsgRaw:='version du systeme|system version|Systemversion|'+
   'version del sistema|versione del sistema';
  hFirst+17:MsgRaw:='attend n secondes|wait n seconds|n Sekunden warten|'+
   'espera n segundos|attende n secondi';
  hFirst+18:MsgRaw:='decale les parametres, controle des boucles|shift '+
   'parameters, loop control|Parameter schieben, Schleifensteuerung|'+
   'desplaza parametros, control de bucles|sposta parametri, controllo cicli';
  hFirst+19:MsgRaw:='test conditionnel|conditional|Bedingung|condicional|'+
   'condizionale';
  hFirst+20:MsgRaw:='boucles for et while|for and while loops|for- und '+
   'while-Schleifen|bucles for y while|cicli for e while';
  Else MsgRaw:='?|?|?|?|?';
 End;
End;

Function Msg(Id:Byte):String;
Var
 S:String;
 I,L:Integer;
Begin
 S:=MsgRaw(Id)+'|';
 L:=Lang;
 While L>0 do Begin
  I:=Pos('|',S);
  Delete(S,1,I);
  Dec(L);
 End;
 I:=Pos('|',S);
 Msg:=Copy(S,1,I-1);
End;

{ Message d'erreur du shell, sur la sortie d'erreur standard ; Pre est
  le nom de la commande ou de l'objet fautif, St le code retour }
Procedure Fail(Const Pre:String;Id:Byte;St:Integer);Begin
 Write(ErrOut,'sh: ');
 If Pre<>''Then Write(ErrOut,Pre,': ');
 WriteLn(ErrOut,Msg(Id));
 Flush(ErrOut);
 LastStatus:=St;
End;

{ ---------------------------------------------------------------------
  Environnement (bloc de memoire du PSP) et variables
  --------------------------------------------------------------------- }
Procedure EnvPut(Const T:String);
Var
 I:Integer;
Begin
 For I:=1 to Length(T)do Begin
  If EnvLen<EnvMax Then EnvBuf[EnvLen]:=Ord(T[I]);
  Inc(EnvLen);
 End;
 If EnvLen<EnvMax Then EnvBuf[EnvLen]:=0;
 Inc(EnvLen);
End;

{ Lit la chaine de l'environnement qui commence en Scan }
Function EnvRead(Var Scan:Integer):String;
Var
 S:String;
Begin
 S:='';
 While(Scan<EnvCap)and(PeekB(EnvSeg,Scan)<>0)do Begin
  If Length(S)<255 Then S:=S+Chr(PeekB(EnvSeg,Scan));
  Inc(Scan);
 End;
 Inc(Scan);
 EnvRead:=S;
End;

Function EnvFind(Const Name:String;Var Val:String):Boolean;
Var
 Scan,P:Integer;
 S,U:String;
Begin
 EnvFind:=False;
 If EnvSeg=0 Then Exit;
 U:=UpStr(Name);
 Scan:=0;
 While(Scan<EnvCap-2)and(PeekB(EnvSeg,Scan)<>0)do Begin
  S:=EnvRead(Scan);
  P:=Pos('=',S);
  If(P>1)and(UpStr(Copy(S,1,P-1))=U)Then Begin
   Val:=Copy(S,P+1,255);
   EnvFind:=True;
   Exit;
  End;
 End;
End;

{ Fixe (ou supprime si Del) une variable d'environnement ; False si plein }
Function EnvSet(Name,Val:String;Del:Boolean):Boolean;
Var
 Scan,Start,K,I,Q:Integer;
 Same:Boolean;
Begin
 EnvSet:=False;
 If EnvSeg=0 Then Exit;
 Name:=UpStr(Name)+'=';
 EnvLen:=0;Scan:=0;
 While(Scan<EnvCap-2)and(PeekB(EnvSeg,Scan)<>0)do Begin
  Start:=Scan;K:=1;Same:=True;
  While(Scan<EnvCap)and(PeekB(EnvSeg,Scan)<>0)do Begin
   If(K<=Length(Name))and(UpCase(Chr(PeekB(EnvSeg,Scan)))<>Name[K])Then
    Same:=False;
   Inc(K);
   Inc(Scan);
  End;
  Inc(Scan);
  If Not(Same and(K>Length(Name)))Then
   For I:=Start to Scan-1 do Begin
    If EnvLen<EnvMax Then EnvBuf[EnvLen]:=PeekB(EnvSeg,I);
    Inc(EnvLen);
   End;
 End;
 If Not Del Then EnvPut(Name+Val);
 If EnvLen=0 Then Begin
  EnvBuf[0]:=0;
  EnvLen:=1;
 End;
 EnvBuf[EnvLen]:=0;
 Inc(EnvLen);
 { nombre de chaines et chemin du programme }
 If(Scan+3<EnvCap)and(PeekW(EnvSeg,Scan+1)=1)Then Begin
  Q:=Scan+3;
  While(Q<EnvCap)and(PeekB(EnvSeg,Q)<>0)and(Q-Scan<130)do Inc(Q);
  For I:=Scan+1 to Q do Begin
   If EnvLen<EnvMax Then EnvBuf[EnvLen]:=PeekB(EnvSeg,I);
   Inc(EnvLen);
  End;
 End;
 If EnvLen+2>EnvCap Then Exit;
 For I:=0 to EnvLen-1 do PokeB(EnvSeg,I,EnvBuf[I]);
 EnvSet:=True;
End;

{ Reserve un bloc d'environnement plus grand que celui du PSP (le noyau
  n'en donne qu'un tout petit) ; sans effet si la memoire manque }
Procedure EnvInit;
Var
 R:Registers;
 Old,NewSeg:Word;
 I:Integer;
Begin
 Old:=PeekW(PrefixSeg,$2C);
 EnvSeg:=Old;EnvCap:=0;
 If Old<>0 Then Begin
  EnvCap:=PeekW(Old-1,3);
  If EnvCap>EnvMax div 16 Then EnvCap:=EnvMax div 16;
  EnvCap:=EnvCap*16;
 End;
 {$IFNDEF FPC}
 R.AH:=$4A;R.ES:=PrefixSeg;R.BX:=SSeg-PrefixSeg+4097;
 MsDos(R);
 R.AH:=$48;R.BX:=EnvMax div 16;
 MsDos(R);
 If(R.Flags and FCarry)=0 Then Begin
  NewSeg:=R.AX;
  For I:=0 to EnvMax-1 do Begin
   If I<EnvCap Then PokeB(NewSeg,I,PeekB(Old,I))
               Else PokeB(NewSeg,I,0);
  End;
  PokeW(PrefixSeg,$2C,NewSeg);
  EnvSeg:=NewSeg;
  EnvCap:=EnvMax;
 End;
 {$ENDIF}
End;

Function LocFind(Const N:String):Integer;
Var
 I:Integer;
Begin
 LocFind:=0;
 For I:=1 to MaxVars do If Vars[I].Name=N Then Begin
  LocFind:=I;
  Exit;
 End;
End;

Function GetVar(Name:String;Var V:String):Boolean;
Var
 I:Integer;
Begin
 Name:=UpStr(Name);
 I:=LocFind(Copy(Name,1,15));
 If I>0 Then Begin
  V:=Vars[I].Val;
  GetVar:=True;
 End
  Else
 GetVar:=EnvFind(Name,V);
End;

{ Valeur d'une variable, ou Def si elle est absente ou vide }
Function VarOr(Const Name,Def:String):String;
Var
 V:String;
Begin
 If GetVar(Name,V)and(V<>'')Then VarOr:=V
                            Else VarOr:=Def;
End;

Procedure UpdateLang;
Var
 V:String;
 K:Integer;
Begin
 Lang:=0;
 If GetVar('LANGUAGE',V)Then Begin
  If(V<>'')and(V[1]in['"',''''])Then Delete(V,1,1);
  V:=UpStr(Copy(V,1,2));
  K:=Pos(V,'ENGRSPIT');
  If Odd(K)and(Length(V)=2)Then Lang:=(K+1)shr 1;
 End;
End;

{ Longueur du nom de variable qui commence en S[I] }
Function IdentLen(Const S:String;I,B:Integer):Integer;
Var
 J:Integer;
Begin
 J:=I;
 If(J<=B)and(S[J]in['A'..'Z','a'..'z','_'])Then Begin
  Inc(J);
  While(J<=B)and(S[J]in['A'..'Z','a'..'z','_','0'..'9'])do Inc(J);
 End;
 IdentLen:=J-I;
End;

Function ValidName(Const N:String):Boolean;Begin
 ValidName:=(N<>'')and(Length(N)<=15)and(IdentLen(N,1,Length(N))=Length(N));
End;

{ Fixe une variable : dans l'environnement si elle y est deja (exportee),
  sinon dans la table locale }
Procedure SetVar(Name,Val:String);
Var
 I:Integer;
 T:String;
Begin
 Name:=Copy(UpStr(Name),1,15);
 If EnvFind(Name,T)Then Begin
  If Not EnvSet(Name,Val,False)Then Fail('',mEnvFull,1);
 End
  Else
 Begin
  I:=LocFind(Name);
  If I=0 Then I:=LocFind('');
  If I=0 Then Fail('',mEnvFull,1)
   Else
  Begin
   Vars[I].Name:=Name;
   Vars[I].Val:=Val;
  End;
 End;
 If Name='LANGUAGE'Then UpdateLang;
End;

{ Exporte une variable (avec la valeur Val si HasVal, sinon la sienne) }
Procedure ExportVar(Name:String;HasVal:Boolean;Val:String);
Var
 I:Integer;
Begin
 Name:=Copy(UpStr(Name),1,15);
 I:=LocFind(Name);
 If I>0 Then Begin
  If Not HasVal Then Val:=Vars[I].Val;
  Vars[I].Name:='';
 End
  Else
 If Not HasVal Then If Not EnvFind(Name,Val)Then Val:='';
 If Not EnvSet(Name,Val,False)Then Fail('',mEnvFull,1);
 If Name='LANGUAGE'Then UpdateLang;
End;

Procedure UnsetVar(Name:String);
Var
 I:Integer;
Begin
 Name:=Copy(UpStr(Name),1,15);
 I:=LocFind(Name);
 If I>0 Then Vars[I].Name:='';
 If EnvSet(Name,'',True)Then;
 If Name='LANGUAGE'Then UpdateLang;
End;

{ ---------------------------------------------------------------------
  Repertoire courant en notation Linux, invite
  --------------------------------------------------------------------- }
{ Minuscules et / comme separateur (C:\BIN -> c:/bin) }
Function ToSlash(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 to Length(S)do
  If S[I]='\'Then S[I]:='/'
             Else S[I]:=LowC(S[I]);
 ToSlash:=S;
End;

{ Repertoire courant en notation Linux : /bin, b:/dir }
Function UnixCwd:String;
Var
 S:String;
Begin
 GetDir(0,S);
 S:=ToSlash(S);
 If S[1]=LowC(RootDrive)Then Delete(S,1,2);
 UnixCwd:=S;
End;

Procedure UpdatePwd;Begin
 If EnvSet('PWD',UnixCwd,False)Then;
End;

Procedure ShowPrompt(PS2:Boolean);
Var
 S,T:String;
 I,K:Integer;
 Y,Mo,D,Dw,H,Mi,Se,Hs:Word;
Begin
 If PS2 Then S:=VarOr('PS2','> ')
        Else S:=VarOr('PS1','\u@\h:\w\$ ');
 I:=1;
 While I<=Length(S)do Begin
  If(S[I]='\')and(I<Length(S))Then Begin
   Inc(I);
   Case S[I] of
    'u':Write(VarOr('USER','root'));
    'h':Write(VarOr('HOSTNAME','linux0'));
    'w':Write(UnixCwd);
    'W':Begin
     T:=UnixCwd;
     K:=Length(T);
     While(K>0)and(T[K]<>'/')do Dec(K);
     Write(Copy(T,K+1,255));
     If K=Length(T)Then Write('/');
    End;
    '$':If VarOr('USER','root')='root'Then Write('#')
                                     Else Write('$');
    'n':WriteLn;
    't':Begin
     GetTime(H,Mi,Se,Hs);
     Write(Pad2(H),':',Pad2(Mi),':',Pad2(Se));
    End;
    'd':Begin
     GetDate(Y,Mo,D,Dw);
     Write(Copy('SunMonTueWedThuFriSat',Dw*3+1,3),' ',
           Copy('JanFebMarAprMayJunJulAugSepOctNovDec',Mo*3-2,3),' ',D);
    End;
    'e':Write(#27);
    '[',']':;
    Else Write(S[I]);
   End;
  End
   Else
  Write(S[I]);
  Inc(I);
 End;
End;

{ ---------------------------------------------------------------------
  Analyse lexicale : separateurs, mots-cles, mots, globbing
  --------------------------------------------------------------------- }
{ Affectation PATH=... : le ; fait partie de la valeur (liste DOS) }
Function IsPathAsg(Const S:String;I,B:Integer):Boolean;Begin
 IsPathAsg:=(I+4<=B)and(S[I+4]='=')and(UpStr(Copy(S,I,4))='PATH');
End;

Function KwCode(Const W:String):Byte;
Var
 K:Integer;
Begin
 KwCode:=0;
 K:=Pos(Copy(W+'      ',1,6),
        'then  elif  else  fi    do    done  if    for   while ');
 If(K>0)and((K-1)mod 6=0)Then Begin
  K:=(K-1)div 6;
  If K>5 Then KwCode:=kwOpen
         Else KwCode:=1 shl K;
 End;
End;

{ Parcourt S[P..B] hors guillemets.
  Mode 0 : premier ; && || de niveau 0 (Kind = separateur)
  Mode 3 : premier | de niveau 0
  Mode 1 : premier mot-cle de Mask (then elif else fi do done) de niveau 0
  Mode 2 : la ligne est-elle incomplete ? (Kind=1 si oui, 2 si guillemet)
  Rend la position trouvee, B+1 sinon. }
Function Walk(Const S:String;P,B:Integer;Mode,Mask:Byte;Var Kind:Byte):Integer;
Var
 I,WS,Depth:Integer;
 AtStart,LastOp,Open,Stop,SemiW:Boolean;
 C:Char;
 K,Sep:Byte;
 W:String[8];
Begin
 I:=P;Depth:=0;AtStart:=True;LastOp:=False;Open:=False;Kind:=0;
 While I<=B do Begin
  C:=S[I];
  If(C=' ')or(C=#9)Then Inc(I)
   Else
  Begin
   Sep:=0;
   If C=';'Then Sep:=sepSeq Else
   If C='|'Then Begin
    If(I<B)and(S[I+1]='|')Then Sep:=sepOr
                          Else Sep:=sepPipe;
   End
    Else
   If(C='&')and(I<B)and(S[I+1]='&')Then Sep:=sepAnd;
   If Sep<>0 Then Begin
    If(Depth=0)and(((Mode=0)and(Sep<>sepPipe))or
      ((Mode=3)and(Sep=sepPipe)))Then Begin
     Walk:=I;
     Kind:=Sep;
     Exit;
    End;
    Inc(I);
    If(Sep=sepAnd)or(Sep=sepOr)Then Inc(I);
    AtStart:=True;
    LastOp:=Sep<>sepSeq;
   End
    Else
   If(C='<')or(C='>')Then Begin
    Inc(I);
    If(C='>')and(I<=B)and(S[I]='>')Then Inc(I);
    If(C='>')and(I<=B)and(S[I]='&')Then Inc(I);
    AtStart:=False;
    LastOp:=False;
   End
    Else
   Begin
    WS:=I;Stop:=False;
    SemiW:=AtStart and IsPathAsg(S,I,B);
    While(I<=B)and Not Stop do Begin
     C:=S[I];
     If(C in[' ',#9,'|','<','>'])or((C=';')and Not SemiW)Then Stop:=True Else
     If(C='&')and(I<B)and(S[I+1]='&')Then Stop:=True Else
     If C=''''Then Begin
      Inc(I);
      While(I<=B)and(S[I]<>'''')do Inc(I);
      If I>B Then Open:=True
             Else Inc(I);
     End
      Else
     If C='"'Then Begin
      Inc(I);
      While(I<=B)and(S[I]<>'"')do Begin
       If(S[I]='\')and(I<B)and(S[I+1]in['"','$'])Then Inc(I);
       Inc(I);
      End;
      If I>B Then Open:=True
             Else Inc(I);
     End
      Else
     If(C='\')and(I<B)and(S[I+1]in['$','"','''',' '])Then Inc(I,2)
                                                      Else Inc(I);
    End;
    LastOp:=False;
    If AtStart Then Begin
     W:=LoStr(Copy(S,WS,I-WS));
     K:=KwCode(W);
     If K=kwOpen Then Begin
      Inc(Depth);
      AtStart:=W<>'for';
     End
      Else
     If(K=kwFi)or(K=kwDone)Then Begin
      If Depth=0 Then Begin
       If(Mode=1)and((K and Mask)<>0)Then Begin
        Walk:=WS;
        Kind:=K;
        Exit;
       End;
      End
       Else
      Dec(Depth);
      AtStart:=False;
     End
      Else
     If K<>0 Then Begin
      If(Depth=0)and(Mode=1)and((K and Mask)<>0)Then Begin
       Walk:=WS;
       Kind:=K;
       Exit;
      End;
      AtStart:=True;
     End
      Else
     AtStart:=False;
    End;
   End;
  End;
 End;
 Walk:=B+1;
 Kind:=0;
 If Mode=2 Then Begin
  If(Depth>0)or LastOp Then Kind:=1;
  If Open Then Kind:=2;
 End;
End;

Function Incomplete(Const S:String):Byte;
Var
 K:Byte;
 Dummy:Integer;
Begin
 Dummy:=Walk(S,1,Length(S),2,0,K);
 Incomplete:=K;
End;

{ Retire le commentaire (# en debut de mot, hors guillemets) }
Function StripComment(Const L:String):String;
Var
 I:Integer;
 Q:Char;
Begin
 Q:=#0;
 I:=1;
 While I<=Length(L)do Begin
  If Q<>#0 Then Begin
   If L[I]=Q Then Q:=#0;
  End
   Else
  If(L[I]='"')or(L[I]='''')Then Q:=L[I] Else
  If(L[I]='#')and((I=1)or(L[I-1]in[' ',#9,';','|','&']))Then Begin
   StripComment:=TrimR(Copy(L,1,I-1));
   Exit;
  End;
  Inc(I);
 End;
 StripComment:=TrimR(L);
End;

{ Expansion des variables (NOM, accolades, ? # 0..9 *) en S[I] (I sur le
  dollar) ; la valeur est ajoutee a W }
Procedure ExpandVar(Const S:String;Var I:Integer;B:Integer;Var W:String);
Var
 Nm:TStr15;
 J,K:Integer;
 V:String;
Begin
 J:=I+1;
 If(J<=B)and(S[J]='{')Then Begin
  Inc(J);
  K:=J;
  While(K<=B)and(S[K]<>'}')do Inc(K);
  Nm:=Copy(S,J,K-J);
  I:=K+1;
 End
  Else
 Begin
  K:=IdentLen(S,J,B);
  If(K=0)and(J<=B)and(S[J]in['0'..'9','?','#','*','@'])Then K:=1;
  Nm:=Copy(S,J,K);
  I:=J+K;
 End;
 V:='$';
 If Nm<>''Then Begin
  V:='';
  Case Nm[1] of
   '?':V:=IntStr(LastStatus);
   '#':V:=IntStr(Frames[FrameTop].Cnt);
   '0'..'9':V:=Frames[FrameTop].A[Ord(Nm[1])-48];
   '*','@':
    For K:=1 to Frames[FrameTop].Cnt do Begin
     If K>1 Then V:=V+' ';
     V:=V+Frames[FrameTop].A[K];
    End;
   Else If Not GetVar(Nm,V)Then V:='';
  End;
 End;
 W:=W+V;
End;

{ Lit un mot en S[I..B] : guillemets, echappements, variables, ~ }
Procedure ReadWord(Const S:String;Var I:Integer;B:Integer;Var W:String;
                   Var Fl:Byte);
Var
 C,Q:Char;
 WS:Integer;
 Stop:Boolean;
Begin
 W:='';Fl:=0;WS:=I;Q:=#0;Stop:=False;
 While(I<=B)and Not Stop do Begin
  C:=S[I];
  If Q<>#0 Then Begin
   If(C='$')and(Q='"')Then ExpandVar(S,I,B,W)
    Else
   Begin
    If C=Q Then Q:=#0 Else
    If(C='\')and(Q='"')and(I<B)and(S[I+1]in['"','$'])Then Begin
     Inc(I);
     W:=W+S[I];
    End
     Else
    W:=W+C;
    Inc(I);
   End;
  End
   Else
  If(C in[' ',#9,'|','<','>'])or((C=';')and Not SemiOK)or
    ((C='&')and(I<B)and(S[I+1]='&'))Then Stop:=True
  Else
  If(C='''')or(C='"')Then Begin
   Q:=C;
   Fl:=Fl or fQuoted;
   If C=''''Then Fl:=Fl or fSingle;
   Inc(I);
  End
   Else
  If(C='\')and(I<B)and(S[I+1]in['$','"','''',' '])Then Begin
   W:=W+S[I+1];
   Fl:=Fl or fQuoted;
   Inc(I,2);
  End
   Else
  If C='$'Then Begin
   Fl:=Fl or fVar;
   ExpandVar(S,I,B,W);
  End
   Else
  If(C='~')and(I=WS)and((I=B)or
    (S[I+1]in[' ',#9,';','|','<','>','/','\']))Then Begin
   W:=VarOr('HOME','\');
   Inc(I);
   If(W[Length(W)]in['/','\'])and(I<=B)and(S[I]in['/','\'])Then Inc(I);
  End
   Else
  Begin
   If C in['*','?']Then Fl:=Fl or fGlob;
   W:=W+C;
   Inc(I);
  End;
 End;
End;

{ Compare un nom de fichier a un modele * ? (sans tenir compte de la casse) }
Function WildMatch(Const P,N:String;PI,NI:Integer):Boolean;
Var
 K:Integer;
Begin
 WildMatch:=False;
 While PI<=Length(P)do Begin
  If P[PI]='*'Then Begin
   While(PI<=Length(P))and(P[PI]='*')do Inc(PI);
   If PI>Length(P)Then Begin
    WildMatch:=True;
    Exit;
   End;
   For K:=NI to Length(N)+1 do
    If WildMatch(P,N,PI,K)Then Begin
     WildMatch:=True;
     Exit;
    End;
   Exit;
  End
   Else
  If NI>Length(N)Then Exit Else
  If(P[PI]<>'?')and(UpCase(P[PI])<>UpCase(N[NI]))Then Exit
   Else
  Begin
   Inc(PI);
   Inc(NI);
  End;
 End;
 WildMatch:=NI>Length(N);
End;

{ Fichier suivant (ordre alphabetique) apres Prev qui verifie le modele ;
  Prev recoit le nom DOS trouve }
Function NextGlob(Const Pat:String;Var Prev:TStr12;Var Res:TStr127):Boolean;
Var
 Rec:SearchRec;
 L,I:Integer;
 Dp,Fp:String;
 Best:TStr12;
 Found:Boolean;
Begin
 NextGlob:=False;
 L:=0;
 For I:=1 to Length(Pat)do If Pat[I]in['/','\',':']Then L:=I;
 Dp:=Copy(Pat,1,L);
 Fp:=Copy(Pat,L+1,255);
 If IsWild(Dp)Then Exit;
 Found:=False;
 Best:='';
 FindFirst(SlashToBack(Dp)+'*.*',ReadOnly or Archive or Directory,Rec);
 While DosError=0 do Begin
  If(Rec.Name[1]<>'.')and WildMatch(Fp,Rec.Name,1,1)Then Begin
   If(Prev='')or(UpStr(Rec.Name)>Prev)Then
    If(Not Found)or(UpStr(Rec.Name)<Best)Then Begin
     Best:=UpStr(Rec.Name);
     Found:=True;
    End;
  End;
  FindNext(Rec);
 End;
 If Found Then Begin
  Prev:=Best;
  Res:=Dp+LoStr(Best);
  NextGlob:=True;
 End;
End;

Procedure InitSpec(Var Sp:TSpec);Begin
 Sp.InF:='';Sp.OutF:='';Sp.ErrF:='';
 Sp.OutApp:=False;Sp.ErrApp:=False;Sp.ErrToOut:=False;Sp.Bad:=False;
End;

Procedure SkipSp(Const S:String;Var I:Integer;B:Integer);Begin
 While(I<=B)and(S[I]in[' ',#9])do Inc(I);
End;

{ Redirection > >> < 2> 2>> 2>&1 en S[I] ; False si ce n'en est pas une }
Function TryRedir(Const S:String;Var I:Integer;B:Integer;Var Sp:TSpec):Boolean;
Var
 C:Char;
 Fd:Byte;
 App:Boolean;
 W:String;
 Fl:Byte;
 Ok:Boolean;
Begin
 C:=S[I];
 Ok:=(C in['<','>'])or((C in['1','2'])and(I<B)and(S[I+1]='>'));
 TryRedir:=Ok;
 If Ok Then Begin
  Fd:=1;
  If C in['1','2']Then Begin
   Fd:=Ord(C)-48;
   Inc(I);
   C:='>';
  End;
  Inc(I);
  App:=(C='>')and(I<=B)and(S[I]='>');
  If App Then Inc(I);
  If(C='>')and(I<=B)and(S[I]='&')Then Begin
   If(Fd=2)and(I<B)and(S[I+1]='1')Then Sp.ErrToOut:=True
                                  Else Sp.Bad:=True;
   Inc(I,2);
  End
   Else
  Begin
   SkipSp(S,I,B);
   ReadWord(S,I,B,W,Fl);
   If W=''Then Sp.Bad:=True;
   If LoStr(W)='/dev/null'Then W:='NUL'
                          Else W:=SlashToBack(W);
   If C='<'Then Sp.InF:=W Else
   If Fd=2 Then Begin
    Sp.ErrF:=W;
    Sp.ErrApp:=App;
   End
    Else
   Begin
    Sp.OutF:=W;
    Sp.OutApp:=App;
   End;
  End;
 End;
End;

{ Ajoute un mot a la liste des arguments (globbing sur place) }
Procedure AddOne(Var A:TArgs;Const W:String;Fl:Byte);
Var
 Prev:TStr12;
 Res:TStr127;
 Any:Boolean;
Begin
 Any:=False;
 If(Fl and fGlob)<>0 Then Begin
  Prev:='';
  While NextGlob(W,Prev,Res)do Begin
   Any:=True;
   If A.N>MaxArg Then A.Over:=True
    Else
   Begin
    A.A[A.N]:=Res;
    A.NoConv[A.N]:=False;
    Inc(A.N);
   End;
  End;
 End;
 If Not Any Then Begin
  If A.N>MaxArg Then A.Over:=True
   Else
  Begin
   A.A[A.N]:=W;
   A.NoConv[A.N]:=(Fl and fSingle)<>0;
   Inc(A.N);
  End;
 End;
End;

{ Ajoute un mot lu : decoupage en champs d'une variable non quotee }
Procedure AddWord(Var A:TArgs;Const W:String;Fl:Byte);
Var
 I,J:Integer;
Begin
 If((Fl and fVar)<>0)and((Fl and fQuoted)=0)Then Begin
  I:=1;
  While I<=Length(W)do Begin
   While(I<=Length(W))and(W[I]in[' ',#9])do Inc(I);
   J:=I;
   While(J<=Length(W))and Not(W[J]in[' ',#9])do Inc(J);
   If J>I Then AddOne(A,Copy(W,I,J-I),Fl);
   I:=J;
  End;
 End
  Else
 AddOne(A,W,Fl);
End;

{ ---------------------------------------------------------------------
  Lecture de lignes (fichier, entree standard), redirections
  --------------------------------------------------------------------- }
Function OpenReader(Var R:TReader;Const Path:String;Size:Word):Boolean;Begin
 R.H:=DosFileOpen(Path,0);
 R.Size:=Size;R.Pos:=0;R.Len:=0;
 OpenReader:=R.H<>NoH;
End;

Procedure CloseReader(Var R:TReader);Begin
 DosFileClose(R.H);
 R.H:=NoH;
End;

{ Lit une ligne (LF ou CR LF) ; False a la fin du fichier }
Function ReadLineFrom(Var R:TReader;Var S:String):Boolean;
Var
 C:Byte;
 Got:Boolean;
Begin
 S:='';Got:=False;
 ReadLineFrom:=False;
 While True do Begin
  If R.Pos>=R.Len Then Begin
   R.Len:=DosRead(R.H,R.Buf,R.Size);
   R.Pos:=0;
   If R.Len=0 Then Begin
    ReadLineFrom:=Got;
    Exit;
   End;
  End;
  C:=R.Buf[R.Pos];
  Inc(R.Pos);
  If C=10 Then Begin
   ReadLineFrom:=True;
   Exit;
  End;
  Got:=True;
  If(C<>13)and(C<>26)and(Length(S)<250)Then S:=S+Chr(C);
 End;
End;

Procedure RedirEnd(Var R:TRedir);Begin
 Flush(Output);
 If R.SErr<>NoH Then Begin
  DosForceDup(R.SErr,2);
  DosFileClose(R.SErr);
 End;
 If R.SOut<>NoH Then Begin
  DosForceDup(R.SOut,1);
  DosFileClose(R.SOut);
 End;
 If R.OutH<>NoH Then Begin
  CurOutH:=R.OldH;
  SetTextHandle(Output,R.OldH);
  DosFileClose(R.OutH);
 End;
 If R.SIn<>NoH Then Begin
  DosForceDup(R.SIn,0);
  DosFileClose(R.SIn);
 End;
End;

{ Met en place les redirections : handles DOS 0/1/2 (pour les programmes
  externes) et handle du Text Output (pour les commandes internes) }
Function RedirBegin(Const Sp:TSpec;Var R:TRedir):Boolean;
Var
 H:Word;
Begin
 RedirBegin:=False;
 R.SIn:=NoH;R.SOut:=NoH;R.SErr:=NoH;R.OutH:=NoH;R.OldH:=CurOutH;
 If Sp.InF<>''Then Begin
  H:=DosFileOpen(Sp.InF,0);
  If H=NoH Then Begin
   Fail(Sp.InF,mNoFile,1);
   Exit;
  End;
  R.SIn:=DosDup(0);
  DosForceDup(H,0);
  DosFileClose(H);
 End;
 If Sp.OutF<>''Then Begin
  If Sp.OutApp Then H:=DosFileOpen(Sp.OutF,2)
               Else H:=DosFileOpen(Sp.OutF,1);
  If H=NoH Then Begin
   Fail(Sp.OutF,mCantCreate,1);
   RedirEnd(R);
   Exit;
  End;
  Flush(Output);
  R.SOut:=DosDup(1);
  DosForceDup(H,1);
  CurOutH:=H;
  SetTextHandle(Output,H);
  R.OutH:=H;
 End;
 If Sp.ErrF<>''Then Begin
  If Sp.ErrApp Then H:=DosFileOpen(Sp.ErrF,2)
               Else H:=DosFileOpen(Sp.ErrF,1);
  If H=NoH Then Begin
   Fail(Sp.ErrF,mCantCreate,1);
   RedirEnd(R);
   Exit;
  End;
  R.SErr:=DosDup(2);
  DosForceDup(H,2);
  DosFileClose(H);
 End
  Else
 If Sp.ErrToOut Then Begin
  R.SErr:=DosDup(2);
  DosForceDup(1,2);
 End;
 RedirBegin:=True;
End;

{ ---------------------------------------------------------------------
  Historique et edition de la ligne de commande (clavier)
  --------------------------------------------------------------------- }
Procedure AddHist(Const L:String);
Var
 I:Integer;
Begin
 If L=''Then Exit;
 If(HistN>0)and(Hist[HistN]=Copy(L,1,119))Then Exit;
 If HistN=MaxHist Then Begin
  For I:=1 to MaxHist-1 do Hist[I]:=Hist[I+1];
 End
  Else
 Inc(HistN);
 Hist[HistN]:=L;
End;

Function ScrW:Integer;Begin
 ScrW:=Lo(WindMax)-Lo(WindMin)+1;
End;

{ Repeint la ligne a partir de (SX,SY) et place le curseur }
Procedure Redraw(Const S:String;P:Integer;SX:Integer;Var SY:Integer;
                 Var OldLen:Integer);
Var
 W,N,Cells:Integer;
Begin
 W:=ScrW;
 GotoXY(SX,SY);
 Write(S);
 N:=OldLen-Length(S);
 If N<0 Then N:=0;
 If N>0 Then Write(' ':N);
 Cells:=SX-1+Length(S)+N;
 SY:=WhereY-(Cells div W);
 OldLen:=Length(S);
 Cells:=SX-1+P;
 GotoXY(Cells mod W+1,SY+Cells div W);
End;

{ Edite une ligne au clavier ; False sur Ctrl+D en debut de ligne }
Function EditLine(Var S:String;UseHist:Boolean):Boolean;
Var
 P,OldLen,SX,SY,HI:Integer;
 K:Char;
 Saved:String;
 Done:Boolean;
Begin
 EditLine:=True;
 CtrlC:=False;
 S:='';P:=0;OldLen:=0;HI:=HistN+1;Saved:='';Done:=False;
 SX:=WhereX;SY:=WhereY;
 While Not Done do Begin
  K:=ReadKey;
  Case K of
   #13:Begin
    Redraw(S,Length(S),SX,SY,OldLen);
    WriteLn;
    Done:=True;
   End;
   #3:Begin
    Write('^C');
    WriteLn;
    S:='';
    CtrlC:=True;
    Done:=True;
   End;
   #4:If S=''Then Begin
    WriteLn;
    EditLine:=False;
    Done:=True;
   End
    Else
   If P<Length(S)Then Delete(S,P+1,1);
   #8:If P>0 Then Begin
    Delete(S,P,1);
    Dec(P);
   End;
   #1:P:=0;
   #5:P:=Length(S);
   #11:S:=Copy(S,1,P);
   #21,#27:Begin
    S:='';
    P:=0;
   End;
   #0:Begin
    K:=ReadKey;
    Case K of
     #75:If P>0 Then Dec(P);
     #77:If P<Length(S)Then Inc(P);
     #71:P:=0;
     #79:P:=Length(S);
     #83:If P<Length(S)Then Delete(S,P+1,1);
     #72:If UseHist and(HI>1)Then Begin
      If HI=HistN+1 Then Saved:=S;
      Dec(HI);
      S:=Hist[HI];
      P:=Length(S);
     End;
     #80:If UseHist and(HI<=HistN)Then Begin
      Inc(HI);
      If HI>HistN Then S:=Saved
                  Else S:=Hist[HI];
      P:=Length(S);
     End;
    End;
   End;
   Else
   If(K>=' ')and(Length(S)<250)Then Begin
    Insert(K,S,P+1);
    Inc(P);
   End;
  End;
  If Not Done Then Redraw(S,P,SX,SY,OldLen);
 End;
End;

{ Ligne physique : clavier si l'entree est la console, sinon le lecteur R }
Function GetPhys(Var R:TReader;Kbd:Boolean;PS2:Boolean;Var S:String):Boolean;
Begin
 If Kbd and DosIsDevice(0)and DosIsDevice(CurOutH)Then Begin
  ShowPrompt(PS2);
  GetPhys:=EditLine(S,True);
 End
  Else
 GetPhys:=ReadLineFrom(R,S);
End;

{ Ligne logique : plusieurs lignes physiques tant qu'un if/for/while,
  un guillemet ou un operateur final reste ouvert }
Function ReadLogical(Var R:TReader;Kbd:Boolean;Var Acc:String):Boolean;
Var
 L,T:String;
 St:Byte;
Begin
 Acc:='';St:=0;ReadLogical:=False;
 Repeat
  If Not GetPhys(R,Kbd,St<>0,L)Then Begin
   If St<>0 Then Fail('',mEofUnexp,2);
   Exit;
  End;
  If CtrlC Then Begin
   Acc:='';
   LastStatus:=130;
   ReadLogical:=True;
   Exit;
  End;
  If St=0 Then Acc:=StripComment(L) Else
  If St=2 Then Acc:=Acc+#13#10+L
   Else
  Begin
   T:=TrimR(Acc);
   L:=StripComment(L);
   If T[Length(T)]in['|','&']Then Acc:=T+' '+L
                             Else Acc:=T+' ; '+L;
  End;
  If Length(Acc)>240 Then Begin
   Fail('',mTooLong,2);
   Acc:='';
   ReadLogical:=True;
   Exit;
  End;
  St:=Incomplete(Acc);
 Until St=0;
 ReadLogical:=True;
End;

{ ---------------------------------------------------------------------
  Recherche et lancement des programmes
  --------------------------------------------------------------------- }
Procedure ExecList(Const S:String;P,B:Integer);Forward;
Procedure RunScript(Const Path:String;Var A:TArgs;First:Integer;
                    IsSource:Boolean);Forward;

Function FileExists(Const P:String):Boolean;
Var
 Rec:SearchRec;
Begin
 FindFirst(P,Archive or ReadOnly or Hidden or SysFile,Rec);
 FileExists:=DosError=0;
End;

{ Fichier ou repertoire : Dir et taille }
Function FileInfo(Const P:String;Var IsDir:Boolean;Var Size:LongInt):Boolean;
Var
 Rec:SearchRec;
 D:String;
Begin
 FileInfo:=False;IsDir:=False;Size:=0;
 D:=SlashToBack(P);
 If(D='')or IsWild(D)Then Exit;
 While(Length(D)>1)and(D[Length(D)]='\')and Not((Length(D)=3)and
   (D[2]=':'))do Delete(D,Length(D),1);
 If(D='\')or(D='.')or(D='..')or(D[Length(D)]=':')or
   ((Length(D)=3)and(D[2]=':'))Then Begin
  IsDir:=True;
  FileInfo:=True;
  Exit;
 End;
 FindFirst(D,Archive or ReadOnly or Hidden or SysFile or Directory,Rec);
 If DosError=0 Then Begin
  FileInfo:=True;
  IsDir:=(Rec.Attr and Directory)<>0;
  Size:=Rec.Size;
 End;
End;

{ Programme (.COM .EXE .SH) dans le repertoire courant puis dans PATH }
Function FindProgram(Const Name:String):TPath79;
Var
 U,Pth:String;
 R:TPath79;
 I:Integer;
 HasExt:Boolean;
Begin
 U:=UpStr(SlashToBack(Name));
 Pth:=VarOr('PATH','');
 HasExt:=False;
 I:=Length(U);
 While(I>0)and Not(U[I]in['\',':'])do Begin
  If U[I]='.'Then HasExt:=True;
  Dec(I);
 End;
 If HasExt Then R:=FSearch(U,Pth)
  Else
 Begin
  R:=FSearch(U+'.COM',Pth);
  If R=''Then R:=FSearch(U+'.EXE',Pth);
  If R=''Then R:=FSearch(U+'.SH',Pth);
 End;
 FindProgram:=R;
End;

{ Ligne de commande DOS des arguments 1.. (limitee a 125 caracteres) }
Function BuildTail(Var A:TArgs;Var Tail:ComStr):Boolean;
Var
 I:Integer;
 T:String;
Begin
 Tail:='';
 BuildTail:=True;
 For I:=1 to A.N-1 do Begin
  T:=A.A[I];
  If Not A.NoConv[I]Then T:=ConvArg(T);
  If(T='')or(Pos(' ',T)>0)Then T:='"'+T+'"';
  If Length(Tail)+Length(T)+1>125 Then BuildTail:=False
                                  Else Tail:=Tail+' '+T;
 End;
End;

Function RunExternal(Var A:TArgs):Integer;
Var
 Prog:PathStr;
 Tail:ComStr;
 C:Word;
Begin
 RunExternal:=127;
 Prog:=FindProgram(A.A[0]);
 If Prog=''Then Fail(A.A[0],mNotFound,127)
  Else
 If Copy(Prog,Length(Prog)-2,3)='.SH'Then Begin
  RunScript(Prog,A,1,False);
  RunExternal:=LastStatus;
 End
  Else
 If Not BuildTail(A,Tail)Then Begin
  Fail(A.A[0],mArgLong,126);
  RunExternal:=126;
 End
  Else
 Begin
  Flush(Output);
  SwapVectors;
  Exec(Prog,Tail);
  SwapVectors;
  If DosError<>0 Then Begin
   Fail(A.A[0],mExecFail,126);
   RunExternal:=126;
  End
   Else
  Begin
   C:=DosExitCode;
   If Hi(C)=1 Then RunExternal:=130
              Else RunExternal:=Lo(C);
  End;
 End;
End;

{ ---------------------------------------------------------------------
  Commandes internes
  --------------------------------------------------------------------- }
Function BuiltinIndex(Const Nm:String):Integer;
Var
 I:Integer;
Begin
 BuiltinIndex:=0;
 For I:=1 to BuiltinCount do If BuiltinNames[I]=Nm Then BuiltinIndex:=I;
End;

Function AliasFind(Const Nm:String):Integer;
Var
 I:Integer;
Begin
 AliasFind:=0;
 For I:=1 to MaxAlias do
  If(Aliases[I].Name<>'')and(Aliases[I].Name=Nm)Then AliasFind:=I;
End;

{ Change de repertoire (et de lecteur si Dest en designe un) }
Function ChDirTo(Dest:String):Boolean;
Var
 R:Registers;
 Old:Byte;
 E:Word;
Begin
 Dest:=SlashToBack(Dest);
 E:=0;
 R.AH:=$19;
 MsDos(R);
 Old:=R.AL;
 If(Length(Dest)>=2)and(Dest[2]=':')Then Begin
  R.AH:=$0E;R.DL:=Ord(UpCase(Dest[1]))-65;
  MsDos(R);
  R.AH:=$19;
  MsDos(R);
  If R.AL<>Ord(UpCase(Dest[1]))-65 Then E:=15;
  Delete(Dest,1,2);
 End;
 While(Length(Dest)>1)and(Dest[Length(Dest)]='\')do Delete(Dest,Length(Dest),1);
 If(E=0)and(Dest<>'')Then Begin
  {$I-}
  ChDir(Dest);
  E:=IOResult;
  {$I+}
 End;
 If E<>0 Then Begin
  R.AH:=$0E;R.DL:=Old;
  MsDos(R);
 End;
 ChDirTo:=E=0;
End;

Procedure BiCd(Var A:TArgs);
Var
 Dest,Old:String;
Begin
 LastStatus:=0;
 GetDir(0,Old);
 Old:=ToSlash(Old);
 Dest:='';
 If A.N>1 Then Dest:=A.A[1]
          Else If Not GetVar('HOME',Dest)Then Dest:='';
 If Dest='-'Then Begin
  If Not GetVar('OLDPWD',Dest)Then Dest:='';
  If Dest=''Then Fail('cd',mNoOldPwd,1);
 End
  Else
 If Dest=''Then Fail('cd',mNoHome,1);
 If LastStatus<>0 Then Exit;
 If Not ChDirTo(Dest)Then Fail('cd: '+Dest,mNoDir,1)
  Else
 Begin
  If EnvSet('OLDPWD',Old,False)Then;
  UpdatePwd;
  If(A.N>1)and(A.A[1]='-')Then WriteLn(UnixCwd);
 End;
End;

Procedure BiEcho(Var A:TArgs);
Var
 I,J:Integer;
 NoNl:Boolean;
Begin
 LastStatus:=0;
 I:=1;
 NoNl:=(A.N>1)and(A.A[1]='-n');
 If NoNl Then Inc(I);
 For J:=I to A.N-1 do Begin
  If J>I Then Write(' ');
  Write(A.A[J]);
 End;
 If Not NoNl Then WriteLn;
End;

Procedure ListEnv(Const Pre:String);
Var
 Scan:Integer;
Begin
 Scan:=0;
 While(EnvSeg<>0)and(Scan<EnvCap-2)and(PeekB(EnvSeg,Scan)<>0)do
  WriteLn(Pre,EnvRead(Scan));
End;

Procedure BiExport(Var A:TArgs);
Var
 I,P:Integer;
Begin
 LastStatus:=0;
 If A.N<2 Then ListEnv('export ')
  Else
 For I:=1 to A.N-1 do Begin
  P:=Pos('=',A.A[I]);
  If P=0 Then P:=Length(A.A[I])+1;
  If ValidName(Copy(A.A[I],1,P-1))Then
   ExportVar(Copy(A.A[I],1,P-1),P<=Length(A.A[I]),Copy(A.A[I],P+1,255))
  Else
   Fail('export: '+A.A[I],mBadId,1);
 End;
End;

Procedure BiSet(Var A:TArgs);
Var
 I,P:Integer;
Begin
 LastStatus:=0;
 If A.N<2 Then Begin
  For I:=1 to MaxVars do
   If Vars[I].Name<>''Then WriteLn(Vars[I].Name,'=',Vars[I].Val);
  ListEnv('');
 End
  Else
 For I:=1 to A.N-1 do Begin
  P:=Pos('=',A.A[I]);
  If(P>1)and ValidName(Copy(A.A[I],1,P-1))Then
   SetVar(Copy(A.A[I],1,P-1),Copy(A.A[I],P+1,255));
 End;
End;

Procedure BiUnset(Var A:TArgs);
Var
 I:Integer;
Begin
 LastStatus:=0;
 For I:=1 to A.N-1 do UnsetVar(A.A[I]);
End;

Procedure BiExit(Var A:TArgs);
Var
 N:LongInt;
Begin
 If A.N>1 Then Begin
  If StrInt(A.A[1],N)Then LastStatus:=N and 255
                     Else Fail('exit: '+A.A[1],mNumReq,2);
 End;
 ExitReq:=True;
End;

Procedure BiHelp;
Var
 I:Integer;
Begin
 LastStatus:=0;
 WriteLn(Msg(mBanner));
 WriteLn;
 WriteLn(Msg(mHelpHead));
 For I:=0 to hCount-1 do
  WriteLn(' ',HelpSyn[I],' ':19-Length(HelpSyn[I]),Msg(hFirst+I));
 WriteLn;
 WriteLn(Msg(mHelpTail),' c1 ; c2   c1 && c2   c1 || c2   c1 | c2');
 WriteLn('  c > f   c >> f   c < f   c 2> f   c 2>&1   $VAR  ${VAR}  $?  $#');
End;

Procedure BiHistory;
Var
 I:Integer;
Begin
 LastStatus:=0;
 For I:=1 to HistN do WriteLn(IntStr(I):5,'  ',Hist[I]);
End;

Procedure BiAlias(Var A:TArgs);
Var
 I,J,K,P:Integer;
Begin
 LastStatus:=0;
 If A.N<2 Then Begin
  For I:=1 to MaxAlias do
   If Aliases[I].Name<>''Then
    WriteLn('alias ',Aliases[I].Name,'=''',Aliases[I].Val,'''');
 End
  Else
 For I:=1 to A.N-1 do Begin
  P:=Pos('=',A.A[I]);
  If P<2 Then Fail('alias: '+A.A[I],mBadId,1)
   Else
  Begin
   J:=AliasFind(Copy(LoStr(A.A[I]),1,P-1));
   If J=0 Then
    For K:=MaxAlias downto 1 do If Aliases[K].Name=''Then J:=K;
   If J=0 Then Fail('',mEnvFull,1)
    Else
   Begin
    Aliases[J].Name:=Copy(LoStr(A.A[I]),1,P-1);
    Aliases[J].Val:=Copy(A.A[I],P+1,255);
   End;
  End;
 End;
End;

Procedure BiUnalias(Var A:TArgs);
Var
 I,J:Integer;
Begin
 LastStatus:=0;
 For I:=1 to A.N-1 do Begin
  If A.A[I]='-a'Then
   For J:=1 to MaxAlias do Aliases[J].Name:=''
  Else Begin
   J:=AliasFind(LoStr(A.A[I]));
   If J>0 Then Aliases[J].Name:=''
          Else Fail('unalias: '+A.A[I],mNotFoundT,1);
  End;
 End;
End;

Procedure BiType(Var A:TArgs);
Var
 I,J:Integer;
 Nm,Prog:String;
Begin
 LastStatus:=0;
 For I:=1 to A.N-1 do Begin
  Nm:=LoStr(A.A[I]);
  J:=AliasFind(Nm);
  Prog:=FindProgram(Nm);
  If J>0 Then WriteLn(Nm,' ',Msg(mIsAlias),' ',Aliases[J].Val)
   Else
  If BuiltinIndex(Nm)>0 Then WriteLn(Nm,' ',Msg(mIsBuiltin))
   Else
  If Prog<>''Then WriteLn(Nm,' ',Msg(mIs),' ',ToSlash(Prog))
   Else
  Fail('type: '+Nm,mNotFoundT,1);
 End;
End;

{ Nom DOS d'un script : tel quel ou cherche dans le repertoire courant/PATH }
Function ScriptPath(Const Name:String):TPath79;
Var
 P:TPath79;
Begin
 P:=UpStr(SlashToBack(Name));
 If Not FileExists(P)Then P:=FindProgram(Name);
 ScriptPath:=P;
End;

Procedure BiSource(Var A:TArgs);
Var
 Prog:TPath79;
Begin
 LastStatus:=0;
 If A.N<2 Then Fail('source',mMissArg,2)
  Else
 Begin
  Prog:=ScriptPath(A.A[1]);
  If Prog=''Then Fail(A.A[1],mNoFile,1)
            Else RunScript(Prog,A,2,True);
 End;
End;

{ Lit une ligne de l'entree standard (clavier ou fichier redirige) }
Function ReadStdLine(Var S:String):Boolean;Begin
 If DosIsDevice(0)and DosIsDevice(CurOutH)Then
  ReadStdLine:=EditLine(S,False)
 Else
  ReadStdLine:=ReadLineFrom(StdR,S);
End;

Procedure BiRead(Var A:TArgs);
Var
 I:Integer;
 L:String;
Begin
 LastStatus:=0;
 I:=1;
 If(A.N>2)and(A.A[1]='-p')Then Begin
  Write(A.A[2]);
  I:=3;
 End;
 If Not ReadStdLine(L)Then Begin
  L:='';
  LastStatus:=1;
 End;
 If I>=A.N Then SetVar('REPLY',L)
           Else SetVar(A.A[I],L);
End;

Function TestExpr(Var A:TArgs;P,Q:Integer;Var Bad:Boolean):Boolean;
Var
 N,K:Integer;
 Op,X,Y:String;
 IsD:Boolean;
 Sz,NX,NY:LongInt;
Begin
 TestExpr:=False;
 N:=Q-P+1;
 If(A.A[P]='!')and(N>1)Then TestExpr:=Not TestExpr(A,P+1,Q,Bad)
  Else
 If N=1 Then TestExpr:=A.A[P]<>''
  Else
 If N=2 Then Begin
  Op:=A.A[P];X:=A.A[P+1];
  If(Length(Op)<>2)or(Op[1]<>'-')Then Bad:=True
   Else
  Case Op[2] of
   'z':TestExpr:=X='';
   'n':TestExpr:=X<>'';
   'e':TestExpr:=FileInfo(X,IsD,Sz);
   'f':TestExpr:=FileInfo(X,IsD,Sz)and Not IsD;
   'd':TestExpr:=FileInfo(X,IsD,Sz)and IsD;
   Else Bad:=True;
  End;
 End
  Else
 If N=3 Then Begin
  X:=A.A[P];Op:=A.A[P+1];Y:=A.A[P+2];
  If(Op='=')or(Op='==')Then TestExpr:=X=Y Else
  If Op='!='Then TestExpr:=X<>Y
   Else
  Begin
   K:=Pos(Copy(Op,2,2),'eq ne lt le gt ge ');
   If(K=0)or(Op[1]<>'-')or Not StrInt(X,NX)or Not StrInt(Y,NY)Then Bad:=True
    Else
   Case K div 3 of
    0:TestExpr:=NX=NY;
    1:TestExpr:=NX<>NY;
    2:TestExpr:=NX<NY;
    3:TestExpr:=NX<=NY;
    4:TestExpr:=NX>NY;
    5:TestExpr:=NX>=NY;
   End;
  End;
 End
  Else
 Bad:=True;
End;

Procedure BiTest(Var A:TArgs;Bracket:Boolean);
Var
 Q:Integer;
 Bad:Boolean;
Begin
 Bad:=False;
 Q:=A.N-1;
 If Bracket Then Begin
  If A.A[Q]<>']'Then Bad:=True;
  Dec(Q);
 End;
 If Bad Then Fail('[',mSyntax,2)
  Else
 Begin
  If TestExpr(A,1,Q,Bad)Then LastStatus:=0
                        Else LastStatus:=1;
  If Bad Then Fail('test',mSyntax,2);
 End;
End;

Function MkDirOne(Const D:String):Boolean;
Var
 E:Word;
Begin
 {$I-}
 MkDir(D);
 E:=IOResult;
 {$I+}
 MkDirOne:=E=0;
End;

Procedure BiMkdir(Var A:TArgs);
Var
 I,J:Integer;
 Pf,IsD:Boolean;
 D,Part:String;
 Sz:LongInt;
Begin
 LastStatus:=0;
 Pf:=False;
 For I:=1 to A.N-1 do If A.A[I]='-p'Then Pf:=True;
 For I:=1 to A.N-1 do
  If A.A[I][1]<>'-'Then Begin
   D:=SlashToBack(A.A[I]);
   While(Length(D)>1)and(D[Length(D)]='\')do Delete(D,Length(D),1);
   If Pf Then
    For J:=1 to Length(D)do
     If D[J]='\'Then Begin
      Part:=Copy(D,1,J-1);
      If(Part<>'')and(Part[Length(Part)]<>':')and
        Not(FileInfo(Part,IsD,Sz)and IsD)Then
       If MkDirOne(Part)Then;
     End;
   If Not(Pf and FileInfo(D,IsD,Sz)and IsD)Then
    If Not MkDirOne(D)Then Fail('mkdir: '+A.A[I],mCantMkdir,1);
  End;
End;

Function VerString:String;Begin
 VerString:='LINUX-0 KERNEL16 version DOS '+IntStr(Lo(DosVersion))+'.'+
            IntStr(Hi(DosVersion));
End;

Procedure BiSleep(Var A:TArgs);
Var
 N,I:LongInt;
Begin
 LastStatus:=0;
 If(A.N<2)or Not StrInt(A.A[1],N)Then Fail('sleep',mNumReq,1)
  Else
 For I:=1 to N do Delay(1000);
End;

Procedure RunBuiltin(I:Integer;Var A:TArgs);Begin
 Case I of
  1:BiCd(A);
  2:Begin
   LastStatus:=0;
   WriteLn(UnixCwd);
  End;
  3:BiEcho(A);
  4:BiExport(A);
  5:BiSet(A);
  6:BiUnset(A);
  7:Begin
   LastStatus:=0;
   ListEnv('');
  End;
  8,9:BiExit(A);
  10:BiHelp;
  11:BiHistory;
  12:BiAlias(A);
  13:BiUnalias(A);
  14:BiType(A);
  15,16:BiSource(A);
  17:BiRead(A);
  18:BiTest(A,False);
  19:BiTest(A,True);
  20,29:LastStatus:=0;
  21:LastStatus:=1;
  22:BiMkdir(A);
  23:Begin
   LastStatus:=0;
   ClrScr;
  End;
  24,25:Begin
   LastStatus:=0;
   If(I=24)or(A.N>1)Then WriteLn(VerString)
                    Else WriteLn('LINUX-0');
  End;
  26:BiSleep(A);
  27,28:Begin
   LastStatus:=0;
   BrkReq:=I-26;
  End;
  30:Begin
   LastStatus:=1;
   If Frames[FrameTop].Cnt>0 Then Begin
    LastStatus:=0;
    For I:=1 to Frames[FrameTop].Cnt-1 do
     Frames[FrameTop].A[I]:=Frames[FrameTop].A[I+1];
    Dec(Frames[FrameTop].Cnt);
   End;
  End;
 End;
End;

{ ---------------------------------------------------------------------
  Execution : listes, tuyaux, commandes simples et composees.
  Les procedures recursives evitent les grosses variables chaines locales
  (la pile du programme est limitee) : les chaines temporaires sont dans
  des fonctions feuilles.
  --------------------------------------------------------------------- }
Procedure EraseFile(Const Nm:String);
Var
 F:File;
Begin
 Assign(F,Nm);
 {$I-}
 Erase(F);
 {$I+}
 If IOResult<>0 Then;
End;

{ Nom du fichier temporaire d'un tuyau : Code = niveau * 16 + numero }
Function PipeName(Code:Integer):TPath79;
Var
 T:TPath79;
Begin
 T:='SHP'+IntStr(Code div 16)+IntStr(Code mod 16)+'.TMP';
 If TmpDir<>''Then T:=TmpDir+'\'+T;
 PipeName:=T;
End;

{ Redirections par defaut dues aux tuyaux }
Procedure SetPipes(Var Sp:TSpec;PIn,POut:Integer);Begin
 InitSpec(Sp);
 If PIn>0 Then Sp.InF:=PipeName(PIn);
 If POut>0 Then Sp.OutF:=PipeName(POut);
End;

{ Repertoire des fichiers temporaires des tuyaux (cree au besoin) }
Procedure PrepareTmp;
Var
 IsD:Boolean;
 Sz:LongInt;
Begin
 If(TmpDir<>'')and Not(FileInfo(TmpDir,IsD,Sz)and IsD)Then
  If Not MkDirOne(TmpDir)Then TmpDir:='';
End;

Function UserAbort:Boolean;Begin
 UserAbort:=False;
 If DosIsDevice(0)Then
  If KeyPressed Then
   If ReadKey=#3 Then UserAbort:=True;
End;

{ Le mot W (minuscules) commence-t-il en S[I] ? }
Function WordAt(Const S:String;I,B:Integer;Const W:String):Boolean;
Var
 K:Integer;
Begin
 WordAt:=False;
 If I+Length(W)-1>B Then Exit;
 For K:=1 to Length(W)do If LowC(S[I+K-1])<>W[K]Then Exit;
 WordAt:=(I+Length(W)>B)or(S[I+Length(W)]in[' ',#9,';']);
End;

{ 1 = if, 2 = for, 3 = while, 0 = autre }
Function CompoundKind(Const S:String;I,B:Integer):Byte;Begin
 If WordAt(S,I,B,'if')Then CompoundKind:=1 Else
 If WordAt(S,I,B,'for')Then CompoundKind:=2 Else
 If WordAt(S,I,B,'while')Then CompoundKind:=3
                         Else CompoundKind:=0;
End;

Function SubStr15(Const S:String;I,N:Integer):TStr15;Begin
 SubStr15:=Copy(S,I,N);
End;

{ Numero de l'alias dont le nom commence en S[I] (le mot finit en J-1) }
Function AliasAt(Const S:String;I,B:Integer;Var J:Integer):Integer;Begin
 AliasAt:=0;
 J:=I;
 While(J<=B)and(S[J]in['A'..'Z','a'..'z','0'..'9','_','-','.'])do Inc(J);
 If(AliasDepth=0)and(J>I)and((J>B)or(S[J]in[' ',#9]))Then
  AliasAt:=AliasFind(LoStr(Copy(S,I,J-I)));
End;

{ Numero de la commande interne, ou 0 (env avec arguments : externe) }
Function BuiltinOf(Const Cmd:String;Argc:Integer):Integer;
Var
 K:Integer;
Begin
 K:=BuiltinIndex(LoStr(Cmd));
 If(K=7)and(Argc>1)Then K:=0;
 BuiltinOf:=K;
End;

{ Decoupe S[P..B] en arguments (variables, guillemets, globbing), en
  affectations NOM=valeur (Asg) et en redirections (Sp) }
Procedure Tokenize(Const S:String;P,B:Integer;Var A:TArgs;Var Sp:TSpec;
                   Var Asg:Boolean);
Var
 I,J,K:Integer;
 W:String;
 Fl:Byte;
Begin
 I:=P;
 While I<=B do Begin
  SkipSp(S,I,B);
  J:=I;
  If I<=B Then Begin
   K:=IdentLen(S,I,B);
   If S[I]=';'Then Inc(I) Else
   If TryRedir(S,I,B,Sp)Then Begin End
    Else
   If(A.N=0)and(K>0)and(K<=15)and(I+K<=B)and(S[I+K]='=')Then Begin
    SemiOK:=IsPathAsg(S,J,B);
    Inc(I,K+1);
    ReadWord(S,I,B,W,Fl);
    SemiOK:=False;
    LastStatus:=0;
    SetVar(Copy(S,J,K),W);
    Asg:=True;
   End
    Else
   Begin
    ReadWord(S,I,B,W,Fl);
    AddWord(A,W,Fl);
   End;
   If I=J Then Inc(I);
  End;
 End;
End;

{ Execute le texte d'un alias suivi du reste de la commande }
Procedure ExecAlias(Const V,S:String;J,B:Integer;Var Sp:TSpec);
Var
 T:String;
 R:TRedir;
Begin
 T:=V+Copy(S,J,B-J+1);
 If RedirBegin(Sp,R)Then Begin
  Inc(AliasDepth);
  ExecList(T,1,Length(T));
  Dec(AliasDepth);
  RedirEnd(R);
 End
  Else
 LastStatus:=1;
End;

Procedure ExecSimple(Const S:String;P,B,PIn,POut:Integer);
Var
 A:TArgs;
 Sp:TSpec;
 R:TRedir;
 I,J,K:Integer;
 Asg:Boolean;
Begin
 I:=P;
 SkipSp(S,I,B);
 If I<=B Then Begin
  SetPipes(Sp,PIn,POut);
  K:=AliasAt(S,I,B,J);
  If K>0 Then ExecAlias(Aliases[K].Val,S,J,B,Sp)
   Else
  Begin
   A.N:=0;A.Over:=False;Asg:=False;
   Tokenize(S,P,B,A,Sp,Asg);
   If Sp.Bad Then Fail('',mSyntax,2) Else
   If A.Over Then Fail('',mTooMany,1) Else
   If Not RedirBegin(Sp,R)Then LastStatus:=1
    Else
   Begin
    If A.N=0 Then Begin
     If Not Asg Then LastStatus:=0;
    End
     Else
    Begin
     K:=BuiltinOf(A.A[0],A.N);
     If K>0 Then RunBuiltin(K,A)
            Else LastStatus:=RunExternal(A);
    End;
    RedirEnd(R);
   End;
  End;
 End;
End;

{ Un tour de boucle for : fixe la variable et execute le corps }
Function ForRun(Const Nm,Val:String;Const S:String;Bs,Be:Integer):Boolean;Begin
 SetVar(Nm,Val);
 ExecList(S,Bs,Be);
 ForRun:=Not(ExitReq or(BrkReq=3));
 If BrkReq=1 Then Begin
  BrkReq:=0;
  ForRun:=False;
 End
  Else
 If BrkReq=2 Then BrkReq:=0;
 If UserAbort Then Begin
  LastStatus:=130;
  ForRun:=False;
 End;
End;

{ Un mot de la liste du for : globbing paresseux, tri alphabetique }
Function ForGlob(Const Nm,W:String;Fl:Byte;Const S:String;Bs,Be:Integer):
         Boolean;
Var
 Prev:TStr12;
 Res:TStr127;
 Go,Any:Boolean;
Begin
 Go:=True;Any:=False;
 If(Fl and fGlob)<>0 Then Begin
  Prev:='';
  While Go and NextGlob(W,Prev,Res)do Begin
   Any:=True;
   Go:=ForRun(Nm,Res,S,Bs,Be);
  End;
 End;
 If Not Any Then Go:=ForRun(Nm,W,S,Bs,Be);
 ForGlob:=Go;
End;

{ Champ suivant (separe par des blancs) de W a partir de N }
Function NextField(Const W:String;Var N:Integer;Var F:TStr127):Boolean;
Var
 J:Integer;
Begin
 While(N<=Length(W))and(W[N]in[' ',#9])do Inc(N);
 J:=N;
 While(J<=Length(W))and Not(W[J]in[' ',#9])do Inc(J);
 F:=Copy(W,N,J-N);
 NextField:=J>N;
 N:=J;
End;

Procedure ExecFor(Const S:String;P,E:Integer);
Var
 I,J,Qd,Qe,N:Integer;
 K,Fl:Byte;
 Nm:TStr15;
 F:TStr127;
 W:String;
 Go,HasIn:Boolean;
Begin
 I:=P+3;
 SkipSp(S,I,E);
 J:=IdentLen(S,I,E);
 Nm:=SubStr15(S,I,J);
 Inc(I,J);
 SkipSp(S,I,E);
 HasIn:=WordAt(S,I,E,'in');
 If HasIn Then Inc(I,2);
 Qd:=Walk(S,I,E,1,kwDo,K);
 If(Not ValidName(Nm))or(Qd>E)Then Fail('',mSyntax,2)
  Else
 Begin
  Qe:=Walk(S,Qd+2,E,1,kwDone,K);
  If Qe>E Then Fail('',mEofUnexp,2)
   Else
  Begin
   LastStatus:=0;
   Go:=True;
   If HasIn Then
    While Go and(I<Qd)and Not ExitReq do Begin
     SkipSp(S,I,Qd-1);
     If I<Qd Then
      If S[I]=';'Then Inc(I)
       Else
      Begin
       J:=I;
       ReadWord(S,I,Qd-1,W,Fl);
       If I=J Then Inc(I);
       If((Fl and fVar)<>0)and((Fl and fQuoted)=0)Then Begin
        N:=1;
        While Go and NextField(W,N,F)do Go:=ForGlob(Nm,F,Fl,S,Qd+2,Qe-1);
       End
        Else
       Go:=ForGlob(Nm,W,Fl,S,Qd+2,Qe-1);
      End;
    End
   Else
   For N:=1 to Frames[FrameTop].Cnt do
    If Go and Not ExitReq Then
     Go:=ForRun(Nm,Frames[FrameTop].A[N],S,Qd+2,Qe-1);
  End;
 End;
End;

Procedure ExecWhile(Const S:String;P,E:Integer);
Var
 Qd,Qe:Integer;
 K:Byte;
 Go:Boolean;
Begin
 Qd:=Walk(S,P+5,E,1,kwDo,K);
 Qe:=Walk(S,Qd+2,E,1,kwDone,K);
 If Qe>E Then Fail('',mSyntax,2)
  Else
 Begin
  Go:=True;
  While Go and Not ExitReq do Begin
   ExecList(S,P+5,Qd-1);
   If(LastStatus<>0)or ExitReq or(BrkReq<>0)Then Go:=False
    Else
   Begin
    ExecList(S,Qd+2,Qe-1);
    If BrkReq=2 Then BrkReq:=0;
    If BrkReq<>0 Then Go:=False;
    If UserAbort Then Begin
     LastStatus:=130;
     Go:=False;
    End;
   End;
  End;
  If BrkReq=1 Then BrkReq:=0;
 End;
End;

Procedure ExecIf(Const S:String;P,E:Integer);
Var
 C,Qt,Q2,Q3:Integer;
 K,K2:Byte;
Begin
 C:=P+2;
 While True do Begin
  Qt:=Walk(S,C,E,1,kwThen,K);
  Q2:=Walk(S,Qt+4,E,1,kwElif or kwElse or kwFi,K2);
  If Q2>E Then Begin
   Fail('',mSyntax,2);
   Exit;
  End;
  ExecList(S,C,Qt-1);
  If ExitReq or(BrkReq<>0)Then Exit;
  If LastStatus=0 Then Begin
   ExecList(S,Qt+4,Q2-1);
   Exit;
  End;
  If K2=kwElif Then C:=Q2+4
   Else
  Begin
   If K2=kwElse Then Begin
    Q3:=Walk(S,Q2+4,E,1,kwFi,K);
    ExecList(S,Q2+4,Q3-1);
   End
    Else
   LastStatus:=0;
   Exit;
  End;
 End;
End;

{ if / for / while ; les redirections suivent le mot-cle de fermeture }
Procedure ExecCompound(Const S:String;I,J,B:Integer;Kd:Byte;PIn,POut:Integer);
Var
 E:Integer;
 K:Byte;
 Sp:TSpec;
 R:TRedir;
Begin
 E:=Walk(S,J,B,1,kwFi or kwDone,K);
 If(E>B)or((K=kwFi)<>(Kd=1))Then Fail('',mEofUnexp,2)
  Else
 Begin
  If K=kwFi Then Inc(E)
            Else Inc(E,3);
  SetPipes(Sp,PIn,POut);
  J:=E+1;
  While J<=B do Begin
   SkipSp(S,J,B);
   If(J<=B)and Not TryRedir(S,J,B,Sp)Then Begin
    Sp.Bad:=True;
    J:=B+1;
   End;
  End;
  If Sp.Bad Then Fail('',mSyntax,2) Else
  If Not RedirBegin(Sp,R)Then LastStatus:=1
   Else
  Begin
   If Kd=1 Then ExecIf(S,I,E) Else
   If Kd=2 Then ExecFor(S,I,E)
           Else ExecWhile(S,I,E);
   RedirEnd(R);
  End;
 End;
End;

Procedure ExecStage(Const S:String;P,B,PIn,POut:Integer);
Var
 I,J:Integer;
 Kd:Byte;
Begin
 I:=P;
 SkipSp(S,I,B);
 J:=I;
 While(J<=B)and(S[J]in['A'..'Z','a'..'z'])do Inc(J);
 Kd:=CompoundKind(S,I,B);
 If Kd>0 Then ExecCompound(S,I,J,B,Kd,PIn,POut)
         Else ExecSimple(S,P,B,PIn,POut);
End;

Procedure RunPipeline(Const S:String;P,B:Integer);
Var
 Q,Cur,N,PIn,POut:Integer;
 K:Byte;
Begin
 Q:=Walk(S,P,B,3,0,K);
 If Q>B Then ExecStage(S,P,B,0,0)
  Else
 Begin
  PrepareTmp;
  Inc(PipeLevel);
  PIn:=0;Cur:=P;N:=0;
  Repeat
   Q:=Walk(S,Cur,B,3,0,K);
   Inc(N);
   If Q>B Then POut:=0
          Else POut:=PipeLevel*16+N;
   ExecStage(S,Cur,Q-1,PIn,POut);
   If PIn>0 Then EraseFile(PipeName(PIn));
   PIn:=POut;
   Cur:=Q+1;
  Until Q>B;
  Dec(PipeLevel);
 End;
End;

Procedure ExecList(Const S:String;P,B:Integer);
Var
 Q,I:Integer;
 K,Prev:Byte;
Begin
 Prev:=sepSeq;
 I:=P;
 If SPtr<7000 Then Begin
  Fail('',mTooDeep,1);
  I:=B+1;
 End;
 While(I<=B)and Not ExitReq and(BrkReq=0)do Begin
  Q:=Walk(S,I,B,0,0,K);
  If(Prev=sepSeq)or((Prev=sepAnd)and(LastStatus=0))or
    ((Prev=sepOr)and(LastStatus<>0))Then RunPipeline(S,I,Q-1);
  Prev:=K;
  I:=Q+1;
  If(K=sepAnd)or(K=sepOr)Then Inc(I);
 End;
End;

{ Ligne logique complete }
Procedure RunLine(Const L:String);Begin
 If BrkReq<>3 Then BrkReq:=0;
 ExecList(L,1,Length(L));
 If BrkReq<>3 Then BrkReq:=0;
End;

{ $0 du script }
Procedure SetFrameName(Const Path:String);Begin
 Frames[FrameTop].A[0]:=ToSlash(Path);
End;

Procedure RunScript(Const Path:String;Var A:TArgs;First:Integer;
                    IsSource:Boolean);
Var
 Rd:TReader;
 Acc:String;
 I,K:Integer;
 SavedAlias:Byte;
Begin
 If FrameTop>=MaxFrame Then Fail('',mTooDeep,1) Else
 If Not OpenReader(Rd,Path,128)Then Fail(Path,mNoFile,127)
  Else
 Begin
  Inc(FrameTop);
  SetFrameName(Path);
  K:=0;
  For I:=First to A.N-1 do If K<9 Then Begin
   Inc(K);
   Frames[FrameTop].A[K]:=A.A[I];
  End;
  Frames[FrameTop].Cnt:=K;
  SavedAlias:=AliasDepth;
  AliasDepth:=0;
  LastStatus:=0;
  While Not ExitReq and(BrkReq<>3)and ReadLogical(Rd,False,Acc)do
   RunLine(Acc);
  If BrkReq=3 Then BrkReq:=0;
  CloseReader(Rd);
  Dec(FrameTop);
  AliasDepth:=SavedAlias;
  If ExitReq and Not IsSource Then ExitReq:=False;
 End;
End;

{ ---------------------------------------------------------------------
  Demarrage
  --------------------------------------------------------------------- }
Procedure SetDefault(Const Nm,Val:String);
Var
 V:String;
Begin
 If Not GetVar(Nm,V)Then
  If EnvSet(Nm,Val,False)Then;
End;

Var
 Tail,T1,Rest:String;
 I,N:Integer;
 Interactive,Skip:Boolean;

BEGIN
 CheckBreak:=False;SemiOK:=False;
 LastStatus:=0;ExitReq:=False;BrkReq:=0;CtrlC:=False;
 AliasDepth:=0;PipeLevel:=0;FrameTop:=0;HistN:=0;
 For I:=1 to MaxVars do Vars[I].Name:='';
 For I:=1 to MaxAlias do Aliases[I].Name:='';
 For I:=0 to MaxFrame do Frames[I].Cnt:=0;
 Frames[0].A[0]:='sh';
 Lang:=0;
 { sortie d'erreur : handle 2 }
 Assign(ErrOut,'');
 Rewrite(ErrOut);
 SetTextHandle(ErrOut,2);
 { sortie standard : si elle est redirigee, ne pas passer par l'ecran }
 CurOutH:=1;
 If Not DosIsDevice(1)Then Begin
  I:=DosDup(1);
  If I<>NoH Then Begin
   CurOutH:=I;
   SetTextHandle(Output,I);
  End;
 End;
 StdR.H:=0;StdR.Size:=1;StdR.Pos:=0;StdR.Len:=0;
 EnvInit;
 GetDir(0,Tail);
 RootDrive:=UpCase(Tail[1]);
 SetDefault('USER','root');
 SetDefault('HOSTNAME','linux0');
 SetDefault('HOME','\');
 SetDefault('PATH','\BIN');
 SetDefault('SHELL','\BIN\SH.EXE');
 UpdateLang;
 UpdatePwd;
 If Not GetVar('TMP',Tail)Then
  If Not GetVar('TEMP',Tail)Then Tail:='\TMP';
 TmpDir:=Tail;
 { ligne de commande : SH [-c commande] [script [arguments]] }
 Tail:='';
 N:=PeekB(PrefixSeg,$80);
 If N>127 Then N:=127;
 For I:=1 to N do Tail:=Tail+Chr(PeekB(PrefixSeg,$80+I));
 Tail:=TrimR(TrimL(Tail));
 Repeat
  I:=Pos(' ',Tail+' ');
  T1:=Copy(Tail,1,I-1);
  Rest:=TrimL(Copy(Tail,I,255));
  { arguments DOS de SHELL= (C:\ /P) : ignores }
  Skip:=(T1<>'')and((T1[Length(T1)]in['\',':'])or
        ((T1[1]='/')and(Length(T1)=2)));
  If Skip Then Tail:=Rest;
 Until Not Skip;
 Interactive:=DosIsDevice(0)and DosIsDevice(CurOutH);
 If T1='-c'Then Begin
  If(Rest<>'')and(Rest[1]='"')and(Rest[Length(Rest)]='"')Then
   Rest:=Copy(Rest,2,Length(Rest)-2);
  RunLine(Rest);
 End
  Else
 If T1<>''Then Begin
  Rest:='. '+T1+' '+Rest;
  RunLine(Rest);
 End
  Else
 Begin
  If Interactive Then WriteLn(Msg(mBanner));
  If FileExists('\ETC\PROFILE')Then RunLine('. \ETC\PROFILE');
  While Not ExitReq do
   If Not ReadLogical(StdR,True,Line)Then ExitReq:=True
    Else
   If Line<>''Then Begin
    AddHist(Line);
    RunLine(Line);
   End;
 End;
 Flush(Output);
 Halt(LastStatus and 255);
END.
