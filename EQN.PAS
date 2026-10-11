{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program EQN(Input,Output);

Uses DOS;

Const
 MaxLineLength=255;

Type
 TText=String[MaxLineLength];

Var
 SourceFile:Text;
 SourceName,FontName,DeviceName,MacroDirectory:TText;
 InputFromFile,InEquation,InlineActive,AllowAttachedRequest:Boolean;
 NoNewline,ReduceSize,IgnoreEqnrc:Boolean;
 HelpRequested,VersionRequested,HasDelimiters:Boolean;
 OpenDelimiter,CloseDelimiter:Char;
 PointSize,MinimumSize,ScriptSize:Integer;
 InlineBuffer,LineText:TText;
 I,ErrorCode:Integer;

Function IntToStr(Value:Integer):String;
Var
 Number:String[16];
Begin
 Str(Value,Number);
 While(Length(Number)>0)And(Number[1]=' ')Do Delete(Number,1,1);
 IntToStr:=Number;
End;

Procedure AppendText(Var Destination:TText;Const Value:String);
Begin
 If Length(Destination)+Length(Value)<=MaxLineLength Then
  Destination:=Destination+Value;
End;

Function StartsWith(Const Value,Prefix:String):Boolean;
Var
 Index:Integer;
Begin
 StartsWith:=False;
 If Length(Value)<Length(Prefix)Then Exit;
 For Index:=1 To Length(Prefix)Do
  If Value[Index]<>Prefix[Index]Then Exit;
 StartsWith:=True;
End;

Function FindCharacter(Const Value:String;Character:Char;
                       StartAt:Integer):Integer;
Var
 Index:Integer;
Begin
 FindCharacter:=0;
 If StartAt<1 Then StartAt:=1;
 For Index:=StartAt To Length(Value)Do
  If Value[Index]=Character Then Begin
   FindCharacter:=Index;
   Exit;
  End;
End;

Function IsWordCharacter(Character:Char):Boolean;
Begin
 IsWordCharacter:=Character In['A'..'Z','a'..'z','0'..'9','_'];
End;

Function TranslateWord(Const Word:String):String;
Begin
 If Word='times'Then TranslateWord:='*' Else
 If Word='cdot'Then TranslateWord:='.' Else
 If(Word='over')Or(Word='above')Then TranslateWord:='/' Else
 If(Word='from')Or(Word='sub')Then TranslateWord:='_' Else
 If(Word='to')Or(Word='sup')Then TranslateWord:='^' Else
 If Word='infinity'Then TranslateWord:='inf' Else
 If Word='approx'Then TranslateWord:='~=' Else
 If Word='neq'Then TranslateWord:='<>' Else
 If Word='le'Then TranslateWord:='<=' Else
 If Word='ge'Then TranslateWord:='>=' Else
 If Word='sum'Then TranslateWord:='SUM' Else
 If Word='prod'Then TranslateWord:='PROD' Else
 If Word='int'Then TranslateWord:='INT' Else
 If Word='partial'Then TranslateWord:='d' Else
 If Word='union'Then TranslateWord:='U' Else
 If Word='inter'Then TranslateWord:='n' Else
 If(Word='left')Or(Word='right')Or(Word='size')Or
   (Word='font')Then TranslateWord:='' Else
 TranslateWord:=Word;
End;

Procedure ConvertExpression(Const Expression:String;Var Converted:TText);
Var
 Position,StartAt:Integer;
 Word,Translated:String;
 Quoted,ScriptPending,SqrtOpen:Boolean;
Begin
 Converted:='';
 Position:=1;
 Quoted:=False;
 ScriptPending:=False;
 SqrtOpen:=False;
 While Position<=Length(Expression)Do Begin
  If Expression[Position]='"'Then Begin
   Quoted:=Not Quoted;
   Inc(Position);
  End Else If Quoted Then Begin
   AppendText(Converted,Expression[Position]);
   Inc(Position);
  End Else If IsWordCharacter(Expression[Position])Then Begin
   StartAt:=Position;
   While(Position<=Length(Expression))And
        IsWordCharacter(Expression[Position])Do Inc(Position);
   Word:=Copy(Expression,StartAt,Position-StartAt);
   If Word='sqrt'Then Begin
    AppendText(Converted,'sqrt(');
    SqrtOpen:=True;
   End Else If(Word='bold')Or(Word='fat')Then
    AppendText(Converted,'\fB')
   Else If Word='italic'Then AppendText(Converted,'\fI')
   Else If(Word='roman')Or(Word='rom')Then AppendText(Converted,'\fR')
   Else If(Word='sub')Or(Word='from')Then Begin
    AppendText(Converted,'_');
    If ScriptSize>0 Then Begin
     AppendText(Converted,'\s-');
     AppendText(Converted,IntToStr(ScriptSize));
     ScriptPending:=True;
    End;
   End Else If(Word='sup')Or(Word='to')Then Begin
    AppendText(Converted,'^');
    If ScriptSize>0 Then Begin
     AppendText(Converted,'\s-');
     AppendText(Converted,IntToStr(ScriptSize));
     ScriptPending:=True;
    End;
   End Else Begin
    Translated:=TranslateWord(Word);
    AppendText(Converted,Translated);
   End;
   If ScriptPending And(Word<>'sub')And(Word<>'sup')And
      (Word<>'from')And(Word<>'to')Then Begin
    AppendText(Converted,'\s+');
    AppendText(Converted,IntToStr(ScriptSize));
    ScriptPending:=False;
   End;
  End Else Begin
   Case Expression[Position]Of
    '{':AppendText(Converted,'(');
    '}':AppendText(Converted,')');
    '~':AppendText(Converted,' ');
   Else AppendText(Converted,Expression[Position]);
   End;
   Inc(Position);
  End;
 End;
 If ScriptPending Then Begin
  AppendText(Converted,'\s+');
  AppendText(Converted,IntToStr(ScriptSize));
 End;
 If SqrtOpen Then AppendText(Converted,')');
End;

Function EffectivePointSize:Integer;
Var
 ResultSize:Integer;
Begin
 ResultSize:=PointSize;
 If ReduceSize And(ResultSize>0)Then Dec(ResultSize);
 If(ResultSize>0)And(ResultSize<MinimumSize)Then
  ResultSize:=MinimumSize;
 EffectivePointSize:=ResultSize;
End;

Procedure WriteFormatted(Const Expression:String);
Var
 Converted:TText;
 Size:Integer;
Begin
 ConvertExpression(Expression,Converted);
 If FontName<>''Then Write('\f',FontName);
 Size:=EffectivePointSize;
 If Size>0 Then Write('\s',Size);
 Write(Converted);
 If Size>0 Then Write('\s0');
 If FontName<>''Then Write('\fP');
End;

Function IsRequest(Const Value,RequestName:String):Boolean;
Var
 NextCharacter:Char;
Begin
 IsRequest:=False;
 If Length(Value)<Length(RequestName)+1 Then Exit;
 If Value[1]<>'.'Then Exit;
 If Copy(Value,2,Length(RequestName))<>RequestName Then Exit;
 If(Length(Value)=Length(RequestName)+1)Or AllowAttachedRequest Then Begin
  IsRequest:=True;
  Exit;
 End;
 NextCharacter:=Value[Length(RequestName)+2];
 IsRequest:=NextCharacter In[' ',#9];
End;

Procedure ProcessTextLine(Const Value:String);
Var
 Position,CloseAt:Integer;
 Expression:String;
Begin
 Position:=1;
 If InlineActive Then Begin
  CloseAt:=FindCharacter(Value,CloseDelimiter,1);
  If CloseAt=0 Then Begin
   If NoNewline Then Begin
    Write(OpenDelimiter,InlineBuffer,' ',Value);
    InlineBuffer:='';
    InlineActive:=False;
    WriteLn;
   End Else Begin
    AppendText(InlineBuffer,' ');
    AppendText(InlineBuffer,Value);
   End;
   Exit;
  End;
  AppendText(InlineBuffer,' ');
  AppendText(InlineBuffer,Copy(Value,1,CloseAt-1));
  WriteFormatted(InlineBuffer);
  InlineBuffer:='';
  InlineActive:=False;
  Position:=CloseAt+1;
 End;
 While Position<=Length(Value)Do Begin
  If HasDelimiters And(Value[Position]=OpenDelimiter)Then Begin
   CloseAt:=FindCharacter(Value,CloseDelimiter,Position+1);
   If CloseAt>0 Then Begin
    Expression:=Copy(Value,Position+1,CloseAt-Position-1);
    WriteFormatted(Expression);
    Position:=CloseAt+1;
   End Else Begin
    If NoNewline Then
     Write(OpenDelimiter,Copy(Value,Position+1,MaxLineLength))
    Else Begin
     InlineBuffer:=Copy(Value,Position+1,MaxLineLength);
     InlineActive:=True;
    End;
    Position:=Length(Value)+1;
   End;
  End Else Begin
   Write(Value[Position]);
   Inc(Position);
  End;
 End;
 If Not InlineActive Then WriteLn;
End;

Procedure ProcessLine(Const Value:String);
Begin
 If InEquation Then Begin
  If IsRequest(Value,'EN')Then Begin
   InEquation:=False;
   WriteLn('.ce 0');
  WriteLn('.sp');
  End Else Begin
   WriteFormatted(Value);
   WriteLn;
  End;
 End Else If IsRequest(Value,'EQ')Then Begin
  InEquation:=True;
  WriteLn('.sp');
  WriteLn('.ce 1');
 End Else ProcessTextLine(Value);
End;

Procedure ShowHelp;
Begin
 WriteLn('EQN - Cette commande permet de lancer le preprocesseur de notation mathematique pour roff.');
 WriteLn;
 WriteLn('Syntaxe: EQN [options] [fichier]');
 WriteLn; 
 WriteLn('  -dxy    Delimiteurs d''equations en ligne');
 WriteLn('  -C      Accepter .EQ/.EN suivis d''autres caracteres');
 WriteLn('  -N      Interdire les equations en ligne sur plusieurs lignes');
 WriteLn('  -v      Afficher la version');
 WriteLn('  -r      Reduire la taille d''un point');
 WriteLn('  -mn     Taille minimale en points');
 WriteLn('  -Tnom   Peripherique de sortie (option acceptee)');
 WriteLn('  -Mdir   Repertoire eqnrc (option acceptee)');
 WriteLn('  -R      Ne pas charger eqnrc');
 WriteLn('  -fF     Police des equations');
 WriteLn('  -sn     Taille des equations');
 WriteLn('  -pn     Reduction de taille des indices/exposants');
 WriteLn;
 WriteLn('Mots reconnus: over, sub, sup, sqrt, bold, italic, sum, int.');
End;

Procedure ShowVersion;
Begin
 WriteLn('EQN 1.0 - LINUX-0 Pascal');
End;

Procedure SetNumericOption(Const OptionName,OptionText:String;
                           Var Target:Integer);
Var
 Err:Integer;
Begin
 Val(OptionText,Target,Err);
 If(Err<>0)Or(Target<0)Then Begin
  WriteLn('eqn: valeur invalide pour ',OptionName,': ',OptionText);
  Halt(2);
 End;
End;

Procedure ParseOptions;
Var
 OptionText,Value:String;
 OptionLetter:Char;
Begin
 I:=1;
 While I<=ParamCount Do Begin
  OptionText:=ParamStr(I);
  If(OptionText='--help')Or(OptionText='-h')Or
    (OptionText='/?')Or(OptionText='/h')Then HelpRequested:=True
  Else If(OptionText='--version')Or(OptionText='-v')Then
   VersionRequested:=True
  Else If(Length(OptionText)>1)And(OptionText[1]='-')Then Begin
   OptionLetter:=OptionText[2];
   Value:=Copy(OptionText,3,MaxLineLength);
   If(OptionLetter='d')Or(OptionLetter='f')Or(OptionLetter='p')Or
     (OptionLetter='s')Or(OptionLetter='m')Or(OptionLetter='T')Or
     (OptionLetter='M')Then Begin
    If Value=''Then Begin
     Inc(I);
     If I>ParamCount Then Begin
      WriteLn('eqn: option -',OptionLetter,' requiert une valeur');
      Halt(2);
     End;
     Value:=ParamStr(I);
    End;
    Case OptionLetter Of
     'd':Begin
      If Length(Value)<2 Then Begin
       WriteLn('eqn: -d requiert deux separateurs');
       Halt(2);
      End;
      OpenDelimiter:=Value[1];
      CloseDelimiter:=Value[2];
      HasDelimiters:=True;
     End;
     'f':FontName:=Value;
     'T':DeviceName:=Value;
     'M':MacroDirectory:=Value;
     'p':SetNumericOption('-p',Value,ScriptSize);
     's':SetNumericOption('-s',Value,PointSize);
     'm':SetNumericOption('-m',Value,MinimumSize);
    End;
   End Else If OptionLetter='C'Then AllowAttachedRequest:=True
   Else If OptionLetter='N'Then NoNewline:=True
   Else If OptionLetter='R'Then IgnoreEqnrc:=True
   Else If OptionLetter='r'Then ReduceSize:=True
   Else Begin
    WriteLn('eqn: option inconnue: ',OptionText);
    Halt(2);
   End;
  End Else If SourceName=''Then SourceName:=OptionText
  Else Begin
   WriteLn('eqn: un seul fichier d''entree est accepte');
   Halt(2);
  End;
  Inc(I);
 End;
End;

Procedure ProcessInput;
Begin
 If InputFromFile Then Begin
  While Not EOF(SourceFile)Do Begin
   ReadLn(SourceFile,LineText);
   ProcessLine(LineText);
  End;
 End Else Begin
  While Not EOF(Input)Do Begin
   ReadLn(Input,LineText);
   ProcessLine(LineText);
  End;
 End;
 If InlineActive Then Begin
  WriteFormatted(InlineBuffer);
  InlineActive:=False;
  WriteLn;
 End;
End;

Begin
 SourceName:='';
 FontName:='';
 DeviceName:='';
 MacroDirectory:='';
 InputFromFile:=False;
 InEquation:=False;
 InlineActive:=False;
 AllowAttachedRequest:=False;
 NoNewline:=False;
 ReduceSize:=False;
 IgnoreEqnrc:=False;
 HelpRequested:=False;
 VersionRequested:=False;
 HasDelimiters:=False;
 OpenDelimiter:='$';
 CloseDelimiter:='$';
 PointSize:=0;
 MinimumSize:=0;
 ScriptSize:=3;
 InlineBuffer:='';
 ParseOptions;
 If HelpRequested Then Begin ShowHelp;Halt;End;
 If VersionRequested Then Begin ShowVersion;Halt;End;
 If SourceName<>''Then Begin
  Assign(SourceFile,SourceName);
  {$I-}Reset(SourceFile);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
   WriteLn('eqn: fichier introuvable: ',SourceName);
   Halt(1);
  End;
  InputFromFile:=True;
 End;
 ProcessInput;
 If InputFromFile Then Close(SourceFile);
End.