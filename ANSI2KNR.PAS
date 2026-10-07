{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ANSI2KNR(Input,Output);

Uses DOS;

Const
  MaxHeaderLength=255;
  MaxParameters=32;

Type
  THeader=Array[1..MaxHeaderLength]Of Char;
  TParameters=Array[1..MaxParameters]Of String;

Var
  InputFile,OutputFile:Text;
  InputStream,OutputStream:^Text;
  InputName,OutputName,LineFileName,CurrentParam:String;
  Header:THeader;
  ParameterNames,ParameterDeclarations:TParameters;
  HeaderLength,HeaderLine,SourceLine,ParameterCount:Integer;
  ArgumentIndex,I:Integer;
  UseInputFile,UseOutputFile,HaveFilename,HasPending:Boolean;
  PendingChar:Char;
  Candidate,Overflow,InBlockComment,InLineComment:Boolean;
  InQuote,Escaped:Boolean;
  QuoteChar:Char;
  BraceDepth,ParenDepth,BracketDepth:Integer;

Function ReadChar(Var C:Char):Boolean;
Begin
  If HasPending Then Begin
    C:=PendingChar;
    HasPending:=False;
    ReadChar:=True;
    Exit;
  End;
  If EOF(InputStream^)Then Begin
    ReadChar:=False;
    Exit;
  End;
  Read(InputStream^,C);
  ReadChar:=True;
End;

Function PeekChar(Var C:Char):Boolean;
Begin
  If Not HasPending Then Begin
    If EOF(InputStream^)Then Begin
      PeekChar:=False;
      Exit;
    End;
    Read(InputStream^,PendingChar);
    HasPending:=True;
  End;
  C:=PendingChar;
  PeekChar:=True;
End;

Procedure WriteChar(C:Char);
Begin
  Write(OutputStream^,C);
End;

Procedure WriteText(Const S:String);
Var
  I:Integer;
Begin
  For I:=1 to Length(S)Do WriteChar(S[I]);
End;

Procedure AppendHeader(C:Char);
Begin
  If HeaderLength<MaxHeaderLength Then Begin
    Inc(HeaderLength);
    Header[HeaderLength]:=C;
  End Else Overflow:=True;
End;

Function HeaderText:String;
Var
  I:Integer;
  S:String;
Begin
  S:='';
  For I:=1 to HeaderLength Do S:=S+Header[I];
  HeaderText:=S;
End;

Function IdentifierStart(C:Char):Boolean;
Begin
  IdentifierStart:=C in['A'..'Z','a'..'z','_','$'];
End;

Function IdentifierChar(C:Char):Boolean;
Begin
  IdentifierChar:=IdentifierStart(C)or(C in['0'..'9']);
End;

Function TrimWhitespace(Const S:String):String;
Var
  First,Last:Integer;
Begin
  First:=1;
  Last:=Length(S);
  While(First<=Last)and(S[First]in[' ',#9,#10,#13])Do Inc(First);
  While(Last>=First)and(S[Last]in[' ',#9,#10,#13])Do Dec(Last);
  TrimWhitespace:=Copy(S,First,Last-First+1);
End;

Function IsTypeWord(Const S:String):Boolean;
Begin
  IsTypeWord:=(S='void')or(S='char')or(S='short')or(S='int')or
    (S='long')or(S='float')or(S='double')or(S='signed')or
    (S='unsigned')or(S='const')or(S='volatile')or(S='restrict')or
    (S='register')or(S='auto')or(S='static')or(S='extern')or
    (S='struct')or(S='union')or(S='enum')or(S='_Bool')or
    (S='inline')or(S='__inline__')or(S='__restrict');
End;

Function RemoveComments(Const S:String):String;
Var
  I:Integer;
  InBlock,_InLine,InString,InChar,Escape:Boolean;
  Clean:String;
Begin
  Clean:=S;
  InBlock:=False;
  _InLine:=False;
  InString:=False;
  InChar:=False;
  Escape:=False;
  I:=1;
  While I<=Length(S)Do Begin
    If InBlock Then Begin
      Clean[I]:=' ';
      If(S[I]='*')and(I<Length(S))and(S[I+1]='/')Then Begin
        Clean[I+1]:=' ';
        Inc(I);
        InBlock:=False;
      End;
    End Else If _InLine Then Begin
      If S[I]in[#10,#13]Then _InLine:=False Else Clean[I]:=' ';
    End Else If InString or InChar Then Begin
      If Escape Then Escape:=False Else
      If S[I]=Chr(92)Then Escape:=True Else
      If InString and(S[I]=Chr(34))Then InString:=False Else
      If InChar and(S[I]=Chr(39))Then InChar:=False;
    End Else If(S[I]='/')and(I<Length(S))and(S[I+1]='*')Then Begin
      Clean[I]:=' ';
      Clean[I+1]:=' ';
      Inc(I);
      InBlock:=True;
    End Else If(S[I]='/')and(I<Length(S))and(S[I+1]='/')Then Begin
      Clean[I]:=' ';
      Clean[I+1]:=' ';
      Inc(I);
      _InLine:=True;
    End Else If S[I]=Chr(34)Then InString:=True Else
    If S[I]=Chr(39)Then InChar:=True;
    Inc(I);
  End;
  RemoveComments:=Clean;
End;

Function GetParameterName(Const Decl:String; Var Name:String):Boolean;
Var
  I,Start,Count:Integer;
  Word:String;
Begin
  Name:='';
  Count:=0;
  I:=1;
  While I<=Length(Decl)Do Begin
    If IdentifierStart(Decl[I])Then Begin
      Start:=I;
      Inc(I);
      While(I<=Length(Decl))and IdentifierChar(Decl[I])Do Inc(I);
      Word:=Copy(Decl,Start,I-Start);
      If Not IsTypeWord(Word)Then Begin
        Name:=Word;
        Inc(Count);
      End;
    End Else Inc(I);
  End;
  GetParameterName:=(Name<>'')and(Count>0);
End;

Function ConvertHeader(Const S:String):Boolean;
Var
  Clean,FunctionName,Prefix,Parameter,Name:String;
  OpenParen,CloseParen,Depth,I,NameEnd,NameStart:Integer;
  Start,Finish,ParenNest,BracketNest:Integer;
  LineNumberString:String;
Begin
  ConvertHeader:=False;
  Clean:=RemoveComments(S);
  OpenParen:=0;
  For I:=1 to Length(Clean)Do
    If Clean[I]='('Then Begin
      OpenParen:=I;
      Break;
    End;
  If OpenParen=0 Then Exit;
  Depth:=0;
  CloseParen:=0;
  For I:=OpenParen to Length(Clean)Do Begin
    If Clean[I]='('Then Inc(Depth) Else
    If Clean[I]=')'Then Begin
      Dec(Depth);
      If Depth=0 Then Begin
        CloseParen:=I;
        Break;
      End;
    End;
  End;
  If CloseParen=0 Then Exit;
  I:=OpenParen-1;
  While(I>0)and(Clean[I]in[' ',#9,#10,#13])Do Dec(I);
  NameEnd:=I;
  While(I>0)and IdentifierChar(Clean[I])Do Dec(I);
  NameStart:=I+1;
  If(NameStart>NameEnd)or Not IdentifierStart(Clean[NameStart])Then Exit;
  FunctionName:=Copy(Clean,NameStart,NameEnd-NameStart+1);
  If(FunctionName='if')or(FunctionName='while')or(FunctionName='for')or
    (FunctionName='switch')or(FunctionName='sizeof')or
    (FunctionName='typedef')or(FunctionName='return')Then Exit;
  Prefix:=Copy(Clean,1,NameStart-1);
  If TrimWhitespace(Prefix)=''Then Exit;
  I:=CloseParen+1;
  While(I<=Length(Clean))and(Clean[I]in[' ',#9,#10,#13])Do Inc(I);
  If I<=Length(Clean)Then Exit;

  ParameterCount:=0;
  Parameter:=TrimWhitespace(Copy(Clean,OpenParen+1,CloseParen-OpenParen-1));
  If(Parameter<>'')and(Parameter<>'void')Then Begin
    Start:=OpenParen+1;
    ParenNest:=0;
    BracketNest:=0;
    For I:=OpenParen+1 to CloseParen Do Begin
      If I=CloseParen Then Finish:=I-1 Else Begin
        If Clean[I]='('Then Inc(ParenNest) Else
        If Clean[I]=')'Then Dec(ParenNest) Else
        If Clean[I]='['Then Inc(BracketNest) Else
        If Clean[I]=']'Then Dec(BracketNest);
        If(Clean[I]=',')and(ParenNest=0)and(BracketNest=0)Then
          Finish:=I-1 Else Continue;
      End;
      Parameter:=TrimWhitespace(Copy(Clean,Start,Finish-Start+1));
      If(Parameter='')or(Parameter='...')or
        (Parameter='void')or(Parameter='')Then Exit;
      If ParameterCount>=MaxParameters Then Exit;
      If Not GetParameterName(Parameter,Name)Then Exit;
      Inc(ParameterCount);
      ParameterNames[ParameterCount]:=Name;
      ParameterDeclarations[ParameterCount]:=TrimWhitespace(Copy(S,Start,Finish-Start+1));
      Start:=I+1;
    End;
  End;

  If HaveFilename Then Begin
    Str(HeaderLine,LineNumberString);
    WriteText('#line '+LineNumberString);
    WriteText(' "');
    For I:=1 to Length(LineFileName)Do Begin
      If(LineFileName[I]=Chr(92))or(LineFileName[I]=Chr(34))Then WriteChar(Chr(92));
      WriteChar(LineFileName[I]);
    End;
    WriteText('"'+#10);
  End;
  WriteText(Copy(S,1,NameStart-1));
  WriteText(FunctionName+'(');
  For I:=1 to ParameterCount Do Begin
    If I>1 Then WriteText(', ');
    WriteText(ParameterNames[I]);
  End;
  WriteText(')'+#10);
  For I:=1 to ParameterCount Do Begin
    WriteText(ParameterDeclarations[I]);
    WriteText(';'+#10);
  End;
  ConvertHeader:=True;
End;

Procedure ResetHeader;
Begin
  HeaderLength:=0;
  Candidate:=False;
  Overflow:=False;
  ParenDepth:=0;
  BracketDepth:=0;
End;

Procedure FlushHeader;
Var
  I:Integer;
Begin
  For I:=1 to HeaderLength Do WriteChar(Header[I]);
  ResetHeader;
End;

Procedure ReadAndConvert;
Var
  C,NextC:Char;
  HaveChar,SpecialHandled,NormalChar:Boolean;
  PreviousWasStar:Boolean;
  HeaderString:String;
Begin
  SourceLine:=1;
  HeaderLine:=1;
  BraceDepth:=0;
  ResetHeader;
  InBlockComment:=False;
  InLineComment:=False;
  InQuote:=False;
  Escaped:=False;
  QuoteChar:=#0;
  PreviousWasStar:=False;
  HasPending:=False;
  HaveChar:=ReadChar(C);
  While HaveChar Do Begin
    SpecialHandled:=False;
    NormalChar:=Not InBlockComment and Not InLineComment and Not InQuote;
    If Candidate and(HeaderLength<MaxHeaderLength)Then AppendHeader(C) Else
    If Candidate Then Overflow:=True;
    If Not Candidate and(BraceDepth=0)and(C in[' ',#9,#10,#13])Then Begin
      WriteChar(C);
    End Else If Not Candidate and(BraceDepth=0)and(C='#')Then Begin
      Repeat
        WriteChar(C);
        If C=#10 Then Begin
          Inc(SourceLine);
          Break;
        End;
        If Not ReadChar(C)Then Begin
          HaveChar:=False;
          Break;
        End;
      Until False;
      HaveChar:=ReadChar(C);
      Continue;
    End Else If BraceDepth=0 Then Begin
      If Not Candidate Then Begin
        Candidate:=True;
        HeaderLine:=SourceLine;
        HeaderLength:=0;
        AppendHeader(C);
      End;
      If NormalChar and(C='/')and PeekChar(NextC)and
        ((NextC='*')or(NextC='/'))Then Begin
        If HeaderLength<MaxHeaderLength Then AppendHeader(NextC)
                                        Else Overflow:=True;
        ReadChar(NextC);
        If NextC='*'Then InBlockComment:=True Else InLineComment:=True;
        SpecialHandled:=True;
      End;
    End Else WriteChar(C);

    If Not SpecialHandled Then Begin
      If InBlockComment Then Begin
        If PreviousWasStar and(C='/')Then InBlockComment:=False;
        PreviousWasStar:=C='*';
      End Else If InLineComment Then Begin
        If C=#10 Then InLineComment:=False;
      End Else If InQuote Then Begin
        If Escaped Then Escaped:=False Else
        If C=Chr(92)Then Escaped:=True Else
        If C=QuoteChar Then InQuote:=False;
      End Else If(C='/')and PeekChar(NextC)and
        ((NextC='*')or(NextC='/'))Then Begin
        If BraceDepth>0 Then Begin
          WriteChar(NextC);
          ReadChar(NextC);
          If NextC='*'Then InBlockComment:=True Else InLineComment:=True;
        End;
      End Else If(C=Chr(34))or(C=Chr(39))Then Begin
        InQuote:=True;
        QuoteChar:=C;
      End Else If BraceDepth=0 Then Begin
        If C='('Then Inc(ParenDepth) Else
        If C=')'Then Dec(ParenDepth) Else
        If C='['Then Inc(BracketDepth) Else
        If C=']'Then Dec(BracketDepth);
        If(ParenDepth=0)and(BracketDepth=0)and(C=';')Then FlushHeader Else
        If(ParenDepth=0)and(BracketDepth=0)and(C='{')Then Begin
          HeaderString:=Copy(HeaderText,1,HeaderLength-1);
          If Not Overflow and ConvertHeader(HeaderString)Then WriteText('{'+#10)
          Else Begin
            If Overflow Then FlushHeader Else Begin
              For I:=1 to HeaderLength-1 Do WriteChar(Header[I]);
              WriteChar('{');
              ResetHeader;
            End;
          End;
          BraceDepth:=1;
        End;
      End Else If C='{'Then Inc(BraceDepth) Else
      If C='}'Then Begin
        Dec(BraceDepth);
        If BraceDepth=0 Then ResetHeader;
      End;
    End;
    If C=#10 Then Inc(SourceLine);
    HaveChar:=ReadChar(C);
  End;
  If Candidate and(HeaderLength>0)Then FlushHeader;
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('ANSI2KNR : Convert ANSI C function definitions to K&R C.');
    WriteLn('Syntax: ansi2knr [--filename NAME] [INPUT [OUTPUT]]');
    WriteLn(' --filename NAME  Name used in #line directives');
    WriteLn('Without files, standard input and output are used.');
  End Else Begin
    WriteLn('ANSI2KNR : Cette commande permet de convertir les d'+#130+'finitions ANSI C en K&R C.');
    WriteLn;
    WriteLn('Syntaxe : ansi2knr [--filename NOM] [ENTREE [SORTIE]]');
    WriteLn;
    WriteLn(' --filename NOM  Nom utilise dans les directives #line');
    WriteLn('Sans fichiers, utilise stdin et stdout.');
  End;
End;

BEGIN
  InputName:='';
  OutputName:='';
  LineFileName:='';
  UseInputFile:=False;
  UseOutputFile:=False;
  HaveFilename:=False;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    CurrentParam:=ParamStr(ArgumentIndex);
    If(CurrentParam='--help')or(CurrentParam='-h')or(CurrentParam='/?')or
      (CurrentParam='/h')or(CurrentParam='/H')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(CurrentParam='--version')or(CurrentParam='-v')Then Begin
      WriteLn('ansi2knr (LINUX-0) 1.0');
      Halt(0);
    End Else If CurrentParam='--filename'Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then Begin
        WriteLn('Erreur : nom manquant apres --filename');
        Halt(2);
      End;
      LineFileName:=ParamStr(ArgumentIndex);
      HaveFilename:=True;
    End Else If Copy(CurrentParam,1,11)='--filename='Then Begin
      LineFileName:=Copy(CurrentParam,12,244);
      HaveFilename:=True;
    End Else If(Length(CurrentParam)>0)and(CurrentParam[1]='-')Then Begin
      WriteLn('Erreur : option inconnue : ',CurrentParam);
      Halt(2);
    End Else If Not UseInputFile Then Begin
      InputName:=CurrentParam;
      UseInputFile:=True;
    End Else If Not UseOutputFile Then Begin
      OutputName:=CurrentParam;
      UseOutputFile:=True;
    End Else Begin
      WriteLn('Erreur : trop d''arguments');
      Halt(2);
    End;
    Inc(ArgumentIndex);
  End;

  If UseInputFile Then Begin
    {$I-}Assign(InputFile,InputName);
    Reset(InputFile);{$I+}
    If IOResult<>0 Then Begin
      WriteLn('Erreur : impossible de lire ',InputName);
      Halt(1);
    End;
    InputStream:=@InputFile;
  End Else InputStream:=@Input;
  If UseOutputFile Then Begin
    {$I-}Assign(OutputFile,OutputName);
    Rewrite(OutputFile);{$I+}
    If IOResult<>0 Then Begin
      WriteLn('Erreur : impossible de creer ',OutputName);
      Halt(1);
    End;
    OutputStream:=@OutputFile;
  End Else OutputStream:=@Output;
  ReadAndConvert;
  If UseInputFile Then Close(InputFile);
  If UseOutputFile Then Close(OutputFile);
END.
