{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/test et /bin/[ : evaluation d'expressions conditionnelles
      POSIX : -e -f -d -r -w -x -s -L -h -b -c -p -S -t -z -n, = == != < >,
      -eq -ne -lt -le -gt -ge, -nt -ot -ef, ! ( ) -a -o.
}

Program TEST;

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');

Var
  Args : Array[1..128] Of String;
  N, P : LongInt;
  Err : Boolean;

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

Procedure Fail(Const Msg : String);
Begin
  SysPut(2, 'test: ' + Msg + #10);
  SysExit(2);
End;

Function ToInt(Const S : String) : LongInt;
Var V, E : LongInt;
Begin
  Val(S, V, E);
  If E <> 0 Then Fail(S + ' : nombre entier attendu');
  ToInt := V;
End;

Function FileTest(Op, F : String) : Boolean;
Var St : TSysStat; M : LongInt; R : Boolean;
Begin
  FileTest := False;
  If Op = '-L' Then
  Begin
    FileTest := (SysLStat(F, St) = 0) And ((St.Mode And $F000) = $A000);
    Exit;
  End;
  If Op = '-h' Then
  Begin
    FileTest := (SysLStat(F, St) = 0) And ((St.Mode And $F000) = $A000);
    Exit;
  End;
  If SysStat(F, St) <> 0 Then Exit;
  M := St.Mode And $F000;
  R := False;
  If Op = '-e' Then R := True
  Else If Op = '-f' Then R := M = $8000
  Else If Op = '-d' Then R := M = $4000
  Else If Op = '-b' Then R := M = $6000
  Else If Op = '-c' Then R := M = $2000
  Else If Op = '-p' Then R := M = $1000
  Else If Op = '-S' Then R := M = $C000
  Else If Op = '-s' Then R := St.Size > 0
  Else If Op = '-r' Then R := SysAccess(F, 4) = 0
  Else If Op = '-w' Then R := SysAccess(F, 2) = 0
  Else If Op = '-x' Then R := SysAccess(F, 1) = 0
  Else If Op = '-u' Then R := (St.Mode And $800) <> 0
  Else If Op = '-g' Then R := (St.Mode And $400) <> 0
  Else If Op = '-k' Then R := (St.Mode And $200) <> 0
  Else If Op = '-O' Then R := St.Uid = SysGetEUid
  Else If Op = '-G' Then R := St.Gid = SysGetEGid;
  FileTest := R;
End;

Function IsUnary(Const S : String) : Boolean;
Begin
  IsUnary := (Length(S) = 2) And (S[1] = '-') And
             (Pos(S[2], 'efdbcpSsrwxLhugkOGtzn') > 0);
End;

Function IsBinary(Const S : String) : Boolean;
Begin
  IsBinary := (S = '=') Or (S = '==') Or (S = '!=') Or (S = '<') Or
    (S = '>') Or (S = '-eq') Or (S = '-ne') Or (S = '-lt') Or (S = '-le') Or
    (S = '-gt') Or (S = '-ge') Or (S = '-nt') Or (S = '-ot') Or (S = '-ef');
End;

Function Cmp3(Const Op, A, B : String) : Boolean;
Var X, Y : LongInt; S1, S2 : TSysStat; R1, R2 : LongInt;
Begin
  Cmp3 := False;
  If Op = '=' Then Cmp3 := A = B
  Else If Op = '==' Then Cmp3 := A = B
  Else If Op = '!=' Then Cmp3 := A <> B
  Else If Op = '<' Then Cmp3 := A < B
  Else If Op = '>' Then Cmp3 := A > B
  Else If Op = '-nt' Then
  Begin
    R1 := SysStat(A, S1);
    R2 := SysStat(B, S2);
    Cmp3 := ((R1 = 0) And (R2 <> 0)) Or
            ((R1 = 0) And (R2 = 0) And (S1.MTime > S2.MTime));
  End
  Else If Op = '-ot' Then
  Begin
    R1 := SysStat(A, S1);
    R2 := SysStat(B, S2);
    Cmp3 := ((R1 <> 0) And (R2 = 0)) Or
            ((R1 = 0) And (R2 = 0) And (S1.MTime < S2.MTime));
  End
  Else If Op = '-ef' Then
  Begin
    R1 := SysStat(A, S1);
    R2 := SysStat(B, S2);
    Cmp3 := (R1 = 0) And (R2 = 0) And (S1.Dev = S2.Dev) And
            (S1.Ino = S2.Ino);
  End
  Else
  Begin
    X := ToInt(A);
    Y := ToInt(B);
    If Op = '-eq' Then Cmp3 := X = Y
    Else If Op = '-ne' Then Cmp3 := X <> Y
    Else If Op = '-lt' Then Cmp3 := X < Y
    Else If Op = '-le' Then Cmp3 := X <= Y
    Else If Op = '-gt' Then Cmp3 := X > Y
    Else If Op = '-ge' Then Cmp3 := X >= Y;
  End;
End;

Function ParseOr : Boolean; Forward;

Function ParsePrimary : Boolean;
Var R : Boolean; Op : String; Fd, E : LongInt;
Begin
  ParsePrimary := False;
  If P > N Then Fail('expression attendue');
  Op := Args[P];
  If Op = '(' Then
  Begin
    Inc(P);
    R := ParseOr;
    If (P > N) Or (Args[P] <> ')') Then Fail(') attendue');
    Inc(P);
    ParsePrimary := R;
    Exit;
  End;
  If Op = '!' Then
  Begin
    If (P < N) Then
    Begin
      Inc(P);
      ParsePrimary := Not ParsePrimary;
      Exit;
    End;
  End;
  { binaire : A op B }
  If (P + 2 <= N) And IsBinary(Args[P + 1]) And
     Not ((Args[P + 1] = '-a') Or (Args[P + 1] = '-o')) Then
  Begin
    ParsePrimary := Cmp3(Args[P + 1], Args[P], Args[P + 2]);
    P := P + 3;
    Exit;
  End;
  If (P + 1 <= N) And IsUnary(Op) And (P + 1 <= N) Then
  Begin
    If Op = '-t' Then
    Begin
      Val(Args[P + 1], Fd, E);
      ParsePrimary := (E = 0) And SysIsATty(Fd);
    End
    Else If Op = '-z' Then ParsePrimary := Args[P + 1] = ''
    Else If Op = '-n' Then ParsePrimary := Args[P + 1] <> ''
    Else ParsePrimary := FileTest(Op, Args[P + 1]);
    P := P + 2;
    Exit;
  End;
  { chaine seule : vraie si non vide }
  ParsePrimary := Op <> '';
  Inc(P);
End;

Function ParseAnd : Boolean;
Var R : Boolean;
Begin
  R := ParsePrimary;
  While (P <= N) And (Args[P] = '-a') Do
  Begin
    Inc(P);
    If Not ParsePrimary Then R := False;
  End;
  ParseAnd := R;
End;

Function ParseOr : Boolean;
Var R : Boolean;
Begin
  R := ParseAnd;
  While (P <= N) And (Args[P] = '-o') Do
  Begin
    Inc(P);
    If ParseAnd Then R := True;
  End;
  ParseOr := R;
End;

Var
  I, NA : LongInt;
  Prog : String;
  R : Boolean;
Begin
  NA := SysArgCount;
  Prog := SysArgStr(0);
  I := Length(Prog);
  While (I > 0) And (Prog[I] <> '/') Do Dec(I);
  Prog := Copy(Prog, I + 1, 255);
  N := 0;
  For I := 1 To NA - 1 Do
    If N < 128 Then
    Begin
      Inc(N);
      Args[N] := SysArgStr(I);
    End;
  If Prog = '[' Then
  Begin
    If (N = 0) Or (Args[N] <> ']') Then Fail('] manquant');
    Dec(N);
  End;
  If N = 0 Then SysExit(1);
  P := 1;
  R := ParseOr;
  If P <= N Then Fail('argument en trop : ' + Args[P]);
  If R Then SysExit(0) Else SysExit(1);
End.
