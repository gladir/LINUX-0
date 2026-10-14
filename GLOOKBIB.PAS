{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande glookbib - Recherche dans les bibliographies
}

Program GLOOKBIB;

Uses DOS;

Const
 MaxFiles=64;
 MaxKeys=32;
 MaxKeyLength=40;
 MaxRecordLines=200;
 MinKeyLength=3;

Type
 TText=String[255];
 TKey=String[MaxKeyLength];
 TLineArray=Array[1..MaxRecordLines]Of TText;
 PLineArray=^TLineArray;

Var
 FileNames:Array[1..MaxFiles]Of TText;
 FileCount:Integer;
 IgnoreFields:TText;
 TruncLength:Integer;
 Keys:Array[1..MaxKeys]Of TKey;
 Found:Array[1..MaxKeys]Of Boolean;
 KeyCount:Integer;
 RecLines:PLineArray;
 RecCount:Integer;
 MatchCount:Integer;

Procedure ShowUsage;Begin
 WriteLn('Syntaxe: glookbib [ -v ] [ -istring ] [ -tn ] filename ...');
End;

Procedure ShowHelp;Begin
 WriteLn('GLOOKBIB : Cette commande permet d''effectuer une recherche bibliographique',
         ' dans les bases de donnees.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -v          Affiche la version');
 WriteLn('  -istring    Ignore les champs %x pour chaque lettre x de la chaine');
 WriteLn('  -tn         Tronque les mots-cles a n caracteres (defaut: 6)');
 WriteLn('  filename    Fichier(s) de bibliographie (format refer)');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure ShowVersion;Begin
 WriteLn('glookbib (clone) version 1.0');
End;

Function IsWordChar(C:Char):Boolean;Begin
 IsWordChar:=C In ['A'..'Z','a'..'z','0'..'9'];
End;

Function ToLower(C:Char):Char;Begin
 If C In ['A'..'Z']Then ToLower:=Chr(Ord(C)+32)
                   Else ToLower:=C;
End;

Function ToNumber(Const S:TText;Var N:Integer):Boolean;
Var
 Err:Integer;
Begin
 Val(S,N,Err);
 ToNumber:=(Err=0)And(N>0);
End;

Function ParseArguments:Boolean;
Var
 I:Integer;
 Arg,Opt:TText;
 Ok:Boolean;
Begin
 ParseArguments:=False;
 FileCount:=0;
 IgnoreFields:='';
 TruncLength:=6;
 I:=1;
 While I<=ParamCount Do Begin
  Arg:=ParamStr(I);
  If(Arg='/?')Or(Arg='--help')Or(Arg='-h')Or(Arg='/h')Or(Arg='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If(Length(Arg)>1)And(Arg[1]='-')Then Begin
   Case Arg[2]Of
    'v':Begin
     ShowVersion;
     Halt(0);
    End;
    'i':Begin
     If Length(Arg)>2Then IgnoreFields:=Copy(Arg,3,255)
      Else
     Begin
      Inc(I);
      If I>ParamCount Then Begin
       ShowUsage;
       Exit;
      End;
      IgnoreFields:=ParamStr(I);
     End;
    End;
    't':Begin
     If Length(Arg)>2Then Opt:=Copy(Arg,3,255)
      Else
     Begin
      Inc(I);
      If I>ParamCount Then Begin
       ShowUsage;
       Exit;
      End;
      Opt:=ParamStr(I);
     End;
     Ok:=ToNumber(Opt,TruncLength);
     If Not Ok Then Begin
      WriteLn('glookbib: valeur invalide pour -t: ',Opt);
      Exit;
     End;
     If TruncLength>MaxKeyLength Then TruncLength:=MaxKeyLength;
    End;
    Else Begin
     WriteLn('glookbib: option inconnue: ',Arg);
     ShowUsage;
     Exit;
    End;
   End;
  End
   Else
  Begin
   If FileCount>=MaxFiles Then Begin
    WriteLn('glookbib: trop de fichiers');
    Exit;
   End;
   Inc(FileCount);
   FileNames[FileCount]:=Arg;
  End;
  Inc(I);
 End;
 If FileCount=0Then Begin
  ShowUsage;
  Exit;
 End;
 ParseArguments:=True;
End;

{ Extrait le prochain mot de S a partir de Pos, tronque et en minuscules }
Function NextWord(Const S:TText;Var Pos:Integer;Var W:TKey):Boolean;
Var
 Len:Integer;
Begin
 NextWord:=False;
 While(Pos<=Length(S))And Not IsWordChar(S[Pos])Do Inc(Pos);
 If Pos>Length(S)Then Exit;
 W:='';
 Len:=0;
 While(Pos<=Length(S))And IsWordChar(S[Pos])Do Begin
  If Len<TruncLength Then Begin
   Inc(Len);
   W:=W+ToLower(S[Pos]);
  End;
  Inc(Pos);
 End;
 NextWord:=True;
End;

Procedure ParseQuery(Const Q:TText);
Var
 P,J:Integer;
 W:TKey;
 Dup:Boolean;
Begin
 KeyCount:=0;
 P:=1;
 While NextWord(Q,P,W)Do Begin
  If(Length(W)>=MinKeyLength)Or(Length(W)=TruncLength)Then Begin
   Dup:=False;
   For J:=1 to KeyCount Do If Keys[J]=W Then Dup:=True;
   If Not Dup And(KeyCount<MaxKeys)Then Begin
    Inc(KeyCount);
    Keys[KeyCount]:=W;
   End;
  End;
 End;
End;

Procedure ScanLine(Const S:TText);
Var
 P,J:Integer;
 W:TKey;
Begin
 P:=1;
 While NextWord(S,P,W)Do
  For J:=1 to KeyCount Do If Not Found[J]And(Keys[J]=W)Then Found[J]:=True;
End;

Function AllFound:Boolean;
Var
 J:Integer;
Begin
 AllFound:=False;
 For J:=1 to KeyCount Do If Not Found[J]Then Exit;
 AllFound:=True;
End;

Procedure FlushRecord;
Var
 I:Integer;
Begin
 If(RecCount>0)Then Begin
  If AllFound Then Begin
   For I:=1 to RecCount Do WriteLn(RecLines^[I]);
   WriteLn;
   Inc(MatchCount);
  End;
 End;
 RecCount:=0;
 FillChar(Found,SizeOf(Found),0);
End;

Function IsBlank(Const S:TText):Boolean;
Var
 I:Integer;
Begin
 IsBlank:=False;
 For I:=1 to Length(S)Do If Not(S[I]In[' ',#9,#13])Then Exit;
 IsBlank:=True;
End;

Procedure SearchFile(Const Name:TText);
Var
 F:Text;
 Line:TText;
 Skipping:Boolean;
Begin
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  WriteLn('glookbib: impossible d''ouvrir ',Name);
  Exit;
 End;
 RecCount:=0;
 Skipping:=False;
 FillChar(Found,SizeOf(Found),0);
 While Not EOF(F)Do Begin
  ReadLn(F,Line);
  If IsBlank(Line)Then Begin
   FlushRecord;
   Skipping:=False;
  End
   Else
  Begin
   If RecCount<MaxRecordLines Then Begin
    Inc(RecCount);
    RecLines^[RecCount]:=Line;
   End;
   { Champ %X : ignore si X est dans la liste -i; les suites heritent }
   If(Line[1]='%')And(Length(Line)>1)Then
    Skipping:=Pos(Line[2],IgnoreFields)>0
   Else If Not(Line[1]In[' ',#9])Then Skipping:=False;
   If Not Skipping Then ScanLine(Line);
  End;
 End;
 FlushRecord;
 Close(F);
End;

Procedure Prompt;Begin
 {$IFDEF FPC}
 Write(StdErr,'> ');
 {$ELSE}
 Write('> ');
 {$ENDIF}
End;

Var
 I:Integer;
 Query:TText;

BEGIN
 If Not ParseArguments Then Halt(1);
 New(RecLines);
 Prompt;
 While Not EOF(Input)Do Begin
  ReadLn(Query);
  ParseQuery(Query);
  If KeyCount>0Then Begin
   MatchCount:=0;
   For I:=1 to FileCount Do SearchFile(FileNames[I]);
   If MatchCount=0Then WriteLn('Aucune correspondance');
  End;
  Prompt;
 End;
 {$IFDEF FPC}
 WriteLn(StdErr);
 {$ELSE}
 WriteLn;
 {$ENDIF}
 Dispose(RecLines);
END.
