{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande make - Moteur de production de fichiers
}

Program MAKE;

{$X+}
{$R-}
{$M 60000,0,200000}

Uses DOS;

Const
 MaxVars=500;
 MaxRules=300;
 MaxCmds=2000;
 MaxBuilt=300;
 MaxPhony=120;
 MaxSuffix=30;
 MaxIf=24;
 MaxFiles=16;
 MaxDirs=16;
 MaxGoals=32;
 MaxAssume=40;
 OrgDefault=1;
 OrgEnv=2;
 OrgFile=3;
 OrgEnvOver=4;
 OrgOverride=5;
 OrgCmd=7;
 Tab=#9;

Type
 PStr=^String;
 TVar=Record
  Name:String[63];
  Val:PStr;
  Simple:Boolean;
  Org:Integer;
 End;
 TVarArr=Array[1..MaxVars]Of TVar;
 PVarArr=^TVarArr;
 TRule=Record
  Targ:String[127];
  Pre:PStr;
  OrdPre:PStr;
  CFirst,CCnt:Integer;
  IsPat:Boolean;
  Builtin:Boolean;
  Line:Longint;
 End;
 TRuleArr=Array[1..MaxRules]Of TRule;
 PRuleArr=^TRuleArr;
 TBuilt=Record
  Name:String[127];
  State:Integer;      { 1 en cours, 2 termine }
  Time:Longint;
  Updated:Boolean;
  Failed:Boolean;
 End;
 TBuiltArr=Array[1..MaxBuilt]Of TBuilt;
 PBuiltArr=^TBuiltArr;
 TArgs=Array[1..6]Of String;

Var
 Vars:PVarArr;
 VarCnt:Integer;
 Rules:PRuleArr;
 RuleCnt:Integer;
 Cmds:Array[1..MaxCmds]Of PStr;
 CmdCnt:Integer;
 Built:PBuiltArr;
 BuiltCnt:Integer;
 Phony:Array[1..MaxPhony]Of String[63];
 PhonyCnt:Integer;
 Suffixes:Array[1..MaxSuffix]Of String[15];
 SuffixCnt:Integer;
 IfActive:Array[0..MaxIf]Of Boolean;
 IfDone:Array[0..MaxIf]Of Boolean;
 IfTop:Integer;
 MakeFiles:Array[1..MaxFiles]Of String[127];
 MakeFileCnt:Integer;
 IncDirs:Array[1..MaxDirs]Of String[127];
 IncDirCnt:Integer;
 Goals:Array[1..MaxGoals]Of String[127];
 GoalCnt:Integer;
 AssumeOld:Array[1..MaxAssume]Of String[127];
 AssumeOldCnt:Integer;
 AssumeNew:Array[1..MaxAssume]Of String[127];
 AssumeNewCnt:Integer;
 DefaultGoal:String[127];
 { Etat de l'expansion }
 AutoTarget,AutoFirst,AutoAll,AutoPlus,AutoNewer,AutoStem:String;
 Dummy:Integer;
 FuncDepth:Integer;
 { Options }
 OptAlways,OptDry,OptSilent,OptKeep,OptIgnore,OptTouch,OptQuestion,OptEnvOver,
 OptNoRules,OptNoVars,OptPrintDb,OptPrintDir,OptDebug,OptWarnUndef,OptNoPrintDir:Boolean;
 SilentAll,IgnoreAll:Boolean;
 ExitCode:Integer;
 ErrorsSeen:Boolean;
 LineNo:Longint;
 CurFile:String;
 ProgName:String;
 TmpCounter:Integer;
 DidRun:Boolean;
 AnyRebuild:Boolean;

Procedure ShowUsage;Begin
 WriteLn('Usage: make [ -f makefile ] [ option ] ... target ...');
End;

Procedure ShowHelp;Begin
 WriteLn('MAKE : Cette commande permet de lancer le moteur de production, lequel effectue des');
 WriteLn('commandes permettant la creation des fichiers.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -b, -m                       Ignorees (compatibilite)');
 WriteLn('  -B, --always-make            Reconstruit toutes les cibles');
 WriteLn('  -C dir, --directory=dir      Change de repertoire avant de lire les makefiles');
 WriteLn('  -d, --debug[=FLAGS]          Informations de debogage');
 WriteLn('  -e, --environment-overrides  Les variables d''environnement ont priorite');
 WriteLn('  -f file, --file=file         Makefile a utiliser (repetable)');
 WriteLn('  -i, --ignore-errors          Ignore les erreurs des commandes');
 WriteLn('  -I dir, --include-dir=dir    Repertoire de recherche pour include');
 WriteLn('  -j [n], -l [n]               Acceptes (execution toujours sequentielle)');
 WriteLn('  -k, --keep-going             Continue malgre les erreurs');
 WriteLn('  -L, --check-symlink-times    Accepte, sans effet');
 WriteLn('  -n, --dry-run, --just-print, --recon  Affiche les commandes sans les executer');
 WriteLn('  --no-builtin-rules, -r       Retire les regles implicites predefinies');
 WriteLn('  --no-builtin-variables, -R   Retire les variables predefinies');
 WriteLn('  -o file, --old-file=file, --assume-old=file  Considere le fichier comme ancien');
 WriteLn('  -p, --print-data-base        Affiche la base de donnees (regles et variables)');
 WriteLn('  -q, --question               Mode question (code de retour 1 si a refaire)');
 WriteLn('  -s, --silent, --quiet        Mode silencieux');
 WriteLn('  -S, --no-keep-going, --stop  Arrete a la premiere erreur');
 WriteLn('  -t, --touch                  Met a jour les dates au lieu d''executer');
 WriteLn('  -v, --version                Affiche la version');
 WriteLn('  -w, --print-directory        Affiche le repertoire courant');
 WriteLn('  -W file, --what-if=file, --new-file=file, --assume-new=file');
 WriteLn('                               Considere le fichier comme modifie');
 WriteLn('  --warn-undefined-variables   Avertit des variables non definies');
 WriteLn('  VAR=valeur                   Definit une variable (priorite maximale)');
 WriteLn('  --help, /?                   Affiche cette aide');
End;

Procedure Die(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'make: *** ',S);
 {$ELSE}
 WriteLn('make: *** ',S);
 {$ENDIF}
 Halt(2);
End;

Procedure Warn(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'make: ',S);
 {$ELSE}
 WriteLn('make: ',S);
 {$ENDIF}
End;

Procedure Dbg(Const S:String);Begin
 If OptDebug Then WriteLn(S);
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

Function IsBlankCh(C:Char):Boolean;Begin
 IsBlankCh:=(C=' ')Or(C=#9);
End;

{ Mots separes par des blancs }
Function NextWord(Const S:String;Var P:Integer;Var W:String):Boolean;
Var
 J:Integer;
Begin
 NextWord:=False;
 While(P<=Length(S))And IsBlankCh(S[P])Do Inc(P);
 If P>Length(S)Then Exit;
 J:=P;
 While(J<=Length(S))And Not IsBlankCh(S[J])Do Inc(J);
 W:=Copy(S,P,J-P);
 P:=J;
 NextWord:=True;
End;

Function WordCount(Const S:String):Integer;
Var
 P,N:Integer;
 W:String;
Begin
 P:=1;
 N:=0;
 While NextWord(S,P,W)Do Inc(N);
 WordCount:=N;
End;

Function WordN(Const S:String;N:Integer):String;
Var
 P,K:Integer;
 W:String;
Begin
 P:=1;
 K:=0;
 WordN:='';
 While NextWord(S,P,W)Do Begin
  Inc(K);
  If K=N Then Begin
   WordN:=W;
   Exit;
  End;
 End;
End;

Function Lower(Const S:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:=S;
 For I:=1 to Length(R)Do If R[I]In['A'..'Z']Then R[I]:=Chr(Ord(R[I])+32);
 Lower:=R;
End;

{ ------------------------- Temps ------------------------- }

Function NowPacked:Longint;
Var
 Y,Mo,D,Dw,H,Mi,S,S100:Word;
 DT:DateTime;
 T:Longint;
Begin
 GetDate(Y,Mo,D,Dw);
 GetTime(H,Mi,S,S100);
 DT.Year:=Y;
 DT.Month:=Mo;
 DT.Day:=D;
 DT.Hour:=H;
 DT.Min:=Mi;
 DT.Sec:=S;
 PackTime(DT,T);
 NowPacked:=T;
End;

Function FileTime(Const N:String):Longint;
Var
 SR:SearchRec;
Begin
 FileTime:=0;
 If N=''Then Exit;
 FindFirst(N,AnyFile,SR);
 If DosError=0Then FileTime:=SR.Time;
 {$IFDEF FPC}
 FindClose(SR);
 {$ENDIF}
End;

{ ------------------------- Variables ------------------------- }

Function FindVar(Const N:String):Integer;
Var
 I:Integer;
Begin
 FindVar:=0;
 For I:=1 to VarCnt Do If Vars^[I].Name=N Then Begin
  FindVar:=I;
  Exit;
 End;
End;

Function OrgRank(Org:Integer):Integer;Begin
 OrgRank:=Org;
End;

Procedure SetVar(Const N,V:String;Simple:Boolean;Org:Integer);
Var
 I:Integer;
Begin
 I:=FindVar(N);
 If I=0Then Begin
  If VarCnt>=MaxVars Then Begin
   Warn('trop de variables');
   Exit;
  End;
  Inc(VarCnt);
  I:=VarCnt;
  Vars^[I].Name:=Copy(N,1,63);
  Vars^[I].Org:=0;
 End;
 If Org<Vars^[I].Org Then Exit;
 Vars^[I].Val:=NewPStr(V);
 Vars^[I].Simple:=Simple;
 Vars^[I].Org:=Org;
End;

Function IsPhony(Const N:String):Boolean;
Var
 I:Integer;
Begin
 IsPhony:=False;
 For I:=1 to PhonyCnt Do If Phony[I]=N Then IsPhony:=True;
End;

{ ------------------------- Execution de commandes ------------------------- }

Function RunCmd(Const Cmd:String):Integer;
Var
 S:String;
 I:Integer;
Begin
 {$IFDEF UNIX}
 S:='';
 For I:=1 to Length(Cmd)Do Begin
  If Cmd[I]=''''Then S:=S+'''\'''''
                Else S:=S+Cmd[I];
 End;
 SwapVectors;
 Exec('/bin/sh','-c '''+S+'''');
 SwapVectors;
 {$ELSE}
 SwapVectors;
 Exec(GetEnv('COMSPEC'),'/C '+Cmd);
 SwapVectors;
 {$ENDIF}
 If DosError<>0Then RunCmd:=127
               Else RunCmd:=Lo(DosExitCode);
End;

Function ShellOutput(Const Cmd:String):String;
Var
 Tmp,L,R:String;
 F:Text;
 Code:Integer;
Begin
 Inc(TmpCounter);
 Tmp:='make'+IntStr(TmpCounter)+'.tmp';
 Code:=RunCmd(Cmd+' > '+Tmp);
 R:='';
 Assign(F,Tmp);
 {$I-}Reset(F);{$I+}
 If IOResult=0Then Begin
  While Not EOF(F)Do Begin
   ReadLn(F,L);
   If R<>''Then R:=R+' ';
   R:=R+Trim(L);
  End;
  Close(F);
  Erase(F);
 End;
 ShellOutput:=R;
End;

{ ------------------------- Motifs (%) ------------------------- }

Function PatMatch(Const Pat,W:String;Var Stem:String):Boolean;
Var
 P:Integer;
 Pre,Suf:String;
Begin
 Stem:='';
 P:=Pos('%',Pat);
 If P=0Then Begin
  PatMatch:=(Pat=W);
  Exit;
 End;
 Pre:=Copy(Pat,1,P-1);
 Suf:=Copy(Pat,P+1,255);
 PatMatch:=False;
 If Length(W)<Length(Pre)+Length(Suf)Then Exit;
 If Copy(W,1,Length(Pre))<>Pre Then Exit;
 If Copy(W,Length(W)-Length(Suf)+1,Length(Suf))<>Suf Then Exit;
 Stem:=Copy(W,Length(Pre)+1,Length(W)-Length(Pre)-Length(Suf));
 PatMatch:=True;
End;

Function ReplaceStem(Const Repl,Stem:String):String;
Var
 P:Integer;
Begin
 P:=Pos('%',Repl);
 If P=0Then ReplaceStem:=Repl
       Else ReplaceStem:=Copy(Repl,1,P-1)+Stem+Copy(Repl,P+1,255);
End;

Function ReplaceAll(Const S,Old,New:String):String;
Var
 R:String;
 P:Integer;
Begin
 If Old=''Then Begin
  ReplaceAll:=S;
  Exit;
 End;
 R:='';
 P:=Pos(Old,S);
 If P=0Then Begin
  ReplaceAll:=S;
  Exit;
 End;
 ReplaceAll:=Copy(S,1,P-1)+New+ReplaceAll(Copy(S,P+Length(Old),255),Old,New);
End;

Function Expand(Const S:String;Depth:Integer):String;Forward;

{ Separe des arguments aux virgules de premier niveau }
Procedure SplitArgs(Const A:String;Max:Integer;Var Args:TArgs;Var N:Integer);
Var
 I,D,K:Integer;
 C:Char;
Begin
 N:=1;
 For K:=1 to 6 Do Args[K]:='';
 D:=0;
 For I:=1 to Length(A)Do Begin
  C:=A[I];
  If(C='(')Or(C='{')Then Inc(D)
  Else If(C=')')Or(C='}')Then Dec(D);
  If(C=',')And(D=0)And(N<Max)Then Inc(N)
   Else
  Args[N]:=Args[N]+C;
 End;
End;

Function SortedUnique(Const S:String):String;
Var
 W:Array[1..100]Of String[63];
 N,I,J,P:Integer;
 X:String;
 T:String[63];
 R:String;
Begin
 N:=0;
 P:=1;
 While NextWord(S,P,X)And(N<100)Do Begin
  Inc(N);
  W[N]:=Copy(X,1,63);
 End;
 For I:=2 to N Do Begin
  T:=W[I];
  J:=I-1;
  While(J>=1)And(W[J]>T)Do Begin
   W[J+1]:=W[J];
   Dec(J);
  End;
  W[J+1]:=T;
 End;
 R:='';
 For I:=1 to N Do
  If(I=1)Or(W[I]<>W[I-1])Then Begin
   If R<>''Then R:=R+' ';
   R:=R+W[I];
  End;
 SortedUnique:=R;
End;

Function Wildcard(Const Pats:String):String;
Var
 P,I,J:Integer;
 Pat,Dir,R:String;
 SR:SearchRec;
 Names:Array[1..100]Of String[127];
 N:Integer;
 T:String[127];
Begin
 R:='';
 P:=1;
 N:=0;
 While NextWord(Pats,P,Pat)Do Begin
  I:=Length(Pat);
  While(I>0)And Not(Pat[I]In['/','\'])Do Dec(I);
  Dir:=Copy(Pat,1,I);
  FindFirst(Pat,AnyFile,SR);
  While(DosError=0)And(N<100)Do Begin
   If(SR.Name<>'.')And(SR.Name<>'..')Then Begin
    Inc(N);
    Names[N]:=Copy(Dir+SR.Name,1,127);
   End;
   FindNext(SR);
  End;
  {$IFDEF FPC}
  FindClose(SR);
  {$ENDIF}
 End;
 For I:=2 to N Do Begin
  T:=Names[I];
  J:=I-1;
  While(J>=1)And(Names[J]>T)Do Begin
   Names[J+1]:=Names[J];
   Dec(J);
  End;
  Names[J+1]:=T;
 End;
 For I:=1 to N Do Begin
  If R<>''Then R:=R+' ';
  R:=R+Names[I];
 End;
 Wildcard:=R;
End;

Function DirPart(Const W:String):String;
Var
 I:Integer;
Begin
 I:=Length(W);
 While(I>0)And Not(W[I]In['/','\'])Do Dec(I);
 If I=0Then DirPart:='./'
       Else DirPart:=Copy(W,1,I);
End;

Function NotDirPart(Const W:String):String;
Var
 I:Integer;
Begin
 I:=Length(W);
 While(I>0)And Not(W[I]In['/','\'])Do Dec(I);
 NotDirPart:=Copy(W,I+1,255);
End;

Function SuffixPart(Const W:String):String;
Var
 I:Integer;
Begin
 SuffixPart:='';
 I:=Length(W);
 While(I>0)And(W[I]<>'.')And Not(W[I]In['/','\'])Do Dec(I);
 If(I>0)And(W[I]='.')Then SuffixPart:=Copy(W,I,255);
End;

Function EvalFunc(Const Fn,A:String;Depth:Integer):String;
Var
 Args:TArgs;
 N,I,K,P,Num,Num2:Integer;
 R,W,X,Stem,Pat,Lst,S1:String;
 Match:Boolean;
 Code:Integer;
Begin
 R:='';
 If Fn='if'Then Begin
  SplitArgs(A,3,Args,N);
  If Trim(Expand(Args[1],Depth+1))<>''Then R:=Expand(Args[2],Depth+1)
  Else If N>=3Then R:=Expand(Args[3],Depth+1);
  EvalFunc:=R;
  Exit;
 End;
 If Fn='foreach'Then Begin
  SplitArgs(A,3,Args,N);
  S1:=Trim(Expand(Args[1],Depth+1));
  Lst:=Expand(Args[2],Depth+1);
  P:=1;
  While NextWord(Lst,P,W)Do Begin
   SetVar(S1,W,True,OrgOverride);
   If R<>''Then R:=R+' ';
   R:=R+Expand(Args[3],Depth+1);
  End;
  EvalFunc:=R;
  Exit;
 End;
 If(Fn='strip')Or(Fn='sort')Or(Fn='words')Or(Fn='firstword')Or(Fn='lastword')Or(Fn='basename')Or
    (Fn='suffix')Or(Fn='notdir')Or(Fn='dir')Or(Fn='abspath')Or(Fn='realpath')Or(Fn='wildcard')Or
    (Fn='shell')Or(Fn='info')Or(Fn='warning')Or(Fn='error')Or(Fn='origin')Then Begin
  N:=1;
  Args[1]:=Expand(A,Depth+1);
 End
  Else
 Begin
  SplitArgs(A,3,Args,N);
  For I:=1 to N Do Args[I]:=Expand(Args[I],Depth+1);
 End;
 If Fn='subst'Then R:=ReplaceAll(Args[3],Args[1],Args[2])
 Else If Fn='patsubst'Then Begin
  P:=1;
  While NextWord(Args[3],P,W)Do Begin
   If R<>''Then R:=R+' ';
   If PatMatch(Trim(Args[1]),W,Stem)Then R:=R+ReplaceStem(Trim(Args[2]),Stem)
                                    Else R:=R+W;
  End;
 End
 Else If Fn='strip'Then Begin
  R:='';
  P:=1;
  S1:=Args[1];
  While NextWord(S1,P,W)Do Begin
   If R<>''Then R:=R+' ';
   R:=R+W;
  End;
 End
 Else If Fn='findstring'Then Begin
  If Pos(Args[1],Args[2])>0Then R:=Args[1];
 End
 Else If(Fn='filter')Or(Fn='filter-out')Then Begin
  P:=1;
  While NextWord(Args[2],P,W)Do Begin
   Match:=False;
   K:=1;
   While NextWord(Args[1],K,Pat)Do If PatMatch(Pat,W,Stem)Then Match:=True;
   If Match=(Fn='filter')Then Begin
    If R<>''Then R:=R+' ';
    R:=R+W;
   End;
  End;
 End
 Else If Fn='sort'Then R:=SortedUnique(Args[1])
 Else If Fn='word'Then Begin
  Val(Trim(Args[1]),Num,Code);
  If(Code=0)And(Num>=1)Then R:=WordN(Args[2],Num);
 End
 Else If Fn='wordlist'Then Begin
  SplitArgs(A,3,Args,N);
  For I:=1 to N Do Args[I]:=Expand(Args[I],Depth+1);
  Val(Trim(Args[1]),Num,Code);
  Val(Trim(Args[2]),Num2,Code);
  For I:=Num to Num2 Do Begin
   X:=WordN(Args[3],I);
   If X<>''Then Begin
    If R<>''Then R:=R+' ';
    R:=R+X;
   End;
  End;
 End
 Else If Fn='words'Then R:=IntStr(WordCount(Args[1]))
 Else If Fn='firstword'Then R:=WordN(Args[1],1)
 Else If Fn='lastword'Then R:=WordN(Args[1],WordCount(Args[1]))
 Else If(Fn='addprefix')Or(Fn='addsuffix')Then Begin
  P:=1;
  While NextWord(Args[2],P,W)Do Begin
   If R<>''Then R:=R+' ';
   If Fn='addprefix'Then R:=R+Args[1]+W
                    Else R:=R+W+Args[1];
  End;
 End
 Else If(Fn='basename')Or(Fn='suffix')Or(Fn='notdir')Or(Fn='dir')Or(Fn='abspath')Or(Fn='realpath')Then Begin
  P:=1;
  While NextWord(Args[1],P,W)Do Begin
   If R<>''Then R:=R+' ';
   If Fn='basename'Then Begin
    X:=SuffixPart(W);
    R:=R+Copy(W,1,Length(W)-Length(X));
   End
   Else If Fn='suffix'Then R:=R+SuffixPart(W)
   Else If Fn='notdir'Then R:=R+NotDirPart(W)
   Else If Fn='dir'Then R:=R+DirPart(W)
   Else R:=R+FExpand(W);
  End;
 End
 Else If Fn='wildcard'Then R:=Wildcard(Args[1])
 Else If Fn='shell'Then R:=ShellOutput(Args[1])
 Else If Fn='origin'Then Begin
  K:=FindVar(Trim(Args[1]));
  If K=0Then R:='undefined'
  Else Case Vars^[K].Org of
   OrgDefault:R:='default';
   OrgEnv,OrgEnvOver:R:='environment';
   OrgFile:R:='file';
   OrgOverride:R:='override';
   Else R:='command line';
  End;
 End
 Else If Fn='info'Then WriteLn(Args[1])
 Else If Fn='warning'Then Warn(CurFile+':'+IntStr(LineNo)+': '+Args[1])
 Else If Fn='error'Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,CurFile,':',LineNo,': *** ',Args[1],'.  Stop.');
  {$ELSE}
  WriteLn(CurFile,':',LineNo,': *** ',Args[1],'.  Stop.');
  {$ENDIF}
  Halt(2);
 End
 Else Begin
  Warn('fonction inconnue: '+Fn);
 End;
 EvalFunc:=R;
End;

Function IsFuncName(Const N:String):Boolean;Begin
 IsFuncName:=(N='subst')Or(N='patsubst')Or(N='strip')Or(N='findstring')Or(N='filter')Or
  (N='filter-out')Or(N='sort')Or(N='word')Or(N='wordlist')Or(N='words')Or(N='firstword')Or
  (N='lastword')Or(N='addprefix')Or(N='addsuffix')Or(N='basename')Or(N='suffix')Or
  (N='notdir')Or(N='dir')Or(N='abspath')Or(N='realpath')Or(N='wildcard')Or(N='shell')Or
  (N='if')Or(N='foreach')Or(N='origin')Or(N='info')Or(N='warning')Or(N='error');
End;

{ Valeur d'une variable (avec variables automatiques) }
Function VarValue(Const Name:String;Depth:Integer):String;
Var
 I:Integer;
 C,Q:Char;
 V,R,W:String;
 P:Integer;
Begin
 VarValue:='';
 If(Length(Name)=1)Or((Length(Name)=2)And(Name[2]In['D','F']))Then Begin
  C:=Name[1];
  If C In['@','<','^','+','?','*','%']Then Begin
   Case C of
    '@':V:=AutoTarget;
    '<':V:=AutoFirst;
    '^':V:=AutoAll;
    '+':V:=AutoPlus;
    '?':V:=AutoNewer;
    '*':V:=AutoStem;
    Else V:='';
   End;
   If Length(Name)=2Then Begin
    R:='';
    P:=1;
    While NextWord(V,P,W)Do Begin
     If R<>''Then R:=R+' ';
     If Name[2]='D'Then Begin
      Q:=#0;
      R:=R+Copy(DirPart(W),1,Length(DirPart(W))-1);
      If DirPart(W)='./'Then R:=Copy(R,1,Length(R)-1)+'.';
     End
      Else
     R:=R+NotDirPart(W);
    End;
    V:=R;
   End;
   VarValue:=V;
   Exit;
  End;
 End;
 I:=FindVar(Name);
 If I=0Then Begin
  If OptWarnUndef Then Warn(CurFile+':'+IntStr(LineNo)+': warning: undefined variable '''+Name+'''');
  Exit;
 End;
 If Vars^[I].Simple Then VarValue:=Vars^[I].Val^
  Else
 Begin
  If Depth>40Then Die('Recursive variable '''+Name+''' references itself (eventually).  Stop.');
  VarValue:=Expand(Vars^[I].Val^,Depth+1);
 End;
End;

Function EvalRef(Const Content:String;Depth:Integer):String;
Var
 P,Q,I:Integer;
 Fn,Rest,Nm,Cnt,Pat,Repl,Stem,W,R,Base:String;
Begin
 { fonction ? }
 P:=1;
 While(P<=Length(Content))And Not IsBlankCh(Content[P])Do Inc(P);
 If P<=Length(Content)Then Begin
  Fn:=Copy(Content,1,P-1);
  If IsFuncName(Fn)Then Begin
   While(P<=Length(Content))And IsBlankCh(Content[P])Do Inc(P);
   EvalRef:=EvalFunc(Fn,Copy(Content,P,255),Depth);
   Exit;
  End;
 End;
 Cnt:=Expand(Content,Depth+1);
 { reference avec substitution : $(VAR:a=b) }
 P:=Pos(':',Cnt);
 If P>0Then Begin
  Q:=Pos('=',Copy(Cnt,P+1,255));
  If Q>0Then Begin
   Nm:=Copy(Cnt,1,P-1);
   Pat:=Copy(Cnt,P+1,Q-1);
   Repl:=Copy(Cnt,P+Q+1,255);
   Base:=VarValue(Nm,Depth);
   R:='';
   I:=1;
   If Pos('%',Pat)=0Then Begin
    Pat:='%'+Pat;
    Repl:='%'+Repl;
   End;
   While NextWord(Base,I,W)Do Begin
    If R<>''Then R:=R+' ';
    If PatMatch(Pat,W,Stem)Then R:=R+ReplaceStem(Repl,Stem)
                           Else R:=R+W;
   End;
   EvalRef:=R;
   Exit;
  End;
 End;
 EvalRef:=VarValue(Cnt,Depth);
End;

Function Expand(Const S:String;Depth:Integer):String;
Var
 R,Cnt:String;
 I,D,Start:Integer;
 C,Op,Cl:Char;
Begin
 If Depth>50Then Begin
  Expand:=S;
  Exit;
 End;
 R:='';
 I:=1;
 While I<=Length(S)Do Begin
  C:=S[I];
  If C<>'$'Then Begin
   R:=R+C;
   Inc(I);
  End
   Else
  Begin
   Inc(I);
   If I>Length(S)Then Begin
    R:=R+'$';
    Break;
   End;
   C:=S[I];
   If C='$'Then Begin
    R:=R+'$';
    Inc(I);
   End
   Else If(C='(')Or(C='{')Then Begin
    Op:=C;
    If C='('Then Cl:=')'
            Else Cl:='}';
    Start:=I+1;
    D:=1;
    Inc(I);
    While(I<=Length(S))And(D>0)Do Begin
     If S[I]=Op Then Inc(D)
     Else If S[I]=Cl Then Dec(D);
     Inc(I);
    End;
    If D>0Then Cnt:=Copy(S,Start,255)
          Else Cnt:=Copy(S,Start,I-Start-1);
    R:=R+EvalRef(Cnt,Depth);
   End
    Else
   Begin
    R:=R+VarValue(C,Depth);
    Inc(I);
   End;
  End;
 End;
 Expand:=R;
End;

{ ------------------------- Regles ------------------------- }

Var
 CurRules:Array[1..40]Of Integer;
 CurRuleN:Integer;
 RecCmds:Array[1..60]Of PStr;
 RecN:Integer;

Function FindExplicit(Const T:String):Integer;
Var
 I:Integer;
Begin
 FindExplicit:=0;
 For I:=1 to RuleCnt Do
  If(Not Rules^[I].IsPat)And(Rules^[I].Targ=T)Then Begin
   FindExplicit:=I;
   Exit;
  End;
End;

Function IsSuffix(Const S:String):Boolean;
Var
 I:Integer;
Begin
 IsSuffix:=False;
 For I:=1 to SuffixCnt Do If Suffixes[I]=S Then IsSuffix:=True;
End;

Procedure AddSuffix(Const S:String);Begin
 If(S<>'')And Not IsSuffix(S)And(SuffixCnt<MaxSuffix)Then Begin
  Inc(SuffixCnt);
  Suffixes[SuffixCnt]:=Copy(S,1,15);
 End;
End;

{ Cree une regle (ou fusionne les prerequis) et retourne son indice }
Function AddRule(Const T,Pre,OrdPre:String;IsPat,Builtin:Boolean):Integer;
Var
 I,S1,S2:Integer;
 Targ,P:String;
 Idx:Integer;
Begin
 Targ:=T;
 P:=Pre;
 { regle de suffixe : .c.o ou .c }
 If(Targ[1]='.')And(Pos('%',Targ)=0)And(Trim(Pre)='')And Not IsPat Then Begin
  If IsSuffix(Targ)Then Begin
   P:='%'+Targ;
   Targ:='%';
   IsPat:=True;
  End
   Else
  For I:=2 to Length(Targ)-1 Do
   If(Targ[I]='.')And IsSuffix(Copy(Targ,1,I-1))And IsSuffix(Copy(Targ,I,255))Then Begin
    P:='%'+Copy(Targ,1,I-1);
    Targ:='%'+Copy(Targ,I,255);
    IsPat:=True;
    Break;
   End;
 End;
 Idx:=0;
 If Not IsPat Then Idx:=FindExplicit(Targ);
 If Idx=0Then Begin
  If RuleCnt>=MaxRules Then Begin
   Die('trop de regles.  Stop.');
  End;
  Inc(RuleCnt);
  Idx:=RuleCnt;
  Rules^[Idx].Targ:=Copy(Targ,1,127);
  Rules^[Idx].Pre:=NewPStr(Trim(P));
  Rules^[Idx].OrdPre:=NewPStr(Trim(OrdPre));
  Rules^[Idx].CFirst:=0;
  Rules^[Idx].CCnt:=0;
  Rules^[Idx].IsPat:=IsPat;
  Rules^[Idx].Builtin:=Builtin;
  Rules^[Idx].Line:=LineNo;
 End
  Else
 Begin
  Rules^[Idx].Pre:=NewPStr(Trim(Rules^[Idx].Pre^+' '+P));
  Rules^[Idx].OrdPre:=NewPStr(Trim(Rules^[Idx].OrdPre^+' '+OrdPre));
 End;
 AddRule:=Idx;
End;

Procedure FlushRecipe;
Var
 I,J,First:Integer;
Begin
 If(RecN>0)And(CurRuleN>0)Then Begin
  First:=CmdCnt+1;
  For I:=1 to RecN Do Begin
   If CmdCnt>=MaxCmds Then Die('trop de commandes.  Stop.');
   Inc(CmdCnt);
   Cmds[CmdCnt]:=RecCmds[I];
  End;
  For J:=1 to CurRuleN Do Begin
   Rules^[CurRules[J]].CFirst:=First;
   Rules^[CurRules[J]].CCnt:=RecN;
  End;
 End;
 RecN:=0;
End;

Procedure AddRecipe(Const L:String);Begin
 If RecN<60Then Begin
  Inc(RecN);
  RecCmds[RecN]:=NewPStr(L);
 End;
End;

{ ------------------------- Analyse du makefile ------------------------- }

Function StripComment(Const L:String):String;
Var
 I:Integer;
Begin
 I:=1;
 While I<=Length(L)Do Begin
  If(L[I]='\')And(I<Length(L))And(L[I+1]='#')Then Inc(I,2)
  Else If L[I]='#'Then Begin
   StripComment:=Copy(L,1,I-1);
   Exit;
  End
  Else Inc(I);
 End;
 StripComment:=L;
End;

{ Classe une ligne : 1 affectation, 2 regle, 0 autre }
Function Classify(Const L:String;Var P1,OpLen:Integer;Var Op:String):Integer;
Var
 I,D:Integer;
 C:Char;
Begin
 Classify:=0;
 D:=0;
 I:=1;
 While I<=Length(L)Do Begin
  C:=L[I];
  If(C='$')And(I<Length(L))And(L[I+1]In['(','{'])Then Begin
   Inc(D);
   Inc(I,2);
   Continue;
  End;
  If(D>0)And((C=')')Or(C='}'))Then Dec(D)
  Else If D=0Then Begin
   If C='='Then Begin
    Op:='=';
    P1:=I;
    OpLen:=1;
    If(I>1)And(L[I-1]=':')Then Begin
     Op:=':=';
     P1:=I-1;
     OpLen:=2;
     If(P1>1)And(L[P1-1]=':')Then Begin
      Dec(P1);
      Inc(OpLen);
     End;
    End
    Else If(I>1)And(L[I-1]='+')Then Begin
     Op:='+=';
     P1:=I-1;
     OpLen:=2;
    End
    Else If(I>1)And(L[I-1]='?')Then Begin
     Op:='?=';
     P1:=I-1;
     OpLen:=2;
    End
    Else If(I>1)And(L[I-1]='!')Then Begin
     Op:='!=';
     P1:=I-1;
     OpLen:=2;
    End;
    Classify:=1;
    Exit;
   End
   Else If C=':'Then Begin
    If(I<Length(L))And(L[I+1]='=')Then Begin
     Op:=':=';
     P1:=I;
     OpLen:=2;
     Classify:=1;
     Exit;
    End;
    If(I<Length(L)-1)And(L[I+1]=':')And(L[I+2]='=')Then Begin
     Op:=':=';
     P1:=I;
     OpLen:=3;
     Classify:=1;
     Exit;
    End;
    If Not((I>=2)And(UpCase(L[I-1])In['A'..'Z'])And((I=2)Or IsBlankCh(L[I-2]))And
           (I<Length(L))And(L[I+1]In['\','/']))Then Begin
     P1:=I;
     Classify:=2;
     Exit;
    End;
   End;
  End;
  Inc(I);
 End;
End;

Procedure DoAssign(Const L:String;P1,OpLen:Integer;Const Op:String;Org:Integer);
Var
 Nm,V,Old:String;
 I:Integer;
Begin
 Nm:=Trim(Expand(Copy(L,1,P1-1),0));
 V:=Trim(Copy(L,P1+OpLen,255));
 If Nm=''Then Exit;
 I:=FindVar(Nm);
 If Op=':='Then SetVar(Nm,Expand(V,0),True,Org)
 Else If Op='?='Then Begin
  If I=0Then SetVar(Nm,V,False,Org);
 End
 Else If Op='+='Then Begin
  If I=0Then SetVar(Nm,V,False,Org)
  Else Begin
   If Org<Vars^[I].Org Then Exit;
   If Vars^[I].Simple Then Old:=Vars^[I].Val^+' '+Expand(V,0)
                      Else Old:=Vars^[I].Val^+' '+V;
   Vars^[I].Val:=NewPStr(Trim(Old));
  End;
 End
 Else If Op='!='Then SetVar(Nm,ShellOutput(Expand(V,0)),True,Org)
 Else SetVar(Nm,V,False,Org);
End;

Procedure DoSpecial(Const T,Pre:String);
Var
 P:Integer;
 W:String;
Begin
 If T='.PHONY'Then Begin
  P:=1;
  While NextWord(Pre,P,W)Do
   If PhonyCnt<MaxPhony Then Begin
    Inc(PhonyCnt);
    Phony[PhonyCnt]:=Copy(W,1,63);
   End;
 End
 Else If T='.SUFFIXES'Then Begin
  If Trim(Pre)=''Then SuffixCnt:=0
   Else Begin
    P:=1;
    While NextWord(Pre,P,W)Do AddSuffix(W);
   End;
 End
 Else If T='.SILENT'Then Begin
  If Trim(Pre)=''Then SilentAll:=True;
 End
 Else If T='.IGNORE'Then Begin
  If Trim(Pre)=''Then IgnoreAll:=True;
 End;
End;

Function IsSpecialIgnored(Const T:String):Boolean;Begin
 IsSpecialIgnored:=(T='.PRECIOUS')Or(T='.SECONDARY')Or(T='.INTERMEDIATE')Or
  (T='.DELETE_ON_ERROR')Or(T='.NOTPARALLEL')Or(T='.ONESHELL')Or(T='.EXPORT_ALL_VARIABLES')Or
  (T='.POSIX')Or(T='.LOW_RESOLUTION_TIME')Or(T='.SECONDEXPANSION');
End;

Function TopColon(Const S:String):Integer;
Var
 I,D:Integer;
Begin
 TopColon:=0;
 D:=0;
 For I:=1 to Length(S)Do Begin
  If(S[I]='$')And(I<Length(S))And(S[I+1]In['(','{'])Then Inc(D)
  Else If(D>0)And((S[I]=')')Or(S[I]='}'))Then Dec(D)
  Else If(D=0)And(S[I]=':')Then Begin
   TopColon:=I;
   Exit;
  End;
 End;
End;

Procedure DoRule(Const L:String;ColonPos:Integer);
Var
 Left,Right,InlCmd,PreS,OrdS,TP,PP,Stem,W,Np,Q,Pr:String;
 I,P,K,Idx:Integer;
 StaticR:Boolean;
Begin
 FlushRecipe;
 CurRuleN:=0;
 Left:=Expand(Copy(L,1,ColonPos-1),0);
 Right:=Copy(L,ColonPos+1,255);
 If(Right<>'')And(Right[1]=':')Then Right:=Copy(Right,2,255);
 { commande en ligne apres ; }
 InlCmd:='';
 P:=0;
 For I:=1 to Length(Right)Do If(Right[I]=';')And(P=0)Then P:=I;
 If P>0Then Begin
  InlCmd:=Trim(Copy(Right,P+1,255));
  Right:=Copy(Right,1,P-1);
 End;
 StaticR:=False;
 K:=TopColon(Right);
 If K>0Then Begin
  StaticR:=True;
  TP:=Trim(Expand(Copy(Right,1,K-1),0));
  PP:=Trim(Expand(Copy(Right,K+1,255),0));
 End
  Else
 Begin
  Right:=Expand(Right,0);
  PreS:=Right;
  OrdS:='';
  P:=Pos('|',Right);
  If P>0Then Begin
   PreS:=Copy(Right,1,P-1);
   OrdS:=Copy(Right,P+1,255);
  End;
 End;
 I:=1;
 While NextWord(Left,I,W)Do Begin
  If StaticR Then Begin
   If PatMatch(TP,W,Stem)Then Begin
    Np:='';
    Q:=PP;
    P:=1;
    While NextWord(Q,P,Pr)Do Np:=Np+' '+ReplaceStem(Pr,Stem);
    Idx:=AddRule(W,Np,'',False,False);
   End
    Else
   Idx:=0;
  End
  Else If(W[1]='.')And((W='.PHONY')Or(W='.SUFFIXES')Or(W='.SILENT')Or(W='.IGNORE')Or
          IsSpecialIgnored(W))Then Begin
   DoSpecial(W,PreS);
   Idx:=0;
  End
  Else Begin
   Idx:=AddRule(W,PreS,OrdS,Pos('%',W)>0,False);
   If(DefaultGoal='')And Not Rules^[Idx].IsPat And(W[1]<>'.')Then DefaultGoal:=Copy(W,1,127);
  End;
  If(Idx>0)And(CurRuleN<40)Then Begin
   Inc(CurRuleN);
   CurRules[CurRuleN]:=Idx;
  End;
 End;
 If InlCmd<>''Then AddRecipe(InlCmd);
End;

{ ------------------------- Conditionnelles ------------------------- }

Function EvalIfeq(Const A:String):Boolean;
Var
 S:String;
 I,D,Q:Integer;
 X,Y:String;
 C:Char;
Begin
 EvalIfeq:=False;
 S:=Trim(Expand(A,0));
 If S=''Then Exit;
 If S[1]='('Then Begin
  D:=0;
  Q:=0;
  For I:=2 to Length(S)Do Begin
   If(S[I]='(')Or(S[I]='{')Then Inc(D)
   Else If(S[I]=')')Or(S[I]='}')Then Dec(D)
   Else If(S[I]=',')And(D=0)And(Q=0)Then Q:=I;
  End;
  If Q=0Then Exit;
  X:=Trim(Copy(S,2,Q-2));
  Y:=Trim(Copy(S,Q+1,Length(S)-Q-1));
  EvalIfeq:=(X=Y);
 End
  Else
 Begin
  C:=S[1];
  If Not(C In['''','"'])Then Exit;
  I:=2;
  While(I<=Length(S))And(S[I]<>C)Do Inc(I);
  X:=Copy(S,2,I-2);
  S:=Trim(Copy(S,I+1,255));
  If S=''Then Exit;
  C:=S[1];
  Y:=Copy(S,2,Length(S)-2);
  EvalIfeq:=(X=Y);
 End;
End;

Function EvalCond(Const Dir,Rest:String):Boolean;
Var
 Nm:String;
 I:Integer;
 Def:Boolean;
Begin
 If(Dir='ifeq')Then EvalCond:=EvalIfeq(Rest)
 Else If Dir='ifneq'Then EvalCond:=Not EvalIfeq(Rest)
 Else Begin
  Nm:=Trim(Expand(Rest,0));
  I:=FindVar(Nm);
  Def:=False;
  If I>0Then Begin
   If Vars^[I].Val^<>''Then Def:=True;
  End;
  If Dir='ifdef'Then EvalCond:=Def
                Else EvalCond:=Not Def;
 End;
End;

Function ReadLogical(Var F:Text;Var L:String;Var Recipe:Boolean):Boolean;
Var
 T:String;
 N,I:Integer;
Begin
 ReadLogical:=False;
 If EOF(F)Then Exit;
 ReadLn(F,L);
 Inc(LineNo);
 ReadLogical:=True;
 Recipe:=(L<>'')And(L[1]=Tab);
 While True Do Begin
  N:=0;
  I:=Length(L);
  While(I>0)And(L[I]='\')Do Begin
   Inc(N);
   Dec(I);
  End;
  If Not Odd(N)Then Break;
  L:=Copy(L,1,Length(L)-1);
  If EOF(F)Then Break;
  ReadLn(F,T);
  Inc(LineNo);
  If Recipe Then L:=L+' '+Trim(T)
            Else L:=L+' '+Trim(T);
 End;
End;

Function FindInclude(Const Nm:String):String;
Var
 I:Integer;
Begin
 FindInclude:='';
 If FileTime(Nm)>0Then Begin
  FindInclude:=Nm;
  Exit;
 End;
 For I:=1 to IncDirCnt Do
  If FileTime(IncDirs[I]+'/'+Nm)>0Then Begin
   FindInclude:=IncDirs[I]+'/'+Nm;
   Exit;
  End;
End;

Procedure ParseFile(Const Name:String;Depth:Integer;Optional:Boolean);
Var
 F:Text;
 L,T,Dir,Rest,Nm,V,W,Full,Body:String;
 Recipe,Inactive:Boolean;
 P1,OpLen,K,I,Org,Base,P:Integer;
 Op:String;
 SaveFile:String;
 SaveLine:Longint;
 Cond:Boolean;
Begin
 Full:=FindInclude(Name);
 If Full=''Then Begin
  If Not Optional Then Die(Name+': No such file or directory.  Stop.');
  Exit;
 End;
 Assign(F,Full);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  If Not Optional Then Die(Name+': No such file or directory.  Stop.');
  Exit;
 End;
 SaveFile:=CurFile;
 SaveLine:=LineNo;
 CurFile:=Full;
 LineNo:=0;
 Base:=IfTop;
 CurRuleN:=0;
 RecN:=0;
 While ReadLogical(F,L,Recipe)Do Begin
  If Recipe Then Begin
   If IfActive[IfTop]And(CurRuleN>0)Then Begin
    T:=Copy(L,2,255);
    If Trim(T)<>''Then AddRecipe(T);
   End;
   Continue;
  End;
  L:=StripComment(L);
  T:=Trim(L);
  If T=''Then Continue;
  { directive ? }
  K:=1;
  While(K<=Length(T))And Not IsBlankCh(T[K])Do Inc(K);
  Dir:=Copy(T,1,K-1);
  Rest:=Trim(Copy(T,K,255));
  If(Dir='ifdef')Or(Dir='ifndef')Or(Dir='ifeq')Or(Dir='ifneq')Then Begin
   FlushRecipe;
   If IfTop>=MaxIf Then Die('conditionnelles trop imbriquees.  Stop.');
   Cond:=False;
   If IfActive[IfTop]Then Cond:=EvalCond(Dir,Rest);
   Inc(IfTop);
   IfActive[IfTop]:=IfActive[IfTop-1]And Cond;
   IfDone[IfTop]:=Cond;
   Continue;
  End;
  If Dir='else'Then Begin
   FlushRecipe;
   If IfTop<=Base Then Die(CurFile+':'+IntStr(LineNo)+': extraneous ''else''.  Stop.');
   If Rest=''Then Begin
    IfActive[IfTop]:=IfActive[IfTop-1]And Not IfDone[IfTop];
    IfDone[IfTop]:=True;
   End
    Else
   Begin
    K:=1;
    While(K<=Length(Rest))And Not IsBlankCh(Rest[K])Do Inc(K);
    Cond:=False;
    If IfActive[IfTop-1]And Not IfDone[IfTop]Then Cond:=EvalCond(Copy(Rest,1,K-1),Trim(Copy(Rest,K,255)));
    IfActive[IfTop]:=IfActive[IfTop-1]And Not IfDone[IfTop]And Cond;
    If Cond Then IfDone[IfTop]:=True;
   End;
   Continue;
  End;
  If Dir='endif'Then Begin
   FlushRecipe;
   If IfTop<=Base Then Die(CurFile+':'+IntStr(LineNo)+': extraneous ''endif''.  Stop.');
   Dec(IfTop);
   Continue;
  End;
  If Not IfActive[IfTop]Then Continue;
  If(Dir='include')Or(Dir='-include')Or(Dir='sinclude')Then Begin
   FlushRecipe;
   CurRuleN:=0;
   Rest:=Expand(Rest,0);
   I:=1;
   While NextWord(Rest,I,W)Do ParseFile(W,Depth+1,Dir<>'include');
   Continue;
  End;
  If(Dir='vpath')Or(Dir='VPATH')Or(Dir='unexport')Or((Dir='export')And(Rest=''))Then Continue;
  If Dir='define'Then Begin
   FlushRecipe;
   Nm:=Trim(Rest);
   Op:='=';
   If(Length(Nm)>0)And(Nm[Length(Nm)]='=')Then Begin
    Nm:=Trim(Copy(Nm,1,Length(Nm)-1));
    If(Length(Nm)>0)And(Nm[Length(Nm)]=':')Then Begin
     Nm:=Trim(Copy(Nm,1,Length(Nm)-1));
     Op:=':=';
    End;
   End;
   Body:='';
   While ReadLogical(F,L,Recipe)Do Begin
    If Trim(L)='endef'Then Break;
    If Body<>''Then Body:=Body+#10;
    Body:=Body+L;
   End;
   If Op=':='Then SetVar(Expand(Nm,0),Expand(Body,0),True,OrgFile)
             Else SetVar(Expand(Nm,0),Body,False,OrgFile);
   Continue;
  End;
  Org:=OrgFile;
  If(Dir='override')Then Begin
   Org:=OrgOverride;
   T:=Rest;
  End
  Else If(Dir='export')Then T:=Rest;
  Op:='';
  K:=Classify(T,P1,OpLen,Op);
  If K=1Then Begin
   FlushRecipe;
   CurRuleN:=0;
   DoAssign(T,P1,OpLen,Op,Org);
  End
  Else If K=2Then DoRule(T,P1)
  Else Begin
   Warn(CurFile+':'+IntStr(LineNo)+': *** missing separator.  Stop.');
   Halt(2);
  End;
 End;
 FlushRecipe;
 Close(F);
 If IfTop>Base Then Die(CurFile+': missing ''endif''.  Stop.');
 CurFile:=SaveFile;
 LineNo:=SaveLine;
End;

{ ------------------------- Moteur de production ------------------------- }

Function FindBuilt(Const T:String):Integer;
Var
 I:Integer;
Begin
 FindBuilt:=0;
 For I:=1 to BuiltCnt Do If Built^[I].Name=T Then Begin
  FindBuilt:=I;
  Exit;
 End;
End;

Function IsAssumeOld(Const T:String):Boolean;
Var
 I:Integer;
Begin
 IsAssumeOld:=False;
 For I:=1 to AssumeOldCnt Do If AssumeOld[I]=T Then IsAssumeOld:=True;
End;

Function IsAssumeNew(Const T:String):Boolean;
Var
 I:Integer;
Begin
 IsAssumeNew:=False;
 For I:=1 to AssumeNewCnt Do If AssumeNew[I]=T Then IsAssumeNew:=True;
End;

Procedure TouchFile(Const N:String);
Var
 F:File;
Begin
 Assign(F,N);
 FileMode:=2;
 {$I-}Reset(F,1);{$I+}
 If IOResult=0Then Begin
  SetFTime(F,NowPacked);
  Close(F);
 End
  Else
 Begin
  {$I-}Rewrite(F,1);{$I+}
  If IOResult=0Then Close(F);
 End;
End;

Function CanMake(Const W:String;D:Integer):Boolean;Forward;

Function FindImplicit(Const T:String;D:Integer;Var Ri:Integer;Var Stem:String):Boolean;
Var
 Pass,I,P:Integer;
 Ok:Boolean;
 Pr,W2:String;
Begin
 FindImplicit:=False;
 For Pass:=0 to 1 Do
  For I:=1 to RuleCnt Do
   If Rules^[I].IsPat And(Rules^[I].Builtin=(Pass=1))And(Rules^[I].CCnt>0)Then
    If PatMatch(Rules^[I].Targ,T,Stem)Then Begin
     Ok:=True;
     P:=1;
     While Ok And NextWord(Rules^[I].Pre^,P,Pr)Do Begin
      W2:=ReplaceStem(Pr,Stem);
      If(W2<>T)And Not CanMake(W2,D-1)Then Ok:=False;
      If W2=T Then Ok:=False;
     End;
     If Ok Then Begin
      Ri:=I;
      FindImplicit:=True;
      Exit;
     End;
    End;
End;

Function CanMake(Const W:String;D:Integer):Boolean;
Var
 Ri:Integer;
 Stem:String;
Begin
 CanMake:=True;
 If FileTime(W)>0Then Exit;
 If IsPhony(W)Then Exit;
 Ri:=FindExplicit(W);
 If Ri>0Then Exit;
 If(D>0)And FindImplicit(W,D,Ri,Stem)Then Exit;
 CanMake:=False;
End;

Function RunRecipe(Const T:String;First,Cnt:Integer):Boolean;
Var
 I,K,P:Integer;
 Raw,Part,Cmd,Exp_:String;
 Silent,Ign,Force:Boolean;
 Code:Integer;
Begin
 RunRecipe:=True;
 For I:=First to First+Cnt-1 Do Begin
  Raw:=Cmds[I]^;
  Force:=(Pos('$(MAKE)',Raw)>0)Or(Pos('${MAKE}',Raw)>0);
  Exp_:=Expand(Raw,0);
  K:=1;
  While K<=Length(Exp_)Do Begin
   P:=K;
   While(P<=Length(Exp_))And(Exp_[P]<>#10)Do Inc(P);
   Part:=Copy(Exp_,K,P-K);
   K:=P+1;
   Cmd:=Trim(Part);
   Silent:=SilentAll Or OptSilent;
   Ign:=IgnoreAll Or OptIgnore;
   While(Cmd<>'')And(Cmd[1]In['@','-','+',' ',Tab])Do Begin
    If Cmd[1]='@'Then Silent:=True
    Else If Cmd[1]='-'Then Ign:=True
    Else If Cmd[1]='+'Then Force:=True;
    Cmd:=Copy(Cmd,2,255);
   End;
   If Cmd=''Then Continue;
   If Not Silent Or(OptDry And Not Force)Then WriteLn(Cmd);
   If OptDry And Not Force Then Continue;
   Flush(Output);
   DidRun:=True;
   Code:=RunCmd(Cmd);
   If Code<>0Then Begin
    If Ign Then Begin
     Warn('['+T+'] Error '+IntStr(Code)+' (ignored)');
    End
     Else
    Begin
     Flush(Output);
     Warn('*** ['+T+'] Error '+IntStr(Code));
     RunRecipe:=False;
     Exit;
    End;
   End;
  End;
 End;
End;

Function UpdateTarget(Const T,Parent:String;Depth:Integer):Boolean;
Var
 B,Ri,Ii,I,P,X:Integer;
 Pre,OrdP,Plus,All,Newer,First,W,Stem,Pr:String;
 TTime,Newest,PTime:Longint;
 Need,PreUpd,Failed,Phon,HasCmd:Boolean;
 CFirst,CCnt:Integer;
Begin
 UpdateTarget:=True;
 B:=FindBuilt(T);
 If B>0Then Begin
  If Built^[B].State=1Then Begin
   Warn('Circular '+Parent+' <- '+T+' dependency dropped.');
   Exit;
  End;
  UpdateTarget:=Not Built^[B].Failed;
  Exit;
 End;
 If BuiltCnt>=MaxBuilt Then Die('trop de cibles.  Stop.');
 Inc(BuiltCnt);
 B:=BuiltCnt;
 Built^[B].Name:=Copy(T,1,127);
 Built^[B].State:=1;
 Built^[B].Time:=0;
 Built^[B].Updated:=False;
 Built^[B].Failed:=False;
 Phon:=IsPhony(T);
 Ri:=FindExplicit(T);
 Pre:='';
 OrdP:='';
 CFirst:=0;
 CCnt:=0;
 Stem:='';
 If Ri>0Then Begin
  Pre:=Rules^[Ri].Pre^;
  OrdP:=Rules^[Ri].OrdPre^;
  CFirst:=Rules^[Ri].CFirst;
  CCnt:=Rules^[Ri].CCnt;
 End;
 If(CCnt=0)And Not Phon Then Begin
  If FindImplicit(T,2,Ii,Stem)Then Begin
   P:=1;
   While NextWord(Rules^[Ii].Pre^,P,W)Do Pre:=Pre+' '+ReplaceStem(W,Stem);
   CFirst:=Rules^[Ii].CFirst;
   CCnt:=Rules^[Ii].CCnt;
   Ri:=Ii;
  End;
 End;
 If(Ri=0)Then Begin
  { cible sans regle }
  Ri:=FindExplicit('.DEFAULT');
  If(Ri>0)And(FileTime(T)=0)Then Begin
   CFirst:=Rules^[Ri].CFirst;
   CCnt:=Rules^[Ri].CCnt;
  End
  Else If FileTime(T)>0Then Begin
   Built^[B].State:=2;
   Built^[B].Time:=FileTime(T);
   Exit;
  End
  Else Begin
   Built^[B].State:=2;
   Built^[B].Failed:=True;
   If Parent<>''Then Warn('*** No rule to make target '''+T+''', needed by '''+Parent+'''.  Stop.')
                Else Warn('*** No rule to make target '''+T+'''.  Stop.');
   ErrorsSeen:=True;
   If Not OptKeep Then Halt(2);
   UpdateTarget:=False;
   Exit;
  End;
 End;
 HasCmd:=CCnt>0;
 If IsAssumeOld(T)Then Begin
  Built^[B].State:=2;
  Built^[B].Time:=FileTime(T);
  Exit;
 End;
 { prerequis }
 Failed:=False;
 PreUpd:=False;
 Newest:=0;
 TTime:=FileTime(T);
 If IsAssumeNew(T)Then TTime:=MaxLongint;
 First:='';
 All:='';
 Plus:='';
 P:=1;
 While NextWord(Pre,P,W)Do Begin
  If Not UpdateTarget(W,T,Depth+1)Then Failed:=True;
  X:=FindBuilt(W);
  If X>0Then Begin
   PTime:=Built^[X].Time;
   If Built^[X].Updated Then PreUpd:=True;
   If PTime>Newest Then Newest:=PTime;
  End;
  If First=''Then First:=W;
  Plus:=Plus+' '+W;
  If Pos(' '+W+' ',' '+All+' ')=0Then All:=All+' '+W;
 End;
 P:=1;
 While NextWord(OrdP,P,W)Do
  If Not UpdateTarget(W,T,Depth+1)Then Failed:=True;
 If Failed Then Begin
  Built^[B].State:=2;
  Built^[B].Failed:=True;
  Warn('Target '''+T+''' not remade because of errors.');
  UpdateTarget:=False;
  Exit;
 End;
 If IsAssumeNew(T)Then TTime:=MaxLongint
                  Else TTime:=FileTime(T);
 Need:=Phon Or OptAlways Or(TTime=0)Or(Newest>TTime)Or PreUpd;
 If Not Need Then Begin
  Built^[B].State:=2;
  Built^[B].Time:=TTime;
  Exit;
 End;
 If Not HasCmd Then Begin
  Built^[B].State:=2;
  Built^[B].Updated:=PreUpd Or(Phon And(Pre<>''));
  If TTime>0Then Built^[B].Time:=TTime
            Else Built^[B].Time:=NowPacked;
  If Built^[B].Updated Then AnyRebuild:=True;
  Exit;
 End;
 { variables automatiques }
 Newer:='';
 P:=1;
 While NextWord(Pre,P,W)Do Begin
  X:=FindBuilt(W);
  If(X>0)And((TTime=0)Or(Built^[X].Time>TTime)Or Built^[X].Updated)Then
   If Pos(' '+W+' ',' '+Newer+' ')=0Then Newer:=Newer+' '+W;
 End;
 AutoTarget:=T;
 AutoFirst:=First;
 AutoAll:=Trim(All);
 AutoPlus:=Trim(Plus);
 AutoNewer:=Trim(Newer);
 AutoStem:=Stem;
 AnyRebuild:=True;
 If OptQuestion Then Begin
  Built^[B].State:=2;
  Built^[B].Updated:=True;
  Built^[B].Time:=NowPacked;
  Exit;
 End;
 If OptTouch And Not Phon Then Begin
  If Not OptSilent Then WriteLn('touch ',T);
  If Not OptDry Then TouchFile(T);
 End
  Else
 Begin
  If Not RunRecipe(T,CFirst,CCnt)Then Begin
   Built^[B].State:=2;
   Built^[B].Failed:=True;
   ErrorsSeen:=True;
   If Not OptKeep Then Halt(2);
   UpdateTarget:=False;
   Exit;
  End;
 End;
 Built^[B].State:=2;
 Built^[B].Updated:=True;
 TTime:=FileTime(T);
 If OptDry Or(TTime=0)Or Phon Then TTime:=NowPacked;
 Built^[B].Time:=TTime;
End;

{ ------------------------- Base de donnees et initialisation ------------------------- }

Procedure PrintDb;
Var
 I,J:Integer;
 O:String;
Begin
 WriteLn('# Variables');
 WriteLn;
 For I:=1 to VarCnt Do Begin
  Case Vars^[I].Org of
   OrgDefault:O:='default';
   OrgEnv,OrgEnvOver:O:='environment';
   OrgFile:O:='makefile';
   OrgOverride:O:='override';
   Else O:='command line';
  End;
  WriteLn('# ',O);
  If Vars^[I].Simple Then WriteLn(Vars^[I].Name,' := ',Vars^[I].Val^)
                     Else WriteLn(Vars^[I].Name,' = ',Vars^[I].Val^);
 End;
 WriteLn;
 WriteLn('# Implicit Rules');
 For I:=1 to RuleCnt Do
  If Rules^[I].IsPat Then Begin
   WriteLn(Rules^[I].Targ,': ',Rules^[I].Pre^);
   For J:=Rules^[I].CFirst to Rules^[I].CFirst+Rules^[I].CCnt-1 Do WriteLn(Tab,Cmds[J]^);
  End;
 WriteLn;
 WriteLn('# Files');
 For I:=1 to PhonyCnt Do WriteLn('.PHONY: ',Phony[I]);
 For I:=1 to RuleCnt Do
  If Not Rules^[I].IsPat Then Begin
   Write(Rules^[I].Targ,':');
   If Rules^[I].Pre^<>''Then Write(' ',Rules^[I].Pre^);
   If Rules^[I].OrdPre^<>''Then Write(' | ',Rules^[I].OrdPre^);
   WriteLn;
   For J:=Rules^[I].CFirst to Rules^[I].CFirst+Rules^[I].CCnt-1 Do WriteLn(Tab,Cmds[J]^);
  End;
End;

Procedure BuiltinRule(Const T,Pre,Cmd:String);
Var
 Idx:Integer;
Begin
 Idx:=AddRule(T,Pre,'',True,True);
 If CmdCnt<MaxCmds Then Begin
  Inc(CmdCnt);
  Cmds[CmdCnt]:=NewPStr(Cmd);
  Rules^[Idx].CFirst:=CmdCnt;
  Rules^[Idx].CCnt:=1;
 End;
End;

Procedure InitBuiltins;
Var
 I:Integer;
 S,Shell:String;
Begin
 If Not OptNoVars Then Begin
  SetVar('CC','cc',False,OrgDefault);
  SetVar('CXX','g++',False,OrgDefault);
  SetVar('CPP','$(CC) -E',False,OrgDefault);
  SetVar('AS','as',False,OrgDefault);
  SetVar('AR','ar',False,OrgDefault);
  SetVar('ARFLAGS','rv',False,OrgDefault);
  SetVar('LD','ld',False,OrgDefault);
  SetVar('RM','rm -f',False,OrgDefault);
  SetVar('COMPILE.c','$(CC) $(CFLAGS) $(CPPFLAGS) $(TARGET_ARCH) -c',False,OrgDefault);
  SetVar('COMPILE.cc','$(CXX) $(CXXFLAGS) $(CPPFLAGS) $(TARGET_ARCH) -c',False,OrgDefault);
  SetVar('COMPILE.s','$(AS) $(ASFLAGS) $(TARGET_MACH)',False,OrgDefault);
  SetVar('LINK.o','$(CC) $(LDFLAGS) $(TARGET_ARCH)',False,OrgDefault);
  SetVar('LINK.c','$(CC) $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) $(TARGET_ARCH)',False,OrgDefault);
  SetVar('OUTPUT_OPTION','-o $@',False,OrgDefault);
 End;
 SetVar('MAKE',ProgName,False,OrgDefault);
 SetVar('MAKELEVEL','0',False,OrgDefault);
 GetDir(0,S);
 SetVar('CURDIR',S,True,OrgDefault);
 {$IFDEF UNIX}
 Shell:='/bin/sh';
 {$ELSE}
 Shell:=GetEnv('COMSPEC');
 {$ENDIF}
 SetVar('SHELL',Shell,False,OrgDefault);
 If Not OptNoRules Then Begin
  SuffixCnt:=0;
  AddSuffix('.out');AddSuffix('.a');AddSuffix('.ln');AddSuffix('.o');AddSuffix('.c');
  AddSuffix('.cc');AddSuffix('.C');AddSuffix('.cpp');AddSuffix('.p');AddSuffix('.f');
  AddSuffix('.s');AddSuffix('.S');AddSuffix('.h');AddSuffix('.y');AddSuffix('.l');
  BuiltinRule('%.o','%.c','$(COMPILE.c) $(OUTPUT_OPTION) $<');
  BuiltinRule('%.o','%.cc','$(COMPILE.cc) $(OUTPUT_OPTION) $<');
  BuiltinRule('%.o','%.cpp','$(COMPILE.cc) $(OUTPUT_OPTION) $<');
  BuiltinRule('%.o','%.C','$(COMPILE.cc) $(OUTPUT_OPTION) $<');
  BuiltinRule('%.o','%.s','$(COMPILE.s) -o $@ $<');
  BuiltinRule('%','%.o','$(LINK.o) $^ $(LOADLIBES) $(LDLIBS) -o $@');
  BuiltinRule('%','%.c','$(LINK.c) $^ $(LOADLIBES) $(LDLIBS) -o $@');
 End;
 { variables d'environnement }
 For I:=1 to EnvCount Do Begin
  S:=EnvStr(I);
  If Pos('=',S)>1Then Begin
   If OptEnvOver Then SetVar(Copy(S,1,Pos('=',S)-1),Copy(S,Pos('=',S)+1,255),False,OrgEnvOver)
                 Else SetVar(Copy(S,1,Pos('=',S)-1),Copy(S,Pos('=',S)+1,255),False,OrgEnv);
  End;
 End;
End;

{ ------------------------- Options ------------------------- }

Var
 CmdVars:Array[1..30]Of PStr;
 CmdVarCnt:Integer;
 DirChanged:Boolean;
 WantVersion,WantHelp:Boolean;

Function LongToShort(Const N:String;Var Ch:Char):Boolean;
Const
 Names:Array[1..34]Of String[26]=('always-make','assume-new','assume-old','check-symlink-times',
  'debug','directory','dry-run','environment-overrides','file','makefile','ignore-errors',
  'include-dir','jobs','just-print','keep-going','load-average','new-file','no-builtin-rules',
  'no-builtin-variables','no-keep-going','old-file','print-data-base','print-directory',
  'question','quiet','recon','silent','stop','touch','version','what-if',
  'warn-undefined-variables','no-print-directory','help');
 Chars:String[34]='BWoLdCneffiIjnklWrRSopwqsnsStvWUNh';
Var
 I,Cnt,Found:Integer;
Begin
 LongToShort:=False;
 Cnt:=0;
 Found:=0;
 For I:=1 to 34Do Begin
  If Names[I]=N Then Begin
   Ch:=Chars[I];
   LongToShort:=True;
   Exit;
  End;
  If(Length(N)>0)And(Copy(Names[I],1,Length(N))=N)Then Begin
   Inc(Cnt);
   Found:=I;
  End;
 End;
 If Cnt=1Then Begin
  Ch:=Chars[Found];
  LongToShort:=True;
 End;
End;

Procedure ApplyOption(Ch:Char;Const V:String);
Begin
 Case Ch of
  'B':OptAlways:=True;
  'W':If AssumeNewCnt<MaxAssume Then Begin
   Inc(AssumeNewCnt);
   AssumeNew[AssumeNewCnt]:=Copy(V,1,127);
  End;
  'o':If AssumeOldCnt<MaxAssume Then Begin
   Inc(AssumeOldCnt);
   AssumeOld[AssumeOldCnt]:=Copy(V,1,127);
  End;
  'L','b','m','j','l','z','y':;
  'd':OptDebug:=True;
  'C':Begin
   {$I-}ChDir(V);{$I+}
   If IOResult<>0Then Begin
    Warn('*** impossible de changer de repertoire: '+V);
    Halt(2);
   End;
   DirChanged:=True;
  End;
  'n':OptDry:=True;
  'e':OptEnvOver:=True;
  'f':If MakeFileCnt<MaxFiles Then Begin
   Inc(MakeFileCnt);
   MakeFiles[MakeFileCnt]:=Copy(V,1,127);
  End;
  'i':OptIgnore:=True;
  'I':If IncDirCnt<MaxDirs Then Begin
   Inc(IncDirCnt);
   IncDirs[IncDirCnt]:=Copy(V,1,127);
  End;
  'k':OptKeep:=True;
  'r':OptNoRules:=True;
  'R':Begin
   OptNoVars:=True;
   OptNoRules:=True;
  End;
  'S':OptKeep:=False;
  'p':OptPrintDb:=True;
  'w':OptPrintDir:=True;
  'N':OptNoPrintDir:=True;
  'q':OptQuestion:=True;
  's':OptSilent:=True;
  't':OptTouch:=True;
  'v':WantVersion:=True;
  'U':OptWarnUndef:=True;
  'h':WantHelp:=True;
 End;
End;

Function AllDigits(Const S:String):Boolean;
Var
 I:Integer;
Begin
 AllDigits:=S<>'';
 For I:=1 to Length(S)Do If Not(S[I]In['0'..'9','.'])Then AllDigits:=False;
End;

Procedure ParseArgs;
Var
 I,J,Eq:Integer;
 A,V,Name:String;
 Ch:Char;
Begin
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(A='/?')Then WantHelp:=True
  Else If Copy(A,1,2)='--'Then Begin
   Eq:=Pos('=',A);
   If Eq>0Then Begin
    Name:=Copy(A,3,Eq-3);
    V:=Copy(A,Eq+1,255);
   End
    Else
   Begin
    Name:=Copy(A,3,255);
    V:='';
   End;
   If Not LongToShort(Name,Ch)Then Begin
    WriteLn('make: unrecognized option ''',A,'''');
    ShowUsage;
    Halt(2);
   End;
   If(Ch In['f','C','I','o','W'])And(Eq=0)Then Begin
    Inc(I);
    If I<=ParamCount Then V:=ParamStr(I);
   End;
   If Name='no-print-directory'Then Ch:='N';
   If Name='warn-undefined-variables'Then Ch:='U';
   ApplyOption(Ch,V);
  End
  Else If(Copy(A,1,2)='+f')Then Begin
   V:=Copy(A,3,255);
   If V=''Then Begin
    Inc(I);
    If I<=ParamCount Then V:=ParamStr(I);
   End;
   ApplyOption('f',V);
  End
  Else If(Length(A)>1)And(A[1]='-')Then Begin
   J:=2;
   While J<=Length(A)Do Begin
    Ch:=A[J];
    Inc(J);
    If Ch In['f','C','I','o','W']Then Begin
     V:=Copy(A,J,255);
     If V=''Then Begin
      Inc(I);
      If I<=ParamCount Then V:=ParamStr(I);
     End;
     ApplyOption(Ch,V);
     J:=Length(A)+1;
    End
    Else If Ch In['j','l']Then Begin
     V:=Copy(A,J,255);
     If(V='')And(I<ParamCount)And AllDigits(ParamStr(I+1))Then Inc(I);
     J:=Length(A)+1;
    End
    Else If Ch In['B','L','b','m','d','n','e','i','k','r','R','S','p','w','q','s','t','v','h']Then
     ApplyOption(Ch,'')
    Else Begin
     WriteLn('make: invalid option -- ''',Ch,'''');
     ShowUsage;
     Halt(2);
    End;
   End;
  End
  Else If Pos('=',A)>1Then Begin
   If CmdVarCnt<30Then Begin
    Inc(CmdVarCnt);
    CmdVars[CmdVarCnt]:=NewPStr(A);
   End;
  End
  Else Begin
   If GoalCnt<MaxGoals Then Begin
    Inc(GoalCnt);
    Goals[GoalCnt]:=Copy(A,1,127);
   End;
  End;
  Inc(I);
 End;
End;

Var
 I,K:Integer;
 Cwd:String;
 Found:Boolean;
 L:String;

BEGIN
 ProgName:=ParamStr(0);
 New(Vars);
 New(Rules);
 New(Built);
 IfActive[0]:=True;
 IfTop:=0;
 DefaultGoal:='';
 ParseArgs;
 If WantHelp Then Begin
  ShowHelp;
  Halt(0);
 End;
 If WantVersion Then Begin
  WriteLn('GNU Make 4.4 (clone)');
  WriteLn('Ce programme est un clone ecrit en Pascal.');
  Halt(0);
 End;
 InitBuiltins;
 For I:=1 to CmdVarCnt Do Begin
  L:=CmdVars[I]^;
  K:=Pos('=',L);
  If(K>1)And(L[K-1]=':')Then SetVar(Trim(Copy(L,1,K-2)),Expand(Copy(L,K+1,255),0),True,OrgCmd)
                        Else SetVar(Trim(Copy(L,1,K-1)),Copy(L,K+1,255),False,OrgCmd);
 End;
 GetDir(0,Cwd);
 If(DirChanged Or OptPrintDir)And Not OptNoPrintDir Then Begin
  WriteLn('make: Entering directory ''',Cwd,'''');
  OptPrintDir:=True;
 End;
 { lecture des makefiles }
 Found:=False;
 If MakeFileCnt=0Then Begin
  If FileTime('GNUmakefile')>0Then Begin
   MakeFileCnt:=1;
   MakeFiles[1]:='GNUmakefile';
  End
  Else If FileTime('makefile')>0Then Begin
   MakeFileCnt:=1;
   MakeFiles[1]:='makefile';
  End
  Else If FileTime('Makefile')>0Then Begin
   MakeFileCnt:=1;
   MakeFiles[1]:='Makefile';
  End;
 End;
 For I:=1 to MakeFileCnt Do Begin
  ParseFile(MakeFiles[I],0,False);
  Found:=True;
 End;
 If(Not Found)And(GoalCnt=0)Then Die('No targets specified and no makefile found.  Stop.');
 If GoalCnt=0Then Begin
  If DefaultGoal=''Then Die('No targets.  Stop.');
  GoalCnt:=1;
  Goals[1]:=DefaultGoal;
 End;
 { MAKECMDGOALS }
 L:='';
 For I:=1 to GoalCnt Do L:=L+' '+Goals[I];
 SetVar('MAKECMDGOALS',Trim(L),True,OrgDefault);
 If OptPrintDb Then PrintDb;
 AnyRebuild:=False;
 For I:=1 to GoalCnt Do Begin
  Dummy:=0;
  K:=FindBuilt(Goals[I]);
  DidRun:=False;
  If UpdateTarget(Goals[I],'',0)Then Begin
   K:=FindBuilt(Goals[I]);
   If(K>0)And Not Built^[K].Updated And Not OptQuestion Then Begin
    If FindExplicit(Goals[I])>0Then Begin
     If Rules^[FindExplicit(Goals[I])].CCnt>0Then Warn('''' + Goals[I] + ''' is up to date.')
                                              Else Warn('Nothing to be done for ''' + Goals[I] + '''.');
    End
     Else
    Warn('''' + Goals[I] + ''' is up to date.');
   End;
  End;
 End;
 If OptPrintDir Then WriteLn('make: Leaving directory ''',Cwd,'''');
 If ErrorsSeen Then Halt(2);
 If OptQuestion And AnyRebuild Then Halt(1);
END.
