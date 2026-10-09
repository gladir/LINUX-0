{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program DIRCMP;

Uses DOS;

Const
  CompareBufferSize=2048;

Type
  TName=String[127];
  PNameNode=^TNameNode;
  TNameNode=Record
    Name:TName;
    Seen:Boolean;
    Next:PNameNode;
  End;
  TNameList=Record
    First,Last:PNameNode;
    Count:LongInt;
  End;
  TCompareBuffer=Array[0..CompareBufferSize-1]Of Byte;

Var
  DirectoryOne,DirectoryTwo:String;
  NamesOne,NamesTwo:TNameList;
  WidthValue,ErrorCode:Integer;
  Argument:String;
  DifferenceOnly,SuppressSame,ErrorFound:Boolean;
  ArgumentIndex:Integer;
  LanguageCode:String;

Procedure UsageError(Const MessageText:String);
Begin
  WriteLn('dircmp: ',MessageText);
  Halt(2);
End;

Procedure PrintHelp;
Begin
  If Copy(LanguageCode,1,2)='EN'Then Begin
    WriteLn('DIRCMP : Compare the files in two directories.');
    WriteLn('Syntax: dircmp [-d] [-s] [-w width] directory1 directory2');
    WriteLn(' -d       Display only entries that differ');
    WriteLn(' -s       Suppress entries for identical files');
    WriteLn(' -w N     Set the displayed file-name width');
    WriteLn('Files are compared byte-for-byte; subdirectories are not traversed.');
  End Else Begin
    WriteLn('DIRCMP : Cette commande permet de comparer les fichiers de deux r'+#130+'pertoires.');
    WriteLn;
    WriteLn('Syntaxe : dircmp [-d] [-s] [-w largeur] repertoire1 repertoire2');
    WriteLn;
    WriteLn(' -d       Afficher seulement les entrees differentes');
    WriteLn(' -s       Cacher les fichiers identiques');
    WriteLn(' -w N     Definir la largeur du nom affiche');
    WriteLn;
    WriteLn('Les fichiers sont compares octet par octet, sans parcours recursif.');
  End;
End;

Procedure ReportError(Const MessageText:String);
Begin
  If Copy(LanguageCode,1,2)='EN'Then WriteLn('dircmp: ',MessageText)
  Else WriteLn('dircmp : ',MessageText);
  ErrorFound:=True;
End;

Procedure OptionError(Const MessageText:String);
Begin
  WriteLn('dircmp: ',MessageText);
  Halt(2);
End;

Function DirectorySeparator(Const Path:String):Char;
Begin
  If(Pos('/',Path)>0)and(Pos('\',Path)=0)Then DirectorySeparator:='/'
  Else DirectorySeparator:='\';
End;

Function JoinPath(Const DirectoryName,BaseName:String):String;
Var
  Separator:Char;
Begin
  Separator:=DirectorySeparator(DirectoryName);
  If(DirectoryName<>'')and(DirectoryName[Length(DirectoryName)]in['\','/'])Then
    JoinPath:=DirectoryName+BaseName
  Else JoinPath:=DirectoryName+Separator+BaseName;
End;

Procedure InitializeNameList(Var Names:TNameList);
Begin
  Names.First:=Nil;
  Names.Last:=Nil;
  Names.Count:=0;
End;

Procedure AppendName(Var Names:TNameList; Const Name:String);
Var
  NewNode:PNameNode;
Begin
  New(NewNode);
  NewNode^.Name:=Name;
  NewNode^.Seen:=False;
  NewNode^.Next:=Nil;
  If Names.Last=Nil Then Names.First:=NewNode
  Else Names.Last^.Next:=NewNode;
  Names.Last:=NewNode;
  Inc(Names.Count);
End;

Procedure FreeNameList(Var Names:TNameList);
Var
  Node,NextNode:PNameNode;
Begin
  Node:=Names.First;
  While Node<>Nil Do Begin
    NextNode:=Node^.Next;
    Dispose(Node);
    Node:=NextNode;
  End;
  InitializeNameList(Names);
End;

Procedure ReadDirectory(Const DirectoryName:String; Var Names:TNameList);
Var
  Entry:SearchRec;
  Pattern:String;
Begin
  InitializeNameList(Names);
  Pattern:=JoinPath(DirectoryName,'*.*');
  FindFirst(Pattern,AnyFile,Entry);
  If DosError<>0Then Begin
    If Copy(LanguageCode,1,2)='EN'Then ReportError('cannot read directory '+DirectoryName)
    Else ReportError('impossible de lire le repertoire '+DirectoryName);
    Exit;
  End;
  While DosError=0 Do Begin
    If(Entry.Name<>'.')and(Entry.Name<>'..')and
      ((Entry.Attr and Directory)=0)Then Begin
      AppendName(Names,Entry.Name);
    End;
    FindNext(Entry);
  End;
  {$IFDEF FPC}FindClose(Entry);{$ENDIF}
End;

Function EqualName(Const FirstName,SecondName:String):Boolean;
Var
  Index:Integer;
  FirstChar,SecondChar:Char;
Begin
  EqualName:=False;
  If Length(FirstName)<>Length(SecondName)Then Exit;
  For Index:=1 to Length(FirstName)Do Begin
    FirstChar:=FirstName[Index];
    SecondChar:=SecondName[Index];
    If FirstChar in['A'..'Z']Then FirstChar:=Chr(Ord(FirstChar)+32);
    If SecondChar in['A'..'Z']Then SecondChar:=Chr(Ord(SecondChar)+32);
    If FirstChar<>SecondChar Then Exit;
  End;
  EqualName:=True;
End;

Function FindName(Const Name:String; Var Names:TNameList):PNameNode;
Var
  Node:PNameNode;
Begin
  FindName:=Nil;
  Node:=Names.First;
  While Node<>Nil Do Begin
    If EqualName(Name,Node^.Name)Then Begin
      FindName:=Node;
      Exit;
    End;
    Node:=Node^.Next;
  End;
End;

Function CompareFiles(Const NameOne,NameTwo:String):Integer;
Var
  FileOne,FileTwo:File;
  BufferOne,BufferTwo:TCompareBuffer;
  CountReadOne,CountReadTwo:Word;
  Index:Integer;
  ReadError:Integer;
  Different:Boolean;
Begin
  CompareFiles:=2;
  Assign(FileOne,NameOne);Assign(FileTwo,NameTwo);
  FileMode:=0;
  {$I-}Reset(FileOne,1);{$I+}
  ReadError:=IOResult;
  If ReadError<>0 Then Exit;
  {$I-}Reset(FileTwo,1);{$I+}
  ReadError:=IOResult;
  If ReadError<>0 Then Begin Close(FileOne);Exit;End;
  If FileSize(FileOne)<>FileSize(FileTwo)Then Begin
    CompareFiles:=1;
    Close(FileTwo);Close(FileOne);
    Exit;
  End;
  CompareFiles:=0;
  Different:=False;
  Repeat
    BlockRead(FileOne,BufferOne,SizeOf(BufferOne),CountReadOne);
    BlockRead(FileTwo,BufferTwo,SizeOf(BufferTwo),CountReadTwo);
    If CountReadOne<>CountReadTwo Then Begin Different:=True;Break;End;
    If CountReadOne=0 Then Break;
    For Index:=0 to CountReadOne-1 Do
      If BufferOne[Index]<>BufferTwo[Index]Then Begin Different:=True;Break;End;
    If Different Then Break;
  Until False;
  If Different Then CompareFiles:=1;
  Close(FileTwo);Close(FileOne);
End;

Function PadName(Const Name:String):String;
Var
  ResultValue:String;
Begin
  ResultValue:=Name;
  While Length(ResultValue)<WidthValue Do ResultValue:=ResultValue+' ';
  PadName:=ResultValue;
End;

Procedure DisplayResult(Const Marker,Name:String);
Begin
  If DifferenceOnly and(Marker='=')Then Exit;
  If SuppressSame and(Marker='=')Then Exit;
  WriteLn(Marker,' ',PadName(Name));
End;

Procedure CompareDirectories;
Var
  NodeOne,NodeTwo:PNameNode;
  CompareResult:Integer;
  FileOne,FileTwo:String;
Begin
  ReadDirectory(DirectoryOne,NamesOne);
  ReadDirectory(DirectoryTwo,NamesTwo);
  If ErrorFound Then Begin FreeNameList(NamesOne);FreeNameList(NamesTwo);Exit;End;
  NodeOne:=NamesOne.First;
  While NodeOne<>Nil Do Begin
    NodeTwo:=FindName(NodeOne^.Name,NamesTwo);
    If NodeTwo=Nil Then DisplayResult('<',NodeOne^.Name)
    Else Begin
      NodeTwo^.Seen:=True;
      FileOne:=JoinPath(DirectoryOne,NodeOne^.Name);
      FileTwo:=JoinPath(DirectoryTwo,NodeTwo^.Name);
      CompareResult:=CompareFiles(FileOne, FileTwo);
      If CompareResult=0 Then DisplayResult('=',NodeOne^.Name)
      Else If CompareResult=1 Then DisplayResult('!',NodeOne^.Name)
      Else Begin
        ReportError('impossible de comparer '+NodeOne^.Name);
        DisplayResult('!',NodeOne^.Name);
      End;
    End;
    NodeOne:=NodeOne^.Next;
  End;
  NodeTwo:=NamesTwo.First;
  While NodeTwo<>Nil Do Begin
    If Not NodeTwo^.Seen Then DisplayResult('>',NodeTwo^.Name);
    NodeTwo:=NodeTwo^.Next;
  End;
  If(NamesOne.Count=0)and(NamesTwo.Count=0)and Not DifferenceOnly Then
    WriteLn('Les deux repertoires sont vides.');
  FreeNameList(NamesOne);
  FreeNameList(NamesTwo);
End;

BEGIN
  LanguageCode:=GetEnv('LANGUAGE');
  DifferenceOnly:=False;SuppressSame:=False;WidthValue:=32;ErrorFound:=False;
  DirectoryOne:='';DirectoryTwo:='';ArgumentIndex:=1;
  While ArgumentIndex<=ParamCount Do Begin
    Argument:=ParamStr(ArgumentIndex);
    If(Argument='--help')or(Argument='-h')or(Argument='/?')Then Begin PrintHelp;Halt(0);End
    Else If(Argument='--version')or(Argument='-V')Then Begin WriteLn('dircmp (LINUX-0) 1.0');Halt(0);End
    Else If Argument='-d'Then DifferenceOnly:=True
    Else If Argument='-s'Then SuppressSame:=True
    Else If(Argument='-w')Then Begin
      Inc(ArgumentIndex);
      If ArgumentIndex>ParamCount Then UsageError('-w attend une largeur');
      Val(ParamStr(ArgumentIndex),WidthValue,ErrorCode);
      If(ErrorCode<>0)or(WidthValue<0)or(WidthValue>255)Then UsageError('largeur invalide');
    End Else If(Length(Argument)>2)and(Copy(Argument,1,2)='-w')Then Begin
      Val(Copy(Argument,3,255),WidthValue,ErrorCode);
      If(ErrorCode<>0)or(WidthValue<0)or(WidthValue>255)Then UsageError('largeur invalide');
    End Else If(Length(Argument)>1)and(Argument[1]='-')Then UsageError('option inconnue: '+Argument)
    Else If DirectoryOne=''Then DirectoryOne:=Argument
    Else If DirectoryTwo=''Then DirectoryTwo:=Argument
    Else UsageError('deux repertoires seulement sont requis');
    Inc(ArgumentIndex);
  End;
  If(DirectoryOne='')or(DirectoryTwo='')Then Begin PrintHelp;Halt(2);End;
  CompareDirectories;
  If ErrorFound Then Halt(1);
END.