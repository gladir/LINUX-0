{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program EXPR;

Uses DOS;

Const
 MaxTokens=64;
 MaxTokenLength=255;

Type
 TExprToken=String[MaxTokenLength];
 TTokenArray=Array[1..MaxTokens]Of TExprToken;

Var
 Tokens:TTokenArray;
 ResultValue:TExprToken;
 TokenCount,TokenPosition:Integer;
 ParseError:Boolean;
 ErrorText:String;

Function ParseOr:TExprToken;Forward;

Procedure SetError(Const MessageText:String);
Begin
 If Not ParseError Then ErrorText:=MessageText;
 ParseError:=True;
End;

Function CurrentToken:TExprToken;
Begin
 If TokenPosition<=TokenCount Then CurrentToken:=Tokens[TokenPosition]
 Else CurrentToken:='';
End;

Function IsTrue(Const Value:TExprToken):Boolean;
Begin
 IsTrue:=(Value<>'')And(Value<>'0');
End;

Function ToInteger(Const Value:TExprToken;Var Number:LongInt):Boolean;
Var
 ErrorCode:Integer;
Begin
 Val(Value,Number,ErrorCode);
 ToInteger:=ErrorCode=0;
End;

Function IntegerText(Value:LongInt):TExprToken;
Var
 Number:String[20];
Begin
 Str(Value,Number);
 While(Length(Number)>0)And(Number[1]=' ')Do Delete(Number,1,1);
 IntegerText:=Number;
End;

Function ParsePrimary:TExprToken;
Var
 Value:TExprToken;
Begin
 ParsePrimary:='';
 If TokenPosition>TokenCount Then Begin
  SetError('operande manquant');
  Exit;
 End;
 If CurrentToken='('Then Begin
  Inc(TokenPosition);
  Value:=ParseOr;
  If CurrentToken<>')'Then SetError('parenthese fermante manquante')
  Else Inc(TokenPosition);
  ParsePrimary:=Value;
  Exit;
 End;
 If CurrentToken=')'Then Begin
  SetError('operande inattendu: )');
  Inc(TokenPosition);
  Exit;
 End;
 ParsePrimary:=CurrentToken;
 Inc(TokenPosition);
End;

Function ParseMultiply:TExprToken;
Var
 LeftValue,RightValue,OperatorText:TExprToken;
 LeftNumber,RightNumber,ResultNumber:LongInt;
Begin
 LeftValue:=ParsePrimary;
 While(CurrentToken='*')Or(CurrentToken='/')Or(CurrentToken='%')Do Begin
  OperatorText:=CurrentToken;
  Inc(TokenPosition);
  RightValue:=ParsePrimary;
  If ParseError Then Begin ParseMultiply:='';Exit;End;
  If Not ToInteger(LeftValue,LeftNumber)Or
     Not ToInteger(RightValue,RightNumber)Then Begin
   SetError('operandes numeriques requis');
   ParseMultiply:='';
   Exit;
  End;
  If((OperatorText='/')Or(OperatorText='%'))And(RightNumber=0)Then Begin
   SetError('division par zero');
   ParseMultiply:='';
   Exit;
  End;
  If OperatorText='*'Then ResultNumber:=LeftNumber*RightNumber
  Else If OperatorText='/'Then ResultNumber:=LeftNumber Div RightNumber
  Else ResultNumber:=LeftNumber Mod RightNumber;
  LeftValue:=IntegerText(ResultNumber);
 End;
 ParseMultiply:=LeftValue;
End;

Function ParseAdd:TExprToken;
Var
 LeftValue,RightValue,OperatorText:TExprToken;
 LeftNumber,RightNumber:LongInt;
Begin
 LeftValue:=ParseMultiply;
 While(CurrentToken='+')Or(CurrentToken='-')Do Begin
  OperatorText:=CurrentToken;
  Inc(TokenPosition);
  RightValue:=ParseMultiply;
  If ParseError Then Begin ParseAdd:='';Exit;End;
  If Not ToInteger(LeftValue,LeftNumber)Or
     Not ToInteger(RightValue,RightNumber)Then Begin
   SetError('operandes numeriques requis');
   ParseAdd:='';
   Exit;
  End;
  If OperatorText='+'Then LeftNumber:=LeftNumber+RightNumber
  Else LeftNumber:=LeftNumber-RightNumber;
  LeftValue:=IntegerText(LeftNumber);
 End;
 ParseAdd:=LeftValue;
End;

Function ParseCompare:TExprToken;
Var
 LeftValue,RightValue,OperatorText:TExprToken;
 LeftNumber,RightNumber:LongInt;
 LeftNumeric,RightNumeric,Matches:Boolean;
Begin
 LeftValue:=ParseAdd;
 While(CurrentToken='=')Or(CurrentToken='!=')Or(CurrentToken='<')Or
       (CurrentToken='<=')Or(CurrentToken='>')Or(CurrentToken='>=')Do Begin
  OperatorText:=CurrentToken;
  Inc(TokenPosition);
  RightValue:=ParseAdd;
  If ParseError Then Begin ParseCompare:='';Exit;End;
  LeftNumeric:=ToInteger(LeftValue,LeftNumber);
  RightNumeric:=ToInteger(RightValue,RightNumber);
  If LeftNumeric And RightNumeric Then Begin
   If OperatorText='='Then Matches:=LeftNumber=RightNumber Else
   If OperatorText='!='Then Matches:=LeftNumber<>RightNumber Else
   If OperatorText='<'Then Matches:=LeftNumber<RightNumber Else
   If OperatorText='<='Then Matches:=LeftNumber<=RightNumber Else
   If OperatorText='>'Then Matches:=LeftNumber>RightNumber Else
    Matches:=LeftNumber>=RightNumber;
  End Else Begin
   If OperatorText='='Then Matches:=LeftValue=RightValue Else
   If OperatorText='!='Then Matches:=LeftValue<>RightValue Else
   If OperatorText='<'Then Matches:=LeftValue<RightValue Else
   If OperatorText='<='Then Matches:=LeftValue<=RightValue Else
   If OperatorText='>'Then Matches:=LeftValue>RightValue Else
    Matches:=LeftValue>=RightValue;
  End;
  If Matches Then LeftValue:='1'Else LeftValue:='0';
 End;
 ParseCompare:=LeftValue;
End;

Function ParseAnd:TExprToken;
Var
 LeftValue,RightValue:TExprToken;
Begin
 LeftValue:=ParseCompare;
 While CurrentToken='&'Do Begin
  Inc(TokenPosition);
  RightValue:=ParseCompare;
  If IsTrue(LeftValue)And IsTrue(RightValue)Then Begin
   If LeftValue='0'Then LeftValue:=RightValue;
  End Else LeftValue:='0';
 End;
 ParseAnd:=LeftValue;
End;

Function ParseOr:TExprToken;
Var
 LeftValue,RightValue:TExprToken;
Begin
 LeftValue:=ParseAnd;
 While CurrentToken='|'Do Begin
  Inc(TokenPosition);
  RightValue:=ParseAnd;
  If Not IsTrue(LeftValue)Then LeftValue:=RightValue;
 End;
 ParseOr:=LeftValue;
End;

Procedure ShowHelp;
Begin
 WriteLn('EXPR - Cette commande permet d'''+#130+'valuer une expression.');
 WriteLn;
 WriteLn('Syntaxe: EXPR expression');
 WriteLn;
 WriteLn('Operateurs, par ordre de priorite:');
 WriteLn('  |  choix entre deux valeurs');
 WriteLn('  &  et logique');
 WriteLn('  = != < <= > >=  comparaisons');
 WriteLn('  + -  addition et soustraction');
 WriteLn('  * / %  multiplication, division entiere et reste');
 WriteLn('  ( )  parenthese une sous-expression');
 WriteLn('Les arguments doivent etre separes; proteger * entre quotes dans le shell.');
 WriteLn;
 WriteLn('Exemple: EXPR 1 + 2 * 3');
End;

Procedure ShowVersion;
Begin
 WriteLn('expr 1.0 - LINUX-0 Pascal');
End;

Procedure ReadArguments;
Var
 Index:Integer;
Begin
 TokenCount:=0;
 For Index:=1 To ParamCount Do Begin
  If TokenCount>=MaxTokens Then Begin
   SetError('trop d''arguments');
   Exit;
  End;
  Inc(TokenCount);
  Tokens[TokenCount]:=ParamStr(Index);
 End;
End;

Begin
 If(ParamCount=1)And((ParamStr(1)='--help')Or(ParamStr(1)='-h')Or
   (ParamStr(1)='/?')Or(ParamStr(1)='/h')Or(ParamStr(1)='/H'))Then Begin
  ShowHelp;
  Halt(0);
 End;
 If(ParamCount=1)And((ParamStr(1)='--version')Or
   (ParamStr(1)='-V'))Then Begin
  ShowVersion;
  Halt(0);
 End;
 ErrorText:='';
 ParseError:=False;
 ReadArguments;
 If Not ParseError Then Begin
  If TokenCount=0 Then SetError('expression manquante')
  Else Begin
   TokenPosition:=1;
   ResultValue:=ParseOr;
   If(TokenPosition<=TokenCount)And Not ParseError Then
    SetError('syntaxe invalide pres de: '+CurrentToken);
  End;
 End;
 If ParseError Then Begin
  WriteLn('expr: ',ErrorText);
  Halt(2);
 End;
 WriteLn(ResultValue);
 If IsTrue(ResultValue)Then Halt(0)Else Halt(1);
End.