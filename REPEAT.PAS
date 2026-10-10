{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Repeat a command a specified number of times)
}

Program RepeatApp;

Uses DOS;

Const
  MaxCommandLength=120;

Type
  TCommandText=String[MaxCommandLength];
  TArgument=String[255];

Var
  CommandShell:TArgument;
  CommandText:TCommandText;
  ShellParameters:TCommandText;
  LanguageCode:String[20];
  RepeatCount,RunIndex,ErrorCode:Integer;
  LastCommandStatus:Word;

Function QuoteArgument(Const Value:TArgument):TArgument;
Var
  Index:Integer;
  NeedsQuotes:Boolean;
  ResultText:TArgument;
Begin
  NeedsQuotes:=False;
  For Index:=1 to Length(Value)Do
    If Value[Index]in[' ',#9]Then NeedsQuotes:=True;
  If Not NeedsQuotes Then Begin
    QuoteArgument:=Value;
    Exit;
  End;
  ResultText:='"';
  For Index:=1 to Length(Value)Do Begin
    If Value[Index]='"'Then ResultText:=ResultText+'"';
    ResultText:=ResultText+Value[Index];
  End;
  ResultText:=ResultText+'"';
  QuoteArgument:=ResultText;
End;

Function ParseCount(Const Value:TArgument; Var CountValue:Integer):Boolean;
Var
  ErrorCode:Integer;
  ParsedValue:Integer;
Begin
  Val(Value,ParsedValue,ErrorCode);
  ParseCount:=ErrorCode=0;
  If ErrorCode=0 Then CountValue:=ParsedValue;
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('repeat - execute a command repeatedly');
    WriteLn('Usage: repeat count command [arguments ...]');
    WriteLn('The command is run count times through the command shell.');
  End Else Begin
    WriteLn('REPEAT - Cette commande permet d''ex'+#130+'cuter une commande plusieurs fois.');
    WriteLn;
    WriteLn('Syntaxe : repeat nombre commande [arguments ...]');
    WriteLn;
    WriteLn('La commande est lancee le nombre de fois indique.');
  End;
End;

Procedure UsageError;
Begin
  If Copy(LanguageCode,1,2)='EN'Then
    WriteLn('Usage: repeat count command [arguments ...]')
  Else WriteLn('Syntaxe : repeat nombre commande [arguments ...]');
  Halt(2);
End;

Procedure BuildCommand;
Var
  ArgumentIndex:Integer;
  Argument,Part:TArgument;
Begin
  CommandText:='';
  For ArgumentIndex:=2 to ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    Part:=QuoteArgument(Argument);
    If CommandText<>''Then CommandText:=CommandText+' ';
    If Length(CommandText)+Length(Part)>MaxCommandLength Then Begin
      If Copy(LanguageCode,1,2)='EN'Then
        WriteLn('repeat: command line exceeds the DOS limit')
      Else WriteLn('repeat : ligne de commande trop longue pour DOS');
      Halt(2);
    End;
    CommandText:=CommandText+Part;
  End;
End;

Begin
  LanguageCode:=GetEnv('LANGUAGE');
  If(ParamCount=1)and((ParamStr(1)='--help')or(ParamStr(1)='-h')or
    (ParamStr(1)='/?')or(ParamStr(1)='/h')or(ParamStr(1)='/H'))Then Begin
    PrintHelp;
    Halt(0);
  End;
  If ParamCount<2 Then UsageError;
  If Not ParseCount(ParamStr(1),RepeatCount)Then UsageError;
  If RepeatCount<0 Then UsageError;
  BuildCommand;
  If CommandText=''Then UsageError;
  CommandShell:=GetEnv('COMSPEC');
  If CommandShell=''Then CommandShell:='COMMAND.COM';
  ShellParameters:='/C '+CommandText;
  LastCommandStatus:=0;
  For RunIndex:=1 to RepeatCount Do Begin
    SwapVectors;
    Exec(CommandShell,ShellParameters);
    SwapVectors;
    ErrorCode:=DosError;
    If ErrorCode<>0 Then Begin
      If Copy(LanguageCode,1,2)='EN'Then
        WriteLn('repeat: cannot start command shell, DOS error ',ErrorCode)
      Else WriteLn('repeat : impossible de lancer le shell, erreur DOS ',ErrorCode);
      Halt(127);
    End;
    LastCommandStatus:=DosExitCode;
  End;
  Halt(LastCommandStatus);
END.
