{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande htpasswd - Gestion des fichiers de mots de passe d'Apache
}

Program HTPASSWD;

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
 SB:Array[0..511]Of Byte=(
  14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7,
  0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8,
  4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0,
  15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13,
  15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10,
  3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5,
  0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15,
  13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9,
  10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8,
  13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1,
  13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7,
  1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12,
  7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15,
  13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9,
  10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4,
  3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14,
  2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9,
  14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6,
  4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14,
  11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3,
  12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11,
  10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8,
  9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6,
  4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13,
  4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1,
  13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6,
  1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2,
  6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12,
  13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7,
  1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2,
  7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8,
  2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11);
 IP:Array[0..63]Of Byte=(58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,
  62,54,46,38,30,22,14,6,64,56,48,40,32,24,16,8,57,49,41,33,25,17,9,1,
  59,51,43,35,27,19,11,3,61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7);
 FP:Array[0..63]Of Byte=(40,8,48,16,56,24,64,32,39,7,47,15,55,23,63,31,
  38,6,46,14,54,22,62,30,37,5,45,13,53,21,61,29,36,4,44,12,52,20,60,28,
  35,3,43,11,51,19,59,27,34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25);
 PC1C:Array[0..27]Of Byte=(57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,
  59,51,43,35,27,19,11,3,60,52,44,36);
 PC1D:Array[0..27]Of Byte=(63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,
  61,53,45,37,29,21,13,5,28,20,12,4);
 PC2C:Array[0..23]Of Byte=(14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2);
 PC2D:Array[0..23]Of Byte=(41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,
  34,53,46,42,50,36,29,32);
 Shifts:Array[0..15]Of Byte=(1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1);
 EBox:Array[0..47]Of Byte=(32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,
  16,17,16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1);
 PBox:Array[0..31]Of Byte=(16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,
  2,8,24,14,32,27,3,9,19,13,30,6,22,11,4,25);
 Itoa64:String[64]='./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
 B64:String[64]='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
 HexDigits:String[16]='0123456789abcdef';

Type
 TDigest=Array[0..19]Of Byte;

Var
 MB:Array[0..1151]Of Byte;
 ML:Integer;
 MD:TDigest;
 OptB,OptC,OptN,OptM,OptD,OptP,OptS,OptDel:Boolean;
 KS:Array[0..15,0..47]Of Byte;
 Ee:Array[0..47]Of Byte;
 Blk:Array[0..65]Of Byte;

Procedure ShowUsage;Begin
 WriteLn('Usage:');
 WriteLn('        htpasswd [-cmD] passwordfile username');
 WriteLn('        htpasswd -b[cmDdps] passwordfile username password');
 WriteLn;
 WriteLn('        htpasswd -n[mdps] username');
 WriteLn('        htpasswd -nb[mdps] username password');
End;

Procedure ShowHelp;Begin
 WriteLn('HTPASSWD : Cette commande permet d''encrypter les mots de passe des fichiers ',
         '".htpasswd" qu''utilise Apache.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -b          Mode lot: le mot de passe est donne sur la ligne de commande');
 WriteLn('  -c          Cree le fichier de mots de passe (ecrase s''il existe)');
 WriteLn('  -n          Affiche le resultat sur la sortie standard au lieu d''un fichier');
 WriteLn('  -m          Encryption MD5 (apr1)');
 WriteLn('  -d          Encryption crypt() (par defaut)');
 WriteLn('  -s          Encryption SHA-1');
 WriteLn('  -p          Mot de passe en clair');
 WriteLn('  -D          Supprime l''utilisateur');
 WriteLn('  --help      Affiche cette aide');
End;

Procedure Fail(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,S);
 {$ELSE}
 WriteLn(S);
 {$ENDIF}
 Halt(1);
End;

Function IntStr(N:Longint):String;
Var
 S:String;
Begin
 Str(N,S);
 IntStr:=S;
End;

Function RotL(X:Longint;N:Integer):Longint;Begin
 RotL:=(X Shl N)Or((X Shr(32-N))And((Longint(1)Shl N)-1));
End;

{ ------------------------- MD5 sur MB[0..ML-1] -> MD[0..15] ------------------------- }

Procedure MD5Run;
Var
 W:Array[0..15]Of Longint;
 Total,Blk_,I,J,G:Integer;
 A,B,C,D,AA,BB,CC,DD,F:Longint;
 Bits:Longint;
Begin
 MB[ML]:=$80;
 Total:=((ML+8)Div 64+1)*64;
 For I:=ML+1 to Total-1 Do MB[I]:=0;
 Bits:=Longint(ML)*8;
 MB[Total-8]:=Bits And 255;
 MB[Total-7]:=(Bits Shr 8)And 255;
 A:=1732584193;
 B:=-271733879;
 C:=-1732584194;
 D:=271733878;
 For Blk_:=0 to Total Div 64-1 Do Begin
  For I:=0 to 15 Do Begin
   J:=Blk_*64+I*4;
   W[I]:=Longint(MB[J])Or(Longint(MB[J+1])Shl 8)Or(Longint(MB[J+2])Shl 16)Or(Longint(MB[J+3])Shl 24);
  End;
  AA:=A;BB:=B;CC:=C;DD:=D;
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
  A:=A+AA;B:=B+BB;C:=C+CC;D:=D+DD;
 End;
 For I:=0 to 3 Do Begin
  Case I of
   0:F:=A;
   1:F:=B;
   2:F:=C;
   Else F:=D;
  End;
  For J:=0 to 3 Do MD[I*4+J]:=(F Shr(8*J))And 255;
 End;
End;

{ ------------------------- SHA-1 sur MB[0..ML-1] -> MD[0..19] ------------------------- }

Procedure SHA1Run;
Var
 W:Array[0..79]Of Longint;
 Total,Blk_,I,J:Integer;
 H0,H1,H2,H3,H4,A,B,C,D,E,F,K,T:Longint;
 Bits:Longint;
Begin
 MB[ML]:=$80;
 Total:=((ML+8)Div 64+1)*64;
 For I:=ML+1 to Total-1 Do MB[I]:=0;
 Bits:=Longint(ML)*8;
 MB[Total-2]:=(Bits Shr 8)And 255;
 MB[Total-1]:=Bits And 255;
 H0:=1732584193;
 H1:=-271733879;
 H2:=-1732584194;
 H3:=271733878;
 H4:=-1009589776;
 For Blk_:=0 to Total Div 64-1 Do Begin
  For I:=0 to 15 Do Begin
   J:=Blk_*64+I*4;
   W[I]:=(Longint(MB[J])Shl 24)Or(Longint(MB[J+1])Shl 16)Or(Longint(MB[J+2])Shl 8)Or Longint(MB[J+3]);
  End;
  For I:=16 to 79 Do W[I]:=RotL(W[I-3]Xor W[I-8]Xor W[I-14]Xor W[I-16],1);
  A:=H0;B:=H1;C:=H2;D:=H3;E:=H4;
  For I:=0 to 79 Do Begin
   If I<20Then Begin
    F:=(B And C)Or((Not B)And D);
    K:=1518500249;
   End
   Else If I<40Then Begin
    F:=B Xor C Xor D;
    K:=1859775393;
   End
   Else If I<60Then Begin
    F:=(B And C)Or(B And D)Or(C And D);
    K:=-1894007588;
   End
   Else Begin
    F:=B Xor C Xor D;
    K:=-899497514;
   End;
   T:=RotL(A,5)+F+E+K+W[I];
   E:=D;
   D:=C;
   C:=RotL(B,30);
   B:=A;
   A:=T;
  End;
  H0:=H0+A;H1:=H1+B;H2:=H2+C;H3:=H3+D;H4:=H4+E;
 End;
 For I:=0 to 4 Do Begin
  Case I of
   0:F:=H0;
   1:F:=H1;
   2:F:=H2;
   3:F:=H3;
   Else F:=H4;
  End;
  For J:=0 to 3 Do MD[I*4+J]:=(F Shr(24-8*J))And 255;
 End;
End;

Function Base64Of(Const D:TDigest;N:Integer):String;
Var
 I:Integer;
 V:Longint;
 S:String;
Begin
 S:='';
 I:=0;
 While I<N Do Begin
  V:=Longint(D[I])Shl 16;
  If I+1<N Then V:=V Or(Longint(D[I+1])Shl 8);
  If I+2<N Then V:=V Or D[I+2];
  S:=S+B64[((V Shr 18)And 63)+1]+B64[((V Shr 12)And 63)+1];
  If I+1<N Then S:=S+B64[((V Shr 6)And 63)+1]
           Else S:=S+'=';
  If I+2<N Then S:=S+B64[(V And 63)+1]
           Else S:=S+'=';
  Inc(I,3);
 End;
 Base64Of:=S;
End;

{ ------------------------- MD5 crypt (apr1) ------------------------- }

Procedure AddStr(Const S:String);
Var
 I:Integer;
Begin
 For I:=1 to Length(S)Do Begin
  MB[ML]:=Ord(S[I]);
  Inc(ML);
 End;
End;

Procedure AddDig(Const D:TDigest;N:Integer);
Var
 I:Integer;
Begin
 For I:=0 to N-1 Do Begin
  MB[ML]:=D[I];
  Inc(ML);
 End;
End;

Function To64(V:Longint;N:Integer):String;
Var
 S:String;
Begin
 S:='';
 While N>0Do Begin
  S:=S+Itoa64[(V And 63)+1];
  V:=(V Shr 6)And $3FFFFFF;
  Dec(N);
 End;
 To64:=S;
End;

Function Apr1(Const Pw,Salt:String):String;
Var
 Fin:TDigest;
 I,PL:Integer;
 S:String;
 Magic:String;
Begin
 Magic:='$apr1$';
 ML:=0;
 AddStr(Pw);AddStr(Salt);AddStr(Pw);
 MD5Run;
 Fin:=MD;
 ML:=0;
 AddStr(Pw);AddStr(Magic);AddStr(Salt);
 PL:=Length(Pw);
 While PL>0Do Begin
  If PL>16Then AddDig(Fin,16)
          Else AddDig(Fin,PL);
  Dec(PL,16);
 End;
 I:=Length(Pw);
 While I>0Do Begin
  If(I And 1)<>0Then AddStr(#0)
                Else AddStr(Copy(Pw,1,1));
  I:=I Shr 1;
 End;
 MD5Run;
 Fin:=MD;
 For I:=0 to 999 Do Begin
  ML:=0;
  If(I And 1)<>0Then AddStr(Pw)
                Else AddDig(Fin,16);
  If I Mod 3<>0Then AddStr(Salt);
  If I Mod 7<>0Then AddStr(Pw);
  If(I And 1)<>0Then AddDig(Fin,16)
                Else AddStr(Pw);
  MD5Run;
  Fin:=MD;
 End;
 S:=Magic+Salt+'$';
 S:=S+To64((Longint(Fin[0])Shl 16)Or(Longint(Fin[6])Shl 8)Or Fin[12],4);
 S:=S+To64((Longint(Fin[1])Shl 16)Or(Longint(Fin[7])Shl 8)Or Fin[13],4);
 S:=S+To64((Longint(Fin[2])Shl 16)Or(Longint(Fin[8])Shl 8)Or Fin[14],4);
 S:=S+To64((Longint(Fin[3])Shl 16)Or(Longint(Fin[9])Shl 8)Or Fin[15],4);
 S:=S+To64((Longint(Fin[4])Shl 16)Or(Longint(Fin[10])Shl 8)Or Fin[5],4);
 S:=S+To64(Fin[11],2);
 Apr1:=S;
End;

{ ------------------------- crypt() DES traditionnel ------------------------- }

Procedure DesSetKey;
Var
 C,D:Array[0..27]Of Byte;
 I,J,K:Integer;
 T:Byte;
Begin
 For J:=0 to 27 Do Begin
  C[J]:=Blk[PC1C[J]-1];
  D[J]:=Blk[PC1D[J]-1];
 End;
 For I:=0 to 15 Do Begin
  For K:=1 to Shifts[I]Do Begin
   T:=C[0];
   For J:=0 to 26 Do C[J]:=C[J+1];
   C[27]:=T;
   T:=D[0];
   For J:=0 to 26 Do D[J]:=D[J+1];
   D[27]:=T;
  End;
  For J:=0 to 23 Do Begin
   KS[I][J]:=C[PC2C[J]-1];
   KS[I][J+24]:=D[PC2D[J]-29];
  End;
 End;
End;

Procedure DesEncrypt;
Var
 L,R,Tmp,F:Array[0..31]Of Byte;
 PreS:Array[0..47]Of Byte;
 I,J,M,T,K:Integer;
Begin
 For J:=0 to 31 Do Begin
  L[J]:=Blk[IP[J]-1];
  R[J]:=Blk[IP[J+32]-1];
 End;
 For I:=0 to 15 Do Begin
  For J:=0 to 31 Do Tmp[J]:=R[J];
  For J:=0 to 47 Do PreS[J]:=R[Ee[J]-1]Xor KS[I][J];
  For J:=0 to 7 Do Begin
   T:=6*J;
   K:=SB[J*64+(PreS[T]Shl 5)+(PreS[T+1]Shl 3)+(PreS[T+2]Shl 2)+(PreS[T+3]Shl 1)+
      PreS[T+4]+(PreS[T+5]Shl 4)];
   For M:=0 to 3 Do F[4*J+M]:=(K Shr(3-M))And 1;
  End;
  For J:=0 to 31 Do R[J]:=L[J]Xor F[PBox[J]-1];
  For J:=0 to 31 Do L[J]:=Tmp[J];
 End;
 For J:=0 to 63 Do Begin
  T:=FP[J]-1;
  If T<32Then Blk[J]:=R[T]
         Else Blk[J]:=L[T-32];
 End;
End;

Function SaltVal(C:Char):Integer;
Var
 V:Integer;
Begin
 V:=Ord(C);
 If V>Ord('Z')Then V:=V-6;
 If V>Ord('9')Then V:=V-7;
 SaltVal:=V-Ord('.');
End;

Function DesCrypt(Const Pw,Salt:String):String;
Var
 I,J,C,K:Integer;
 T:Byte;
 S:String;
Begin
 FillChar(Blk,SizeOf(Blk),0);
 I:=0;
 K:=1;
 While(K<=Length(Pw))And(I<64)Do Begin
  C:=Ord(Pw[K]);
  For J:=0 to 6 Do Begin
   Blk[I]:=(C Shr(6-J))And 1;
   Inc(I);
  End;
  Inc(I);
  Inc(K);
 End;
 DesSetKey;
 FillChar(Blk,SizeOf(Blk),0);
 For I:=0 to 47 Do Ee[I]:=EBox[I];
 For I:=0 to 1 Do Begin
  C:=SaltVal(Salt[I+1]);
  For J:=0 to 5 Do If((C Shr J)And 1)<>0Then Begin
   T:=Ee[6*I+J];
   Ee[6*I+J]:=Ee[6*I+J+24];
   Ee[6*I+J+24]:=T;
  End;
 End;
 For I:=1 to 25 Do DesEncrypt;
 S:=Salt[1]+Salt[2];
 For I:=0 to 10 Do Begin
  C:=0;
  For J:=0 to 5 Do C:=(C Shl 1)Or Blk[6*I+J];
  S:=S+Itoa64[C+1];
 End;
 DesCrypt:=S;
End;

{ ------------------------- Programme principal ------------------------- }

Function RandSalt(N:Integer):String;
Var
 S:String;
 I:Integer;
Begin
 S:='';
 For I:=1 to N Do S:=S+Itoa64[Random(64)+1];
 RandSalt:=S;
End;

Function MakeHash(Const Pw:String):String;Begin
 If OptP Then MakeHash:=Pw
 Else If OptS Then Begin
  ML:=0;
  AddStr(Pw);
  SHA1Run;
  MakeHash:='{SHA}'+Base64Of(MD,20);
 End
 Else If OptM Then MakeHash:=Apr1(Pw,RandSalt(8))
 Else MakeHash:=DesCrypt(Pw,RandSalt(2));
End;

Function Field1(Const L:String):String;
Var
 P:Integer;
Begin
 P:=Pos(':',L);
 If P=0Then Field1:=L
       Else Field1:=Copy(L,1,P-1);
End;

Var
 I,J,N:Integer;
 A,PassFile,User,Pw,P2,Line,Tmp,L:String;
 Pos_:Array[1..3]Of String;
 F,T:Text;
 Found,Exists:Boolean;
 D:Char;

BEGIN
 Randomize;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='/?')Or(A='-h')Or(A='/h')Then Begin
   ShowHelp;
   Halt(0);
  End;
 End;
 N:=0;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(Length(A)>1)And(A[1]='-')And(N=0)Then Begin
   For J:=2 to Length(A)Do Begin
    D:=A[J];
    Case D of
     'b':OptB:=True;
     'c':OptC:=True;
     'n':OptN:=True;
     'm':OptM:=True;
     'd':OptD:=True;
     'p':OptP:=True;
     's':OptS:=True;
     'D':OptDel:=True;
     Else Begin
      WriteLn('htpasswd: option inconnue: -',D);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
  End
   Else
  Begin
   If N<3Then Begin
    Inc(N);
    Pos_[N]:=A;
   End
    Else
   Begin
    ShowUsage;
    Halt(1);
   End;
  End;
 End;
 { Attribution des parametres positionnels }
 If OptN Then Begin
  If OptDel Or OptC Then Begin
   ShowUsage;
   Halt(1);
  End;
  If(N<>1+Ord(OptB))Then Begin
   ShowUsage;
   Halt(1);
  End;
  PassFile:='';
  User:=Pos_[1];
  If OptB Then Pw:=Pos_[2];
 End
  Else
 Begin
  If OptDel Then Begin
   If N<>2Then Begin
    ShowUsage;
    Halt(1);
   End;
   PassFile:=Pos_[1];
   User:=Pos_[2];
  End
   Else
  Begin
   If N<>2+Ord(OptB)Then Begin
    ShowUsage;
    Halt(1);
   End;
   PassFile:=Pos_[1];
   User:=Pos_[2];
   If OptB Then Pw:=Pos_[3];
  End;
 End;
 If Pos(':',User)>0Then Fail('htpasswd: le nom d''utilisateur ne peut pas contenir ":"');
 { Suppression }
 If OptDel Then Begin
  Assign(F,PassFile);
  {$I-}Reset(F);{$I+}
  If IOResult<>0Then Fail('htpasswd: impossible d''ouvrir le fichier '+PassFile);
  Tmp:=PassFile+'.tmp';
  Assign(T,Tmp);
  {$I-}Rewrite(T);{$I+}
  If IOResult<>0Then Fail('htpasswd: impossible de creer '+Tmp);
  Found:=False;
  While Not EOF(F)Do Begin
   ReadLn(F,L);
   If Field1(L)=User Then Found:=True
                     Else WriteLn(T,L);
  End;
  Close(F);
  Close(T);
  If Not Found Then Begin
   Erase(T);
   Fail('User '+User+' not found');
  End;
  Erase(F);
  Rename(T,PassFile);
  WriteLn('Deleting password for user ',User);
  Halt(0);
 End;
 { Mot de passe }
 If Not OptB Then Begin
  Write('New password: ');
  ReadLn(Pw);
  Write('Re-type new password: ');
  ReadLn(P2);
  If Pw<>P2 Then Fail('htpasswd: password verification error');
 End;
 If Length(Pw)>127Then Fail('htpasswd: le mot de passe est trop long (127 caracteres maximum)');
 Line:=User+':'+MakeHash(Pw);
 If OptN Then Begin
  WriteLn(Line);
  Halt(0);
 End;
 If OptP Then WriteLn('Warning: storing passwords as plain text might just not work on this platform.');
 { Mise a jour du fichier }
 Exists:=False;
 If Not OptC Then Begin
  Assign(F,PassFile);
  {$I-}Reset(F);{$I+}
  If IOResult<>0Then
   Fail('htpasswd: cannot modify file '+PassFile+'; use ''-c'' to create it.');
  Close(F);
  Exists:=True;
 End;
 Tmp:=PassFile+'.tmp';
 Assign(T,Tmp);
 {$I-}Rewrite(T);{$I+}
 If IOResult<>0Then Fail('htpasswd: impossible de creer '+Tmp);
 Found:=False;
 If Exists Then Begin
  Assign(F,PassFile);
  Reset(F);
  While Not EOF(F)Do Begin
   ReadLn(F,L);
   If Field1(L)=User Then Begin
    If Not Found Then WriteLn(T,Line);
    Found:=True;
   End
    Else
   WriteLn(T,L);
  End;
  Close(F);
 End;
 If Not Found Then WriteLn(T,Line);
 Close(T);
 If Exists Then Begin
  Assign(F,PassFile);
  Erase(F);
 End
  Else
 Begin
  Assign(F,PassFile);
  {$I-}Erase(F);{$I+}
  If IOResult<>0Then;
 End;
 Assign(T,Tmp);
 {$I-}Rename(T,PassFile);{$I+}
 If IOResult<>0Then Fail('htpasswd: impossible de remplacer '+PassFile);
 If Found Then WriteLn('Updating password for user ',User)
          Else WriteLn('Adding password for user ',User);
END.
