{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Maintenance MALL et MyISAM 3.23/4.0 sans index.
    Slots statiques, lignes dynamiques et BLOB; pas de compression ou RAID.
}

Program MYISAMCHK;

{$IFDEF FPC}
 {$MODE TP}
 {$H-}
{$ENDIF}

Uses DOS;

Const
 DataMagic='MALLMYD1';
 IndexMagic='MALLMYI1';
 MaxLong=2147483647;

Type
 TMagic=Array[0..7]of Char;
 TDataHeader=Packed Record
  Magic:TMagic;
  RecSize,RecCount,ActiveCount:Longint;
  Reserved:Array[0..11]of Byte;
 End;
 TIndexHeader=Packed Record
  Magic:TMagic;
  KeySize:Word;
  EntryCount:Longint;
  Reserved:Array[0..17]of Byte;
 End;
 TEntry=Packed Record
  Status:Byte;
  Key:Array[0..15]of Char;
  DataOfs:Longint;
 End;
 TMode=(_Check,_Recover,_Optimize,_Describe);
 PDynamicBlock=^TDynamicBlock;
 TDynamicBlock=Record
  Offset,Span,Payload,DataLength,RowLength,NextOffset,PrevOffset:Longint;
  Kind:Byte;
  Used:Boolean;
  Following:PDynamicBlock;
 End;

Var
 Mode:TMode;
 English,Silent,Verbose,EndOptions,AnyTable,AnyError:Boolean;
 Arg,BaseName,DataName,IndexName,TempData,TempIndex,BackupData,BackupIndex:String;
 D,F,TD,TI:File;
 DOpen,FOpen,TDOpen,TIOpen,MadeTD,MadeTI:Boolean;
 IOFailed,CanRepair:Boolean;
 DH:TDataHeader;
 IH:TIndexHeader;
 DataSize,IndexSize,SlotSize,Slots,Entries,Active,Problems:Longint;
 CopyBuffer:Array[0..4095]of Byte;
 ArgIndex:Integer;
 Native,NativeSupported:Boolean;
 NativeState:Array[0..175]of Byte;
 NativeBase:Array[0..99]of Byte;
 NativeRef,NativeOptions,NativeKeys:Word;
 NativeKeyStart,NativeRecLength,NativeDeleted:Longint;
 NativeDynamic:Boolean;
 NativeFields,NativeDefinitions,NativePackBits:Longint;
 DynamicBlocks,DynamicCursor:PDynamicBlock;
 DynamicCount,DynamicFree,DynamicPosition,DynamicRemaining:Longint;
 DynamicFlags:Array[0..1169]of Byte;

Function Upper(S:String):String;
Var J:Integer;
Begin
 For J:=1 to Length(S)Do
  If S[J]in['a'..'z']Then S[J]:=Chr(Ord(S[J])-32);
 Upper:=S;
End;

Function Msg(Const FR,EN:String):String;
Begin
 If English Then Msg:=EN Else Msg:=FR;
End;

Function Number(N:Longint):String;
Var S:String;
Begin
 Str(N,S);
 Number:=S;
End;

Procedure Diagnostic(Const S:String);
{$IFNDEF FPC}
Var R:Registers; Line:String;
{$ENDIF}
Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'myisamchk: ',S);
 {$ELSE}
 Line:='myisamchk: '+S+#13+#10;
 R.AH:=$40;
 R.BX:=2;
 R.CX:=Length(Line);
 R.DS:=Seg(Line[1]);
 R.DX:=Ofs(Line[1]);
 MsDos(R);
 {$ENDIF}
End;

Procedure Error(Const S:String);
Begin
 Diagnostic(S);
 AnyError:=True;
End;

Procedure IOError(Const Operation:String);
Begin
 Error(BaseName+': '+Operation);
 IOFailed:=True;
End;

Procedure Issue(Const S:String;Repairable:Boolean);
Begin
 Inc(Problems);
 Diagnostic(BaseName+': '+S);
 If Not Repairable Then CanRepair:=False;
End;

Function ReadAt(Var H:File;Offset:Longint;Var Buffer;Count:Word):Boolean;
Var Got:Word; Code:Integer;
Begin
 ReadAt:=False;
 {$I-}Seek(H,Offset);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('erreur de positionnement en lecture','read seek error'));
  Exit;
 End;
 {$I-}BlockRead(H,Buffer,Count,Got);{$I+}
 Code:=IOResult;
 If(Code<>0)Or(Got<>Count)Then Begin
  IOError(Msg('lecture incomplete ou erreur de lecture','short read or read error'));
  Exit;
 End;
 ReadAt:=True;
End;

Function WriteData(Var H:File;Var Buffer;Count:Word):Boolean;
Var Done:Word; Code:Integer;
Begin
 WriteData:=False;
 {$I-}BlockWrite(H,Buffer,Count,Done);{$I+}
 Code:=IOResult;
 If(Code<>0)Or(Done<>Count)Then Begin
  IOError(Msg('ecriture incomplete ou erreur d''ecriture','short write or write error'));
  Exit;
 End;
 WriteData:=True;
End;

Procedure CloseFile(Var H:File;Var Opened:Boolean);
Begin
 If Not Opened Then Exit;
 {$I-}Close(H);{$I+}
 Opened:=False;
 If IOResult<>0Then IOError(Msg('erreur de fermeture','close error'));
End;

Function Exists(Const Name:String):Boolean;
Var SR:SearchRec; Code:Integer;
Begin
 FindFirst(Name,AnyFile,SR);
 Code:=DosError;
 Exists:=Code=0;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
 If(Code<>0)And(Code<>2)And(Code<>3)And(Code<>18)Then Begin
  IOError(Msg('impossible de verifier le chemin : ','cannot inspect path: ')+Name);
  Exists:=True;
 End;
End;

Procedure RemoveTemp(Const Name:String;Var Made:Boolean);
Var H:File;
Begin
 If Not Made Then Exit;
 Assign(H,Name);
 {$I-}Erase(H);{$I+}
 If IOResult<>0Then IOError(Msg('impossible de supprimer : ','cannot remove: ')+Name)
 Else Made:=False;
End;

Function MoveFile(Const OldName,NewName:String):Boolean;
Var H:File;
Begin
 MoveFile:=False;
 If Exists(NewName)Then Begin
  IOError(Msg('le chemin existe deja : ','path already exists: ')+NewName);
  Exit;
 End;
 Assign(H,OldName);
 {$I-}Rename(H,NewName);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('renommage impossible : ','cannot rename: ')+OldName+' -> '+NewName);
  Exit;
 End;
 MoveFile:=True;
End;

Function OpenSource(Var H:File;Const Name:String;Var Opened:Boolean):Boolean;
Begin
 OpenSource:=False;
 Assign(H,Name);
 { Lecture seule, partage interdit : ne jamais travailler sur une table ouverte. }
 FileMode:=16;
 {$I-}Reset(H,1);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('ouverture exclusive impossible : ','cannot open exclusively: ')+Name);
  Exit;
 End;
 Opened:=True;
 OpenSource:=True;
End;

Function SourceSize(Var H:File;Var Size:Longint):Boolean;
Var
 {$IFDEF FPC}
 Value:Int64;
 {$ELSE}
 Value:Longint;
 {$ENDIF}
 Code:Integer;
Begin
 SourceSize:=False;
 {$I-}Value:=FileSize(H);{$I+}
 Code:=IOResult;
 If(Code<>0)Or(Value<0)Or(Value>MaxLong)Then Begin
  IOError(Msg('taille inaccessible ou fichier de plus de 2 Gio',
              'size unavailable or file larger than 2 GiB'));
  Exit;
 End;
 Size:=Value;
 SourceSize:=True;
End;

Function CreateTemp(Var H:File;Const Name:String;
                    Var Opened,Made:Boolean):Boolean;
Begin
 CreateTemp:=False;
 If Exists(Name)Then Begin
  IOError(Msg('le fichier temporaire existe deja : ','temporary path already exists: ')+Name);
  Exit;
 End;
 If IOFailed Then Exit;
 Assign(H,Name);
 FileMode:=18;
 {$I-}Rewrite(H,1);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('creation impossible : ','cannot create: ')+Name);
  Exit;
 End;
 Opened:=True;
 Made:=True;
 CreateTemp:=True;
End;

Function MagicIs(Const Magic:TMagic;Const S:String):Boolean;
Var J:Integer; OK:Boolean;
Begin
 OK:=True;
 For J:=0 to 7Do If Magic[J]<>S[J+1]Then OK:=False;
 MagicIs:=OK;
End;

Function EntryAt(N:Longint;Var E:TEntry):Boolean;
Begin
 EntryAt:=ReadAt(F,32+N*21,E,21);
End;

Function ValidOffset(Offset:Longint):Boolean;
Begin
 ValidOffset:=False;
 If Offset<32Then Exit;
 If Offset>=DataSize Then Exit;
 ValidOffset:=((Offset-32)Mod SlotSize)=0;
End;

Function StatusAt(Offset:Longint;Var Status:Byte):Boolean;
Begin
 StatusAt:=ReadAt(D,Offset,Status,1);
End;

Function SameKey(Const A,B:TEntry):Boolean;
Var J:Integer; OK:Boolean;
Begin
 OK:=True;
 For J:=0 to 15Do If A.Key[J]<>B.Key[J]Then OK:=False;
 SameKey:=OK;
End;

Function FindForSlot(Offset:Longint;Var Found:TEntry;Var Matches:Longint):Boolean;
Var N:Longint; E:TEntry;
Begin
 FindForSlot:=False;
 Matches:=0;
 For N:=0 to Entries-1Do Begin
  If Not EntryAt(N,E)Then Exit;
  If E.DataOfs=Offset Then Begin
   Found:=E;
   Inc(Matches);
  End;
 End;
 FindForSlot:=True;
End;

{ Layout commun a MySQL 3.23.58 et 4.0.30, mi_open.c et myisampack.h.
  Contrairement a MALL, les entiers natifs sont big-endian. }
Function ReadBE(Var Buffer;Count:Word;AllowEnd:Boolean):Longint;
Type TBytes=Array[0..175]of Byte;
Var P:^TBytes; J:Word; Value:Longint; AllFF:Boolean;
Begin
 P:=@Buffer;
 AllFF:=True;
 For J:=0 to Count-1Do If P^[J]<>255Then AllFF:=False;
 If AllFF And AllowEnd Then Begin
  ReadBE:=-1;
  Exit;
 End;
 Value:=0;
 For J:=0 to Count-1Do Begin
  If Value>(MaxLong-P^[J])Div 256Then Begin
   ReadBE:=-2;
   Exit;
  End;
  Value:=Value*256+P^[J];
 End;
 ReadBE:=Value;
End;

Procedure StoreBE(Var Buffer;Count:Word;Value:Longint);
Type TBytes=Array[0..175]of Byte;
Var P:^TBytes; J:Integer;
Begin
 P:=@Buffer;
 If Value=-1Then FillChar(Buffer,Count,255)
 Else
  For J:=Count-1Downto 0Do Begin
   P^[J]:=Value Mod 256;
   Value:=Value Div 256;
  End;
End;

Function NativeLoad:Boolean;
Var BasePos,HeaderLength,StateLength,BaseLength,Parts,Blocks:Longint;
    Fields,Definitions,TotalLength,J,FieldLength,FieldType,PackedFields,Blobs:Longint;
    Column:Array[0..6]of Byte;
Begin
 NativeLoad:=False;
 Native:=True;
 NativeSupported:=False;
 If IndexSize<176Then Begin
  Error(BaseName+': '+Msg('en-tete MyISAM tronque','truncated MyISAM header'));
  Exit;
 End;
 If Not ReadAt(F,0,NativeState,176)Then Exit;
 HeaderLength:=ReadBE(NativeState[6],2,False);
 StateLength:=ReadBE(NativeState[8],2,False);
 BaseLength:=ReadBE(NativeState[10],2,False);
 BasePos:=ReadBE(NativeState[12],2,False);
 Parts:=ReadBE(NativeState[14],2,False);
 NativeKeys:=NativeState[18];
 Blocks:=NativeState[21];
 If(StateLength<>176)Or(BaseLength<>100)Or
   (BasePos<>176+NativeKeys*8+Blocks*8+Parts*4)Or
   (BasePos+100>HeaderLength)Or(HeaderLength>IndexSize)Then Begin
  Error(BaseName+': '+Msg(
   'en-tete invalide ou layout incompatible avec MyISAM 3.23/4.0',
   'invalid header or layout incompatible with MyISAM 3.23/4.0'));
  Exit;
 End;
 If Not ReadAt(F,BasePos,NativeBase,100)Then Exit;
 NativeOptions:=ReadBE(NativeState[4],2,False);
 NativeDynamic:=(NativeOptions And 1)<>0;
 NativeKeyStart:=ReadBE(NativeBase[0],8,False);
 NativeRecLength:=ReadBE(NativeBase[44],4,False);
 SlotSize:=ReadBE(NativeBase[48],4,False);
 NativeRef:=NativeBase[72];
 If(NativeKeyStart<HeaderLength)Or(NativeKeyStart>IndexSize)Or
   (NativeKeyStart Mod 1024<>0)Or
   (NativeRecLength<=0)Or(SlotSize<=0)Or
   (NativeRef<2)Or(NativeRef>8)Or
   (NativeBase[73]<2)Or(NativeBase[73]>8)Or
   (NativeKeys<>NativeBase[74])Then Begin
  Error(BaseName+': '+Msg('description MyISAM invalide ou taille non geree',
                         'invalid MyISAM description or unsupported size'));
  Exit;
 End;
 If Not OpenSource(D,DataName,DOpen)Then Exit;
 If Not SourceSize(D,DataSize)Then Exit;
 NativeSupported:=(NativeKeys=0)And(NativeState[19]=0)And
  (Parts=0)And(ReadBE(NativeState[16],2,False)=0)And(Blocks=0)And
  (NativeState[22]=0)And(NativeState[23]=0)And
  ((NativeOptions And Not(1+2+8+16+32+64+128))=0)And
  (NativeBase[87]=0);
 If Not NativeDynamic Then
  NativeSupported:=NativeSupported And
   (ReadBE(NativeBase[78],2,False)=0)And((NativeOptions And 8)=0);
 If NativeSupported Then Begin
  Fields:=ReadBE(NativeBase[64],4,False);
  Definitions:=BasePos+100;
  NativeFields:=Fields;
  NativeDefinitions:=Definitions;
  NativePackBits:=ReadBE(NativeBase[76],2,False);
  If(Fields<=0)Or(Fields>(HeaderLength-Definitions)Div 7)Or
    (Definitions+Fields*7<>HeaderLength)Or
    (ReadBE(NativeBase[68],4,False)<>NativePackBits)Or
    (NativePackBits>SizeOf(DynamicFlags))Or
    (NativeBase[75]<>0)Then Begin
   Error(BaseName+': '+Msg('definitions de colonnes incoherentes',
                          'inconsistent column definitions'));
   Exit;
  End;
  TotalLength:=0;
  PackedFields:=0;
  Blobs:=0;
  For J:=0 to Fields-1Do Begin
   If Not ReadAt(F,Definitions+J*7,Column,7)Then Exit;
   FieldType:=ReadBE(Column[0],2,False);
   If Not((FieldType=0)Or(FieldType=9)Or
     (NativeDynamic And((FieldType=1)Or(FieldType=2)Or
      (FieldType=3)Or(FieldType=4)Or(FieldType=8))))Then Begin
    Error(BaseName+': '+Msg('type de colonne non gere',
                           'unsupported column type'));
    Exit;
   End;
   FieldLength:=ReadBE(Column[2],2,False);
   If(FieldLength=0)Or(FieldLength>NativeRecLength-TotalLength)Then Begin
    Error(BaseName+': '+Msg('longueurs de colonnes incoherentes',
                           'inconsistent column lengths'));
    Exit;
   End;
   If(FieldType>=1)And(FieldType<=4)Then Inc(PackedFields);
   If FieldType=4Then Begin
    Inc(Blobs);
    If(FieldLength<9)Or(FieldLength>12)Then Begin
     Error(BaseName+': '+Msg('description BLOB invalide','invalid BLOB description'));
     Exit;
    End;
   End;
   If(FieldType=8)And(FieldLength<2)Then Begin
    Error(BaseName+': '+Msg('description VARCHAR invalide','invalid VARCHAR description'));
    Exit;
   End;
   TotalLength:=TotalLength+FieldLength;
  End;
  If(TotalLength<>NativeRecLength)Or
    ((PackedFields+7)Div 8<>NativePackBits)Or
    (Blobs<>ReadBE(NativeBase[78],2,False))Then Begin
   Error(BaseName+': '+Msg('longueur de ligne incoherente',
                          'inconsistent row length'));
   Exit;
  End;
  If NativeDynamic Then Begin
   If(ReadBE(NativeBase[60],4,False)<20)Or
     (ReadBE(NativeBase[60],4,False)>16777212)Or
     (ReadBE(NativeBase[60],4,False)Mod 4<>0)Or
     (DataSize Mod 4<>0)Then Begin
    Error(BaseName+': '+Msg('alignement dynamique invalide',
                           'invalid dynamic alignment'));
    Exit;
   End;
   NativeLoad:=True;
   Exit;
  End;
  TotalLength:=NativeRecLength;
  If TotalLength<=NativeRef Then TotalLength:=NativeRef+1;
  If(NativeOptions And 32)<>0Then Begin
   If TotalLength=MaxLong Then Begin
    Error(BaseName+': '+Msg('taille de slot trop grande','slot size too large'));
    Exit;
   End;
   Inc(TotalLength);
  End;
  If SlotSize<>TotalLength Then Begin
   Error(BaseName+': '+Msg('taille de slot statique invalide',
                          'invalid static slot size'));
   Exit;
  End;
  If DataSize Mod SlotSize<>0Then Begin
   Error(BaseName+': '+Msg('enregistrement statique tronque',
                          'truncated static record'));
   Exit;
  End;
  Slots:=DataSize Div SlotSize;
  If((NativeRef=2)And(Slots>65535))Or
    ((NativeRef=3)And(Slots>16777215))Then Begin
   Error(BaseName+': '+Msg('capacite des pointeurs depassee',
                          'record pointer capacity exceeded'));
   Exit;
  End;
 End;
 NativeLoad:=True;
End;

Procedure NativeCompare(Offset:Word;Expected:Longint;Const LabelText:String);
Begin
 If ReadBE(NativeState[Offset],8,False)<>Expected Then
  Issue(LabelText,True);
End;

Procedure FreeDynamicBlocks;
Var P:PDynamicBlock;
Begin
 While DynamicBlocks<>Nil Do Begin
  P:=DynamicBlocks;
  DynamicBlocks:=P^.Following;
  Dispose(P);
 End;
End;

Function DynamicError(Const FR,EN:String):Boolean;
Begin
 Error(BaseName+': '+Msg(FR,EN));
 CanRepair:=False;
 DynamicError:=False;
End;

Function DynamicFind(Offset:Longint):PDynamicBlock;
Var P:PDynamicBlock;
Begin
 P:=DynamicBlocks;
 While P<>Nil Do Begin
  If P^.Offset=Offset Then Begin
   DynamicFind:=P;
   Exit;
  End;
  P:=P^.Following;
 End;
 DynamicFind:=Nil;
End;

Function DynamicScan:Boolean;
Var P,Tail:PDynamicBlock; Offset,HeaderSize:Longint;
    H:Array[0..19]of Byte;
    {$IFDEF FPC}SavedReturnNil:Boolean;{$ENDIF}
Begin
 DynamicScan:=False;
 FreeDynamicBlocks;
 DynamicCount:=0;
 DynamicFree:=0;
 NativeDeleted:=0;
 Tail:=Nil;
 Offset:=0;
 While Offset<DataSize Do Begin
  If DataSize-Offset<20Then Begin
   DynamicScan:=DynamicError('bloc dynamique tronque','truncated dynamic block');
   Exit;
  End;
  If Not ReadAt(D,Offset,H,20)Then Exit;
  {$IFDEF FPC}
  SavedReturnNil:=ReturnNilIfGrowHeapFails;
  ReturnNilIfGrowHeapFails:=True;
  GetMem(P,SizeOf(TDynamicBlock));
  ReturnNilIfGrowHeapFails:=SavedReturnNil;
  If P=Nil Then Begin
  {$ELSE}
  If MaxAvail<SizeOf(TDynamicBlock)Then Begin
  {$ENDIF}
   DynamicScan:=DynamicError('memoire insuffisante pour les blocs',
                            'insufficient memory for block map');
   Exit;
  End;
  {$IFNDEF FPC}
  New(P);
  {$ENDIF}
  FillChar(P^,SizeOf(TDynamicBlock),0);
  If Tail=Nil Then DynamicBlocks:=P Else Tail^.Following:=P;
  Tail:=P;
  P^.Offset:=Offset;
  P^.Kind:=H[0];
  P^.NextOffset:=-1;
  P^.PrevOffset:=-1;
  HeaderSize:=0;
  Case H[0]Of
   0:Begin
    P^.Span:=ReadBE(H[1],3,False);
    P^.NextOffset:=ReadBE(H[4],8,True);
    P^.PrevOffset:=ReadBE(H[12],8,True);
   End;
   1,7:Begin
    HeaderSize:=3;
    P^.DataLength:=ReadBE(H[1],2,False);
   End;
   2,8:Begin
    HeaderSize:=4;
    P^.DataLength:=ReadBE(H[1],3,False);
   End;
   3,9:Begin
    HeaderSize:=4;
    P^.DataLength:=ReadBE(H[1],2,False);
    P^.Span:=H[3];
   End;
   4,10:Begin
    HeaderSize:=5;
    P^.DataLength:=ReadBE(H[1],3,False);
    P^.Span:=H[4];
   End;
   5:Begin
    HeaderSize:=13;
    P^.RowLength:=ReadBE(H[1],2,False);
    P^.DataLength:=ReadBE(H[3],2,False);
    P^.NextOffset:=ReadBE(H[5],8,False);
   End;
   6:Begin
    HeaderSize:=15;
    P^.RowLength:=ReadBE(H[1],3,False);
    P^.DataLength:=ReadBE(H[4],3,False);
    P^.NextOffset:=ReadBE(H[7],8,False);
   End;
   11:Begin
    HeaderSize:=11;
    P^.DataLength:=ReadBE(H[1],2,False);
    P^.NextOffset:=ReadBE(H[3],8,False);
   End;
   12:Begin
    HeaderSize:=12;
    P^.DataLength:=ReadBE(H[1],3,False);
    P^.NextOffset:=ReadBE(H[4],8,False);
   End;
   13:Begin
    HeaderSize:=16;
    P^.RowLength:=ReadBE(H[1],4,False);
    P^.DataLength:=ReadBE(H[5],3,False);
    P^.NextOffset:=ReadBE(H[8],8,False);
   End;
  Else
   DynamicScan:=DynamicError('type de bloc dynamique invalide',
                            'invalid dynamic block type');
   Exit;
  End;
  If H[0]<>0Then Begin
   P^.Span:=P^.Span+HeaderSize+P^.DataLength;
   P^.Payload:=Offset+HeaderSize;
   If(H[0]>=1)And(H[0]<=4)Then P^.RowLength:=P^.DataLength;
   If(P^.DataLength<=0)Or
     (((H[0]<=6)Or(H[0]=13))And(P^.RowLength<=0))Then Begin
    DynamicScan:=DynamicError('longueur de bloc ou de ligne invalide',
                             'invalid block or row length');
    Exit;
   End;
  End;
  If(P^.Span<ReadBE(NativeBase[60],4,False))Or
    (P^.Span>16777212)Or(P^.Span Mod 4<>0)Or
    (P^.Span>DataSize-Offset)Then Begin
   DynamicScan:=DynamicError('longueur ou alignement de bloc invalide',
                            'invalid block length or alignment');
   Exit;
  End;
  Inc(DynamicCount);
  If H[0]=0Then Begin
   Inc(NativeDeleted);
   DynamicFree:=DynamicFree+P^.Span;
  End;
  Offset:=Offset+P^.Span;
 End;
 DynamicScan:=True;
End;

Procedure ChecksumByte(Value:Byte;Var HighWord,LowWord:Word);
Var LowValue,HighValue:Longint;
Begin
 { Rotation/addition modulo 2^32, sans entier non signe 32 bits. }
 HighValue:=Longint(HighWord Mod 256)*256+LowWord Div 256;
 LowValue:=Longint(LowWord Mod 256)*256+Value+HighWord Div 256;
 HighWord:=(HighValue+LowValue Div 65536)Mod 65536;
 LowWord:=LowValue Mod 65536;
End;

Procedure DynamicStart(P:PDynamicBlock);
Begin
 DynamicCursor:=P;
 DynamicPosition:=0;
 DynamicRemaining:=P^.RowLength;
End;

Function DynamicRead(Var Buffer;Count:Word):Boolean;
Type TBuffer=Array[0..4095]of Byte;
Var B:^TBuffer; Done,Part:Word;
Begin
 DynamicRead:=False;
 If Count>DynamicRemaining Then Begin
  DynamicRead:=DynamicError('ligne dynamique tronquee','truncated dynamic row');
  Exit;
 End;
 B:=@Buffer;
 Done:=0;
 While Done<Count Do Begin
  If DynamicPosition=DynamicCursor^.DataLength Then Begin
   DynamicCursor:=DynamicFind(DynamicCursor^.NextOffset);
   DynamicPosition:=0;
  End;
  If DynamicCursor=Nil Then Begin
   DynamicRead:=DynamicError('chaine dynamique interrompue','broken dynamic chain');
   Exit;
  End;
  Part:=Count-Done;
  If DynamicCursor^.DataLength-DynamicPosition<Part Then
   Part:=DynamicCursor^.DataLength-DynamicPosition;
  If Not ReadAt(D,DynamicCursor^.Payload+DynamicPosition,B^[Done],Part)Then Exit;
  Inc(Done,Part);
  DynamicPosition:=DynamicPosition+Part;
  DynamicRemaining:=DynamicRemaining-Part;
 End;
 DynamicRead:=True;
End;

Function DynamicConsume(Count:Longint;Var HighWord,LowWord:Word):Boolean;
Var Part,J:Word;
Begin
 DynamicConsume:=False;
 If(Count<0)Or(Count>DynamicRemaining)Then Begin
  DynamicConsume:=DynamicError('longueur de colonne invalide','invalid column length');
  Exit;
 End;
 While Count>0Do Begin
  Part:=SizeOf(CopyBuffer);
  If Count<Part Then Part:=Count;
  If Not DynamicRead(CopyBuffer,Part)Then Exit;
  For J:=0 to Part-1Do ChecksumByte(CopyBuffer[J],HighWord,LowWord);
  Count:=Count-Part;
 End;
 DynamicConsume:=True;
End;

Procedure DynamicFill(Count:Longint;Value:Byte;Var HighWord,LowWord:Word);
Begin
 While Count>0Do Begin
  ChecksumByte(Value,HighWord,LowWord);
  Dec(Count);
 End;
End;

Function DynamicRow(P:PDynamicBlock;Var HighWord,LowWord:Word):Boolean;
Var J,K,FieldType,FieldLength,Length,FlagIndex,BitValue:Longint;
    Column:Array[0..6]of Byte; Bytes:Array[0..3]of Byte;
    PackedField:Boolean; StoredChecksum:Byte;
Begin
 DynamicRow:=False;
 DynamicStart(P);
 HighWord:=0;
 LowWord:=0;
 If Not DynamicRead(DynamicFlags,NativePackBits)Then Exit;
 FlagIndex:=0;
 BitValue:=1;
 For J:=0 to NativeFields-1Do Begin
  If Not ReadAt(F,NativeDefinitions+J*7,Column,7)Then Exit;
  FieldType:=ReadBE(Column[0],2,False);
  FieldLength:=ReadBE(Column[2],2,False);
  PackedField:=False;
  If(FieldType>=1)And(FieldType<=4)Then Begin
   PackedField:=(DynamicFlags[FlagIndex]And BitValue)<>0;
   BitValue:=BitValue*2;
   If BitValue=256Then Begin
    BitValue:=1;
    Inc(FlagIndex);
   End;
  End;
  Length:=FieldLength;
  If(FieldType=4)Then Begin
   Length:=0;
   If Not PackedField Then Begin
    K:=FieldLength-8;
    If Not DynamicRead(Bytes,K)Then Exit;
    While K>0Do Begin
     Dec(K);
     If Length>(MaxLong-Bytes[K])Div 256Then Begin
      DynamicRow:=DynamicError('BLOB trop grand','BLOB too large');
      Exit;
     End;
     Length:=Length*256+Bytes[K];
    End;
    If Length=0Then Begin
     DynamicRow:=DynamicError('BLOB vide non canonique','noncanonical empty BLOB');
     Exit;
    End;
   End;
  End
  Else If(FieldType=8)Or(PackedField And((FieldType=1)Or(FieldType=2)))Then Begin
   If Not DynamicRead(Bytes,1)Then Exit;
   Length:=Bytes[0];
   If(FieldType=8)And(Length=255)Then Begin
    If Not DynamicRead(Bytes,2)Then Exit;
    Length:=ReadBE(Bytes,2,False);
   End
   Else If(FieldType<>8)And(FieldLength>255)And(Length>=128)Then Begin
    If Not DynamicRead(Bytes,1)Then Exit;
    Length:=(Length And 127)+Longint(Bytes[0])*128;
   End;
   If((FieldType=8)And(Length>FieldLength-2))Or
     ((FieldType<>8)And(Length>=FieldLength))Then Begin
    DynamicRow:=DynamicError('longueur de champ compacte invalide',
                            'invalid packed field length');
    Exit;
   End;
  End
  Else If PackedField Then Length:=0;
  If PackedField And(FieldType=2)Then
   DynamicFill(FieldLength-Length,32,HighWord,LowWord);
  If Not DynamicConsume(Length,HighWord,LowWord)Then Exit;
  If PackedField And(FieldType=1)Then
   DynamicFill(FieldLength-Length,32,HighWord,LowWord);
  If PackedField And(FieldType=3)Then
   DynamicFill(FieldLength,0,HighWord,LowWord);
 End;
 If BitValue<>1Then
  If DynamicFlags[FlagIndex]And(256-BitValue)<>0Then Begin
   DynamicRow:=DynamicError('bits de compactage reserves non nuls',
                           'nonzero reserved packing bits');
   Exit;
  End;
 If(NativeOptions And 32)<>0Then Begin
  If Not DynamicRead(StoredChecksum,1)Then Exit;
  If StoredChecksum<>LowWord Mod 256Then
   Issue(Msg('checksum de ligne dynamique incoherent',
             'dynamic row checksum mismatch'),False);
 End;
 If DynamicRemaining<>0Then Begin
  DynamicRow:=DynamicError('octets inexpliques dans la ligne dynamique',
                          'unexplained bytes in dynamic row');
  Exit;
 End;
 DynamicRow:=True;
End;

Function DynamicValidate:Boolean;
Var P,Q:PDynamicBlock; Remaining,Head,Previous,Visited,Sum:Longint;
    RowHigh,RowLow,SumHigh,SumLow:Word; J:Integer; ChecksumOK:Boolean;
Begin
 DynamicValidate:=False;
 If Not DynamicScan Then Exit;
 Active:=0;
 SumHigh:=0;
 SumLow:=0;
 P:=DynamicBlocks;
 While P<>Nil Do Begin
  If(P^.Kind<>0)And((P^.Kind<=6)Or(P^.Kind=13))Then Begin
   Inc(Active);
   Q:=P;
   Remaining:=P^.RowLength;
   While Q<>Nil Do Begin
    If Q^.Used Or(Q^.Kind=0)Or((Q<>P)And
      ((Q^.Kind<=6)Or(Q^.Kind=13)))Or
      (Q^.DataLength>Remaining)Then Begin
     DynamicValidate:=DynamicError('cycle, bloc partage ou longueur de chaine invalide',
                                  'cycle, shared block or invalid chain length');
     Exit;
    End;
    Q^.Used:=True;
    Remaining:=Remaining-Q^.DataLength;
    If Q^.NextOffset=-1Then Break;
    If Remaining=0Then Break;
    Q:=DynamicFind(Q^.NextOffset);
   End;
   If(Q=Nil)Or(Remaining<>0)Then Begin
    DynamicValidate:=DynamicError('chaine dynamique incomplete','incomplete dynamic chain');
    Exit;
   End;
   If Q^.NextOffset<>-1Then Begin
    DynamicValidate:=DynamicError('chaine dynamique trop longue','overlong dynamic chain');
    Exit;
   End;
   If Not DynamicRow(P,RowHigh,RowLow)Then Exit;
   Sum:=Longint(SumLow)+RowLow;
   SumLow:=Sum Mod 65536;
   SumHigh:=(Longint(SumHigh)+RowHigh+Sum Div 65536)Mod 65536;
  End;
  P:=P^.Following;
 End;
 P:=DynamicBlocks;
 While P<>Nil Do Begin
  If(P^.Kind<>0)And Not P^.Used Then Begin
   DynamicValidate:=DynamicError('bloc dynamique orphelin','orphan dynamic block');
   Exit;
  End;
  P:=P^.Following;
 End;
 If(NativeOptions And 32)<>0Then Begin
  ChecksumOK:=True;
  For J:=100 to 103Do If NativeState[J]<>0Then ChecksumOK:=False;
  If(ReadBE(NativeState[104],2,False)<>SumHigh)Or
    (ReadBE(NativeState[106],2,False)<>SumLow)Then ChecksumOK:=False;
  If Not ChecksumOK Then Issue(Msg('checksum de table incoherent',
                                  'table checksum mismatch'),False);
 End;
 NativeCompare(28,Active,Msg('compteur actif incorrect','incorrect active count'));
 NativeCompare(36,NativeDeleted,Msg('compteur supprime incorrect','incorrect deleted count'));
 NativeCompare(44,DynamicCount,Msg('compteur de blocs incorrect','incorrect block count'));
 NativeCompare(60,IndexSize,Msg('taille d''index declaree incorrecte','incorrect stored index size'));
 NativeCompare(68,DataSize,Msg('taille des donnees declaree incorrecte','incorrect stored data size'));
 NativeCompare(76,DynamicFree,Msg('espace libre declare incorrect','incorrect stored free space'));
 NativeCompare(84,0,Msg('espace libre index incorrect','incorrect free index space'));
 NativeCompare(136,0,Msg('masque des index incorrect','incorrect index map'));
 If ReadBE(NativeState[24],2,False)<>0Then
  Issue(Msg('compteur d''ouverture non nul','nonzero open count'),True);
 If(NativeState[26]And 6)<>0Then
  Issue(Msg('table marquee endommagee','table marked crashed'),True);
 If IndexSize<>NativeKeyStart Then
  Issue(Msg('octets d''index inexpliques pour une table sans index',
            'unexplained index bytes in a table without indexes'),False);
 Head:=ReadBE(NativeState[52],8,True);
 Previous:=-1;
 Visited:=0;
 While Head<>-1Do Begin
  Q:=DynamicFind(Head);
  If Q=Nil Then Break;
  If(Q^.Kind<>0)Or Q^.Used Then Break;
  Q^.Used:=True;
  If Q^.PrevOffset<>Previous Then
   Issue(Msg('lien arriere de suppression invalide','invalid backward deleted link'),True);
  Previous:=Head;
  Head:=Q^.NextOffset;
  Inc(Visited);
 End;
 If(Head<>-1)Or(Visited<>NativeDeleted)Then
  Issue(Msg('chaine des blocs supprimes invalide ou incomplete',
            'invalid or incomplete deleted block chain'),True);
 DynamicValidate:=True;
End;

Function NativeRowChecksum(Offset:Longint;Var HighWord,LowWord:Word):Boolean;
Var Remaining:Longint; Count,J:Word;
Begin
 NativeRowChecksum:=False;
 HighWord:=0;
 LowWord:=0;
 Remaining:=NativeRecLength;
 While Remaining>0Do Begin
  Count:=SizeOf(CopyBuffer);
  If Remaining<Count Then Count:=Remaining;
  If Not ReadAt(D,Offset,CopyBuffer,Count)Then Exit;
  For J:=0 to Count-1Do ChecksumByte(CopyBuffer[J],HighWord,LowWord);
  Offset:=Offset+Count;
  Remaining:=Remaining-Count;
 End;
 NativeRowChecksum:=True;
End;

Function NativeValidate:Boolean;
Var N,Head,Next,Visited:Longint; Status:Byte;
    Link:Array[0..7]of Byte;
    RowHigh,RowLow,SumHigh,SumLow:Word; Sum:Longint; J:Integer;
    ChecksumOK:Boolean;
Begin
 If NativeDynamic Then Begin
  NativeValidate:=DynamicValidate;
  Exit;
 End;
 NativeValidate:=False;
 Active:=0;
 SumHigh:=0;
 SumLow:=0;
 For N:=0 to Slots-1Do Begin
  If Not StatusAt(N*SlotSize,Status)Then Exit;
  If Status<>0Then Begin
   Inc(Active);
   If(NativeOptions And 32)<>0Then Begin
    If Not NativeRowChecksum(N*SlotSize,RowHigh,RowLow)Then Exit;
    Sum:=Longint(SumLow)+RowLow;
    SumLow:=Sum Mod 65536;
    SumHigh:=(Longint(SumHigh)+RowHigh+Sum Div 65536)Mod 65536;
   End;
  End;
 End;
 If(NativeOptions And 32)<>0Then Begin
  ChecksumOK:=True;
  For J:=100 to 103Do
   If NativeState[J]<>0Then ChecksumOK:=False;
  If(ReadBE(NativeState[104],2,False)<>SumHigh)Or
    (ReadBE(NativeState[106],2,False)<>SumLow)Then ChecksumOK:=False;
  If Not ChecksumOK Then
   Issue(Msg(
    'checksum incoherent : donnees ou somme endommagees; correction refusee',
    'checksum mismatch: data or checksum damaged; repair refused'),False);
 End;
 NativeDeleted:=Slots-Active;
 NativeCompare(28,Active,Msg('compteur actif incorrect','incorrect active count'));
 NativeCompare(36,NativeDeleted,Msg('compteur supprime incorrect','incorrect deleted count'));
 NativeCompare(44,Slots,Msg('compteur de blocs incorrect','incorrect block count'));
 NativeCompare(60,IndexSize,Msg('taille d''index declaree incorrecte','incorrect stored index size'));
 NativeCompare(68,DataSize,Msg('taille des donnees declaree incorrecte','incorrect stored data size'));
 NativeCompare(76,NativeDeleted*SlotSize,Msg('espace libre declare incorrect','incorrect stored free space'));
 NativeCompare(84,0,Msg('espace libre index incorrect','incorrect free index space'));
 NativeCompare(136,0,Msg('masque des index incorrect','incorrect index map'));
 If ReadBE(NativeState[24],2,False)<>0Then
  Issue(Msg('compteur d''ouverture non nul','nonzero open count'),True);
 If(NativeState[26]And 6)<>0Then
  Issue(Msg('table marquee endommagee','table marked crashed'),True);
 If IndexSize<>NativeKeyStart Then
  Issue(Msg('octets d''index inexpliques pour une table sans index',
            'unexplained index bytes in a table without indexes'),False);
 Head:=ReadBE(NativeState[52],8,True);
 Visited:=0;
 While Head<>-1Do Begin
  If(Head<0)Or(Head>=DataSize)Then Begin
   Issue(Msg('tete ou lien de suppression hors limites',
             'deleted-chain head or link out of bounds'),True);
   Break;
  End;
  If Head Mod SlotSize<>0Then Begin
   Issue(Msg('lien de suppression non aligne','unaligned deleted-chain link'),True);
   Break;
  End;
  If Visited>=NativeDeleted Then Begin
   Issue(Msg('cycle ou chaine de suppression trop longue',
             'cycle or overlong deleted chain'),True);
   Break;
  End;
  If Not StatusAt(Head,Status)Then Exit;
  If Status<>0Then Begin
   Issue(Msg('ligne active dans la chaine de suppression',
             'active row in deleted chain'),True);
   Break;
  End;
  Inc(Visited);
  If Not ReadAt(D,Head+1,Link,NativeRef)Then Exit;
  Next:=ReadBE(Link,NativeRef,True);
  If Next=-1Then Head:=-1
  Else If(Next<0)Or(Next>=Slots)Then Begin
   Issue(Msg('pointeur de suppression invalide','invalid deleted record pointer'),True);
   Break;
  End
  Else Head:=Next*SlotSize;
 End;
 If Visited<>NativeDeleted Then
  Issue(Msg('slots supprimes absents de la chaine',
            'deleted slots missing from chain'),True);
 NativeValidate:=True;
End;

Function LoadHeaders:Boolean;
Begin
 LoadHeaders:=False;
 If Not OpenSource(F,IndexName,FOpen)Then Exit;
 If Not SourceSize(F,IndexSize)Then Exit;
 If IndexSize<8Then Begin
  Error(BaseName+': '+Msg('en-tete d''index tronque','truncated index header'));
  Exit;
 End;
 If Not ReadAt(F,0,IH.Magic,8)Then Exit;
 If Not MagicIs(IH.Magic,IndexMagic)Then Begin
  If(Ord(IH.Magic[0])=$FE)And(Ord(IH.Magic[1])=$FE)And
    (Ord(IH.Magic[2])=7)And(Ord(IH.Magic[3])=1)Then Begin
   LoadHeaders:=NativeLoad;
   Exit;
  End
  Else If(Ord(IH.Magic[0])=$FE)And(Ord(IH.Magic[1])=$FE)Then
   Error(BaseName+': '+Msg(
    'MyISAM natif MySQL/MariaDB : pas encore pris en charge; aucune modification',
    'native MySQL/MariaDB MyISAM: not yet supported; no changes'))
  Else Error(BaseName+': '+Msg('format d''index inconnu','unknown index format'));
  Exit;
 End;
 Native:=False;
 If Not OpenSource(D,DataName,DOpen)Then Exit;
 If Not SourceSize(D,DataSize)Then Exit;
 If(DataSize<32)Or(IndexSize<32)Then Begin
  Error(BaseName+': '+Msg('en-tete tronque','truncated header'));
  Exit;
 End;
 If Not ReadAt(D,0,DH,32)Then Exit;
 If Not ReadAt(F,0,IH,32)Then Exit;
 If Not MagicIs(DH.Magic,DataMagic)Then Begin
  Error(BaseName+': '+Msg('format de donnees inconnu','unknown data format'));
  Exit;
 End;
 If(DH.RecSize<=0)Or(DH.RecSize>MaxLong-33)Or(IH.KeySize<>16)Then Begin
  Error(BaseName+': '+Msg('taille d''enregistrement ou de cle invalide',
                         'invalid record or key size'));
  Exit;
 End;
 SlotSize:=DH.RecSize+1;
 If((DataSize-32)Mod SlotSize<>0)Or((IndexSize-32)Mod 21<>0)Then Begin
  Error(BaseName+': '+Msg('enregistrement ou entree d''index incomplet',
                         'partial record or index entry'));
  Exit;
 End;
 Slots:=(DataSize-32)Div SlotSize;
 Entries:=(IndexSize-32)Div 21;
 LoadHeaders:=True;
End;

Function Validate:Boolean;
Var N,K,Offset,Matches:Longint; Status,OtherStatus:Byte; E,Other:TEntry;
Begin
 If Native Then Begin
  Validate:=NativeValidate;
  Exit;
 End;
 Validate:=False;
 Active:=0;
 For N:=0 to Slots-1Do Begin
  Offset:=32+N*SlotSize;
  If Not StatusAt(Offset,Status)Then Exit;
  If Status>1Then Issue(Msg('statut de donnees invalide au slot ',
                            'invalid data status at slot ')+Number(N),False);
  If Status=0Then Inc(Active);
 End;
 If DH.RecCount<>Slots Then
  Issue(Msg('compteur de slots incorrect','incorrect slot count'),True);
 If DH.ActiveCount<>Active Then
  Issue(Msg('compteur de lignes actives incorrect','incorrect active row count'),True);
 If IH.EntryCount<>Entries Then
  Issue(Msg('compteur d''index incorrect','incorrect index count'),True);
 For N:=0 to Entries-1Do Begin
  If Not EntryAt(N,E)Then Exit;
  If E.Status>1Then Issue(Msg('statut d''index invalide : ',
                             'invalid index status: ')+Number(N),False);
  If Not ValidOffset(E.DataOfs)Then
   Issue(Msg('pointeur d''index invalide : ','invalid index pointer: ')+Number(N),False)
  Else Begin
   If Not StatusAt(E.DataOfs,Status)Then Exit;
   If E.Status<>Status Then
    Issue(Msg('statuts index/donnees differents : ',
              'index/data status mismatch: ')+Number(N),True);
   If Status=0Then
    For K:=0 to N-1Do Begin
     If Not EntryAt(K,Other)Then Exit;
     If ValidOffset(Other.DataOfs)Then Begin
      If Not StatusAt(Other.DataOfs,OtherStatus)Then Exit;
      If(OtherStatus=0)And SameKey(E,Other)Then
       Issue(Msg('cle dupliquee dans les lignes actives',
                 'duplicate key among active rows'),False);
     End;
    End;
  End;
 End;
 For N:=0 to Slots-1Do Begin
  Offset:=32+N*SlotSize;
  If Not StatusAt(Offset,Status)Then Exit;
  If Status=0Then Begin
   If Not FindForSlot(Offset,E,Matches)Then Exit;
   If Matches<>1Then
    Issue(Msg('cle absente ou ambigue au slot ',
              'missing or ambiguous key at slot ')+Number(N),False);
  End;
 End;
 Validate:=True;
End;

Function CopyRange(Var Source,Target:File;Offset,Length:Longint):Boolean;
Var Count:Word;
Begin
 CopyRange:=False;
 While Length>0Do Begin
  Count:=SizeOf(CopyBuffer);
  If Length<Count Then Count:=Length;
  If Not ReadAt(Source,Offset,CopyBuffer,Count)Then Exit;
  If Not WriteData(Target,CopyBuffer,Count)Then Exit;
  Offset:=Offset+Count;
  Length:=Length-Count;
 End;
 CopyRange:=True;
End;

Function CopyBytes(Offset,Length:Longint):Boolean;
Begin
 CopyBytes:=CopyRange(D,TD,Offset,Length);
End;

Function DynamicBuild:Boolean;
Var P,Q:PDynamicBlock; Head,Previous,NewSize,Count,Remaining,PartLength:Longint;
    Span,HeaderSize,Padding:Longint; H:Array[0..19]of Byte;
    Part:Word; First:Boolean;
Begin
 DynamicBuild:=False;
 If Not CreateTemp(TD,TempData,TDOpen,MadeTD)Then Exit;
 If Not CreateTemp(TI,TempIndex,TIOpen,MadeTI)Then Exit;
 If Not CopyRange(F,TI,0,IndexSize)Then Exit;
 Head:=-1;
 Previous:=-1;
 NewSize:=DataSize;
 Count:=DynamicCount;
 If Mode<>_Optimize Then Begin
  If Not CopyBytes(0,DataSize)Then Exit;
  P:=DynamicBlocks;
  While P<>Nil Do Begin
   If P^.Kind=0Then Begin
    If Head=-1Then Head:=P^.Offset;
    Q:=P^.Following;
    While Q<>Nil Do Begin
     If Q^.Kind=0Then Break;
     Q:=Q^.Following;
    End;
    If Q=Nil Then StoreBE(H[0],8,-1)
             Else StoreBE(H[0],8,Q^.Offset);
    StoreBE(H[8],8,Previous);
    {$I-}Seek(TD,P^.Offset+4);{$I+}
    If IOResult<>0Then Begin
     IOError(Msg('positionnement du lien impossible','cannot seek to deleted link'));
     Exit;
    End;
    If Not WriteData(TD,H,16)Then Exit;
    Previous:=P^.Offset;
   End;
   P:=P^.Following;
  End;
 End
 Else Begin
  NewSize:=0;
  Count:=0;
  P:=DynamicBlocks;
  While P<>Nil Do Begin
   If(P^.Kind<>0)And((P^.Kind<=6)Or(P^.Kind=13))Then Begin
    DynamicStart(P);
    Remaining:=P^.RowLength;
    First:=True;
    While Remaining>0Do Begin
     FillChar(H,SizeOf(H),0);
     If Remaining<=16777207Then Begin
      HeaderSize:=5;
      PartLength:=Remaining;
      Span:=HeaderSize+PartLength;
      If Span<20Then Span:=20;
      If Span Mod 4<>0Then Span:=Span+4-Span Mod 4;
      If First Then H[0]:=4 Else H[0]:=10;
      StoreBE(H[1],3,PartLength);
      H[4]:=Span-HeaderSize-PartLength;
     End
     Else Begin
      PartLength:=16777196;
      If First Then HeaderSize:=16 Else HeaderSize:=12;
      Span:=HeaderSize+PartLength;
      If NewSize>MaxLong-Span Then Begin
       DynamicBuild:=DynamicError('donnees compactees trop grandes',
                                 'compacted data too large');
       Exit;
      End;
      If First Then Begin
       H[0]:=13;
       StoreBE(H[1],4,P^.RowLength);
       StoreBE(H[5],3,PartLength);
       StoreBE(H[8],8,NewSize+Span);
      End
      Else Begin
       H[0]:=12;
       StoreBE(H[1],3,PartLength);
       StoreBE(H[4],8,NewSize+Span);
      End;
     End;
     If NewSize>MaxLong-Span Then Begin
      DynamicBuild:=DynamicError('donnees compactees trop grandes',
                                'compacted data too large');
      Exit;
     End;
     If Not WriteData(TD,H,HeaderSize)Then Exit;
     Padding:=Span-HeaderSize-PartLength;
     Remaining:=Remaining-PartLength;
     While PartLength>0Do Begin
      Part:=SizeOf(CopyBuffer);
      If PartLength<Part Then Part:=PartLength;
      If Not DynamicRead(CopyBuffer,Part)Then Exit;
      If Not WriteData(TD,CopyBuffer,Part)Then Exit;
      PartLength:=PartLength-Part;
     End;
     FillChar(H,SizeOf(H),0);
     If Not WriteData(TD,H,Padding)Then Exit;
     NewSize:=NewSize+Span;
     Inc(Count);
     First:=False;
    End;
   End;
   P:=P^.Following;
  End;
  NativeDeleted:=0;
  DynamicFree:=0;
 End;
 StoreBE(NativeState[24],2,0);
 NativeState[26]:=NativeState[26]And $F8;
 StoreBE(NativeState[28],8,Active);
 StoreBE(NativeState[36],8,NativeDeleted);
 StoreBE(NativeState[44],8,Count);
 StoreBE(NativeState[52],8,Head);
 StoreBE(NativeState[60],8,IndexSize);
 StoreBE(NativeState[68],8,NewSize);
 StoreBE(NativeState[76],8,DynamicFree);
 StoreBE(NativeState[84],8,0);
 StoreBE(NativeState[136],8,0);
 {$I-}Seek(TI,0);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('positionnement de l''en-tete impossible','cannot seek to header'));
  Exit;
 End;
 If Not WriteData(TI,NativeState,176)Then Exit;
 CloseFile(TD,TDOpen);
 CloseFile(TI,TIOpen);
 DynamicBuild:=Not IOFailed;
End;

Function NativeBuild:Boolean;
Var N,Offset,NewSize,Deleted,Head,Previous:Longint;
    Status:Byte; Link:Array[0..7]of Byte;
Begin
 If NativeDynamic Then Begin
  NativeBuild:=DynamicBuild;
  Exit;
 End;
 NativeBuild:=False;
 If Not CreateTemp(TD,TempData,TDOpen,MadeTD)Then Exit;
 If Not CreateTemp(TI,TempIndex,TIOpen,MadeTI)Then Exit;
 If Not CopyRange(F,TI,0,IndexSize)Then Exit;
 Head:=-1;
 Previous:=-1;
 Deleted:=0;
 NewSize:=0;
 For N:=0 to Slots-1Do Begin
  Offset:=N*SlotSize;
  If Not StatusAt(Offset,Status)Then Exit;
  If(Mode<>_Optimize)Or(Status<>0)Then Begin
   If Not CopyBytes(Offset,SlotSize)Then Exit;
   NewSize:=NewSize+SlotSize;
   If Status=0Then Begin
    StoreBE(Link,NativeRef,Previous);
    {$I-}Seek(TD,Offset+1);{$I+}
    If IOResult<>0Then Begin
     IOError(Msg('positionnement du lien impossible','cannot seek to deleted link'));
     Exit;
    End;
    If Not WriteData(TD,Link,NativeRef)Then Exit;
    {$I-}Seek(TD,NewSize);{$I+}
    If IOResult<>0Then Begin
     IOError(Msg('positionnement du slot impossible','cannot seek to slot'));
     Exit;
    End;
    Previous:=N;
    Head:=Offset;
    Inc(Deleted);
   End;
  End;
 End;
 StoreBE(NativeState[24],2,0);
 NativeState[26]:=NativeState[26]And $F8;
 StoreBE(NativeState[28],8,Active);
 StoreBE(NativeState[36],8,Deleted);
 StoreBE(NativeState[44],8,NewSize Div SlotSize);
 StoreBE(NativeState[52],8,Head);
 StoreBE(NativeState[60],8,IndexSize);
 StoreBE(NativeState[68],8,NewSize);
 StoreBE(NativeState[76],8,Deleted*SlotSize);
 StoreBE(NativeState[84],8,0);
 StoreBE(NativeState[136],8,0);
 {$I-}Seek(TI,0);{$I+}
 If IOResult<>0Then Begin
  IOError(Msg('positionnement de l''en-tete impossible','cannot seek to header'));
  Exit;
 End;
 If Not WriteData(TI,NativeState,176)Then Exit;
 CloseFile(TD,TDOpen);
 CloseFile(TI,TIOpen);
 NativeBuild:=Not IOFailed;
End;

Function BuildTables:Boolean;
Var N,Offset,Matches,NewOffset:Longint; Status:Byte; E:TEntry;
    NewDH:TDataHeader; NewIH:TIndexHeader;
Begin
 If Native Then Begin
  BuildTables:=NativeBuild;
  Exit;
 End;
 BuildTables:=False;
 If Not CreateTemp(TD,TempData,TDOpen,MadeTD)Then Exit;
 If Not CreateTemp(TI,TempIndex,TIOpen,MadeTI)Then Exit;
 NewDH:=DH;
 NewIH:=IH;
 NewDH.RecCount:=Slots;
 If Mode=_Optimize Then NewDH.RecCount:=Active;
 NewDH.ActiveCount:=Active;
 NewIH.EntryCount:=Active;
 If Not WriteData(TD,NewDH,32)Then Exit;
 If Not WriteData(TI,NewIH,32)Then Exit;
 NewOffset:=32;
 For N:=0 to Slots-1Do Begin
  Offset:=32+N*SlotSize;
  If Not StatusAt(Offset,Status)Then Exit;
  If(Mode<>_Optimize)Or(Status=0)Then Begin
   If Not CopyBytes(Offset,SlotSize)Then Exit;
   If Status=0Then Begin
    If Not FindForSlot(Offset,E,Matches)Then Exit;
    If Matches<>1Then Begin
     IOError(Msg('la table a change pendant la lecture','table changed while reading'));
     Exit;
    End;
    E.Status:=0;
    E.DataOfs:=NewOffset;
    If Not WriteData(TI,E,21)Then Exit;
   End;
   NewOffset:=NewOffset+SlotSize;
  End;
 End;
 CloseFile(TD,TDOpen);
 CloseFile(TI,TIOpen);
 BuildTables:=Not IOFailed;
End;

Function InstallTables:Boolean;
Var SavedD,SavedI,InstalledD,InstalledI,OK:Boolean;
Begin
 InstallTables:=False;
 SavedD:=False;
 SavedI:=False;
 InstalledD:=False;
 InstalledI:=False;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 If IOFailed Then Exit;
 { Les originaux sont conserves; jamais d'ecrasement d'une sauvegarde. }
 SavedD:=MoveFile(DataName,BackupData);
 If SavedD Then SavedI:=MoveFile(IndexName,BackupIndex);
 If SavedI Then Begin
  InstalledD:=MoveFile(TempData,DataName);
  If InstalledD Then Begin
   MadeTD:=False;
   InstalledI:=MoveFile(TempIndex,IndexName);
   If InstalledI Then MadeTI:=False;
  End;
 End;
 If InstalledI Then Begin
  InstallTables:=True;
  Exit;
 End;
 { Annulation des renommages; en cas d'echec, conserver tous les fichiers. }
 OK:=True;
 If InstalledD Then Begin
  OK:=MoveFile(DataName,TempData);
  If OK Then MadeTD:=True;
 End;
 If SavedI Then
  If Not MoveFile(BackupIndex,IndexName)Then OK:=False;
 If SavedD Then
  If Not MoveFile(BackupData,DataName)Then OK:=False;
 If Not OK Then Begin
  MadeTD:=False;
  MadeTI:=False;
  Error(BaseName+': '+Msg(
   'annulation incomplete : conserver .DMB/.IMB/.TMD/.TMI pour restauration manuelle',
   'incomplete rollback: preserve .DMB/.IMB/.TMD/.TMI for manual restoration'));
 End;
End;

Function VerifyBuilt:Boolean;
Var OriginalData,OriginalIndex:String; OK:Boolean;
Begin
 VerifyBuilt:=False;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 If IOFailed Then Exit;
 OriginalData:=DataName;
 OriginalIndex:=IndexName;
 DataName:=TempData;
 IndexName:=TempIndex;
 Problems:=0;
 CanRepair:=True;
 OK:=LoadHeaders;
 If OK Then OK:=Validate;
 If Problems<>0Then OK:=False;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 DataName:=OriginalData;
 IndexName:=OriginalIndex;
 If IOFailed Then OK:=False;
 If Not OK Then Error(BaseName+': '+Msg(
  'verification des temporaires echouee; originaux inchanges',
  'temporary verification failed; originals unchanged'));
 VerifyBuilt:=OK;
End;

Procedure WorkTable;
Begin
 If Not LoadHeaders Then Exit;
 If Native Then Begin
  If Not Silent Then WriteLn(BaseName,': MyISAM (layout 3.23/4.0)');
  If(Mode=_Describe)Or Verbose Then Begin
   WriteLn('  ',Msg('Options : ','Options: '),NativeOptions);
   WriteLn('  ',Msg('Index : ','Indexes: '),NativeKeys);
   WriteLn('  ',Msg('Longueur de ligne : ','Row length: '),NativeRecLength);
   WriteLn('  ',Msg('Taille de slot : ','Slot size: '),SlotSize);
   WriteLn('  ',Msg('Taille des donnees : ','Data size: '),DataSize);
   WriteLn('  CHECKSUM : ',(NativeOptions And 32)<>0);
  End;
  If Mode=_Describe Then Exit;
  If Not NativeSupported Then Begin
   Error(BaseName+': '+Msg(
    'MyISAM : index, compression et RAID non geres; aucune modification',
    'MyISAM: indexes, compression and RAID unsupported; no changes'));
   Exit;
  End;
 End
 Else Begin
 If Not Silent Then
  WriteLn(BaseName,': MALLMYD1/MALLMYI1 (',
   Msg('pas MyISAM natif','not native MyISAM'),')');
 If(Mode=_Describe)Or Verbose Then Begin
  WriteLn('  ',Msg('Taille enregistrement : ','Record size: '),DH.RecSize);
  WriteLn('  ',Msg('Slots physiques : ','Physical slots: '),Slots);
  WriteLn('  ',Msg('Entrees physiques : ','Physical index entries: '),Entries);
  WriteLn('  ',Msg('Compteurs declares : ','Stored counts: '),
          DH.RecCount,' / ',DH.ActiveCount,' / ',IH.EntryCount);
 End;
 If Mode=_Describe Then Exit;
 End;
 If Not Validate Then Exit;
 If(Mode=_Check)Then Begin
  If Problems>0Then Error(BaseName+': '+Number(Problems)+' '+
   Msg('anomalie(s); aucune modification','issue(s); no changes'))
  Else If Not Silent Then Begin
   If Native And NativeDynamic Then Write(BaseName,': OK (MyISAM dynamic/BLOB; ')
   Else If Native Then Write(BaseName,': OK (MyISAM static; ')
             Else Write(BaseName,': OK (structure MALL; ');
   WriteLn(Active,' ',Msg('ligne(s) active(s))','active row(s))'));
  End;
  Exit;
 End;
 If Not CanRepair Then Begin
  If Native Then Error(BaseName+': '+Msg(
   'correction refusee : integrite des donnees non etablie; aucune modification',
   'repair refused: data integrity not established; no changes'))
  Else Error(BaseName+': '+Msg(
    'reparation refusee : cle ou structure irrecuperable sans schema; aucune modification',
    'repair refused: key or structure cannot be recovered without schema; no changes'));
  Exit;
 End;
 If Exists(BackupData)Or Exists(BackupIndex)Or
    Exists(TempData)Or Exists(TempIndex)Then Begin
  Error(BaseName+': '+Msg(
   'sauvegarde ou temporaire deja present; deplacer ces fichiers avant de recommencer',
   'backup or temporary path already exists; move these files before retrying'));
  Exit;
 End;
 If IOFailed Then Exit;
 If Not BuildTables Then Exit;
 If Not VerifyBuilt Then Exit;
 If Not InstallTables Then Exit;
 If Not Silent Then Begin
  WriteLn(BaseName,': ',Msg('operation terminee, lignes actives : ',
                           'operation completed, active rows: '),Active);
  WriteLn('  ',Msg('Originaux conserves : ','Originals saved: '),
          BackupData,' ',BackupIndex);
 End;
End;

Procedure ProcessTable(Const Name:String);
Var L:Integer;
Begin
 AnyTable:=True;
 IOFailed:=False;
 Native:=False;
 NativeDynamic:=False;
 CanRepair:=True;
 Problems:=0;
 DOpen:=False;
 FOpen:=False;
 TDOpen:=False;
 TIOpen:=False;
 MadeTD:=False;
 MadeTI:=False;
 BaseName:=Name;
 L:=Length(BaseName);
 If L>=4Then
  If(Upper(Copy(BaseName,L-3,4))='.MYI')Or
    (Upper(Copy(BaseName,L-3,4))='.MYD')Then
   BaseName:=Copy(BaseName,1,L-4);
 If(BaseName='')Or(Length(BaseName)>251)Then Begin
  Error(Msg('nom de table vide ou trop long','empty or too long table name'));
  Exit;
 End;
 DataName:=BaseName+'.MYD';
 IndexName:=BaseName+'.MYI';
 TempData:=BaseName+'.TMD';
 TempIndex:=BaseName+'.TMI';
 BackupData:=BaseName+'.DMB';
 BackupIndex:=BaseName+'.IMB';
 WorkTable;
 CloseFile(D,DOpen);
 CloseFile(F,FOpen);
 CloseFile(TD,TDOpen);
 CloseFile(TI,TIOpen);
 RemoveTemp(TempData,MadeTD);
 RemoveTemp(TempIndex,MadeTI);
 FreeDynamicBlocks;
End;

Procedure ProcessArgument(Const Name:String);
Var SR:SearchRec; Dir:DirStr; Stem:NameStr; Ext:ExtStr;
    Pattern:String; Code:Integer; Found:Boolean;
Begin
 If(Pos('*',Name)=0)And(Pos('?',Name)=0)Then Begin
  ProcessTable(Name);
  Exit;
 End;
 Pattern:=Name;
 FSplit(Pattern,Dir,Stem,Ext);
 If Ext=''Then Pattern:=Pattern+'.MYI'
 Else If(Upper(Ext)<>'.MYI')And(Upper(Ext)<>'.MYD')Then Begin
  Error(Msg('motif attendu : *.MYI ou *.MYD','expected pattern: *.MYI or *.MYD'));
  Exit;
 End;
 Found:=False;
 FindFirst(Pattern,AnyFile,SR);
 Code:=DosError;
 While Code=0Do Begin
  If(SR.Attr And Directory)=0Then Begin
   Found:=True;
   ProcessTable(Dir+SR.Name);
  End;
  FindNext(SR);
  Code:=DosError;
 End;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
 If(Code<>18)And(Code<>2)Then
  Error(Msg('erreur de recherche : ','file search error: ')+Pattern);
 If Not Found Then Error(Msg('aucune table : ','no matching table: ')+Pattern);
End;

Procedure ShowHelp;
Begin
 WriteLn('MYISAMCHK : ',Msg('Maintenance MALL et MyISAM 3.23/4.0.',
                           'MALL and MyISAM 3.23/4.0 maintenance.'));
 WriteLn('Syntaxe / Usage: myisamchk [options] tbl_name ...');
 WriteLn;
 WriteLn(Msg('MALLMYD1/MALLMYI1 et layout MyISAM 3.23/4.0 (176/100 octets).',
             'MALLMYD1/MALLMYI1 and MyISAM 3.23/4.0 layout (176/100 bytes).'));
 WriteLn(Msg('Natif : statique ou dynamique sans index; BLOB et CHECKSUM acceptes.',
             'Native: static or dynamic without indexes; BLOB and CHECKSUM accepted.'));
 WriteLn(Msg('Dynamique : blocs fragmentes, champs compactes, chaines libres.',
             'Dynamic: fragmented blocks, packed fields, free block chains.'));
 WriteLn(Msg('Checksum incoherent : verification en echec et correction refusee.',
             'Checksum mismatch: check fails and repair is refused.'));
 WriteLn(Msg('Indexe, comprime, RAID : verification et correction refusees.',
             'Indexed, compressed, RAID: checking and repair refused.'));
 WriteLn(Msg('La signature ne permet pas d''identifier la version exacte du serveur.',
             'The signature cannot identify the exact server version.'));
 WriteLn;
 WriteLn(Msg('  -c, --check          Verification MALL ou native geree (defaut).',
             '  -c, --check          MALL or supported native check (default).'));
 WriteLn(Msg('  -e, --extend-check   Meme verification, sans raccourci.',
             '  -e, --extend-check   Same check, without shortcuts.'));
 WriteLn(Msg('  -r, --recover        Corrige compteurs et statuts, reconstruit l''index.',
             '  -r, --recover        Fix counts/statuses and rebuild the index.'));
 WriteLn(Msg('                      Natif : compteurs et chaine des suppressions.',
             '                      Native: counts and deleted-record chain.'));
 WriteLn(Msg('  --optimize           Retire aussi les slots supprimes.',
             '  --optimize           Also remove deleted data slots.'));
 WriteLn(Msg('                      Dynamique : regroupe aussi les fragments.',
             '                      Dynamic: also coalesce row fragments.'));
 WriteLn(Msg('  -d, --description    En-tetes seulement, sans verdict d''integrite.',
             '  -d, --description    Headers only; not an integrity verdict.'));
 WriteLn(Msg('  -s, --silent         Masque les messages ordinaires, pas les erreurs.',
             '  -s, --silent         Hide normal messages, not errors.'));
 WriteLn(Msg('  -v, --verbose        Affiche les compteurs et tailles.',
             '  -v, --verbose        Display counts and sizes.'));
 WriteLn('  --backup             ',Msg('Sauvegarde obligatoire, toujours active.',
                                        'Mandatory backup, always enabled.'));
 WriteLn('  /?, --help, -h, /h, /H');
 WriteLn('  --version');
 WriteLn('  --                   ',Msg('Fin des options.','End of options.'));
 WriteLn;
 WriteLn(Msg('Nom avec ou sans .MYI/.MYD; motifs *.MYI et *.MYD acceptes.',
             'Names with or without .MYI/.MYD; *.MYI and *.MYD patterns accepted.'));
 WriteLn(Msg('ARRETER l''application et le serveur avant toute operation.',
             'STOP the application and server before any operation.'));
 WriteLn(Msg('Reparation prudente : aucune cle inventee ni ligne active supprimee.',
             'Conservative repair: no invented keys or discarded active rows.'));
 WriteLn(Msg('Le statut du slot .MYD fait foi; le contenu des champs reste opaque.',
             'The .MYD slot status is authoritative; field contents remain opaque.'));
 WriteLn(Msg('MyISAM : 0 = supprime, non nul = actif (inverse du format MALL).',
             'MyISAM: 0 = deleted, nonzero = active (unlike the MALL format).'));
 WriteLn(Msg('Cle absente/ambigue, doublon ou structure invalide : refus de reparer.',
             'Missing/ambiguous keys, duplicates or invalid structure: repair refused.'));
 WriteLn(Msg('Originaux : .DMB/.IMB; temporaires : .TMD/.TMI. Aucun ecrasement.',
             'Originals: .DMB/.IMB; temporary files: .TMD/.TMI. Never overwritten.'));
 WriteLn(Msg('Deux fichiers : remplacement non atomique; conserver les sauvegardes.',
             'Two files: replacement is not atomic; retain the backups.'));
 WriteLn(Msg('Verification quadratique, memoire bornee; fichiers < 2 Gio.',
             'Quadratic check, bounded memory; files < 2 GiB.'));
End;

Function Option(Const A:String):Boolean;
Begin
 Option:=True;
 If(A='-c')Or(A='--check')Or(A='-e')Or(A='--extend-check')Then Mode:=_Check
 Else If(A='-r')Or(A='--recover')Then Mode:=_Recover
 Else If A='--optimize'Then Mode:=_Optimize
 Else If(A='-d')Or(A='--description')Then Mode:=_Describe
 Else If(A='-s')Or(A='--silent')Then Silent:=True
 Else If(A='-v')Or(A='--verbose')Then Verbose:=True
 Else If A='--backup'Then
 Else Option:=False;
End;

BEGIN
 English:=Upper(GetEnv('LANGUAGE'))='EN';
 AnyError:=False;
 AnyTable:=False;
 Silent:=False;
 Verbose:=False;
 Mode:=_Check;
 EndOptions:=False;
 { Valider toutes les options avant de permettre une modification de table. }
 For ArgIndex:=1 to ParamCount Do Begin
  Arg:=ParamStr(ArgIndex);
  If Not EndOptions Then Begin
   If Arg='--'Then EndOptions:=True
   Else If(Arg='/?')Or(Arg='--help')Or(Arg='-h')Or
          (Arg='/h')Or(Arg='/H')Then Begin
    ShowHelp;
    Halt(0);
   End
   Else If Arg='--version'Then Begin
    WriteLn('MYISAMCHK 0.4-Pascal - MALL / MyISAM 3.23/4.0 static/dynamic/BLOB, no indexes');
    Halt(0);
   End
   Else If(Length(Arg)>0)Then
    If Arg[1]='-'Then
     If Not Option(Arg)Then Begin
      Error(Msg('option inconnue ou non implementee : ',
                'unknown or unimplemented option: ')+Arg);
      Halt(1);
     End;
  End;
 End;
 EndOptions:=False;
 For ArgIndex:=1 to ParamCount Do Begin
  Arg:=ParamStr(ArgIndex);
  If Not EndOptions And(Arg='--')Then EndOptions:=True
  Else If EndOptions Then ProcessArgument(Arg)
  Else If Arg=''Then ProcessArgument(Arg)
  Else If Arg[1]<>'-'Then ProcessArgument(Arg);
 End;
 If Not AnyTable Then Begin
  Error(Msg('aucune table indiquee','no table specified'));
  Halt(1);
 End;
 If AnyError Then Halt(1);
END.
