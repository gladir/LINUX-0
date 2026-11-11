{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: mkdir de LINUX-0 : cree des repertoires (mode 0777 filtre
   par umask), avec "." et "..". -p cree aussi les repertoires parents
   manquants et ne signale pas un repertoire deja present. Messages en
   francais, ou selon la variable d'environnement LANGUAGE : EN anglais,
   GR allemand, SP espagnol, IT italien.
   Usage : mkdir [-p] repertoire...
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program MkDir_;

Const
 mUsage=1; mHelp2=2; mHelp3=3; mBadOpt=4;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..4,1..5] Of PChar=(
  ('Usage : mkdir [-p] repertoire...','Usage: mkdir [-p] directory...',
   'Aufruf: mkdir [-p] Verzeichnis...','Uso: mkdir [-p] directorio...',
   'Uso: mkdir [-p] directory...'),
  ('Cree des repertoires.','Create directories.',
   'Legt Verzeichnisse an.','Crea directorios.','Crea directory.'),
  ('  -p  cree aussi les repertoires parents manquants',
   '  -p  also create missing parent directories',
   '  -p  legt auch fehlende uebergeordnete Verzeichnisse an',
   '  -p  crea tambien los directorios padre que falten',
   '  -p  crea anche le directory superiori mancanti'),
  ('mkdir : option inconnue : ','mkdir: unknown option: ',
   'mkdir: unbekannte Option: ','mkdir: opcion desconocida: ',
   'mkdir: opzione sconosciuta: '));

Var
 I,R,N:Integer; Parents:Boolean; S:String; St:TStat;

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

Procedure Make(P:String);
{ cree P; avec -p, ses parents d'abord, sans erreur s'il existe deja }
Var K:Integer; D:String;
Begin
 While (Length(P)>1)And(P[Length(P)]='/') Do Dec(P[0]);
 If Parents Then Begin
  If (SysStat(P,St)=0)And(St.Mode And S_IFMT=S_IFDIR) Then Exit;
  K:=Length(P);
  While (K>0)And(P[K]<>'/') Do Dec(K);
  If K>1 Then Begin
   D:=Copy(P,1,K-1);
   If SysStat(D,St)<0 Then Make(D);
  End;
 End;
 If SysMkdir(P,$1FF)<0 Then Begin
  Put(2,'mkdir : '+P+' : '+SysErrorText(Errno)+#10); R:=1;
 End;
End;

BEGIN
 R:=0; Parents:=False; I:=1;
 While (I<ArgCount)And(Copy(ArgStr(I),1,1)='-')And(ArgStr(I)<>'-') Do Begin
  S:=ArgStr(I);
  If (S='-h')Or(S='--help') Then Begin
   For N:=mUsage To mHelp3 Do Put(1,Msg(N)+#10);
   Halt(0);
  End Else If S='-p' Then Parents:=True
  Else If S='--' Then Begin Inc(I); Break End
  Else Begin Put(2,Msg(mBadOpt)+S+#10); Put(2,Msg(mUsage)+#10); Halt(2) End;
  Inc(I);
 End;
 If (I>=ArgCount)Or(ArgStr(1)='/?') Then Begin
  If ArgStr(1)='/?' Then Begin
   For N:=mUsage To mHelp3 Do Put(1,Msg(N)+#10);
   Halt(0);
  End;
  Put(2,Msg(mUsage)+#10); Halt(2);
 End;
 While I<ArgCount Do Begin Make(ArgStr(I)); Inc(I) End;
 Halt(R);
END.
