{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Clone de la commande gsoelim - Interprete les requetes .so de groff
}

Program GSOELIM;

{$X+}

Uses DOS;

Const
 MaxDepth=10;
 MaxDirs=16;
 MaxFiles=32;

Var
 OptC:Boolean;
 Dirs:Array[1..MaxDirs]Of String[127];
 DirCnt:Integer;
 FileNames:Array[1..MaxFiles]Of String[127];
 FileCnt:Integer;
 ErrCount:Integer;

Procedure ShowUsage;Begin
 WriteLn('Usage: gsoelim [ -Cv ] [ -Idir ] [ files ... ]');
End;

Procedure ShowHelp;Begin
 WriteLn('GSOELIM : Cette commande permet d''interpreter les requetes .so en sortie groff.');
 WriteLn;
 ShowUsage;
 WriteLn;
 WriteLn('  -C          Reconnait .so meme suivi d''un caractere autre qu''un espace');
 WriteLn('  -v          Affiche le numero de version');
 WriteLn('  -Idir       Ajoute dir au chemin de recherche des fichiers inclus');
 WriteLn('  files       Fichiers a traiter (- ou aucun: entree standard)');
 WriteLn('  /?, --help  Affiche cette aide');
End;

Procedure Msg(Const S:String);Begin
 {$IFDEF FPC}
 WriteLn(StdErr,'gsoelim: ',S);
 {$ELSE}
 WriteLn('gsoelim: ',S);
 {$ENDIF}
 Inc(ErrCount);
End;

Function Trim(Const S:String):String;
Var
 A,B:Integer;
Begin
 A:=1;
 B:=Length(S);
 While(A<=B)And(S[A]In[' ',#9,#13])Do Inc(A);
 While(B>=A)And(S[B]In[' ',#9,#13])Do Dec(B);
 Trim:=Copy(S,A,B-A+1);
End;

Function CanOpen(Const Name:String):Boolean;
Var
 F:Text;
Begin
 CanOpen:=False;
 If Name=''Then Exit;
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult=0Then Begin
  Close(F);
  CanOpen:=True;
 End;
End;

Function FindFile(Const Name:String):String;
Var
 I:Integer;
 P:String;
Begin
 FindFile:='';
 If CanOpen(Name)Then Begin
  FindFile:=Name;
  Exit;
 End;
 For I:=1 to DirCnt Do Begin
  P:=Dirs[I]+'/'+Name;
  If CanOpen(P)Then Begin
   FindFile:=P;
   Exit;
  End;
 End;
End;

{ Reconnait une ligne ".so fichier" et retourne le nom du fichier }
Function IsSo(Const L:String;Var Arg:String):Boolean;
Var
 I:Integer;
 S:String;
Begin
 IsSo:=False;
 Arg:='';
 If(Length(L)<3)Or(L[1]<>'.')Then Exit;
 I:=2;
 While(I<=Length(L))And(L[I]In[' ',#9])Do Inc(I);
 If Copy(L,I,2)<>'so'Then Exit;
 Inc(I,2);
 If(I<=Length(L))And Not(L[I]In[' ',#9])And Not OptC Then Exit;
 S:=Trim(Copy(L,I,255));
 If S=''Then Exit;
 If S[1]='"'Then Begin
  S:=Copy(S,2,255);
  I:=Pos('"',S);
  If I>0Then S:=Copy(S,1,I-1);
 End;
 If S=''Then Exit;
 Arg:=S;
 IsSo:=True;
End;

Procedure Process(Const Name:String;Depth:Integer);
Var
 F:Text;
 L,Arg,Path,Disp:String;
 N:Longint;
Begin
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  Msg('impossible d''ouvrir '+Name);
  Exit;
 End;
 If Name=''Then Disp:='-'
           Else Disp:=Name;
 If(Name<>'')Or(Depth>0)Then WriteLn('.lf 1 ',Disp);
 N:=0;
 While Not EOF(F)Do Begin
  ReadLn(F,L);
  Inc(N);
  If IsSo(L,Arg)Then Begin
   Path:=FindFile(Arg);
   If Depth>=MaxDepth Then Begin
    Msg(Disp+':'+'inclusions trop imbriquees: '+Arg);
    WriteLn(L);
   End
   Else If Path=''Then Begin
    Msg('impossible d''ouvrir '+Arg);
    WriteLn(L);
   End
   Else Begin
    Process(Path,Depth+1);
    If(Name<>'')Or(Depth>0)Then Begin
     Write('.lf ',N+1,' ',Disp);
     WriteLn;
    End;
   End;
  End
   Else
  WriteLn(L);
 End;
 Close(F);
End;

Var
 I,J:Integer;
 A,V:String;

BEGIN
 ErrCount:=0;
 DirCnt:=0;
 FileCnt:=0;
 I:=1;
 While I<=ParamCount Do Begin
  A:=ParamStr(I);
  If(A='/?')Or(A='--help')Or(A='/h')Or(A='/H')Then Begin
   ShowHelp;
   Halt(0);
  End;
  If A='--version'Then A:='-v';
  If(Length(A)>1)And(A[1]='-')Then Begin
   J:=2;
   While J<=Length(A)Do Begin
    Case A[J]of
     'C':Begin
      OptC:=True;
      Inc(J);
     End;
     'v':Begin
      WriteLn('GNU soelim (clone) version 1.0');
      Halt(0);
     End;
     'I':Begin
      V:=Copy(A,J+1,255);
      If V=''Then Begin
       Inc(I);
       If I<=ParamCount Then V:=ParamStr(I);
      End;
      If(V<>'')And(DirCnt<MaxDirs)Then Begin
       Inc(DirCnt);
       Dirs[DirCnt]:=Copy(V,1,127);
      End;
      J:=Length(A)+1;
     End;
     Else Begin
      WriteLn('gsoelim: option inconnue: -',A[J]);
      ShowUsage;
      Halt(1);
     End;
    End;
   End;
   If A='-'Then Begin
    Inc(FileCnt);
    FileNames[FileCnt]:='';
   End;
  End
   Else
  Begin
   If FileCnt<MaxFiles Then Begin
    Inc(FileCnt);
    FileNames[FileCnt]:=Copy(A,1,127);
   End;
  End;
  Inc(I);
 End;
 If FileCnt=0Then Process('',0)
  Else
 For I:=1 to FileCnt Do Process(FileNames[I],0);
 If ErrCount>0Then Halt(1);
END.
