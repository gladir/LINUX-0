{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande gpic - Compilateur d'images pic pour troff ou TeX
}

Program GPIC;

{$X+}

Uses DOS;

Const
 MaxObj=150;
 MaxTok=200;
 MaxVar=64;
 MaxPts=16;
 MaxStack=16;
 KBox=1;
 KCircle=2;
 KEllipse=3;
 KArc=4;
 KLine=5;
 KSpline=6;
 KMove=7;
 KText=8;

Type
 TObj=Record
  Kind:Integer;
  X,Y,W,H,R:Real;
  NP:Integer;
  PX,PY:Array[0..MaxPts-1]Of Real;
  Arrow,Style:Integer;
  Dash,Fill,Thick:Real;
  CW:Boolean;
  CX,CY:Real;
  NT:Integer;
  Txt:Array[1..4]Of String[60];
  TAl,TVa:Array[1..4]Of Integer;
  Lbl:String[31];
 End;
 PObj=^TObj;

Var
 Objs:Array[1..MaxObj]Of PObj;
 ObjCnt:Integer;
 CurX,CurY,DirX,DirY:Real;
 StX,StY,StDX,StDY:Array[1..MaxStack]Of Real;
 StTop:Integer;
 VarName:Array[1..MaxVar]Of String[15];
 VarVal:Array[1..MaxVar]Of Real;
 VarCnt:Integer;
 Tk:Array[1..MaxTok]Of String[63];
 TKind:Array[1..MaxTok]Of Integer;  { 1 nombre, 2 identifiant, 3 chaine, 4 ponctuation }
 TNum:Array[1..MaxTok]Of Real;
 NTk,TP:Integer;
 LineNo:Longint;
 Failed:Boolean;
 OptN,OptC,OptT,OptCap,OptZ:Boolean;
 PicW,PicH:Real;
 MinX,MinY,MaxX,MaxY:Real;
 Sc,PicHeight:Real;

Procedure ShowUsage;Begin
 WriteLn('Usage: gpic [ -nvC ] [ filename ... ]');
 WriteLn('       gpic -t [ -cvzC ] [ filename ... ]');
End;

Procedure ShowHelp;Begin
 WriteLn('GPIC : Cette commande permet de compiler des images pour le troff ou le TeX.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -n          N''utilise pas les extensions groff des commandes de dessin');
 WriteLn('  -v          Affiche la version');
 WriteLn('  -C          Mode de compatibilite (.PS/.PE suivis d''autres caracteres)');
 WriteLn('  -t          Genere du code TeX (tpic) au lieu de troff');
 WriteLn('  -c          Avec -t : accepte .PS/.PE commencant par un point');
 WriteLn('  -z          Avec -t : dessine les points avec des lignes de longueur nulle');
 WriteLn('  filename    Fichier(s) source (defaut: entree standard)');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Err(Const Msg:String);Begin
 If Not Failed Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,'gpic: ligne ',LineNo,': ',Msg);
  {$ELSE}
  WriteLn('gpic: ligne ',LineNo,': ',Msg);
  {$ENDIF}
 End;
 Failed:=True;
 TP:=NTk+1;
End;

Function IntStr(N:Longint):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

Function F3(R:Real):String;
Var
 S:String;
Begin
 Str(R:0:3,S);
 If S='-0.000'Then S:='0.000';
 F3:=S;
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

Function IsAlpha(C:Char):Boolean;Begin
 IsAlpha:=C In['A'..'Z','a'..'z','_'];
End;

Function IsDigit(C:Char):Boolean;Begin
 IsDigit:=C In['0'..'9'];
End;

Function Cur:String;Begin
 If TP<=NTk Then Cur:=Tk[TP]
            Else Cur:='';
End;

Function CurKind:Integer;Begin
 If TP<=NTk Then CurKind:=TKind[TP]
            Else CurKind:=0;
End;

Function Peek(N:Integer):String;Begin
 If TP+N<=NTk Then Peek:=Tk[TP+N]
              Else Peek:='';
End;

Function Is_(Const S:String):Boolean;Begin
 Is_:=(TP<=NTk)And(TKind[TP]<>3)And(Tk[TP]=S);
End;

Function Accept(Const S:String):Boolean;Begin
 Accept:=Is_(S);
 If Is_(S)Then Inc(TP);
End;

Procedure AddTok(K:Integer;Const S:String;V:Real);Begin
 If NTk<MaxTok Then Begin
  Inc(NTk);
  Tk[NTk]:=Copy(S,1,63);
  TKind[NTk]:=K;
  TNum[NTk]:=V;
 End;
End;

{ Decoupe une ligne en lexemes }
Procedure Tokenize(Const L:String);
Var
 I,J,Code:Integer;
 S:String;
 V:Real;
Begin
 NTk:=0;
 TP:=1;
 I:=1;
 While I<=Length(L)Do Begin
  If L[I]In[' ',#9,#13]Then Inc(I)
  Else If L[I]='#'Then Break
  Else If L[I]='"'Then Begin
   J:=I+1;
   S:='';
   While(J<=Length(L))And(L[J]<>'"')Do Begin
    If(L[J]='\')And(J<Length(L))And(L[J+1]='"')Then Inc(J);
    S:=S+L[J];
    Inc(J);
   End;
   AddTok(3,S,0);
   I:=J+1;
  End
  Else If IsDigit(L[I])Or((L[I]='.')And(I<Length(L))And IsDigit(L[I+1]))Then Begin
   J:=I;
   While(J<=Length(L))And(IsDigit(L[J])Or(L[J]='.'))Do Inc(J);
   S:=Copy(L,I,J-I);
   Val(S,V,Code);
   If Code<>0Then V:=0;
   AddTok(1,S,V);
   I:=J;
  End
  Else If IsAlpha(L[I])Then Begin
   J:=I;
   While(J<=Length(L))And(IsAlpha(L[J])Or IsDigit(L[J]))Do Inc(J);
   AddTok(2,Copy(L,I,J-I),0);
   I:=J;
  End
  Else Begin
   If Copy(L,I,3)='<->'Then Begin
    AddTok(4,'<->',0);
    Inc(I,3);
   End
   Else If(Copy(L,I,2)='->')Or(Copy(L,I,2)='<-')Or(Copy(L,I,2)=':=')Or
          (Copy(L,I,2)='+=')Or(Copy(L,I,2)='-=')Or(Copy(L,I,2)='*=')Or
          (Copy(L,I,2)='/=')Then Begin
    AddTok(4,Copy(L,I,2),0);
    Inc(I,2);
   End
   Else Begin
    AddTok(4,L[I],0);
    Inc(I);
   End;
  End;
 End;
End;

{ ------------------------- Variables ------------------------- }

Function FindVar(Const N:String):Integer;
Var
 I:Integer;
Begin
 FindVar:=0;
 For I:=1 to VarCnt Do If VarName[I]=N Then FindVar:=I;
End;

Procedure SetVar(Const N:String;V:Real);
Var
 I:Integer;
Begin
 I:=FindVar(N);
 If I=0Then Begin
  If VarCnt>=MaxVar Then Exit;
  Inc(VarCnt);
  I:=VarCnt;
  VarName[I]:=Copy(N,1,15);
 End;
 VarVal[I]:=V;
End;

Function GetVar(Const N:String):Real;
Var
 I:Integer;
Begin
 I:=FindVar(N);
 If I=0Then GetVar:=0
       Else GetVar:=VarVal[I];
End;

Procedure InitVars;Begin
 VarCnt:=0;
 SetVar('boxwid',0.75);
 SetVar('boxht',0.5);
 SetVar('circlerad',0.25);
 SetVar('ellipsewid',0.75);
 SetVar('ellipseht',0.5);
 SetVar('linewid',0.5);
 SetVar('lineht',0.5);
 SetVar('movewid',0.5);
 SetVar('moveht',0.5);
 SetVar('arcrad',0.25);
 SetVar('arrowwid',0.05);
 SetVar('arrowht',0.1);
 SetVar('dashwid',0.05);
 SetVar('textht',0.16);
 SetVar('textwid',0);
 SetVar('scale',1);
 SetVar('linethick',0.8);
 SetVar('maxpswid',8.5);
 SetVar('maxpsht',11);
End;

{ ------------------------- Objets, positions, expressions ------------------------- }

Function ParseExpr:Real;Forward;

Function KindOf(Const S:String):Integer;Begin
 KindOf:=0;
 If S='box'Then KindOf:=KBox
 Else If S='circle'Then KindOf:=KCircle
 Else If S='ellipse'Then KindOf:=KEllipse
 Else If S='arc'Then KindOf:=KArc
 Else If(S='line')Or(S='arrow')Then KindOf:=KLine
 Else If S='spline'Then KindOf:=KSpline
 Else If S='move'Then KindOf:=KMove;
End;

Function IsCorner(Const S:String):Boolean;Begin
 IsCorner:=(S='n')Or(S='s')Or(S='e')Or(S='w')Or(S='ne')Or(S='nw')Or(S='se')Or
           (S='sw')Or(S='c')Or(S='center')Or(S='t')Or(S='b')Or(S='l')Or(S='r')Or
           (S='top')Or(S='bottom')Or(S='left')Or(S='right')Or(S='start')Or(S='end');
End;

Function IsOrdinalSuffix(Const S:String):Boolean;Begin
 IsOrdinalSuffix:=(S='st')Or(S='nd')Or(S='rd')Or(S='th');
End;

Function FindLabel(Const N:String):Integer;
Var
 I:Integer;
Begin
 FindLabel:=0;
 For I:=ObjCnt downto 1 Do If Objs[I]^.Lbl=N Then Begin
  FindLabel:=I;
  Exit;
 End;
End;

Function IsPlaceStart:Boolean;Begin
 IsPlaceStart:=False;
 If TP>NTk Then Exit;
 If(TKind[TP]=2)And((Tk[TP]='last')Or(Tk[TP]='the'))Then IsPlaceStart:=True
 Else If(TKind[TP]=2)And(Tk[TP][1]In['A'..'Z'])And(FindLabel(Tk[TP])>0)Then IsPlaceStart:=True
 Else If(TKind[TP]=1)And IsOrdinalSuffix(Peek(1))Then IsPlaceStart:=True;
End;

{ Identifie un objet : label, "last box", "2nd circle" ... }
Function FindObj(Var Idx:Integer):Boolean;
Var
 N,K,I,C:Integer;
 FromEnd:Boolean;
Begin
 FindObj:=False;
 Idx:=0;
 Accept('the');
 If(CurKind=2)And(Tk[TP][1]In['A'..'Z'])And(FindLabel(Cur)>0)Then Begin
  Idx:=FindLabel(Cur);
  Inc(TP);
  FindObj:=True;
  Exit;
 End;
 FromEnd:=False;
 N:=1;
 If CurKind=1Then Begin
  N:=Round(TNum[TP]);
  Inc(TP);
  If IsOrdinalSuffix(Cur)Then Inc(TP);
  If Accept('last')Then FromEnd:=True;
 End
  Else
 Begin
  If Not Accept('last')Then Exit;
  FromEnd:=True;
 End;
 K:=KindOf(Cur);
 If K=0Then Begin
  Err('type d''objet attendu apres last/ordinal');
  Exit;
 End;
 Inc(TP);
 C:=0;
 If FromEnd Then Begin
  For I:=ObjCnt downto 1 Do If Objs[I]^.Kind=K Then Begin
   Inc(C);
   If C=N Then Begin
    Idx:=I;
    Break;
   End;
  End;
 End
  Else
 Begin
  For I:=1 to ObjCnt Do If Objs[I]^.Kind=K Then Begin
   Inc(C);
   If C=N Then Begin
    Idx:=I;
    Break;
   End;
  End;
 End;
 If Idx=0Then Begin
  Err('objet introuvable');
  Exit;
 End;
 FindObj:=True;
End;

Procedure CornerPos(O:PObj;Const C:String;Var X,Y:Real);
Var
 HX,HY,F:Real;
Begin
 HX:=O^.W/2;
 HY:=O^.H/2;
 F:=1;
 If(O^.Kind=KCircle)Or(O^.Kind=KEllipse)Then F:=0.70710678;
 X:=O^.X;
 Y:=O^.Y;
 If(C='start')And(O^.NP>0)Then Begin
  X:=O^.PX[0];
  Y:=O^.PY[0];
 End
 Else If(C='end')And(O^.NP>0)Then Begin
  X:=O^.PX[O^.NP-1];
  Y:=O^.PY[O^.NP-1];
 End
 Else If(C='n')Or(C='t')Or(C='top')Then Y:=O^.Y+HY
 Else If(C='s')Or(C='b')Or(C='bottom')Then Y:=O^.Y-HY
 Else If(C='e')Or(C='r')Or(C='right')Then X:=O^.X+HX
 Else If(C='w')Or(C='l')Or(C='left')Then X:=O^.X-HX
 Else If C='ne'Then Begin X:=O^.X+HX*F;Y:=O^.Y+HY*F;End
 Else If C='nw'Then Begin X:=O^.X-HX*F;Y:=O^.Y+HY*F;End
 Else If C='se'Then Begin X:=O^.X+HX*F;Y:=O^.Y-HY*F;End
 Else If C='sw'Then Begin X:=O^.X-HX*F;Y:=O^.Y-HY*F;End;
End;

{ Lit un coin optionnel (.ne) }
Function ReadCorner:String;Begin
 ReadCorner:='';
 If Is_('.')And IsCorner(Peek(1))Then Begin
  ReadCorner:=Peek(1);
  Inc(TP,2);
 End;
End;

Function ParsePlace(Var X,Y:Real):Boolean;
Var
 Idx:Integer;
 C:String;
Begin
 ParsePlace:=False;
 C:='';
 If Is_('.')And IsCorner(Peek(1))And(Peek(2)='of')Then Begin
  C:=Peek(1);
  Inc(TP,3);
 End;
 If Not FindObj(Idx)Then Exit;
 If C=''Then C:=ReadCorner;
 CornerPos(Objs[Idx],C,X,Y);
 ParsePlace:=True;
End;

Function ParseFunction(Const Nm:String):Real;
Var
 A,B,R:Real;
Begin
 Accept('(');
 A:=ParseExpr;
 B:=0;
 If Accept(',')Then B:=ParseExpr;
 If Not Accept(')')Then Err('")" attendue');
 R:=0;
 If Nm='sin'Then R:=Sin(A)
 Else If Nm='cos'Then R:=Cos(A)
 Else If Nm='sqrt'Then Begin
  If A<0Then A:=0;
  R:=Sqrt(A);
 End
 Else If Nm='abs'Then R:=Abs(A)
 Else If Nm='int'Then R:=Int(A)
 Else If Nm='exp'Then R:=Exp(A*Ln(10))
 Else If Nm='log'Then Begin
  If A>0Then R:=Ln(A)/Ln(10);
 End
 Else If Nm='atan2'Then Begin
  If A=0Then Begin
   If B<0Then R:=Pi
         Else R:=0;
  End
   Else
  Begin
   R:=ArcTan(A/B);
   If B<0Then Begin
    If A>=0Then R:=R+Pi
           Else R:=R-Pi;
   End;
  End;
 End
 Else If Nm='max'Then Begin
  If A>B Then R:=A
         Else R:=B;
 End
 Else If Nm='min'Then Begin
  If A<B Then R:=A
         Else R:=B;
 End
 Else If Nm='rand'Then R:=Frac(Abs(A)*0.6180339887);
 ParseFunction:=R;
End;

Function ParseFactor:Real;Forward;

Function ParsePrimary:Real;
Var
 Idx:Integer;
 C,Nm:String;
 X,Y:Real;
 O:PObj;
Begin
 ParsePrimary:=0;
 If CurKind=1Then Begin
  If IsOrdinalSuffix(Peek(1))Then Begin
   If Not FindObj(Idx)Then Exit;
  End
   Else
  Begin
   ParsePrimary:=TNum[TP];
   Inc(TP);
   Exit;
  End;
 End
 Else If Is_('(')Then Begin
  Inc(TP);
  ParsePrimary:=ParseExpr;
  If Not Accept(')')Then Err('")" attendue');
  Exit;
 End
 Else If Is_('-')Then Begin
  Inc(TP);
  ParsePrimary:=-ParseFactor;
  Exit;
 End
 Else If Is_('+')Then Begin
  Inc(TP);
  ParsePrimary:=ParseFactor;
  Exit;
 End
 Else If IsPlaceStart Then Begin
  If Not FindObj(Idx)Then Exit;
 End
 Else If CurKind=2Then Begin
  Nm:=Cur;
  Inc(TP);
  If Is_('(')And((Nm='sin')Or(Nm='cos')Or(Nm='sqrt')Or(Nm='abs')Or(Nm='int')Or
     (Nm='exp')Or(Nm='log')Or(Nm='atan2')Or(Nm='max')Or(Nm='min')Or(Nm='rand'))Then
   ParsePrimary:=ParseFunction(Nm)
  Else ParsePrimary:=GetVar(Nm);
  Exit;
 End
 Else Begin
  Err('expression invalide pres de "'+Cur+'"');
  Exit;
 End;
 { Attribut d'un objet : A.wid, last box.ht ... }
 O:=Objs[Idx];
 If Is_('.')Then Begin
  Nm:=Peek(1);
  If(Nm='wid')Or(Nm='width')Then Begin Inc(TP,2);ParsePrimary:=O^.W;End
  Else If(Nm='ht')Or(Nm='height')Then Begin Inc(TP,2);ParsePrimary:=O^.H;End
  Else If(Nm='rad')Or(Nm='radius')Then Begin Inc(TP,2);ParsePrimary:=O^.W/2;End
  Else If(Nm='diam')Or(Nm='diameter')Then Begin Inc(TP,2);ParsePrimary:=O^.W;End
  Else Begin
   C:=ReadCorner;
   CornerPos(O,C,X,Y);
   If Accept('.')Then Begin
    If Accept('x')Then ParsePrimary:=X
     Else
    If Accept('y')Then ParsePrimary:=Y
     Else
    Err('".x" ou ".y" attendu');
   End
    Else
   Err('attribut d''objet attendu');
  End;
 End
  Else
 Err('attribut d''objet attendu');
End;

Function ParseFactor:Real;
Var
 V,E:Real;
Begin
 V:=ParsePrimary;
 While Accept('^')Do Begin
  E:=ParsePrimary;
  If V>0Then V:=Exp(E*Ln(V))
        Else V:=0;
 End;
 ParseFactor:=V;
End;

Function ParseTerm:Real;
Var
 V,D:Real;
Begin
 V:=ParseFactor;
 While Is_('*')Or Is_('/')Or Is_('%')Do Begin
  If Accept('*')Then V:=V*ParseFactor
  Else If Accept('/')Then Begin
   D:=ParseFactor;
   If D=0Then Err('division par zero')
         Else V:=V/D;
  End
  Else Begin
   Inc(TP);
   D:=ParseFactor;
   If Round(D)=0Then Err('modulo par zero')
                Else V:=Round(V)Mod Round(D);
  End;
 End;
 ParseTerm:=V;
End;

Function ParseExpr:Real;
Var
 V:Real;
Begin
 V:=ParseTerm;
 While Is_('+')Or Is_('-')Do Begin
  If Accept('+')Then V:=V+ParseTerm
                Else Begin
                 Inc(TP);
                 V:=V-ParseTerm;
                End;
 End;
 ParseExpr:=V;
End;

{ Position : Here, (x,y), place, place +/- (x,y) }
Function ParsePos(Var X,Y:Real):Boolean;
Var
 DX,DY:Real;
 Sg:Real;
Begin
 ParsePos:=False;
 If Accept('Here')Then Begin
  X:=CurX;
  Y:=CurY;
 End
 Else If Is_('(')Then Begin
  Inc(TP);
  X:=ParseExpr;
  If Not Accept(',')Then Begin
   Err('"," attendue dans la position');
   Exit;
  End;
  Y:=ParseExpr;
  If Not Accept(')')Then Begin
   Err('")" attendue');
   Exit;
  End;
 End
 Else If Not ParsePlace(X,Y)Then Exit;
 While(Is_('+')Or Is_('-'))And(Peek(1)='(')Do Begin
  If Is_('-')Then Sg:=-1
             Else Sg:=1;
  Inc(TP,2);
  DX:=ParseExpr;
  If Not Accept(',')Then Begin
   Err('"," attendue dans la position');
   Exit;
  End;
  DY:=ParseExpr;
  If Not Accept(')')Then Begin
   Err('")" attendue');
   Exit;
  End;
  X:=X+Sg*DX;
  Y:=Y+Sg*DY;
 End;
 ParsePos:=Not Failed;
End;

{ ------------------------- Creation des objets ------------------------- }

Function IsDirWord(Const S:String):Boolean;Begin
 IsDirWord:=(S='up')Or(S='down')Or(S='left')Or(S='right');
End;

Procedure DirVec(Const S:String;Var DX,DY:Real);Begin
 DX:=0;
 DY:=0;
 If S='up'Then DY:=1
 Else If S='down'Then DY:=-1
 Else If S='left'Then DX:=-1
 Else DX:=1;
End;

Function ExprFollows:Boolean;Begin
 ExprFollows:=(CurKind=1)Or Is_('(')Or Is_('-')Or
              ((CurKind=2)And((FindVar(Cur)>0)Or IsPlaceStart));
End;

Function TextWidth(Const S:String):Real;Begin
 TextWidth:=Length(S)*0.075;
End;

Procedure ParseObject(K:Integer;Const Lbl:String;ArrowKw:Boolean);
Var
 O,Prev:PObj;
 HasAt,HasFrom,HasTo,HasWith,SegOpen,WSet,HSet:Boolean;
 AX,AY,FX,FY,TX2,TY2,V,LDX,LDY,DL,OX,OY,Len:Real;
 WC,Nm:String;
 I:Integer;
 T:TObj;

 Procedure AddPt(X,Y:Real);Begin
  If O^.NP<MaxPts Then Begin
   O^.PX[O^.NP]:=X;
   O^.PY[O^.NP]:=Y;
   Inc(O^.NP);
  End;
 End;

 Procedure EnsureStart;Begin
  If O^.NP=0Then Begin
   If HasFrom Then AddPt(FX,FY)
              Else AddPt(CurX,CurY);
  End;
 End;

 Function DefLen(DX:Real):Real;Begin
  If K=KMove Then Begin
   If DX<>0Then DefLen:=GetVar('movewid')
           Else DefLen:=GetVar('moveht');
  End
   Else
  Begin
   If DX<>0Then DefLen:=GetVar('linewid')
           Else DefLen:=GetVar('lineht');
  End;
 End;

Begin
 If ObjCnt>=MaxObj Then Begin
  Err('trop d''objets');
  Exit;
 End;
 New(O);
 FillChar(O^,SizeOf(O^),0);
 O^.Kind:=K;
 O^.Lbl:=Copy(Lbl,1,31);
 O^.Thick:=1;
 O^.Dash:=GetVar('dashwid');
 HasAt:=False;
 HasFrom:=False;
 HasTo:=False;
 HasWith:=False;
 SegOpen:=False;
 WSet:=False;
 HSet:=False;
 WC:='';
 Case K of
  KBox:Begin O^.W:=GetVar('boxwid');O^.H:=GetVar('boxht');End;
  KCircle:Begin O^.R:=GetVar('circlerad');End;
  KEllipse:Begin O^.W:=GetVar('ellipsewid');O^.H:=GetVar('ellipseht');End;
  KArc:O^.R:=GetVar('arcrad');
 End;
 If ArrowKw Then O^.Arrow:=1;
 While(TP<=NTk)And Not Is_(';')And Not Is_('}')Do Begin
  If CurKind=3Then Begin
   If O^.NT<4Then Begin
    Inc(O^.NT);
    O^.Txt[O^.NT]:=Copy(Cur,1,60);
   End;
   Inc(TP);
  End
  Else If CurKind=1Then Begin
   Err('nombre inattendu: '+Cur);
  End
  Else If IsDirWord(Cur)Then Begin
   DirVec(Cur,LDX,LDY);
   Inc(TP);
   DirX:=LDX;
   DirY:=LDY;
   If(K=KLine)Or(K=KSpline)Or(K=KMove)Then Begin
    If ExprFollows Then V:=ParseExpr
                   Else V:=DefLen(LDX);
    EnsureStart;
    If Not SegOpen Then Begin
     AddPt(O^.PX[O^.NP-1],O^.PY[O^.NP-1]);
     SegOpen:=True;
    End;
    O^.PX[O^.NP-1]:=O^.PX[O^.NP-1]+LDX*V;
    O^.PY[O^.NP-1]:=O^.PY[O^.NP-1]+LDY*V;
   End
    Else
   If ExprFollows Then V:=ParseExpr;
  End
  Else If Accept('then')Then SegOpen:=False
  Else If Accept('at')Then Begin
   If ParsePos(AX,AY)Then HasAt:=True;
  End
  Else If Accept('from')Then Begin
   If ParsePos(FX,FY)Then HasFrom:=True;
   If(O^.NP=1)And HasFrom Then Begin
    O^.PX[0]:=FX;
    O^.PY[0]:=FY;
   End;
  End
  Else If Accept('to')Then Begin
   If ParsePos(TX2,TY2)Then Begin
    If K=KArc Then HasTo:=True
     Else
    Begin
     EnsureStart;
     AddPt(TX2,TY2);
     SegOpen:=False;
    End;
   End;
  End
  Else If Accept('with')Then Begin
   WC:=ReadCorner;
   If Accept('at')Then Begin
    If ParsePos(AX,AY)Then HasWith:=True;
   End
    Else
   Err('"at" attendu apres "with"');
  End
  Else If(Cur='wid')Or(Cur='width')Then Begin
   Inc(TP);
   V:=ParseExpr;
   If K=KCircle Then O^.R:=V/2 Else O^.W:=V;
   WSet:=True;
  End
  Else If(Cur='ht')Or(Cur='height')Then Begin
   Inc(TP);
   V:=ParseExpr;
   If K=KCircle Then O^.R:=V/2 Else O^.H:=V;
   HSet:=True;
  End
  Else If(Cur='rad')Or(Cur='radius')Then Begin
   Inc(TP);
   O^.R:=ParseExpr;
  End
  Else If(Cur='diam')Or(Cur='diameter')Then Begin
   Inc(TP);
   O^.R:=ParseExpr/2;
  End
  Else If Cur='dashed'Then Begin
   Inc(TP);
   O^.Style:=1;
   If ExprFollows Then O^.Dash:=ParseExpr;
  End
  Else If Cur='dotted'Then Begin
   Inc(TP);
   O^.Style:=2;
   If ExprFollows Then O^.Dash:=ParseExpr;
  End
  Else If(Cur='invis')Or(Cur='invisible')Then Begin
   Inc(TP);
   O^.Style:=3;
  End
  Else If Cur='solid'Then Begin
   Inc(TP);
   O^.Style:=0;
  End
  Else If(Cur='fill')Or(Cur='filled')Or(Cur='shaded')Then Begin
   Inc(TP);
   O^.Fill:=0.5;
   If ExprFollows Then O^.Fill:=ParseExpr;
  End
  Else If Cur='thick'Then Begin
   Inc(TP);
   O^.Thick:=2;
   If ExprFollows Then O^.Thick:=ParseExpr;
  End
  Else If Cur='thin'Then Begin
   Inc(TP);
   O^.Thick:=0.5;
  End
  Else If Cur='chop'Then Begin
   Inc(TP);
   If ExprFollows Then V:=ParseExpr;
  End
  Else If Cur='cw'Then Begin
   Inc(TP);
   O^.CW:=True;
  End
  Else If Cur='ccw'Then Begin
   Inc(TP);
   O^.CW:=False;
  End
  Else If Cur='same'Then Begin
   Inc(TP);
   Prev:=Nil;
   For I:=ObjCnt downto 1 Do If(Prev=Nil)And(Objs[I]^.Kind=K)Then Prev:=Objs[I];
   If Prev<>Nil Then Begin
    O^.W:=Prev^.W;
    O^.H:=Prev^.H;
    O^.R:=Prev^.R;
    O^.Style:=Prev^.Style;
    O^.Dash:=Prev^.Dash;
    O^.Fill:=Prev^.Fill;
    O^.Thick:=Prev^.Thick;
    O^.Arrow:=Prev^.Arrow;
   End;
  End
  Else If Cur='->'Then Begin
   Inc(TP);
   O^.Arrow:=O^.Arrow Or 1;
  End
  Else If Cur='<-'Then Begin
   Inc(TP);
   O^.Arrow:=O^.Arrow Or 2;
  End
  Else If Cur='<->'Then Begin
   Inc(TP);
   O^.Arrow:=3;
  End
  Else If(Cur='ljust')Or(Cur='rjust')Or(Cur='center')Or(Cur='above')Or(Cur='below')Then Begin
   If O^.NT>0Then Begin
    If Cur='ljust'Then O^.TAl[O^.NT]:=1
    Else If Cur='rjust'Then O^.TAl[O^.NT]:=2
    Else If Cur='center'Then O^.TAl[O^.NT]:=0
    Else If Cur='above'Then O^.TVa[O^.NT]:=1
    Else O^.TVa[O^.NT]:=2;
   End;
   Inc(TP);
  End
  Else Err('attribut inconnu: '+Cur);
 End;
 If Failed Then Begin
  Dispose(O);
  Exit;
 End;
 { ---- Finalisation selon le type ---- }
 If(K=KLine)Or(K=KSpline)Or(K=KMove)Then Begin
  EnsureStart;
  If O^.NP<2Then Begin
   AddPt(O^.PX[0]+DirX*DefLen(DirX),O^.PY[0]+DirY*DefLen(DirX));
  End;
  OX:=(O^.PX[0]+O^.PX[O^.NP-1])/2;
  OY:=(O^.PY[0]+O^.PY[O^.NP-1])/2;
  If HasAt Then Begin
   For I:=0 to O^.NP-1 Do Begin
    O^.PX[I]:=O^.PX[I]+AX-OX;
    O^.PY[I]:=O^.PY[I]+AY-OY;
   End;
  End;
  DL:=0;
  OX:=O^.PX[O^.NP-1]-O^.PX[O^.NP-2];
  OY:=O^.PY[O^.NP-1]-O^.PY[O^.NP-2];
  If(OX<>0)Or(OY<>0)Then Begin
   If Abs(OX)>=Abs(OY)Then Begin
    If OX>0Then DirX:=1 Else DirX:=-1;
    DirY:=0;
   End
    Else
   Begin
    DirX:=0;
    If OY>0Then DirY:=1 Else DirY:=-1;
   End;
  End;
  O^.X:=(O^.PX[0]+O^.PX[O^.NP-1])/2;
  O^.Y:=(O^.PY[0]+O^.PY[O^.NP-1])/2;
  O^.W:=Abs(O^.PX[O^.NP-1]-O^.PX[0]);
  O^.H:=Abs(O^.PY[O^.NP-1]-O^.PY[0]);
  CurX:=O^.PX[O^.NP-1];
  CurY:=O^.PY[O^.NP-1];
 End
 Else If K=KArc Then Begin
  If HasFrom Then Begin
   OX:=FX;
   OY:=FY;
  End
   Else
  Begin
   OX:=CurX;
   OY:=CurY;
  End;
  If HasTo Then Begin
   Len:=Sqrt(Sqr(TX2-OX)+Sqr(TY2-OY));
   If Len=0Then Len:=0.0001;
   If O^.R*2<Len Then O^.R:=Len/2;
   DL:=Sqrt(Sqr(O^.R)-Sqr(Len/2));
   If O^.CW Then V:=-1 Else V:=1;
   O^.CX:=(OX+TX2)/2-V*DL*(TY2-OY)/Len;
   O^.CY:=(OY+TY2)/2+V*DL*(TX2-OX)/Len;
   O^.PX[0]:=OX;
   O^.PY[0]:=OY;
   O^.PX[1]:=TX2;
   O^.PY[1]:=TY2;
  End
   Else
  Begin
   If O^.CW Then V:=-1 Else V:=1;
   O^.CX:=OX-V*O^.R*DirY;
   O^.CY:=OY+V*O^.R*DirX;
   O^.PX[0]:=OX;
   O^.PY[0]:=OY;
   { vecteur centre->depart tourne de V * 90 degres }
   O^.PX[1]:=O^.CX-V*(OY-O^.CY);
   O^.PY[1]:=O^.CY+V*(OX-O^.CX);
   LDX:=DirX;
   LDY:=DirY;
   DirX:=-V*LDY;
   DirY:=V*LDX;
  End;
  O^.NP:=2;
  O^.X:=(O^.PX[0]+O^.PX[1])/2;
  O^.Y:=(O^.PY[0]+O^.PY[1])/2;
  O^.W:=Abs(O^.PX[1]-O^.PX[0]);
  O^.H:=Abs(O^.PY[1]-O^.PY[0]);
  CurX:=O^.PX[1];
  CurY:=O^.PY[1];
 End
 Else Begin
  If K=KCircle Then Begin
   O^.W:=O^.R*2;
   O^.H:=O^.R*2;
  End
  Else If K=KEllipse Then O^.R:=0
  Else If K=KText Then Begin
   For I:=1 to O^.NT Do If TextWidth(O^.Txt[I])>O^.W Then O^.W:=TextWidth(O^.Txt[I]);
   O^.H:=O^.NT*GetVar('textht');
  End;
  If HasAt Then Begin
   O^.X:=AX;
   O^.Y:=AY;
  End
  Else If HasWith Then Begin
   FillChar(T,SizeOf(T),0);
   T.Kind:=K;
   T.W:=O^.W;
   T.H:=O^.H;
   CornerPos(@T,WC,OX,OY);
   O^.X:=AX-OX;
   O^.Y:=AY-OY;
  End
  Else Begin
   If K=KText Then Begin
    O^.X:=CurX;
    O^.Y:=CurY;
   End
    Else
   Begin
    O^.X:=CurX+DirX*O^.W/2;
    O^.Y:=CurY+DirY*O^.H/2;
   End;
  End;
  If K<>KText Then Begin
   CurX:=O^.X+DirX*O^.W/2;
   CurY:=O^.Y+DirY*O^.H/2;
  End;
 End;
 Inc(ObjCnt);
 Objs[ObjCnt]:=O;
End;

{ ------------------------- Instructions ------------------------- }

Procedure SkipRest;Begin
 TP:=NTk+1;
End;

Procedure ParseStatements;
Var
 Nm,Lbl:String;
 K:Integer;
 V:Real;
 X,Y:Real;
 Op:String;
 O:PObj;
Begin
 While(TP<=NTk)And Not Failed Do Begin
  If Accept(';')Then
  Else If Is_('{')Then Begin
   Inc(TP);
   If StTop<MaxStack Then Begin
    Inc(StTop);
    StX[StTop]:=CurX;
    StY[StTop]:=CurY;
    StDX[StTop]:=DirX;
    StDY[StTop]:=DirY;
   End;
  End
  Else If Is_('}')Then Begin
   Inc(TP);
   If StTop>0Then Begin
    CurX:=StX[StTop];
    CurY:=StY[StTop];
    DirX:=StDX[StTop];
    DirY:=StDY[StTop];
    Dec(StTop);
   End;
  End
  Else If CurKind=3Then ParseObject(KText,'',False)
  Else If CurKind=2Then Begin
   Nm:=Cur;
   Lbl:='';
   If Peek(1)=':'Then Begin
    Lbl:=Nm;
    Inc(TP,2);
    Nm:=Cur;
    If Is_('(')Or Is_('Here')Or IsPlaceStart Then Begin
     If ParsePos(X,Y)Then Begin
      New(O);
      FillChar(O^,SizeOf(O^),0);
      O^.Kind:=KMove;
      O^.Lbl:=Copy(Lbl,1,31);
      O^.X:=X;
      O^.Y:=Y;
      If ObjCnt<MaxObj Then Begin
       Inc(ObjCnt);
       Objs[ObjCnt]:=O;
      End;
     End;
     Continue;
    End;
   End;
   K:=KindOf(Nm);
   If K>0Then Begin
    Inc(TP);
    ParseObject(K,Lbl,Nm='arrow');
   End
   Else If CurKind=3Then ParseObject(KText,Lbl,False)
   Else If IsDirWord(Nm)And Not(Peek(1)='=')Then Begin
    DirVec(Nm,DirX,DirY);
    Inc(TP);
   End
   Else If(Peek(1)='=')Or(Peek(1)=':=')Or(Peek(1)='+=')Or(Peek(1)='-=')Or
           (Peek(1)='*=')Or(Peek(1)='/=')Then Begin
    Op:=Peek(1);
    Inc(TP,2);
    V:=ParseExpr;
    If Op='+='Then V:=GetVar(Nm)+V
    Else If Op='-='Then V:=GetVar(Nm)-V
    Else If Op='*='Then V:=GetVar(Nm)*V
    Else If(Op='/=')And(V<>0)Then V:=GetVar(Nm)/V;
    SetVar(Nm,V);
   End
   Else If Nm='print'Then Begin
    Inc(TP);
    If CurKind=3Then WriteLn(Cur)
    Else If ExprFollows Then WriteLn(ParseExpr:0:3);
    SkipRest;
   End
   Else If(Nm='define')Or(Nm='copy')Or(Nm='for')Or(Nm='if')Or(Nm='sh')Or
           (Nm='exec')Or(Nm='reset')Or(Nm='command')Or(Nm='undef')Then
    Err('instruction non supportee: '+Nm)
   Else Err('instruction inconnue: '+Nm);
  End
  Else If Is_('[')Or Is_(']')Then Err('les blocs [ ] ne sont pas supportes')
  Else Err('syntaxe invalide pres de "'+Cur+'"');
 End;
End;

{ ------------------------- Boite englobante ------------------------- }

Procedure AddBB(X,Y:Real);Begin
 If X<MinX Then MinX:=X;
 If X>MaxX Then MaxX:=X;
 If Y<MinY Then MinY:=Y;
 If Y>MaxY Then MaxY:=Y;
End;

Procedure ObjBBox(O:PObj);
Var
 I:Integer;
 MX,MY:Real;
Begin
 Case O^.Kind of
  KBox,KCircle,KEllipse,KText:Begin
   If(O^.W>0)Or(O^.H>0)Or(O^.Kind<>KText)Then Begin
    AddBB(O^.X-O^.W/2,O^.Y-O^.H/2);
    AddBB(O^.X+O^.W/2,O^.Y+O^.H/2);
   End;
  End;
  KLine,KSpline,KMove:Begin
   For I:=0 to O^.NP-1 Do AddBB(O^.PX[I],O^.PY[I]);
   If(O^.NP=0)And(O^.Lbl='')Then AddBB(O^.X,O^.Y);
  End;
  KArc:Begin
   AddBB(O^.PX[0],O^.PY[0]);
   AddBB(O^.PX[1],O^.PY[1]);
   MX:=O^.PX[0]+O^.PX[1]-2*O^.CX;
   MY:=O^.PY[0]+O^.PY[1]-2*O^.CY;
   If(MX<>0)Or(MY<>0)Then Begin
    AddBB(O^.CX+O^.R*MX/Sqrt(MX*MX+MY*MY),O^.CY+O^.R*MY/Sqrt(MX*MX+MY*MY));
   End;
  End;
 End;
End;

{ ------------------------- Primitives de sortie ------------------------- }

Function PX_(X:Real):Real;Begin
 PX_:=Sc*(X-MinX);
End;

Function PY_(Y:Real):Real;Begin
 PY_:=PicHeight-Sc*(Y-MinY);
End;

Function Milli(R:Real):String;Begin
 Milli:=IntStr(Round(R*1000));
End;

Function Pre(X,Y:Real):String;Begin
 Pre:='\Z#\v'''+F3(PY_(Y))+'i''\h'''+F3(PX_(X))+'i''';
End;

Procedure TexPa(X,Y:Real);Begin
 Write('\special{pa ',Milli(PX_(X)),' ',Milli(PY_(Y)),'}%');
 WriteLn;
End;

Procedure RawLine(X1,Y1,X2,Y2:Real);Begin
 If OptT Then Begin
  TexPa(X1,Y1);
  TexPa(X2,Y2);
  WriteLn('\special{fp}%');
 End
  Else
 WriteLn(Pre(X1,Y1),'\D''l ',F3(Sc*(X2-X1)),'i ',F3(-Sc*(Y2-Y1)),'i''#\c');
End;

{ Segment avec style : 0 plein, 1 tirets, 2 pointille }
Procedure StyledLine(X1,Y1,X2,Y2:Real;Style:Integer;Dash:Real);
Var
 L,T,UX,UY,E:Real;
Begin
 L:=Sqrt(Sqr(X2-X1)+Sqr(Y2-Y1));
 If(Style=0)Or(L=0)Or(Dash<=0)Then Begin
  RawLine(X1,Y1,X2,Y2);
  Exit;
 End;
 If OptT And(Style=1)Then Begin
  TexPa(X1,Y1);
  TexPa(X2,Y2);
  WriteLn('\special{da ',F3(Dash*Sc),'}%');
  Exit;
 End;
 If OptT And(Style=2)And Not OptZ Then Begin
  TexPa(X1,Y1);
  TexPa(X2,Y2);
  WriteLn('\special{dt ',F3(Dash*Sc),'}%');
  Exit;
 End;
 UX:=(X2-X1)/L;
 UY:=(Y2-Y1)/L;
 T:=0;
 While T<L Do Begin
  If Style=1Then Begin
   E:=T+Dash;
   If E>L Then E:=L;
   RawLine(X1+UX*T,Y1+UY*T,X1+UX*E,Y1+UY*E);
   T:=T+2*Dash;
  End
   Else
  Begin
   RawLine(X1+UX*T,Y1+UY*T,X1+UX*T+UX*0.004,Y1+UY*T+UY*0.004);
   T:=T+Dash;
  End;
 End;
End;

Procedure ArrowHead(TX,TY,FX,FY:Real);
Var
 L,UX,UY,HT,WD:Real;
Begin
 L:=Sqrt(Sqr(TX-FX)+Sqr(TY-FY));
 If L=0Then Exit;
 UX:=(TX-FX)/L;
 UY:=(TY-FY)/L;
 HT:=GetVar('arrowht');
 WD:=GetVar('arrowwid');
 RawLine(TX,TY,TX-UX*HT-UY*WD,TY-UY*HT+UX*WD);
 RawLine(TX,TY,TX-UX*HT+UY*WD,TY-UY*HT-UX*WD);
End;

Procedure ThickOn(O:PObj);Begin
 If O^.Thick<>1Then Begin
  If OptT Then WriteLn('\special{pn ',Round(8*O^.Thick),'}%')
          Else WriteLn('\Z#\D''t ',F3(GetVar('linethick')*O^.Thick/72),'i''#\c');
 End;
End;

Procedure ThickOff(O:PObj);Begin
 If O^.Thick<>1Then Begin
  If OptT Then WriteLn('\special{pn 8}%')
          Else WriteLn('\Z#\D''t -1''#\c');
 End;
End;

Procedure DrawClosed(O:PObj);
Var
 X1,Y1,X2,Y2:Real;
Begin
 X1:=O^.X-O^.W/2;
 Y1:=O^.Y-O^.H/2;
 X2:=O^.X+O^.W/2;
 Y2:=O^.Y+O^.H/2;
 Case O^.Kind of
  KBox:Begin
   If(O^.Style=0)Then Begin
    If OptT Then Begin
     If O^.Fill>0Then WriteLn('\special{sh ',F3(1-O^.Fill),'}%');
     TexPa(X1,Y1);TexPa(X2,Y1);TexPa(X2,Y2);TexPa(X1,Y2);TexPa(X1,Y1);
     WriteLn('\special{fp}%');
    End
     Else
    Begin
     If O^.Fill>0Then WriteLn('\Z#\D''f ',Round(O^.Fill*1000),'''#\c');
     Write(Pre(X1,Y1),'\D''');
     If O^.Fill>0Then Write('P') Else Write('p');
     Write(' ',F3(Sc*O^.W),'i 0i 0i ',F3(-Sc*O^.H),'i ',F3(-Sc*O^.W),'i 0i');
     WriteLn('''#\c');
    End;
   End
    Else
   Begin
    StyledLine(X1,Y1,X2,Y1,O^.Style,O^.Dash);
    StyledLine(X2,Y1,X2,Y2,O^.Style,O^.Dash);
    StyledLine(X2,Y2,X1,Y2,O^.Style,O^.Dash);
    StyledLine(X1,Y2,X1,Y1,O^.Style,O^.Dash);
   End;
  End;
  KCircle,KEllipse:Begin
   If OptT Then Begin
    If O^.Fill>0Then Begin
     WriteLn('\special{sh ',F3(1-O^.Fill),'}%');
     WriteLn('\special{ia ',Milli(PX_(O^.X)),' ',Milli(PY_(O^.Y)),' ',
             Milli(Sc*O^.W/2),' ',Milli(Sc*O^.H/2),' 0 6.28319}%');
    End
     Else
    WriteLn('\special{ar ',Milli(PX_(O^.X)),' ',Milli(PY_(O^.Y)),' ',
            Milli(Sc*O^.W/2),' ',Milli(Sc*O^.H/2),' 0 6.28319}%');
   End
    Else
   Begin
    If O^.Fill>0Then WriteLn('\Z#\D''f ',Round(O^.Fill*1000),'''#\c');
    Write(Pre(X1,O^.Y),'\D''');
    If O^.Kind=KCircle Then Begin
     If O^.Fill>0Then Write('C') Else Write('c');
     Write(' ',F3(Sc*O^.W),'i');
    End
     Else
    Begin
     If O^.Fill>0Then Write('E') Else Write('e');
     Write(' ',F3(Sc*O^.W),'i ',F3(Sc*O^.H),'i');
    End;
    WriteLn('''#\c');
   End;
  End;
 End;
End;

Function ArcTan2_(Y,X:Real):Real;
Var
 A:Real;
Begin
 If X=0Then Begin
  If Y>=0Then ArcTan2_:=Pi/2
         Else ArcTan2_:=-Pi/2;
  Exit;
 End;
 A:=ArcTan(Y/X);
 If X<0Then Begin
  If Y>=0Then A:=A+Pi
         Else A:=A-Pi;
 End;
 ArcTan2_:=A;
End;

Procedure DrawOpen(O:PObj);
Var
 I:Integer;
 A1,A2:Real;
Begin
 Case O^.Kind of
  KLine:Begin
   For I:=1 to O^.NP-1 Do
    StyledLine(O^.PX[I-1],O^.PY[I-1],O^.PX[I],O^.PY[I],O^.Style,O^.Dash);
   If(O^.Arrow And 1)<>0Then ArrowHead(O^.PX[O^.NP-1],O^.PY[O^.NP-1],O^.PX[O^.NP-2],O^.PY[O^.NP-2]);
   If(O^.Arrow And 2)<>0Then ArrowHead(O^.PX[0],O^.PY[0],O^.PX[1],O^.PY[1]);
  End;
  KSpline:Begin
   If OptT Then Begin
    For I:=0 to O^.NP-1 Do TexPa(O^.PX[I],O^.PY[I]);
    WriteLn('\special{sp}%');
   End
    Else
   Begin
    Write(Pre(O^.PX[0],O^.PY[0]),'\D''~');
    For I:=1 to O^.NP-1 Do
     Write(' ',F3(Sc*(O^.PX[I]-O^.PX[I-1])),'i ',F3(-Sc*(O^.PY[I]-O^.PY[I-1])),'i');
    WriteLn('''#\c');
   End;
   If(O^.Arrow And 1)<>0Then ArrowHead(O^.PX[O^.NP-1],O^.PY[O^.NP-1],O^.PX[O^.NP-2],O^.PY[O^.NP-2]);
   If(O^.Arrow And 2)<>0Then ArrowHead(O^.PX[0],O^.PY[0],O^.PX[1],O^.PY[1]);
  End;
  KArc:Begin
   If OptT Then Begin
    A1:=-ArcTan2_(O^.PY[0]-O^.CY,O^.PX[0]-O^.CX);
    A2:=-ArcTan2_(O^.PY[1]-O^.CY,O^.PX[1]-O^.CX);
    If Not O^.CW Then Begin
     A1:=A1+A2;
     A2:=A1-A2;
     A1:=A1-A2;
    End;
    While A2<=A1 Do A2:=A2+2*Pi;
    WriteLn('\special{ar ',Milli(PX_(O^.CX)),' ',Milli(PY_(O^.CY)),' ',
            Milli(Sc*O^.R),' ',Milli(Sc*O^.R),' ',F3(A1),' ',F3(A2),'}%');
   End
    Else If O^.CW Then
   WriteLn(Pre(O^.PX[1],O^.PY[1]),'\D''a ',F3(Sc*(O^.CX-O^.PX[1])),'i ',
           F3(-Sc*(O^.CY-O^.PY[1])),'i ',F3(Sc*(O^.PX[0]-O^.CX)),'i ',
           F3(-Sc*(O^.PY[0]-O^.CY)),'i''#\c')
   Else
   WriteLn(Pre(O^.PX[0],O^.PY[0]),'\D''a ',F3(Sc*(O^.CX-O^.PX[0])),'i ',
           F3(-Sc*(O^.CY-O^.PY[0])),'i ',F3(Sc*(O^.PX[1]-O^.CX)),'i ',
           F3(-Sc*(O^.PY[1]-O^.CY)),'i''#\c');
   If(O^.Arrow And 1)<>0Then ArrowHead(O^.PX[1],O^.PY[1],O^.PX[1]-(O^.PY[1]-O^.CY),O^.PY[1]+(O^.PX[1]-O^.CX));
  End;
 End;
End;

Procedure DrawText(O:PObj);
Var
 I:Integer;
 Y,LH:Real;
 Body:String;
Begin
 LH:=GetVar('textht');
 For I:=1 to O^.NT Do Begin
  Y:=O^.Y+((O^.NT+1)/2-I)*LH;
  If O^.TVa[I]=1Then Y:=Y+LH/2
  Else If O^.TVa[I]=2Then Y:=Y-LH/2;
  If OptT Then Begin
   Write('\graphtemp=.5ex\advance\graphtemp by ',F3(PY_(Y)),'in\rlap{\kern ',
         F3(PX_(O^.X)),'in\lower\graphtemp\hbox to 0pt{');
   If O^.TAl[I]<>1Then Write('\hss ');
   Write(O^.Txt[I]);
   If O^.TAl[I]<>2Then Write('\hss');
   WriteLn('}}%');
  End
   Else
  Begin
   Write(Pre(O^.X,Y));
   If O^.TAl[I]=0Then Write('\h''-(\w''',O^.Txt[I],'''u/2u)''')
   Else If O^.TAl[I]=2Then Write('\h''-\w''',O^.Txt[I],'''u''');
   WriteLn(O^.Txt[I],'#\c');
  End;
 End;
End;

Procedure EmitPicture;
Var
 I:Integer;
 O:PObj;
 W,H:Real;
Begin
 If ObjCnt=0Then Exit;
 MinX:=1E30;MinY:=1E30;MaxX:=-1E30;MaxY:=-1E30;
 For I:=1 to ObjCnt Do ObjBBox(Objs[I]);
 If MaxX<MinX Then Exit;
 W:=MaxX-MinX;
 H:=MaxY-MinY;
 Sc:=1;
 If(PicW>0)And(W>0)Then Sc:=PicW/W;
 If(PicH>0)And(H>0)And((PicW<=0)Or(PicH/H<Sc))Then Sc:=PicH/H;
 If GetVar('scale')>0Then Sc:=Sc/GetVar('scale');
 PicHeight:=Sc*H;
 If OptT Then Begin
  WriteLn('\expandafter\ifx\csname graph\endcsname\relax \csname newbox\endcsname\graph\fi');
  WriteLn('\expandafter\ifx\csname graphtemp\endcsname\relax \csname newdimen\endcsname\graphtemp\fi');
  WriteLn('\setbox\graph=\vtop{\vskip 0pt\hbox{%');
  WriteLn('\special{pn 8}%');
 End
  Else
 Begin
  WriteLn('.br');
  WriteLn('.ne ',F3(Sc*H),'i');
  WriteLn('.nr 0Z \n(.u');
  WriteLn('.nf');
 End;
 For I:=1 to ObjCnt Do Begin
  O:=Objs[I];
  If(O^.Style<>3)And(O^.Kind<>KMove)And(O^.Kind<>KText)Then Begin
   ThickOn(O);
   If(O^.Kind=KBox)Or(O^.Kind=KCircle)Or(O^.Kind=KEllipse)Then DrawClosed(O)
                                                           Else DrawOpen(O);
   ThickOff(O);
  End;
  If O^.NT>0Then DrawText(O);
 End;
 If OptT Then Begin
  WriteLn('\hbox{\vrule depth ',F3(PicHeight),'in width 0pt height 0pt}%');
  WriteLn('\kern ',F3(Sc*W),'in');
  WriteLn('}%');
  WriteLn('}%');
 End
  Else
 Begin
  WriteLn('\&');
  WriteLn('.if \n(0Z .fi');
  WriteLn('.sp ',F3(Sc*H),'i');
 End;
End;

Procedure ResetPicture;
Var
 I:Integer;
Begin
 For I:=1 to ObjCnt Do Dispose(Objs[I]);
 ObjCnt:=0;
 CurX:=0;
 CurY:=0;
 DirX:=1;
 DirY:=0;
 StTop:=0;
 InitVars;
End;

{ ------------------------- Traitement des fichiers ------------------------- }

Function StartsPS(Const L:String):Boolean;Begin
 StartsPS:=False;
 If Copy(L,1,3)<>'.PS'Then Exit;
 If OptC Then StartsPS:=True
  Else StartsPS:=(Length(L)=3)Or(L[4]In[' ',#9,'0'..'9','<','.']);
End;

Function StartsPE(Const L:String):Boolean;Begin
 StartsPE:=False;
 If Copy(L,1,3)<>'.PE'Then Exit;
 If OptC Then StartsPE:=True
  Else StartsPE:=(Length(L)=3)Or(L[4]In[' ',#9]);
End;

Procedure ProcessFile(Const Name:String);
Var
 F:Text;
 Line,Next:String;
 InPic:Boolean;
Begin
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  WriteLn('gpic: impossible d''ouvrir ',Name);
  Exit;
 End;
 InPic:=False;
 LineNo:=0;
 While Not EOF(F)Do Begin
  ReadLn(F,Line);
  Inc(LineNo);
  While(Length(Line)>0)And(Line[Length(Line)]='\')And Not EOF(F)Do Begin
   ReadLn(F,Next);
   Inc(LineNo);
   Line:=Copy(Line,1,Length(Line)-1)+Next;
  End;
  If Not InPic Then Begin
   If StartsPS(Line)Then Begin
    InPic:=True;
    ResetPicture;
    PicW:=0;
    PicH:=0;
    Tokenize(Copy(Line,4,255));
    If CurKind=1Then Begin
     PicW:=TNum[TP];
     Inc(TP);
     If CurKind=1Then PicH:=TNum[TP];
    End;
   End
   Else WriteLn(Line);
  End
  Else If StartsPE(Line)Then Begin
   EmitPicture;
   InPic:=False;
  End
  Else If(Length(Line)>0)And(Line[1]='.')Then
  Else Begin
   Failed:=False;
   Tokenize(Line);
   ParseStatements;
  End;
 End;
 If InPic Then EmitPicture;
 Close(F);
End;

Var
 I,J:Integer;
 Arg:String;
 FileCnt:Integer;

BEGIN
 ObjCnt:=0;
 FileCnt:=0;
 For I:=1 to ParamCount Do Begin
  Arg:=ParamStr(I);
  If(Arg='/?')Or(Arg='--help')Or(Arg='/h')Or(Arg='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
 End;
 For I:=1 to ParamCount Do Begin
  Arg:=ParamStr(I);
  If(Length(Arg)>1)And(Arg[1]='-')Then Begin
   For J:=2 to Length(Arg)Do Case Arg[J]of
    'n':OptN:=True;
    'C':OptC:=True;
    't':OptT:=True;
    'c':OptCap:=True;
    'z':OptZ:=True;
    'v':Begin
     WriteLn('GNU pic (clone) version 1.0');
     Halt(0);
    End;
    Else Begin
     WriteLn('gpic: option inconnue: -',Arg[J]);
     ShowUsage;
     Halt(1);
    End;
   End;
  End;
 End;
 If OptCap And Not OptT Then Begin
  ShowUsage;
  Halt(1);
 End;
 If OptCap Then OptC:=True;
 ResetPicture;
 For I:=1 to ParamCount Do Begin
  Arg:=ParamStr(I);
  If Not((Length(Arg)>1)And(Arg[1]='-'))Then Begin
   Inc(FileCnt);
   ProcessFile(Arg);
  End;
 End;
 If FileCnt=0Then ProcessFile('');
END.
