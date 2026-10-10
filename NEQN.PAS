{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program NEQN(Input,Output);

Uses DOS;

Const
  MaxLineLength=255;

Type
  TLineText=String[MaxLineLength];

Var
  SourceFile:Text;
  SourceName:TLineText;
  InputLine,OutputLine,Token:TLineText;
  Position:Integer;
  InEquation,English:Boolean;
  LineNumber:LongInt;
  LanguageCode:String[20];

Procedure AppendText(Var Destination:TLineText; Const Piece:TLineText);
Var
  Available:Integer;
Begin
  Available:=MaxLineLength-Length(Destination);
  If Available<=0 Then Exit;
  If Length(Piece)<=Available Then Destination:=Destination+Piece
  Else Destination:=Destination+Copy(Piece,1,Available);
End;

Function LowerText(Const Value:TLineText):TLineText;
Var
  Index:Integer;
  Character:Char;
  ResultText:TLineText;
Begin
  ResultText:=Value;
  For Index:=1 to Length(ResultText)Do Begin
    Character:=ResultText[Index];
    If(Character>='A')and(Character<='Z')Then
      ResultText[Index]:=Chr(Ord(Character)+32);
  End;
  LowerText:=ResultText;
End;

Function IsWordCharacter(Character:Char):Boolean;
Begin
  IsWordCharacter:=((Character>='A')and(Character<='Z'))or
    ((Character>='a')and(Character<='z'))or
    ((Character>='0')and(Character<='9'))or(Character='_');
End;

Function RoffSymbol(Const Word:TLineText):TLineText;
Var
  LowerWord:TLineText;
Begin
  LowerWord:=LowerText(Word);
  RoffSymbol:=Word;
  If LowerWord='alpha'Then RoffSymbol:=#92+'(*a'
  Else If LowerWord='beta'Then RoffSymbol:=#92+'(*b'
  Else If LowerWord='gamma'Then RoffSymbol:=#92+'(*g'
  Else If LowerWord='delta'Then RoffSymbol:=#92+'(*d'
  Else If LowerWord='epsilon'Then RoffSymbol:=#92+'(*e'
  Else If LowerWord='zeta'Then RoffSymbol:=#92+'(*z'
  Else If LowerWord='eta'Then RoffSymbol:=#92+'(*y'
  Else If LowerWord='theta'Then RoffSymbol:=#92+'(*h'
  Else If LowerWord='iota'Then RoffSymbol:=#92+'(*i'
  Else If LowerWord='kappa'Then RoffSymbol:=#92+'(*k'
  Else If LowerWord='lambda'Then RoffSymbol:=#92+'(*l'
  Else If LowerWord='mu'Then RoffSymbol:=#92+'(*m'
  Else If LowerWord='nu'Then RoffSymbol:=#92+'(*n'
  Else If LowerWord='xi'Then RoffSymbol:=#92+'(*c'
  Else If LowerWord='omicron'Then RoffSymbol:='o'
  Else If LowerWord='pi'Then RoffSymbol:=#92+'(*p'
  Else If LowerWord='rho'Then RoffSymbol:=#92+'(*r'
  Else If LowerWord='sigma'Then RoffSymbol:=#92+'(*s'
  Else If LowerWord='tau'Then RoffSymbol:=#92+'(*t'
  Else If LowerWord='upsilon'Then RoffSymbol:=#92+'(*u'
  Else If LowerWord='phi'Then RoffSymbol:=#92+'(*f'
  Else If LowerWord='chi'Then RoffSymbol:=#92+'(*x'
  Else If LowerWord='psi'Then RoffSymbol:=#92+'(*q'
  Else If LowerWord='omega'Then RoffSymbol:=#92+'(*w'
  Else If LowerWord='infinity'Then RoffSymbol:=#92+'(if'
  Else If LowerWord='partial'Then RoffSymbol:=#92+'(pd'
  Else If LowerWord='integral'Then RoffSymbol:=#92+'(is'
  Else If LowerWord='sum'Then RoffSymbol:=#92+'(sum'
  Else If LowerWord='product'Then RoffSymbol:=#92+'(product'
  Else If LowerWord='union'Then RoffSymbol:=#92+'(cu'
  Else If LowerWord='intersection'Then RoffSymbol:=#92+'(ca'
  Else If LowerWord='in'Then RoffSymbol:=#92+'(mo'
  Else If LowerWord='notin'Then RoffSymbol:=#92+'(nm'
  Else If LowerWord='times'Then RoffSymbol:=#92+'(mu'
  Else If LowerWord='cdot'Then RoffSymbol:=#92+'(bu'
  Else If LowerWord='plusminus'Then RoffSymbol:=#92+'(+-'
  Else If LowerWord='le'Then RoffSymbol:=#92+'(<='
  Else If LowerWord='ge'Then RoffSymbol:=#92+'(>='
  Else If LowerWord='ne'Then RoffSymbol:=#92+'(!='
  Else If LowerWord='approx'Then RoffSymbol:=#92+'(~~'
  Else If LowerWord='equiv'Then RoffSymbol:=#92+'(=='
  Else If LowerWord='rightarrow'Then RoffSymbol:=#92+'(->'
  Else If LowerWord='leftarrow'Then RoffSymbol:=#92+'(<-'
  Else If LowerWord='degree'Then RoffSymbol:=#92+'(de'
  Else If LowerWord='copyright'Then RoffSymbol:=#92+'(co';
End;

Procedure TranslateEquation(Const SourceLine:TLineText; Var ResultLine:TLineText);
Var
  Word:TLineText;
  WordStart,WordLength:Integer;
  VerticalPending:Char;
  VerticalGroupDirection:Char;
  VerticalGroup,SkipSpaces:Boolean;
Begin
  ResultLine:='';
  Position:=1;
  VerticalPending:=#0;
  VerticalGroupDirection:=#0;
  VerticalGroup:=False;
  SkipSpaces:=False;
  While Position<=Length(SourceLine)Do Begin
    If IsWordCharacter(SourceLine[Position])Then Begin
      WordStart:=Position;
      While(Position<=Length(SourceLine))and
            IsWordCharacter(SourceLine[Position])Do Inc(Position);
      WordLength:=Position-WordStart;
      Word:=Copy(SourceLine,WordStart,WordLength);
      If LowerText(Word)='over'Then Begin
        While(Length(ResultLine)>0)and(ResultLine[Length(ResultLine)]=' ')Do
          Delete(ResultLine,Length(ResultLine),1);
        AppendText(ResultLine,'/');
        SkipSpaces:=True;
      End
      Else If LowerText(Word)='sqrt'Then AppendText(ResultLine,'sqrt ')
      Else If LowerText(Word)='sup'Then Begin
        While(Length(ResultLine)>0)and(ResultLine[Length(ResultLine)]=' ')Do
          Delete(ResultLine,Length(ResultLine),1);
        VerticalPending:='u';SkipSpaces:=True;
      End
      Else If LowerText(Word)='sub'Then Begin
        While(Length(ResultLine)>0)and(ResultLine[Length(ResultLine)]=' ')Do
          Delete(ResultLine,Length(ResultLine),1);
        VerticalPending:='d';SkipSpaces:=True;
      End
      Else If LowerText(Word)='from'Then Begin VerticalPending:='d';SkipSpaces:=True;End
      Else If LowerText(Word)='to'Then Begin VerticalPending:='u';SkipSpaces:=True;End
      Else If LowerText(Word)='left'Then Begin End
      Else If LowerText(Word)='right'Then Begin End
      Else If LowerText(Word)='roman'Then AppendText(ResultLine,#92+'fR')
      Else If LowerText(Word)='italic'Then AppendText(ResultLine,#92+'fI')
      Else If LowerText(Word)='bold'Then AppendText(ResultLine,#92+'fB')
      Else Begin
        If VerticalPending<>#0 Then AppendText(ResultLine,#92+VerticalPending);
        Token:=RoffSymbol(Word);
        AppendText(ResultLine,Token);
        If VerticalPending<>#0 Then Begin
          If VerticalPending='u'Then AppendText(ResultLine,#92+'d')
          Else AppendText(ResultLine,#92+'u');
          VerticalPending:=#0;
        End;
      End;
    End Else Begin
      If SkipSpaces and(SourceLine[Position]in[' ',#9])Then Begin
        Inc(Position);
        Continue;
      End;
      SkipSpaces:=False;
      If(VerticalPending<>#0)and(SourceLine[Position]='{')Then Begin
        AppendText(ResultLine,#92+VerticalPending+'(');
        VerticalGroup:=True;
        VerticalGroupDirection:=VerticalPending;
        VerticalPending:=#0;
        SkipSpaces:=True;
        Inc(Position);
        Continue;
      End;
      Case SourceLine[Position]Of
        '{':AppendText(ResultLine,'(');
        '}':Begin
          If VerticalGroup Then
            While(Length(ResultLine)>0)and(ResultLine[Length(ResultLine)]=' ')Do
              Delete(ResultLine,Length(ResultLine),1);
          AppendText(ResultLine,')');
          If VerticalGroup Then Begin
            If VerticalGroupDirection='u'Then AppendText(ResultLine,#92+'d')
            Else AppendText(ResultLine,#92+'u');
            VerticalGroup:=False;
            VerticalGroupDirection:=#0;
          End;
        End;
        '<':Begin
          If(Position<Length(SourceLine))and(SourceLine[Position+1]='=')Then Begin
            AppendText(ResultLine,#92+'(<=');Inc(Position);
          End Else AppendText(ResultLine,'<');
        End;
        '>':Begin
          If(Position<Length(SourceLine))and(SourceLine[Position+1]='=')Then Begin
            AppendText(ResultLine,#92+'(>=');Inc(Position);
          End Else AppendText(ResultLine,'>');
        End;
        '~':Begin
          If(Position<Length(SourceLine))and(SourceLine[Position+1]='=')Then Begin
            AppendText(ResultLine,#92+'(~~');Inc(Position);
          End Else AppendText(ResultLine,'~');
        End;
        '#':AppendText(ResultLine,#92+'(!=' );
      Else AppendText(ResultLine,SourceLine[Position]);
      End;
      Inc(Position);
    End;
  End;
  If VerticalPending<>#0 Then Begin
    If VerticalPending='u'Then AppendText(ResultLine,#92+'d')
    Else AppendText(ResultLine,#92+'u');
  End;
End;

Function IsRequest(Const SourceLine:TLineText; Const RequestName:String):Boolean;
Var
  CleanLine:TLineText;
Begin
  CleanLine:=SourceLine;
  While(Length(CleanLine)>0)and(CleanLine[1]in[' ',#9])Do Delete(CleanLine,1,1);
  IsRequest:=Copy(CleanLine,1,Length(RequestName)+1)='.'+RequestName;
End;

Procedure ProcessLine(Const SourceLine:TLineText);
Begin
  If IsRequest(SourceLine,'EQ')Then Begin
    InEquation:=True;
    WriteLn(SourceLine);
  End Else If IsRequest(SourceLine,'EN')Then Begin
    InEquation:=False;
    WriteLn(SourceLine);
  End Else If InEquation Then Begin
    TranslateEquation(SourceLine,OutputLine);
    WriteLn(OutputLine);
  End Else WriteLn(SourceLine);
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('neqn - preprocess equations for troff');
    WriteLn('Usage: neqn [file]');
    WriteLn('Reads standard input when no file is specified.');
    WriteLn('Processes equations between .EQ and .EN requests.');
  End Else Begin
    WriteLn('neqn - Cette commande permet de lancer le pr'+#130+'processeur d'''+#130+'quations pour troff.');
    WriteLn;
    WriteLn('Syntaxe : neqn [fichier]');
    WriteLn;
    WriteLn('Sans fichier, lit l''entree standard.');
    WriteLn('Traite les equations placees entre les requetes .EQ et .EN.');
  End;
End;

Procedure ProcessInput(Var Source:Text);
Var
  ErrorCode:Integer;
Begin
  LineNumber:=0;
  While Not EOF(Source)Do Begin
    {$I-}ReadLn(Source,InputLine);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      If English Then WriteLn('neqn: read error at line ',LineNumber+1)
      Else WriteLn('neqn : erreur de lecture a la ligne ',LineNumber+1);
      Halt(1);
    End;
    Inc(LineNumber);
    ProcessLine(InputLine);
  End;
End;

Var
  Argument:TLineText;
  ErrorCode:Integer;
Begin
  LanguageCode:=GetEnv('LANGUAGE');
  English:=Copy(LanguageCode,1,2)='EN';
  InEquation:=False;
  SourceName:='';
  If ParamCount>1 Then Begin
    If English Then WriteLn('Usage: neqn [file]')
    Else WriteLn('Syntaxe : neqn [fichier]');
    Halt(2);
  End;
  If ParamCount=1 Then Begin
    Argument:=ParamStr(1);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin
      PrintHelp;
      Halt(0);
    End;
    If(Argument='--version')or(Argument='-V')Then Begin
      WriteLn('neqn (LINUX-0) 1.0');
      Halt(0);
    End;
    SourceName:=Argument;
    Assign(SourceFile,SourceName);
    {$I-}Reset(SourceFile);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      If English Then WriteLn('neqn: cannot open ',SourceName)
      Else WriteLn('neqn : impossible d''ouvrir ',SourceName);
      Halt(1);
    End;
    ProcessInput(SourceFile);
    {$I-}Close(SourceFile);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      If English Then WriteLn('neqn: error closing ',SourceName)
      Else WriteLn('neqn : erreur a la fermeture de ',SourceName);
      Halt(1);
    End;
  End Else ProcessInput(Input);
END.
