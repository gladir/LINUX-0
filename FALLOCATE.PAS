{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program FALLOCATE;

Uses DOS;

Const
 BufferSize=4096;
 MaxFileLength=2147483646;

Type
 TFileName=String[127];
 TText=String[255];
 TByteBuffer=Array[1..BufferSize]Of Byte;

Var
 TargetFile:File;
 Buffer:TByteBuffer;
 FileName:TFileName;
 Argument,ValueText:TText;
 OffsetValue,LengthValue,EndPosition,CurrentSize,ZeroEnd:LongInt;
 BytesToWrite,WriteCount:Word;
 ArgumentIndex,ErrorCode,Index:Integer;
 KeepSize,PunchHole,LengthSpecified,FileOpened:Boolean;
 HelpRequested,VersionRequested:Boolean;
 OldFileMode:Byte;

Procedure ShowHelp;
Begin
 WriteLn('FALLOCATE - Cette commande permet d''allouer une plage dans un fichier.');
 WriteLn;
 WriteLn('Syntaxe: FALLOCATE [options] fichier');
 WriteLn;
 WriteLn('  -h, --help          Afficher cette aide');
 WriteLn('  -V, --version       Afficher la version');
 WriteLn('  -l, --length N      Taille de la plage, en octets');
 WriteLn('  -o, --offset N      Position de la plage, en octets');
 WriteLn('  -n, --keep-size     Ne pas modifier la longueur du fichier');
 WriteLn('  -p, --punch-hole    Remplacer par des zeros dans la plage existante');
 WriteLn;
 WriteLn('Limites DOS: pas de reservation sparse hors longueur logique;');
 WriteLn('punch-hole ecrit des zeros mais ne libere pas les blocs du disque.');
End;

Procedure OptionError(Const MessageText:TText);
Begin
 WriteLn('fallocate: ',MessageText);
 Halt(2);
End;

Function ParseNumber(Const NumberText:TText;Const OptionName:TText):LongInt;
Var
 Parsed:LongInt;
 Err:Integer;
Begin
 Val(NumberText,Parsed,Err);
 If(Err<>0)Or(Parsed<0)Then
  OptionError('valeur invalide pour '+OptionName+': '+NumberText);
 ParseNumber:=Parsed;
End;

Function GetOptionValue(Var Index:Integer;Const OptionName,InlineValue:TText):TText;
Begin
 If InlineValue<>''Then GetOptionValue:=InlineValue
 Else Begin
  Inc(Index);
  If Index>ParamCount Then OptionError('valeur manquante pour '+OptionName);
  GetOptionValue:=ParamStr(Index);
 End;
End;

Procedure ParseOptions;
Var
 Index,EqualPosition:Integer;
 OptionText,OptionValue,OptionName:TText;
 StopOptions:Boolean;
Begin
 FileName:='';
 OffsetValue:=0;
 LengthValue:=0;
 LengthSpecified:=False;
 KeepSize:=False;
 PunchHole:=False;
 HelpRequested:=False;
 VersionRequested:=False;
 StopOptions:=False;
 Index:=1;
 While Index<=ParamCount Do Begin
  OptionText:=ParamStr(Index);
  If StopOptions Then Begin
   If FileName<>''Then OptionError('un seul fichier peut etre traite');
   FileName:=OptionText;
  End Else If OptionText='--'Then StopOptions:=True
  Else If(OptionText='-h')Or(OptionText='--help')Or
          (OptionText='/?')Or(OptionText='/h')Or(OptionText='/H')Then
   HelpRequested:=True
  Else If(OptionText='-V')Or(OptionText='--version')Then
   VersionRequested:=True
  Else If(OptionText='-n')Or(OptionText='--keep-size')Then
   KeepSize:=True
  Else If(OptionText='-p')Or(OptionText='--punch-hole')Then Begin
   PunchHole:=True;
   KeepSize:=True;
  End Else If(OptionText='-l')Or(OptionText='--length')Or
              (Copy(OptionText,1,2)='-l')Or
              (Copy(OptionText,1,9)='--length=')Then Begin
   If Copy(OptionText,1,9)='--length='Then Begin
    OptionName:='--length';
    OptionValue:=Copy(OptionText,10,255);
   End Else If Copy(OptionText,1,2)='-l'Then Begin
    OptionName:='-l';
    OptionValue:=Copy(OptionText,3,255);
   End Else Begin
    OptionName:=OptionText;
    OptionValue:='';
   End;
   ValueText:=GetOptionValue(Index,OptionName,OptionValue);
   LengthValue:=ParseNumber(ValueText,OptionName);
   LengthSpecified:=True;
  End Else If(OptionText='-o')Or(OptionText='--offset')Or
              (Copy(OptionText,1,2)='-o')Or
              (Copy(OptionText,1,9)='--offset=')Then Begin
   If Copy(OptionText,1,9)='--offset='Then Begin
    OptionName:='--offset';
    OptionValue:=Copy(OptionText,10,255);
   End Else If Copy(OptionText,1,2)='-o'Then Begin
    OptionName:='-o';
    OptionValue:=Copy(OptionText,3,255);
   End Else Begin
    OptionName:=OptionText;
    OptionValue:='';
   End;
   ValueText:=GetOptionValue(Index,OptionName,OptionValue);
   OffsetValue:=ParseNumber(ValueText,OptionName);
  End Else If(Length(OptionText)>0)And(OptionText[1]='-')Then
   OptionError('option inconnue: '+OptionText)
  Else Begin
   If FileName<>''Then OptionError('un seul fichier peut etre traite');
   FileName:=OptionText;
  End;
  Inc(Index);
 End;
 If HelpRequested Or VersionRequested Then Exit;
 If FileName=''Then OptionError('nom de fichier manquant');
 If Not LengthSpecified Then OptionError('la taille -l/--length est obligatoire');
 If LengthValue=0 Then OptionError('la taille doit etre superieure a zero');
 If OffsetValue>MaxFileLength-LengthValue Then
  OptionError('la plage depasse la taille maximale geree par DOS');
End;

Procedure OpenTarget;
Begin
 Assign(TargetFile,FileName);
 OldFileMode:=FileMode;
 FileMode:=2;
 {$I-}Reset(TargetFile,1);{$I+}
 ErrorCode:=IOResult;
 If ErrorCode<>0 Then Begin
  {$I-}Rewrite(TargetFile,1);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
   FileMode:=OldFileMode;
   WriteLn('fallocate: impossible de creer ',FileName);
   Halt(1);
  End;
 End;
 FileMode:=OldFileMode;
 FileOpened:=True;
End;

Procedure WriteZeros(StartOffset,EndOffset:LongInt);
Var
 Remaining,ChunkSize:LongInt;
 ChunkCount:Word;
Begin
 Remaining:=EndOffset-StartOffset;
 If Remaining<=0 Then Exit;
 For Index:=1 To BufferSize Do Buffer[Index]:=0;
 Seek(TargetFile,StartOffset);
 While Remaining>0 Do Begin
  If Remaining>BufferSize Then ChunkSize:=BufferSize
                          Else ChunkSize:=Remaining;
  ChunkCount:=ChunkSize;
  {$I-}BlockWrite(TargetFile,Buffer,ChunkCount,WriteCount);{$I+}
  ErrorCode:=IOResult;
  If(ErrorCode<>0)Or(WriteCount<>ChunkCount)Then Begin
   WriteLn('fallocate: erreur durant l''ecriture de ',FileName);
   Close(TargetFile);
   FileOpened:=False;
   Halt(1);
  End;
  Dec(Remaining,ChunkSize);
 End;
End;

Procedure AllocateRange;
Begin
 OpenTarget;
 CurrentSize:=FileSize(TargetFile);
 EndPosition:=OffsetValue+LengthValue;
 If PunchHole Then Begin
  ZeroEnd:=EndPosition;
  If ZeroEnd>CurrentSize Then ZeroEnd:=CurrentSize;
  If OffsetValue<ZeroEnd Then WriteZeros(OffsetValue,ZeroEnd);
 End Else If KeepSize Then Begin
  If EndPosition>CurrentSize Then Begin
   Close(TargetFile);
   FileOpened:=False;
   WriteLn('fallocate: --keep-size avec extension impossible sous DOS');
   Halt(1);
  End;
 End Else If EndPosition>CurrentSize Then Begin
  Seek(TargetFile,EndPosition-1);
  Buffer[1]:=0;
  {$I-}BlockWrite(TargetFile,Buffer,1,WriteCount);{$I+}
  ErrorCode:=IOResult;
  If(ErrorCode<>0)Or(WriteCount<>1)Then Begin
   WriteLn('fallocate: impossible d''allouer la plage demandee');
   Close(TargetFile);
   FileOpened:=False;
   Halt(1);
  End;
 End;
 {$I-}Close(TargetFile);{$I+}
 ErrorCode:=IOResult;
 FileOpened:=False;
 If ErrorCode<>0 Then Begin
  WriteLn('fallocate: erreur a la fermeture de ',FileName);
  Halt(1);
 End;
 If PunchHole Then
  WriteLn('fallocate: plage mise a zero; les blocs disque ne sont pas liberes');
End;

BEGIN
 FileOpened:=False;
 ParseOptions;
 If HelpRequested Then Begin ShowHelp;Halt(0);End;
 If VersionRequested Then Begin
  WriteLn('fallocate 1.0 - LINUX-0 Pascal');
  Halt(0);
 End;
 AllocateRange;
END.