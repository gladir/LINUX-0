{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program CMP;

Uses DOS;

Var
  FileA,FileB:File;
  FileNameA,FileNameB,Argument,OptionValue,LanguageCode:String;
  SkipA,SkipB,ByteLimit,ComparedBytes,ByteNumber,LineNumber:LongInt;
  ByteA,ByteB:Byte;
  ReadCountA,ReadCountB:Word;
  PrintBytes,ListMode,QuietMode,LimitSet,Different:Boolean;
  FileAOpen,FileBOpen,EndOptions:Boolean;
  ArgumentIndex,ColonPosition,ErrorCode:Integer;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('CMP : Compare two files byte by byte.');
    WriteLn('Syntax: cmp [-b] [-i SKIP1:SKIP2] [-l] [-n LIMIT] [-s] FILE1 FILE2');
    WriteLn(' -b, --print-bytes  Show differing byte values');
    WriteLn(' -i, --ignore-initial N[:M]  Skip bytes in the input files');
    WriteLn(' -l, --verbose      List every differing byte');
    WriteLn(' -n, --bytes LIMIT  Compare no more than LIMIT bytes');
    WriteLn(' -s, --quiet, --silent  Suppress normal output');
    WriteLn(' -v, --version      Display version');
    WriteLn(' --help             Display this help');
  End Else Begin
    WriteLn('CMP : Cette commande permet de comparer deux fichiers octet par octet.');
    WriteLn;
    WriteLn('Syntaxe : cmp [-b] [-i SAUT1:SAUT2] [-l] [-n LIMITE] [-s] FICHIER1 FICHIER2');
    WriteLn;
    WriteLn(' -b, --print-bytes  Afficher les valeurs des octets differents');
    WriteLn(' -i, --ignore-initial N[:M]  Sauter des octets dans les fichiers');
    WriteLn(' -l, --verbose      Lister tous les octets differents');
    WriteLn(' -n, --bytes LIMITE Comparer au plus LIMITE octets');
    WriteLn(' -s, --quiet, --silent  Supprimer les sorties normales');
    WriteLn(' -v, --version      Afficher la version');
    WriteLn(' --help             Afficher cette aide');
  End;
End;

Procedure UsageError(Const MessageFrench,MessageEnglish:String);
Begin
  If Copy(LanguageCode,1,2)='EN'Then WriteLn('cmp: ',MessageEnglish)
  Else WriteLn('cmp : ',MessageFrench);
  Halt(2);
End;

Function ParseCount(Const TextValue:String; Var Value:LongInt):Boolean;
Var
  Position,Digit:Integer;
  CurrentValue:LongInt;
Begin
  ParseCount:=False;
  If TextValue=''Then Exit;
  CurrentValue:=0;
  For Position:=1 to Length(TextValue)Do Begin
    If Not(TextValue[Position]in['0'..'9'])Then Exit;
    Digit:=Ord(TextValue[Position])-Ord('0');
    If CurrentValue>214748364 Then Exit;
    If(CurrentValue=214748364)and(Digit>7)Then Exit;
    CurrentValue:=CurrentValue*10+Digit;
  End;
  Value:=CurrentValue;
  ParseCount:=True;
End;

Procedure ParseIgnoreInitial(Const TextValue:String);
Var
  FirstValue,SecondValue:LongInt;
Begin
  ColonPosition:=Pos(':',TextValue);
  If ColonPosition=0 Then Begin
    If Not ParseCount(TextValue,FirstValue)Then
      UsageError('valeur invalide pour -i','invalid value for -i');
    SkipA:=FirstValue;
    SkipB:=FirstValue;
  End Else Begin
    If Pos(':',Copy(TextValue,ColonPosition+1,255))>0 Then
      UsageError('valeur invalide pour -i','invalid value for -i');
    If Not ParseCount(Copy(TextValue,1,ColonPosition-1),FirstValue)or
      Not ParseCount(Copy(TextValue,ColonPosition+1,255),SecondValue)Then
      UsageError('valeur invalide pour -i','invalid value for -i');
    SkipA:=FirstValue;
    SkipB:=SecondValue;
  End;
End;

Procedure ReadOptionValue(Const OptionName:String; Var Index:Integer;
                          Const Current:String; Var Value:String);
Begin
  If Current<>''Then Value:=Current Else Begin
    Inc(Index);
    If Index>ParamCount Then
      UsageError('valeur manquante pour '+OptionName,
                 'missing value for '+OptionName);
    Value:=ParamStr(Index);
  End;
End;

Function OctalText(Value:Byte):String;
Var
  TextValue:String;
Begin
  Str(Value,TextValue);
  TextValue:='';
  Repeat
    TextValue:=Chr(Ord('0')+(Value mod 8))+TextValue;
    Value:=Value div 8;
  Until Value=0;
  While Length(TextValue)<3 Do TextValue:='0'+TextValue;
  OctalText:=TextValue;
End;

Function PrintableByte(Value:Byte):String;
Begin
  If(Value>=32)and(Value<=126)Then
    PrintableByte:=Chr(39)+Chr(Value)+Chr(39)
  Else PrintableByte:='?';
End;

Procedure PrintDifference;
Begin
  If QuietMode Then Exit;
  Different:=True;
  If ListMode Then Begin
    WriteLn(ByteNumber:8,' ',OctalText(ByteA),' ',OctalText(ByteB));
  End Else Begin
    Write(FileNameA,' ',FileNameB,' differ: byte ',ByteNumber,
          ', line ',LineNumber);
    If PrintBytes Then
      Write(' is ',OctalText(ByteA),' ',PrintableByte(ByteA),' ',
            OctalText(ByteB),' ',PrintableByte(ByteB));
    WriteLn;
  End;
End;

Procedure ReportEOF(Const FileName:String);
Begin
  Different:=True;
  If Not QuietMode Then
    WriteLn('cmp: EOF on ',FileName,' after byte ',ComparedBytes,
            ', in line ',LineNumber);
End;

Procedure CompareFiles;
Var
  HasByteA,HasByteB:Boolean;
Begin
  Different:=False;
  ComparedBytes:=0;
  ByteNumber:=0;
  LineNumber:=1;
  If SkipA<FileSize(FileA)Then Seek(FileA,SkipA)
  Else Seek(FileA,FileSize(FileA));
  If SkipB<FileSize(FileB)Then Seek(FileB,SkipB)
  Else Seek(FileB,FileSize(FileB));

  While Not LimitSet or(ComparedBytes<ByteLimit)Do Begin
    BlockRead(FileA,ByteA,1,ReadCountA);
    BlockRead(FileB,ByteB,1,ReadCountB);
    HasByteA:=ReadCountA=1;
    HasByteB:=ReadCountB=1;
    If Not HasByteA and Not HasByteB Then Break;
    If Not HasByteA Then Begin
      ReportEOF(FileNameA);
      Break;
    End;
    If Not HasByteB Then Begin
      ReportEOF(FileNameB);
      Break;
    End;
    Inc(ComparedBytes);
    Inc(ByteNumber);
    If ByteA<>ByteB Then Begin
      Different:=True;
      If ListMode Then Begin
        If Not QuietMode Then
          WriteLn(ByteNumber:8,' ',OctalText(ByteA),' ',OctalText(ByteB));
      End Else Begin
        PrintDifference;
        Break;
      End;
    End;
    If ByteA=10 Then Inc(LineNumber);
  End;
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  FileNameA:='';
  FileNameB:='';
  SkipA:=0;
  SkipB:=0;
  ByteLimit:=0;
  LimitSet:=False;
  PrintBytes:=False;
  ListMode:=False;
  QuietMode:=False;
  FileAOpen:=False;
  FileBOpen:=False;
  EndOptions:=False;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If Not EndOptions and(Argument='--')Then EndOptions:=True Else
    If Not EndOptions and(Argument='--help')Then Begin
      PrintHelp;
      Halt(0);
    End Else If Not EndOptions and
      ((Argument='--version')or(Argument='-v'))Then Begin
      WriteLn('cmp (LINUX-0) 1.0');
      Halt(0);
    End Else If Not EndOptions and
      ((Argument='-b')or(Argument='--print-bytes'))Then PrintBytes:=True Else
    If Not EndOptions and
      ((Argument='-l')or(Argument='--verbose'))Then ListMode:=True Else
    If Not EndOptions and
      ((Argument='-s')or(Argument='--silent')or
       (Argument='--quiet'))Then QuietMode:=True Else
    If Not EndOptions and((Argument='-i')or
      (Argument='--ignore-initial'))Then Begin
      ReadOptionValue(Argument,ArgumentIndex,'',OptionValue);
      ParseIgnoreInitial(OptionValue);
    End Else If Not EndOptions and(Argument='--bytes')Then Begin
      ReadOptionValue(Argument,ArgumentIndex,'',OptionValue);
      If Not ParseCount(OptionValue,ByteLimit)Then
        UsageError('limite invalide','invalid byte limit');
      LimitSet:=True;
    End Else If Not EndOptions and(Argument='-n')Then Begin
      ReadOptionValue(Argument,ArgumentIndex,'',OptionValue);
      If Not ParseCount(OptionValue,ByteLimit)Then
        UsageError('limite invalide','invalid byte limit');
      LimitSet:=True;
    End Else If Not EndOptions and(Length(Argument)>2)and
      (Copy(Argument,1,2)='-i')Then Begin
      OptionValue:=Copy(Argument,3,255);
      If(Length(OptionValue)>0)and(OptionValue[1]='=')Then
        Delete(OptionValue,1,1);
      ParseIgnoreInitial(OptionValue);
    End Else If Not EndOptions and(Length(Argument)>2)and
      (Copy(Argument,1,2)='-n')Then Begin
      OptionValue:=Copy(Argument,3,255);
      If(Length(OptionValue)>0)and(OptionValue[1]='=')Then
        Delete(OptionValue,1,1);
      If Not ParseCount(OptionValue,ByteLimit)Then
        UsageError('limite invalide','invalid byte limit');
      LimitSet:=True;
    End Else If Not EndOptions and(Length(Argument)>8)and
      (Copy(Argument,1,8)='--bytes=')Then Begin
      OptionValue:=Copy(Argument,9,255);
      If Not ParseCount(OptionValue,ByteLimit)Then
        UsageError('limite invalide','invalid byte limit');
      LimitSet:=True;
    End Else If Not EndOptions and(Length(Argument)>17)and
      (Copy(Argument,1,17)='--ignore-initial=')Then Begin
      OptionValue:=Copy(Argument,18,255);
      ParseIgnoreInitial(OptionValue);
    End Else If Not EndOptions and(Length(Argument)>1)and
      (Argument[1]='-')Then Begin
      If(Length(Argument)>2)and(Argument[1]='-')Then
        UsageError('option inconnue : '+Argument,'unknown option: '+Argument);
      For ErrorCode:=2 to Length(Argument)Do Begin
        If Argument[ErrorCode]='b'Then PrintBytes:=True Else
        If Argument[ErrorCode]='l'Then ListMode:=True Else
        If Argument[ErrorCode]='s'Then QuietMode:=True Else
          UsageError('option inconnue : '+Argument,'unknown option: '+Argument);
      End;
    End Else If FileNameA=''Then FileNameA:=Argument Else
    If FileNameB=''Then FileNameB:=Argument Else
      UsageError('trop de noms de fichiers','too many file names');
    Inc(ArgumentIndex);
  End;

  If(FileNameA='')or(FileNameB='')Then Begin
    PrintHelp;
    Halt(2);
  End;
  Assign(FileA,FileNameA);
  FileMode:=0;
  {$I-}Reset(FileA,1);{$I+}
  If IOResult<>0 Then Begin
    WriteLn('cmp: ',FileNameA,': impossible de lire le fichier');
    Halt(2);
  End;
  FileAOpen:=True;
  Assign(FileB,FileNameB);
  FileMode:=0;
  {$I-}Reset(FileB,1);{$I+}
  If IOResult<>0 Then Begin
    Close(FileA);
    WriteLn('cmp: ',FileNameB,': impossible de lire le fichier');
    Halt(2);
  End;
  FileBOpen:=True;
  CompareFiles;
  If FileBOpen Then Close(FileB);
  If FileAOpen Then Close(FileA);
  If Different Then Halt(1);
END.