{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program SED;

Type
  TCommand = Record
    Cmd:Char;           { 's', 'd', 'p' }
    Pattern:String;     { motif à rechercher }
    Replacement:String; { remplacement pour 's' }
    Global:Boolean;     { option 'g' pour 's' }
  End;

Function ParseCommand(Const CmdStr:String; Var Cmd:TCommand):Boolean;
Var
  I,Start:Integer;
  Delimiter:Char;
Begin
  ParseCommand:=False;
  If Length(CmdStr)=0 Then Exit;
  
  Cmd.Cmd:=CmdStr[1];
  If Cmd.Cmd='s' Then Begin
    If Length(CmdStr)<4 Then Exit;
    Delimiter:=CmdStr[2];
    
    { Recherche du pattern }
    Start:=3;
    I:=Start;
    While(I<=Length(CmdStr))and(CmdStr[I]<>Delimiter)do Inc(I);
    Cmd.Pattern:=Copy(CmdStr,Start,I-Start);
    
    { Recherche du remplacement }
    If I>=Length(CmdStr)Then Exit;
    Start:=I+1;
    I:=Start;
    While(I<=Length(CmdStr))and(CmdStr[I]<>Delimiter)do Inc(I);
    Cmd.Replacement:=Copy(CmdStr,Start,I-Start);
    
    { Vérification option globale }
    Cmd.Global:=(I<Length(CmdStr))and(CmdStr[I+1]='g');
    ParseCommand:=True;
  End
  Else If(Cmd.Cmd='d')or(Cmd.Cmd='p')Then Begin
    ParseCommand:=True;
  End;
End;

Function ApplySubstitution(Const Line,Pattern,Replacement:String; Global:Boolean):String;
Var
  Result,Temp:String;
  P,I:Integer;
Begin
  Result:=Line;
  I:=1;
  Repeat
    P:=Pos(Pattern,Copy(Result,I,Length(Result)));
    If P>0 Then Begin
      P:=P+I-1;
      Temp:=Copy(Result,1,P-1)+Replacement+
            Copy(Result,P+Length(Pattern),Length(Result));
      Result:=Temp;
      If Global Then I:=P+Length(Replacement)
                Else Break;
    End;
  Until P=0;
  ApplySubstitution:=Result;
End;

Procedure ProcessSedCommand(Const Command:String);
Var
  Line:String;
  Cmd:TCommand;
Begin
  If Not ParseCommand(Command,Cmd)Then Begin
    WriteLn('Erreur: Commande sed invalide');
    Exit;
  End;
  
  While Not EOF do Begin
    ReadLn(Line);
    Case Cmd.Cmd of
      's': Begin { Substitution }
        Line:=ApplySubstitution(Line,Cmd.Pattern,Cmd.Replacement,Cmd.Global);
        WriteLn(Line);
      End;
      'd': Begin { Delete }
        If Pos(Cmd.Pattern,Line)=0 Then WriteLn(Line);
      End;
      'p': Begin { Print }
        WriteLn(Line);
        If Pos(Cmd.Pattern,Line)>0 Then WriteLn(Line);
      End;
    End;
  End;
End;

BEGIN
END.