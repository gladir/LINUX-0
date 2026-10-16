{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande lispmtopgm - Convertit un bitmap Lisp Machine en PGM
}

Program LISPMTOPGM;

{$X+}
{$R-}

Uses DOS;

Const
 Magic='This is a BitMap file';

Var
 F:File;
 InBuf:Array[0..4095]Of Byte;
 InPos,InLen:Integer;
 InEof,UseStdin:Boolean;
 OutBuf:String;
 Item:Longint;
 BitsPerItem,MaxBitsPerItem,BitShift:Integer;
 BitMask:Longint;

Procedure ShowUsage;Begin
 WriteLn('Usage: lispmtopgm [lispmfile]');
End;

Procedure ShowHelp;Begin
 WriteLn('LISPMTOPGM : Cette commande permet d''effectuer la conversion d''un fichier de ',
         'bitmap machine Lisp a un format PGM.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  lispmfile   Fichier bitmap Lisp Machine (defaut: entree standard)');
 WriteLn('  /?, --help  Affiche cette aide');
 WriteLn;
 WriteLn('Le PGM (P5) est ecrit sur la sortie standard; redirigez-la dans un fichier.');
End;

Procedure Fail(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'lispmtopgm: ',S);
 {$ELSE}
 WriteLn('lispmtopgm: ',S);
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

Function GetB:Integer;
Var
 N:Word;
 C:Char;
Begin
 If UseStdin Then Begin
  If EOF(Input)Then Fail('EOF / read error');
  Read(Input,C);
  GetB:=Ord(C);
  Exit;
 End;
 If InPos>=InLen Then Begin
  If InEof Then Fail('EOF / read error');
  BlockRead(F,InBuf,SizeOf(InBuf),N);
  InLen:=N;
  InPos:=0;
  If N=0Then Begin
   InEof:=True;
   Fail('EOF / read error');
  End;
 End;
 GetB:=InBuf[InPos];
 Inc(InPos);
End;

Function ReadShort:Integer;
Var
 A,B:Integer;
Begin
 A:=GetB;
 B:=GetB;
 ReadShort:=A Or(B Shl 8);
End;

Function ReadLong:Longint;
Var
 A,B,C,D:Longint;
Begin
 A:=GetB;
 B:=GetB;
 C:=GetB;
 D:=GetB;
 ReadLong:=A Or(B Shl 8)Or(C Shl 16)Or(D Shl 24);
End;

Procedure FlushOut;Begin
 If Length(OutBuf)>0Then Write(OutBuf);
 OutBuf:='';
End;

Procedure PutB(B:Integer);Begin
 OutBuf:=OutBuf+Chr(B And 255);
 If Length(OutBuf)>=250Then FlushOut;
End;

Function WordSize(Depth:Integer):Integer;Begin
 If Depth<=1Then WordSize:=1
 Else If Depth=2Then WordSize:=2
 Else If Depth<=4Then WordSize:=4
 Else If Depth<=8Then WordSize:=8
 Else If Depth<=16Then WordSize:=16
 Else If Depth<=32Then WordSize:=32
 Else Begin
  Fail('depth was '+IntStr(Depth)+', which is not in the range 1-32.');
  WordSize:=32;
 End;
End;

Function GetVal:Longint;
Var
 B:Longint;
Begin
 If BitsPerItem=0Then Begin
  Item:=Not ReadLong;
  BitsPerItem:=32;
  BitShift:=0;
 End;
 If BitShift=0Then B:=Item And BitMask
  Else
 B:=((Item Shr BitShift)And((Longint(1)Shl(32-BitShift))-1))And BitMask;
 BitsPerItem:=BitsPerItem-MaxBitsPerItem;
 BitShift:=BitShift+MaxBitsPerItem;
 GetVal:=B;
End;

Var
 I,Cols,Rows,Cols32,Depth,PadRight:Integer;
 Row,Col:Integer;
 MaxVal,V:Longint;
 Hdr:String;
 A:String;
 Given:Integer;

BEGIN
 Given:=0;
 For I:=1 to ParamCount Do Begin
  A:=ParamStr(I);
  If(A='--help')Or(A='-help')Or(A='/?')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If(A='--version')Or(A='-version')Then Begin
   WriteLn('lispmtopgm (netpbm clone) 1.0');
   Halt(0);
  End;
  Inc(Given);
 End;
 If Given>1Then Begin
  ShowUsage;
  Halt(1);
 End;
 UseStdin:=Given=0;
 If Not UseStdin Then Begin
  Assign(F,ParamStr(1));
  {$I-}Reset(F,1);{$I+}
  If IOResult<>0Then Fail('impossible d''ouvrir '+ParamStr(1));
 End;
 InPos:=0;
 InLen:=0;
 InEof:=False;
 OutBuf:='';
 Hdr:='';
 For I:=1 to Length(Magic)Do Hdr:=Hdr+Chr(GetB);
 If Hdr<>Magic Then Fail('bad id string in Lispm file');
 Cols:=ReadShort;
 Rows:=ReadShort;
 Cols32:=ReadShort;
 Depth:=GetB;
 If Depth=0Then Depth:=1;
 PadRight:=((Cols+31)Div 32)*32-Cols;
 MaxBitsPerItem:=WordSize(Depth);
 BitMask:=(Longint(1)Shl MaxBitsPerItem)-1;
 If MaxBitsPerItem=32Then BitMask:=-1;
 BitsPerItem:=0;
 For I:=1 to 9Do GetB;
 If Depth>16Then Fail('depth is too large');
 MaxVal:=Longint(1)Shl Depth;
 If MaxVal>65535Then Fail('depth is too large - maxval would exceed 65535');
 { en-tete PGM brut (P5) }
 Hdr:='P5'+#10+IntStr(Cols)+' '+IntStr(Rows)+#10+IntStr(MaxVal)+#10;
 For I:=1 to Length(Hdr)Do PutB(Ord(Hdr[I]));
 For Row:=1 to Rows Do Begin
  For Col:=1 to Cols Do Begin
   V:=GetVal;
   If V>MaxVal Then V:=MaxVal;
   If MaxVal>255Then Begin
    PutB((V Shr 8)And 255);
    PutB(V And 255);
   End
    Else
   PutB(V And 255);
  End;
  For Col:=1 to PadRight Do V:=GetVal;
 End;
 FlushOut;
 If Not UseStdin Then Close(F);
END.
