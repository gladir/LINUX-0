{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit MC146818;

INTERFACE

Const
 RTC_ALWAYS_BCD=1;  { RTC fonctionne en mode binaire }
 RTC_DEC_YEAR=$3F;  { Oó nous stockons l'annÇe rÇelle sur les machines DEC. }

 RTC_SECONDS=0;
 RTC_SECONDS_ALARM=1;
 RTC_MINUTES=2;
 RTC_MINUTES_ALARM=3;
 RTC_HOURS=4;
 RTC_HOURS_ALARM=5;

  { RTC_*_ALARM est toujours vrai si les 2 bits de poids fort sont dÇfinis }
 RTC_ALARM_DONT_CARE=$C0;

 RTC_DAY_OF_WEEK=6;
 RTC_DAY_OF_MONTH=7;
 RTC_MONTH=8;
 RTC_YEAR=9;

  { Registres de contrìle - Noms Motorola }
 RTC_REG_A=10;
 RTC_REG_B=11;
 RTC_REG_C=12;
 RTC_REG_D=13;

  { SÇlection de frÇquence }
 RTC_FREQ_SELECT=RTC_REG_A;

  { Mise Ö jour en cours - dÇfini Ö "1" 244 microsecondes avant que le RTC ne soit dÇsactivÇ du bus,
    rÇinitialisÇ apräs la mise Ö jour (peut prendre 1,984 ms @ 32768Hz RefClock),
    totalisant un intervalle maximum Ö l'Çtat haut de 2,228 ms. }
 RTC_UIP=$80;
 RTC_DIV_CTL=$70;

  { Contrìle du diviseur : valeurs d'horloge de rÇfÇrence 4,194 / 1,049 MHz / 32,768 kHz }
 RTC_REF_CLCK_4MHZ=$00;
 RTC_REF_CLCK_1MHZ=$10;
 RTC_REF_CLCK_32KHZ=$20;

  { 2 valeurs pour la rÇinitialisation de l'Çtage diviseur, autres pour "test uniquement" }
 RTC_DIV_RESET1=$60;
 RTC_DIV_RESET2=$70;

  { Dans AMD BKDG, les bits 5 et 6 sont rÇservÇs, le bit 4 est pour la sÇlection du banc dv0 }
 RTC_AMD_BANK_SELECT=$10;

  { Interruption pÇriodique / SÇlection de la frÇquence d'onde carrÇe. 0=aucune, 1=32.8kHz,... 15=2Hz }
 RTC_RATE_SELECT=$0F;

  { Contrìle RTC }
 RTC_CONTROL=RTC_REG_B;
 RTC_SET=$80;        { DÇsactive les mises Ö jour pour le rÇglage de l'horloge }
 RTC_PIE=$40;        { Activation de l'interruption pÇriodique }
 RTC_AIE=$20;        { Activation de l'interruption d'alarme }
 RTC_UIE=$10;        { Activation de l'interruption de fin de mise Ö jour }
 RTC_SQWE=$08;       { Activation de la sortie onde carrÇe }
 RTC_DM_BINARY=$04;  { Toutes les valeurs de temps/date sont en BCD si dÇsactivÇ }
 RTC_24H=$02;        { Mode 24 heures - sinon le bit 7 des heures indique PM }
 RTC_DST_EN=$01;     { Commutation automatique DST - fonctionne uniquement pour les êtats-Unis }

  { Indicateurs d'interruption RTC }
 RTC_INTR_FLAGS=RTC_REG_C;
  { Attention - rÇinitialisÇ Ö la lecture }
 RTC_IRQF=$80;       { L'un des 3 suivants est actif }
 RTC_PF=$40;
 RTC_AF=$20;
 RTC_UF=$10;

  { RTC valide }
 RTC_VALID=RTC_REG_D;
 RTC_VRT=$80;        { RAM et heure valides }

  { DÇfinition par dÇfaut de l'Çtendue d'entrÇe/sortie RTC }
 RTC_IO_EXTENT=$8;
 RTC_IO_EXTENT_USED=$2;
 RTC_IOMAPPED=1;  { Par dÇfaut en mode cartographiÇ d'entrÇe/sortie }

 UIP_RECHECK_DELAY = 100;  { microsecondes }
 UIP_RECHECK_DELAY_MS = 1000 div UIP_RECHECK_DELAY;  { conversion en millisecondes }

Type
 TDevice=Pointer;

 TCmosRtcBoardInfo=Record
  WakeOn:Procedure(Dev:TDevice);
  WakeOff:Procedure(Dev:TDevice);
  Flags:LongInt;
  AddressSpace:Integer;
  RtcDayAlarm:Byte;   { zÇro ou index de registre }
  RtcMonAlarm:Byte;   { zÇro ou index de registre }
  RtcCentury:Byte;    { zÇro ou index de registre }
 End;

Const
 CMOS_RTC_FLAGS_NOFREQ=1 shl 0;

Type
 Rtc_Time=Record
  Tm_Sec:Integer;    { Secondes }
  Tm_Min:Integer;    { Minutes }
  Tm_Hour:Integer;   { Heures }
  Tm_Mday:Integer;   { Jour du mois }
  Tm_Mon:Integer;    { Mois }
  Tm_Year:Integer;   { AnnÇe }
  Tm_Wday:Integer;   { Jour de la semaine }
  Tm_Yday:Integer;   { Jour de l'annÇe }
  Tm_IsDst:Integer;  { Heure d'ÇtÇ }
 End;

 Tmc146818_get_time_callback_param=Record
  time:^Rtc_Time;
  real_year:Byte;
  century:Byte;
  ctrl:Byte;
 End;

 TCallback=Procedure(Seconds:Byte;Param_in:Pointer);

Function Mc146818_Does_Rtc_Work:Boolean;
Function Mc146818_Get_Time(Var Time:Rtc_Time;Timeout:Integer):Integer;
Function Mc146818_Set_Time(Var Time:Rtc_Time):Integer;
Function Mc146818_Avoid_UIP(Callback:TCallback;Timeout:Integer;Param:Pointer):Boolean;

IMPLEMENTATION

Uses Crt,Errno;

Var
 rtc_lock:Byte;

Procedure Disable;Begin
 {$IFNDEF FPC}
  Inline($FA); { CLI - Clear Interrupt Flag }
 {$ENDIF}
End;

Procedure Enable;Begin
 {$IFNDEF FPC}
  Inline($FB);  { Le code machine pour l'instruction 'sti' }
 {$ENDIF}
End;

Function bcd2bin(bcd: Byte):Byte;Begin
 bcd2bin:=((bcd shr 4)*10)+(bcd and $0F);
End;

Function bin2bcd(value:byte):byte;Begin
 bin2bcd:=(value div 10) * $10+(value mod 10);
End;

Procedure spin_lock_irqsave(Var lock:Byte;Var Flags:Byte);Begin
 { ImplÇmentation fictive de verrouillage d'interruptions }
End;

Procedure spin_unlock_irqrestore(Var lock:Byte;Var Flags:Byte);Begin
 { ImplÇmentation fictive de dÇverrouillage d'interruptions }
End;

Function IsLeapYear(Y:Word):Boolean;Begin
 IsLeapYear:=(Y mod 4=0)and((Y mod 100<>0)or(Y mod 400=0));
End;

Function CMOS_READ(Reg:Byte):Byte;Begin
 {$IFDEF FPC}
  CMOS_READ:=0;
 {$ELSE}
  Port[$70]:=Reg;        { SÇlectionne le registre du CMOS }
  CMOS_READ:=Port[$71];  { Lit la valeur du registre sÇlectionnÇ }
 {$ENDIF}
End;

Procedure CMOS_WRITE(data:byte;addr:byte);Begin
 {$IFNDEF FPC}
  Port[$70]:=addr;
  Port[$71]:=data;
 {$ENDIF}
End;

Function UIP_RECHECK_LOOPS_MS(x:Integer):Integer;Begin
 UIP_RECHECK_LOOPS_MS:=x div UIP_RECHECK_DELAY_MS;
End;

Function Mc146818_Does_Rtc_Work:Boolean;Begin
 Mc146818_Does_Rtc_Work:=Mc146818_Avoid_UIP(nil,1000,nil);
End;

Procedure mc146818_get_time_callback(seconds:Byte;Param_in:Pointer);Far;
Var
 P:^Tmc146818_get_time_callback_param;
Begin
 p:=param_in;
 p^.time^.tm_sec:=seconds;
 p^.time^.tm_min:=CMOS_READ(RTC_MINUTES);
 p^.time^.tm_hour:=CMOS_READ(RTC_HOURS);
 p^.time^.tm_mday:=CMOS_READ(RTC_DAY_OF_MONTH);
 p^.time^.tm_mon:=CMOS_READ(RTC_MONTH);
 p^.time^.tm_year:=CMOS_READ(RTC_YEAR);
 {$IFDEF CONFIG_MACH_DECSTATION}
 p^.real_year:=CMOS_READ(RTC_DEC_YEAR);
 {$ENDIF}
 {$IFDEF CONFIG_ACPI}
 If acpi_gbl_FADT.header.revision>=FADT2_REVISION_ID and(acpi_gbl_FADT.century<>0)Then Begin
  p^.century:=CMOS_READ(acpi_gbl_FADT.century);
 End
  Else
 Begin
  p^.century:=0;
 End;
 {$ENDIF}
 p^.ctrl:=CMOS_READ(RTC_CONTROL);
End;

Function Mc146818_Get_Time(Var Time:Rtc_Time;Timeout:Integer):Integer;
Var
 p:Tmc146818_get_time_callback_param;
 CallBack:TCallback;
 PCallBack:Pointer Absolute CallBack;
Begin
 p.time:=@time;
 PCallBack:=@mc146818_get_time_callback;
 If Not Mc146818_avoid_UIP(CallBack,timeout,@p)Then Begin
  FillChar(time,SizeOf(Rtc_Time),0);
  Mc146818_Get_Time:= -ETIMEDOUT; { Remplacer par un code d'erreur appropriÇ }
  Exit;
 End;
 If(p.ctrl and RTC_DM_BINARY = 0) or(RTC_ALWAYS_BCD<>0)Then Begin
  time.tm_sec:=bcd2bin(time.tm_sec);
  time.tm_min:=bcd2bin(time.tm_min);
  time.tm_hour:=bcd2bin(time.tm_hour);
  time.tm_mday:=bcd2bin(time.tm_mday);
  time.tm_mon:=bcd2bin(time.tm_mon);
  time.tm_year:=bcd2bin(time.tm_year);
  {$IFDEF CONFIG_ACPI}
   p.century := bcd2bin(p.century);
  {$ENDIF}
 End;
 {$IFDEF CONFIG_MACH_DECSTATION}
 Time.tm_year:=Time.tm_year+p.real_year-72;
 {$ENDIF}
 {$IFDEF CONFIG_ACPI}
  If p.century>19 Then Time.tm_year:=Time.tm_year+(p.century-19)*100;
 {$ENDIF}
 If time.tm_year<=69 Then Time.tm_year:=Time.tm_year+100;
 Time.tm_mon := time.tm_mon - 1;
 Mc146818_Get_Time := 0;
End;

Function Mc146818_Set_Time(Var Time:Rtc_Time):Integer;
Var
 flags:Byte;
 mon,day,hrs,min,sec:Byte;
 save_control,save_freq_select:Byte;
 yrs:Word;
 century:Byte;
 real_yrs:Word;
Begin
 yrs:=time.tm_year;
 mon:=time.tm_mon+1;  { tm_mon commence Ö zÇro }
 day:=time.tm_mday;
 hrs:=time.tm_hour;
 min:=time.tm_min;
 sec:=time.tm_sec;
 If yrs>255 then Begin
  Mc146818_Set_Time:=-1; { -EINVAL }
  Exit;
 End;
 { Gestion de l'annÇe rÇelle pour DECSTATION }
 real_yrs:=yrs;
 yrs:=72;
 If(Not IsLeapYear(real_yrs+1900))and(Mon<3)Then Begin
  real_yrs:=real_yrs-1;
  yrs:=73;
 End;
 { Gestion de l'annÇe et du siäcle avec ACPI }
 century := 0;
 {$IFDEF CONFIG_ACPI}
  If(acpi_gbl_FADT.header.revision>=FADT2_REVISION_ID)and(acpi_gbl_FADT.century <> 0)Then Begin
   century:=(yrs+1900) div 100;
   yrs:=yrs mod 100;
  End;
 {$ENDIF}
 If yrs>169 Then Begin
  Mc146818_Set_Time:=-1; { -EINVAL }
  Exit;
 End;
 If yrs>=100 Then yrs:=yrs-100;
 spin_lock_irqsave(rtc_lock, flags);
 save_control := CMOS_READ(RTC_CONTROL);
 spin_unlock_irqrestore(rtc_lock, flags);
 If(save_control and RTC_DM_BINARY=0)or(RTC_ALWAYS_BCD=1)Then Begin
  Sec:=bin2bcd(sec);
  Min:=bin2bcd(min);
  Hrs:=bin2bcd(hrs);
  Day:=bin2bcd(day);
  Mon:=bin2bcd(mon);
  Yrs:=bin2bcd(yrs);
  Century:=bin2bcd(century);
 End;
 spin_lock_irqsave(rtc_lock, flags);
 save_control := CMOS_READ(RTC_CONTROL);
 CMOS_WRITE(save_control or RTC_SET, RTC_CONTROL);
 save_freq_select := CMOS_READ(RTC_FREQ_SELECT);
 CMOS_WRITE(save_freq_select or RTC_DIV_RESET2, RTC_FREQ_SELECT);
 { Ecrire les valeurs dans les registres du RTC }
 {$IFDEF CONFIG_MACH_DECSTATION}
  CMOS_WRITE(real_yrs,RTC_DEC_YEAR);
 {$ENDIF}
 CMOS_WRITE(yrs, RTC_YEAR);
 CMOS_WRITE(mon, RTC_MONTH);
 CMOS_WRITE(day, RTC_DAY_OF_MONTH);
 CMOS_WRITE(hrs, RTC_HOURS);
 CMOS_WRITE(min, RTC_MINUTES);
 CMOS_WRITE(sec, RTC_SECONDS);
 {$IFDEF CONFIG_ACPI}
  If(acpi_gbl_FADT.header.revision >= FADT2_REVISION_ID)and(acpi_gbl_FADT.century<>0)Then Begin
   CMOS_WRITE(century,acpi_gbl_FADT.century);
  End;
 {$ENDIF}
 CMOS_WRITE(save_control, RTC_CONTROL);
 CMOS_WRITE(save_freq_select, RTC_FREQ_SELECT);
 spin_unlock_irqrestore(rtc_lock, flags);
 Mc146818_Set_Time:= 0;
End;

Function Mc146818_Avoid_UIP(Callback:TCallback;Timeout:Integer;Param:Pointer):Boolean;
Var
 i:Integer;
 seconds:Byte;
Begin
 For i:=0 to UIP_RECHECK_LOOPS_MS(i)do Begin
  If UIP_RECHECK_LOOPS_MS(i)>=Timeout Then Break;
   { Verrouillage des interruptions }
  Disable;
   { Lire la valeur des secondes avant de vÇrifier UIP }
  Seconds:=CMOS_READ(RTC_SECONDS);
   { VÇrifier si une mise Ö jour est en cours }
  If(CMOS_READ(RTC_FREQ_SELECT) and RTC_UIP)<>0 Then Begin
   Enable;
   Delay(UIP_RECHECK_DELAY div 1000); { Conversion usec -> ms }
   Continue;
  End;
   { Revalidation de la lecture }
  If seconds<>CMOS_READ(RTC_SECONDS)Then Begin
   Enable;
   Continue;
  End;
   { Appeler la fonction de rappel si dÇfinie }
  If Assigned(callback)Then callback(Seconds,Param);
   { VÇrifier Ö nouveau l'indicateur UIP }
  If (CMOS_READ(RTC_FREQ_SELECT) and RTC_UIP)<>0 Then Begin
   Enable;
   Delay(UIP_RECHECK_DELAY div 1000);
   Continue;
  End;
   { VÇrifier si le NMI a affectÇ la lecture }
  If Seconds<>CMOS_READ(RTC_SECONDS)Then Begin
   Enable;
   Continue;
  End;
   { DÇverrouiller les interruptions }
  Enable;
    { Avertissement si la lecture prend trop de temps }
  If UIP_RECHECK_LOOPS_MS(i) >= 100 Then Begin
   WriteLn('La lecture de l''heure actuelle Ö partir ',
           'du RTC a pris environ', UIP_RECHECK_LOOPS_MS(i), ' ms');
  End;
  Mc146818_Avoid_UIP:=True;
  Exit;
 End;
 Mc146818_Avoid_UIP:=False;
End;

END.