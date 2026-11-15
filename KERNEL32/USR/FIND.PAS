{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/find : parcourt des arborescences (find [chemin...] [-name p] [-iname p] [-type f|d|l] [-maxdepth n] [-mindepth n] [-empty] [-size [+-]n[ck]] [-mtime [+-]n] [-newer f] [-not] [-print] [-print0] [-delete] [-exec cmd {} ;]).
}

Program FIND;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');

Function PS(P : PChar) : String;
Var X : String;
Begin
  X := '';
  While P^ <> #0 Do
  Begin
    X := X + P^;
    Inc(P);
  End;
  PS := X;
End;

Function NumS(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NumS := S;
End;

Procedure Usage(Const Syn : String);
Begin
  SysPut(2, PS(UsageW[SysLang]) + Syn + #10);
  SysExit(1);
End;

Procedure Warn(Const What : String);
Begin
  SysPut(2, 'find: ' + What + ': ' + SysErrorText(SysErrno) + #10);
End;

Function BaseOf(Const P : String) : String;
Var K, L : LongInt;
Begin
  L := Length(P);
  While (L > 1) And (P[L] = '/') Do Dec(L);
  K := L;
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  BaseOf := Copy(P, K + 1, L - K);
End;

Function IsDir(Const P : String) : Boolean;
Var St : TSysStat;
Begin
  IsDir := (SysStat(P, St) = 0) And ((St.Mode And $F000) = $4000);
End;

Const
  MAXT = 40;

Var
  Roots : Array[1..32] Of String;
  NRoots : LongInt;
  { tests : 1 name 2 iname 3 type 4 empty 5 size 6 mtime 7 newer 8 user }
  TKind : Array[1..MAXT] Of LongInt;
  TStr : Array[1..MAXT] Of String;
  TNum : Array[1..MAXT] Of LongInt;
  TCmp : Array[1..MAXT] Of LongInt;      { -1 moins 0 egal 1 plus }
  TNot : Array[1..MAXT] Of Boolean;
  { actions : 0 aucune (print implicite) 1 print 2 print0 3 delete 4 exec }
  NTests, Action, MaxD, MinD, Rc : LongInt;
  ExecArgs : Array[1..30] Of String;
  NExec : LongInt;
  NewerT, Now1 : LongInt;
  Plus : Boolean;

Function Lower(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    If (S[K] >= 'A') And (S[K] <= 'Z') Then S[K] := Chr(Ord(S[K]) + 32);
  Lower := S;
End;

{ motif * ? [..] }
Function Match(Const P : String; PI : LongInt; Const S : String; SI : LongInt) : Boolean;
Var Ok, Neg : Boolean; C : Char; K : LongInt;
Begin
  While PI <= Length(P) Do
  Begin
    If P[PI] = '*' Then
    Begin
      While (PI <= Length(P)) And (P[PI] = '*') Do Inc(PI);
      If PI > Length(P) Then
      Begin
        Match := True;
        Exit;
      End;
      For K := SI To Length(S) + 1 Do
        If Match(P, PI, S, K) Then
        Begin
          Match := True;
          Exit;
        End;
      Match := False;
      Exit;
    End;
    If SI > Length(S) Then
    Begin
      Match := False;
      Exit;
    End;
    If P[PI] = '?' Then
    Begin
      Inc(PI);
      Inc(SI);
    End
    Else If P[PI] = '[' Then
    Begin
      C := S[SI];
      Inc(PI);
      Neg := (PI <= Length(P)) And ((P[PI] = '!') Or (P[PI] = '^'));
      If Neg Then Inc(PI);
      Ok := False;
      While (PI <= Length(P)) And (P[PI] <> ']') Do
      Begin
        If (PI + 2 <= Length(P)) And (P[PI + 1] = '-') And (P[PI + 2] <> ']') Then
        Begin
          If (C >= P[PI]) And (C <= P[PI + 2]) Then Ok := True;
          Inc(PI, 3);
        End
        Else
        Begin
          If C = P[PI] Then Ok := True;
          Inc(PI);
        End;
      End;
      Inc(PI);
      Inc(SI);
      If Ok = Neg Then
      Begin
        Match := False;
        Exit;
      End;
    End
    Else
    Begin
      If P[PI] = '\' Then Inc(PI);
      If (PI > Length(P)) Or (P[PI] <> S[SI]) Then
      Begin
        Match := False;
        Exit;
      End;
      Inc(PI);
      Inc(SI);
    End;
  End;
  Match := SI > Length(S);
End;

Function EmptyDir(Const Path : String) : Boolean;
Var D, Ino : LongInt; Nm : String;
Begin
  EmptyDir := True;
  D := SysOpenDir(Path);
  If D < 0 Then Exit;
  While SysReadDir(D, Nm, Ino) Do
    If (Nm <> '.') And (Nm <> '..') Then EmptyDir := False;
  SysCloseDir(D);
End;

Function CmpNum(V, N, Cmp : LongInt) : Boolean;
Begin
  If Cmp < 0 Then CmpNum := V < N
  Else If Cmp > 0 Then CmpNum := V > N
  Else CmpNum := V = N;
End;

Function Test(I : LongInt; Const Path, Name : String; Var St : TSysStat) : Boolean;
Var R : Boolean; T : LongInt; St2 : TSysStat;
Begin
  R := True;
  Case TKind[I] Of
    1 : R := Match(TStr[I], 1, Name, 1);
    2 : R := Match(Lower(TStr[I]), 1, Lower(Name), 1);
    3 : Begin
          T := St.Mode And $F000;
          If TStr[I] = 'f' Then R := T = $8000
          Else If TStr[I] = 'd' Then R := T = $4000
          Else If TStr[I] = 'l' Then R := T = $A000
          Else If TStr[I] = 'c' Then R := T = $2000
          Else If TStr[I] = 'b' Then R := T = $6000
          Else If TStr[I] = 'p' Then R := T = $1000
          Else R := False;
        End;
    4 : If (St.Mode And $F000) = $4000 Then R := EmptyDir(Path)
        Else R := St.Size = 0;
    5 : Begin
          If TStr[I] = 'c' Then T := St.Size
          Else If TStr[I] = 'k' Then T := (St.Size + 1023) Div 1024
          Else T := (St.Size + 511) Div 512;
          R := CmpNum(T, TNum[I], TCmp[I]);
        End;
    6 : R := CmpNum((Now1 - St.MTime) Div 86400, TNum[I], TCmp[I]);
    7 : R := St.MTime > NewerT;
    8 : R := St.Uid = TNum[I];
  End;
  If TNot[I] Then R := Not R;
  Test := R;
End;


Function FindExe(Const Name : String) : String;
Var Path, Dir : String; K : LongInt;
Begin
  FindExe := Name;
  If Pos('/', Name) > 0 Then Exit;
  Path := SysGetEnv('PATH');
  If Path = '' Then Path := '/bin:/usr/bin:/sbin:/usr/sbin';
  While Path <> '' Do
  Begin
    K := Pos(':', Path);
    If K = 0 Then
    Begin
      Dir := Path;
      Path := '';
    End
    Else
    Begin
      Dir := Copy(Path, 1, K - 1);
      Path := Copy(Path, K + 1, 255);
    End;
    If SysAccess(Dir + '/' + Name, 1) = 0 Then
    Begin
      FindExe := Dir + '/' + Name;
      Exit;
    End;
  End;
End;

Procedure RunExec(Const Path : String);
Var K, Pid, St : LongInt; A : String;
Begin
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysArgReset;
    For K := 1 To NExec Do
      If ExecArgs[K] = '{}' Then SysArgAdd(Path) Else SysArgAdd(ExecArgs[K]);
    SysEnvInherit;
    A := FindExe(ExecArgs[1]);
    SysArgExec(A);
    SysExit(127);
  End;
  SysWaitPid(Pid, St, 0);
End;

Procedure Visit(Path : String; Depth : LongInt);
Var St : TSysStat; I, D, Ino : LongInt; Nm, Name : String; Ok : Boolean;
Begin
  If SysLStat(Path, St) < 0 Then
  Begin
    Warn(Path);
    Rc := 1;
    Exit;
  End;
  Name := BaseOf(Path);
  If (Path = '/') Then Name := '/';
  If Depth >= MinD Then
  Begin
    Ok := True;
    For I := 1 To NTests Do
      If Ok And (Not Test(I, Path, Name, St)) Then Ok := False;
    If Ok Then
      Case Action Of
        0, 1 : SysPut(1, Path + #10);
        2 : SysPut(1, Path + #0);
        3 : If (St.Mode And $F000) = $4000 Then SysRmdir(Path) Else SysUnlink(Path);
        4 : RunExec(Path);
      End;
  End;
  If ((St.Mode And $F000) = $4000) And (Depth < MaxD) Then
  Begin
    D := SysOpenDir(Path);
    If D < 0 Then
    Begin
      Warn(Path);
      Rc := 1;
      Exit;
    End;
    While SysReadDir(D, Nm, Ino) Do
      If (Nm <> '.') And (Nm <> '..') Then
      Begin
        If Path[Length(Path)] = '/' Then Visit(Path + Nm, Depth + 1)
        Else Visit(Path + '/' + Nm, Depth + 1);
      End;
    SysCloseDir(D);
  End;
End;

Procedure AddTest(K : LongInt; Const S : String; N, Cmp : LongInt; Neg : Boolean);
Begin
  If NTests >= MAXT Then Exit;
  Inc(NTests);
  TKind[NTests] := K;
  TStr[NTests] := S;
  TNum[NTests] := N;
  TCmp[NTests] := Cmp;
  TNot[NTests] := Neg;
End;

Procedure NumArg(Const S : String; Var N, Cmp : LongInt; Var U : String);
Var T : String; Code : LongInt;
Begin
  Cmp := 0;
  T := S;
  If (T <> '') And (T[1] = '+') Then
  Begin
    Cmp := 1;
    T := Copy(T, 2, 40);
  End
  Else If (T <> '') And (T[1] = '-') Then
  Begin
    Cmp := -1;
    T := Copy(T, 2, 40);
  End;
  U := '';
  If (T <> '') And ((T[Length(T)] = 'c') Or (T[Length(T)] = 'k')) Then
  Begin
    U := T[Length(T)];
    T := Copy(T, 1, Length(T) - 1);
  End;
  Val(T, N, Code);
End;

Var
  I, N, Cmp : LongInt;
  A, U : String;
  Neg : Boolean;
  St : TSysStat;

BEGIN
  NRoots := 0;
  NTests := 0;
  Action := 0;
  MaxD := 100000;
  MinD := 0;
  NExec := 0;
  Rc := 0;
  Neg := False;
  Now1 := SysTime;
  I := 1;
  While (I < SysArgCount) And (SysArgStr(I) <> '') And
        (Copy(SysArgStr(I), 1, 1) <> '-') And (SysArgStr(I) <> '!') And
        (SysArgStr(I) <> '(') Do
  Begin
    If NRoots < 32 Then
    Begin
      Inc(NRoots);
      Roots[NRoots] := SysArgStr(I);
    End;
    Inc(I);
  End;
  If NRoots = 0 Then
  Begin
    NRoots := 1;
    Roots[1] := '.';
  End;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-name') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      AddTest(1, SysArgStr(I), 0, 0, Neg);
      Neg := False;
    End
    Else If (A = '-iname') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      AddTest(2, SysArgStr(I), 0, 0, Neg);
      Neg := False;
    End
    Else If (A = '-type') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      AddTest(3, SysArgStr(I), 0, 0, Neg);
      Neg := False;
    End
    Else If A = '-empty' Then
    Begin
      AddTest(4, '', 0, 0, Neg);
      Neg := False;
    End
    Else If (A = '-size') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      NumArg(SysArgStr(I), N, Cmp, U);
      AddTest(5, U, N, Cmp, Neg);
      Neg := False;
    End
    Else If (A = '-mtime') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      NumArg(SysArgStr(I), N, Cmp, U);
      AddTest(6, '', N, Cmp, Neg);
      Neg := False;
    End
    Else If (A = '-newer') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      If SysStat(SysArgStr(I), St) = 0 Then NewerT := St.MTime Else NewerT := 0;
      AddTest(7, '', 0, 0, Neg);
      Neg := False;
    End
    Else If (A = '-user') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), N, Cmp);
      If Cmp <> 0 Then N := 0;
      AddTest(8, '', N, 0, Neg);
      Neg := False;
    End
    Else If (A = '-maxdepth') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), MaxD, Cmp);
    End
    Else If (A = '-mindepth') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Val(SysArgStr(I), MinD, Cmp);
    End
    Else If (A = '-not') Or (A = '!') Then Neg := True
    Else If A = '-print' Then Action := 1
    Else If A = '-print0' Then Action := 2
    Else If A = '-delete' Then Action := 3
    Else If A = '-exec' Then
    Begin
      Action := 4;
      Inc(I);
      While (I < SysArgCount) And (SysArgStr(I) <> ';') And
            (SysArgStr(I) <> '+') Do
      Begin
        If NExec < 30 Then
        Begin
          Inc(NExec);
          ExecArgs[NExec] := SysArgStr(I);
        End;
        Inc(I);
      End;
    End
    Else If (A = '-a') Or (A = '-and') Then
    Begin
    End
    Else
    Begin
      SysPut(2, 'find: ' + A + #10);
      SysExit(1);
    End;
    Inc(I);
  End;
  If (Action = 4) And (NExec = 0) Then Usage('find [path...] [expression]');
  For I := 1 To NRoots Do Visit(Roots[I], 0);
  SysExit(Rc);
END.
