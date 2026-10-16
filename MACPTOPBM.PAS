{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande macptopbm - Convertit une image MacPaint en PBM
}

Program MACPTOPBM;

{$X+}
{$R-}

Uses DOS;

Const
 MaxLines=720;
 BytesWide=72;
 HeaderLength=512;

Type
 TPic=Array[0..MaxLines-1,0..BytesWide-1]Of Byte;
 PPic=^TPic;

Var
 F:File;
 InBuf:Array[0..4095]Of Byte;
 InPos,InLen:Integer;
 InEof,UseStdin:Boolean;
 OutBuf:String;
 Pic:PPic;

Procedure ShowUsage;Begin
 WriteLn('Usage: macptopbm [-extraskip N] [macpfile]');
End;

Procedure ShowHelp;Begin
 WriteLn('MACPTOPBM : Cette commande permet d''effectuer la conversion d''un fichier d''image ',
         'MacPaint au format portable Bitmap.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -extraskip N  Saute N octets supplementaires au debut du fichier');
 WriteLn('                (ex: 128 pour un en-tete MacBinary/finderinfo)');
 WriteLn('  macpfile      Fichier MacPaint (defaut: entree standard)');
 WriteLn('  /?, --help    Affiche cette aide');
 WriteLn;
 WriteLn('Le PBM (P4, 576x720 au maximum) est ecrit sur la sortie standard; redirigez-la.');
End;

Procedure Fail(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'macptopbm: ',S);
 {$ELSE}
 WriteLn('macptopbm: ',S);
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

{ Retourne -1 en fin de fichier }
Function GetB:Integer;
Var
 N:Word;
 C:Char;
Begin
 If UseStdin Then Begin
  If EOF(Input)Then Begin
   GetB:=-1;
   Exit;
  End;
  Read(Input,C);
  GetB:=Ord(C);
  Exit;
 End;
 If InPos>=InLen Then Begin
  If InEof Then Begin
   GetB:=-1;
   Exit;
  End;
  BlockRead(F,InBuf,SizeOf(InBuf),N);
  InLen:=N;
  InPos:=0;
  If N=0Then Begin
   InEof:=True;
   GetB:=-1;
   Exit;
  End;
 End;
 GetB:=InBuf[InPos];
 Inc(InPos);
End;

Procedure FlushOut;Begin
 If Length(OutBuf)>0Then Write(OutBuf);
 OutBuf:='';
End;

Procedure PutB(B:Integer);Begin
 OutBuf:=OutBuf+Chr(B And 255);
 If Length(OutBuf)>=250Then FlushOut;
End;

Function ToNumber(Const S:String;Var N:Longint):Boolean;
Var
 Err:Integer;
Begin
 Val(S,N,Err);
 ToNumber:=(Err=0)And(N>=0);
End;

{ -extraskip peut etre abrege: -e, -ex, ... -extraskip }
Function IsExtraSkip(Const A:String):Boolean;
Var
 S:String;
Begin
 IsExtraSkip:=False;
 If(Length(A)<2)Or(A[1]<>'-')Then Exit;
 S:=Copy(A,2,255);
 If S[1]='-'Then S:=Copy(S,2,255);
 If(S<>'')And(Length(S)<=9)And(Copy('extraskip',1,Length(S))=S)Then IsExtraSkip:=True;
End;

Var
 I,B,Cnt,J,Row,Col,Rows:Integer;
 ExtraSkip,Tmp:Longint;
 A,FileName:String;
 Done:Boolean;

BEGIN
 ExtraSkip:=0;
 FileName:='';
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='-help')Or(A='/?')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End
  Else If(A='--version')Or(A='-version')Then Begin
   WriteLn('macptopbm (netpbm clone) 1.0');
   Halt(0);
  End
  Else If IsExtraSkip(A)Then Begin
   Inc(I);
   If I>ParamCount Then Begin
    ShowUsage;
    Halt(1);
   End;
   If Not ToNumber(ParamStr(I),ExtraSkip)Then Fail('valeur invalide pour -extraskip: '+ParamStr(I));
  End
  Else If(Length(A)>1)And(A[1]='-')Then Begin
   WriteLn('macptopbm: option inconnue: ',A);
   ShowUsage;
   Halt(1);
  End
  Else Begin
   If FileName<>''Then Begin
    ShowUsage;
    Halt(1);
   End;
   FileName:=A;
  End;
  Inc(I);
 End;
 UseStdin:=FileName='';
 {$IFDEF FPC}
 { Free Pascal: lecture binaire de l'entree standard via son descripteur }
 If UseStdin Then Begin
  {$IFDEF UNIX}
  Assign(F,'/dev/null');
  {$ELSE}
  Assign(F,'NUL');
  {$ENDIF}
  {$I-}Reset(F,1);{$I+}
  If IOResult<>0Then Fail('impossible de lire l''entree standard');
  FileRec(F).Handle:=StdInputHandle;
  UseStdin:=False;
 End
  Else
 {$ENDIF}
 If Not UseStdin Then Begin
  Assign(F,FileName);
  {$I-}Reset(F,1);{$I+}
  If IOResult<>0Then Fail('impossible d''ouvrir '+FileName);
 End;
 InPos:=0;
 InLen:=0;
 InEof:=False;
 OutBuf:='';
 New(Pic);
 FillChar(Pic^,SizeOf(Pic^),0);
 { En-tete: octets supplementaires puis 512 octets }
 For Tmp:=1 to ExtraSkip+HeaderLength Do
  If GetB<0Then Fail('fin de fichier prematuree dans l''en-tete');
 { Decompression PackBits }
 Row:=0;
 Col:=0;
 Done:=False;
 While Not Done And(Row<MaxLines)Do Begin
  Cnt:=GetB;
  If Cnt<0Then Break;
  If Cnt<128Then Begin
   For J:=0 to Cnt Do Begin
    B:=GetB;
    If B<0Then Begin
     Done:=True;
     Break;
    End;
    If Row<MaxLines Then Pic^[Row,Col]:=B;
    Inc(Col);
    If Col>=BytesWide Then Begin
     Col:=0;
     Inc(Row);
    End;
   End;
  End
   Else
  Begin
   B:=GetB;
   If B<0Then Break;
   For J:=1 to 257-Cnt Do Begin
    If Row<MaxLines Then Pic^[Row,Col]:=B;
    Inc(Col);
    If Col>=BytesWide Then Begin
     Col:=0;
     Inc(Row);
    End;
   End;
  End;
 End;
 Rows:=Row;
 If Rows=0Then Fail('aucune ligne d''image lue (fichier vide ou -extraskip incorrect)');
 If Rows<MaxLines Then Begin
  {$IFDEF FPC}
  WriteLn(StdErr,'macptopbm: attention: seulement ',Rows,' lignes sur ',MaxLines,' lues');
  {$ELSE}
  WriteLn('macptopbm: attention: seulement ',Rows,' lignes sur ',MaxLines,' lues');
  {$ENDIF}
 End;
 A:='P4'+#10+IntStr(BytesWide*8)+' '+IntStr(Rows)+#10;
 For I:=1 to Length(A)Do PutB(Ord(A[I]));
 For Row:=0 to Rows-1 Do
  For Col:=0 to BytesWide-1 Do PutB(Pic^[Row,Col]);
 FlushOut;
 If Not UseStdin Then Close(F);
 Dispose(Pic);
END.
