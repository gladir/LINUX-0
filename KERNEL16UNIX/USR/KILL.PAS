{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: kill de LINUX-0 : envoie un signal (SIGTERM par defaut) aux
   processus indiques. Le signal est un numero ou un nom de UNIX V7 (HUP,
   INT, QUIT, ILL, TRAP, IOT, EMT, FPE, KILL, BUS, SEGV, SYS, PIPE, ALRM,
   TERM). kill -l liste les noms.
   Usage : kill [-signal] pid...
}

Program Kill;

Const
 Names:Array[1..15]Of String[4]=('HUP','INT','QUIT','ILL','TRAP','IOT','EMT',
   'FPE','KILL','BUS','SEGV','SYS','PIPE','ALRM','TERM');

Var
 Sig,I,K,Pid,E,R:Integer; S:String;

BEGIN
 Sig:=SIGTERM; I:=1; R:=0;
 If ArgCount<2 Then Begin WriteLn('usage : kill [-signal] pid...'); Halt(2) End;
 S:=ArgStr(1);
 If S='-l' Then Begin
  For K:=1 To 15 Do Write(Names[K],' ');
  WriteLn; Halt(0);
 End;
 If (S<>'')And(S[1]='-') Then Begin
  Delete(S,1,1);
  If Copy(S,1,3)='SIG' Then Delete(S,1,3);
  Val(S,Sig,E);
  If E<>0 Then Begin
   Sig:=0;
   For K:=1 To 15 Do If Names[K]=S Then Sig:=K;
  End;
  If (Sig<=0)Or(Sig>=NSIG) Then Begin WriteLn('kill : signal inconnu : ',S); Halt(2) End;
  I:=2;
 End;
 For K:=I To ArgCount-1 Do Begin
  Val(ArgStr(K),Pid,E);
  If E<>0 Then Begin WriteLn('kill : ',ArgStr(K),' : numero de processus attendu'); R:=1 End
  Else If SysKill(Pid,Sig)<0 Then Begin
   WriteLn('kill : ',Pid,' : ',SysErrorText(Errno)); R:=1;
  End;
 End;
 Halt(R);
END.
