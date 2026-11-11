{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: rm de LINUX-0 : supprime des fichiers (unlink); -r supprime
   aussi les repertoires et leur contenu, -f ne signale pas les erreurs.
   Usage : rm [-rf] fichier...
}

Program Rm;

Var
 I,R:Integer; Force,Rec:Boolean; S:String;

Procedure Remove(P:String);
Var St:TStat; Fd,N,Pos_,K:Integer; Buf:Array[0..511]Of Byte; Name:String;
  Names:Array[1..32]Of String[63]; NN:Integer; More:Boolean;
Begin
 If SysStat(P,St)<0 Then Begin
  If Not Force Then Begin WriteLn('rm : ',P,' : ',SysErrorText(Errno)); R:=1 End;
  Exit;
 End;
 If St.Mode And S_IFMT=S_IFDIR Then Begin
  If Not Rec Then Begin WriteLn('rm : ',P,' : est un repertoire'); R:=1; Exit End;
  { contenu supprime par lots de 32 noms (le repertoire change pendant la
    suppression) }
  Repeat
   Fd:=SysOpen(P,O_RDONLY,0);
   If Fd<0 Then Break;
   NN:=0; More:=False;
   Repeat
    N:=SysGetDirEntries(Fd,Buf,SizeOf(Buf));
    Pos_:=0;
    While Pos_<N Do Begin
     Name:='';
     For K:=0 To Buf[Pos_+7]-1 Do Name:=Name+Chr(Buf[Pos_+8+K]);
     If (Name<>'.')And(Name<>'..') Then Begin
      If NN<32 Then Begin Inc(NN); Names[NN]:=Name End Else More:=True;
     End;
     Inc(Pos_,Buf[Pos_+4]+Buf[Pos_+5]*256);
    End;
   Until N<=0;
   SysClose(Fd);
   For K:=1 To NN Do Remove(P+'/'+Names[K]);
  Until Not More;
  If SysRmdir(P)<0 Then
   If Not Force Then Begin WriteLn('rm : ',P,' : ',SysErrorText(Errno)); R:=1 End;
 End Else If SysUnlink(P)<0 Then
  If Not Force Then Begin WriteLn('rm : ',P,' : ',SysErrorText(Errno)); R:=1 End;
End;

BEGIN
 R:=0; Force:=False; Rec:=False; I:=1;
 While (I<ArgCount)And(Copy(ArgStr(I),1,1)='-')And(ArgStr(I)<>'-') Do Begin
  S:=ArgStr(I);
  If Pos('r',S)>0 Then Rec:=True;
  If Pos('f',S)>0 Then Force:=True;
  Inc(I);
 End;
 If I>=ArgCount Then Begin WriteLn('usage : rm [-rf] fichier...'); Halt(2) End;
 While I<ArgCount Do Begin Remove(ArgStr(I)); Inc(I) End;
 Halt(R);
END.
