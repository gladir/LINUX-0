{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program SED(Input,Output);

Uses DOS;

Type
  TCommand = Record
    Cmd:Char;
    Pattern:String;
    Replacement:String;
    Global:Boolean;
  End;

Var
  Cmd:TCommand;
  FileView:Text;
  Line,Script,Param:String;
  I,ScriptIndex,FirstFileIndex:Integer;
  SuppressDefault,Deleted:Boolean;
  TmpLanguage:String;

Function StrToUpper(S:String):String;
Var
  I:Integer;
Begin
  For I:=1 to Length(S)do
    If S[I]in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
  StrToUpper:=S;
End;

Function ParseCommand(Const CmdStr:String; Var Parsed:TCommand):Boolean;
Var
  I,Start:Integer;
  Delimiter:Char;
Begin
  ParseCommand:=False;
  If CmdStr='d' Then Begin
    Parsed.Cmd:='d';
    ParseCommand:=True;
    Exit;
  End;
  If CmdStr='p' Then Begin
    Parsed.Cmd:='p';
    ParseCommand:=True;
    Exit;
  End;
  If Length(CmdStr)<4 Then Exit;
  If CmdStr[1]<>'s' Then Exit;
  Delimiter:=CmdStr[2];
  If Delimiter='\' Then Exit;

  Start:=3;
  I:=Start;
  While(I<=Length(CmdStr))and(CmdStr[I]<>Delimiter)do Inc(I);
  If I>Length(CmdStr) Then Exit;
  Parsed.Pattern:=Copy(CmdStr,Start,I-Start);
  If Parsed.Pattern='' Then Exit;

  Start:=I+1;
  I:=Start;
  While(I<=Length(CmdStr))and(CmdStr[I]<>Delimiter)do Inc(I);
  Parsed.Replacement:=Copy(CmdStr,Start,I-Start);
  Parsed.Global:=False;
  If I<=Length(CmdStr) Then Begin
    If I<Length(CmdStr) Then Begin
    If Copy(CmdStr,I+1,Length(CmdStr))<>'g' Then Exit;
    Parsed.Global:=True;
    End;
  End;
  Parsed.Cmd:='s';
  ParseCommand:=True;
End;

Function ApplySubstitution(Const Source,Pattern,Replacement:String;
                           Global:Boolean):String;
Var
  ResultLine:String;
  P,SearchFrom:Integer;
Begin
  ResultLine:=Source;
  SearchFrom:=1;
  Repeat
    P:=Pos(Pattern,Copy(ResultLine,SearchFrom,Length(ResultLine)));
    If P>0 Then Begin
      P:=P+SearchFrom-1;
      ResultLine:=Copy(ResultLine,1,P-1)+Replacement+
                  Copy(ResultLine,P+Length(Pattern),Length(ResultLine));
      If Not Global Then Break;
      SearchFrom:=P+Length(Replacement);
    End;
  Until P=0;
  ApplySubstitution:=ResultLine;
End;

Procedure ProcessInput(Var Source:Text);
Begin
  While Not EOF(Source) Do Begin
    ReadLn(Source,Line);
    Deleted:=False;
    Case Cmd.Cmd Of
      's':Line:=ApplySubstitution(Line,Cmd.Pattern,Cmd.Replacement,Cmd.Global);
      'd':Deleted:=True;
      'p':WriteLn(Output,Line);
    End;
    If Not SuppressDefault And Not Deleted Then WriteLn(Output,Line);
  End;
End;

BEGIN
  If(ParamCount=0)or(ParamStr(1)='/?')or(ParamStr(1)='--help')or
    (ParamStr(1)='-h')or(ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
    TmpLanguage:=GetEnv('LANGUAGE');
    If StrToUpper(Copy(TmpLanguage,1,2))='EN' Then Begin
      WriteLn('SED : Stream editor (literal patterns; basic commands).');
      WriteLn('Syntax: sed [-n] [-e SCRIPT] [FILE]...');
      WriteLn('Commands: s/old/new/[g], d, p');
      WriteLn('Without FILE, reads standard input.');
    End
     Else Begin
      WriteLn('SED : Editeur de flux (motifs litteraux; commandes de base).');
      WriteLn('Syntaxe : sed [-n] [-e SCRIPT] [FICHIER]...');
      WriteLn('Commandes : s/ancien/nouveau/[g], d, p');
      WriteLn('Sans fichier, lit l''entree standard.');
    End;
  End
   Else Begin
    SuppressDefault:=False;
    ScriptIndex:=0;
    I:=1;
    While I<=ParamCount Do Begin
      Param:=ParamStr(I);
      If Param='-n' Then Begin
        SuppressDefault:=True;
        Inc(I);
      End
       Else If Param='-e' Then Begin
        Inc(I);
        If I>ParamCount Then Begin
          WriteLn('Erreur : script manquant apres -e');
          Halt(2);
        End;
        ScriptIndex:=I;
        Break;
      End
       Else Begin
        ScriptIndex:=I;
        Break;
      End;
    End;

    If ScriptIndex=0 Then Begin
      WriteLn('Erreur : script sed manquant');
      Halt(2);
    End;
    Script:=ParamStr(ScriptIndex);
    FirstFileIndex:=ScriptIndex+1;
    If Not ParseCommand(Script,Cmd) Then Begin
      WriteLn('Erreur : commande sed invalide : ',Script);
      Halt(2);
    End;

    If FirstFileIndex>ParamCount Then ProcessInput(Input)
     Else Begin
      For I:=FirstFileIndex to ParamCount Do Begin
        {$I-}Assign(FileView,ParamStr(I));
        Reset(FileView);{$I+}
        If IOResult<>0 Then Begin
          WriteLn('Erreur : impossible de lire ',ParamStr(I));
          Halt(1);
        End;
        ProcessInput(FileView);
        Close(FileView);
      End;
    End;
  End;
END.