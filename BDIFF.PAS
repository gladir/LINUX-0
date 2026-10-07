{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program BDIFF;

Uses DOS;

Const
  MaxBlockLines=64;

Type
  TLineArray=Array[1..MaxBlockLines]Of String;
  TLCSMatrix=Array[1..MaxBlockLines+1,1..MaxBlockLines+1]Of Word;

Var
  FileA,FileB:Text;
  LinesA,LinesB:TLineArray;
  LCS:TLCSMatrix;
  FileNameA,FileNameB,Argument:String;
  ChunkSize,CountA,CountB,FileLineA,FileLineB:Integer;
  ArgumentIndex,ErrorCode:Integer;
  Silent,HasChunkSize,OpenedA,OpenedB:Boolean;
  Different:Boolean;

Function IntString(Value:Integer):String;
Var
  S:String;
Begin
  Str(Value,S);
  IntString:=S;
End;

Procedure Diagnostic(Const MessageText:String);
Begin
  If Not Silent Then WriteLn(MessageText);
End;

Function ReadChunk(Var Source:Text; Var Lines:TLineArray):Integer;
Var
  Count:Integer;
Begin
  Count:=0;
  While(Count<ChunkSize)and Not EOF(Source)Do Begin
    Inc(Count);
    ReadLn(Source,Lines[Count]);
  End;
  ReadChunk:=Count;
End;

Procedure BuildLCS;
Var
  I,J:Integer;
Begin
  For I:=1 to CountA+1 Do LCS[I,CountB+1]:=0;
  For J:=1 to CountB+1 Do LCS[CountA+1,J]:=0;
  For I:=CountA downto 1 Do
    For J:=CountB downto 1 Do Begin
      If LinesA[I]=LinesB[J]Then
        LCS[I,J]:=LCS[I+1,J+1]+1
      Else If LCS[I+1,J]>=LCS[I,J+1]Then
        LCS[I,J]:=LCS[I+1,J]
      Else LCS[I,J]:=LCS[I,J+1];
    End;
End;

Function LineRange(StartLine,Count:Integer):String;
Begin
  If Count=1 Then LineRange:=IntString(StartLine)
             Else LineRange:=IntString(StartLine)+','+
                             IntString(StartLine+Count-1);
End;

Procedure PrintChange(StartA,StartB,Deleted,Inserted:Integer);
Var
  I,LocalStartA,LocalStartB:Integer;
Begin
  LocalStartA:=StartA-FileLineA+1;
  LocalStartB:=StartB-FileLineB+1;
  If Deleted=0 Then
    WriteLn(StartA-1,'a',LineRange(StartB,Inserted))
  Else If Inserted=0 Then
    WriteLn(LineRange(StartA,Deleted),'d',StartB-1)
  Else
    WriteLn(LineRange(StartA,Deleted),'c',LineRange(StartB,Inserted));
  If Deleted>0 Then Begin
    For I:=LocalStartA to LocalStartA+Deleted-1 Do WriteLn('< ',LinesA[I]);
    If Inserted>0 Then WriteLn('---');
  End;
  If Inserted>0 Then
    For I:=LocalStartB to LocalStartB+Inserted-1 Do WriteLn('> ',LinesB[I]);
End;

Procedure CompareChunk;
Var
  I,J,StartA,StartB,Deleted,Inserted:Integer;
  TakeInsert:Boolean;
Begin
  BuildLCS;
  I:=1;
  J:=1;
  While(I<=CountA)or(J<=CountB)Do Begin
    If(I<=CountA)and(J<=CountB)and(LinesA[I]=LinesB[J])Then Begin
      Inc(I);
      Inc(J);
    End Else Begin
      StartA:=I;
      StartB:=J;
      Deleted:=0;
      Inserted:=0;
      While(I<=CountA)or(J<=CountB)Do Begin
        If(I<=CountA)and(J<=CountB)and(LinesA[I]=LinesB[J])Then Break;
        TakeInsert:=False;
        If I>CountA Then TakeInsert:=True Else
        If J<=CountB Then TakeInsert:=LCS[I,J+1]>=LCS[I+1,J];
        If TakeInsert Then Begin
          Inc(Inserted);
          Inc(J);
        End Else Begin
          Inc(Deleted);
          Inc(I);
        End;
      End;
      PrintChange(FileLineA+StartA-1,FileLineB+StartB-1,Deleted,Inserted);
      Different:=True;
    End;
  End;
End;

Procedure CloseFiles;
Begin
  If OpenedA Then Close(FileA);
  If OpenedB Then Close(FileB);
End;

Procedure PrintHelp;
Begin
  If Copy(GetEnv('LANGUAGE'),1,2)='EN'Then Begin
    WriteLn('BDIFF : Compare large text files in bounded line blocks.');
    WriteLn('Syntax: bdiff file1 file2 [n] [-s]');
    WriteLn(' n  Maximum number of lines compared per block (1..64)');
    WriteLn(' -s Suppress diagnostics');
  End Else Begin
    WriteLn('BDIFF : Cette commande permet de comparer de grands fichiers texte par blocs de lignes.');
    WriteLn;
    WriteLn('Syntaxe : bdiff fichier1 fichier2 [n] [-s]');
    WriteLn;
    WriteLn(' n  Nombre maximal de lignes comparees par bloc (1 a 64)');
    WriteLn(' -s Supprime les diagnostics');
  End;
End;

BEGIN
  If ParamCount=0 Then Begin
    PrintHelp;
    Halt(2);
  End;
  FileNameA:='';
  FileNameB:='';
  ChunkSize:=64;
  HasChunkSize:=False;
  Silent:=False;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')or
      (Argument='/h')or(Argument='/H')Then Begin
      PrintHelp;
      Halt(0);
    End Else If(Argument='--version')or(Argument='-v')Then Begin
      WriteLn('bdiff (LINUX-0) 1.0');
      Halt(0);
    End Else If(Argument='-s')or(Argument='--silent')Then
      Silent:=True
    Else If(Length(Argument)>1)and(Argument[1]='-')Then Begin
      Diagnostic('Erreur : option inconnue : '+Argument);
      Halt(2);
    End Else If FileNameA=''Then FileNameA:=Argument Else
    If FileNameB=''Then FileNameB:=Argument Else If Not HasChunkSize Then Begin
      Val(Argument,ChunkSize,ErrorCode);
      If(ErrorCode<>0)or(ChunkSize<1)or(ChunkSize>MaxBlockLines)Then Begin
        Diagnostic('Erreur : n doit etre entre 1 et '+IntString(MaxBlockLines));
        Halt(2);
      End;
      HasChunkSize:=True;
    End Else Begin
      Diagnostic('Erreur : trop d''arguments');
      Halt(2);
    End;
    Inc(ArgumentIndex);
  End;
  If(FileNameA='')or(FileNameB='')Then Begin
    Diagnostic('Erreur : deux noms de fichiers sont requis');
    Halt(2);
  End;
  {$I-}Assign(FileA,FileNameA);
  Reset(FileA);{$I+}
  If IOResult<>0 Then Begin
    Diagnostic('Erreur : impossible de lire '+FileNameA);
    Halt(1);
  End;
  OpenedA:=True;
  {$I-}Assign(FileB,FileNameB);
  Reset(FileB);{$I+}
  If IOResult<>0 Then Begin
    Close(FileA);
    Diagnostic('Erreur : impossible de lire '+FileNameB);
    Halt(1);
  End;
  OpenedB:=True;
  FileLineA:=1;
  FileLineB:=1;
  Different:=False;
  Repeat
    CountA:=ReadChunk(FileA,LinesA);
    CountB:=ReadChunk(FileB,LinesB);
    If(CountA>0)or(CountB>0)Then Begin
      CompareChunk;
      Inc(FileLineA,CountA);
      Inc(FileLineB,CountB);
    End;
  Until(CountA=0)and(CountB=0);
  CloseFiles;
  If Different Then Halt(1);
END.
