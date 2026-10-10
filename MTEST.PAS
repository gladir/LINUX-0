{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Testeur autonome de fichiers de configuration mtools)
}

Program MTEST;

Uses DOS;

Const
  MaxConfigName=127;
  MaxConfigLine=255;
  MaxKeyLength=40;
  MaxValueLength=200;

Type
  TConfigName=String[MaxConfigName];
  TConfigLine=String[MaxConfigLine];
  TKey=String[MaxKeyLength];
  TValue=String[MaxValueLength];
  TDriveSet=Set Of 'A'..'Z';

Var
  ConfigName:TConfigName;
  ConfigFile:Text;
  ConfigLine:TConfigLine;
  DriveLetters:TDriveSet;
  LineNumber,DirectiveCount,DriveCount,ErrorCount,WarningCount:LongInt;
  LanguageCode:String[20];
  English,ConfigFound,LineValid,ActiveDrive:Boolean;

Function IsEnglish:Boolean;
Begin
  IsEnglish:=English;
End;

Function TrimText(Value:TConfigLine):TConfigLine;
Begin
  While(Length(Value)>0)and(Value[1]in[' ',#9])Do Delete(Value,1,1);
  While(Length(Value)>0)and(Value[Length(Value)]in[' ',#9])Do
    Delete(Value,Length(Value),1);
  TrimText:=Value;
End;

Function ToUpperChar(Value:Char):Char;
Begin
  If(Value>='a')and(Value<='z')Then ToUpperChar:=Chr(Ord(Value)-32)
  Else ToUpperChar:=Value;
End;

Function StartsWithDrive(Const Value:TConfigLine):Boolean;
Begin
  StartsWithDrive:=False;
  If Length(Value)<7 Then Exit;
  StartsWithDrive:=(Copy(Value,1,6)='drive ')or(Copy(Value,1,6)='DRIVE ');
End;

Procedure PrintHelp;
Begin
  If IsEnglish Then Begin
    WriteLn('mtest - mtools configuration file test');
    WriteLn('Usage: mtest [configuration-file]');
    WriteLn('Without a filename, MTOOLSRC and standard config names are checked.');
  End Else Begin
    WriteLn('mtest - Cette commande permet de lancer le testeur de configuration mtools.');
    WriteLn;
    WriteLn('Syntaxe : mtest [fichier-de-configuration]');
    WriteLn;
    WriteLn('Sans nom, MTOOLSRC et les noms de configuration usuels sont testes.');
  End;
End;

Procedure PrintError(Const MessageText:TConfigLine);
Begin
  WriteLn(ConfigName,':',LineNumber,': ',MessageText);
  Inc(ErrorCount);
End;

Procedure PrintWarning(Const MessageText:TConfigLine);
Begin
  WriteLn(ConfigName,':',LineNumber,': ',MessageText);
  Inc(WarningCount);
End;

Function IsDriveLetter(Value:Char):Boolean;
Begin
  Value:=ToUpperChar(Value);
  IsDriveLetter:=(Value>='A')and(Value<='Z');
End;

Function ValidKey(Const Value:TKey):Boolean;
Var
  Index:Integer;
  Character:Char;
Begin
  ValidKey:=False;
  If Value=''Then Exit;
  Character:=Value[1];
  If Not((Character>='A')and(Character<='Z'))and
     Not((Character>='a')and(Character<='z'))and(Character<>'_')Then Exit;
  For Index:=2 to Length(Value)Do Begin
    Character:=Value[Index];
    If Not((Character>='A')and(Character<='Z'))and
       Not((Character>='a')and(Character<='z'))and
       Not((Character>='0')and(Character<='9'))and
       (Character<>'_')and(Character<>'-')Then Exit;
  End;
  ValidKey:=True;
End;

Function QuoteCount(Const Value:TConfigLine):Integer;
Var
  Index,CountValue:Integer;
  InQuote:Boolean;
Begin
  CountValue:=0;
  InQuote:=False;
  For Index:=1 to Length(Value)Do Begin
    If Value[Index]='"'Then InQuote:=Not InQuote;
    If Value[Index]='"'Then Inc(CountValue);
  End;
  QuoteCount:=CountValue;
End;

Procedure CheckAssignment(Const Value:TConfigLine; DriveDirective:Boolean);
Var
  EqualPosition,TokenStart,Index:Integer;
  KeyText:TKey;
  ValueText:TValue;
  Token:TConfigLine;
  Remaining:TConfigLine;
  InQuote:Boolean;
Begin
  Remaining:=TrimText(Value);
  While Remaining<>''Do Begin
    TokenStart:=1;
    InQuote:=False;
    While TokenStart<=Length(Remaining)Do Begin
      If Remaining[TokenStart]='"'Then InQuote:=Not InQuote
      Else If Not InQuote and((Remaining[TokenStart]=' ')or
              (Remaining[TokenStart]=#9))Then Break;
      Inc(TokenStart);
    End;
    Token:=Copy(Remaining,1,TokenStart-1);
    If Token=''Then Begin
      Remaining:=TrimText(Copy(Remaining,TokenStart+1,MaxConfigLine));
      Continue;
    End;
    EqualPosition:=0;
    For Index:=1 to Length(Token)Do If Token[Index]='='Then Begin
      EqualPosition:=Index;
      Break;
    End;
    If EqualPosition=0 Then Begin
      If DriveDirective and((Token='exclusive')or(Token='sync')or
         (Token='mformat_only')or(Token=' nolock'))Then Begin
        Remaining:=TrimText(Copy(Remaining,TokenStart,MaxConfigLine));
        Continue;
      End;
      If DriveDirective and((Token='use_xdf')or(Token='scsi')or
         (Token='privileged'))Then Begin
        Remaining:=TrimText(Copy(Remaining,TokenStart,MaxConfigLine));
        Continue;
      End;
      PrintError('expected key=value assignment');
      Exit;
    End;
    KeyText:=Copy(Token,1,EqualPosition-1);
    ValueText:=Copy(Token,EqualPosition+1,MaxValueLength);
    If Not ValidKey(KeyText)Then Begin
      PrintError('invalid configuration key');
      Exit;
    End;
    If ValueText=''Then Begin
      PrintError('configuration value is empty');
      Exit;
    End;
    If DriveDirective and(QuoteCount(Token)Mod 2<>0)Then Begin
      PrintError('unmatched double quote');
      Exit;
    End;
    Inc(DirectiveCount);
    If TokenStart>Length(Remaining)Then Remaining:=''
    Else Remaining:=TrimText(Copy(Remaining,TokenStart,MaxConfigLine));
  End;
End;

Procedure CheckDriveDirective(Const Value:TConfigLine);
Var
  Position:Integer;
  DriveLetter:Char;
  DriveName:TConfigLine;
Begin
  Position:=7;
  While(Position<=Length(Value))and(Value[Position]in[' ',#9])Do Inc(Position);
  If Position+1>Length(Value)Then Begin
    PrintError('drive directive requires a letter followed by colon');
    Exit;
  End;
  DriveLetter:=ToUpperChar(Value[Position]);
  If Not IsDriveLetter(DriveLetter)or(Value[Position+1]<>':')Then Begin
    PrintError('invalid drive name; expected a letter followed by colon');
    Exit;
  End;
  If DriveLetter in DriveLetters Then
    PrintWarning('drive is configured more than once')
  Else Begin
    DriveLetters:=DriveLetters+[DriveLetter];
    Inc(DriveCount);
  End;
  Position:=Position+2;
  DriveName:=TrimText(Copy(Value,Position,MaxConfigLine));
  ActiveDrive:=True;
  Inc(DirectiveCount);
  If DriveName<>''Then CheckAssignment(DriveName,True);
End;

Procedure CheckConfigLine;
Var
  CleanLine,KeyText,ValueText:TConfigLine;
  EqualPosition,Index:Integer;
  InQuote:Boolean;
Begin
  CleanLine:=TrimText(ConfigLine);
  If(CleanLine='')or(CleanLine[1]='#')or(CleanLine[1]=';')Then Exit;
  If StartsWithDrive(CleanLine)Then Begin
    CheckDriveDirective(CleanLine);
    Exit;
  End;
  EqualPosition:=0;
  InQuote:=False;
  For Index:=1 to Length(CleanLine)Do Begin
    If CleanLine[Index]='"'Then InQuote:=Not InQuote;
    If(CleanLine[Index]='#')and Not InQuote Then Begin
      CleanLine:=TrimText(Copy(CleanLine,1,Index-1));
      Break;
    End;
    If(CleanLine[Index]='=')and(EqualPosition=0)Then EqualPosition:=Index;
  End;
  If CleanLine=''Then Exit;
  If EqualPosition=0 Then Begin
    If ActiveDrive and((CleanLine='exclusive')or(CleanLine='sync')or
       (CleanLine='mformat_only')or(CleanLine='use_xdf')or
       (CleanLine='scsi')or(CleanLine='privileged')or
       (CleanLine='nolock'))Then Begin
      Inc(DirectiveCount);
      Exit;
    End;
    PrintError('expected a drive directive or key=value assignment');
    Exit;
  End;
  KeyText:=TrimText(Copy(CleanLine,1,EqualPosition-1));
  ValueText:=TrimText(Copy(CleanLine,EqualPosition+1,MaxConfigLine));
  If Not ValidKey(KeyText)Then Begin
    PrintError('invalid configuration key');
    Exit;
  End;
  If ValueText=''Then Begin
    PrintError('configuration value is empty');
    Exit;
  End;
  If(QuoteCount(ValueText)Mod 2)<>0 Then Begin
    PrintError('unmatched double quote');
    Exit;
  End;
  Inc(DirectiveCount);
End;

Procedure TestConfig(Const Name:TConfigName);
Var
  ErrorCode:Integer;
Begin
  ConfigName:=Name;
  Assign(ConfigFile,ConfigName);
  {$I-}Reset(ConfigFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Exit;
  ConfigFound:=True;
  LineNumber:=0;
  DirectiveCount:=0;
  DriveCount:=0;
  ErrorCount:=0;
  WarningCount:=0;
  DriveLetters:=[];
  ActiveDrive:=False;
  While Not EOF(ConfigFile)Do Begin
    {$I-}ReadLn(ConfigFile,ConfigLine);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      Inc(LineNumber);
      PrintError('I/O error while reading configuration');
      Break;
    End;
    Inc(LineNumber);
    CheckConfigLine;
  End;
  {$I-}Close(ConfigFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then PrintError('I/O error while closing configuration');
  If English Then Begin
    WriteLn(ConfigName,': ',LineNumber,' lines, ',DirectiveCount,
            ' assignments, ',DriveCount,' drives');
    If WarningCount>0 Then WriteLn('Warnings: ',WarningCount);
    If ErrorCount=0 Then WriteLn('Configuration syntax looks valid.')
    Else WriteLn('Configuration test failed: ',ErrorCount,' error(s).');
  End Else Begin
    WriteLn(ConfigName,' : ',LineNumber,' lignes, ',DirectiveCount,
            ' directives, ',DriveCount,' lecteurs');
    If WarningCount>0 Then WriteLn('Avertissements : ',WarningCount);
    If ErrorCount=0 Then WriteLn('La syntaxe du fichier semble valide.')
    Else WriteLn('Echec du test : ',ErrorCount,' erreur(s).');
  End;
End;

Function FileExists(Const Name:TConfigName):Boolean;
Var
  SearchRecord:SearchRec;
Begin
  FindFirst(Name,AnyFile,SearchRecord);
  FileExists:=DosError=0;
End;

Procedure TestDefaultConfig;
Var
  Candidate:TConfigName;
  EnvironmentName:String[127];
Begin
  ConfigFound:=False;
  EnvironmentName:=GetEnv('MTOOLSRC');
  If EnvironmentName<>''Then Begin
    Candidate:=EnvironmentName;
    If FileExists(Candidate)Then Begin TestConfig(Candidate);Exit;End;
    If English Then WriteLn('MTOOLSRC points to a missing file: ',Candidate)
    Else WriteLn('MTOOLSRC indique un fichier absent : ',Candidate);
    Halt(1);
  End;
  Candidate:='MTOOLS.CNF';
  If FileExists(Candidate)Then Begin TestConfig(Candidate);Exit;End;
  Candidate:='MTOOLS.CONF';
  If FileExists(Candidate)Then Begin TestConfig(Candidate);Exit;End;
  Candidate:='MTOOLS.INI';
  If FileExists(Candidate)Then Begin TestConfig(Candidate);Exit;End;
  Candidate:='.MTOOLSRC';
  If FileExists(Candidate)Then Begin TestConfig(Candidate);Exit;End;
  If English Then Begin
    WriteLn('No mtools configuration file was found.');
    WriteLn('Set MTOOLSRC or specify a configuration filename.');
  End Else Begin
    WriteLn('Aucun fichier de configuration mtools trouve.');
    WriteLn('Definissez MTOOLSRC ou indiquez un fichier en argument.');
  End;
  Halt(1);
End;

Var
  Argument:TConfigName;
BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  English:=Copy(LanguageCode,1,2)='EN';
  If(ParamCount=1)and((ParamStr(1)='-h')or(ParamStr(1)='--help')or
     (ParamStr(1)='/?'))Then Begin PrintHelp;Halt(0);End;
  If ParamCount>1 Then Begin
    If English Then WriteLn('Usage: mtest [configuration-file]')
    Else WriteLn('Syntaxe : mtest [fichier-de-configuration]');
    Halt(2);
  End;
  If ParamCount=1 Then Begin
    Argument:=ParamStr(1);
    TestConfig(Argument);
    If Not ConfigFound Then Begin
      If English Then WriteLn('mtest: cannot open ',Argument)
      Else WriteLn('mtest : impossible d''ouvrir ',Argument);
      Halt(1);
    End;
  End Else TestDefaultConfig;
  If ErrorCount>0 Then Halt(1);
  Halt(0);
END.