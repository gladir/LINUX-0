{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: iptables, iptables-save, iptables-restore (le nom lu dans
   argv[0]) : programme frontal et syntaxe de iptables. En attendant netfilter
   dans le noyau, les regles ne sont PAS appliquees : elles sont gardees au
   format iptables-save dans /var/lib/iptables.rules (IPTABLES_RULES=chemin) et
   un avertissement le rappelle sur l'erreur standard quand elles changent.
   iptables [-t table] -A|-I|-D chaine [n] regle | -F [chaine] | -L [chaine]
            [-n] [-v] | -S [chaine] | -P chaine cible | -N chaine | -X [chaine]
            | -Z
   regle : -p proto -s adresse -d adresse -i interface -o interface
           --sport p --dport p -m etat/--state ... -j cible
   Tables : filter (INPUT FORWARD OUTPUT), nat, mangle, raw. }

Program IpTables;

Const
  MaxR = 300;
  MaxC = 60;

Var
  RT, RC, RS : Array[0..MaxR - 1] Of String[100];   { table, chaine, regle }
  NR : LongInt;
  CT, CC, CP : Array[0..MaxC - 1] Of String[40];    { table, chaine, politique }
  NC : LongInt;
  Tbl, StateFile, Prog : String;
  Numeric, Verbose, Changed : Boolean;

Procedure Die(Const S : String);
Begin
  SysPut(2, Prog + ': ' + S + #10);
  SysExit(1);
End;

Function Word_(Const L : String; N : LongInt) : String;
Var I, K, S : LongInt;
Begin
  Word_ := '';
  I := 1;
  For K := 1 To N Do
  Begin
    While (I <= Length(L)) And (L[I] = ' ') Do Inc(I);
    S := I;
    While (I <= Length(L)) And (L[I] <> ' ') Do Inc(I);
    If K = N Then Word_ := Copy(L, S, I - S);
  End;
End;

Function Rest(Const L : String; N : LongInt) : String;
Var I, K : LongInt;
Begin
  I := 1;
  For K := 1 To N Do
  Begin
    While (I <= Length(L)) And (L[I] = ' ') Do Inc(I);
    While (I <= Length(L)) And (L[I] <> ' ') Do Inc(I);
  End;
  While (I <= Length(L)) And (L[I] = ' ') Do Inc(I);
  Rest := Copy(L, I, 200);
End;

Function FindChain(Const T, C : String) : LongInt;
Var I : LongInt;
Begin
  FindChain := -1;
  For I := 0 To NC - 1 Do
    If (CT[I] = T) And (CC[I] = C) Then FindChain := I;
End;

Procedure AddChain(Const T, C, P : String);
Begin
  If (FindChain(T, C) >= 0) Or (NC >= MaxC) Then Exit;
  CT[NC] := T; CC[NC] := C; CP[NC] := P;
  Inc(NC);
End;

Procedure Defaults;
Begin
  AddChain('filter', 'INPUT', 'ACCEPT');
  AddChain('filter', 'FORWARD', 'ACCEPT');
  AddChain('filter', 'OUTPUT', 'ACCEPT');
  AddChain('nat', 'PREROUTING', 'ACCEPT');
  AddChain('nat', 'INPUT', 'ACCEPT');
  AddChain('nat', 'OUTPUT', 'ACCEPT');
  AddChain('nat', 'POSTROUTING', 'ACCEPT');
  AddChain('mangle', 'PREROUTING', 'ACCEPT');
  AddChain('mangle', 'INPUT', 'ACCEPT');
  AddChain('mangle', 'FORWARD', 'ACCEPT');
  AddChain('mangle', 'OUTPUT', 'ACCEPT');
  AddChain('mangle', 'POSTROUTING', 'ACCEPT');
  AddChain('raw', 'PREROUTING', 'ACCEPT');
  AddChain('raw', 'OUTPUT', 'ACCEPT');
End;

Procedure AddRule(Const T, C, R : String; Pos : LongInt);
Var I, K, Cnt : LongInt;
Begin
  If NR >= MaxR Then Die('trop de regles');
  K := NR;
  If Pos > 0 Then
  Begin
    { insertion avant la Pos-ieme regle de la chaine }
    Cnt := 0;
    K := NR;
    For I := 0 To NR - 1 Do
      If (RT[I] = T) And (RC[I] = C) Then
      Begin
        Inc(Cnt);
        If Cnt = Pos Then
        Begin
          K := I;
          Break;
        End;
      End;
    For I := NR DownTo K + 1 Do
    Begin
      RT[I] := RT[I - 1]; RC[I] := RC[I - 1]; RS[I] := RS[I - 1];
    End;
  End;
  RT[K] := T; RC[K] := C; RS[K] := R;
  Inc(NR);
End;

Procedure DelRuleAt(K : LongInt);
Var I : LongInt;
Begin
  For I := K To NR - 2 Do
  Begin
    RT[I] := RT[I + 1]; RC[I] := RC[I + 1]; RS[I] := RS[I + 1];
  End;
  Dec(NR);
End;

Procedure Load;
Var F : LongInt; L, T, K : String;
Begin
  NR := 0;
  NC := 0;
  Defaults;
  F := SysOpen(StateFile, O_RDONLY, 0);
  If F < 0 Then Exit;
  T := 'filter';
  While SysReadLine(F, L) Do
  Begin
    If (L = '') Or (L[1] = '#') Then Continue;
    If L[1] = '*' Then T := Copy(L, 2, 20)
    Else If L[1] = ':' Then
    Begin
      K := Copy(Word_(L, 1), 2, 40);
      If FindChain(T, K) >= 0 Then CP[FindChain(T, K)] := Word_(L, 2)
      Else AddChain(T, K, Word_(L, 2));
    End
    Else If Copy(L, 1, 3) = '-A ' Then AddRule(T, Word_(L, 2), Rest(L, 2), 0);
  End;
  SysClose(F);
End;

Procedure Save;
Var F, I, K : LongInt; L : String; Tables : Array[0..3] Of String[8];
Begin
  SysMkdir('/var', 493);
  SysMkdir('/var/lib', 493);
  F := SysOpen(StateFile, O_WRONLY Or O_CREAT Or O_TRUNC, 384);
  If F < 0 Then Die(StateFile + ' : ' + SysErrorText(SysErrno));
  Tables[0] := 'raw'; Tables[1] := 'mangle'; Tables[2] := 'nat';
  Tables[3] := 'filter';
  For K := 0 To 3 Do
  Begin
    L := '*' + Tables[K] + #10;
    SysWrite(F, L[1], Length(L));
    For I := 0 To NC - 1 Do
      If CT[I] = Tables[K] Then
      Begin
        If CP[I] = '' Then CP[I] := '-';
        L := ':' + CC[I] + ' ' + CP[I] + ' [0:0]' + #10;
        SysWrite(F, L[1], Length(L));
      End;
    For I := 0 To NR - 1 Do
      If RT[I] = Tables[K] Then
      Begin
        L := '-A ' + RC[I] + ' ' + RS[I] + #10;
        SysWrite(F, L[1], Length(L));
      End;
    L := 'COMMIT' + #10;
    SysWrite(F, L[1], Length(L));
  End;
  SysClose(F);
End;

Function IsBuiltin(Const T, C : String) : Boolean;
Var I : LongInt;
Begin
  I := FindChain(T, C);
  IsBuiltin := (I >= 0) And (CP[I] <> '-');
End;

{ adresse pour -L : anywhere ou la valeur }
Function Addr(Const A : String) : String;
Begin
  If (A = '') Or (A = '0.0.0.0/0') Then
  Begin
    If Numeric Then Addr := '0.0.0.0/0' Else Addr := 'anywhere';
  End
  Else Addr := A;
End;

Function Opt(Const R, O : String) : String;
Var I : LongInt; W : String;
Begin
  Opt := '';
  I := 1;
  While Word_(R, I) <> '' Do
  Begin
    W := Word_(R, I);
    If (W = O) Or (('!' = W) And (Word_(R, I + 1) = O)) Then
    Begin
      If W = '!' Then Opt := '!' + Word_(R, I + 2) Else Opt := Word_(R, I + 1);
      Exit;
    End;
    Inc(I);
  End;
End;

Function ServName(Const P : String) : String;
Begin
  ServName := P;
  If Numeric Then Exit;
  If P = '22' Then ServName := 'ssh'
  Else If P = '80' Then ServName := 'http'
  Else If P = '443' Then ServName := 'https'
  Else If P = '25' Then ServName := 'smtp'
  Else If P = '53' Then ServName := 'domain'
  Else If P = '23' Then ServName := 'telnet';
End;

Procedure ListChain(Const T, C : String);
Var I, N : LongInt; R, Pr, X, Tg, Ex, Pol : String;
Begin
  I := FindChain(T, C);
  If I < 0 Then Die('Chain ' + C + ' inconnue');
  If CP[I] = '-' Then
    SysPut(1, 'Chain ' + C + ' (0 references)' + #10)
  Else
    SysPut(1, 'Chain ' + C + ' (policy ' + CP[I] + ')' + #10);
  SysPut(1, 'target     prot opt source               destination' + #10);
  For N := 0 To NR - 1 Do
    If (RT[N] = T) And (RC[N] = C) Then
    Begin
      R := RS[N];
      Tg := Opt(R, '-j');
      Pr := Opt(R, '-p');
      If Pr = '' Then Pr := 'all';
      Ex := '';
      If Opt(R, '--sport') <> '' Then Ex := Ex + ' spt:' + ServName(Opt(R,
        '--sport'));
      If Opt(R, '--dport') <> '' Then Ex := Ex + ' dpt:' + ServName(Opt(R,
        '--dport'));
      If Opt(R, '--state') <> '' Then Ex := Ex + ' state ' + Opt(R, '--state');
      If Opt(R, '-i') <> '' Then Ex := Ex + ' in:' + Opt(R, '-i');
      If Opt(R, '-o') <> '' Then Ex := Ex + ' out:' + Opt(R, '-o');
      If (Pr <> 'all') And (Ex <> '') Then Ex := ' ' + Pr + Ex;
      While Length(Tg) < 10 Do Tg := Tg + ' ';
      X := Pr;
      While Length(X) < 5 Do X := X + ' ';
      Pol := Addr(Opt(R, '-s'));
      While Length(Pol) < 21 Do Pol := Pol + ' ';
      SysPut(1, Tg + ' ' + X + '--  ' + Pol + Addr(Opt(R, '-d')) + Ex + #10);
    End;
End;

Var
  I, K, Pos, Nth : LongInt;
  A, Cmd, Ch, Arg, Rule, Pol : String;
  Dummy : LongInt;
  F : LongInt; L, T : String;
Begin
  Prog := SysArgStr(0);
  K := Length(Prog);
  While (K > 0) And (Prog[K] <> '/') Do Dec(K);
  Prog := Copy(Prog, K + 1, 30);
  StateFile := SysGetEnv('IPTABLES_RULES');
  If StateFile = '' Then StateFile := '/var/lib/iptables.rules';
  Tbl := 'filter';
  Numeric := False;
  Verbose := False;
  Changed := False;
  Load;
  If Prog = 'iptables-save' Then
  Begin
    Save;
    F := SysOpen(StateFile, O_RDONLY, 0);
    If F >= 0 Then
    Begin
      While SysReadLine(F, L) Do SysPut(1, L + #10);
      SysClose(F);
    End;
    SysExit(0);
  End;
  If Prog = 'iptables-restore' Then
  Begin
    NR := 0;
    NC := 0;
    T := 'filter';
    While SysReadLine(0, L) Do
    Begin
      If (L = '') Or (L[1] = '#') Then Continue;
      If L[1] = '*' Then T := Copy(L, 2, 20)
      Else If L[1] = ':' Then AddChain(T, Copy(Word_(L, 1), 2, 40), Word_(L, 2))
      Else If Copy(L, 1, 3) = '-A ' Then AddRule(T, Word_(L, 2), Rest(L, 2), 0);
    End;
    Save;
    SysExit(0);
  End;
  Cmd := '';
  Ch := '';
  Arg := '';
  Rule := '';
  Pos := 0;
  I := 1;
  While I < SysArgCount Do
  Begin
    A := SysArgStr(I);
    If (A = '-t') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Tbl := SysArgStr(I);
    End
    Else If A = '-n' Then Numeric := True
    Else If A = '-v' Then Verbose := True
    Else If (A = '-A') Or (A = '-I') Or (A = '-D') Or (A = '-F') Or
            (A = '-L') Or (A = '-S') Or (A = '-P') Or (A = '-N') Or
            (A = '-X') Or (A = '-Z') Then
    Begin
      Cmd := A;
      If (I + 1 < SysArgCount) And (SysArgStr(I + 1)[1] <> '-') Then
      Begin
        Inc(I);
        Ch := SysArgStr(I);
        If ((A = '-I') Or (A = '-D')) And (I + 1 < SysArgCount) And
           (SysArgStr(I + 1)[1] >= '0') And (SysArgStr(I + 1)[1] <= '9') Then
        Begin
          Inc(I);
          Val(SysArgStr(I), Pos, Dummy);
        End;
        If (A = '-P') And (I + 1 < SysArgCount) Then
        Begin
          Inc(I);
          Pol := SysArgStr(I);
        End;
      End;
    End
    Else If A = '-m' Then
    Begin
      Rule := Rule + ' -m ' + SysArgStr(I + 1);
      Inc(I);
    End
    Else If (A = '-h') Or (A = '--help') Then
    Begin
      SysPut(1, 'Usage: iptables [-t table] -A|-I|-D|-F|-L|-S|-P|-N|-X|-Z' +
             ' chaine [regle] ; -p -s -d -i -o --sport --dport --state -j' +
             #10);
      SysExit(0);
    End
    Else
    Begin
      If Rule <> '' Then Rule := Rule + ' ';
      Rule := Rule + A;
    End;
    Inc(I);
  End;
  While (Length(Rule) > 0) And (Rule[1] = ' ') Do Delete(Rule, 1, 1);
  If Cmd = '' Then Die('commande manquante');
  If (Ch <> '') And (FindChain(Tbl, Ch) < 0) And (Cmd <> '-N') Then
    Die('Chain ' + Ch + ' inconnue dans la table ' + Tbl);
  If Cmd = '-A' Then
  Begin
    If Ch = '' Then Die('chaine manquante');
    AddRule(Tbl, Ch, Rule, 0);
    Changed := True;
  End
  Else If Cmd = '-I' Then
  Begin
    AddRule(Tbl, Ch, Rule, Pos);
    Changed := True;
  End
  Else If Cmd = '-D' Then
  Begin
    Nth := 0;
    K := -1;
    For I := 0 To NR - 1 Do
      If (RT[I] = Tbl) And (RC[I] = Ch) Then
      Begin
        Inc(Nth);
        If ((Pos > 0) And (Nth = Pos)) Or ((Pos = 0) And (RS[I] = Rule)) Then
        Begin
          K := I;
          Break;
        End;
      End;
    If K < 0 Then Die('regle introuvable');
    DelRuleAt(K);
    Changed := True;
  End
  Else If Cmd = '-F' Then
  Begin
    K := 0;
    While K < NR Do
      If (RT[K] = Tbl) And ((Ch = '') Or (RC[K] = Ch)) Then DelRuleAt(K)
      Else Inc(K);
    Changed := True;
  End
  Else If Cmd = '-P' Then
  Begin
    If Not IsBuiltin(Tbl, Ch) Then Die('politique : chaine predefinie requise');
    If (Pol <> 'ACCEPT') And (Pol <> 'DROP') Then Die('cible invalide : ' +
      Pol);
    CP[FindChain(Tbl, Ch)] := Pol;
    Changed := True;
  End
  Else If Cmd = '-N' Then
  Begin
    If FindChain(Tbl, Ch) >= 0 Then Die('Chain already exists');
    AddChain(Tbl, Ch, '-');
    Changed := True;
  End
  Else If Cmd = '-X' Then
  Begin
    K := 0;
    While K < NC Do
      If (CT[K] = Tbl) And (CP[K] = '-') And ((Ch = '') Or (CC[K] = Ch)) Then
      Begin
        For I := K To NC - 2 Do
        Begin
          CT[I] := CT[I + 1]; CC[I] := CC[I + 1]; CP[I] := CP[I + 1];
        End;
        Dec(NC);
      End
      Else Inc(K);
    Changed := True;
  End
  Else If Cmd = '-Z' Then
  Begin
  End
  Else If Cmd = '-L' Then
  Begin
    If Ch <> '' Then ListChain(Tbl, Ch)
    Else
      For I := 0 To NC - 1 Do
        If CT[I] = Tbl Then
        Begin
          ListChain(Tbl, CC[I]);
          SysPut(1, #10);
        End;
  End
  Else If Cmd = '-S' Then
  Begin
    For I := 0 To NC - 1 Do
      If (CT[I] = Tbl) And ((Ch = '') Or (CC[I] = Ch)) Then
        If CP[I] = '-' Then SysPut(1, '-N ' + CC[I] + #10)
        Else SysPut(1, '-P ' + CC[I] + ' ' + CP[I] + #10);
    For I := 0 To NR - 1 Do
      If (RT[I] = Tbl) And ((Ch = '') Or (RC[I] = Ch)) Then
        SysPut(1, '-A ' + RC[I] + ' ' + RS[I] + #10);
  End;
  If Changed Then
  Begin
    Save;
    SysPut(2, Prog + ': noyau sans netfilter : regles enregistrees dans ' +
           StateFile + ', non appliquees' + #10);
  End;
End.
