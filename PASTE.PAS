{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program PASTE;

Uses DOS;

Const
 MaxFiles = 100;
 MaxLineLength = 4096;
 VersionStr = '1.0';

Type
 TLanguage = (_French, _English);

Var
 Language: TLanguage;
 ShowHelp: Boolean;
 ShowVersion: Boolean;
 SerialMode: Boolean;
 DelimiterList: String;
 FileCount: Integer;
 FileNames: Array[1..MaxFiles] of String;
 I, J: Integer;
 Arg: String;
 ArgLen: Integer;
 ArgIndex: Integer;
 FileIndex: Integer;
 CurrentDelim: Char;
 DelimIndex: Integer;

Procedure GetLanguage;
Var
 LangEnv: String;
Begin
 LangEnv := GetEnv('LANGUAGE');
 If (LangEnv = 'EN') or (LangEnv = 'en') Then
  Language := _English
 Else
  Language := _French;
End;

Procedure ShowHelpMessage;
Begin
 If Language = _French Then Begin
  WriteLn('PASTE : Cette commande permet de fusionner les lignes des fichiers');
  WriteLn('Syntaxe : PASTE [options] [fichier...]');
  WriteLn('');
  WriteLn('Options :');
  WriteLn('  /?               Affiche cette aide');
  WriteLn('  --help           Affiche cette aide');
  WriteLn('  -h               Affiche cette aide');
  WriteLn('  -s               Mode serie (fusionner les lignes d''un fichier)');
  WriteLn('  --serial         Mode serie');
  WriteLn('  -d DELIM         Specifier les delimiteurs');
  WriteLn('  --delimiters=DEL Specifier les delimiteurs');
  WriteLn('  --version        Affiche la version');
 End
 Else Begin
  WriteLn('PASTE: Merge lines of files');
  WriteLn('Syntax: PASTE [options] [file...]');
  WriteLn('');
  WriteLn('Options:');
  WriteLn('  /?               Display this help');
  WriteLn('  --help           Display this help');
  WriteLn('  -h               Display this help');
  WriteLn('  -s               Serial mode (merge lines from one file)');
  WriteLn('  --serial         Serial mode');
  WriteLn('  -d DELIM         Specify delimiters');
  WriteLn('  --delimiters=DEL Specify delimiters');
  WriteLn('  --version        Display version');
 End;
End;

Procedure ShowVersionMessage;
Begin
 WriteLn('PASTE version ', VersionStr);
End;

Procedure ParseArguments;
Var
 Index: Integer;
 EqualPos: Integer;
Begin
 ShowHelp := False;
 ShowVersion := False;
 SerialMode := False;
 DelimiterList := #9;
 FileCount := 0;
 
 Index := 1;
 While Index <= ParamCount Do Begin
  Arg := ParamStr(Index);
  ArgLen := Length(Arg);
  
  If (Arg = '/?') or (Arg = '--help') or (Arg = '-h') or 
     (Arg = '/h') or (Arg = '/H') Then
   ShowHelp := True
  Else If Arg = '--version' Then
   ShowVersion := True
  Else If (Arg = '-s') or (Arg = '--serial') Then
   SerialMode := True
  Else If Arg = '-d' Then Begin
   Index := Index + 1;
   If Index <= ParamCount Then
    DelimiterList := ParamStr(Index);
  End
  Else If (Length(Arg) > 12) and (Copy(Arg, 1, 12) = '--delimiters=') Then
   DelimiterList := Copy(Arg, 13, ArgLen - 12)
  Else If (Arg[1] <> '-') and (Arg[1] <> '/') Then Begin
   FileCount := FileCount + 1;
   If FileCount <= MaxFiles Then
    FileNames[FileCount] := Arg;
  End;
  
  Index := Index + 1;
 End;
End;

Procedure PasteSerialMode;
Var
 FileHandle: Text;
 Line: String;
 First: Boolean;
 FileIdx: Integer;
 ErrorCode: Integer;
Begin
 For FileIdx := 1 To FileCount Do Begin
  Assign(FileHandle, FileNames[FileIdx]);
  {$I-}
  Reset(FileHandle);
  {$I+}
  ErrorCode := IOResult;
  
  If ErrorCode = 0 Then Begin
   First := True;
   While not EOF(FileHandle) Do Begin
    ReadLn(FileHandle, Line);
    If not First Then
     Write(#9);
    Write(Line);
    First := False;
   End;
   WriteLn;
   Close(FileHandle);
  End
  Else Begin
   If Language = _French Then
    WriteLn('Erreur : impossible d''ouvrir le fichier ', FileNames[FileIdx])
   Else
    WriteLn('Error: cannot open file ', FileNames[FileIdx]);
  End;
 End;
End;

Procedure PasteParallelMode;
Var
 FileHandles: Array[1..MaxFiles] of Text;
 Lines: Array[1..MaxFiles] of String;
 FileEOF: Array[1..MaxFiles] of Boolean;
 AnyFileNotEOF: Boolean;
 FileIdx: Integer;
 ErrorCode: Integer;
 DelimIdx: Integer;
 OutputLine: String;
Begin
 For FileIdx := 1 To FileCount Do Begin
  Assign(FileHandles[FileIdx], FileNames[FileIdx]);
  {$I-}
  Reset(FileHandles[FileIdx]);
  {$I+}
  ErrorCode := IOResult;
  
  If ErrorCode <> 0 Then Begin
   If Language = _French Then
    WriteLn('Erreur : impossible d''ouvrir le fichier ', FileNames[FileIdx])
   Else
    WriteLn('Error: cannot open file ', FileNames[FileIdx]);
   FileEOF[FileIdx] := True;
  End
  Else
   FileEOF[FileIdx] := EOF(FileHandles[FileIdx]);
 End;
 
 While True Do Begin
  AnyFileNotEOF := False;
  OutputLine := '';
  
  For FileIdx := 1 To FileCount Do Begin
   If FileEOF[FileIdx] Then
    Lines[FileIdx] := ''
   Else Begin
    ReadLn(FileHandles[FileIdx], Lines[FileIdx]);
    If EOF(FileHandles[FileIdx]) Then
     FileEOF[FileIdx] := True;
    AnyFileNotEOF := True;
   End;
  End;
  
  If not AnyFileNotEOF Then
   Break;
  
  For FileIdx := 1 To FileCount Do Begin
   If FileIdx > 1 Then Begin
    DelimIdx := ((FileIdx - 2) mod Length(DelimiterList)) + 1;
    If DelimIdx > Length(DelimiterList) Then
     DelimIdx := Length(DelimiterList);
    OutputLine := OutputLine + DelimiterList[DelimIdx];
   End;
   OutputLine := OutputLine + Lines[FileIdx];
  End;
  
  WriteLn(OutputLine);
 End;
 
 For FileIdx := 1 To FileCount Do Begin
  If not FileEOF[FileIdx] Then
   Close(FileHandles[FileIdx]);
 End;
End;

Procedure ProcessStdIn;
Var
 Line: String;
 First: Boolean;
Begin
 First := True;
 While not EOF Do Begin
  ReadLn(Line);
  If not First Then
   Write(#9);
  Write(Line);
  First := False;
 End;
 WriteLn;
End;

BEGIN
 GetLanguage;
 ParseArguments;
 
 If ShowHelp Then Begin
  ShowHelpMessage;
 End
 Else If ShowVersion Then Begin
  ShowVersionMessage;
 End
 Else Begin
  If FileCount = 0 Then Begin
   If SerialMode Then
    ProcessStdIn
   Else Begin
    If Language = _French Then
     WriteLn('Erreur : aucun fichier specifie')
    Else
     WriteLn('Error: no file specified');
   End;
  End
  Else Begin
   If SerialMode Then
    PasteSerialMode
   Else
    PasteParallelMode;
  End;
 End;
END.
