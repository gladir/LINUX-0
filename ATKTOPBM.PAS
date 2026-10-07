{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program ATKTOPBM(Input,Output);

Uses DOS;

Const
  MaxHeaderLine=255;
  MaxRowBytes=8192;

Type
  TRow=Array[1..MaxRowBytes]Of Byte;

Var
  RasterFile:File;
  RasterRow:TRow;
  LineText,WordText:String;
  Width,Height,RowBytes,ObjectId:LongInt;
  RasterVersion,Options:LongInt;
  XScale,YScale,XOffset,YOffset,SubWidth,SubHeight:LongInt;
  RowIndex,I:LongInt;
  UseFile:Boolean;
  HasPending:Boolean;
  PendingByte:Byte;
  ReadCount:Word;

Function ReadByte(Var Value:Byte):Boolean;
Begin
  If HasPending Then Begin
    Value:=PendingByte;
    HasPending:=False;
    ReadByte:=True;
    Exit;
  End;
  If UseFile Then Begin
    If FilePos(RasterFile)>=FileSize(RasterFile)Then Begin
      ReadByte:=False;
      Exit;
    End;
    BlockRead(RasterFile,Value,1,ReadCount);
    ReadByte:=ReadCount=1;
  End Else Begin
    If EOF(Input)Then Begin
      ReadByte:=False;
      Exit;
    End;
    Read(Input,Value);
    ReadByte:=True;
  End;
End;

Procedure UnreadByte(Value:Byte);
Begin
  PendingByte:=Value;
  HasPending:=True;
End;

Function ReadLineFromRaster(Var S:String):Boolean;
Var
  B:Byte;
  Found:Boolean;
Begin
  S:='';
  Found:=False;
  While ReadByte(B)Do Begin
    Found:=True;
    If B=10 Then Break;
    If(B<>13)and(Length(S)<MaxHeaderLine)Then S:=S+Chr(B);
  End;
  ReadLineFromRaster:=Found;
End;

Function NextWord(Const S:String; Var Index:Integer):String;
Var
  Start:Integer;
Begin
  While(Index<=Length(S))and(S[Index]in[' ',#9])Do Inc(Index);
  Start:=Index;
  While(Index<=Length(S))and(Not(S[Index]in[' ',#9]))Do Inc(Index);
  NextWord:=Copy(S,Start,Index-Start);
End;

Function ParseLong(Const S:String; Var Value:LongInt):Boolean;
Var
  ErrorCode:Integer;
Begin
  Val(S,Value,ErrorCode);
  ParseLong:=ErrorCode=0;
End;

Function ParseBeginDataId(Const S:String; Var Id:LongInt):Boolean;
Var
  Marker,Digits:String;
  Start,Finish:Integer;
Begin
  ParseBeginDataId:=False;
  Marker:='\begindata{raster,';
  If Copy(S,1,Length(Marker))<>Marker Then Exit;
  Start:=Length(Marker)+1;
  Finish:=Start;
  While(Finish<=Length(S))and(S[Finish]in['0'..'9'])Do Inc(Finish);
  If(Finish=Start)or(Finish>Length(S))or(S[Finish]<>'}')Then Exit;
  Digits:=Copy(S,Start,Finish-Start);
  If Not ParseLong(Digits,Id)Then Exit;
  ParseBeginDataId:=True;
End;

Procedure ReadHeader;
Var
  Index:Integer;
  Keyword:String;
  LineId:LongInt;
Begin
  If Not ReadLineFromRaster(LineText)Then Begin
    WriteLn('Erreur : fichier raster vide');
    Halt(1);
  End;
  If Not ParseBeginDataId(LineText,ObjectId)Then Begin
    WriteLn('Erreur : objet Andrew Raster invalide');
    Halt(1);
  End;
  If Not ReadLineFromRaster(LineText)Then Begin
    WriteLn('Erreur : entete raster tronquee');
    Halt(1);
  End;
  Index:=1;
  If Not ParseLong(NextWord(LineText,Index),RasterVersion)or
    Not ParseLong(NextWord(LineText,Index),Options)or
    Not ParseLong(NextWord(LineText,Index),XScale)or
    Not ParseLong(NextWord(LineText,Index),YScale)or
    Not ParseLong(NextWord(LineText,Index),XOffset)or
    Not ParseLong(NextWord(LineText,Index),YOffset)or
    Not ParseLong(NextWord(LineText,Index),SubWidth)or
    Not ParseLong(NextWord(LineText,Index),SubHeight)Then Begin
    WriteLn('Erreur : parametres raster invalides');
    Halt(1);
  End;
  If RasterVersion<2 Then Begin
    WriteLn('Erreur : version de raster anterieure a BE2');
    Halt(1);
  End;
  If Not ReadLineFromRaster(LineText)Then Begin
    WriteLn('Erreur : description des bits absente');
    Halt(1);
  End;
  Index:=1;
  Keyword:=NextWord(LineText,Index);
  If Keyword<>'bits'Then Begin
    WriteLn('Erreur : mot-cle bits attendu');
    Halt(1);
  End;
  If Not ParseLong(NextWord(LineText,Index),LineId)or
    Not ParseLong(NextWord(LineText,Index),Width)or
    Not ParseLong(NextWord(LineText,Index),Height)Then Begin
    WriteLn('Erreur : dimensions raster invalides');
    Halt(1);
  End;
  If(Width<=0)or(Height<=0)or(Width>MaxRowBytes*8)or(Height>1000000)Then Begin
    WriteLn('Erreur : dimensions hors limites');
    Halt(1);
  End;
  RowBytes:=(Width+7)div 8;
End;

Function HexValue(B:Byte):Integer;
Begin
  If(B>=Ord('0'))and(B<=Ord('9'))Then HexValue:=B-Ord('0')Else
  If(B>=Ord('A'))and(B<=Ord('F'))Then HexValue:=B-Ord('A')+10 Else
  If(B>=Ord('a'))and(B<=Ord('f'))Then HexValue:=B-Ord('a')+10 Else
    HexValue:=-1;
End;

Procedure StoreRun(Value:Byte; Count:LongInt; Var Cursor:LongInt);
Var
  I:LongInt;
Begin
  If Count>RowBytes-Cursor+1 Then Count:=RowBytes-Cursor+1;
  For I:=1 to Count Do Begin
    RasterRow[Cursor]:=Value;
    Inc(Cursor);
  End;
End;

Function ReadRasterRow:Boolean;
Var
  State:Integer;
  B:Byte;
  Nibble,PendingNibble:Integer;
  RepeatCount,Cursor:LongInt;
  RowEnd:Boolean;
Begin
  For Cursor:=1 to RowBytes Do RasterRow[Cursor]:=0;
  Cursor:=1;
  State:=0;
  PendingNibble:=0;
  RepeatCount:=0;
  RowEnd:=False;
  While ReadByte(B)Do Begin
    If B=Ord('|')Then Begin
      RowEnd:=True;
      Break;
    End;
    If(B=Ord(Chr(92)))or(B=Ord('{'))Then Begin
      UnreadByte(B);
      ReadRasterRow:=False;
      Exit;
    End;
    If(B<=32)Then Continue;
    If(B>=Ord('g'))and(B<=Ord('z'))Then Begin
      If State<>0 Then State:=0;
      RepeatCount:=B-Ord('f');
      StoreRun(0,RepeatCount,Cursor);
      Continue;
    End;
    If(B>=Ord('G'))and(B<=Ord('Z'))Then Begin
      If State<>0 Then State:=0;
      RepeatCount:=B-Ord('F');
      StoreRun(255,RepeatCount,Cursor);
      Continue;
    End;
    If(B>=Ord('!'))and(B<=Ord('/'))Then Begin
      If State<>0 Then State:=0;
      RepeatCount:=B-$1F;
      State:=3;
      Continue;
    End;
    Nibble:=HexValue(B);
    If Nibble>=0 Then Begin
      Case State Of
        0:Begin
          PendingNibble:=Nibble shl 4;
          State:=1;
        End;
        1:Begin
          StoreRun(Byte(PendingNibble or Nibble),1,Cursor);
          State:=0;
        End;
        3:Begin
          PendingNibble:=Nibble shl 4;
          State:=4;
        End;
        4:Begin
          StoreRun(Byte(PendingNibble or Nibble),RepeatCount,Cursor);
          State:=0;
        End;
      End;
    End Else State:=0;
  End;
  If Not RowEnd Then Begin
    ReadRasterRow:=False;
    Exit;
  End;
  If Cursor<=RowBytes Then
    StoreRun(0,RowBytes-Cursor+1,Cursor);
  If(Width mod 8)<>0Then
    RasterRow[RowBytes]:=RasterRow[RowBytes]and
      Byte($FF shl (8-(Width mod 8)));
  ReadRasterRow:=True;
End;

Procedure WritePBMRow;
Var
  I:Integer;
Begin
  For I:=1 to RowBytes Do Write(Output,Chr(RasterRow[I]));
End;

Procedure ValidateEndMarker;
Var
  B:Byte;
  MarkerLine:String;
  MarkerId:LongInt;
Begin
  While ReadByte(B)Do
    If B=Ord(Chr(92))Then Break;
  If B<>Ord(Chr(92))Then Begin
    WriteLn('Erreur : marqueur enddata absent');
    Halt(1);
  End;
  If Not ReadLineFromRaster(MarkerLine)Then Begin
    WriteLn('Erreur : marqueur enddata incomplet');
    Halt(1);
  End;
  If Copy(MarkerLine,1,Length('enddata{raster,'))<>'enddata{raster,'Then Begin
    WriteLn('Erreur : marqueur enddata invalide');
    Halt(1);
  End;
  WordText:=Copy(MarkerLine,Length('enddata{raster,')+1,Length(MarkerLine));
  I:=Pos('}',WordText);
  If(I=0)or Not ParseLong(Copy(WordText,1,I-1),MarkerId)Then Begin
    WriteLn('Erreur : identifiant enddata invalide');
    Halt(1);
  End;
  If MarkerId<>ObjectId Then Begin
    WriteLn('Erreur : identifiant enddata different');
    Halt(1);
  End;
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('ATKTOPBM : Convert an Andrew Toolkit raster object to PBM.');
    WriteLn('Syntax: atktopbm [atkfile]');
    WriteLn('Reads stdin when atkfile is omitted; writes raw PBM P4 to stdout.');
    WriteLn('Supports Andrew BE2 raster version 2 and later.');
  End Else Begin
    WriteLn('ATKTOPBM : Cette commande permet de convertir un objet raster Andrew Toolkit en PBM.');
    WriteLn;
    WriteLn('Syntaxe : atktopbm [fichier]');
    WriteLn;
    WriteLn('Sans fichier, lit stdin; produit un PBM brut P4 sur stdout.');
    WriteLn('Prend en charge les rasters BE2 version 2 et ulterieure.');
  End;
End;

BEGIN
  UseFile:=ParamCount=1;
  If ParamCount>1 Then Begin
    WriteLn('Erreur : syntaxe : atktopbm [fichier]');
    Halt(2);
  End;
  If(ParamCount=1)and((ParamStr(1)='--help')or(ParamStr(1)='-h')or
    (ParamStr(1)='/?')or(ParamStr(1)='/h')or(ParamStr(1)='/H'))Then Begin
    PrintHelp;
    Halt(0);
  End;
  If(ParamCount=1)and((ParamStr(1)='--version')or(ParamStr(1)='-v'))Then Begin
    WriteLn('atktopbm (LINUX-0) 1.0');
    Halt(0);
  End;
  If UseFile Then Begin
    {$I-}Assign(RasterFile,ParamStr(1));
    Reset(RasterFile,1);{$I+}
    If IOResult<>0 Then Begin
      WriteLn('Erreur : impossible de lire ',ParamStr(1));
      Halt(1);
    End;
  End;
  ReadHeader;
  WriteLn(Output,'P4');
  WriteLn(Output,Width,' ',Height);
  For RowIndex:=1 to Height Do Begin
    If Not ReadRasterRow Then Begin
      WriteLn('Erreur : raster tronque ou ligne malformee');
      Halt(1);
    End;
    WritePBMRow;
  End;
  ValidateEndMarker;
  If UseFile Then Close(RasterFile);
END.
