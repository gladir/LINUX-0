{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program EMACS(Input,Output);

Uses DOS,CRT;

Const
 ScreenColumns=80;
 FirstTextRow=2;
 TextRows=22;
 StatusRow=24;
 ShortcutRow=25;
 MaxTextLength=255;

Type
 TText=String[MaxTextLength];
 TFileName=String[127];
 PLine=^TLine;
 TLine=Record
  Text:TText;
  Previous,Next:PLine;
 End;

Var
 FirstLine,LastLine,CurrentLine:PLine;
 LineCount,CurrentLineNumber,TopLine:LongInt;
 CursorColumn,LeftColumn:Integer;
 FileName,StatusMessage,KillText,LastSearch:TText;
 LanguageText:TText;
 Modified,English,QuitRequested:Boolean;
 Argument:TFileName;
 Key:Char;
 Index:Integer;
 HelpRequested:Boolean;

Function LText(FrenchText,EnglishText:TText):TText;
Begin
 If English Then LText:=EnglishText Else LText:=FrenchText;
End;

Function LineAt(Number:LongInt):PLine;
Var
 Node:PLine;
 Index:LongInt;
Begin
 LineAt:=Nil;
 If(Number<1)Or(Number>LineCount)Then Exit;
 Node:=FirstLine;
 For Index:=1 To Number-1 Do Node:=Node^.Next;
 LineAt:=Node;
End;

Procedure InsertLineAfter(PreviousLine:PLine;Const Value:TText;
                          Var NewLine:PLine);
Begin
 New(NewLine);
 NewLine^.Text:=Value;
 If PreviousLine=Nil Then Begin
  NewLine^.Previous:=Nil;
  NewLine^.Next:=FirstLine;
  If FirstLine<>Nil Then FirstLine^.Previous:=NewLine
                    Else LastLine:=NewLine;
  FirstLine:=NewLine;
 End Else Begin
  NewLine^.Previous:=PreviousLine;
  NewLine^.Next:=PreviousLine^.Next;
  If PreviousLine^.Next<>Nil Then PreviousLine^.Next^.Previous:=NewLine
                             Else LastLine:=NewLine;
  PreviousLine^.Next:=NewLine;
 End;
 Inc(LineCount);
End;

Procedure RemoveLine(Node:PLine);
Begin
 If Node=Nil Then Exit;
 If Node^.Previous<>Nil Then Node^.Previous^.Next:=Node^.Next
                        Else FirstLine:=Node^.Next;
 If Node^.Next<>Nil Then Node^.Next^.Previous:=Node^.Previous
                     Else LastLine:=Node^.Previous;
 Dispose(Node);
 Dec(LineCount);
End;

Procedure ClearBuffer;
Begin
 While FirstLine<>Nil Do RemoveLine(FirstLine);
 CurrentLine:=Nil;
 CurrentLineNumber:=0;
 LineCount:=0;
 CursorColumn:=0;
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
 CurrentLine:=LineAt(Number);
 If CursorColumn>Length(CurrentLine^.Text)Then
  CursorColumn:=Length(CurrentLine^.Text);
End;

Procedure SetStatus(Const MessageText:TText);
Begin
 StatusMessage:=MessageText;
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
 RowIndex,ScreenRow,CursorX,CursorY:Integer;
 Title:TText;
Begin
 EnsureCursorVisible;
 TextBackground(Blue);
 TextColor(White);
 GotoXY(1,1);
 ClrEol;
 If FileName=''Then Title:=' GNU Emacs  *scratch*'
                 Else Title:=' GNU Emacs  '+FileName;
 If Modified Then Title:=Title+' *';
 Write(Copy(Title,1,ScreenColumns));
 TextBackground(Black);
 TextColor(LightGray);
 Node:=LineAt(TopLine);
 For RowIndex:=0 To TextRows-1 Do Begin
  ScreenRow:=FirstTextRow+RowIndex;
  GotoXY(1,ScreenRow);
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
  Write(CurrentLineNumber,'/',LineCount,'  ',
        LText('Colonne ','Column '),CursorColumn+1)
 Else Write(LText('Tampon vide','Empty buffer'));
 GotoXY(1,ShortcutRow);
 ClrEol;
 Write('^X^S ',LText('Ecrire','Save'),'  ^X^C ',
   LText('Quitter','Quit'),'  F7/^S ',LText('Chercher','Search'),
       '  ^K ',LText('Couper','Kill'),'  ^Y ',LText('Coller','Yank'));
 TextBackground(Black);
 TextColor(LightGray);
 If CurrentLineNumber>0 Then Begin
  CursorY:=CurrentLineNumber-TopLine+FirstTextRow;
  CursorX:=CursorColumn-LeftColumn+1;
  If CursorY<FirstTextRow Then CursorY:=FirstTextRow;
  If CursorY>FirstTextRow+TextRows-1 Then
   CursorY:=FirstTextRow+TextRows-1;
  If CursorX<1 Then CursorX:=1;
  If CursorX>ScreenColumns Then CursorX:=ScreenColumns;
  GotoXY(CursorX,CursorY);
 End Else GotoXY(1,FirstTextRow);
End;

Procedure InsertCharacter(Character:Char);
Var
 NewLine:PLine;
Begin
 If CurrentLine=Nil Then Begin
  InsertLineAfter(Nil,'',NewLine);
  CurrentLine:=NewLine;
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
 StatusMessage:='';
End;

Procedure InsertNewLine;
Var
 NewLine:PLine;
 Remainder:TText;
Begin
 If CurrentLine=Nil Then Begin
  InsertLineAfter(Nil,'',NewLine);
  CurrentLine:=NewLine;
  CurrentLineNumber:=1;
  CursorColumn:=0;
  Modified:=True;
  Exit;
 End;
 Remainder:=Copy(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
 Delete(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
 InsertLineAfter(CurrentLine,Remainder,NewLine);
 CurrentLine:=NewLine;
 Inc(CurrentLineNumber);
 CursorColumn:=0;
 Modified:=True;
 StatusMessage:='';
End;

Procedure BackspaceCharacter;
Var
 PreviousLine:PLine;
Begin
 If CurrentLine=Nil Then Exit;
 If CursorColumn>0 Then Begin
  Delete(CurrentLine^.Text,CursorColumn,1);
  Dec(CursorColumn);
  Modified:=True;
 End Else If CurrentLine^.Previous<>Nil Then Begin
  PreviousLine:=CurrentLine^.Previous;
  If Length(PreviousLine^.Text)+Length(CurrentLine^.Text)<=MaxTextLength Then Begin
   CursorColumn:=Length(PreviousLine^.Text);
   PreviousLine^.Text:=PreviousLine^.Text+CurrentLine^.Text;
   RemoveLine(CurrentLine);
   CurrentLine:=PreviousLine;
   Dec(CurrentLineNumber);
   Modified:=True;
  End Else SetStatus(LText('Ligne precedente trop longue',
                           'Previous line is too long'));
 End;
End;

Procedure DeleteCharacter;
Var
 NextLine:PLine;
Begin
 If CurrentLine=Nil Then Exit;
 If CursorColumn<Length(CurrentLine^.Text)Then Begin
  Delete(CurrentLine^.Text,CursorColumn+1,1);
  Modified:=True;
 End Else If CurrentLine^.Next<>Nil Then Begin
  NextLine:=CurrentLine^.Next;
  If Length(CurrentLine^.Text)+Length(NextLine^.Text)<=MaxTextLength Then Begin
   CurrentLine^.Text:=CurrentLine^.Text+NextLine^.Text;
   RemoveLine(NextLine);
   Modified:=True;
  End Else SetStatus(LText('Ligne suivante trop longue',
                           'Next line is too long'));
 End;
End;

Procedure MoveLeft;
Begin
 If CurrentLine=Nil Then Exit;
 If CursorColumn>0 Then Dec(CursorColumn)
 Else If CurrentLine^.Previous<>Nil Then Begin
  CurrentLine:=CurrentLine^.Previous;
  Dec(CurrentLineNumber);
  CursorColumn:=Length(CurrentLine^.Text);
 End;
End;

Procedure MoveRight;
Begin
 If CurrentLine=Nil Then Exit;
 If CursorColumn<Length(CurrentLine^.Text)Then Inc(CursorColumn)
 Else If CurrentLine^.Next<>Nil Then Begin
  CurrentLine:=CurrentLine^.Next;
  Inc(CurrentLineNumber);
  CursorColumn:=0;
 End;
End;

Function FindInLine(Const SourceText,SearchText:TText;
                    StartAt,Direction:Integer):Integer;
Var
 Position,PatternIndex,LastPosition:Integer;
 Matches:Boolean;
Begin
 FindInLine:=0;
 If SearchText=''Then Exit;
 LastPosition:=Length(SourceText)-Length(SearchText)+1;
 If Direction>0 Then Begin
  If StartAt<1 Then StartAt:=1;
  Position:=StartAt;
  While Position<=LastPosition Do Begin
   Matches:=True;
   For PatternIndex:=1 To Length(SearchText)Do
    If SourceText[Position+PatternIndex-1]<>SearchText[PatternIndex]Then
     Matches:=False;
   If Matches Then Begin FindInLine:=Position;Exit;End;
   Inc(Position);
  End;
 End Else Begin
  If StartAt>LastPosition Then StartAt:=LastPosition;
  Position:=StartAt;
  While Position>=1 Do Begin
   Matches:=True;
   For PatternIndex:=1 To Length(SearchText)Do
    If SourceText[Position+PatternIndex-1]<>SearchText[PatternIndex]Then
     Matches:=False;
   If Matches Then Begin FindInLine:=Position;Exit;End;
   Dec(Position);
  End;
 End;
End;

Procedure SearchFrom(StartLine:PLine;StartNumber:LongInt;StartColumn:Integer;
                     Const SearchValue:TText;Direction:Integer;
                     Var Found:Boolean);
Var
 SearchNode:PLine;
 SearchNumber:LongInt;
 FoundAt,StartAt:Integer;
Begin
 Found:=False;
 If(SearchValue='')Or(StartLine=Nil)Then Exit;
 SearchNode:=StartLine;
 SearchNumber:=StartNumber;
 While SearchNode<>Nil Do Begin
  If SearchNode=StartLine Then Begin
   If Direction>0 Then StartAt:=StartColumn+1
   Else StartAt:=StartColumn-Length(SearchValue)+1;
  End Else If Direction>0 Then StartAt:=1
  Else StartAt:=MaxTextLength;
  FoundAt:=FindInLine(SearchNode^.Text,SearchValue,StartAt,Direction);
  If FoundAt>0 Then Begin
   CurrentLine:=SearchNode;
   CurrentLineNumber:=SearchNumber;
   CursorColumn:=FoundAt-1;
   Found:=True;
   Exit;
  End;
  If Direction>0 Then Begin
   SearchNode:=SearchNode^.Next;
   Inc(SearchNumber);
  End Else Begin
   SearchNode:=SearchNode^.Previous;
   Dec(SearchNumber);
  End;
 End;
End;

Procedure ReadPrompt(Const PromptText,DefaultText:TText;
                     Var ResultText:TText;Var Cancelled:Boolean);
Var
 Key:Char;
 PromptLength:Integer;
Begin
 ResultText:=DefaultText;
 Cancelled:=False;
 PromptLength:=Length(PromptText);
 Repeat
  TextBackground(Blue);
  TextColor(White);
  GotoXY(1,StatusRow);
  ClrEol;
  Write(PromptText,ResultText);
  If PromptLength+Length(ResultText)+1>ScreenColumns Then
   GotoXY(ScreenColumns,StatusRow)
  Else GotoXY(PromptLength+Length(ResultText)+1,StatusRow);
  Key:=ReadKey;
  If(Key=#27)Or(Key=#7)Then Cancelled:=True
  Else If Key=#13 Then Exit
  Else If Key=#8 Then Begin
   If ResultText<>''Then Delete(ResultText,Length(ResultText),1);
  End Else If Key=#0 Then Key:=ReadKey
  Else If(Ord(Key)>=32)And(Length(ResultText)<MaxTextLength)Then
   ResultText:=ResultText+Key;
 Until Cancelled;
End;

Procedure SearchText(Direction:Integer);
Var
 SearchTextValue:TText;
 PromptText:TText;
 Cancelled,Found,QueryChanged:Boolean;
 BaseLine,StartLine,LastGoodLine:PLine;
 BaseNumber,StartNumber,LastGoodNumber:LongInt;
 BaseColumn,StartColumn,LastGoodColumn,PromptLength:Integer;
 Key:Char;
Begin
 SearchTextValue:=LastSearch;
 BaseLine:=CurrentLine;
 BaseNumber:=CurrentLineNumber;
 BaseColumn:=CursorColumn;
 StartLine:=BaseLine;
 StartNumber:=BaseNumber;
 StartColumn:=BaseColumn;
 LastGoodLine:=BaseLine;
 LastGoodNumber:=BaseNumber;
 LastGoodColumn:=BaseColumn;
 Found:=False;
 Cancelled:=False;
 If SearchTextValue<>''Then Begin
  If Direction>0 Then Inc(StartColumn);
  SearchFrom(StartLine,StartNumber,StartColumn,SearchTextValue,
             Direction,Found);
  If Found Then Begin
   LastGoodLine:=CurrentLine;
   LastGoodNumber:=CurrentLineNumber;
   LastGoodColumn:=CursorColumn;
  End Else Begin
   CurrentLine:=LastGoodLine;
   CurrentLineNumber:=LastGoodNumber;
   CursorColumn:=LastGoodColumn;
  End;
 End;
 Repeat
  DrawEditor;
  If Found Or(SearchTextValue='')Then
   PromptText:=LText('Recherche: ','I-search: ')
  Else PromptText:=LText('Echec recherche: ','Failing I-search: ');
  PromptLength:=Length(PromptText);
  TextBackground(Blue);
  TextColor(White);
  GotoXY(1,StatusRow);
  ClrEol;
  Write(PromptText,SearchTextValue);
  If PromptLength+Length(SearchTextValue)+1>ScreenColumns Then
   GotoXY(ScreenColumns,StatusRow)
  Else GotoXY(PromptLength+Length(SearchTextValue)+1,StatusRow);
  Key:=ReadKey;
  QueryChanged:=False;
  If(Key=#27)Or(Key=#7)Then Cancelled:=True
  Else If Key=#13 Then Break
  Else If Key=#8 Then Begin
   If SearchTextValue<>''Then Begin
    Delete(SearchTextValue,Length(SearchTextValue),1);
    QueryChanged:=True;
   End;
  End Else If Key=#0 Then Key:=ReadKey
  Else If(Key=#19)Or(Ord(Key)=31)Then Begin
   If SearchTextValue<>''Then Begin
    StartLine:=CurrentLine;
    StartNumber:=CurrentLineNumber;
    StartColumn:=CursorColumn+1;
    SearchFrom(StartLine,StartNumber,StartColumn,SearchTextValue,
               Direction,Found);
    If Found Then Begin
     LastGoodLine:=CurrentLine;
     LastGoodNumber:=CurrentLineNumber;
     LastGoodColumn:=CursorColumn;
    End Else Begin
     CurrentLine:=LastGoodLine;
     CurrentLineNumber:=LastGoodNumber;
     CursorColumn:=LastGoodColumn;
    End;
   End;
  End Else If(Ord(Key)>=32)And
              (Length(SearchTextValue)<MaxTextLength)Then Begin
   SearchTextValue:=SearchTextValue+Key;
   QueryChanged:=True;
  End;
  If QueryChanged Then Begin
   If SearchTextValue=''Then Begin
    CurrentLine:=BaseLine;
    CurrentLineNumber:=BaseNumber;
    CursorColumn:=BaseColumn;
    LastGoodLine:=BaseLine;
    LastGoodNumber:=BaseNumber;
    LastGoodColumn:=BaseColumn;
    Found:=False;
   End Else Begin
    StartLine:=BaseLine;
    StartNumber:=BaseNumber;
    StartColumn:=BaseColumn;
    SearchFrom(StartLine,StartNumber,StartColumn,SearchTextValue,
               Direction,Found);
    If Found Then Begin
     LastGoodLine:=CurrentLine;
     LastGoodNumber:=CurrentLineNumber;
     LastGoodColumn:=CursorColumn;
    End Else Begin
     CurrentLine:=LastGoodLine;
     CurrentLineNumber:=LastGoodNumber;
     CursorColumn:=LastGoodColumn;
    End;
   End;
  End;
 Until Cancelled;
 If Cancelled Then Begin
  CurrentLine:=BaseLine;
  CurrentLineNumber:=BaseNumber;
  CursorColumn:=BaseColumn;
  SetStatus(LText('Recherche annulee','Search cancelled'));
 End Else Begin
  LastSearch:=SearchTextValue;
  If Found Then SetStatus(LText('Texte trouve','Search string found'))
  Else If SearchTextValue<>''Then
   SetStatus(LText('Texte introuvable','Search string not found'))
  Else StatusMessage:='';
 End;
End;

Procedure SaveTextFile(Const Name:TFileName);
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
  WriteLn(Destination,Node^.Text);
  Node:=Node^.Next;
 End;
 {$I-}Close(Destination);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
  SetStatus(LText('Erreur durant l''ecriture','Write error'));
  Exit;
 End;
 FileName:=Name;
 Modified:=False;
 SetStatus(LText('Fichier ecrit: ','Wrote file: ')+Name);
End;

Procedure LoadTextFile(Const Name:TFileName);
Var
 Source:Text;
 SourceLine:TText;
 NewLine:PLine;
 ErrorCode:Integer;
Begin
 Assign(Source,Name);
 {$I-}Reset(Source);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
  SetStatus(LText('Impossible de lire le fichier: ',
                  'Cannot read file: ')+Name);
  Exit;
 End;
 ClearBuffer;
 While Not EOF(Source)Do Begin
  ReadLn(Source,SourceLine);
  InsertLineAfter(LastLine,SourceLine,NewLine);
 End;
 {$I-}Close(Source);{$I+}
 ErrorCode:=IOResult;
 If LineCount=0 Then Begin
  InsertLineAfter(Nil,'',NewLine);
  CurrentLine:=NewLine;
  CurrentLineNumber:=1;
 End Else Begin
  CurrentLine:=FirstLine;
  CurrentLineNumber:=1;
 End;
 CursorColumn:=0;
 FileName:=Name;
 Modified:=False;
 StatusMessage:='';
End;

Procedure SaveAs;
Var
 NameText:TText;
 Cancelled:Boolean;
Begin
 ReadPrompt(LText('Ecrire le fichier: ','Write file: '),FileName,
            NameText,Cancelled);
 If Not Cancelled Then SaveTextFile(NameText);
End;

Function SaveChanges:Boolean;Forward;

Procedure OpenFile;
Var
 NameText:TText;
 Cancelled:Boolean;
Begin
 ReadPrompt(LText('Ouvrir le fichier: ','Open file: '),FileName,
            NameText,Cancelled);
 If Cancelled Or(NameText='')Then Exit;
 If SaveChanges Then LoadTextFile(NameText);
End;

Function SaveChanges:Boolean;
Var
 Key:Char;
Begin
 SaveChanges:=True;
 If Not Modified Then Exit;
 SetStatus(LText('Enregistrer? (o/n/annuler)',
                 'Save changes? (y/n/cancel)'));
 DrawEditor;
 Repeat
  Key:=UpCase(ReadKey);
 Until(Key='O')Or(Key='Y')Or(Key='N')Or(Key=#27)Or(Key=#7);
 If(Key='N')Then Exit;
 If(Key=#27)Or(Key=#7)Then Begin SaveChanges:=False;Exit;End;
 If FileName=''Then SaveAs Else SaveTextFile(FileName);
 SaveChanges:=Not Modified;
End;

Procedure KillToEndOfLine;
Begin
 If CurrentLine=Nil Then Exit;
 KillText:=Copy(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
 If KillText<>''Then Begin
  Delete(CurrentLine^.Text,CursorColumn+1,MaxTextLength);
  Modified:=True;
  SetStatus(LText('Texte coupe','Text killed'));
 End;
End;

Procedure YankText;
Begin
 If(CurrentLine=Nil)Or(KillText='')Then Exit;
 If Length(CurrentLine^.Text)+Length(KillText)>MaxTextLength Then Begin
  SetStatus(LText('Texte trop long pour cette ligne',
                  'Text is too long for this line'));
  Exit;
 End;
 Insert(KillText,CurrentLine^.Text,CursorColumn+1);
 Inc(CursorColumn,Length(KillText));
 Modified:=True;
 StatusMessage:='';
End;

Procedure HandleExtendedKey(Key:Char);
Begin
 Case Ord(Key)Of
  72:If CurrentLineNumber>1 Then SetCurrentLine(CurrentLineNumber-1);
  80:If CurrentLineNumber<LineCount Then SetCurrentLine(CurrentLineNumber+1);
  75:MoveLeft;
  77:MoveRight;
  71:CursorColumn:=0;
  79:If CurrentLine<>Nil Then CursorColumn:=Length(CurrentLine^.Text);
  73:If CurrentLineNumber>1 Then
      SetCurrentLine(CurrentLineNumber-TextRows);
  81:If CurrentLineNumber<LineCount Then
      SetCurrentLine(CurrentLineNumber+TextRows);
  83:DeleteCharacter;
 End;
End;

Procedure HandleControlX;
Var
 Key:Char;
Begin
 Key:=ReadKey;
 Case Key Of
  #19:Key:='S';
  #23:Key:='W';
  #6:Key:='F';
  #3:Key:='C';
 Else Key:=UpCase(Key);
 End;
 Case Key Of
  'S':If FileName=''Then SaveAs Else SaveTextFile(FileName);
  'W':SaveAs;
  'F':OpenFile;
  'C':If SaveChanges Then QuitRequested:=True;
 Else SetStatus(LText('Commande C-x inconnue','Unknown C-x command'));
 End;
End;

Procedure ShowHelp;
Begin
 ClrScr;
 WriteLn('GNU Emacs - ',LText('editeur de texte','text editor'));
 WriteLn;
 WriteLn('C-x C-s  ',LText('Enregistrer','Save'));
 WriteLn('C-x C-w  ',LText('Enregistrer sous','Save as'));
 WriteLn('C-x C-f  ',LText('Ouvrir un fichier','Open a file'));
 WriteLn('C-x C-c  ',LText('Quitter','Quit'));
 WriteLn('C-s / C-r  ',LText('Rechercher avant / arriere',
                            'Search forward / backward'));
 WriteLn('F7  ',LText('Rechercher (raccourci alternatif)',
                     'Search (alternative shortcut)'));
 WriteLn('C-k / C-y  ',LText('Couper la fin de ligne / coller',
                            'Kill to end of line / yank'));
 WriteLn('C-a / C-e  ',LText('Debut / fin de ligne','Beginning / end of line'));
 WriteLn;
 Write(LText('Appuyez sur une touche pour continuer...',
             'Press any key to continue...'));
 ReadKey;
End;

Procedure ShowUsage;
Begin
 WriteLn('EMACS - ',LText('Cette commande permet d''utiliser un editeur de texte avec macros',
                       'text editor with macros'));
 WriteLn;
 WriteLn('Syntaxe: EMACS [--help] [fichier]');
 WriteLn;
 WriteLn(LText('Commandes: C-x C-s enregistrer, C-x C-c quitter,',
               'Commands: C-x C-s save, C-x C-c quit,'));
 WriteLn(LText('C-s rechercher, C-k couper, C-y coller.',
               'C-s search, C-k kill, C-y yank.'));
End;

Begin
 FirstLine:=Nil;
 LastLine:=Nil;
 CurrentLine:=Nil;
 LineCount:=0;
 CurrentLineNumber:=0;
 CursorColumn:=0;
 TopLine:=1;
 LeftColumn:=0;
 FileName:='';
 StatusMessage:='';
 KillText:='';
 LastSearch:='';
 Modified:=False;
 QuitRequested:=False;
 LanguageText:=GetEnv('LANGUAGE');
 English:=False;
 If Length(LanguageText)>=2 Then
  English:=(UpCase(LanguageText[1])='E')And
           (UpCase(LanguageText[2])='N');
 HelpRequested:=False;
 Argument:='';
 For Index:=1 To ParamCount Do Begin
  If(ParamStr(Index)='/?')Or(ParamStr(Index)='-h')Or
    (ParamStr(Index)='--help')Then HelpRequested:=True
  Else If(ParamStr(Index)='--version')Then Begin
   WriteLn('GNU Emacs clone - LINUX-0');
   Halt;
  End Else If(Argument='')Then Argument:=ParamStr(Index);
 End;
 If HelpRequested Then Begin ShowUsage;Halt;End;
 If Argument<>''Then LoadTextFile(Argument)
 Else Begin
  InsertLineAfter(Nil,'',CurrentLine);
  CurrentLineNumber:=1;
 End;
 ClrScr;
 Repeat
  DrawEditor;
  Key:=ReadKey;
  StatusMessage:='';
  If Key=#0 Then Begin
   Key:=ReadKey;
    If(Ord(Key)=31)Or(Ord(Key)=65)Then SearchText(1)
   Else HandleExtendedKey(Key);
  End
  Else Case Key Of
   #1:CursorColumn:=0;
   #5:If CurrentLine<>Nil Then CursorColumn:=Length(CurrentLine^.Text);
   #2:MoveLeft;
   #6:MoveRight;
   #14:If CurrentLineNumber<LineCount Then
        SetCurrentLine(CurrentLineNumber+1);
   #16:If CurrentLineNumber>1 Then
        SetCurrentLine(CurrentLineNumber-1);
   #7:SetStatus(LText('Annule','Cancelled'));
   #8:BackspaceCharacter;
   #11:KillToEndOfLine;
   #13:InsertNewLine;
   #19:SearchText(1);
   #18:SearchText(-1);
   #24:HandleControlX;
   #25:YankText;
   #4:DeleteCharacter;
   #9:Begin InsertCharacter(' ');InsertCharacter(' ');
        InsertCharacter(' ');InsertCharacter(' ');End;
   #27:ShowHelp;
  Else If Ord(Key)>=32 Then InsertCharacter(Key);
  End;
 Until QuitRequested;
 ClrScr;
 ClearBuffer;
End.