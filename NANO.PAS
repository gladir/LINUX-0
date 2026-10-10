{ @author: Sylvain Maltais (support@gladir.com)
 @created: 2026
 @website(https://www.gladir.com/linux-0)
 @abstract(Target: Turbo Pascal 7, Free Pascal 3.2) }

Program NANO;


Uses DOS,CRT;

Const
 ScreenColumns=80;
 FirstTextRow=2;
 DefaultTextRows=21;
 StatusRow=23;
 ShortcutRow=24;
 SecondShortcutRow=25;
 MaxTextLength=255;
 MaxFiles=16;
 MaxTabSize=16;

Type
 TText=String[MaxTextLength];
 TFileName=String[127];
 PLine=^TLine;
 TLine=Record
  Text:TText;
  Previous,Next:PLine;
 End;
 TFileList=Array[1..MaxFiles]Of TFileName;

Var
 FirstLine,LastLine,CurrentLine:PLine;
 LineCount,CurrentLineNumber,TopLine:LongInt;
 CursorColumn,LeftColumn:Integer;
 VisibleTextRows:Integer;
 FileNames:TFileList;
 FileCount,CurrentFileIndex:Integer;
 FileName,StatusMessage,CutText,BackupDirectory,OperatingDirectory:TText;
 QuoteString,SpellerProgram,SyntaxName:TText;
 Modified,QuitRequested,English,ViewOnly:Boolean;
 FileLoadOK:Boolean;
 SmartHome,AutoIndent,BackupEnabled,BoldText,ConstantPosition:Boolean;
 CutToEnd,ConvertTabs,MultiBuffer,NoConvert,NoFinalNewline:Boolean;
 NoHelp,NoWrap,MoreSpace,PreserveKeys,QuickBlank,RestrictedMode:Boolean;
 SmoothScroll,SuspendEnabled,TempFile,WordBounds,MouseEnabled:Boolean;
 RebindDelete,RebindKeypad,HistoryLog:Boolean;
 TabSize,FillColumn,StartLine,StartColumn:Integer;

Function LText(FrenchText,EnglishText:TText):TText;Begin
 If English Then LText:=EnglishText Else LText:=FrenchText;
End;

Function NodeAt(Number:LongInt):PLine;
Var
 Node:PLine;
 Index:LongInt;
Begin
 NodeAt:=Nil;
 If(Number<1)Or(Number>LineCount)Then Exit;
 Node:=FirstLine;
 For Index:=1 To Number-1 Do Node:=Node^.Next;
 NodeAt:=Node;
End;

Procedure InsertNodeAfter(PreviousNode:PLine; Const Value:TText;
                          Var NewNode:PLine);Begin
 New(NewNode);
 NewNode^.Text:=Value;
 If PreviousNode=Nil Then Begin
  NewNode^.Previous:=Nil;
  NewNode^.Next:=FirstLine;
  If FirstLine<>Nil Then FirstLine^.Previous:=NewNode
                    Else LastLine:=NewNode;
  FirstLine:=NewNode;
 End Else
 Begin
  NewNode^.Previous:=PreviousNode;
  NewNode^.Next:=PreviousNode^.Next;
  If PreviousNode^.Next<>Nil Then PreviousNode^.Next^.Previous:=NewNode
                             Else LastLine:=NewNode;
  PreviousNode^.Next:=NewNode;
 End;
 Inc(LineCount);
End;

Procedure RemoveNode(Node:PLine);Begin
 If Node=Nil Then Exit;
 If Node^.Previous<>Nil Then Node^.Previous^.Next:=Node^.Next
                        Else FirstLine:=Node^.Next;
 If Node^.Next<>Nil Then Node^.Next^.Previous:=Node^.Previous
                    Else LastLine:=Node^.Previous;
 Dispose(Node);
 Dec(LineCount);
End;

Procedure FreeBuffer;Begin
 While FirstLine<>Nil Do RemoveNode(FirstLine);
 CurrentLine:=Nil;
 CurrentLineNumber:=0;
 LineCount:=0;
End;

Procedure SetCurrentLine(Number:LongInt);Begin
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
 If CursorColumn>Length(CurrentLine^.Text)Then    CursorColumn:=Length(CurrentLine^.Text);
End;

Procedure SetStatus(Const MessageText:TText);Begin
 StatusMessage:=MessageText;
End;

Procedure DrawShortcut(RowPosition,ColumnPosition:Integer;
                       Const KeyName,Description:TText);Begin
 GotoXY(ColumnPosition,RowPosition);
 TextBackground(White);
 TextColor(Magenta);
 Write(KeyName);
 TextBackground(Magenta);
 TextColor(White);
 Write(' ',Description);
End;

Procedure EnsureCursorVisible;Begin
 If CurrentLineNumber<TopLine Then TopLine:=CurrentLineNumber;
 If CurrentLineNumber>=TopLine+VisibleTextRows Then    TopLine:=CurrentLineNumber-
 VisibleTextRows+1;
 If CursorColumn<LeftColumn Then LeftColumn:=CursorColumn;
 If CursorColumn>=LeftColumn+ScreenColumns Then    LeftColumn:=CursorColumn-ScreenColumns+
 1;
 If TopLine<1 Then TopLine:=1;
 If LeftColumn<0 Then LeftColumn:=0;
End;

Procedure DrawEditor;
Var
 Node:PLine;
 RowNumber,ScreenLine,CursorX,CursorY:Integer;
 Title:TText;
Begin
 EnsureCursorVisible;
 TextBackground(White);
 TextColor(Magenta);
 GotoXY(1,1);
 ClrEol;
 Title:=' GNU nano  '+FileName;
 If Modified Then Title:=Title+' *';
 Write(Copy(Title,1,ScreenColumns));
 TextBackground(Magenta);
 TextColor(LightGray);
 Node:=NodeAt(TopLine);
 For RowNumber:=0 To VisibleTextRows-1 Do Begin
  ScreenLine:=FirstTextRow+RowNumber;
  GotoXY(1,ScreenLine);
  ClrEol;
  If Node<>Nil Then Begin
   Write(Copy(Node^.Text,LeftColumn+1,ScreenColumns));
   Node:=Node^.Next;
  End;
 End;
 TextBackground(Magenta);
 TextColor(White);
 GotoXY(1,StatusRow);
 ClrEol;
 If StatusMessage<>''Then Write(Copy(StatusMessage,1,ScreenColumns))
 Else If ConstantPosition And(CurrentLineNumber>0)Then    Write(LText('Ligne ','Line '),
 CurrentLineNumber,'/',LineCount,
 '  ',LText('Colonne ','Column '),CursorColumn+1)
 Else If FileName<>''Then Write(FileName,'  ',LineCount,' ',
 LText('lignes','lines'));
 If Not NoHelp Then Begin
  GotoXY(1,ShortcutRow);ClrEol;
  GotoXY(1,SecondShortcutRow);ClrEol;
  DrawShortcut(ShortcutRow,1,'^G',LText('Aide','Help'));
  DrawShortcut(ShortcutRow,14,'^O',LText('Ecrire','Write'));
  DrawShortcut(ShortcutRow,27,'^R',LText('Lire fich.','Read File'));
  DrawShortcut(ShortcutRow,40,'^Y',LText('Page prec.','Prev Page'));
  DrawShortcut(ShortcutRow,53,'^K',LText('Couper','Cut Text'));
  DrawShortcut(ShortcutRow,66,'^C',LText('Pos. cur.','Cur Pos'));
  DrawShortcut(SecondShortcutRow,1,'^X',LText('Quitter','Exit'));
  DrawShortcut(SecondShortcutRow,14,'^J',LText('Justifier','Justify'));
  DrawShortcut(SecondShortcutRow,27,'^W',LText('Chercher','Where Is'));
  DrawShortcut(SecondShortcutRow,40,'^V',LText('Page suiv.','Next Page'));
  DrawShortcut(SecondShortcutRow,53,'^U',LText('Coller','UnCut'));
  DrawShortcut(SecondShortcutRow,66,'^T',LText('Orthograph.','Spell'));
 End;
 TextBackground(Magenta);
 TextColor(LightGray);
 If CurrentLineNumber>0 Then Begin
  CursorY:=CurrentLineNumber-TopLine+FirstTextRow;
  CursorX:=CursorColumn-LeftColumn+1;
  If CursorY<FirstTextRow Then CursorY:=FirstTextRow;
  If CursorY>FirstTextRow+VisibleTextRows-1 Then CursorY:=FirstTextRow+VisibleTextRows-1;
  If CursorX<1 Then CursorX:=1;
  If CursorX>ScreenColumns Then CursorX:=ScreenColumns;
  GotoXY(CursorX,CursorY);
 End Else GotoXY(1,FirstTextRow);
End;

Procedure InsertCharacter(Character:Char);
Var
 NewNode:PLine;
Begin
 If ViewOnly Then Exit;
 If CurrentLine=Nil Then Begin
  InsertNodeAfter(Nil,'',NewNode);
  CurrentLine:=NewNode;
  CurrentLineNumber:=1;
  CursorColumn:=0;
 End;
 If Length(CurrentLine^.Text)>=MaxTextLength Then Begin
  SetStatus(LText('Ligne trop longue','Line is full'));
  Exit;
 End;
 Insert(Character,CurrentLine^.Text,CursorColumn+1);
 Inc(CursorColumn);
 Modified:=True;
End;

Procedure InsertNewLine;
Var
 NewNode:PLine;
 Remainder:TText;
 IndentLength,Index:Integer;
Begin
 If ViewOnly Then Exit;
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
 If AutoIndent Then Begin
  IndentLength:=0;
  While(IndentLength<Length(CurrentLine^.Text))And
  (CurrentLine^.Text[IndentLength+1]In[' ',#9])Do      Inc(IndentLength);
  If IndentLength>MaxTextLength-Length(Remainder)Then      IndentLength:=MaxTextLength-
  Length(Remainder);
  For Index:=IndentLength Downto 1 Do      Insert(CurrentLine^.Text[Index],Remainder,1);
 End;
 InsertNodeAfter(CurrentLine,Remainder,NewNode);
 Inc(CurrentLineNumber);
 CurrentLine:=NewNode;
 CursorColumn:=0;
 If AutoIndent Then
 While(CursorColumn<Length(CurrentLine^.Text))And
 (CurrentLine^.Text[CursorColumn+1]In[' ',#9])Do Inc(CursorColumn);
 Modified:=True;
End;

Procedure BackspaceCharacter;
Var
 PreviousNode:PLine;
Begin
 If ViewOnly Or(CurrentLine=Nil)Then Exit;
 If CursorColumn>0 Then Begin
  Delete(CurrentLine^.Text,CursorColumn,1);
  Dec(CursorColumn);
  Modified:=True;
 End Else If CurrentLine^.Previous<>Nil Then Begin
  PreviousNode:=CurrentLine^.Previous;
  If Length(PreviousNode^.Text)+Length(CurrentLine^.Text)<=MaxTextLength Then Begin
   CursorColumn:=Length(PreviousNode^.Text);
   PreviousNode^.Text:=PreviousNode^.Text+CurrentLine^.Text;
   RemoveNode(CurrentLine);
   CurrentLine:=PreviousNode;
   Dec(CurrentLineNumber);
   Modified:=True;
  End;
 End;
End;

Procedure DeleteCharacter;
Var
 NextNode:PLine;
Begin
 If ViewOnly Or(CurrentLine=Nil)Then Exit;
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

Procedure MoveLeft;Begin
 If CurrentLine=Nil Then Exit;
 If CursorColumn>0 Then Dec(CursorColumn) Else
 If CurrentLine^.Previous<>Nil Then Begin
  Dec(CurrentLineNumber);
  CurrentLine:=CurrentLine^.Previous;
  CursorColumn:=Length(CurrentLine^.Text);
 End;
End;

Procedure MoveRight;Begin
 If CurrentLine=Nil Then Exit;
 If CursorColumn<Length(CurrentLine^.Text)Then Inc(CursorColumn)
 Else If CurrentLine^.Next<>Nil Then Begin
  Inc(CurrentLineNumber);
  CurrentLine:=CurrentLine^.Next;
  CursorColumn:=0;
 End;
End;

Procedure MoveVertical(Delta:LongInt);Begin
 If LineCount=0 Then Exit;
 SetCurrentLine(CurrentLineNumber+Delta);
End;

Procedure MoveHome;
Var
 Index:Integer;
Begin
 If CurrentLine=Nil Then Exit;
 If SmartHome Then Begin
  Index:=0;
  While(Index<Length(CurrentLine^.Text))And
  (CurrentLine^.Text[Index+1]In[' ',#9])Do Inc(Index);
  If CursorColumn=Index Then CursorColumn:=0 Else CursorColumn:=Index;
 End Else CursorColumn:=0;
End;

Procedure CutCurrentLine;
Var
 PreviousNode,NextNode:PLine;
Begin
 If ViewOnly Or(CurrentLine=Nil)Then Exit;
 If CutToEnd Then Begin
  CutText:=Copy(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
  Delete(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
 End Else
 Begin
  CutText:=CurrentLine^.Text;
  PreviousNode:=CurrentLine^.Previous;
  NextNode:=CurrentLine^.Next;
  If LineCount=1 Then CurrentLine^.Text:=''
   Else
  Begin
   RemoveNode(CurrentLine);
   If NextNode<>Nil Then CurrentLine:=NextNode
                    Else CurrentLine:=PreviousNode;
   If PreviousNode<>Nil Then Dec(CurrentLineNumber)
                        Else CurrentLineNumber:=1;
   If CurrentLine<>Nil Then CursorColumn:=Length(CurrentLine^.Text);
  End;
 End;
 Modified:=True;
 SetStatus(LText('Texte coupe','Text cut'));
End;

Procedure PasteCutText;Begin
 If ViewOnly Or(CutText='')Or(CurrentLine=Nil)Then Exit;
 If Length(CurrentLine^.Text)+Length(CutText)<=MaxTextLength Then Begin
  Insert(CutText,CurrentLine^.Text,CursorColumn+1);
  Inc(CursorColumn,Length(CutText));
  Modified:=True;
 End;
End;

Procedure JustifyCurrentLine;
Type
 TPositionList=Array[1..MaxTextLength]Of Integer;
Var
 WordStart,WordLength:TPositionList;
 ResultText:TText;
 Position,WordCount,CharCount,GapCount,TargetWidth:Integer;
 SpacesPerGap,ExtraSpaces,Index,SpaceIndex:Integer;
Begin
 If ViewOnly Or(CurrentLine=Nil)Then Exit;
 WordCount:=0;CharCount:=0;Position:=1;
 While Position<=Length(CurrentLine^.Text)Do Begin
  While(Position<=Length(CurrentLine^.Text))And
    (CurrentLine^.Text[Position]In[' ',#9])Do Inc(Position);
  If Position<=Length(CurrentLine^.Text)Then Begin
   Inc(WordCount);
   WordStart[WordCount]:=Position;
     While(Position<=Length(CurrentLine^.Text))And
       Not(CurrentLine^.Text[Position]In[' ',#9])Do Inc(Position);
   WordLength[WordCount]:=Position-WordStart[WordCount];
   Inc(CharCount,WordLength[WordCount]);
  End;
 End;
 If WordCount<2 Then Begin
  SetStatus(LText('La ligne ne contient pas assez de mots',
         'Not enough words on this line'));
  Exit;
 End;
 TargetWidth:=FillColumn;
 If TargetWidth<CharCount+WordCount-1 Then TargetWidth:=CharCount+WordCount-1;
 If TargetWidth>MaxTextLength Then TargetWidth:=MaxTextLength;
 GapCount:=WordCount-1;
 SpacesPerGap:=(TargetWidth-CharCount)Div GapCount;
 ExtraSpaces:=(TargetWidth-CharCount)Mod GapCount;
 ResultText:='';
 For Index:=1 To WordCount Do Begin
  ResultText:=ResultText+Copy(CurrentLine^.Text,WordStart[Index],WordLength[Index]);
  If Index<WordCount Then Begin
   For SpaceIndex:=1 To SpacesPerGap Do ResultText:=ResultText+' ';
   If Index<=ExtraSpaces Then ResultText:=ResultText+' ';
  End;
 End;
 CurrentLine^.Text:=ResultText;
 CursorColumn:=Length(ResultText);
 Modified:=True;
 SetStatus(LText('Ligne justifiee','Line justified'));
End;

Function FindInLine(Const SourceText,SearchText:TText;
                    StartAt:Integer):Integer;
Var
 Position,PatternIndex,SourceLength,SearchLength:Integer;
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
  For PatternIndex:=1 To SearchLength Do      If SourceText[Position+PatternIndex-1]<>
  SearchText[PatternIndex]Then Begin
   Matches:=False;
   Break;
  End;
  If Matches Then Begin
   FindInLine:=Position;Exit;
  End;
  Inc(Position);
 End;
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
  TextBackground(Magenta);
 TextColor(White);
 ClrEol;
 Write(PromptText,ResultText);
 Key:=ReadKey;
 If Key=#27 Then Begin
  Cancelled:=True;ResultText:='';
 End
 Else If Key=#13 Then Exit Else
 If Key=#8 Then Begin
  If ResultText<>''Then Delete(ResultText,Length(ResultText),1);
 End Else If Ord(Key)>=32 Then Begin
  If Length(ResultText)<MaxTextLength Then ResultText:=ResultText+Key;
 End;
 Until Cancelled;
End;

Procedure SearchText;
Var
 Pattern:TText;
 Cancelled:Boolean;
 Node:PLine;
 Index,FoundAt:LongInt;
Begin
 ReadPrompt(LText('Chercher: ','Search: '),'',Pattern,Cancelled);
 If Cancelled Or(Pattern='')Or(CurrentLine=Nil)Then Exit;
 Node:=CurrentLine;
 Index:=CurrentLineNumber;
 FoundAt:=0;
 While Node<>Nil Do Begin
  If Node=CurrentLine Then FoundAt:=FindInLine(Node^.Text,Pattern,CursorColumn+2)
                      Else FoundAt:=FindInLine(Node^.Text,Pattern,1);
  If FoundAt>0 Then Begin
   CurrentLine:=Node;
   CurrentLineNumber:=Index;
   CursorColumn:=FoundAt-1;
   SetStatus(LText('Texte trouve','Search string found'));
   Exit;
  End;
  Node:=Node^.Next;
  Inc(Index);
 End;
 Node:=FirstLine;
 Index:=1;
 While(Node<>Nil)And(Index<CurrentLineNumber)Do Begin
  FoundAt:=FindInLine(Node^.Text,Pattern,1);
  If FoundAt>0 Then Begin
   CurrentLine:=Node;
   CurrentLineNumber:=Index;
   CursorColumn:=FoundAt-1;
   SetStatus(LText('Texte trouve','Search string found'));
   Exit;
  End;
  Node:=Node^.Next;
  Inc(Index);
 End;
 SetStatus(LText('Texte introuvable','Search string not found'));
End;

Procedure CopyFileText(Const SourceName,DestinationName:TText);
Var
 Source,Destination:Text;
 LineText:TText;
 ErrorCode:Integer;
Begin
 Assign(Source,SourceName);
  {$I-}Reset(Source);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Exit;
 Assign(Destination,DestinationName);
  {$I-}Rewrite(Destination);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
 {$I-}Close(Source);{$I+}ErrorCode:=IOResult;Exit;
 End;
 While Not EOF(Source)Do Begin
  ReadLn(Source,LineText);
  WriteLn(Destination,LineText);
 End;
 Close(Source);
 Close(Destination);
End;

Function BackupName(Const Name:TText):TText;
Var
 Index:Integer;
 ResultName:TText;
Begin
 If BackupDirectory<>''Then Begin
  ResultName:=BackupDirectory;
  If(ResultName[Length(ResultName)]<>'/')And
  (ResultName[Length(ResultName)]<>#92)Then ResultName:=ResultName+#92;
  Index:=Length(Name);
  While(Index>0)And(Name[Index]<>'/')And(Name[Index]<>#92)Do Dec(Index);
  ResultName:=ResultName+Copy(Name,Index+1,MaxTextLength)+'~';
 End Else ResultName:=Name+'~';
 BackupName:=ResultName;
End;

Procedure SaveTextFile(Const Name:TText);
Var
 Destination:Text;
 Node:PLine;
 ErrorCode:Integer;
 SearchRecord:SearchRec;
 BackupFile:TText;
Begin
 If Name=''Then Begin
  SetStatus(LText('Nom de fichier requis','A filename is required'));Exit;
 End;
 If RestrictedMode And(Name<>FileName)Then Begin
  SetStatus(LText('Nom interdit en mode restreint',
  'Filename forbidden in restricted mode'));
  Exit;
 End;
 If BackupEnabled Then Begin
  FindFirst(Name,AnyFile,SearchRecord);
  If DosError=0 Then Begin
   BackupFile:=BackupName(Name);
   CopyFileText(Name,BackupFile);
  End;
 End;
 Assign(Destination,Name);
  {$I-}Rewrite(Destination);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
  SetStatus(LText('Impossible d''ecrire le fichier','Cannot write file')+' '+Name);
  Exit;
 End;
 Node:=FirstLine;
 While Node<>Nil Do Begin
  If NoFinalNewline And(Node^.Next=Nil)Then Write(Destination,Node^.Text)
  Else WriteLn(Destination,Node^.Text);
  Node:=Node^.Next;
 End;
  {$I-}Close(Destination);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
  SetStatus(LText('Erreur durant l''ecriture','Write error'));Exit;
 End;
 FileName:=Name;
 Modified:=False;
 SetStatus(LText('Ecrit','Wrote')+' '+Name);
End;

Procedure LoadTextFile(Const Name:TText);
Var
 Source:Text;
 SourceLine:TText;
 NewNode:PLine;
 ErrorCode:Integer;
Begin
 FileLoadOK:=False;
 Assign(Source,Name);
  {$I-}Reset(Source);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
  SetStatus(LText('Impossible de lire','Cannot read')+' '+Name);
  Exit;
 End;
 FreeBuffer;
 While Not EOF(Source)Do Begin
  ReadLn(Source,SourceLine);
  InsertNodeAfter(LastLine,SourceLine,NewNode);
 End;
 Close(Source);
 FileName:=Name;
 Modified:=False;
 If LineCount>0 Then Begin
  SetCurrentLine(StartLine);
  CursorColumn:=StartColumn-1;
  If CursorColumn>Length(CurrentLine^.Text)Then CursorColumn:=Length(CurrentLine^.Text);
 End;
 FileLoadOK:=True;
 SetStatus(LText('Fichier lu','Read file')+' '+Name);
End;

Procedure SavePrompt;
Var
 Name:TText;
 Cancelled:Boolean;
Begin
 ReadPrompt(LText('Nom du fichier a ecrire: ','File Name to Write: '),FileName,Name,
 Cancelled);
 If Not Cancelled Then SaveTextFile(Name);
End;

Procedure ReadPromptFile;
Var
 Name:TText;
 Cancelled:Boolean;
 Source:Text;
 SourceLine:TText;
 NewNode,InsertNode:PLine;
 ErrorCode:Integer;
Begin
 ReadPrompt(LText('Fichier a inserer: ','File to Insert: '),'',Name,Cancelled);
 If Cancelled Or(Name='')Then Exit;
 If RestrictedMode Then Begin
  SetStatus(LText('Lecture interdite en mode restreint',
  'Read forbidden in restricted mode'));
  Exit;
 End;
 Assign(Source,Name);
  {$I-}Reset(Source);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
  SetStatus(LText('Fichier introuvable','File not found'));Exit;
 End;
 InsertNode:=CurrentLine;
 While Not EOF(Source)Do Begin
  ReadLn(Source,SourceLine);
  InsertNodeAfter(InsertNode,SourceLine,NewNode);
  InsertNode:=NewNode;
 End;
 Close(Source);
 If CurrentLine=Nil Then Begin
  CurrentLine:=FirstLine;
  CurrentLineNumber:=1;
  CursorColumn:=0;
 End;
 Modified:=True;
 SetStatus(LText('Fichier insere','File inserted'));
End;

Procedure ExitEditor;
Var
 Key:Char;
Begin
 If Not Modified Then Begin
  If CurrentFileIndex<FileCount Then Begin
   Inc(CurrentFileIndex);
   FileName:=FileNames[CurrentFileIndex];
   FreeBuffer;
   StartLine:=1;StartColumn:=1;
   LoadTextFile(FileName);
  End Else QuitRequested:=True;
  Exit;
 End;
 If TempFile And(FileName<>'')Then Begin
  SaveTextFile(FileName);
  If Modified Then Exit;
  If CurrentFileIndex<FileCount Then Begin
   Inc(CurrentFileIndex);
   FileName:=FileNames[CurrentFileIndex];
   FreeBuffer;
   StartLine:=1;StartColumn:=1;
   LoadTextFile(FileName);
  End Else QuitRequested:=True;
  Exit;
 End;
 GotoXY(1,StatusRow);
  TextBackground(Magenta);TextColor(White);ClrEol;
 Write(LText('Enregistrer les modifications? (O)ui/(N)on/(A)nnuler: ',
 'Save modified buffer? (Y)es/(N)o/(C)ancel: '));
 Key:=UpCase(ReadKey);
 If(Key='Y')Or(Key='O')Then Begin
  If FileName=''Then SavePrompt Else SaveTextFile(FileName);
  If Not Modified Then Begin
   If CurrentFileIndex<FileCount Then Begin
    Inc(CurrentFileIndex);FileName:=FileNames[CurrentFileIndex];
    FreeBuffer;StartLine:=1;StartColumn:=1;LoadTextFile(FileName);
   End Else QuitRequested:=True;
  End;
 End Else If Key='N'Then Begin
  If CurrentFileIndex<FileCount Then Begin
   Inc(CurrentFileIndex);FileName:=FileNames[CurrentFileIndex];
   FreeBuffer;StartLine:=1;StartColumn:=1;LoadTextFile(FileName);
  End Else QuitRequested:=True;
 End Else StatusMessage:='';
End;

Procedure ShowHelp;
Var
 Key:Char;
Begin
 ClrScr;TextBackground(Magenta);TextColor(White);GotoXY(1,2);
 WriteLn('GNU nano - ',LText('Aide','Help'));WriteLn;
 WriteLn('^G  ',LText('Afficher cette aide','Display this help'));
 WriteLn('^O  ',LText('Ecrire le fichier','Write Out'));
 WriteLn('^R  ',LText('Inserer un fichier','Read File'));
 WriteLn('^W  ',LText('Chercher du texte','Where Is'));
 WriteLn('^K  ',LText('Couper du texte','Cut Text'));
 WriteLn('^U  ',LText('Coller du texte','Uncut Text'));
 WriteLn('^X  ',LText('Quitter','Exit'));WriteLn;
 WriteLn(LText('Fleches: deplacer le curseur','Arrow keys: move cursor'));
 WriteLn('Backspace/Delete: ',LText('effacer','delete'));
 GotoXY(1,ShortcutRow);ClrEol;
 Write(LText('Appuyez sur une touche pour revenir','Press any key to return'));
 Key:=ReadKey;StatusMessage:='';
End;

Procedure HandleControlKey(Key:Char);
Var
 Spaces,Index:Integer;
Begin
 Case Ord(Key)Of
 7:ShowHelp;
  3:Begin
   ConstantPosition:=Not ConstantPosition;
   If ConstantPosition Then SetStatus(LText('Position du curseur affichee','Constant cursor position enabled'))
   Else SetStatus(LText('Position du curseur masquee','Constant cursor position disabled'));
  End;
 11:CutCurrentLine;
 14:MoveVertical(1);
 15:SavePrompt;
 18:ReadPromptFile;
 19:SavePrompt;
 21:PasteCutText;
 22:MoveVertical(VisibleTextRows);
 23:SearchText;
 24:ExitEditor;
 25:MoveVertical(-VisibleTextRows);
 13:InsertNewLine;
  10:JustifyCurrentLine;
 8:BackspaceCharacter;
 9:
 Begin
  If ConvertTabs Then Spaces:=TabSize-(CursorColumn Mod TabSize)
                 Else Spaces:=1;
  If ConvertTabs Then
  For Index:=1 To Spaces Do InsertCharacter(' ')
  Else InsertCharacter(#9);
 End;
 17:If PreserveKeys Then InsertCharacter(Key);
  20:SetStatus(LText('Correcteur orthographique non integre',
                    'No spell checker is built in'));
End;
End;

Procedure HandleExtendedKey;
Var
 Key:Char;
Begin
 Key:=ReadKey;
 Case Ord(Key)Of
 71:MoveHome;
 72:MoveVertical(-1);
 75:MoveLeft;
 77:MoveRight;
 79:If CurrentLine<>Nil Then CursorColumn:=Length(CurrentLine^.Text);
 80:MoveVertical(1);
 73:MoveVertical(-VisibleTextRows);
 81:MoveVertical(VisibleTextRows);
 83:DeleteCharacter;
End;
End;

Function ParseNumber(Const Value:TText; Var ResultValue:Integer):Boolean;
Var
 ErrorCode:Integer;
 Parsed:Integer;
Begin
 Val(Value,Parsed,ErrorCode);
 ParseNumber:=ErrorCode=0;
 If ErrorCode=0 Then ResultValue:=Parsed;
End;

Procedure ParseStartLocation(Const Value:TText);
Var
 CommaPosition,Index:Integer;
 LineText,ColumnText:TText;
Begin
 StartLine:=1;StartColumn:=1;CommaPosition:=0;
 For Index:=1 To Length(Value)Do If Value[Index]=','Then CommaPosition:=Index;
 If CommaPosition=0 Then LineText:=Copy(Value,2,MaxTextLength)
  Else
 Begin
  LineText:=Copy(Value,2,CommaPosition-2);
  ColumnText:=Copy(Value,CommaPosition+1,MaxTextLength);
 End;
 If Not ParseNumber(LineText,StartLine)Then StartLine:=1;
 If(CommaPosition>0)And Not ParseNumber(ColumnText,StartColumn)Then StartColumn:=1;
 If StartLine<1 Then StartLine:=1;
 If StartColumn<1 Then StartColumn:=1;
End;

Procedure PrintHelp;Begin
 WriteLn('NANP - ',LText('Cette commande permet de lancer l''editeur de texte ASCII',
 'Text editor'));
 WriteLn;
 WriteLn(LText('Syntaxe: nano [OPTIONS] [[+LIGNE[,COLONNE]] FICHIER]...',
 'Usage: nano [OPTIONS] [[+LINE[,COLUMN]] FILE]...'));
 WriteLn;
 WriteLn(LText('Options principales:','Main options:'));
 WriteLn('  -A, --smarthome       -i, --autoindent');
 WriteLn('  -B, --backup          -C dir, --backupdir=dir');
 WriteLn('  -c, --const           -k, --cut');
 WriteLn('  -E, --tabstospaces    -F, --multibuffer');
 WriteLn('  -L, --nonewlines      -O, --morespace');
 WriteLn('  -R, --restricted      -T n, --tabsize=n');
 WriteLn('  -t, --tempfile        -v, --view');
 WriteLn('  -w, --nowrap          -x, --nohelp');
 WriteLn('  -h, --help            -V, --version');
 Flush(Output);
End;

Procedure OptionError(Const MessageText:TText);Begin
 WriteLn('nano: ',MessageText);
 Halt(2);
End;

Procedure AddFileName(Const Name:TText);Begin
 If FileCount>=MaxFiles Then OptionError(LText('Trop de fichiers','Too many files'));
 Inc(FileCount);
 FileNames[FileCount]:=Name;
End;

Procedure ParseArguments;
Var
 Index,NumericValue:Integer;
 ErrorCode:Integer;
 Arg,OptionValue:TText;
Begin
 FileCount:=0;CurrentFileIndex:=0;
 Index:=1;
 While Index<=ParamCount Do Begin
  Arg:=ParamStr(Index);
  If(Arg='--help')Or(Arg='-h')Or(Arg='/?')Then Begin
   PrintHelp;Halt(0);
  End
  Else If(Arg='--version')Or(Arg='-V')Then Begin
   WriteLn('GNU nano, version 1.0 (LINUX-0)');Halt(0);
  End
  Else If(Arg='+')Or((Length(Arg)>1)And(Arg[1]='+'))Then Begin
   ParseStartLocation(Arg);
  End Else If(Arg='-A')Or(Arg='--smarthome')Then SmartHome:=True
  Else If(Arg='-a')Or(Arg='-b')Or(Arg='-e')Or(Arg='-f')Or
  (Arg='-g')Or(Arg='-j')Then Begin
  End
  Else If(Arg='--autoindent')Or(Arg='-i')Then AutoIndent:=True
  Else If(Arg='-B')Or(Arg='--backup')Then BackupEnabled:=True
  Else If(Arg='--boldtext')Or(Arg='-D')Then BoldText:=True
  Else If(Arg='-c')Or(Arg='--const')Then ConstantPosition:=True
  Else If(Arg='--cut')Or(Arg='-k')Then CutToEnd:=True
  Else If(Arg='-d')Or(Arg='--rebinddelete')Then RebindDelete:=True
  Else If(Arg='-E')Or(Arg='--tabstospaces')Then ConvertTabs:=True
  Else If(Arg='-F')Or(Arg='--multibuffer')Then MultiBuffer:=True
  Else If(Arg='-H')Or(Arg='--historylog')Then HistoryLog:=True
  Else If(Arg='-I')Or(Arg='--ignorercfiles')Then Begin
  End
  Else If(Arg='-K')Or(Arg='--rebindkeypad')Then RebindKeypad:=True
  Else If(Arg='-L')Or(Arg='--nonewlines')Then NoFinalNewline:=True
  Else If(Arg='-l')Or(Arg='--nofollow')Then Begin
  End
  Else If(Arg='-m')Or(Arg='--mouse')Then MouseEnabled:=True
  Else If(Arg='--noconvert')Or(Arg='-N')Then NoConvert:=True
  Else If(Arg='--nohelp')Or(Arg='-x')Then NoHelp:=True
  Else If(Arg='--nowrap')Or(Arg='-w')Then NoWrap:=True
  Else If(Arg='-O')Or(Arg='--morespace')Then MoreSpace:=True
  Else If(Arg='-p')Or(Arg='--preserve')Then PreserveKeys:=True
  Else If(Arg='--quickblank')Or(Arg='-U')Then QuickBlank:=True
  Else If(Arg='-R')Or(Arg='--restricted')Then RestrictedMode:=True
  Else If(Arg='-S')Or(Arg='--smooth')Then SmoothScroll:=True
  Else If(Arg='--suspend')Or(Arg='-z')Then SuspendEnabled:=True
  Else If(Arg='-t')Or(Arg='--tempfile')Then TempFile:=True
  Else If(Arg='-v')Or(Arg='--view')Then ViewOnly:=True
  Else If(Arg='-W')Or(Arg='--wordbounds')Then WordBounds:=True
  Else If(Arg='-C')Or(Arg='-o')Or(Arg='--operatingdir')Then Begin
   Inc(Index);
   If Index>ParamCount Then OptionError(Arg+' '+LText('attend un repertoire',
   'requires a directory'));
   OptionValue:=ParamStr(Index);
   If Arg='-C'Then BackupDirectory:=OptionValue Else OperatingDirectory:=OptionValue;
  End Else If(Arg='-Q')Or(Arg='-s')Or(Arg='-Y')Then Begin
   Inc(Index);
   If Index>ParamCount Then OptionError(Arg+' '+LText('attend une valeur',
   'requires a value'));
   OptionValue:=ParamStr(Index);
   If Arg='-Q'Then QuoteString:=OptionValue
   Else If Arg='-s'Then SpellerProgram:=OptionValue Else SyntaxName:=OptionValue;
  End Else If(Arg='-r')Or(Arg='-T')Then Begin
   Inc(Index);
   If Index>ParamCount Then OptionError(Arg+' '+LText('attend un nombre',
   'requires a number'));
   OptionValue:=ParamStr(Index);
   If Not ParseNumber(OptionValue,NumericValue)Then OptionError(LText('Nombre invalide',
   'Invalid number'));
   If Arg='-T'Then TabSize:=NumericValue Else FillColumn:=NumericValue;
  End Else If Copy(Arg,1,15)='--operatingdir='Then OperatingDirectory:=Copy(Arg,16,
  MaxTextLength)
  Else If Copy(Arg,1,12)='--backupdir='Then BackupDirectory:=Copy(Arg,13,MaxTextLength)
  Else If Copy(Arg,1,8)='--fill='Then Begin
   OptionValue:=Copy(Arg,9,MaxTextLength);
   If Not ParseNumber(OptionValue,FillColumn)Then OptionError(LText('Colonne invalide',
   'Invalid column'));
  End Else If Copy(Arg,1,10)='--tabsize='Then Begin
   OptionValue:=Copy(Arg,11,MaxTextLength);
   If Not ParseNumber(OptionValue,TabSize)Then OptionError(LText(
   'Taille de tabulation invalide','Invalid tab size'));
  End Else If Copy(Arg,1,11)='--quotestr='Then QuoteString:=Copy(Arg,12,MaxTextLength)
  Else If Copy(Arg,1,10)='--speller='Then SpellerProgram:=Copy(Arg,11,MaxTextLength)
  Else If Copy(Arg,1,9)='--syntax='Then SyntaxName:=Copy(Arg,10,MaxTextLength)
  Else If(Length(Arg)>1)And(Arg[1]='-')Then OptionError(LText('Option inconnue: ',
  'Unknown option: ')+Arg)
  Else AddFileName(Arg);
  Inc(Index);
 End;
 If TabSize<1 Then TabSize:=8;
 If TabSize>MaxTabSize Then TabSize:=MaxTabSize;
 If FillColumn<0 Then FillColumn:=0;
 If OperatingDirectory<>''Then Begin
  If RestrictedMode Then OptionError(LText('Option interdite en mode restreint',
  'Option forbidden in restricted mode'));
    {$I-}ChDir(OperatingDirectory);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then OptionError(LText('Repertoire invalide',
  'Invalid operating directory'));
 End;
 If RestrictedMode Then Begin
  If FileCount>1 Then OptionError(LText('Plusieurs fichiers interdits en mode restreint',
  'Multiple files forbidden in restricted mode'));
  If BackupEnabled Then OptionError(LText('Sauvegarde interdite en mode restreint',
  'Backup forbidden in restricted mode'));
 End;
End;

Var
 Key:Char;
 SearchRecord:SearchRec;
 EnvLanguage:String[20];
 FileExists:Boolean;

BEGIN
 FirstLine:=Nil;LastLine:=Nil;CurrentLine:=Nil;
 LineCount:=0;CurrentLineNumber:=0;TopLine:=1;
 CursorColumn:=0;LeftColumn:=0;
 VisibleTextRows:=DefaultTextRows;
 FileName:='';StatusMessage:='';CutText:='';
 Modified:=False;QuitRequested:=False;
 FileLoadOK:=False;
 SmartHome:=False;AutoIndent:=False;BackupEnabled:=False;
 BoldText:=False;ConstantPosition:=False;CutToEnd:=False;
 ConvertTabs:=False;MultiBuffer:=False;NoConvert:=False;
 NoFinalNewline:=False;NoHelp:=False;NoWrap:=False;MoreSpace:=False;
 PreserveKeys:=False;QuickBlank:=False;RestrictedMode:=False;
 SmoothScroll:=False;SuspendEnabled:=False;TempFile:=False;
 ViewOnly:=False;WordBounds:=False;MouseEnabled:=False;
 RebindDelete:=False;RebindKeypad:=False;HistoryLog:=False;
 BackupDirectory:='';OperatingDirectory:='';QuoteString:='"';
 SpellerProgram:='';SyntaxName:='';TabSize:=8;FillColumn:=0;
 StartLine:=1;StartColumn:=1;
 EnvLanguage:=GetEnv('LANGUAGE');
 English:=Copy(EnvLanguage,1,2)='EN';
 ParseArguments;
 If MoreSpace Then VisibleTextRows:=DefaultTextRows+1;
 If FileCount>0 Then Begin
  CurrentFileIndex:=1;
  FileName:=FileNames[1];
  FindFirst(FileName,AnyFile,SearchRecord);
  FileExists:=DosError=0;
  If FileExists Then Begin
   If(SearchRecord.Attr And Directory)<>0 Then Begin
    WriteLn('nano: ',LText('le nom indique est un repertoire','filename is a directory'));
    Halt(2);
   End;
   LoadTextFile(FileName);
   If Not FileLoadOK Then Begin
    WriteLn('nano: ',StatusMessage);Halt(1);
   End;
  End Else
  Begin
   If RestrictedMode Then Begin
    WriteLn('nano: ',LText('fichier interdit en mode restreint',
    'file forbidden in restricted mode'));Halt(2);
   End;
   StatusMessage:=LText('Nouveau fichier','New file');
  End;
 End Else StatusMessage:=LText('Nouveau fichier','New file');
 TextBackground(Black);TextColor(LightGray);ClrScr;
 Repeat
 DrawEditor;
 StatusMessage:='';
 Key:=ReadKey;
 If Key=#0 Then HandleExtendedKey Else
 If Ord(Key)<32 Then HandleControlKey(Key) Else
 If Ord(Key)<127 Then InsertCharacter(Key);
 Until QuitRequested;
 TextBackground(Black);TextColor(LightGray);ClrScr;
 FreeBuffer;
END.
