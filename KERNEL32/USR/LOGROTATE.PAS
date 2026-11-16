{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /sbin/logrotate : rotation des journaux.
   logrotate [-f] [-d] [-s etat] [fichier_de_configuration]
   (defaut /etc/logrotate.conf ; -f force la rotation, -d affiche sans rien
   faire, -s fichier d'etat, defaut /var/lib/logrotate.status).
   Configuration : directives globales puis blocs  chemin... { directives } ;
   "include dossier|fichier". Directives : rotate N, daily, weekly, monthly,
   size N[k|M|G], missingok, notifempty, copytruncate, create [mode
   [proprietaire [groupe]]], nocreate, compress/nocompress (la compression
   n'est pas faite : signalee), prerotate/postrotate ... endscript (executes
   par /bin/sh -c), olddir dossier. Les fichiers tournent en f.1, f.2...
   jusqu'a rotate N (le plus ancien est supprime). }

Program LogRotate;

Const
  MaxLines = 400;

Var
  Force, DryRun : Boolean;
  StateFile, Conf : String;
  { directives du bloc courant }
  Rot, SizeLim, Period : LongInt;      { Period : 0 aucune, 1 jour, 7, 30 }
  MissOk, NotEmpty, CopyTr, NoCreate, Compress : Boolean;
  CrMode, CrUid, CrGid : LongInt;
  PostS, PreS, OldDir : String;
  GRot, GSize, GPer : LongInt;
  GMiss, GNotE, GCopy, GComp : Boolean;
  Path : Array[0..19] Of String[100];
  NPath : LongInt;
  StK : Array[0..199] Of String[100];
  StD : Array[0..199] Of LongInt;
  StN : LongInt;
  Today : LongInt;
  Errors : LongInt;

Procedure Say(Const S : String);
Begin
  SysPut(1, S + #10);
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Function ToInt(Const S : String) : LongInt;
Var V, E : LongInt;
Begin
  Val(S, V, E);
  If E <> 0 Then V := 0;
  ToInt := V;
End;

Function ToOct(Const S : String) : LongInt;
Var I, V : LongInt;
Begin
  V := 0;
  For I := 1 To Length(S) Do
    If (S[I] >= '0') And (S[I] <= '7') Then V := V * 8 + Ord(S[I]) - 48;
  ToOct := V;
End;

{ uid d'un nom d'utilisateur (/etc/passwd) }
Function UserId(Const N : String; Var Uid : LongInt) : Boolean;
Var P : TSysPasswd;
Begin
  UserId := SysGetPw(N, False, 0, P);
  If UserId Then Uid := P.Uid;
End;

Function LastDay(Const P : String) : LongInt;
Var I : LongInt;
Begin
  LastDay := 0;
  For I := 0 To StN - 1 Do
    If StK[I] = P Then LastDay := StD[I];
End;

Procedure SetLastDay(Const P : String; D : LongInt);
Var I : LongInt;
Begin
  For I := 0 To StN - 1 Do
    If StK[I] = P Then
    Begin
      StD[I] := D;
      Exit;
    End;
  If StN < 200 Then
  Begin
    StK[StN] := P;
    StD[StN] := D;
    Inc(StN);
  End;
End;

Procedure LoadState;
Var F, P : LongInt; L : String;
Begin
  StN := 0;
  F := SysOpen(StateFile, O_RDONLY, 0);
  If F < 0 Then Exit;
  While SysReadLine(F, L) Do
  Begin
    P := Length(L);
    While (P > 0) And (L[P] <> ' ') Do Dec(P);
    If P > 1 Then SetLastDay(Copy(L, 1, P - 1), ToInt(Copy(L, P + 1, 10)));
  End;
  SysClose(F);
End;

Procedure SaveState;
Var F, I : LongInt; L : String;
Begin
  If DryRun Then Exit;
  SysMkdir('/var', 493);
  SysMkdir('/var/lib', 493);
  F := SysOpen(StateFile, O_WRONLY Or O_CREAT Or O_TRUNC, 420);
  If F < 0 Then Exit;
  For I := 0 To StN - 1 Do
  Begin
    L := StK[I] + ' ' + NumS(StD[I]) + #10;
    SysWrite(F, L[1], Length(L));
  End;
  SysClose(F);
End;

Procedure ResetBlock;
Begin
  Rot := GRot; SizeLim := GSize; Period := GPer;
  MissOk := GMiss; NotEmpty := GNotE; CopyTr := GCopy; Compress := GComp;
  NoCreate := False;
  CrMode := -1; CrUid := -1; CrGid := -1;
  PostS := ''; PreS := ''; OldDir := '';
End;

Function ParseSize(Const S : String) : LongInt;
Var V, E, N : LongInt; T : String; M : LongInt;
Begin
  T := S;
  M := 1;
  N := Length(T);
  If N = 0 Then
  Begin
    ParseSize := 0;
    Exit;
  End;
  Case UpCase(T[N]) Of
    'K' : M := 1024;
    'M' : M := 1048576;
    'G' : M := 1073741824;
  End;
  If M > 1 Then Delete(T, N, 1);
  Val(T, V, E);
  If E <> 0 Then V := 0;
  ParseSize := V * M;
End;

Function Word_(Const L : String; N : LongInt) : String;
Var I, K, S : LongInt;
Begin
  Word_ := '';
  I := 1;
  For K := 1 To N Do
  Begin
    While (I <= Length(L)) And ((L[I] = ' ') Or (L[I] = #9)) Do Inc(I);
    S := I;
    While (I <= Length(L)) And (L[I] <> ' ') And (L[I] <> #9) Do Inc(I);
    If K = N Then Word_ := Copy(L, S, I - S);
  End;
End;

Procedure RunScript(Const S : String);
Var Pid, St : LongInt;
Begin
  If (S = '') Or DryRun Then Exit;
  SysArgReset;
  SysArgAdd('sh');
  SysArgAdd('-c');
  SysArgAdd(S);
  SysEnvInherit;
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgExec('/bin/sh');
    SysExit(127);
  End;
  If Pid > 0 Then SysWaitPid(Pid, St, 0);
End;

{ nom du fichier de rang N (f.N) dans le dossier d'archivage }
Function Arch(Const F : String; N : LongInt) : String;
Var B, D : String; I : LongInt;
Begin
  B := F;
  D := '';
  If OldDir <> '' Then
  Begin
    I := Length(F);
    While (I > 0) And (F[I] <> '/') Do Dec(I);
    B := OldDir + '/' + Copy(F, I + 1, 100);
  End;
  Arch := B + '.' + NumS(N);
End;

Procedure Rotate(Const F : String);
Var St : TSysStat; I, D, Fd, Fo, R : LongInt; Due : Boolean;
  Buf : Array[0..8191] Of Byte;
Begin
  If SysStat(F, St) < 0 Then
  Begin
    If Not MissOk Then
    Begin
      Say('logrotate: ' + F + ' : absent');
      Inc(Errors);
    End;
    Exit;
  End;
  If NotEmpty And (St.Size = 0) Then Exit;
  Due := Force;
  If Not Due Then
  Begin
    D := LastDay(F);
    If (Period > 0) And (Today - D >= Period) Then Due := True;
    If (Period = 0) And (SizeLim = 0) Then Due := False;
    If (SizeLim > 0) And (St.Size >= SizeLim) Then Due := True;
    If (Period > 0) And (D = 0) Then Due := True;
  End;
  If Not Due Then
  Begin
    If DryRun Then Say('pas de rotation de ' + F);
    Exit;
  End;
  If DryRun Then
  Begin
    Say('rotation de ' + F);
    Exit;
  End;
  If Compress Then Say('logrotate: compression non geree, ignoree (' + F + ')');
  RunScript(PreS);
  If OldDir <> '' Then SysMkdir(OldDir, 493);
  If Rot = 0 Then SysUnlink(F)
  Else
  Begin
    SysUnlink(Arch(F, Rot));
    For I := Rot - 1 DownTo 1 Do SysRename(Arch(F, I), Arch(F, I + 1));
    If CopyTr Then
    Begin
      Fd := SysOpen(F, O_RDWR, 0);
      Fo := SysOpen(Arch(F, 1), O_WRONLY Or O_CREAT Or O_TRUNC,
                    St.Mode And $1FF);
      If (Fd >= 0) And (Fo >= 0) Then
      Begin
        Repeat
          R := SysRead(Fd, Buf, 8192);
          If R > 0 Then SysWrite(Fo, Buf, R);
        Until R <= 0;
        LnxSys3(93, Fd, 0, 0);
      End;
      If Fd >= 0 Then SysClose(Fd);
      If Fo >= 0 Then SysClose(Fo);
    End
    Else
    Begin
      SysRename(F, Arch(F, 1));
      If Not NoCreate Then
      Begin
        Fd := SysOpen(F, O_WRONLY Or O_CREAT, 420);
        If Fd >= 0 Then SysClose(Fd);
        If CrMode >= 0 Then SysChmod(F, CrMode)
        Else SysChmod(F, St.Mode And $FFF);
        If CrUid >= 0 Then SysChown(F, CrUid, CrGid)
        Else SysChown(F, St.Uid, St.Gid);
      End;
    End;
  End;
  RunScript(PostS);
  SetLastDay(F, Today);
  Say('rotation de ' + F);
End;

{ chemins avec un joker * simple dans le dernier composant }
Procedure Expand(Const Pat : String);
Var I, Dh, Ino : LongInt; Dir, Pre, Suf, N : String; Star : LongInt;
Begin
  Star := Pos('*', Pat);
  If Star = 0 Then
  Begin
    If NPath < 20 Then
    Begin
      Path[NPath] := Pat;
      Inc(NPath);
    End;
    Exit;
  End;
  I := Length(Pat);
  While (I > 0) And (Pat[I] <> '/') Do Dec(I);
  Dir := Copy(Pat, 1, I - 1);
  If Dir = '' Then Dir := '/';
  Pre := Copy(Pat, I + 1, Star - I - 1);
  Suf := Copy(Pat, Star + 1, 100);
  Dh := SysOpenDir(Dir);
  If Dh < 0 Then Exit;
  While SysReadDir(Dh, N, Ino) Do
    If (Copy(N, 1, Length(Pre)) = Pre) And
       (Copy(N, Length(N) - Length(Suf) + 1, Length(Suf)) = Suf) And
       (N <> '.') And (N <> '..') And (NPath < 20) Then
    Begin
      Path[NPath] := Dir + '/' + N;
      Inc(NPath);
    End;
  SysCloseDir(Dh);
End;

Procedure ReadConf(Const FileName : String); Forward;

{ applique une directive de la ligne L au bloc ou aux directives globales }
Procedure Directive(Const L : String; Global : Boolean);
Var W, V : String; N : LongInt;
Begin
  W := Word_(L, 1);
  V := Word_(L, 2);
  If W = 'rotate' Then Rot := ToInt(V)
  Else If W = 'daily' Then Period := 1
  Else If W = 'weekly' Then Period := 7
  Else If W = 'monthly' Then Period := 30
  Else If (W = 'size') Or (W = 'minsize') Then SizeLim := ParseSize(V)
  Else If W = 'missingok' Then MissOk := True
  Else If W = 'nomissingok' Then MissOk := False
  Else If W = 'notifempty' Then NotEmpty := True
  Else If W = 'ifempty' Then NotEmpty := False
  Else If W = 'copytruncate' Then CopyTr := True
  Else If W = 'nocopytruncate' Then CopyTr := False
  Else If W = 'compress' Then Compress := True
  Else If W = 'nocompress' Then Compress := False
  Else If W = 'nocreate' Then NoCreate := True
  Else If W = 'olddir' Then OldDir := V
  Else If W = 'create' Then
  Begin
    NoCreate := False;
    If V <> '' Then CrMode := ToOct(V);
    If Word_(L, 3) <> '' Then
    Begin
      If Not UserId(Word_(L, 3), CrUid) Then CrUid := ToInt(Word_(L, 3));
      CrGid := CrUid;
      If Word_(L, 4) <> '' Then CrGid := ToInt(Word_(L, 4));
    End;
  End
  Else If W = 'include' Then ReadConf(V);
  If Global Then
  Begin
    GRot := Rot; GSize := SizeLim; GPer := Period;
    GMiss := MissOk; GNotE := NotEmpty; GCopy := CopyTr; GComp := Compress;
  End;
End;

Procedure ReadConf(Const FileName : String);
Var F, Dh, Ino, I : LongInt; L, N, W : String; InBlk, InScr : Boolean;
  Scr : String; ScrKind : LongInt; St : TSysStat; Names : String;
Begin
  If (SysStat(FileName, St) = 0) And ((St.Mode And S_IFMT) = S_IFDIR) Then
  Begin
    Dh := SysOpenDir(FileName);
    If Dh < 0 Then Exit;
    While SysReadDir(Dh, N, Ino) Do
      If (N <> '.') And (N <> '..') And (Copy(N, Length(N), 1) <> '~') Then
        ReadConf(FileName + '/' + N);
    SysCloseDir(Dh);
    Exit;
  End;
  F := SysOpen(FileName, O_RDONLY, 0);
  If F < 0 Then Exit;
  InBlk := False;
  InScr := False;
  NPath := 0;
  ScrKind := 0;
  While SysReadLine(F, L) Do
  Begin
    While (Length(L) > 0) And ((L[1] = ' ') Or (L[1] = #9)) Do Delete(L, 1, 1);
    If InScr Then
    Begin
      If L = 'endscript' Then
      Begin
        InScr := False;
        If ScrKind = 1 Then PreS := Scr Else PostS := Scr;
      End
      Else Scr := Scr + L + #10;
      Continue;
    End;
    If (L = '') Or (L[1] = '#') Then Continue;
    If InBlk Then
    Begin
      If L = '}' Then
      Begin
        For I := 0 To NPath - 1 Do Rotate(Path[I]);
        InBlk := False;
        NPath := 0;
        ResetBlock;
      End
      Else If (L = 'postrotate') Or (L = 'prerotate') Then
      Begin
        InScr := True;
        Scr := '';
        If L = 'prerotate' Then ScrKind := 1 Else ScrKind := 2;
      End
      Else Directive(L, False);
    End
    Else If L[Length(L)] = '{' Then
    Begin
      Names := Copy(L, 1, Length(L) - 1);
      NPath := 0;
      I := 1;
      While Word_(Names, I) <> '' Do
      Begin
        Expand(Word_(Names, I));
        Inc(I);
      End;
      ResetBlock;
      InBlk := True;
    End
    Else Directive(L, True);
  End;
  SysClose(F);
End;

Var
  I : LongInt;
  A : String;
Begin
  Force := False;
  DryRun := False;
  StateFile := '/var/lib/logrotate.status';
  Conf := '/etc/logrotate.conf';
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If A = '-f' Then Force := True
    Else If A = '-d' Then DryRun := True
    Else If (A = '-s') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      StateFile := SysArgStr(I);
    End
    Else If (A <> '') And (A[1] <> '-') Then Conf := A
    Else
    Begin
      SysPut(2, 'Usage: logrotate [-f] [-d] [-s etat] [configuration]' + #10);
      SysExit(1);
    End;
    Inc(I);
  End;
  Today := SysTime Div 86400;
  GRot := 4; GSize := 0; GPer := 0;
  GMiss := False; GNotE := False; GCopy := False; GComp := False;
  ResetBlock;
  LoadState;
  ReadConf(Conf);
  SaveState;
  If Errors > 0 Then SysExit(1);
End.
