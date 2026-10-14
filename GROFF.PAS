{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande groff - Formateur de documents (troff simplifie)
}

Program GROFF;

{$X+}
{$M 32768,0,655360}

Uses DOS;

Const
 MaxRegs=200;
 MaxStrs=150;
 MaxMacs=60;
 MaxMacLines=120;
 MaxFrames=12;
 MaxWords=100;
 MaxDirs=16;
 MaxFiles=32;
 MaxIe=16;
 UW=24;     { largeur d'un caractere, en unites (10 cpi a 240 dpi) }
 UH=40;     { hauteur d'une ligne, en unites (6 lpi) }
 UI=240;    { unites par pouce }
 BuiltinCount=51;

Type
 PStr=^String;
 TMac=Record
  NL:Integer;
  L:Array[1..MaxMacLines]Of PStr;
 End;
 PMac=^TMac;
 TFrame=Record
  Kind:Integer;       { 0 fichier, 1 macro, 2 macro interne }
  F:Text;
  Mac:PMac;
  Idx,Cnt:Integer;
  NA:Integer;
  A:Array[0..9]Of String[100];
  AllArgs:String[200];
 End;

Const
 { Macros man minimales integrees }
 Builtin:Array[1..BuiltinCount]Of String[60]=(
  '.de TH',
  '.sp 1',
  '.tl ''\\$1(\\$2)''\\$3''\\$1(\\$2)''',
  '.sp 1',
  '..',
  '.de SH',
  '.sp 1',
  '.in 0',
  '.ti 0',
  '\\$*',
  '.br',
  '.in 7n',
  '..',
  '.de SS',
  '.sp 1',
  '.in 3n',
  '\\$*',
  '.br',
  '.in 7n',
  '..',
  '.de PP',
  '.br',
  '.sp 1',
  '.in 7n',
  '..',
  '.de LP',
  '.PP',
  '..',
  '.de P',
  '.PP',
  '..',
  '.de B',
  '\\$*',
  '..',
  '.de I',
  '\\$*',
  '..',
  '.de BR',
  '\\$1\\$2\\$3\\$4\\$5\\$6',
  '..',
  '.de TP',
  '.br',
  '.sp 1',
  '.in 7n',
  '..',
  '.de RS',
  '.in +7n',
  '..',
  '.de RE',
  '.in -7n',
  '..');

Var
 RegName:Array[1..MaxRegs]Of String[15];
 RegVal,RegInc:Array[1..MaxRegs]Of Longint;
 RegCnt:Integer;
 StrName:Array[1..MaxStrs]Of String[15];
 StrVal:Array[1..MaxStrs]Of PStr;
 StrCnt:Integer;
 MacName:Array[1..MaxMacs]Of String[15];
 MacBody:Array[1..MaxMacs]Of PMac;
 MacCnt:Integer;
 Fr:Array[1..MaxFrames]Of TFrame;
 FTop:Integer;
 IeStack:Array[1..MaxIe]Of Boolean;
 IeTop:Integer;
 Dev:String[15];
 OptSupp,OptZZ,OptA,OptV,OptVer,OptI,OptE:Boolean;
 PreT,PreP,PreE,PreS,PreR:Boolean;
 TmacDirs:Array[1..MaxDirs]Of String[127];
 TmacCnt:Integer;
 Pkgs:Array[1..8]Of String[15];
 PkgCnt:Integer;
 FileNames:Array[1..MaxFiles]Of String[127];
 FileCnt:Integer;
 PageSel:String[100];
 FirstPage:Longint;
 { Etat du formateur }
 LL,LT,PO,PL,Indent,PrevIn,TempIn:Longint;
 TempOn,Fill,Eject:Boolean;
 AdjMode:Char;
 LineIndent:Longint;
 Inter,PageOn:Boolean;
 CeCount,UlCount:Integer;
 PageNo:Longint;
 PageLine:Integer;
 PageLines:Integer;
 AtTopAuto,DocStarted,PageHasText,PageOpen:Boolean;
 Words:Array[1..MaxWords]Of String[120];
 WLen:Array[1..MaxWords]Of Integer;
 WGap:Array[1..MaxWords]Of Integer;
 WCount,CurLen:Integer;
 AltFlag:Boolean;
 SrcLine:Longint;
 CurFile:String[127];
 ExitNow:Boolean;
 Utf:Boolean;

Procedure ShowUsage;Begin
 WriteLn('Usage: groff [ -tpeszaivhblCENRVXZ ] [ -wname ] [ -Wname ] [ -mname ] [ -Fdir ]');
 WriteLn('             [ -Tdev ] [ -ffam ] [ -Mdir ] [ -dcs ] [ -rcn ] [ -nnum ]');
 WriteLn('             [ -olist ] [ -Parg ] [ files ... ]');
End;

Procedure ShowHelp;Begin
 WriteLn('GROFF : Cette commande permet d''effectuer le formatage de document systeme ',
         'au premier plan.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -a          Approximation ASCII de la sortie');
 WriteLn('  -b          Trace des appels lors des erreurs (accepte)');
 WriteLn('  -C          Mode de compatibilite');
 WriteLn('  -e -p -R -s -t  Preprocesseurs eqn, pic, refer, soelim, tbl (non executes)');
 WriteLn('  -E          Supprime les messages d''erreur de troff');
 WriteLn('  -h          Affiche cette aide');
 WriteLn('  -i          Lit aussi l''entree standard apres les fichiers');
 WriteLn('  -l          Impression (accepte, sans effet)');
 WriteLn('  -N          eqn: pas de saut de ligne apres les delimiteurs (accepte)');
 WriteLn('  -v          Affiche le numero de version');
 WriteLn('  -V          Affiche la ligne de commande du pipeline au lieu de l''executer');
 WriteLn('  -X          Previsualisation (accepte, sans effet)');
 WriteLn('  -z          Supprime la sortie, ne garde que les messages d''erreur');
 WriteLn('  -Z          Sortie intermediaire (format ditroff) sans post-processeur');
 WriteLn('  -wname -Wname  Active/desactive des avertissements (acceptes)');
 WriteLn('  -mname      Charge le paquetage de macros tmac.name (an est integre)');
 WriteLn('  -Fdir -Mdir Repertoires de recherche des macros');
 WriteLn('  -Tdev       Peripherique: ascii (defaut), utf8, latin1, ps, dvi ...');
 WriteLn('  -ffam       Famille de polices (acceptee)');
 WriteLn('  -dcs        Definit la chaine c (ou name=valeur)');
 WriteLn('  -rcn        Definit le registre c (ou name=valeur)');
 WriteLn('  -nnum       Numero de la premiere page');
 WriteLn('  -olist      N''imprime que les pages de la liste (ex: 1,3-5)');
 WriteLn('  -Parg       Argument pour le post-processeur (accepte)');
 WriteLn('  files       Fichiers a formater (- pour l''entree standard)');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Warn(Const Msg:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'groff: ',CurFile,':',SrcLine,': ',Msg);
 {$ELSE}
 WriteLn('groff: ',CurFile,':',SrcLine,': ',Msg);
 {$ENDIF}
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

Function TrimRight(Const S:String):String;
Var
 B:Integer;
Begin
 B:=Length(S);
 While(B>0)And(S[B]In[' ',#9,#13])Do Dec(B);
 TrimRight:=Copy(S,1,B);
End;

Function Spaces(N:Integer):String;
Var
 S:String;
Begin
 S:='';
 While(N>0)And(Length(S)<250)Do Begin
  S:=S+' ';
  Dec(N);
 End;
 Spaces:=S;
End;

Function VisLen(Const S:String):Integer;
Var
 I,N:Integer;
Begin
 N:=0;
 For I:=1 to Length(S)Do If(Ord(S[I])<128)Or(Ord(S[I])>191)Then Inc(N);
 VisLen:=N;
End;

Function NewPStr(Const S:String):PStr;
Var
 P:PStr;
Begin
 GetMem(P,Length(S)+1);
 Move(S,P^,Length(S)+1);
 NewPStr:=P;
End;

{ ------------------------- Registres, chaines, macros ------------------------- }

Function FindReg(Const N:String):Integer;
Var
 I:Integer;
Begin
 FindReg:=0;
 For I:=1 to RegCnt Do If RegName[I]=N Then Begin
  FindReg:=I;
  Exit;
 End;
End;

Procedure SetReg(Const N:String;V:Longint);
Var
 I:Integer;
Begin
 I:=FindReg(N);
 If I=0Then Begin
  If RegCnt>=MaxRegs Then Exit;
  Inc(RegCnt);
  I:=RegCnt;
  RegName[I]:=Copy(N,1,15);
  RegInc[I]:=0;
 End;
 RegVal[I]:=V;
End;

Function CurArgCount:Integer;
Var
 I:Integer;
Begin
 CurArgCount:=0;
 For I:=FTop downto 1 Do If Fr[I].Kind>0Then Begin
  CurArgCount:=Fr[I].NA;
  Exit;
 End;
End;

Function CurArg(N:Integer):String;
Var
 I:Integer;
Begin
 CurArg:='';
 For I:=FTop downto 1 Do If Fr[I].Kind>0Then Begin
  If(N>=1)And(N<=Fr[I].NA)Then CurArg:=Fr[I].A[N];
  If N=0Then CurArg:=Fr[I].AllArgs;
  Exit;
 End;
End;

Function GetReg(Const N:String;Step:Integer):Longint;
Var
 I:Integer;
 Y,M,D,DW:Word;
Begin
 GetReg:=0;
 If N='.l'Then GetReg:=LL
 Else If N='.i'Then GetReg:=Indent
 Else If N='.o'Then GetReg:=PO
 Else If N='.p'Then GetReg:=PL
 Else If N='.u'Then GetReg:=Ord(Fill)
 Else If N='.c'Then GetReg:=SrcLine
 Else If N='.$'Then GetReg:=CurArgCount
 Else If N='.s'Then GetReg:=10
 Else If N='.f'Then GetReg:=1
 Else If N='.v'Then GetReg:=UH
 Else If N='.H'Then GetReg:=UI
 Else If N='.V'Then GetReg:=UI
 Else If N='%'Then GetReg:=PageNo
 Else If N='ln'Then GetReg:=SrcLine
 Else If N='nl'Then GetReg:=PageLine*UH
 Else If(N='dw')Or(N='dy')Or(N='mo')Or(N='yr')Then Begin
  GetDate(Y,M,D,DW);
  If N='dw'Then GetReg:=DW+1
  Else If N='dy'Then GetReg:=D
  Else If N='mo'Then GetReg:=M
  Else GetReg:=Y Mod 100;
 End
 Else Begin
  I:=FindReg(N);
  If I>0Then Begin
   If Step<>0Then RegVal[I]:=RegVal[I]+Step*RegInc[I];
   GetReg:=RegVal[I];
  End;
 End;
End;

Function FindStr(Const N:String):Integer;
Var
 I:Integer;
Begin
 FindStr:=0;
 For I:=1 to StrCnt Do If StrName[I]=N Then Begin
  FindStr:=I;
  Exit;
 End;
End;

Procedure SetStr(Const N,V:String);
Var
 I:Integer;
Begin
 I:=FindStr(N);
 If I=0Then Begin
  If StrCnt>=MaxStrs Then Exit;
  Inc(StrCnt);
  I:=StrCnt;
  StrName[I]:=Copy(N,1,15);
 End;
 StrVal[I]:=NewPStr(V);
End;

Function GetStr(Const N:String):String;
Var
 I:Integer;
Begin
 I:=FindStr(N);
 If I>0Then GetStr:=StrVal[I]^
       Else GetStr:='';
End;

Function FindMac(Const N:String):Integer;
Var
 I:Integer;
Begin
 FindMac:=0;
 For I:=1 to MacCnt Do If MacName[I]=N Then Begin
  FindMac:=I;
  Exit;
 End;
End;

Function SpecialChar(Const N:String):String;Begin
 SpecialChar:='?';
 If(N='em')Or(N='en')Or(N='hy')Or(N='mi')Or(N='-')Then Begin
  If Utf And(N='em')Then SpecialChar:=#226#128#148
  Else If Utf And(N='en')Then SpecialChar:=#226#128#147
  Else SpecialChar:='-';
 End
 Else If N='bu'Then Begin
  If Utf Then SpecialChar:=#226#128#162
         Else SpecialChar:='o';
 End
 Else If N='co'Then SpecialChar:='(C)'
 Else If N='rg'Then SpecialChar:='(R)'
 Else If N='tm'Then SpecialChar:='(TM)'
 Else If(N='lq')Or(N='rq')Or(N='dq')Then SpecialChar:='"'
 Else If N='oq'Then SpecialChar:='`'
 Else If(N='cq')Or(N='aq')Then SpecialChar:=''''
 Else If N='ra'Then SpecialChar:='->'
 Else If N='la'Then SpecialChar:='<-'
 Else If N='mu'Then SpecialChar:='x'
 Else If N='de'Then SpecialChar:='o'
 Else If N='dg'Then SpecialChar:='+'
 Else If N='ct'Then SpecialChar:='c'
 Else If N='Do'Then SpecialChar:='$'
 Else If N='sc'Then SpecialChar:='S'
 Else If N='pl'Then SpecialChar:='+'
 Else If N='eq'Then SpecialChar:='='
 Else If N='sl'Then SpecialChar:='/'
 Else If N='ff'Then SpecialChar:='ff'
 Else If N='fi'Then SpecialChar:='fi'
 Else If N='fl'Then SpecialChar:='fl'
 Else If N='Fi'Then SpecialChar:='ffi'
 Else If N='Fl'Then SpecialChar:='ffl'
 Else If N='ga'Then SpecialChar:='`'
 Else If N='aa'Then SpecialChar:=''''
 Else If N='ru'Then SpecialChar:='_'
 Else If N='ul'Then SpecialChar:='_'
 Else If N='bv'Then SpecialChar:='|'
 Else If N='or'Then SpecialChar:='|'
 Else If N='ti'Then SpecialChar:='~'
 Else If N='ha'Then SpecialChar:='^'
 Else If N='Bq'Then SpecialChar:=',,'
 Else If N='ap'Then SpecialChar:='~'
 Else If N='<='Then SpecialChar:='<='
 Else If N='>='Then SpecialChar:='>='
 Else If N='!='Then SpecialChar:='!='
 Else If N='+-'Then SpecialChar:='+-';
End;

{ ------------------------- Expressions numeriques ------------------------- }

Var
 ES:String;
 EP:Integer;
 EDef:Char;

Function ECmp:Real;Forward;

Procedure ESkip;Begin
 While(EP<=Length(ES))And(ES[EP]=' ')Do Inc(EP);
End;

Function UnitScale(C:Char):Real;Begin
 Case C of
  'i':UnitScale:=UI;
  'c':UnitScale:=UI/2.54;
  'P':UnitScale:=UI/6;
  'p':UnitScale:=UI/72;
  'm','n':UnitScale:=UW;
  'v':UnitScale:=UH;
  'M':UnitScale:=UW/100;
  Else UnitScale:=1;
 End;
End;

Function EPrim:Real;
Var
 V,F:Real;
 Neg:Boolean;
 C:Char;
 Start:Integer;
Begin
 ESkip;
 Neg:=False;
 While(EP<=Length(ES))And(ES[EP]In['-','+'])Do Begin
  If ES[EP]='-'Then Neg:=Not Neg;
  Inc(EP);
  ESkip;
 End;
 V:=0;
 If(EP<=Length(ES))And(ES[EP]='(')Then Begin
  Inc(EP);
  V:=ECmp;
  ESkip;
  If(EP<=Length(ES))And(ES[EP]=')')Then Inc(EP);
 End
  Else
 Begin
  Start:=EP;
  While(EP<=Length(ES))And(ES[EP]In['0'..'9'])Do Begin
   V:=V*10+Ord(ES[EP])-48;
   Inc(EP);
  End;
  If(EP<=Length(ES))And(ES[EP]='.')Then Begin
   Inc(EP);
   F:=0.1;
   While(EP<=Length(ES))And(ES[EP]In['0'..'9'])Do Begin
    V:=V+(Ord(ES[EP])-48)*F;
    F:=F/10;
    Inc(EP);
   End;
  End;
  If EP>Start Then Begin
   If EP<=Length(ES)Then Begin
    C:=ES[EP];
    If C In['i','c','P','p','m','n','u','v','M']Then Begin
     V:=V*UnitScale(C);
     Inc(EP);
    End
     Else
    V:=V*UnitScale(EDef);
   End
    Else
   V:=V*UnitScale(EDef);
  End;
 End;
 If Neg Then V:=-V;
 EPrim:=V;
End;

Function EMul:Real;
Var
 V,D:Real;
 C_:Char;
Begin
 V:=EPrim;
 ESkip;
 While(EP<=Length(ES))And(ES[EP]In['*','/','%'])Do Begin
  C_:=ES[EP];
  Inc(EP);
  D:=EPrim;
  If C_='*'Then V:=V*D
  Else If D<>0Then Begin
   If C_='/'Then V:=Int(V/D)
            Else V:=Round(V)Mod Round(D);
  End;
  ESkip;
 End;
 EMul:=V;
End;

Function EAdd:Real;
Var
 V:Real;
 C_:Char;
Begin
 V:=EMul;
 ESkip;
 While(EP<=Length(ES))And(ES[EP]In['+','-'])Do Begin
  C_:=ES[EP];
  Inc(EP);
  If C_='+'Then V:=V+EMul
           Else V:=V-EMul;
  ESkip;
 End;
 EAdd:=V;
End;

Function ECmp:Real;
Var
 V,W:Real;
 Op:String;
Begin
 V:=EAdd;
 ESkip;
 While(EP<=Length(ES))And(ES[EP]In['<','>','=','&',':'])Do Begin
  Op:=ES[EP];
  Inc(EP);
  If(EP<=Length(ES))And(ES[EP]In['=','<','>'])And(Op<>'&')And(Op<>':')Then Begin
   Op:=Op+ES[EP];
   Inc(EP);
  End;
  W:=EAdd;
  If Op='<'Then V:=Ord(V<W)
  Else If Op='>'Then V:=Ord(V>W)
  Else If(Op='=')Or(Op='==')Then V:=Ord(V=W)
  Else If Op='<='Then V:=Ord(V<=W)
  Else If Op='>='Then V:=Ord(V>=W)
  Else If Op='&'Then V:=Ord((V>0)And(W>0))
  Else If Op=':'Then V:=Ord((V>0)Or(W>0));
  ESkip;
 End;
 ECmp:=V;
End;

{ Evalue une expression au debut de S (a partir de P); Rel=1 si +n, 2 si -n }
Function EvalNum(Const S:String;Var P:Integer;Def:Char;Var Rel:Integer):Longint;
Var
 V:Real;
Begin
 ES:=S;
 EP:=P;
 EDef:=Def;
 Rel:=0;
 ESkip;
 If(EP<=Length(ES))And(ES[EP]='+')Then Begin
  Rel:=1;
  Inc(EP);
 End
 Else If(EP<=Length(ES))And(ES[EP]='-')And(EP<Length(ES))And(ES[EP+1]<>'(')Then Begin
  Rel:=2;
  Inc(EP);
 End;
 V:=ECmp;
 P:=EP;
 EvalNum:=Round(V);
End;

Function Apply(Old:Longint;Const S:String;Def:Char):Longint;
Var
 P,Rel:Integer;
 V:Longint;
Begin
 P:=1;
 V:=EvalNum(S,P,Def,Rel);
 If Rel=1Then Apply:=Old+V
 Else If Rel=2Then Apply:=Old-V
 Else Apply:=V;
End;

{ ------------------------- Interpolation des echappements ------------------------- }

Procedure ReadName(Const S:String;Var I:Integer;Var Nm:String);Begin
 Nm:='';
 If I>Length(S)Then Exit;
 If S[I]='('Then Begin
  Nm:=Copy(S,I+1,2);
  Inc(I,3);
 End
 Else If S[I]='['Then Begin
  Inc(I);
  While(I<=Length(S))And(S[I]<>']')Do Begin
   Nm:=Nm+S[I];
   Inc(I);
  End;
  Inc(I);
 End
 Else Begin
  Nm:=S[I];
  Inc(I);
 End;
End;

Function Expand(Const S:String;Depth:Integer):String;
Var
 R,Nm,V,Sub:String;
 I,J,N,Step,Rel:Integer;
 C,Dl:Char;
 Val_:Longint;
Begin
 R:='';
 I:=1;
 While I<=Length(S)Do Begin
  C:=S[I];
  If C<>'\'Then Begin
   R:=R+C;
   Inc(I);
  End
   Else
  Begin
   Inc(I);
   If I>Length(S)Then Break;
   C:=S[I];
   Inc(I);
   Case C of
    '\','e':R:=R+'\';
    '"':I:=Length(S)+1;
    '#':I:=Length(S)+1;
    '*':Begin
     ReadName(S,I,Nm);
     If Depth<8Then R:=R+Expand(GetStr(Nm),Depth+1);
    End;
    'n':Begin
     Step:=0;
     If(I<=Length(S))And(S[I]='+')Then Begin
      Step:=1;
      Inc(I);
     End
     Else If(I<=Length(S))And(S[I]='-')Then Begin
      Step:=-1;
      Inc(I);
     End;
     ReadName(S,I,Nm);
     R:=R+IntStr(GetReg(Nm,Step));
    End;
    '$':Begin
     If I<=Length(S)Then Begin
      If S[I]='*'Then R:=R+CurArg(0)
      Else If S[I]In['0'..'9']Then R:=R+CurArg(Ord(S[I])-48);
      Inc(I);
     End;
    End;
    'w':Begin
     If I<=Length(S)Then Begin
      Dl:=S[I];
      J:=I+1;
      While(J<=Length(S))And(S[J]<>Dl)Do Inc(J);
      Sub:=Expand(Copy(S,I+1,J-I-1),Depth+1);
      R:=R+IntStr(VisLen(Sub)*UW);
      I:=J+1;
     End;
    End;
    'h':Begin
     If I<=Length(S)Then Begin
      Dl:=S[I];
      J:=I+1;
      While(J<=Length(S))And(S[J]<>Dl)Do Inc(J);
      Sub:=Expand(Copy(S,I+1,J-I-1),Depth+1);
      N:=1;
      Val_:=EvalNum(Sub,N,'m',Rel);
      If Val_>0Then R:=R+Spaces(Val_ Div UW);
      I:=J+1;
     End;
    End;
    '(':Begin
     Nm:=Copy(S,I,2);
     Inc(I,2);
     R:=R+SpecialChar(Nm);
    End;
    '[':Begin
     Dec(I);
     ReadName(S,I,Nm);
     R:=R+SpecialChar(Nm);
    End;
    'f','F','g','k','z':Begin
     ReadName(S,I,Nm);
    End;
    's':Begin
     While(I<=Length(S))And(S[I]In['+','-'])Do Inc(I);
     If(I<=Length(S))And(S[I]='(')Then Inc(I,3)
      Else
     While(I<=Length(S))And(S[I]In['0'..'9'])Do Inc(I);
    End;
    'N','v','x','l','L','D','o','b','X','H','S':Begin
     If I<=Length(S)Then Begin
      Dl:=S[I];
      J:=I+1;
      While(J<=Length(S))And(S[J]<>Dl)Do Inc(J);
      If C='N'Then Begin
       N:=1;
       Sub:=Copy(S,I+1,J-I-1);
       Val_:=EvalNum(Sub,N,'u',Rel);
       If(Val_>0)And(Val_<256)Then R:=R+Chr(Val_);
      End;
      I:=J+1;
     End;
    End;
    '&':R:=R+#2;
    ' ','0':R:=R+#1;
    '|','^','%','{','}','a','p','r','u','d',',','/','_':;
    't':R:=R+#9;
    'c':R:=R+#3;
    '-':R:=R+'-';
    '.':R:=R+'.';
    '''':R:=R+'''';
    '`':R:=R+'`';
    Else R:=R+C;
   End;
  End;
 End;
 Expand:=R;
End;

{ ------------------------- Pile d'entree ------------------------- }

Function PushFile(Const Name:String):Boolean;Begin
 PushFile:=False;
 If FTop>=MaxFrames Then Begin
  Warn('trop de fichiers/macros imbriques');
  Exit;
 End;
 Assign(Fr[FTop+1].F,Name);
 {$I-}Reset(Fr[FTop+1].F);{$I+}
 If IOResult<>0Then Exit;
 Inc(FTop);
 Fr[FTop].Kind:=0;
 If Name=''Then CurFile:='<stdin>'
           Else CurFile:=Copy(Name,1,127);
 PushFile:=True;
End;

{ Mot numero N d'une chaine, les guillemets groupent }
Function ArgWord(Const A:String;N:Integer):String;
Var
 I,K:Integer;
 W:String;
Begin
 I:=1;
 K:=0;
 ArgWord:='';
 While I<=Length(A)Do Begin
  While(I<=Length(A))And(A[I]In[' ',#9])Do Inc(I);
  If I>Length(A)Then Exit;
  W:='';
  If A[I]='"'Then Begin
   Inc(I);
   While(I<=Length(A))And(A[I]<>'"')Do Begin
    W:=W+A[I];
    Inc(I);
   End;
   Inc(I);
  End
   Else
  While(I<=Length(A))And Not(A[I]In[' ',#9])Do Begin
   W:=W+A[I];
   Inc(I);
  End;
  Inc(K);
  If K=N Then Begin
   ArgWord:=W;
   Exit;
  End;
 End;
End;

Function WordCount(Const A:String):Integer;
Var
 N:Integer;
Begin
 N:=0;
 While ArgWord(A,N+1)<>''Do Inc(N);
 WordCount:=N;
End;

Procedure SetupArgs(Const A:String);
Var
 I:Integer;
Begin
 Fr[FTop].NA:=WordCount(A);
 If Fr[FTop].NA>9Then Fr[FTop].NA:=9;
 For I:=1 to 9Do Fr[FTop].A[I]:=ArgWord(A,I);
 Fr[FTop].AllArgs:=Copy(A,1,200);
End;

Function PushMacro(Idx:Integer;Const A:String):Boolean;Begin
 PushMacro:=False;
 If FTop>=MaxFrames Then Begin
  Warn('macros trop imbriquees');
  Exit;
 End;
 Inc(FTop);
 Fr[FTop].Kind:=1;
 Fr[FTop].Mac:=MacBody[Idx];
 Fr[FTop].Idx:=1;
 Fr[FTop].Cnt:=MacBody[Idx]^.NL;
 SetupArgs(A);
 PushMacro:=True;
End;

Procedure PushBuiltin;Begin
 If FTop>=MaxFrames Then Exit;
 Inc(FTop);
 Fr[FTop].Kind:=2;
 Fr[FTop].Idx:=1;
 Fr[FTop].Cnt:=BuiltinCount;
 Fr[FTop].NA:=0;
End;

Function RawLine(Var S:String):Boolean;Begin
 RawLine:=False;
 While FTop>0Do Begin
  Case Fr[FTop].Kind of
   0:Begin
    If EOF(Fr[FTop].F)Then Begin
     Close(Fr[FTop].F);
     Dec(FTop);
    End
     Else
    Begin
     ReadLn(Fr[FTop].F,S);
     Inc(SrcLine);
     RawLine:=True;
     Exit;
    End;
   End;
   1:Begin
    If Fr[FTop].Idx>Fr[FTop].Cnt Then Dec(FTop)
     Else
    Begin
     S:=Fr[FTop].Mac^.L[Fr[FTop].Idx]^;
     Inc(Fr[FTop].Idx);
     RawLine:=True;
     Exit;
    End;
   End;
   Else Begin
    If Fr[FTop].Idx>Fr[FTop].Cnt Then Dec(FTop)
     Else
    Begin
     S:=Builtin[Fr[FTop].Idx];
     Inc(Fr[FTop].Idx);
     RawLine:=True;
     Exit;
    End;
   End;
  End;
 End;
End;

{ Lit une ligne logique : une \ en fin de ligne joint la suivante }
Function GetLine(Var S:String):Boolean;
Var
 T:String;
 N,I:Integer;
 Ok:Boolean;
Begin
 Ok:=RawLine(S);
 GetLine:=Ok;
 If Not Ok Then Exit;
 While True Do Begin
  N:=0;
  I:=Length(S);
  While(I>0)And(S[I]='\')Do Begin
   Inc(N);
   Dec(I);
  End;
  If Not Odd(N)Then Break;
  S:=Copy(S,1,Length(S)-1);
  If Not RawLine(T)Then Break;
  S:=S+T;
 End;
End;

{ ------------------------- Sortie des pages ------------------------- }

Function PageSelected(N:Longint):Boolean;
Var
 I,J,K,Dash:Integer;
 Tok:String;
 A,B,Err_:Longint;
 E:Integer;
Begin
 If PageSel=''Then Begin
  PageSelected:=True;
  Exit;
 End;
 PageSelected:=False;
 I:=1;
 While I<=Length(PageSel)Do Begin
  J:=I;
  While(J<=Length(PageSel))And(PageSel[J]<>',')Do Inc(J);
  Tok:=Copy(PageSel,I,J-I);
  I:=J+1;
  Dash:=Pos('-',Tok);
  If Dash=0Then Begin
   Val(Tok,A,E);
   If(E=0)And(A=N)Then PageSelected:=True;
  End
   Else
  Begin
   A:=-2147483647;
   B:=2147483647;
   If Dash>1Then Val(Copy(Tok,1,Dash-1),A,E);
   If Dash<Length(Tok)Then Val(Copy(Tok,Dash+1,20),B,E);
   If(N>=A)And(N<=B)Then PageSelected:=True;
  End;
 End;
End;

Procedure StartDoc;Begin
 DocStarted:=True;
 If Inter And Not OptSupp Then Begin
  WriteLn('x T ',Dev);
  WriteLn('x res ',UI,' 1 1');
  WriteLn('x init');
  WriteLn('x font 1 R');
  WriteLn('f1');
  WriteLn('s10');
 End;
End;

Procedure OpenPage;Begin
 PageOpen:=True;
 PageOn:=PageSelected(PageNo)And Not OptSupp;
 If Inter And PageOn Then WriteLn('p',PageNo);
End;

Procedure ClosePage;
Var
 I:Integer;
Begin
 If Not PageOpen Then Exit;
 If(Not Inter)And PageOn And(PageLine>0)Then
  For I:=PageLine to PageLines-1 Do WriteLn;
 PageOpen:=False;
End;

Procedure EnsureRoom;Begin
 If Not DocStarted Then StartDoc;
 If Not PageOpen Then OpenPage;
End;

Procedure NextPage(Auto:Boolean);Begin
 ClosePage;
 Inc(PageNo);
 PageLine:=0;
 AtTopAuto:=Auto;
End;

Procedure WriteInter(Const S:String);
Var
 K,I,J:Integer;
Begin
 K:=0;
 While(K<Length(S))And(S[K+1]=' ')Do Inc(K);
 WriteLn('V',(PageLine+1)*UH);
 WriteLn('H',K*UW);
 I:=K+1;
 While I<=Length(S)Do Begin
  J:=I;
  If S[I]=' 'Then Begin
   While(J<=Length(S))And(S[J]=' ')Do Inc(J);
   WriteLn('h',(J-I)*UW);
  End
   Else
  Begin
   While(J<=Length(S))And(S[J]<>' ')Do Inc(J);
   WriteLn('t',Copy(S,I,J-I));
  End;
  I:=J;
 End;
 WriteLn('n',UH,' 0');
End;

Procedure EmitBlank(N:Integer);
Var
 K:Integer;
Begin
 For K:=1 to N Do Begin
  EnsureRoom;
  If PageLine>=PageLines Then Begin
   NextPage(True);
   Exit;
  End;
  If Not AtTopAuto Then Begin
   If(Not Inter)And PageOn Then WriteLn;
   Inc(PageLine);
  End;
 End;
End;

Procedure EmitText(Const S:String);Begin
 EnsureRoom;
 If PageLine>=PageLines Then Begin
  NextPage(True);
  EnsureRoom;
 End;
 AtTopAuto:=False;
 If PageOn Then Begin
  If Inter Then WriteInter(TrimRight(S))
           Else WriteLn(TrimRight(S));
 End;
 Inc(PageLine);
End;

{ ------------------------- Remplissage et justification ------------------------- }

Function CleanWord(Const W:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:='';
 For I:=1 to Length(W)Do Begin
  If W[I]=#1Then R:=R+' '
  Else If(W[I]<>#2)And(W[I]<>#3)Then R:=R+W[I];
 End;
 CleanWord:=R;
End;

Procedure FlushLine(Justify:Boolean;Mode:Char);
Var
 I,Avail,Extra,Pad,Pos_,Guard:Integer;
 S:String;
 Gaps:Array[1..MaxWords]Of Integer;
Begin
 If WCount=0Then Exit;
 Avail:=(LL-LineIndent)Div UW;
 For I:=1 to WCount-1 Do Gaps[I]:=WGap[I];
 If(Mode='b')And Justify And(WCount>1)And(CurLen<Avail)Then Begin
  Extra:=Avail-CurLen;
  Guard:=0;
  While(Extra>0)And(Guard<1000)Do Begin
   For I:=1 to WCount-1 Do Begin
    If AltFlag Then Pos_:=I
               Else Pos_:=WCount-I;
    If(Extra>0)And(WGap[Pos_]>0)Then Begin
     Inc(Gaps[Pos_]);
     Dec(Extra);
    End;
   End;
   Inc(Guard);
  End;
 End;
 Pad:=0;
 If Mode='c'Then Pad:=(Avail-CurLen)Div 2
 Else If Mode='r'Then Pad:=Avail-CurLen;
 If Pad<0Then Pad:=0;
 S:=Spaces((PO+LineIndent)Div UW+Pad);
 For I:=1 to WCount Do Begin
  S:=S+Words[I];
  If I<WCount Then S:=S+Spaces(Gaps[I]);
 End;
 EmitText(S);
 AltFlag:=Not AltFlag;
 WCount:=0;
 CurLen:=0;
 TempOn:=False;
End;

Procedure BreakLine;Begin
 FlushLine(False,AdjMode);
End;

Procedure AddWord(Const W0:String);
Var
 W:String;
 L:Integer;
Begin
 W:=CleanWord(W0);
 L:=VisLen(W);
 If WCount>0Then Begin
  If(WCount>=MaxWords)Or((WGap[WCount]>0)And(CurLen+WGap[WCount]+L>(LL-LineIndent)Div UW))Then
   FlushLine(True,AdjMode);
 End;
 If WCount=0Then Begin
  If TempOn Then LineIndent:=TempIn
            Else LineIndent:=Indent;
  CurLen:=0;
 End
  Else
 CurLen:=CurLen+WGap[WCount];
 Inc(WCount);
 Words[WCount]:=Copy(W,1,120);
 WLen[WCount]:=L;
 WGap[WCount]:=1;
 CurLen:=CurLen+L;
End;

Procedure FillLine(Const S0:String);
Var
 S,W:String;
 I,J,Lead,Last:Integer;
 Cont:Boolean;
 C:Char;
Begin
 S:=S0;
 Lead:=0;
 If(S<>'')And(S[1]=' ')Then Begin
  BreakLine;
  While(Lead<Length(S))And(S[Lead+1]=' ')Do Inc(Lead);
 End;
 If CeCount>0Then BreakLine;
 Cont:=False;
 I:=Lead+1;
 Last:=WCount;
 While I<=Length(S)Do Begin
  While(I<=Length(S))And(S[I]=' ')Do Inc(I);
  If I>Length(S)Then Break;
  J:=I;
  While(J<=Length(S))And(S[J]<>' ')Do Inc(J);
  W:=Copy(S,I,J-I);
  I:=J;
  Cont:=False;
  If(Length(W)>0)And(W[Length(W)]=#3)Then Cont:=True;
  If(Lead>0)And(Last=WCount)Then Begin
   W:=Spaces(Lead)+W;
   Lead:=0;
  End;
  AddWord(W);
 End;
 If WCount>0Then Begin
  W:=CleanWord(Words[WCount]);
  J:=Length(W);
  While(J>0)And(W[J]In[')','"','''',']','*'])Do Dec(J);
  If(J>0)And(W[J]In['.','?','!'])Then WGap[WCount]:=2
                                  Else WGap[WCount]:=1;
  If Cont Then WGap[WCount]:=0;
 End;
 If CeCount>0Then Begin
  FlushLine(False,'c');
  Dec(CeCount);
 End;
 C:=' ';
End;

Procedure NoFillLine(Const S:String);
Var
 T:String;
 I,Pad,Avail:Integer;
Begin
 BreakLine;
 T:='';
 For I:=1 to Length(S)Do Begin
  If S[I]=#9Then Begin
   Repeat
    T:=T+' ';
   Until Length(T)Mod 5=0;
  End
  Else If S[I]=#1Then T:=T+' '
  Else If(S[I]<>#2)And(S[I]<>#3)Then T:=T+S[I];
 End;
 Pad:=0;
 If TempOn Then Pad:=TempIn
           Else Pad:=Indent;
 TempOn:=False;
 Pad:=(PO+Pad)Div UW;
 If CeCount>0Then Begin
  Avail:=(LL-Indent)Div UW;
  If VisLen(T)<Avail Then Pad:=Pad+(Avail-VisLen(T))Div 2;
  Dec(CeCount);
 End;
 EmitText(Spaces(Pad)+T);
End;

Procedure TextLine(Const S:String);Begin
 If Trim(S)=''Then Begin
  BreakLine;
  EmitBlank(1);
 End
 Else If Fill Then FillLine(S)
 Else NoFillLine(S);
End;

{ ------------------------- Requetes ------------------------- }

Procedure ProcessLine(Const Line:String;Expanded:Boolean);Forward;

Function Halve(Const S:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:='';
 I:=1;
 While I<=Length(S)Do Begin
  If(S[I]='\')And(I<Length(S))And(S[I+1]='\')Then Begin
   R:=R+'\';
   Inc(I,2);
  End
   Else
  Begin
   R:=R+S[I];
   Inc(I);
  End;
 End;
 Halve:=R;
End;

Function SkipWords(Const A:String;N:Integer):String;
Var
 I,K:Integer;
Begin
 I:=1;
 For K:=1 to N Do Begin
  While(I<=Length(A))And(A[I]In[' ',#9])Do Inc(I);
  While(I<=Length(A))And Not(A[I]In[' ',#9])Do Inc(I);
 End;
 While(I<=Length(A))And(A[I]In[' ',#9])Do Inc(I);
 SkipWords:=Copy(A,I,255);
End;

Procedure ReadBody(Const Name:String;Mode:Integer;Const EndMark:String);
Var
 M:Integer;
 L:String;
Begin
 M:=0;
 If Mode<2Then Begin
  M:=FindMac(Name);
  If M=0Then Begin
   If MacCnt>=MaxMacs Then Begin
    Warn('trop de macros');
    Mode:=2;
   End
    Else
   Begin
    Inc(MacCnt);
    M:=MacCnt;
    MacName[M]:=Copy(Name,1,15);
    New(MacBody[M]);
    MacBody[M]^.NL:=0;
   End;
  End
  Else If Mode=0Then MacBody[M]^.NL:=0;
 End;
 While RawLine(L)Do Begin
  If(L='..')Or((EndMark<>'')And(L='.'+EndMark))Then Break;
  If(Mode<2)And(MacBody[M]^.NL<MaxMacLines)Then Begin
   Inc(MacBody[M]^.NL);
   MacBody[M]^.L[MacBody[M]^.NL]:=NewPStr(Halve(L));
  End;
 End;
End;

Procedure SkipBlock(Bal:Integer);
Var
 L:String;
 I:Integer;
Begin
 While(Bal>0)And RawLine(L)Do Begin
  I:=1;
  While I<Length(L)Do Begin
   If(L[I]='\')And(L[I+1]='{')Then Inc(Bal)
   Else If(L[I]='\')And(L[I+1]='}')Then Dec(Bal);
   If L[I]='\'Then Inc(I);
   Inc(I);
  End;
 End;
End;

Function CountOpen(Const S:String):Integer;
Var
 I,N:Integer;
Begin
 N:=0;
 For I:=1 to Length(S)-1 Do If(S[I]='\')And(S[I+1]='{')Then Inc(N);
 CountOpen:=N;
End;

Function EvalCond(Const S:String;Var P:Integer):Boolean;
Var
 Neg,Res_:Boolean;
 C,Dl:Char;
 A,B:String;
 Rel:Integer;
 V:Longint;
Begin
 Neg:=False;
 Res_:=False;
 While(P<=Length(S))And(S[P]=' ')Do Inc(P);
 While(P<=Length(S))And(S[P]='!')Do Begin
  Neg:=Not Neg;
  Inc(P);
 End;
 If P<=Length(S)Then Begin
  C:=S[P];
  If(C In['n','t','o','e'])And((P=Length(S))Or(S[P+1]=' '))Then Begin
   If C='n'Then Res_:=True
   Else If C='o'Then Res_:=Odd(PageNo)
   Else If C='e'Then Res_:=Not Odd(PageNo);
   Inc(P);
  End
  Else If(C In['d','r'])And(P<Length(S))And(S[P+1]=' ')Then Begin
   Inc(P,2);
   A:='';
   While(P<=Length(S))And(S[P]<>' ')Do Begin
    A:=A+S[P];
    Inc(P);
   End;
   If C='d'Then Res_:=(FindMac(A)>0)Or(FindStr(A)>0)
           Else Res_:=FindReg(A)>0;
  End
  Else If C In['0'..'9','+','-','(','.']Then Begin
   V:=EvalNum(S,P,'u',Rel);
   If Rel=2Then V:=-V;
   Res_:=V>0;
  End
  Else Begin
   Dl:=C;
   Inc(P);
   A:='';
   While(P<=Length(S))And(S[P]<>Dl)Do Begin
    A:=A+S[P];
    Inc(P);
   End;
   Inc(P);
   B:='';
   While(P<=Length(S))And(S[P]<>Dl)Do Begin
    B:=B+S[P];
    Inc(P);
   End;
   Inc(P);
   Res_:=(A=B);
  End;
 End;
 If Neg Then Res_:=Not Res_;
 EvalCond:=Res_;
End;

Procedure DoTitle(Const A:String);
Var
 Dl:Char;
 Part:Array[1..3]Of String;
 I,K,W:Integer;
 S:String;
Begin
 BreakLine;
 If A=''Then Exit;
 Dl:=A[1];
 K:=1;
 Part[1]:='';
 Part[2]:='';
 Part[3]:='';
 For I:=2 to Length(A)Do Begin
  If A[I]=Dl Then Begin
   Inc(K);
   If K>3Then Break;
  End
   Else
  Part[K]:=Part[K]+A[I];
 End;
 W:=LT Div UW;
 S:=Spaces(W);
 For I:=1 to Length(Part[1])Do If I<=W Then S[I]:=Part[1][I];
 K:=(W-Length(Part[2]))Div 2;
 For I:=1 to Length(Part[2])Do If(K+I>=1)And(K+I<=W)Then S[K+I]:=Part[2][I];
 K:=W-Length(Part[3]);
 For I:=1 to Length(Part[3])Do If(K+I>=1)And(K+I<=W)Then S[K+I]:=Part[3][I];
 EmitText(Spaces(PO Div UW)+TrimRight(S));
End;

Function IsIgnored(Const N:String):Boolean;Begin
 IsIgnored:=(N='ns')Or(N='rs')Or(N='ps')Or(N='vs')Or(N='ft')Or(N='hy')Or(N='nh')Or
  (N='ta')Or(N='bd')Or(N='cs')Or(N='ss')Or(N='lg')Or(N='mk')Or(N='rt')Or(N='sv')Or
  (N='os')Or(N='ev')Or(N='ec')Or(N='eo')Or(N='lf')Or(N='it')Or(N='di')Or(N='da')Or
  (N='wh')Or(N='ch')Or(N='dt')Or(N='fp')Or(N='tr')Or(N='lc')Or(N='hc')Or(N='nm')Or
  (N='nn')Or(N='cc')Or(N='c2')Or(N='sy')Or(N='fl')Or(N='af')Or(N='pc')Or(N='ul')Or
  (N='cu')Or(N='uf')Or(N='hw')Or(N='hla')Or(N='hpf')Or(N='mc')Or(N='fam')Or
  (N='nx')Or(N='cf')Or(N='pi')Or(N='sp_')Or(N='ne_')Or(N='pn')Or(N='als')Or
  (N='char')Or(N='fchar')Or(N='ssz')Or(N='warn')Or(N='tag')Or(N='pnr')Or(N='shc')Or
  (N='nroff')Or(N='troff');
End;

Procedure DoRequest(Const Nm,RestRaw:String;Brk,Expanded:Boolean);
Var
 A,W1,V:String;
 M,N,P,Rel,I:Integer;
 Lv:Longint;
 Ok:Boolean;
 Rest:String;
Begin
 If Not Expanded Then A:=Expand(RestRaw,0)
                 Else A:=RestRaw;
 M:=FindMac(Nm);
 If M>0Then Begin
  PushMacro(M,A);
  Exit;
 End;
 If Nm='br'Then BreakLine
 Else If Nm='sp'Then Begin
  If Brk Then BreakLine;
  If A=''Then N:=1
   Else
  Begin
   Lv:=Apply(0,A,'v');
   N:=Lv Div UH;
  End;
  If N>0Then EmitBlank(N);
 End
 Else If Nm='fi'Then Begin
  BreakLine;
  Fill:=True;
 End
 Else If Nm='nf'Then Begin
  BreakLine;
  Fill:=False;
 End
 Else If Nm='ad'Then Begin
  W1:=ArgWord(A,1);
  If(W1='')Or(W1='b')Or(W1='n')Then AdjMode:='b'
  Else If W1='c'Then AdjMode:='c'
  Else If W1='r'Then AdjMode:='r'
  Else AdjMode:='l';
 End
 Else If Nm='na'Then AdjMode:='l'
 Else If Nm='ce'Then Begin
  BreakLine;
  If A=''Then CeCount:=1
         Else CeCount:=Apply(0,A,'u');
 End
 Else If Nm='in'Then Begin
  BreakLine;
  If A=''Then Begin
   Lv:=Indent;
   Indent:=PrevIn;
   PrevIn:=Lv;
  End
   Else
  Begin
   PrevIn:=Indent;
   Indent:=Apply(Indent,A,'m');
  End;
  If Indent<0Then Indent:=0;
 End
 Else If Nm='ti'Then Begin
  BreakLine;
  TempIn:=Apply(Indent,A,'m');
  If TempIn<0Then TempIn:=0;
  TempOn:=True;
 End
 Else If Nm='ll'Then Begin
  If A<>''Then LL:=Apply(LL,A,'m');
  If LL<UW Then LL:=UW;
 End
 Else If Nm='lt'Then Begin
  If A<>''Then LT:=Apply(LT,A,'m');
 End
 Else If Nm='po'Then Begin
  If A<>''Then PO:=Apply(PO,A,'m');
  If PO<0Then PO:=0;
 End
 Else If Nm='pl'Then Begin
  If A<>''Then PL:=Apply(PL,A,'v');
  PageLines:=PL Div UH;
  If PageLines<1Then PageLines:=1;
 End
 Else If Nm='bp'Then Begin
  If Brk Then BreakLine;
  If PageOpen Or DocStarted Then Begin
   EnsureRoom;
   If PageLine>0Then NextPage(False);
  End;
  If A<>''Then PageNo:=Apply(PageNo,A,'u');
 End
 Else If Nm='ne'Then Begin
  If A=''Then N:=1
   Else
  Begin
   Lv:=Apply(0,A,'v');
   N:=Lv Div UH;
   If N<1Then N:=1;
  End;
  BreakLine;
  EnsureRoom;
  If(PageLine>0)And(PageLine+N>PageLines)Then NextPage(False);
 End
 Else If Nm='nr'Then Begin
  W1:=ArgWord(A,1);
  Rest:=SkipWords(A,1);
  If W1<>''Then Begin
   SetReg(W1,Apply(GetReg(W1,0),ArgWord(Rest,1),'u'));
   If ArgWord(Rest,2)<>''Then Begin
    P:=FindReg(W1);
    If P>0Then RegInc[P]:=Apply(0,ArgWord(Rest,2),'u');
   End;
  End;
 End
 Else If Nm='rr'Then Begin
  P:=FindReg(ArgWord(A,1));
  If P>0Then RegName[P]:='';
 End
 Else If(Nm='ds')Or(Nm='as')Then Begin
  W1:=ArgWord(RestRaw,1);
  V:=Halve(SkipWords(RestRaw,1));
  If(V<>'')And(V[1]='"')Then V:=Copy(V,2,255);
  If Nm='as'Then V:=GetStr(W1)+V;
  If W1<>''Then SetStr(W1,V);
 End
 Else If(Nm='de')Or(Nm='am')Or(Nm='de1')Then Begin
  If Nm='am'Then ReadBody(ArgWord(RestRaw,1),1,ArgWord(RestRaw,2))
            Else ReadBody(ArgWord(RestRaw,1),0,ArgWord(RestRaw,2));
 End
 Else If Nm='ig'Then ReadBody('',2,ArgWord(RestRaw,1))
 Else If Nm='rm'Then Begin
  P:=FindMac(ArgWord(A,1));
  If P>0Then MacName[P]:='';
  P:=FindStr(ArgWord(A,1));
  If P>0Then StrName[P]:='';
 End
 Else If Nm='rn'Then Begin
  P:=FindMac(ArgWord(A,1));
  If P>0Then MacName[P]:=Copy(ArgWord(A,2),1,15);
 End
 Else If(Nm='so')Or(Nm='mso')Then Begin
  If Not PushFile(Trim(A))Then Warn('impossible d''ouvrir '+Trim(A));
 End
 Else If Nm='ex'Then ExitNow:=True
 Else If Nm='ab'Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,A);
  {$ELSE}
  WriteLn(A);
  {$ENDIF}
  ExitNow:=True;
 End
 Else If Nm='tm'Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,A);
  {$ELSE}
  WriteLn(A);
  {$ENDIF}
 End
 Else If Nm='tl'Then DoTitle(A)
 Else If(Nm='if')Or(Nm='ie')Or(Nm='el')Then Begin
  P:=1;
  If Nm='el'Then Begin
   If IeTop>0Then Begin
    Ok:=Not IeStack[IeTop];
    Dec(IeTop);
   End
    Else
   Ok:=False;
  End
   Else
  Begin
   Ok:=EvalCond(A,P);
   If Nm='ie'Then Begin
    If IeTop<MaxIe Then Inc(IeTop);
    IeStack[IeTop]:=Ok;
   End;
  End;
  Rest:=Copy(A,P,255);
  While(Rest<>'')And(Rest[1]=' ')Do Rest:=Copy(Rest,2,255);
  If Ok Then Begin
   If Rest<>''Then ProcessLine(Rest,True);
  End
  Else If CountOpen(RestRaw)>0Then SkipBlock(CountOpen(RestRaw));
 End
 Else If IsIgnored(Nm)Then
 Else If Not OptE Then Warn('requete inconnue: '+Nm);
End;

Procedure ProcessLine(Const Line:String;Expanded:Boolean);
Var
 C:Char;
 I:Integer;
 Nm,Rest:String;
Begin
 If Line=''Then Begin
  TextLine('');
  Exit;
 End;
 C:=Line[1];
 If(C='.')Or(C='''')Then Begin
  I:=2;
  While(I<=Length(Line))And(Line[I]In[' ',#9])Do Inc(I);
  Nm:='';
  While(I<=Length(Line))And Not(Line[I]In[' ',#9])And(Length(Nm)<15)Do Begin
   Nm:=Nm+Line[I];
   Inc(I);
  End;
  If(Nm='')Or(Nm[1]='\')Then Exit;
  Rest:=Copy(Line,I,255);
  While(Rest<>'')And(Rest[1]In[' ',#9])Do Rest:=Copy(Rest,2,255);
  DoRequest(Nm,Rest,C='.',Expanded);
 End
  Else
 Begin
  If Expanded Then TextLine(Line)
              Else TextLine(Expand(Line,0));
 End;
End;

Procedure RunStack;
Var
 L:String;
Begin
 While(FTop>0)And Not ExitNow Do Begin
  If Not GetLine(L)Then Break;
  ProcessLine(L,False);
 End;
End;

{ ------------------------- Macros et options ------------------------- }

Procedure AddTmacDir(Const D:String);Begin
 If(D<>'')And(TmacCnt<MaxDirs)Then Begin
  Inc(TmacCnt);
  TmacDirs[TmacCnt]:=Copy(D,1,127);
 End;
End;

Function FindTmac(Const Name:String):String;
Var
 I:Integer;
 R:String;
Begin
 FindTmac:='';
 For I:=1 to TmacCnt Do Begin
  R:=FSearch('tmac.'+Name,TmacDirs[I]);
  If R=''Then R:=FSearch(Name+'.tmac',TmacDirs[I]);
  If R<>''Then Begin
   FindTmac:=R;
   Exit;
  End;
 End;
End;

Procedure LoadPackage(Const Name:String);
Var
 P:String;
Begin
 P:=FindTmac(Name);
 If P<>''Then Begin
  If PushFile(P)Then RunStack;
 End
 Else If(Name='an')Or(Name='man')Or(Name='andoc')Then Begin
  PushBuiltin;
  RunStack;
 End
 Else Warn('paquetage de macros introuvable: tmac.'+Name);
End;

Procedure DefineOpt(Const V:String;IsReg:Boolean);
Var
 K:Integer;
 Nm,Vl:String;
Begin
 K:=Pos('=',V);
 If K>0Then Begin
  Nm:=Copy(V,1,K-1);
  Vl:=Copy(V,K+1,255);
 End
  Else
 Begin
  Nm:=Copy(V,1,1);
  Vl:=Copy(V,2,255);
 End;
 If Nm=''Then Exit;
 If IsReg Then SetReg(Nm,Apply(0,Vl,'u'))
          Else SetStr(Nm,Vl);
End;

Procedure ShowPipeline;
Var
 S:String;
 I:Integer;
Begin
 S:='';
 If PreS Then S:=S+'soelim | ';
 If PreR Then S:=S+'refer | ';
 If PreP Then S:=S+'pic | ';
 If PreT Then S:=S+'tbl | ';
 If PreE Then S:=S+'eqn | ';
 S:=S+'troff';
 For I:=1 to PkgCnt Do S:=S+' -m'+Pkgs[I];
 S:=S+' -T'+Dev;
 For I:=1 to FileCnt Do S:=S+' '+FileNames[I];
 If Not OptZZ Then Begin
  If(Dev='ascii')Or(Dev='latin1')Or(Dev='utf8')Or(Dev='cp1047')Then S:=S+' | grotty'
  Else If Dev='dvi'Then S:=S+' | grodvi'
  Else If Dev='html'Then S:=S+' | post-grohtml'
  Else If Dev='ps'Then S:=S+' | grops'
  Else S:=S+' | grops';
 End;
 WriteLn(S);
End;

Var
 I,J,K:Integer;
 Arg,V:String;
 C:Char;
 Env:String;
 Any:Boolean;

BEGIN
 Dev:='ascii';
 FirstPage:=1;
 PageSel:='';
 FTop:=0;
 IeTop:=0;
 TmacCnt:=0;
 PkgCnt:=0;
 FileCnt:=0;
 LL:=1560;
 LT:=1560;
 PO:=0;
 PL:=11*UI;
 PageLines:=PL Div UH;
 Indent:=0;
 PrevIn:=0;
 Fill:=True;
 AdjMode:='b';
 SrcLine:=0;
 CurFile:='';
 I:=1;
 While I<=ParamCount Do Begin
  Arg:=ParamStr(I);
  If(Arg='/?')Or(Arg='--help')Or(Arg='/h')Or(Arg='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If Arg='--version'Then Arg:='-v';
  If(Length(Arg)>1)And(Arg[1]='-')Then Begin
   J:=2;
   While J<=Length(Arg)Do Begin
    C:=Arg[J];
    Inc(J);
    Case C of
     't':PreT:=True;
     'p':PreP:=True;
     'e':PreE:=True;
     's':PreS:=True;
     'R':PreR:=True;
     'z':OptSupp:=True;
     'Z':OptZZ:=True;
     'a':OptA:=True;
     'i':OptI:=True;
     'V':OptV:=True;
     'E':OptE:=True;
     'b','l','C','N','X':;
     'h':Begin
      ShowHelp;
      Halt(0);
     End;
     'v':OptVer:=True;
     'w','W','m','F','T','f','M','d','r','n','o','P':Begin
      If J<=Length(Arg)Then V:=Copy(Arg,J,255)
       Else
      Begin
       Inc(I);
       If I<=ParamCount Then V:=ParamStr(I)
                        Else V:='';
      End;
      J:=Length(Arg)+1;
      Case C of
       'm':If PkgCnt<8Then Begin
        Inc(PkgCnt);
        Pkgs[PkgCnt]:=Copy(V,1,15);
       End;
       'F','M':Begin
        AddTmacDir(V);
        AddTmacDir(V+'/tmac');
       End;
       'T':Dev:=Copy(V,1,15);
       'd':DefineOpt(V,False);
       'r':DefineOpt(V,True);
       'n':Val(V,FirstPage,K);
       'o':PageSel:=Copy(V,1,100);
      End;
     End;
     Else Begin
      WriteLn('groff: option inconnue: -',C);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
   If Arg='-'Then Begin
    Inc(FileCnt);
    FileNames[FileCnt]:='-';
   End;
  End
   Else
  Begin
   If FileCnt<MaxFiles Then Begin
    Inc(FileCnt);
    FileNames[FileCnt]:=Copy(Arg,1,127);
   End;
  End;
  Inc(I);
 End;
 If OptVer Then Begin
  WriteLn('GNU groff version 1.19.2 (clone)');
  WriteLn('GNU troff version 1.19.2 (clone)');
  Halt(0);
 End;
 Utf:=(Dev='utf8');
 Inter:=OptZZ Or Not(OptA Or(Dev='ascii')Or(Dev='latin1')Or(Dev='utf8')Or(Dev='cp1047'));
 If OptV Then Begin
  ShowPipeline;
  Halt(0);
 End;
 PageNo:=FirstPage;
 SetStr('.T',Dev);
 AddTmacDir('.');
 Env:=GetEnv('GROFF_TMAC_PATH');
 While Env<>''Do Begin
  K:=Pos(';',Env);
  If K=0Then Begin
   AddTmacDir(Env);
   Env:='';
  End
   Else
  Begin
   AddTmacDir(Copy(Env,1,K-1));
   Env:=Copy(Env,K+1,255);
  End;
 End;
 For I:=1 to PkgCnt Do LoadPackage(Pkgs[I]);
 Any:=False;
 For I:=1 to FileCnt Do Begin
  If ExitNow Then Break;
  If FileNames[I]='-'Then V:=''
                     Else V:=FileNames[I];
  Any:=True;
  If PushFile(V)Then RunStack
   Else Begin
    {$IFDEF FPC}
    WriteLn(StdErr,'groff: impossible d''ouvrir ',FileNames[I]);
    {$ELSE}
    WriteLn('groff: impossible d''ouvrir ',FileNames[I]);
    {$ENDIF}
   End;
 End;
 If(Not Any)Or OptI Then Begin
  If PushFile('')Then RunStack;
 End;
 BreakLine;
 If PageOpen Then ClosePage;
 If DocStarted And Inter And Not OptSupp Then Begin
  WriteLn('x trailer');
  WriteLn('V',PL);
  WriteLn('x stop');
 End;
END.
