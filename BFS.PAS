{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program BFS(Input,Output);

Uses DOS;

Const
  MaxCommandLength=255;

Var
  TextFile:Text;
  BinaryFile:File;
  FileName,CommandLine,OutputLine:String;
  LineCount,CurrentLine,FileBytes:LongInt;
  CommandPosition,ErrorCode:Integer;
  SuppressSize,QuitRequested:Boolean;

Function TrimText(S:String):String;
Var
  First,Last:Integer;
Begin
  First:=1;
  Last:=Length(S);
  While(First<=Last)and(S[First]in[' ',#9])Do Inc(First);
  While(Last>=First)and(S[Last]in[' ',#9])Do Dec(Last);
  TrimText:=Copy(S,First,Last-First+1);
End;

Function IntString(Value:LongInt):String;
Var
  S:String;
Begin
  Str(Value,S);
  IntString:=S;
End;

Procedure CountFile;
Begin
  LineCount:=0;
  {$I-}Assign(TextFile,FileName);
  Reset(TextFile);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire ',FileName);
    Halt(1);
  End;
  While Not EOF(TextFile)Do Begin
    ReadLn(TextFile);
    Inc(LineCount);
  End;
  Close(TextFile);
  Assign(BinaryFile,FileName);
  {$I-}Reset(BinaryFile,1);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de mesurer ',FileName);
    Halt(1);
  End;
  FileBytes:=FileSize(BinaryFile);
  Close(BinaryFile);
End;

Function ReadLineAt(Target:LongInt; Var S:String):Boolean;
Var
  Source:Text;
  Number:LongInt;
Begin
  ReadLineAt:=False;
  If(Target<1)or(Target>LineCount)Then Exit;
  {$I-}Assign(Source,FileName);
  Reset(Source);{$I+}
  If IOResult<>0 Then Exit;
  Number:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,S);
    Inc(Number);
    If Number=Target Then Begin
      ReadLineAt:=True;
      Break;
    End;
  End;
  Close(Source);
End;

Procedure PrintLines(FirstLine,LastLine:LongInt; Numbered:Boolean);
Var
  Source:Text;
  Number:LongInt;
  S:String;
Begin
  If FirstLine<1 Then FirstLine:=1;
  If LastLine>LineCount Then LastLine:=LineCount;
  If FirstLine>LastLine Then Exit;
  {$I-}Assign(Source,FileName);
  Reset(Source);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de relire ',FileName);
    Exit;
  End;
  Number:=0;
  While(Not EOF(Source))and(Number<LastLine)Do Begin
    ReadLn(Source,S);
    Inc(Number);
    If Number>=FirstLine Then Begin
      If Numbered Then Write(Number:6,'  ');
      WriteLn(S);
      CurrentLine:=Number;
    End;
  End;
  Close(Source);
End;

Function FindForward(Const Needle:String; StartLine:LongInt;
                     Var FoundLine:LongInt):Boolean;
Var
  Source:Text;
  S:String;
  Number:LongInt;
Begin
  FindForward:=False;
  {$I-}Assign(Source,FileName);
  Reset(Source);{$I+}
  If IOResult<>0 Then Exit;
  Number:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,S);
    Inc(Number);
    If(Number>=StartLine)and(Pos(Needle,S)>0)Then Begin
      FoundLine:=Number;
      FindForward:=True;
      Break;
    End;
  End;
  Close(Source);
End;

Function FindBackward(Const Needle:String; StartLine:LongInt;
                      Var FoundLine:LongInt):Boolean;
Var
  Source:Text;
  S:String;
  Number:LongInt;
Begin
  FindBackward:=False;
  If StartLine>LineCount Then StartLine:=LineCount;
  {$I-}Assign(Source,FileName);
  Reset(Source);{$I+}
  If IOResult<>0 Then Exit;
  Number:=0;
  While(Not EOF(Source))and(Number<StartLine)Do Begin
    ReadLn(Source,S);
    Inc(Number);
    If Pos(Needle,S)>0 Then Begin
      FoundLine:=Number;
      FindBackward:=True;
    End;
  End;
  Close(Source);
End;

Function ReadAddress(Var Position:Integer; Var Value:LongInt):Boolean;
Var
  Start:Integer;
  S:String;
Begin
  ReadAddress:=False;
  While(Position<=Length(CommandLine))and(CommandLine[Position]=' ')Do Inc(Position);
  If Position>Length(CommandLine)Then Exit;
  If CommandLine[Position]='$'Then Begin
    Value:=LineCount;
    Inc(Position);
    ReadAddress:=True;
    Exit;
  End;
  Start:=Position;
  While(Position<=Length(CommandLine))and
    (CommandLine[Position]in['0'..'9'])Do Inc(Position);
  If Position=Start Then Exit;
  S:=Copy(CommandLine,Start,Position-Start);
  Val(S,Value,ErrorCode);
  ReadAddress:=ErrorCode=0;
End;

Procedure ShowHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('BFS : Browse a large text file interactively.');
    WriteLn('Syntax: bfs [-] filename');
    WriteLn('Commands: p print, n numbered print, = line number,');
    WriteLn('          /text/ forward search, ?text? backward search,');
    WriteLn('          g/text/p print every matching line, f filename, q quit.');
  End Else Begin
    WriteLn('BFS : Cette commande permet de parcourir interactivement un grand fichier texte.');
    WriteLn;
    WriteLn('Syntaxe : bfs [-] fichier');
    WriteLn;
    WriteLn('Commandes : p afficher, n afficher avec numero, = numero,');
    WriteLn('            /texte/ chercher avant, ?texte? chercher arriere,');
    WriteLn('            g/texte/p afficher les correspondances, f fichier, q quitter.');
  End;
End;

Procedure ExecuteCommand;
Var
  FirstAddress,SecondAddress,FoundLine,Start:LongInt;
  HasAddress,HasSecondAddress:Boolean;
  Operation,Delimiter:Char;
  S:String;
Begin
  CommandLine:=TrimText(CommandLine);
  If CommandLine=''Then Begin
    If CurrentLine<LineCount Then PrintLines(CurrentLine+1,CurrentLine+1,False);
    Exit;
  End;
  CommandPosition:=1;
  HasAddress:=ReadAddress(CommandPosition,FirstAddress);
  HasSecondAddress:=False;
  If HasAddress and(CommandPosition<=Length(CommandLine))and
    (CommandLine[CommandPosition]=',')Then Begin
    Inc(CommandPosition);
    HasSecondAddress:=ReadAddress(CommandPosition,SecondAddress);
    If Not HasSecondAddress Then SecondAddress:=LineCount;
  End;
  While(CommandPosition<=Length(CommandLine))and
    (CommandLine[CommandPosition]=' ')Do Inc(CommandPosition);
  If HasAddress Then Begin
    If Not HasSecondAddress Then SecondAddress:=FirstAddress;
    If CommandPosition>Length(CommandLine)Then Begin
      PrintLines(FirstAddress,SecondAddress,False);
      Exit;
    End;
  End Else Begin
    FirstAddress:=CurrentLine;
    SecondAddress:=CurrentLine;
  End;
  Operation:=CommandLine[CommandPosition];
  Inc(CommandPosition);
  Case Operation Of
    'p':Begin
      If Not HasAddress and(FirstAddress<1)Then Begin
        FirstAddress:=1;
        SecondAddress:=1;
      End;
      PrintLines(FirstAddress,SecondAddress,False);
    End;
    'n':Begin
      If Not HasAddress and(FirstAddress<1)Then Begin
        FirstAddress:=1;
        SecondAddress:=1;
      End;
      PrintLines(FirstAddress,SecondAddress,True);
    End;
    '=':Begin
      If Not HasAddress Then FirstAddress:=LineCount;
      WriteLn(FirstAddress);
    End;
    'f':WriteLn(FileName);
    'q','Q':QuitRequested:=True;
    'h':ShowHelp;
    '/','?':Begin
      Delimiter:=Operation;
      Start:=CommandPosition;
      While(CommandPosition<=Length(CommandLine))and
        (CommandLine[CommandPosition]<>Delimiter)Do Inc(CommandPosition);
      S:=Copy(CommandLine,Start,CommandPosition-Start);
      If S=''Then Begin
        WriteLn('?');
        Exit;
      End;
      If Operation='/'Then Begin
        If Not FindForward(S,CurrentLine+1,FoundLine)Then
          If Not FindForward(S,1,FoundLine)Then FoundLine:=0;
      End Else Begin
        If CurrentLine<=0 Then Start:=LineCount Else Start:=CurrentLine-1;
        If Not FindBackward(S,Start,FoundLine)Then FoundLine:=0;
      End;
      If FoundLine=0 Then WriteLn('?')
                     Else PrintLines(FoundLine,FoundLine,False);
    End;
    'g':Begin
      If(CommandPosition>Length(CommandLine))or
        Not(CommandLine[CommandPosition]in['/','?'])Then Begin
        WriteLn('?');
        Exit;
      End;
      Delimiter:=CommandLine[CommandPosition];
      Inc(CommandPosition);
      Start:=CommandPosition;
      While(CommandPosition<=Length(CommandLine))and
        (CommandLine[CommandPosition]<>Delimiter)Do Inc(CommandPosition);
      S:=Copy(CommandLine,Start,CommandPosition-Start);
      If S=''Then Begin
        WriteLn('?');
        Exit;
      End;
      For FoundLine:=1 to LineCount Do
        If ReadLineAt(FoundLine,OutputLine)and(Pos(S,OutputLine)>0)Then
          PrintLines(FoundLine,FoundLine,False);
    End;
    Else WriteLn('?');
  End;
End;

BEGIN
  FileName:='';
  SuppressSize:=False;
  If(ParamCount=1)and((ParamStr(1)='--help')or(ParamStr(1)='-h')or
    (ParamStr(1)='/?')or(ParamStr(1)='/h')or(ParamStr(1)='/H'))Then Begin
    ShowHelp;
    Halt(0);
  End;
  If(ParamCount=1)and((ParamStr(1)='--version')or(ParamStr(1)='-v'))Then Begin
    WriteLn('bfs (LINUX-0) 1.0');
    Halt(0);
  End;
  If ParamCount=1 Then FileName:=ParamStr(1) Else
  If ParamCount=2 Then Begin
    If ParamStr(1)='-'Then Begin
      SuppressSize:=True;
      FileName:=ParamStr(2);
    End Else Begin
      ShowHelp;
      Halt(2);
    End;
  End Else Begin
    ShowHelp;
    Halt(2);
  End;
  CountFile;
  If Not SuppressSize Then WriteLn(FileBytes,' bytes');
  CurrentLine:=0;
  QuitRequested:=False;
  While Not QuitRequested Do Begin
    Write('*');
    ReadLn(Input,CommandLine);
    ExecuteCommand;
  End;
END.
