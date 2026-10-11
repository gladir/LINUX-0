{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program EGREP(Input,Output);

Uses DOS;

Const
 MaxNodes=512;
 MaxPatterns=64;
 MaxFiles=64;
 MaxContext=64;

Type
 TText=String[255];
 TChars=Set Of Char;
 TPositions=Set Of Byte;
 TNode=Record
  Kind:Char;
  Left,Right,Minimum,Maximum:Integer;
  Chars:TChars;
 End;
 PLine=^TLine;
 TLine=Record
  Value:TText;
  Number,Offset:LongInt;
 End;

Var
 Nodes:Array[1..MaxNodes]Of TNode;
 NodeDepth:Array[1..MaxNodes]Of Integer;
 Roots:Array[1..MaxPatterns]Of Integer;
 Patterns:Array[1..MaxPatterns]Of TText;
 Files:Array[1..MaxFiles]Of TText;
 History:Array[0..MaxContext]Of PLine;
 NodeCount,PatternCount,FileCount:Integer;
 BeforeCount,AfterCount:Integer;
 IgnoreCase,Invert,WholeWord,WholeLine,CountMode:Boolean;
 ListMatches,ListNonMatches,Quiet,Silent,NoFilePrefix:Boolean;
 English,HadError,AnySelected,ExplicitPatterns:Boolean;
 Pattern:TText;
 ParsePosition,ParseDepth:Integer;
 ParseFailed:Boolean;
 CurrentText,CurrentFile:TText;
 TextLength:Integer;
 LineNumber,ByteOffset,SelectedCount,LastPrinted,AfterUntil:LongInt;
 HistoryCount,HistoryNext:Integer;
 PrintedGroup:Boolean;
 NumberPrefix,BytePrefix:Boolean;

Procedure Diagnostic(Const FrenchText,EnglishText:TText);
Begin
 HadError:=True;
 If Silent Then Exit;
 {$IFDEF FPC}
 If English Then WriteLn(ErrOutput,'egrep: ',EnglishText)
 Else WriteLn(ErrOutput,'egrep : ',FrenchText);
 {$ELSE}
 If English Then WriteLn('egrep: ',EnglishText)
 Else WriteLn('egrep : ',FrenchText);
 {$ENDIF}
End;

Procedure UsageError(Const Value:TText);
Begin
 Diagnostic(Value,Value);Halt(2);
End;

Function NewNode(Kind:Char; Left,Right:Integer):Integer;
Var Depth:Integer;
Begin
 NewNode:=0;
 If NodeCount=MaxNodes Then Begin ParseFailed:=True;Exit;End;
 Depth:=0;
 If Left<>0 Then Depth:=NodeDepth[Left];
 If Right<>0 Then
  If NodeDepth[Right]>Depth Then Depth:=NodeDepth[Right];
 Inc(Depth);
 If Depth>64 Then Begin ParseFailed:=True;Exit;End;
 Inc(NodeCount);
 NodeDepth[NodeCount]:=Depth;
 Nodes[NodeCount].Kind:=Kind;
 Nodes[NodeCount].Left:=Left;Nodes[NodeCount].Right:=Right;
 Nodes[NodeCount].Chars:=[];
 NewNode:=NodeCount;
End;

Function Peek:Char;
Begin
 Peek:=#0;
 If ParsePosition<=Length(Pattern)Then Peek:=Pattern[ParsePosition];
End;

Procedure ClassCharacters(Const Name:TText;Var Characters:TChars);
Begin
 Characters:=[];
 If Name='digit'Then Characters:=['0'..'9']
 Else If Name='alpha'Then Characters:=['A'..'Z','a'..'z']
 Else If Name='alnum'Then Characters:=['A'..'Z','a'..'z','0'..'9']
 Else If Name='lower'Then Characters:=['a'..'z']
 Else If Name='upper'Then Characters:=['A'..'Z']
 Else If Name='space'Then Characters:=[#9..#13,' ']
 Else If Name='blank'Then Characters:=[#9,' ']
 Else If Name='xdigit'Then Characters:=['0'..'9','A'..'F','a'..'f']
 Else If Name='cntrl'Then Characters:=[#0..#31,#127]
 Else If Name='print'Then Characters:=[#32..#126]
 Else If Name='graph'Then Characters:=[#33..#126]
 Else If Name='punct'Then
  Characters:=[#33..#126]-['A'..'Z','a'..'z','0'..'9']
 Else ParseFailed:=True;
End;

Function ParseExpression:Integer;Forward;

Function ParseAtom:Integer;
Var Root,Start,Index:Integer; FirstChar,LastChar:Char;
    Characters,ClassChars:TChars; Negated,Closed:Boolean; Name:TText;
Begin
 Root:=0;
 If Peek='('Then Begin
  Inc(ParsePosition);Inc(ParseDepth);
  If ParseDepth>32 Then Begin ParseFailed:=True;ParseAtom:=0;Exit;End;
  Root:=ParseExpression;
  If Peek<>')'Then ParseFailed:=True Else Inc(ParsePosition);
  Dec(ParseDepth);
 End Else If Peek In['^','$']Then Begin
  Root:=NewNode(Peek,0,0);Inc(ParsePosition);
 End Else Begin
  Characters:=[];
  If Peek='.'Then Begin Characters:=[#0..#255];Inc(ParsePosition);End
  Else If Peek='['Then Begin
   Inc(ParsePosition);Negated:=Peek='^';
   If Negated Then Inc(ParsePosition);
   If Peek=']'Then Begin Characters:=[']'];Inc(ParsePosition);End;
   Closed:=False;
   While Peek<>#0 Do Begin
    If Peek=']'Then Begin Closed:=True;Inc(ParsePosition);Break;End;
    If Copy(Pattern,ParsePosition,2)='[:'Then Begin
     Inc(ParsePosition,2);Start:=ParsePosition;
     While(Peek<>#0)And(Copy(Pattern,ParsePosition,2)<>':]')Do Inc(ParsePosition);
     Name:=Copy(Pattern,Start,ParsePosition-Start);
    ClassCharacters(Name,ClassChars);
    Characters:=Characters+ClassChars;
     If Peek=#0 Then Break;
     Inc(ParsePosition,2);Continue;
    End;
    FirstChar:=Peek;Inc(ParsePosition);
    If(Peek='-')And(ParsePosition<Length(Pattern))Then Begin
     If Pattern[ParsePosition+1]<>']'Then Begin
      Inc(ParsePosition);LastChar:=Peek;Inc(ParsePosition);
      If FirstChar>LastChar Then ParseFailed:=True
      Else For Index:=Ord(FirstChar)To Ord(LastChar)Do
       Characters:=Characters+[Chr(Index)];
      Continue;
     End;
    End;
    Characters:=Characters+[FirstChar];
   End;
   If Not Closed Then ParseFailed:=True;
   If IgnoreCase Then
    For Index:=Ord('a')To Ord('z')Do
     If(Chr(Index)In Characters)Or(Chr(Index-32)In Characters)Then
      Characters:=Characters+[Chr(Index),Chr(Index-32)];
   If Negated Then Characters:=[#0..#255]-Characters;
  End Else Begin
   FirstChar:=Peek;
   If FirstChar In['*','+','?','{',')']Then ParseFailed:=True;
   If FirstChar=#92 Then Begin
    Inc(ParsePosition);FirstChar:=Peek;
    If FirstChar=#0 Then ParseFailed:=True;
    If FirstChar='n'Then FirstChar:=#10
    Else If FirstChar='t'Then FirstChar:=#9;
   End;
   Characters:=[FirstChar];Inc(ParsePosition);
   If IgnoreCase Then Begin
    If FirstChar In['a'..'z']Then Characters:=Characters+[UpCase(FirstChar)]
    Else If FirstChar In['A'..'Z']Then
     Characters:=Characters+[Chr(Ord(FirstChar)+32)];
   End;
  End;
  Root:=NewNode('c',0,0);
  If Root<>0 Then Nodes[Root].Chars:=Characters;
 End;
 ParseAtom:=Root;
End;

Function ReadBound:Integer;
Var Value:Integer; HadDigit:Boolean;
Begin
 Value:=0;HadDigit:=False;
 While Peek In['0'..'9']Do Begin
  HadDigit:=True;
  If Value>255 Then ParseFailed:=True
  Else Value:=Value*10+Ord(Peek)-Ord('0');
  Inc(ParsePosition);
 End;
 If Not HadDigit Or(Value>255)Then ParseFailed:=True;
 ReadBound:=Value;
End;

Function ParsePiece:Integer;
Var Root,RepeatNode,LowBound,HighBound:Integer; OperatorChar:Char;
Begin
 Root:=ParseAtom;OperatorChar:=Peek;
 If OperatorChar In['*','+','?','{']Then Begin
  Inc(ParsePosition);LowBound:=0;HighBound:=255;
  If OperatorChar='+'Then LowBound:=1;
  If OperatorChar='?'Then HighBound:=1;
  If OperatorChar='{'Then Begin
   LowBound:=ReadBound;HighBound:=LowBound;
   If Peek=','Then Begin
    Inc(ParsePosition);
    If Peek='}'Then HighBound:=255 Else HighBound:=ReadBound;
   End;
   If Peek<>'}'Then ParseFailed:=True Else Inc(ParsePosition);
   If HighBound<LowBound Then ParseFailed:=True;
  End;
  RepeatNode:=NewNode('r',Root,0);
  If RepeatNode<>0 Then Begin
   Nodes[RepeatNode].Minimum:=LowBound;Nodes[RepeatNode].Maximum:=HighBound;
  End;
  Root:=RepeatNode;
 End;
 ParsePiece:=Root;
End;

Function ParseSequence:Integer;
Var Root,Piece:Integer;
Begin
 Root:=NewNode('e',0,0);
 While Not(Peek In[#0,'|',')'])And Not ParseFailed Do Begin
  Piece:=ParsePiece;Root:=NewNode('s',Root,Piece);
 End;
 ParseSequence:=Root;
End;

Function ParseExpression:Integer;
Var Root,Right:Integer;
Begin
 Root:=ParseSequence;
 While(Peek='|')And Not ParseFailed Do Begin
  Inc(ParsePosition);Right:=ParseSequence;Root:=NewNode('|',Root,Right);
 End;
 ParseExpression:=Root;
End;

Procedure Evaluate(Root:Integer; Const Starts:TPositions; Var Ends:TPositions);
Var Middle,Current,Next:TPositions; Position,Count:Integer;
Begin
 Ends:=[];
 If Root=0 Then Exit;
 Case Nodes[Root].Kind Of
  'e':Ends:=Starts;
  '^':If 0 In Starts Then Ends:=[0];
  '$':If TextLength In Starts Then Ends:=[TextLength];
  'c':For Position:=0 To TextLength-1 Do
   If Position In Starts Then
    If CurrentText[Position+1]In Nodes[Root].Chars Then Ends:=Ends+[Position+1];
  '|':Begin
   Evaluate(Nodes[Root].Left,Starts,Middle);
   Evaluate(Nodes[Root].Right,Starts,Ends);Ends:=Ends+Middle;
  End;
  's':Begin
   Evaluate(Nodes[Root].Left,Starts,Middle);
   Evaluate(Nodes[Root].Right,Middle,Ends);
  End;
  'r':Begin
   Current:=Starts;
   If Nodes[Root].Minimum=0 Then Ends:=Current;
   For Count:=1 To Nodes[Root].Maximum Do Begin
    Evaluate(Nodes[Root].Left,Current,Next);
    If Count>=Nodes[Root].Minimum Then Ends:=Ends+Next;
    If Next=[]Then Break;
    If Next=Current Then Begin
     Ends:=Ends+Next;Break;
    End;
    Current:=Next;
   End;
  End;
 End;
End;

Function WordCharacter(Value:Char):Boolean;
Begin
 WordCharacter:=Value In['A'..'Z','a'..'z','0'..'9','_'];
End;

Function LineMatches:Boolean;
Var Index,Start,Finish:Integer; Starts,Ends:TPositions;
Begin
 LineMatches:=False;TextLength:=Length(CurrentText);
 For Index:=1 To PatternCount Do
  For Start:=0 To TextLength Do Begin
   If WholeLine And(Start<>0)Then Break;
   If WholeWord And(Start>0)Then
    If WordCharacter(CurrentText[Start])Then Continue;
   Starts:=[Start];Evaluate(Roots[Index],Starts,Ends);
   For Finish:=Start To TextLength Do
    If Finish In Ends Then Begin
     If WholeLine And(Finish<>TextLength)Then Continue;
     If WholeWord And(Finish<TextLength)Then
      If WordCharacter(CurrentText[Finish+1])Then Continue;
     LineMatches:=True;Exit;
    End;
  End;
End;

Procedure AddPatterns(Const Value:TText);
Var Start,Index:Integer;
Begin
 Start:=1;
 For Index:=1 To Length(Value)+1 Do Begin
  If Index<=Length(Value)Then If Value[Index]<>#10 Then Continue;
  If PatternCount=MaxPatterns Then UsageError('Maximum 64 expressions');
  Inc(PatternCount);Patterns[PatternCount]:=Copy(Value,Start,Index-Start);
  Start:=Index+1;
 End;
End;

Function ReadLine(Var Source:Text; Var Value:TText; Var Bytes:LongInt):Boolean;
Var Character:Char; Code:Integer; TooLong,HadData:Boolean;
Begin
 Value:='';Bytes:=0;TooLong:=False;HadData:=False;
 While True Do Begin
  {$I-}
  If EOF(Source)Then Begin {$I+}Break;End;
  Read(Source,Character);
  {$I+}Code:=IOResult;
  If Code<>0 Then Begin Diagnostic('Erreur de lecture','Read error');Break;End;
  HadData:=True;Inc(Bytes);
  If Character=#10 Then Break;
  If Length(Value)=255 Then TooLong:=True Else Value:=Value+Character;
 End;
 If Value<>''Then
  If Value[Length(Value)]=#13 Then Delete(Value,Length(Value),1);
 If TooLong Then Begin
  Diagnostic('Ligne de plus de 255 octets: '+CurrentFile,
             'Line exceeds 255 bytes: '+CurrentFile);Value:='';
 End;
 ReadLine:=HadData And Not TooLong;
End;

Procedure LoadPatterns(Const Name:TText);
Var Source:Text; Value:TText; Bytes:LongInt; Code:Integer;
Begin
 Assign(Source,Name);FileMode:=0;
 {$I-}Reset(Source);{$I+}Code:=IOResult;
 If Code<>0 Then UsageError('Impossible de lire les expressions: '+Name);
 CurrentFile:=Name;
 While ReadLine(Source,Value,Bytes)Do AddPatterns(Value);
 {$I-}Close(Source);{$I+}Code:=IOResult;
 If Code<>0 Then UsageError('Erreur de fermeture: '+Name);
End;

Procedure PrintLine(Line:PLine; Selected:Boolean);
Var Separator:Char;
Begin
 If Line^.Number<=LastPrinted Then Exit;
 If(BeforeCount+AfterCount>0)And PrintedGroup And
   (Line^.Number>LastPrinted+1)Then WriteLn('--');
 Separator:='-';If Selected Then Separator:=':';
 If(FileCount>1)And Not NoFilePrefix Then Write(CurrentFile,Separator);
 If NumberPrefix Then Write(Line^.Number,Separator);
 If BytePrefix Then Write(Line^.Offset,Separator);
 WriteLn(Line^.Value);LastPrinted:=Line^.Number;PrintedGroup:=True;
End;

Procedure ProcessStream(Var Source:Text; Const Name:TText);
Var Bytes:LongInt; Line:TLine; Selected:Boolean; Index,Slot:Integer;
Begin
 CurrentFile:=Name;LineNumber:=0;ByteOffset:=0;SelectedCount:=0;
 LastPrinted:=0;AfterUntil:=0;HistoryCount:=0;HistoryNext:=0;PrintedGroup:=False;
 While ReadLine(Source,CurrentText,Bytes)Do Begin
  Inc(LineNumber);Line.Value:=CurrentText;Line.Number:=LineNumber;Line.Offset:=ByteOffset;
  Inc(ByteOffset,Bytes);Selected:=LineMatches Xor Invert;
  If Selected Then Begin Inc(SelectedCount);AnySelected:=True;End;
  If Selected And Quiet Then Exit;
  If Not(CountMode Or ListMatches Or ListNonMatches Or Quiet)Then Begin
   If Selected Then Begin
    For Index:=HistoryCount Downto 1 Do Begin
     Slot:=(HistoryNext-Index+MaxContext+1)Mod(MaxContext+1);
     PrintLine(History[Slot],False);
    End;
    PrintLine(@Line,True);AfterUntil:=LineNumber+AfterCount;
   End Else If LineNumber<=AfterUntil Then PrintLine(@Line,False);
  End;
  History[HistoryNext]^:=Line;
  HistoryNext:=(HistoryNext+1)Mod(MaxContext+1);
  If HistoryCount<BeforeCount Then Inc(HistoryCount);
 End;
 If Quiet Then Exit;
 If ListMatches Then Begin If SelectedCount>0 Then WriteLn(Name);End
 Else If ListNonMatches Then Begin If SelectedCount=0 Then WriteLn(Name);End
 Else If CountMode Then Begin
  If(FileCount>1)And Not NoFilePrefix Then Write(Name,':');
  WriteLn(SelectedCount);
 End;
End;

Procedure Help;
Begin
 If English Then Begin
  WriteLn('EGREP : Search extended regular expressions in files or standard input.');
  WriteLn('Usage: egrep [options] pattern [file ...]');
 End Else Begin
  WriteLn('EGREP : Cette commande permet de rechercher des expressions r'+#130+'guli'+#138+'res '+#130+'tendues.');
  WriteLn;
  WriteLn('Syntaxe : egrep [options] expression [fichier ...]');
  WriteLn;
  WriteLn('-b  Indique le prefixe octet');
  WriteLn('-c  Compte les lignes correspondant au motif');
  WriteLn('-h  N''affiche pas le nom des fichiers');
  WriteLn('-i  Ignore la casse');
  WriteLn('-l  Affiche uniquement les noms des fichiers contenant des correspondances');
  WriteLn('-L  Affiche uniquement les noms des fichiers ne contenant pas de correspondances');
  WriteLn('-n  Affiche le numero de ligne');
  WriteLn('-q  Mode silencieux');
  WriteLn('-s  Supprime les messages d''erreur');
  WriteLn('-v  Inverse la correspondance');
  WriteLn('-w  Correspondance sur des mots entiers');
  WriteLn('-x  Correspondance sur des lignes entieres');
  WriteLn('-V  Affiche la version');
  WriteLn('-e expression  -f fichier-expressions  -A num  -B num  -C num  -num');
  WriteLn('ERE: | () [] [[:digit:]] . ^ $ * + ? {m,n}; -- termine les options.');
  WriteLn('Limites: lignes/motifs 255 octets; contexte 64; repetition 255; pas de backreferences.');
 End;

End;

Function ContextNumber(Const Value:TText):Integer;
Var Number,Code:Integer;
Begin
 Val(Value,Number,Code);
 If Code<>0 Then UsageError('Contexte invalide');
 If(Number<0)Or(Number>MaxContext)Then UsageError('Contexte hors limites (0..64)');
 ContextNumber:=Number;
End;

Procedure Options;
Var Index,Position,Number:Integer; Argument,Value:TText; OptionChar:Char;
    EndOptions,NumericOption:Boolean;
Begin
 Index:=1;EndOptions:=False;
 While Index<=ParamCount Do Begin
  Argument:=ParamStr(Index);
  If Not EndOptions And(Argument='--')Then EndOptions:=True
  Else If Not EndOptions And((Argument='--help')Or(Argument='/?')Or
    (Argument='/h')Or(Argument='/H'))Then Begin Help;Halt(0);End
  Else If Not EndOptions And((Argument='--version')Or(Argument='-V'))Then Begin
   WriteLn('egrep (LINUX-0) 1.0');Halt(0);
  End Else If Not EndOptions And(Length(Argument)>1)And(Argument[1]='-')Then Begin
   NumericOption:=True;
   For Position:=2 To Length(Argument)Do
    If Not(Argument[Position]In['0'..'9'])Then NumericOption:=False;
   If NumericOption Then Begin
    Number:=ContextNumber(Copy(Argument,2,255));BeforeCount:=Number;AfterCount:=Number;
   End Else Begin
    Position:=2;
    While Position<=Length(Argument)Do Begin
     OptionChar:=Argument[Position];
     Case OptionChar Of
      'b':BytePrefix:=True;
      'c':CountMode:=True;
      'h':NoFilePrefix:=True;
      'i':IgnoreCase:=True;
      'l':ListMatches:=True;
      'L':ListNonMatches:=True;
      'n':NumberPrefix:=True;
      'q':Quiet:=True;
      's':Silent:=True;
      'v':Invert:=True;
      'w':WholeWord:=True;
      'x':WholeLine:=True;
      'e','f','A','B','C':Begin
       Value:=Copy(Argument,Position+1,255);
       If Value=''Then Begin
        Inc(Index);If Index>ParamCount Then UsageError('Argument d''option manquant');
        Value:=ParamStr(Index);
       End;
       If OptionChar In['e','f']Then Begin
        ExplicitPatterns:=True;
        If OptionChar='e'Then AddPatterns(Value)Else LoadPatterns(Value);
       End Else Begin
        Number:=ContextNumber(Value);
        If OptionChar In['A','C']Then AfterCount:=Number;
        If OptionChar In['B','C']Then BeforeCount:=Number;
       End;
       Position:=Length(Argument);
      End;
     Else UsageError('Option inconnue: '+Argument);End;
     Inc(Position);
    End;
   End;
  End Else If Not ExplicitPatterns Then Begin
   AddPatterns(Argument);ExplicitPatterns:=True;
  End Else Begin
   If FileCount=MaxFiles Then UsageError('Maximum 64 fichiers');
   Inc(FileCount);Files[FileCount]:=Argument;
  End;
  Inc(Index);
 End;
 If Not ExplicitPatterns Then UsageError('Expression requise');
End;

Var Index,Code:Integer; Source:Text;
Begin
 English:=Copy(GetEnv('LANGUAGE'),1,2)='EN';
 NodeCount:=0;PatternCount:=0;FileCount:=0;BeforeCount:=0;AfterCount:=0;
 IgnoreCase:=False;Invert:=False;WholeWord:=False;WholeLine:=False;
 CountMode:=False;ListMatches:=False;ListNonMatches:=False;Quiet:=False;
 Silent:=False;NoFilePrefix:=False;NumberPrefix:=False;BytePrefix:=False;
 HadError:=False;AnySelected:=False;ExplicitPatterns:=False;
 Options;
 For Index:=1 To PatternCount Do Begin
  Pattern:=Patterns[Index];ParsePosition:=1;ParseDepth:=0;ParseFailed:=False;
  Roots[Index]:=ParseExpression;
  If ParseFailed Or(Peek<>#0)Then UsageError('Expression invalide ou trop complexe: '+Pattern);
 End;
 For Index:=0 To MaxContext Do New(History[Index]);
 If FileCount=0 Then ProcessStream(Input,'(standard input)')
 Else For Index:=1 To FileCount Do Begin
  If Files[Index]='-'Then ProcessStream(Input,'(standard input)')
  Else Begin
   Assign(Source,Files[Index]);FileMode:=0;
   {$I-}Reset(Source);{$I+}Code:=IOResult;
   If Code<>0 Then Diagnostic('Impossible de lire '+Files[Index],'Cannot read '+Files[Index])
   Else Begin
    ProcessStream(Source,Files[Index]);
    {$I-}Close(Source);{$I+}Code:=IOResult;
    If Code<>0 Then Diagnostic('Erreur de fermeture','Error closing input');
   End;
  End;
  If Quiet And AnySelected Then Break;
 End;
 For Index:=0 To MaxContext Do Dispose(History[Index]);
 If Quiet And AnySelected Then Halt(0);
 If HadError Then Halt(2);
 If Not AnySelected Then Halt(1);
END.