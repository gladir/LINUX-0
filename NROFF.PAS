{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program NROFF;

Uses DOS;

Const
 MaxLineLength = 255;
 MaxPageWidth = 80;
 MaxPageHeight = 66;

Type
 TLanguage = (_French, _English);

Var
 Language: TLanguage;
 ShowHelp: Boolean;
 EchoMode: Boolean;
 HaltAtFirstPage: Boolean;
 ReadFromStdin: Boolean;
 QuietMode: Boolean;
 InputFile: String;
 MacroName: String;
 PageNumber: Integer;
 PageList: String;
 RegisterA: Integer;
 LineSpacing: Integer;
 TerminalType: String;
 CurrentPage: Integer;
 CurrentLine: Integer;
 Buffer: String;
 I, J: Integer;
 LineCount: Integer;
 FileHandle: Text;
 CharCount: Integer;
 LineWidth: Integer;
 CurrentChar: Char;

Function StrToInt(S: String): Integer;
Var
 Result: Integer;
 I: Integer;
Begin
 Result := 0;
 For I := 1 To Length(S) Do Begin
  If S[I] in ['0'..'9'] Then
   Result := Result * 10 + Ord(S[I]) - Ord('0');
 End;
 StrToInt := Result;
End; 

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
  WriteLn('NROFF : Cette commande permet d''effectuer le formatage de documents pour ',
          'l''affichage ou l''impression.');
  WriteLn;
  WriteLn('Syntaxe : NROFF [options] [fichier]');
  WriteLn;
  WriteLn('Options :');
  WriteLn('  /?        Affiche cette aide');
  WriteLn('  --help    Affiche cette aide');
  WriteLn('  -h        Affiche cette aide');
  WriteLn('  -e        Mode echo');
  WriteLn('  -i        Lecture depuis l''entree standard');
  WriteLn('  -q        Mode silencieux');
  WriteLn('  -mNOM     Utilise le fichier de macros NOM');
  WriteLn('  -nN       Commence a la page N');
  WriteLn('  -oLISTE   Imprime les pages de la liste');
  WriteLn('  -raN      Definit le registre a');
  WriteLn('  -sN       Definit l''espacement');
  WriteLn('  -TNOM     Definit le type de terminal');
 End
 Else Begin
  WriteLn('NROFF: Document formatting for display or printing');
  WriteLn('Syntax: NROFF [options] [file]');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  /?        Display this help');
  WriteLn('  --help    Display this help');
  WriteLn('  -h        Display this help');
  WriteLn('  -e        Echo mode');
  WriteLn('  -i        Read from standard input');
  WriteLn('  -q        Quiet mode');
  WriteLn('  -mNAME    Use macro file NAME');
  WriteLn('  -nN       Start at page N');
  WriteLn('  -oLIST    Print pages in LIST');
  WriteLn('  -raN      Set register a');
  WriteLn('  -sN       Set spacing');
  WriteLn('  -TNAME    Set terminal type');
 End;
End;

Procedure ProcessLine(Var Line: String);
Var
 OutputLine: String;
 Pos: Integer;
 TabPos: Integer;
 Col: Integer;
 TabWidth: Integer;
Begin
 OutputLine := '';
 Col := 0;
 TabWidth := 8;
 
 For Pos := 1 To Length(Line) Do Begin
  If Line[Pos] = #9 Then Begin
   TabPos := ((Col Div TabWidth) + 1) * TabWidth;
   While Col < TabPos Do Begin
    OutputLine := OutputLine + ' ';
    Col := Col + 1;
   End;
  End
  Else If Line[Pos] = #10 Then Begin
   WriteLn(OutputLine);
   OutputLine := '';
   Col := 0;
  End
  Else Begin
   OutputLine := OutputLine + Line[Pos];
   Col := Col + 1;
  End;
  
  If Col >= MaxPageWidth Then Begin
   WriteLn(OutputLine);
   OutputLine := '';
   Col := 0;
  End;
 End;
 
 If OutputLine <> '' Then
  WriteLn(OutputLine);
End;

Procedure ProcessFile(FileName: String);
Var
 F: Text;
 Line: String;
 LineNum: Integer;
 PageNum: Integer;
 LinesOnPage: Integer;
 PrintPage: Boolean;
 CharPos: Integer;
Begin
 Assign(F, FileName);
 {$I-}
 Reset(F);
 {$I+}
 
 If IOResult <> 0 Then Begin
  If Language = _French Then
   WriteLn('Erreur : impossible d''ouvrir le fichier ', FileName)
  Else
   WriteLn('Error: cannot open file ', FileName);
  Exit;
 End;
 
 LineNum := 0;
 PageNum := 1;
 LinesOnPage := 0;
 
 While not EOF(F) Do Begin
  ReadLn(F, Line);
  LineNum := LineNum + 1;
  
  PrintPage := True;
  If PageList <> '' Then Begin
   PrintPage := False;
  End;
  
  If PrintPage Then Begin
   If EchoMode Then Begin
    If Language = _French Then
     WriteLn('# Ligne ', LineNum, ': ', Line)
    Else
     WriteLn('# Line ', LineNum, ': ', Line);
   End
   Else
    ProcessLine(Line);
   
   LinesOnPage := LinesOnPage + 1;
   
   If LinesOnPage >= MaxPageHeight Then Begin
    PageNum := PageNum + 1;
    LinesOnPage := 0;
    
    If HaltAtFirstPage Then Begin
     Close(F);
     Exit;
    End;
   End;
  End;
 End;
 
 Close(F);
End;

Procedure ProcessStdIn;
Var
 Line: String;
 LineNum: Integer;
 PageNum: Integer;
 LinesOnPage: Integer;
Begin
 LineNum := 0;
 PageNum := 1;
 LinesOnPage := 0;
 
 While not EOF Do Begin
  ReadLn(Line);
  LineNum := LineNum + 1;
  
  If EchoMode Then Begin
   If Language = _French Then
    WriteLn('# Ligne ', LineNum, ': ', Line)
   Else
    WriteLn('# Line ', LineNum, ': ', Line);
  End
  Else
   ProcessLine(Line);
  
  LinesOnPage := LinesOnPage + 1;
  
  If LinesOnPage >= MaxPageHeight Then Begin
   PageNum := PageNum + 1;
   LinesOnPage := 0;
   
   If HaltAtFirstPage Then
    Exit;
  End;
 End;
End;

Procedure ParseArguments;
Var
 ArgIndex: Integer;
 Arg: String;
 ArgLen: Integer;
Begin
 ShowHelp := False;
 EchoMode := False;
 HaltAtFirstPage := False;
 ReadFromStdin := False;
 QuietMode := False;
 InputFile := '';
 MacroName := '';
 PageNumber := 1;
 PageList := '';
 RegisterA := 0;
 LineSpacing := 1;
 TerminalType := 'ascii';
 
 For ArgIndex := 1 To ParamCount Do Begin
  Arg := ParamStr(ArgIndex);
  ArgLen := Length(Arg);
  
  If (Arg = '/?') or (Arg = '--help') or (Arg = '-h') or 
     (Arg = '/h') or (Arg = '/H') Then
   ShowHelp := True
  Else If Arg = '-e' Then
   EchoMode := True
  Else If Arg = '-h' Then
   HaltAtFirstPage := True
  Else If Arg = '-i' Then
   ReadFromStdin := True
  Else If Arg = '-q' Then
   QuietMode := True
  Else If (Arg[1] = '-') and (Arg[2] = 'm') and (ArgLen > 2) Then
   MacroName := Copy(Arg, 3, ArgLen - 2)
  Else If (Arg[1] = '-') and (Arg[2] = 'n') and (ArgLen > 2) Then
   PageNumber := StrToInt(Copy(Arg, 3, ArgLen - 2))
  Else If (Arg[1] = '-') and (Arg[2] = 'o') and (ArgLen > 2) Then
   PageList := Copy(Arg, 3, ArgLen - 2)
  Else If (Arg[1] = '-') and (Arg[2] = 'r') and (Arg[3] = 'a') and (ArgLen > 3) Then
   RegisterA := StrToInt(Copy(Arg, 4, ArgLen - 3))
  Else If (Arg[1] = '-') and (Arg[2] = 's') and (ArgLen > 2) Then
   LineSpacing := StrToInt(Copy(Arg, 3, ArgLen - 2))
  Else If (Arg[1] = '-') and (Arg[2] = 'T') and (ArgLen > 2) Then
   TerminalType := Copy(Arg, 3, ArgLen - 2)
  Else If (Arg[1] <> '-') and (Arg[1] <> '/') Then
   InputFile := Arg;
 End;
End;

BEGIN
 GetLanguage;
 ParseArguments;
 
 If ShowHelp Then Begin
  ShowHelpMessage;
 End
 Else Begin
  If ReadFromStdin Then
   ProcessStdIn
  Else If InputFile <> '' Then
   ProcessFile(InputFile)
  Else Begin
   If Language = _French Then
    WriteLn('Erreur : aucun fichier d''entree specifie')
   Else
    WriteLn('Error: no input file specified');
  End;
 End;
END.
