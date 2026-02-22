{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program AC;

{$A-}

Uses DOS,Strings;

Const
 EMPTY         = 0;  { Enregistrement vide }
 RUN_LVL       = 1;  { Changement de niveau d'ex�cution }
 BOOT_TIME     = 2;  { Heure de d�marrage du syst�me }
 NEW_TIME      = 3;  { Changement d'heure (ancien temps) }
 OLD_TIME      = 4;  { Changement d'heure (nouveau temps) }
 INIT_PROCESS  = 5;  { Processus d'initialisation }
 LOGIN_PROCESS = 6;  { Processus de connexion }
 USER_PROCESS  = 7;  { Session utilisateur active }
 DEAD_PROCESS  = 8;  { Processus termin� }
 ACCOUNTING    = 9;  { Audit }

 UT_LINESIZE=32;
 UT_NAMESIZE=32;
 UT_HOSTSIZE=256;

Type
 TExitStatus=Record
  e_termination: {$IFDEF FPC}SmallInt{$ELSE}Integer{$ENDIF};  { Code de terminaison }
  e_exit:{$IFDEF FPC}SmallInt{$ELSE}Integer{$ENDIF};          { Code de sortie }
 End;

 TTimeVal=Record
  tv_sec:LongInt;   { Secondes depuis l'epoch }
  tv_usec:LongInt;  { Microsecondes }
 End;

 TUTMPX32=Record
  ut_type:{$IFDEF FPC}SmallInt{$ELSE}Integer{$ENDIF};
  ut_pid:LongInt;
  ut_line:Array[0..UT_LINESIZE-1] of Char;
  ut_id:Array[0..3] of Char;
  ut_user:Array[0..UT_NAMESIZE-1] of Char;
  ut_host:Array[0..UT_HOSTSIZE-1] of Char;
  ut_exit:TExitStatus;
  ut_session:LongInt;
  ut_tv:TTimeVal;
  ut_addr_v6:Array[0..3] of LongInt;
  __glibc_reserved:Array[0..19] of Byte;
 End;

 TUTMPX64=Record
  ut_type:{$IFDEF FPC}SmallInt{$ELSE}Integer{$ENDIF};
  ut_pid:LongInt;
  ut_pid2:Word;
  ut_line:Array[0..UT_LINESIZE-1] of Char;
  ut_id:Array[0..3] of Char;
  ut_user:Array[0..UT_NAMESIZE-1] of Char;
  ut_host:Array[0..UT_HOSTSIZE-1] of Char;
  ut_exit:TExitStatus;
  ut_session:LongInt;
  ut_tv:TTimeVal;
  ut_session64:LongInt;
  ut_addr_v6:array[0..3] of LongInt;
  __glibc_reserved:Array[0..15] of Byte;
 End;

Const
 WtmpFile:String='/var/log/wtmp';

Var
 Language:(_French,_English,_Germany,_Italian,_Spain,_Albanian,_Portuguese,_Swedish,_Danish,_Japanese);
 TmpLanguage:String;
 f:File;
 rec:TUTMPX64;
 numRead:Integer;
 i:Integer;
 DailyTotals,PrintYear,IndividualTotals,AllDays,PrintZeros:Boolean;
 UserCount:Integer;
 BaseDir:String;
 People:String;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

Function PadRight(S:String;Space:Byte):String;
Var
 I:Byte;
Begin
 If Length(S)<Space Then For I:=Length(S)+1 to Space do S:=S+' ';
 PadRight:=S;
End;

Function PadZeroLeft(Value:Integer;Space:Byte):String;
Var
 S:String;
Begin
 Str(Value,S);
 While Length(S)<Space do S:='0'+S;
 PadZeroLeft:=S;
End;

Procedure TruncAfterSemicolon(Var S:String);
Var
 I:Byte;
Begin
 For I:=1to Length(S)do If S[I]=';'Then Begin
  S[0]:=Chr(I-1);
  Exit;
 End;
End;

Function Path2Dir(Const Path:String):String;
Var
 D:DirStr;
 N:NameStr;
 E:ExtStr;
Begin
 Path2Dir:='';
 If Path=''Then Exit;
 FSplit(Path,D,N,E);
 If E=''Then Begin
  If D[Length(D)]<>'\'Then D:=D+'\';
  D:=D+E;
 End;
 If D=''Then Path2Dir:='' Else
 If D[Length(D)]<>'\'Then D:=D+'\';
 Path2Dir:=D;
End;

Function IsWildCard(Const Path:String):Boolean;Begin
 IsWildCard:=(Pos('*',Path)>0)or(Pos('?',Path)>0);
End;

Function DirExist(Dir:String):Boolean;
Var
 Rec:SearchRec;
Begin
 If Length(Dir)=0Then DirExist:=True
  Else
 Begin
  TruncAfterSemicolon(Dir);
  If Dir[Length(Dir)]='\'Then Dir:=Dir+'*.*' Else
  If IsWildCard(Dir)Then Dir:=Path2Dir(Dir)+'*.*';
  FindFirst(Dir,Directory,Rec);
  DirExist:=DOSError=0;
 End;
End;

Procedure JulianToGregorian(JulianDN:LongInt;Var Year,Month,Day:Word);
Var
 YYear,XYear,Temp,TempMonth:LongInt;
Begin
 Temp:=((JulianDN-1721119) shl 2)-1;
 JulianDN:=Temp Div 146097;
 XYear:=(Temp Mod 146097) or 3;
 YYear:=(XYear Div 1461);
 Temp:=((((XYear mod 1461)+4) shr 2)*5)-3;
 Day:=((Temp Mod 153)+5) Div 5;
 TempMonth:=Temp Div 153;
 If TempMonth>=10 Then Begin
  Inc(YYear);
  Dec(TempMonth,12);
 End;
 Inc(TempMonth,3);
 Month:=TempMonth;
 Year:=YYear+(JulianDN*100);
End;

Procedure EpochToLocal(Epoch:LongInt;Var Year,Month,Day,Hour,Minute,Second:Word);
Var
 DateNum:LongInt;
Begin
 DateNum:=(Epoch div 86400)+2440588;
 JulianToGregorian(DateNum,Year,Month,day);
 Epoch:=Abs(Epoch mod 86400);
 Hour:=Epoch div 3600;
 Epoch:=Epoch mod 3600;
 Minute:=Epoch div 60;
 Second:=Epoch mod 60;
End;

Function DateTimeToStr(DateTime:LongInt):String;
Var
 Year,Month,Day,Hour,Min,Sec,MSec:Word;
 S,R:String;
Begin
 EpochToLocal(DateTime,Year,Month,Day,Hour,Min,Sec);
 R:=PadZeroLeft(Day,2)+'/'+PadZeroLeft(Month,2)+'/'+PadZeroLeft(Year,4)+' ';
 Str(Hour:2,S);
 R:=R+S+':';
 R:=R+PadZeroLeft(Min,2)+':'+PadZeroLeft(Sec,2);
 DateTimeToStr:=R;
End;

BEGIN
 Language:=_French;
 TmpLanguage:=GetEnv('LANGUAGE');
 If TmpLanguage<>''Then Begin
  If TmpLanguage[1]='"'Then TmpLanguage:=Copy(TmpLanguage,2,255);
  If StrToUpper(Copy(TmpLanguage,1,2))='EN'Then Language:=_English Else
  If StrToUpper(Copy(TmpLanguage,1,2))='GR'Then Language:=_Germany Else
  If StrToUpper(Copy(TmpLanguage,1,2))='IT'Then Language:=_Italian Else
  If StrToUpper(Copy(TmpLanguage,1,2))='SP'Then Language:=_Spain Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='SQ')or
    (StrToUpper(Copy(TmpLanguage,1,3))='ALB')Then Language:=_Albanian Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='PT')or
    (StrToUpper(Copy(TmpLanguage,1,3))='PRT')Then Language:=_Portuguese Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='SE')or
    (StrToUpper(Copy(TmpLanguage,1,3))='SWE')Then Language:=_Swedish Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='DK')or
    (StrToUpper(Copy(TmpLanguage,1,3))='DNK')Then Language:=_Danish Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='JP')or
    (StrToUpper(Copy(TmpLanguage,1,3))='JPN')Then Language:=_Japanese;
 End;
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  Case Language of
   _English:Begin
    WriteLn('AC : This command displays user login time statistics.');
    WriteLn;
    Writeln('Syntax : AC [options] [people]');
    WriteLn;
    Writeln('  -a, --all-days        Include all days');
    Writeln('  -d, --daily-totals    Print daily totals');
    Writeln('  -y, --print-year      Print year information');
    Writeln('  -p, --individual-totals Print individual totals');
    Writeln('  -f, --file <file>     Use alternative wtmp file');
    Writeln('  -z, --print-zeros     Print zero entries');
    Writeln('  -V, --version         Display version information');
    Writeln('  -h, --help            Display this command help');
    WriteLn(' --cygwin               Search in Cygwin directories');
    WriteLn(' --cygwin32             Search in 32-bit Cygwin directories');
    WriteLn(' --cygwin64             Search in 64-bit Cygwin directories');
   End;
   _Germany:Begin
    WriteLn('AC : Dieser Befehl zeigt Benutzer-Anmeldezeit-Statistiken an.');
    WriteLn;
    Writeln('Syntax : AC [Optionen] [Benutzer]');
    WriteLn;
    Writeln('  -a, --all-days        Alle Tage einschließen');
    Writeln('  -d, --daily-totals    Tägliche Gesamtsummen drucken');
    Writeln('  -y, --print-year      Jahresinformationen drucken');
    Writeln('  -p, --individual-totals Individuelle Gesamtsummen drucken');
    Writeln('  -f, --file <Datei>    Alternative wtmp-Datei verwenden');
    Writeln('  -z, --print-zeros     Null-Einträge drucken');
    Writeln('  -V, --version         Versionsinformationen anzeigen');
    Writeln('  -h, --help            Diese Befehlshilfe anzeigen');
    WriteLn(' --cygwin               In Cygwin-Verzeichnissen suchen');
    WriteLn(' --cygwin32             In 32-Bit-Cygwin-Verzeichnissen suchen');
    WriteLn(' --cygwin64             In 64-Bit-Cygwin-Verzeichnissen suchen');
   End;
   _Italian:Begin
    WriteLn('AC : Questo comando visualizza le statistiche del tempo di accesso utente.');
    WriteLn;
    Writeln('Sintassi : AC [opzioni] [utenti]');
    WriteLn;
    Writeln('  -a, --all-days        Includi tutti i giorni');
    Writeln('  -d, --daily-totals    Stampa totali giornalieri');
    Writeln('  -y, --print-year      Stampa informazioni anno');
    Writeln('  -p, --individual-totals Stampa totali individuali');
    Writeln('  -f, --file <file>     Usa file wtmp alternativo');
    Writeln('  -z, --print-zeros     Stampa voci zero');
    Writeln('  -V, --version         Visualizza informazioni versione');
    Writeln('  -h, --help            Visualizza aiuto comando');
    WriteLn(' --cygwin               Cerca nelle directory Cygwin');
    WriteLn(' --cygwin32             Cerca nelle directory Cygwin 32-bit');
    WriteLn(' --cygwin64             Cerca nelle directory Cygwin 64-bit');
   End;
   _Spain:Begin
    WriteLn('AC : Este comando muestra estadísticas de tiempo de conexión de usuario.');
    WriteLn;
    Writeln('Sintaxis : AC [opciones] [usuarios]');
    WriteLn;
    Writeln('  -a, --all-days        Incluir todos los días');
    Writeln('  -d, --daily-totals    Imprimir totales diarios');
    Writeln('  -y, --print-year      Imprimir información del año');
    Writeln('  -p, --individual-totals Imprimir totales individuales');
    Writeln('  -f, --file <archivo>  Usar archivo wtmp alternativo');
    Writeln('  -z, --print-zeros     Imprimir entradas cero');
    Writeln('  -V, --version         Mostrar información de versión');
    Writeln('  -h, --help            Mostrar ayuda del comando');
    WriteLn(' --cygwin               Buscar en directorios Cygwin');
    WriteLn(' --cygwin32             Buscar en directorios Cygwin 32-bit');
    WriteLn(' --cygwin64             Buscar en directorios Cygwin 64-bit');
   End;
   _Albanian:Begin
    WriteLn('AC : Ky komandë shfaq statistikat e kohës së hyrjes së përdoruesit.');
    WriteLn;
    Writeln('Sintaksa : AC [opsione] [njerëz]');
    WriteLn;
    Writeln('  -a, --all-days        Përfshi të gjitha ditët');
    Writeln('  -d, --daily-totals    Shtyp totalet ditore');
    Writeln('  -y, --print-year      Shtyp informacionin e vitit');
    Writeln('  -p, --individual-totals Shtyp totalet individuale');
    Writeln('  -f, --file <skedar>   Përdor skedar wtmp alternativ');
    Writeln('  -z, --print-zeros     Shtyp hyrjet zero');
    Writeln('  -V, --version         Shfaq informacionin e versionit');
    Writeln('  -h, --help            Shfaq ndihmën e komandës');
    WriteLn(' --cygwin               Kërko në dosjet e Cygwin');
    WriteLn(' --cygwin32             Kërko në dosjet e Cygwin 32-bit');
    WriteLn(' --cygwin64             Kërko në dosjet e Cygwin 64-bit');
   End;
   _Portuguese:Begin
    WriteLn('AC : Este comando exibe estatísticas de tempo de login do usuário.');
    WriteLn;
    Writeln('Sintaxe : AC [opções] [pessoas]');
    WriteLn;
    Writeln('  -a, --all-days        Incluir todos os dias');
    Writeln('  -d, --daily-totals    Imprimir totais diários');
    Writeln('  -y, --print-year      Imprimir informações do ano');
    Writeln('  -p, --individual-totals Imprimir totais individuais');
    Writeln('  -f, --file <arquivo>  Usar arquivo wtmp alternativo');
    Writeln('  -z, --print-zeros     Imprimir entradas zero');
    Writeln('  -V, --version         Exibir informações da versão');
    Writeln('  -h, --help            Exibir ajuda do comando');
    WriteLn(' --cygwin               Procurar em diretórios Cygwin');
    WriteLn(' --cygwin32             Procurar em diretórios Cygwin 32-bit');
    WriteLn(' --cygwin64             Procurar em diretórios Cygwin 64-bit');
   End;
   _Swedish:Begin
    WriteLn('AC : Detta kommando visar användarinloggnings-tidsstatistik.');
    WriteLn;
    Writeln('Syntax : AC [alternativ] [personer]');
    WriteLn;
    Writeln('  -a, --all-days        Inkludera alla dagar');
    Writeln('  -d, --daily-totals    Skriv ut dagliga totaler');
    Writeln('  -y, --print-year      Skriv ut årsinformation');
    Writeln('  -p, --individual-totals Skriv ut individuella totaler');
    Writeln('  -f, --file <fil>      Använd alternativ wtmp-fil');
    Writeln('  -z, --print-zeros     Skriv ut nollposter');
    Writeln('  -V, --version         Visa versionsinformation');
    Writeln('  -h, --help            Visa kommandohjälp');
    WriteLn(' --cygwin               Sök i Cygwin-kataloger');
    WriteLn(' --cygwin32             Sök i 32-bitars Cygwin-kataloger');
    WriteLn(' --cygwin64             Sök i 64-bitars Cygwin-kataloger');
   End;
   _Danish:Begin
    WriteLn('AC : Denne kommando viser brugerlogin-tidsstatistikker.');
    WriteLn;
    Writeln('Syntaks : AC [muligheder] [personer]');
    WriteLn;
    Writeln('  -a, --all-days        Inkluder alle dage');
    Writeln('  -d, --daily-totals    Udskriv daglige totaler');
    Writeln('  -y, --print-year      Udskriv årsinformation');
    Writeln('  -p, --individual-totals Udskriv individuelle totaler');
    Writeln('  -f, --file <fil>      Brug alternativ wtmp-fil');
    Writeln('  -z, --print-zeros     Udskriv nul-poster');
    Writeln('  -V, --version         Vis versionsinformation');
    Writeln('  -h, --help            Vis kommandohjælp');
    WriteLn(' --cygwin               Søg i Cygwin-mapper');
    WriteLn(' --cygwin32             Søg i 32-bit Cygwin-mapper');
    WriteLn(' --cygwin64             Søg i 64-bit Cygwin-mapper');
   End;
   _Japanese:Begin
    WriteLn('AC : Kono komando wa yūzā roguuin jikan no tōkei o hyōji shimasu.');
    WriteLn;
    Writeln('Kōbun : AC [opushon] [hito]');
    WriteLn;
    Writeln('  -a, --all-days        Subete no hi o fukumu');
    Writeln('  -d, --daily-totals    Mainichi no gōkei o insatsu');
    Writeln('  -y, --print-year      Toshi jōhō o insatsu');
    Writeln('  -p, --individual-totals Kojin no gōkei o insatsu');
    Writeln('  -f, --file <fairu>    Daitai wtmp fairu o shiyō');
    Writeln('  -z, --print-zeros     Zero entorī o insatsu');
    Writeln('  -V, --version         Bājon jōhō o hyōji');
    Writeln('  -h, --help            Komando herupu o hyōji');
    WriteLn(' --cygwin               Cygwin direktorī de kensaku');
    WriteLn(' --cygwin32             32-bitto Cygwin direktorī de kensaku');
    WriteLn(' --cygwin64             64-bitto Cygwin direktorī de kensaku');
   End;
   Else Begin
    WriteLn('AC : Cette commande permet d''afficher les statistiques ',
                  'de temps de connexions d''un utilisateur.');
    WriteLn;
    Writeln('Syntaxe : AC [options] [people]');
    WriteLn;
    Writeln('  -a, --all-days        Inclut tous les jours');
    Writeln('  -d, --daily-totals    Affiche les totaux quotidiens');
    Writeln('  -y, --print-year      Affiche les informations année');
    Writeln('  -p, --individual-totals Affiche les totaux individuels');
    Writeln('  -f, --file <fichier>  Utilise un fichier wtmp alternatif');
    Writeln('  -z, --print-zeros     Affiche les entrées nulles');
    Writeln('  -V, --version         Affiche les informations version');
    Writeln('  -h, --help            Affiche l''aide de cette commande');
    WriteLn(' --cygwin               Recherche dans les dossiers de Cygwin');
    WriteLn(' --cygwin32             Recherche dans les dossiers de Cygwin en 32 bits');
    WriteLn(' --cygwin64             Recherche dans les dossiers de Cygwin en 64 bits');
   End;
  End;
 End
  Else
 Begin
  BaseDir:='';
  DailyTotals:=False;
  PrintYear:=False;
  IndividualTotals:=False;
  AllDays:=False;
  PrintZeros:=False;
  People:='';
  i:=1;
  While i<=ParamCount do Begin
   If ParamStr(I)='--cygwin'Then Begin
    If DirExist('/cygwin')Then BaseDir:='/cygwin' Else
    If DirExist('/cygwin32')Then BaseDir:='/cygwin32' Else
    If DirExist('/cygwin64')Then BaseDir:='/cygwin64';
   End
    Else
   If ParamStr(I)='--cygwin64'Then BaseDir:='/cygwin64' Else
   If ParamStr(I)='--cygwin32'Then BaseDir:='/cygwin32' Else
   If(ParamStr(i)='-d')or(ParamStr(i)='--daily-totals')Then DailyTotals:=True Else
   If(ParamStr(i)='-y')or(ParamStr(i)='--print-year')Then PrintYear:=True Else
   If(ParamStr(i)='-p')or(ParamStr(i)='--individual-totals')Then IndividualTotals:=True Else
   If(ParamStr(i)='-f')or(ParamStr(i)='--file')Then Begin
    If i<ParamCount Then Begin
     Inc(i);
     WtmpFile := ParamStr(i);
    End;
   End
    Else
   If(ParamStr(i)='-a')or(ParamStr(i)='--all-days')Then AllDays := True Else
   If(ParamStr(i)='-z')or(ParamStr(i)='--print-zeros')Then PrintZeros := True Else
   If(ParamStr(i)='-V')or(ParamStr(i)='--version')Then begin
    Writeln('ac - 1.0 - Clone Pascal');
    Halt(0);
   End
    else
   If People=''Then People:=ParamStr(i)
    Else
   Begin
    Writeln('Param�tre inconnu: ', ParamStr(i));
    Halt(1);
   End;
   Inc(i);
  End;
  {$I-}Assign(f,BaseDir+WtmpFile);
  Reset(f,1);{$I+}
  If IOResult<>0 Then Begin
   Case Language of
    _English:WriteLn('Cannot open file ',BaseDir+WtmpFile);
    _Germany:WriteLn('Datei kann nicht geöffnet werden ',BaseDir+WtmpFile);
    _Italian:WriteLn('Impossibile aprire il file ',BaseDir+WtmpFile);
    _Spain:WriteLn('No se puede abrir el archivo ',BaseDir+WtmpFile);
    _Albanian:WriteLn('Nuk mund të hapet skedari ',BaseDir+WtmpFile);
    _Portuguese:WriteLn('Não é possível abrir o arquivo ',BaseDir+WtmpFile);
    _Swedish:WriteLn('Kan inte öppna fil ',BaseDir+WtmpFile);
    _Danish:WriteLn('Kan ikke åbne fil ',BaseDir+WtmpFile);
    _Japanese:WriteLn('Fairu o hiraku koto ga dekimasen ',BaseDir+WtmpFile);
    Else WriteLn('Impossible d''ouvrir le fichier ',BaseDir+WtmpFile);
   End;
   Halt(1);
  End;
  While Not EOF(f) do begin
   BlockRead(f,Rec,SizeOf(rec),numRead);
   If NumRead<>SizeOf(rec)Then Break;
   If People<>''Then Begin
    If(rec.ut_user=People)Then Begin
     If Not(AllDays)Then Begin
      Writeln('Utilisateur: ', rec.ut_user, ' � ',
               rec.ut_line,', h�te : ',rec.ut_host);
      WriteLn(DateTimeToStr(rec.ut_tv.tv_sec));
     End;
     Inc(userCount);
    End;
   End
    Else
   If rec.ut_type=USER_PROCESS Then Begin
    If Not(AllDays)Then Begin
     Writeln('Utilisateur: ', rec.ut_user, ' � ',
              rec.ut_line,', h�te : ',rec.ut_host);
     WriteLn(DateTimeToStr(rec.ut_tv.tv_sec));
    End;
    Inc(userCount);
   End;
  End;
  Close(f);
  If DailyTotals then Writeln('Jours totales actifs.');
  If PrintYear then Writeln('Ann�e ayant �t� affich.');
  If IndividualTotals then Writeln('Totals individuel active.');
  If AllDays then Begin
   Writeln('  total  ', userCount);
  End;
  If PrintZeros then Writeln('Affiche les nombres d''entr�es vide.');
 End;
END.
