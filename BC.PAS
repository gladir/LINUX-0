{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program BC(Input,Output);

Uses DOS;

Const
  MaxLineLength=255;
  MaxScale=12;
  MaxFiles=32;

Type
  TVariables=Array['a'..'z']Of Real;
  TFileNames=Array[1..MaxFiles]Of String;

Var
  SourceFile:Text;
  Variables:TVariables;
  FileNames:TFileNames;
  ExpressionLine,CurrentArg:String;
  Position,CurrentLine,ScaleDigits,InputBase,OutputBase:Integer;
  FileCount,ArgumentIndex,I:Integer;
  MathLibrary,Quiet,Interactive:Boolean;
  StopProgram,ParseError:Boolean;
  ErrorMessage:String;

Function ParseExpression:Real;Forward;
Function ParseTerm:Real;Forward;
Function ParsePower:Real;Forward;
Function ParsePrimary:Real;Forward;

Procedure SetError(Const MessageText:String);
Begin
  If Not ParseError Then ErrorMessage:=MessageText;
  ParseError:=True;
End;

Procedure SkipSpaces;
Begin
  While(Position<=Length(ExpressionLine))and
    (ExpressionLine[Position]in[' ',#9])Do Inc(Position);
End;

Function ReadIdentifier:String;
Var
  Start:Integer;
Begin
  SkipSpaces;
  Start:=Position;
  While(Position<=Length(ExpressionLine))and
    (ExpressionLine[Position]in['a'..'z','A'..'Z','0'..'9','_'])Do
    Inc(Position);
  ReadIdentifier:=Copy(ExpressionLine,Start,Position-Start);
End;

Function ReadNumber:Real;
Var
  Start,ErrorCode:Integer;
  NumberText:String;
  Value:Real;
Begin
  SkipSpaces;
  Start:=Position;
  While(Position<=Length(ExpressionLine))and
    (ExpressionLine[Position]in['0'..'9','.'])Do Inc(Position);
  NumberText:=Copy(ExpressionLine,Start,Position-Start);
  If NumberText=''Then Begin
    SetError('nombre attendu');
    ReadNumber:=0;
    Exit;
  End;
  Val(NumberText,Value,ErrorCode);
  If ErrorCode<>0 Then Begin
    SetError('nombre invalide : '+NumberText);
    Value:=0;
  End;
  ReadNumber:=Value;
End;

Function ApplyFunction(Const FunctionName:String; Value:Real):Real;
Begin
  ApplyFunction:=0;
  If Not MathLibrary Then Begin
    SetError('fonction mathematique indisponible sans -l');
    Exit;
  End;
  If(FunctionName='s')or(FunctionName='sin')Then ApplyFunction:=Sin(Value) Else
  If(FunctionName='c')or(FunctionName='cos')Then ApplyFunction:=Cos(Value) Else
  If(FunctionName='a')or(FunctionName='atan')Then ApplyFunction:=ArcTan(Value) Else
  If(FunctionName='e')or(FunctionName='exp')Then ApplyFunction:=Exp(Value) Else
  If(FunctionName='l')or(FunctionName='ln')Then Begin
    If Value<=0 Then SetError('ln exige une valeur positive')
              Else ApplyFunction:=Ln(Value);
  End Else If(FunctionName='sqrt')Then Begin
    If Value<0 Then SetError('sqrt exige une valeur positive')
              Else ApplyFunction:=Sqrt(Value);
  End Else SetError('fonction inconnue : '+FunctionName);
End;

Function ParsePrimary:Real;
Var
  Identifier:String;
  Value:Real;
Begin
  SkipSpaces;
  If Position>Length(ExpressionLine)Then Begin
    SetError('expression incomplete');
    ParsePrimary:=0;
    Exit;
  End;
  If ExpressionLine[Position]='('Then Begin
    Inc(Position);
    Value:=ParseExpression;
    SkipSpaces;
    If(Position>Length(ExpressionLine))or(ExpressionLine[Position]<>')')Then
      SetError('parenthese fermante manquante')
    Else Inc(Position);
    ParsePrimary:=Value;
    Exit;
  End;
  If ExpressionLine[Position]in['0'..'9','.']Then Begin
    ParsePrimary:=ReadNumber;
    Exit;
  End;
  If ExpressionLine[Position]in['a'..'z','A'..'Z','_']Then Begin
    Identifier:=ReadIdentifier;
    SkipSpaces;
    If(Position<=Length(ExpressionLine))and
      (ExpressionLine[Position]='(')Then Begin
      Inc(Position);
      Value:=ParseExpression;
      SkipSpaces;
      If(Position>Length(ExpressionLine))or(ExpressionLine[Position]<>')')Then
        SetError('parenthese fermante manquante')
      Else Inc(Position);
      ParsePrimary:=ApplyFunction(Identifier,Value);
    End Else If Identifier='scale'Then ParsePrimary:=ScaleDigits Else
    If Identifier='ibase'Then ParsePrimary:=InputBase Else
    If Identifier='obase'Then ParsePrimary:=OutputBase Else
    If(Length(Identifier)=1)and(Identifier[1]in['a'..'z'])Then
      ParsePrimary:=Variables[Identifier[1]]
    Else Begin
      SetError('variable inconnue : '+Identifier);
      ParsePrimary:=0;
    End;
    Exit;
  End;
  SetError('operande invalide');
  ParsePrimary:=0;
  Inc(Position);
End;

Function ParsePower:Real;
Var
  LeftValue,RightValue,PowerResult:Real;
  Exponent,Count,Sign:LongInt;
Begin
  ParsePower:=0;
  SkipSpaces;
  Sign:=1;
  If Position<=Length(ExpressionLine)Then Begin
    If ExpressionLine[Position]='-'Then Begin
      Sign:=-1;
      Inc(Position);
    End Else If ExpressionLine[Position]='+'Then Inc(Position);
  End;
  LeftValue:=ParsePrimary;
  SkipSpaces;
  If(Position<=Length(ExpressionLine))and
    (ExpressionLine[Position]='^')Then Begin
    Inc(Position);
    RightValue:=ParsePower;
    If RightValue<>Trunc(RightValue)Then Begin
      SetError('exposant entier requis');
      ParsePower:=0;
      Exit;
    End;
    Exponent:=Trunc(RightValue);
    If(LeftValue=0)and(Exponent<0)Then Begin
      SetError('division par zero');
      ParsePower:=0;
      Exit;
    End;
    If Exponent<0 Then Begin
      LeftValue:=1/LeftValue;
      Exponent:=-Exponent;
    End;
    PowerResult:=1;
    For Count:=1 to Exponent Do PowerResult:=PowerResult*LeftValue;
    ParsePower:=Sign*PowerResult;
  End Else ParsePower:=Sign*LeftValue;
End;

Function ParseTerm:Real;
Var
  Value,RightValue:Real;
  OperatorChar:Char;
Begin
  Value:=ParsePower;
  SkipSpaces;
  While(Position<=Length(ExpressionLine))and
    (ExpressionLine[Position]in['*','/','%'])Do Begin
    OperatorChar:=ExpressionLine[Position];
    Inc(Position);
    RightValue:=ParsePower;
    Case OperatorChar Of
      '*':Value:=Value*RightValue;
      '/':If RightValue=0 Then SetError('division par zero')
                           Else Value:=Value/RightValue;
      '%':If RightValue=0 Then SetError('modulo par zero')
                           Else Value:=Value-Trunc(Value/RightValue)*RightValue;
    End;
    SkipSpaces;
  End;
  ParseTerm:=Value;
End;

Function ParseExpression:Real;
Var
  Value,RightValue:Real;
  OperatorChar:Char;
Begin
  Value:=ParseTerm;
  SkipSpaces;
  While(Position<=Length(ExpressionLine))and
    (ExpressionLine[Position]in['+','-'])Do Begin
    OperatorChar:=ExpressionLine[Position];
    Inc(Position);
    RightValue:=ParseTerm;
    If OperatorChar='+'Then Value:=Value+RightValue
                          Else Value:=Value-RightValue;
    SkipSpaces;
  End;
  ParseExpression:=Value;
End;

Function FormatNumber(Value:Real):String;
Var
  S:String;
  ScalePower:Real;
  I,Digits:Integer;
  Whole:LongInt;
Begin
  Digits:=ScaleDigits;
  If Digits<0 Then Digits:=0;
  If Digits>MaxScale Then Digits:=MaxScale;
  ScalePower:=1;
  For I:=1 to Digits Do ScalePower:=ScalePower*10;
  Whole:=Trunc(Value*ScalePower);
  Value:=Whole/ScalePower;
  Str(Value:0:Digits,S);
  If(Digits>0)and(Pos('.',S)>0)Then Begin
    While(Length(S)>0)and(S[Length(S)]='0')Do S[0]:=Chr(Length(S)-1);
    If(Length(S)>0)and(S[Length(S)]='.')Then S[0]:=Chr(Length(S)-1);
  End;
  FormatNumber:=S;
End;

Function FindAssignment(Const S:String; Var Name:String;
                        Var RightSide:String):Boolean;
Var
  I,EqualPosition:Integer;
  LeftSide:String;
Begin
  FindAssignment:=False;
  EqualPosition:=0;
  For I:=1 to Length(S)Do
    If S[I]='='Then Begin
      EqualPosition:=I;
      Break;
    End;
  If EqualPosition=0 Then Exit;
  LeftSide:=Copy(S,1,EqualPosition-1);
  Name:='';
  For I:=1 to Length(LeftSide)Do
    If Not(LeftSide[I]in[' ',#9])Then Name:=Name+LeftSide[I];
  RightSide:=Copy(S,EqualPosition+1,Length(S));
  FindAssignment:=(Name<>'');
End;

Procedure EvaluateLine(Const SourceLine:String);
Var
  Name,RightSide,Command:String;
  Value:Real;
Begin
  ParseError:=False;
  ErrorMessage:='';
  ExpressionLine:=SourceLine;
  Position:=1;
  SkipSpaces;
  If Position>Length(ExpressionLine)Then Exit;
  If ExpressionLine[Position]='#'Then Exit;
  Command:=Copy(ExpressionLine,Position,Length(ExpressionLine));
  If(Command='quit')or(Command='halt')Then Begin
    StopProgram:=True;
    Exit;
  End;
  If Copy(Command,1,5)='scale'Then Begin
    Position:=Position+5;
    SkipSpaces;
    If(Position<=Length(ExpressionLine))and(ExpressionLine[Position]='=')Then Begin
      Inc(Position);
      Value:=ParseExpression;
      If Not ParseError Then Begin
        ScaleDigits:=Trunc(Value);
        If ScaleDigits<0 Then ScaleDigits:=0;
        If ScaleDigits>MaxScale Then ScaleDigits:=MaxScale;
      End;
      Exit;
    End;
  End;
  If FindAssignment(ExpressionLine,Name,RightSide)Then Begin
    ExpressionLine:=RightSide;
    Position:=1;
    Value:=ParseExpression;
    SkipSpaces;
    If(Position<=Length(ExpressionLine))and(ExpressionLine[Position]<>';')Then
      SetError('texte inattendu apres expression : '+ExpressionLine[Position]);
    If Not ParseError Then Begin
      If Length(Name)=1 Then Variables[Name[1]]:=Value Else
      If Name='scale'Then Begin
        ScaleDigits:=Trunc(Value);
        If ScaleDigits<0 Then ScaleDigits:=0;
        If ScaleDigits>MaxScale Then ScaleDigits:=MaxScale;
      End Else SetError('affectation non prise en charge : '+Name);
    End;
  End Else Begin
    Position:=1;
    Value:=ParseExpression;
    SkipSpaces;
    If(Position<=Length(ExpressionLine))and(ExpressionLine[Position]<>';')Then
      SetError('texte inattendu apres expression : '+ExpressionLine[Position]);
  End;
  If ParseError Then Begin
    WriteLn('Erreur ligne ',CurrentLine,': ',ErrorMessage);
    Exit;
  End;
  WriteLn(FormatNumber(Value));
End;

Procedure ProcessInput(Var Source:Text);
Var
  Line:String;
  I,Start,First:Integer;
Begin
  While Not EOF(Source)and Not StopProgram Do Begin
    If Interactive Then Write('> ');
    ReadLn(Source,Line);
    Inc(CurrentLine);
    First:=1;
    While(First<=Length(Line))and(Line[First]in[' ',#9])Do Inc(First);
    If(First<=Length(Line))and(Line[First]<>'#')Then Begin
      Start:=1;
      For I:=1 to Length(Line)+1 Do Begin
        If(I>Length(Line))or(Line[I]=';')Then Begin
          EvaluateLine(Copy(Line,Start,I-Start));
          Start:=I+1;
          If StopProgram Then Break;
        End;
      End;
    End;
  End;
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('BC : An arbitrary precision calculator language subset.');
    WriteLn('Syntax: bc [-hilqswv] [long options] [FILE ...]');
    WriteLn(' -l, --mathlib  Enable s, c, a, l, e and sqrt functions');
    WriteLn(' -q, --quiet    Suppress startup banner');
    WriteLn(' -i             Force interactive mode');
    WriteLn('Assignments, scale, arithmetic, powers, variables and parentheses are supported.');
  End Else Begin
    WriteLn('BC : Cette commande permet de lancer une calculatrice en ligne de commande.');
    WriteLn;
    WriteLn('Syntaxe : bc [-hilqswv] [fichier ...]');
    WriteLn;
    WriteLn(' -l, --mathlib  Active les fonctions mathematiques');
    WriteLn(' -q, --quiet    Supprime la banniere');
    WriteLn(' -i, --interactive  Force le mode interactif');
    WriteLn('Expressions, variables, affectations, scale et parentheses sont prises en charge.');
  End;
End;

Procedure ProcessFile(Const Name:String);
Begin
  {$I-}Assign(SourceFile,Name);
  Reset(SourceFile);{$I+}
  If IOResult<>0Then Begin
    WriteLn('Erreur : impossible de lire ',Name);
    Halt(1);
  End;
  ProcessInput(SourceFile);
  Close(SourceFile);
End;

BEGIN
  ScaleDigits:=0;
  InputBase:=10;
  OutputBase:=10;
  MathLibrary:=False;
  Quiet:=False;
  Interactive:=False;
  StopProgram:=False;
  CurrentLine:=0;
  ParseError:=False;
  ErrorMessage:='';
  For I:=Ord('a')to Ord('z')Do Variables[Chr(I)]:=0;
  FileCount:=0;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    CurrentArg:=ParamStr(ArgumentIndex);
    If(CurrentArg='--help')or(CurrentArg='-h')or(CurrentArg='/?')or
      (CurrentArg='/h')or(CurrentArg='/H')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(CurrentArg='--version')or(CurrentArg='-v')Then Begin
      WriteLn('bc (LINUX-0) 1.0');
      Halt(0);
    End Else If(CurrentArg='-q')or(CurrentArg='--quiet')Then Quiet:=True Else
    If(CurrentArg='-i')or(CurrentArg='--interactive')Then Interactive:=True Else
    If(CurrentArg='-l')or(CurrentArg='--mathlib')Then MathLibrary:=True Else
    If(CurrentArg='-s')or(CurrentArg='--standard')Then Begin
    End Else If(CurrentArg='-w')or(CurrentArg='--warn')Then Begin
    End Else
    If(Length(CurrentArg)>1)and(CurrentArg[1]='-')Then Begin
      For I:=2 to Length(CurrentArg)Do Begin
        If CurrentArg[I]='h'Then Begin
          PrintHelp;
          Halt(0);
        End Else If CurrentArg[I]='v'Then Begin
          WriteLn('bc (LINUX-0) 1.0');
          Halt(0);
        End Else If CurrentArg[I]='q'Then Quiet:=True Else
        If CurrentArg[I]='i'Then Interactive:=True Else
        If CurrentArg[I]='l'Then MathLibrary:=True Else
        If CurrentArg[I]='s'Then Begin
        End Else If CurrentArg[I]='w'Then Begin
        End Else Begin
          WriteLn('Erreur : option inconnue : ',CurrentArg);
          Halt(2);
        End;
      End;
    End Else Begin
      If FileCount>=MaxFiles Then Begin
        WriteLn('Erreur : trop de fichiers');
        Halt(2);
      End;
      Inc(FileCount);
      FileNames[FileCount]:=CurrentArg;
    End;
    Inc(ArgumentIndex);
  End;
  If FileCount=0 Then Begin
    If Not Quiet Then WriteLn('bc (LINUX-0) 1.0');
    ProcessInput(Input);
  End Else For I:=1 to FileCount Do Begin
    ProcessFile(FileNames[I]);
    If StopProgram Then Break;
  End;
  If(FileCount>0)and Interactive and Not StopProgram Then
    ProcessInput(Input);
END.
