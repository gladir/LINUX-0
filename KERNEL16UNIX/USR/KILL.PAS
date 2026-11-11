{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: kill de LINUX-0 : envoie un signal (SIGTERM par defaut) aux
   processus indiques. Le signal est un numero ou un nom de UNIX V7 (HUP,
   INT, QUIT, ILL, TRAP, IOT, EMT, FPE, KILL, BUS, SEGV, SYS, PIPE, ALRM,
   TERM). kill -l liste les noms. Messages en francais, ou selon la variable
   d'environnement LANGUAGE : EN anglais, GR allemand, SP espagnol, IT
   italien.
   Usage : kill [-signal] pid...
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program Kill;

Const
 Names:Array[1..15]Of String[4]=('HUP','INT','QUIT','ILL','TRAP','IOT','EMT',
   'FPE','KILL','BUS','SEGV','SYS','PIPE','ALRM','TERM');
 mUsage=1; mHelp2=2; mHelp3=3; mBadSig=4; mNeedPid=5;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..5,1..5] Of PChar=(
  ('Usage : kill [-signal] pid...','Usage: kill [-signal] pid...',
   'Aufruf: kill [-Signal] pid...','Uso: kill [-senal] pid...',
   'Uso: kill [-segnale] pid...'),
  ('Envoie un signal (TERM par defaut) aux processus; kill -l : les noms.',
   'Send a signal (TERM by default) to processes; kill -l: the names.',
   'Sendet ein Signal (Standard TERM) an Prozesse; kill -l: die Namen.',
   'Envia una senal (TERM por omision) a procesos; kill -l: los nombres.',
   'Invia un segnale (TERM di default) ai processi; kill -l: i nomi.'),
  ('Le signal est un numero ou un nom : HUP, INT, KILL, TERM...',
   'The signal is a number or a name: HUP, INT, KILL, TERM...',
   'Das Signal ist eine Nummer oder ein Name: HUP, INT, KILL, TERM...',
   'La senal es un numero o un nombre: HUP, INT, KILL, TERM...',
   'Il segnale e un numero o un nome: HUP, INT, KILL, TERM...'),
  ('kill : signal inconnu : ','kill: unknown signal: ',
   'kill: unbekanntes Signal: ','kill: senal desconocida: ',
   'kill: segnale sconosciuto: '),
  (' : numero de processus attendu',' : process number expected',
   ' : Prozessnummer erwartet',' : se esperaba un numero de proceso',
   ' : numero di processo atteso'));

Var
 Sig,I,K,Pid,E,R:Integer; S:String;

Function Msg(Id:Integer):String;
Var P:PChar; T:String;
Begin
 P:=M[Id,SysLang]; T:='';
 While P^<>#0 Do Begin T:=T+P^; Inc(P) End;
 Msg:=T;
End;

Procedure Put(Fd:Integer;S:String);
Begin
 If Length(S)>0 Then SysWrite(Fd,S[1],Length(S));
End;

BEGIN
 Sig:=SIGTERM; I:=1; R:=0;
 S:=ArgStr(1);
 If (S='/?')Or(S='-h')Or(S='--help') Then Begin
  Put(1,Msg(mUsage)+#10+Msg(mHelp2)+#10+Msg(mHelp3)+#10); Halt(0);
 End;
 If ArgCount<2 Then Begin Put(2,Msg(mUsage)+#10); Halt(2) End;
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
  If (Sig<=0)Or(Sig>=NSIG) Then Begin
   Put(2,Msg(mBadSig)+S+#10); Halt(2);
  End;
  I:=2;
 End;
 For K:=I To ArgCount-1 Do Begin
  Val(ArgStr(K),Pid,E);
  If E<>0 Then Begin
   Put(2,'kill : '+ArgStr(K)+Msg(mNeedPid)+#10); R:=1;
  End Else If SysKill(Pid,Sig)<0 Then Begin
   Str(Pid,S); Put(2,'kill : '+S+' : '+SysErrorText(Errno)+#10); R:=1;
  End;
 End;
 Halt(R);
END.
