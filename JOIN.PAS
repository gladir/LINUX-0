{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande join - Fusionne les lignes de deux fichiers sur un champ commun
}

Program JOIN;

{$X+}

Uses DOS;

Const
 MaxG=200;
 MaxO=40;

Type
 TGroup=Record
  N:Integer;
  Key:String;
  L:Array[1..MaxG]Of String;
 End;
 PGroup=^TGroup;
 TInp=Record
  F:Text;
  Have:Boolean;
  Line:String;
  Name:String;
  LineNo:Longint;
  Fld:Integer;
  PrevKey:String;
  Warned:Boolean;
 End;

Var
 I1,I2:TInp;
 G1,G2:PGroup;
 A1,A2,V1,V2,IgnCase,HasSep:Boolean;
 Sep:Char;
 Empty:String;
 OFile:Array[1..MaxO]Of Integer;
 OFld:Array[1..MaxO]Of Integer;
 OCnt:Integer;
 Unsorted:Boolean;
 OutSep:String;

Procedure ShowUsage;Begin
 WriteLn('Usage: join [-a 1|2] [-v 1|2] [-e empty-string] [-o field-list...] [-t char]');
 WriteLn('            [-j[1|2] field] [-1 field] [-2 field] file1 file2');
 WriteLn('       join {--help,--version}');
End;

Procedure ShowHelp;Begin
 WriteLn('JOIN : Cette commande permet de fusionner des lignes de deux fichiers en un champ commun.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -1 champ    Champ de jointure du fichier 1');
 WriteLn('  -2 champ    Champ de jointure du fichier 2');
 WriteLn('  -a numero   Affiche aussi les lignes du fichier 1 ou 2 sans correspondance');
 WriteLn('  -e chaine   Remplace les champs vides ou absents par cette chaine');
 WriteLn('  -i          Ignore la casse lors de la comparaison');
 WriteLn('  -j champ    Champ de jointure des deux fichiers');
 WriteLn('  -j1 champ   Champ de jointure du fichier 1');
 WriteLn('  -j2 champ   Champ de jointure du fichier 2');
 WriteLn('  -o liste    Format de sortie: 0 (champ de jointure) ou F.N (fichier F, champ N)');
 WriteLn('  -t car      Utilise car comme separateur de champs');
 WriteLn('  -v numero   N''affiche que les lignes sans correspondance du fichier 1 ou 2');
 WriteLn('  --help      Affiche cette aide');
 WriteLn('  --version   Affiche la version');
End;

Procedure Fail(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'join: ',S);
 {$ELSE}
 WriteLn('join: ',S);
 {$ENDIF}
 Halt(1);
End;

Procedure Warn(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'join: ',S);
 {$ELSE}
 WriteLn('join: ',S);
 {$ENDIF}
End;

Function IntStr(N:Longint):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

Function ToNum(Const S:String;Var N:Integer):Boolean;
Var
 Err:Integer;
Begin
 Val(S,N,Err);
 ToNum:=(Err=0)And(N>0);
End;

Function UpStr(Const S:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:=S;
 For I:=1 to Length(R)Do If R[I]In['a'..'z']Then R[I]:=Chr(Ord(R[I])-32);
 UpStr:=R;
End;

{ ------------------------- Champs ------------------------- }

Function IsBlank(C:Char):Boolean;Begin
 IsBlank:=(C=' ')Or(C=#9);
End;

{ Champ N d'une ligne ('' si absent); Found indique si le champ existe }
Function FieldAt(Const L:String;N:Integer;Var Found:Boolean):String;
Var
 I,K,J:Integer;
Begin
 FieldAt:='';
 Found:=False;
 I:=1;
 K:=0;
 If HasSep Then Begin
  While I<=Length(L)+1 Do Begin
   J:=I;
   While(J<=Length(L))And(L[J]<>Sep)Do Inc(J);
   Inc(K);
   If K=N Then Begin
    FieldAt:=Copy(L,I,J-I);
    Found:=True;
    Exit;
   End;
   If J>Length(L)Then Exit;
   I:=J+1;
  End;
 End
  Else
 Begin
  While I<=Length(L)Do Begin
   While(I<=Length(L))And IsBlank(L[I])Do Inc(I);
   If I>Length(L)Then Exit;
   J:=I;
   While(J<=Length(L))And Not IsBlank(L[J])Do Inc(J);
   Inc(K);
   If K=N Then Begin
    FieldAt:=Copy(L,I,J-I);
    Found:=True;
    Exit;
   End;
   I:=J;
  End;
 End;
End;

Function FieldCount(Const L:String):Integer;
Var
 N:Integer;
 F:Boolean;
Begin
 N:=0;
 While True Do Begin
  FieldAt(L,N+1,F);
  If Not F Then Break;
  Inc(N);
 End;
 FieldCount:=N;
End;

Function KeyOf(Const L:String;Fld:Integer):String;
Var
 F:Boolean;
Begin
 KeyOf:=FieldAt(L,Fld,F);
End;

Function Cmp(Const A,B:String):Integer;Begin
 If IgnCase Then Begin
  If UpStr(A)<UpStr(B)Then Cmp:=-1
  Else If UpStr(A)>UpStr(B)Then Cmp:=1
  Else Cmp:=0;
 End
  Else
 Begin
  If A<B Then Cmp:=-1
  Else If A>B Then Cmp:=1
  Else Cmp:=0;
 End;
End;

{ ------------------------- Lecture des fichiers ------------------------- }

Procedure OpenInp(Var I:TInp;Const Name:String;Fld:Integer);Begin
 I.Name:=Name;
 If Name='-'Then Assign(I.F,'')
            Else Assign(I.F,Name);
 {$I-}Reset(I.F);{$I+}
 If IOResult<>0Then Fail('impossible d''ouvrir '+Name);
 I.Have:=False;
 I.LineNo:=0;
 I.Fld:=Fld;
 I.PrevKey:='';
 I.Warned:=False;
End;

Procedure Advance(Var I:TInp);Begin
 If EOF(I.F)Then Begin
  I.Have:=False;
  Exit;
 End;
 ReadLn(I.F,I.Line);
 Inc(I.LineNo);
 I.Have:=True;
End;

Procedure ReadGroup(Var I:TInp;G:PGroup);
Var
 K,K2:String;
Begin
 G^.N:=0;
 If Not I.Have Then Exit;
 K:=KeyOf(I.Line,I.Fld);
 G^.Key:=K;
 If(I.PrevKey<>'')And(Cmp(K,I.PrevKey)<0)And Not I.Warned Then Begin
  Warn(I.Name+':'+IntStr(I.LineNo)+': is not sorted: '+I.Line);
  I.Warned:=True;
  Unsorted:=True;
 End;
 I.PrevKey:=K;
 Repeat
  If G^.N<MaxG Then Begin
   Inc(G^.N);
   G^.L[G^.N]:=I.Line;
  End;
  Advance(I);
  If Not I.Have Then Break;
  K2:=KeyOf(I.Line,I.Fld);
 Until Cmp(K2,K)<>0;
End;

{ ------------------------- Sortie ------------------------- }

Function EmptyFix(Const S:String):String;Begin
 If(S='')And(Empty<>'')Then EmptyFix:=Empty
                       Else EmptyFix:=S;
End;

{ Tous les champs de L sauf le champ Skip, separes par OutSep }
Function Others(Const L:String;Skip:Integer):String;
Var
 I,N:Integer;
 F:Boolean;
 R,V:String;
Begin
 R:='';
 N:=FieldCount(L);
 For I:=1 to N Do If I<>Skip Then Begin
  V:=FieldAt(L,I,F);
  R:=R+OutSep+V;
 End;
 Others:=R;
End;

{ L1 / L2 : lignes (Has1/Has2 indiquent leur presence) }
Procedure PrintLine(Has1:Boolean;Const L1:String;Has2:Boolean;Const L2:String);
Var
 I:Integer;
 S,V,Key:String;
 F:Boolean;
Begin
 If Has1 Then Key:=KeyOf(L1,I1.Fld)
         Else Key:=KeyOf(L2,I2.Fld);
 If OCnt=0Then Begin
  S:=Key;
  If Has1 Then S:=S+Others(L1,I1.Fld);
  If Has2 Then S:=S+Others(L2,I2.Fld);
  WriteLn(S);
  Exit;
 End;
 S:='';
 For I:=1 to OCnt Do Begin
  V:='';
  If OFile[I]=0Then V:=Key
  Else If(OFile[I]=1)And Has1 Then V:=FieldAt(L1,OFld[I],F)
  Else If(OFile[I]=2)And Has2 Then V:=FieldAt(L2,OFld[I],F);
  If I>1Then S:=S+OutSep;
  S:=S+EmptyFix(V);
 End;
 WriteLn(S);
End;

Procedure Unpaired(Which:Integer;G:PGroup);
Var
 I:Integer;
Begin
 If Which=1Then Begin
  If Not(A1 Or V1)Then Exit;
  For I:=1 to G^.N Do PrintLine(True,G^.L[I],False,'');
 End
  Else
 Begin
  If Not(A2 Or V2)Then Exit;
  For I:=1 to G^.N Do PrintLine(False,'',True,G^.L[I]);
 End;
End;

Procedure ParseOList(Const S:String);
Var
 I,J,P,N:Integer;
 Tok:String;
Begin
 I:=1;
 While I<=Length(S)Do Begin
  While(I<=Length(S))And(S[I]In[',',' ',#9])Do Inc(I);
  If I>Length(S)Then Break;
  J:=I;
  While(J<=Length(S))And Not(S[J]In[',',' ',#9])Do Inc(J);
  Tok:=Copy(S,I,J-I);
  I:=J;
  If OCnt>=MaxO Then Fail('liste -o trop longue');
  Inc(OCnt);
  If Tok='0'Then Begin
   OFile[OCnt]:=0;
   OFld[OCnt]:=0;
  End
   Else
  Begin
   P:=Pos('.',Tok);
   If P=0Then Fail('format de champ invalide: '+Tok);
   If Not ToNum(Copy(Tok,1,P-1),N)Or((N<>1)And(N<>2))Then Fail('numero de fichier invalide: '+Tok);
   OFile[OCnt]:=N;
   If Not ToNum(Copy(Tok,P+1,10),N)Then Fail('numero de champ invalide: '+Tok);
   OFld[OCnt]:=N;
  End;
 End;
End;

Var
 I,N,F1,F2,C:Integer;
 A,V:String;
 Names:Array[1..2]Of String;
 NN:Integer;

BEGIN
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If A='--version'Then Begin
   WriteLn('join (GNU coreutils clone) 1.0');
   Halt(0);
  End;
 End;
 F1:=1;
 F2:=1;
 Empty:='';
 OCnt:=0;
 NN:=0;
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(Length(A)>1)And(A[1]='-')Then Begin
   C:=Ord(A[2]);
   V:=Copy(A,3,255);
   Case A[2]of
    '1','2':Begin
     If V=''Then Begin
      Inc(I);
      If I<=ParamCount Then V:=ParamStr(I);
     End;
     If Not ToNum(V,N)Then Fail('numero de champ invalide: '+V);
     If A[2]='1'Then F1:=N Else F2:=N;
    End;
    'a','v':Begin
     If V=''Then Begin
      Inc(I);
      If I<=ParamCount Then V:=ParamStr(I);
     End;
     If V='1'Then Begin
      If A[2]='a'Then A1:=True Else V1:=True;
     End
     Else If V='2'Then Begin
      If A[2]='a'Then A2:=True Else V2:=True;
     End
     Else Fail('numero de fichier invalide pour -'+A[2]+': '+V);
    End;
    'e':Begin
     If V=''Then Begin
      Inc(I);
      If I<=ParamCount Then V:=ParamStr(I);
     End;
     Empty:=V;
    End;
    'i':IgnCase:=True;
    'o':Begin
     If V=''Then Begin
      Inc(I);
      If I<=ParamCount Then V:=ParamStr(I);
     End;
     ParseOList(V);
    End;
    't':Begin
     If V=''Then Begin
      Inc(I);
      If I<=ParamCount Then V:=ParamStr(I);
     End;
     If Length(V)>1Then Fail('separateur de plusieurs caracteres: '+V);
     If V<>''Then Begin
      HasSep:=True;
      Sep:=V[1];
     End;
    End;
    'j':Begin
     If(V='1')Or(V='2')Then Begin
      Inc(I);
      If I<=ParamCount Then A:=ParamStr(I)
                       Else A:='';
      If Not ToNum(A,N)Then Fail('numero de champ invalide: '+A);
      If V='1'Then F1:=N Else F2:=N;
     End
      Else
     Begin
      If V=''Then Begin
       Inc(I);
       If I<=ParamCount Then V:=ParamStr(I);
      End;
      If Not ToNum(V,N)Then Fail('numero de champ invalide: '+V);
      F1:=N;
      F2:=N;
     End;
    End;
    Else Begin
     WriteLn('join: option inconnue: ',A);
     ShowUsage;
     Halt(1);
    End;
   End;
  End
   Else
  Begin
   If NN<2Then Begin
    Inc(NN);
    Names[NN]:=A;
   End
    Else
   Begin
    ShowUsage;
    Halt(1);
   End;
  End;
  Inc(I);
 End;
 If NN<>2Then Begin
  ShowUsage;
  Halt(1);
 End;
 If(Names[1]='-')And(Names[2]='-')Then Fail('les deux fichiers ne peuvent pas etre l''entree standard');
 If HasSep Then OutSep:=Sep
           Else OutSep:=' ';
 OpenInp(I1,Names[1],F1);
 OpenInp(I2,Names[2],F2);
 New(G1);
 New(G2);
 Advance(I1);
 Advance(I2);
 ReadGroup(I1,G1);
 ReadGroup(I2,G2);
 While(G1^.N>0)And(G2^.N>0)Do Begin
  C:=Cmp(G1^.Key,G2^.Key);
  If C<0Then Begin
   Unpaired(1,G1);
   ReadGroup(I1,G1);
  End
  Else If C>0Then Begin
   Unpaired(2,G2);
   ReadGroup(I2,G2);
  End
  Else Begin
   If Not(V1 Or V2)Then
    For I:=1 to G1^.N Do
     For N:=1 to G2^.N Do PrintLine(True,G1^.L[I],True,G2^.L[N]);
   ReadGroup(I1,G1);
   ReadGroup(I2,G2);
  End;
 End;
 While G1^.N>0Do Begin
  Unpaired(1,G1);
  ReadGroup(I1,G1);
 End;
 While G2^.N>0Do Begin
  Unpaired(2,G2);
  ReadGroup(I2,G2);
 End;
 Close(I1.F);
 Close(I2.F);
 If Unsorted Then Halt(1);
END.
