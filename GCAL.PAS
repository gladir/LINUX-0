{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program GCAL;

Uses DOS;

Const
 MaxNotes=128;
 MaxNoteText=120;

Type
 TNoteText=String[MaxNoteText];
 TNote=Record
  Year,Month,Day:Integer;
  Text:TNoteText;
 End;
 TNoteArray=Array[1..MaxNotes]Of TNote;
 TMonthNames=Array[1..12]Of String[9];
 TWeekNames=Array[0..6]Of String[3];

Var
 Notes:TNoteArray;
 NoteCount:Integer;
 MonthNames:TMonthNames;
 WeekNames:TWeekNames;
 JulianCalendar,SundayFirst,ShowYear:Boolean;
 CurrentYear,CurrentMonth:Word;
 DisplayYear,DisplayMonth:Integer;
 CurrentDay,DayOfWeekValue:Word;
 ArgumentIndex,ErrorCode,ArgumentMonth,ArgumentYear:Integer;
 HelpRequested,VersionRequested,HaveMonth,HaveYear:Boolean;
 SourceName,Argument:String[127];

Function IsLeapYear(Year:Integer):Boolean;
Begin
 If JulianCalendar Then IsLeapYear:=(Year Mod 4)=0
 Else IsLeapYear:=((Year Mod 4)=0)And
                  (((Year Mod 100)<>0)Or((Year Mod 400)=0));
End;

Function DaysInMonth(Year,Month:Integer):Integer;
Begin
 Case Month Of
  1,3,5,7,8,10,12:DaysInMonth:=31;
  4,6,9,11:DaysInMonth:=30;
  2:If IsLeapYear(Year)Then DaysInMonth:=29 Else DaysInMonth:=28;
 Else DaysInMonth:=0;
 End;
End;

Function MonthName(Month:Integer):String;
Begin
 MonthName:=MonthNames[Month];
End;

Function DayOfWeek(Year,Month,Day:LongInt):Integer;
Var
 A,Y,M:LongInt;
 JulianDay:LongInt;
Begin
 A:=(14-Month)Div 12;
 Y:=Year+4800-A;
 M:=Month+12*A-3;
 If JulianCalendar Then
  JulianDay:=Day+(153*M+2)Div 5+365*Y+Y Div 4-32083
 Else
  JulianDay:=Day+(153*M+2)Div 5+365*Y+Y Div 4-Y Div 100+Y Div 400-32045;
 DayOfWeek:=JulianDay Mod 7;
End;

Procedure ShowHelp;
Begin
 WriteLn('GCAL - Cette commande permet d''afficher un calendrier julien ou gregorien.');
 WriteLn;
 WriteLn('Syntaxe: GCAL [options] [mois [annee]] [@fichier-notes]');
 WriteLn;
 WriteLn('  -g          Calendrier gregorien (defaut)');
 WriteLn('  -j          Calendrier julien');
 WriteLn('  -m          Semaines commencant lundi (defaut)');
 WriteLn('  -s          Semaines commencant dimanche');
 WriteLn('  -y ANNEE    Afficher les douze mois de l''annee');
 WriteLn('  %AAAA-MM-JJ Afficher le mois de la date indiquee');
 WriteLn('  @fichier    Notes au format AAAA-MM-JJ texte');
 WriteLn('  -h, --help  Afficher cette aide');
 WriteLn('  -V, --version Afficher la version');
End;

Procedure ShowVersion;
Begin
 WriteLn('gcal 1.0 - LINUX-0 Pascal');
End;

Procedure AddNote(Const Value:String);
Var
 NoteLine:TNoteText;
 NoteYear,NoteMonth,NoteDay,Err:Integer;
 NoteText:String;
Begin
 NoteLine:=Value;
 If Length(NoteLine)<10 Then Exit;
 If(NoteLine[5]<>'-')Or(NoteLine[8]<>'-')Then Exit;
 Val(Copy(NoteLine,1,4),NoteYear,Err);
 If Err<>0 Then Exit;
 Val(Copy(NoteLine,6,2),NoteMonth,Err);
 If Err<>0 Then Exit;
 Val(Copy(NoteLine,9,2),NoteDay,Err);
 If Err<>0 Then Exit;
 If(NoteMonth<1)Or(NoteMonth>12)Or(NoteDay<1)Or
   (NoteDay>DaysInMonth(NoteYear,NoteMonth))Then Exit;
 NoteText:=Copy(NoteLine,11,MaxNoteText);
 While(Length(NoteText)>0)And(NoteText[1]In[' ',#9])Do
  Delete(NoteText,1,1);
 If NoteCount>=MaxNotes Then Exit;
 Inc(NoteCount);
 Notes[NoteCount].Year:=NoteYear;
 Notes[NoteCount].Month:=NoteMonth;
 Notes[NoteCount].Day:=NoteDay;
 Notes[NoteCount].Text:=NoteText;
End;

Procedure LoadNotes(Const Name:String);
Var
 NoteFile:Text;
 NoteLine:TNoteText;
 OldFileMode:Byte;
Begin
 Assign(NoteFile,Name);
 OldFileMode:=FileMode;
 FileMode:=0;
 {$I-}Reset(NoteFile);{$I+}
 ErrorCode:=IOResult;
 FileMode:=OldFileMode;
 If ErrorCode<>0 Then Begin
  WriteLn('gcal: impossible de lire ',Name);
  Exit;
 End;
 While Not EOF(NoteFile)Do Begin
  ReadLn(NoteFile,NoteLine);
  AddNote(NoteLine);
 End;
 {$I-}Close(NoteFile);{$I+}
 ErrorCode:=IOResult;
End;

Procedure PrintNotes(Year,Month:Integer);
Var
 NoteIndex:Integer;
Begin
 For NoteIndex:=1 To NoteCount Do
  If(Notes[NoteIndex].Year=Year)And(Notes[NoteIndex].Month=Month)Then
   WriteLn(Notes[NoteIndex].Day:2,' ',Notes[NoteIndex].Text);
End;

Procedure PrintMonth(Year,Month:Integer);
Var
 Day,Weekday,Column,StartOffset:Integer;
Begin
 If(Year<1)Or(Year>9999)Or(Month<1)Or(Month>12)Then Exit;
 If JulianCalendar Then WriteLn(MonthName(Month),' ',Year,'  (Julien)')
 Else WriteLn(MonthName(Month),' ',Year,'  (Gregorien)');
 For Column:=0 To 6 Do Write(WeekNames[Column]:4);
 WriteLn;
 Weekday:=DayOfWeek(Year,Month,1);
 If SundayFirst Then StartOffset:=(Weekday+1)Mod 7
 Else StartOffset:=Weekday;
 For Column:=1 To StartOffset Do Write(' ':4);
 For Day:=1 To DaysInMonth(Year,Month)Do Begin
  Write(Day:4);
  If((StartOffset+Day)Mod 7)=0 Then WriteLn;
 End;
 If((StartOffset+DaysInMonth(Year,Month))Mod 7)<>0 Then WriteLn;
 PrintNotes(Year,Month);
 WriteLn;
End;

Procedure SetMonthNames;
Begin
 MonthNames[1]:='Janvier';
 MonthNames[2]:='Fevrier';
 MonthNames[3]:='Mars';
 MonthNames[4]:='Avril';
 MonthNames[5]:='Mai';
 MonthNames[6]:='Juin';
 MonthNames[7]:='Juillet';
 MonthNames[8]:='Aout';
 MonthNames[9]:='Septembre';
 MonthNames[10]:='Octobre';
 MonthNames[11]:='Novembre';
 MonthNames[12]:='Decembre';
 WeekNames[0]:='Lun';
 WeekNames[1]:='Mar';
 WeekNames[2]:='Mer';
 WeekNames[3]:='Jeu';
 WeekNames[4]:='Ven';
 WeekNames[5]:='Sam';
 WeekNames[6]:='Dim';
 If SundayFirst Then Begin
  WeekNames[0]:='Dim';
  WeekNames[1]:='Lun';
  WeekNames[2]:='Mar';
  WeekNames[3]:='Mer';
  WeekNames[4]:='Jeu';
  WeekNames[5]:='Ven';
  WeekNames[6]:='Sam';
 End;
End;

Function ParseDate(Const Value:String;Var Year,Month:Integer):Boolean;
Var
 DateValue:String;
 Err:Integer;
Begin
 DateValue:=Value;
 If(Length(DateValue)>0)And(DateValue[1]='%')Then
  Delete(DateValue,1,1);
 ParseDate:=False;
 If(Length(DateValue)=7)And(DateValue[5]='-')Then Begin
  Val(Copy(DateValue,1,4),Year,Err);
  If Err<>0 Then Exit;
  Val(Copy(DateValue,6,2),Month,Err);
  If Err<>0 Then Exit;
 End Else If(Length(DateValue)=10)And(DateValue[5]='-')And
              (DateValue[8]='-')Then Begin
  Val(Copy(DateValue,1,4),Year,Err);
  If Err<>0 Then Exit;
  Val(Copy(DateValue,6,2),Month,Err);
  If Err<>0 Then Exit;
 End Else Exit;
 ParseDate:=(Year>=1)And(Year<=9999)And(Month>=1)And(Month<=12);
End;

Procedure ParseArguments;
Var
 ArgumentIndex:Integer;
 ArgumentYear,ArgumentMonth:Integer;
 Argument:String;
Begin
 JulianCalendar:=False;
 SundayFirst:=False;
 ShowYear:=False;
 HelpRequested:=False;
 VersionRequested:=False;
 HaveMonth:=False;
 HaveYear:=False;
 SourceName:='';
 NoteCount:=0;
 GetDate(CurrentYear,CurrentMonth,CurrentDay,DayOfWeekValue);
 DisplayYear:=CurrentYear;
 DisplayMonth:=CurrentMonth;
 ArgumentIndex:=1;
 While ArgumentIndex<=ParamCount Do Begin
  Argument:=ParamStr(ArgumentIndex);
  If(Argument='--help')Or(Argument='-h')Or(Argument='/?')Or
    (Argument='/h')Or(Argument='/H')Then HelpRequested:=True
  Else If(Argument='--version')Or(Argument='-V')Then VersionRequested:=True
  Else If Argument='-j'Then JulianCalendar:=True
  Else If Argument='-g'Then JulianCalendar:=False
  Else If Argument='-s'Then SundayFirst:=True
  Else If Argument='-m'Then SundayFirst:=False
  Else If(Argument='-y')Or(Argument='--year')Then Begin
   Inc(ArgumentIndex);
   If ArgumentIndex>ParamCount Then Begin
    WriteLn('gcal: annee manquante apres -y');
    Halt(2);
   End;
   Val(ParamStr(ArgumentIndex),DisplayYear,ErrorCode);
   If(ErrorCode<>0)Or(DisplayYear<1)Or(DisplayYear>9999)Then Begin
    WriteLn('gcal: annee invalide');
    Halt(2);
   End;
   ShowYear:=True;
  End Else If(Length(Argument)>1)And(Argument[1]='@')Then
   SourceName:=Copy(Argument,2,127)
  Else If ParseDate(Argument,ArgumentYear,ArgumentMonth)Then Begin
   DisplayYear:=ArgumentYear;
   DisplayMonth:=ArgumentMonth;
   HaveMonth:=True;
   HaveYear:=True;
  End Else If(Length(Argument)=4)Then Begin
   Val(Argument,ArgumentYear,ErrorCode);
   If(ErrorCode=0)And(ArgumentYear>=1)And(ArgumentYear<=9999)Then Begin
    DisplayYear:=ArgumentYear;
    HaveYear:=True;
    If Not HaveMonth Then ShowYear:=True;
   End Else Begin
    Val(Argument,ArgumentMonth,ErrorCode);
    If(ErrorCode=0)And(ArgumentMonth>=1)And(ArgumentMonth<=12)Then Begin
     DisplayMonth:=ArgumentMonth;
     HaveMonth:=True;
    End Else Begin
     WriteLn('gcal: argument invalide: ',Argument);
     Halt(2);
    End;
   End;
  End Else If(Length(Argument)<=2)Then Begin
   Val(Argument,ArgumentMonth,ErrorCode);
   If(ErrorCode<>0)Or(ArgumentMonth<1)Or(ArgumentMonth>12)Then Begin
    WriteLn('gcal: mois invalide: ',Argument);
    Halt(2);
   End;
   DisplayMonth:=ArgumentMonth;
   HaveMonth:=True;
  End Else Begin
   WriteLn('gcal: option ou date inconnue: ',Argument);
   Halt(2);
  End;
  Inc(ArgumentIndex);
 End;
 If HaveMonth And Not HaveYear Then DisplayYear:=CurrentYear;
 If HaveYear And Not HaveMonth And Not ShowYear Then ShowYear:=True;
 If SourceName<>''Then LoadNotes(SourceName);
End;

Begin
 SetMonthNames;
 ParseArguments;
 If HelpRequested Then Begin ShowHelp;Halt(0);End;
 If VersionRequested Then Begin ShowVersion;Halt(0);End;
 SetMonthNames;
 If ShowYear Then Begin
  For ArgumentIndex:=1 To 12 Do PrintMonth(DisplayYear,ArgumentIndex);
 End Else PrintMonth(DisplayYear,DisplayMonth);
End.