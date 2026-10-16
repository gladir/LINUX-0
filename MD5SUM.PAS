{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande md5sum - Calcule et verifie les sommes MD5
}

Program MD5SUM;

{$X+}
{$R-}

Uses DOS;

Const
 KT:Array[0..63]Of Longint=(
  -680876936,-389564586,606105819,-1044525330,
  -176418897,1200080426,-1473231341,-45705983,
  1770035416,-1958414417,-42063,-1990404162,
  1804603682,-40341101,-1502002290,1236535329,
  -165796510,-1069501632,643717713,-373897302,
  -701558691,38016083,-660478335,-405537848,
  568446438,-1019803690,-187363961,1163531501,
  -1444681467,-51403784,1735328473,-1926607734,
  -378558,-2022574463,1839030562,-35309556,
  -1530992060,1272893353,-155497632,-1094730640,
  681279174,-358537222,-722521979,76029189,
  -640364487,-421815835,530742520,-995338651,
  -198630844,1126891415,-1416354905,-57434055,
  1700485571,-1894986606,-1051523,-2054922799,
  1873313359,-30611744,-1560198380,1309151649,
  -145523070,-1120210379,718787259,-343485551);
 SH:Array[0..63]Of Integer=(
  7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
  5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
  4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
  6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21);
 HexDigits:String[16]='0123456789abcdef';

Type
 TBytes=Array[0..65534]Of Byte;

Var
 St:Array[0..3]Of Longint;
 Blk:Array[0..63]Of Byte;
 BlkLen:Integer;
 LenLo,LenHi:Longint;
 InF:File;
 InBuf:Array[0..4095]Of Byte;
 OptB,OptV,OptT,OptCheck,OptString:Boolean;
 CheckName,StrArg:String;
 ErrCount:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: md5sum [-bv] [-c [ file ]]');
 WriteLn('       md5sum file ...');
End;

Procedure ShowHelp;Begin
 WriteLn('MD5SUM : Cette commande permet d''effectuer la verification et la generation ',
         'd''un message MD5.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -b, --binary                Fichiers binaires');
 WriteLn('  -c file, --check=file       Verifie les sommes d''un fichier produit precedemment');
 WriteLn('  -s string, --string=string  Calcule la somme d''une chaine au lieu d''un fichier');
 WriteLn('  -t, --text                  Fichiers texte');
 WriteLn('  -v, --verbose               Affichage detaille');
 WriteLn('  --help                      Affiche cette aide');
 WriteLn('  --version                   Affiche la version');
End;

Function IntStr(N:Longint):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

Procedure Err(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'md5sum: ',S);
 {$ELSE}
 WriteLn('md5sum: ',S);
 {$ENDIF}
 Inc(ErrCount);
End;

Function RotL(X:Longint;N:Integer):Longint;Begin
 RotL:=(X Shl N)Or((X Shr(32-N))And((Longint(1)Shl N)-1));
End;

Procedure Transform;
Var
 W:Array[0..15]Of Longint;
 I,J,G:Integer;
 A,B,C,D,F:Longint;
Begin
 For I:=0 to 15 Do Begin
  J:=I*4;
  W[I]:=Longint(Blk[J])Or(Longint(Blk[J+1])Shl 8)Or(Longint(Blk[J+2])Shl 16)Or(Longint(Blk[J+3])Shl 24);
 End;
 A:=St[0];B:=St[1];C:=St[2];D:=St[3];
 For I:=0 to 63 Do Begin
  If I<16Then Begin
   F:=(B And C)Or((Not B)And D);
   G:=I;
  End
  Else If I<32Then Begin
   F:=(D And B)Or((Not D)And C);
   G:=(5*I+1)Mod 16;
  End
  Else If I<48Then Begin
   F:=B Xor C Xor D;
   G:=(3*I+5)Mod 16;
  End
  Else Begin
   F:=C Xor(B Or(Not D));
   G:=(7*I)Mod 16;
  End;
  F:=F+A+KT[I]+W[G];
  A:=D;
  D:=C;
  C:=B;
  B:=B+RotL(F,SH[I]);
 End;
 St[0]:=St[0]+A;St[1]:=St[1]+B;St[2]:=St[2]+C;St[3]:=St[3]+D;
End;

Procedure MD5Init;Begin
 St[0]:=1732584193;
 St[1]:=-271733879;
 St[2]:=-1732584194;
 St[3]:=271733878;
 BlkLen:=0;
 LenLo:=0;
 LenHi:=0;
End;

{ Compte les octets traites (fichiers de moins de 2 Go) }
Procedure AddLen(N:Longint);Begin
 LenLo:=LenLo+N;
End;

Procedure MD5Byte(B:Byte);Begin
 Blk[BlkLen]:=B;
 Inc(BlkLen);
 If BlkLen=64Then Begin
  Transform;
  BlkLen:=0;
 End;
End;

Procedure MD5Update(Var Buf;N:Integer);
Var
 PB:^TBytes;
 I:Integer;
Begin
 PB:=@Buf;
 For I:=0 to N-1 Do MD5Byte(PB^[I]);
 AddLen(N);
End;

Function MD5Final:String;
Var
 I,J,G:Integer;
 R:String;
 LL,LH,F:Longint;
Begin
 LL:=LenLo Shl 3;
 LH:=(LenLo Shr 29)And 7;
 MD5Byte($80);
 While BlkLen<>56Do MD5Byte(0);
 For I:=0 to 3 Do MD5Byte((LL Shr(8*I))And 255);
 For I:=0 to 3 Do MD5Byte((LH Shr(8*I))And 255);
 R:='';
 For I:=0 to 3 Do Begin
  F:=St[I];
  For J:=0 to 3 Do Begin
   G:=(F Shr(8*J))And 255;
   R:=R+HexDigits[(G Shr 4)+1]+HexDigits[(G And 15)+1];
  End;
 End;
 MD5Final:=R;
End;

Function StrMD5(Const S:String):String;
Var
 I:Integer;
Begin
 MD5Init;
 For I:=1 to Length(S)Do MD5Byte(Ord(S[I]));
 AddLen(Length(S));
 StrMD5:=MD5Final;
End;

{ Somme d'un fichier ('-' = entree standard); retourne False si illisible }
Function FileMD5(Const Name:String;Var Hex:String):Boolean;
Var
 N:Word;
Begin
 FileMD5:=False;
 If Name='-'Then Begin
  {$IFDEF FPC}
  {$IFDEF UNIX}
  Assign(InF,'/dev/null');
  {$ELSE}
  Assign(InF,'NUL');
  {$ENDIF}
  {$I-}Reset(InF,1);{$I+}
  If IOResult<>0Then Begin
   Err('impossible de lire l''entree standard');
   Exit;
  End;
  FileRec(InF).Handle:=StdInputHandle;
  {$ELSE}
  Err('entree standard binaire non supportee');
  Exit;
  {$ENDIF}
 End
  Else
 Begin
  Assign(InF,Name);
  {$I-}Reset(InF,1);{$I+}
  If IOResult<>0Then Begin
   Err(Name+': No such file or directory');
   Exit;
  End;
 End;
 MD5Init;
 Repeat
  BlockRead(InF,InBuf,SizeOf(InBuf),N);
  If N>0Then MD5Update(InBuf,N);
 Until N=0;
 Close(InF);
 Hex:=MD5Final;
 FileMD5:=True;
End;

Procedure DoFile(Const Name:String);
Var
 H:String;
Begin
 If FileMD5(Name,H)Then Begin
  If OptB Then WriteLn(H,' *',Name)
          Else WriteLn(H,'  ',Name);
 End;
End;

Function IsHex(C:Char):Boolean;Begin
 IsHex:=C In['0'..'9','a'..'f','A'..'F'];
End;

Function LowerS(Const S:String):String;
Var
 I:Integer;
 R:String;
Begin
 R:=S;
 For I:=1 to Length(R)Do If R[I]In['A'..'Z']Then R[I]:=Chr(Ord(R[I])+32);
 LowerS:=R;
End;

Procedure DoCheck(Const ListName:String);
Var
 T:Text;
 L,Want,Name,Got:String;
 Total,Bad,Fmt,I:Integer;
 Ok:Boolean;
Begin
 If ListName=''Then Assign(T,'')
               Else Assign(T,ListName);
 {$I-}Reset(T);{$I+}
 If IOResult<>0Then Begin
  Err(ListName+': No such file or directory');
  Exit;
 End;
 Total:=0;
 Bad:=0;
 Fmt:=0;
 While Not EOF(T)Do Begin
  ReadLn(T,L);
  If Length(L)<35Then Begin
   If Length(L)>0Then Inc(Fmt);
   Continue;
  End;
  Ok:=True;
  For I:=1 to 32 Do If Not IsHex(L[I])Then Ok:=False;
  If Not Ok Or(L[33]<>' ')Or Not(L[34]In[' ','*'])Then Begin
   Inc(Fmt);
   Continue;
  End;
  Want:=LowerS(Copy(L,1,32));
  Name:=Copy(L,35,255);
  Inc(Total);
  If FileMD5(Name,Got)Then Begin
   If Got=Want Then WriteLn(Name,': OK')
    Else Begin
     WriteLn(Name,': FAILED');
     If OptV Then WriteLn('  attendu: ',Want,'  calcule: ',Got);
     Inc(Bad);
    End;
  End
   Else
  Begin
   WriteLn(Name,': FAILED open or read');
   Inc(Bad);
  End;
 End;
 Close(T);
 If Fmt>0Then Err('WARNING: '+IntStr(Fmt)+' line(s) are improperly formatted');
 If Bad>0Then Err('WARNING: '+IntStr(Bad)+' of '+IntStr(Total)+' computed checksums did NOT match');
 If OptV Then WriteLn(Total-Bad,' / ',Total,' fichiers verifies');
End;

Var
 I,NF:Integer;
 A,V:String;
 Files:Array[1..64]Of String[127];

BEGIN
 ErrCount:=0;
 NF:=0;
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='-h')Or(A='/h')Then Begin
   ShowHelp;
   Halt(0);
  End
  Else If A='--version'Then Begin
   WriteLn('md5sum (clone) 1.0');
   Halt(0);
  End
  Else If A='--binary'Then OptB:=True
  Else If A='--text'Then OptT:=True
  Else If A='--verbose'Then OptV:=True
  Else If Copy(A,1,8)='--check='Then Begin
   OptCheck:=True;
   CheckName:=Copy(A,9,255);
  End
  Else If A='--check'Then Begin
   OptCheck:=True;
   If(I<ParamCount)And(Copy(ParamStr(I+1),1,1)<>'-')Then Begin
    Inc(I);
    CheckName:=ParamStr(I);
   End;
  End
  Else If Copy(A,1,9)='--string='Then Begin
   OptString:=True;
   StrArg:=Copy(A,10,255);
  End
  Else If(Length(A)>1)And(A[1]='-')And(A[2]<>'-')Then Begin
   V:=Copy(A,2,255);
   While V<>''Do Begin
    Case V[1]of
     'b':OptB:=True;
     't':OptT:=True;
     'v':OptV:=True;
     'c':Begin
      OptCheck:=True;
      If Length(V)>1Then Begin
       CheckName:=Copy(V,2,255);
       V:='';
      End
      Else If(I<ParamCount)And(Copy(ParamStr(I+1),1,1)<>'-')Then Begin
       Inc(I);
       CheckName:=ParamStr(I);
      End;
     End;
     's':Begin
      OptString:=True;
      If Length(V)>1Then Begin
       StrArg:=Copy(V,2,255);
       V:='';
      End
      Else If I<ParamCount Then Begin
       Inc(I);
       StrArg:=ParamStr(I);
      End;
     End;
     Else Begin
      WriteLn('md5sum: option inconnue: -',V[1]);
      ShowUsage;
      Halt(2);
     End;
    End;
    If V<>''Then V:=Copy(V,2,255);
   End;
  End
  Else Begin
   If NF<64Then Begin
    Inc(NF);
    Files[NF]:=Copy(A,1,127);
   End;
  End;
  Inc(I);
 End;
 If OptString Then Begin
  WriteLn('MD5 ("',StrArg,'") = ',StrMD5(StrArg));
  Halt(0);
 End;
 If OptCheck Then Begin
  DoCheck(CheckName);
  If ErrCount>0Then Halt(1);
  Halt(0);
 End;
 If NF=0Then DoFile('-')
  Else
 For I:=1 to NF Do DoFile(Files[I]);
 If ErrCount>0Then Halt(1);
END.
