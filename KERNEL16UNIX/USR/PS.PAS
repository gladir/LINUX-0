{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal (LPC /X))
  @description: ps de LINUX-0 : liste des processus (table du noyau, appel
   systeme procinfo) : numero, pere, utilisateur, etat (R pret, S en
   attente, Z zombie), image en memoire (L) ou dans la zone de va-et-vient
   (W), memoire, temps processeur et commande; memoire et va-et-vient.
   Usage : ps
}

Program PS;

Var
 P:TProcInfo; I:Integer; S,F:Char; T:Longint; M:TMemInfo;

Function Pad(L:Longint;W:Integer):String;
Var S:String;
Begin
 Str(L:W,S); Pad:=S;
End;

BEGIN
 If SysMemInfo(M)>=0 Then
  Begin
   WriteLn('memoire : ',Longint(M.TotalParas)*16 Div 1024,' Ko, libre ',
     Longint(M.FreeParas)*16 Div 1024,' Ko, ',M.ProcCount,' processus sur ',M.ProcMax);
   If M.SwapKB>0 Then
    WriteLn('va-et-vient : ',M.SwapKB,' Ko, libre ',M.SwapFreeKB,' Ko, ',
      M.SwapOuts,' sorties, ',M.SwapIns,' retours');
  End;
 WriteLn('  PID  PPID   UID S F   MEM   TIME COMMAND');
 For I:=1 To 63 Do
  If SysProcInfo(I,P) Then Begin
   Case P.Stat Of 1:S:='R'; 2:S:='S'; Else S:='Z' End;
   T:=(P.Ticks*10) Div 182;
   If P.Flags And 2<>0 Then F:='W' Else F:='L';
   WriteLn(Pad(P.Pid,5),Pad(P.PPid,6),Pad(P.Uid,6),' ',S,' ',F,Pad(Longint(P.Paras)*16 Div 1024,5),'K',
     Pad(T Div 60,4),':',Chr(48+(T Mod 60) Div 10),Chr(48+T Mod 10),' ',P.Name);
  End;
END.
