{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program CHECKNR(Input,Output);

Uses DOS;

Const
  MaxFiles=32;
  MaxPairs=32;
  MaxFrames=64;
  MaxCommands=64;

Type
  TName=String[2];
  TFileArray=Array[1..MaxFiles]Of String;
  TNameArray=Array[1..MaxPairs]Of TName;
  TFrame=Record
    StartName,EndName:TName;
    StartLine:LongInt;
    IgnoreBody:Boolean;
  End;
  TFrameArray=Array[1..MaxFrames]Of TFrame;
  TCommandArray=Array[1..MaxCommands]Of TName;

Var
  SourceFile:Text;
  FileNames:TFileArray;
  PairStarts,PairEnds:TNameArray;
  NoArgumentCommands:TCommandArray;
  Frames:TFrameArray;
  FileName,Argument,LanguageCode:String;
  LineText:String;
  OptionStartName,OptionEndName:TName;
  FileCount,ArgumentIndex,LineNumber,ErrorCount:LongInt;
  PairCount,NoArgumentCount,FrameCount,BraceDepth:Integer;
  BraceStartLine:LongInt;
  CheckFonts,CheckSizes,EndOptions:Boolean;

Function NormalizeName(Const Token:String):TName;
Var
  StartPosition,NameLength:Integer;
Begin
  StartPosition:=1;
  If(Length(Token)>0)and(Token[1]in['.',''''])Then StartPosition:=2;
  NameLength:=Length(Token)-StartPosition+1;
  If NameLength>2 Then NameLength:=2;
  If NameLength<0 Then NameLength:=0;
  NormalizeName:=Copy(Token,StartPosition,NameLength);
End;

Function RequestName(Const TextLine:String):TName;
Var
  Position,StartPosition:Integer;
Begin
  RequestName:='';
  Position:=1;
  While(Position<=Length(TextLine))and
    (TextLine[Position]in[' ',#9])Do Inc(Position);
  If(Position>Length(TextLine))or
    not(TextLine[Position]in['.',''''])Then Exit;
  Inc(Position);
  StartPosition:=Position;
  While(Position<=Length(TextLine))and(Position-StartPosition<2)and
    not(TextLine[Position]in[' ',#9])Do Inc(Position);
  If Position=StartPosition Then Exit;
  RequestName:=Copy(TextLine,StartPosition,Position-StartPosition);
End;

Procedure ReportError(Const SourceName,MessageFrench,MessageEnglish:String;
                      AtLine:LongInt);
Var
  Number:String;
Begin
  Str(AtLine,Number);
  Write(SourceName,':',Number,': ');
  If Copy(LanguageCode,1,2)='EN'Then WriteLn(MessageEnglish)
  Else WriteLn(MessageFrench);
  Inc(ErrorCount);
End;

Procedure AddPair(Const StartName,EndName:TName);
Begin
  If PairCount>=MaxPairs Then Begin
    If Copy(LanguageCode,1,2)='EN'Then WriteLn('checknr: too many macro pairs')
    Else WriteLn('checknr : trop de paires de macros');
    Halt(2);
  End;
  Inc(PairCount);
  PairStarts[PairCount]:=StartName;
  PairEnds[PairCount]:=EndName;
End;

Procedure AddNoArgumentCommand(Const CommandName:TName);
Begin
  If NoArgumentCount>=MaxCommands Then Begin
    If Copy(LanguageCode,1,2)='EN'Then WriteLn('checknr: too many commands')
    Else WriteLn('checknr : trop de commandes');
    Halt(2);
  End;
  Inc(NoArgumentCount);
  NoArgumentCommands[NoArgumentCount]:=CommandName;
End;

Function IsNoArgumentCommand(Const CommandName:TName):Boolean;
Var
  Index:Integer;
Begin
  IsNoArgumentCommand:=False;
  For Index:=1 to NoArgumentCount Do
    If NoArgumentCommands[Index]=CommandName Then Begin
      IsNoArgumentCommand:=True;
      Exit;
    End;
End;

Function IsOpeningRequest(Const Request:TName; Var EndName:TName):Boolean;
Var
  Index:Integer;
Begin
  IsOpeningRequest:=False;
  For Index:=1 to PairCount Do
    If PairStarts[Index]=Request Then Begin
      EndName:=PairEnds[Index];
      IsOpeningRequest:=True;
      Exit;
    End;
End;

Function IsClosingRequest(Const Request:TName):Boolean;
Var
  Index:Integer;
Begin
  IsClosingRequest:=False;
  For Index:=1 to PairCount Do
    If PairEnds[Index]=Request Then Begin
      IsClosingRequest:=True;
      Exit;
    End;
End;

Function ReadWord(Const TextLine:String; Var Position:Integer):String;
Var
  StartPosition:Integer;
Begin
  While(Position<=Length(TextLine))and
    (TextLine[Position]in[' ',#9])Do Inc(Position);
  StartPosition:=Position;
  While(Position<=Length(TextLine))and
    not(TextLine[Position]in[' ',#9])Do Inc(Position);
  ReadWord:=Copy(TextLine,StartPosition,Position-StartPosition);
End;

Function IsValidFontEscape(Const TextLine:String; SlashPosition:Integer):Boolean;
Var
  Position:Integer;
Begin
  Position:=SlashPosition+2;
  IsValidFontEscape:=False;
  If Position>Length(TextLine)Then Exit;
  If TextLine[Position]='('Then Begin
    IsValidFontEscape:=Position+2<=Length(TextLine);
    Exit;
  End;
  If TextLine[Position]='['Then Begin
    Inc(Position);
    While(Position<=Length(TextLine))and(TextLine[Position]<>']')Do
      Inc(Position);
    IsValidFontEscape:=Position<=Length(TextLine);
    Exit;
  End;
  IsValidFontEscape:=True;
End;

Function IsValidSizeEscape(Const TextLine:String; SlashPosition:Integer):Boolean;
Var
  Position,DigitCount:Integer;
Begin
  Position:=SlashPosition+2;
  IsValidSizeEscape:=False;
  If Position>Length(TextLine)Then Exit;
  If TextLine[Position]='('Then Begin
    IsValidSizeEscape:=Position+2<=Length(TextLine);
    Exit;
  End;
  If TextLine[Position]='['Then Begin
    Inc(Position);
    While(Position<=Length(TextLine))and(TextLine[Position]<>']')Do
      Inc(Position);
    IsValidSizeEscape:=Position<=Length(TextLine);
    Exit;
  End;
  If TextLine[Position]in['+','-']Then Inc(Position);
  DigitCount:=0;
  While(Position<=Length(TextLine))and(TextLine[Position]in['0'..'9'])Do Begin
    Inc(DigitCount);
    Inc(Position);
  End;
  IsValidSizeEscape:=DigitCount>0;
End;

Procedure ScanEscapes(Const SourceName:String);
Var
  Position:Integer;
Begin
  Position:=1;
  While Position<=Length(LineText)Do Begin
    If LineText[Position]=#92 Then Begin
      If Position<Length(LineText)Then Begin
        If LineText[Position+1]=#92 Then Inc(Position,2) Else
        If LineText[Position+1]='{'Then Begin
          Inc(BraceDepth);
          If BraceDepth=1 Then BraceStartLine:=LineNumber;
          Inc(Position,2);
        End Else If LineText[Position+1]='}'Then Begin
          If BraceDepth=0 Then
            ReportError(SourceName,'fermeture \} sans ouverture \{',
                        'closing \} without opening \{',LineNumber)
          Else Dec(BraceDepth);
          Inc(Position,2);
        End Else If(CheckFonts)and(LineText[Position+1]='f')Then Begin
          If Not IsValidFontEscape(LineText,Position)Then
            ReportError(SourceName,'echappement de police \f incomplet',
                        'incomplete font escape \f',LineNumber);
          Inc(Position,2);
        End Else If(CheckSizes)and(LineText[Position+1]='s')Then Begin
          If Not IsValidSizeEscape(LineText,Position)Then
            ReportError(SourceName,'echappement de taille \s invalide',
                        'invalid size escape \s',LineNumber);
          Inc(Position,2);
        End Else Inc(Position,2);
      End Else Inc(Position);
    End Else Inc(Position);
  End;
End;

Procedure CheckStream(Var Source:Text; Const SourceName:String);
Var
  Request,EndName,WordText,MacroName,StopName:TName;
  Position:Integer;
  Ignoring:Boolean;
Begin
  FrameCount:=0;
  BraceDepth:=0;
  BraceStartLine:=0;
  LineNumber:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,LineText);
    Inc(LineNumber);
    Request:=RequestName(LineText);
    Ignoring:=(FrameCount>0)and Frames[FrameCount].IgnoreBody;
    If Ignoring Then Begin
      If Request=Frames[FrameCount].EndName Then Dec(FrameCount);
    End Else Begin
      If(Request='de')or(Request='am')or(Request='ig')Then Begin
        Position:=1;
        WordText:=ReadWord(LineText,Position);
        If Request='ig'Then Begin
          WordText:=ReadWord(LineText,Position);
          If WordText=''Then StopName:=NormalizeName('..')
          Else StopName:=NormalizeName(WordText);
          MacroName:=Request;
        End Else Begin
          WordText:=ReadWord(LineText,Position);
          MacroName:=NormalizeName(WordText);
          WordText:=ReadWord(LineText,Position);
          If WordText=''Then StopName:=NormalizeName('..')
          Else StopName:=NormalizeName(WordText);
        End;
        If(FrameCount>=MaxFrames)or(MacroName='')Then
          ReportError(SourceName,'definition de macro invalide',
                      'invalid macro definition',LineNumber)
        Else Begin
          Inc(FrameCount);
          Frames[FrameCount].StartName:=Request;
          Frames[FrameCount].EndName:=StopName;
          Frames[FrameCount].StartLine:=LineNumber;
          Frames[FrameCount].IgnoreBody:=Request='ig';
        End;
      End Else If(FrameCount>0)and
        (Request=Frames[FrameCount].EndName)Then Dec(FrameCount)
      Else If IsOpeningRequest(Request,EndName)Then Begin
        If FrameCount>=MaxFrames Then
          ReportError(SourceName,'imbrication de macros trop profonde',
                      'macro nesting too deep',LineNumber)
        Else Begin
          Inc(FrameCount);
          Frames[FrameCount].StartName:=Request;
          Frames[FrameCount].EndName:=EndName;
          Frames[FrameCount].StartLine:=LineNumber;
          Frames[FrameCount].IgnoreBody:=False;
        End;
      End Else If IsClosingRequest(Request)Then Begin
        If(FrameCount=0)or(Frames[FrameCount].EndName<>Request)Then
          ReportError(SourceName,'fermeture de macro sans ouverture : .'+Request,
                      'macro end without matching start: .'+Request,LineNumber)
        Else Dec(FrameCount);
      End;
      If Not IsNoArgumentCommand(Request)Then ScanEscapes(SourceName);
    End;
  End;
  While FrameCount>0 Do Begin
    ReportError(SourceName,'macro .'+Frames[FrameCount].StartName+
                ' sans fermeture .'+Frames[FrameCount].EndName,
                'macro .'+Frames[FrameCount].StartName+
                ' without closing .'+Frames[FrameCount].EndName,
                Frames[FrameCount].StartLine);
    Dec(FrameCount);
  End;
  If BraceDepth>0 Then
    ReportError(SourceName,'\{ sans \}','\{ without \}',BraceStartLine);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('CHECKNR : Check nroff and troff input for possible errors.');
    WriteLn('Syntax: checknr [-f] [-s] [-a .x .y ...] [-c .x ...] [file ...]');
    WriteLn(' -f  Do not check font escapes');
    WriteLn(' -s  Do not check size escapes');
    WriteLn(' -a  Add pairs of macro requests to check');
    WriteLn(' -c  List requests that take no arguments');
    WriteLn('With no file, input is read from standard input.');
    WriteLn('Default pairs: .EQ/.EN, .TS/.TE, .PS/.PE, .DS/.DE,');
    WriteLn('.FS/.FE, .KS/.KE and .RS/.RE.');
  End Else Begin
    WriteLn('CHECKNR : Cette commande permet de v'+#130+'rifier les entr'+#130+'es nroff et troff et signale les erreurs.');
    WriteLn;
    WriteLn('Syntaxe : checknr [-f] [-s] [-a .x .y ...] [-c .x ...] [fichier ...]');
    WriteLn;
    WriteLn(' -f  Ne pas verifier les '+#130+'chappements de police');
    WriteLn(' -s  Ne pas verifier les '+#130+'chappements de taille');
    WriteLn(' -a  Ajouter des paires de requetes de macros a verifier');
    WriteLn(' -c  Lister les requetes sans arguments');
    WriteLn('Sans fichier, lit les donnees depuis l''entree standard.');
    WriteLn('Paires par defaut : .EQ/.EN, .TS/.TE, .PS/.PE, .DS/.DE,');
    WriteLn('.FS/.FE, .KS/.KE et .RS/.RE.');
  End;
End;

Procedure OptionError(Const MessageFrench,MessageEnglish:String);
Begin
  If Copy(LanguageCode,1,2)='EN'Then WriteLn('checknr: ',MessageEnglish)
  Else WriteLn('checknr : ',MessageFrench);
  Halt(2);
End;

Function IsMacroArgument(Const Value:String):Boolean;
Begin
  IsMacroArgument:=(Value<>'')and(Value[1]='.');
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  FileCount:=0;
  PairCount:=0;
  NoArgumentCount:=0;
  CheckFonts:=True;
  CheckSizes:=True;
  EndOptions:=False;
  AddPair('EQ','EN');
  AddPair('TS','TE');
  AddPair('PS','PE');
  AddPair('DS','DE');
  AddPair('FS','FE');
  AddPair('KS','KE');
  AddPair('RS','RE');

  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If Not EndOptions and(Argument='--')Then EndOptions:=True Else
    If Not EndOptions and((Argument='--help')or(Argument='-h')or
      (Argument='/?')or(Argument='/h')or(Argument='/H'))Then Begin
      PrintHelp;
      Halt(0);
    End Else If Not EndOptions and
      ((Argument='--version')or(Argument='-V'))Then Begin
      WriteLn('checknr (LINUX-0) 1.0');
      Halt(0);
    End Else If Not EndOptions and(Argument='-f')Then CheckFonts:=False Else
    If Not EndOptions and(Argument='-s')Then CheckSizes:=False Else
    If Not EndOptions and(Argument='-a')Then Begin
      Inc(ArgumentIndex);
      If(ArgumentIndex>ParamCount)or
        Not IsMacroArgument(ParamStr(ArgumentIndex))Then
        OptionError('paires de macros requises apres -a',
                    'macro pairs required after -a');
      While(ArgumentIndex<=ParamCount)and
        IsMacroArgument(ParamStr(ArgumentIndex))Do Begin
        OptionStartName:=NormalizeName(ParamStr(ArgumentIndex));
        Inc(ArgumentIndex);
        If(ArgumentIndex>ParamCount)or
          Not IsMacroArgument(ParamStr(ArgumentIndex))Then
          OptionError('nom de fermeture manquant dans -a',
                      'missing closing macro name in -a');
        OptionEndName:=NormalizeName(ParamStr(ArgumentIndex));
        AddPair(OptionStartName,OptionEndName);
        Inc(ArgumentIndex);
      End;
      Dec(ArgumentIndex);
    End Else If Not EndOptions and(Argument='-c')Then Begin
      Inc(ArgumentIndex);
      If(ArgumentIndex>ParamCount)or
        Not IsMacroArgument(ParamStr(ArgumentIndex))Then
        OptionError('nom de commande requis apres -c',
                    'command name required after -c');
      While(ArgumentIndex<=ParamCount)and
        IsMacroArgument(ParamStr(ArgumentIndex))Do Begin
        AddNoArgumentCommand(NormalizeName(ParamStr(ArgumentIndex)));
        Inc(ArgumentIndex);
      End;
      Dec(ArgumentIndex);
    End Else If Not EndOptions and(Length(Argument)>1)and
      (Argument[1]='-')Then OptionError('option inconnue : '+Argument,
                                         'unknown option: '+Argument)
    Else Begin
      If FileCount>=MaxFiles Then
        OptionError('trop de fichiers','too many files');
      Inc(FileCount);
      FileNames[FileCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;

  ErrorCount:=0;
  If FileCount=0 Then CheckStream(Input,'stdin')
  Else For ArgumentIndex:=1 to FileCount Do Begin
    FileName:=FileNames[ArgumentIndex];
    Assign(SourceFile,FileName);
    {$I-}Reset(SourceFile);{$I+}
    If IOResult<>0 Then Begin
      If Copy(LanguageCode,1,2)='EN'Then
        WriteLn('checknr: cannot read ',FileName)
      Else WriteLn('checknr : impossible de lire ',FileName);
      Inc(ErrorCount);
    End Else Begin
      CheckStream(SourceFile,FileName);
      Close(SourceFile);
    End;
  End;
  If ErrorCount>0 Then Halt(1);
END.