{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program AR;

Uses DOS;

Const
  ArMagic:Array[1..8]Of Char=('!','<','a','r','c','h','>',#10);
  ArHeaderSize=60;
  BufferSize=4096;
  MaxFiles=64;

Type
  TArHeader=Array[1..ArHeaderSize]Of Char;
  TBuffer=Array[1..BufferSize]Of Byte;
  TFileNames=Array[1..MaxFiles]Of String;

Var
  ArchiveFile,TempFile,MemberFile,ExtractFile:File;
  Header:TArHeader;
  Buffer:TBuffer;
  Files:TFileNames;
  ArchiveName,TempArchiveName,BackupArchiveName:String;
  MemberName,MemberField,PositionMember:String;
  Operation,PositionMode:Char;
  FileCount:Integer;
  ArchiveSize,BodyOffset,RawMemberSize,MemberDataOffset,MemberDataSize:LongInt;
  StringTableOffset,StringTableSize:LongInt;
  IsSpecial,HasPosition,Verbose,ArchiveExists:Boolean;
  ReadCount,WriteCount:Word;

Function TrimRightText(S:String):String;
Begin
  While(Length(S)>0)and(S[Length(S)]=' ')Do
    S[0]:=Chr(Length(S)-1);
  TrimRightText:=S;
End;

Function TrimText(S:String):String;
Var
  First:Integer;
Begin
  First:=1;
  While(First<=Length(S))and(S[First]=' ')Do Inc(First);
  TrimText:=TrimRightText(Copy(S,First,Length(S)));
End;

Function BaseName(Const S:String):String;
Var
  I,Start:Integer;
Begin
  Start:=1;
  For I:=1 to Length(S)Do
    If(S[I]='/')or(S[I]='\')Then Start:=I+1;
  BaseName:=Copy(S,Start,Length(S));
End;

Function ParseDecimal(Const S:String; Var Value:LongInt):Boolean;
Var
  ErrorCode:Integer;
  T:String;
Begin
  T:=TrimText(S);
  Val(T,Value,ErrorCode);
  ParseDecimal:=ErrorCode=0;
End;

Function HeaderString(Start,Count:Integer):String;
Var
  I:Integer;
  S:String;
Begin
  S:='';
  For I:=Start to Start+Count-1 Do S:=S+Header[I];
  HeaderString:=S;
End;

Function ReadArchiveHeader:Boolean;
Var
  Count:Word;
  I:Integer;
  NameLength:LongInt;
  OffsetText:String;
Begin
  ReadArchiveHeader:=False;
  If FilePos(ArchiveFile)+ArHeaderSize>ArchiveSize Then Exit;
  BlockRead(ArchiveFile,Header,ArHeaderSize,Count);
  If Count<>ArHeaderSize Then Exit;
  If(Header[59]<>'`')or(Header[60]<>#10)Then Exit;
  BodyOffset:=FilePos(ArchiveFile);
  If Not ParseDecimal(HeaderString(49,10),RawMemberSize)Then Exit;
  If RawMemberSize<0 Then Exit;
  If BodyOffset+RawMemberSize+(RawMemberSize mod 2)>ArchiveSize Then Exit;
  MemberField:=TrimText(HeaderString(1,16));
  MemberName:=MemberField;
  MemberDataOffset:=BodyOffset;
  MemberDataSize:=RawMemberSize;
  IsSpecial:=False;
  If(MemberField='/')or(MemberField='/SYM64/')or(MemberField='//')Then
    IsSpecial:=True;
  If MemberField='//'Then Begin
    StringTableOffset:=BodyOffset;
    StringTableSize:=RawMemberSize;
  End Else If Copy(MemberField,1,3)='#1/'Then Begin
    OffsetText:=Copy(MemberField,4,Length(MemberField));
    If Not ParseDecimal(OffsetText,NameLength)Then Exit;
    If(NameLength<0)or(NameLength>RawMemberSize)Then Exit;
    MemberName:='';
    For I:=0 to NameLength-1 Do Begin
      Seek(ArchiveFile,BodyOffset+I);
      BlockRead(ArchiveFile,Buffer,1,ReadCount);
      If(ReadCount<>1)or(Length(MemberName)>=255)Then Exit;
      MemberName:=MemberName+Chr(Buffer[1]);
    End;
    MemberDataOffset:=BodyOffset+NameLength;
    MemberDataSize:=RawMemberSize-NameLength;
    IsSpecial:=False;
  End Else If(Length(MemberField)>1)and(MemberField[1]='/')and
    (MemberField[2]in['0'..'9'])Then Begin
    OffsetText:=Copy(MemberField,2,Length(MemberField));
    If Not ParseDecimal(OffsetText,NameLength)Then Exit;
    If(NameLength<0)or(NameLength>=StringTableSize)Then Exit;
    MemberName:='';
    For I:=0 to 254 Do Begin
      If NameLength+I>=StringTableSize Then Break;
      Seek(ArchiveFile,StringTableOffset+NameLength+I);
      BlockRead(ArchiveFile,Buffer,1,ReadCount);
      If ReadCount<>1 Then Exit;
      If(Buffer[1]=Ord('/'))or(Buffer[1]=10)Then Break;
      MemberName:=MemberName+Chr(Buffer[1]);
    End;
    IsSpecial:=False;
  End Else If(Length(MemberName)>0)and
    (MemberName[Length(MemberName)]='/')Then
    MemberName:=Copy(MemberName,1,Length(MemberName)-1);
  ReadArchiveHeader:=True;
End;

Function FileExistsTP(Name:String):Boolean;
Var
  Search:SearchRec;
Begin
  FindFirst(Name,AnyFile,Search);
  FileExistsTP:=DosError=0;
  {$IFDEF FPC}FindClose(Search);{$ENDIF}
End;

Procedure WriteMagic(Var F:File);
Var
  MagicBuffer:Array[1..8]Of Char;
  Count:Word;
  I:Integer;
Begin
  For I:=1 to 8 Do MagicBuffer[I]:=ArMagic[I];
  BlockWrite(F,MagicBuffer,8,Count);
End;

Function CheckArchive(Var F:File):Boolean;
Var
  MagicBuffer:Array[1..8]Of Char;
  Count:Word;
  I:Integer;
Begin
  CheckArchive:=False;
  Seek(F,0);
  BlockRead(F,MagicBuffer,8,Count);
  If Count<>8 Then Exit;
  For I:=1 to 8 Do If MagicBuffer[I]<>ArMagic[I]Then Exit;
  CheckArchive:=True;
End;

Procedure CopyBytes(Var SourceFile,DestFile:File; Count:LongInt);
Var
  Requested:Word;
  Read:Word;
Begin
  While Count>0 Do Begin
    If Count>BufferSize Then Requested:=BufferSize Else Requested:=Word(Count);
    BlockRead(SourceFile,Buffer,Requested,Read);
    If(Read=0)or(Read<>Requested)Then Begin
      WriteLn('Erreur : lecture incomplete de l''archive');
      Halt(1);
    End;
    BlockWrite(DestFile,Buffer,Read,WriteCount);
    If WriteCount<>Read Then Begin
      WriteLn('Erreur : ecriture incomplete de l''archive');
      Halt(1);
    End;
    Dec(Count,Read);
  End;
End;

Procedure CopyRawMember(Var DestFile:File);
Var
  NextOffset:LongInt;
  Pad:Byte;
  Count:Word;
Begin
  Seek(ArchiveFile,BodyOffset);
  BlockWrite(DestFile,Header,ArHeaderSize,Count);
  If Count<>ArHeaderSize Then Begin
    WriteLn('Erreur : ecriture impossible');
    Halt(1);
  End;
  CopyBytes(ArchiveFile,DestFile,RawMemberSize);
  If(RawMemberSize mod 2)=1Then Begin
    Seek(ArchiveFile,BodyOffset+RawMemberSize);
    BlockRead(ArchiveFile,Pad,1,Count);
    If Count=1Then BlockWrite(DestFile,Pad,1,Count);
  End;
  NextOffset:=BodyOffset+RawMemberSize+(RawMemberSize mod 2);
  Seek(ArchiveFile,NextOffset);
End;

Function MakeField(Const S:String; Width:Integer):String;
Var
  T:String;
Begin
  T:=Copy(S,1,Width);
  While Length(T)<Width Do T:=T+' ';
  MakeField:=T;
End;

Procedure PutField(Start,Width:Integer; Const S:String);
Var
  I:Integer;
  T:String;
Begin
  T:=MakeField(S,Width);
  For I:=1 to Width Do Header[Start+I-1]:=T[I];
End;

Procedure WriteMemberHeader(Var DestFile:File; Const Name:String;
                            DataSize:LongInt; BSDNameLength:Integer);
Var
  NameField,DateField,UIDField,GIDField,ModeField,SizeField:String;
  Count:Word;
Begin
  For Count:=1 to ArHeaderSize Do Header[Count]:=' ';
  If BSDNameLength>0 Then Begin
    Str(BSDNameLength,NameField);
    NameField:='#1/'+NameField;
  End Else Begin
    NameField:=Name+'/';
  End;
  DateField:='0';
  UIDField:='0';
  GIDField:='0';
  ModeField:='100644';
  Str(DataSize,SizeField);
  PutField(1,16,NameField);
  PutField(17,12,DateField);
  PutField(29,6,UIDField);
  PutField(35,6,GIDField);
  PutField(41,8,ModeField);
  PutField(49,10,SizeField);
  Header[59]:='`';
  Header[60]:=#10;
  BlockWrite(DestFile,Header,ArHeaderSize,Count);
  If Count<>ArHeaderSize Then Begin
    WriteLn('Erreur : impossible d''ecrire l''entete');
    Halt(1);
  End;
End;

Procedure AddFileToArchive(Var DestFile:File; Const Path:String);
Var
  Name:String;
  FileSizeValue,RawSize:LongInt;
  BSDNameLength:Integer;
  Pad:Byte;
  Count:Word;
Begin
  {$I-}Assign(MemberFile,Path);
  Reset(MemberFile,1);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : fichier introuvable : ',Path);
    Halt(1);
  End;
  FileSizeValue:=FileSize(MemberFile);
  Name:=BaseName(Path);
  BSDNameLength:=0;
  If(Length(Name)>15)or(Pos(' ',Name)>0)Then BSDNameLength:=Length(Name);
  RawSize:=FileSizeValue+BSDNameLength;
  WriteMemberHeader(DestFile,Name,RawSize,BSDNameLength);
  If BSDNameLength>0 Then Begin
    For Count:=1 to BSDNameLength Do Begin
      Buffer[1]:=Ord(Name[Count]);
      BlockWrite(DestFile,Buffer,1,WriteCount);
    End;
  End;
  CopyBytes(MemberFile,DestFile,FileSizeValue);
  If(RawSize mod 2)=1Then Begin
    Pad:=10;
    BlockWrite(DestFile,Pad,1,Count);
  End;
  Close(MemberFile);
  If Verbose Then WriteLn('a - ',Name);
End;

Function IsRequested(Const Name:String):Boolean;
Var
  I:Integer;
Begin
  IsRequested:=False;
  If FileCount=0 Then Begin
    IsRequested:=True;
    Exit;
  End;
  For I:=1 to FileCount Do
    If(Name=Files[I])or(Name=BaseName(Files[I]))Then Begin
      IsRequested:=True;
      Exit;
    End;
End;

Function IsInputFile(Const Name:String):Boolean;
Var
  I:Integer;
Begin
  IsInputFile:=False;
  For I:=1 to FileCount Do
    If(Name=BaseName(Files[I]))or(Name=Files[I])Then Begin
      IsInputFile:=True;
      Exit;
    End;
End;

Procedure ShowMember(Const Name:String);
Var
  Count,I:Word;
Begin
  If Verbose Then Write(Name,' ');
  Seek(ArchiveFile,MemberDataOffset);
  While MemberDataSize>0 Do Begin
    If MemberDataSize>BufferSize Then Count:=BufferSize
                                 Else Count:=Word(MemberDataSize);
    BlockRead(ArchiveFile,Buffer,Count,ReadCount);
    If ReadCount<>Count Then Begin
      WriteLn('Erreur : membre tronque : ',Name);
      Halt(1);
    End;
    For I:=1 to Count Do Write(Output,Chr(Buffer[I]));
    Dec(MemberDataSize,Count);
  End;
  If Verbose Then WriteLn;
End;

Procedure ListMember(Const Name:String);
Begin
  WriteLn(Name);
End;

Procedure ExtractMember(Const Name:String);
Var
  SafeName:String;
  Count:Word;
Begin
  SafeName:=BaseName(Name);
  If SafeName=''Then Exit;
  {$I-}Assign(ExtractFile,SafeName);
  Rewrite(ExtractFile,1);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de creer ',SafeName);
    Halt(1);
  End;
  Seek(ArchiveFile,MemberDataOffset);
  While MemberDataSize>0 Do Begin
    If MemberDataSize>BufferSize Then Count:=BufferSize
                                 Else Count:=Word(MemberDataSize);
    BlockRead(ArchiveFile,Buffer,Count,ReadCount);
    If ReadCount<>Count Then Begin
      Close(ExtractFile);
      WriteLn('Erreur : membre tronque : ',Name);
      Halt(1);
    End;
    BlockWrite(ExtractFile,Buffer,Count,WriteCount);
    Dec(MemberDataSize,Count);
  End;
  Close(ExtractFile);
  If Verbose Then WriteLn('x - ',SafeName);
End;

Procedure CopySelectedMembers(Var DestFile:File);
Var
  NextOffset:LongInt;
  SavedHeader:TArHeader;
  SavedName,SavedField:String;
  SavedBodyOffset,SavedRawSize,SavedDataOffset,SavedDataSize:LongInt;
  SavedSpecial:Boolean;
Begin
  SavedHeader:=Header;
  SavedName:=MemberName;
  SavedField:=MemberField;
  SavedBodyOffset:=BodyOffset;
  SavedRawSize:=RawMemberSize;
  SavedDataOffset:=MemberDataOffset;
  SavedDataSize:=MemberDataSize;
  SavedSpecial:=IsSpecial;
  Seek(ArchiveFile,8);
  While FilePos(ArchiveFile)<ArchiveSize Do Begin
    If Not ReadArchiveHeader Then Break;
    NextOffset:=BodyOffset+RawMemberSize+(RawMemberSize mod 2);
    If Not IsSpecial and IsRequested(MemberName)Then CopyRawMember(DestFile)
                                               Else Seek(ArchiveFile,NextOffset);
  End;
  Header:=SavedHeader;
  MemberName:=SavedName;
  MemberField:=SavedField;
  BodyOffset:=SavedBodyOffset;
  RawMemberSize:=SavedRawSize;
  MemberDataOffset:=SavedDataOffset;
  MemberDataSize:=SavedDataSize;
  IsSpecial:=SavedSpecial;
End;

Procedure AddInputFiles(Var DestFile:File);
Var
  I:Integer;
  SavedHeader:TArHeader;
Begin
  SavedHeader:=Header;
  For I:=1 to FileCount Do AddFileToArchive(DestFile,Files[I]);
  Header:=SavedHeader;
End;

Procedure RewriteArchive;
Var
  NextOffset:LongInt;
  Selected,Keep,MovedWritten,FilesWritten:Boolean;
Begin
  If Length(ArchiveName)>245 Then Begin
    WriteLn('Erreur : nom d''archive trop long');
    Halt(1);
  End;
  TempArchiveName:=ArchiveName+'.tmp';
  BackupArchiveName:=ArchiveName+'.bak';
  If ArchiveExists Then Begin
    Assign(ArchiveFile,ArchiveName);
    Reset(ArchiveFile,1);
    ArchiveSize:=FileSize(ArchiveFile);
    StringTableOffset:=-1;
    StringTableSize:=0;
  End;
  If FileExistsTP(TempArchiveName)Then Begin
    Assign(TempFile,TempArchiveName);
    {$I-}Erase(TempFile);{$I+}
    If IOResult<>0 Then Begin
    End;
  End;
  Assign(TempFile,TempArchiveName);
  Rewrite(TempFile,1);
  WriteMagic(TempFile);
  MovedWritten:=False;
  FilesWritten:=False;
  If ArchiveExists Then Begin
    Seek(ArchiveFile,8);
    While FilePos(ArchiveFile)<ArchiveSize Do Begin
      If Not ReadArchiveHeader Then Begin
        Close(TempFile);
        WriteLn('Erreur : entete ar invalide');
        Halt(1);
      End;
      NextOffset:=BodyOffset+RawMemberSize+(RawMemberSize mod 2);
      Selected:=Not IsSpecial and IsRequested(MemberName);
      Keep:=True;
      Case Operation Of
        'd':If Selected Then Keep:=False;
        'r':If Selected and IsInputFile(MemberName)Then Keep:=False;
        'm':If Selected Then Keep:=False;
      End;
      If(Operation='m')and HasPosition and Not MovedWritten and
        (MemberName=PositionMember)and(PositionMode in['b','i'])Then Begin
        CopySelectedMembers(TempFile);
        MovedWritten:=True;
      End;
      If(Operation='r')and HasPosition and Not FilesWritten and
        (MemberName=PositionMember)and(PositionMode in['b','i'])Then Begin
        AddInputFiles(TempFile);
        FilesWritten:=True;
      End;
      If Keep Then CopyRawMember(TempFile)
             Else Seek(ArchiveFile,NextOffset);
      If(Operation='m')and HasPosition and Not MovedWritten and
        (MemberName=PositionMember)and(PositionMode='a')Then Begin
        CopySelectedMembers(TempFile);
        MovedWritten:=True;
      End;
      If(Operation='r')and HasPosition and Not FilesWritten and
        (MemberName=PositionMember)and(PositionMode='a')Then Begin
        AddInputFiles(TempFile);
        FilesWritten:=True;
      End;
      Seek(ArchiveFile,NextOffset);
    End;
  End;
  If(Operation='m')and Not MovedWritten Then CopySelectedMembers(TempFile);
  If(Operation='r')and Not FilesWritten Then AddInputFiles(TempFile);
  Close(TempFile);
  If ArchiveExists Then Close(ArchiveFile);
  If ArchiveExists Then Begin
    If FileExistsTP(BackupArchiveName)Then Begin
      Assign(TempFile,BackupArchiveName);
      {$I-}Erase(TempFile);{$I+}
      If IOResult<>0 Then Begin
      End;
    End;
    Assign(ArchiveFile,ArchiveName);
    Assign(TempFile,BackupArchiveName);
    {$I-}Rename(ArchiveFile,BackupArchiveName);{$I+}
    If IOResult<>0 Then Begin
      WriteLn('Erreur : impossible de sauvegarder l''archive');
      Halt(1);
    End;
  End;
  Assign(TempFile,TempArchiveName);
  Assign(ArchiveFile,ArchiveName);
  {$I-}Rename(TempFile,ArchiveName);{$I+}
  If IOResult<>0 Then Begin
    If ArchiveExists Then Begin
      Assign(TempFile,BackupArchiveName);
      Assign(ArchiveFile,ArchiveName);
      {$I-}Rename(TempFile,ArchiveName);{$I+}
      If IOResult<>0 Then Begin
      End;
    End;
    WriteLn('Erreur : impossible de remplacer l''archive');
    Halt(1);
  End;
  If ArchiveExists Then Begin
    Assign(TempFile,BackupArchiveName);
    {$I-}Erase(TempFile);{$I+}
    If IOResult<>0 Then Begin
    End;
  End;
  ArchiveExists:=True;
End;

Procedure AppendFiles;
Var
  I:Integer;
Begin
  If Not ArchiveExists Then Begin
    Assign(ArchiveFile,ArchiveName);
    Rewrite(ArchiveFile,1);
    WriteMagic(ArchiveFile);
  End Else Begin
    Assign(ArchiveFile,ArchiveName);
    Reset(ArchiveFile,1);
    Seek(ArchiveFile,FileSize(ArchiveFile));
  End;
  For I:=1 to FileCount Do AddFileToArchive(ArchiveFile,Files[I]);
  Close(ArchiveFile);
End;

Procedure ProcessArchive;
Var
  NextOffset:LongInt;
Begin
  If Not ArchiveExists Then Begin
    WriteLn('Erreur : archive introuvable : ',ArchiveName);
    Halt(1);
  End;
  Assign(ArchiveFile,ArchiveName);
  {$I-}Reset(ArchiveFile,1);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('Erreur : impossible de lire ',ArchiveName);
    Halt(1);
  End;
  ArchiveSize:=FileSize(ArchiveFile);
  If Not CheckArchive(ArchiveFile)Then Begin
    Close(ArchiveFile);
    WriteLn('Erreur : archive ar invalide');
    Halt(1);
  End;
  StringTableOffset:=-1;
  StringTableSize:=0;
  Seek(ArchiveFile,8);
  While FilePos(ArchiveFile)<ArchiveSize Do Begin
    If Not ReadArchiveHeader Then Begin
      Close(ArchiveFile);
      WriteLn('Erreur : entete ar invalide');
      Halt(1);
    End;
    NextOffset:=BodyOffset+RawMemberSize+(RawMemberSize mod 2);
    If Not IsSpecial and IsRequested(MemberName)Then Begin
      Case Operation Of
        't':ListMember(MemberName);
        'p':ShowMember(MemberName);
        'x':ExtractMember(MemberName);
      End;
    End;
    Seek(ArchiveFile,NextOffset);
  End;
  Close(ArchiveFile);
End;

Procedure PrintHelp;
Begin
  WriteLn('AR : Cette commande permet de manipuler une archive Unix ar.');
  WriteLn;
  WriteLn('Syntaxe : ar [options] d|m|p|q|r|t|x [archive] [fichiers...]');
  WriteLn;
  WriteLn(' d  Supprime les membres; m  deplace les membres en fin d''archive');
  WriteLn(' p  Ecrit les membres sur stdout; q  ajoute; r  remplace/ajoute');
  WriteLn(' t  Liste les membres; x  extrait les membres');
  WriteLn(' v  Affichage detaille; V  version');
  WriteLn;
  WriteLn('Format standard pris en charge; l''index des symboles ELF n''est pas regenere.');
End;

Procedure ParseOptions;
Var
  Param,OptionText:String;
  I,ActionCount:Integer;
  PositionFlag:Boolean;
Begin
  If ParamCount=0 Then Begin
    PrintHelp;
    Halt(0);
  End;
  Param:=ParamStr(1);
  If(Param='--help')or(Param='-h')or(Param='/?')or(Param='/h')or
    (Param='/H')Then Begin
    PrintHelp;
    Halt(0);
  End;
  If(Param='--version')or(Param='-V')Then Begin
    WriteLn('ar (LINUX-0) 1.0');
    Halt(0);
  End;
  If(Param[1]='-')Then OptionText:=Copy(Param,2,Length(Param))
                    Else OptionText:=Param;
  Operation:=' ';
  ActionCount:=0;
  Verbose:=False;
  PositionFlag:=False;
  PositionMode:=' ';
  For I:=1 to Length(OptionText)Do Begin
    If OptionText[I]in['d','m','p','q','r','t','x']Then Begin
      Operation:=OptionText[I];
      Inc(ActionCount);
    End Else If OptionText[I]in['a','b','i']Then Begin
      PositionFlag:=True;
      PositionMode:=OptionText[I];
    End Else
    If OptionText[I]='v'Then Verbose:=True Else
    If OptionText[I]='V'Then Begin
      WriteLn('ar (LINUX-0) 1.0');
      Halt(0);
    End Else If Not(OptionText[I]in['c','l','o','s','u'])Then Begin
      WriteLn('Erreur : option ar inconnue : ',OptionText[I]);
      Halt(2);
    End;
  End;
  If ActionCount<>1 Then Begin
    WriteLn('Erreur : une seule operation ar doit etre indiquee');
    Halt(2);
  End;
  If PositionFlag and Not(Operation in['m','r'])Then Begin
    WriteLn('Erreur : a, b et i ne sont valides qu''avec m ou r');
    Halt(2);
  End;
  I:=2;
  If PositionFlag Then Begin
    If I>ParamCount Then Begin
      WriteLn('Erreur : membre de position manquant');
      Halt(2);
    End;
    PositionMember:=ParamStr(I);
    HasPosition:=True;
    Inc(I);
  End Else HasPosition:=False;
  If I>ParamCount Then Begin
    WriteLn('Erreur : nom d''archive manquant');
    Halt(2);
  End;
  ArchiveName:=ParamStr(I);
  Inc(I);
  FileCount:=0;
  While I<=ParamCount Do Begin
    If FileCount>=MaxFiles Then Begin
      WriteLn('Erreur : trop de fichiers');
      Halt(2);
    End;
    Inc(FileCount);
    Files[FileCount]:=ParamStr(I);
    Inc(I);
  End;
  If(Operation in['d','m'])and(FileCount=0)Then Begin
    WriteLn('Erreur : au moins un nom de membre est requis');
    Halt(2);
  End;
End;

BEGIN
  StringTableOffset:=-1;
  StringTableSize:=0;
  ArchiveName:='';
  ArchiveExists:=False;
  HasPosition:=False;
  Verbose:=False;
  ParseOptions;
  Assign(ArchiveFile,ArchiveName);
  {$I-}Reset(ArchiveFile,1);{$I+}
  If IOResult=0Then Begin
    ArchiveExists:=True;
    ArchiveSize:=FileSize(ArchiveFile);
    If Not CheckArchive(ArchiveFile)Then Begin
      Close(ArchiveFile);
      WriteLn('Erreur : archive ar invalide');
      Halt(1);
    End;
    StringTableOffset:=-1;
    StringTableSize:=0;
    Close(ArchiveFile);
  End;
  If Not ArchiveExists And(Operation in['d','m','p','t','x'])Then Begin
    WriteLn('Erreur : archive introuvable : ',ArchiveName);
    Halt(1);
  End;
  Case Operation Of
    't','p','x':ProcessArchive;
    'q':Begin
      If FileCount=0 Then Begin
        WriteLn('Erreur : aucun fichier a ajouter');
        Halt(2);
      End;
      AppendFiles;
    End;
    'd','m':RewriteArchive;
    'r':Begin
      If FileCount=0 Then Begin
        WriteLn('Erreur : aucun fichier a ajouter ou remplacer');
        Halt(2);
      End;
      RewriteArchive;
    End;
  End;
END.
