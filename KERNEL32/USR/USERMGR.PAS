{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: gestion des comptes (un seul programme, nom lu dans argv[0]) :
      useradd userdel usermod groupadd groupdel groupmod adduser addgroup
      deluser delgroup chpasswd : editent /etc/passwd, /etc/shadow et
      /etc/group (reserve a root).
}

Program USERMGR;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  MaxL = 400;

Type
  TLines = Array[1..MaxL] Of String;

Var
  PwLn, ShLn, GrLn : TLines;
  NPw, NSh, NGr : LongInt;
  Prog, Etc : String;
  ShellSet : Boolean;
  Args : Array[1..40] Of String;
  NA : LongInt;

Function PS(Q : PChar) : String;
Var X : String;
Begin
  X := '';
  While Q^ <> #0 Do
  Begin
    X := X + Q^;
    Inc(Q);
  End;
  PS := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

{ messages : 1 deja existant, 2 inconnu, 3 root requis, 4 id invalide,
  5 groupe principal, 6 plus de place }
Const
  M1 : Array[1..5] Of PChar = ('existe deja', 'already exists',
    'existiert bereits', 'ya existe', 'esiste gia');
  M2 : Array[1..5] Of PChar = ('inexistant', 'does not exist',
    'existiert nicht', 'no existe', 'non esiste');
  M3 : Array[1..5] Of PChar = ('reserve a root', 'only root may do this',
    'nur root darf das', 'solo root puede', 'solo root puo');
  M5 : Array[1..5] Of PChar = ('groupe principal d''un utilisateur',
    'primary group of a user', 'Hauptgruppe eines Benutzers',
    'grupo primario de un usuario', 'gruppo primario di un utente');

Procedure Die(Const Msg : String);
Begin
  SysPut(2, Prog + ': ' + Msg + #10);
  SysExit(1);
End;

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(UsageW[SysLang]) + Prog + ' ' + Syn + #10);
  SysExit(2);
End;

Function Field(Const L : String; N : LongInt) : String;
Var K, I, Start : LongInt;
Begin
  I := 1;
  Start := 1;
  For K := 1 To Length(L) + 1 Do
    If (K > Length(L)) Or (L[K] = ':') Then
    Begin
      If I = N Then
      Begin
        Field := Copy(L, Start, K - Start);
        Exit;
      End;
      Inc(I);
      Start := K + 1;
    End;
  Field := '';
End;

Function SetField(Const L : String; N : LongInt; Const V : String) : String;
Var K, I, Start : LongInt; R : String;
Begin
  R := '';
  I := 1;
  Start := 1;
  For K := 1 To Length(L) + 1 Do
    If (K > Length(L)) Or (L[K] = ':') Then
    Begin
      If I = N Then R := R + V Else R := R + Copy(L, Start, K - Start);
      If K <= Length(L) Then R := R + ':';
      Inc(I);
      Start := K + 1;
    End;
  If I <= N Then
  Begin
    While I < N Do
    Begin
      R := R + ':';
      Inc(I);
    End;
    R := R + ':' + V;
  End;
  SetField := R;
End;

Procedure LoadFile(Const Fn : String; Var A : TLines; Var N : LongInt);
Var Fd : LongInt; L : String;
Begin
  N := 0;
  Fd := SysOpen(Fn, 0, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
    If (L <> '') And (N < MaxL) Then
    Begin
      Inc(N);
      A[N] := L;
    End;
  SysClose(Fd);
End;

Procedure SaveFile(Const Fn : String; Var A : TLines; N, Mode : LongInt);
Var Fd, K : LongInt; Tmp : String;
Begin
  Tmp := Fn + '.new';
  Fd := SysOpen(Tmp, $241, Mode);
  If Fd < 0 Then Die(Fn + ' : ' + SysErrorText(SysErrno));
  For K := 1 To N Do SysPut(Fd, A[K] + #10);
  SysClose(Fd);
  SysChmod(Tmp, Mode);
  SysRename(Tmp, Fn);
End;

Function FindL(Var A : TLines; N : LongInt; Const Name : String;
              Fld : LongInt) : LongInt;
Var K : LongInt;
Begin
  FindL := 0;
  For K := 1 To N Do
    If Field(A[K], Fld) = Name Then
    Begin
      FindL := K;
      Exit;
    End;
End;

Procedure LoadAll;
Var F : String;
Begin
  F := Etc + '/passwd';
  LoadFile(F, PwLn, NPw);
  F := Etc + '/shadow';
  LoadFile(F, ShLn, NSh);
  F := Etc + '/group';
  LoadFile(F, GrLn, NGr);
End;

Procedure SaveAll;
Var F : String;
Begin
  F := Etc + '/passwd';
  SaveFile(F, PwLn, NPw, 420);
  F := Etc + '/shadow';
  SaveFile(F, ShLn, NSh, 384);
  F := Etc + '/group';
  SaveFile(F, GrLn, NGr, 420);
End;

Function ToInt(Const S : String; Var V : LongInt) : Boolean;
Var E : LongInt;
Begin
  Val(S, V, E);
  ToInt := (E = 0) And (S <> '');
End;

Function FreeId(Var A : TLines; N, Fld, Lo, Hi : LongInt) : LongInt;
Var Id, K, V : LongInt; Used : Boolean;
Begin
  For Id := Lo To Hi Do
  Begin
    Used := False;
    For K := 1 To N Do
      If ToInt(Field(A[K], Fld), V) And (V = Id) Then Used := True;
    If Not Used Then
    Begin
      FreeId := Id;
      Exit;
    End;
  End;
  Die('plus d''identifiant libre');
  FreeId := 0;
End;

{ liste "a,b,c" : ajoute / retire un membre }
Function AddMember(Const Lst, U : String) : String;
Begin
  If Lst = '' Then AddMember := U
  Else If Pos(',' + U + ',', ',' + Lst + ',') > 0 Then AddMember := Lst
  Else AddMember := Lst + ',' + U;
End;

Function DelMember(Const Lst, U : String) : String;
Var T : String; P : LongInt;
Begin
  T := ',' + Lst + ',';
  P := Pos(',' + U + ',', T);
  If P > 0 Then T := Copy(T, 1, P) + Copy(T, P + Length(U) + 2, 255);
  If Length(T) >= 2 Then T := Copy(T, 2, Length(T) - 2) Else T := '';
  DelMember := T;
End;

Function GidOf(Const G : String) : LongInt;
Var K, V : LongInt;
Begin
  If ToInt(G, V) Then
  Begin
    GidOf := V;
    Exit;
  End;
  K := FindL(GrLn, NGr, G, 1);
  If K = 0 Then Die('groupe ' + G + ' : ' + PS(M2[SysLang]));
  ToInt(Field(GrLn[K], 3), V);
  GidOf := V;
End;

Procedure SetGroups(Const U, List : String; Append : Boolean);
Var K, J : LongInt; G, Lst : String;
Begin
  { retire U des groupes non cites (sauf -a) }
  If Not Append Then
    For K := 1 To NGr Do
      GrLn[K] := SetField(GrLn[K], 4, DelMember(Field(GrLn[K], 4), U));
  Lst := List + ',';
  While Lst <> '' Do
  Begin
    J := Pos(',', Lst);
    G := Copy(Lst, 1, J - 1);
    Lst := Copy(Lst, J + 1, 255);
    If G = '' Then Continue;
    K := FindL(GrLn, NGr, G, 1);
    If K = 0 Then Die('groupe ' + G + ' : ' + PS(M2[SysLang]));
    GrLn[K] := SetField(GrLn[K], 4, AddMember(Field(GrLn[K], 4), U));
  End;
End;

Procedure RunProg(Const Path : String; A1, A2, A3, A4 : String);
Var Pid, St : LongInt;
Begin
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    SysArgAdd(Path);
    If A1 <> '' Then SysArgAdd(A1);
    If A2 <> '' Then SysArgAdd(A2);
    If A3 <> '' Then SysArgAdd(A3);
    If A4 <> '' Then SysArgAdd(A4);
    SysArgExec(Path);
    SysExit(127);
  End;
  SysWaitPid(Pid, St, 0);
End;

Function DaysNow : String;
Begin
  DaysNow := NumS(SysTime Div 86400);
End;

{ ---------- groupes ---------- }

Procedure DoGroupAdd(Const Name : String; Gid : LongInt; System : Boolean);
Var Lo, Hi : LongInt;
Begin
  If FindL(GrLn, NGr, Name, 1) <> 0 Then Die('groupe ' + Name + ' : ' +
                                           PS(M1[SysLang]));
  If Gid < 0 Then
  Begin
    If System Then
    Begin
      Lo := 100;
      Hi := 999;
    End
    Else
    Begin
      Lo := 1000;
      Hi := 59999;
    End;
    Gid := FreeId(GrLn, NGr, 3, Lo, Hi);
  End;
  If NGr >= MaxL Then Die('trop de groupes');
  Inc(NGr);
  GrLn[NGr] := Name + ':x:' + NumS(Gid) + ':';
End;

{ ---------- utilisateurs ---------- }

Procedure DoUserAdd(Const Name : String; Uid, Gid : LongInt;
                    Const GName, Home, Shell, Gecos, Groups, Crypt : String;
                    MkHome, System, NoGroup : Boolean);
Var K, Lo, Hi, G : LongInt; H : String;
Begin
  If FindL(PwLn, NPw, Name, 1) <> 0 Then Die('utilisateur ' + Name + ' : ' +
                                           PS(M1[SysLang]));
  If (Name = '') Or (Pos(':', Name) > 0) Then Die('nom invalide');
  If System Then
  Begin
    Lo := 100;
    Hi := 999;
  End
  Else
  Begin
    Lo := 1000;
    Hi := 59999;
  End;
  If Uid < 0 Then Uid := FreeId(PwLn, NPw, 3, Lo, Hi);
  G := Gid;
  If (G < 0) And (GName <> '') Then G := GidOf(GName);
  If G < 0 Then
  Begin
    { groupe prive du meme nom }
    K := FindL(GrLn, NGr, Name, 1);
    If K <> 0 Then ToInt(Field(GrLn[K], 3), G)
    Else
    Begin
      If NoGroup Then G := 100
      Else
      Begin
        DoGroupAdd(Name, -1, System);
        ToInt(Field(GrLn[NGr], 3), G);
      End;
    End;
  End;
  H := Home;
  If H = '' Then H := '/home/' + Name;
  If NPw >= MaxL Then Die('trop d''utilisateurs');
  Inc(NPw);
  PwLn[NPw] := Name + ':x:' + NumS(Uid) + ':' + NumS(G) + ':' + Gecos + ':' +
              H + ':' + Shell;
  If NSh < MaxL Then
  Begin
    Inc(NSh);
    If Crypt <> '' Then ShLn[NSh] := Name + ':' + Crypt + ':' + DaysNow +
                                    ':0:99999:7:::'
    Else ShLn[NSh] := Name + ':!:' + DaysNow + ':0:99999:7:::';
  End;
  If Groups <> '' Then SetGroups(Name, Groups, True);
  If MkHome Then
  Begin
    SysMkdir(H, 493);
    SysChown(H, Uid, G);
    SysChmod(H, 493);
  End;
End;

Procedure DoUserDel(Const Name : String; RemoveHome : Boolean);
Var K, J, G : LongInt; Home : String;
Begin
  K := FindL(PwLn, NPw, Name, 1);
  If K = 0 Then Die('utilisateur ' + Name + ' : ' + PS(M2[SysLang]));
  If Field(PwLn[K], 3) = '0' Then Die('root ne peut pas etre supprime');
  Home := Field(PwLn[K], 6);
  ToInt(Field(PwLn[K], 4), G);
  For J := K To NPw - 1 Do PwLn[J] := PwLn[J + 1];
  Dec(NPw);
  K := FindL(ShLn, NSh, Name, 1);
  If K <> 0 Then
  Begin
    For J := K To NSh - 1 Do ShLn[J] := ShLn[J + 1];
    Dec(NSh);
  End;
  For K := 1 To NGr Do
    GrLn[K] := SetField(GrLn[K], 4, DelMember(Field(GrLn[K], 4), Name));
  { groupe prive devenu orphelin }
  K := FindL(GrLn, NGr, Name, 1);
  If K <> 0 Then
  Begin
    J := 0;
    For G := 1 To NPw Do
      If Field(PwLn[G], 4) = Field(GrLn[K], 3) Then J := 1;
    If (J = 0) And (Field(GrLn[K], 4) = '') Then
    Begin
      For J := K To NGr - 1 Do GrLn[J] := GrLn[J + 1];
      Dec(NGr);
    End;
  End;
  If RemoveHome And (Length(Home) > 2) And (Home <> '/') Then
    RunProg('/bin/rm', '-rf', Home, '', '');
End;

Procedure DoChpasswd;
Var L, U, P : String; K, N : LongInt; Enc : Boolean; I : LongInt;
Begin
  Enc := False;
  For I := 1 To NA Do
    If (Args[I] = '-e') Or (Args[I] = '--encrypted') Then Enc := True;
  N := 0;
  While SysReadLine(0, L) Do
  Begin
    K := Pos(':', L);
    If K = 0 Then Continue;
    U := Copy(L, 1, K - 1);
    P := Copy(L, K + 1, 255);
    K := FindL(ShLn, NSh, U, 1);
    If K = 0 Then
    Begin
      SysPut(2, 'chpasswd: utilisateur ' + U + ' : ' + PS(M2[SysLang]) + #10);
      Continue;
    End;
    If Not Enc Then
    Begin
      N := Ord(U[1]) + SysTime;
      P := SysCrypt(P, Chr(97 + N Mod 26) + Chr(97 + (N Div 26) Mod 26));
    End;
    ShLn[K] := SetField(ShLn[K], 2, P);
    ShLn[K] := SetField(ShLn[K], 3, DaysNow);
  End;
End;

Function ShellOk(Const S : String) : Boolean;
Begin
  ShellOk := (S = '') Or (SysAccess(S, 0) = 0);
End;

Function NextArg(Var I : LongInt) : String;
Begin
  Inc(I);
  If I > NA Then Usage('[options] nom');
  NextArg := Args[I];
End;

Var
  I, Uid, Gid, G2, K : LongInt;
  A, Name, Home, Shell, Gecos, Groups, GName, Crypt, NewName : String;
  MkHome, Sys, Append, RemoveHome, NoGroup, Lock, Unlock : Boolean;
  NewUid, NewGid, NewHome : String;
  Pos1 : LongInt;
Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 255);
  If SysGetEUid <> 0 Then Die(PS(M3[SysLang]));
  Etc := SysGetEnv('USERMGR_ROOT') + '/etc';
  If SysGetEnv('USERMGR_ROOT') = '' Then Etc := '/etc';
  ShellSet := False;
  NA := 0;
  For I := 1 To SysArgCount - 1 Do
    If NA < 40 Then
    Begin
      Inc(NA);
      Args[NA] := SysArgStr(I);
    End;
  LoadAll;
  Uid := -1;
  Gid := -1;
  Name := '';
  Home := '';
  Shell := '/bin/sh';
  Gecos := '';
  Groups := '';
  GName := '';
  Crypt := '';
  NewName := '';
  NewUid := '';
  NewGid := '';
  NewHome := '';
  MkHome := False;
  Sys := False;
  Append := False;
  RemoveHome := False;
  NoGroup := False;
  Lock := False;
  Unlock := False;
  I := 0;
  While I < NA Do
  Begin
    Inc(I);
    A := Args[I];
    If (A = '-u') Or (A = '--uid') Then
    Begin
      NewUid := NextArg(I);
      If Not ToInt(NewUid, Uid) Then Die('uid invalide');
    End
    Else If (A = '-g') Or (A = '--gid') Or (A = '--ingroup') Then
    Begin
      GName := NextArg(I);
      NewGid := GName;
      If ToInt(GName, Gid) Then GName := '';
    End
    Else If (A = '-G') Or (A = '--groups') Then Groups := NextArg(I)
    Else If (A = '-d') Or (A = '--home') Or (A = '--home-dir') Then
    Begin
      Home := NextArg(I);
      NewHome := Home;
    End
    Else If (A = '-s') Or (A = '--shell') Then
    Begin
      Shell := NextArg(I);
      ShellSet := True;
    End
    Else If (A = '-c') Or (A = '--comment') Or (A = '--gecos') Then
      Gecos := NextArg(I)
    Else If (A = '-p') Or (A = '--password') Then Crypt := NextArg(I)
    Else If (A = '-l') Or (A = '--login') Then NewName := NextArg(I)
    Else If A = '-m' Then MkHome := True
    Else If (A = '-M') Or (A = '--no-create-home') Then MkHome := False
    Else If (A = '-r') And ((Prog = 'userdel') Or (Prog = 'deluser')) Then
      RemoveHome := True
    Else If (A = '--remove-home') Then RemoveHome := True
    Else If (A = '-r') Or (A = '--system') Then Sys := True
    Else If A = '-a' Then Append := True
    Else If A = '-aG' Then
    Begin
      Append := True;
      Groups := NextArg(I);
    End
    Else If A = '-L' Then Lock := True
    Else If A = '-U' Then Unlock := True
    Else If (A = '-e') Or (A = '--encrypted') Or (A = '-f') Or (A = '-o') Or
            (A = '--disabled-password') Or (A = '--disabled-login') Or
            (A = '--quiet') Or (A = '-q') Or (A = '-n') Then
    Begin
      If (A = '--disabled-password') Or (A = '--disabled-login') Then
        Crypt := '';
    End
    Else If (Length(A) > 0) And (A[1] = '-') Then Usage('[options] nom')
    Else If Name = '' Then Name := A
    Else If ((Prog = 'adduser') Or (Prog = 'deluser')) And (Groups = '') Then
      Groups := A;
  End;
  { adduser Debian : "adduser utilisateur groupe" ajoute au groupe }
  If (Prog = 'adduser') And (Groups <> '') And
     (FindL(PwLn, NPw, Name, 1) <> 0) Then
  Begin
    SetGroups(Name, Groups, True);
    SaveAll;
    SysExit(0);
  End;
  If (Prog = 'deluser') And (Groups <> '') And
     (FindL(PwLn, NPw, Name, 1) <> 0) Then
  Begin
    K := FindL(GrLn, NGr, Groups, 1);
    If K = 0 Then Die('groupe ' + Groups + ' : ' + PS(M2[SysLang]));
    GrLn[K] := SetField(GrLn[K], 4, DelMember(Field(GrLn[K], 4), Name));
    SaveAll;
    SysExit(0);
  End;
  If Prog = 'chpasswd' Then
  Begin
    DoChpasswd;
    SaveAll;
    SysExit(0);
  End;
  If Name = '' Then Usage('[options] nom');
  If (Prog = 'useradd') Or (Prog = 'adduser') Then
  Begin
    If Prog = 'adduser' Then MkHome := True;
    DoUserAdd(Name, Uid, Gid, GName, Home, Shell, Gecos, Groups, Crypt,
              MkHome, Sys, NoGroup);
    SaveAll;
  End
  Else If (Prog = 'userdel') Or ((Prog = 'deluser') And
          (FindL(PwLn, NPw, Name, 1) <> 0)) Then
  Begin
    DoUserDel(Name, RemoveHome);
    SaveAll;
  End
  Else If Prog = 'usermod' Then
  Begin
    K := FindL(PwLn, NPw, Name, 1);
    If K = 0 Then Die('utilisateur ' + Name + ' : ' + PS(M2[SysLang]));
    If NewUid <> '' Then PwLn[K] := SetField(PwLn[K], 3, NumS(Uid));
    If NewGid <> '' Then PwLn[K] := SetField(PwLn[K], 4, NumS(GidOf(NewGid)));
    If Gecos <> '' Then PwLn[K] := SetField(PwLn[K], 5, Gecos);
    If NewHome <> '' Then
    Begin
      If MkHome Then
      Begin
        If FindL(PwLn, NPw, Name, 1) <> 0 Then
          SysRename(Field(PwLn[K], 6), NewHome);
      End;
      PwLn[K] := SetField(PwLn[K], 6, NewHome);
    End;
    If ShellSet Then
      PwLn[K] := SetField(PwLn[K], 7, Shell);
    If Groups <> '' Then SetGroups(Name, Groups, Append);
    G2 := FindL(ShLn, NSh, Name, 1);
    If G2 <> 0 Then
    Begin
      If Crypt <> '' Then ShLn[G2] := SetField(ShLn[G2], 2, Crypt);
      If Lock And (Copy(Field(ShLn[G2], 2), 1, 1) <> '!') Then
        ShLn[G2] := SetField(ShLn[G2], 2, '!' + Field(ShLn[G2], 2));
      If Unlock And (Copy(Field(ShLn[G2], 2), 1, 1) = '!') Then
        ShLn[G2] := SetField(ShLn[G2], 2, Copy(Field(ShLn[G2], 2), 2, 255));
    End;
    If NewName <> '' Then
    Begin
      If FindL(PwLn, NPw, NewName, 1) <> 0 Then
        Die('utilisateur ' + NewName + ' : ' + PS(M1[SysLang]));
      PwLn[K] := SetField(PwLn[K], 1, NewName);
      If G2 <> 0 Then ShLn[G2] := SetField(ShLn[G2], 1, NewName);
      For K := 1 To NGr Do
        If Pos(',' + Name + ',', ',' + Field(GrLn[K], 4) + ',') > 0 Then
          GrLn[K] := SetField(GrLn[K], 4,
            AddMember(DelMember(Field(GrLn[K], 4), Name), NewName));
    End;
    SaveAll;
  End
  Else If (Prog = 'groupadd') Or (Prog = 'addgroup') Then
  Begin
    DoGroupAdd(Name, Gid, Sys);
    SaveAll;
  End
  Else If (Prog = 'groupdel') Or (Prog = 'delgroup') Or (Prog = 'deluser') Then
  Begin
    K := FindL(GrLn, NGr, Name, 1);
    If K = 0 Then Die('groupe ' + Name + ' : ' + PS(M2[SysLang]));
    For G2 := 1 To NPw Do
      If Field(PwLn[G2], 4) = Field(GrLn[K], 3) Then
        Die('groupe ' + Name + ' : ' + PS(M5[SysLang]));
    For G2 := K To NGr - 1 Do GrLn[G2] := GrLn[G2 + 1];
    Dec(NGr);
    SaveAll;
  End
  Else If Prog = 'groupmod' Then
  Begin
    K := FindL(GrLn, NGr, Name, 1);
    If K = 0 Then Die('groupe ' + Name + ' : ' + PS(M2[SysLang]));
    If NewName <> '' Then GrLn[K] := SetField(GrLn[K], 1, NewName);
    If Gid >= 0 Then GrLn[K] := SetField(GrLn[K], 3, NumS(Gid));
    SaveAll;
  End
  Else Die('commande inconnue');
End.
