{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande mkdirhier - Cree un repertoire et ses parents
}

Program MKDIRHIER;

{$X+}

Uses DOS;

Var
 OptV:Boolean;
 ErrCount:Integer;

Procedure ShowUsage;Begin
 WriteLn('usage: mkdirhier directory ...');
End;

Procedure ShowHelp;Begin
 WriteLn('MKDIRHIER : Cette commande permet de creer un repertoire hierarchique.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  directory   Chemin a creer; les repertoires parents manquants sont crees aussi');
 WriteLn('  -v          Affiche chaque repertoire cree');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Err(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'mkdirhier: ',S);
 {$ELSE}
 WriteLn('mkdirhier: ',S);
 {$ENDIF}
 Inc(ErrCount);
End;

{ 0 = n'existe pas, 1 = repertoire, 2 = fichier }
Function Kind(Const P:String):Integer;
Var
 SR:SearchRec;
Begin
 Kind:=0;
 FindFirst(P,AnyFile,SR);
 If DosError=0Then Begin
  If(SR.Attr And Directory)<>0Then Kind:=1
                              Else Kind:=2;
 End;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
End;

Procedure MakeHier(Const Arg:String);
Var
 S,Prefix:String;
 I,Start,K:Integer;
 Last:String;
Begin
 S:=Arg;
 For I:=1 to Length(S)Do If S[I]='\'Then S[I]:='/';
 While(Length(S)>1)And(S[Length(S)]='/')Do S:=Copy(S,1,Length(S)-1);
 If S=''Then Exit;
 Start:=1;
 { lecteur DOS : C: ou C:/ }
 If(Length(S)>=2)And(S[2]=':')Then Begin
  Start:=3;
  If(Length(S)>=3)And(S[3]='/')Then Start:=4;
 End
 Else If S[1]='/'Then Start:=2;
 I:=Start;
 While I<=Length(S)+1 Do Begin
  If(I>Length(S))Or(S[I]='/')Then Begin
   Prefix:=Copy(S,1,I-1);
   K:=Length(Prefix);
   While(K>0)And(Prefix[K]<>'/')Do Dec(K);
   If(Prefix<>'')And(Prefix[Length(Prefix)]='/')Then Begin
    { segment vide (//) }
   End
    Else
   Begin
    Last:=Copy(Prefix,K+1,255);
    If(Last<>'.')And(Last<>'..')And(Last<>'')And Not((Length(Prefix)=2)And(Prefix[2]=':'))Then Begin
     Case Kind(Prefix)of
      0:Begin
       {$I-}MkDir(Prefix);{$I+}
       If IOResult<>0Then Begin
        Err('cannot create directory '''+Prefix+'''');
        Exit;
       End;
       If OptV Then WriteLn('mkdirhier: created directory ''',Prefix,'''');
      End;
      2:Begin
       Err(Prefix+': not a directory');
       Exit;
      End;
     End;
    End;
   End;
  End;
  Inc(I);
 End;
End;

Var
 I,N:Integer;
 A:String;

BEGIN
 ErrCount:=0;
 N:=0;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='-h')Or(A='/h')Then Begin
   ShowHelp;
   Halt(0);
  End;
 End;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='-v')Or(A='--verbose')Then OptV:=True
  Else If A='-p'Then
  Else Begin
   Inc(N);
   MakeHier(A);
  End;
 End;
 If N=0Then Begin
  ShowUsage;
  Halt(1);
 End;
 If ErrCount>0Then Halt(1);
END.
