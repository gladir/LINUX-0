{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/chown, /bin/chgrp : change le proprietaire et le groupe (-R recursif, -h ignore) ; chgrp est ce programme sous un autre nom.
}

Program CHOWN;

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
  SysPut(2, 'chown: ' + What + ': ' + SysErrorText(SysErrno) + #10);
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

Var
  Grp : Boolean;
  Uid, Gid, Rc, I, N : LongInt;
  Rec : Boolean;
  A, Spec, UPart, GPart : String;

Function GidOf(Const Name : String) : LongInt;
Var Fd, K, Code : LongInt; L, F : String;
Begin
  GidOf := -1;
  Val(Name, K, Code);
  If (Code = 0) And (Name <> '') Then
  Begin
    GidOf := K;
    Exit;
  End;
  Fd := SysOpen('/etc/group', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
  Begin
    K := Pos(':', L);
    If (K > 0) And (Copy(L, 1, K - 1) = Name) Then
    Begin
      F := Copy(L, K + 1, 255);
      K := Pos(':', F);
      F := Copy(F, K + 1, 255);
      K := Pos(':', F);
      If K > 0 Then F := Copy(F, 1, K - 1);
      Val(F, K, Code);
      GidOf := K;
      Break;
    End;
  End;
  SysClose(Fd);
End;

Function UidOf(Const Name : String) : LongInt;
Var K, Code : LongInt; P : TSysPasswd;
Begin
  UidOf := -1;
  Val(Name, K, Code);
  If (Code = 0) And (Name <> '') Then
  Begin
    UidOf := K;
    Exit;
  End;
  If SysGetPwNam(Name, P) Then UidOf := P.Uid;
End;

Procedure Apply(Path : String);
Var St : TSysStat; D, Ino : LongInt; Nm : String;
Begin
  If SysChown(Path, Uid, Gid) < 0 Then
  Begin
    Warn(Path);
    Rc := 1;
  End;
  If Rec And (SysLStat(Path, St) = 0) And ((St.Mode And $F000) = $4000) Then
  Begin
    D := SysOpenDir(Path);
    If D >= 0 Then
    Begin
      While SysReadDir(D, Nm, Ino) Do
        If (Nm <> '.') And (Nm <> '..') Then
        Begin
          If Path[Length(Path)] = '/' Then Apply(Path + Nm)
          Else Apply(Path + '/' + Nm);
        End;
      SysCloseDir(D);
    End;
  End;
End;

BEGIN
  Grp := Pos('chgrp', SysArgStr(0)) > 0;
  Rec := False;
  Rc := 0;
  Uid := -1;
  Gid := -1;
  N := 0;
  For I := 1 To SysArgCount - 1 Do
  Begin
    A := SysArgStr(I);
    If (N = 0) And ((A = '-R') Or (A = '-r')) Then Rec := True
    Else If (N = 0) And (A = '-h') Then
    Begin
    End
    Else If N = 0 Then
    Begin
      Spec := A;
      N := 1;
      If Grp Then
      Begin
        Gid := GidOf(Spec);
        If Gid < 0 Then
        Begin
          SysPut(2, 'chgrp: ' + Spec + #10);
          SysExit(1);
        End;
      End
      Else
      Begin
        UPart := Spec;
        GPart := '';
        N := Pos(':', Spec);
        If N = 0 Then N := Pos('.', Spec);
        If N > 0 Then
        Begin
          UPart := Copy(Spec, 1, N - 1);
          GPart := Copy(Spec, N + 1, 255);
        End;
        N := 1;
        If UPart <> '' Then
        Begin
          Uid := UidOf(UPart);
          If Uid < 0 Then
          Begin
            SysPut(2, 'chown: ' + UPart + #10);
            SysExit(1);
          End;
        End;
        If GPart <> '' Then
        Begin
          Gid := GidOf(GPart);
          If Gid < 0 Then
          Begin
            SysPut(2, 'chown: ' + GPart + #10);
            SysExit(1);
          End;
        End;
      End;
    End
    Else
    Begin
      N := 2;
      Apply(A);
    End;
  End;
  If N < 2 Then Usage('chown [-R] owner[:group] file... | chgrp [-R] group file...');
  SysExit(Rc);
END.
