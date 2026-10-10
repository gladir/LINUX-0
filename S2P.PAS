{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description(Ce programme traduit les scripts sed de base en Perl.)
}

Program S2P(Input,Output);

Uses DOS;

Const
  MaxScripts=32;
  MaxScriptLength=255;
  MaxAddressLength=80;

Type
  TScriptText=String[MaxScriptLength];
  TAddressText=String[MaxAddressLength];
  TScriptEntry=Record
    IsFile:Boolean;
    Text:TScriptText;
  End;
  TScriptArray=Array[1..MaxScripts]Of TScriptEntry;

Var
  Scripts:TScriptArray;
  ScriptCount:Integer;
  SuppressDefault,DebugMode,English:Boolean;
  LanguageCode:String[20];
  ParseError:Boolean;

Function TrimText(Value:TScriptText):TScriptText;
Begin
  While(Length(Value)>0)and(Value[1]in[' ',#9])Do Delete(Value,1,1);
  While(Length(Value)>0)and(Value[Length(Value)]in[' ',#9])Do
    Delete(Value,Length(Value),1);
  TrimText:=Value;
End;

Procedure AddScript(IsFile:Boolean; Const Value:TScriptText);
Begin
  If ScriptCount>=MaxScripts Then Begin
    If English Then WriteLn('s2p: too many scripts')
    Else WriteLn('s2p : trop de scripts');
    Halt(2);
  End;
  Inc(ScriptCount);
  Scripts[ScriptCount].IsFile:=IsFile;
  Scripts[ScriptCount].Text:=Value;
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('s2p - This command translates basic sed scripts into Perl.');
    WriteLn('Usage: s2p [-n] [-D] [-e script] [-f script-file] [file]');
    WriteLn('With no script, sed commands are read from standard input.');
    WriteLn('Supported commands: s///, d, p, q, = and simple addresses.');
  End Else Begin
    WriteLn('S2P - Cette commande permet de traduire les scripts sed de base en Perl.');
    WriteLn;
    WriteLn('Syntaxe : s2p [-n] [-D] [-e script] [-f fichier-script] [fichier]');
    WriteLn;
    WriteLn(' -n             Ne pas afficher les lignes par defaut');
    WriteLn(' -D             Activer le mode debug');
    WriteLn(' -e script      Specifier un script sed a traduire');
    WriteLn(' -f fichier     Specifier un fichier contenant un script sed');
    WriteLn;
    WriteLn('Sans script, les commandes sed sont lues depuis l''entree standard.');
    WriteLn('Commandes gerees : s///, d, p, q, = et adresses simples.');
  End;
End;

Procedure UsageError(Const MessageText:TScriptText);
Begin
  If English Then WriteLn('s2p: ',MessageText)
  Else WriteLn('s2p : ',MessageText);
  Halt(2);
End;

Procedure PerlRegex(Const Pattern:TScriptText);
Var
  Position:Integer;
  Character:Char;
 Begin
   Write('/');
   Position:=1;
  While Position<=Length(Pattern)Do Begin
    Character:=Pattern[Position];
    If Character=#92 Then Begin
      If Position<Length(Pattern)Then Begin
        Inc(Position);
        Character:=Pattern[Position];
        If Character in['(',')','+','?','|','{','}']Then
          Write(Character)
        Else Begin
          Write(#92,Character);
        End;
      End Else Write(#92);
    End Else If Character='/'Then Write(#92,'/')
    Else If(Character='$')and(Position<Length(Pattern))Then Write(#92,'$')
    Else If Character in['(',')','+','?','{','}','|']Then Write(#92,Character)
    Else If Character='@'Then Write(#92,'@')
    Else Write(Character);
    Inc(Position);
  End;
  Write('/');
End;

Procedure PerlReplacement(Const Replacement:TScriptText);
Var
  Position:Integer;
  Character:Char;
Begin
  Position:=1;
  While Position<=Length(Replacement)Do Begin
    Character:=Replacement[Position];
    If Character=#92 Then Begin
      If Position<Length(Replacement)Then Begin
        Inc(Position);
        Character:=Replacement[Position];
        If Character in['1'..'9']Then Write('$',Character)
        Else If Character='&'Then Write('&')
        Else If Character='/'Then Write(#92,'/')
        Else Write(#92,Character);
      End Else Write(#92);
    End Else If Character='&'Then Write('$&')
    Else If Character='/'Then Write(#92,'/')
    Else If Character='$'Then Write(#92,'$')
    Else If Character='@'Then Write(#92,'@')
    Else Write(Character);
    Inc(Position);
  End;
  Write('/');
End;

Function IsDigits(Const Value:TScriptText):Boolean;
Var
  Index:Integer;
Begin
  IsDigits:=Value<>'';
  For Index:=1 to Length(Value)Do
    If Not(Value[Index]in['0'..'9'])Then IsDigits:=False;
End;

Procedure WriteAddressCondition(Const Address:TAddressText);
Var
  CommaPosition,Index:Integer;
  FirstAddress,SecondAddress:TAddressText;
Begin
  CommaPosition:=0;
  For Index:=1 to Length(Address)Do
    If Address[Index]=','Then Begin CommaPosition:=Index;Break;End;
  If CommaPosition=0 Then Begin
    If IsDigits(Address)Then Write('$. == ',Address)
    Else If Address='$'Then Write('eof()')
    Else If(Length(Address)>1)and(Address[1]='/')and
      (Address[Length(Address)]='/')Then Begin
      Write('$_ =~ ');
      PerlRegex(Copy(Address,2,Length(Address)-2));
    End Else Begin
      Write('1');
      ParseError:=True;
    End;
  End Else Begin
    FirstAddress:=Copy(Address,1,CommaPosition-1);
    SecondAddress:=Copy(Address,CommaPosition+1,MaxAddressLength);
    If IsDigits(FirstAddress)and IsDigits(SecondAddress)Then
      Write('$. >= ',FirstAddress,' && $. <= ',SecondAddress)
    Else Begin
      Write('1');
      ParseError:=True;
    End;
  End;
End;

Procedure TranslateCommand(Const SourceLine:TScriptText);
Var
  CleanLine,Address,Pattern,Replacement,Flags:TScriptText;
  Position,Start:Integer;
  Command:Char;
  Delimiter:Char;
  Negated,HasAddress:Boolean;
Begin
  CleanLine:=TrimText(SourceLine);
  If CleanLine=''Then Exit;
  If CleanLine[1]='#'Then Begin
    If Copy(CleanLine,1,2)='#n'Then SuppressDefault:=True;
    Exit;
  End;
  Position:=1;
  HasAddress:=False;
  Address:='';
  If(Position<=Length(CleanLine))and(CleanLine[Position]in['0'..'9','$'])Then Begin
    HasAddress:=True;
    Start:=Position;
    If CleanLine[Position]='$'Then Inc(Position)
    Else While(Position<=Length(CleanLine))and
      (CleanLine[Position]in['0'..'9'])Do Inc(Position);
    If(Position<=Length(CleanLine))and(CleanLine[Position]=',')Then Begin
      Inc(Position);
      If(Position<=Length(CleanLine))and(CleanLine[Position]='$')Then Inc(Position)
      Else While(Position<=Length(CleanLine))and
        (CleanLine[Position]in['0'..'9'])Do Inc(Position);
    End;
    Address:=Copy(CleanLine,Start,Position-Start);
  End Else If(Position<=Length(CleanLine))and(CleanLine[Position]='/')Then Begin
    HasAddress:=True;
    Start:=Position;
    Inc(Position);
    While(Position<=Length(CleanLine))and(CleanLine[Position]<>'/')Do Inc(Position);
    If Position>Length(CleanLine)Then Begin
      WriteLn('  # s2p: malformed address');
      ParseError:=True;
      Exit;
    End;
    Inc(Position);
    Address:=Copy(CleanLine,Start,Position-Start);
  End;
  Negated:=False;
  If HasAddress and(Position<=Length(CleanLine))and(CleanLine[Position]='!')Then Begin
    Negated:=True;
    Inc(Position);
  End;
  While(Position<=Length(CleanLine))and(CleanLine[Position]in[' ',#9])Do Inc(Position);
  If Position>Length(CleanLine)Then Exit;
  Command:=CleanLine[Position];
  Inc(Position);
  If HasAddress Then Begin
    Write('  if (');
    If Negated Then Write('!(');
    WriteAddressCondition(Address);
    If Negated Then Write(')');
    WriteLn(') {');
  End;
  Case Command Of
    's':Begin
      If Position>Length(CleanLine)Then Begin
        WriteLn('    # s2p: missing substitution');
        ParseError:=True;
      End Else Begin
        Delimiter:=CleanLine[Position];
        Inc(Position);
        Start:=Position;
        While(Position<=Length(CleanLine))and(CleanLine[Position]<>Delimiter)Do Inc(Position);
        If Position>Length(CleanLine)Then Begin
          WriteLn('    # s2p: unterminated pattern');
          ParseError:=True;
        End Else Begin
          Pattern:=Copy(CleanLine,Start,Position-Start);
          Inc(Position);
          Start:=Position;
          While(Position<=Length(CleanLine))and(CleanLine[Position]<>Delimiter)Do Inc(Position);
          If Position>Length(CleanLine)Then Begin
            WriteLn('    # s2p: unterminated replacement');
            ParseError:=True;
          End Else Begin
            Replacement:=Copy(CleanLine,Start,Position-Start);
            Inc(Position);
            Flags:=Copy(CleanLine,Position,MaxScriptLength);
            Write('    s');PerlRegex(Pattern);PerlReplacement(Replacement);
            If Pos('g',Flags)>0 Then Write('g');
            WriteLn(';');
            If(Pos('p',Flags)>0)and SuppressDefault Then WriteLn('    print $_;');
          End;
        End;
      End;
    End;
    'd':WriteLn('    next LINE;');
    'p':WriteLn('    print $_;');
    'q':Begin
      If Not SuppressDefault Then WriteLn('    print $_;');
      WriteLn('    last LINE;');
    End;
    '=':WriteLn('    print "$.\n";');
    'b':WriteLn('    # sed branch command requires labels; omitted');
    'y':WriteLn('    # sed transliteration command not supported');
  Else Begin
    Write('    # unsupported sed command: ');
    WriteLn(CleanLine);
    ParseError:=True;
  End;
  End;
  If HasAddress Then WriteLn('  }');
End;

Procedure TranslateScriptLine(Const ScriptLine:TScriptText);
Var
  Start,Index:Integer;
  CommandLine:TScriptText;
Begin
  Start:=1;
  For Index:=1 to Length(ScriptLine)+1 Do Begin
    If(Index>Length(ScriptLine))or(ScriptLine[Index]=';')Then Begin
      CommandLine:=TrimText(Copy(ScriptLine,Start,Index-Start));
      If CommandLine<>''Then TranslateCommand(CommandLine);
      Start:=Index+1;
    End;
  End;
End;

Procedure TranslateScriptFile(Const FileName:TScriptText);
 Var
   ScriptFile:Text;
   ScriptLine:TScriptText;
   ErrorCode:Integer;
Begin
  Assign(ScriptFile,FileName);
  {$I-}Reset(ScriptFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then UsageError('impossible de lire le script '+FileName);
  While Not EOF(ScriptFile)Do Begin
    ReadLn(ScriptFile,ScriptLine);
    TranslateScriptLine(ScriptLine);
  End;
  Close(ScriptFile);
End;

Procedure EmitPerlHeader;
Begin
  WriteLn('#!/usr/bin/perl');
  WriteLn('LINE: while (<>) {');
  If DebugMode Then WriteLn('  # generated with s2p debug mode');
End;

Procedure EmitPerlFooter;
Begin
  If Not SuppressDefault Then WriteLn('  print $_;');
  WriteLn('}');
End;

Function IsScriptFile(Const FileName:TScriptText):Boolean;
Var
  SearchRecord:SearchRec;
Begin
  FindFirst(FileName,AnyFile,SearchRecord);
  IsScriptFile:=(DosError=0)and((SearchRecord.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(SearchRecord);{$ENDIF}
End;

Procedure ParseArguments;
Var
  Argument:TScriptText;
  Index:Integer;
  HasInputScript:Boolean;
Begin
  HasInputScript:=False;
  Index:=1;
  While Index<=ParamCount Do Begin
    Argument:=ParamStr(Index);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')or(Argument='-?')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(Argument='--version')or(Argument='-V')Then Begin

      WriteLn('s2p (LINUX-0) 1.0');
      Halt(0);
    End Else If(Argument='-n')Then SuppressDefault:=True
    Else If(Argument='-D')Then DebugMode:=True
    Else If Argument='-p'Then SuppressDefault:=False
    Else If(Argument='-e')or(Argument='-f')Then Begin
      Inc(Index);
      If Index>ParamCount Then UsageError(Argument+' requires an argument');
      HasInputScript:=True;
      If Argument='-e'Then AddScript(False,ParamStr(Index))
      Else AddScript(True,ParamStr(Index));
    End Else If(Length(Argument)>1)and(Argument[1]='-')Then
      UsageError('unknown option '+Argument)
    Else If Not HasInputScript Then Begin
      AddScript(IsScriptFile(Argument),Argument);
      HasInputScript:=True;
    End Else UsageError('unexpected argument '+Argument);
    Inc(Index);
  End;
  If ScriptCount=0 Then AddScript(True,'');
End;

Procedure TranslateAllScripts;
Var
  Index:Integer;
  ScriptFile:Text;
  ScriptLine:TScriptText;
  ErrorCode:Integer;
Begin
  EmitPerlHeader;
  For Index:=1 to ScriptCount Do Begin
    If Scripts[Index].IsFile Then Begin
      If Scripts[Index].Text=''Then Begin
        While Not EOF(Input)Do Begin
          ReadLn(Input,ScriptLine);
          TranslateScriptLine(ScriptLine);
        End;
      End Else Begin
        Assign(ScriptFile,Scripts[Index].Text);
        {$I-}Reset(ScriptFile);{$I+}
        ErrorCode:=IOResult;
        If ErrorCode<>0 Then UsageError('impossible de lire '+Scripts[Index].Text);
        While Not EOF(ScriptFile)Do Begin
          ReadLn(ScriptFile,ScriptLine);
          TranslateScriptLine(ScriptLine);
        End;
        Close(ScriptFile);
      End;
    End Else TranslateScriptLine(Scripts[Index].Text);
  End;
  EmitPerlFooter;
  If ParseError Then Halt(1);
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  English:=Copy(LanguageCode,1,2)='EN';
  ScriptCount:=0;
  SuppressDefault:=False;
  DebugMode:=False;
  ParseArguments;
  TranslateAllScripts;
END.
