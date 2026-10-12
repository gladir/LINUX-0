{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program FROMDOS;

Uses DOS;

Const
 BufferSize=1024;
 MaxFiles=32;

Type
 TFileName=String[127];
 TByteBuffer=Array[1..BufferSize]Of Byte;

Var
 SourceFile,TargetFile,SwapFile:File;
 InputBuffer,OutputBuffer:TByteBuffer;
 FileNames:Array[1..MaxFiles]Of TFileName;
 FileCount,Index:Integer;
 BytesRead,BufferPosition,OutputCount,WriteCount,ErrorCode:Word;
 OriginalAttr:Word;
 OriginalTime:LongInt;
 SourceName,TempName,BackupName,SwapName:TFileName;
 ToUnix,AlwaysConvert,MakeBackup,AbortOnError,ForceReadOnly:Boolean;
 PreserveTime,Verbose,OverwriteNoBackup:Boolean;
 ErrorFound,StopProcessing,FileFailed:Boolean;
 PendingCR,Changed:Boolean;
 OldFileMode:Byte;
 StandardInputLine:String[255];

Procedure ReportError(Const Name,MessageText:TFileName);
Begin
 WriteLn('fromdos: ',Name,': ',MessageText);
 ErrorFound:=True;
 FileFailed:=True;
 If AbortOnError Then StopProcessing:=True;
End;

Procedure ShowHelp;
Begin
 WriteLn('FROMDOS - Cette commnande permet de convertir automatiquement les fins de ligne DOS et Unix.');
 WriteLn;
 WriteLn('Syntaxe: FROMDOS [options] fichier ...');
 WriteLN;
 WriteLn('  -a  Toujours reecrire le fichier, meme sans changement');
 WriteLn('  -b  Garder l''original dans un fichier .BAK');
 WriteLn('  -d  Convertir DOS vers Unix (defaut)');
 WriteLn('  -u  Convertir Unix vers DOS');
 WriteLn('  -e  Arreter au premier fichier en erreur');
 WriteLn('  -f  Autoriser la conversion des fichiers en lecture seule');
 WriteLn('  -o  Remplacer l''original sans sauvegarde');
 WriteLn('  -p  Preserver la date et l''heure DOS');
 WriteLn('  -v  Afficher les fichiers traites');
 WriteLn('  -h, --help  Afficher cette aide');
 WriteLn('  -V, --version  Afficher la version');
 WriteLn('DOS ne gere pas le proprietaire Unix; -p conserve seulement la date/heure.');
End;

Procedure ShowVersion;
Begin
 WriteLn('fromdos 1.0 - LINUX-0 Pascal');
End;

Function FileExists(Const Name:TFileName):Boolean;
Var
 SearchData:SearchRec;
 Found:Boolean;
Begin
 FindFirst(Name,AnyFile,SearchData);
 Found:=DosError=0;
 FileExists:=Found;
 {$IFDEF FPC}
 If Found Then FindClose(SearchData);
 {$ENDIF}
End;

Function MakeSideName(Const Name,Extension:TFileName):TFileName;
Var
 NameIndex,SlashPosition,DotPosition:Integer;
 DirectoryPart,BaseName:String;
Begin
 SlashPosition:=0;
 DotPosition:=0;
 For NameIndex:=1 To Length(Name)Do Begin
  If(Name[NameIndex]='\')Or(Name[NameIndex]='/')Then Begin
   SlashPosition:=NameIndex;
   DotPosition:=0;
  End Else If Name[NameIndex]='.'Then DotPosition:=NameIndex;
 End;
 DirectoryPart:=Copy(Name,1,SlashPosition);
 If DotPosition>SlashPosition Then
  BaseName:=Copy(Name,SlashPosition+1,DotPosition-SlashPosition-1)
 Else BaseName:=Copy(Name,SlashPosition+1,Length(Name));
 If Length(BaseName)>9-Length(Extension)Then
  BaseName:=Copy(BaseName,1,9-Length(Extension));
 If BaseName=''Then BaseName:='F';
 MakeSideName:=DirectoryPart+BaseName+Extension;
End;

Function FindTemporaryName(Const Name:TFileName;Kind:Char):TFileName;
Var
 Number:Integer;
 Suffix,Candidate:TFileName;
Begin
 FindTemporaryName:='';
 For Number:=0 To 99 Do Begin
  Suffix:='.'+Kind+Chr(Ord('0')+(Number Div 10))+
              Chr(Ord('0')+(Number Mod 10));
  Candidate:=MakeSideName(Name,Suffix);
  If(Candidate<>Name)And Not FileExists(Candidate)Then Begin
   FindTemporaryName:=Candidate;
   Exit;
  End;
 End;
End;

Procedure FlushOutput;
Begin
 If OutputCount=0 Then Exit;
 {$I-}BlockWrite(TargetFile,OutputBuffer,OutputCount,WriteCount);{$I+}
 ErrorCode:=IOResult;
 If(ErrorCode<>0)Or(WriteCount<>OutputCount)Then
  ReportError(SourceName,'erreur durant l''ecriture du temporaire');
 OutputCount:=0;
End;

Procedure PutByte(Value:Byte);
Begin
 Inc(OutputCount);
 OutputBuffer[OutputCount]:=Value;
 If OutputCount=BufferSize Then FlushOutput;
End;

Procedure ConvertByte(Value:Byte);
Begin
 If ToUnix Then Begin
  If PendingCR Then Begin
   If Value=10 Then Begin
    PutByte(10);
    Changed:=True;
    PendingCR:=False;
    Exit;
   End Else Begin
    PutByte(13);
    PendingCR:=False;
   End;
  End;
  If Value=13 Then PendingCR:=True
  Else PutByte(Value);
 End Else Begin
  If PendingCR Then Begin
   If Value=10 Then Begin
    PutByte(13);
    PutByte(10);
    PendingCR:=False;
    Exit;
   End Else Begin
    PutByte(13);
    PendingCR:=False;
   End;
  End;
  If Value=13 Then PendingCR:=True
  Else If Value=10 Then Begin
   PutByte(13);
   PutByte(10);
   Changed:=True;
  End Else PutByte(Value);
 End;
End;

Procedure DeleteTemporary;
Var
 IgnoredError:Word;
Begin
 Assign(TargetFile,TempName);
 {$I-}Erase(TargetFile);{$I+}
 IgnoredError:=IOResult;
End;

Procedure RestoreOriginal;
Var
 IgnoredError:Word;
Begin
 Assign(SwapFile,SwapName);
 {$I-}Rename(SwapFile,SourceName);{$I+}
 IgnoredError:=IOResult;
 If ForceReadOnly And(OriginalAttr And ReadOnly<>0)Then Begin
  Assign(SourceFile,SourceName);
  {$I-}SetFAttr(SourceFile,OriginalAttr);{$I+}
  IgnoredError:=IOResult;
 End;
End;

Procedure ReplaceOriginal;
Var
 RenameError,IgnoredError:Word;
Begin
 Assign(SourceFile,SourceName);
 If MakeBackup And Not OverwriteNoBackup Then Begin
  BackupName:=MakeSideName(SourceName,'.BAK');
  If FileExists(BackupName)Then Begin
   ReportError(SourceName,'le fichier de sauvegarde existe deja');
   Exit;
  End;
  {$I-}Rename(SourceFile,BackupName);{$I+}
  RenameError:=IOResult;
  If RenameError<>0 Then Begin
   ReportError(SourceName,'impossible de creer la sauvegarde');
   Exit;
  End;
  Assign(TargetFile,TempName);
  {$I-}Rename(TargetFile,SourceName);{$I+}
  RenameError:=IOResult;
  If RenameError<>0 Then Begin
   Assign(SourceFile,BackupName);
   {$I-}Rename(SourceFile,SourceName);{$I+}
   IgnoredError:=IOResult;
   ReportError(SourceName,'impossible d''installer le fichier converti');
   Exit;
  End;
 End Else Begin
  SwapName:=FindTemporaryName(SourceName,'S');
  If SwapName=''Then Begin
   ReportError(SourceName,'impossible de trouver un nom temporaire');
   Exit;
  End;
  {$I-}Rename(SourceFile,SwapName);{$I+}
  RenameError:=IOResult;
  If RenameError<>0 Then Begin
   ReportError(SourceName,'impossible de remplacer le fichier');
   Exit;
  End;
  Assign(TargetFile,TempName);
  {$I-}Rename(TargetFile,SourceName);{$I+}
  RenameError:=IOResult;
  If RenameError<>0 Then Begin
   RestoreOriginal;
   ReportError(SourceName,'impossible d''installer le fichier converti');
   Exit;
  End;
  Assign(SwapFile,SwapName);
  {$I-}Erase(SwapFile);{$I+}
  IgnoredError:=IOResult;
 End;
 Assign(SourceFile,SourceName);
 {$I-}SetFAttr(SourceFile,OriginalAttr);{$I+}
 IgnoredError:=IOResult;
 If PreserveTime Then Begin
  OldFileMode:=FileMode;
  FileMode:=2;
  {$I-}Reset(SourceFile);{$I+}
  RenameError:=IOResult;
  FileMode:=OldFileMode;
  If RenameError=0 Then Begin
   {$I-}SetFTime(SourceFile,OriginalTime);{$I+}
   IgnoredError:=IOResult;
   {$I-}Close(SourceFile);{$I+}
   IgnoredError:=IOResult;
  End;
 End;
End;

Procedure ProcessFile(Const Name:TFileName);
Var
 BufferIndex:Word;
 FileOpenError:Word;
Begin
 SourceName:=Name;
 FileFailed:=False;
 Assign(SourceFile,SourceName);
 GetFAttr(SourceFile,OriginalAttr);
 If DosError<>0 Then Begin
  ReportError(SourceName,'fichier introuvable');
  Exit;
 End;
 If((OriginalAttr And ReadOnly)<>0)And Not ForceReadOnly Then Begin
  ReportError(SourceName,'fichier en lecture seule (utilisez -f)');
  Exit;
 End;
 OldFileMode:=FileMode;
 FileMode:=0;
 {$I-}Reset(SourceFile,1);{$I+}
 FileOpenError:=IOResult;
 FileMode:=OldFileMode;
 If FileOpenError<>0 Then Begin
  ReportError(SourceName,'impossible de lire le fichier');
  Exit;
 End;
 If PreserveTime Then GetFTime(SourceFile,OriginalTime);
 TempName:=FindTemporaryName(SourceName,'T');
 If TempName=''Then Begin
  {$I-}Close(SourceFile);{$I+}
  ErrorCode:=IOResult;
  ReportError(SourceName,'impossible de trouver un nom temporaire');
  Exit;
 End;
 Assign(TargetFile,TempName);
 {$I-}Rewrite(TargetFile,1);{$I+}
 FileOpenError:=IOResult;
 If FileOpenError<>0 Then Begin
  {$I-}Close(SourceFile);{$I+}
  ErrorCode:=IOResult;
  ReportError(SourceName,'impossible de creer le fichier temporaire');
  Exit;
 End;
 BytesRead:=0;
 OutputCount:=0;
 PendingCR:=False;
 Changed:=False;
 Repeat
  {$I-}BlockRead(SourceFile,InputBuffer,SizeOf(InputBuffer),BytesRead);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
   ReportError(SourceName,'erreur durant la lecture');
   Break;
  End;
  For BufferIndex:=1 To BytesRead Do ConvertByte(InputBuffer[BufferIndex]);
 Until(BytesRead=0)Or FileFailed;
 If PendingCR Then PutByte(13);
 FlushOutput;
 {$I-}Close(SourceFile);{$I+}
 ErrorCode:=IOResult;
 {$I-}Close(TargetFile);{$I+}
 FileOpenError:=IOResult;
 If ErrorCode<>0 Then
  ReportError(SourceName,'erreur a la fermeture du fichier source');
 If FileOpenError<>0 Then
  ReportError(SourceName,'erreur a la fermeture du temporaire');
 If FileFailed Then Begin
  DeleteTemporary;
  Exit;
 End;
 If Not Changed And Not AlwaysConvert Then Begin
  DeleteTemporary;
  If Verbose Then WriteLn(SourceName,': deja converti');
  Exit;
 End;
 If ForceReadOnly And(OriginalAttr And ReadOnly<>0)Then Begin
  Assign(SourceFile,SourceName);
  {$I-}SetFAttr(SourceFile,OriginalAttr And Not ReadOnly);{$I+}
  ErrorCode:=IOResult;
  If ErrorCode<>0 Then Begin
   DeleteTemporary;
   ReportError(SourceName,'impossible de retirer l''attribut lecture seule');
   Exit;
  End;
 End;
 ReplaceOriginal;
 If FileFailed Then DeleteTemporary
 Else If Verbose Then WriteLn(SourceName,': converti');
End;

Procedure AddFile(Const Name:TFileName);
Begin
 If FileCount>=MaxFiles Then Begin
  WriteLn('fromdos: trop de fichiers');
  Halt(2);
 End;
 Inc(FileCount);
 FileNames[FileCount]:=Name;
End;

Procedure ProcessStandardInput;
Var
 CharacterIndex:Integer;
Begin
 While Not EOF(Input)Do Begin
  ReadLn(Input,StandardInputLine);
  For CharacterIndex:=1 To Length(StandardInputLine)Do
   Write(StandardInputLine[CharacterIndex]);
  If ToUnix Then Write(#10)
  Else Write(#13,#10);
 End;
End;

Procedure ParseOptions;
Var
 ArgumentIndex,OptionPosition:Integer;
 Argument:TFileName;
Begin
 FileCount:=0;
 ToUnix:=True;
 AlwaysConvert:=False;
 MakeBackup:=False;
 AbortOnError:=False;
 ForceReadOnly:=False;
 PreserveTime:=False;
 Verbose:=False;
 OverwriteNoBackup:=False;
 ErrorFound:=False;
 StopProcessing:=False;
 ArgumentIndex:=1;
 While ArgumentIndex<=ParamCount Do Begin
  Argument:=ParamStr(ArgumentIndex);
  If(Argument='--help')Or(Argument='-h')Or(Argument='/?')Or
    (Argument='/h')Or(Argument='/H')Then Begin ShowHelp;Halt(0);End
  Else If(Argument='--version')Or(Argument='-V')Then Begin
   ShowVersion;
   Halt(0);
  End Else If Argument='--'Then Begin
   Inc(ArgumentIndex);
   While ArgumentIndex<=ParamCount Do Begin
    AddFile(ParamStr(ArgumentIndex));
    Inc(ArgumentIndex);
   End;
   Exit;
  End Else If(Length(Argument)>1)And(Argument[1]='-')Then Begin
   OptionPosition:=2;
   While OptionPosition<=Length(Argument)Do Begin
    Case Argument[OptionPosition]Of
     'a':AlwaysConvert:=True;
     'b':MakeBackup:=True;
     'd':ToUnix:=True;
     'e':AbortOnError:=True;
     'f':ForceReadOnly:=True;
     'o':OverwriteNoBackup:=True;
     'p':PreserveTime:=True;
     'u':ToUnix:=False;
     'v':Verbose:=True;
    Else Begin
     WriteLn('fromdos: option inconnue: -',Argument[OptionPosition]);
     Halt(2);
    End;
    End;
    Inc(OptionPosition);
   End;
  End Else AddFile(Argument);
  Inc(ArgumentIndex);
 End;
 If MakeBackup And OverwriteNoBackup Then MakeBackup:=False;
End;

Begin
 ParseOptions;
 If FileCount=0 Then ProcessStandardInput
 Else For Index:=1 To FileCount Do Begin
   ProcessFile(FileNames[Index]);
   If StopProcessing Then Break;
  End;
 If ErrorFound Then Halt(1);
End.