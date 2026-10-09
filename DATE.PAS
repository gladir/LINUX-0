{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program DATE;

Uses DOS;

Const
  MonthShort:Array[1..12]Of String[3]=
    ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
  MonthLong:Array[1..12]Of String[9]=
    ('January','February','March','April','May','June','July','August','September','October','November','December');
  DayShort:Array[0..6]Of String[3]=('Sun','Mon','Tue','Wed','Thu','Fri','Sat');
  DayLong:Array[0..6]Of String[9]=
    ('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday');

Var
  YearValue,MonthValue,DayValue,HourValue,MinuteValue,SecondValue,Hundredths:Word;
  DayOfWeekValue:Word;
  DayOfYearValue:Integer;
  MinutesWest:Integer;
  EpochSeconds,TimeAdjustment:LongInt;
  FormatString,DateArgument,Argument,LanguageCode,OutputText:String;
  ArgumentIndex,FormatIndex,ErrorCode:Integer;
  HasDateArgument,SetMode,UTCMode,NoHardwareSync:Boolean;
  UseFormat,AdjustmentSet:Boolean;

Function IsLeapYear(Value:Integer):Boolean;
Begin
  IsLeapYear:=(Value mod 4=0)and((Value mod 100<>0)or(Value mod 400=0));
End;

Function DaysInMonth(ValueYear,ValueMonth:Integer):Integer;
Begin
  Case ValueMonth Of
    4,6,9,11:DaysInMonth:=30;
    2:If IsLeapYear(ValueYear)Then DaysInMonth:=29 Else DaysInMonth:=28;
  Else DaysInMonth:=31;
  End;
End;

Function DayOfYear(ValueYear,ValueMonth,ValueDay:Integer):Integer;
Var
  Index,Total:Integer;
Begin
  Total:=ValueDay;
  For Index:=1 to ValueMonth-1 Do Inc(Total,DaysInMonth(ValueYear,Index));
  DayOfYear:=Total;
End;

Function DaysBeforeYear(ValueYear:Integer):LongInt;
Var
  PreviousYear:LongInt;
Begin
  PreviousYear:=ValueYear-1;
  DaysBeforeYear:=365*PreviousYear+PreviousYear div 4-
    PreviousYear div 100+PreviousYear div 400;
End;

Function DaysSinceEpoch(ValueYear,ValueMonth,ValueDay:Integer):LongInt;
Begin
  DaysSinceEpoch:=DaysBeforeYear(ValueYear)-DaysBeforeYear(1970)+
    DayOfYear(ValueYear,ValueMonth,ValueDay)-1;
End;

Function WeekdaySundayZero(ValueYear,ValueMonth,ValueDay:Integer):Integer;
Var
  Days:LongInt;
Begin
  Days:=DaysSinceEpoch(ValueYear,ValueMonth,ValueDay);
  WeekdaySundayZero:=Integer((Days+4)mod 7);
End;

Function ISOWeeksInYear(ValueYear:Integer):Integer;
Var
  FirstWeekday:Integer;
Begin
  FirstWeekday:=WeekdaySundayZero(ValueYear,1,1);
  If(FirstWeekday=4)or((FirstWeekday=3)and IsLeapYear(ValueYear))Then
    ISOWeeksInYear:=53
  Else ISOWeeksInYear:=52;
End;

Procedure GetISOWeek(ValueYear,ValueMonth,ValueDay:Integer;
                     Var ResultYear,ResultWeek:Integer);
Var
  ISOWeekdayValue,Ordinal,WeekNumber:Integer;
Begin
  ISOWeekdayValue:=((WeekdaySundayZero(ValueYear,ValueMonth,ValueDay)+6)mod 7)+1;
  Ordinal:=DayOfYear(ValueYear,ValueMonth,ValueDay);
  WeekNumber:=(Ordinal-ISOWeekdayValue+10)div 7;
  ResultYear:=ValueYear;
  If WeekNumber<1 Then Begin
    Dec(ResultYear);
    ResultWeek:=ISOWeeksInYear(ResultYear);
  End Else If WeekNumber>ISOWeeksInYear(ValueYear)Then Begin
    Inc(ResultYear);
    ResultWeek:=1;
  End Else ResultWeek:=WeekNumber;
End;

Function NumberText(Value:LongInt; Width:Integer; Fill:Char):String;
Var
  TextValue:String;
Begin
  Str(Value,TextValue);
  While Length(TextValue)<Width Do TextValue:=Fill+TextValue;
  NumberText:=TextValue;
End;

Function MonthName(ValueMonth:Integer; LongName:Boolean):String;
Begin
  If(ValueMonth<1)or(ValueMonth>12)Then Begin MonthName:=''; Exit; End;
  If LongName Then MonthName:=MonthLong[ValueMonth]
  Else MonthName:=MonthShort[ValueMonth];
End;

Function DayName(ValueDay:Integer; LongName:Boolean):String;
Begin
  If(ValueDay<0)or(ValueDay>6)Then Begin DayName:=''; Exit; End;
  If LongName Then DayName:=DayLong[ValueDay]
  Else DayName:=DayShort[ValueDay];
End;

Procedure NormalizeDateTime(Var ValueYear,ValueMonth,ValueDay,
                            ValueHour,ValueMinute,ValueSecond:Integer;
                            OffsetSeconds:LongInt);
Var
  TotalSeconds:LongInt;
  Days,SecondsInDay:LongInt;
Begin
  TotalSeconds:=DaysSinceEpoch(ValueYear,ValueMonth,ValueDay)*86400+
    ValueHour*3600+ValueMinute*60+ValueSecond+OffsetSeconds;
  Days:=TotalSeconds div 86400;
  SecondsInDay:=TotalSeconds mod 86400;
  If SecondsInDay<0 Then Begin Dec(Days); Inc(SecondsInDay,86400); End;
  ValueYear:=1970;
  If Days>=0 Then Begin
    While Days>=365 Do Begin
      If IsLeapYear(ValueYear)Then Begin
        If Days<366 Then Break;
        Dec(Days,366);
      End Else Dec(Days,365);
      Inc(ValueYear);
    End;
  End Else Begin
    While Days<0 Do Begin
      Dec(ValueYear);
      If IsLeapYear(ValueYear)Then Inc(Days,366)Else Inc(Days,365);
    End;
  End;
  ValueMonth:=1;
  While Days>=DaysInMonth(ValueYear,ValueMonth)Do Begin
    Dec(Days,DaysInMonth(ValueYear,ValueMonth));
    Inc(ValueMonth);
  End;
  ValueDay:=Days+1;
  ValueHour:=SecondsInDay div 3600;
  ValueMinute:=(SecondsInDay mod 3600)div 60;
  ValueSecond:=SecondsInDay mod 60;
End;

Function TryParseEpoch(Const Value:String; Var EpochValue:LongInt):Boolean;Forward;

Function ParseDateValue(Const TextValue:String):Boolean;
Var
  Numbers:Array[1..6]Of LongInt;
  NumberCount,Index,StartPosition,ValueLength:Integer;
  ValueYear,ValueMonth,ValueDay,ValueHour,ValueMinute,ValueSecond:Integer;
  NumberTextValue:String;
  ParsedValue:LongInt;
Begin
  ParseDateValue:=False;
  NumberCount:=0;
  Index:=1;
  If(Length(TextValue)>0)and(TextValue[1]='@')Then Begin
    If Not TryParseEpoch(Copy(TextValue,2,255),ParsedValue)Then Exit;
    ValueYear:=1970;ValueMonth:=1;ValueDay:=1;
    ValueHour:=0;ValueMinute:=0;ValueSecond:=0;
    NormalizeDateTime(ValueYear,ValueMonth,ValueDay,ValueHour,ValueMinute,
                      ValueSecond,ParsedValue);
    YearValue:=ValueYear;MonthValue:=ValueMonth;DayValue:=ValueDay;
    HourValue:=ValueHour;MinuteValue:=ValueMinute;SecondValue:=ValueSecond;
    Hundredths:=0;
    ParseDateValue:=True;
    Exit;
  End;
  While Index<=Length(TextValue)Do Begin
    If TextValue[Index]in['0'..'9']Then Begin
      StartPosition:=Index;
      While(Index<=Length(TextValue))and(TextValue[Index]in['0'..'9'])Do Inc(Index);
      NumberTextValue:=Copy(TextValue,StartPosition,Index-StartPosition);
      If NumberCount=0 Then ValueLength:=Length(NumberTextValue);
      If NumberCount<6 Then Begin
        Inc(NumberCount);
        Val(NumberTextValue,Numbers[NumberCount],ErrorCode);
        If ErrorCode<>0 Then Exit;
      End;
    End Else Inc(Index);
  End;
  If(NumberCount=1)and(ValueLength in[8,10,12,14])Then Begin
    NumberTextValue:=TextValue;
    Index:=1;
    While(Index<=Length(NumberTextValue))and not(NumberTextValue[Index]in['0'..'9'])Do Inc(Index);
    NumberTextValue:=Copy(NumberTextValue,Index,255);
    Val(Copy(NumberTextValue,1,4),ValueYear,ErrorCode);If ErrorCode<>0 Then Exit;
    Val(Copy(NumberTextValue,5,2),ValueMonth,ErrorCode);If ErrorCode<>0 Then Exit;
    Val(Copy(NumberTextValue,7,2),ValueDay,ErrorCode);If ErrorCode<>0 Then Exit;
    ValueHour:=0;ValueMinute:=0;ValueSecond:=0;
    If ValueLength>=10 Then Val(Copy(NumberTextValue,9,2),ValueHour,ErrorCode);
    If ValueLength>=12 Then Val(Copy(NumberTextValue,11,2),ValueMinute,ErrorCode);
    If ValueLength>=14 Then Val(Copy(NumberTextValue,13,2),ValueSecond,ErrorCode);
    If ErrorCode<>0 Then Exit;
  End Else If NumberCount>=3 Then Begin
    If Numbers[1]>31 Then Begin
      ValueYear:=Numbers[1];ValueMonth:=Numbers[2];ValueDay:=Numbers[3];
    End Else Begin
      ValueMonth:=Numbers[1];ValueDay:=Numbers[2];ValueYear:=Numbers[3];
      If ValueYear<100 Then
        If ValueYear<69 Then Inc(ValueYear,2000)Else Inc(ValueYear,1900);
    End;
    ValueHour:=0;ValueMinute:=0;ValueSecond:=0;
    If NumberCount>=4 Then ValueHour:=Numbers[4];
    If NumberCount>=5 Then ValueMinute:=Numbers[5];
    If NumberCount>=6 Then ValueSecond:=Numbers[6];
  End Else Exit;
  If(ValueYear<1980)or(ValueYear>2099)or(ValueMonth<1)or(ValueMonth>12)or
    (ValueDay<1)or(ValueDay>DaysInMonth(ValueYear,ValueMonth))or
    (ValueHour>23)or(ValueMinute>59)or(ValueSecond>59)Then Exit;
  YearValue:=ValueYear;MonthValue:=ValueMonth;DayValue:=ValueDay;
  HourValue:=ValueHour;MinuteValue:=ValueMinute;SecondValue:=ValueSecond;
  Hundredths:=0;
  ParseDateValue:=True;
End;

Function TryParseEpoch(Const Value:String; Var EpochValue:LongInt):Boolean;
Var
  Index,Digit:Integer;
  Accumulator:LongInt;
Begin
  TryParseEpoch:=False;
  If Value=''Then Exit;
  Accumulator:=0;
  For Index:=1 to Length(Value)Do Begin
    If Not(Value[Index]in['0'..'9'])Then Exit;
    Digit:=Ord(Value[Index])-Ord('0');
    If Accumulator>214748364 Then Exit;
    Accumulator:=Accumulator*10+Digit;
  End;
  EpochValue:=Accumulator;
  TryParseEpoch:=True;
End;

Function FormatTimezone(ColonCount:Integer):String;
Var
  Offset,HoursValue,MinutesValue:Integer;
  SignChar:Char;
Begin
  If UTCMode Then Offset:=0 Else Offset:=-MinutesWest;
  If Offset<0 Then Begin SignChar:='-';Offset:=-Offset;End
  Else SignChar:='+';
  HoursValue:=Offset div 60;
  MinutesValue:=Offset mod 60;
  If ColonCount=1 Then FormatTimezone:=SignChar+NumberText(HoursValue,2,'0')+':' +NumberText(MinutesValue,2,'0')
  Else If ColonCount=2 Then FormatTimezone:=SignChar+NumberText(HoursValue,2,'0')+':'+
    NumberText(MinutesValue,2,'0')+':00'
  Else If ColonCount=3 Then Begin
    If MinutesValue=0 Then FormatTimezone:=SignChar+NumberText(HoursValue,2,'0')
    Else FormatTimezone:=SignChar+NumberText(HoursValue,2,'0')+':' +NumberText(MinutesValue,2,'0');
  End Else FormatTimezone:=SignChar+NumberText(HoursValue,2,'0')+
                                  NumberText(MinutesValue,2,'0');
End;

Function FormatDate(Const FormatValue:String):String;
Var
  Index,FormatCode,ColonCount,Hour12,SundayWeek,MondayWeek:Integer;
  ResultValue,Replacement:String;
  ISOYearValue,ISOWeekValue:Integer;
  WeekdayValue:Integer;
Begin
  ResultValue:='';
  WeekdayValue:=WeekdaySundayZero(YearValue,MonthValue,DayValue);
  DayOfYearValue:=DayOfYear(YearValue,MonthValue,DayValue);
  GetISOWeek(YearValue,MonthValue,DayValue,ISOYearValue,ISOWeekValue);
  SundayWeek:=(DayOfYearValue-1+WeekdaySundayZero(YearValue,1,1))div 7;
  MondayWeek:=(DayOfYearValue-1+((WeekdaySundayZero(YearValue,1,1)+6)mod 7))div 7;
  Index:=1;
  While Index<=Length(FormatValue)Do Begin
    If FormatValue[Index]<>'%'Then Begin
      ResultValue:=ResultValue+FormatValue[Index];
      Inc(Index);
    End Else Begin
      Inc(Index);
      If Index>Length(FormatValue)Then Begin ResultValue:=ResultValue+'%';Break;End;
      ColonCount:=0;
      While(Index<=Length(FormatValue))and(FormatValue[Index]=':')Do Begin
        Inc(ColonCount);Inc(Index);
      End;
      If Index>Length(FormatValue)Then Break;
      FormatCode:=Ord(FormatValue[Index]);
      Case Chr(FormatCode)Of
        '%':Replacement:='%';
        'a':Replacement:=DayName(WeekdayValue,False);
        'A':Replacement:=DayName(WeekdayValue,True);
        'b','h':Replacement:=MonthName(MonthValue,False);
        'B':Replacement:=MonthName(MonthValue,True);
        'c':Replacement:=DayName(WeekdayValue,False)+' '+MonthName(MonthValue,False)+' '+
                         NumberText(DayValue,2,' ')+ ' '+NumberText(HourValue,2,'0')+':'+
                         NumberText(MinuteValue,2,'0')+':'+NumberText(SecondValue,2,'0')+' '+
                         NumberText(YearValue,4,'0');
        'C':Replacement:=NumberText(YearValue div 100,2,'0');
        'd':Replacement:=NumberText(DayValue,2,'0');
        'D':Replacement:=NumberText(MonthValue,2,'0')+'/'+NumberText(DayValue,2,'0')+'/'+
                         NumberText(YearValue mod 100,2,'0');
        'e':Replacement:=NumberText(DayValue,2,' ');
        'F':Replacement:=NumberText(YearValue,4,'0')+'-'+NumberText(MonthValue,2,'0')+'-'+NumberText(DayValue,2,'0');
        'g':Replacement:=NumberText(ISOYearValue mod 100,2,'0');
        'G':Replacement:=NumberText(ISOYearValue,4,'0');
        'H','k':Replacement:=NumberText(HourValue,2,'0');
        'I','l':Begin
          Hour12:=HourValue mod 12;
          If Hour12=0 Then Hour12:=12;
          If Chr(FormatCode)='l'Then Replacement:=NumberText(Hour12,1,' ')
          Else Replacement:=NumberText(Hour12,2,'0');
        End;
        'j':Replacement:=NumberText(DayOfYearValue,3,'0');
        'm':Replacement:=NumberText(MonthValue,2,'0');
        'M':Replacement:=NumberText(MinuteValue,2,'0');
        'n':Replacement:=#10;
        'N':Replacement:=NumberText(Hundredths*10000000,9,'0');
        'p':If HourValue<12 Then Replacement:='AM'Else Replacement:='PM';
        'P':If HourValue<12 Then Replacement:='am'Else Replacement:='pm';
        'r':Begin
          Hour12:=HourValue mod 12;If Hour12=0 Then Hour12:=12;
          If HourValue<12 Then Replacement:='AM'Else Replacement:='PM';
          Replacement:=NumberText(Hour12,2,'0')+':'+NumberText(MinuteValue,2,'0')+':'+
            NumberText(SecondValue,2,'0')+' '+Replacement;
        End;
        'R':Replacement:=NumberText(HourValue,2,'0')+':'+NumberText(MinuteValue,2,'0');
        's':Begin
          EpochSeconds:=DaysSinceEpoch(YearValue,MonthValue,DayValue)*86400+
            HourValue*3600+MinuteValue*60+SecondValue;
          If Not UTCMode Then Inc(EpochSeconds,LongInt(MinutesWest)*60);
          Str(EpochSeconds,Replacement);
        End;
        'S':Replacement:=NumberText(SecondValue,2,'0');
        't':Replacement:=#9;
        'T':Replacement:=NumberText(HourValue,2,'0')+':'+NumberText(MinuteValue,2,'0')+':'+NumberText(SecondValue,2,'0');
        'u':Replacement:=NumberText(((WeekdayValue+6)mod 7)+1,1,'0');
        'U':Replacement:=NumberText(SundayWeek,2,'0');
        'V':Replacement:=NumberText(ISOWeekValue,2,'0');
        'w':Replacement:=NumberText(WeekdayValue,1,'0');
        'W':Replacement:=NumberText(MondayWeek,2,'0');
        'x':Replacement:=NumberText(MonthValue,2,'0')+'/'+NumberText(DayValue,2,'0')+'/'+NumberText(YearValue mod 100,2,'0');
        'X':Replacement:=NumberText(HourValue,2,'0')+':'+NumberText(MinuteValue,2,'0')+':'+NumberText(SecondValue,2,'0');
        'y':Replacement:=NumberText(YearValue mod 100,2,'0');
        'Y':Replacement:=NumberText(YearValue,4,'0');
        'z':Replacement:=FormatTimezone(ColonCount);
        'Z':If UTCMode Then Replacement:='UTC'Else Replacement:='LOCAL';
      Else Replacement:='%'+Chr(FormatCode);
      End;
      ResultValue:=ResultValue+Replacement;
      Inc(Index);
    End;
  End;
  FormatDate:=ResultValue;
End;

Procedure AddAdjustment(Value:LongInt);
Var
  Total:LongInt;
  DaysValue:LongInt;
  HundredthsInDay:LongInt;
Begin
  Total:=HourValue*360000+MinuteValue*6000+SecondValue*100+Hundredths+Value;
  DaysValue:=Total div 8640000;
  HundredthsInDay:=Total mod 8640000;
  If HundredthsInDay<0 Then Begin Dec(DaysValue); Inc(HundredthsInDay,8640000); End;
    HourValue:=HundredthsInDay div 360000;
    MinuteValue:=(HundredthsInDay mod 360000)div 6000;
    SecondValue:=(HundredthsInDay mod 6000)div 100;
    Hundredths:=HundredthsInDay mod 100;
  While DaysValue>0 Do Begin
    If DayValue<DaysInMonth(YearValue,MonthValue)Then Inc(DayValue)
    Else Begin
      DayValue:=1;
      If MonthValue<12 Then Inc(MonthValue)
      Else Begin MonthValue:=1;Inc(YearValue);End;
    End;
    Dec(DaysValue);
  End;
  While DaysValue<0 Do Begin
    If DayValue>1 Then Dec(DayValue)
    Else Begin
      If MonthValue>1 Then Dec(MonthValue)
      Else Begin MonthValue:=12;Dec(YearValue);End;
      DayValue:=DaysInMonth(YearValue,MonthValue);
    End;
    Inc(DaysValue);
  End;
End;

Function ParseAdjustment(Const Value:String):LongInt;
Var
  Index,SignValue,DecimalPlaces,Digit:Integer;
  ResultValue:LongInt;
  AfterDecimal:Boolean;
Begin
  SignValue:=1;Index:=1;DecimalPlaces:=0;AfterDecimal:=False;ResultValue:=0;
  If(Length(Value)>0)and(Value[1]='-')Then Begin SignValue:=-1;Inc(Index);End
  Else If(Length(Value)>0)and(Value[1]='+')Then Inc(Index);
  While Index<=Length(Value)Do Begin
    If Value[Index]='.'Then AfterDecimal:=True
    Else If Value[Index]in['0'..'9']Then Begin
      Digit:=Ord(Value[Index])-Ord('0');
      If ResultValue<10000000 Then ResultValue:=ResultValue*10+Digit;
      If AfterDecimal Then Inc(DecimalPlaces);
    End Else Begin ParseAdjustment:=0;Exit;End;
    Inc(Index);
  End;
  While DecimalPlaces<2 Do Begin ResultValue:=ResultValue*10;Inc(DecimalPlaces);End;
  While DecimalPlaces>2 Do Begin ResultValue:=ResultValue div 10;Dec(DecimalPlaces);End;
  ParseAdjustment:=SignValue*ResultValue;
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('DATE : Display or set the system date and time.');
    WriteLn('Syntax: date [-u] [-d date] [-s date] [-t minutes-west] [-a adjustment] [+format]');
    WriteLn(' -u          Interpret/display the value as UTC');
    WriteLn(' -d DATE     Display a parsed date without changing the clock');
    WriteLn(' -s DATE     Set the DOS system date and time');
    WriteLn(' -t MINUTES  Set the minutes-west offset for %z and %s');
    WriteLn(' +FORMAT     Format with strftime-style conversions');
    WriteLn('Supports the documented calendar, time, week and epoch conversions.');
  End Else Begin
    WriteLn('DATE : Cette commande permet d''afficher ou de r'+#130+'gler la date et l''heure du systeme.');
    WriteLn;
    WriteLn('Syntaxe : date [-u] [-d date] [-s date] [-t minutes-ouest] [-a ajustement] [+format]');
    WriteLn;
    WriteLn(' -u          Interpreter et afficher la valeur en UTC');
    WriteLn(' -d DATE     Afficher une date analysee sans changer l''horloge');
    WriteLn(' -s DATE     Regler la date et l''heure DOS');
    WriteLn(' -t MINUTES  Definir le decalage ouest pour %z et %s');
    WriteLn(' +FORMAT     Formater avec les conversions strftime documentees');
    WriteLn;
    WriteLn('Prend en charge les conversions de calendrier, heure, semaine et epoch.');
  End;
End;

Procedure OptionError(Const MessageText:String);
Begin WriteLn('date: ',MessageText);Halt(2);End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  GetDate(YearValue,MonthValue,DayValue,DayOfWeekValue);
  GetTime(HourValue,MinuteValue,SecondValue,Hundredths);
  MinutesWest:=0;UTCMode:=False;SetMode:=False;
  NoHardwareSync:=False;UseFormat:=False;AdjustmentSet:=False;
  HasDateArgument:=False;TimeAdjustment:=0;FormatString:='';DateArgument:='';
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('date (LINUX-0) 1.0');Halt(0);End
    Else If(Argument='-u')or(Argument='--universal')Then UTCMode:=True
    Else If(Argument='-c')Then Begin End
    Else If(Argument='-n')Then NoHardwareSync:=True
    Else If(Argument='-d')or(Argument='--date')Then Begin
      Inc(ArgumentIndex);If ArgumentIndex>ParamCount Then OptionError('-d attend une date');
      DateArgument:=ParamStr(ArgumentIndex);HasDateArgument:=True;
    End Else If(Argument='-s')or(Argument='--set')Then Begin
      Inc(ArgumentIndex);If ArgumentIndex>ParamCount Then OptionError('-s attend une date');
      DateArgument:=ParamStr(ArgumentIndex);HasDateArgument:=True;SetMode:=True;
    End Else If(Argument='-t')Then Begin
      Inc(ArgumentIndex);If ArgumentIndex>ParamCount Then OptionError('-t attend un decalage en minutes');
      Val(ParamStr(ArgumentIndex),MinutesWest,ErrorCode);
      If ErrorCode<>0 Then OptionError('decalage horaire invalide');
    End Else If(Argument='-a')Then Begin
      Inc(ArgumentIndex);If ArgumentIndex>ParamCount Then OptionError('-a attend un ajustement');
      TimeAdjustment:=ParseAdjustment(ParamStr(ArgumentIndex));AdjustmentSet:=True;
    End Else If(Length(Argument)>7)and(Copy(Argument,1,7)='--date=')Then Begin
      DateArgument:=Copy(Argument,8,255);HasDateArgument:=True;
    End Else If(Length(Argument)>6)and(Copy(Argument,1,6)='--set=')Then Begin
      DateArgument:=Copy(Argument,7,255);HasDateArgument:=True;SetMode:=True;
    End Else If(Length(Argument)>1)and(Argument[1]='+')Then Begin
      FormatString:=Copy(Argument,2,255);UseFormat:=True;
    End Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      If(Argument[2]='-')Then OptionError('option inconnue: '+Argument);
      For FormatIndex:=2 to Length(Argument)Do Begin
        If Argument[FormatIndex]='u'Then UTCMode:=True
        Else If Argument[FormatIndex]='c'Then Begin End
        Else If Argument[FormatIndex]='n'Then NoHardwareSync:=True
        Else OptionError('option inconnue: '+Argument);
      End;
    End Else Begin DateArgument:=Argument;HasDateArgument:=True;SetMode:=True;End;
    Inc(ArgumentIndex);
  End;
  If HasDateArgument Then
    If Not ParseDateValue(DateArgument)Then OptionError('date invalide: '+DateArgument);
  If AdjustmentSet Then AddAdjustment(TimeAdjustment);
  If SetMode and Not NoHardwareSync Then Begin
    SetDate(YearValue,MonthValue,DayValue);
    SetTime(HourValue,MinuteValue,SecondValue,Hundredths);
  End;
  If UseFormat Then OutputText:=FormatDate(FormatString)
  Else OutputText:=FormatDate('%a %b %e %H:%M:%S %Y');
  WriteLn(OutputText);
END.