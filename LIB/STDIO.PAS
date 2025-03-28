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

IMPLEMENTATION

Uses DOS;

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

END.