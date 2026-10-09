{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ED(Input,Output);

Uses DOS;

Const
  MaxLineLength=255;
  MaxFileName=127;

Type
  PLine=^TLineNode;
  TLineNode=Record
    Text:String[MaxLineLength];
    Previous,Next:PLine;
  End;

Var
  FirstLine,LastLine,CurrentLine:PLine;
  CurrentLineNumber,LineCount:LongInt;
  FileName,Prompt,CommandLine,LanguageCode,Argument:String;
  SuppressDiagnostics,Changed,QuitRequested,QuitWarned:Boolean;
  StandardInputMode,EncryptMode:Boolean;
  ArgumentIndex:Integer;
  LastStatus:Integer;

Function TrimText(Value:String):String;
Begin
  While(Length(Value)>0)and(Value[1]in[' ',#9])Do Delete(Value,1,1);
  While(Length(Value)>0)and(Value[Length(Value)]in[' ',#9])Do
    Delete(Value,Length(Value),1);
  TrimText:=Value;
End;

Function NodeAt(Number:LongInt):PLine;
Var
  Node:PLine;
  Index:LongInt;
Begin
  NodeAt:=Nil;
  If(Number<1)or(Number>LineCount)Then Exit;
  Node:=FirstLine;
  For Index:=1 to Number-1 Do Node:=Node^.Next;
  NodeAt:=Node;
End;

Procedure InsertAfter(PreviousNode:PLine; Const TextLine:String);
Var
  NewNode:PLine;
Begin
  New(NewNode);
  NewNode^.Text:=TextLine;
  If PreviousNode=Nil Then Begin
    NewNode^.Previous:=Nil;
    NewNode^.Next:=FirstLine;
    If FirstLine<>Nil Then FirstLine^.Previous:=NewNode
    Else LastLine:=NewNode;
    FirstLine:=NewNode;
  End Else Begin
    NewNode^.Previous:=PreviousNode;
    NewNode^.Next:=PreviousNode^.Next;
    If PreviousNode^.Next<>Nil Then PreviousNode^.Next^.Previous:=NewNode
    Else LastLine:=NewNode;
    PreviousNode^.Next:=NewNode;
  End;
  Inc(LineCount);
  CurrentLine:=NewNode;
  CurrentLineNumber:=0;
  If NewNode^.Previous<>Nil Then Begin
    CurrentLine:=FirstLine;
    CurrentLineNumber:=1;
    While CurrentLine<>NewNode Do Begin CurrentLine:=CurrentLine^.Next;Inc(CurrentLineNumber);End;
  End Else CurrentLineNumber:=1;
  Changed:=True;
End;

Procedure DeleteLine(Number:LongInt);
Var
  Node:PLine;
Begin
  Node:=NodeAt(Number);
  If Node=Nil Then Exit;
  If Node^.Previous<>Nil Then Node^.Previous^.Next:=Node^.Next
  Else FirstLine:=Node^.Next;
  If Node^.Next<>Nil Then Node^.Next^.Previous:=Node^.Previous
  Else LastLine:=Node^.Previous;
  If Node^.Next<>Nil Then CurrentLine:=Node^.Next
  Else CurrentLine:=Node^.Previous;
  Dispose(Node);
  Dec(LineCount);
  If Number>LineCount Then CurrentLineNumber:=LineCount
  Else CurrentLineNumber:=Number;
  Changed:=True;
End;

Procedure ClearBuffer;
Var
  Node,NextNode:PLine;
Begin
  Node:=FirstLine;
  While Node<>Nil Do Begin
    NextNode:=Node^.Next;
    Dispose(Node);
    Node:=NextNode;
  End;
  FirstLine:=Nil;LastLine:=Nil;CurrentLine:=Nil;
  LineCount:=0;CurrentLineNumber:=0;Changed:=False;
End;

Procedure EditorError(Const MessageText:String);
Begin
  If Not SuppressDiagnostics Then WriteLn('? ',MessageText);
  LastStatus:=1;
End;

Procedure LoadFile(Const Name:String; InsertAfterLine:LongInt; ReplaceBuffer:Boolean);
Var
  Source:Text;
  SourceLine:String;
  InsertNode:PLine;
  NumberRead:LongInt;
Begin
  Assign(Source,Name);
  {$I-}Reset(Source);{$I+}
  If IOResult<>0 Then Begin EditorError('impossible de lire '+Name);Exit;End;
  If ReplaceBuffer Then ClearBuffer;
  InsertNode:=NodeAt(InsertAfterLine);
  NumberRead:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,SourceLine);
    InsertAfter(InsertNode,SourceLine);
    InsertNode:=CurrentLine;
    Inc(NumberRead);
  End;
  Close(Source);
  If ReplaceBuffer Then Begin
    FileName:=Name;
    Changed:=False;
  End Else If NumberRead>0 Then Changed:=True;
  If Not SuppressDiagnostics Then WriteLn(NumberRead,'');
  LastStatus:=0;
End;

Procedure WriteFile(Const Name:String; FirstNumber,LastNumber:LongInt);
Var
  Destination:Text;
  Node:PLine;
  Index:LongInt;
Begin
  If(FirstNumber<1)or(LastNumber>LineCount)or(FirstNumber>LastNumber+1)Then Begin
    EditorError('adresse hors limites');
    Exit;
  End;
  Assign(Destination,Name);
  {$I-}Rewrite(Destination);{$I+}
  If IOResult<>0 Then Begin EditorError('impossible d''ecrire '+Name);Exit;End;
  Node:=NodeAt(FirstNumber);
  For Index:=FirstNumber to LastNumber Do Begin
    If Node=Nil Then Break;
    WriteLn(Destination,Node^.Text);
    Node:=Node^.Next;
  End;
  Close(Destination);
  FileName:=Name;
  If(FirstNumber=1)and(LastNumber=LineCount)Then Changed:=False;
  If Not SuppressDiagnostics Then WriteLn(LastNumber-FirstNumber+1,'');
  LastStatus:=0;
End;

Function ParseAddress(Const TextLine:String; Var Position:Integer;
                      DefaultValue:LongInt):LongInt;
Var
  Start,Value:LongInt;
  ErrorCode:Integer;
  SearchText:String;
  Node:PLine;
Begin
  While(Position<=Length(TextLine))and(TextLine[Position]=' ')Do Inc(Position);
  ParseAddress:=DefaultValue;
  If Position>Length(TextLine)Then Exit;
  If TextLine[Position]='.'Then Begin
    ParseAddress:=CurrentLineNumber;
    Inc(Position);
  End Else If TextLine[Position]='$'Then Begin
    ParseAddress:=LineCount;
    Inc(Position);
  End Else If TextLine[Position]in['0'..'9']Then Begin
    Start:=Position;
    While(Position<=Length(TextLine))and(TextLine[Position]in['0'..'9'])Do Inc(Position);
    Val(Copy(TextLine,Start,Position-Start),Value,ErrorCode);
    If ErrorCode=0 Then ParseAddress:=Value;
  End Else If TextLine[Position]='/'Then Begin
    Inc(Position);Start:=Position;
    While(Position<=Length(TextLine))and(TextLine[Position]<>'/')Do Inc(Position);
    SearchText:=Copy(TextLine,Start,Position-Start);
    If Position<=Length(TextLine)Then Inc(Position);
    Node:=CurrentLine;
    If Node=Nil Then Node:=FirstLine Else Node:=Node^.Next;
    Value:=CurrentLineNumber+1;
    While Node<>Nil Do Begin
      If Pos(SearchText,Node^.Text)>0 Then Begin ParseAddress:=Value;Exit;End;
      Node:=Node^.Next;Inc(Value);
    End;
  End;
End;

Function ReadDelimited(Const TextLine:String; Var Position:Integer;
                       Delimiter:Char):String;
Var
  Value:String;
Begin
  ReadDelimited:='';
  Value:='';
  While Position<=Length(TextLine)Do Begin
    If TextLine[Position]=Delimiter Then Begin Inc(Position);Break;End;
    If(TextLine[Position]=#92)and(Position<Length(TextLine))Then Inc(Position);
    Value:=Value+TextLine[Position];
    Inc(Position);
  End;
  ReadDelimited:=Value;
End;

Function ReplaceText(Const Source,OldText,NewText:String; Global:Boolean):String;
Var
  Position:Integer;
  ResultValue:String;
Begin
  ResultValue:='';Position:=1;
  If OldText=''Then Begin ReplaceText:=Source;Exit;End;
  While Position<=Length(Source)Do Begin
    If Copy(Source,Position,Length(OldText))=OldText Then Begin
      ResultValue:=ResultValue+NewText;
      Inc(Position,Length(OldText));
      If Not Global Then Begin
        ReplaceText:=ResultValue+Copy(Source,Position,255);
        Exit;
      End;
    End Else Begin
      ResultValue:=ResultValue+Source[Position];
      Inc(Position);
    End;
  End;
  ReplaceText:=ResultValue;
End;

Procedure PrintRange(FirstNumber,LastNumber:LongInt; Numbered:Boolean);
Var
  Node:PLine;
  Index:LongInt;
Begin
  If(FirstNumber<1)or(LastNumber>LineCount)or(FirstNumber>LastNumber)Then Begin
    EditorError('adresse hors limites');
    Exit;
  End;
  Node:=NodeAt(FirstNumber);
  For Index:=FirstNumber to LastNumber Do Begin
    If Numbered Then Write(Index,#9);
    WriteLn(Node^.Text);
    Node:=Node^.Next;
  End;
  CurrentLine:=NodeAt(LastNumber);
  CurrentLineNumber:=LastNumber;
  LastStatus:=0;
End;

Procedure InsertInput(AfterNumber:LongInt);
Var
  InsertNode:PLine;
  InputLine:String;
Begin
  If(AfterNumber<0)or(AfterNumber>LineCount)Then Begin
    EditorError('adresse hors limites');
    Exit;
  End;
  InsertNode:=NodeAt(AfterNumber);
  Repeat
    ReadLn(Input,InputLine);
    If InputLine='.'Then Break;
    New(CurrentLine);
    CurrentLine^.Text:=InputLine;
    CurrentLine^.Previous:=InsertNode;
    If InsertNode<>Nil Then CurrentLine^.Next:=InsertNode^.Next
    Else CurrentLine^.Next:=FirstLine;
    If CurrentLine^.Next<>Nil Then CurrentLine^.Next^.Previous:=CurrentLine
    Else LastLine:=CurrentLine;
    If InsertNode<>Nil Then InsertNode^.Next:=CurrentLine
    Else FirstLine:=CurrentLine;
    InsertNode:=CurrentLine;
    Inc(LineCount);
    CurrentLineNumber:=AfterNumber+1;
    Inc(AfterNumber);
    Changed:=True;
  Until False;
  LastStatus:=0;
End;

Procedure PrintListLine(Number:LongInt; Const Value:String);
Var
  Index:Integer;
Begin
  Write(Number:6,#9);
  For Index:=1 to Length(Value)Do Begin
    Case Value[Index]Of
      #9:Write('\t');
      #13:Write('\r');
      #92:Write('\\');
    Else Write(Value[Index]);
    End;
  End;
  WriteLn('$');
End;

Procedure ExecuteCommand(Const CommandText:String);
Var
  Position:Integer;
  FirstNumber,LastNumber,AddressValue:LongInt;
  Command:Char;
  Delimiter:Char;
  CommandArgument,Pattern,Replacement:String;
  Node:PLine;
  Index:LongInt;
  GlobalReplace:Boolean;
Begin
  Position:=1;
  FirstNumber:=ParseAddress(CommandText,Position,CurrentLineNumber);
  LastNumber:=FirstNumber;
  While(Position<=Length(CommandText))and(CommandText[Position]=' ')Do Inc(Position);
  If(Position<=Length(CommandText))and(CommandText[Position]=',')Then Begin
    Inc(Position);
    LastNumber:=ParseAddress(CommandText,Position,LineCount);
  End;
  While(Position<=Length(CommandText))and(CommandText[Position]=' ')Do Inc(Position);
  If Position>Length(CommandText)Then Begin
    If CurrentLineNumber>0 Then PrintRange(FirstNumber,LastNumber,False)
    Else EditorError('commande manquante');
    Exit;
  End;
  Command:=CommandText[Position];
  Inc(Position);
  While(Position<=Length(CommandText))and(CommandText[Position]=' ')Do Inc(Position);
  CommandArgument:=Copy(CommandText,Position,255);
  Case Command Of
    'a':InsertInput(FirstNumber);
    'i':InsertInput(FirstNumber-1);
    'c':Begin
      If(FirstNumber<1)or(LastNumber>LineCount)or(FirstNumber>LastNumber)Then
        EditorError('adresse hors limites')
      Else Begin
        For Index:=LastNumber downto FirstNumber Do DeleteLine(Index);
        InsertInput(FirstNumber-1);
      End;
    End;
    'd':Begin
      If(FirstNumber<1)or(LastNumber>LineCount)or(FirstNumber>LastNumber)Then
        EditorError('adresse hors limites')
      Else For Index:=LastNumber downto FirstNumber Do DeleteLine(Index);
    End;
    'p':PrintRange(FirstNumber,LastNumber,False);
    'n':PrintRange(FirstNumber,LastNumber,True);
    'l':Begin
      If(FirstNumber<1)or(LastNumber>LineCount)or(FirstNumber>LastNumber)Then
        EditorError('adresse hors limites')
      Else Begin
        Node:=NodeAt(FirstNumber);
        For Index:=FirstNumber to LastNumber Do Begin
          PrintListLine(Index,Node^.Text);
          Node:=Node^.Next;
        End;
      End;
    End;
    '=':WriteLn(LastNumber);
    'w':Begin
      CommandArgument:=TrimText(CommandArgument);
      If CommandArgument=''Then CommandArgument:=FileName;
      If CommandArgument=''Then EditorError('nom de fichier requis')
      Else WriteFile(CommandArgument,1,LineCount);
    End;
    'q':Begin
      If Changed and Not QuitWarned Then Begin
        WriteLn('?');
        QuitWarned:=True;
      End Else QuitRequested:=True;
    End;
    'Q':QuitRequested:=True;
    'e':Begin
      If Changed Then EditorError('modifications non enregistrees (utilisez Q pour forcer)')
      Else Begin
        CommandArgument:=TrimText(CommandArgument);
        If CommandArgument=''Then EditorError('nom de fichier requis')
        Else LoadFile(CommandArgument,0,True);
      End;
    End;
    'r':Begin
      CommandArgument:=TrimText(CommandArgument);
      If CommandArgument=''Then EditorError('nom de fichier requis')
      Else Begin
        AddressValue:=FirstNumber;
        If AddressValue<0 Then AddressValue:=0;
        LoadFile(CommandArgument,AddressValue,False);
      End;
    End;
    's':Begin
      If(FirstNumber<1)or(LastNumber>LineCount)Then EditorError('adresse hors limites')
      Else Begin
        If Position>Length(CommandText)Then Delimiter:='/'
        Else Delimiter:=CommandText[Position];
        Inc(Position);
        Pattern:=ReadDelimited(CommandText,Position,Delimiter);
        Replacement:=ReadDelimited(CommandText,Position,Delimiter);
        GlobalReplace:=(Pos('g',Copy(CommandText,Position,255))>0);
        Node:=NodeAt(FirstNumber);
        For Index:=FirstNumber to LastNumber Do Begin
          Node^.Text:=ReplaceText(Node^.Text,Pattern,Replacement,GlobalReplace);
          Node:=Node^.Next;
        End;
        Changed:=True;LastStatus:=0;
      End;
    End;
  Else EditorError('commande inconnue');
  End;
End;

Procedure ReadCommandLoop;
Var
  CommandText:String;
Begin
  While Not QuitRequested Do Begin
    If Prompt<>''Then Write(Prompt);
    If EOF(Input)Then Break;
    ReadLn(Input,CommandText);
    ExecuteCommand(CommandText);
  End;
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('ED : Line-oriented text editor.');
    WriteLn('Syntax: ed [-C] [-p string] [-s] [-x] [filename]');
    WriteLn('Commands: a append, i insert, c change, d delete, p print, n numbered, l list');
    WriteLn('          s/pattern/replacement/[g], w [file], e file, r file, q, Q');
    WriteLn('Input for a/i/c ends with a single period on a line.');
  End Else Begin
    WriteLn('ED : Cette commande permet de lancer l'''+#130+'diteur de texte ligne par ligne.');
    WriteLn;
    WriteLn('Syntaxe : ed [-C] [-p chaine] [-s] [-x] [fichier]');
    WriteLn;
    WriteLn('Commandes : a ajouter, i inserer, c changer, d supprimer, p afficher, n numeroter, l lister');
    WriteLn('            s/motif/remplacement/[g], w [fichier], e fichier, r fichier, q, Q');
    WriteLn('La saisie de a/i/c se termine par un point seul sur une ligne.');
  End;
End;

BEGIN
  FileName:='';Prompt:='';SuppressDiagnostics:=False;EncryptMode:=False;
  Changed:=False;QuitRequested:=False;QuitWarned:=False;
  FirstLine:=Nil;LastLine:=Nil;CurrentLine:=Nil;LineCount:=0;CurrentLineNumber:=0;
  LanguageCode:=GetEnv('LANGUAGE');
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('ed (LINUX-0) 1.0');Halt(0);End
    Else If(Argument='-s')Then SuppressDiagnostics:=True
    Else If(Argument='-C')Then Begin End
    Else If(Argument='-x')Then EncryptMode:=True
    Else If(Argument='-p')Then Begin
      Inc(ArgumentIndex);If ArgumentIndex>ParamCount Then Begin WriteLn('ed: -p attend une invite');Halt(2);End;
      Prompt:=ParamStr(ArgumentIndex);
    End Else If(Argument='-')Then Begin End
    Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin WriteLn('ed: option inconnue ',Argument);Halt(2);End
    Else If FileName=''Then FileName:=Argument
    Else Begin WriteLn('ed: un seul fichier est accepte');Halt(2);End;
    Inc(ArgumentIndex);
  End;
  If FileName<>''Then LoadFile(FileName,0,True);
  ReadCommandLoop;
  If EncryptMode Then WriteLn('ed: chiffrement interactif indisponible; fichier conserve en clair');
  ClearBuffer;
END.