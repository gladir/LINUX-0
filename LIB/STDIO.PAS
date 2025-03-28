{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit STDIO;

INTERFACE

Uses Strings;

Const
  EOF=-1;       { Fin de fichier }

  { Modes de mise en m‚moire tampon utilis‚s par setvbuf }
 _IOFBF=0;   { EntiŠrement mis en m‚moire tampon }
 _IOLBF=1;   { Mis en m‚moire tampon par ligne }
 _IONBF=2;   { Pas de mise en m‚moire tampon }

Type
 FileOfChar=File Of Char;
 PFile=^File;

Procedure ClearErr(Var F:File);
Function  CTermID(S:PChar):PChar;
Function  CUserID(S:PChar):PChar;
Procedure EndMntEnt(Var FileP:File);
Function  FClose(Var F:File):Integer;
Function  FEOF(Var F:File):Integer;
Function  FError(Var F:File):Integer;
Function  FFlush(Var F:Text):Integer;
Function  FGetC(Var F:FileOfChar):Char;
Function  FGetPos(Var F:File;Pos:LongInt):LongInt;
Function  FGetS(Var S:String;Size:Integer;Var F:Text):String;
Function  FileNo(Var F:File):Integer;
Function  FOpen(FileName,Mode:String):PFile;
Function  FPrintF(Var F:Text;Format:String;Var Buffer):Integer;
Function  FPutC(Var F:Text;C:Char):Integer;
Function  FPutS(Var F:Text;S:String):Integer;
Function  FRead(Var Buffer;Size,N:Integer;Var F:File):Integer;
Function  FSeek(Var F:File;Offset:LongInt;Base:Integer):Integer;
Function  FSetPos(Var F:File;Offset:LongInt):Integer;
Function  FTell(Var F:File):LongInt;
Function  FWrite(Var Buffer;Size,N:Integer;Var F:File):Integer;
Function  GetC(Var F:Text):Char;
Function  GetChar:Char;
Function  PrintF(Format:String;Var Buffer):Integer;
Function  PutC(C:Integer;Var Stream:Text):Integer;
Function  PutChar(C:Char):Integer;
Function  PutS(S:String):Integer;
Function  Remove(PathName:String):Integer;
Function  Rename(Old,New:String):Integer;
Procedure Rewind(Var F:File);
Function  SPrintF(Var Target:String;Format:String;Var Buffer):Integer;
Function  UngetC(C:Char;Var PtrFichier:Text):Char;

IMPLEMENTATION

Uses DOS;

 { Priv‚ }
Function ByteHex2Str(value:Byte):String;
Const
 matrix:Array[0..15]of Char = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
Begin
 ByteHex2Str:=matrix[(value shr 4) and $0F]+matrix[value and $F];
End;

Procedure ClearErr(Var F:File);Begin
 {$I-}
  { Force une mise … jour sans affecter la position du fichier }
 Seek(F,FilePos(F));
 {$I+}
End;

Function CTermID(S:PChar):PChar;
Const
 TerminalName:String[3]='CON'; { Nom du terminal sous DOS/Windows }
Var
 I: Integer;
Begin
 If S<>NIL Then Begin
   { Copier manuellement la chaŒne de caractŠres }
  I:=0;
  While(I<Length(TerminalName))do Begin
   S[I] := TerminalName[I+1];
   Inc(I);
  End;
  S[I]:=#0; { Terminer la chaŒne avec un caractŠre nul }
  CTermID:=S;
 End
  Else
 CTermID:=@TerminalName;
End;

Function CUserID(S:PChar):PChar;
Const
 DefaultUser: string[8] = 'unknown'; { Nom par d‚faut si non trouv‚ }
Var
 EnvUser:PChar;
 I:Integer;
 Tmp:Array[0..255]of Char;
begin
 StrPCopy(Tmp,GetEnv('USERNAME'));
 EnvUser:=StrNew(Tmp);
 If(EnvUser=NIL)or(StrLen(EnvUser)=0)Then Begin
  StrPCopy(Tmp,GetEnv('LOGNAME'));
  EnvUser:=StrNew(Tmp); { Essayer LOGNAME sous Unix }
 End;
 If EnvUser=NIL Then Begin
  EnvUser:=@DefaultUser[1]; { Utiliser 'unknown' si rien n'est trouv‚ }
 End;
 If(S<>NIL)Then Begin
  I:=0;
  While(EnvUser[I]<>#0)and(I < 8)do Begin
   S[I]:=EnvUser[I];
   Inc(I);
  End;
  S[I]:=#0; { Ajouter le caractŠre de fin de chaŒne }
  CUserID:=S;
 End
  Else
 CUserID:=EnvUser;
End;

Procedure EndMntEnt(Var FileP:File);Begin
 Close(FileP);  { Ferme le fichier sp‚cifi‚ }
End;

Function FClose(Var F:File):Integer;Begin
 System.Close(F);
End;

Function FEOF(Var F:File):Integer;Begin
 If System.EOF(F)Then FEOF:=0
          Else FEOF:=-1;
End;

Function FError(Var F:File):Integer;Begin
 FError:=IOResult;
End;

Function FFlush(Var F:Text):Integer;Begin
 Flush(F);
 FFlush:=IOResult;
End;

Function FGetC(Var F:FileOfChar):Char;
Var
 C:Char;
Begin
 System.Read(F,C);
End;

Function FGetPos(Var F:File;Pos:LongInt):LongInt;Begin
 FGetPos:=FilePos(F);
End;

Function FGetS(Var S:String;Size:Integer;Var F:Text):String;Begin
 ReadLn(F,S);
 FGetS:=S;
End;

Function FileNo(Var F:File):Integer;Begin
 FileNo:=FileRec(F).Handle;
End;

Function FOpen(FileName,Mode:String):PFile;
Var
 P:File;
 T:Text;
Begin
 If Pos('t',Mode)>0Then Begin
  Assign(T,FileName);
  If Pos('a',Mode)>0Then Begin
   Reset(T);
  End
   Else
  If Pos('w+',Mode)>0 Then Begin
   Rewrite(T);
  End;
  FOpen:=@T;
 End
  Else
 Begin
  Assign(P,FileName);
  If Pos('a',Mode)>0Then Begin
   Reset(P,1);
  End
   Else
  If Pos('w+',Mode)>0 Then Begin
   Rewrite(P,1);
  End;
  FOpen:=@P;
 End;
End;

Function FPrintF(Var F:Text;Format:String;Var Buffer):Integer;
Type
 PtrRec=Record
  Ofs,Seg:Word; { Offset et Segment }
 End;
Var
 Ptr:Pointer;
 PtrReal:PtrRec Absolute Ptr;
 PChr:^Char Absolute Ptr;
 PInt:^Integer Absolute Ptr;
 PStr:^String Absolute Ptr;
 I:Byte;
Begin
 I:=1;
 While(I<=Length(Format))do Begin
  If '%'=Format[I]Then Begin
   I:=I+1;
   Case Format[I]of
    'c':Begin
     System.Write(F,PChr^);
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Char));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Char));
     {$ENDIF}
    End;
    'i':Begin
     System.Write(F,PInt^);
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Integer));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Integer));
     {$ENDIF}
    End;
    's':Begin
     System.Write(F,PStr^);
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(String));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(String));
     {$ENDIF}
    End;
    'x':Begin
     System.Write(F,ByteHex2Str(Byte(PChr^)));
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Char));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Char));
     {$ENDIF}
    End;
   End;
  End;
  I:=I+1;
 End;
End;

Function FPutC(Var F:Text;C:Char):Integer;Begin
 System.Write(F,C);
 FPutC:=IoResult;
End;

Function FPutS(Var F:Text;S:String):Integer;Begin
 WriteLn(F,S);
 FPutS:=IoResult;
End;

Function FRead(Var Buffer;Size,N:Integer;Var F:File):Integer;
Var
 L:Word;
Begin
 BlockRead(F,Buffer,Size*N,L);
 FRead:=L;
End;

Function FSeek(Var F:File;Offset:LongInt;Base:Integer):Integer;Begin
 Seek(F,Offset);
 FSeek:=IoResult;
End;

Function FSetPos(Var F:File;Offset:LongInt):Integer;Begin
 Seek(F,Offset);
 FSetPos:=IoResult;
End;

Function FTell(Var F:File):LongInt;Begin
 FTell:=FilePos(F);
End;

Function FWrite(Var Buffer;Size,N:Integer;Var F:File):Integer;
Var
 L:Word;
Begin
 BlockWrite(F,Buffer,Size*N,L);
 FWrite:=L;
End;

Function GetC(Var F:Text):Char;
Var
 C:Char;
Begin
 System.Read(F,C);
 GetC:=C;
End;

Function GetChar:Char;
Var
 C:Char;
Begin
 System.Read(C);
 GetChar:=C;
End;

Function PrintF(Format:String;Var Buffer):Integer;
Type
 PtrRec=Record
  Ofs,Seg:Word; { Offset et Segment }
 End;
Var
 Ptr:Pointer;
 PtrReal:PtrRec Absolute Ptr;
 PChr:^Char Absolute Ptr;
 PInt:^Integer Absolute Ptr;
 PStr:^String Absolute Ptr;
 I:Byte;
Begin
 I:=1;
 While(I<=Length(Format))do Begin
  If '%'=Format[I]Then Begin
   I:=I+1;
   Case Format[I]of
    'c':Begin
     System.Write(PChr^);
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Char));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Char));
     {$ENDIF}
    End;
    'i':Begin
     System.Write(PInt^);
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Integer));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Integer));
     {$ENDIF}
    End;
    's':Begin
     System.Write(PStr^);
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(String));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(String));
     {$ENDIF}
    End;
    'x':Begin
     System.Write(ByteHex2Str(Byte(PChr^)));
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Char));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Char));
     {$ENDIF}
    End;
   End;
  End;
  I:=I+1;
 End;
End;

Function PutC(C:Integer;Var Stream:Text):Integer;Begin
 System.Write(Stream,C);
 PutC:=IOResult;
End;

Function PutChar(C:Char):Integer;Begin
 System.Write(C);
 PutChar:=IOResult;
End;

Function PutS(S:String):Integer;Begin
 WriteLn(S);
End;

Function Remove(PathName:String):Integer;
Var
 F:File;
Begin
 {$I-}Assign(F,PathName);
 Erase(F);
 {$I+}
 Remove:=IoResult;
End;

Function Rename(Old,New:String):Integer;
Var
 F:File;
Begin
 {$I-}Assign(F,Old);
 System.Rename(F,New);
 {$I+}
 Rename:=IoResult;
End;

Procedure Rewind(Var F:File);Begin
 Seek(F,0);
End;

Function SPrintF(Var Target:String;Format:String;Var Buffer):Integer;
Type
 PtrRec=Record
  Ofs,Seg:Word; { Offset et Segment }
 End;
Var
 Ptr:Pointer;
 PtrReal:PtrRec Absolute Ptr;
 PChr:^Char Absolute Ptr;
 PInt:^Integer Absolute Ptr;
 PStr:^String Absolute Ptr;
 I:Byte;
 SInt:String;
 Err:Word;
Begin
 Target:='';
 I:=1;
 While(I<=Length(Format))do Begin
  If '%'=Format[I]Then Begin
   I:=I+1;
   Case Format[I]of
    'c':Begin
     Target:=Target+PChr^;
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Char));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Char));
     {$ENDIF}
    End;
    'i':Begin
     Val(SInt,PInt^,Err);
     Target:=Target+SInt;
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Integer));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Integer));
     {$ENDIF}
    End;
    's':Begin
     Target:=Target+PStr^;
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(String));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(String));
     {$ENDIF}
    End;
    'x':Begin
     Target:=Target+ByteHex2Str(Byte(PChr^));
     {$IFDEF FPC}
      Inc(Ptr,SizeOf(Char));
     {$ELSE}
      Inc(PtrReal.Ofs,SizeOf(Char));
     {$ENDIF}
    End;
   End;
  End;
  I:=I+1;
 End;
 SPrintF:=Length(Target);
End;

Function UngetC(C:Char;Var PtrFichier:Text):Char;
Var
 R:Char;
Begin
 System.Read(PtrFichier,R);
 System.Write(PtrFichier,C);
 UngetC:=R;
End;

END.