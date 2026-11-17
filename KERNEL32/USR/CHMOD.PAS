{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/chmod : modes Unix (chmod(2)), a la place de la version
   DOS de la racine du depot.
   chmod [-R] [-v] [-c] [-f] MODE FICHIER...
   MODE : octal (755, 4755) ou symbolique [ugoa]*([-+=][rwxXst]*|[ugo])
   separes par des virgules (u+x, go-w, a=rx, u=rwx,go=rx, +t, g+s, u+s).
   -R : recursif (les liens symboliques ne sont pas suivis). }

Program Chmod;

Var
  Recursive, Verbose, Quiet : Boolean;
  Spec : String;
  Errors : LongInt;

Function Octal(Const S : String; Var V : LongInt) : Boolean;
Var I : LongInt;
Begin
  Octal := False;
  If (S = '') Or (Length(S) > 4) Then Exit;
  V := 0;
  For I := 1 To Length(S) Do
  Begin
    If (S[I] < '0') Or (S[I] > '7') Then Exit;
    V := V * 8 + Ord(S[I]) - 48;
  End;
  Octal := True;
End;

{ applique la specification symbolique a Mode ; IsDir : pour X }
Function Symbolic(Const Sp : String; Mode : LongInt; IsDir : Boolean;
  Var Ok : Boolean) : LongInt;
Var I, Who, Op, Bits, P, Mask, Um : LongInt; C : Char; NoWho : Boolean;
Begin
  Ok := True;
  I := 1;
  While I <= Length(Sp) Do
  Begin
    Who := 0;
    While (I <= Length(Sp)) And (Sp[I] In ['u', 'g', 'o', 'a']) Do
    Begin
      Case Sp[I] Of
        'u' : Who := Who Or 1;
        'g' : Who := Who Or 2;
        'o' : Who := Who Or 4;
      Else
        Who := Who Or 7;
      End;
      Inc(I);
    End;
    If Who = 0 Then
    Begin
      Who := 7;
      NoWho := True;
    End
    Else NoWho := False;
    While (I <= Length(Sp)) And (Sp[I] In ['+', '-', '=']) Do
    Begin
      Op := Ord(Sp[I]);
      Inc(I);
      Bits := 0;
      If (I <= Length(Sp)) And (Sp[I] In ['u', 'g', 'o']) Then
      Begin
        { copie des droits d'une autre classe }
        Case Sp[I] Of
          'u' : P := (Mode Shr 6) And 7;
          'g' : P := (Mode Shr 3) And 7;
        Else
          P := Mode And 7;
        End;
        If (Who And 1) <> 0 Then Bits := Bits Or (P Shl 6);
        If (Who And 2) <> 0 Then Bits := Bits Or (P Shl 3);
        If (Who And 4) <> 0 Then Bits := Bits Or P;
        Inc(I);
      End
      Else
        While (I <= Length(Sp)) And (Sp[I] In ['r', 'w', 'x', 'X', 's', 't'])
        Do
        Begin
          C := Sp[I];
          Case C Of
            'r' : P := 4;
            'w' : P := 2;
            'x' : P := 1;
            'X' : If IsDir Or ((Mode And $49) <> 0) Then P := 1 Else P := 0;
          Else
            P := 0;
          End;
          If P > 0 Then
          Begin
            If (Who And 1) <> 0 Then Bits := Bits Or (P Shl 6);
            If (Who And 2) <> 0 Then Bits := Bits Or (P Shl 3);
            If (Who And 4) <> 0 Then Bits := Bits Or P;
          End
          Else If C = 's' Then
          Begin
            If (Who And 1) <> 0 Then Bits := Bits Or $800;
            If (Who And 2) <> 0 Then Bits := Bits Or $400;
          End
          Else If C = 't' Then Bits := Bits Or $200;
          Inc(I);
        End;
      { sans classe : le umask s'applique aux droits }
      If NoWho Then
      Begin
        Um := SysUmask(0);
        SysUmask(Um);
        Bits := Bits And Not (Um And $1FF);
      End;
      { masque des bits de la classe visee }
      Mask := 0;
      If (Who And 1) <> 0 Then Mask := Mask Or $1C0 Or $800;
      If (Who And 2) <> 0 Then Mask := Mask Or $38 Or $400;
      If (Who And 4) <> 0 Then Mask := Mask Or 7 Or $200;
      If Op = Ord('+') Then Mode := Mode Or Bits
      Else If Op = Ord('-') Then Mode := Mode And Not Bits
      Else
      Begin
        { sur un dossier, = ne retire pas setuid/setgid (comme GNU) }
        If IsDir Then Mask := Mask And Not $C00;
        Mode := (Mode And Not Mask) Or Bits;
      End;
    End;
    If (I <= Length(Sp)) And (Sp[I] = ',') Then Inc(I)
    Else If I <= Length(Sp) Then
    Begin
      Ok := False;
      Exit;
    End;
  End;
  Symbolic := Mode;
End;

Procedure One(Const Path : String);
Var St : TSysStat; M, New_, D, Ino : LongInt; Ok : Boolean; N : String;
Begin
  If SysLStat(Path, St) < 0 Then
  Begin
    If Not Quiet Then SysPut(2, 'chmod: ' + Path + ' : ' +
      SysErrorText(SysErrno) + #10);
    Inc(Errors);
    Exit;
  End;
  If (St.Mode And S_IFMT) <> S_IFLNK Then
  Begin
    M := St.Mode And $FFF;
    If Octal(Spec, New_) Then
    Begin
      { dossier : setuid/setgid conserves si le mode a 4 chiffres au plus }
      If ((St.Mode And S_IFMT) = S_IFDIR) And (Length(Spec) < 5) Then
        New_ := New_ Or (M And $C00);
    End
    Else
    Begin
      New_ := Symbolic(Spec, M, (St.Mode And S_IFMT) = S_IFDIR, Ok);
      If Not Ok Then
      Begin
        SysPut(2, 'chmod: mode invalide : ' + Spec + #10);
        SysExit(1);
      End;
    End;
    If SysChmod(Path, New_) < 0 Then
    Begin
      If Not Quiet Then SysPut(2, 'chmod: ' + Path + ' : ' +
        SysErrorText(SysErrno) + #10);
      Inc(Errors);
    End
    Else If Verbose Then SysPut(1, 'mode de ' + Path + ' modifie' + #10);
  End;
  If Recursive And ((St.Mode And S_IFMT) = S_IFDIR) Then
  Begin
    D := SysOpenDir(Path);
    If D < 0 Then Exit;
    While SysReadDir(D, N, Ino) Do
      If (N <> '.') And (N <> '..') Then One(Path + '/' + N);
    SysCloseDir(D);
  End;
End;

Var
  I, NF : LongInt;
  A : String;
Begin
  Recursive := False; Verbose := False; Quiet := False;
  Spec := '';
  NF := 0;
  Errors := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-R') Or (A = '--recursive') Then Recursive := True
    Else If (A = '-v') Or (A = '-c') Then Verbose := True
    Else If (A = '-f') Then Quiet := True
    Else If (Spec = '') And ((A[1] <> '-') Or (Length(A) > 1) And
            (A[2] In ['r', 'w', 'x', 'X', 's', 't', 'u', 'g', 'o', 'a']))
    Then Spec := A
    Else If A[1] = '-' Then
    Begin
      SysPut(2, 'chmod: option inconnue : ' + A + #10);
      SysExit(1);
    End
    Else
    Begin
      One(A);
      Inc(NF);
    End;
    Inc(I);
  End;
  If (Spec = '') Or (NF = 0) Then
  Begin
    SysPut(2, 'Usage: chmod [-R] MODE FICHIER...' + #10);
    SysExit(1);
  End;
  If Errors > 0 Then SysExit(1);
End.
