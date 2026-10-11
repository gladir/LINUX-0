{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program FORMAT;

Uses DOS;

Const
 MaxTextLength=255;

Type
 TText=String[MaxTextLength];

Var
 ArgumentIndex:Integer;
 ErrorFound:Boolean;

Procedure ReportError(Const MessageText:TText);
Begin
 WriteLn('format: ',MessageText);
 ErrorFound:=True;
End;

Function IntegerText(Value:LongInt):TText;
Var
 Number:String[20];
Begin
 Str(Value,Number);
 While(Length(Number)>0)And(Number[1]=' ')Do Delete(Number,1,1);
 IntegerText:=Number;
End;

Function ConvertBase(Value:LongInt;Base:Integer;UpperCaseDigits:Boolean):TText;
Const
 LowerDigits='0123456789abcdef';
 UpperDigits='0123456789ABCDEF';
Var
 Digits:String[16];
 ResultText:TText;
 Remainder:Integer;
 Negative:Boolean;
Begin
 If UpperCaseDigits Then Digits:=UpperDigits Else Digits:=LowerDigits;
 Negative:=Value<0;
 If Negative Then Value:=-Value;
 ResultText:='';
 Repeat
  Remainder:=Value Mod Base;
  ResultText:=Digits[Remainder+1]+ResultText;
  Value:=Value Div Base;
 Until Value=0;
 If Negative Then ResultText:='-'+ResultText;
 ConvertBase:=ResultText;
End;

Function ReadNumber(Const ValueText:TText;Var Value:LongInt):Boolean;
Var
 ErrorCode:Integer;
Begin
 Val(ValueText,Value,ErrorCode);
 ReadNumber:=ErrorCode=0;
End;

Procedure WritePadded(Const Value:TText;Width,Precision:Integer;
                      LeftAlign,ZeroPad,Numeric:Boolean);
Var
 OutputText,Padding:String;
 PaddingCount,Index,SignLength:Integer;
Begin
 OutputText:=Value;
 If Precision>=0 Then Begin
  If Numeric Then Begin
   SignLength:=0;
   If(Length(OutputText)>0)And(OutputText[1]='-')Then SignLength:=1;
   While Length(OutputText)-SignLength<Precision Do Begin
    If SignLength=1 Then Insert('0',OutputText,2)
    Else OutputText:='0'+OutputText;
   End;
  End Else If Length(OutputText)>Precision Then
   OutputText:=Copy(OutputText,1,Precision);
 End;
 PaddingCount:=Width-Length(OutputText);
 If PaddingCount<0 Then PaddingCount:=0;
 Padding:='';
 For Index:=1 To PaddingCount Do
  If ZeroPad And Numeric And Not LeftAlign Then Padding:=Padding+'0'
  Else Padding:=Padding+' ';
 If LeftAlign Then Write(OutputText,Padding)
 Else If ZeroPad And Numeric And(Length(OutputText)>0)And
         (OutputText[1]='-')Then
  Write('-',Padding,Copy(OutputText,2,MaxTextLength))
 Else Write(Padding,OutputText);
End;

Procedure WriteConversion(Const FormatText:TText;Var Position:Integer);
Var
 Width,Precision:Integer;
 LeftAlign,ZeroPad,Numeric:Boolean;
 Conversion:Char;
 ValueText,OutputText:TText;
 NumericValue:LongInt;
Begin
 LeftAlign:=False;
 ZeroPad:=False;
 Width:=0;
 Precision:=-1;
 Inc(Position);
 If(Position>Length(FormatText))Then Begin
  Write('%');
  Exit;
 End;
 If FormatText[Position]='%'Then Begin
  Write('%');
  Inc(Position);
  Exit;
 End;
 While(Position<=Length(FormatText))And
      (FormatText[Position]In['-','0'])Do Begin
  If FormatText[Position]='-'Then LeftAlign:=True
  Else ZeroPad:=True;
  Inc(Position);
 End;
 While(Position<=Length(FormatText))And
      (FormatText[Position]In['0'..'9'])Do Begin
  If Width<1000 Then Width:=Width*10+Ord(FormatText[Position])-Ord('0');
  Inc(Position);
 End;
 If(Position<=Length(FormatText))And(FormatText[Position]='.')Then Begin
  Precision:=0;
  Inc(Position);
  While(Position<=Length(FormatText))And
       (FormatText[Position]In['0'..'9'])Do Begin
   If Precision<1000 Then Precision:=Precision*10+
    Ord(FormatText[Position])-Ord('0');
   Inc(Position);
  End;
 End;
 If Position>Length(FormatText)Then Begin
  ReportError('specificateur de format incomplet');
  Exit;
 End;
 Conversion:=FormatText[Position];
 Inc(Position);
 If Not(Conversion In['s','d','i','u','x','X','o','c'])Then Begin
  ReportError('conversion inconnue: %'+Conversion);
  Exit;
 End;
 If ArgumentIndex>ParamCount Then Begin
  ReportError('argument manquant pour %'+Conversion);
  Exit;
 End;
 ValueText:=ParamStr(ArgumentIndex);
 Inc(ArgumentIndex);
 OutputText:=ValueText;
 Numeric:=False;
 Case Conversion Of
  's':OutputText:=ValueText;
  'c':Begin
   If ReadNumber(ValueText,NumericValue)Then Begin
    If(NumericValue<0)Or(NumericValue>255)Then Begin
     ReportError('valeur hors plage pour %c');
     Exit;
    End;
    OutputText:=Chr(NumericValue);
   End Else If ValueText<>''Then OutputText:=ValueText[1]
   Else OutputText:='';
  End;
 Else Begin
  Numeric:=True;
  If Not ReadNumber(ValueText,NumericValue)Then Begin
   ReportError('valeur numerique invalide: '+ValueText);
   Exit;
  End;
  Case Conversion Of
   'd','i','u':OutputText:=IntegerText(NumericValue);
   'x':OutputText:=ConvertBase(NumericValue,16,False);
   'X':OutputText:=ConvertBase(NumericValue,16,True);
   'o':OutputText:=ConvertBase(NumericValue,8,False);
  End;
 End;
 End;
 WritePadded(OutputText,Width,Precision,LeftAlign,ZeroPad,Numeric);
End;

Procedure WriteFormat(Const FormatText:TText);
Var
 Position:Integer;
 Character:Char;
Begin
 Position:=1;
 While Position<=Length(FormatText)Do Begin
  Character:=FormatText[Position];
  If Character='%'Then WriteConversion(FormatText,Position)
  Else If Character=#92 Then Begin
   Inc(Position);
   If Position<=Length(FormatText)Then Begin
    Case FormatText[Position]Of
     'n':WriteLn;
     't':Write(#9);
     'r':Write(#13);
     'b':Write(#8);
     'a':Write(#7);
     'f':Write(#12);
     #92:Write(#92);
    Else Write(FormatText[Position]);
    End;
    Inc(Position);
   End;
  End Else Begin
   Write(Character);
   Inc(Position);
  End;
 End;
End;

Procedure ShowHelp;
Begin
 WriteLn('FORMAT - Cette commande permet de formater une chaine avec des arguments.');
 WriteLn;
 WriteLn('Syntaxe: FORMAT formatString [arguments ...]');
 WriteLn('  %s texte    Chaine');
 WriteLn('  %d, %i      Entier decimal');
 WriteLn('  %u          Entier non signe');
 WriteLn('  %x, %X, %o  Entier hexadecimal ou octal');
 WriteLn('  %c          Caractere');
 WriteLn('  %%          Signe pourcent');
 WriteLn;
 WriteLn('Largeur, precision, - pour aligner a gauche et 0 sont reconnus.');
 WriteLn('Echappements: \n, \t, \r, \\');
End;

Procedure ShowVersion;
Begin
 WriteLn('format 1.0 - LINUX-0 Pascal');
End;

Begin
 ErrorFound:=False;
 If(ParamCount=1)And((ParamStr(1)='/?')Or(ParamStr(1)='/h')Or
   (ParamStr(1)='/H')Or(ParamStr(1)='-h')Or
   (ParamStr(1)='--help'))Then Begin
  ShowHelp;
  Halt(0);
 End;
 If(ParamCount=1)And((ParamStr(1)='-V')Or
   (ParamStr(1)='--version'))Then Begin
  ShowVersion;
  Halt(0);
 End;
 If ParamCount=0 Then Begin
  ReportError('formatString manquant');
  Halt(2);
 End;
 ArgumentIndex:=2;
 WriteFormat(ParamStr(1));
 If ErrorFound Then Halt(2);
End.