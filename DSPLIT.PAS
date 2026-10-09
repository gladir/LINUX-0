{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program DSPLIT;

Uses DOS;

Const
  CopyBufferSize=4096;
  MaxPieces=1000;
  DefaultPieceSize=1440000;

Type
  TCopyBuffer=Array[0..CopyBufferSize-1]Of Byte;

Var
  SourceFile,TargetFile:File;
  Buffer:TCopyBuffer;
  InputName,OutputBase,OutputName,Argument,LanguageCode:String;
  PieceSize,Remaining,TotalBytes:LongInt;
  PieceNumber,ArgumentIndex,FileCount,ErrorCode:Integer;
  ReadCount,WriteCount,Requested:Word;
  FileOpened,ErrorFound,QuietMode:Boolean;
  Search:SearchRec;

Procedure ReportError(Const MessageText:String);
Begin
  If Not QuietMode Then WriteLn('dsplit: ',MessageText);
  ErrorFound:=True;
End;

Procedure OptionError(Const MessageText:String);
Begin
  WriteLn('dsplit: ',MessageText);
  Halt(2);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('DSPLIT : Split a large file into numbered binary pieces.');
    WriteLn('Syntax: dsplit [-size N] [input_file [output_base]]');
    WriteLn(' -size N  Maximum size of each output piece in bytes');
    WriteLn('If output_base is omitted, the default prefix is x.');
    WriteLn('Pieces are named output_base000, output_base001, and so on.');
  End Else Begin
    WriteLn('DSPLIT : Cette commande permet de d'+#130+'couper un fichier volumineux en morceaux binaires num'+#130+'rotes.');
    WriteLn;
    WriteLn('Syntaxe : dsplit [-size N] [fichier_entree [base_sortie]]');
    WriteLn;
    WriteLn(' -size N  Taille maximale de chaque morceau en octets');
    WriteLn('Sans base_sortie, le prefixe utilise est x.');
    WriteLn('Les morceaux sont nommes base_sortie000, base_sortie001, etc.');
  End;
End;

Function FileExistsTP(Const Name:String):Boolean;
Begin
  FindFirst(Name,AnyFile,Search);
  FileExistsTP:=(DosError=0)and((Search.Attr and Directory)=0);
  {$IFDEF FPC}FindClose(Search);{$ENDIF}
End;

Function PieceName(Number:Integer):String;
Var
  Digits:String;
Begin
  Str(Number,Digits);
  While Length(Digits)<3 Do Digits:='0'+Digits;
  PieceName:=OutputBase+Digits;
End;

Procedure SplitFile;
Var
  PieceBytes:LongInt;
Begin
  If OutputBase=''Then OutputBase:='x';
  If(OutputBase='')or(Length(OutputBase)>124)Then
    OptionError('base de sortie invalide ou trop longue');
  Assign(SourceFile,InputName);
  FileMode:=0;
  {$I-}Reset(SourceFile,1);{$I+}
  If IOResult<>0 Then Begin ReportError('impossible de lire '+InputName);Exit;End;
  FileOpened:=True;
  Remaining:=FileSize(SourceFile);
  TotalBytes:=0;
  PieceNumber:=0;
  Repeat
    If PieceNumber>=MaxPieces Then Begin
      ReportError('limite de 1000 morceaux depassee');
      Break;
    End;
    OutputName:=PieceName(PieceNumber);
    If FileExistsTP(OutputName)Then Begin
      ReportError('le fichier de sortie existe deja: '+OutputName);
      Break;
    End;
    Assign(TargetFile,OutputName);
    FileMode:=1;
    {$I-}Rewrite(TargetFile,1);{$I+}
    If IOResult<>0 Then Begin ReportError('impossible de creer '+OutputName);Break;End;
    PieceBytes:=0;
    While(PieceBytes<PieceSize)and(Remaining>0)Do Begin
      Requested:=CopyBufferSize;
      If Remaining<Requested Then Requested:=Remaining;
      If PieceSize-PieceBytes<Requested Then Requested:=PieceSize-PieceBytes;
      {$I-}BlockRead(SourceFile,Buffer,Requested,ReadCount);{$I+}
      If(IOResult<>0)or(ReadCount=0)Then Begin
        ReportError('erreur de lecture dans '+InputName);
        Break;
      End;
      {$I-}BlockWrite(TargetFile,Buffer,ReadCount,WriteCount);{$I+}
      If(IOResult<>0)or(WriteCount<>ReadCount)Then Begin
        ReportError('erreur d''ecriture dans '+OutputName);
        Break;
      End;
      Inc(PieceBytes,ReadCount);
      Inc(TotalBytes,ReadCount);
      Dec(Remaining,ReadCount);
    End;
    Close(TargetFile);
    If ErrorFound Then Begin
      Assign(TargetFile,OutputName);{$I-}Erase(TargetFile);{$I+}ErrorCode:=IOResult;
      Break;
    End;
    If Not QuietMode Then WriteLn(OutputName,' (',PieceBytes,' octets)');
    Inc(PieceNumber);
  Until Remaining=0;
  If FileOpened Then Begin Close(SourceFile);FileOpened:=False;End;
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  PieceSize:=DefaultPieceSize;
  QuietMode:=False;ErrorFound:=False;FileOpened:=False;
  InputName:='';OutputBase:='';FileCount:=0;ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('dsplit (LINUX-0) 1.0');Halt(0);End
    Else If(Argument='-q')Then QuietMode:=True
    Else If(Argument='-size')or(Argument='-s')Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then OptionError('-size attend un nombre');
      Val(ParamStr(ArgumentIndex),PieceSize,ErrorCode);
      If(ErrorCode<>0)or(PieceSize<1)Then OptionError('taille de morceau invalide');
    End Else If(Length(Argument)>6)and(Copy(Argument,1,6)='-size=')Then Begin
      Val(Copy(Argument,7,255),PieceSize,ErrorCode);
      If(ErrorCode<>0)or(PieceSize<1)Then OptionError('taille de morceau invalide');
    End Else If(Length(Argument)>1)and(Argument[1]='-')Then
      OptionError('option inconnue: '+Argument)
    Else Begin
      Inc(FileCount);
      If FileCount>2 Then OptionError('un fichier source et une base de sortie au maximum');
      If FileCount=1 Then InputName:=Argument Else OutputBase:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If InputName=''Then Begin PrintHelp;Halt(2);End;
  ArgumentIndex:=1;
  SplitFile;
  If ErrorFound Then Halt(1);
END.