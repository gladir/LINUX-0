{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program RED(Input,Output);

Uses DOS;

Const
  MaxLineLength=255;
  MaxFileName=127;

Type
  TLineText=String[MaxLineLength];
  TFileName=String[MaxFileName];
  PLine=^TLine;
  TLine=Record
    Text:TLineText;
    Previous,Next:PLine;
  End;

Var
  FirstLine,LastLine,CurrentLine:PLine;
  SearchInfo:SearchRec;
  CurrentLineNumber,LineCount:LongInt;
  FileName,Prompt,LanguageCode:TFileName;
  SuppressDiagnostics,Changed,QuitRequested,QuitWarned:Boolean;
  ArgumentIndex:Integer;
  LastStatus:Integer;
  InitialFileExists:Boolean;

Function TrimText(Value:TLineText):TLineText;
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

Procedure InsertAfter(PreviousNode:PLine; Const Value:TLineText;
                      Var NewNode:PLine);
Begin
  New(NewNode);
  NewNode^.Text:=Value;
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
  Dispose(Node);
  Dec(LineCount);
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
  FirstLine:=Nil;
  LastLine:=Nil;
  CurrentLine:=Nil;
  CurrentLineNumber:=0;
  LineCount:=0;
  Changed:=False;
End;

Procedure EditorError(Const MessageText:TLineText);
Begin
  If Not SuppressDiagnostics Then WriteLn('? ',MessageText);
  LastStatus:=1;
End;

Function RestrictedName(Const Name:TFileName):Boolean;
Var
  Index:Integer;
Begin
  RestrictedName:=False;
  If(Name='')or(Name='.')or(Name='..')Then Begin
    RestrictedName:=True;
    Exit;
  End;
  For Index:=1 to Length(Name)Do
    If(Name[Index]='/')or(Name[Index]=#92)or(Name[Index]=':')or
      (Name[Index]='*')or(Name[Index]='?')Then Begin
      RestrictedName:=True;
      Exit;
    End;
End;

Procedure LoadFile(Const Name:TFileName; AfterLine:LongInt;
                   ReplaceBuffer:Boolean);
Var
  Source:Text;
  SourceLine:TLineText;
  InsertNode,NewNode:PLine;
  ErrorCode:Integer;
Begin
  If RestrictedName(Name)Then Begin
    EditorError('nom de fichier interdit en mode restreint');
    Exit;
  End;
  Assign(Source,Name);
  {$I-}Reset(Source);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    EditorError('impossible de lire '+Name);
    Exit;
  End;
  If ReplaceBuffer Then ClearBuffer;
  InsertNode:=NodeAt(AfterLine);
  While Not EOF(Source)Do Begin
    ReadLn(Source,SourceLine);
    InsertAfter(InsertNode,SourceLine,NewNode);
    InsertNode:=NewNode;
  End;
  Close(Source);
  If ReplaceBuffer Then Begin
    FileName:=Name;
    Changed:=False;
  End Else Changed:=True;
  If Not SuppressDiagnostics Then WriteLn(LineCount,'');
  LastStatus:=0;
End;

Procedure WriteFile(Const Name:TFileName);
Var
  Destination:Text;
  Node:PLine;
  ErrorCode:Integer;
  Written:LongInt;
Begin
  If RestrictedName(Name)Then Begin
    EditorError('nom de fichier interdit en mode restreint');
    Exit;
  End;
  Assign(Destination,Name);
  {$I-}Rewrite(Destination);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    EditorError('impossible d''ecrire '+Name);
    Exit;
  End;
  Node:=FirstLine;
  While Node<>Nil Do Begin
    WriteLn(Destination,Node^.Text);
    Node:=Node^.Next;
  End;
  {$I-}Close(Destination);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    EditorError('erreur durant l''ecriture de '+Name);
    Exit;
  End;
  FileName:=Name;
  Changed:=False;
  Written:=LineCount;
  If Not SuppressDiagnostics Then WriteLn(Written,'');
  LastStatus:=0;
End;

Function ParseAddress(Const CommandText:TLineText; Var Position:Integer;
                      DefaultValue:LongInt):LongInt;
Var
  StartPosition,ParsedValue:Integer;
  ErrorCode:Integer;
  SearchText:TLineText;
  Node:PLine;
  Number:LongInt;
Begin
  While(Position<=Length(CommandText))and(CommandText[Position]=' ')Do Inc(Position);
  ParseAddress:=DefaultValue;
  If Position>Length(CommandText)Then Exit;
  If CommandText[Position]='.'Then Begin
    ParseAddress:=CurrentLineNumber;
    Inc(Position);
  End Else If CommandText[Position]='$'Then Begin
    ParseAddress:=LineCount;
    Inc(Position);
  End Else If CommandText[Position]in['0'..'9']Then Begin
    StartPosition:=Position;
    While(Position<=Length(CommandText))and
          (CommandText[Position]in['0'..'9'])Do Inc(Position);
    Val(Copy(CommandText,StartPosition,Position-StartPosition),ParsedValue,ErrorCode);
    If ErrorCode=0 Then ParseAddress:=ParsedValue;
  End Else If CommandText[Position]='/'Then Begin
    Inc(Position);
    StartPosition:=Position;
    While(Position<=Length(CommandText))and(CommandText[Position]<>'/')Do Inc(Position);
    SearchText:=Copy(CommandText,StartPosition,Position-StartPosition);
    If Position<=Length(CommandText)Then Inc(Position);
    Node:=CurrentLine;
    If Node=Nil Then Node:=FirstLine Else Node:=Node^.Next;
    Number:=CurrentLineNumber+1;
    While Node<>Nil Do Begin
      If Pos(SearchText,Node^.Text)>0 Then Begin ParseAddress:=Number;Exit;End;
      Node:=Node^.Next;
      Inc(Number);
    End;
  End;
End;

Function ReadDelimited(Const CommandText:TLineText; Var Position:Integer;
                       Delimiter:Char):TLineText;
Var
  Value:TLineText;
Begin
  Value:='';
  While Position<=Length(CommandText)Do Begin
    If CommandText[Position]=Delimiter Then Begin
      Inc(Position);
      Break;
    End;
    If(CommandText[Position]=#92)and(Position<Length(CommandText))Then Inc(Position);
    Value:=Value+CommandText[Position];
    Inc(Position);
  End;
  ReadDelimited:=Value;
End;

Function ReplaceText(Const Source,OldText,NewText:TLineText;
                     Global:Boolean):TLineText;
Var
  Position:Integer;
  ResultText:TLineText;
Begin
  ResultText:='';
  Position:=1;
  If OldText=''Then Begin ReplaceText:=Source;Exit;End;
  While Position<=Length(Source)Do Begin
    If Copy(Source,Position,Length(OldText))=OldText Then Begin
      ResultText:=ResultText+NewText;
      Inc(Position,Length(OldText));
      If Not Global Then Begin
        ReplaceText:=ResultText+Copy(Source,Position,MaxLineLength);
        Exit;
      End;
    End Else Begin
      ResultText:=ResultText+Source[Position];
      Inc(Position);
    End;
  End;
  ReplaceText:=ResultText;
End;

Procedure PrintRange(FirstNumber,LastNumber:LongInt; Numbered:Boolean);
Var
  Node:PLine;
  Index:LongInt;
Begin
  If(FirstNumber<1)or(LastNumber>LineCount)or
    (FirstNumber>LastNumber)Then Begin
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
  InsertNode,NewNode:PLine;
  InputLine:TLineText;
Begin
  If(AfterNumber<0)or(AfterNumber>LineCount)Then Begin
    EditorError('adresse hors limites');
    Exit;
  End;
  InsertNode:=NodeAt(AfterNumber);
  Repeat
    If EOF(Input)Then Begin
      EditorError('fin de l''entree avant le point final');
      Exit;
    End;
    ReadLn(Input,InputLine);
    If InputLine='.'Then Break;
    InsertAfter(InsertNode,InputLine,NewNode);
    InsertNode:=NewNode;
    Inc(AfterNumber);
  Until False;
  CurrentLine:=InsertNode;
  CurrentLineNumber:=AfterNumber;
  Changed:=True;
  LastStatus:=0;
End;

Procedure ExecuteCommand(Const CommandText:TLineText);
Var
  Position,CommaPosition:Integer;
  FirstNumber,LastNumber,Index:LongInt;
  Command,Delimiter:Char;
  Argument,Pattern,Replacement:TLineText;
  Node:PLine;
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
  Argument:=Copy(CommandText,Position,MaxLineLength);
  Case Command Of
    'a':InsertInput(FirstNumber);
    'i':InsertInput(FirstNumber-1);
    'c':Begin
      If(FirstNumber<1)or(LastNumber>LineCount)or
        (FirstNumber>LastNumber)Then EditorError('adresse hors limites')
      Else Begin
        For Index:=LastNumber downto FirstNumber Do DeleteLine(Index);
        InsertInput(FirstNumber-1);
      End;
    End;
    'd':Begin
      If(FirstNumber<1)or(LastNumber>LineCount)or
        (FirstNumber>LastNumber)Then EditorError('adresse hors limites')
      Else Begin
        For Index:=LastNumber downto FirstNumber Do DeleteLine(Index);
        If FirstNumber>LineCount Then FirstNumber:=LineCount;
        CurrentLine:=NodeAt(FirstNumber);
        CurrentLineNumber:=FirstNumber;
        Changed:=True;
      End;
    End;
    'p':PrintRange(FirstNumber,LastNumber,False);
    'n':PrintRange(FirstNumber,LastNumber,True);
    '=':WriteLn(LastNumber);
    'w':Begin
      Argument:=TrimText(Argument);
      If Argument=''Then Argument:=FileName;
      If Argument=''Then EditorError('nom de fichier requis')
      Else WriteFile(Argument);
    End;
    'r':Begin
      Argument:=TrimText(Argument);
      If Argument=''Then EditorError('nom de fichier requis')
      Else LoadFile(Argument,FirstNumber,False);
    End;
    'e':Begin
      Argument:=TrimText(Argument);
      If Changed Then EditorError('modifications non enregistrees')
      Else If Argument=''Then EditorError('nom de fichier requis')
      Else Begin
        LoadFile(Argument,0,True);
        CurrentLine:=FirstLine;
        CurrentLineNumber:=1;
      End;
    End;
    'q':Begin
      If Changed and Not QuitWarned Then Begin
        WriteLn('?');
        QuitWarned:=True;
      End Else QuitRequested:=True;
    End;
    'Q':QuitRequested:=True;
    's':Begin
      If(FirstNumber<1)or(LastNumber>LineCount)Then EditorError('adresse hors limites')
      Else Begin
        If Position>Length(CommandText)Then Delimiter:='/'
        Else Delimiter:=CommandText[Position];
        Inc(Position);
        Pattern:=ReadDelimited(CommandText,Position,Delimiter);
        Replacement:=ReadDelimited(CommandText,Position,Delimiter);
        GlobalReplace:=Pos('g',Copy(CommandText,Position,MaxLineLength))>0;
        Node:=NodeAt(FirstNumber);
        For Index:=FirstNumber to LastNumber Do Begin
          Node^.Text:=ReplaceText(Node^.Text,Pattern,Replacement,GlobalReplace);
          Node:=Node^.Next;
        End;
        Changed:=True;
        LastStatus:=0;
      End;
    End;
  Else EditorError('commande inconnue');
  End;
End;

Procedure ReadCommandLoop;
Var
  CommandText:TLineText;
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
    WriteLn('RED : Restricted line-oriented text editor.');
    WriteLn('Syntax: red [-C] [-p string] [-s] [-] [-x] filename');
    WriteLn('Commands: a append, i insert, c change, d delete, p print, n number');
    WriteLn('          s/pattern/replacement/[g], w [file], e file, r file, q, Q');
    WriteLn('Input for a/i/c ends with a single period on a line.');
    WriteLn('File names are restricted to the current directory.');
  End Else Begin
    WriteLn('RED : Cette commande permet de lancer l'''+#130+'diteur de texte ligne par ligne restreint.');
    WriteLn;
    WriteLn('Syntaxe : red [-C] [-p chaine] [-s] [-] [-x] fichier');
    WriteLn;
    WriteLn('Commandes : a ajouter, i inserer, c changer, d supprimer, p afficher');
    WriteLn('            s/motif/remplacement/[g], w [fichier], e fichier, r fichier, q, Q');
    WriteLn('La saisie de a/i/c se termine par un point seul sur une ligne.');
    WriteLn('Les noms de fichiers sont limites au repertoire courant.');
  End;
End;

Procedure ParseOptions;
Var
  Argument:TFileName;
  FileNameSeen:Boolean;
Begin
  ArgumentIndex:=1;
  FileNameSeen:=False;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='-h')or(Argument='--help')or(Argument='/?')Then Begin
      PrintHelp;
      Halt(0);
    End Else If Argument='-s'Then SuppressDiagnostics:=True
    Else If Argument='-'Then Begin End
    Else If(Argument='-C')or(Argument='-x')Then Begin
      If Copy(LanguageCode,1,2)='EN'Then
        WriteLn('red: encryption is not supported; no file was changed')
      Else WriteLn('red : le chiffrement n''est pas pris en charge; aucun fichier modifie');
      Halt(2);
    End Else If Argument='-p'Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then Begin
        WriteLn('red: -p attend une invite');
        Halt(2);
      End;
      Prompt:=ParamStr(ArgumentIndex);
    End Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      WriteLn('red: option inconnue ',Argument);
      Halt(2);
    End Else If Not FileNameSeen Then Begin
      FileName:=Argument;
      FileNameSeen:=True;
    End Else Begin
      WriteLn('red: un seul fichier est accepte');
      Halt(2);
    End;
    Inc(ArgumentIndex);
  End;
  If Not FileNameSeen Then Begin
    If Copy(LanguageCode,1,2)='EN'Then WriteLn('Usage: red [-C] [-p string] [-s] [-] [-x] filename')
    Else WriteLn('Syntaxe : red [-C] [-p chaine] [-s] [-] [-x] fichier');
    Halt(2);
  End;
  If RestrictedName(FileName)Then Begin
    WriteLn('red: nom de fichier interdit en mode restreint');
    Halt(2);
  End;
End;

Begin
  FirstLine:=Nil;
  LastLine:=Nil;
  CurrentLine:=Nil;
  LineCount:=0;
  CurrentLineNumber:=0;
  FileName:='';
  Prompt:='';
  LanguageCode:=GetEnv('LANGUAGE');
  SuppressDiagnostics:=False;
  Changed:=False;
  QuitRequested:=False;
  QuitWarned:=False;
  LastStatus:=0;
  ParseOptions;
  FindFirst(FileName,AnyFile,SearchInfo);
  InitialFileExists:=DosError=0;
  {$IFDEF FPC}FindClose(SearchInfo);{$ENDIF}
  If InitialFileExists Then Begin
    If(SearchInfo.Attr and Directory)<>0 Then Begin
      WriteLn('red: le nom indique est un repertoire');
      Halt(2);
    End;
    LoadFile(FileName,0,True);
    If LastStatus<>0 Then Halt(1);
    CurrentLine:=FirstLine;
    If LineCount>0 Then CurrentLineNumber:=1;
  End;
  ReadCommandLoop;
  ClearBuffer;
End.
