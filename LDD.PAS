{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande ldd - Liste les dependances dynamiques d'objets ELF
}

Program LDD;

{$X+}
{$M 32768,0,655360}

Uses DOS;

Const
 HexDigits:String[16]='0123456789abcdef';
 MaxNeed=48;
 MaxLibs=120;
 MaxLoad=16;
 MaxDirs=96;
 MaxFiles=32;
 DT_PLTRELSZ=2;
 DT_HASH=4;
 DT_SYMTAB=6;
 DT_RELA=7;
 DT_RELASZ=8;
 DT_REL=17;
 DT_RELSZ=18;
 DT_PLTREL=20;
 DT_JMPREL=23;
 MaxUndef=200;
 DT_NULL=0;
 DT_NEEDED=1;
 DT_STRTAB=5;
 DT_SONAME=14;
 DT_RPATH=15;
 DT_RUNPATH=29;
 PT_LOAD=1;
 PT_DYNAMIC=2;
 PT_INTERP=3;

Type
 TElf=Record
  Ok,Dyn,Is64,BE:Boolean;
  Interp:String[127];
  NNeed:Integer;
  Need:Array[1..MaxNeed]Of String[63];
  RPath,RunPath:String[255];
  Origin:String[127];
  SymOff,SymN,StrOff:Longint;
  RelaOff,RelaSz,RelOff,RelSz,JmpOff,JmpSz:Longint;
  JmpIsRela:Boolean;
 End;
 TLib=Record
  Name:String[63];
  Path:String[127];
  Req:String[127];
 End;

Type
 TLibArr=Array[1..MaxLibs]Of TLib;
 TDirArr=Array[1..MaxDirs]Of String[127];
 TUNameArr=Array[1..MaxUndef]Of String[63];
 TUOwnArr=Array[1..MaxUndef]Of String[127];
 TUFoundArr=Array[1..MaxUndef]Of Boolean;
 PLibs=^TLibArr;
 PDirs=^TDirArr;
 PUName=^TUNameArr;
 PUOwn=^TUOwnArr;
 PUFound=^TUFoundArr;

Var
 F:File;
 Libs:PLibs;
 LibCnt:Integer;
 Dirs:PDirs;
 DirCnt:Integer;
 LdPath:String;
 MainRPath:String;
 ErrCount:Integer;
 Names:Array[1..MaxFiles]Of String[127];
 NameCnt:Integer;
 LoadVA,LoadOff,LoadSz:Array[1..MaxLoad]Of Longint;
 LoadCnt:Integer;
 OptD,OptR,OptS,OptI:Boolean;
 UName:PUName;
 UOwn:PUOwn;
 UFound:PUFound;
 UCnt:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: ldd [ -d | -r ] [ -f ] [ -i ] [ -l ] [ -s ] [ -v ] filename');
End;

Procedure ShowHelp;Begin
 WriteLn('LDD : Cette commande permet d''afficher la liste des dependances dynamiques ',
         'des fichiers executables ou des objets partages.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -v          Affiche les informations de version et quitte');
 WriteLn('  -V          Affiche les informations de version du resolveur de liens (ld.so)');
 WriteLn('  -d          Effectue les deplacements et signale les fonctions et objets manquants');
 WriteLn('  -r          Identique a -d: deplacements, objets et fonctions manquants');
 WriteLn('  -s          Affiche le chemin de recherche et les repertoires essayes');
 WriteLn('  -i          Affiche l''ordre d''initialisation des objets (approximation)');
 WriteLn('  -f -l       Acceptees, sans effet (pas de fichier illisible ni de liaison');
 WriteLn('              differee a gerer ici)');
 WriteLn('  (les symboles manquants sont ecrits sur la sortie d''erreur)');
 WriteLn('  --help      Affiche cette aide');
 WriteLn;
 WriteLn('Les bibliotheques sont cherchees dans RPATH, LD_LIBRARY_PATH, RUNPATH,');
 WriteLn('/etc/ld.so.conf et les repertoires systeme usuels.');
End;

Procedure Msg(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'ldd: ',S);
 {$ELSE}
 WriteLn('ldd: ',S);
 {$ENDIF}
 Inc(ErrCount);
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

Function HexStr(N:Longint;Digits:Integer):String;
Var
 S:String;
 I:Integer;
Begin
 S:='';
 For I:=1 to Digits Do Begin
  S:=HexDigits[(N And 15)+1]+S;
  N:=(N Shr 4)And $0FFFFFFF;
 End;
 HexStr:=S;
End;

Function FakeAddr(Idx:Integer):String;Begin
 FakeAddr:='0x00007f8a'+HexStr(Longint(Idx)*$200000+$10000,8);
End;

{ ------------------------- Lecture ELF ------------------------- }

Function GetU(Off:Longint;Size:Integer;BE:Boolean):Longint;
Var
 B:Array[0..7]Of Byte;
 N:Word;
 I,Lo:Integer;
 V:Longint;
Begin
 GetU:=0;
 If Off<0Then Exit;
 Seek(F,Off);
 FillChar(B,SizeOf(B),0);
 BlockRead(F,B,Size,N);
 If N<>Size Then Exit;
 V:=0;
 If Not BE Then Begin
  If Size>4Then Lo:=4
           Else Lo:=Size;
  For I:=Lo-1 downto 0 Do V:=(V Shl 8)Or B[I];
 End
  Else
 Begin
  If Size>4Then Lo:=Size-4
           Else Lo:=0;
  For I:=Lo to Size-1 Do V:=(V Shl 8)Or B[I];
 End;
 GetU:=V;
End;

Function GetStr(Off:Longint):String;
Var
 S:String;
 C:Byte;
 N:Word;
Begin
 S:='';
 If Off>=0Then Begin
  Seek(F,Off);
  While Length(S)<250Do Begin
   BlockRead(F,C,1,N);
   If(N<>1)Or(C=0)Then Break;
   S:=S+Chr(C);
  End;
 End;
 GetStr:=S;
End;

Function VaToOff(VA:Longint):Longint;
Var
 I:Integer;
Begin
 VaToOff:=-1;
 For I:=1 to LoadCnt Do
  If(VA>=LoadVA[I])And(VA<LoadVA[I]+LoadSz[I])Then Begin
   VaToOff:=VA-LoadVA[I]+LoadOff[I];
   Exit;
  End;
End;

Function DirOf(Const P:String):String;
Var
 I:Integer;
Begin
 I:=Length(P);
 While(I>0)And Not(P[I]In['/','\'])Do Dec(I);
 If I=0Then DirOf:='.'
       Else If I=1Then DirOf:=Copy(P,1,1)
       Else DirOf:=Copy(P,1,I-1);
End;

{ Analyse un fichier ELF; retourne False si le fichier ne peut pas etre ouvert }
Function ParseElf(Const Path:String;Var E:TElf):Boolean;
Var
 Id:Array[0..15]Of Byte;
 N:Word;
 ShOff,ShEnt,ShNum,SecType,SecSize,SecEnt:Longint;
 VSym,VHash,VRela,VRel,VJmp:Longint;
 Sz,PhOff,PhEnt,PhNum,I,Cnt:Longint;
 PType,POff,PVa,PFileSz,DynOff,DynSz,EntSz,Tag,Val_,StrVA,StrOff:Longint;
 NeedOff:Array[1..MaxNeed]Of Longint;
 NN:Integer;
 RP,RU:Longint;
 Base,HdrSz:Longint;
 W:Integer;
Begin
 ParseElf:=False;
 E.Ok:=False;
 E.Dyn:=False;
 E.NNeed:=0;
 E.SymN:=0;
 E.Interp:='';
 E.RPath:='';
 E.RunPath:='';
 E.Origin:=DirOf(Path);
 LoadCnt:=0;
 Assign(F,Path);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0Then Exit;
 ParseElf:=True;
 Sz:=FileSize(F);
 If Sz<52Then Begin
  Close(F);
  Exit;
 End;
 BlockRead(F,Id,16,N);
 If(Id[0]<>$7F)Or(Id[1]<>Ord('E'))Or(Id[2]<>Ord('L'))Or(Id[3]<>Ord('F'))Then Begin
  Close(F);
  Exit;
 End;
 E.Ok:=True;
 E.Is64:=Id[4]=2;
 E.BE:=Id[5]=2;
 If E.Is64 Then Begin
  PhOff:=GetU(32,8,E.BE);
  PhEnt:=GetU(54,2,E.BE);
  PhNum:=GetU(56,2,E.BE);
 End
  Else
 Begin
  PhOff:=GetU(28,4,E.BE);
  PhEnt:=GetU(42,2,E.BE);
  PhNum:=GetU(44,2,E.BE);
 End;
 DynOff:=-1;
 DynSz:=0;
 For I:=0 to PhNum-1 Do Begin
  Base:=PhOff+I*PhEnt;
  PType:=GetU(Base,4,E.BE);
  If E.Is64 Then Begin
   POff:=GetU(Base+8,8,E.BE);
   PVa:=GetU(Base+16,8,E.BE);
   PFileSz:=GetU(Base+32,8,E.BE);
  End
   Else
  Begin
   POff:=GetU(Base+4,4,E.BE);
   PVa:=GetU(Base+8,4,E.BE);
   PFileSz:=GetU(Base+16,4,E.BE);
  End;
  If(PType=PT_LOAD)And(LoadCnt<MaxLoad)Then Begin
   Inc(LoadCnt);
   LoadVA[LoadCnt]:=PVa;
   LoadOff[LoadCnt]:=POff;
   LoadSz[LoadCnt]:=PFileSz;
  End
  Else If PType=PT_DYNAMIC Then Begin
   DynOff:=POff;
   DynSz:=PFileSz;
  End
  Else If PType=PT_INTERP Then E.Interp:=Copy(GetStr(POff),1,127);
 End;
 If DynOff<0Then Begin
  Close(F);
  Exit;
 End;
 E.Dyn:=True;
 If E.Is64 Then EntSz:=16
          Else EntSz:=8;
 If E.Is64 Then W:=8
          Else W:=4;
 NN:=0;
 StrVA:=0;
 VSym:=0;VHash:=0;VRela:=0;VRel:=0;VJmp:=0;
 E.RelaSz:=0;E.RelSz:=0;E.JmpSz:=0;E.JmpIsRela:=True;
 E.SymOff:=-1;E.SymN:=0;E.StrOff:=-1;E.RelaOff:=-1;E.RelOff:=-1;E.JmpOff:=-1;
 RP:=-1;
 RU:=-1;
 Cnt:=DynSz Div EntSz;
 For I:=0 to Cnt-1 Do Begin
  Tag:=GetU(DynOff+I*EntSz,W,E.BE);
  Val_:=GetU(DynOff+I*EntSz+W,W,E.BE);
  If Tag=DT_NULL Then Break;
  If Tag=DT_NEEDED Then Begin
   If NN<MaxNeed Then Begin
    Inc(NN);
    NeedOff[NN]:=Val_;
   End;
  End
  Else If Tag=DT_STRTAB Then StrVA:=Val_
  Else If Tag=DT_SYMTAB Then VSym:=Val_
  Else If Tag=DT_HASH Then VHash:=Val_
  Else If Tag=DT_RELA Then VRela:=Val_
  Else If Tag=DT_RELASZ Then E.RelaSz:=Val_
  Else If Tag=DT_REL Then VRel:=Val_
  Else If Tag=DT_RELSZ Then E.RelSz:=Val_
  Else If Tag=DT_JMPREL Then VJmp:=Val_
  Else If Tag=DT_PLTRELSZ Then E.JmpSz:=Val_
  Else If Tag=DT_PLTREL Then E.JmpIsRela:=(Val_=7)
  Else If Tag=DT_RPATH Then RP:=Val_
  Else If Tag=DT_RUNPATH Then RU:=Val_;
 End;
 StrOff:=VaToOff(StrVA);
 If StrOff<0Then StrOff:=StrVA;
 For I:=1 to NN Do E.Need[I]:=Copy(GetStr(StrOff+NeedOff[I]),1,63);
 E.NNeed:=NN;
 E.StrOff:=StrOff;
 If VSym<>0Then E.SymOff:=VaToOff(VSym);
 If VRela<>0Then E.RelaOff:=VaToOff(VRela);
 If VRel<>0Then E.RelOff:=VaToOff(VRel);
 If VJmp<>0Then E.JmpOff:=VaToOff(VJmp);
 { nombre de symboles: sections .dynsym, puis DT_HASH, puis heuristique }
 If E.Is64 Then Begin
  ShOff:=GetU(40,8,E.BE);
  ShEnt:=GetU(58,2,E.BE);
  ShNum:=GetU(60,2,E.BE);
 End
  Else
 Begin
  ShOff:=GetU(32,4,E.BE);
  ShEnt:=GetU(46,2,E.BE);
  ShNum:=GetU(48,2,E.BE);
 End;
 For I:=0 to ShNum-1 Do Begin
  Base:=ShOff+I*ShEnt;
  SecType:=GetU(Base+4,4,E.BE);
  If SecType=11Then Begin
   If E.Is64 Then Begin
    SecSize:=GetU(Base+32,8,E.BE);
    SecEnt:=GetU(Base+56,8,E.BE);
   End
    Else
   Begin
    SecSize:=GetU(Base+20,4,E.BE);
    SecEnt:=GetU(Base+36,4,E.BE);
   End;
   If SecEnt>0Then E.SymN:=SecSize Div SecEnt;
  End;
 End;
 If(E.SymN=0)And(VHash<>0)Then Begin
  HdrSz:=VaToOff(VHash);
  If HdrSz>=0Then E.SymN:=GetU(HdrSz+4,4,E.BE);
 End;
 If(E.SymN=0)And(E.SymOff>=0)And(StrOff>E.SymOff)Then Begin
  If E.Is64 Then E.SymN:=(StrOff-E.SymOff)Div 24
            Else E.SymN:=(StrOff-E.SymOff)Div 16;
 End;
 If RP>=0Then E.RPath:=Copy(GetStr(StrOff+RP),1,255);
 If RU>=0Then E.RunPath:=Copy(GetStr(StrOff+RU),1,255);
 Close(F);
End;

{ ------------------------- Recherche des bibliotheques ------------------------- }

Procedure AddDir(Const D:String);
Var
 I:Integer;
Begin
 If(D='')Or(DirCnt>=MaxDirs)Then Exit;
 For I:=1 to DirCnt Do If Dirs^[I]=D Then Exit;
 Inc(DirCnt);
 Dirs^[DirCnt]:=Copy(D,1,127);
End;

Procedure ReadConf(Const Path:String;Depth:Integer);
Var
 T:Text;
 L,Dir,Pat:String;
 SR:SearchRec;
 P:Integer;
Begin
 If Depth>3Then Exit;
 Assign(T,Path);
 {$I-}Reset(T);{$I+}
 If IOResult<>0Then Exit;
 While Not EOF(T)Do Begin
  ReadLn(T,L);
  P:=Pos('#',L);
  If P>0Then L:=Copy(L,1,P-1);
  L:=Trim(L);
  If L=''Then Continue;
  If Copy(L,1,8)='include 'Then Begin
   Pat:=Trim(Copy(L,9,200));
   P:=Length(Pat);
   While(P>0)And(Pat[P]<>'/')Do Dec(P);
   If P>0Then Dir:=Copy(Pat,1,P)
         Else Dir:='';
   FindFirst(Pat,AnyFile,SR);
   While DosError=0Do Begin
    If(SR.Attr And Directory)=0Then ReadConf(Dir+SR.Name,Depth+1);
    FindNext(SR);
   End;
  End
   Else
  AddDir(L);
 End;
 Close(T);
End;

Procedure InitDirs;Begin
 DirCnt:=0;
 ReadConf('/etc/ld.so.conf',0);
 AddDir('/lib');
 AddDir('/usr/lib');
 AddDir('/lib64');
 AddDir('/usr/lib64');
 AddDir('/lib/x86_64-linux-gnu');
 AddDir('/usr/lib/x86_64-linux-gnu');
 AddDir('/lib/i386-linux-gnu');
 AddDir('/usr/lib/i386-linux-gnu');
 AddDir('/lib/aarch64-linux-gnu');
 AddDir('/usr/lib/aarch64-linux-gnu');
 AddDir('/usr/local/lib');
 LdPath:=GetEnv('LD_LIBRARY_PATH');
End;

Function Replace(Const S,Old,New:String):String;
Var
 P:Integer;
 R:String;
Begin
 R:=S;
 P:=Pos(Old,R);
 While P>0Do Begin
  R:=Copy(R,1,P-1)+New+Copy(R,P+Length(Old),255);
  P:=Pos(Old,R);
 End;
 Replace:=R;
End;

Function SearchList(Const Name,List,Origin,Why:String):String;
Var
 L,D:String;
 P:Integer;
 R:String;
Begin
 SearchList:='';
 L:=List;
 If OptS And(List<>'')Then WriteLn('  search path=',List,' (',Why,')');
 While L<>''Do Begin
  P:=Pos(':',L);
  If P=0Then Begin
   D:=L;
   L:='';
  End
   Else
  Begin
   D:=Copy(L,1,P-1);
   L:=Copy(L,P+1,255);
  End;
  D:=Replace(Replace(D,'${ORIGIN}',Origin),'$ORIGIN',Origin);
  If D=''Then D:='.';
  If OptS Then WriteLn('  trying path=',D,'/',Name);
  R:=FSearch(Name,D);
  If R<>''Then Begin
   SearchList:=R;
   Exit;
  End;
 End;
End;

Function FileOK(Const P:String):Boolean;
Var
 T:File;
 Ok:Boolean;
Begin
 Assign(T,P);
 {$I-}Reset(T,1);{$I+}
 Ok:=IOResult=0;
 If Ok Then Close(T);
 FileOK:=Ok;
End;

Function Resolve(Const Name,Req:String;Const E:TElf):String;
Var
 R,Joined:String;
 I:Integer;
Begin
 Resolve:='';
 If OptS Then WriteLn('find object=',Name,'; required by ',Req);
 If Pos('/',Name)>0Then Begin
  If FileOK(Name)Then Resolve:=Name;
  Exit;
 End;
 If E.RunPath=''Then Begin
  R:=SearchList(Name,E.RPath,E.Origin,'RPATH from file '+Req);
  If R=''Then R:=SearchList(Name,MainRPath,E.Origin,'RPATH from main file');
  If R<>''Then Begin
   Resolve:=R;
   Exit;
  End;
 End;
 R:=SearchList(Name,LdPath,E.Origin,'LD_LIBRARY_PATH');
 If R<>''Then Begin
  Resolve:=R;
  Exit;
 End;
 R:=SearchList(Name,E.RunPath,E.Origin,'RUNPATH from file '+Req);
 If R<>''Then Begin
  Resolve:=R;
  Exit;
 End;
 If OptS Then Begin
  Joined:='';
  For I:=1 to DirCnt Do Begin
   If Joined<>''Then Joined:=Joined+':';
   If Length(Joined)+Length(Dirs^[I])<250Then Joined:=Joined+Dirs^[I];
  End;
  WriteLn('  search path=',Joined,' (default)');
 End;
 For I:=1 to DirCnt Do Begin
  If OptS Then WriteLn('  trying path=',Dirs^[I],'/',Name);
  R:=FSearch(Name,Dirs^[I]);
  If R<>''Then Begin
   Resolve:=R;
   Exit;
  End;
 End;
End;

Function BaseName(Const P:String):String;
Var
 I:Integer;
Begin
 I:=Length(P);
 While(I>0)And Not(P[I]In['/','\'])Do Dec(I);
 BaseName:=Copy(P,I+1,255);
End;

Function SeenLib(Const Name:String):Boolean;
Var
 I:Integer;
Begin
 SeenLib:=False;
 For I:=1 to LibCnt Do If Libs^[I].Name=Name Then SeenLib:=True;
End;

Procedure AddNeeds(Const E:TElf;Const Req:String);
Var
 I:Integer;
Begin
 For I:=1 to E.NNeed Do
  If Not SeenLib(E.Need[I])And(LibCnt<MaxLibs)Then Begin
   Inc(LibCnt);
   Libs^[LibCnt].Name:=E.Need[I];
   Libs^[LibCnt].Path:='';
   Libs^[LibCnt].Req:=Copy(Req,1,127);
  End;
End;

{ ------------------------- Verification des symboles (-d / -r) ------------------------- }

Function SymSize(Const E:TElf):Integer;Begin
 If E.Is64 Then SymSize:=24
           Else SymSize:=16;
End;

Procedure ReadSym(Const E:TElf;Idx:Longint;Var Name:String;Var Info:Integer;Var Shndx:Longint);
Var
 B:Longint;
Begin
 B:=E.SymOff+Idx*SymSize(E);
 If E.Is64 Then Begin
  Info:=GetU(B+4,1,E.BE);
  Shndx:=GetU(B+6,2,E.BE);
 End
  Else
 Begin
  Info:=GetU(B+12,1,E.BE);
  Shndx:=GetU(B+14,2,E.BE);
 End;
 Name:=Copy(GetStr(E.StrOff+GetU(B,4,E.BE)),1,63);
End;

Procedure AddUndef(Const Name,Owner:String);
Var
 I:Integer;
Begin
 If(Name='')Or(UCnt>=MaxUndef)Then Exit;
 For I:=1 to UCnt Do If UName^[I]=Name Then Exit;
 Inc(UCnt);
 UName^[UCnt]:=Name;
 UOwn^[UCnt]:=Copy(Owner,1,127);
 UFound^[UCnt]:=False;
End;

{ Parcourt une table de relocations et note les symboles globaux non definis }
Procedure ScanRelocs(Const E:TElf;Off,Sz:Longint;IsRela:Boolean;Const Owner:String);
Var
 EntSz,I,Base,SymIdx,Info,Shndx:Longint;
 Nm:String;
 Inf:Integer;
Begin
 If(Off<0)Or(Sz<=0)Or(E.SymOff<0)Then Exit;
 If E.Is64 Then Begin
  If IsRela Then EntSz:=24
            Else EntSz:=16;
 End
  Else
 Begin
  If IsRela Then EntSz:=12
            Else EntSz:=8;
 End;
 For I:=0 to Sz Div EntSz-1 Do Begin
  Base:=Off+I*EntSz;
  If E.Is64 Then Begin
   If E.BE Then SymIdx:=GetU(Base+8,4,True)
           Else SymIdx:=GetU(Base+12,4,False);
  End
   Else
  Begin
   Info:=GetU(Base+4,4,E.BE);
   SymIdx:=(Info Shr 8)And $FFFFFF;
  End;
  If SymIdx>0Then Begin
   ReadSym(E,SymIdx,Nm,Inf,Shndx);
   If(Shndx=0)And((Inf Shr 4)=1)Then AddUndef(Nm,Owner);
  End;
 End;
End;

Procedure CollectUndef(Const Path:String;Const E:TElf;Funcs:Boolean);Begin
 Assign(F,Path);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0Then Exit;
 ScanRelocs(E,E.RelaOff,E.RelaSz,True,Path);
 ScanRelocs(E,E.RelOff,E.RelSz,False,Path);
 If Funcs Then ScanRelocs(E,E.JmpOff,E.JmpSz,E.JmpIsRela,Path);
 Close(F);
End;

Procedure ResolveDefs(Const Path:String;Const E:TElf);
Var
 I:Longint;
 J,Inf:Integer;
 Shndx:Longint;
 Nm:String;
 Left:Integer;
Begin
 If(E.SymOff<0)Or(E.SymN=0)Then Exit;
 Assign(F,Path);
 {$I-}Reset(F,1);{$I+}
 If IOResult<>0Then Exit;
 For I:=1 to E.SymN-1 Do Begin
  Left:=0;
  For J:=1 to UCnt Do If Not UFound^[J]Then Inc(Left);
  If Left=0Then Break;
  ReadSym(E,I,Nm,Inf,Shndx);
  If(Shndx<>0)And(((Inf Shr 4)=1)Or((Inf Shr 4)=2))Then
   For J:=1 to UCnt Do If(Not UFound^[J])And(UName^[J]=Nm)Then UFound^[J]:=True;
 End;
 Close(F);
End;

Procedure CheckSymbols(Const MainPath:String;Const ME:TElf);
Var
 L:TElf;
 I:Integer;
Begin
 UCnt:=0;
 CollectUndef(MainPath,ME,OptR);
 For I:=1 to LibCnt Do
  If Libs^[I].Path<>''Then
   If ParseElf(Libs^[I].Path,L)Then
    If L.Ok And L.Dyn Then CollectUndef(Libs^[I].Path,L,OptR);
 ResolveDefs(MainPath,ME);
 For I:=1 to LibCnt Do
  If Libs^[I].Path<>''Then
   If ParseElf(Libs^[I].Path,L)Then
    If L.Ok And L.Dyn Then ResolveDefs(Libs^[I].Path,L);
 For I:=1 to UCnt Do
  If Not UFound^[I]Then Begin
   {$IFDEF FPC}
   WriteLn(StdErr,'undefined symbol: ',UName^[I],#9,'(',UOwn^[I],')');
   {$ELSE}
   WriteLn('undefined symbol: ',UName^[I],#9,'(',UOwn^[I],')');
   {$ENDIF}
  End;
End;

Procedure DoFile(Const Name:String;Header:Boolean);
Var
 E,L:TElf;
 I:Integer;
 P:String;
 IBase:String;
Begin
 If Not ParseElf(Name,E)Then Begin
  Msg(Name+': No such file or directory');
  Exit;
 End;
 If Header Then WriteLn(Name,':');
 If Not E.Ok Or Not E.Dyn Then Begin
  WriteLn(#9,'not a dynamic executable');
  Inc(ErrCount);
  Exit;
 End;
 MainRPath:=E.RPath;
 If E.RunPath<>''Then MainRPath:=E.RunPath;
 LibCnt:=0;
 AddNeeds(E,Name);
 IBase:=BaseName(E.Interp);
 I:=1;
 While I<=LibCnt Do Begin
  If(Libs^[I].Name<>IBase)Then Begin
   P:=Resolve(Libs^[I].Name,Libs^[I].Req,E);
   Libs^[I].Path:=P;
   If P<>''Then Begin
    If ParseElf(P,L)Then Begin
     If L.Ok And L.Dyn Then AddNeeds(L,P);
    End;
   End;
  End;
  Inc(I);
 End;
 For I:=1 to LibCnt Do Begin
  If Libs^[I].Name=IBase Then Continue;
  If Libs^[I].Path=''Then WriteLn(#9,Libs^[I].Name,' => not found')
   Else
  WriteLn(#9,Libs^[I].Name,' => ',Libs^[I].Path,' (',FakeAddr(I),')');
 End;
 If E.Interp<>''Then WriteLn(#9,E.Interp,' (',FakeAddr(LibCnt+1),')');
 If OptI Then
  For I:=LibCnt downto 1 Do
   If(Libs^[I].Path<>'')And(Libs^[I].Name<>IBase)Then WriteLn(#9,'init object=',Libs^[I].Path);
 If OptD Or OptR Then CheckSymbols(Name,E);
End;

Var
 I,J:Integer;
 A:String;

BEGIN
 ErrCount:=0;
 NameCnt:=0;
 New(Libs);
 New(Dirs);
 New(UName);
 New(UOwn);
 New(UFound);
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If A='--version'Then A:='-v';
  If(Length(A)>1)And(A[1]='-')Then Begin
   For J:=2 to Length(A)Do Begin
    Case A[J]of
     'd','r':Begin
      OptD:=True;
      OptR:=True;
     End;
     's':OptS:=True;
     'i':OptI:=True;
     'f','l':;
     'v':Begin
      WriteLn('ldd (GNU libc clone) 1.0');
      Halt(0);
     End;
     'V':Begin
      WriteLn('ld.so (GNU libc clone) 1.0');
      Halt(0);
     End;
     Else Begin
      WriteLn('ldd: option inconnue: -',A[J]);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
  End
   Else
  Begin
   If NameCnt<MaxFiles Then Begin
    Inc(NameCnt);
    Names[NameCnt]:=Copy(A,1,127);
   End;
  End;
 End;
 If NameCnt=0Then Begin
  WriteLn('ldd: missing file arguments');
  ShowUsage;
  Halt(1);
 End;
 InitDirs;
 For I:=1 to NameCnt Do DoFile(Names[I],NameCnt>1);
 If ErrCount>0Then Halt(1);
END.
