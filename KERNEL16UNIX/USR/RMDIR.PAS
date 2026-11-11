{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: rmdir de LINUX-0 : supprime des repertoires vides. Messages
   en francais, ou selon la variable d'environnement LANGUAGE : EN anglais,
   GR allemand, SP espagnol, IT italien.
   Usage : rmdir repertoire...
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program RmDir_;

Const
 mUsage=1; mHelp2=2;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..2,1..5] Of PChar=(
  ('Usage : rmdir repertoire...','Usage: rmdir directory...',
   'Aufruf: rmdir Verzeichnis...','Uso: rmdir directorio...',
   'Uso: rmdir directory...'),
  ('Supprime des repertoires vides.','Remove empty directories.',
   'Entfernt leere Verzeichnisse.','Elimina directorios vacios.',
   'Rimuove directory vuote.'));

Var
 I,R:Integer; S:String;

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
 R:=0;
 S:=ArgStr(1);
 If (S='/?')Or(S='-h')Or(S='--help') Then Begin
  Put(1,Msg(mUsage)+#10+Msg(mHelp2)+#10); Halt(0);
 End;
 If ArgCount<2 Then Begin Put(2,Msg(mUsage)+#10); Halt(2) End;
 For I:=1 To ArgCount-1 Do
  If SysRmdir(ArgStr(I))<0 Then Begin
   Put(2,'rmdir : '+ArgStr(I)+' : '+SysErrorText(Errno)+#10); R:=1;
  End;
 Halt(R);
END.
