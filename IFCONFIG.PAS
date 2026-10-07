{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @version: 1.00
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2
  @description: Commande ifconfig (configuration interface)
}

Program IFCONFIG;

{$IFDEF FPC}
 {$mode objfpc}
{$ELSE}
 Uses DOS;
{$ENDIF}

{$IFDEF FPC}
Type
 DWORD=LongWord;
 UINT=LongWord;
 ULONG=LongWord;
 BOOL=LongInt;

 { Structure pour les informations d'interface }
 TInterfaceInfo = Record
  Name:String;
  DisplayName:String;
  Description:String;
  IPAddress:String;
  NetMask:String;
  Broadcast:String;
  Gateway:String;
  MACAddress:String;
  MTU:DWORD;
  Speed:DWORD;
  Status:String;
  InterfaceType:String;
  DHCPEnabled:Boolean;
  PacketsReceived:DWORD;
  PacketsTransmitted:DWORD;
  BytesReceived:DWORD;
  BytesTransmitted:DWORD;
  ErrorsReceived:DWORD;
  ErrorsTransmitted:DWORD;
 End;

 { Structure IP_ADAPTER_INFO �tendue }
 IP_ADDR_STRING = Record
  Next:Pointer;
  IpAddress:Array[0..15] of AnsiChar;
  IpMask:Array[0..15] of AnsiChar;
  Context:DWORD;
 End;
 PIP_ADDR_STRING = ^IP_ADDR_STRING;

 IP_ADAPTER_INFO = Record
  Next:Pointer;
  ComboIndex:DWORD;
  AdapterName:Array[0..259] of AnsiChar;
  Description:Array[0..131] of AnsiChar;
  AddressLength:UINT;
  Address:Array[0..7] of Byte;
  Index:DWORD;
  AdapterType:UINT;
  DhcpEnabled:UINT;
  CurrentIpAddress:PIP_ADDR_STRING;
  IpAddressList:IP_ADDR_STRING;
  GatewayList:IP_ADDR_STRING;
  DhcpServer:IP_ADDR_STRING;
  HaveWins:BOOL;
  PrimaryWinsServer:IP_ADDR_STRING;
  SecondaryWinsServer:IP_ADDR_STRING;
  LeaseObtained:Int64;
  LeaseExpires:Int64;
 End;
 PIP_ADAPTER_INFO = ^IP_ADAPTER_INFO;

 { Structure MIB_IFROW pour les statistiques }
 MIB_IFROW = Record
  wszName:Array[0..255] of WideChar;
  dwIndex:DWORD;
  dwType:DWORD;
  dwMtu:DWORD;
  dwSpeed:DWORD;
  dwPhysAddrLen:DWORD;
  bPhysAddr:Array[0..7] of Byte;
  dwAdminStatus:DWORD;
  dwOperStatus:DWORD;
  dwLastChange:DWORD;
  dwInOctets:DWORD;
  dwInUcastPkts:DWORD;
  dwInNUcastPkts:DWORD;
  dwInDiscards:DWORD;
  dwInErrors:DWORD;
  dwInUnknownProtos:DWORD;
  dwOutOctets:DWORD;
  dwOutUcastPkts:DWORD;
  dwOutNUcastPkts:DWORD;
  dwOutDiscards:DWORD;
  dwOutErrors:DWORD;
  dwOutQLen:DWORD;
  dwDescrLen:DWORD;
  bDescr:Array[0..255] of Byte;
 End;
 PMIB_IFROW = ^MIB_IFROW;

Const
 { Constantes pour les types d'adaptateurs }
 MIB_IF_TYPE_OTHER = 1;
 MIB_IF_TYPE_ETHERNET_CSMACD = 6;
 MIB_IF_TYPE_ISO88025_TOKENRING = 9;
 MIB_IF_TYPE_FDDI = 15;
 MIB_IF_TYPE_PPP = 23;
 MIB_IF_TYPE_SOFTWARE_LOOPBACK = 24;
 MIB_IF_TYPE_ATM = 37;
 MIB_IF_TYPE_IEEE80211 = 71;

 { Constantes d'erreur }
 NO_ERROR = 0;
 ERROR_BUFFER_OVERFLOW = 111;
 ERROR_INSUFFICIENT_BUFFER = 122;

Var
 InterfaceList:Array[0..31] of TInterfaceInfo;
 InterfaceCount:Integer;

 { Fonctions externes }
Function GetAdaptersInfo(pAdapterInfo:PIP_ADAPTER_INFO;Var pOutBufLen:ULONG):DWORD;stdcall;external 'iphlpapi.dll';
Function GetIfEntry(pIfRow:PMIB_IFROW):DWORD;stdcall;external 'iphlpapi.dll';
{$ENDIF}

{$IFNDEF FPC}
Type
 TNetBIOSNCB=Record
  ncb_command:Byte;
  ncb_retcode:Byte;
  ncb_lsn:Byte;
  ncb_num:Byte;
  ncb_buffer:Pointer;
  ncb_length:Word;
  ncb_callname:Array[0..15] of Char;
  ncb_name:Array[0..15] of Char;
  ncb_rto:Byte;
  ncb_sto:Byte;
  ncb_post:Pointer;
  ncb_lana_num:Byte;
  ncb_cmd_cplt:Byte;
  ncb_reserve:Array[0..13] of Char;
 End;

 TAdapterStatus=Record
  adapter_address:Array[0..5] of Byte;
  rev_major:Byte;
  reserved0:Byte;
  adapter_type:Byte;
  rev_minor:Byte;
  duration:Word;
  frmr_recv:Word;
  frmr_xmit:Word;
  iframe_recv_err:Word;
  xmit_aborts:Word;
  xmit_success:LongInt;
  recv_success:LongInt;
  iframe_xmit_err:Word;
  recv_buff_unavail:Word;
  t1_timeouts:Word;
  ti_timeouts:Word;
  reserved1:LongInt;
  free_ncbs:Word;
  max_cfg_ncbs:Word;
  max_ncbs:Word;
  xmit_buf_unavail:Word;
  max_dgram_size:Word;
  pending_sess:Word;
  max_cfg_sess:Word;
  max_sess:Word;
  max_sess_pkt_size:Word;
  name_count:Word;
 End;

Var
 NCB:TNetBIOSNCB;
 AdapterInfo:TAdapterStatus;
{$ENDIF}

Function IntToStr(Value:LongInt):String;
Var
 S:String;
Begin
 Str(Value,S);
 IntToStr:=S;
End;

{$IFDEF FPC}
Function UIntToStr(Value:QWord):String;
Var
 S:String;
Begin
 S:='';
 Repeat
  S:=Chr(Ord('0')+(Value mod 10))+S;
  Value:=Value div 10;
 Until Value=0;
 UIntToStr:=S;
End;
{$ENDIF}

Function UpperCase(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 To Length(S) Do
  If S[I] in ['a'..'z'] Then S[I]:=Chr(Ord(S[I])-32);
 UpperCase:=S;
End;

Function LowerCase(S:String):String;
Var
 I:Integer;
Begin
 For I:=1 To Length(S) Do
  If S[I] in ['A'..'Z'] Then S[I]:=Chr(Ord(S[I])+32);
 LowerCase:=S;
End;

Function Pos(SubStr,S:String):Integer;
Var
 I,J:Integer;
 Found:Boolean;
Begin
 Pos:=0;
 For I:=1 To Length(S)-Length(SubStr)+1 Do Begin
  Found:=True;
  For J:=1 To Length(SubStr) Do
   If S[I+J-1]<>SubStr[J] Then Begin
    Found:=False;
    Break;
   End;
  If Found Then Begin
   Pos:=I;
   Break;
  End;
 End;
End;

 { Fonction pour convertir un nombre en hexadecimal }
Function IntToHex(Value:Integer;Digits:Integer):String;
Const
 HexChars:String='0123456789ABCDEF';
Var
 HexResult:String;
 I:Integer;
Begin
 HexResult:='';
 For I:=1 To Digits Do Begin
  HexResult:=HexChars[(Value and 15)+1]+HexResult;
  Value:=Value shr 4;
 End;
 IntToHex:=HexResult;
End;

{$IFDEF FPC}
 { Fonction pour convertir un type d'interface en nom }
Function GetInterfaceTypeName(InterfaceType:DWORD):String;Begin
 Case InterfaceType Of
  MIB_IF_TYPE_OTHER:GetInterfaceTypeName:='Other';
  MIB_IF_TYPE_ETHERNET_CSMACD:GetInterfaceTypeName:='Ethernet';
  MIB_IF_TYPE_ISO88025_TOKENRING:GetInterfaceTypeName:='Token Ring';
  MIB_IF_TYPE_FDDI:GetInterfaceTypeName:='FDDI';
  MIB_IF_TYPE_PPP:GetInterfaceTypeName:='PPP';
  MIB_IF_TYPE_SOFTWARE_LOOPBACK:GetInterfaceTypeName:='Loopback';
  MIB_IF_TYPE_ATM:GetInterfaceTypeName:='ATM';
  MIB_IF_TYPE_IEEE80211:GetInterfaceTypeName:='IEEE 802.11';
  Else GetInterfaceTypeName:='Unknown ('+UIntToStr(InterfaceType)+')';
 End;
End;

 { Fonction pour formater une adresse MAC }
Function FormatMAC(MACBytes:Array of Byte;Len:Integer):String;
Var
 I:Integer;
 MACResult:String;
Begin
 MACResult:='';
 For I:=0 To Len-1 Do Begin
  If I>0 Then MACResult:=MACResult+':';
  MACResult:=MACResult+LowerCase(IntToHex(MACBytes[I],2));
 End;
 FormatMAC:=MACResult;
End;

 { Fonction pour calculer l'adresse de diffusion }
Function CalculateBroadcast(IPAddr,NetMask:String):String;
Var
 IP,Mask:Array[0..3] of Byte;
 Broadcast:Array[0..3] of Byte;
 I,DotPos,Start:Integer;
 PartStr:String;
 PartIndex:Integer;
Begin
  { Analyser l'adresse IP }
 PartIndex:=0;
 Start:=1;
 For I:=1 To Length(IPAddr)+1 Do Begin
  If (I>Length(IPAddr)) or (IPAddr[I]='.') Then Begin
   PartStr:=Copy(IPAddr,Start,I-Start);
   If (PartIndex<4) and (PartStr<>'') Then Begin
    Val(PartStr,IP[PartIndex]);
    Inc(PartIndex);
   End;
   Start:=I+1;
  End;
 End;
  { Analyser le masque }
 PartIndex:=0;
 Start:=1;
 For I:=1 To Length(NetMask)+1 Do Begin
  If (I>Length(NetMask)) or (NetMask[I]='.') Then Begin
   PartStr:=Copy(NetMask,Start,I-Start);
   If (PartIndex<4) and (PartStr<>'') Then Begin
    Val(PartStr,Mask[PartIndex]);
    Inc(PartIndex);
   End;
   Start:=I+1;
  End;
 End;
  { Calculer la diffusion }
 For I:=0 To 3 Do Broadcast[I]:=IP[I] or (not Mask[I]);
 CalculateBroadcast:=IntToStr(Broadcast[0])+'.'+IntToStr(Broadcast[1])+'.'+
                    IntToStr(Broadcast[2])+'.'+IntToStr(Broadcast[3]);
End;

 { Fonction pour formater les octets en unites lisibles }
Function FormatBytes(Bytes:DWORD):String;Begin
 If Bytes<1024 Then FormatBytes:=UIntToStr(Bytes)+' O' Else
 If Bytes<1048576 Then FormatBytes:=UIntToStr(Bytes div 1024)+' Ko' Else
 If Bytes<1073741824 Then FormatBytes:=UIntToStr(Bytes div 1048576)+' Mo'
                     Else FormatBytes:=UIntToStr(Bytes div 1073741824)+' Go';
End;

 { Procedure pour obtenir les informations des interfaces }
Function GetInterfaceInfo:Boolean;
Var
 pAdapterInfo,pAdapter:PIP_ADAPTER_INFO;
 OutBufLen:ULONG;
 RetVal:DWORD;
 IfRow:MIB_IFROW;
 I:Integer;
Begin
 GetInterfaceInfo:=False;
 InterfaceCount:=0;
 OutBufLen:=0;
  { Premi�re appel pour obtenir la taille }
 RetVal:=GetAdaptersInfo(nil,OutBufLen);
 If RetVal<>ERROR_BUFFER_OVERFLOW Then Exit;
  { Allouer la m�moire }
 GetMem(pAdapterInfo,OutBufLen);
 Try
   { Obtenir les informations des adaptateurs }
  RetVal:=GetAdaptersInfo(pAdapterInfo,OutBufLen);
  If RetVal=NO_ERROR Then Begin
   pAdapter:=pAdapterInfo;
   While (pAdapter<>nil) and (InterfaceCount<32) Do Begin
    With InterfaceList[InterfaceCount] Do Begin
    Name:='eth'+UIntToStr(pAdapter^.Index);
     DisplayName:=StrPas(pAdapter^.AdapterName);
     Description:=StrPas(pAdapter^.Description);
     IPAddress:=StrPas(pAdapter^.IpAddressList.IpAddress);
     NetMask:=StrPas(pAdapter^.IpAddressList.IpMask);
     Gateway:=StrPas(pAdapter^.GatewayList.IpAddress);
     MACAddress:=FormatMAC(pAdapter^.Address,pAdapter^.AddressLength);
     DHCPEnabled:=(pAdapter^.DhcpEnabled<>0);
      { Calculer broadcast }
     If (IPAddress<>'0.0.0.0')and(NetMask<>'0.0.0.0')Then Broadcast:=CalculateBroadcast(IPAddress,NetMask)
                                                     Else Broadcast:='0.0.0.0';
      { Obtenir les statistiques via GetIfEntry }
     FillChar(IfRow,SizeOf(IfRow),0);
     IfRow.dwIndex:=pAdapter^.Index;
     If GetIfEntry(@IfRow)=NO_ERROR Then Begin
      MTU:=IfRow.dwMtu;
      Speed:=IfRow.dwSpeed;
      InterfaceType:=GetInterfaceTypeName(IfRow.dwType);
      PacketsReceived:=IfRow.dwInUcastPkts+IfRow.dwInNUcastPkts;
      PacketsTransmitted:=IfRow.dwOutUcastPkts+IfRow.dwOutNUcastPkts;
      BytesReceived:=IfRow.dwInOctets;
      BytesTransmitted:=IfRow.dwOutOctets;
      ErrorsReceived:=IfRow.dwInErrors;
      ErrorsTransmitted:=IfRow.dwOutErrors;
      If IfRow.dwOperStatus=1 Then Status:='UP'
                              Else Status:='DOWN';
     End
      Else
     Begin
      MTU:=1500;
      Speed:=0;
      InterfaceType:='Unknown';
      Status:='UNKNOWN';
     End;
    End;
    Inc(InterfaceCount);
    pAdapter:=PIP_ADAPTER_INFO(pAdapter^.Next);
   End;
   GetInterfaceInfo:=True;
  End;
 Finally
  FreeMem(pAdapterInfo);
 End;
End;

 { Proc�dure pour afficher une interface (style Linux) }
Procedure ShowInterface(Index:Integer;ShowAll:Boolean);
Var
 FlagsStr:String;
Begin
 With InterfaceList[Index] Do Begin
  { Ne pas afficher les interfaces DOWN sauf si demande }
  If (Not ShowAll) and (Status='DOWN') and (IPAddress='0.0.0.0') Then Exit;
   { Nom de l'interface et drapeaux }
  Write(Name);
  FlagsStr:='';
  If Status='UP' Then FlagsStr:=FlagsStr+'UP ';
  If IPAddress<>'0.0.0.0' Then FlagsStr:=FlagsStr+'RUNNING ';
  If Broadcast<>'0.0.0.0' Then FlagsStr:=FlagsStr+'BROADCAST ';
  If DHCPEnabled Then FlagsStr:=FlagsStr+'DHCP ';
  FlagsStr:=FlagsStr+'MULTICAST';
  WriteLn(': flags=<',FlagsStr,'> mtu ',MTU);
   { Type d'interface }
  WriteLn('        ',InterfaceType);
   { Configuration IP }
  If IPAddress<>'0.0.0.0' Then Begin
   Write('        inet ',IPAddress);
   If NetMask<>'0.0.0.0' Then Write('  masque r'+#130+'seau ',NetMask);
   If Broadcast<>'0.0.0.0' Then Write('  diffusion ',Broadcast);
   WriteLn;
  End;
   { Adresse MAC }
  If (MACAddress<>'')and(MACAddress<>'00:00:00:00:00:00')Then WriteLn('        ether ',MACAddress);
   { Statistiques }
  WriteLn('        RX paquets ',PacketsReceived,'  octets ',BytesReceived,' (',FormatBytes(BytesReceived),')');
  WriteLn('        RX erreurs ',ErrorsReceived,'  paquet perdue 0  ex'+#130+'cuter 0  trame 0');
  WriteLn('        TX paquets ',PacketsTransmitted,'  bytes ',BytesTransmitted,
          ' (',FormatBytes(BytesTransmitted),')');
  WriteLn('        TX erreurs ',ErrorsTransmitted,'  paquet perdue 0  ex'+#130+'cuter 0  op'+#130+'rateur 0');
  WriteLn('        collisions 0');
  WriteLn;
 End;
End;

 { Proc�dure pour afficher toutes les interfaces }
Procedure ShowAllInterfaces(ShowAll:Boolean);
Var
 I:Integer;
Begin
 If GetInterfaceInfo Then Begin
  For I:=0 To InterfaceCount-1 Do
   ShowInterface(I,ShowAll);
 End Else
  WriteLn('Erreur lors de la r'+#130+'cup'+#130+'ration des informations d''interface');
End;

 { Proc�dure pour afficher une interface sp�cifique }
Procedure ShowSpecificInterface(InterfaceName:String);
Var
 I:Integer;
 Found:Boolean;
Begin
 Found:=False;
 If GetInterfaceInfo Then Begin
  For I:=0 To InterfaceCount-1 Do Begin
   If (InterfaceList[I].Name=InterfaceName) or
      (Pos(UpperCase(InterfaceName),UpperCase(InterfaceList[I].Description))>0) Then Begin
    ShowInterface(I,True);
    Found:=True;
   End;
  End;
  If Not Found Then
   WriteLn(InterfaceName,': erreur lors de la r'+#130+'cup'+#130+'ration des drapeaux de ',
           'l''interface: P'+#130+'riph'+#130+'rique non trouv'+#130);
 End;
End;

{ Procedure pour afficher un resume des interfaces }
Procedure ShowBriefInterfaces;
Var
 I:Integer;
Begin
 WriteLn('Nom    Etat   Adresse IP       Masque r'+#130+'seau    Adresse MAC');
 WriteLn('------ ------ ---------------- ---------------- -----------------');
 If GetInterfaceInfo Then Begin
  For I:=0 To InterfaceCount-1 Do Begin
   With InterfaceList[I] Do Begin
    Write(Name);
    While Length(Name)<7 Do Begin
     Write(' ');
     Name:=Name+' ';
    End;
    Write(Status);
    While Length(Status)<7 Do Begin
     Write(' ');
     Status:=Status+' ';
    End;
    Write(IPAddress);
    While Length(IPAddress)<17 Do Begin
     Write(' ');
     IPAddress:=IPAddress+' ';
    End;
    Write(NetMask);
    While Length(NetMask)<17 Do Begin
     Write(' ');
     NetMask:=NetMask+' ';
    End;
    WriteLn(MACAddress);
   End;
  End;
 End;
End;
{$ENDIF}

{$IFNDEF FPC}
Function DetectWATTCP(Var IPAddress:LongInt):Boolean;
Var
 IPDetected:Boolean;
 DetectedAddress:LongInt;
Begin
 IPDetected:=False;
 DetectedAddress:=0;
 ASM
  MOV AX, 6100h
  INT 2Fh
  CMP AL, 0
  JNE @no_wattcp
  MOV AX, 6101h
  INT 2Fh
  JC @no_wattcp
  MOV WORD PTR DetectedAddress, AX
  MOV WORD PTR DetectedAddress+2, DX
  MOV IPDetected, 1
@no_wattcp:
 END;
 IPAddress:=DetectedAddress;
 DetectWATTCP:=IPDetected;
End;

Function IPToString(IP:LongInt):String;Begin
 IPToString:=IntToStr(IP and $FF)+'.'+
             IntToStr((IP shr 8) and $FF)+'.'+
             IntToStr((IP shr 16) and $FF)+'.'+
             IntToStr((IP shr 24) and $FF);
End;

Function IsNetBIOSInstalled:Boolean;
Var
 NetBIOSPresent:Boolean;
Begin
 NetBIOSPresent:=False;
 ASM
  PUSH ES
  MOV AX, 0
  MOV ES, AX
  MOV BX, 5Ch * 4
  MOV AX, ES:[BX]
  MOV DX, ES:[BX+2]
  OR AX, DX
  JZ @no_netbios
  MOV NetBIOSPresent, 1
@no_netbios:
  POP ES
 END;
 IsNetBIOSInstalled:=NetBIOSPresent;
End;

Procedure CallNetBIOS(Var NCB:TNetBIOSNCB);
Begin
 If Not IsNetBIOSInstalled Then Begin
  NCB.ncb_retcode:=$FF;
  Exit;
 End;
 ASM
  PUSH DS
  LES BX, NCB
  MOV AX, DS
  MOV ES, AX
  INT 5Ch
  POP DS
 END;
End;

Function GetDosAdapterStatus:Boolean;
Begin
 FillChar(NCB,SizeOf(NCB),0);
 FillChar(AdapterInfo,SizeOf(AdapterInfo),0);
 NCB.ncb_command:=$33;
 NCB.ncb_lana_num:=0;
 NCB.ncb_buffer:=@AdapterInfo;
 NCB.ncb_length:=SizeOf(AdapterInfo);
 NCB.ncb_callname[0]:='*';
 CallNetBIOS(NCB);
 GetDosAdapterStatus:=(NCB.ncb_retcode=0);
End;

Function FormatDosMAC:String;
Begin
 FormatDosMAC:=IntToHex(AdapterInfo.adapter_address[0],2)+':'+
               IntToHex(AdapterInfo.adapter_address[1],2)+':'+
               IntToHex(AdapterInfo.adapter_address[2],2)+':'+
               IntToHex(AdapterInfo.adapter_address[3],2)+':'+
               IntToHex(AdapterInfo.adapter_address[4],2)+':'+
               IntToHex(AdapterInfo.adapter_address[5],2);
End;

Procedure ShowDosInterface;
Var
 IPAddress:LongInt;
 HasWATTCP,HasNetBIOS:Boolean;
Begin
 HasWATTCP:=DetectWATTCP(IPAddress);
 HasNetBIOS:=GetDosAdapterStatus;
 If Not HasWATTCP and Not HasNetBIOS Then Begin
  WriteLn('Aucune information r'+#130+'seau disponible via WATTCP/DOS ou NetBIOS.');
  Exit;
 End;
 WriteLn('lan0: flags=<UP>');
 If HasWATTCP Then
  WriteLn('        inet ',IPToString(IPAddress))
 Else
  WriteLn('        Adresse IPv4 indisponible (WATTCP/DOS non disponible).');
 If HasNetBIOS Then Begin
  WriteLn('        Type adaptateur ',AdapterInfo.adapter_type);
  WriteLn('        ether ',FormatDosMAC);
  WriteLn('        RX paquets ',AdapterInfo.recv_success);
  WriteLn('        TX paquets ',AdapterInfo.xmit_success);
 End
 Else
  WriteLn('        MAC et compteurs indisponibles (NetBIOS non disponible).');
End;

Procedure ShowDosBrief;
Var
 IPAddress:LongInt;
 HasWATTCP,HasNetBIOS:Boolean;
Begin
 WriteLn('Interface Etat   IPv4            Adresse MAC');
 WriteLn('--------- ------ --------------- -----------------');
 HasWATTCP:=DetectWATTCP(IPAddress);
 HasNetBIOS:=GetDosAdapterStatus;
 If Not HasWATTCP and Not HasNetBIOS Then Begin
  WriteLn('Aucune information r'+#130+'seau disponible.');
  Exit;
 End;
 Write('lan0      UP     ');
 If HasWATTCP Then Write(IPToString(IPAddress)) Else Write('n/d');
 Write('  ');
 If HasNetBIOS Then WriteLn(FormatDosMAC) Else WriteLn('n/d');
End;

Procedure ShowDosSpecificInterface(InterfaceName:String);
Begin
 If (UpperCase(InterfaceName)='LAN0') or (UpperCase(InterfaceName)='ETH0') Then
  ShowDosInterface
 Else
  WriteLn(InterfaceName,': interface non trouvee.');
End;
{$ENDIF}

 { Procedure pour analyser les parametres }
Procedure ParseCommand;
Var
 Cmd:String;
Begin
 If ParamCount<1 Then Begin
  {$IFDEF FPC}
   ShowAllInterfaces(False);
  {$ELSE}
    ShowDosInterface;
  {$ENDIF}
  Exit;
 End;
 Cmd:=UpperCase(ParamStr(1));
 If (Cmd='-A') or (Cmd='--ALL') Then Begin
  {$IFDEF FPC}
  ShowAllInterfaces(True);
  {$ELSE}
  ShowDosInterface;
  {$ENDIF}
 End
  Else
 If (Cmd='-S') or (Cmd='--SHORT') Then Begin
  {$IFDEF FPC}
  ShowBriefInterfaces;
  {$ELSE}
  ShowDosBrief;
  {$ENDIF}
 End
  Else
 If (Cmd[1]<>'-') and (Cmd[1]<>'/') Then Begin
  { Interface specifique }
  {$IFDEF FPC}
   ShowSpecificInterface(ParamStr(1));
  {$ELSE}
    ShowDosSpecificInterface(ParamStr(1));
  {$ENDIF}
 End
  Else
 Begin
  WriteLn('Option inconnue : ',Cmd);
  WriteLn('Options disponibles : -a, -s, interface');
 End;
End;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('IFCONFIG : Cette commande permet d''effectuer la configuration et l''affichage des interfaces r'+#130+'seau');
  WriteLn;
  WriteLn('Syntaxe :');
  WriteLn('  IFCONFIG                    Afficher les interfaces actives');
  WriteLn('  IFCONFIG -a                 Afficher toutes les interfaces');
  WriteLn('  IFCONFIG -s                 Affichage r'+#130+'sum'+#130);
  WriteLn('  IFCONFIG interface          Afficher une interface sp'+#130+'cifique');
  WriteLn;
  WriteLn('Param'+#138+'tres :');
  WriteLn('  interface   Nom de l''interface (exemple: eth0, eth1)');
  WriteLn;
  WriteLn('Exemples :');
  WriteLn('  IFCONFIG                    # Afficher interfaces actives');
  WriteLn('  IFCONFIG -a                 # Toutes les interfaces');
  WriteLn('  IFCONFIG -s                 # R'+#130+'sum'+#130+' tabulaire');
  WriteLn('  IFCONFIG eth0               # Interface sp'+#130+'cifique');
  WriteLn;
  WriteLn('Turbo Pascal: IPv4 via WATTCP/DOS; MAC et stats via NetBIOS si disponible.');
  WriteLn('Free Pascal: informations detaillees sous Windows.');
 End
  Else
 If ParamStr(1)='--version'Then Begin
  WriteLn('IFCONFIG 1.00 - Configuration interface r'+#130+'seau, NETWORKKIT-P, LINUX-0, corail');
  WriteLn('Licence MIT');
  WriteLn;
  WriteLn(#144,'crit par Sylvain Maltais');
 End
  Else
 Begin
  ParseCommand;
 End;
END.
