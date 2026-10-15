{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande htdigest - Gestion des fichiers digest d'Apache
}

Program HTDIGEST;

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

Var
 Create:Boolean;

Procedure ShowUsage;Begin
 WriteLn('Usage: htdigest [ -c ] passwdfile realm username');
End;

Procedure ShowHelp;Begin
 WriteLn('HTDIGEST : Cette commande permet d''effectuer la gestion des fichiers utilisateur ',
         'pour l''authentification "digest" d''Apache.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -c          Cree le fichier de mots de passe (ecrase s''il existe)');
 WriteLn('  passwdfile  Fichier contenant les mots de passe');
 WriteLn('  realm       Nom de domaine ("realm") de l''utilisateur');
 WriteLn('  username    Utilisateur a creer ou mettre a jour');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Fail(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,S);
 {$ELSE}
 WriteLn(S);
 {$ENDIF}
 Halt(1);
End;

{ ------------------------- MD5 ------------------------- }

Function RotL(X:Longint;N:Integer):Longint;Begin
 RotL:=(X Shl N)Or((X Shr(32-N))And((Longint(1)Shl N)-1));
End;

Function MD5Hex(Const S:String):String;
Var
 M:Array[0..319]Of Byte;
 W:Array[0..15]Of Longint;
 Len,Total,Blk,I,J,G:Integer;
 A,B,C,D,AA,BB,CC,DD,F:Longint;
 Bits:Longint;
 R:String;
Begin
 Len:=Length(S);
 FillChar(M,SizeOf(M),0);
 For I:=1 to Len Do M[I-1]:=Ord(S[I]);
 M[Len]:=$80;
 Total:=((Len+8)Div 64+1)*64;
 Bits:=Longint(Len)*8;
 M[Total-8]:=Bits And 255;
 M[Total-7]:=(Bits Shr 8)And 255;
 A:=1732584193;
 B:=-271733879;
 C:=-1732584194;
 D:=271733878;
 For Blk:=0 to Total Div 64-1 Do Begin
  For I:=0 to 15 Do Begin
   J:=Blk*64+I*4;
   W[I]:=Longint(M[J])Or(Longint(M[J+1])Shl 8)Or(Longint(M[J+2])Shl 16)Or(Longint(M[J+3])Shl 24);
  End;
  AA:=A;
  BB:=B;
  CC:=C;
  DD:=D;
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
  A:=A+AA;
  B:=B+BB;
  C:=C+CC;
  D:=D+DD;
 End;
 R:='';
 For I:=0 to 3 Do Begin
  Case I of
   0:F:=A;
   1:F:=B;
   2:F:=C;
   Else F:=D;
  End;
  For J:=0 to 3 Do Begin
   G:=(F Shr(8*J))And 255;
   R:=R+HexDigits[(G Shr 4)+1]+HexDigits[(G And 15)+1];
  End;
 End;
 MD5Hex:=R;
End;

{ ------------------------- Fichier de mots de passe ------------------------- }

Function Field(Const L:String;N:Integer):String;
Var
 I,K:Integer;
 S:String;
Begin
 K:=1;
 S:='';
 For I:=1 to Length(L)Do Begin
  If L[I]=':'Then Inc(K)
  Else If K=N Then S:=S+L[I];
 End;
 Field:=S;
End;

Var
 I,N:Integer;
 A,PassFile,Realm,User,P1,P2,Tmp,L,Line:String;
 F,T:Text;
 Found:Boolean;
 R:Integer;

BEGIN
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='/?')Or(A='--help')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
 End;
 N:=0;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='-c')And(N=0)Then Create:=True
  Else Begin
   Inc(N);
   If N=1Then PassFile:=A
   Else If N=2Then Realm:=A
   Else If N=3Then User:=A;
  End;
 End;
 If N<>3Then Begin
  ShowUsage;
  Halt(1);
 End;
 If(Pos(':',User)>0)Or(Pos(':',Realm)>0)Then Fail('htdigest: le nom d''utilisateur et le realm ne peuvent pas contenir ":"');
 Found:=False;
 If Create Then Begin
  Assign(T,PassFile);
  {$I-}Rewrite(T);{$I+}
  If IOResult<>0Then Fail('Could not open passwd file '+PassFile+' for writing.');
  Close(T);
 End
  Else
 Begin
  Assign(F,PassFile);
  {$I-}Reset(F);{$I+}
  If IOResult<>0Then
   Fail('Could not open passwd file '+PassFile+' for reading.'+#13#10+'Use -c option to create new one.');
  While Not EOF(F)Do Begin
   ReadLn(F,L);
   If(Field(L,1)=User)And(Field(L,2)=Realm)Then Found:=True;
  End;
  Close(F);
 End;
 If Found Then WriteLn('Changing password for user ',User,' in realm ',Realm)
          Else WriteLn('Adding user ',User,' in realm ',Realm);
 Write('New password: ');
 ReadLn(P1);
 Write('Re-type new password: ');
 ReadLn(P2);
 If P1<>P2 Then Fail('They don''t match, sorry.');
 Line:=User+':'+Realm+':'+MD5Hex(User+':'+Realm+':'+P1);
 { Reecriture via un fichier temporaire }
 Tmp:=PassFile+'.tmp';
 Assign(T,Tmp);
 {$I-}Rewrite(T);{$I+}
 If IOResult<>0Then Fail('Could not open temp file '+Tmp+'.');
 Found:=False;
 Assign(F,PassFile);
 {$I-}Reset(F);{$I+}
 If IOResult=0Then Begin
  While Not EOF(F)Do Begin
   ReadLn(F,L);
   If(Field(L,1)=User)And(Field(L,2)=Realm)Then Begin
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
 Assign(F,PassFile);
 {$I-}Erase(F);{$I+}
 R:=IOResult;
 Assign(T,Tmp);
 {$I-}Rename(T,PassFile);{$I+}
 If IOResult<>0Then Fail('Could not replace passwd file '+PassFile+'.');
END.
