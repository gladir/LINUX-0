{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program DC(Input,Output);

Uses DOS;

Const
  MaxLimbs=96;
  LimbBase=10000;
  MaxStack=32;
  MaxFiles=16;
  NumberDigits:Array[0..15]Of Char=
    ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');

Type
  TBigInteger=Record
    Sign:Integer;
    Count:Integer;
    Digits:Array[0..MaxLimbs-1]Of Word;
  End;
  TBigStack=Array[1..MaxStack]Of TBigInteger;
  TRegisterArray=Array['a'..'z']Of TBigInteger;
  TFileArray=Array[1..MaxFiles]Of String[127];

Var
  Stack:TBigStack;
  Registers:TRegisterArray;
  FileNames:TFileArray;
  StackCount,FileCount,InputBase,OutputBase,ScaleValue:Integer;
  ArgumentIndex:Integer;
  Argument,LanguageCode:String;
  InputFile:Text;
  Terminated:Boolean;
  ParseError,ErrorFound:Boolean;

Procedure ClearBig(Var Value:TBigInteger);
Var
  Index:Integer;
Begin
  Value.Sign:=0;
  Value.Count:=0;
  For Index:=0 to MaxLimbs-1 Do Value.Digits[Index]:=0;
End;

Procedure NormalizeBig(Var Value:TBigInteger);
Begin
  While(Value.Count>0)and(Value.Digits[Value.Count-1]=0)Do Dec(Value.Count);
  If Value.Count=0 Then Value.Sign:=0;
End;

Function CompareAbs(Const First,Second:TBigInteger):Integer;
Var
  Index:Integer;
Begin
  If First.Count<Second.Count Then Begin CompareAbs:=-1;Exit;End;
  If First.Count>Second.Count Then Begin CompareAbs:=1;Exit;End;
  For Index:=First.Count-1 downto 0 Do Begin
    If First.Digits[Index]<Second.Digits[Index]Then Begin CompareAbs:=-1;Exit;End;
    If First.Digits[Index]>Second.Digits[Index]Then Begin CompareAbs:=1;Exit;End;
  End;
  CompareAbs:=0;
End;

Procedure AddAbs(Const First,Second:TBigInteger; Var ResultValue:TBigInteger);
Var
  Index,MaxCount:Integer;
  Carry,Total:LongInt;
Begin
  ClearBig(ResultValue);
  If First.Count>Second.Count Then MaxCount:=First.Count Else MaxCount:=Second.Count;
  Carry:=0;
  For Index:=0 to MaxCount-1 Do Begin
    Total:=Carry;
    If Index<First.Count Then Inc(Total,First.Digits[Index]);
    If Index<Second.Count Then Inc(Total,Second.Digits[Index]);
    ResultValue.Digits[Index]:=Total mod LimbBase;
    Carry:=Total div LimbBase;
  End;
  ResultValue.Count:=MaxCount;
  If Carry>0 Then Begin
    If ResultValue.Count<MaxLimbs Then Begin
      ResultValue.Digits[ResultValue.Count]:=Carry;
      Inc(ResultValue.Count);
    End Else ParseError:=True;
  End;
  ResultValue.Sign:=1;
End;

Procedure SubtractAbs(Const First,Second:TBigInteger; Var ResultValue:TBigInteger);
Var
  Index:Integer;
  Borrow,Total:LongInt;
Begin
  ClearBig(ResultValue);
  Borrow:=0;
  For Index:=0 to First.Count-1 Do Begin
    Total:=LongInt(First.Digits[Index])-Borrow;
    If Index<Second.Count Then Dec(Total,Second.Digits[Index]);
    If Total<0 Then Begin Inc(Total,LimbBase);Borrow:=1;End Else Borrow:=0;
    ResultValue.Digits[Index]:=Total;
  End;
  ResultValue.Count:=First.Count;
  ResultValue.Sign:=1;
  NormalizeBig(ResultValue);
End;

Procedure AddBig(Const First,Second:TBigInteger; Var ResultValue:TBigInteger);
Var
  CompareValue:Integer;
  Temporary:TBigInteger;
Begin
  If First.Sign=0 Then Begin ResultValue:=Second;Exit;End;
  If Second.Sign=0 Then Begin ResultValue:=First;Exit;End;
  If First.Sign=Second.Sign Then Begin
    AddAbs(First,Second,ResultValue);
    ResultValue.Sign:=First.Sign;
  End Else Begin
    CompareValue:=CompareAbs(First,Second);
    If CompareValue=0 Then ClearBig(ResultValue)
    Else If CompareValue>0 Then Begin
      SubtractAbs(First,Second,Temporary);
      ResultValue:=Temporary;
      ResultValue.Sign:=First.Sign;
    End Else Begin
      SubtractAbs(Second,First,Temporary);
      ResultValue:=Temporary;
      ResultValue.Sign:=Second.Sign;
    End;
  End;
End;

Procedure NegateBig(Var Value:TBigInteger);
Begin
  Value.Sign:=-Value.Sign;
End;

Procedure MultiplySmall(Var Value:TBigInteger; Factor:Word);
Var
  Index:Integer;
  Carry,Total:LongInt;
Begin
  If(Value.Sign=0)or(Factor=0)Then Begin ClearBig(Value);Exit;End;
  Carry:=0;
  For Index:=0 to Value.Count-1 Do Begin
    Total:=LongInt(Value.Digits[Index])*Factor+Carry;
    Value.Digits[Index]:=Total mod LimbBase;
    Carry:=Total div LimbBase;
  End;
  While Carry>0 Do Begin
    If Value.Count>=MaxLimbs Then Begin ParseError:=True;Exit;End;
    Value.Digits[Value.Count]:=Carry mod LimbBase;
    Carry:=Carry div LimbBase;
    Inc(Value.Count);
  End;
End;

Procedure AddSmall(Var Value:TBigInteger; Amount:Word);
Var
  Index:Integer;
  Carry,Total:LongInt;
Begin
  If Amount=0 Then Exit;
  If Value.Sign<0 Then Begin
    WriteLn('dc: internal signed parse error');
    ParseError:=True;
    Exit;
  End;
  If Value.Sign=0 Then Value.Sign:=1;
  Carry:=Amount;
  Index:=0;
  While Carry>0 Do Begin
    If Index>=MaxLimbs Then Begin ParseError:=True;Exit;End;
    If Index>=Value.Count Then Begin Value.Digits[Index]:=0;Inc(Value.Count);End;
    Total:=Value.Digits[Index]+Carry;
    Value.Digits[Index]:=Total mod LimbBase;
    Carry:=Total div LimbBase;
    Inc(Index);
  End;
End;

Procedure MultiplyBig(Const First,Second:TBigInteger; Var ResultValue:TBigInteger);
Var
  FirstIndex,SecondIndex,Index:Integer;
  Carry,Total:LongInt;
Begin
  ClearBig(ResultValue);
  If(First.Sign=0)or(Second.Sign=0)Then Exit;
  For FirstIndex:=0 to First.Count-1 Do Begin
    Carry:=0;
    For SecondIndex:=0 to Second.Count-1 Do Begin
      Index:=FirstIndex+SecondIndex;
      If Index>=MaxLimbs Then Begin ParseError:=True;Exit;End;
      Total:=ResultValue.Digits[Index]+
        LongInt(First.Digits[FirstIndex])*Second.Digits[SecondIndex]+Carry;
      ResultValue.Digits[Index]:=Total mod LimbBase;
      Carry:=Total div LimbBase;
    End;
    Index:=FirstIndex+Second.Count;
    While Carry>0 Do Begin
      If Index>=MaxLimbs Then Begin ParseError:=True;Exit;End;
      Total:=ResultValue.Digits[Index]+Carry;
      ResultValue.Digits[Index]:=Total mod LimbBase;
      Carry:=Total div LimbBase;
      Inc(Index);
    End;
  End;
  ResultValue.Count:=First.Count+Second.Count;
  If ResultValue.Count>MaxLimbs Then ResultValue.Count:=MaxLimbs;
  ResultValue.Sign:=First.Sign*Second.Sign;
  NormalizeBig(ResultValue);
End;

Function DivideSmall(Var Value:TBigInteger; Divisor:Word):Word;
Var
  Index:Integer;
  RemainderValue,Total:LongInt;
Begin
  RemainderValue:=0;
  For Index:=Value.Count-1 downto 0 Do Begin
    Total:=RemainderValue*LimbBase+Value.Digits[Index];
    Value.Digits[Index]:=Total div Divisor;
    RemainderValue:=Total mod Divisor;
  End;
  NormalizeBig(Value);
  DivideSmall:=RemainderValue;
End;

Procedure ShiftBaseAdd(Var Value:TBigInteger; Digit:Word);
Var
  Index:Integer;
Begin
  If Value.Count>=MaxLimbs Then Begin ParseError:=True;Exit;End;
  For Index:=Value.Count downto 1 Do Value.Digits[Index]:=Value.Digits[Index-1];
  Value.Digits[0]:=Digit;
  Inc(Value.Count);
  If Value.Sign=0 Then Value.Sign:=1;
  NormalizeBig(Value);
End;

Procedure DivideBig(Const Dividend,Divisor:TBigInteger;
                    Var Quotient,RemainderValue:TBigInteger);
Var
  Index,LowValue,HighValue,MiddleValue,BestValue,CompareValue:Integer;
  Trial,PositiveDividend,PositiveDivisor,NewRemainder:TBigInteger;
Begin
  ClearBig(Quotient);
  ClearBig(RemainderValue);
  If Divisor.Sign=0 Then Begin ParseError:=True;Exit;End;
  PositiveDividend:=Dividend;
  PositiveDivisor:=Divisor;
  PositiveDividend.Sign:=Abs(PositiveDividend.Sign);
  PositiveDivisor.Sign:=Abs(PositiveDivisor.Sign);
  Quotient.Count:=Dividend.Count;
  For Index:=Dividend.Count-1 downto 0 Do Begin
    ShiftBaseAdd(RemainderValue,PositiveDividend.Digits[Index]);
    LowValue:=0;HighValue:=LimbBase-1;BestValue:=0;
    While LowValue<=HighValue Do Begin
      MiddleValue:=(LowValue+HighValue)div 2;
      Trial:=PositiveDivisor;
      MultiplySmall(Trial,MiddleValue);
      CompareValue:=CompareAbs(Trial,RemainderValue);
      If CompareValue<=0 Then Begin BestValue:=MiddleValue;LowValue:=MiddleValue+1;End
      Else HighValue:=MiddleValue-1;
    End;
    Quotient.Digits[Index]:=BestValue;
    If BestValue>0 Then Begin
      Trial:=PositiveDivisor;
      MultiplySmall(Trial,BestValue);
      SubtractAbs(RemainderValue,Trial,NewRemainder);
      RemainderValue:=NewRemainder;
    End;
  End;
  Quotient.Sign:=Dividend.Sign*Divisor.Sign;
  RemainderValue.Sign:=Dividend.Sign;
  NormalizeBig(Quotient);
  NormalizeBig(RemainderValue);
End;

Function DigitValue(Value:Char):Integer;
Begin
  If Value in['0'..'9']Then DigitValue:=Ord(Value)-Ord('0')
  Else If Value in['A'..'F']Then DigitValue:=Ord(Value)-Ord('A')+10
  Else If Value in['a'..'f']Then DigitValue:=Ord(Value)-Ord('a')+10
  Else DigitValue:=-1;
End;

Function ParseBigNumber(Const Token:String; Base:Integer;
                        Var Value:TBigInteger):Boolean;
Var
  Index,Digit,SignValue:Integer;
Begin
  ClearBig(Value);
  ParseBigNumber:=False;
  Index:=1;SignValue:=1;
  If(Length(Token)>0)and(Token[1]='_')Then Begin SignValue:=-1;Inc(Index);End
  Else If(Length(Token)>0)and(Token[1]='-')Then Begin SignValue:=-1;Inc(Index);End
  Else If(Length(Token)>0)and(Token[1]='+')Then Inc(Index);
  If Index>Length(Token)Then Exit;
  For Index:=Index to Length(Token)Do Begin
    Digit:=DigitValue(Token[Index]);
    If(Digit<0)or(Digit>=Base)Then Exit;
    MultiplySmall(Value,Base);
    AddSmall(Value,Digit);
    If ParseError Then Exit;
  End;
  Value.Sign:=SignValue;
  NormalizeBig(Value);
  ParseBigNumber:=True;
End;

Function BigToString(Value:TBigInteger; Base:Integer):String;
Var
  RemainderValue:Word;
  ResultValue:String;
  OriginalSign:Integer;
Begin
  ResultValue:='';
  If Value.Sign=0 Then Begin BigToString:='0';Exit;End;
  OriginalSign:=Value.Sign;
  Value.Sign:=1;
  While Value.Count>0 Do Begin
    RemainderValue:=DivideSmall(Value,Base);
    ResultValue:=NumberDigits[RemainderValue]+ResultValue;
  End;
  If OriginalSign<0 Then ResultValue:='-'+ResultValue;
  BigToString:=ResultValue;
End;

Procedure PushBig(Const Value:TBigInteger);
Begin
  If StackCount>=MaxStack Then Begin WriteLn('dc: pile pleine');ParseError:=True;Exit;End;
  Inc(StackCount);
  Stack[StackCount]:=Value;
End;

Procedure PopBig(Var Value:TBigInteger);
Begin
  If StackCount=0 Then Begin WriteLn('dc: pile vide');ParseError:=True;ClearBig(Value);Exit;End;
  Value:=Stack[StackCount];
  Dec(StackCount);
End;

Procedure PrintBig(Const Value:TBigInteger; AddNewLine:Boolean);
Var
  TextValue:String;
Begin
  TextValue:=BigToString(Value,OutputBase);
  If AddNewLine Then WriteLn(TextValue)Else Write(TextValue);
End;

Procedure PerformBinary(Operation:Char);
Var
  First,Second,ResultValue,RemainderValue,Temporary:TBigInteger;
Begin
  PopBig(Second);If ParseError Then Exit;
  PopBig(First);If ParseError Then Begin PushBig(Second);Exit;End;
  Case Operation Of
    '+':AddBig(First,Second,ResultValue);
    '-':Begin NegateBig(Second);AddBig(First,Second,ResultValue);End;
    '*':MultiplyBig(First,Second,ResultValue);
    '/':DivideBig(First,Second,ResultValue,RemainderValue);
    '%':Begin DivideBig(First,Second,ResultValue,RemainderValue);ResultValue:=RemainderValue;End;
    '~':DivideBig(First,Second,ResultValue,RemainderValue);
    '^':Begin
      If Second.Sign<0 Then ParseError:=True
      Else Begin
        ClearBig(ResultValue);
        ResultValue.Sign:=1;ResultValue.Count:=1;ResultValue.Digits[0]:=1;
        While Second.Sign<>0 Do Begin
          If(Second.Digits[0]mod 2)=1 Then Begin
            MultiplyBig(ResultValue,First,Temporary);
            ResultValue:=Temporary;
          End;
          DivideSmall(Second,2);
          If Second.Sign<>0 Then Begin
            MultiplyBig(First,First,Temporary);
            First:=Temporary;
          End;
          If ParseError Then Break;
        End;
      End;
    End;
  End;
  If ParseError Then Exit;
  PushBig(ResultValue);
  If(Operation='~')and Not ParseError Then PushBig(RemainderValue);
End;

Procedure ExecuteLine(Const Line:String);Forward;

Procedure ExecuteToken(Const Token:String);
Var
  Value,ResultValue:TBigInteger;
  Name:Char;
  RemainderValue:Word;
  Parsed:Boolean;
Begin
  ParseError:=False;
  If Token=''Then Exit;
  If ParseBigNumber(Token,InputBase,Value)Then Begin PushBig(Value);Exit;End;
  If Length(Token)=2 Then Begin
    Name:=Token[2];
    If Name in['A'..'Z']Then Name:=Chr(Ord(Name)+32);
    Case Token[1]Of
      's':Begin PopBig(Value);If Not ParseError Then Registers[Name]:=Value;End;
      'l':PushBig(Registers[Name]);
      'S':Begin PopBig(Value);If Not ParseError Then PushBig(Registers[Name]);Registers[Name]:=Value;End;
      'L':Begin Value:=Registers[Name];PushBig(Value);ClearBig(Registers[Name]);End;
    Else Begin WriteLn('dc: commande inconnue: ',Token);ParseError:=True;End;
    End;
    Exit;
  End;
  If Length(Token)<>1 Then Begin WriteLn('dc: jeton invalide: ',Token);ParseError:=True;Exit;End;
  Case Token[1]Of
    '+','-','*','/','%','~','^':PerformBinary(Token[1]);
    'p':If StackCount=0 Then Begin WriteLn('dc: pile vide');ParseError:=True;End
       Else PrintBig(Stack[StackCount],True);
    'n':If StackCount=0 Then Begin WriteLn('dc: pile vide');ParseError:=True;End
       Else Begin PrintBig(Stack[StackCount],False);PopBig(Value);End;
    'f':Begin
      Parsed:=False;
      While StackCount>0 Do Begin PrintBig(Stack[StackCount],True);Dec(StackCount);Parsed:=True;End;
      If Not Parsed Then WriteLn('dc: pile vide');
    End;
    'd':If StackCount=0 Then Begin WriteLn('dc: pile vide');ParseError:=True;End
       Else PushBig(Stack[StackCount]);
    'r':If StackCount<2 Then Begin WriteLn('dc: deux valeurs requises');ParseError:=True;End
       Else Begin Value:=Stack[StackCount];Stack[StackCount]:=Stack[StackCount-1];Stack[StackCount-1]:=Value;End;
    'c':StackCount:=0;
    'z':Begin ClearBig(Value);Value.Sign:=1;Value.Count:=1;Value.Digits[0]:=StackCount;PushBig(Value);End;
    'Z':If StackCount=0 Then Begin WriteLn('dc: pile vide');ParseError:=True;End
       Else Begin
         Value:=Stack[StackCount];
         ClearBig(ResultValue);ResultValue.Sign:=1;ResultValue.Count:=1;
         If Value.Count>0 Then ResultValue.Digits[0]:=(Value.Count-1)*4+Length(BigToString(Value,10));
         PushBig(ResultValue);
       End;
    'i','o':Begin
      PopBig(Value);
      If Not ParseError Then Begin
        If(Value.Sign<0)or(Value.Count>1)Then ParseError:=True
        Else Begin
          If Value.Count=0 Then RemainderValue:=0
          Else RemainderValue:=Value.Digits[0];
          If(RemainderValue<2)or(RemainderValue>16)Then ParseError:=True
          Else If Token[1]='i'Then InputBase:=RemainderValue
          Else OutputBase:=RemainderValue;
        End;
      End;
    End;
    'k':Begin PopBig(Value);If Not ParseError Then ScaleValue:=Value.Digits[0];End;
    'a':If StackCount=0 Then Begin WriteLn('dc: pile vide');ParseError:=True;End
       Else If(Stack[StackCount].Sign<0)or(Stack[StackCount].Count>1)or
         (Stack[StackCount].Digits[0]>255)Then Write('?')
       Else Write(Chr(Stack[StackCount].Digits[0]));
    'P':Begin PopBig(Value);If Not ParseError Then Write(BigToString(Value,OutputBase));End;
    'q','Q':Terminated:=True;
    '?':Begin ReadLn(Argument);ExecuteLine(Argument);End;
    'x':If StackCount=0 Then Begin WriteLn('dc: pile vide');ParseError:=True;End;
    Else Begin WriteLn('dc: commande inconnue: ',Token);ParseError:=True;End;
  End;
End;

Procedure ExecuteLine(Const Line:String);
Var
  Position,StartPosition:Integer;
  NumericStart:Boolean;
  Token:String;
  ResultValue:TBigInteger;
Begin
  Position:=1;
  While Position<=Length(Line)Do Begin
    If Line[Position]in[' ',#9,#10,#13]Then Inc(Position)
    Else Begin
      StartPosition:=Position;
      NumericStart:=Line[Position]='_';
      If NumericStart Then Inc(Position);
      While(Position<=Length(Line))and
        (DigitValue(Line[Position])>=0)and(DigitValue(Line[Position])<InputBase)Do
        Inc(Position);
      If Position>StartPosition Then Begin
        Token:=Copy(Line,StartPosition,Position-StartPosition);
        If ParseBigNumber(Token,InputBase,ResultValue)Then PushBig(ResultValue)
        Else Begin WriteLn('dc: nombre invalide: ',Token);ParseError:=True;End;
      End Else Begin
        Token:=Line[Position];Inc(Position);
        If(Token[1]in['s','l','S','L'])and(Position<=Length(Line))and
          Not(Line[Position]in[' ',#9,#10,#13])Then Begin
          Token:=Token+Line[Position];
          Inc(Position);
        End;
        ExecuteToken(Token);
      End;
    End;
  End;
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('DC : Arbitrary-precision reverse Polish calculator.');
    WriteLn('Syntax: dc [file]');
    WriteLn('Operators: + - * / % ~ ^');
    WriteLn('Commands: p print, n print/pop, f stack, d duplicate, r swap, c clear');
    WriteLn('          sa/la store/load register a; i/o set input/output base; q quit');
    WriteLn('Numbers use the current input base (2..16); _ prefixes a negative number.');
  End Else Begin
    WriteLn('DC : Cette commande permet d''utiliser une calculatrice RPN a entiers de grande pr'+#130+'cision.');
    WriteLn;
    WriteLn('Syntaxe : dc [fichier]');
    WriteLn;
    WriteLn('Operateurs : + - * / % ~ ^');
    WriteLn('Commandes : p afficher, n afficher/depiler, f pile, d dupliquer, r inverser, c vider');
    WriteLn('            sa/la stocker/charger le registre a; i/o bases entree/sortie; q quitter');
    WriteLn('Base numerique 2..16; _ prefixe un nombre negatif.');
  End;
End;

Procedure ProcessInput(Var Source:Text);
Var
  Line:String;
Begin
  While Not EOF(Source)and Not Terminated Do Begin
    ReadLn(Source,Line);
    ExecuteLine(Line);
  End;
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  StackCount:=0;InputBase:=10;OutputBase:=10;ScaleValue:=0;
  Terminated:=False;ParseError:=False;ErrorFound:=False;
  FileCount:=0;ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('dc (LINUX-0) 1.0');Halt(0);End
    Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      WriteLn('dc: option inconnue: ',Argument);Halt(2);
    End Else Begin
      If FileCount>=MaxFiles Then Begin WriteLn('dc: trop de fichiers');Halt(2);End;
      Inc(FileCount);FileNames[FileCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If FileCount=0 Then ProcessInput(Input)
  Else For ArgumentIndex:=1 to FileCount Do Begin
    Assign(InputFile,FileNames[ArgumentIndex]);
    {$I-}Reset(InputFile);{$I+}
    If IOResult<>0 Then Begin
      WriteLn('dc: impossible de lire ',FileNames[ArgumentIndex]);
      ErrorFound:=True;
    End Else Begin
      ProcessInput(InputFile);
      Close(InputFile);
    End;
    If Terminated Then Break;
  End;
  If ErrorFound Then Halt(1);
END.