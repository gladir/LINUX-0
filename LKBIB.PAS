{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande lkbib - Recherche bibliographique par mots-cles
}

Program LKBIB;

{$X+}

Uses DOS;

Const
 MaxFiles=32;
 MaxKeys=64;
 MaxRecordLines=200;

Type
 TLine=String[255];
 TLineArray=Array[1..MaxRecordLines]Of TLine;
 PLineArray=^TLineArray;

Var
 DBFiles:Array[1..MaxFiles]Of String[127];
 DBCount:Integer;
 IgnoreFields:String[26];
 TruncLen:Integer;
 Keys:Array[1..MaxKeys]Of String[40];
 Found:Array[1..MaxKeys]Of Boolean;
 KeyCount:Integer;
 RecLines:PLineArray;
 RecCount:Integer;
 MatchCount:Integer;
 FileErrors:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: lkbib [ -v ] [ -ifields ] [ -pfilename ] [ -tn ] key ...');
End;

Procedure ShowHelp;Begin
 WriteLn('LKBIB : Cette commande permet d''effectuer la recherche bibliographique dans les ',
         'bases de donnees.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -v          Affiche le numero de version');
 WriteLn('  -ifields    Ignore ces champs (lettres) lors de la recherche');
 WriteLn('  -pfilename  Base de donnees bibliographique (repetable; defaut: variable REFER)');
 WriteLn('  -tn         Tronque les mots-cles a n caracteres (defaut: 6)');
 WriteLn('  key         Mots-cles recherches (tous doivent se trouver dans la notice)');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Fail(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'lkbib: ',S);
 {$ELSE}
 WriteLn('lkbib: ',S);
 {$ENDIF}
 Halt(2);
End;

Function Trim(Const S:String):String;
Var
 A,B:Integer;
Begin
 A:=1;
 B:=Length(S);
 While(A<=B)And(S[A]In[' ',#9,#13])Do Inc(A);
 While(B>=A)And(S[B]In[' ',#9,#13])Do Dec(B);
 Trim:=Copy(S,A,B-A+1);
End;

Function ToNumber(Const S:String;Var N:Integer):Boolean;
Var
 Err:Integer;
Begin
 Val(S,N,Err);
 ToNumber:=(Err=0)And(N>0);
End;

Function IsWordChar(C:Char):Boolean;Begin
 IsWordChar:=C In['A'..'Z','a'..'z','0'..'9'];
End;

Function Lower(C:Char):Char;Begin
 If C In['A'..'Z']Then Lower:=Chr(Ord(C)+32)
                  Else Lower:=C;
End;

Function NextWord(Const S:String;Var P:Integer;Var W:String):Boolean;
Var
 Len:Integer;
Begin
 NextWord:=False;
 While(P<=Length(S))And Not IsWordChar(S[P])Do Inc(P);
 If P>Length(S)Then Exit;
 W:='';
 Len:=0;
 While(P<=Length(S))And IsWordChar(S[P])Do Begin
  If Len<TruncLen Then Begin
   Inc(Len);
   W:=W+Lower(S[P]);
  End;
  Inc(P);
 End;
 NextWord:=True;
End;

Procedure AddKeys(Const S:String);
Var
 P,J:Integer;
 W:String;
 Dup:Boolean;
Begin
 P:=1;
 While NextWord(S,P,W)Do Begin
  If(Length(W)>=3)Or(Length(W)=TruncLen)Then Begin
   Dup:=False;
   For J:=1 to KeyCount Do If Keys[J]=W Then Dup:=True;
   If Not Dup And(KeyCount<MaxKeys)Then Begin
    Inc(KeyCount);
    Keys[KeyCount]:=Copy(W,1,40);
    Found[KeyCount]:=False;
   End;
  End;
 End;
End;

Procedure ScanLine(Const S:String);
Var
 P,J:Integer;
 W:String;
Begin
 P:=1;
 While NextWord(S,P,W)Do
  For J:=1 to KeyCount Do If Not Found[J]And(Keys[J]=W)Then Found[J]:=True;
End;

Function AllFound:Boolean;
Var
 J:Integer;
Begin
 AllFound:=False;
 For J:=1 to KeyCount Do If Not Found[J]Then Exit;
 AllFound:=True;
End;

Procedure FlushRecord;
Var
 I:Integer;
Begin
 If RecCount>0Then Begin
  If AllFound Then Begin
   For I:=1 to RecCount Do WriteLn(RecLines^[I]);
   WriteLn;
   Inc(MatchCount);
  End;
 End;
 RecCount:=0;
 For I:=1 to KeyCount Do Found[I]:=False;
End;

Function IsBlank(Const S:String):Boolean;
Var
 I:Integer;
Begin
 IsBlank:=False;
 For I:=1 to Length(S)Do If Not(S[I]In[' ',#9,#13])Then Exit;
 IsBlank:=True;
End;

Procedure SearchFile(Const Name:String);
Var
 F:Text;
 Line:TLine;
 Skipping:Boolean;
Begin
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,'lkbib: impossible d''ouvrir ',Name);
  {$ELSE}
  WriteLn('lkbib: impossible d''ouvrir ',Name);
  {$ENDIF}
  Inc(FileErrors);
  Exit;
 End;
 RecCount:=0;
 Skipping:=False;
 While Not EOF(F)Do Begin
  ReadLn(F,Line);
  If IsBlank(Line)Then Begin
   FlushRecord;
   Skipping:=False;
  End
   Else
  Begin
   If RecCount<MaxRecordLines Then Begin
    Inc(RecCount);
    RecLines^[RecCount]:=Line;
   End;
   { Champ %X : ignore si X est dans la liste -i; les suites heritent }
   If(Line[1]='%')And(Length(Line)>1)Then
    Skipping:=Pos(Line[2],IgnoreFields)>0
   Else If Not(Line[1]In[' ',#9])Then Skipping:=False;
   If Not Skipping Then ScanLine(Line);
  End;
 End;
 FlushRecord;
 Close(F);
End;

Var
 I,N:Integer;
 A,V:String;
 Env:String;

BEGIN
 DBCount:=0;
 IgnoreFields:='';
 TruncLen:=6;
 KeyCount:=0;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If A='--version'Then Begin
   WriteLn('GNU lkbib (groff clone) 1.0');
   Halt(0);
  End;
 End;
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(Length(A)>1)And(A[1]='-')And(A[2]In['v','i','p','t'])Then Begin
   V:=Copy(A,3,255);
   If A[2]='v'Then Begin
    WriteLn('GNU lkbib (groff clone) 1.0');
    Halt(0);
   End;
   If V=''Then Begin
    Inc(I);
    If I>ParamCount Then Begin
     ShowUsage;
     Halt(2);
    End;
    V:=ParamStr(I);
   End;
   Case A[2]of
    'i':IgnoreFields:=Copy(V,1,26);
    'p':If DBCount<MaxFiles Then Begin
     Inc(DBCount);
     DBFiles[DBCount]:=Copy(V,1,127);
    End;
    't':If Not ToNumber(V,TruncLen)Then Fail('valeur invalide pour -t: '+V);
   End;
  End
  Else If(Length(A)>1)And(A[1]='-')Then Begin
   WriteLn('lkbib: option inconnue: ',A);
   ShowUsage;
   Halt(2);
  End
   Else
  AddKeys(A);
  Inc(I);
 End;
 If TruncLen>40Then TruncLen:=40;
 If KeyCount=0Then Begin
  ShowUsage;
  Halt(2);
 End;
 If DBCount=0Then Begin
  Env:=GetEnv('REFER');
  If Env<>''Then Begin
   Inc(DBCount);
   DBFiles[DBCount]:=Copy(Env,1,127);
  End
   Else
  Fail('aucune base de donnees (utilisez -p ou la variable REFER)');
 End;
 New(RecLines);
 MatchCount:=0;
 For N:=1 to DBCount Do SearchFile(DBFiles[N]);
 Dispose(RecLines);
 If FileErrors>0Then Halt(2);
 If MatchCount=0Then Halt(1);
END.
