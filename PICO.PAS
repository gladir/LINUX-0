{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program PICO;

Uses DOS,CRT;

Const
  ScreenColumns=80;
  ScreenRows=25;
  FirstTextRow=2;
  TextRows=21;
  StatusRow=24;
  ShortcutRow=25;
  MaxTextLength=255;
  MaxNameLength=127;

Type
  TText=String[MaxTextLength];
  PLine=^TLine;
  TLine=Record
    Text:TText;
    Previous,Next:PLine;
  End;

Var
  FirstLine,LastLine,CurrentLine:PLine;
  LineCount,CurrentLineNumber,TopLine:LongInt;
  CursorColumn,LeftColumn:Integer;
  FileName,CutLine,StatusMessage:TText;
  Modified,QuitRequested,English,CutAvailable,FileLoadOK:Boolean;

Function LText(FrenchText,EnglishText:TText):TText;
Begin
  If English Then LText:=EnglishText Else LText:=FrenchText;
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

Procedure InsertNodeAfter(PreviousNode:PLine; Const Value:TText;
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

Procedure RemoveNode(Node:PLine);
Begin
  If Node=Nil Then Exit;
  If Node^.Previous<>Nil Then Node^.Previous^.Next:=Node^.Next
  Else FirstLine:=Node^.Next;
  If Node^.Next<>Nil Then Node^.Next^.Previous:=Node^.Previous
  Else LastLine:=Node^.Previous;
  Dispose(Node);
  Dec(LineCount);
End;

Procedure SetCurrentLine(Number:LongInt);
Begin
  If LineCount=0 Then Begin
    CurrentLine:=Nil;
    CurrentLineNumber:=0;
    CursorColumn:=0;
    Exit;
  End;
  If Number<1 Then Number:=1;
  If Number>LineCount Then Number:=LineCount;
  CurrentLineNumber:=Number;
  CurrentLine:=NodeAt(Number);
  If CursorColumn>Length(CurrentLine^.Text)Then
    CursorColumn:=Length(CurrentLine^.Text);
End;

Procedure EnsureCursorVisible;
Begin
  If CurrentLineNumber<TopLine Then TopLine:=CurrentLineNumber;
  If CurrentLineNumber>=TopLine+TextRows Then
    TopLine:=CurrentLineNumber-TextRows+1;
  If CursorColumn<LeftColumn Then LeftColumn:=CursorColumn;
  If CursorColumn>=LeftColumn+ScreenColumns Then
    LeftColumn:=CursorColumn-ScreenColumns+1;
  If TopLine<1 Then TopLine:=1;
  If LeftColumn<0 Then LeftColumn:=0;
End;

Procedure DrawEditor;
Var
  Node:PLine;
  RowNumber,ScreenLine,CursorX,CursorY:Integer;
  Title:String[255];
Begin
  EnsureCursorVisible;
  TextBackground(Blue);
  TextColor(White);
  GotoXY(1,1);
  ClrEol;
  Title:=' PICO - Pine Composer  '+FileName;
  If Modified Then Title:=Title+' *';
  Write(Copy(Title,1,ScreenColumns));
  TextBackground(Black);
  TextColor(LightGray);
  Node:=NodeAt(TopLine);
  For RowNumber:=0 to TextRows-1 Do Begin
    ScreenLine:=FirstTextRow+RowNumber;
    GotoXY(1,ScreenLine);
    ClrEol;
    If Node<>Nil Then Begin
      Write(Copy(Node^.Text,LeftColumn+1,ScreenColumns));
      Node:=Node^.Next;
    End;
  End;
  TextBackground(Blue);
  TextColor(White);
  GotoXY(1,StatusRow);
  ClrEol;
  If StatusMessage<>''Then Write(Copy(StatusMessage,1,ScreenColumns))
  Else If CurrentLineNumber>0 Then
    Write(LText('Ligne ','Line '),CurrentLineNumber,'/',LineCount,
          '  ',LText('Colonne ','Column '),CursorColumn+1);
  GotoXY(1,ShortcutRow);
  ClrEol;
  Write('^G ',LText('Aide','Help'),'  ^O ',LText('Ecrire','Write'),'  ^R ',
        LText('Lire','Read'),'  ^W ',LText('Chercher','Where Is'),
        '  ^K ',LText('Couper','Cut'),'  ^U ',LText('Coller','Uncut'),
        '  ^X ',LText('Quitter','Exit'));
  TextBackground(Black);
  TextColor(LightGray);
  If CurrentLineNumber>0 Then Begin
    CursorY:=CurrentLineNumber-TopLine+FirstTextRow;
    CursorX:=CursorColumn-LeftColumn+1;
    If CursorY<FirstTextRow Then CursorY:=FirstTextRow;
    If CursorY>FirstTextRow+TextRows-1 Then CursorY:=FirstTextRow+TextRows-1;
    If CursorX<1 Then CursorX:=1;
    If CursorX>ScreenColumns Then CursorX:=ScreenColumns;
    GotoXY(CursorX,CursorY);
  End Else GotoXY(1,FirstTextRow);
End;

Procedure SetStatus(Const MessageText:TText);
Begin
  StatusMessage:=MessageText;
End;

Function LongIntText(Value:LongInt):TText;
Var
  NumberText:String[16];
Begin
  Str(Value,NumberText);
  While(Length(NumberText)>0)and(NumberText[1]=' ')Do
    Delete(NumberText,1,1);
  LongIntText:=NumberText;
End;

Procedure InsertCharacter(Character:Char);
Var
  NewNode:PLine;
Begin
  If CurrentLine=Nil Then Begin
    InsertNodeAfter(Nil,'',NewNode);
    CurrentLine:=NewNode;
    CurrentLineNumber:=1;
    CursorColumn:=0;
  End;
  If Length(CurrentLine^.Text)>=MaxTextLength Then Begin
    SetStatus(LText('Ligne trop longue (255 caracteres maximum)',
                    'Line is full (255 character maximum)'));
    Exit;
  End;
  Insert(Character,CurrentLine^.Text,CursorColumn+1);
  Inc(CursorColumn);
  Modified:=True;
End;

Procedure InsertNewLine;
Var
  NewNode:PLine;
  Remainder:String[MaxTextLength];
Begin
  If CurrentLine=Nil Then Begin
    InsertNodeAfter(Nil,'',NewNode);
    CurrentLine:=NewNode;
    CurrentLineNumber:=1;
    CursorColumn:=0;
    Modified:=True;
    Exit;
  End;
  Remainder:=Copy(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
  Delete(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
  InsertNodeAfter(CurrentLine,Remainder,NewNode);
  Inc(CurrentLineNumber);
  CurrentLine:=NewNode;
  CursorColumn:=0;
  Modified:=True;
End;

Procedure BackspaceCharacter;
Var
  PreviousNode:PLine;
  PreviousNumber:LongInt;
Begin
  If CurrentLine=Nil Then Exit;
  If CursorColumn>0 Then Begin
    Delete(CurrentLine^.Text,CursorColumn,1);
    Dec(CursorColumn);
    Modified:=True;
  End Else If CurrentLine^.Previous<>Nil Then Begin
    PreviousNode:=CurrentLine^.Previous;
    PreviousNumber:=CurrentLineNumber-1;
    If Length(PreviousNode^.Text)+Length(CurrentLine^.Text)<=MaxTextLength Then Begin
      CursorColumn:=Length(PreviousNode^.Text);
      PreviousNode^.Text:=PreviousNode^.Text+CurrentLine^.Text;
      RemoveNode(CurrentLine);
      CurrentLine:=PreviousNode;
      CurrentLineNumber:=PreviousNumber;
      Modified:=True;
    End;
  End;
End;

Procedure DeleteCharacter;
Var
  NextNode:PLine;
Begin
  If CurrentLine=Nil Then Exit;
  If CursorColumn<Length(CurrentLine^.Text)Then Begin
    Delete(CurrentLine^.Text,CursorColumn+1,1);
    Modified:=True;
  End Else If CurrentLine^.Next<>Nil Then Begin
    NextNode:=CurrentLine^.Next;
    If Length(CurrentLine^.Text)+Length(NextNode^.Text)<=MaxTextLength Then Begin
      CurrentLine^.Text:=CurrentLine^.Text+NextNode^.Text;
      RemoveNode(NextNode);
      Modified:=True;
    End;
  End;
End;

Procedure MoveLeft;
Begin
  If CurrentLine=Nil Then Exit;
  If CursorColumn>0 Then Dec(CursorColumn)
  Else If CurrentLine^.Previous<>Nil Then Begin
    Dec(CurrentLineNumber);
    CurrentLine:=CurrentLine^.Previous;
    CursorColumn:=Length(CurrentLine^.Text);
  End;
End;

Procedure MoveRight;
Begin
  If CurrentLine=Nil Then Exit;
  If CursorColumn<Length(CurrentLine^.Text)Then Inc(CursorColumn)
  Else If CurrentLine^.Next<>Nil Then Begin
    Inc(CurrentLineNumber);
    CurrentLine:=CurrentLine^.Next;
    CursorColumn:=0;
  End;
End;

Procedure MoveVertical(Delta:LongInt);
Var
  NewNumber:LongInt;
Begin
  If LineCount=0 Then Exit;
  NewNumber:=CurrentLineNumber+Delta;
  If NewNumber<1 Then NewNumber:=1;
  If NewNumber>LineCount Then NewNumber:=LineCount;
  SetCurrentLine(NewNumber);
End;

Procedure CutCurrentLine;
Var
  PreviousNode,NextNode:PLine;
Begin
  If CurrentLine=Nil Then Exit;
  CutLine:=CurrentLine^.Text;
  CutAvailable:=True;
  PreviousNode:=CurrentLine^.Previous;
  NextNode:=CurrentLine^.Next;
  If LineCount=1 Then Begin
    CurrentLine^.Text:='';
    CursorColumn:=0;
  End Else Begin
    RemoveNode(CurrentLine);
    If NextNode<>Nil Then Begin
      CurrentLine:=NextNode;
      CursorColumn:=0;
    End Else Begin
      CurrentLine:=PreviousNode;
      CursorColumn:=Length(CurrentLine^.Text);
    End;
    If PreviousNode<>Nil Then CurrentLineNumber:=CurrentLineNumber-1
    Else CurrentLineNumber:=1;
  End;
  Modified:=True;
  SetStatus(LText('Ligne coupee','Line cut'));
End;

Procedure PasteCutLine;
Var
  PreviousNode,NewNode:PLine;
Begin
  If Not CutAvailable Then Begin
    SetStatus(LText('Rien a coller','Nothing to uncut'));
    Exit;
  End;
  If CurrentLine=Nil Then PreviousNode:=Nil
  Else PreviousNode:=CurrentLine;
  InsertNodeAfter(PreviousNode,CutLine,NewNode);
  If PreviousNode=Nil Then CurrentLineNumber:=1
  Else Inc(CurrentLineNumber);
  CurrentLine:=NewNode;
  CursorColumn:=0;
  Modified:=True;
  SetStatus(LText('Ligne collee','Line pasted'));
End;

Procedure LoadTextFile(Const Name:TText; AfterLine:LongInt;
                       ReplaceBuffer:Boolean);
Var
  Source:Text;
  SourceLine:TText;
  InsertNode,NewNode:PLine;
  ErrorCode:Integer;
  NumberRead:LongInt;
Begin
  FileLoadOK:=False;
  Assign(Source,Name);
  {$I-}Reset(Source);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    SetStatus(LText('Impossible de lire le fichier',
                    'Cannot read file')+' '+Name);
    Exit;
  End;
  If ReplaceBuffer Then Begin
    While FirstLine<>Nil Do RemoveNode(FirstLine);
    CurrentLine:=Nil;
    CurrentLineNumber:=0;
    CursorColumn:=0;
  End;
  If AfterLine<1 Then InsertNode:=Nil Else InsertNode:=NodeAt(AfterLine);
  NumberRead:=0;
  While Not EOF(Source)Do Begin
    {$I-}ReadLn(Source,SourceLine);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      {$I-}Close(Source);{$I+}
      ErrorCode:=IOResult;
      SetStatus(LText('Erreur durant la lecture','Read error')+' '+Name);
      Exit;
    End;
    InsertNodeAfter(InsertNode,SourceLine,NewNode);
    InsertNode:=NewNode;
    Inc(NumberRead);
  End;
  {$I-}Close(Source);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    SetStatus(LText('Erreur a la fermeture du fichier',
                    'Error closing file')+' '+Name);
    Exit;
  End;
  If ReplaceBuffer Then Begin
    FileName:=Name;
    Modified:=False;
    If FirstLine<>Nil Then Begin
      CurrentLine:=FirstLine;
      CurrentLineNumber:=1;
      CursorColumn:=0;
    End;
  End Else If NumberRead>0 Then Modified:=True;
  FileLoadOK:=True;
  SetStatus(LText('Fichier lu','Read file')+' '+Name);
End;

Procedure SaveTextFile(Const Name:TText);
Var
  Destination:Text;
  Node:PLine;
  ErrorCode:Integer;
Begin
  If Name=''Then Begin
    SetStatus(LText('Nom de fichier requis','A filename is required'));
    Exit;
  End;
  Assign(Destination,Name);
  {$I-}Rewrite(Destination);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    SetStatus(LText('Impossible d''ecrire le fichier',
                    'Cannot write file')+' '+Name);
    Exit;
  End;
  Node:=FirstLine;
  While Node<>Nil Do Begin
    {$I-}WriteLn(Destination,Node^.Text);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      {$I-}Close(Destination);{$I+}
      ErrorCode:=IOResult;
      SetStatus(LText('Erreur durant l''ecriture','Write error')+' '+Name);
      Exit;
    End;
    Node:=Node^.Next;
  End;
  {$I-}Close(Destination);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
    SetStatus(LText('Erreur a la fermeture du fichier',
                    'Error closing file')+' '+Name);
    Exit;
  End;
  FileName:=Name;
  Modified:=False;
  SetStatus(LText('Ecrit','Wrote')+' '+Name);
End;

Procedure ReadPrompt(Const PromptText,DefaultText:TText;
                     Var ResultText:TText; Var Cancelled:Boolean);
Var
  Key:Char;
Begin
  ResultText:=DefaultText;
  Cancelled:=False;
  Repeat
    GotoXY(1,StatusRow);
    TextBackground(Blue);
    TextColor(White);
    ClrEol;
    Write(PromptText,ResultText);
    Key:=ReadKey;
    If Key=#27 Then Begin
      Cancelled:=True;
      ResultText:='';
    End Else If Key=#13 Then Exit
    Else If Key=#8 Then Begin
      If ResultText<>''Then Delete(ResultText,Length(ResultText),1);
    End Else If Ord(Key)>=32 Then Begin
      If Length(ResultText)<MaxTextLength Then ResultText:=ResultText+Key;
    End;
  Until Cancelled;
End;

Procedure SaveWithPrompt;
Var
  Name:TText;
  Cancelled:Boolean;
Begin
  ReadPrompt(LText('Ecrire le fichier sous: ','File Name to Write: '),
             FileName,Name,Cancelled);
  If Not Cancelled Then SaveTextFile(Name);
End;

Procedure ReadWithPrompt;
Var
  Name:TText;
  Cancelled:Boolean;
  AfterLine:LongInt;
Begin
  ReadPrompt(LText('Lire le fichier: ','File to Insert: '),'',Name,Cancelled);
  If Cancelled or(Name='')Then Exit;
  AfterLine:=CurrentLineNumber;
  LoadTextFile(Name,AfterLine,False);
  If CurrentLineNumber=0 Then SetCurrentLine(AfterLine+1);
End;

Function FindInLine(Const SourceText,SearchText:TText;
                    StartAt:Integer):Integer;
Var
  Position,PatternIndex:Integer;
  SourceLength,SearchLength:Integer;
  Matches:Boolean;
Begin
  FindInLine:=0;
  SourceLength:=Length(SourceText);
  SearchLength:=Length(SearchText);
  If SearchLength=0 Then Exit;
  If StartAt<1 Then StartAt:=1;
  Position:=StartAt;
  While Position<=SourceLength-SearchLength+1 Do Begin
    Matches:=True;
    For PatternIndex:=1 to SearchLength Do
      If SourceText[Position+PatternIndex-1]<>SearchText[PatternIndex]Then Begin
        Matches:=False;
        Break;
      End;
    If Matches Then Begin
      FindInLine:=Position;
      Exit;
    End;
    Inc(Position);
  End;
End;

Procedure SearchPrompt;
Var
  SearchText:TText;
  Cancelled:Boolean;
  Node:PLine;
  Index,StartColumn:LongInt;
  FoundAt:Integer;
Begin
  ReadPrompt(LText('Chercher: ','Search: '),'',SearchText,Cancelled);
  If Cancelled or(SearchText='')Then Exit;
  Node:=CurrentLine;
  Index:=CurrentLineNumber;
  For StartColumn:=1 to LineCount Do Begin
    If Node=Nil Then Begin Node:=FirstLine;Index:=1;End;
    If StartColumn=1 Then FoundAt:=FindInLine(Node^.Text,SearchText,CursorColumn+1)
    Else FoundAt:=FindInLine(Node^.Text,SearchText,1);
    If FoundAt>0 Then Begin
      If StartColumn=1 Then Inc(CursorColumn,FoundAt-1)
      Else Begin
        CurrentLine:=Node;
        CurrentLineNumber:=Index;
        CursorColumn:=FoundAt-1;
      End;
      SetStatus(LText('Texte trouve','Search string found'));
      Exit;
    End;
    Node:=Node^.Next;
    Inc(Index);
  End;
  SetStatus(LText('Texte introuvable','Search string not found'));
End;

Procedure ShowHelp;
Var
  Key:Char;
Begin
  ClrScr;
  TextBackground(Blue);
  TextColor(White);
  GotoXY(1,2);
  WriteLn('PICO - ',LText('Aide','Help'));
  WriteLn;
  WriteLn('^G  ',LText('Afficher cette aide','Display this help'));
  WriteLn('^O  ',LText('Ecrire le fichier','Write Out'));
  WriteLn('^R  ',LText('Lire un fichier dans le buffer','Read File'));
  WriteLn('^W  ',LText('Chercher du texte','Where Is'));
  WriteLn('^K  ',LText('Couper la ligne courante','Cut line'));
  WriteLn('^U  ',LText('Inserer la ligne coupee','Uncut line'));
  WriteLn('^X  ',LText('Quitter','Exit'));
  WriteLn;
  WriteLn(LText('Fleches: deplacer le curseur',
                'Arrow keys: move the cursor'));
  WriteLn(LText('Entree: couper la ligne au curseur',
                'Enter: split the line at the cursor'));
  WriteLn(LText('Echap: annuler une invite','Escape: cancel a prompt'));
  GotoXY(1,ShortcutRow);
  ClrEol;
  Write(LText('Appuyez sur une touche pour revenir',
               'Press any key to return'));
  Key:=ReadKey;
  StatusMessage:='';
End;

Procedure ExitPrompt;
Var
  Key:Char;
Begin
  If Not Modified Then Begin
    QuitRequested:=True;
    Exit;
  End;
  GotoXY(1,StatusRow);
  TextBackground(Blue);
  TextColor(White);
  ClrEol;
  Write(LText('Enregistrer les modifications? (O)ui/(N)on/(A)nnuler: ',
               'Save modified buffer? (Y)es/(N)o/(C)ancel: '));
  Key:=ReadKey;
  If English Then Key:=UpCase(Key)
  Else Key:=UpCase(Key);
  If(Key='Y')or(Key='O')Then Begin
    If FileName=''Then SaveWithPrompt Else SaveTextFile(FileName);
    If Not Modified Then QuitRequested:=True;
  End Else If Key='N'Then QuitRequested:=True
  Else StatusMessage:='';
End;

Procedure HandleControlKey(Key:Char);
Var
  Spaces,Index:Integer;
Begin
  Case Ord(Key)Of
    8:BackspaceCharacter;
    3:Begin
      If CurrentLineNumber>0 Then
        SetStatus(LText('Ligne ','Line ')+LongIntText(CurrentLineNumber));
    End;
    7:ShowHelp;
    9:Begin
      Spaces:=8-(CursorColumn Mod 8);
      For Index:=1 to Spaces Do InsertCharacter(' ');
    End;
    11:CutCurrentLine;
    14:MoveVertical(1);
    15:SaveWithPrompt;
    18:ReadWithPrompt;
    19:SaveWithPrompt;
    21:PasteCutLine;
    22:MoveVertical(TextRows);
    23:SearchPrompt;
    24:ExitPrompt;
    25:MoveVertical(-TextRows);
    13:InsertNewLine;
  End;
End;

Procedure HandleExtendedKey;
Var
  Key:Char;
Begin
  Key:=ReadKey;
  Case Ord(Key)Of
    71:If CurrentLine<>Nil Then CursorColumn:=0;
    72:MoveVertical(-1);
    75:MoveLeft;
    77:MoveRight;
    79:If CurrentLine<>Nil Then CursorColumn:=Length(CurrentLine^.Text);
    80:MoveVertical(1);
    73:MoveVertical(-TextRows);
    81:MoveVertical(TextRows);
    83:DeleteCharacter;
  End;
End;

Procedure FreeBuffer;
Begin
  While FirstLine<>Nil Do RemoveNode(FirstLine);
  CurrentLine:=Nil;
  CurrentLineNumber:=0;
  LineCount:=0;
End;

Var
  Key:Char;
  SearchRecord:SearchRec;
  FilePresent:Boolean;
  Arg:String[MaxTextLength];
  ErrorCode:Integer;
  EnvLanguage:String[20];
BEGIN
 {$IFDEF FPC}
  {$IFDEF WINDOWS}
   SetUseACP(False);
  {$ENDIF}
 {$ENDIF}
  FirstLine:=Nil;
  LastLine:=Nil;
  CurrentLine:=Nil;
  LineCount:=0;
  CurrentLineNumber:=0;
  CursorColumn:=0;
  TopLine:=1;
  LeftColumn:=0;
  FileName:='';
  CutLine:='';
  CutAvailable:=False;
  StatusMessage:='';
  Modified:=False;
  QuitRequested:=False;
  EnvLanguage:=GetEnv('LANGUAGE');
  English:=Copy(EnvLanguage,1,2)='EN';

  If ParamCount>1 Then Begin
    WriteLn(LText('Syntaxe: pico [fichier]','Syntax: pico [filename]'));
    Halt(2);
  End;
  If ParamCount=1 Then Begin
    Arg:=ParamStr(1);
    If(Arg='-h')or(Arg='--help')or(Arg='/?')or(Arg='/h')or(Arg='/H')Then Begin
      WriteLn('PICO - ',LText('Cette commande permet de lancer l'''+#130+'diteur de texte en mode terminal',
                               'Terminal text editor'));
      WriteLn;
      WriteLn(LText('Syntaxe: pico [fichier]','Syntax: pico [filename]'));
      WriteLn;
      WriteLn(LText('Raccourcis: Ctrl-G aide, Ctrl-O ecrire, Ctrl-X quitter',
                    'Keys: Ctrl-G help, Ctrl-O write, Ctrl-X exit'));
      Halt(0);
    End;
    FileName:=Arg;
    FindFirst(FileName,AnyFile,SearchRecord);
    FilePresent:=DosError=0;
    If FilePresent Then Begin
      If(SearchRecord.Attr and Directory)<>0 Then Begin
        WriteLn(LText('pico: le nom indique est un repertoire',
                      'pico: filename is a directory'));
        Halt(2);
      End;
      LoadTextFile(FileName,0,True);
      If Not FileLoadOK Then Begin
        WriteLn('pico: ',StatusMessage);
        Halt(1);
      End;
    End Else Begin
      FileName:=Arg;
      SetStatus(LText('Nouveau fichier','New file'));
    End;
  End;

  TextBackground(Black);
  TextColor(LightGray);
  ClrScr;
  Repeat
    DrawEditor;
    StatusMessage:='';
    Key:=ReadKey;
    If Key=#0 Then HandleExtendedKey
    Else If Ord(Key)<32 Then HandleControlKey(Key)
    Else If Ord(Key)<127 Then InsertCharacter(Key);
  Until QuitRequested;
  TextBackground(Black);
  TextColor(LightGray);
  ClrScr;
  FreeBuffer;
END.