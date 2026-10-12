{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program GETOPT;

Uses DOS;

Const
 MaxArguments=64;
 MaxLongOptions=48;
 MaxOutputTokens=128;

Type
 TText=String[255];
 TLongName=String[63];
 TLongOption=Record
  Name:TLongName;
  ArgumentMode:Char;
 End;
 TLongOptionArray=Array[1..MaxLongOptions]Of TLongOption;
 TArgumentArray=Array[1..MaxArguments]Of TText;
 TOutputArray=Array[1..MaxOutputTokens]Of TText;
 TQuoteArray=Array[1..MaxOutputTokens]Of Boolean;
 PLongOptionArray=^TLongOptionArray;
 PArgumentArray=^TArgumentArray;
 POutputArray=^TOutputArray;
 PQuoteArray=^TQuoteArray;

Var
 LongOptions:PLongOptionArray;
 Operands:PArgumentArray;
 OutputTokens:POutputArray;
 QuoteToken:PQuoteArray;
 LongOptionCount,OperandCount,TrailingCount,OutputCount:Integer;
 ProgramName,ShellName,ShortOptions:TText;
 AlternativeMode,QuietErrors,QuietOutput,UnquotedMode:Boolean;
 HelpRequested,VersionRequested,TestMode,ErrorFound:Boolean;
 ColonMode:Boolean;
 PositionalOptstring:Boolean;

Procedure ShowHelp;Forward;
Procedure ShowVersion;Forward;
Procedure ParseLongOptionList(Const ListText:TText);Forward;
Procedure ProcessLongToken(Const Token:TText;Var Index:Integer);Forward;
Function ShortArgumentMode(OptionLetter:Char):Char;Forward;

Procedure ReportError(Const MessageText:TText);
Begin
 If Not QuietErrors Then WriteLn(ProgramName,': ',MessageText);
 ErrorFound:=True;
End;

Procedure OptionError(Const MessageText:TText);
Begin
 WriteLn('getopt: ',MessageText);
 Halt(2);
End;

Function BeginsWith(Const Value,Prefix:TText):Boolean;
Var
 Index:Integer;
Begin
 BeginsWith:=False;
 If Length(Value)<Length(Prefix)Then Exit;
 For Index:=1 To Length(Prefix)Do
  If Value[Index]<>Prefix[Index]Then Exit;
 BeginsWith:=True;
End;

Procedure AddOutput(Const Value:TText;NeedsQuote:Boolean);
Begin
 If OutputCount>=MaxOutputTokens Then Begin
  ReportError('trop d''options');
  Exit;
 End;
 Inc(OutputCount);
 OutputTokens^[OutputCount]:=Value;
 QuoteToken^[OutputCount]:=NeedsQuote;
End;

Procedure AddOperand(Const Value:TText);
Begin
 If OperandCount>=MaxArguments Then Begin
  ReportError('trop d''arguments');
  Exit;
 End;
 Inc(OperandCount);
 Operands^[OperandCount]:=Value;
End;

Procedure AllocateWorkArrays;
Begin
 LongOptions:=Nil;
 Operands:=Nil;
 OutputTokens:=Nil;
 QuoteToken:=Nil;
 GetMem(LongOptions,SizeOf(TLongOptionArray));
 If LongOptions=Nil Then OptionError('memoire insuffisante pour les options longues');
 GetMem(Operands,SizeOf(TArgumentArray));
 If Operands=Nil Then OptionError('memoire insuffisante pour les arguments');
 GetMem(OutputTokens,SizeOf(TOutputArray));
 If OutputTokens=Nil Then OptionError('memoire insuffisante pour la sortie');
 GetMem(QuoteToken,SizeOf(TQuoteArray));
 If QuoteToken=Nil Then OptionError('memoire insuffisante pour les citations');
End;

Procedure FreeWorkArrays;
Begin
 If QuoteToken<>Nil Then FreeMem(QuoteToken,SizeOf(TQuoteArray));
 If OutputTokens<>Nil Then FreeMem(OutputTokens,SizeOf(TOutputArray));
 If Operands<>Nil Then FreeMem(Operands,SizeOf(TArgumentArray));
 If LongOptions<>Nil Then FreeMem(LongOptions,SizeOf(TLongOptionArray));
 QuoteToken:=Nil;
 OutputTokens:=Nil;
 Operands:=Nil;
 LongOptions:=Nil;
End;

Function FindLongOption(Const Name:TText;Var MatchIndex:Integer;
                        Var IsAmbiguous:Boolean):Boolean;
Var
 Index,Matches:Integer;
Begin
 FindLongOption:=False;
 IsAmbiguous:=False;
 Matches:=0;
 MatchIndex:=0;
 For Index:=1 To LongOptionCount Do Begin
  If LongOptions^[Index].Name=Name Then Begin
   MatchIndex:=Index;
   FindLongOption:=True;
   Exit;
  End;
  If BeginsWith(LongOptions^[Index].Name,Name)Then Begin
   Inc(Matches);
   MatchIndex:=Index;
  End;
 End;
 If Matches=1 Then FindLongOption:=True
 Else If Matches>1 Then IsAmbiguous:=True;
End;

Procedure AddLongOption(Const Name:TText;Mode:Char);
Begin
 If LongOptionCount>=MaxLongOptions Then OptionError('trop d''options longues');
 Inc(LongOptionCount);
 LongOptions^[LongOptionCount].Name:=Name;
 LongOptions^[LongOptionCount].ArgumentMode:=Mode;
End;

Procedure ParseLongOptionList(Const ListText:TText);
Var
 Position,StartAt,NameLength:Integer;
 Name:TText;
 Mode:Char;
Begin
 Position:=1;
 While Position<=Length(ListText)Do Begin
  StartAt:=Position;
  While(Position<=Length(ListText))And(ListText[Position]<>',')Do
   Inc(Position);
  NameLength:=Position-StartAt;
  Mode:='n';
  If(NameLength>0)And(ListText[StartAt+NameLength-1]=':')Then Begin
   Mode:='r';
   Dec(NameLength);
   If(NameLength>0)And(ListText[StartAt+NameLength-1]=':')Then Begin
    Mode:='o';
    Dec(NameLength);
   End;
  End;
  If NameLength>0 Then Begin
   Name:=Copy(ListText,StartAt,NameLength);
   AddLongOption(Name,Mode);
  End;
  Inc(Position);
 End;
End;

Function ShortArgumentMode(OptionLetter:Char):Char;
Var
 Position:Integer;
Begin
 ShortArgumentMode:=#0;
 For Position:=1 To Length(ShortOptions)Do
  If ShortOptions[Position]=OptionLetter Then Begin
   If(Position<Length(ShortOptions))And(ShortOptions[Position+1]=':')Then Begin
    If(Position+1<Length(ShortOptions))And(ShortOptions[Position+2]=':')Then
     ShortArgumentMode:='o'
    Else ShortArgumentMode:='r';
   End Else ShortArgumentMode:='n';
   Exit;
  End;
End;

Procedure ProcessLongToken(Const Token:TText;Var Index:Integer);
Var
 Body,OptionName,OptionValue,OutputName:TText;
 EqualPosition,MatchIndex:Integer;
 HasValue,Ambiguous:Boolean;
Begin
 Body:=Token;
 If AlternativeMode Then Delete(Body,1,1)
 Else Delete(Body,1,2);
 EqualPosition:=Pos('=',Body);
 HasValue:=EqualPosition>0;
 If HasValue Then Begin
  OptionName:=Copy(Body,1,EqualPosition-1);
  OptionValue:=Copy(Body,EqualPosition+1,255);
 End Else Begin
  OptionName:=Body;
  OptionValue:='';
 End;
 If Not FindLongOption(OptionName,MatchIndex,Ambiguous)Then Begin
  If Ambiguous Then ReportError('option longue ambigue: '+Token)
  Else ReportError('option longue inconnue: '+Token);
  Exit;
 End;
 OutputName:='--'+LongOptions^[MatchIndex].Name;
 Case LongOptions^[MatchIndex].ArgumentMode Of
  'n':Begin
   If HasValue Then ReportError('option sans argument: '+Token)
   Else AddOutput(OutputName,False);
  End;
  'r':Begin
   If Not HasValue Then Begin
    If(Index<OperandCount)And(Operands^[Index+1]<>'--')Then Begin
     Inc(Index);
     OptionValue:=Operands^[Index];
    End Else If Not ColonMode Then Begin
     ReportError('argument manquant pour '+Token);
     Exit;
    End;
   End;
   AddOutput(OutputName,False);
   AddOutput(OptionValue,True);
  End;
  'o':Begin
   AddOutput(OutputName,False);
   If HasValue Then AddOutput(OptionValue,True);
  End;
 End;
End;

Procedure ProcessShortToken(Const Token:TText;Var Index:Integer);
Var
 Position:Integer;
 OptionLetter,Mode:Char;
 OptionValue:TText;
Begin
 Position:=2;
 While Position<=Length(Token)Do Begin
  OptionLetter:=Token[Position];
  Mode:=ShortArgumentMode(OptionLetter);
  If Mode=#0 Then Begin
   If ColonMode Then AddOutput('-'+OptionLetter,False)
   Else ReportError('option inconnue: -'+OptionLetter);
   Inc(Position);
  End Else Begin
   AddOutput('-'+OptionLetter,False);
   Inc(Position);
   If Mode='r'Then Begin
    OptionValue:=Copy(Token,Position,255);
    If OptionValue=''Then Begin
     If Index<OperandCount Then Begin
      Inc(Index);
      OptionValue:=Operands^[Index];
     End Else If Not ColonMode Then Begin
      ReportError('argument manquant pour -'+OptionLetter);
      Exit;
     End;
    End;
    AddOutput(OptionValue,True);
    Exit;
   End Else If Mode='o'Then Begin
    OptionValue:=Copy(Token,Position,255);
    If OptionValue<>''Then AddOutput(OptionValue,True);
    Exit;
   End;
  End;
 End;
End;

Procedure ParseGetoptOptions;
Var
 Index,Position:Integer;
 Token,Value,OptionName:TText;
Begin
 ShortOptions:='';
 LongOptionCount:=0;
 OperandCount:=0;
 TrailingCount:=0;
 OutputCount:=0;
 ProgramName:='getopt';
 ShellName:='sh';
 AlternativeMode:=False;
 QuietErrors:=False;
 QuietOutput:=False;
 UnquotedMode:=False;
 HelpRequested:=False;
 VersionRequested:=False;
 TestMode:=False;
 ErrorFound:=False;
 ColonMode:=False;
 PositionalOptstring:=False;
 Index:=1;
 While Index<=ParamCount Do Begin
  Token:=ParamStr(Index);
  If PositionalOptstring Then AddOperand(Token)
  Else If(Token='-T')Or(Token='--test')Then TestMode:=True
  Else If(Token='-a')Or(Token='--alternative')Then AlternativeMode:=True
  Else If(Token='-q')Or(Token='--quiet')Then QuietErrors:=True
  Else If(Token='-Q')Or(Token='--quiet-output')Then QuietOutput:=True
  Else If(Token='-u')Or(Token='--unquoted')Then UnquotedMode:=True
    Else If(Token='-h')Or(Token='--help')Or(Token='/?')Or
      (Token='/h')Or(Token='/H')Then HelpRequested:=True
  Else If(Token='-V')Or(Token='--version')Then VersionRequested:=True
  Else If(Token='-o')Or(Token='--options')Or(Token='-l')Or
          (Token='--longoptions')Or(Token='-n')Or(Token='--name')Or
          (Token='-s')Or(Token='--shell')Then Begin
   If Index=ParamCount Then OptionError('argument manquant pour '+Token);
   Inc(Index);
   Value:=ParamStr(Index);
   If(Token='-o')Or(Token='--options')Then Begin
    ShortOptions:=Value;
    If(ShortOptions<>'')And(ShortOptions[1]=':')Then ColonMode:=True;
   End Else If(Token='-l')Or(Token='--longoptions')Then
    ParseLongOptionList(Value)
   Else If(Token='-n')Or(Token='--name')Then ProgramName:=Value
   Else ShellName:=Value;
  End Else If BeginsWith(Token,'--options=')Then Begin
   ShortOptions:=Copy(Token,11,255);
   If(ShortOptions<>'')And(ShortOptions[1]=':')Then ColonMode:=True;
  End Else If BeginsWith(Token,'--longoptions=')Then
   ParseLongOptionList(Copy(Token,15,255))
  Else If BeginsWith(Token,'--name=')Then ProgramName:=Copy(Token,8,255)
  Else If BeginsWith(Token,'--shell=')Then ShellName:=Copy(Token,9,255)
  Else If Token='--'Then Begin
   Inc(Index);
   If ShortOptions=''Then Begin
    If Index>ParamCount Then OptionError('optstring manquant');
    ShortOptions:=ParamStr(Index);
    If(ShortOptions<>'')And(ShortOptions[1]=':')Then ColonMode:=True;
    Inc(Index);
   End;
   While Index<=ParamCount Do Begin
    AddOperand(ParamStr(Index));
    Inc(Index);
   End;
   Break;
  End Else If(Length(Token)>1)And(Token[1]='-')Then Begin
   If ShortOptions=''Then Begin
    ShortOptions:=Token;
    If(ShortOptions<>'')And(ShortOptions[1]=':')Then ColonMode:=True;
   End Else If(Length(Token)>2)And(Token[2]='-')Then
    ReportError('option getopt inconnue: '+Token)
   Else Begin
    Position:=2;
    While Position<=Length(Token)Do Begin
     If Token[Position]='a'Then AlternativeMode:=True
     Else If Token[Position]='q'Then QuietErrors:=True
     Else If Token[Position]='Q'Then QuietOutput:=True
     Else If Token[Position]='u'Then UnquotedMode:=True
     Else If Token[Position]='T'Then TestMode:=True
     Else If(Token[Position]='o')Or(Token[Position]='l')Or
             (Token[Position]='n')Or(Token[Position]='s')Then Begin
      OptionName:=Token[Position];
      Value:=Copy(Token,Position+1,255);
      If Value=''Then Begin
       Inc(Index);
       If Index>ParamCount Then OptionError('argument manquant pour -'+OptionName);
       Value:=ParamStr(Index);
      End;
      If OptionName='o'Then Begin
       ShortOptions:=Value;
       If(ShortOptions<>'')And(ShortOptions[1]=':')Then ColonMode:=True;
      End Else If OptionName='l'Then ParseLongOptionList(Value)
      Else If OptionName='n'Then ProgramName:=Value
      Else ShellName:=Value;
      Position:=Length(Token)+1;
     End Else Begin
      ReportError('option getopt inconnue: -'+Token[Position]);
      Inc(Position);
     End;
    End;
   End;
  End Else If ShortOptions=''Then Begin
   ShortOptions:=Token;
   If(ShortOptions<>'')And(ShortOptions[1]=':')Then ColonMode:=True;
    PositionalOptstring:=True;
    End Else AddOperand(Token);
  Inc(Index);
 End;
 If TestMode Then Begin ShowVersion;Halt(4);End;
 If HelpRequested Then Begin ShowHelp;Halt(0);End;
 If VersionRequested Then Begin ShowVersion;Halt(0);End;
 If ShortOptions=''Then OptionError('optstring manquant');
End;

Procedure ShowHelp;
Begin
 WriteLn('GETOPT - Cette commande permet d''analyser les options d''une ligne de commande');
 WriteLn;
 WriteLn('Syntaxe: GETOPT [-a] [-qQTu] [-o optstring] [-l longopts]');
 WriteLn('         [-n progname] [-s shell] [--] optstring parametres');
 WriteLn; 
 WriteLn('  -a, --alternative       Autoriser les options longues -nom');
 WriteLn('  -l, --longoptions LISTE Definir les options longues');
 WriteLn('  -n, --name NOM          Nom utilise pour les erreurs');
 WriteLn('  -o, --options CHAINE    Definir les options courtes');
 WriteLn('  -q, --quiet             Supprimer les diagnostics');
 WriteLn('  -Q, --quiet-output      Ne rien ecrire en sortie normale');
 WriteLn('  -s, --shell SHELL       Conventions de citation sh ou csh');
 WriteLn('  -T, --test              Afficher la version et retourner 4');
 WriteLn('  -u, --unquoted          Ne pas citer les arguments');
 WriteLn('  -h, --help              Afficher cette aide');
 WriteLn('  -V, --version           Afficher la version');
End;

Procedure ShowVersion;
Begin
 WriteLn('getopt 1.0 - LINUX-0 Pascal');
End;

Function QuoteArgument(Const Value:TText):TText;
Var
 ResultText:TText;
 Position:Integer;
 CshMode:Boolean;
Begin
 If UnquotedMode Then Begin QuoteArgument:=Value;Exit;End;
 CshMode:=(ShellName='csh')Or(ShellName='tcsh');
 ResultText:='';
 If CshMode Then Begin
  ResultText:='"';
  For Position:=1 To Length(Value)Do Begin
   If Value[Position]In['"','\','$','`','!']Then ResultText:=ResultText+'\';
   ResultText:=ResultText+Value[Position];
  End;
  ResultText:=ResultText+'"';
 End Else Begin
  ResultText:='''';
  For Position:=1 To Length(Value)Do Begin
   If Value[Position]=''''Then ResultText:=ResultText+'''\'''''
   Else ResultText:=ResultText+Value[Position];
  End;
  ResultText:=ResultText+'''';
 End;
 QuoteArgument:=ResultText;
End;

Procedure ProcessOptionArguments;
Var
 Index,Position,MatchIndex:Integer;
 Token,OptionName,OptionValue,Canonical:TText;
 OptionLetter,Mode:Char;
 HasValue,Ambiguous,FoundLong:Boolean;
Begin
 Index:=1;
 While Index<=OperandCount Do Begin
  Token:=Operands^[Index];
  If Token='--'Then Begin
   Inc(Index);
   While Index<=OperandCount Do Begin
   If TrailingCount<MaxArguments Then Begin
    Inc(TrailingCount);
    Operands^[TrailingCount]:=Operands^[Index];
   End Else ReportError('trop d''arguments');
    Inc(Index);
   End;
  Break;
  End Else If(Token='-')Or(Length(Token)<2)Or(Token[1]<>'-')Then
  Begin
   If TrailingCount<MaxArguments Then Begin
    Inc(TrailingCount);
    Operands^[TrailingCount]:=Token;
   End Else ReportError('trop d''arguments');
  End
  Else If Copy(Token,1,2)='--'Then Begin
   OptionName:=Copy(Token,3,Length(Token));
   Position:=Pos('=',OptionName);
   HasValue:=Position>0;
   If HasValue Then Begin
    OptionValue:=Copy(OptionName,Position+1,255);
    OptionName:=Copy(OptionName,1,Position-1);
   End Else OptionValue:='';
   If Not FindLongOption(OptionName,MatchIndex,Ambiguous)Then Begin
    If Ambiguous Then ReportError('option longue ambigue: '+Token)
    Else ReportError('option longue inconnue: '+Token);
   End Else Begin
    Canonical:='--'+LongOptions^[MatchIndex].Name;
    Mode:=LongOptions^[MatchIndex].ArgumentMode;
    If Mode='n'Then Begin
     If HasValue Then ReportError('option sans argument: '+Token)
     Else AddOutput(Canonical,False);
    End Else If Mode='r'Then Begin
     If Not HasValue Then Begin
      If(Index<OperandCount)And(Operands^[Index+1]<>'--')Then Begin
       Inc(Index);
       OptionValue:=Operands^[Index];
      End Else If Not ColonMode Then Begin
       ReportError('argument manquant pour '+Token);
       OptionValue:='';
      End;
     End;
     AddOutput(Canonical,False);
     AddOutput(OptionValue,True);
    End Else Begin
     AddOutput(Canonical,False);
     If HasValue Then AddOutput(OptionValue,True);
    End;
   End;
  End Else If(Length(Token)>2)And(Token[2]='-')Then Begin
   If AlternativeMode Then Begin
    OptionName:=Copy(Token,2,Length(Token)-1);
    FoundLong:=FindLongOption(OptionName,MatchIndex,Ambiguous);
    If FoundLong Then Begin
     Delete(Token,1,1);
     ProcessLongToken(Token,Index);
    End Else If Ambiguous Then ReportError('option longue ambigue: '+Token)
    Else ReportError('option inconnue: '+Token);
   End Else ReportError('option inconnue: '+Token);
  End Else Begin
   FoundLong:=False;
   If AlternativeMode Then Begin
    OptionName:=Copy(Token,2,Length(Token)-1);
    FoundLong:=FindLongOption(OptionName,MatchIndex,Ambiguous);
    If FoundLong Then ProcessLongToken(Token,Index)
    Else If Ambiguous Then Begin
     ReportError('option longue ambigue: '+Token);
     FoundLong:=True;
    End;
   End;
   If Not FoundLong Then Begin
    Position:=2;
    While Position<=Length(Token)Do Begin
    OptionLetter:=Token[Position];
    Mode:=ShortArgumentMode(OptionLetter);
    If Mode=#0 Then Begin
     If ColonMode Then AddOutput('-'+OptionLetter,False)
     Else ReportError('option inconnue: -'+OptionLetter);
     Inc(Position);
    End Else Begin
     AddOutput('-'+OptionLetter,False);
     Inc(Position);
     If Mode='r'Then Begin
      OptionValue:=Copy(Token,Position,255);
      If OptionValue=''Then Begin
       If Index<OperandCount Then Begin
        Inc(Index);
        OptionValue:=Operands^[Index];
       End Else If Not ColonMode Then Begin
        ReportError('argument manquant pour -'+OptionLetter);
        OptionValue:='';
       End;
      End;
      AddOutput(OptionValue,True);
      Break;
     End Else If Mode='o'Then Begin
      OptionValue:=Copy(Token,Position,255);
      If OptionValue<>''Then AddOutput(OptionValue,True);
      Break;
     End;
    End;
    End;
   End;
  End;
  Inc(Index);
 End;
 AddOutput('--',False);
 For Index:=1 To TrailingCount Do AddOutput(Operands^[Index],True);
End;

Procedure WriteOutput;
Var
 Index:Integer;
 Value:TText;
Begin
 If QuietOutput Then Exit;
 For Index:=1 To OutputCount Do Begin
  Write(' ');
  If QuoteToken^[Index]Then Value:=QuoteArgument(OutputTokens^[Index])
                        Else Value:=OutputTokens^[Index];
  Write(Value);
 End;
 WriteLn;
End;

Begin
 AllocateWorkArrays;
 ParseGetoptOptions;
 ProcessOptionArguments;
 If ErrorFound Then Begin
  FreeWorkArrays;
  Halt(1);
 End;
 WriteOutput;
 FreeWorkArrays;
End.