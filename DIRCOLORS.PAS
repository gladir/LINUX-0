{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program DIRCOLORS;

Uses DOS;

Const
  MaxRules=96;

Type
  TRule=Record
    Name:String[63];
    Color:String[63];
  End;
  TRuleArray=Array[1..MaxRules]Of TRule;

Var
  Rules:TRuleArray;
  RuleCount,FileCount,ArgumentIndex,ErrorCode:Integer;
  FileNames:Array[1..16]Of String[127];
  Argument,LanguageCode:String;
  CShellMode,PrintDatabaseMode,QuietMode,ErrorFound:Boolean;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('DIRCOLORS : Generate LS_COLORS shell settings.');
    WriteLn('Syntax: dircolors [-b|-c|-p] [file ...]');
    WriteLn(' -b, --sh, --bourne-shell  Emit Bourne shell syntax');
    WriteLn(' -c, --csh, --c-shell     Emit C shell syntax');
    WriteLn(' -p, --print-database     Print the built-in color database');
    WriteLn('With no file, the built-in database is used.');
  End Else Begin
    WriteLn('DIRCOLORS : Cette commande permet de g'+#130+'n'+#130+'rer les r'+#130+'glages de couleurs LS_COLORS.');
    WriteLn;
    WriteLn('Syntaxe : dircolors [-b|-c|-p] [fichier ...]');
    WriteLn;
    WriteLn(' -b, --sh, --bourne-shell  Produire la syntaxe Bourne shell');
    WriteLn(' -c, --csh, --c-shell     Produire la syntaxe C shell');
    WriteLn(' -p, --print-database     Afficher la base de couleurs integree');
    WriteLn('Sans fichier, utilise la base integree.');
  End;
End;

Procedure OptionError(Const MessageText:String);
Begin
  WriteLn('dircolors: ',MessageText);
  Halt(2);
End;

Function TrimText(Value:String):String;
Begin
  While(Length(Value)>0)and(Value[1]in[' ',#9])Do Delete(Value,1,1);
  While(Length(Value)>0)and(Value[Length(Value)]in[' ',#9,#13])Do
    Delete(Value,Length(Value),1);
  TrimText:=Value;
End;

Function IsRuleNameCharacter(Value:Char):Boolean;
Begin
  IsRuleNameCharacter:=Value in['A'..'Z','a'..'z','0'..'9','_','-','.','*','?'];
End;

Function IsColorCharacter(Value:Char):Boolean;
Begin
  IsColorCharacter:=Value in['0'..'9',';'];
End;

Function FindRule(Const Name:String):Integer;
Var
  Index:Integer;
Begin
  FindRule:=0;
  For Index:=1 to RuleCount Do
    If Rules[Index].Name=Name Then Begin FindRule:=Index;Exit;End;
End;

Procedure SetRule(Const Name,Color:String);
Var
  Index:Integer;
Begin
  If(Name='')or(Length(Name)>63)or(Length(Color)>63)Then Exit;
  For Index:=1 to Length(Color)Do
    If Not IsColorCharacter(Color[Index])Then Exit;
  Index:=FindRule(Name);
  If Index=0 Then Begin
    If RuleCount>=MaxRules Then Exit;
    Inc(RuleCount);
    Index:=RuleCount;
  End;
  Rules[Index].Name:=Name;
  Rules[Index].Color:=Color;
End;

Procedure LoadDefaults;
Begin
  RuleCount:=0;
  SetRule('NORMAL','0');
  SetRule('FILE','0');
  SetRule('DIR','01;34');
  SetRule('LINK','01;36');
  SetRule('FIFO','40;33');
  SetRule('SOCK','01;35');
  SetRule('DOOR','01;35');
  SetRule('BLK','40;33;01');
  SetRule('CHR','40;33;01');
  SetRule('ORPHAN','40;31;01');
  SetRule('MISSING','00');
  SetRule('SETUID','37;41');
  SetRule('SETGID','30;43');
  SetRule('CAPABILITY','30;41');
  SetRule('STICKY_OTHER_WRITABLE','30;42');
  SetRule('OTHER_WRITABLE','34;42');
  SetRule('STICKY','37;44');
  SetRule('*.tar','01;31');
  SetRule('*.tgz','01;31');
  SetRule('*.arc','01;31');
  SetRule('*.arj','01;31');
  SetRule('*.taz','01;31');
  SetRule('*.lha','01;31');
  SetRule('*.lz4','01;31');
  SetRule('*.lzh','01;31');
  SetRule('*.lzma','01;31');
  SetRule('*.tlz','01;31');
  SetRule('*.txz','01;31');
  SetRule('*.tzo','01;31');
  SetRule('*.t7z','01;31');
  SetRule('*.zip','01;31');
  SetRule('*.z','01;31');
  SetRule('*.dz','01;31');
  SetRule('*.gz','01;31');
  SetRule('*.lz','01;31');
  SetRule('*.xz','01;31');
  SetRule('*.bz2','01;31');
  SetRule('*.bz','01;31');
  SetRule('*.tbz','01;31');
  SetRule('*.tbz2','01;31');
  SetRule('*.tz','01;31');
  SetRule('*.deb','01;31');
  SetRule('*.rpm','01;31');
  SetRule('*.jar','01;31');
  SetRule('*.rar','01;31');
  SetRule('*.7z','01;31');
  SetRule('*.Z','01;31');
  SetRule('*.webm','01;35');
  SetRule('*.mkv','01;35');
  SetRule('*.mp4','01;35');
  SetRule('*.avi','01;35');
  SetRule('*.mpg','01;35');
  SetRule('*.mpeg','01;35');
  SetRule('*.mp3','00;36');
  SetRule('*.wav','00;36');
  SetRule('*.ogg','00;36');
  SetRule('*.flac','00;36');
  SetRule('*.jpg','00;35');
  SetRule('*.jpeg','00;35');
  SetRule('*.png','00;35');
  SetRule('*.gif','00;35');
  SetRule('*.bmp','00;35');
End;

Procedure PrintDatabase;
Var
  Index:Integer;
Begin
  WriteLn('# Configuration file for dircolors');
  WriteLn('# Built-in defaults for the LINUX-0 dircolors clone');
  WriteLn('TERM *');
  For Index:=1 to RuleCount Do WriteLn(Rules[Index].Name,' ',Rules[Index].Color);
End;

Procedure ParseDatabaseLine(Const Line:String);
Var
  Position,NameStart,ColorStart:Integer;
  Name,Color:String;
Begin
  Position:=1;
  While(Position<=Length(Line))and(Line[Position]in[' ',#9])Do Inc(Position);
  If(Position>Length(Line))or(Line[Position]='#')Then Exit;
  NameStart:=Position;
  While(Position<=Length(Line))and IsRuleNameCharacter(Line[Position])Do Inc(Position);
  Name:=Copy(Line,NameStart,Position-NameStart);
  While(Position<=Length(Line))and(Line[Position]in[' ',#9])Do Inc(Position);
  If(Position>Length(Line))or(Name='')Then Exit;
  ColorStart:=Position;
  While(Position<=Length(Line))and not(Line[Position]in[' ',#9,'#'])Do Inc(Position);
  Color:=Copy(Line,ColorStart,Position-ColorStart);
  If(Name='TERM')or(Name='COLOR')or(Name='OPTIONS')or(Name='EIGHTBIT')Then Exit;
  If(Name[1]='.')Then Name:='*'+Name;
  SetRule(Name,Color);
End;

Procedure LoadDatabase(Const FileName:String);
Var
  DatabaseFile:Text;
  Line:String;
Begin
  Assign(DatabaseFile,FileName);
  {$I-}Reset(DatabaseFile);{$I+}
  If IOResult<>0Then Begin
    If Not QuietMode Then WriteLn('dircolors: impossible de lire ',FileName);
    ErrorFound:=True;
    Exit;
  End;
  While Not EOF(DatabaseFile)Do Begin ReadLn(DatabaseFile,Line);ParseDatabaseLine(Line);End;
  Close(DatabaseFile);
End;

Procedure WriteShellOutput;
Var
  Index:Integer;
Begin
  If CShellMode Then Write('setenv LS_COLORS ''')
  Else Write('LS_COLORS=''');
  For Index:=1 to RuleCount Do Begin
    If Index>1 Then Write(':');
    Write(Rules[Index].Name,'=',Rules[Index].Color);
  End;
  If CShellMode Then WriteLn('''')
  Else WriteLn('''; export LS_COLORS');
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  CShellMode:=False;PrintDatabaseMode:=False;QuietMode:=False;ErrorFound:=False;
  FileCount:=0;ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('dircolors (LINUX-0) 1.0');Halt(0);End
    Else If(Argument='-b')or(Argument='--sh')or(Argument='--bourne-shell')Then CShellMode:=False
    Else If(Argument='-c')or(Argument='--csh')or(Argument='--c-shell')Then CShellMode:=True
    Else If(Argument='-p')or(Argument='--print-database')Then PrintDatabaseMode:=True
    Else If(Argument='-q')Then QuietMode:=True
    Else If(Length(Argument)>1)and(Argument[1]='-')Then OptionError('option inconnue: '+Argument)
    Else Begin
      If FileCount>=16 Then OptionError('trop de fichiers');
      Inc(FileCount);FileNames[FileCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  LoadDefaults;
  If PrintDatabaseMode Then Begin PrintDatabase;Halt(0);End;
  For ArgumentIndex:=1 to FileCount Do LoadDatabase(FileNames[ArgumentIndex]);
  If ErrorFound Then Halt(1);
  WriteShellOutput;
END.