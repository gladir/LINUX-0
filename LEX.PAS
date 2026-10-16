{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande lex - Generateur d'analyseurs lexicaux (produit lex.yy.c)
}

Program LEX;

{$X+}
{$R-}
{$M 49152,0,655360}

Uses DOS;

Const
 MaxNfa=4000;
 MaxSets=1000;
 MaxRules=150;
 MaxDfa=500;
 MaxNames=60;
 MaxConds=16;
 MaxVerb=400;
 MaxAct=1500;
 MaxUser=1500;
 PoolSz=30000;
 MaxDepth=12;

Type
 PStr=^String;
 TCSet=Set Of Char;
 TByteArr=Array[1..MaxNfa]Of Byte;
 TWordArr=Array[1..MaxNfa]Of Word;
 TSetArr=Array[1..MaxSets]Of TCSet;
 PByteArr=^TByteArr;
 PWordArr=^TWordArr;
 PSetArr=^TSetArr;
 TPool=Array[0..PoolSz]Of Word;
 PPool=^TPool;
 TRow=Array[0..255]Of Integer;
 PRow=^TRow;
 TRule=Record
  Pat:PStr;
  Explicit:Boolean;
  Mask:Word;
  ActFirst,ActCnt:Integer;
  ActBar:Boolean;
  Line:Longint;
  Start:Integer;
  Bol:Boolean;
  Trail:Integer;
 End;
 TFrag=Record
  S,E:Integer;
 End;

Var
 { NFA }
 NKind:PByteArr;      { 0 epsilon, 1 ensemble, 2 acceptation }
 NN1,NN2,NSet,NRule:PWordArr;
 NfaCnt:Integer;
 Sets:PSetArr;
 SetCnt:Integer;
 { Specification }
 Rules:Array[1..MaxRules]Of TRule;
 RuleCnt:Integer;
 DefName:Array[1..MaxNames]Of String[31];
 DefText:Array[1..MaxNames]Of String[200];
 DefCnt:Integer;
 CondName:Array[0..MaxConds-1]Of String[31];
 CondInc:Array[0..MaxConds-1]Of Boolean;
 CondCnt:Integer;
 Verb:Array[1..MaxVerb]Of PStr;
 VerbCnt:Integer;
 Acts:Array[1..MaxAct]Of PStr;
 ActCnt:Integer;
 UserCode:Array[1..MaxUser]Of PStr;
 UserCnt:Integer;
 { DFA }
 DOff,DLen:Array[1..MaxDfa]Of Word;
 DAcc:Array[1..MaxDfa]Of Integer;
 DfaCnt:Integer;
 Rows:Array[0..MaxDfa]Of PRow;
 Pool:PPool;
 PoolPos:Longint;
 Cls:Array[0..255]Of Integer;
 Rep:Array[0..255]Of Integer;
 NC:Integer;
 StartDfa:Array[0..2*MaxConds-1]Of Integer;
 { Analyse d'expressions }
 PS:String;
 PP:Integer;
 Depth:Integer;
 TrailMode,TrailVar:Boolean;
 TrailLen:Integer;
 Failed:Boolean;
 LineNo:Longint;
 { Options }
 OptT,OptV,OptN,OptQ:Boolean;
 InName:String;
 OutF:Text;
 HasYywrap,HasMain:Boolean;
 DfaUsed:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: lex [-c] [-n] [-t] [-v] [-e | -w] [-V -Q[y | n]] [file]');
End;

Procedure ShowHelp;Begin
 WriteLn('LEX : Cette commande permet de generer les programmes pour les taches lexicales.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -c          Genere du C (par defaut)');
 WriteLn('  -n          Ne pas afficher le resume des statistiques (par defaut)');
 WriteLn('  -t          Ecrit le programme sur la sortie standard au lieu de lex.yy.c');
 WriteLn('  -v          Affiche un resume des statistiques sur la sortie d''erreur');
 WriteLn('  -e, -w      Caracteres larges (acceptes, sans effet)');
 WriteLn('  -V          Affiche la version');
 WriteLn('  -Q y|n      Ajoute (y) ou non (n) la version dans le fichier genere');
 WriteLn('  file        Specification lex (defaut: entree standard)');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Err(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'lex: ligne ',LineNo,': ',S);
 {$ELSE}
 WriteLn('lex: ligne ',LineNo,': ',S);
 {$ENDIF}
 Failed:=True;
End;

Function IntStr(N:Longint):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
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

Function NewPStr(Const S:String):PStr;
Var
 P:PStr;
Begin
 GetMem(P,Length(S)+1);
 Move(S,P^,Length(S)+1);
 NewPStr:=P;
End;

Function IsAlpha(C:Char):Boolean;Begin
 IsAlpha:=C In['A'..'Z','a'..'z','_'];
End;

Function IsAlnum(C:Char):Boolean;Begin
 IsAlnum:=C In['A'..'Z','a'..'z','_','0'..'9'];
End;

Function IsBlank(C:Char):Boolean;Begin
 IsBlank:=(C=' ')Or(C=#9);
End;

{ ------------------------- Automate non deterministe ------------------------- }

Function NewNfa(K:Integer):Integer;Begin
 If NfaCnt>=MaxNfa Then Begin
  If Not Failed Then Err('expression trop complexe (trop d''etats)');
  Failed:=True;
  NewNfa:=1;
  Exit;
 End;
 Inc(NfaCnt);
 NKind^[NfaCnt]:=K;
 NN1^[NfaCnt]:=0;
 NN2^[NfaCnt]:=0;
 NSet^[NfaCnt]:=0;
 NRule^[NfaCnt]:=0;
 NewNfa:=NfaCnt;
End;

Function AddSet(Const S:TCSet):Integer;
Var
 I:Integer;
Begin
 For I:=1 to SetCnt Do If Sets^[I]=S Then Begin
  AddSet:=I;
  Exit;
 End;
 If SetCnt>=MaxSets Then Begin
  Err('trop de classes de caracteres');
  AddSet:=1;
  Exit;
 End;
 Inc(SetCnt);
 Sets^[SetCnt]:=S;
 AddSet:=SetCnt;
End;

Procedure MkSet(Const S:TCSet;Var F:TFrag);
Var
 A,B:Integer;
Begin
 A:=NewNfa(1);
 B:=NewNfa(0);
 NSet^[A]:=AddSet(S);
 NN1^[A]:=B;
 F.S:=A;
 F.E:=B;
 If TrailMode Then Inc(TrailLen);
End;

Procedure MkEmpty(Var F:TFrag);
Var
 A,B:Integer;
Begin
 A:=NewNfa(0);
 B:=NewNfa(0);
 NN1^[A]:=B;
 F.S:=A;
 F.E:=B;
End;

Procedure Cat(Var A:TFrag;Const B:TFrag);Begin
 NN1^[A.E]:=B.S;
 A.E:=B.E;
End;

Procedure MkAlt(Var A:TFrag;Const B:TFrag);
Var
 S,E:Integer;
Begin
 S:=NewNfa(0);
 E:=NewNfa(0);
 NN1^[S]:=A.S;
 NN2^[S]:=B.S;
 NN1^[A.E]:=E;
 NN1^[B.E]:=E;
 A.S:=S;
 A.E:=E;
End;

Procedure MkStar(Var A:TFrag;Plus,Quest:Boolean);
Var
 S,E:Integer;
Begin
 S:=NewNfa(0);
 E:=NewNfa(0);
 If Plus Then Begin
  NN1^[A.E]:=A.S;
  NN2^[A.E]:=E;
  A.E:=E;
 End
  Else
 Begin
  NN1^[S]:=A.S;
  NN2^[S]:=E;
  If Quest Then NN1^[A.E]:=E
   Else Begin
    NN1^[A.E]:=A.S;
    NN2^[A.E]:=E;
   End;
  A.S:=S;
  A.E:=E;
 End;
End;

{ ------------------------- Expressions regulieres ------------------------- }

Var
 ParenDepth:Integer;

Procedure ParseAlt(Var F:TFrag);Forward;

Function ReadEscape:Char;
Var
 C:Char;
 V,N:Integer;
Begin
 { PP pointe sur le caractere qui suit le \ }
 If PP>Length(PS)Then Begin
  ReadEscape:='\';
  Exit;
 End;
 C:=PS[PP];
 Inc(PP);
 Case C of
  'n':ReadEscape:=#10;
  't':ReadEscape:=#9;
  'r':ReadEscape:=#13;
  'b':ReadEscape:=#8;
  'f':ReadEscape:=#12;
  'v':ReadEscape:=#11;
  'a':ReadEscape:=#7;
  '0'..'7':Begin
   V:=Ord(C)-48;
   N:=1;
   While(N<3)And(PP<=Length(PS))And(PS[PP]In['0'..'7'])Do Begin
    V:=V*8+Ord(PS[PP])-48;
    Inc(PP);
    Inc(N);
   End;
   ReadEscape:=Chr(V And 255);
  End;
  'x':Begin
   V:=0;
   N:=0;
   While(N<2)And(PP<=Length(PS))And(PS[PP]In['0'..'9','a'..'f','A'..'F'])Do Begin
    If PS[PP]In['0'..'9']Then V:=V*16+Ord(PS[PP])-48
    Else If PS[PP]In['a'..'f']Then V:=V*16+Ord(PS[PP])-87
    Else V:=V*16+Ord(PS[PP])-55;
    Inc(PP);
    Inc(N);
   End;
   ReadEscape:=Chr(V And 255);
  End;
  Else ReadEscape:=C;
 End;
End;

Procedure ParseClass(Var F:TFrag);
Var
 S:TCSet;
 Neg,First:Boolean;
 C,D,X:Char;
Begin
 S:=[];
 Neg:=False;
 Inc(PP);
 If(PP<=Length(PS))And(PS[PP]='^')Then Begin
  Neg:=True;
  Inc(PP);
 End;
 First:=True;
 While(PP<=Length(PS))And((PS[PP]<>']')Or First)Do Begin
  First:=False;
  C:=PS[PP];
  Inc(PP);
  If C='\'Then C:=ReadEscape;
  If(PP+1<=Length(PS))And(PS[PP]='-')And(PS[PP+1]<>']')Then Begin
   Inc(PP);
   D:=PS[PP];
   Inc(PP);
   If D='\'Then D:=ReadEscape;
   If D<C Then Err('intervalle de classe invalide')
    Else
   For X:=C to D Do S:=S+[X];
  End
   Else
  S:=S+[C];
 End;
 If PP>Length(PS)Then Err('"]" attendu')
                 Else Inc(PP);
 If Neg Then S:=[#0..#255]-S;
 MkSet(S,F);
End;

Procedure ParseAtom(Var F:TFrag);
Var
 C,D:Char;
 T:TFrag;
 Nm:String;
 I,K:Integer;
 SavePS:String;
 SavePP:Integer;
 S:TCSet;
 First:Boolean;
Begin
 C:=PS[PP];
 If C='('Then Begin
  Inc(PP);
  Inc(ParenDepth);
  ParseAlt(F);
  Dec(ParenDepth);
  If(PP<=Length(PS))And(PS[PP]=')')Then Inc(PP)
                                  Else Err('")" attendu');
 End
 Else If C='['Then ParseClass(F)
 Else If C='"'Then Begin
  Inc(PP);
  First:=True;
  While(PP<=Length(PS))And(PS[PP]<>'"')Do Begin
   D:=PS[PP];
   Inc(PP);
   If D='\'Then D:=ReadEscape;
   MkSet([D],T);
   If First Then F:=T
            Else Cat(F,T);
   First:=False;
  End;
  If PP>Length(PS)Then Err('guillemet fermant manquant')
                  Else Inc(PP);
  If First Then MkEmpty(F);
 End
 Else If C='.'Then Begin
  Inc(PP);
  MkSet([#0..#255]-[#10],F);
 End
 Else If C='\'Then Begin
  Inc(PP);
  D:=ReadEscape;
  MkSet([D],F);
 End
 Else If(C='{')And(PP<Length(PS))And IsAlpha(PS[PP+1])Then Begin
  Inc(PP);
  Nm:='';
  While(PP<=Length(PS))And(PS[PP]<>'}')Do Begin
   Nm:=Nm+PS[PP];
   Inc(PP);
  End;
  Inc(PP);
  K:=0;
  For I:=1 to DefCnt Do If DefName[I]=Nm Then K:=I;
  If K=0Then Begin
   Err('definition inconnue: {'+Nm+'}');
   MkEmpty(F);
  End
  Else If Depth>=MaxDepth Then Begin
   Err('definitions trop imbriquees');
   MkEmpty(F);
  End
   Else
  Begin
   SavePS:=PS;
   SavePP:=PP;
   PS:=DefText[K];
   PP:=1;
   Inc(Depth);
   Inc(ParenDepth);
   ParseAlt(F);
   Dec(ParenDepth);
   Dec(Depth);
   PS:=SavePS;
   PP:=SavePP;
  End;
 End
 Else Begin
  Inc(PP);
  MkSet([C],F);
 End;
End;

Procedure ParseItem(Var F:TFrag);
Var
 AtomStart,AtomEnd,N,M,I,Code:Integer;
 Unbounded:Boolean;
 T,R:TFrag;
 Num:String;
 C:Char;
Begin
 AtomStart:=PP;
 ParseAtom(F);
 AtomEnd:=PP;
 While(PP<=Length(PS))And((PS[PP]In['*','+','?'])Or
       ((PS[PP]='{')And(PP<Length(PS))And(PS[PP+1]In['0'..'9'])))Do Begin
  If TrailMode Then TrailVar:=True;
  C:=PS[PP];
  If C='*'Then Begin
   Inc(PP);
   MkStar(F,False,False);
  End
  Else If C='+'Then Begin
   Inc(PP);
   MkStar(F,True,False);
  End
  Else If C='?'Then Begin
   Inc(PP);
   MkStar(F,False,True);
  End
  Else Begin
   Inc(PP);
   Num:='';
   While(PP<=Length(PS))And(PS[PP]In['0'..'9'])Do Begin
    Num:=Num+PS[PP];
    Inc(PP);
   End;
   Val(Num,N,Code);
   M:=N;
   Unbounded:=False;
   If(PP<=Length(PS))And(PS[PP]=',')Then Begin
    Inc(PP);
    Num:='';
    While(PP<=Length(PS))And(PS[PP]In['0'..'9'])Do Begin
     Num:=Num+PS[PP];
     Inc(PP);
    End;
    If Num=''Then Unbounded:=True
    Else Val(Num,M,Code);
   End;
   If(PP<=Length(PS))And(PS[PP]='}')Then Inc(PP)
                                     Else Err('"}" attendu');
   AtomEnd:=PP;
   If(N>40)Or(M>40)Or((Not Unbounded)And(M<N))Then Err('repetition invalide')
    Else
   Begin
    MkEmpty(R);
    For I:=1 to N Do Begin
     If I=1Then T:=F
      Else Begin
       PP:=AtomStart;
       ParseAtom(T);
       PP:=AtomEnd;
      End;
     Cat(R,T);
    End;
    If Unbounded Then Begin
     PP:=AtomStart;
     ParseAtom(T);
     PP:=AtomEnd;
     MkStar(T,False,False);
     Cat(R,T);
    End
     Else
    For I:=N+1 to M Do Begin
     PP:=AtomStart;
     ParseAtom(T);
     PP:=AtomEnd;
     MkStar(T,False,True);
     Cat(R,T);
    End;
    F:=R;
   End;
  End;
 End;
End;

Procedure ParseSeq(Var F:TFrag);
Var
 T:TFrag;
 First:Boolean;
Begin
 First:=True;
 While(PP<=Length(PS))And(PS[PP]<>')')And(PS[PP]<>'|')And
      Not((PS[PP]='/')And(ParenDepth=0)And(Depth=0))Do Begin
  ParseItem(T);
  If First Then F:=T
           Else Cat(F,T);
  First:=False;
  If Failed Then Break;
 End;
 If First Then MkEmpty(F);
End;

Procedure ParseAlt(Var F:TFrag);
Var
 B:TFrag;
Begin
 ParseSeq(F);
 While(PP<=Length(PS))And(PS[PP]='|')Do Begin
  Inc(PP);
  If TrailMode Then TrailVar:=True;
  ParseSeq(B);
  MkAlt(F,B);
 End;
End;

{ Compile la regle R en un fragment d'automate }
Procedure CompileRule(R:Integer);
Var
 F,T:TFrag;
 Eol:Boolean;
 L,Q,I:Integer;
 A:Integer;
Begin
 LineNo:=Rules[R].Line;
 PS:=Rules[R].Pat^;
 Rules[R].Bol:=False;
 Rules[R].Trail:=0;
 Eol:=False;
 If(Length(PS)>0)And(PS[1]='^')Then Begin
  Rules[R].Bol:=True;
  PS:=Copy(PS,2,255);
 End;
 L:=Length(PS);
 If(L>0)And(PS[L]='$')And((L=1)Or(PS[L-1]<>'\'))Then Begin
  Q:=0;
  For I:=1 to L Do If PS[I]='"'Then Inc(Q);
  If Not Odd(Q)Then Begin
   Eol:=True;
   PS:=Copy(PS,1,L-1);
  End;
 End;
 PP:=1;
 Depth:=0;
 ParenDepth:=0;
 TrailMode:=False;
 TrailLen:=0;
 TrailVar:=False;
 ParseAlt(F);
 If(PP<=Length(PS))And(PS[PP]='/')Then Begin
  Inc(PP);
  TrailMode:=True;
  ParseAlt(T);
  TrailMode:=False;
  Cat(F,T);
  If TrailVar Then Err('contexte de queue de longueur variable non supporte');
  Rules[R].Trail:=TrailLen;
 End;
 If PP<=Length(PS)Then Err('caractere inattendu dans l''expression: '+Copy(PS,PP,1));
 If Eol Then Begin
  MkSet([#10],T);
  Cat(F,T);
  Inc(Rules[R].Trail);
 End;
 A:=NewNfa(2);
 NRule^[A]:=R;
 NN1^[F.E]:=A;
 Rules[R].Start:=F.S;
End;

Const
 Drv1:Array[1..94]Of String[90]=(
  'int yywrap(void);',
  '',
  'FILE *yyin = NULL, *yyout = NULL;',
  'char yytext[YYLMAX];',
  'int yyleng = 0;',
  'static int yy_cond = 0;',
  'static int yy_bol = 1;',
  'static int yy_more = 0;',
  'static int yy_buf[YYLMAX];',
  'static int yy_nbuf = 0;',
  '',
  'static int yy_get(void)',
  '{',
  '    if (yy_nbuf > 0) return yy_buf[--yy_nbuf];',
  '    return getc(yyin);',
  '}',
  '',
  'static void yy_unget(int c)',
  '{',
  '    if (c != EOF && yy_nbuf < YYLMAX) yy_buf[yy_nbuf++] = c;',
  '}',
  '',
  'static void yy_less(int n)',
  '{',
  '    while (yyleng > n) yy_unget((unsigned char)yytext[--yyleng]);',
  '    yytext[yyleng] = 0;',
  '}',
  '',
  'static int input(void)',
  '{',
  '    int c = yy_get();',
  '    return c == EOF ? 0 : c;',
  '}',
  '',
  'static void unput(int c)',
  '{',
  '    yy_unget(c);',
  '}',
  '',
  '#define ECHO fwrite(yytext, yyleng, 1, yyout)',
  '#define BEGIN yy_cond =',
  '#define yymore() (yy_more = 1)',
  '#define yyless(n) yy_less(n)',
  '#define yyterminate() return 0',
  '#define REJECT { fprintf(stderr, "lex: REJECT is not supported\n"); exit(1); }',
  '',
  'int yylex(void)',
  '{',
  '    int s, s2, c, len, base, last_rule, last_len, tl;',
  '',
  '    if (!yyin) yyin = stdin;',
  '    if (!yyout) yyout = stdout;',
  '    for (;;) {',
  '        c = yy_get();',
  '        if (c == EOF) {',
  '            if (yywrap()) return 0;',
  '            continue;',
  '        }',
  '        yy_unget(c);',
  '        base = yy_more ? yyleng : 0;',
  '        yy_more = 0;',
  '        len = base;',
  '        s = yy_start[yy_cond * 2 + yy_bol];',
  '        last_rule = 0;',
  '        last_len = base;',
  '        for (;;) {',
  '            c = yy_get();',
  '            if (c == EOF) break;',
  '            s2 = yy_nxt[s * YY_NC + yy_ec[c]];',
  '            if (!s2) {',
  '                yy_unget(c);',
  '                break;',
  '            }',
  '            if (len < YYLMAX - 1) yytext[len++] = (char)c;',
  '            s = s2;',
  '            if (yy_accept[s]) {',
  '                last_rule = yy_accept[s];',
  '                last_len = len;',
  '            }',
  '        }',
  '        while (len > last_len) yy_unget((unsigned char)yytext[--len]);',
  '        if (last_rule == 0) {',
  '            c = yy_get();',
  '            putc(c, yyout);',
  '            yy_bol = (c == ''\n'');',
  '            yyleng = 0;',
  '            continue;',
  '        }',
  '        tl = yy_trail[last_rule];',
  '        while (tl-- > 0 && len > 0) yy_unget((unsigned char)yytext[--len]);',
  '        yytext[len] = 0;',
  '        yyleng = len;',
  '        if (len > 0) yy_bol = (yytext[len - 1] == ''\n'');',
  '        switch (last_rule) {');

Const
 Drv2:Array[1..3]Of String[90]=(
  '        }',
  '    }',
  '}');


{ ------------------------- Lecture de la specification ------------------------- }

Procedure AddVerb(Const L:String);Begin
 If VerbCnt<MaxVerb Then Begin
  Inc(VerbCnt);
  Verb[VerbCnt]:=NewPStr(L);
 End;
End;

Procedure AddCond(Const N:String;Inc_:Boolean);
Var
 I:Integer;
Begin
 For I:=0 to CondCnt-1 Do If CondName[I]=N Then Exit;
 If CondCnt>=MaxConds Then Begin
  Err('trop de conditions de depart');
  Exit;
 End;
 CondName[CondCnt]:=Copy(N,1,31);
 CondInc[CondCnt]:=Inc_;
 Inc(CondCnt);
End;

Function FindCond(Const N:String):Integer;
Var
 I:Integer;
Begin
 FindCond:=-1;
 For I:=0 to CondCnt-1 Do If CondName[I]=N Then FindCond:=I;
End;

Procedure ParseCondDecl(Const L:String;Inc_:Boolean);
Var
 I,J:Integer;
 W:String;
Begin
 I:=1;
 While(I<=Length(L))And Not IsBlank(L[I])Do Inc(I);
 While I<=Length(L)Do Begin
  While(I<=Length(L))And(IsBlank(L[I])Or(L[I]=','))Do Inc(I);
  J:=I;
  While(J<=Length(L))And Not IsBlank(L[J])And(L[J]<>',')Do Inc(J);
  W:=Copy(L,I,J-I);
  If W<>''Then AddCond(W,Inc_);
  I:=J;
 End;
End;

{ Difference d'accolades dans une ligne de code C (ignore chaines et commentaires) }
Function BraceDelta(Const L:String;Var InCom:Boolean):Integer;
Var
 I,D:Integer;
 Q:Char;
Begin
 D:=0;
 I:=1;
 Q:=#0;
 While I<=Length(L)Do Begin
  If InCom Then Begin
   If(L[I]='*')And(I<Length(L))And(L[I+1]='/')Then Begin
    InCom:=False;
    Inc(I);
   End;
  End
  Else If Q<>#0Then Begin
   If L[I]='\'Then Inc(I)
   Else If L[I]=Q Then Q:=#0;
  End
  Else If(L[I]='/')And(I<Length(L))And(L[I+1]='*')Then Begin
   InCom:=True;
   Inc(I);
  End
  Else If(L[I]='"')Or(L[I]='''')Then Q:=L[I]
  Else If L[I]='{'Then Inc(D)
  Else If L[I]='}'Then Dec(D);
  Inc(I);
 End;
 BraceDelta:=D;
End;

Procedure AddAct(Const L:String);Begin
 If ActCnt<MaxAct Then Begin
  Inc(ActCnt);
  Acts[ActCnt]:=NewPStr(L);
 End;
End;

Procedure ReadRule(Const L:String;Var F:Text);
Var
 I,J,K:Integer;
 Pat,CondS,Act,Nm,Line2:String;
 Q,Br:Boolean;
 Mask:Word;
 Expl:Boolean;
 Dp,C:Integer;
 InCom:Boolean;
Begin
 I:=1;
 Expl:=False;
 Mask:=0;
 If L[1]='<'Then Begin
  J:=Pos('>',L);
  If J>0Then Begin
   CondS:=Copy(L,2,J-2);
   I:=J+1;
   Expl:=True;
   K:=1;
   While K<=Length(CondS)Do Begin
    J:=K;
    While(J<=Length(CondS))And(CondS[J]<>',')Do Inc(J);
    Nm:=Copy(CondS,K,J-K);
    K:=J+1;
    If Nm='*'Then Mask:=$FFFF
    Else Begin
     C:=FindCond(Nm);
     If C<0Then Err('condition de depart inconnue: '+Nm)
           Else Mask:=Mask Or(Word(1)Shl C);
    End;
   End;
  End;
 End;
 J:=I;
 Q:=False;
 Br:=False;
 While J<=Length(L)Do Begin
  If L[J]='\'Then Inc(J)
  Else If Q Then Begin
   If L[J]='"'Then Q:=False;
  End
  Else If Br Then Begin
   If L[J]=']'Then Br:=False;
  End
  Else If L[J]='"'Then Q:=True
  Else If L[J]='['Then Begin
   Br:=True;
   If(J<Length(L))And(L[J+1]='^')Then Inc(J);
   If(J<Length(L))And(L[J+1]=']')Then Inc(J);
  End
  Else If IsBlank(L[J])Then Break;
  Inc(J);
 End;
 Pat:=Copy(L,I,J-I);
 While(J<=Length(L))And IsBlank(L[J])Do Inc(J);
 Act:=Copy(L,J,255);
 If RuleCnt>=MaxRules Then Begin
  Err('trop de regles');
  Exit;
 End;
 Inc(RuleCnt);
 Rules[RuleCnt].Pat:=NewPStr(Pat);
 Rules[RuleCnt].Explicit:=Expl;
 Rules[RuleCnt].Mask:=Mask;
 Rules[RuleCnt].Line:=LineNo;
 Rules[RuleCnt].ActFirst:=ActCnt+1;
 Rules[RuleCnt].ActBar:=(Trim(Act)='|');
 If Not Rules[RuleCnt].ActBar Then Begin
  If Trim(Act)=''Then Act:=';';
  AddAct(Act);
  InCom:=False;
  Dp:=BraceDelta(Act,InCom);
  While(Dp>0)And Not EOF(F)Do Begin
   ReadLn(F,Line2);
   Inc(LineNo);
   AddAct(Line2);
   Dp:=Dp+BraceDelta(Line2,InCom);
  End;
 End;
 Rules[RuleCnt].ActCnt:=ActCnt-Rules[RuleCnt].ActFirst+1;
End;

Procedure ReadSpec(Var F:Text);
Var
 L,T,Nm:String;
 Section:Integer;
 InVerb,InCom:Boolean;
 I:Integer;
Begin
 Section:=1;
 InVerb:=False;
 InCom:=False;
 LineNo:=0;
 While Not EOF(F)Do Begin
  ReadLn(F,L);
  Inc(LineNo);
  T:=Trim(L);
  If Section=3Then Begin
   If UserCnt<MaxUser Then Begin
    Inc(UserCnt);
    UserCode[UserCnt]:=NewPStr(L);
   End;
  End
  Else If(Copy(L,1,2)='%%')Then Inc(Section)
  Else If Section=1Then Begin
   If InVerb Then Begin
    If T='%}'Then InVerb:=False
             Else AddVerb(L);
   End
   Else If InCom Then Begin
    AddVerb(L);
    If Pos('*/',L)>0Then InCom:=False;
   End
   Else If T=''Then
   Else If T='%{'Then InVerb:=True
   Else If(Copy(L,1,2)='%s')Or(Copy(L,1,6)='%start')Then ParseCondDecl(L,True)
   Else If Copy(L,1,2)='%x'Then ParseCondDecl(L,False)
   Else If L[1]='%'Then
   Else If IsBlank(L[1])Then AddVerb(L)
   Else If Copy(L,1,2)='/*'Then Begin
    AddVerb(L);
    If Pos('*/',L)=0Then InCom:=True;
   End
   Else Begin
    I:=1;
    Nm:='';
    While(I<=Length(L))And IsAlnum(L[I])Do Begin
     Nm:=Nm+L[I];
     Inc(I);
    End;
    If(Nm='')Or Not IsAlpha(Nm[1])Then Err('definition invalide')
    Else If DefCnt>=MaxNames Then Err('trop de definitions')
    Else Begin
     Inc(DefCnt);
     DefName[DefCnt]:=Copy(Nm,1,31);
     DefText[DefCnt]:=Copy(Trim(Copy(L,I,255)),1,200);
    End;
   End;
  End
  Else Begin
   If InCom Then Begin
    If Pos('*/',L)>0Then InCom:=False;
   End
   Else If T=''Then
   Else If T='%{'Then Begin
    While Not EOF(F)Do Begin
     ReadLn(F,L);
     Inc(LineNo);
     If Trim(L)='%}'Then Break;
     AddVerb(L);
    End;
   End
   Else If(Copy(T,1,2)='/*')Then Begin
    If Pos('*/',T)=0Then InCom:=True;
   End
   Else If IsBlank(L[1])Then
   Else ReadRule(L,F);
  End;
 End;
End;

{ ------------------------- Construction du DFA ------------------------- }

Var
 Mark:PWordArr;
 Stamp:Word;
 Tmp:PWordArr;
 TmpN:Integer;
 Stk:PWordArr;

Procedure NewStamp;
Var
 I:Integer;
Begin
 If Stamp=65535Then Begin
  For I:=1 to MaxNfa Do Mark^[I]:=0;
  Stamp:=0;
 End;
 Inc(Stamp);
 TmpN:=0;
End;

Procedure AddClosure(S:Integer);
Var
 Sp,X:Integer;
Begin
 Sp:=1;
 Stk^[1]:=S;
 While Sp>0Do Begin
  X:=Stk^[Sp];
  Dec(Sp);
  If(X>0)And(Mark^[X]<>Stamp)Then Begin
   Mark^[X]:=Stamp;
   If NKind^[X]=0Then Begin
    If NN1^[X]<>0Then Begin
     Inc(Sp);
     Stk^[Sp]:=NN1^[X];
    End;
    If NN2^[X]<>0Then Begin
     Inc(Sp);
     Stk^[Sp]:=NN2^[X];
    End;
   End
    Else
   Begin
    Inc(TmpN);
    Tmp^[TmpN]:=X;
   End;
  End;
 End;
End;

Procedure SortTmp;
Var
 I,J:Integer;
 V:Word;
Begin
 For I:=2 to TmpN Do Begin
  V:=Tmp^[I];
  J:=I-1;
  While(J>=1)And(Tmp^[J]>V)Do Begin
   Tmp^[J+1]:=Tmp^[J];
   Dec(J);
  End;
  Tmp^[J+1]:=V;
 End;
End;

Function FindOrAddDfa:Integer;
Var
 I,J:Integer;
 Same:Boolean;
 Acc,R:Integer;
Begin
 SortTmp;
 For I:=1 to DfaCnt Do
  If DLen[I]=TmpN Then Begin
   Same:=True;
   For J:=1 to TmpN Do
    If Pool^[DOff[I]+J-1]<>Tmp^[J]Then Begin
     Same:=False;
     Break;
    End;
   If Same Then Begin
    FindOrAddDfa:=I;
    Exit;
   End;
  End;
 If(DfaCnt>=MaxDfa)Or(PoolPos+TmpN>=PoolSz)Then Begin
  If Not Failed Then Err('trop d''etats DFA');
  Failed:=True;
  FindOrAddDfa:=1;
  Exit;
 End;
 Inc(DfaCnt);
 DOff[DfaCnt]:=PoolPos;
 DLen[DfaCnt]:=TmpN;
 Acc:=0;
 For J:=1 to TmpN Do Begin
  Pool^[PoolPos]:=Tmp^[J];
  Inc(PoolPos);
  If NKind^[Tmp^[J]]=2Then Begin
   R:=NRule^[Tmp^[J]];
   If(Acc=0)Or(R<Acc)Then Acc:=R;
  End;
 End;
 DAcc[DfaCnt]:=Acc;
 FindOrAddDfa:=DfaCnt;
End;

Procedure ComputeClasses;
Var
 NewId:Array[0..255,0..1]Of Integer;
 I,C,B,Old,Nx:Integer;
Begin
 For C:=0 to 255 Do Cls[C]:=0;
 NC:=1;
 For I:=1 to SetCnt Do Begin
  For C:=0 to 255 Do Begin
   NewId[C,0]:=-1;
   NewId[C,1]:=-1;
  End;
  Nx:=0;
  For C:=0 to 255 Do Begin
   Old:=Cls[C];
   B:=Ord(Chr(C)In Sets^[I]);
   If NewId[Old,B]<0Then Begin
    NewId[Old,B]:=Nx;
    Inc(Nx);
   End;
   Cls[C]:=NewId[Old,B];
  End;
  NC:=Nx;
 End;
 For C:=0 to 255 Do Rep[C]:=-1;
 For C:=255 downto 0 Do Rep[Cls[C]]:=C;
End;

Procedure BuildDfa;
Var
 C,B,I,S,X,K,Dst:Integer;
 Active:Boolean;
Begin
 ComputeClasses;
 DfaCnt:=0;
 PoolPos:=0;
 { etats de depart par condition et ancrage de debut de ligne }
 For C:=0 to CondCnt-1 Do
  For B:=0 to 1 Do Begin
   NewStamp;
   For I:=1 to RuleCnt Do Begin
    If Rules[I].Explicit Then Active:=(Rules[I].Mask And(Word(1)Shl C))<>0
                         Else Active:=CondInc[C];
    If Rules[I].Bol And(B=0)Then Active:=False;
    If Active Then AddClosure(Rules[I].Start);
   End;
   StartDfa[C*2+B]:=FindOrAddDfa;
  End;
 S:=1;
 While(S<=DfaCnt)And Not Failed Do Begin
  GetMem(Rows[S],NC*2);
  For K:=0 to NC-1 Do Begin
   NewStamp;
   For I:=1 to DLen[S]Do Begin
    X:=Pool^[DOff[S]+I-1];
    If NKind^[X]=1Then
     If Chr(Rep[K])In Sets^[NSet^[X]]Then AddClosure(NN1^[X]);
   End;
   If TmpN=0Then Rows[S]^[K]:=0
            Else Rows[S]^[K]:=FindOrAddDfa;
  End;
  Inc(S);
 End;
End;

{ ------------------------- Generation du code C ------------------------- }

Var
 TabLine:String;

Procedure W(Const S:String);Begin
 WriteLn(OutF,S);
End;

Procedure TabStart(Const Decl:String);Begin
 W(Decl+' = {');
 TabLine:='  ';
End;

Procedure TabNum(V:Integer;Last:Boolean);Begin
 TabLine:=TabLine+IntStr(V);
 If Not Last Then TabLine:=TabLine+',';
 If Length(TabLine)>70Then Begin
  W(TabLine);
  TabLine:='  ';
 End;
End;

Procedure TabEnd;Begin
 If Trim(TabLine)<>''Then W(TabLine);
 W('};');
End;

Procedure FindUser(Const Key:String;Var Found:Boolean);
Var
 I:Integer;
Begin
 For I:=1 to VerbCnt Do If Pos(Key,Verb[I]^)>0Then Found:=True;
 For I:=1 to UserCnt Do If Pos(Key,UserCode[I]^)>0Then Found:=True;
End;

Procedure WriteOutput;
Var
 I,J,S,C:Integer;
 StartRule:Integer;
Begin
 W('/* lex.yy.c : genere par lex (clone) */');
 If OptQ Then W('/* lex (clone) version 1.0 */');
 W('#include <stdio.h>');
 W('#include <stdlib.h>');
 W('#include <string.h>');
 W('#define YYLMAX 8192');
 W('#define YY_NC '+IntStr(NC));
 W('#define INITIAL 0');
 For I:=1 to CondCnt-1 Do W('#define '+CondName[I]+' '+IntStr(I));
 W('');
 For I:=1 to VerbCnt Do W(Verb[I]^);
 W('');
 TabStart('static const unsigned char yy_ec[256]');
 For C:=0 to 255 Do TabNum(Cls[C],C=255);
 TabEnd;
 TabStart('static const short yy_nxt['+IntStr((DfaCnt+1)*NC)+']');
 For C:=0 to NC-1 Do TabNum(0,False);
 For S:=1 to DfaCnt Do
  For C:=0 to NC-1 Do TabNum(Rows[S]^[C],(S=DfaCnt)And(C=NC-1));
 TabEnd;
 TabStart('static const short yy_accept['+IntStr(DfaCnt+1)+']');
 TabNum(0,False);
 For S:=1 to DfaCnt Do TabNum(DAcc[S],S=DfaCnt);
 TabEnd;
 TabStart('static const short yy_trail['+IntStr(RuleCnt+1)+']');
 TabNum(0,RuleCnt=0);
 For I:=1 to RuleCnt Do TabNum(Rules[I].Trail,I=RuleCnt);
 TabEnd;
 TabStart('static const short yy_start['+IntStr(CondCnt*2)+']');
 For I:=0 to CondCnt*2-1 Do TabNum(StartDfa[I],I=CondCnt*2-1);
 TabEnd;
 W('');
 For I:=1 to 94 Do W(Drv1[I]);
 For I:=1 to RuleCnt Do Begin
  W('        case '+IntStr(I)+':');
  If Not Rules[I].ActBar Then Begin
   For J:=Rules[I].ActFirst to Rules[I].ActFirst+Rules[I].ActCnt-1 Do W('            '+Acts[J]^);
   W('            break;');
  End;
 End;
 For I:=1 to 3 Do W(Drv2[I]);
 W('');
 If Not HasYywrap Then Begin
  W('int yywrap(void)');
  W('{');
  W('    return 1;');
  W('}');
  W('');
 End;
 For I:=1 to UserCnt Do W(UserCode[I]^);
 If Not HasMain Then Begin
  W('');
  W('int main(void)');
  W('{');
  W('    yylex();');
  W('    return 0;');
  W('}');
 End;
End;

Var
 I,J:Integer;
 A,V:String;
 InF:Text;
 Found:Boolean;
 TotalAct:Integer;

BEGIN
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
 End;
 InName:='';
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(Length(A)>1)And(A[1]='-')Then Begin
   J:=2;
   While J<=Length(A)Do Begin
    Case A[J]of
     'c','e','w':Inc(J);
     'n':Begin
      OptN:=True;
      Inc(J);
     End;
     't':Begin
      OptT:=True;
      Inc(J);
     End;
     'v':Begin
      OptV:=True;
      Inc(J);
     End;
     'V':Begin
      {$IFDEF FPC}
      WriteLn(StdErr,'lex (clone) version 1.0');
      {$ELSE}
      WriteLn('lex (clone) version 1.0');
      {$ENDIF}
      Inc(J);
     End;
     'Q':Begin
      V:=Copy(A,J+1,1);
      If V=''Then Begin
       Inc(I);
       If I<=ParamCount Then V:=ParamStr(I);
      End;
      OptQ:=(V='y')Or(V='Y');
      J:=Length(A)+1;
     End;
     Else Begin
      WriteLn('lex: option inconnue: -',A[J]);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
  End
   Else
  Begin
   If InName<>''Then Begin
    ShowUsage;
    Halt(1);
   End;
   InName:=A;
  End;
  Inc(I);
 End;
 New(NKind);
 New(NN1);
 New(NN2);
 New(NSet);
 New(NRule);
 New(Sets);
 New(Pool);
 New(Mark);
 New(Tmp);
 New(Stk);
 For I:=1 to MaxNfa Do Mark^[I]:=0;
 NfaCnt:=0;
 SetCnt:=0;
 CondName[0]:='INITIAL';
 CondInc[0]:=True;
 CondCnt:=1;
 Assign(InF,InName);
 {$I-}Reset(InF);{$I+}
 If IOResult<>0Then Begin
  WriteLn('lex: impossible d''ouvrir ',InName);
  Halt(1);
 End;
 ReadSpec(InF);
 Close(InF);
 If RuleCnt=0Then Err('aucune regle dans la specification');
 For I:=1 to RuleCnt Do If Not Failed Then CompileRule(I);
 If Failed Then Halt(1);
 BuildDfa;
 If Failed Then Halt(1);
 HasYywrap:=False;
 HasMain:=False;
 FindUser('yywrap',HasYywrap);
 FindUser('main',HasMain);
 If OptT Then Begin
  Assign(OutF,'');
  Rewrite(OutF);
 End
  Else
 Begin
  Assign(OutF,'lex.yy.c');
  {$I-}Rewrite(OutF);{$I+}
  If IOResult<>0Then Begin
   WriteLn('lex: impossible de creer lex.yy.c');
   Halt(1);
  End;
 End;
 WriteOutput;
 Close(OutF);
 If OptV And Not OptN Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,RuleCnt,' regles, ',NfaCnt,' etats NFA, ',DfaCnt,' etats DFA, ',NC,' classes d''equivalence');
  {$ELSE}
  WriteLn(RuleCnt,' regles, ',NfaCnt,' etats NFA, ',DfaCnt,' etats DFA, ',NC,' classes d''equivalence');
  {$ENDIF}
 End;
END.
