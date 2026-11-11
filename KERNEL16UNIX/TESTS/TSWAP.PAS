{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: Test du va-et-vient de LINUX-0 : 8 processus d'environ
   75 Ko (bien plus que la memoire libre) remplissent un tableau de leur
   motif, dorment et calculent a tour de role, puis verifient leurs
   donnees, qui ont fait des allers-retours dans la zone de va-et-vient;
   puis exec de gros programmes avec des processus en attente.
   Lance comme /etc/init par TESTS/RUNTESTS.SH; affiche TERMINE a la fin.
}

Program TSWAP;

{$M 8192,0,0}

Const
 N=8;
 SZ=50000;

Var
 Buf:Array[0..SZ-1]Of Byte;
 Pids:Array[1..N]Of Integer;
 I,K,St,W,Bad:Integer; J:Word;
 M:TMemInfo; X:Longint;

Function Check(V:Byte):Boolean;
Var J:Word;
Begin
 Check:=False;
 For J:=0 To SZ-1 Do If Buf[J]<>Byte(V+J) Then Exit;
 Check:=True;
End;

Begin
 SysMemInfo(M);
 WriteLn('== memoire libre ',Longint(M.FreeParas)*16 Div 1024,' Ko, va-et-vient ',M.SwapKB,' Ko');
 For J:=0 To SZ-1 Do Buf[J]:=Byte(J);
 WriteLn('== 8 processus de 75 Ko');
 For I:=1 To N Do Begin
  Pids[I]:=Fork;
  If Pids[I]<0 Then WriteLn('ECHEC fork ',I,' : ',SysErrorText(Errno));
  If Pids[I]=0 Then Begin
   For J:=0 To SZ-1 Do Buf[J]:=Byte(I*37+J);
   For K:=1 To 3 Do Begin
    SysNap(300+I*50);
    X:=0; While X<200000 Do Inc(X);
    If Not Check(I*37) Then SysExit(1);
   End;
   SysExit(0);
  End;
 End;
 Bad:=0;
 For I:=1 To N Do Begin
  W:=WaitPid(-1,St,0);
  If St<>0 Then Begin WriteLn('ECHEC processus ',W,' etat ',St); Inc(Bad) End;
 End;
 If Not Check(0) Then Begin WriteLn('ECHEC donnees du pere'); Inc(Bad) End;
 SysMemInfo(M);
 WriteLn('sorties ',M.SwapOuts,', retours ',M.SwapIns);
 If (Bad=0)And(M.SwapOuts>0)And(M.SwapIns>0) Then WriteLn('ok donnees intactes apres va-et-vient')
 Else WriteLn('ECHEC va-et-vient');
 WriteLn('== exec avec des processus en attente');
 For I:=1 To 4 Do Begin
  Pids[I]:=Fork;
  If Pids[I]=0 Then Begin
   For J:=0 To SZ-1 Do Buf[J]:=Byte(I*11+J);
   SysNap(3000);
   If Check(I*11) Then SysExit(0) Else SysExit(1);
  End;
 End;
 Pids[5]:=VFork;
 If Pids[5]=0 Then Begin Execv('/bin/grep','root /etc/passwd'); SysExit(127) End;
 W:=WaitPid(Pids[5],St,0);
 If WExitStatus(St)=127 Then WriteLn('ECHEC exec de grep');
 Bad:=0;
 For I:=1 To 4 Do Begin W:=WaitPid(-1,St,0); If St<>0 Then Inc(Bad) End;
 If Bad=0 Then WriteLn('ok exec de grep, attentes intactes') Else WriteLn('ECHEC attentes');
 SysSync;
 WriteLn('TERMINE');
 Repeat SysSleep(100) Until False;
End.
