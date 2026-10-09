{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program CHECKEQ(Input,Output);

Uses DOS;

Const
  MaxFiles=32;

Type
  TFileArray=Array[1..MaxFiles]Of String;

Var
  SourceFile:Text;
  FileNames:TFileArray;
  FileName,Argument,LanguageCode:String;
  FileCount,ArgumentIndex,LineNumber:LongInt;
  EquationStart,ErrorCount:LongInt;
  InEquation,EndOptions:Boolean;

Function NumberText(Value:LongInt):String;
Var
  TextValue:String;
Begin
  Str(Value,TextValue);
  NumberText:=TextValue;
End;

Function RequestName(Const LineText:String):String;
Var
  Name:String;
Begin
  RequestName:='';
  If(Length(LineText)<3)or not(LineText[1]in['.',''''])Then Exit;
  Name:=Copy(LineText,2,2);
  If(Length(LineText)>3)and not(LineText[4]in[' ',#9])Then Exit;
  RequestName:=Name;
End;

Procedure ReportError(Const SourceName,MessageFrench,MessageEnglish:String;
                      AtLine:LongInt);
Var
  LineText:String;
Begin
  Str(AtLine,LineText);
  Write(SourceName,':',LineText,': ');
  If Copy(LanguageCode,1,2)='EN'Then WriteLn(MessageEnglish)
  Else WriteLn(MessageFrench);
  Inc(ErrorCount);
End;

Procedure CheckStream(Var Source:Text; Const SourceName:String);
Var
  LineText,Request:String;
Begin
  InEquation:=False;
  EquationStart:=0;
  LineNumber:=0;
  While Not EOF(Source)Do Begin
    ReadLn(Source,LineText);
    Inc(LineNumber);
    Request:=RequestName(LineText);
    If Request='EQ'Then Begin
      If InEquation Then
        ReportError(SourceName,'debut .EQ imbrique',
                    'nested .EQ start',LineNumber)
      Else Begin
        InEquation:=True;
        EquationStart:=LineNumber;
      End;
    End Else If Request='EN'Then Begin
      If Not InEquation Then
        ReportError(SourceName,'.EN sans debut .EQ',
                    '.EN without a matching .EQ',LineNumber)
      Else InEquation:=False;
    End;
  End;
  If InEquation Then
    ReportError(SourceName,'.EQ sans fin .EN',
                '.EQ without a matching .EN',EquationStart);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('CHECKEQ : Check equation delimiters in troff input.');
    WriteLn('Syntax: checkeq [file ...]');
    WriteLn('With no files, input is read from standard input.');
    WriteLn('Checks that .EQ and .EN requests are properly paired.');
  End Else Begin
    WriteLn('CHECKEQ : Cette commande permet de v'+#130+'rifier les s'+#130+'parateurs ',
            'd'''+#130+'quations dans un fichier troff.');
    WriteLn;
    WriteLn('Syntaxe : checkeq [fichier ...]');
    WriteLn;
    WriteLn('Sans fichier, lit les donn'+#130+'es depuis l''entr'+#130+'e standard.');
    WriteLn('Verifie que les requ'+#136+'tes .EQ et .EN sont correctement appari'+#130+'es.');
  End;
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  FileCount:=0;
  EndOptions:=False;
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
      WriteLn('checkeq (LINUX-0) 1.0');
      Halt(0);
    End Else If Not EndOptions and(Length(Argument)>1)and
      (Argument[1]='-')Then Begin
      If Copy(LanguageCode,1,2)='EN'Then
        WriteLn('checkeq: unknown option: ',Argument)
      Else WriteLn('checkeq : option inconnue : ',Argument);
      Halt(2);
    End Else Begin
      If FileCount>=MaxFiles Then Begin
        If Copy(LanguageCode,1,2)='EN'Then
          WriteLn('checkeq: too many files')
        Else WriteLn('checkeq : trop de fichiers');
        Halt(2);
      End;
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
        WriteLn('checkeq: cannot read ',FileName)
      Else WriteLn('checkeq : impossible de lire ',FileName);
      Inc(ErrorCount);
    End Else Begin
      CheckStream(SourceFile,FileName);
      Close(SourceFile);
    End;
  End;
  If ErrorCount>0 Then Halt(1);
END.