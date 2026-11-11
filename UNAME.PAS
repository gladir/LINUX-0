{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program UNAME;

{$IFDEF WINDOWS}
Uses SysUtils;
{$ENDIF}
{$IFDEF LPC}
Uses Unix;
{$ENDIF}

Var
 I:Integer;

{$IFDEF LPC}
Function OSVersion:String;
Var
 U:TUtsName;
Begin
 OSVersion:='LINUX-0';
 If SysUname(U)=0 Then OSVersion:=U.SysName;
End;

Procedure ShowUname(Opt:String);
Var
 U:TUtsName;
Begin
 If SysUname(U)<>0 Then Begin
  WriteLn('uname : appel systeme impossible');
  Exit;
 End;
 If(Opt='-s')or(Opt='--kernel-name')Then Write(U.SysName,' ') Else
 If(Opt='-n')or(Opt='--nodename')Then Write(U.NodeName,' ') Else
 If(Opt='-r')or(Opt='--kernel-release')Then Write(U.Release,' ') Else
 If(Opt='-v')or(Opt='--kernel-version')Then Write(U.Version,' ') Else
 If(Opt='-m')or(Opt='--machine')Then Write(U.Machine,' ') Else
 If(Opt='-a')or(Opt='--all')Then
  Write(U.SysName,' ',U.NodeName,' ',U.Release,' ',U.Version,' ',
        U.Machine,' ');
End;
{$ENDIF}

{$IFNDEF LPC}
Function OSVersion:String;Begin
 OSVersion:='MS-DOS';
  {$IFDEF LCLcarbon}
   OSVersion := 'Mac OS X';
  {$ELSE}
   {$IFDEF Linux}
    OSVersion := 'GNU/Linux';
   {$ELSE}
    {$IFDEF UNIX}
     OSVersion := 'Unix';
    {$ELSE}
    {$IFDEF WINDOWS}
     Case Win32Platform of
      0:Case Win32MajorVersion of
       3:OSVersion:='Windows 3';
       Else OSVersion:='Windows';
      End;
      1:Case Win32MajorVersion of
       4:Case Win32MinorVersion of
        0:OSVersion:='Windows 95';
        10:OSVersion:='Windows 98';
        90:OSVersion:='Windows ME';
        Else OSVersion:='Windows 90X';
       End;
      End;
      2:Begin
       Case Win32MajorVersion of
        3:Case Win32MinorVersion of
         1:OSVersion:='Windows NT 3.1';
         50:OSVersion:='Windows NT 3.50';
         51:OSVersion:='Windows NT 3.51';
         Else OSVersion:='Windows NT 3';
        End;
        4:OSVersion:='Windows NT 4';
        5:Case Win32MinorVersion of
         0:OSVersion:='Windows 2000';
         1:OSVersion:='Windows XP';
         2:OSVersion:='Windows XP 64';
         Else OSVersion:='Windows 2000 ou XP';
        End;
        6:Case Win32MinorVersion of
         0:OSVersion:='Windows Vista ou Windows Server 2003';
         1:OSVersion:='Windows 7 ou Windows Server 2008 R2';
         2:OSVersion:='Windows 8 ou Windows Server 2012';
         3:OSVersion:='Windows 8.1 ou Windows Server 2012 R2';
         Else OSVersion:='Windows';
        End;
        Else OSVersion:='Windows';
       End;
      End;
     End;
    {$ENDIF}
   {$ENDIF}
  {$ENDIF}
 {$ENDIF}
End;
{$ENDIF}

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('UNAME : Cette commande permet d''afficher des informations sur ',
          'le systŠme d''exploitation');
  WriteLn;
  WriteLn('Syntaxe : UNAME [-h]');
  WriteLn;
  WriteLn(' -h        Affiche l''aide de cette commande');
  {$IFDEF LPC}
  WriteLn(' -a        Affiche toutes les informations du noyau');
  WriteLn(' -s        Affiche le nom du noyau (LINUX-0)');
  WriteLn(' -n        Affiche le nom de la machine');
  WriteLn(' -r        Affiche la version du noyau (KERNEL16UNIX)');
  WriteLn(' -v        Affiche la version');
  WriteLn(' -m        Affiche l''architecture de la machine');
  {$ENDIF}
  WriteLn(' -o        Affiche le systŠme d''exploitation');
  WriteLn(' -p        Affiche le microprocesseur');
  WriteLn(' --version Affiche la version de la commande');
 End
  Else
 If ParamCount>0Then Begin
  For I:=1 to ParamCount do Begin
   If(ParamStr(I)='-p')or(ParamStr(I)='--processor')Then Begin
    Case Test8086 of
     0:Write('8086 ');
     1:Write('80286 ');
     2:Write('80386 ');
     Else Write(Test8086,' ');
    End;
   End
    Else
   If(ParamStr(I)='-o')or(ParamStr(I)='--operating-system')Then Begin
    Write(OSVersion,' ');
   End
    Else
   If ParamStr(I)='--version'Then Write('Corail Version 1.0 ')
  {$IFDEF LPC}
    Else ShowUname(ParamStr(I))
  {$ENDIF}
   ;
  End;
  WriteLn;
 End
  Else
 {$IFDEF LPC}
 WriteLn(OSVersion)
 {$ELSE}
 WriteLn('Corail')
 {$ENDIF}
 ;
END.