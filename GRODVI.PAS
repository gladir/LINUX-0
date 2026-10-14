{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande grodvi - Convertit la sortie groff au format TeX dvi
}

Program GRODVI;

{$X+}

Uses DOS;

Const
 MaxCache=16;
 MaxDF=60;
 MaxMount=64;
 MaxChars=300;
 MaxDirs=24;
 MaxArgs=40;

Type
 TFont=Record
  Name:String[15];
  Int:String[31];
  Design:Real;
  UnitW:Longint;
  NC:Integer;
  CN:Array[1..MaxChars]Of String[7];
  CW:Array[1..MaxChars]Of Longint;
  CC:Array[1..MaxChars]Of Integer;
 End;
 PFont=^TFont;
 TDF=Record
  Int:String[31];
  Scaled,Design:Longint;
 End;

Var
 OptD:Boolean;
 LineW:Integer;
 Dirs:Array[1..MaxDirs]Of String[127];
 DirCnt:Integer;
 Cache:Array[1..MaxCache]Of PFont;
 CacheCnt:Integer;
 Mount:Array[0..MaxMount]Of String[15];
 DF:Array[0..MaxDF-1]Of TDF;
 DFCnt:Integer;
 CurDF:Integer;
 Res:Longint;
 SizeScale,UnitWDesc:Longint;
 H,V,Dh,Dv:Longint;
 Size:Real;
 FontPos:Integer;
 Thick:Longint;
 Started,InPage,Finished:Boolean;
 LastBop,PosCount:Longint;
 TotPages:Integer;
 Buf:String;
 Arg:Array[1..MaxArgs]Of Longint;
 NArg:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: grodvi [ -dv ] [ -wn ] [ -Fdir ] [ files ... ]');
End;

Procedure ShowHelp;Begin
 WriteLn('GRODVI : Cette commande permet d''effectuer la conversion de la sortie groff ',
         'a celle du format TeX dvi.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -d          Pas de specials de dessin: lignes horizontales/verticales en regles,');
 WriteLn('              autres commandes de dessin ignorees');
 WriteLn('  -v          Affiche le numero de version');
 WriteLn('  -wn         Epaisseur des lignes en milliemes d''em (defaut: 40)');
 WriteLn('  -Fdir       Ajoute dir/devdvi au chemin de recherche des polices');
 WriteLn('  files       Fichiers a traiter (defaut: entree standard)');
 WriteLn('  /?, --help  Affiche cette aide');
 WriteLn;
 WriteLn('Le fichier DVI est ecrit sur la sortie standard (redirigez-la).');
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

Function WordAt(Const S:String;N:Integer):String;
Var
 I,J,K:Integer;
Begin
 I:=1;
 K:=0;
 While I<=Length(S)Do Begin
  While(I<=Length(S))And(S[I]In[' ',#9,#13])Do Inc(I);
  If I>Length(S)Then Break;
  J:=I;
  While(J<=Length(S))And Not(S[J]In[' ',#9,#13])Do Inc(J);
  Inc(K);
  If K=N Then Begin
   WordAt:=Copy(S,I,J-I);
   Exit;
  End;
  I:=J;
 End;
 WordAt:='';
End;

Function ToLong(Const S:String;Def:Longint):Longint;
Var
 N:Longint;
 Err:Integer;
Begin
 Val(S,N,Err);
 If Err<>0Then ToLong:=Def
          Else ToLong:=N;
End;

{ ------------------------- Ecriture binaire DVI ------------------------- }

Procedure FlushBuf;Begin
 If Length(Buf)>0Then Write(Buf);
 Buf:='';
End;

Procedure PutB(B:Longint);Begin
 Buf:=Buf+Chr(B And 255);
 Inc(PosCount);
 If Length(Buf)>=250Then FlushBuf;
End;

Procedure PutL4(N:Longint);Begin
 PutB((N Shr 24)And 255);
 PutB((N Shr 16)And 255);
 PutB((N Shr 8)And 255);
 PutB(N And 255);
End;

Procedure PutW2(N:Longint);Begin
 PutB((N Shr 8)And 255);
 PutB(N And 255);
End;

Procedure Special(Const S:String);
Var
 I:Integer;
Begin
 PutB(239);
 PutB(Length(S));
 For I:=1 to Length(S)Do PutB(Ord(S[I]));
End;

Procedure MoveCmd(Base:Longint;D:Longint);
Var
 A:Longint;
Begin
 If D=0Then Exit;
 A:=D;
 If A<0Then A:=-A;
 If A<127Then Begin
  PutB(Base);
  PutB(D);
 End
 Else If A<32767Then Begin
  PutB(Base+1);
  PutW2(D);
 End
 Else If A<8388607Then Begin
  PutB(Base+2);
  PutB((D Shr 16)And 255);
  PutW2(D);
 End
 Else Begin
  PutB(Base+3);
  PutL4(D);
 End;
End;

Procedure GotoXY(X,Y:Longint);Begin
 MoveCmd(143,X-Dh);
 Dh:=X;
 MoveCmd(157,Y-Dv);
 Dv:=Y;
End;

{ ------------------------- Polices ------------------------- }

Function FindFile(Const Name:String):String;
Var
 I:Integer;
 R:String;
Begin
 FindFile:='';
 For I:=1 to DirCnt Do Begin
  R:=FSearch(Name,Dirs[I]);
  If R<>''Then Begin
   FindFile:=R;
   Exit;
  End;
 End;
End;

Procedure AddDir(Const D:String);Begin
 If(D<>'')And(DirCnt<MaxDirs)Then Begin
  Inc(DirCnt);
  Dirs[DirCnt]:=Copy(D,1,127);
 End;
End;

Function DefaultInternal(Const N:String):String;Begin
 If N='R'Then DefaultInternal:='cmr10'
 Else If N='I'Then DefaultInternal:='cmti10'
 Else If N='B'Then DefaultInternal:='cmbx10'
 Else If N='BI'Then DefaultInternal:='cmbxti10'
 Else If N='S'Then DefaultInternal:='cmsy10'
 Else DefaultInternal:=N;
End;

Function DesignFromName(Const N:String):Real;
Var
 I:Integer;
 V:Longint;
Begin
 I:=Length(N);
 While(I>0)And(N[I]In['0'..'9'])Do Dec(I);
 V:=ToLong(Copy(N,I+1,5),10);
 If V<1Then V:=10;
 DesignFromName:=V;
End;

Procedure ReadDesc;
Var
 F:Text;
 L,P:String;
Begin
 P:=FindFile('DESC');
 If P=''Then Exit;
 Assign(F,P);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Exit;
 While Not EOF(F)Do Begin
  ReadLn(F,L);
  If WordAt(L,1)='res'Then Res:=ToLong(WordAt(L,2),Res)
  Else If WordAt(L,1)='unitwidth'Then UnitWDesc:=ToLong(WordAt(L,2),UnitWDesc)
  Else If WordAt(L,1)='sizescale'Then SizeScale:=ToLong(WordAt(L,2),SizeScale);
 End;
 Close(F);
 If SizeScale<1Then SizeScale:=1;
 If UnitWDesc<1Then UnitWDesc:=10;
End;

Function LoadFont(Const Name:String):PFont;
Var
 I,K,C:Integer;
 P,L,W1,W2:String;
 F:Text;
 Fnt:PFont;
 InChars:Boolean;
 Wd:Longint;
Begin
 LoadFont:=Nil;
 For I:=1 to CacheCnt Do If Cache[I]^.Name=Name Then Begin
  LoadFont:=Cache[I];
  Exit;
 End;
 If CacheCnt>=MaxCache Then Exit;
 New(Fnt);
 Fnt^.Name:=Copy(Name,1,15);
 Fnt^.Int:=DefaultInternal(Name);
 Fnt^.UnitW:=UnitWDesc;
 Fnt^.NC:=0;
 Fnt^.Design:=0;
 P:=FindFile(Name);
 If P<>''Then Begin
  Assign(F,P);
  {$I-}Reset(F);{$I+}
  If IOResult=0Then Begin
   InChars:=False;
   While Not EOF(F)Do Begin
    ReadLn(F,L);
    K:=Pos('#',L);
    If K>0Then L:=Copy(L,1,K-1);
    If Trim(L)=''Then Continue;
    If Not InChars Then Begin
     If WordAt(L,1)='internalname'Then Fnt^.Int:=Copy(WordAt(L,2),1,31)
     Else If WordAt(L,1)='designsize'Then Fnt^.Design:=ToLong(WordAt(L,2),0)
     Else If(WordAt(L,1)='charset')Then InChars:=True;
    End
     Else
    Begin
     W1:=WordAt(L,2);
     If Fnt^.NC<MaxChars Then Begin
      If W1='"'Then Begin
       If Fnt^.NC>0Then Begin
        Inc(Fnt^.NC);
        Fnt^.CN[Fnt^.NC]:=Copy(WordAt(L,1),1,7);
        Fnt^.CW[Fnt^.NC]:=Fnt^.CW[Fnt^.NC-1];
        Fnt^.CC[Fnt^.NC]:=Fnt^.CC[Fnt^.NC-1];
       End;
      End
       Else
      Begin
       K:=Pos(',',W1);
       If K>0Then W1:=Copy(W1,1,K-1);
       Wd:=ToLong(W1,0);
       W2:=WordAt(L,1);
       C:=ToLong(WordAt(L,4),0);
       Inc(Fnt^.NC);
       Fnt^.CN[Fnt^.NC]:=Copy(WordAt(L,1),1,7);
       Fnt^.CW[Fnt^.NC]:=Wd;
       If(C=0)And(Length(W2)=1)Then C:=Ord(W2[1]);
       Fnt^.CC[Fnt^.NC]:=C;
      End;
     End;
    End;
   End;
   Close(F);
  End;
 End;
 If Fnt^.Design<=0Then Fnt^.Design:=DesignFromName(Fnt^.Int);
 Inc(CacheCnt);
 Cache[CacheCnt]:=Fnt;
 LoadFont:=Fnt;
End;

{ ------------------------- Pages DVI ------------------------- }

Procedure WritePreamble;
Var
 I:Integer;
 Cmt:String;
Begin
 Cmt:='grodvi (clone)';
 PutB(247);
 PutB(2);
 PutL4(254000);
 PutL4(Res);
 PutL4(1000);
 PutB(Length(Cmt));
 For I:=1 to Length(Cmt)Do PutB(Ord(Cmt[I]));
 Started:=True;
End;

Procedure EndPage;Begin
 If InPage Then PutB(140);
 InPage:=False;
End;

Procedure BeginPage(N:Longint);
Var
 I:Integer;
 Here:Longint;
Begin
 If Not Started Then WritePreamble;
 EndPage;
 Here:=PosCount;
 PutB(139);
 PutL4(N);
 For I:=1 to 9Do PutL4(0);
 PutL4(LastBop);
 LastBop:=Here;
 InPage:=True;
 Inc(TotPages);
 H:=0;
 V:=0;
 Dh:=0;
 Dv:=0;
 CurDF:=-1;
End;

Procedure PutFntDef(K:Integer);
Var
 I:Integer;
Begin
 PutB(243);
 PutB(K);
 PutL4(0);
 PutL4(DF[K].Scaled);
 PutL4(DF[K].Design);
 PutB(0);
 PutB(Length(DF[K].Int));
 For I:=1 to Length(DF[K].Int)Do PutB(Ord(DF[K].Int[I]));
End;

Function CurName:String;Begin
 If(FontPos>=0)And(FontPos<=MaxMount)And(Mount[FontPos]<>'')Then CurName:=Mount[FontPos]
                                                            Else CurName:='R';
End;

Procedure SelectFont;
Var
 Fnt:PFont;
 Int:String;
 SU,DU:Longint;
 I,K:Integer;
 Dsg:Real;
Begin
 Fnt:=LoadFont(CurName);
 If Fnt<>Nil Then Begin
  Int:=Fnt^.Int;
  Dsg:=Fnt^.Design;
 End
  Else
 Begin
  Int:=DefaultInternal(CurName);
  Dsg:=DesignFromName(Int);
 End;
 SU:=Round(Size*Res/72.27);
 DU:=Round(Dsg*Res/72.27);
 K:=-1;
 For I:=0 to DFCnt-1 Do If(DF[I].Int=Int)And(DF[I].Scaled=SU)Then K:=I;
 If K<0Then Begin
  If DFCnt>=MaxDF Then K:=0
   Else
  Begin
   K:=DFCnt;
   Inc(DFCnt);
   DF[K].Int:=Copy(Int,1,31);
   DF[K].Scaled:=SU;
   DF[K].Design:=DU;
   PutFntDef(K);
  End;
 End;
 If CurDF<>K Then Begin
  PutB(171+K);
  CurDF:=K;
 End;
End;

{ ------------------------- Caracteres ------------------------- }

Function LookupChar(Const Name:String;Var Code:Integer;Var W:Longint):Boolean;
Var
 Fnt:PFont;
 I:Integer;
Begin
 LookupChar:=False;
 Fnt:=LoadFont(CurName);
 If Fnt<>Nil Then
  For I:=1 to Fnt^.NC Do If Fnt^.CN[I]=Name Then Begin
   Code:=Fnt^.CC[I];
   W:=Round(Fnt^.CW[I]*Size/Fnt^.UnitW);
   LookupChar:=True;
   Exit;
  End;
 If Length(Name)=1Then Begin
  Code:=Ord(Name[1]);
  W:=Round(Size*Res/72.27*0.5);
  LookupChar:=True;
 End;
End;

Procedure OutName(Const Name:String);
Var
 Code:Integer;
 W:Longint;
Begin
 If Not InPage Then Exit;
 If Not LookupChar(Name,Code,W)Then Exit;
 GotoXY(H,V);
 SelectFont;
 PutB(133);
 PutB(Code);
 H:=H+W;
End;

{ ------------------------- Dessin ------------------------- }

Function PenSize:Longint;Begin
 If Thick>=0Then PenSize:=Thick
  Else PenSize:=Round(LineW*Size*Res/72.27/1000);
End;

Function Milli(D:Longint):Longint;Begin
 Milli:=Round(D*1000.0/Res);
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

Function FStr(R:Real):String;
Var
 S:String;
Begin
 Str(R:0:4,S);
 FStr:=S;
End;

Procedure PenSpecial;Begin
 Special('pn '+IntStr(Milli(PenSize)));
End;

Procedure DrawRule(X,Y,Hgt,Wid:Longint);Begin
 GotoXY(X,Y);
 PutB(137);
 PutL4(Hgt);
 PutL4(Wid);
End;

Procedure DrawLine(DX,DY:Longint);
Var
 T:Longint;
Begin
 T:=PenSize;
 If OptD Then Begin
  If DY=0Then Begin
   If DX>=0Then DrawRule(H,V+T Div 2,T,DX)
           Else DrawRule(H+DX,V+T Div 2,T,-DX);
  End
  Else If DX=0Then Begin
   If DY>=0Then DrawRule(H-T Div 2,V+DY,DY,T)
           Else DrawRule(H-T Div 2,V,-DY,T);
  End;
 End
  Else
 Begin
  GotoXY(H,V);
  PenSpecial;
  Special('pa 0 0');
  Special('pa '+IntStr(Milli(DX))+' '+IntStr(Milli(DY)));
  Special('fp');
 End;
 H:=H+DX;
 V:=V+DY;
End;

Procedure DrawPoly(Closed,Fill,Spline:Boolean);
Var
 I:Integer;
 X,Y:Longint;
Begin
 If OptD Then Exit;
 GotoXY(H,V);
 PenSpecial;
 If Fill Then Special('sh 0.5');
 Special('pa 0 0');
 X:=0;
 Y:=0;
 I:=1;
 While I+1<=NArg Do Begin
  X:=X+Arg[I];
  Y:=Y+Arg[I+1];
  Special('pa '+IntStr(Milli(X))+' '+IntStr(Milli(Y)));
  Inc(I,2);
 End;
 If Closed Then Special('pa 0 0');
 If Spline Then Special('sp')
           Else Special('fp');
 H:=H+X;
 V:=V+Y;
End;

Procedure DrawCmd(Sub:Char);
Var
 R,A1,A2:Real;
 CX,CY:Longint;
Begin
 Case Sub of
  'l':If NArg>=2Then DrawLine(Arg[1],Arg[2]);
  'c':If NArg>=1Then Begin
   If Not OptD Then Begin
    GotoXY(H,V);
    PenSpecial;
    Special('ar '+IntStr(Milli(Arg[1]Div 2))+' 0 '+IntStr(Milli(Arg[1]Div 2))+' '+
            IntStr(Milli(Arg[1]Div 2))+' 0 6.28319');
   End;
   H:=H+Arg[1];
  End;
  'e':If NArg>=2Then Begin
   If Not OptD Then Begin
    GotoXY(H,V);
    PenSpecial;
    Special('ar '+IntStr(Milli(Arg[1]Div 2))+' 0 '+IntStr(Milli(Arg[1]Div 2))+' '+
            IntStr(Milli(Arg[2]Div 2))+' 0 6.28319');
   End;
   H:=H+Arg[1];
  End;
  'a':If NArg>=4Then Begin
   If Not OptD Then Begin
    GotoXY(H,V);
    PenSpecial;
    R:=Sqrt(Sqr(Arg[1]*1.0)+Sqr(Arg[2]*1.0));
    A1:=ArcTan2_(-Arg[2],-Arg[1]);
    A2:=ArcTan2_(Arg[4],Arg[3]);
    { tpic : angles croissants dans le sens horaire (y vers le bas) }
    R:=A1;
    A1:=A2;
    A2:=R;
    While A2<=A1 Do A2:=A2+2*Pi;
    CX:=Arg[1];
    CY:=Arg[2];
    Special('ar '+IntStr(Milli(CX))+' '+IntStr(Milli(CY))+' '+
            IntStr(Milli(Round(Sqrt(Sqr(Arg[1]*1.0)+Sqr(Arg[2]*1.0)))))+' '+
            IntStr(Milli(Round(Sqrt(Sqr(Arg[1]*1.0)+Sqr(Arg[2]*1.0)))))+' '+
            FStr(A1)+' '+FStr(A2));
   End;
   H:=H+Arg[1]+Arg[3];
   V:=V+Arg[2]+Arg[4];
  End;
  'p':DrawPoly(True,False,False);
  'P':DrawPoly(True,True,False);
  '~':DrawPoly(False,False,True);
  't':If NArg>=1Then Thick:=Arg[1];
 End;
End;

{ ------------------------- Analyse de la sortie groff ------------------------- }

Procedure ReadInt(Const L:String;Var I:Integer;Var N:Longint);
Var
 Neg:Boolean;
Begin
 N:=0;
 Neg:=False;
 While(I<=Length(L))And(L[I]In[' ',#9])Do Inc(I);
 If(I<=Length(L))And(L[I]='-')Then Begin
  Neg:=True;
  Inc(I);
 End;
 While(I<=Length(L))And(L[I]In['0'..'9'])Do Begin
  N:=N*10+Ord(L[I])-48;
  Inc(I);
 End;
 If Neg Then N:=-N;
End;

Procedure ReadWord(Const L:String;Var I:Integer;Var W:String);Begin
 W:='';
 While(I<=Length(L))And Not(L[I]In[' ',#9,#13])Do Begin
  W:=W+L[I];
  Inc(I);
 End;
End;

Procedure XCommand(Const S:String);
Var
 Cmd:String;
 N:Longint;
Begin
 Cmd:=WordAt(S,1);
 If Cmd='res'Then Begin
  N:=ToLong(WordAt(S,2),Res);
  If N>0Then Res:=N;
 End
 Else If Cmd='font'Then Begin
  N:=ToLong(WordAt(S,2),-1);
  If(N>=0)And(N<=MaxMount)Then Mount[N]:=Copy(WordAt(S,3),1,15);
 End
 Else If Cmd='trailer'Then EndPage
 Else If Cmd='stop'Then Begin
  EndPage;
  Finished:=True;
 End;
End;

Procedure ProcessLine(Const L:String);
Var
 I,J,K:Integer;
 C:Char;
 N,M:Longint;
 W:String;
Begin
 I:=1;
 While I<=Length(L)Do Begin
  C:=L[I];
  Case C of
   ' ',#9,#13:Inc(I);
   '#':I:=Length(L)+1;
   '0'..'9':Begin
    If I+2<=Length(L)Then Begin
     N:=(Ord(L[I])-48)*10+Ord(L[I+1])-48;
     H:=H+N;
     OutName(L[I+2]);
    End;
    Inc(I,3);
   End;
   's':Begin
    Inc(I);
    ReadInt(L,I,N);
    Size:=N/SizeScale;
    If Size<1Then Size:=1;
   End;
   'f':Begin
    Inc(I);
    ReadInt(L,I,N);
    FontPos:=N;
   End;
   'H':Begin
    Inc(I);
    ReadInt(L,I,N);
    H:=N;
   End;
   'V':Begin
    Inc(I);
    ReadInt(L,I,N);
    V:=N;
   End;
   'h':Begin
    Inc(I);
    ReadInt(L,I,N);
    H:=H+N;
   End;
   'v':Begin
    Inc(I);
    ReadInt(L,I,N);
    V:=V+N;
   End;
   'c':Begin
    Inc(I);
    If I<=Length(L)Then OutName(L[I]);
    Inc(I);
   End;
   'C':Begin
    Inc(I);
    While(I<=Length(L))And(L[I]=' ')Do Inc(I);
    ReadWord(L,I,W);
    OutName(W);
   End;
   't':Begin
    Inc(I);
    ReadWord(L,I,W);
    For K:=1 to Length(W)Do OutName(W[K]);
   End;
   'u':Begin
    Inc(I);
    ReadInt(L,I,N);
    While(I<=Length(L))And(L[I]=' ')Do Inc(I);
    ReadWord(L,I,W);
    For K:=1 to Length(W)Do Begin
     OutName(W[K]);
     H:=H+N;
    End;
   End;
   'n':Begin
    Inc(I);
    ReadInt(L,I,N);
    ReadInt(L,I,M);
   End;
   'p':Begin
    Inc(I);
    ReadInt(L,I,N);
    BeginPage(N);
   End;
   'w':Inc(I);
   'D':Begin
    Inc(I);
    If I<=Length(L)Then Begin
     C:=L[I];
     Inc(I);
     NArg:=0;
     While I<=Length(L)Do Begin
      J:=I;
      While(J<=Length(L))And(L[J]=' ')Do Inc(J);
      If J>Length(L)Then Break;
      If Not(L[J]In['0'..'9','-'])Then Break;
      I:=J;
      ReadInt(L,I,N);
      If NArg<MaxArgs Then Begin
       Inc(NArg);
       Arg[NArg]:=N;
      End;
     End;
     If InPage Then DrawCmd(C);
    End;
   End;
   'x':Begin
    XCommand(Trim(Copy(L,I+1,255)));
    I:=Length(L)+1;
   End;
   Else Inc(I);
  End;
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
  {$IFDEF FPC}
  WriteLn(StdErr,'grodvi: impossible d''ouvrir ',Name);
  {$ELSE}
  WriteLn('grodvi: impossible d''ouvrir ',Name);
  {$ENDIF}
  Exit;
 End;
 While Not EOF(F)Do Begin
  ReadLn(F,L);
  ProcessLine(L);
 End;
 Close(F);
End;

Procedure Finish;
Var
 I:Integer;
 PostPos:Longint;
 K:Integer;
Begin
 EndPage;
 If Not Started Then WritePreamble;
 PostPos:=PosCount;
 PutB(248);
 PutL4(LastBop);
 PutL4(254000);
 PutL4(Res);
 PutL4(1000);
 PutL4(Round(11.0*Res));
 PutL4(Round(8.5*Res));
 PutW2(2);
 PutW2(TotPages);
 For I:=0 to DFCnt-1 Do PutFntDef(I);
 PutB(249);
 PutL4(PostPos);
 PutB(2);
 K:=4;
 While(PosCount+K)Mod 4<>0Do Inc(K);
 For I:=1 to K Do PutB(223);
 FlushBuf;
End;

Var
 I,J,Cnt:Integer;
 A,V_,Env:String;
 FileNames:Array[1..32]Of String[127];
 N:Integer;

BEGIN
 Res:=57816;
 SizeScale:=1;
 UnitWDesc:=10;
 LineW:=40;
 Size:=10;
 FontPos:=1;
 Thick:=-1;
 LastBop:=-1;
 PosCount:=0;
 Buf:='';
 CurDF:=-1;
 Cnt:=0;
 DirCnt:=0;
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(A='/?')Or(A='--help')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If(Length(A)>1)And(A[1]='-')Then Begin
   J:=2;
   While J<=Length(A)Do Begin
    Case A[J]of
     'd':Begin
      OptD:=True;
      Inc(J);
     End;
     'v':Begin
      WriteLn('GNU grodvi (clone) version 1.0');
      Halt(0);
     End;
     'w':Begin
      V_:=Copy(A,J+1,255);
      If V_=''Then Begin
       Inc(I);
       If I<=ParamCount Then V_:=ParamStr(I);
      End;
      LineW:=ToLong(V_,40);
      J:=Length(A)+1;
     End;
     'F':Begin
      V_:=Copy(A,J+1,255);
      If V_=''Then Begin
       Inc(I);
       If I<=ParamCount Then V_:=ParamStr(I);
      End;
      AddDir(V_+'/devdvi');
      AddDir(V_);
      J:=Length(A)+1;
     End;
     Else Begin
      WriteLn('grodvi: option inconnue: -',A[J]);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
  End
   Else
  Begin
   If Cnt<32Then Begin
    Inc(Cnt);
    FileNames[Cnt]:=Copy(A,1,127);
   End;
  End;
  Inc(I);
 End;
 Env:=GetEnv('GROFF_FONT_PATH');
 While Env<>''Do Begin
  N:=Pos(';',Env);
  If N=0Then Begin
   AddDir(Env+'/devdvi');
   Env:='';
  End
   Else
  Begin
   AddDir(Copy(Env,1,N-1)+'/devdvi');
   Env:=Copy(Env,N+1,255);
  End;
 End;
 AddDir('devdvi');
 AddDir('.');
 ReadDesc;
 If Cnt=0Then ProcessFile('')
  Else
 For N:=1 to Cnt Do ProcessFile(FileNames[N]);
 Finish;
END.
