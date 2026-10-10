{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Remove empty directories)
}

Program RmDirApp;

Uses DOS;

Const
  MaxDirectories=64;
  MaxPathLength=255;

Type
  TPathName=String[MaxPathLength];
  TPathArray=Array[1..MaxDirectories]Of TPathName;

Var
  Directories:TPathArray;
  DirectoryCount,ArgumentIndex:Integer;
  ParentsMode,EndOptions,ErrorFound,English:Boolean;
  LanguageCode:String[20];
  CurrentPath:TPathName;

Function IsSeparator(Character:Char):Boolean;
Begin
  IsSeparator:=(Character='/')or(Character=#92);
End;

Function IsRootPath(Const PathName:TPathName):Boolean;
Begin
  IsRootPath:=False;
  If Length(PathName)=1 Then IsRootPath:=IsSeparator(PathName[1])
  Else If(Length(PathName)=3)and(PathName[2]=':')and
    IsSeparator(PathName[3])Then IsRootPath:=True;
End;

Function TrimTrailingSeparators(Const PathName:TPathName):TPathName;
Var
  ResultPath:TPathName;
Begin
  ResultPath:=PathName;
  While(Length(ResultPath)>1)and IsSeparator(ResultPath[Length(ResultPath)])and
    Not IsRootPath(ResultPath)Do Delete(ResultPath,Length(ResultPath),1);
  TrimTrailingSeparators:=ResultPath;
End;

Function ParentPath(Const PathName:TPathName):TPathName;
Var
  Index:Integer;
  ResultPath:TPathName;
Begin
  ResultPath:='';
  For Index:=Length(PathName) downto 1 Do
    If IsSeparator(PathName[Index])Then Begin
      If Index=1 Then ResultPath:=Copy(PathName,1,1)
      Else If(Index=3)and(PathName[2]=':')Then ResultPath:=Copy(PathName,1,3)
      Else ResultPath:=Copy(PathName,1,Index-1);
      Break;
    End;
  ParentPath:=ResultPath;
End;

Procedure ReportFailure(Const PathName:TPathName; ErrorCode:Integer);
Begin
  ErrorFound:=True;
  If English Then Begin
    Write('rmdir: cannot remove ''',PathName,''': ');
    If ErrorCode=3 Then WriteLn('path not found')
    Else If ErrorCode=5 Then WriteLn('access denied or directory is not empty')
    Else If ErrorCode=16 Then WriteLn('directory cannot be removed')
    Else WriteLn('DOS error ',ErrorCode);
  End Else Begin
    Write('rmdir : impossible de supprimer ''',PathName,''': ');
    If ErrorCode=3 Then WriteLn('chemin introuvable')
    Else If ErrorCode=5 Then WriteLn('acces refuse ou repertoire non vide')
    Else If ErrorCode=16 Then WriteLn('repertoire impossible a supprimer')
    Else WriteLn('erreur DOS ',ErrorCode);
  End;
End;

Function RemoveOne(Const PathName:TPathName):Boolean;
Var
  ErrorCode:Integer;
Begin
  If IsRootPath(PathName)Then Begin
    If English Then WriteLn('rmdir: refusing to remove root directory: ',PathName)
    Else WriteLn('rmdir : refus de supprimer la racine : ',PathName);
    RemoveOne:=False;
    ErrorFound:=True;
    Exit;
  End;
  {$I-}RmDir(PathName);{$I+}
  ErrorCode:=IOResult;
  RemoveOne:=ErrorCode=0;
  If ErrorCode<>0 Then ReportFailure(PathName,ErrorCode);
End;

Procedure RemoveDirectory(Const OriginalPath:TPathName);
Var
  PathName,NextParent:TPathName;
Begin
  PathName:=TrimTrailingSeparators(OriginalPath);
  If PathName=''Then Begin
    If English Then WriteLn('rmdir: empty directory name')
    Else WriteLn('rmdir : nom de repertoire vide');
    ErrorFound:=True;
    Exit;
  End;
  Repeat
    If Not RemoveOne(PathName)Then Exit;
    If Not ParentsMode Then Exit;
    NextParent:=ParentPath(PathName);
    If(NextParent='')or IsRootPath(NextParent)Then Exit;
    PathName:=NextParent;
  Until False;
End;

Procedure PrintHelp;
Begin
  If English Then Begin
    WriteLn('rmdir - remove empty directories');
    WriteLn('Usage: rmdir [-p|--parents] [--help] [--version] dir ...');
    WriteLn(' -p, --parents  Remove parent directories when they become empty');
  End Else Begin
    WriteLn('RMDIR - Cette commande permet d''enlever un ou plusieurs rep'+#130+'rtoires vides');
    WriteLn;
    WriteLn('Syntaxe : rmdir [-p|--parents] [--help] [--version] repertoire ...');
    WriteLn;
    WriteLn(' -p, --parents   Supprimer aussi les rep'+#130+'rtoires parents devenus vides');
    WriteLn(' -h, --help      Affiche ce message d''aide');
    WriteLn(' -V, --version   Affiche la version de la commande');
    WriteLn(' repertoire ...  Indiquer les r'+#130+'pertoires a supprimer');
  End;
End;

Procedure ParseArguments;
Var
  Argument:TPathName;
Begin
  DirectoryCount:=0;
  ParentsMode:=False;
  EndOptions:=False;
  ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If Not EndOptions and(Argument='--')Then EndOptions:=True
    Else If Not EndOptions and((Argument='--help')or(Argument='-?')or
      (Argument='/?')or(Argument='-h')or(Argument='/h')or(Argument='/H'))Then Begin
      PrintHelp;
      Halt(0);
    End Else If Not EndOptions and((Argument='--version')or(Argument='-V'))Then Begin
      WriteLn('rmdir (LINUX-0) 1.0');
      Halt(0);
    End Else If Not EndOptions and((Argument='-p')or(Argument='--parents'))Then
      ParentsMode:=True
    Else If Not EndOptions and(Length(Argument)>1)and(Argument[1]='-')Then Begin
      If English Then WriteLn('rmdir: unknown option ',Argument)
      Else WriteLn('rmdir : option inconnue ',Argument);
      Halt(2);
    End Else Begin
      If DirectoryCount>=MaxDirectories Then Begin
        If English Then WriteLn('rmdir: too many directories')
        Else WriteLn('rmdir : trop de repertoires');
        Halt(2);
      End;
      Inc(DirectoryCount);
      Directories[DirectoryCount]:=Argument;
    End;
    Inc(ArgumentIndex);
  End;
  If DirectoryCount=0 Then Begin
    If English Then WriteLn('Usage: rmdir [-p|--parents] dir ...')
    Else WriteLn('Syntaxe : rmdir [-p|--parents] repertoire ...');
    Halt(2);
  End;
End;

Var
  Index:Integer;
Begin
  LanguageCode:=GetEnv('LANGUAGE');
  English:=Copy(LanguageCode,1,2)='EN';
  ErrorFound:=False;
  ParseArguments;
  For Index:=1 to DirectoryCount Do Begin
    CurrentPath:=Directories[Index];
    RemoveDirectory(CurrentPath);
  End;
  If ErrorFound Then Halt(1);
END.
