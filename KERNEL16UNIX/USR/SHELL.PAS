{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: Interpreteur de commandes UNIX de LINUX-0 (/bin/sh), dans
   l'esprit du Bourne shell de UNIX V7 (sous-ensemble) :
   - commandes simples cherchees dans PATH, fichiers de commandes (un
     executable qui n'est ni COFF ni MZ est lu par sh);
   - guillemets '...', "...", \c; variables $NOM (ou entre accolades), $?, $$, $!, $#,
     $0..$9, $*; NOM=valeur (avant une commande : pour elle seule);
   - motifs * ? [a-z] [!...] dans le dernier element d'un chemin;
   - redirections < > >> 2> 2>> 2>&1, tubes |, sequences ; et fin de ligne,
     arriere-plan &, conditions && et ||, commentaires #;
   - commandes internes : cd, exit, export, unset, set, wait, exec, umask,
     read, shift, . (lecture d'un fichier), : (ne fait rien).
   Signaux comme sh de V7 : l'interpreteur interactif intercepte SIGINT (la
   ligne en cours est abandonnee) et ignore SIGQUIT et SIGTERM; une commande
   au premier plan recoit SIGINT et SIGQUIT, une commande en arriere-plan les
   ignore. $? vaut le code de sortie, ou 128 + numero du signal.
   Usage : sh [-c commande | fichier [arguments]]; un shell de connexion
   (argv[0] commencant par "-") lit /etc/profile et $HOME/.profile.
   Compilation : LPC /X SHELL.PAS  -> /bin/sh
}

Program Shell;

{$I-}

{$M 8192,0,0}

Const
 MAXTOK=48;
 MAXW=64;
 MAXVAR=64;
 MAXJOB=16;
 { genres de jetons }
 tWord=0; tPipe=1; tAmp=2; tSemi=3; tAnd=4; tOr=5; tLess=6; tGreat=7;
 tDGreat=8; tErr=9; tDErr=10; tErrOut=11;
 SEP=#1;    { separation des champs d'une variable developpee }
 GLOBC=#2;  { joker hors guillemets (marque pour les motifs) }

Type
 TStr=String[79];

Var
 TokK:Array[1..MAXTOK]Of Byte;
 TokS:Array[1..MAXTOK]Of TStr;
 NTok:Integer;
 Words:Array[1..MAXW]Of TStr;
 NWords:Integer;
 VarName:Array[1..MAXVAR]Of String[31];
 VarVal:Array[1..MAXVAR]Of TStr;
 VarExp:Array[1..MAXVAR]Of Boolean;
 NVar:Integer;
 Pos0:Array[0..9]Of TStr;   { $0 a $9 }
 NPos:Integer;              { $# }
 Jobs:Array[1..MAXJOB]Of Integer;
 LastStatus,LastBg,I:Integer;
 Interactive,Intr,Done,LexErr:Boolean;
 InFd:Integer;
 InBuf:Array[0..511]Of Char;
 InPos,InLen:Integer;
 Line:String;

{ --- utilitaires ----------------------------------------------------- }

Function IStr(N:Longint):String;
Var S:String;
Begin
 Str(N,S); IStr:=S;
End;

Procedure Put(Fd:Integer;S:String);
Begin
 If Length(S)>0 Then SysWrite(Fd,S[1],Length(S));
End;

Procedure Err(S:String);
Begin
 Put(2,S+#10);
End;

Function Octal(N:Word):String;
Var S:String;
Begin
 S:='';
 Repeat S:=Chr(48+N And 7)+S; N:=N Shr 3 Until N=0;
 While Length(S)<3 Do S:='0'+S;
 Octal:=S;
End;

Procedure OnIntr(Sig:Integer);Far;
Begin
 Intr:=True;
 SysSignal(SIGINT,@OnIntr);   { V7 : l'action est remise a SIG_DFL }
End;

{ --- variables -------------------------------------------------------- }

Function FindVar(N:String):Integer;
Var K:Integer;
Begin
 FindVar:=0;
 For K:=1 To NVar Do If VarName[K]=N Then Begin FindVar:=K; Exit End;
End;

Function GetVar(N:String):String;
Var K:Integer;
Begin
 K:=FindVar(N);
 If K>0 Then GetVar:=VarVal[K] Else GetVar:='';
End;

Procedure SetVar(N,V:String;Exp:Boolean);
Var K:Integer;
Begin
 K:=FindVar(N);
 If K=0 Then Begin
  If NVar=MAXVAR Then Begin Err('sh: trop de variables'); Exit End;
  Inc(NVar); K:=NVar; VarName[K]:=N; VarExp[K]:=False;
 End;
 VarVal[K]:=V;
 If Exp Then VarExp[K]:=True;
End;

Procedure UnsetVar(N:String);
Var K:Integer;
Begin
 K:=FindVar(N);
 If K=0 Then Exit;
 VarName[K]:=VarName[NVar]; VarVal[K]:=VarVal[NVar]; VarExp[K]:=VarExp[NVar];
 Dec(NVar);
End;

Function IsName(S:String):Boolean;
Var K:Integer;
Begin
 IsName:=False;
 If (S='')Or(S[1]In['0'..'9'])Then Exit;
 For K:=1 To Length(S) Do
  If Not(S[K]In['A'..'Z','a'..'z','0'..'9','_'])Then Exit;
 IsName:=True;
End;

Function IsAssign(S:String):Boolean;
Var P:Integer;
Begin
 P:=Pos('=',S);
 IsAssign:=(P>1)And IsName(Copy(S,1,P-1));
End;

Function Special(C:Char):String;
{ $?, $$, $!, $#, $*, $@, $0..$9 }
Var S:String; K:Integer;
Begin
 Case C Of
  '?': Special:=IStr(LastStatus);
  '$': Special:=IStr(GetPid);
  '!': If LastBg>0 Then Special:=IStr(LastBg) Else Special:='';
  '#': Special:=IStr(NPos);
  '*','@': Begin
   S:='';
   For K:=1 To NPos Do Begin
    If K>1 Then S:=S+' ';
    If K<=9 Then S:=S+Pos0[K];
   End;
   Special:=S;
  End;
  '0'..'9': If Ord(C)-48<=NPos Then Special:=Pos0[Ord(C)-48] Else Special:='';
 End;
End;

{ --- lecture des lignes ---------------------------------------------- }

Function ReadLine(Var S:String):Boolean;
{ ligne suivante de InFd; Faux a la fin du fichier. Une interruption
  (SIGINT) abandonne la ligne en cours. }
Var C:Char; N:Integer;
Begin
 S:='';
 Repeat
  If InPos>=InLen Then Begin
   N:=SysRead(InFd,InBuf,SizeOf(InBuf));
   If N<0 Then Begin
    If Intr Then Begin S:=''; ReadLine:=True; Exit End;
    ReadLine:=S<>''; Exit;
   End;
   If N=0 Then Begin ReadLine:=S<>''; Exit End;
   InLen:=N; InPos:=0;
  End;
  C:=InBuf[InPos]; Inc(InPos);
  If C=#10 Then Begin ReadLine:=True; Exit End;
  If Length(S)<255 Then S:=S+C;
 Until False;
End;

{ --- analyse lexicale et developpement ------------------------------- }

Procedure AddTok(K:Byte;S:String);
Begin
 If NTok=MAXTOK Then Begin
  If Not LexErr Then Err('sh: ligne trop longue'); LexErr:=True; Exit;
 End;
 Inc(NTok); TokK[NTok]:=K; TokS[NTok]:=S;
End;

Procedure Lex(L:String);
{ decoupage de la ligne en jetons; les mots restent tels quels (guillemets
  compris) : ils sont developpes au moment d'executer leur commande }
Var P,Q:Integer; C:Char;
Begin
 NTok:=0; LexErr:=False; P:=1;
 While P<=Length(L) Do Begin
  C:=L[P];
  If C In[' ',#9] Then Begin Inc(P); Continue End;
  If C='#' Then Break;
  If C='|' Then Begin
   If (P<Length(L))And(L[P+1]='|') Then Begin AddTok(tOr,'||'); Inc(P,2) End
   Else Begin AddTok(tPipe,'|'); Inc(P) End;
   Continue;
  End;
  If C='&' Then Begin
   If (P<Length(L))And(L[P+1]='&') Then Begin AddTok(tAnd,'&&'); Inc(P,2) End
   Else Begin AddTok(tAmp,'&'); Inc(P) End;
   Continue;
  End;
  If C=';' Then Begin AddTok(tSemi,';'); Inc(P); Continue End;
  If C='<' Then Begin AddTok(tLess,'<'); Inc(P); Continue End;
  If C='>' Then Begin
   If (P<Length(L))And(L[P+1]='>') Then Begin AddTok(tDGreat,'>>'); Inc(P,2) End
   Else Begin AddTok(tGreat,'>'); Inc(P) End;
   Continue;
  End;
  If (C='2')And(P<Length(L))And(L[P+1]='>') Then Begin
   If Copy(L,P,4)='2>&1' Then Begin AddTok(tErrOut,'2>&1'); Inc(P,4) End
   Else If Copy(L,P,3)='2>>' Then Begin AddTok(tDErr,'2>>'); Inc(P,3) End
   Else Begin AddTok(tErr,'2>'); Inc(P,2) End;
   Continue;
  End;
  { mot : jusqu'a un separateur hors guillemets }
  Q:=P;
  While (P<=Length(L))And Not(L[P]In[' ',#9,'|','&',';','<','>']) Do Begin
   C:=L[P];
   If C='\' Then Inc(P,2)
   Else If (C='''')Or(C='"') Then Begin
    Inc(P);
    While (P<=Length(L))And(L[P]<>C) Do Begin
     If (C='"')And(L[P]='\') Then Inc(P);
     Inc(P);
    End;
    If P>Length(L) Then Begin Err('sh: '+C+' manquant'); LexErr:=True End;
    Inc(P);
   End Else Inc(P);
  End;
  If P>Length(L)+1 Then P:=Length(L)+1;
  AddTok(tWord,Copy(L,Q,P-Q));
 End;
End;

Function ExpandWord(L:String;Var Had:Boolean):String;
{ developpement d'un mot : \c, '...', "...", variables ($ hors guillemets :
  blancs de la valeur -> SEP, separation des champs), jokers hors
  guillemets precedes de GLOBC. Had : le mot contenait des guillemets
  (un mot vide entre guillemets reste un argument). }
Var P,K:Integer; W,N,V:String; C:Char;

 Procedure Expand(Quoted:Boolean);
 { $... a la position P (sur le $) }
 Begin
  Inc(P);
  If P>Length(L) Then Begin W:=W+'$'; Exit End;
  If L[P]='{' Then Begin
   N:=''; Inc(P);
   While (P<=Length(L))And(L[P]<>'}') Do Begin N:=N+L[P]; Inc(P) End;
   Inc(P);
   If (Length(N)=1)And(N[1]In['?','$','!','#','*','@','0'..'9']) Then V:=Special(N[1])
   Else V:=GetVar(N);
  End Else If L[P]In['?','$','!','#','*','@','0'..'9'] Then Begin
   V:=Special(L[P]); Inc(P);
  End Else If L[P]In['A'..'Z','a'..'z','_'] Then Begin
   N:='';
   While (P<=Length(L))And(L[P]In['A'..'Z','a'..'z','0'..'9','_']) Do Begin
    N:=N+L[P]; Inc(P);
   End;
   V:=GetVar(N);
  End Else Begin W:=W+'$'; Exit End;
  If Not Quoted Then
   For K:=1 To Length(V) Do If V[K]In[' ',#9] Then V[K]:=SEP;
  W:=W+V;
 End;

Begin
 W:=''; Had:=False; P:=1;
 While P<=Length(L) Do Begin
  C:=L[P];
  If C='\' Then Begin
   Inc(P); If P<=Length(L) Then W:=W+L[P]; Inc(P);
  End Else If C='''' Then Begin
   Inc(P); Had:=True;
   While (P<=Length(L))And(L[P]<>'''') Do Begin W:=W+L[P]; Inc(P) End;
   Inc(P);
  End Else If C='"' Then Begin
   Inc(P); Had:=True;
   While (P<=Length(L))And(L[P]<>'"') Do Begin
    If (L[P]='\')And(P<Length(L))And(L[P+1]In['$','"','\','`']) Then Begin
     W:=W+L[P+1]; Inc(P,2);
    End Else If L[P]='$' Then Expand(True)
    Else Begin W:=W+L[P]; Inc(P) End;
   End;
   Inc(P);
  End Else If C='$' Then Expand(False)
  Else Begin
   If C In['*','?','['] Then W:=W+GLOBC;
   W:=W+C; Inc(P);
  End;
 End;
 ExpandWord:=W;
End;

{ --- motifs (* ? [...]) ----------------------------------------------- }

Function Match(Pat,Name:String):Boolean;
 Function M(P,N:Integer):Boolean;
 Var Ok,Neg:Boolean; Lo:Char;
 Begin
  While P<=Length(Pat) Do Begin
   Case Pat[P] Of
    '*': Begin
     While (P<=Length(Pat))And(Pat[P]='*') Do Inc(P);
     If P>Length(Pat) Then Begin M:=True; Exit End;
     While N<=Length(Name) Do Begin
      If M(P,N) Then Begin M:=True; Exit End;
      Inc(N);
     End;
     M:=False; Exit;
    End;
    '?': Begin
     If N>Length(Name) Then Begin M:=False; Exit End;
     Inc(P); Inc(N);
    End;
    '[': Begin
     If N>Length(Name) Then Begin M:=False; Exit End;
     Inc(P); Neg:=False; Ok:=False;
     If (P<=Length(Pat))And(Pat[P]='!') Then Begin Neg:=True; Inc(P) End;
     While (P<=Length(Pat))And(Pat[P]<>']') Do Begin
      Lo:=Pat[P];
      If (P+2<=Length(Pat))And(Pat[P+1]='-')And(Pat[P+2]<>']') Then Begin
       If (Name[N]>=Lo)And(Name[N]<=Pat[P+2]) Then Ok:=True;
       Inc(P,3);
      End Else Begin
       If Name[N]=Lo Then Ok:=True;
       Inc(P);
      End;
     End;
     Inc(P);
     If Ok=Neg Then Begin M:=False; Exit End;
     Inc(N);
    End;
    Else Begin
     If (N>Length(Name))Or(Pat[P]<>Name[N]) Then Begin M:=False; Exit End;
     Inc(P); Inc(N);
    End;
   End;
  End;
  M:=N>Length(Name);
 End;
Begin
 Match:=M(1,1);
End;

Procedure AddWord(S:String);
Begin
 If NWords=MAXW Then Begin Err('sh: trop d''arguments'); Exit End;
 Inc(NWords); Words[NWords]:=S;
End;

Procedure Glob(W:String);
{ developpe le mot W (marques GLOBC devant les jokers non proteges) }
Var
 Dir,Pat,Lit,Name:String; K,Fd,N,Pos_,First,A,B:Integer; Has:Boolean;
 Buf:Array[0..511]Of Byte; T:TStr;
Begin
 Has:=Pos(GLOBC,W)>0;
 Lit:='';
 For K:=1 To Length(W) Do If W[K]<>GLOBC Then Lit:=Lit+W[K];
 If Not Has Then Begin AddWord(Lit); Exit End;
 K:=Length(Lit);
 While (K>0)And(Lit[K]<>'/') Do Dec(K);
 Dir:=Copy(Lit,1,K); Pat:=Copy(Lit,K+1,255);
 If (Pos('*',Dir)>0)Or(Pos('?',Dir)>0)Or(Pos('[',Dir)>0) Then Begin
  AddWord(Lit); Exit;   { jokers seulement dans le dernier element }
 End;
 If Dir='' Then Fd:=SysOpen('.',O_RDONLY,0) Else Fd:=SysOpen(Dir,O_RDONLY,0);
 If Fd<0 Then Begin AddWord(Lit); Exit End;
 First:=NWords+1;
 Repeat
  N:=SysGetDirEntries(Fd,Buf,SizeOf(Buf));
  Pos_:=0;
  While Pos_<N Do Begin
   Name:='';
   For K:=0 To Buf[Pos_+7]-1 Do Name:=Name+Chr(Buf[Pos_+8+K]);
   If (Name<>'.')And(Name<>'..')And((Name[1]<>'.')Or(Pat[1]='.')) Then
    If Match(Pat,Name) Then AddWord(Dir+Name);
   Inc(Pos_,Buf[Pos_+4]+Buf[Pos_+5]*256);
  End;
 Until N<=0;
 SysClose(Fd);
 If NWords<First Then Begin AddWord(Lit); Exit End;
 { tri par ordre alphabetique }
 For A:=First To NWords-1 Do
  For B:=A+1 To NWords Do
   If Words[B]<Words[A] Then Begin T:=Words[A]; Words[A]:=Words[B]; Words[B]:=T End;
End;

Procedure Fields(Raw:String);
{ developpement, separation des champs (variables developpees hors
  guillemets), puis motifs }
Var K:Integer; F,W:String; Had:Boolean;
Begin
 W:=ExpandWord(Raw,Had);
 If (W='')And Had Then Begin AddWord(''); Exit End;
 If Pos(SEP,W)=0 Then Begin If W<>'' Then Glob(W); Exit End;
 F:='';
 For K:=1 To Length(W) Do
  If W[K]=SEP Then Begin If F<>'' Then Glob(F); F:='' End
  Else F:=F+W[K];
 If F<>'' Then Glob(F);
End;

Function Plain(Raw:String):String;
{ mot developpe sans les marques (cible d'une redirection, affectation) }
Var K:Integer; S,W:String; Had:Boolean;
Begin
 W:=ExpandWord(Raw,Had);
 S:='';
 For K:=1 To Length(W) Do
  If W[K]=SEP Then S:=S+' ' Else If W[K]<>GLOBC Then S:=S+W[K];
 Plain:=S;
End;

{ --- execution -------------------------------------------------------- }

Type
 TCmd=Record
  First,Last:Integer;          { jetons de la commande }
  InF,OutF,ErrF:TStr;
  OutApp,ErrApp,ErrOut:Boolean;
  AFirst,ACount:Integer;       { affectations : Words[AFirst..] }
  WFirst,WCount:Integer;       { mots de la commande : Words[WFirst..] }
 End;

Var
 Cmds:Array[1..8]Of TCmd;

Function Prepare(A,B:Integer;Var C:TCmd):Boolean;
{ jetons A..B -> redirections, affectations et mots developpes }
Var K:Integer; InCmd:Boolean;
Begin
 Prepare:=False;
 C.First:=A; C.Last:=B; C.InF:=''; C.OutF:=''; C.ErrF:='';
 C.OutApp:=False; C.ErrApp:=False; C.ErrOut:=False;
 C.AFirst:=NWords+1; C.ACount:=0; InCmd:=False;
 K:=A;
 While K<=B Do Begin
  Case TokK[K] Of
   tWord: If Not InCmd And IsAssign(TokS[K]) Then Begin
     AddWord(Plain(TokS[K])); Inc(C.ACount);
    End Else Begin
     If Not InCmd Then C.WFirst:=NWords+1;
     InCmd:=True; Fields(TokS[K]);
    End;
   tErrOut: C.ErrOut:=True;
   tLess,tGreat,tDGreat,tErr,tDErr: Begin
     If (K=B)Or(TokK[K+1]<>tWord) Then Begin
      Err('sh: erreur de syntaxe pres de '+TokS[K]); Exit;
     End;
     Case TokK[K] Of
      tLess: C.InF:=Plain(TokS[K+1]);
      tGreat,tDGreat: Begin C.OutF:=Plain(TokS[K+1]); C.OutApp:=TokK[K]=tDGreat End;
      tErr,tDErr: Begin C.ErrF:=Plain(TokS[K+1]); C.ErrApp:=TokK[K]=tDErr End;
     End;
     Inc(K);
    End;
  End;
  Inc(K);
 End;
 If InCmd Then C.WCount:=NWords-C.WFirst+1 Else Begin C.WFirst:=NWords+1; C.WCount:=0 End;
 Prepare:=True;
End;

Function Redirect(Var C:TCmd):Boolean;
{ redirections de C appliquees au processus courant }
Var Fd:Integer;
Begin
 Redirect:=False;
 If C.InF<>'' Then Begin
  Fd:=SysOpen(C.InF,O_RDONLY,0);
  If Fd<0 Then Begin Err(C.InF+': '+SysErrorText(Errno)); Exit End;
  SysDup2(Fd,0); SysClose(Fd);
 End;
 If C.OutF<>'' Then Begin
  If C.OutApp Then Fd:=SysOpen(C.OutF,O_WRONLY Or O_CREAT Or O_APPEND,$1B6)
  Else Fd:=SysCreat(C.OutF,$1B6);
  If Fd<0 Then Begin Err(C.OutF+': '+SysErrorText(Errno)); Exit End;
  SysDup2(Fd,1); SysClose(Fd);
 End;
 If C.ErrOut Then SysDup2(1,2);
 If C.ErrF<>'' Then Begin
  If C.ErrApp Then Fd:=SysOpen(C.ErrF,O_WRONLY Or O_CREAT Or O_APPEND,$1B6)
  Else Fd:=SysCreat(C.ErrF,$1B6);
  If Fd<0 Then Begin Err(C.ErrF+': '+SysErrorText(Errno)); Exit End;
  SysDup2(Fd,2); SysClose(Fd);
 End;
 Redirect:=True;
End;

Function FindAssign(N:String;Var C:TCmd):Integer;
{ affectation de N parmi celles de la commande C }
Var K:Integer;
Begin
 FindAssign:=0;
 For K:=0 To C.ACount-1 Do
  If Copy(Words[C.AFirst+K],1,Length(N)+1)=N+'=' Then FindAssign:=K+1;
End;

Procedure BuildArgv(Var C:TCmd;Script:String);
{ argv (et le fichier de commandes s'il y a lieu) et environnement :
  variables exportees, puis affectations de la commande }
Var K:Integer;
Begin
 ArgReset;
 If Script<>'' Then Begin ArgAdd('sh'); ArgAdd(Script) End
 Else ArgAdd(Words[C.WFirst]);
 For K:=1 To C.WCount-1 Do ArgAdd(Words[C.WFirst+K]);
 For K:=1 To NVar Do
  If VarExp[K] And(FindAssign(VarName[K],C)=0) Then EnvAdd(VarName[K]+'='+VarVal[K]);
 For K:=0 To C.ACount-1 Do EnvAdd(Words[C.AFirst+K]);
End;

Procedure TryExec(Var C:TCmd;Path:String);
{ exece; un fichier executable qui n'est pas un programme est un fichier
  de commandes, lu par /bin/sh (comme sous UNIX V7) }
Begin
 BuildArgv(C,''); ArgExec(Path);
 If Errno=ENOEXEC Then Begin
  BuildArgv(C,Path); ArgExec('/bin/sh'); Errno:=ENOEXEC;
 End;
End;

Procedure ChildExec(Var C:TCmd;Bg:Boolean;PIn,POut,PClose:Integer);
{ dans le fils (vfork) : tubes, signaux, redirections, recherche dans PATH
  et exec. Ne revient jamais. Le fils partage la memoire du pere : il ne
  modifie que ses propres variables locales. }
Var Name,Path,Dirs,D:String; K,E,Fd:Integer;
Begin
 If PIn>=0 Then Begin SysDup2(PIn,0); SysClose(PIn) End;
 If POut>=0 Then Begin SysDup2(POut,1); SysClose(POut) End;
 If PClose>=0 Then SysClose(PClose);
 If Bg Then Begin
  SysSignal(SIGINT,SIG_IGN); SysSignal(SIGQUIT,SIG_IGN);
  If (PIn<0)And(C.InF='') Then Begin
   Fd:=SysOpen('/dev/null',O_RDONLY,0);
   If Fd>=0 Then Begin SysDup2(Fd,0); SysClose(Fd) End;
  End;
 End Else Begin
  SysSignal(SIGINT,SIG_DFL); SysSignal(SIGQUIT,SIG_DFL);
 End;
 SysSignal(SIGTERM,SIG_DFL);
 If Not Redirect(C) Then SysExit(1);
 If C.WCount=0 Then SysExit(0);
 Name:=Words[C.WFirst];
 If Pos('/',Name)>0 Then Begin TryExec(C,Name); E:=Errno End
 Else Begin
  If FindVar('PATH')=0 Then Dirs:='/bin:/usr/bin' Else Dirs:=GetVar('PATH');
  E:=ENOENT;
  Repeat
   K:=Pos(':',Dirs);
   If K=0 Then Begin D:=Dirs; Dirs:='' End
   Else Begin D:=Copy(Dirs,1,K-1); Delete(Dirs,1,K) End;
   If D='' Then Path:=Name Else Path:=D+'/'+Name;
   TryExec(C,Path);
   If Errno<>ENOENT Then E:=Errno;
  Until K=0;
 End;
 If E=ENOENT Then Begin Err(Name+': introuvable'); SysExit(127) End;
 Err(Name+': '+SysErrorText(E));
 SysExit(126);
End;

Function StatusOf(Pid,St:Integer;Bg:Boolean):Integer;
{ $? : code de sortie, ou 128 + signal (message comme sh de V7) }
Var M:String;
Begin
 If WTermSig(St)<>0 Then Begin
  M:=SigName(WTermSig(St));
  If WCoreDump(St) Then M:=M+' (core)';
  If M<>'' Then Begin
   If Bg Then Err(IStr(Pid)+': '+M) Else Err(M);
  End;
  StatusOf:=128+WTermSig(St);
 End Else StatusOf:=WExitStatus(St);
End;

Procedure Forget(Pid:Integer);
Var K:Integer;
Begin
 For K:=1 To MAXJOB Do If Jobs[K]=Pid Then Jobs[K]:=0;
End;

Procedure Remember(Pid:Integer);
Var K:Integer;
Begin
 For K:=1 To MAXJOB Do If Jobs[K]=0 Then Begin Jobs[K]:=Pid; Exit End;
End;

Function IsJob(Pid:Integer):Boolean;
Var K:Integer;
Begin
 IsJob:=False;
 For K:=1 To MAXJOB Do If (Pid>0)And(Jobs[K]=Pid) Then IsJob:=True;
End;

Procedure Reap;
{ commandes en arriere-plan terminees }
Var W,St,X:Integer;
Begin
 Repeat
  W:=WaitPid(-1,St,WNOHANG);
  If W>0 Then Begin X:=StatusOf(W,St,True); Forget(W) End;
 Until W<=0;
End;

Function WaitJobs(Pid:Integer):Integer;
{ commande interne wait : un processus, ou toutes les commandes lancees en
  arriere-plan }
Var W,St,R:Integer;
Begin
 R:=0;
 Repeat
  W:=WaitPid(-1,St,0);
  If W>0 Then Begin
   If IsJob(W) Or (W=Pid) Then R:=StatusOf(W,St,True);
   Forget(W);
   If W=Pid Then Break;
  End;
 Until (W<0)And(Errno<>EINTR) Or Intr;
 WaitJobs:=R;
End;

Procedure RunLine(L:String);Forward;

Procedure RunFile(Path:String;Quiet:Boolean);
{ lecture et execution des lignes d'un fichier de commandes }
Var F:Text; S:String;
Begin
 Assign(F,Path); Reset(F);
 If IOResult<>0 Then Begin
  If Not Quiet Then Begin Err(Path+': impossible d''ouvrir'); LastStatus:=2 End;
  Exit;
 End;
 While Not EOF(F) And Not Done Do Begin
  ReadLn(F,S);
  If IOResult<>0 Then Break;
  RunLine(S);
 End;
 Close(F);
End;

Function ParseOct(S:String;Var N:Word):Boolean;
Var K:Integer;
Begin
 ParseOct:=False; N:=0;
 If S='' Then Exit;
 For K:=1 To Length(S) Do Begin
  If Not(S[K]In['0'..'7']) Then Exit;
  N:=N*8+Ord(S[K])-48;
 End;
 ParseOct:=True;
End;

Function IsBuiltin(Var C:TCmd):Boolean;
Var N:String;
Begin
 IsBuiltin:=False;
 If C.WCount=0 Then Exit;
 N:=Words[C.WFirst];
 IsBuiltin:=(N='cd')Or(N='exit')Or(N='export')Or(N='unset')Or(N='set')Or
   (N='wait')Or(N='exec')Or(N='umask')Or(N='read')Or(N='shift')Or
   (N='.')Or(N=':');
End;

Function ReadVars(Var C:TCmd):Integer;
{ read NOM... : une ligne de l'entree standard, un mot par variable, le
  reste de la ligne dans la derniere }
Var S,W:String; Ch:Char; K,N,P:Integer;
Begin
 S:='';
 Repeat
  N:=SysRead(0,Ch,1);
  If (N<=0)Or(Ch=#10) Then Break;
  If Length(S)<255 Then S:=S+Ch;
 Until False;
 For K:=1 To C.WCount-1 Do Begin
  While (S<>'')And(S[1]In[' ',#9]) Do Delete(S,1,1);
  If K=C.WCount-1 Then W:=S
  Else Begin
   P:=1; While (P<=Length(S))And Not(S[P]In[' ',#9]) Do Inc(P);
   W:=Copy(S,1,P-1); Delete(S,1,P-1);
  End;
  SetVar(Words[C.WFirst+K],W,False);
 End;
 If (N<=0)And(S='') Then ReadVars:=1 Else ReadVars:=0;
End;

Function Builtin(Var C:TCmd):Integer;
Var N,A,D:String; K,E,P:Integer; M:Word;
Begin
 Builtin:=0;
 N:=Words[C.WFirst];
 If C.WCount>1 Then A:=Words[C.WFirst+1] Else A:='';
 If N='cd' Then Begin
  If A='' Then D:=GetVar('HOME') Else D:=A;
  If D='' Then D:='/';
  If SysChdir(D)<0 Then Begin
   Err('cd: '+D+': '+SysErrorText(Errno)); Builtin:=1;
  End;
 End Else If N='exit' Then Begin
  Done:=True;
  If A<>'' Then Begin Val(A,K,E); If E=0 Then LastStatus:=K End;
  Builtin:=LastStatus;
 End Else If N='export' Then Begin
  If C.WCount=1 Then Begin
   For K:=1 To NVar Do If VarExp[K] Then WriteLn('export ',VarName[K],'=',VarVal[K]);
  End Else
   For K:=1 To C.WCount-1 Do Begin
    D:=Words[C.WFirst+K]; P:=Pos('=',D);
    If P>0 Then SetVar(Copy(D,1,P-1),Copy(D,P+1,255),True)
    Else If IsName(D) Then SetVar(D,GetVar(D),True);
   End;
 End Else If N='unset' Then Begin
  For K:=1 To C.WCount-1 Do UnsetVar(Words[C.WFirst+K]);
 End Else If N='set' Then Begin
  For K:=1 To NVar Do WriteLn(VarName[K],'=',VarVal[K]);
 End Else If N='wait' Then Begin
  If A<>'' Then Begin Val(A,K,E); Builtin:=WaitJobs(K) End
  Else Builtin:=WaitJobs(0);
 End Else If N='exec' Then Begin
  If C.WCount=1 Then Begin
   If Not Redirect(C) Then Builtin:=1;
  End Else Begin
   C.WFirst:=C.WFirst+1; C.WCount:=C.WCount-1;
   ChildExec(C,False,-1,-1,-1);
  End;
 End Else If N='umask' Then Begin
  If A='' Then Begin
   M:=SysUmask(0); SysUmask(M); WriteLn(Octal(M));
  End Else If ParseOct(A,M) Then SysUmask(M)
  Else Begin Err('umask: '+A+' : valeur octale attendue'); Builtin:=1 End;
 End Else If N='read' Then Builtin:=ReadVars(C)
 Else If N='shift' Then Begin
  If NPos>0 Then Begin
   For K:=1 To 8 Do Pos0[K]:=Pos0[K+1];
   Pos0[9]:='';
   Dec(NPos);
  End;
 End Else If N='.' Then Begin
  If A='' Then Begin Err('.: nom de fichier attendu'); Builtin:=2 End
  Else Begin RunFile(A,False); Builtin:=LastStatus End;
 End;
End;

Function RunPipeline(A,B:Integer;Bg:Boolean):Integer;
Var
 N,K,J,S,Pid,PIn,Fd0,Fd1,W,St,Left,Save,LastSt:Integer;
 Pids:Array[1..8]Of Integer;
Begin
 RunPipeline:=0;
 Save:=NWords; N:=0; S:=A;
 For K:=A To B+1 Do
  If (K>B)Or(TokK[K]=tPipe) Then Begin
   If (K=S)Or(N=8) Then Begin
    Err('sh: erreur de syntaxe pres de |'); NWords:=Save; RunPipeline:=2; Exit;
   End;
   Inc(N);
   If Not Prepare(S,K-1,Cmds[N]) Then Begin NWords:=Save; RunPipeline:=2; Exit End;
   S:=K+1;
  End;
 If (N=1)And Not Bg Then Begin
  If IsBuiltin(Cmds[1]) Then Begin
   RunPipeline:=Builtin(Cmds[1]); NWords:=Save; Exit;
  End;
  If (Cmds[1].WCount=0)And(Cmds[1].ACount>0) Then Begin
   { NOM=valeur seul : variable de l'interpreteur }
   For K:=0 To Cmds[1].ACount-1 Do Begin
    J:=Pos('=',Words[Cmds[1].AFirst+K]);
    SetVar(Copy(Words[Cmds[1].AFirst+K],1,J-1),
      Copy(Words[Cmds[1].AFirst+K],J+1,255),False);
   End;
   NWords:=Save; Exit;
  End;
 End;
 PIn:=-1; Left:=0; LastSt:=0;
 For K:=1 To N Do Begin
  If K<N Then Begin
   If SysPipe(Fd0,Fd1)<0 Then Begin
    Err('sh: tube impossible : '+SysErrorText(Errno)); Fd0:=-1; Fd1:=-1;
   End;
  End Else Begin Fd0:=-1; Fd1:=-1 End;
  Pid:=VFork;
  If Pid=0 Then ChildExec(Cmds[K],Bg,PIn,Fd1,Fd0);
  If Pid<0 Then Err('sh: fork impossible : '+SysErrorText(Errno))
  Else Inc(Left);
  If PIn>=0 Then SysClose(PIn);
  If Fd1>=0 Then SysClose(Fd1);
  PIn:=Fd0;
  Pids[K]:=Pid;
 End;
 NWords:=Save;
 If Bg Then Begin
  For K:=1 To N Do If Pids[K]>0 Then Remember(Pids[K]);
  LastBg:=Pids[N];
  If Interactive Then WriteLn(Pids[N]);
  Exit;
 End;
 While Left>0 Do Begin
  W:=WaitPid(-1,St,0);
  If W<0 Then Begin If Errno=EINTR Then Continue; Break End;
  J:=0;
  For K:=1 To N Do If Pids[K]=W Then J:=K;
  If J=0 Then Begin K:=StatusOf(W,St,True); Forget(W) End
  Else Begin
   Dec(Left); Pids[J]:=0;
   If J=N Then LastSt:=StatusOf(W,St,False);
  End;
 End;
 RunPipeline:=LastSt;
End;

Var LexGen:Integer;

Procedure RunLine(L:String);
Var I,J,Gen:Integer; Run:Boolean;
Begin
 Lex(L); Inc(LexGen); Gen:=LexGen;
 If LexErr Then Begin LastStatus:=2; Exit End;
 I:=1; Run:=True;
 While I<=NTok Do Begin
  J:=I; While (J<=NTok)And Not(TokK[J]In[tSemi,tAmp,tAnd,tOr]) Do Inc(J);
  If J>I Then Begin
   If Run Then Begin
    LastStatus:=RunPipeline(I,J-1,(J<=NTok)And(TokK[J]=tAmp));
    { une commande interne (.) a pu analyser d'autres lignes }
    If LexGen<>Gen Then Begin Lex(L); Inc(LexGen); Gen:=LexGen End;
   End;
  End Else If (J<=NTok)And((TokK[J]<>tSemi)Or(J<NTok)) Then Begin
   Err('sh: erreur de syntaxe pres de '+TokS[J]); LastStatus:=2; Exit;
  End;
  If Done Then Exit;
  Run:=True;
  If J<=NTok Then Case TokK[J] Of
   tAnd: Run:=LastStatus=0;
   tOr: Run:=LastStatus<>0;
  End;
  I:=J+1;
 End;
End;

Function Prompt:String;
Begin
 If FindVar('PS1')>0 Then Prompt:=GetVar('PS1')
 Else If GetEUid=0 Then Prompt:='# ' Else Prompt:='$ ';
End;

Var
 S:String; K,P:Integer; Login:Boolean;

BEGIN
 NVar:=0; NWords:=0; LastStatus:=0; LastBg:=0; Done:=False; LexGen:=0;
 For K:=1 To MAXJOB Do Jobs[K]:=0;
 For K:=0 To EnvCount-1 Do Begin
  S:=EnvStr(K); P:=Pos('=',S);
  If P>1 Then SetVar(Copy(S,1,P-1),Copy(S,P+1,255),True);
 End;
 If FindVar('PATH')=0 Then SetVar('PATH','/bin:/usr/bin',True);
 For K:=0 To 9 Do Pos0[K]:='';
 Pos0[0]:=ArgStr(0); NPos:=0;
 Login:=(Pos0[0]<>'')And(Pos0[0][1]='-');
 InFd:=0; InPos:=0; InLen:=0;
 If (ArgCount>2)And(ArgStr(1)='-c') Then Begin
  For K:=3 To ArgCount-1 Do If K-3<=9 Then Pos0[K-3]:=ArgStr(K);
  If ArgCount>3 Then NPos:=ArgCount-4;
  RunLine(ArgStr(2));
  SysExit(LastStatus);
 End;
 If ArgCount>1 Then Begin
  { fichier de commandes : $0 = son nom, $1... = les arguments }
  For K:=1 To ArgCount-1 Do If K-1<=9 Then Pos0[K-1]:=ArgStr(K);
  NPos:=ArgCount-2;
  RunFile(ArgStr(1),False);
  SysExit(LastStatus);
 End;
 Interactive:=IsATty(0);
 If Interactive Then Begin
  SysSignal(SIGINT,@OnIntr);
  SysSignal(SIGQUIT,SIG_IGN); SysSignal(SIGTERM,SIG_IGN);
 End;
 If Login Then Begin
  RunFile('/etc/profile',True);
  If GetVar('HOME')<>'' Then RunFile(GetVar('HOME')+'/.profile',True);
 End;
 While Not Done Do Begin
  Reap;
  If Interactive Then Put(2,Prompt);
  Intr:=False;
  If Not ReadLine(Line) Then Break;
  If Intr Then Begin InPos:=InLen; Continue End;
  RunLine(Line);
 End;
 SysExit(LastStatus);
END.
