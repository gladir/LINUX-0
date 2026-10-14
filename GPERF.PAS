{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande gperf - Generateur de fonction de hachage parfaite
}

Program GPERF;

Uses DOS;

Const
 MaxKeys=200;
 MaxDecl=200;
 MaxTrail=200;
 MaxPosList=63;
 TableMax=30000;
 MaxAssoLimit=4096;
 MaxIterations=30000;

Type
 TLine=String[127];
 TKeyStr=String[63];
 TRestStr=String[100];
 TKeyArray=Array[1..MaxKeys]Of TKeyStr;
 TRestArray=Array[1..MaxKeys]Of TRestStr;
 TLineArray=Array[1..MaxDecl]Of TLine;
 TOwnerArray=Array[0..TableMax]Of Word;
 PKeyArray=^TKeyArray;
 PRestArray=^TRestArray;
 PLineArray=^TLineArray;
 POwnerArray=^TOwnerArray;

Var
 Keys:PKeyArray;
 Rest:PRestArray;
 Decl,Trail:PLineArray;
 Owner:POwnerArray;
 KeyCount,DeclCount,TrailCount:Integer;
 Hv:Array[1..MaxKeys]Of Integer;
 Order:Array[1..MaxKeys]Of Integer;
 Asso:Array[0..255]Of Integer;
 UsedCh:Array[0..255]Of Boolean;
 Pos:Array[1..MaxPosList]Of Integer;
 PosCnt:Integer;
 HasLast,AllPos,KSet:Boolean;
 OptA,OptD,OptG,OptL,OptN,OptO,OptP,OptR,OptS,OptT:Boolean;
 InitVal,Jump,SizeMul:Integer;
 FileKey:String;
 CmdLine:String;
 StructName:String;
 AssoMax:Integer;
 Seed:Longint;
 MinH,MaxH,MinL,MaxL:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: gperf [ -adghijklnoprsStv ] [ filekey ]');
End;

Procedure ShowHelp;Begin
 WriteLn('GPERF : Cette commande permet d''effectuer la creation d''une fonction ',
         'hachee a partir d''un ensemble de clefs.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -a          Genere des prototypes ANSI C');
 WriteLn('  -d          Mode debogage (statistiques)');
 WriteLn('  -g          Genere du code GNU C (__inline)');
 WriteLn('  -h          Affiche cette aide');
 WriteLn('  -i n        Valeur initiale des valeurs associees (defaut: 0)');
 WriteLn('  -j n        Pas d''increment des valeurs associees (defaut: 5, 0=aleatoire)');
 WriteLn('  -k liste    Positions des caracteres de la clef (ex: 1,2,$ ou *)');
 WriteLn('  -l          Compare la longueur avant la comparaison de chaines');
 WriteLn('  -n          N''inclut pas la longueur dans la valeur de hachage');
 WriteLn('  -o          Reordonne les clefs par frequence');
 WriteLn('  -p          La fonction retourne un pointeur au lieu d''un booleen');
 WriteLn('  -r          Valeurs associees initiales aleatoires');
 WriteLn('  -s n        Multiplicateur de taille de la table des valeurs');
 WriteLn('  -S          Genere une instruction switch');
 WriteLn('  -t          Autorise un type struct defini par l''utilisateur');
 WriteLn('  -v          Affiche la version');
 WriteLn('  filekey     Fichier de clefs (defaut: entree standard)');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Fail(Const Msg:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'gperf: ',Msg);
 {$ELSE}
 WriteLn('gperf: ',Msg);
 {$ENDIF}
 Halt(1);
End;

Procedure Dbg(Const Msg:String);Begin
 If OptD Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,Msg);
  {$ELSE}
  WriteLn(Msg);
  {$ENDIF}
 End;
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

Function Rnd(N:Integer):Integer;Begin
 Seed:=(Seed*25173+13849)And$FFFF;
 If N<=1 Then Rnd:=0
         Else Rnd:=(Seed Shr 3)Mod N;
End;

{ ------------------------- Analyse des options ------------------------- }

Procedure AddPos(P:Integer);
Var
 I:Integer;
Begin
 If(P<1)Or(P>MaxPosList)Then Fail('position invalide: '+IntStr(P));
 For I:=1 to PosCnt Do If Pos[I]=P Then Exit;
 Inc(PosCnt);
 Pos[PosCnt]:=P;
End;

Procedure ParsePositions(Const S:String);
Var
 I,J,A,B,K:Integer;
 Tok:String;
 Dash:Integer;
Begin
 PosCnt:=0;
 HasLast:=False;
 AllPos:=False;
 KSet:=True;
 I:=1;
 While I<=Length(S)Do Begin
  J:=I;
  While(J<=Length(S))And(S[J]<>',')Do Inc(J);
  Tok:=Trim(Copy(S,I,J-I));
  I:=J+1;
  If Tok=''Then Continue;
  If Tok='*'Then AllPos:=True Else
  If Tok='$'Then HasLast:=True
   Else
  Begin
   Dash:=0;
   For K:=Length(Tok)downto 1 Do If Tok[K]='-'Then Dash:=K;
   If Dash>1Then Begin
    If Not ToNumber(Copy(Tok,1,Dash-1),A)Or Not ToNumber(Copy(Tok,Dash+1,255),B)Then
     Fail('liste de positions invalide: '+S);
    For K:=A to B Do AddPos(K);
   End
    Else
   Begin
    If Not ToNumber(Tok,A)Then Fail('liste de positions invalide: '+S);
    AddPos(A);
   End;
  End;
 End;
End;

Procedure ParseArguments;
Var
 I,J,N:Integer;
 Arg,Val:String;
 C:Char;
Begin
 InitVal:=0;
 Jump:=5;
 SizeMul:=1;
 FileKey:='';
 KSet:=False;
 PosCnt:=0;
 HasLast:=False;
 AllPos:=False;
 CmdLine:='';
 For I:=1 to ParamCount Do Begin
  If CmdLine<>''Then CmdLine:=CmdLine+' ';
  CmdLine:=CmdLine+ParamStr(I);
 End;
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
     'a':OptA:=True;
     'd':OptD:=True;
     'g':OptG:=True;
     'l':OptL:=True;
     'n':OptN:=True;
     'o':OptO:=True;
     'p':OptP:=True;
     'r':OptR:=True;
     't':OptT:=True;
     'h':Begin
      ShowHelp;
      Halt(0);
     End;
     'v':Begin
      WriteLn('GNU gperf (clone) 2.7');
      Halt(0);
     End;
     'S':Begin
      OptS:=True;
      While(J<=Length(Arg))And(Arg[J]In['0'..'9'])Do Inc(J);
     End;
     'i','j','k','s':Begin
      If J<=Length(Arg)Then Val:=Copy(Arg,J,255)
       Else
      Begin
       Inc(I);
       If I>ParamCount Then Begin
        ShowUsage;
        Halt(1);
       End;
       Val:=ParamStr(I);
      End;
      J:=Length(Arg)+1;
      If C='k'Then ParsePositions(Val)
       Else
      Begin
       If Not ToNumber(Val,N)Then Fail('valeur numerique invalide: '+Val);
       Case C of
        'i':InitVal:=N;
        'j':Jump:=N;
        's':SizeMul:=N;
       End;
      End;
     End;
     Else Begin
      WriteLn('gperf: option inconnue: -',C);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
  End
   Else
  Begin
   If FileKey<>''Then Begin
    ShowUsage;
    Halt(1);
   End;
   FileKey:=Arg;
  End;
  Inc(I);
 End;
 If InitVal<0Then InitVal:=0;
 If Jump<0Then Jump:=0;
 If SizeMul<1Then SizeMul:=1;
End;

{ ------------------------- Lecture du fichier de clefs ------------------------- }

Procedure ProcessKeyLine(Const Line:String);
Var
 L,K,R:String;
 I:Integer;
Begin
 L:=Trim(Line);
 If L=''Then Exit;
 R:='';
 If L[1]='"'Then Begin
  K:='';
  I:=2;
  While(I<=Length(L))And(L[I]<>'"')Do Begin
   If(L[I]='\')And(I<Length(L))Then Inc(I);
   K:=K+L[I];
   Inc(I);
  End;
  Inc(I);
  While(I<=Length(L))And(L[I]<>',')Do Inc(I);
  R:=Trim(Copy(L,I+1,255));
 End
  Else
 Begin
  I:=1;
  While(I<=Length(L))And(L[I]<>',')Do Inc(I);
  K:=Trim(Copy(L,1,I-1));
  R:=Trim(Copy(L,I+1,255));
 End;
 If K=''Then Exit;
 If KeyCount>=MaxKeys Then Fail('trop de clefs (maximum '+IntStr(MaxKeys)+')');
 If Length(K)>63Then Fail('clef trop longue: '+K);
 Inc(KeyCount);
 Keys^[KeyCount]:=K;
 If OptT Then Rest^[KeyCount]:=R
         Else Rest^[KeyCount]:='';
End;

Procedure ReadInput;
Var
 F:Text;
 Line:String;
 State,I:Integer;
 T:String;
Begin
 Assign(F,FileKey);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Fail('impossible d''ouvrir '+FileKey);
 State:=0;
 KeyCount:=0;
 DeclCount:=0;
 TrailCount:=0;
 While Not EOF(F)Do Begin
  ReadLn(F,Line);
  T:=Trim(Line);
  If(Length(T)>=2)And(Copy(T,1,2)='%%')And(State<2)Then Inc(State)
  Else Case State of
   0:Begin
    If(T='%{')Or(T='%}')Then
    Else If DeclCount<MaxDecl Then Begin
     Inc(DeclCount);
     Decl^[DeclCount]:=Copy(Line,1,127);
    End;
   End;
   1:ProcessKeyLine(Line);
   2:If TrailCount<MaxTrail Then Begin
    Inc(TrailCount);
    Trail^[TrailCount]:=Copy(Line,1,127);
   End;
  End;
 End;
 Close(F);
 { Aucun %% : tout le fichier est une liste de clefs }
 If State=0Then Begin
  For I:=1 to DeclCount Do ProcessKeyLine(Decl^[I]);
  DeclCount:=0;
 End;
End;

{ Recherche "struct NOM" dans les declarations }
Procedure FindStructName;
Var
 I,P,Q:Integer;
 L:String;
Begin
 StructName:='';
 For I:=1 to DeclCount Do Begin
  L:=Decl^[I];
  P:=System.Pos('struct',L);
  If P>0Then Begin
   Q:=P+6;
   While(Q<=Length(L))And(L[Q]In[' ',#9])Do Inc(Q);
   While(Q<=Length(L))And(L[Q]In['A'..'Z','a'..'z','0'..'9','_'])Do Begin
    StructName:=StructName+L[Q];
    Inc(Q);
   End;
   If StructName<>''Then Exit;
  End;
 End;
End;

{ ------------------------- Recherche de la fonction de hachage ------------------------- }

Function KeyHash(K:Integer):Integer;
Var
 H,J,Len:Integer;
Begin
 Len:=Length(Keys^[K]);
 If OptN Then H:=0
         Else H:=Len;
 For J:=1 to PosCnt Do
  If Pos[J]<=Len Then H:=H+Asso[Ord(Keys^[K][Pos[J]])];
 If HasLast Then H:=H+Asso[Ord(Keys^[K][Len])];
 KeyHash:=H;
End;

Function Evaluate(Var CI,CJ:Integer):Integer;
Var
 Idx,K,H,Cnt:Integer;
Begin
 Cnt:=0;
 CI:=0;
 CJ:=0;
 For Idx:=1 to KeyCount Do Begin
  K:=Order[Idx];
  H:=KeyHash(K);
  Hv[K]:=H;
  If Owner^[H]<>0Then Begin
   Inc(Cnt);
   If CI=0Then Begin
    CI:=K;
    CJ:=Owner^[H];
   End;
  End
   Else
  Owner^[H]:=K;
 End;
 For Idx:=1 to KeyCount Do Owner^[Hv[Idx]]:=0;
 Evaluate:=Cnt;
End;

{ Retourne un caractere choisi au hasard parmi les positions retenues de la clef K }
Function PickChar(K:Integer):Integer;
Var
 M,J,R,Len:Integer;
Begin
 Len:=Length(Keys^[K]);
 M:=0;
 For J:=1 to PosCnt Do If Pos[J]<=Len Then Inc(M);
 If HasLast Then Inc(M);
 If M=0Then Begin
  PickChar:=-1;
  Exit;
 End;
 R:=Rnd(M)+1;
 For J:=1 to PosCnt Do If Pos[J]<=Len Then Begin
  Dec(R);
  If R=0Then Begin
   PickChar:=Ord(Keys^[K][Pos[J]]);
   Exit;
  End;
 End;
 PickChar:=Ord(Keys^[K][Len]);
End;

Function Solve:Boolean;
Var
 C,Cnt,C2,CI,CJ,CI2,CJ2,It,Old,Step,Who,Ch:Integer;
 MaxLen,Bound:Integer;
Begin
 Solve:=False;
 MaxLen:=0;
 For C:=1 to KeyCount Do If Length(Keys^[C])>MaxLen Then MaxLen:=Length(Keys^[C]);
 Bound:=MaxLen+(PosCnt+Ord(HasLast))*(AssoMax-1);
 If Bound>TableMax Then Exit;
 Seed:=12345;
 For C:=0 to 255 Do Begin
  If OptR Then Asso[C]:=Rnd(AssoMax)
          Else Asso[C]:=InitVal Mod AssoMax;
 End;
 Cnt:=Evaluate(CI,CJ);
 It:=0;
 While(Cnt>0)And(It<MaxIterations)Do Begin
  If Rnd(2)=0Then Who:=CI
             Else Who:=CJ;
  Ch:=PickChar(Who);
  If Ch<0Then Ch:=PickChar(CI);
  If Ch>=0Then Begin
   Old:=Asso[Ch];
   If Jump>0Then Step:=Jump Mod AssoMax
            Else Step:=1+Rnd(AssoMax-1);
   If Step=0Then Step:=1;
   Asso[Ch]:=(Old+Step)Mod AssoMax;
   C2:=Evaluate(CI2,CJ2);
   If(C2<=Cnt)Or(Rnd(16)=0)Then Begin
    Cnt:=C2;
    CI:=CI2;
    CJ:=CJ2;
   End
    Else
   Asso[Ch]:=Old;
  End;
  Inc(It);
 End;
 Dbg('Iterations pour table de '+IntStr(AssoMax)+' : '+IntStr(It));
 Solve:=(Cnt=0);
End;

Procedure SortPositions;
Var
 I,J,T:Integer;
Begin
 For I:=1 to PosCnt-1 Do
  For J:=I+1 to PosCnt Do If Pos[J]<Pos[I]Then Begin
   T:=Pos[I];
   Pos[I]:=Pos[J];
   Pos[J]:=T;
  End;
End;

{ -o : les clefs dont les caracteres sont les plus frequents sont traitees d'abord }
Procedure ComputeOrder;
Var
 Freq:Array[0..255]Of Integer;
 Score:Array[1..MaxKeys]Of Longint;
 I,J,T,Len:Integer;
Begin
 For I:=1 to KeyCount Do Order[I]:=I;
 If Not OptO Then Exit;
 FillChar(Freq,SizeOf(Freq),0);
 For I:=1 to KeyCount Do Begin
  Len:=Length(Keys^[I]);
  For J:=1 to PosCnt Do If Pos[J]<=Len Then Inc(Freq[Ord(Keys^[I][Pos[J]])]);
  If HasLast Then Inc(Freq[Ord(Keys^[I][Len])]);
 End;
 For I:=1 to KeyCount Do Begin
  Score[I]:=0;
  Len:=Length(Keys^[I]);
  For J:=1 to PosCnt Do If Pos[J]<=Len Then Score[I]:=Score[I]+Freq[Ord(Keys^[I][Pos[J]])];
  If HasLast Then Score[I]:=Score[I]+Freq[Ord(Keys^[I][Len])];
 End;
 For I:=1 to KeyCount-1 Do
  For J:=I+1 to KeyCount Do If Score[Order[J]]>Score[Order[I]]Then Begin
   T:=Order[I];
   Order[I]:=Order[J];
   Order[J]:=T;
  End;
End;

{ ------------------------- Generation du code C ------------------------- }

Function CStr(Const S:String):String;
Var
 R:String;
 I:Integer;
 N:Integer;
Begin
 R:='"';
 For I:=1 to Length(S)Do Begin
  N:=Ord(S[I]);
  If(S[I]='"')Or(S[I]='\')Then R:=R+'\'+S[I]
  Else If(N<32)Or(N>126)Then
   R:=R+'\'+Chr(48+(N Shr 6)And 7)+Chr(48+(N Shr 3)And 7)+Chr(48+N And 7)
  Else R:=R+S[I];
 End;
 CStr:=R+'"';
End;

Function RetType:String;Begin
 If OptP Then Begin
  If OptT Then RetType:='const struct '+StructName+' *'
          Else RetType:='const char *';
 End
  Else
 RetType:='int';
End;

Procedure EmitHeader;
Var
 I,J:Integer;
 AType:String;
Begin
 WriteLn('/* C code produced by gperf version 2.7 (Pascal clone) */');
 WriteLn('/* Command-line: gperf ',CmdLine,' */');
 For I:=1 to DeclCount Do WriteLn(Decl^[I]);
 WriteLn;
 WriteLn('#define TOTAL_KEYWORDS ',KeyCount);
 WriteLn('#define MIN_WORD_LENGTH ',MinL);
 WriteLn('#define MAX_WORD_LENGTH ',MaxL);
 WriteLn('#define MIN_HASH_VALUE ',MinH);
 WriteLn('#define MAX_HASH_VALUE ',MaxH);
 WriteLn('/* maximum key range = ',MaxH-MinH+1,', duplicates = 0 */');
 WriteLn;
 If OptG Then Begin
  WriteLn('#ifdef __GNUC__');
  WriteLn('__inline');
  WriteLn('#endif');
 End;
 WriteLn('static unsigned int');
 If OptA Then WriteLn('hash (const char *str, unsigned int len)')
  Else
 Begin
  WriteLn('hash (str, len)');
  WriteLn('     register const char *str;');
  WriteLn('     register unsigned int len;');
 End;
 WriteLn('{');
 If MaxH+1>255Then AType:='unsigned short'
              Else AType:='unsigned char';
 WriteLn('  static const ',AType,' asso_values[] =');
 WriteLn('    {');
 For I:=0 to 15 Do Begin
  Write('     ');
  For J:=0 to 15 Do Begin
   Write(' ',Asso[I*16+J]);
   If I*16+J<255Then Write(',');
  End;
  WriteLn;
 End;
 WriteLn('    };');
 If OptN Then WriteLn('  register int hval = 0;')
         Else WriteLn('  register int hval = len;');
 For I:=PosCnt downto 1 Do Begin
  WriteLn('  if (len >= ',Pos[I],')');
  WriteLn('    hval += asso_values[(unsigned char)str[',Pos[I]-1,']];');
 End;
 If HasLast Then WriteLn('  return hval + asso_values[(unsigned char)str[len - 1]];')
            Else WriteLn('  return hval;');
 WriteLn('}');
 WriteLn;
End;

Procedure EmitWordList(Slot:POwnerArray);
Var
 H,K:Integer;
Begin
 If OptT Then WriteLn('static const struct ',StructName,' wordlist[] =')
         Else WriteLn('static const char * const wordlist[] =');
 WriteLn('  {');
 For H:=0 to MaxH Do Begin
  K:=Slot^[H];
  Write('    ');
  If K=0Then Begin
   If OptT Then Write('{""}')
           Else Write('""');
  End
   Else
  Begin
   If OptT Then Begin
    Write('{',CStr(Keys^[K]));
    If Rest^[K]<>''Then Write(', ',Rest^[K]);
    Write('}');
   End
    Else
   Write(CStr(Keys^[K]));
  End;
  If H<MaxH Then Write(',');
  WriteLn;
 End;
 WriteLn('  };');
 WriteLn;
 If OptL Then Begin
  WriteLn('static const unsigned char lengthtable[] =');
  WriteLn('  {');
  For H:=0 to MaxH Do Begin
   K:=Slot^[H];
   Write('    ');
   If K=0Then Write(0)
         Else Write(Length(Keys^[K]));
   If H<MaxH Then Write(',');
   WriteLn;
  End;
  WriteLn('  };');
  WriteLn;
 End;
End;

Procedure EmitLookup(Slot:POwnerArray);
Var
 H,K:Integer;
 Cond,Ret:String;
Begin
 If OptG Then Begin
  WriteLn('#ifdef __GNUC__');
  WriteLn('__inline');
  WriteLn('#endif');
 End;
 WriteLn(RetType);
 If OptA Then WriteLn('in_word_set (const char *str, unsigned int len)')
  Else
 Begin
  WriteLn('in_word_set (str, len)');
  WriteLn('     register const char *str;');
  WriteLn('     register unsigned int len;');
 End;
 WriteLn('{');
 WriteLn('  if (len <= MAX_WORD_LENGTH && len >= MIN_WORD_LENGTH)');
 WriteLn('    {');
 WriteLn('      register int key = hash (str, len);');
 WriteLn;
 WriteLn('      if (key <= MAX_HASH_VALUE && key >= MIN_HASH_VALUE)');
 WriteLn('        {');
 If OptS Then Begin
  WriteLn('          switch (key)');
  WriteLn('            {');
  For H:=MinH to MaxH Do Begin
   K:=Slot^[H];
   If K<>0Then Begin
    WriteLn('              case ',H,':');
    If OptL Then Cond:='len == '+IntStr(Length(Keys^[K]))+
                       ' && !strncmp (str, '+CStr(Keys^[K])+', len)'
            Else Cond:='!strcmp (str, '+CStr(Keys^[K])+')';
    If OptP Then Begin
     If OptT Then Ret:='&wordlist['+IntStr(H)+']'
             Else Ret:=CStr(Keys^[K]);
    End
     Else
    Ret:='1';
    WriteLn('                if (',Cond,')');
    WriteLn('                  return ',Ret,';');
    WriteLn('                break;');
   End;
  End;
  WriteLn('            }');
 End
  Else
 Begin
  If OptT Then WriteLn('          register const char *s = wordlist[key].name;')
          Else WriteLn('          register const char *s = wordlist[key];');
  WriteLn;
  If OptL Then
   Cond:='len == lengthtable[key] && *str == *s && !strncmp (str + 1, s + 1, len - 1)'
  Else
   Cond:='*str == *s && !strcmp (str + 1, s + 1)';
  If OptP Then Begin
   If OptT Then Ret:='&wordlist[key]'
           Else Ret:='s';
  End
   Else
  Ret:='1';
  WriteLn('          if (',Cond,')');
  WriteLn('            return ',Ret,';');
 End;
 WriteLn('        }');
 WriteLn('    }');
 WriteLn('  return 0;');
 WriteLn('}');
End;

Var
 I,K,H,MaxLen:Integer;
 Slot:POwnerArray;
 Done:Boolean;

BEGIN
 ParseArguments;
 New(Keys);
 New(Rest);
 New(Decl);
 New(Trail);
 New(Owner);
 New(Slot);
 FillChar(Owner^,SizeOf(Owner^),0);
 FillChar(Slot^,SizeOf(Slot^),0);
 ReadInput;
 If KeyCount=0Then Fail('aucune clef dans l''entree');
 For I:=1 to KeyCount-1 Do
  For K:=I+1 to KeyCount Do
   If Keys^[I]=Keys^[K]Then Fail('clef dupliquee: '+Keys^[I]);
 If OptT Then Begin
  FindStructName;
  If StructName=''Then Fail('option -t: aucune declaration "struct" trouvee');
 End;
 MaxLen:=0;
 For I:=1 to KeyCount Do If Length(Keys^[I])>MaxLen Then MaxLen:=Length(Keys^[I]);
 { Positions }
 If Not KSet Then Begin
  PosCnt:=0;
  AddPos(1);
  HasLast:=True;
 End
  Else
 Begin
  If AllPos Then
   For I:=1 to MaxLen Do If I<=MaxPosList Then AddPos(I);
  K:=0;
  For I:=1 to PosCnt Do Begin
   If Pos[I]<=MaxLen Then Begin
    Inc(K);
    Pos[K]:=Pos[I];
   End;
  End;
  PosCnt:=K;
 End;
 SortPositions;
 If(PosCnt=0)And Not HasLast Then Fail('aucune position de clef utilisable');
 ComputeOrder;
 { Recherche des valeurs associees }
 AssoMax:=2;
 While AssoMax<KeyCount*SizeMul Do AssoMax:=AssoMax*2;
 Done:=False;
 While(Not Done)And(AssoMax<=MaxAssoLimit)Do Begin
  Done:=Solve;
  If Not Done Then AssoMax:=AssoMax*2;
 End;
 If Not Done Then
  Fail('impossible de trouver une fonction de hachage parfaite; essayez d''autres positions avec -k');
 { Statistiques }
 FillChar(UsedCh,SizeOf(UsedCh),False);
 MinH:=32767;
 MaxH:=0;
 MinL:=255;
 MaxL:=0;
 For I:=1 to KeyCount Do Begin
  H:=KeyHash(I);
  Hv[I]:=H;
  If H<MinH Then MinH:=H;
  If H>MaxH Then MaxH:=H;
  If Length(Keys^[I])<MinL Then MinL:=Length(Keys^[I]);
  If Length(Keys^[I])>MaxL Then MaxL:=Length(Keys^[I]);
  Slot^[H]:=I;
  For K:=1 to PosCnt Do
   If Pos[K]<=Length(Keys^[I])Then UsedCh[Ord(Keys^[I][Pos[K]])]:=True;
  If HasLast Then UsedCh[Ord(Keys^[I][Length(Keys^[I])])]:=True;
 End;
 For K:=0 to 255 Do If Not UsedCh[K]Then Asso[K]:=MaxH+1;
 Dbg('Nombre de clefs : '+IntStr(KeyCount));
 Dbg('Valeur max associee : '+IntStr(AssoMax-1));
 Dbg('Plage de hachage : '+IntStr(MinH)+'..'+IntStr(MaxH));
 EmitHeader;
 If OptT Or Not OptS Then EmitWordList(Slot);
 EmitLookup(Slot);
 For I:=1 to TrailCount Do WriteLn(Trail^[I]);
 Dispose(Slot);
 Dispose(Owner);
 Dispose(Trail);
 Dispose(Decl);
 Dispose(Rest);
 Dispose(Keys);
END.
