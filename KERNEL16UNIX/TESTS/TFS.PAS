{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: Test des systemes de fichiers de LINUX-0 sur /usr (racine
   UFS1) et /boot (FAT16) : creation, gros fichier (blocs indirects),
   relecture, suppression, renommage, repertoires, troncature; liens
   physiques et casse significative (UFS), fichier core.
   Lance comme /etc/init par TESTS/RUNTESTS.SH; affiche TERMINE a la fin.
}

Program TFS;
Var Buf:Array[0..1023] of Byte; I,J,E,N:Integer; F:File; T:Longint; S:String; St:TStat;
Procedure Chk(S:String;E:Integer);Begin If E<>0 Then WriteLn('ECHEC ',S,' -> ',E,' errno=',Errno); End;
Procedure Stress(R:String);
Begin
 WriteLn('== ',R);
 Chk('mkdir',SysMkdir(R+'/d',$1ED));
 For I:=1 To 40 Do Begin
  Str(I,S); Assign(F,R+'/d/f'+S+'.dat'); {$I-}Rewrite(F,1);{$I+} E:=IOResult; Chk('rewrite '+S,E);
  If E=0 Then Begin
   For J:=0 To 1023 Do Buf[J]:=(I+J) And 255;
   For J:=1 To I Do BlockWrite(F,Buf,100+I);
   Close(F);
  End;
 End;
 { gros fichier : 130 Ko (blocs indirects pour UFS) }
 Assign(F,R+'/d/gros.bin'); Rewrite(F,1);
 For J:=1 To 130 Do Begin Buf[0]:=J; BlockWrite(F,Buf,1024) End;
 Close(F);
 Reset(F,1); Seek(F,1024*77); BlockRead(F,Buf,1024); Close(F);
 If Buf[0]<>78 Then WriteLn('ECHEC relecture gros ',Buf[0]);
 Chk('stat',SysStat(R+'/d/gros.bin',St)); If St.Size<>133120 Then WriteLn('ECHEC taille ',St.Size);
 For I:=1 To 40 Do If I Mod 3=0 Then Begin Str(I,S); Chk('unlink '+S,SysUnlink(R+'/d/f'+S+'.dat')) End;
 Chk('rename',SysRename(R+'/d/f1.dat',R+'/d/un.dat'));
 Chk('mkdir2',SysMkdir(R+'/d/sous',$1ED));
 Chk('rename2',SysRename(R+'/d/f2.dat',R+'/d/sous/deux.dat'));
 Chk('mkdir3',SysMkdir(R+'/vide',$1ED));
 Chk('rmdir',SysRmdir(R+'/vide'));
 E:=SysRmdir(R+'/d'); If E=0 Then WriteLn('ECHEC rmdir non vide accepte');
 { troncature du gros fichier puis reecriture courte }
 Assign(F,R+'/d/gros.bin'); Rewrite(F,1); BlockWrite(F,Buf,10); Close(F);
 WriteLn('fin ',R);
End;
Begin
 Stress('/usr');
 WriteLn('== UFS : liens, casse, core');
 Chk('link',SysLink('/usr/d/un.dat','/usr/d/lien'));
 Chk('stat lien',SysStat('/usr/d/lien',St));
 If St.NLink<>2 Then WriteLn('ECHEC nlink ',St.NLink) Else WriteLn('ok lien physique (nlink 2)');
 If SysStat('/usr/d/UN.DAT',St)=0 Then WriteLn('ECHEC casse ignoree')
 Else WriteLn('ok casse significative');
 SysChdir('/usr');
 I:=Fork;
 If I=0 Then Begin SysKill(GetPid,SIGQUIT); SysExit(0) End;
 WaitPid(I,J,0);
 If (WTermSig(J)=SIGQUIT)And(J And $80<>0)And(SysStat('/usr/core',St)=0)And(St.Size>1000) Then
  WriteLn('ok core (',St.Size,' octets)')
 Else WriteLn('ECHEC core etat ',J);
 SysUnlink('/usr/core');
 Stress('/boot');
 SysSync;
 WriteLn('TERMINE');
 Repeat SysSleep(100) Until False;
End.
