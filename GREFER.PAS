{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande grefer - Preprocesseur de references bibliographiques
}

Program GREFER;

{$X+}

Uses DOS;

Const
 MaxFiles=16;
 MaxRefs=60;
 MaxFields=16;
 MaxKeys=16;
 MaxBlock=40;

Type
 TFieldRec=Record
  Ch:Char;
  V:String[100];
 End;
 TRef=Record
  NF:Integer;
  F:Array[1..MaxFields]Of TFieldRec;
 End;
 PRef=^TRef;

Var
 DBFiles:Array[1..MaxFiles]Of String[127];
 DBCount:Integer;
 OptB,OptE,OptP,OptR,OptS,OptC:Boolean;
 AuthRev,FirstNum,TruncLen,LabM,LabN:Integer;
 CapSet,IgnSet,SortSet:String[26];
 LabelField:Char;
 BibMacro:String[31];
 Refs:Array[1..MaxRefs]Of PRef;
 RefCount,NextNum:Integer;
 RefEmitted:Array[1..MaxRefs]Of Boolean;
 Keys:Array[1..MaxKeys]Of String[40];
 Found:Array[1..MaxKeys]Of Boolean;
 KeyCount:Integer;
 Cand,Res,Lit:TRef;
 Matches:Integer;
 Pend:String;
 HasPend:Boolean;
 Accum:Boolean;
 CurFile:String;
 LineNo:Longint;

Procedure ShowUsage;Begin
 WriteLn('Usage: grefer [-benvCPRS] [-a n] [-c fields] [-f n] [-i fields] [-k field]');
 WriteLn('              [-l m,n] [-p filename] [-s fields] [-t n] [-B field.macro]');
 WriteLn('              [filename...]');
End;

Procedure ShowHelp;Begin
 WriteLn('GREFER : Cette commande permet de lancer le preprocesseur des references ',
         'bibliographiques de groff.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -b          Etiquettes sans crochets');
 WriteLn('  -e          Accumule les references (liste a $LIST$ ou en fin de texte)');
 WriteLn('  -n          Ne pas utiliser la base de donnees par defaut');
 WriteLn('  -v          Affiche la version');
 WriteLn('  -C          Mode de compatibilite');
 WriteLn('  -P          Ne deplace pas la ponctuation apres la citation');
 WriteLn('  -R          Ignore les blocs .R1 / .R2');
 WriteLn('  -S          Etiquette de style "Auteur Annee"');
 WriteLn('  -a n        Inverse le nom des n premiers auteurs');
 WriteLn('  -c champs   Met en majuscules les champs indiques');
 WriteLn('  -f n        Numero de la premiere etiquette');
 WriteLn('  -i champs   Champs ignores lors de la recherche');
 WriteLn('  -k champ    Utilise ce champ comme etiquette');
 WriteLn('  -l m,n      Etiquette: m lettres de l''auteur, n chiffres de l''annee');
 WriteLn('  -p fichier  Base de donnees bibliographique (repetable)');
 WriteLn('  -s champs   Trie les references selon ces champs');
 WriteLn('  -t n        Tronque les mots-cles a n caracteres (defaut: 6)');
 WriteLn('  -B champ.macro  Etiquette par champ et macro de bibliographie');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Warn(Const Msg:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'grefer: ',CurFile,':',LineNo,': ',Msg);
 {$ELSE}
 WriteLn('grefer: ',CurFile,':',LineNo,': ',Msg);
 {$ENDIF}
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

Function IntStr(N:Longint):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

Function ToNumber(Const S:String;Var N:Integer):Boolean;
Var
 Err:Integer;
Begin
 Val(S,N,Err);
 ToNumber:=(Err=0)And(S<>'');
End;

Function IsWordChar(C:Char):Boolean;Begin
 IsWordChar:=C In['A'..'Z','a'..'z','0'..'9'];
End;

Function Lower(C:Char):Char;Begin
 If C In['A'..'Z']Then Lower:=Chr(Ord(C)+32)
                  Else Lower:=C;
End;

Function UpperStr(Const S:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:=S;
 For I:=1 to Length(R)Do If R[I]In['a'..'z']Then R[I]:=Chr(Ord(R[I])-32);
 UpperStr:=R;
End;

Function LowerStr(Const S:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:=S;
 For I:=1 to Length(R)Do R[I]:=Lower(R[I]);
 LowerStr:=R;
End;

{ ------------------------- Champs d'une reference ------------------------- }

Procedure AddField(Var R:TRef;Ch:Char;Const V:String);Begin
 If R.NF<MaxFields Then Begin
  Inc(R.NF);
  R.F[R.NF].Ch:=Ch;
  R.F[R.NF].V:=Copy(V,1,100);
 End;
End;

Procedure RemoveField(Var R:TRef;Ch:Char);
Var
 I,K:Integer;
Begin
 K:=0;
 For I:=1 to R.NF Do If R.F[I].Ch<>Ch Then Begin
  Inc(K);
  R.F[K]:=R.F[I];
 End;
 R.NF:=K;
End;

Function GetField(Var R:TRef;Ch:Char;N:Integer):String;
Var
 I,C:Integer;
Begin
 GetField:='';
 C:=0;
 For I:=1 to R.NF Do If R.F[I].Ch=Ch Then Begin
  Inc(C);
  If C=N Then Begin
   GetField:=R.F[I].V;
   Exit;
  End;
 End;
End;

Function SameRef(Var A,B:TRef):Boolean;
Var
 I:Integer;
Begin
 SameRef:=False;
 If A.NF<>B.NF Then Exit;
 For I:=1 to A.NF Do
  If(A.F[I].Ch<>B.F[I].Ch)Or(A.F[I].V<>B.F[I].V)Then Exit;
 SameRef:=True;
End;

{ ------------------------- Recherche dans les bases ------------------------- }

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

Procedure ScanValue(Const S:String);
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
 If KeyCount=0Then Exit;
 For J:=1 to KeyCount Do If Not Found[J]Then Exit;
 AllFound:=True;
End;

Procedure EndRecord;
Var
 J:Integer;
Begin
 If(Cand.NF>0)And AllFound Then Begin
  Inc(Matches);
  If Matches=1Then Res:=Cand;
 End;
 Cand.NF:=0;
 For J:=1 to KeyCount Do Found[J]:=False;
End;

Procedure SearchFile(Const Name:String);
Var
 F:Text;
 L:String;
 Skip:Boolean;
 I:Integer;
Begin
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  Warn('impossible d''ouvrir '+Name);
  Exit;
 End;
 Cand.NF:=0;
 For I:=1 to KeyCount Do Found[I]:=False;
 Skip:=False;
 While Not EOF(F)Do Begin
  ReadLn(F,L);
  If Trim(L)=''Then Begin
   EndRecord;
   Skip:=False;
  End
  Else If(L[1]='%')And(Length(L)>1)Then Begin
   AddField(Cand,L[2],Trim(Copy(L,3,255)));
   Skip:=Pos(L[2],IgnSet)>0;
   If Not Skip Then ScanValue(Copy(L,3,255));
  End
  Else Begin
   If Cand.NF>0Then Begin
    If Length(Cand.F[Cand.NF].V)<99Then
     Cand.F[Cand.NF].V:=Cand.F[Cand.NF].V+' '+Copy(Trim(L),1,100-Length(Cand.F[Cand.NF].V)-1);
   End;
   If Not Skip Then ScanValue(L);
  End;
 End;
 EndRecord;
 Close(F);
End;

{ ------------------------- Etiquettes ------------------------- }

Function Surname(Const S:String):String;
Var
 I:Integer;
Begin
 I:=Length(S);
 While(I>0)And(S[I]<>' ')Do Dec(I);
 Surname:=Copy(S,I+1,255);
End;

Function ReverseName(Const S:String):String;
Var
 I:Integer;
Begin
 I:=Length(S);
 While(I>0)And(S[I]<>' ')Do Dec(I);
 If I=0Then ReverseName:=S
       Else ReverseName:=Copy(S,I+1,255)+', '+Copy(S,1,I-1);
End;

Function MakeLabel(Var R:TRef;Num:Integer):String;
Var
 S,D:String;
 N:Integer;
Begin
 MakeLabel:=IntStr(Num);
 If LabelField<>#0Then Begin
  S:=GetField(R,LabelField,1);
  If S<>''Then MakeLabel:=S;
 End
 Else If LabM>0Then Begin
  S:=Surname(GetField(R,'A',1));
  D:=GetField(R,'D',1);
  N:=LabN;
  If N>Length(D)Then N:=Length(D);
  MakeLabel:=Copy(S,1,LabM)+Copy(D,Length(D)-N+1,N);
 End
 Else If OptS Then Begin
  S:=Surname(GetField(R,'A',1));
  D:=GetField(R,'D',1);
  If S=''Then S:='?';
  MakeLabel:=S+' '+D;
 End;
End;

{ ------------------------- Sortie des references ------------------------- }

Function RefType(Var R:TRef):Integer;Begin
 If GetField(R,'J',1)<>''Then RefType:=1
 Else If GetField(R,'B',1)<>''Then RefType:=3
 Else If GetField(R,'R',1)<>''Then RefType:=4
 Else If GetField(R,'I',1)<>''Then RefType:=2
 Else RefType:=0;
End;

Function TypeName(T:Integer):String;Begin
 Case T of
  1:TypeName:='journal-article';
  2:TypeName:='book';
  3:TypeName:='article-in-book';
  4:TypeName:='tech-report';
  Else TypeName:='other';
 End;
End;

Procedure EmitRef(Var R:TRef);
Var
 I,NA:Integer;
 V:String;
 T:Integer;
Begin
 WriteLn('.]-');
 NA:=0;
 For I:=1 to R.NF Do Begin
  V:=R.F[I].V;
  If R.F[I].Ch='A'Then Begin
   Inc(NA);
   If NA<=AuthRev Then V:=ReverseName(V);
  End;
  If Pos(R.F[I].Ch,CapSet)>0Then V:=UpperStr(V);
  WriteLn('.ds [',R.F[I].Ch,' ',V);
 End;
 WriteLn('.nr [T 0');
 WriteLn('.nr [A 0');
 WriteLn('.nr [O 0');
 T:=RefType(R);
 WriteLn('.][ ',T,' ',TypeName(T));
End;

Function SortKey(Var R:TRef):String;
Var
 I,J:Integer;
 S:String;
Begin
 S:='';
 For I:=1 to Length(SortSet)Do
  For J:=1 to R.NF Do If R.F[J].Ch=SortSet[I]Then S:=S+LowerStr(R.F[J].V)+'|';
 SortKey:=Copy(S,1,200);
End;

Procedure EmitAll;
Var
 Ord_:Array[1..MaxRefs]Of Integer;
 I,J,T,N:Integer;
Begin
 N:=0;
 For I:=1 to RefCount Do If Not RefEmitted[I]Then Begin
  Inc(N);
  Ord_[N]:=I;
 End;
 If SortSet<>''Then
  For I:=1 to N-1 Do
   For J:=I+1 to N Do
    If SortKey(Refs[Ord_[J]]^)<SortKey(Refs[Ord_[I]]^)Then Begin
     T:=Ord_[I];
     Ord_[I]:=Ord_[J];
     Ord_[J]:=T;
    End;
 For I:=1 to N Do Begin
  EmitRef(Refs[Ord_[I]]^);
  RefEmitted[Ord_[I]]:=True;
 End;
End;

{ ------------------------- Traitement des citations ------------------------- }

Procedure FlushPend;Begin
 If HasPend Then WriteLn(Pend);
 HasPend:=False;
 Pend:='';
End;

Function FindRef(Var R:TRef):Integer;
Var
 I:Integer;
Begin
 FindRef:=0;
 For I:=1 to RefCount Do If SameRef(Refs[I]^,R)Then Begin
  FindRef:=I;
  Exit;
 End;
End;

Function StoreRef(Var R:TRef):Integer;Begin
 StoreRef:=0;
 If RefCount>=MaxRefs Then Begin
  Warn('trop de references');
  Exit;
 End;
 Inc(RefCount);
 New(Refs[RefCount]);
 Refs[RefCount]^:=R;
 RefEmitted[RefCount]:=False;
 StoreRef:=RefCount;
End;

Procedure ProcessCitation(Const FirstLine:String;Var F:Text);
Var
 Opening,Closing,L,Mark,Base,Punct,Query:String;
 Done,IsList:Boolean;
 I,K,Idx,NL:Integer;
 LN:Longint;
 Lbl:String;
 Found_:Boolean;
Begin
 Opening:=Trim(Copy(FirstLine,3,255));
 Closing:='';
 Query:='';
 Lit.NF:=0;
 KeyCount:=0;
 IsList:=False;
 Done:=False;
 NL:=0;
 While Not Done And Not EOF(F)Do Begin
  ReadLn(F,L);
  Inc(LineNo);
  If Copy(L,1,2)='.]'Then Begin
   Closing:=Trim(Copy(L,3,255));
   Done:=True;
  End
  Else If(Length(L)>1)And(L[1]='%')Then Begin
   AddField(Lit,L[2],Trim(Copy(L,3,255)));
  End
  Else Begin
   If Trim(L)='$LIST$'Then IsList:=True
    Else
   Begin
    AddKeys(L);
    If Length(Query)<150Then Query:=Query+' '+Trim(L);
   End;
  End;
 End;
 If IsList Then Begin
  FlushPend;
  EmitAll;
  Exit;
 End;
 { Recherche dans les bases }
 Res.NF:=0;
 Matches:=0;
 If KeyCount>0Then Begin
  For I:=1 to DBCount Do SearchFile(DBFiles[I]);
  If Matches=0Then Warn('aucune reference ne correspond a:'+Query)
  Else If Matches>1Then Warn('plusieurs references correspondent a:'+Query);
 End;
 { Les champs litteraux remplacent ceux de la base }
 For I:=1 to Lit.NF Do RemoveField(Res,Lit.F[I].Ch);
 For I:=1 to Lit.NF Do AddField(Res,Lit.F[I].Ch,Lit.F[I].V);
 If Res.NF=0Then Begin
  If HasPend Then Begin
   Pend:=Pend+Opening+Closing;
  End
   Else
  Begin
   Pend:=Opening+Closing;
   HasPend:=Pend<>'';
  End;
  Exit;
 End;
 Idx:=FindRef(Res);
 Found_:=Idx>0;
 If Not Found_ Then Begin
  Idx:=StoreRef(Res);
  If Idx=0Then Exit;
  Inc(NextNum);
 End;
 { Numero de l'etiquette : position dans la liste + numero de depart }
 Lbl:=MakeLabel(Refs[Idx]^,FirstNum+Idx-1);
 If OptB Then Mark:=Lbl
         Else Mark:='\*([.'+Lbl+'\*(.]';
 Base:='';
 Punct:='';
 If HasPend Then Begin
  Base:=Pend;
  If Not OptP And(Length(Base)>0)And(Base[Length(Base)]In['.',',',';',':','!','?'])Then Begin
   Punct:=Base[Length(Base)];
   Base:=Copy(Base,1,Length(Base)-1);
  End;
 End;
 HasPend:=False;
 Pend:='';
 WriteLn(Base,Opening,Mark,Punct,Closing);
 If Not(OptE Or Accum)And Not RefEmitted[Idx]Then Begin
  EmitRef(Refs[Idx]^);
  RefEmitted[Idx]:=True;
 End;
End;

Procedure ProcessR1(Var F:Text);
Var
 L:String;
Begin
 While Not EOF(F)Do Begin
  ReadLn(F,L);
  Inc(LineNo);
  If Copy(L,1,3)='.R2'Then Exit;
  L:=Trim(L);
  If L='accumulate'Then Accum:=True
  Else If L='no-accumulate'Then Accum:=False
  Else If L='bibliography'Then Accum:=True;
 End;
End;

Procedure ProcessFile(Const Name:String);
Var
 F:Text;
 L:String;
Begin
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  CurFile:=Name;
  Warn('impossible d''ouvrir le fichier');
  Exit;
 End;
 If Name=''Then CurFile:='<stdin>'
           Else CurFile:=Name;
 LineNo:=0;
 While Not EOF(F)Do Begin
  ReadLn(F,L);
  Inc(LineNo);
  If Copy(L,1,2)='.['Then ProcessCitation(L,F)
  Else If(Not OptR)And(Copy(L,1,3)='.R1')Then Begin
   FlushPend;
   ProcessR1(F);
  End
  Else If(Length(L)>0)And(L[1]='.')Then Begin
   FlushPend;
   WriteLn(L);
  End
  Else Begin
   FlushPend;
   Pend:=L;
   HasPend:=True;
  End;
 End;
 Close(F);
End;

{ ------------------------- Arguments ------------------------- }

Var
 I,J,K,N:Integer;
 Arg,Val_:String;
 C:Char;
 FileCnt:Integer;
 Files:Array[1..MaxFiles]Of String[127];

BEGIN
 DBCount:=0;
 FileCnt:=0;
 AuthRev:=0;
 FirstNum:=1;
 TruncLen:=6;
 LabM:=0;
 LabN:=0;
 CapSet:='';
 IgnSet:='';
 SortSet:='';
 LabelField:=#0;
 BibMacro:='';
 RefCount:=0;
 NextNum:=0;
 Accum:=False;
 HasPend:=False;
 Pend:='';
 I:=1;
 While I<=ParamCount Do Begin
  Arg:=ParamStr(I);
  If(Arg='/?')Or(Arg='--help')Or(Arg='/h')Or(Arg='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If(Length(Arg)>1)And(Arg[1]='-')Then Begin
   J:=2;
   While J<=Length(Arg)Do Begin
    C:=Arg[J];
    Inc(J);
    Case C of
     'b':OptB:=True;
     'e':OptE:=True;
     'n':;
     'C':OptC:=True;
     'P':OptP:=True;
     'R':OptR:=True;
     'S':OptS:=True;
     'v':Begin
      WriteLn('GNU refer (clone) version 1.0');
      Halt(0);
     End;
     'a','c','f','i','k','l','p','s','t','B':Begin
      If J<=Length(Arg)Then Val_:=Copy(Arg,J,255)
       Else
      Begin
       Inc(I);
       If I>ParamCount Then Begin
        ShowUsage;
        Halt(1);
       End;
       Val_:=ParamStr(I);
      End;
      J:=Length(Arg)+1;
      Case C of
       'a':If Not ToNumber(Val_,AuthRev)Then Begin
        WriteLn('grefer: valeur invalide pour -a: ',Val_);
        Halt(1);
       End;
       'c':CapSet:=Copy(Val_,1,26);
       'f':If Not ToNumber(Val_,FirstNum)Then Begin
        WriteLn('grefer: valeur invalide pour -f: ',Val_);
        Halt(1);
       End;
       'i':IgnSet:=Copy(Val_,1,26);
       'k':If Val_<>''Then LabelField:=Val_[1];
       'l':Begin
        K:=Pos(',',Val_);
        If K=0Then Begin
         If Not ToNumber(Val_,LabM)Then LabM:=0;
         LabN:=2;
        End
         Else
        Begin
         If Not ToNumber(Copy(Val_,1,K-1),LabM)Then LabM:=0;
         If Not ToNumber(Copy(Val_,K+1,255),LabN)Then LabN:=2;
        End;
       End;
       'p':If DBCount<MaxFiles Then Begin
        Inc(DBCount);
        DBFiles[DBCount]:=Copy(Val_,1,127);
       End;
       's':Begin
        SortSet:=Copy(Val_,1,26);
        If SortSet=''Then SortSet:='AD';
       End;
       't':If Not ToNumber(Val_,TruncLen)Then Begin
        WriteLn('grefer: valeur invalide pour -t: ',Val_);
        Halt(1);
       End;
       'B':Begin
        If Val_<>''Then LabelField:=Val_[1];
        K:=Pos('.',Val_);
        If K>0Then BibMacro:=Copy(Val_,K+1,31);
        Accum:=True;
       End;
      End;
     End;
     Else Begin
      WriteLn('grefer: option inconnue: -',C);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
  End
   Else
  Begin
   If FileCnt<MaxFiles Then Begin
    Inc(FileCnt);
    Files[FileCnt]:=Copy(Arg,1,127);
   End;
  End;
  Inc(I);
 End;
 If TruncLen<1Then TruncLen:=6;
 If TruncLen>40Then TruncLen:=40;
 If FileCnt=0Then ProcessFile('')
  Else
 For N:=1 to FileCnt Do ProcessFile(Files[N]);
 FlushPend;
 If OptE Or Accum Then EmitAll;
END.
