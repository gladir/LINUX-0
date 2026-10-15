{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande gzexe - Compresse des fichiers executables
}

Program GZEXE;

{$X+}
{$R-}

Uses DOS;

Const
 StubN=47;
 HistMax=16384;
 ChunkSz=8192;
 WinSz=24576;
 Stub:Array[1..StubN]Of String[80]=(
  '#!/bin/sh',
  'skip=',
  '',
  'tab='''#9'''',
  'nl=''',
  '''',
  'IFS=" $tab$nl"',
  '',
  'umask=`umask`',
  'umask 77',
  '',
  'gztmpdir=',
  'trap ''res=$?',
  '  test -n "$gztmpdir" && rm -fr "$gztmpdir"',
  '  (exit $res); exit $res',
  ''' 0 1 2 3 5 10 13 15',
  '',
  'case $TMPDIR in',
  '  / | /*/) ;;',
  '  *) TMPDIR=/tmp/;;',
  'esac',
  'if type mktemp >/dev/null 2>&1; then',
  '  gztmpdir=`mktemp -d "${TMPDIR}gztmpXXXXXXXXX"`',
  'else',
  '  gztmpdir=${TMPDIR}gztmp$$; mkdir $gztmpdir',
  'fi || { (exit 127); exit 127; }',
  '',
  'gztmp=$gztmpdir/$0',
  'case $0 in',
  '-* | */*''',
  ''') mkdir -p "$gztmp" && rm -r "$gztmp";;',
  '*/*) gztmp=$gztmpdir/`basename "$0"`;;',
  'esac || { (exit 127); exit 127; }',
  '',
  'case `echo X | tail -n +1 2>/dev/null` in',
  'X) tail_n=-n;;',
  '*) tail_n=;;',
  'esac',
  'if tail $tail_n +$skip <"$0" | gzip -cd > "$gztmp"; then',
  '  umask $umask',
  '  chmod 700 "$gztmp"',
  '  (sleep 5; rm -fr "$gztmpdir") 2>/dev/null &',
  '  "$gztmp" ${1+"$@"}; res=$?',
  'else',
  '  printf >&2 ''%s\n'' "Cannot decompress $0"',
  '  (exit 127); res=127',
  'fi; exit $res');
 LBase:Array[0..28]Of Integer=(3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,
  67,83,99,115,131,163,195,227,258);
 LExt:Array[0..28]Of Integer=(0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0);
 DBase:Array[0..29]Of Integer=(1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,
  769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577);
 DExt:Array[0..29]Of Integer=(0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13);
 CodeOrder:Array[0..18]Of Integer=(16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15);

Type
 TWinBuf=Array[0..WinSz-1]Of Byte;
 THeadBuf=Array[0..4095]Of Word;
 TPrevBuf=Array[0..WinSz-1]Of Word;
 PWinBuf=^TWinBuf;
 PHeadBuf=^THeadBuf;
 PPrevBuf=^TPrevBuf;
 THuff=Record
  Count:Array[0..15]Of Integer;
  Sym:Array[0..287]Of Integer;
 End;

Var
 InF,OutF:File;
 InBuf,OutBuf:Array[0..4095]Of Byte;
 InPos,InLen,OutPos:Integer;
 InEof:Boolean;
 BitBuf:Longint;
 BitCnt:Integer;
 Crc:Longint;
 CrcTab:Array[0..255]Of Longint;
 Total:Longint;
 Win:PWinBuf;
 Head:PHeadBuf;
 Prev:PPrevBuf;
 Win32:Array[0..32767]Of Byte;
 WPos:Integer;
 Lens:Array[0..319]Of Integer;
 InfErr:Boolean;
 ErrCount:Integer;
 OptD:Boolean;

Procedure ShowUsage;Begin
 WriteLn('Usage: gzexe [ -d ] [ name ... ]');
End;

Procedure ShowHelp;Begin
 WriteLn('GZEXE : Cette commande permet d''effectuer la compression de fichiers ',
         'executables.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  name        Fichier(s) a compresser; l''original est sauve dans name~');
 WriteLn('  -d          Decompresse les fichiers deja traites par gzexe');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Msg(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'gzexe: ',S);
 {$ELSE}
 WriteLn('gzexe: ',S);
 {$ENDIF}
 Inc(ErrCount);
End;

Function IntStr(N:Longint):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

{ ------------------------- CRC32 ------------------------- }

Procedure InitCrc;
Var
 I,K:Integer;
 C:Longint;
Begin
 For I:=0 to 255 Do Begin
  C:=I;
  For K:=1 to 8 Do Begin
   If(C And 1)<>0Then C:=$EDB88320 Xor((C Shr 1)And $7FFFFFFF)
                 Else C:=(C Shr 1)And $7FFFFFFF;
  End;
  CrcTab[I]:=C;
 End;
End;

Procedure CrcByte(B:Byte);Begin
 Crc:=CrcTab[(Crc Xor B)And 255]Xor((Crc Shr 8)And $FFFFFF);
End;

{ ------------------------- Entrees / sorties binaires ------------------------- }

Function NextByte:Integer;
Var
 N:Word;
Begin
 If InPos>=InLen Then Begin
  If InEof Then Begin
   NextByte:=0;
   InfErr:=True;
   Exit;
  End;
  BlockRead(InF,InBuf,SizeOf(InBuf),N);
  InLen:=N;
  InPos:=0;
  If N=0Then Begin
   InEof:=True;
   NextByte:=0;
   InfErr:=True;
   Exit;
  End;
 End;
 NextByte:=InBuf[InPos];
 Inc(InPos);
End;

Procedure FlushOut;Begin
 If OutPos>0Then BlockWrite(OutF,OutBuf,OutPos);
 OutPos:=0;
End;

Procedure PutByte(B:Integer);Begin
 OutBuf[OutPos]:=B And 255;
 Inc(OutPos);
 If OutPos>=SizeOf(OutBuf)Then FlushOut;
End;

Procedure PutBits(V:Longint;N:Integer);Begin
 BitBuf:=BitBuf Or(V Shl BitCnt);
 BitCnt:=BitCnt+N;
 While BitCnt>=8Do Begin
  PutByte(BitBuf And 255);
  BitBuf:=(BitBuf Shr 8)And $FFFFFF;
  BitCnt:=BitCnt-8;
 End;
End;

Function Rev(V,N:Integer):Longint;
Var
 I:Integer;
 R:Longint;
Begin
 R:=0;
 For I:=1 to N Do Begin
  R:=(R Shl 1)Or(V And 1);
  V:=V Shr 1;
 End;
 Rev:=R;
End;

Procedure PutLit(Sym:Integer);Begin
 If Sym<=143Then PutBits(Rev($30+Sym,8),8)
 Else If Sym<=255Then PutBits(Rev($190+Sym-144,9),9)
 Else If Sym<=279Then PutBits(Rev(Sym-256,7),7)
 Else PutBits(Rev($C0+Sym-280,8),8);
End;

Procedure PutMatch(Len,Dist:Integer);
Var
 C:Integer;
Begin
 C:=28;
 While LBase[C]>Len Do Dec(C);
 PutLit(257+C);
 If LExt[C]>0Then PutBits(Len-LBase[C],LExt[C]);
 C:=29;
 While DBase[C]>Dist Do Dec(C);
 PutBits(Rev(C,5),5);
 If DExt[C]>0Then PutBits(Dist-DBase[C],DExt[C]);
End;

{ ------------------------- Compression (LZ77 + Huffman fixe) ------------------------- }

Function HashAt(I:Integer):Integer;Begin
 HashAt:=((Longint(Win^[I])Shl 8)Xor(Longint(Win^[I+1])Shl 4)Xor Win^[I+2])And 4095;
End;

Procedure Insert(I:Integer);
Var
 H:Integer;
Begin
 H:=HashAt(I);
 Prev^[I]:=Head^[H];
 Head^[H]:=I;
End;

Procedure Compress;
Var
 Hist,N,P,EndP,I,K,L,BestL,BestD,Chain,MaxL:Integer;
 Cand:Word;
 Got:Word;
Begin
 New(Win);
 New(Head);
 New(Prev);
 Crc:=-1;
 Total:=0;
 BitBuf:=0;
 BitCnt:=0;
 { en-tete gzip }
 PutByte($1F);PutByte($8B);PutByte(8);PutByte(0);
 PutByte(0);PutByte(0);PutByte(0);PutByte(0);
 PutByte(0);PutByte(3);
 PutBits(1,1);   { BFINAL }
 PutBits(1,2);   { BTYPE = 01, Huffman fixe }
 Hist:=0;
 While True Do Begin
  BlockRead(InF,Win^[Hist],ChunkSz,Got);
  N:=Got;
  If N=0Then Break;
  For I:=Hist to Hist+N-1 Do CrcByte(Win^[I]);
  Total:=Total+N;
  FillChar(Head^,SizeOf(Head^),$FF);
  For I:=0 to Hist-3 Do Insert(I);
  P:=Hist;
  EndP:=Hist+N;
  While P<EndP Do Begin
   BestL:=0;
   BestD:=0;
   If P+2<EndP Then Begin
    Cand:=Head^[HashAt(P)];
    Chain:=0;
    MaxL:=EndP-P;
    If MaxL>258Then MaxL:=258;
    While(Cand<>$FFFF)And(Chain<32)And(P-Cand<=HistMax)Do Begin
     L:=0;
     While(L<MaxL)And(Win^[Cand+L]=Win^[P+L])Do Inc(L);
     If L>BestL Then Begin
      BestL:=L;
      BestD:=P-Cand;
      If L=MaxL Then Break;
     End;
     Cand:=Prev^[Cand];
     Inc(Chain);
    End;
   End;
   If BestL>=3Then Begin
    PutMatch(BestL,BestD);
    For K:=0 to BestL-1 Do If P+K+2<EndP Then Insert(P+K);
    Inc(P,BestL);
   End
    Else
   Begin
    PutLit(Win^[P]);
    If P+2<EndP Then Insert(P);
    Inc(P);
   End;
  End;
  If EndP>HistMax Then Begin
   Move(Win^[EndP-HistMax],Win^[0],HistMax);
   Hist:=HistMax;
  End
   Else
  Hist:=EndP;
 End;
 PutLit(256);
 If BitCnt>0Then PutBits(0,8-BitCnt);
 Crc:=Not Crc;
 For I:=0 to 3 Do PutByte((Crc Shr(8*I))And 255);
 For I:=0 to 3 Do PutByte((Total Shr(8*I))And 255);
 FlushOut;
 Dispose(Prev);
 Dispose(Head);
 Dispose(Win);
End;

{ ------------------------- Decompression (inflate) ------------------------- }

Function GetBits(N:Integer):Integer;
Var
 V,I:Integer;
Begin
 V:=0;
 For I:=0 to N-1 Do Begin
  If BitCnt=0Then Begin
   BitBuf:=NextByte;
   BitCnt:=8;
  End;
  V:=V Or((BitBuf And 1)Shl I);
  BitBuf:=BitBuf Shr 1;
  Dec(BitCnt);
 End;
 GetBits:=V;
End;

Procedure Construct(Var H:THuff;Start,N:Integer);
Var
 I,S:Integer;
 Offs:Array[0..15]Of Integer;
Begin
 For I:=0 to 15 Do H.Count[I]:=0;
 For S:=0 to N-1 Do Inc(H.Count[Lens[Start+S]]);
 Offs[1]:=0;
 For I:=1 to 14 Do Offs[I+1]:=Offs[I]+H.Count[I];
 For S:=0 to N-1 Do If Lens[Start+S]<>0Then Begin
  H.Sym[Offs[Lens[Start+S]]]:=S;
  Inc(Offs[Lens[Start+S]]);
 End;
End;

Function Decode(Var H:THuff):Integer;
Var
 Code,First,Index,Len,Cnt:Integer;
Begin
 Code:=0;
 First:=0;
 Index:=0;
 For Len:=1 to 15 Do Begin
  Code:=Code Or GetBits(1);
  Cnt:=H.Count[Len];
  If Code-Cnt<First Then Begin
   Decode:=H.Sym[Index+(Code-First)];
   Exit;
  End;
  Index:=Index+Cnt;
  First:=(First+Cnt)Shl 1;
  Code:=Code Shl 1;
 End;
 InfErr:=True;
 Decode:=0;
End;

Procedure OutI(B:Integer);Begin
 Win32[WPos]:=B;
 WPos:=(WPos+1)And 32767;
 PutByte(B);
 CrcByte(B);
 Inc(Total);
End;

Procedure Codes(Var LitH,DistH:THuff);
Var
 Sym,Len,Dist,DS,I:Integer;
Begin
 While Not InfErr Do Begin
  Sym:=Decode(LitH);
  If Sym<256Then OutI(Sym)
  Else If Sym=256Then Exit
  Else Begin
   Sym:=Sym-257;
   If Sym>=29Then Begin
    InfErr:=True;
    Exit;
   End;
   Len:=LBase[Sym]+GetBits(LExt[Sym]);
   DS:=Decode(DistH);
   If DS>=30Then Begin
    InfErr:=True;
    Exit;
   End;
   Dist:=DBase[DS]+GetBits(DExt[DS]);
   For I:=1 to Len Do OutI(Win32[(WPos-Dist)And 32767]);
  End;
 End;
End;

Procedure Inflate;
Var
 Last,Typ,I,Len,NLen,NDist,NCode,Idx,Sym,Rep,Prv:Integer;
 LitH,DistH,LenH:THuff;
Begin
 Repeat
  Last:=GetBits(1);
  Typ:=GetBits(2);
  If Typ=0Then Begin
   BitCnt:=0;
   Len:=NextByte;
   Len:=Len Or(NextByte Shl 8);
   NextByte;
   NextByte;
   For I:=1 to Len Do OutI(NextByte);
  End
  Else If Typ=1Then Begin
   For I:=0 to 143 Do Lens[I]:=8;
   For I:=144 to 255 Do Lens[I]:=9;
   For I:=256 to 279 Do Lens[I]:=7;
   For I:=280 to 287 Do Lens[I]:=8;
   Construct(LitH,0,288);
   For I:=0 to 29 Do Lens[I]:=5;
   Construct(DistH,0,30);
   Codes(LitH,DistH);
  End
  Else If Typ=2Then Begin
   NLen:=GetBits(5)+257;
   NDist:=GetBits(5)+1;
   NCode:=GetBits(4)+4;
   If(NLen>286)Or(NDist>30)Then InfErr:=True
    Else
   Begin
    For I:=0 to 18 Do Lens[I]:=0;
    For I:=0 to NCode-1 Do Lens[CodeOrder[I]]:=GetBits(3);
    Construct(LenH,0,19);
    Idx:=0;
    While(Idx<NLen+NDist)And Not InfErr Do Begin
     Sym:=Decode(LenH);
     If Sym<16Then Begin
      Lens[Idx]:=Sym;
      Inc(Idx);
     End
      Else
     Begin
      Prv:=0;
      If Sym=16Then Begin
       If Idx>0Then Prv:=Lens[Idx-1];
       Rep:=3+GetBits(2);
      End
      Else If Sym=17Then Rep:=3+GetBits(3)
      Else Rep:=11+GetBits(7);
      If Idx+Rep>NLen+NDist Then Begin
       InfErr:=True;
       Break;
      End;
      While Rep>0Do Begin
       Lens[Idx]:=Prv;
       Inc(Idx);
       Dec(Rep);
      End;
     End;
    End;
    If Not InfErr Then Begin
     Construct(LitH,0,NLen);
     Construct(DistH,NLen,NDist);
     Codes(LitH,DistH);
    End;
   End;
  End
  Else InfErr:=True;
 Until(Last=1)Or InfErr;
End;

{ ------------------------- Fichiers ------------------------- }

Function OpenIn(Const Name:String):Boolean;Begin
 Assign(InF,Name);
 {$I-}Reset(InF,1);{$I+}
 OpenIn:=IOResult=0;
 InPos:=0;
 InLen:=0;
 InEof:=False;
 InfErr:=False;
End;

Function OpenOut(Const Name:String):Boolean;Begin
 Assign(OutF,Name);
 {$I-}Rewrite(OutF,1);{$I+}
 OpenOut:=IOResult=0;
 OutPos:=0;
End;

Function CopyFile(Const Src,Dst:String):Boolean;
Var
 Buf:Array[0..4095]Of Byte;
 N:Word;
Begin
 CopyFile:=False;
 If Not OpenIn(Src)Then Exit;
 If Not OpenOut(Dst)Then Begin
  Close(InF);
  Exit;
 End;
 Repeat
  BlockRead(InF,Buf,SizeOf(Buf),N);
  If N>0Then BlockWrite(OutF,Buf,N);
 Until N=0;
 Close(InF);
 Close(OutF);
 CopyFile:=True;
End;

Function ReadLine:String;
Var
 S:String;
 B:Integer;
Begin
 S:='';
 Repeat
  B:=NextByte;
  If InfErr Then Break;
  If(B<>10)And(B<>13)And(Length(S)<200)Then S:=S+Chr(B);
 Until B=10;
 ReadLine:=S;
End;

{ Retourne le numero de ligne ou commencent les donnees, 0 si ce n'est pas un fichier gzexe }
Function GzexeSkip(Const Name:String):Integer;
Var
 L1,L2:String;
 N,Err:Integer;
Begin
 GzexeSkip:=0;
 If Not OpenIn(Name)Then Exit;
 L1:=ReadLine;
 L2:=ReadLine;
 Close(InF);
 If(L1='#!/bin/sh')And(Copy(L2,1,5)='skip=')Then Begin
  Val(Copy(L2,6,10),N,Err);
  If Err=0Then GzexeSkip:=N;
 End;
End;

Function FileSz(Const Name:String):Longint;Begin
 FileSz:=-1;
 If Not OpenIn(Name)Then Exit;
 FileSz:=FileSize(InF);
 Close(InF);
End;

Procedure WriteStub;
Var
 I,J:Integer;
 S:String;
Begin
 For I:=1 to StubN Do Begin
  S:=Stub[I];
  If I=2Then S:='skip='+IntStr(StubN+1);
  For J:=1 to Length(S)Do PutByte(Ord(S[J]));
  PutByte(10);
 End;
End;

Procedure DoCompress(Const Name:String);
Var
 Bak:String;
 Orig,NewSz:Longint;
 Pct:Real;
 S:String;
Begin
 Orig:=FileSz(Name);
 If Orig<0Then Begin
  Msg(Name+': fichier introuvable');
  Exit;
 End;
 If Name[Length(Name)]='~'Then Begin
  Msg(Name+': le nom se termine par ~');
  Exit;
 End;
 If GzexeSkip(Name)>0Then Begin
  Msg(Name+' est deja un fichier gzexe');
  Exit;
 End;
 Bak:=Name+'~';
 If Not CopyFile(Name,Bak)Then Begin
  Msg('impossible de creer '+Bak);
  Exit;
 End;
 If Not OpenIn(Bak)Then Begin
  Msg('impossible de relire '+Bak);
  Exit;
 End;
 If Not OpenOut(Name)Then Begin
  Close(InF);
  Msg('impossible d''ecrire '+Name);
  Exit;
 End;
 WriteStub;
 Compress;
 Close(InF);
 NewSz:=FileSize(OutF);
 Close(OutF);
 If NewSz>=Orig Then Begin
  CopyFile(Bak,Name);
  Assign(InF,Bak);
  {$I-}Erase(InF);{$I+}
  If IOResult<>0Then;
  Msg(Name+': compression impossible (le fichier ne diminue pas)');
  Exit;
 End;
 Pct:=100.0*(Orig-NewSz)/Orig;
 Str(Pct:0:1,S);
 WriteLn(Name,':',#9,S,'%');
End;

Procedure DoDecompress(Const Name:String);
Var
 Bak:String;
 Sk,I,Flg,Len:Integer;
 Tmp:String;
 Want:Longint;
Begin
 If FileSz(Name)<0Then Begin
  Msg(Name+': fichier introuvable');
  Exit;
 End;
 Sk:=GzexeSkip(Name);
 If Sk=0Then Begin
  Msg(Name+' n''est pas un fichier gzexe');
  Exit;
 End;
 Bak:=Name+'~';
 If Not CopyFile(Name,Bak)Then Begin
  Msg('impossible de creer '+Bak);
  Exit;
 End;
 If Not OpenIn(Bak)Then Begin
  Msg('impossible de relire '+Bak);
  Exit;
 End;
 For I:=1 to Sk-1 Do Tmp:=ReadLine;
 { en-tete gzip }
 If(NextByte<>$1F)Or(NextByte<>$8B)Or(NextByte<>8)Then InfErr:=True;
 Flg:=NextByte;
 For I:=1 to 6 Do NextByte;
 If(Flg And 4)<>0Then Begin
  Len:=NextByte;
  Len:=Len Or(NextByte Shl 8);
  For I:=1 to Len Do NextByte;
 End;
 If(Flg And 8)<>0Then Repeat Until(NextByte=0)Or InfErr;
 If(Flg And 16)<>0Then Repeat Until(NextByte=0)Or InfErr;
 If(Flg And 2)<>0Then Begin
  NextByte;
  NextByte;
 End;
 If InfErr Then Begin
  Close(InF);
  Msg(Name+': donnees gzip invalides');
  Exit;
 End;
 If Not OpenOut(Name)Then Begin
  Close(InF);
  Msg('impossible d''ecrire '+Name);
  Exit;
 End;
 Crc:=-1;
 Total:=0;
 BitBuf:=0;
 BitCnt:=0;
 WPos:=0;
 Inflate;
 FlushOut;
 Close(OutF);
 If Not InfErr Then Begin
  BitCnt:=0;
  Want:=0;
  For I:=0 to 3 Do Want:=Want Or(Longint(NextByte)Shl(8*I));
  Crc:=Not Crc;
  If Want<>Crc Then InfErr:=True;
 End;
 Close(InF);
 If InfErr Then Begin
  CopyFile(Bak,Name);
  Msg(Name+': erreur de decompression, original restaure');
 End;
End;

Var
 I,N:Integer;
 A:String;

BEGIN
 ErrCount:=0;
 N:=0;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='/?')Or(A='--help')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
 End;
 InitCrc;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If A='-d'Then OptD:=True
  Else If(Length(A)>1)And(A[1]='-')Then Begin
   WriteLn('gzexe: option inconnue: ',A);
   ShowUsage;
   Halt(1);
  End;
 End;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If A[1]<>'-'Then Begin
   Inc(N);
   If OptD Then DoDecompress(A)
           Else DoCompress(A);
  End;
 End;
 If N=0Then Begin
  ShowUsage;
  Halt(1);
 End;
 If ErrCount>0Then Halt(1);
END.
