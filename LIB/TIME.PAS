{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit TIME;

{$N+}

INTERFACE

Type
 {$IFDEF FPC}
  clock_t=QWord;
 {$ELSE}
  clock_t=LongInt;
 {$ENDIF}

 time_t=LongInt;
 PTimeT=^time_t;

 TM=Record
  tm_year:Integer;
  tm_mon:Integer;
  tm_mday:Integer;
  tm_hour:Integer;
  tm_min:Integer;
  tm_sec:Integer;
 End;
 PTM=^TM;

 TTM=Record
  tm_sec:Integer;   { Secondes (0 … 59) }
  tm_min:Integer;   { Minutes (0 … 59) }
  tm_hour:Integer;  { Heures (0 … 23) }
  tm_mday:Integer;  { Jour du mois (1 … 31) }
  tm_mon:Integer;   { Mois (0 … 11) }
  tm_year:Integer;  { Ann‚es (depuis 1900) }
  tm_wday:Integer;  { Jour de la semaine (0 … 6) }
  tm_yday:Integer;  { Jour de l'ann‚e (0 … 365) }
  tm_isdst:Integer; { Indicateur d'heure d'‚t‚ }
 End;

 TZNameArray = Array[0..1] of String[10];

Var
 tzname:TZNameArray;
 timezone:Integer;
 daylight:Boolean;

Function  AscTime(Const TimePtr:TTM):String;
Function  AscTime_r(Const TimePtr:TTM;Var Buf:String):String;
Function  Clock:Clock_t;
Function  CTime(Var timep:PTimeT):PChar;
Function  DiffTime(Time1,Time0:Comp):Comp;
Function  GMTime(TimeP:LongInt):PTM;
Function  MkTime(Var TimePtr:TM):LongInt;
Function  Time_(ptrheure:PTimeT):time_t;
Procedure tzset;

IMPLEMENTATION

Uses DOS,Strings;

Const
 Days:Array[0..6] of String=('Dim','Lun', 'Mar','Mer','Jeu','Ven','Sam');
 Months:Array[0..11] of String=('Jan', 'F‚v', 'Mar', 'Avr', 'Mai', 'Jui',
                                'Jul', 'Ao–', 'Sep', 'Oct', 'Nov', 'D‚c');

Function AscTime(Const TimePtr:TTM):String;
Var
 Day,Hour,Min,Year,Sec:String;
Begin
  { Format manuellement la chaŒne }
 Str(timeptr.tm_mday, day);
 Str(timeptr.tm_hour, hour);
 Str(timeptr.tm_min, min);
 Str(timeptr.tm_sec, sec);
 Str(timeptr.tm_year + 1900,Year);
 AscTime:= Days[timeptr.tm_wday] + ' ' +
           Months[timeptr.tm_mon] + ' ' +
           day + ' ' +
           Hour + ':' +
           Min + ':' +
           Sec + ' ' +
           Year;
End;

Function AscTime_r(Const TimePtr:TTM;Var Buf:String):String;
Var
 Day,Hour,Min,Sec,Year:String;
Begin
 Str(timeptr.tm_mday, Day);
 Str(timeptr.tm_hour, Hour);
 Str(timeptr.tm_min, Min);
 Str(timeptr.tm_sec, Sec);
 Str(timeptr.tm_year + 1900,Year);
 Buf:=Days[timeptr.tm_wday] + ' ' +
      Months[timeptr.tm_mon] + ' ' +
      Day + ' ' +
      Hour + ':' +
      Min + ':' +
      Sec + ' ' +
      Year;
 Asctime_r:=Buf;
End;

Function Clock:Clock_t;Begin
 {$IFDEF FPC}
  Clock:=GetMsCount; { Obtenir le temps ‚coul‚ en millisecondes depuis le d‚marrage }
  {$ELSE}
  clock:=MemL[$0040:$006C]; { Retourne la valeur du compteur d'horloge }
 {$ENDIF}
End;

Function CTime(Var timep:PTimeT):PChar;
Var
 Year,Month,Day,Hour,Min,Sec:Word;
 WDay:Word;
 TimeStr,StrYear:String;
 StaticBuf:Array[0..25] of Char; { Tampon statique pour entreposer la chaŒne }
Begin
 If timep=Nil Then Begin
  CTime:=Nil;
  Exit;
 End;
  { R‚cup‚ration de l'heure actuelle depuis le BIOS }
 GetTime(Hour,Min,Sec,WDay);
 GetDate(Year,Month,Day,WDay);
  { Formater la chaŒne en style "C" (exemple: Lun Jan 01 12:34:56 2025\n") }
 Str(Year,StrYear);
 TimeStr:=Days[WDay] + ' ' +
          Months[Month-1] + ' ' +
          Chr(Day div 10 + Ord('0')) + Chr(Day mod 10 + Ord('0')) + ' ' +
          Chr(Hour div 10 + Ord('0')) + Chr(Hour mod 10 + Ord('0')) + ':' +
          Chr(Min div 10 + Ord('0')) + Chr(Min mod 10 + Ord('0')) + ':' +
          Chr(Sec div 10 + Ord('0')) + Chr(Sec mod 10 + Ord('0')) + ' ' +
          StrYear+#0; { Ajout du caractŠre de fin de chaŒne de caractŠres C }

  { Copier dans le tampon statique }
 StrPCopy(@StaticBuf,TimeStr);
 CTime:=StrNew(StaticBuf);
End;

Function DiffTime(Time1,Time0:Comp):Comp;Begin
 DiffTime:=Time0-Time1;
End;

Function GMTime(TimeP:LongInt):PTM;
Var
 D:DateTime;
 P:PTM;
Begin
 UnpackTime(TimeP,D);
 GetMem(P,SizeOf(TM));
 P^.tm_year:=D.Year;
 P^.tm_mon:=D.Month;
 P^.tm_mday:=0;
 P^.tm_hour:=D.Hour;
 P^.tm_min:=D.Min;
 P^.tm_sec:=D.Sec;
 GMTime:=P;
End;

Function MkTime(Var TimePtr:TM):LongInt;
Var
 P:LongInt;
 D:DateTime;
Begin
 D.Year:=TimePtr.tm_year;
 D.Month:=TimePtr.tm_mon;
 D.Day:=TimePtr.tm_mday;
 D.Hour:=TimePtr.tm_hour;
 D.Min:=TimePtr.tm_min;
 D.Sec:=TimePtr.tm_sec;
 PackTime(D,P);
 MkTime:=P;
End;

Function Time_(ptrheure:PTimeT):time_t;
Const
 DaysPerMonth:Array[1..12] of Integer=(31,28,31,30,31,30,31,31,30,31,30,31);
Var
 Year,Month,Day,WDay:Word;
 Hour,Min,Sec,Sec100:Word;
 DaysSince1970,LeapYears,TotalDays:LongInt;
 Timestamp:time_t;

   { Fonction pour savoir si une ann‚e est bissextile }
  Function IsLeapYear(Y:Word):Boolean;Begin
   IsLeapYear:=(Y mod 4=0)and((Y mod 100<>0)or(Y mod 400=0));
  End;

   { Calcul du nombre de jours ‚coul‚s depuis 1970 }
  Function DaysSinceEpoch(Y, M, D: Word): LongInt;
  Var
   i:Integer;
   R:LongInt;
  Begin
   R:=0;
    { Ajouter tous les jours des ann‚es complŠtes ‚coul‚es }
   For i:=1970 to Y - 1 do
    If IsLeapYear(i)Then Inc(R,366)
                    Else Inc(R,365);
    { Ajouter tous les jours des mois ‚coul‚s dans l'ann‚e en cours }
   For i := 1 to M - 1 do Begin
    Inc(R, DaysPerMonth[i]);
    If(i=2)and IsLeapYear(Y)Then Inc(R); { F‚vrier a un jour de plus en ann‚e bissextile }
   End;
    { Ajouter les jours du mois en cours }
   Inc(R,D-1);
   DaysSinceEpoch:=R;
  End;

Begin
 GetDate(Year,Month,Day,WDay);
 GetTime(Hour,Min,Sec,Sec100);
 DaysSince1970:=DaysSinceEpoch(Year,Month,Day);
 Timestamp:=(DaysSince1970*86400)+(Hour*3600)+(Min*60)+Sec;
 If(PtrHeure <> Nil)Then PtrHeure^:=Timestamp;
 time_:=Timestamp;
End;

Procedure tzset;
Var
 tzStr:String;
 p:Integer;
Begin
 tzStr:=GetEnv('TZ'); { R‚cupŠre la variable d'environnement TZ }
 If tzStr=''Then Begin
  tzname[0]:='UTC';
  tzname[1]:='UTC+1';
  timezone:=0;
  daylight:=False;
 End
  Else
 Begin
  p:=Pos(',',tzStr);
  If p>0 Then Begin
  tzname[0]:=Copy(tzStr,1,p-1);
  Delete(tzStr,1,p);
  p:=Pos(',',tzStr);
  If p>0 Then Begin
   tzname[1]:=Copy(tzStr,1,p-1);
   Delete(tzStr,1,p);
   Val(tzStr,timezone,p);
   daylight:=True;
  End
   Else
  Begin
   tzname[1]:=tzname[0]+'-DST';
   Val(tzStr,timezone,p);
   daylight:=False;
  End;
 End
  Else
 Begin
  tzname[0]:=tzStr;
  tzname[1]:=tzStr+'-DST';
  timezone:=0;
  daylight:=False;
  End;
 End;
End;

END.