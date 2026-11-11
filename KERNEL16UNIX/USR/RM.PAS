{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: rm de LINUX-0 : supprime des fichiers (unlink); -r (ou -R)
   supprime aussi les repertoires et leur contenu, -f ne signale pas les
   erreurs. Messages en francais, ou selon la variable d'environnement
   LANGUAGE : EN anglais, GR allemand, SP espagnol, IT italien.
   Usage : rm [-rf] fichier...
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program Rm;

{$M 16384,0,0}

Const
 mUsage=1; mHelp2=2; mHelp3=3; mHelp4=4; mIsDir=5;
 { messages : colonnes FR, EN, GR (allemand), SP, IT }
 M:Array[1..5,1..5] Of PChar=(
  ('Usage : rm [-rf] fichier...','Usage: rm [-rf] file...',
   'Aufruf: rm [-rf] Datei...','Uso: rm [-rf] archivo...',
   'Uso: rm [-rf] file...'),
  ('Supprime des fichiers.','Remove files.','Loescht Dateien.',
   'Elimina archivos.','Rimuove file.'),
  ('  -r  supprime aussi les repertoires et leur contenu',
   '  -r  also remove directories and their contents',
   '  -r  loescht auch Verzeichnisse samt Inhalt',
   '  -r  elimina tambien los directorios y su contenido',
   '  -r  rimuove anche le directory e il loro contenuto'),
  ('  -f  ne signale pas les erreurs','  -f  do not report errors',
   '  -f  keine Fehlermeldungen','  -f  no informa de los errores',
   '  -f  non segnala gli errori'),
  (' : est un repertoire',' : is a directory',' : ist ein Verzeichnis',
   ' : es un directorio',' : e una directory'));

Var
 I,R:Integer; Force,Rec:Boolean; S:String;
 Buf:Array[0..511]Of Byte;   { lecture d'un repertoire (hors de la pile) }

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

Procedure Fail(P:String);
Begin
 R:=1;
 If Not Force Then Put(2,'rm : '+P+' : '+SysErrorText(Errno)+#10);
End;

Procedure Remove(P:String);
Var St:TStat; Fd,N,Pos_,K:Integer; Name:String[63];
  Names:Array[1..12]Of String[39]; NN:Integer; More:Boolean;
Begin
 If SysStat(P,St)<0 Then Begin Fail(P); Exit End;
 If St.Mode And S_IFMT=S_IFDIR Then Begin
  If Not Rec Then Begin
   R:=1; Put(2,'rm : '+P+Msg(mIsDir)+#10); Exit;
  End;
  { contenu supprime par lots de 12 noms (le repertoire change pendant la
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
      If NN<12 Then Begin Inc(NN); Names[NN]:=Name End Else More:=True;
     End;
     Inc(Pos_,Buf[Pos_+4]+Buf[Pos_+5]*256);
    End;
   Until N<=0;
   SysClose(Fd);
   For K:=1 To NN Do Remove(P+'/'+Names[K]);
  Until Not More;
  If SysRmdir(P)<0 Then Fail(P);
 End Else If SysUnlink(P)<0 Then Fail(P);
End;

BEGIN
 R:=0; Force:=False; Rec:=False; I:=1;
 S:=ArgStr(1);
 If (S='/?')Or(S='-h')Or(S='--help') Then Begin
  For I:=mUsage To mHelp4 Do Put(1,Msg(I)+#10);
  Halt(0);
 End;
 While (I<ArgCount)And(Copy(ArgStr(I),1,1)='-')And(ArgStr(I)<>'-') Do Begin
  S:=ArgStr(I); Inc(I);
  If S='--' Then Break;
  If (Pos('r',S)>0)Or(Pos('R',S)>0) Then Rec:=True;
  If Pos('f',S)>0 Then Force:=True;
 End;
 If I>=ArgCount Then Begin
  If Not Force Then Begin Put(2,Msg(mUsage)+#10); Halt(2) End;
  Halt(0);
 End;
 While I<ArgCount Do Begin Remove(ArgStr(I)); Inc(I) End;
 Halt(R);
END.
