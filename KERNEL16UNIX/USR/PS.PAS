{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: KERNEL16UNIX (LPC /X))
  @description: ps de LINUX-0 : liste des processus (table du noyau, appel
   systeme procinfo) : numero, pere, utilisateur, etat (R pret, S en
   attente, Z zombie), image en memoire (L) ou dans la zone de va-et-vient
   (W), memoire, temps processeur et commande; memoire et va-et-vient.
   Messages en francais, ou selon la variable d'environnement LANGUAGE : EN
   anglais, GR allemand, SP espagnol, IT italien.
   Usage : ps
}

{$DEFINE LANGERR}   { messages d'erreur du systeme en 5 langues }

Program PS;

Const
 mHelp1=1; mHelp2=2; mMem=3; mSwap=4; mBadOpt=5;
 { messages : colonnes FR, EN, GR (allemand), SP, IT; % = une valeur }
 M:Array[1..5,1..5] Of PChar=(
  ('Usage : ps','Usage: ps','Aufruf: ps','Uso: ps','Uso: ps'),
  ('Liste les processus, la memoire et la zone de va-et-vient.',
   'List the processes, the memory and the swap area.',
   'Zeigt Prozesse, Speicher und Auslagerungsbereich an.',
   'Lista los procesos, la memoria y el area de intercambio.',
   'Elenca i processi, la memoria e l''area di swap.'),
  ('memoire : % Ko, libre % Ko, % processus sur %',
   'memory: % KB, free % KB, % processes of %',
   'Speicher: % KB, frei % KB, % Prozesse von %',
   'memoria: % KB, libre % KB, % procesos de %',
   'memoria: % KB, libera % KB, % processi su %'),
  ('va-et-vient : % Ko, libre % Ko, % sorties, % retours',
   'swap: % KB, free % KB, % swap-outs, % swap-ins',
   'Auslagerung: % KB, frei % KB, % Aus-, % Einlagerungen',
   'intercambio: % KB, libre % KB, % salidas, % entradas',
   'swap: % KB, libero % KB, % uscite, % rientri'),
  ('ps : option inconnue : ','ps: unknown option: ',
   'ps: unbekannte Option: ','ps: opcion desconocida: ',
   'ps: opzione sconosciuta: '));

Var
 P:TProcInfo; I:Integer; S,F:Char; T:Longint; Mi:TMemInfo; A:String;

Function Msg(Id:Integer):String;
Var Q:PChar; X:String;
Begin
 Q:=M[Id,SysLang]; X:='';
 While Q^<>#0 Do Begin X:=X+Q^; Inc(Q) End;
 Msg:=X;
End;

Function Fmt(S:String;A,B,C,D:Longint):String;
{ remplace les quatre premiers % de S par les valeurs A, B, C et D }
Var K,N:Integer; V:Longint; R,X:String;
Begin
 R:=''; N:=0;
 For K:=1 To Length(S) Do
  If S[K]='%' Then Begin
   Inc(N);
   Case N Of 1:V:=A; 2:V:=B; 3:V:=C; Else V:=D End;
   Str(V,X); R:=R+X;
  End Else R:=R+S[K];
 Fmt:=R;
End;

Function Pad(L:Longint;W:Integer):String;
Var S:String;
Begin
 Str(L:W,S); Pad:=S;
End;

BEGIN
 A:=ArgStr(1);
 If (A='/?')Or(A='-h')Or(A='--help') Then Begin
  WriteLn(Msg(mHelp1)); WriteLn(Msg(mHelp2)); Halt(0);
 End;
 If A<>'' Then Begin WriteLn(Msg(mBadOpt),A); Halt(2) End;
 If SysMemInfo(Mi)>=0 Then
  Begin
   WriteLn(Fmt(Msg(mMem),Longint(Mi.TotalParas)*16 Div 1024,
     Longint(Mi.FreeParas)*16 Div 1024,Mi.ProcCount,Mi.ProcMax));
   If Mi.SwapKB>0 Then
    WriteLn(Fmt(Msg(mSwap),Mi.SwapKB,Mi.SwapFreeKB,Mi.SwapOuts,Mi.SwapIns));
  End;
 WriteLn('  PID  PPID   UID S F   MEM   TIME COMMAND');
 For I:=1 To 63 Do
  If SysProcInfo(I,P) Then Begin
   Case P.Stat Of 1:S:='R'; 2:S:='S'; Else S:='Z' End;
   T:=(P.Ticks*10) Div 182;
   If P.Flags And 2<>0 Then F:='W' Else F:='L';
   WriteLn(Pad(P.Pid,5),Pad(P.PPid,6),Pad(P.Uid,6),' ',S,' ',F,
     Pad(Longint(P.Paras)*16 Div 1024,5),'K',
     Pad(T Div 60,4),':',Chr(48+(T Mod 60) Div 10),Chr(48+T Mod 10),' ',
     P.Name);
  End;
END.
