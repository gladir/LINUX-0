{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande merge (RCS) - Fusion a trois fichiers
}

Program MERGE;

{$X+}
{$R-}
{$M 32768,0,400000}

Uses DOS;

Const
 MaxLines=3000;
 MaxOut=7000;
 MaxHunks=1500;
 MaxCells=360000;

Type
 PStr=^String;
 TLines=Array[1..MaxLines]Of PStr;
 PLines=^TLines;
 TOut=Array[1..MaxOut]Of PStr;
 POut=^TOut;
 THunk=Record
  BS,BL,NS,NL:Integer;
 End;
 THunks=Array[1..MaxHunks]Of THunk;
 PHunks=^THunks;
 TRowB=Array[0..32000]Of Byte;
 PRowB=^TRowB;
 TRowW=Array[0..32000]Of Word;
 PRowW=^TRowW;

Var
 LBase,LA,LB:PLines;
 NBase,NA,NB:Integer;
 H1,H2:PHunks;
 N1,N2:Integer;
 Res:POut;
 ResN:Integer;
 OptA,OptE,OptP,OptQ:Boolean;
 Labels:Array[1..3]Of String;
 LabelCnt:Integer;
 FileA,FileBase,FileB:String;
 Conflicts:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: merge [ options ] file1 file2 file3');
End;

Procedure ShowHelp;Begin
 WriteLn('MERGE : Cette commande permet d''effectuer la fusion de deux fichiers en un nouveau fichier.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('Incorpore dans file1 les modifications qui menent de file2 a file3.');
 WriteLn;
 WriteLn('  -A          Conflits au style -A de diff3 (affiche aussi le texte d''origine)');
 WriteLn('  -E          Conflits delimites par <<<<<<< ======= >>>>>>> (defaut)');
 WriteLn('  -e          Comme -E, sans avertissement en cas de conflit');
 WriteLn('  -L etiquette  Etiquette des marqueurs de conflit (jusqu''a trois fois)');
 WriteLn('  -p          Ecrit le resultat sur la sortie standard au lieu de file1');
 WriteLn('  -q          Mode silencieux: pas d''avertissement de conflit');
 WriteLn('  -V          Affiche la version');
 WriteLn('  --help, /?  Affiche cette aide');
 WriteLn;
 WriteLn('Code de retour: 0 sans conflit, 1 avec conflits, 2 en cas d''erreur.');
End;

Procedure Fail(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'merge: ',S);
 {$ELSE}
 WriteLn('merge: ',S);
 {$ENDIF}
 Halt(2);
End;

Function NewPStr(Const S:String):PStr;
Var
 P:PStr;
Begin
 GetMem(P,Length(S)+1);
 Move(S,P^,Length(S)+1);
 NewPStr:=P;
End;

Procedure ReadFile(Const Name:String;L:PLines;Var N:Integer);
Var
 F:Text;
 S:String;
Begin
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Fail(Name+': impossible d''ouvrir le fichier');
 N:=0;
 While Not EOF(F)Do Begin
  ReadLn(F,S);
  If N>=MaxLines Then Fail(Name+': fichier trop long (maximum '+'3000 lignes)');
  Inc(N);
  L^[N]:=NewPStr(S);
 End;
 Close(F);
End;

{ ------------------------- Comparaison (diff) ------------------------- }

Procedure AddHunk(H:PHunks;Var N:Integer;BS,BL,NS,NL:Integer);Begin
 If N>=MaxHunks Then Fail('trop de differences');
 Inc(N);
 H^[N].BS:=BS;
 H^[N].BL:=BL;
 H^[N].NS:=NS;
 H^[N].NL:=NL;
End;

{ Compare X[1..NX] (base) a Y[1..NY]; produit les blocs de differences }
Procedure Diff(X:PLines;NX:Integer;Y:PLines;NY:Integer;H:PHunks;Var HN:Integer);
Var
 P,S,N,M,I,J,SI,SJ:Integer;
 Rows:Array[1..MaxLines]Of PRowB;
 Prev,Cur:PRowW;
 Open:Boolean;
 Dir:Byte;
 Tmp:PRowW;
Begin
 HN:=0;
 P:=0;
 While(P<NX)And(P<NY)And(X^[P+1]^=Y^[P+1]^)Do Inc(P);
 S:=0;
 While(S<NX-P)And(S<NY-P)And(X^[NX-S]^=Y^[NY-S]^)Do Inc(S);
 N:=NX-P-S;
 M:=NY-P-S;
 If(N=0)And(M=0)Then Exit;
 If(N=0)Or(M=0)Or(Longint(N)*M>MaxCells)Then Begin
  AddHunk(H,HN,P+1,N,P+1,M);
  Exit;
 End;
 { LCS sur les suffixes : Len[i][j] = LCS de X[i..N] et Y[j..M] }
 GetMem(Prev,(M+2)*2);
 GetMem(Cur,(M+2)*2);
 For J:=0 to M+1 Do Prev^[J]:=0;
 For I:=N downto 1 Do Begin
  GetMem(Rows[I],M+2);
  Cur^[M+1]:=0;
  For J:=M downto 1 Do Begin
   If X^[P+I]^=Y^[P+J]^Then Begin
    Cur^[J]:=Prev^[J+1]+1;
    Rows[I]^[J]:=1;
   End
   Else If Prev^[J]>=Cur^[J+1]Then Begin
    Cur^[J]:=Prev^[J];
    Rows[I]^[J]:=2;
   End
    Else
   Begin
    Cur^[J]:=Cur^[J+1];
    Rows[I]^[J]:=3;
   End;
  End;
  Tmp:=Prev;
  Prev:=Cur;
  Cur:=Tmp;
 End;
 { parcours avant: construit les blocs }
 I:=1;
 J:=1;
 Open:=False;
 SI:=1;
 SJ:=1;
 While(I<=N)And(J<=M)Do Begin
  Dir:=Rows[I]^[J];
  If Dir=1Then Begin
   If Open Then Begin
    AddHunk(H,HN,P+SI,I-SI,P+SJ,J-SJ);
    Open:=False;
   End;
   Inc(I);
   Inc(J);
  End
   Else
  Begin
   If Not Open Then Begin
    Open:=True;
    SI:=I;
    SJ:=J;
   End;
   If Dir=2Then Inc(I)
           Else Inc(J);
  End;
 End;
 If(I<=N)Or(J<=M)Or Open Then Begin
  If Not Open Then Begin
   SI:=I;
   SJ:=J;
  End;
  AddHunk(H,HN,P+SI,N+1-SI,P+SJ,M+1-SJ);
 End;
 For I:=1 to N Do FreeMem(Rows[I],M+2);
 FreeMem(Prev,(M+2)*2);
 FreeMem(Cur,(M+2)*2);
End;

{ ------------------------- Fusion ------------------------- }

Procedure Emit(Const S:String);Begin
 If ResN>=MaxOut Then Fail('resultat trop long');
 Inc(ResN);
 Res^[ResN]:=NewPStr(S);
End;

Procedure EmitBase(A,B:Integer);
Var
 I:Integer;
Begin
 For I:=A to B Do Emit(LBase^[I]^);
End;

Procedure EmitSrc(L:PLines;A,Cnt:Integer);
Var
 I:Integer;
Begin
 For I:=A to A+Cnt-1 Do Emit(L^[I]^);
End;

{ Texte d'un cote pour la region [RS,RE) de la base, en appliquant les blocs I0..I1 }
Procedure BuildSide(H:PHunks;I0,I1,RS,RE:Integer;Src:PLines;Out:POut;Var On:Integer);
Var
 K,Pos_,I:Integer;
Begin
 On:=0;
 Pos_:=RS;
 For K:=I0 to I1 Do Begin
  For I:=Pos_ to H^[K].BS-1 Do Begin
   Inc(On);
   Out^[On]:=LBase^[I];
  End;
  For I:=H^[K].NS to H^[K].NS+H^[K].NL-1 Do Begin
   Inc(On);
   Out^[On]:=Src^[I];
  End;
  Pos_:=H^[K].BS+H^[K].BL;
 End;
 For I:=Pos_ to RE-1 Do Begin
  Inc(On);
  Out^[On]:=LBase^[I];
 End;
End;

Function SameText(A:POut;NA_:Integer;B:POut;NB_:Integer):Boolean;
Var
 I:Integer;
Begin
 SameText:=False;
 If NA_<>NB_ Then Exit;
 For I:=1 to NA_ Do If A^[I]^<>B^[I]^Then Exit;
 SameText:=True;
End;

Function LabelOf(I:Integer;Const Def:String):String;Begin
 If I<=LabelCnt Then LabelOf:=Labels[I]
                Else LabelOf:=Def;
End;

Procedure MergeAll;
Var
 B,I,J,I1,J1,S1,E1,S2,E2,RS,RE,K:Integer;
 TA,TB,TO_:POut;
 NTA,NTB,NTO:Integer;
Begin
 New(TA);
 New(TB);
 New(TO_);
 B:=1;
 I:=1;
 J:=1;
 ResN:=0;
 While(I<=N1)Or(J<=N2)Do Begin
  If I>N1 Then Begin
   S2:=H2^[J].BS;
   EmitBase(B,S2-1);
   EmitSrc(LB,H2^[J].NS,H2^[J].NL);
   B:=S2+H2^[J].BL;
   Inc(J);
  End
  Else If J>N2 Then Begin
   S1:=H1^[I].BS;
   EmitBase(B,S1-1);
   EmitSrc(LA,H1^[I].NS,H1^[I].NL);
   B:=S1+H1^[I].BL;
   Inc(I);
  End
   Else
  Begin
   S1:=H1^[I].BS;
   E1:=S1+H1^[I].BL;
   S2:=H2^[J].BS;
   E2:=S2+H2^[J].BL;
   If E1<S2 Then Begin
    EmitBase(B,S1-1);
    EmitSrc(LA,H1^[I].NS,H1^[I].NL);
    B:=E1;
    Inc(I);
   End
   Else If E2<S1 Then Begin
    EmitBase(B,S2-1);
    EmitSrc(LB,H2^[J].NS,H2^[J].NL);
    B:=E2;
    Inc(J);
   End
    Else
   Begin
    { chevauchement : regroupe les blocs qui se touchent }
    RS:=S1;
    If S2<RS Then RS:=S2;
    RE:=E1;
    If E2>RE Then RE:=E2;
    I1:=I;
    J1:=J;
    K:=1;
    While K>0Do Begin
     K:=0;
     If(I1<N1)And(H1^[I1+1].BS<=RE)Then Begin
      Inc(I1);
      K:=1;
      If H1^[I1].BS+H1^[I1].BL>RE Then RE:=H1^[I1].BS+H1^[I1].BL;
     End;
     If(J1<N2)And(H2^[J1+1].BS<=RE)Then Begin
      Inc(J1);
      K:=1;
      If H2^[J1].BS+H2^[J1].BL>RE Then RE:=H2^[J1].BS+H2^[J1].BL;
     End;
    End;
    EmitBase(B,RS-1);
    BuildSide(H1,I,I1,RS,RE,LA,TA,NTA);
    BuildSide(H2,J,J1,RS,RE,LB,TB,NTB);
    NTO:=0;
    For K:=RS to RE-1 Do Begin
     Inc(NTO);
     TO_^[NTO]:=LBase^[K];
    End;
    If SameText(TA,NTA,TB,NTB)Then Begin
     For K:=1 to NTA Do Emit(TA^[K]^);
    End
    Else If SameText(TA,NTA,TO_,NTO)Then Begin
     For K:=1 to NTB Do Emit(TB^[K]^);
    End
    Else If SameText(TB,NTB,TO_,NTO)Then Begin
     For K:=1 to NTA Do Emit(TA^[K]^);
    End
    Else Begin
     Inc(Conflicts);
     Emit('<<<<<<< '+LabelOf(1,FileA));
     For K:=1 to NTA Do Emit(TA^[K]^);
     If OptA Then Begin
      Emit('||||||| '+LabelOf(2,FileBase));
      For K:=1 to NTO Do Emit(TO_^[K]^);
     End;
     Emit('=======');
     For K:=1 to NTB Do Emit(TB^[K]^);
     Emit('>>>>>>> '+LabelOf(3,FileB));
    End;
    B:=RE;
    I:=I1+1;
    J:=J1+1;
   End;
  End;
 End;
 EmitBase(B,NBase);
 Dispose(TA);
 Dispose(TB);
 Dispose(TO_);
End;

Var
 I,K:Integer;
 A,V:String;
 NF:Integer;
 Names:Array[1..3]Of String;
 T:Text;

BEGIN
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
 End;
 NF:=0;
 LabelCnt:=0;
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(Length(A)>1)And(A[1]='-')Then Begin
   K:=2;
   While K<=Length(A)Do Begin
    Case A[K]of
     'A':OptA:=True;
     'E':OptA:=False;
     'e':OptE:=True;
     'p':OptP:=True;
     'q':OptQ:=True;
     'V':Begin
      WriteLn('merge (RCS clone) 1.0');
      Halt(0);
     End;
     'L':Begin
      V:=Copy(A,K+1,255);
      If V=''Then Begin
       Inc(I);
       If I<=ParamCount Then V:=ParamStr(I);
      End;
      If LabelCnt>=3Then Fail('trop d''etiquettes -L (maximum 3)');
      Inc(LabelCnt);
      Labels[LabelCnt]:=V;
      K:=Length(A);
     End;
     Else Begin
      WriteLn('merge: option inconnue: -',A[K]);
      ShowUsage;
      Halt(2);
     End;
    End;
    Inc(K);
   End;
  End
   Else
  Begin
   If NF>=3Then Begin
    ShowUsage;
    Halt(2);
   End;
   Inc(NF);
   Names[NF]:=A;
  End;
  Inc(I);
 End;
 If NF<>3Then Begin
  ShowUsage;
  Halt(2);
 End;
 FileA:=Names[1];
 FileBase:=Names[2];
 FileB:=Names[3];
 New(LBase);
 New(LA);
 New(LB);
 New(H1);
 New(H2);
 New(Res);
 ReadFile(FileA,LA,NA);
 ReadFile(FileBase,LBase,NBase);
 ReadFile(FileB,LB,NB);
 Diff(LBase,NBase,LA,NA,H1,N1);
 Diff(LBase,NBase,LB,NB,H2,N2);
 Conflicts:=0;
 MergeAll;
 If OptP Then Begin
  For I:=1 to ResN Do WriteLn(Res^[I]^);
 End
  Else
 Begin
  Assign(T,FileA);
  {$I-}Rewrite(T);{$I+}
  If IOResult<>0Then Fail(FileA+': impossible d''ecrire le fichier');
  For I:=1 to ResN Do WriteLn(T,Res^[I]^);
  Close(T);
 End;
 If Conflicts>0Then Begin
  If Not(OptQ Or OptE)Then Begin
   {$IFDEF FPC}
   WriteLn(StdErr,'merge: warning: conflicts during merge');
   {$ELSE}
   WriteLn('merge: warning: conflicts during merge');
   {$ENDIF}
  End;
  Halt(1);
 End;
END.
