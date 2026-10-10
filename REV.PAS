{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Reverse the characters in each input line)
}

Program REV(Input,Output);

Uses DOS;

Const
  InputBufferSize=4096;
  LineBlockSize=1024;

Type
  TInputBuffer=Array[0..InputBufferSize-1]Of Byte;
  TLineBlockData=Array[1..LineBlockSize]Of Byte;
  PLineBlock=^TLineBlock;
  TLineBlock=Record
    Previous,Next:PLineBlock;
    Count:Integer;
    Data:TLineBlockData;
  End;

Var
  SourceFile:File;
  InputBuffer:TInputBuffer;
  FirstBlock,LastBlock,NewBlock:PLineBlock;
  InputLength,InputPosition,ReadCount:Word;
  LineByteCount:LongInt;
  InputFileName:String[255];
  LanguageCode:String[20];
  InputIsStandard,InputError:Boolean;
  PendingCR:Boolean;

Procedure WriteByte(Value:Byte);
Begin
  Write(Output,Chr(Value));
End;

Procedure ClearLine;
Var
  Block,NextBlock:PLineBlock;
Begin
  Block:=FirstBlock;
  While Block<>Nil Do Begin
    NextBlock:=Block^.Next;
    Dispose(Block);
    Block:=NextBlock;
  End;
  FirstBlock:=Nil;
  LastBlock:=Nil;
  LineByteCount:=0;
End;

Procedure AppendByte(Value:Byte);
Begin
  If(LastBlock=Nil)or(LastBlock^.Count=LineBlockSize)Then Begin
    New(NewBlock);
    NewBlock^.Previous:=LastBlock;
    NewBlock^.Next:=Nil;
    NewBlock^.Count:=0;
    If LastBlock<>Nil Then LastBlock^.Next:=NewBlock
    Else FirstBlock:=NewBlock;
    LastBlock:=NewBlock;
  End;
  Inc(LastBlock^.Count);
  LastBlock^.Data[LastBlock^.Count]:=Value;
  Inc(LineByteCount);
End;

Procedure EmitLine(NewLineStyle:Byte);
Var
  Block:PLineBlock;
  Index:Integer;
Begin
  Block:=LastBlock;
  While Block<>Nil Do Begin
    For Index:=Block^.Count downto 1 Do WriteByte(Block^.Data[Index]);
    Block:=Block^.Previous;
  End;
  If NewLineStyle=1 Then WriteByte(10)
  Else If NewLineStyle=2 Then Begin WriteByte(13);WriteByte(10);End;
  ClearLine;
End;

Procedure ProcessInputByte(Value:Byte);
Begin
  If PendingCR Then Begin
    PendingCR:=False;
    If Value=10 Then Begin
      EmitLine(2);
      Exit;
    End;
    AppendByte(13);
  End;
  If Value=13 Then PendingCR:=True
  Else If Value=10 Then EmitLine(1)
  Else AppendByte(Value);
End;

Procedure ReadFileInput;
Begin
  InputPosition:=0;
  InputLength:=0;
  InputError:=False;
  PendingCR:=False;
  While True Do Begin
    If InputPosition>=InputLength Then Begin
      {$I-}BlockRead(SourceFile,InputBuffer,SizeOf(InputBuffer),ReadCount);{$I+}
      If IOResult<>0 Then Begin InputError:=True;Break;End;
      InputLength:=ReadCount;
      InputPosition:=0;
      If InputLength=0 Then Break;
    End;
    ProcessInputByte(InputBuffer[InputPosition]);
    Inc(InputPosition);
  End;
  If PendingCR Then Begin AppendByte(13);PendingCR:=False;End;
  If LineByteCount>0 Then EmitLine(0);
End;

Procedure ReadStandardInput;
Var
  Character:Char;
Begin
  PendingCR:=False;
  While Not EOF(Input)Do Begin
    If Eoln(Input)Then Begin
      ReadLn(Input);
      EmitLine(1);
    End Else Begin
      Read(Input,Character);
      AppendByte(Ord(Character));
    End;
  End;
  If LineByteCount>0 Then EmitLine(0);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('rev - reverse characters in each line');
    WriteLn('Usage: rev [file]');
    WriteLn('Reads standard input when no file is specified.');
  End Else Begin
    WriteLn('REV - Cette commande permet d''inverser les caract'+#138+'res de chaque ligne.');
    WriteLn;
    WriteLn('Syntaxe : rev [fichier]');
    WriteLn;
    WriteLn('Options :');
    WriteLn(' -h, --help, -?  Affiche cette aide');
    WriteLn(' -V, --version   Affiche la version');
    WriteLn;
    WriteLn('Sans fichier, lit l''entree standard.');
  End;
End;

Procedure UsageError;
Begin
  If Copy(LanguageCode,1,2)='EN'Then WriteLn('Usage: rev [file]')
  Else WriteLn('Syntaxe : rev [fichier]');
  Halt(2);
End;

Var
  ErrorCode:Integer;
Begin
  FirstBlock:=Nil;
  LastBlock:=Nil;
  LineByteCount:=0;
  InputIsStandard:=ParamCount=0;
  LanguageCode:=GetEnv('LANGUAGE');
  If(ParamCount=1)and((ParamStr(1)='-h')or(ParamStr(1)='--help')or
    (ParamStr(1)='-?')or(ParamStr(1)='/?'))Then Begin
    PrintHelp;
    Halt(0);
  End;
  If(ParamCount=1)and((ParamStr(1)='-V')or(ParamStr(1)='--version'))Then Begin
    WriteLn('rev (LINUX-0) 1.0');
    Halt(0);
  End;
  If ParamCount>1 Then UsageError;
  If InputIsStandard Then ReadStandardInput
  Else Begin
    InputFileName:=ParamStr(1);
    Assign(SourceFile,InputFileName);
    FileMode:=0;
    {$I-}Reset(SourceFile,1);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      If Copy(LanguageCode,1,2)='EN'Then WriteLn('rev: cannot open ',InputFileName)
      Else WriteLn('rev : impossible d''ouvrir ',InputFileName);
      Halt(1);
    End;
    ReadFileInput;
    {$I-}Close(SourceFile);{$I+}
    ErrorCode:=IOResult;
    If ErrorCode<>0 Then Begin
      If Copy(LanguageCode,1,2)='EN'Then WriteLn('rev: error closing ',InputFileName)
      Else WriteLn('rev : erreur a la fermeture de ',InputFileName);
      Halt(1);
    End;
  End;
  ClearLine;
  If InputError Then Halt(1);
END.
