{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: /bin/sed : editeur de flux (GNU sed) : commandes s y d D p P
      n N g G h H x q Q l = a i c r R w W b t T : { } z F, adresses (N, $,
      /re/, \cREc, N~M, A,+N, A,~N, 0,/re/, !), BRE/ERE, -n -e -f -E -r -i
      -s -z -l -u, remplacements & \1..\9 \U \L \u \l \E \n.
}

Program SED;

{$I REGEX.INC}

Const
  UsageW : Array[1..5] Of PChar =
    ('Usage : ', 'Usage: ', 'Aufruf: ', 'Uso: ', 'Uso: ');
  LM = 262143;
  MaxCmd = 600;
  PoolMax = 65535;
  ScrMax = 65535;

Type
  TCmd = Record
    Ch : Char;
    Neg, Active, GFlag, PFlag, IFlag : Boolean;
    K1, K2 : Byte;
    N1, N2, Step : LongInt;
    R1, R2 : LongInt;
    TxtS, TxtL : LongInt;
    Tgt : LongInt;
    Re, ReplS, ReplL, Nth, WFd, EndLine : LongInt;
  End;

Var
  Cmds : Array[1..MaxCmd] Of TCmd;
  NCmd : LongInt;
  Pool : Array[0..PoolMax] Of Char;
  PoolN : LongInt;
  Scr : Array[0..ScrMax] Of Char;
  ScrN, SP : LongInt;
  Pat, Tmp, Hold, LA : Array[0..LM] Of Char;
  PLen, HLen, LALen, TLen : LongInt;
  LAValid, LANoNL, CurNoNL, HoldNoNL : Boolean;
  OutBuf : Array[0..32767] Of Char;
  OutN : LongInt;
  OutFd : LongInt;
  InBuf : Array[0..65535] Of Byte;
  InPos, InLen, InFd : LongInt;
  Files : Array[1..64] Of String;
  NFiles, FileIdx : LongInt;
  OptN, OptE, OptI, OptS, OptZ, OptU : Boolean;
  Suffix : String;
  LineW : LongInt;
  LineNo : LongInt;
  LastRe : LongInt;
  Sep : Char;
  ExitCode : LongInt;
  Quit, PendNL, Replaced : Boolean;
  AppQ : Array[0..99] Of LongInt;
  AppK : Array[0..99] Of LongInt;
  AppS, AppL : Array[0..99] Of LongInt;
  NApp : LongInt;
  CurName, TmpName : String;
  NoMoreInput : Boolean;
  Stack : Array[0..63] Of LongInt;
  WNames : Array[1..16] Of String;
  WFds : Array[1..16] Of LongInt;
  NW : LongInt;
  RFd : Array[1..16] Of LongInt;
  RNames : Array[1..16] Of String;
  NR : LongInt;

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

Procedure FlushOut;
Begin
  If OutN > 0 Then SysWrite(OutFd, OutBuf[0], OutN);
  OutN := 0;
End;

Procedure OutC(C : Char);
Begin
  If OutN >= 32768 Then FlushOut;
  OutBuf[OutN] := C;
  Inc(OutN);
End;

Procedure OutMem(Base, N : LongInt);
Var K : LongInt;
Begin
  For K := 0 To N - 1 Do OutC(Chr(Mem[0:Base + K]));
End;

Procedure OutS(Const S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do OutC(S[K]);
End;

Procedure Die(Const Msg : String; Code : LongInt);
Begin
  FlushOut;
  SysPut(2, 'sed: ' + Msg + #10);
  SysExit(Code);
End;

Procedure Usage;
Begin
  SysPut(2, PS(UsageW[SysLang]) +
    'sed [-nErsziu] [-l N] [-i[SUFFIXE]] (-e script | -f fichier | script) ' +
    '[fichier...]' + #10);
  SysExit(1);
End;

{ ---------- analyse du script ---------- }

Function SCh : Char;
Begin
  If SP < ScrN Then SCh := Scr[SP] Else SCh := #0;
End;

Procedure SkipWs;
Begin
  While (SP < ScrN) And ((Scr[SP] = ' ') Or (Scr[SP] = #9)) Do Inc(SP);
End;

Procedure SkipSp;
Begin
  While (SP < ScrN) And ((Scr[SP] = ' ') Or (Scr[SP] = #9) Or
        (Scr[SP] = #10) Or (Scr[SP] = ';')) Do Inc(SP);
End;

Function ReadNumS : LongInt;
Var N : LongInt;
Begin
  N := 0;
  While (SP < ScrN) And (Scr[SP] >= '0') And (Scr[SP] <= '9') Do
  Begin
    N := N * 10 + Ord(Scr[SP]) - 48;
    Inc(SP);
  End;
  ReadNumS := N;
End;

{ lit un motif delimite par D ; \D devient D ; \n -> LF ; \t -> TAB }
Function ReadDelim(D : Char; Regex : Boolean) : String;
Var R : String; C : Char; InBr : Boolean;
Begin
  R := '';
  InBr := False;
  While SP < ScrN Do
  Begin
    C := Scr[SP];
    If (C = D) And (Not InBr) Then Break;
    If C = '\' Then
    Begin
      Inc(SP);
      If SP >= ScrN Then Break;
      C := Scr[SP];
      If C = D Then R := R + D
      Else If C = 'n' Then R := R + #10
      Else If (C = 't') And Regex Then R := R + #9
      Else R := R + '\' + C;
      Inc(SP);
      Continue;
    End;
    If Regex Then
    Begin
      If (C = '[') And (Not InBr) Then
      Begin
        InBr := True;
        R := R + C;
        Inc(SP);
        If (SP < ScrN) And (Scr[SP] = '^') Then
        Begin
          R := R + '^';
          Inc(SP);
        End;
        If (SP < ScrN) And (Scr[SP] = ']') Then
        Begin
          R := R + ']';
          Inc(SP);
        End;
        Continue;
      End;
      If (C = ']') And InBr Then InBr := False;
    End;
    R := R + C;
    Inc(SP);
  End;
  If (SP >= ScrN) Or (Scr[SP] <> D) Then Die('script incomplet', 1);
  Inc(SP);
  ReadDelim := R;
End;

Function CompileRe(Const P : String; Ico : Boolean) : LongInt;
Var Pr : LongInt;
Begin
  If P = '' Then
  Begin
    CompileRe := -2;
    Exit;
  End;
  Pr := ReCompile(P, OptE, Ico);
  If Pr < 0 Then Die('-e expression : ' + ReErr, 1);
  CompileRe := Pr;
End;

Function PoolPut(Const S : String) : LongInt;
Var K : LongInt;
Begin
  PoolPut := PoolN;
  For K := 1 To Length(S) Do
  Begin
    If PoolN < PoolMax Then
    Begin
      Pool[PoolN] := S[K];
      Inc(PoolN);
    End;
  End;
End;

Procedure ParseAddr(Var K : Byte; Var N, Step, R : LongInt);
Var C : Char; Ico : Boolean; Pt : String; D : Char;
Begin
  K := 0;
  C := SCh;
  If (C >= '0') And (C <= '9') Then
  Begin
    N := ReadNumS;
    K := 1;
    If SCh = '~' Then
    Begin
      Inc(SP);
      Step := ReadNumS;
      K := 4;
    End;
  End
  Else If C = '$' Then
  Begin
    Inc(SP);
    K := 2;
  End
  Else If (C = '/') Or (C = '\') Then
  Begin
    If C = '\' Then
    Begin
      Inc(SP);
      D := SCh;
    End
    Else D := '/';
    Inc(SP);
    Pt := ReadDelim(D, True);
    Ico := False;
    While (SCh = 'I') Or (SCh = 'M') Do
    Begin
      If SCh = 'I' Then Ico := True;
      Inc(SP);
    End;
    R := CompileRe(Pt, Ico);
    K := 3;
  End;
End;

Procedure ParseText(Var C : TCmd);
Var T : String; Ch : Char;
Begin
  { a\ texte, a texte (GNU) }
  SkipWs;
  If SCh = '\' Then
  Begin
    Inc(SP);
    SkipWs;
    If SCh = #10 Then Inc(SP);
  End;
  T := '';
  While SP < ScrN Do
  Begin
    Ch := Scr[SP];
    If Ch = '\' Then
    Begin
      Inc(SP);
      If SP < ScrN Then
      Begin
        T := T + Scr[SP];
        Inc(SP);
      End;
      Continue;
    End;
    If Ch = #10 Then Break;
    T := T + Ch;
    Inc(SP);
  End;
  C.TxtS := PoolPut(T + #10);
  C.TxtL := Length(T) + 1;
End;

Function ReadLabel : String;
Var L : String;
Begin
  SkipWs;
  L := '';
  While (SP < ScrN) And (Scr[SP] <> #10) And (Scr[SP] <> ';') And
        (Scr[SP] <> ' ') And (Scr[SP] <> '}') Do
  Begin
    L := L + Scr[SP];
    Inc(SP);
  End;
  ReadLabel := L;
End;

Function ReadFileName : String;
Var L : String;
Begin
  SkipWs;
  L := '';
  While (SP < ScrN) And (Scr[SP] <> #10) Do
  Begin
    L := L + Scr[SP];
    Inc(SP);
  End;
  ReadFileName := L;
End;

Function OpenW(Const Nm : String) : LongInt;
Var K, Fd : LongInt;
Begin
  If Nm = '/dev/stdout' Then
  Begin
    OpenW := -1;
    Exit;
  End;
  If Nm = '/dev/stderr' Then
  Begin
    OpenW := 2;
    Exit;
  End;
  For K := 1 To NW Do
    If WNames[K] = Nm Then
    Begin
      OpenW := WFds[K];
      Exit;
    End;
  Fd := SysOpen(Nm, $241, 438);
  If Fd < 0 Then Die('impossible d''ouvrir ' + Nm + ' : ' +
    SysErrorText(SysErrno), 4);
  If NW < 16 Then
  Begin
    Inc(NW);
    WNames[NW] := Nm;
    WFds[NW] := Fd;
  End;
  OpenW := Fd;
End;

{ remplacement : suite d'elements (type, valeur) dans le pool }
Procedure ParseRepl(Var C : TCmd; Const R : String);
Var K : LongInt; Ch : Char; S : String;
Begin
  S := '';
  K := 1;
  While K <= Length(R) Do
  Begin
    Ch := R[K];
    If Ch = '\' Then
    Begin
      Inc(K);
      If K > Length(R) Then Break;
      Ch := R[K];
      If (Ch >= '0') And (Ch <= '9') Then S := S + #1 + Ch
      Else If (Ch = 'U') Or (Ch = 'L') Or (Ch = 'u') Or (Ch = 'l') Or
              (Ch = 'E') Then S := S + #2 + Ch
      Else If Ch = 'n' Then S := S + #0 + #10
      Else If Ch = 't' Then S := S + #0 + #9
      Else If Ch = #10 Then S := S + #0 + #10
      Else S := S + #0 + Ch;
    End
    Else If Ch = '&' Then S := S + #1 + '0'
    Else S := S + #0 + Ch;
    Inc(K);
  End;
  C.ReplS := PoolN;
  C.ReplL := Length(S);
  For K := 1 To Length(S) Do
  Begin
    If PoolN < PoolMax Then
    Begin
      Pool[PoolN] := S[K];
      Inc(PoolN);
    End;
  End;
End;

Procedure Parse;
Var
  C : Char; Idx, Top, K, Fl : LongInt;
  Rp, Pt, Lb : String;
  Lbls : Array[1..64] Of String;
  LblAt : Array[1..64] Of LongInt;
  NL : LongInt;
  Dc : Char;
  Ico, Done : Boolean;
Begin
  NCmd := 0;
  NL := 0;
  Top := 0;
  SP := 0;
  While True Do
  Begin
    SkipSp;
    If SP >= ScrN Then Break;
    If SCh = '#' Then
    Begin
      While (SP < ScrN) And (Scr[SP] <> #10) Do Inc(SP);
      Continue;
    End;
    If NCmd >= MaxCmd Then Die('script trop long', 1);
    Inc(NCmd);
    Idx := NCmd;
    FillChar(Cmds[Idx], SizeOf(TCmd), 0);
    Cmds[Idx].R1 := -1;
    Cmds[Idx].R2 := -1;
    Cmds[Idx].Tgt := -1;
    Cmds[Idx].WFd := -2;
    ParseAddr(Cmds[Idx].K1, Cmds[Idx].N1, Cmds[Idx].Step, Cmds[Idx].R1);
    If Cmds[Idx].K1 <> 0 Then
    Begin
      SkipWs;
      If SCh = ',' Then
      Begin
        Inc(SP);
        SkipWs;
        If SCh = '+' Then
        Begin
          Inc(SP);
          Cmds[Idx].N2 := ReadNumS;
          Cmds[Idx].K2 := 5;
        End
        Else If SCh = '~' Then
        Begin
          Inc(SP);
          Cmds[Idx].N2 := ReadNumS;
          Cmds[Idx].K2 := 6;
        End
        Else
        Begin
          ParseAddr(Cmds[Idx].K2, Cmds[Idx].N2, K, Cmds[Idx].R2);
          If Cmds[Idx].K2 = 0 Then Die('adresse inattendue', 1);
        End;
        If (Cmds[Idx].K1 = 1) And (Cmds[Idx].N1 = 0) And
           (Cmds[Idx].K2 = 3) Then Cmds[Idx].K1 := 7;
      End;
    End;
    SkipWs;
    While SCh = '!' Do
    Begin
      Cmds[Idx].Neg := True;
      Inc(SP);
      SkipWs;
    End;
    C := SCh;
    Inc(SP);
    Cmds[Idx].Ch := C;
    Case C Of
      '{' :
        Begin
          Inc(Top);
          Stack[Top] := Idx;
        End;
      '}' :
        Begin
          If Top = 0 Then Die('} inattendu', 1);
          Cmds[Stack[Top]].Tgt := Idx;
          Dec(Top);
        End;
      'a', 'i', 'c' : ParseText(Cmds[Idx]);
      ':' :
        Begin
          Lb := ReadLabel;
          If NL < 64 Then
          Begin
            Inc(NL);
            Lbls[NL] := Lb;
            LblAt[NL] := Idx;
          End;
        End;
      'b', 't', 'T' :
        Begin
          Lb := ReadLabel;
          Cmds[Idx].TxtS := PoolPut(Lb);
          Cmds[Idx].TxtL := Length(Lb);
        End;
      'r' :
        Begin
          Lb := ReadFileName;
          Cmds[Idx].TxtS := PoolPut(Lb);
          Cmds[Idx].TxtL := Length(Lb);
        End;
      'R' :
        Begin
          Lb := ReadFileName;
          Cmds[Idx].TxtS := PoolPut(Lb);
          Cmds[Idx].TxtL := Length(Lb);
        End;
      'w', 'W' :
        Begin
          Lb := ReadFileName;
          Cmds[Idx].WFd := OpenW(Lb);
        End;
      'q', 'Q', 'l', 'L' :
        Begin
          SkipWs;
          If (SCh >= '0') And (SCh <= '9') Then Cmds[Idx].N2 := ReadNumS
          Else Cmds[Idx].N2 := -1;
        End;
      's' :
        Begin
          Dc := SCh;
          Inc(SP);
          Pt := ReadDelim(Dc, True);
          Rp := ReadDelim(Dc, False);
          Cmds[Idx].Nth := 1;
          Ico := False;
          Done := False;
          While Not Done Do
          Begin
            Case SCh Of
              'g' : Begin Cmds[Idx].GFlag := True; Inc(SP); End;
              'p' : Begin Cmds[Idx].PFlag := True; Inc(SP); End;
              'i', 'I' : Begin Ico := True; Inc(SP); End;
              'm', 'M', 'e' : Inc(SP);
              '0'..'9' :
                Begin
                  Cmds[Idx].Nth := ReadNumS;
                  If Cmds[Idx].Nth < 1 Then Die('numero invalide', 1);
                End;
              'w' :
                Begin
                  Inc(SP);
                  Lb := ReadFileName;
                  Cmds[Idx].WFd := OpenW(Lb);
                  Done := True;
                End;
            Else
              Done := True;
            End;
          End;
          Cmds[Idx].Re := CompileRe(Pt, Ico);
          ParseRepl(Cmds[Idx], Rp);
          Cmds[Idx].IFlag := Ico;
        End;
      'y' :
        Begin
          Dc := SCh;
          Inc(SP);
          Pt := ReadDelim(Dc, False);
          Rp := ReadDelim(Dc, False);
          { dechiffre \\ et \n deja traites par ReadDelim : reste \\ }
          Fl := 0;
          While Fl < Length(Pt) Do
          Begin
            Inc(Fl);
            If (Pt[Fl] = '\') And (Fl < Length(Pt)) And
               (Pt[Fl + 1] = '\') Then
            Begin
              Delete(Pt, Fl, 1);
            End;
          End;
          Fl := 0;
          While Fl < Length(Rp) Do
          Begin
            Inc(Fl);
            If (Rp[Fl] = '\') And (Fl < Length(Rp)) And
               (Rp[Fl + 1] = '\') Then
            Begin
              Delete(Rp, Fl, 1);
            End;
          End;
          If Length(Pt) <> Length(Rp) Then
            Die('y : les chaines n''ont pas la meme longueur', 1);
          Cmds[Idx].TxtS := PoolPut(Pt + Rp);
          Cmds[Idx].TxtL := Length(Pt);
        End;
      '=', 'd', 'D', 'g', 'G', 'h', 'H', 'n', 'N', 'p', 'P', 'x', 'z',
      'F' : ;
    Else
      Die('commande inconnue : ' + C, 1);
    End;
    SkipWs;
    If (SCh <> #10) And (SCh <> ';') And (SCh <> '}') And (SCh <> #0) And
       (SCh <> '#') And (C <> '{') And (C <> '}') And (C <> 'a') And
       (C <> 'i') And (C <> 'c') Then
      Die('caracteres superflus apres la commande ' + C, 1);
  End;
  If Top > 0 Then Die('{ non ferme', 1);
  { resolution des etiquettes }
  For Idx := 1 To NCmd Do
    If (Cmds[Idx].Ch = 'b') Or (Cmds[Idx].Ch = 't') Or
       (Cmds[Idx].Ch = 'T') Then
    Begin
      Lb := '';
      For K := 0 To Cmds[Idx].TxtL - 1 Do Lb := Lb + Pool[Cmds[Idx].TxtS + K];
      If Lb = '' Then Cmds[Idx].Tgt := NCmd + 1
      Else
      Begin
        Cmds[Idx].Tgt := -1;
        For K := 1 To NL Do
          If Lbls[K] = Lb Then Cmds[Idx].Tgt := LblAt[K];
        If Cmds[Idx].Tgt < 0 Then Die('etiquette inconnue : ' + Lb, 1);
      End;
    End;
End;

{ ---------- entree ---------- }

Function OpenNext : Boolean;
Var Nm : String;
Begin
  OpenNext := False;
  While FileIdx <= NFiles Do
  Begin
    Nm := Files[FileIdx];
    Inc(FileIdx);
    If Nm = '-' Then InFd := 0
    Else
    Begin
      InFd := SysOpen(Nm, 0, 0);
      If InFd < 0 Then
      Begin
        FlushOut;
        SysPut(2, 'sed: impossible de lire ' + Nm + ' : ' +
               SysErrorText(SysErrno) + #10);
        ExitCode := 2;
        Continue;
      End;
    End;
    CurName := Nm;
    InPos := 0;
    InLen := 0;
    OpenNext := True;
    Exit;
  End;
End;

{ lit une ligne dans LA ; Faux si plus rien dans le fichier courant }
Function FetchLine : Boolean;
Var C : LongInt;
Begin
  FetchLine := False;
  LALen := 0;
  LANoNL := False;
  If InFd < 0 Then Exit;
  While True Do
  Begin
    If InPos >= InLen Then
    Begin
      InLen := SysRead(InFd, InBuf[0], 65536);
      InPos := 0;
      If InLen <= 0 Then
      Begin
        InLen := 0;
        If InFd > 0 Then SysClose(InFd);
        InFd := -1;
        If LALen > 0 Then
        Begin
          LANoNL := True;
          FetchLine := True;
        End;
        Exit;
      End;
    End;
    C := InBuf[InPos];
    Inc(InPos);
    If C = Ord(Sep) Then
    Begin
      FetchLine := True;
      Exit;
    End;
    If LALen < LM Then
    Begin
      LA[LALen] := Chr(C);
      Inc(LALen);
    End;
  End;
End;

{ prefetch : remplit LA avec la ligne suivante (autre fichier si !OptS) }
Procedure Prefetch;
Begin
  LAValid := False;
  While True Do
  Begin
    If InFd >= 0 Then
      If FetchLine Then
      Begin
        LAValid := True;
        Exit;
      End;
    If OptS Or OptI Then Exit;
    If Not OpenNext Then Exit;
  End;
End;

Function MoreInput : Boolean;
Begin
  MoreInput := LAValid;
End;

{ ---------- sortie ---------- }

Procedure NlIfPending;
Begin
  If PendNL Then
  Begin
    OutC(Sep);
    PendNL := False;
  End;
End;

Procedure PutPat(Fd : LongInt);
Var Sv : LongInt;
Begin
  If Fd = -1 Then
  Begin
    NlIfPending;
    OutMem(LongInt(@Pat[0]), PLen);
    If CurNoNL Then PendNL := True Else OutC(Sep);
  End
  Else
  Begin
    SysWrite(Fd, Pat[0], PLen);
    Sv := Ord(Sep);
    SysWrite(Fd, Sv, 1);
  End;
End;

Procedure PutMemNL(Base, N : LongInt);
Begin
  NlIfPending;
  OutMem(Base, N);
  OutC(Sep);
End;

Procedure FlushApp;
Var K, Fd, N, L : LongInt; Nm : String; B : Array[0..4095] Of Byte;
Begin
  For K := 0 To NApp - 1 Do
  Begin
    If AppK[K] = 0 Then
    Begin
      NlIfPending;
      OutMem(LongInt(@Pool[AppS[K]]), AppL[K]);
    End
    Else
    Begin
      Nm := '';
      For L := 0 To AppL[K] - 1 Do Nm := Nm + Pool[AppS[K] + L];
      If AppK[K] = 1 Then
      Begin
        Fd := SysOpen(Nm, 0, 0);
        If Fd >= 0 Then
        Begin
          NlIfPending;
          N := SysRead(Fd, B[0], 4096);
          While N > 0 Do
          Begin
            OutMem(LongInt(@B[0]), N);
            N := SysRead(Fd, B[0], 4096);
          End;
          SysClose(Fd);
        End;
      End
      Else
      Begin
        { R : une ligne du fichier }
      End;
    End;
  End;
  NApp := 0;
End;

Procedure AddApp(Kind, S, L : LongInt);
Begin
  If NApp < 100 Then
  Begin
    AppK[NApp] := Kind;
    AppS[NApp] := S;
    AppL[NApp] := L;
    Inc(NApp);
  End;
End;

Procedure ListL(W : LongInt);
Var K, C, Col, Len : LongInt; S : String;
Begin
  Col := 0;
  NlIfPending;
  For K := 0 To PLen - 1 Do
  Begin
    C := Ord(Pat[K]);
    S := '';
    If C = 92 Then S := '\\'
    Else If C = 7 Then S := '\a'
    Else If C = 8 Then S := '\b'
    Else If C = 12 Then S := '\f'
    Else If C = 10 Then S := '\n'
    Else If C = 13 Then S := '\r'
    Else If C = 9 Then S := '\t'
    Else If C = 11 Then S := '\v'
    Else If (C < 32) Or (C > 126) Then
      S := '\' + Chr(48 + (C Shr 6)) + Chr(48 + ((C Shr 3) And 7)) +
           Chr(48 + (C And 7))
    Else S := Chr(C);
    Len := Length(S);
    If (W > 1) And (Col + Len > W - 1) Then
    Begin
      OutS('\' + #10);
      Col := 0;
    End;
    OutS(S);
    Col := Col + Len;
  End;
  OutS('$' + #10);
End;

{ ---------- adresses ---------- }

Function ReMatchPat(R : LongInt) : Boolean;
Var Pr : LongInt;
Begin
  Pr := R;
  If Pr = -2 Then Pr := LastRe;
  If Pr < 0 Then Die('aucune expression reguliere precedente', 1);
  LastRe := Pr;
  ReMatchPat := ReSearch(Pr, LongInt(@Pat[0]), PLen, 0, False);
End;

Function IsLastLine : Boolean;
Begin
  IsLastLine := Not LAValid;
End;

Function MatchOne(K : Byte; N, Step, R : LongInt) : Boolean;
Begin
  MatchOne := False;
  Case K Of
    1 : MatchOne := LineNo = N;
    2 : MatchOne := IsLastLine;
    3 : MatchOne := ReMatchPat(R);
    4 : If Step <= 0 Then MatchOne := LineNo = N
        Else MatchOne := (LineNo >= N) And ((LineNo - N) Mod Step = 0);
  End;
End;

Function Selected(I : LongInt) : Boolean;
Var R : Boolean;
Begin
  If Cmds[I].K1 = 0 Then R := True
  Else If Cmds[I].K2 = 0 Then R := MatchOne(Cmds[I].K1, Cmds[I].N1,
                                           Cmds[I].Step, Cmds[I].R1)
  Else
  Begin
    R := False;
    If Cmds[I].Active Then
    Begin
      R := True;
      Case Cmds[I].K2 Of
        1, 5, 6 : If LineNo >= Cmds[I].EndLine Then Cmds[I].Active := False;
        2 : If IsLastLine Then Cmds[I].Active := False;
        3 : If ReMatchPat(Cmds[I].R2) Then Cmds[I].Active := False;
      End;
      If (Cmds[I].K2 = 1) And (LineNo > Cmds[I].EndLine) Then
      Begin
        Cmds[I].Active := False;
        R := False;
      End;
    End;
    If (Not R) And (Not Cmds[I].Active) Then
    Begin
      If Cmds[I].K1 = 7 Then
      Begin
        { 0,/re/ : actif des la ligne 1 }
        If LineNo = 1 Then
        Begin
          R := True;
          Cmds[I].Active := True;
          If ReMatchPat(Cmds[I].R2) Then Cmds[I].Active := False;
        End;
      End
      Else If MatchOne(Cmds[I].K1, Cmds[I].N1, Cmds[I].Step,
                       Cmds[I].R1) Then
      Begin
        R := True;
        Case Cmds[I].K2 Of
          1 : If Cmds[I].N2 > LineNo Then
              Begin
                Cmds[I].Active := True;
                Cmds[I].EndLine := Cmds[I].N2;
              End;
          5 : If Cmds[I].N2 > 0 Then
              Begin
                Cmds[I].Active := True;
                Cmds[I].EndLine := LineNo + Cmds[I].N2;
              End;
          6 : If Cmds[I].N2 > 0 Then
              Begin
                Cmds[I].Active := True;
                Cmds[I].EndLine := LineNo + Cmds[I].N2 -
                                   (LineNo Mod Cmds[I].N2);
              End;
          2 : If Not IsLastLine Then Cmds[I].Active := True;
          3 : Cmds[I].Active := True;
        End;
      End;
    End;
  End;
  If Cmds[I].Neg Then R := Not R;
  Selected := R;
End;

{ ---------- substitution ---------- }

Procedure TAdd(C : Char);
Begin
  If TLen < LM Then
  Begin
    Tmp[TLen] := C;
    Inc(TLen);
  End;
End;

Var
  CaseMode, OneShot : Char;

Procedure TAddCase(C : Char);
Begin
  If OneShot = 'u' Then
  Begin
    If (C >= 'a') And (C <= 'z') Then C := Chr(Ord(C) - 32);
    OneShot := #0;
  End
  Else If OneShot = 'l' Then
  Begin
    If (C >= 'A') And (C <= 'Z') Then C := Chr(Ord(C) + 32);
    OneShot := #0;
  End
  Else If CaseMode = 'U' Then
  Begin
    If (C >= 'a') And (C <= 'z') Then C := Chr(Ord(C) - 32);
  End
  Else If CaseMode = 'L' Then
  Begin
    If (C >= 'A') And (C <= 'Z') Then C := Chr(Ord(C) + 32);
  End;
  TAdd(C);
End;

Procedure Expand(I : LongInt);
Var K, G, A, B, J : LongInt; T, V : Char;
Begin
  CaseMode := #0;
  OneShot := #0;
  K := 0;
  While K < Cmds[I].ReplL Do
  Begin
    T := Pool[Cmds[I].ReplS + K];
    V := Pool[Cmds[I].ReplS + K + 1];
    K := K + 2;
    If T = #0 Then TAddCase(V)
    Else If T = #1 Then
    Begin
      G := Ord(V) - 48;
      A := ReCap[2 * G];
      B := ReCap[2 * G + 1];
      If (A >= 0) And (B >= A) Then
        For J := A To B - 1 Do TAddCase(Pat[J]);
    End
    Else
    Begin
      If (V = 'U') Or (V = 'L') Then CaseMode := V
      Else If V = 'E' Then
      Begin
        CaseMode := #0;
        OneShot := #0;
      End
      Else OneShot := V;
    End;
  End;
End;

Function DoSubst(I : LongInt) : Boolean;
Var Pr, Pos0, Ms, Me, Cnt, PrevEnd, K : LongInt; Did : Boolean;
Begin
  DoSubst := False;
  Pr := Cmds[I].Re;
  If Pr = -2 Then Pr := LastRe;
  If Pr < 0 Then Die('aucune expression reguliere precedente', 1);
  LastRe := Pr;
  TLen := 0;
  Pos0 := 0;
  Cnt := 0;
  PrevEnd := -1;
  Did := False;
  While Pos0 <= PLen Do
  Begin
    If Not ReSearch(Pr, LongInt(@Pat[0]), PLen, Pos0, True) Then Break;
    Ms := ReCap[0];
    Me := ReCap[1];
    If (Ms = Me) And (Ms = PrevEnd) Then
    Begin
      For K := Pos0 To Ms - 1 Do TAdd(Pat[K]);
      If Ms < PLen Then TAdd(Pat[Ms]);
      Pos0 := Ms + 1;
      Continue;
    End;
    For K := Pos0 To Ms - 1 Do TAdd(Pat[K]);
    Inc(Cnt);
    If Cnt >= Cmds[I].Nth Then
    Begin
      Expand(I);
      Did := True;
    End
    Else
      For K := Ms To Me - 1 Do TAdd(Pat[K]);
    PrevEnd := Me;
    If Me = Ms Then
    Begin
      If Me < PLen Then TAdd(Pat[Me]);
      Pos0 := Me + 1;
    End
    Else Pos0 := Me;
    If Did And (Not Cmds[I].GFlag) Then Break;
  End;
  If Not Did Then Exit;
  For K := Pos0 To PLen - 1 Do TAdd(Pat[K]);
  Move(Tmp[0], Pat[0], TLen);
  PLen := TLen;
  DoSubst := True;
End;

{ ---------- execution ---------- }

Procedure ReadAppendR(I : LongInt);
Begin
  AddApp(1, Cmds[I].TxtS, Cmds[I].TxtL);
End;

Function NextCycleLine : Boolean;
Begin
  NextCycleLine := False;
  If Not LAValid Then Exit;
  Move(LA[0], Pat[0], LALen);
  PLen := LALen;
  CurNoNL := LANoNL;
  Inc(LineNo);
  Prefetch;
  NextCycleLine := True;
End;

Procedure OpenInPlace;
Begin
  TmpName := CurName + '.sedtmp';
  OutFd := SysOpen(TmpName, $241, 420);
  If OutFd < 0 Then Die('impossible de creer ' + TmpName, 4);
End;

Procedure CloseInPlace;
Var St : TSysStat;
Begin
  FlushOut;
  If SysStat(CurName, St) = 0 Then SysChmod(TmpName, St.Mode And $FFF);
  SysClose(OutFd);
  OutFd := 1;
  If Suffix <> '' Then
  Begin
    If Pos('*', Suffix) > 0 Then
      SysRename(CurName, Copy(Suffix, 1, Pos('*', Suffix) - 1) + CurName +
                Copy(Suffix, Pos('*', Suffix) + 1, 255))
    Else SysRename(CurName, CurName + Suffix);
  End;
  SysRename(TmpName, CurName);
End;

Procedure RunScript;
Var
  I, K, Pc, Skip : LongInt; Tst, Restart, NoAuto, EndCycle : Boolean;
  Nm : String; C : Char; N, P0 : LongInt;
Begin
  Restart := False;
  While Not Quit Do
  Begin
    If Not Restart Then
    Begin
      If Not NextCycleLine Then Break;
    End;
    Restart := False;
    Replaced := False;
    Pc := 1;
    NoAuto := False;
    EndCycle := False;
    While (Pc <= NCmd) And (Not EndCycle) Do
    Begin
      I := Pc;
      Inc(Pc);
      If Cmds[I].Ch = '}' Then Continue;
      If Cmds[I].Ch = ':' Then Continue;
      Tst := Selected(I);
      If Not Tst Then
      Begin
        If Cmds[I].Ch = '{' Then Pc := Cmds[I].Tgt + 1;
        Continue;
      End;
      C := Cmds[I].Ch;
      Case C Of
        '{', '}' : ;
        's' :
          If DoSubst(I) Then
          Begin
            Replaced := True;
            If Cmds[I].PFlag Then PutPat(-1);
            If Cmds[I].WFd <> -2 Then PutPat(Cmds[I].WFd);
          End;
        'y' :
          For K := 0 To PLen - 1 Do
            For N := 0 To Cmds[I].TxtL - 1 Do
              If Pat[K] = Pool[Cmds[I].TxtS + N] Then
              Begin
                Pat[K] := Pool[Cmds[I].TxtS + Cmds[I].TxtL + N];
                Break;
              End;
        'd' :
          Begin
            NoAuto := True;
            EndCycle := True;
          End;
        'D' :
          Begin
            P0 := 0;
            While (P0 < PLen) And (Pat[P0] <> #10) Do Inc(P0);
            If P0 >= PLen Then
            Begin
              NoAuto := True;
              EndCycle := True;
            End
            Else
            Begin
              Move(Pat[P0 + 1], Pat[0], PLen - P0 - 1);
              PLen := PLen - P0 - 1;
              NoAuto := True;
              EndCycle := True;
              Restart := True;
            End;
          End;
        'p' : PutPat(-1);
        'P' :
          Begin
            P0 := 0;
            While (P0 < PLen) And (Pat[P0] <> #10) Do Inc(P0);
            PutMemNL(LongInt(@Pat[0]), P0);
          End;
        'n' :
          Begin
            If Not LAValid Then
            Begin
              If OptN Or Not True Then ;
              NoMoreInput := True;
              EndCycle := True;
              Quit := True;
            End
            Else
            Begin
              If Not OptN Then PutPat(-1);
              FlushApp;
              Move(LA[0], Pat[0], LALen);
              PLen := LALen;
              CurNoNL := LANoNL;
              Inc(LineNo);
              Prefetch;
            End;
          End;
        'N' :
          Begin
            If Not LAValid Then
            Begin
              EndCycle := True;
              Quit := True;
            End
            Else
            Begin
              FlushApp;
              Pat[PLen] := #10;
              Inc(PLen);
              Move(LA[0], Pat[PLen], LALen);
              PLen := PLen + LALen;
              CurNoNL := LANoNL;
              Inc(LineNo);
              Prefetch;
            End;
          End;
        'g' :
          Begin
            Move(Hold[0], Pat[0], HLen);
            PLen := HLen;
            CurNoNL := HoldNoNL;
          End;
        'G' :
          Begin
            CurNoNL := CurNoNL And HoldNoNL;
            Pat[PLen] := #10;
            Inc(PLen);
            Move(Hold[0], Pat[PLen], HLen);
            PLen := PLen + HLen;
          End;
        'h' :
          Begin
            Move(Pat[0], Hold[0], PLen);
            HLen := PLen;
            HoldNoNL := CurNoNL;
          End;
        'H' :
          Begin
            HoldNoNL := HoldNoNL And CurNoNL;
            Hold[HLen] := #10;
            Inc(HLen);
            Move(Pat[0], Hold[HLen], PLen);
            HLen := HLen + PLen;
          End;
        'x' :
          Begin
            Move(Pat[0], Tmp[0], PLen);
            TLen := PLen;
            Move(Hold[0], Pat[0], HLen);
            PLen := HLen;
            Move(Tmp[0], Hold[0], TLen);
            HLen := TLen;
            Replaced := Replaced;
            If CurNoNL <> HoldNoNL Then
            Begin
              CurNoNL := Not CurNoNL;
              HoldNoNL := Not HoldNoNL;
            End;
          End;
        'z' : PLen := 0;
        '=' :
          Begin
            NlIfPending;
            OutS(NumS(LineNo) + #10);
          End;
        'F' :
          Begin
            NlIfPending;
            OutS(CurName + #10);
          End;
        'l' :
          Begin
            If Cmds[I].N2 >= 0 Then ListL(Cmds[I].N2) Else ListL(LineW);
          End;
        'a' : AddApp(0, Cmds[I].TxtS, Cmds[I].TxtL);
        'i' :
          Begin
            NlIfPending;
            OutMem(LongInt(@Pool[Cmds[I].TxtS]), Cmds[I].TxtL);
          End;
        'c' :
          Begin
            If (Cmds[I].K2 = 0) Or (Not Cmds[I].Active) Or Cmds[I].Neg Then
            Begin
              NlIfPending;
              OutMem(LongInt(@Pool[Cmds[I].TxtS]), Cmds[I].TxtL);
            End;
            NoAuto := True;
            EndCycle := True;
          End;
        'r' : ReadAppendR(I);
        'R' : ;
        'w' :
          Begin
            If Cmds[I].WFd = -1 Then PutPat(-1) Else PutPat(Cmds[I].WFd);
          End;
        'W' :
          Begin
            P0 := 0;
            While (P0 < PLen) And (Pat[P0] <> #10) Do Inc(P0);
            If Cmds[I].WFd = -1 Then PutMemNL(LongInt(@Pat[0]), P0)
            Else
            Begin
              SysWrite(Cmds[I].WFd, Pat[0], P0);
              Skip := 10;
              SysWrite(Cmds[I].WFd, Skip, 1);
            End;
          End;
        'b' : Pc := Cmds[I].Tgt + 1;
        't' :
          If Replaced Then
          Begin
            Replaced := False;
            Pc := Cmds[I].Tgt + 1;
          End;
        'T' :
          If Not Replaced Then Pc := Cmds[I].Tgt + 1
          Else Replaced := False;
        'q' :
          Begin
            If Cmds[I].N2 >= 0 Then ExitCode := Cmds[I].N2;
            Quit := True;
            EndCycle := True;
          End;
        'Q' :
          Begin
            If Cmds[I].N2 >= 0 Then ExitCode := Cmds[I].N2;
            Quit := True;
            NoAuto := True;
            EndCycle := True;
            NApp := 0;
          End;
      End;
    End;
    If (Not NoAuto) And (Not OptN) Then PutPat(-1);
    FlushApp;
    If Quit And (Not NoAuto) And (Not OptN) And NoMoreInput Then ;
  End;
End;

{ ---------- ligne de commande ---------- }

Var
  I, J, Nb : LongInt;
  A, V1 : String;
  HaveScript, EndOpt : Boolean;
  Fd : LongInt;
  L : String;

Procedure AddScript(Const S : String);
Var K : LongInt;
Begin
  If ScrN > 0 Then
  Begin
    Scr[ScrN] := #10;
    Inc(ScrN);
  End;
  For K := 1 To Length(S) Do
  Begin
    If ScrN < ScrMax Then
    Begin
      Scr[ScrN] := S[K];
      Inc(ScrN);
    End;
  End;
  HaveScript := True;
End;

Procedure AddScriptFile(Const Fn : String);
Var F : LongInt; Ln : String; First : Boolean;
Begin
  If Fn = '-' Then F := 0 Else F := SysOpen(Fn, 0, 0);
  If F < 0 Then Die('impossible de lire ' + Fn + ' : ' +
                    SysErrorText(SysErrno), 1);
  First := True;
  While SysReadLine(F, Ln) Do
  Begin
    If First And (Copy(Ln, 1, 3) = '#n' + '') And (Length(Ln) = 2) Then
      OptN := True
    Else AddScript(Ln);
    First := False;
  End;
  If F > 0 Then SysClose(F);
End;

Begin
  Sep := #10;
  ReN := 0;
  ReSetN := 0;
  LineW := 70;
  OutFd := 1;
  Nb := SysArgCount;
  NFiles := 0;
  HaveScript := False;
  EndOpt := False;
  I := 1;
  While I < Nb Do
  Begin
    A := SysArgStr(I);
    If (Not EndOpt) And (Length(A) > 1) And (A[1] = '-') Then
    Begin
      If A = '--' Then EndOpt := True
      Else If (A = '--quiet') Or (A = '--silent') Then OptN := True
      Else If A = '--regexp-extended' Then OptE := True
      Else If A = '--separate' Then OptS := True
      Else If A = '--null-data' Then OptZ := True
      Else If A = '--unbuffered' Then OptU := True
      Else If (A = '--posix') Or (A = '--debug') Or (A = '--sandbox') Or
              (A = '--follow-symlinks') Or (A = '--binary') Then
      Else If Copy(A, 1, 12) = '--expression' Then
      Begin
        If Length(A) > 13 Then AddScript(Copy(A, 14, 4000))
        Else
        Begin
          Inc(I);
          If I >= Nb Then Usage;
          AddScript(SysArgStr(I));
        End;
      End
      Else If Copy(A, 1, 6) = '--file' Then
      Begin
        If Length(A) > 7 Then AddScriptFile(Copy(A, 8, 255))
        Else
        Begin
          Inc(I);
          If I >= Nb Then Usage;
          AddScriptFile(SysArgStr(I));
        End;
      End
      Else If Copy(A, 1, 10) = '--in-place' Then
      Begin
        OptI := True;
        If Length(A) > 11 Then Suffix := Copy(A, 12, 255);
      End
      Else If Copy(A, 1, 13) = '--line-length' Then
      Begin
        If Length(A) > 14 Then Val(Copy(A, 15, 20), LineW, J);
      End
      Else If A[2] = '-' Then Usage
      Else
      Begin
        J := 2;
        While J <= Length(A) Do
        Begin
          Case A[J] Of
            'n' : OptN := True;
            'E', 'r' : OptE := True;
            's' : OptS := True;
            'z' : OptZ := True;
            'u' : OptU := True;
            'b' : ;
            'i' :
              Begin
                OptI := True;
                Suffix := Copy(A, J + 1, 255);
                J := Length(A);
              End;
            'e', 'f', 'l' :
              Begin
                If J < Length(A) Then V1 := Copy(A, J + 1, 4000)
                Else
                Begin
                  Inc(I);
                  If I >= Nb Then Usage;
                  V1 := SysArgStr(I);
                End;
                If A[J] = 'e' Then AddScript(V1)
                Else If A[J] = 'f' Then AddScriptFile(V1)
                Else Val(V1, LineW, Fd);
                J := Length(A);
              End;
          Else
            Usage;
          End;
          Inc(J);
        End;
      End;
    End
    Else
    Begin
      If (Not HaveScript) Then AddScript(A)
      Else
      Begin
        Inc(NFiles);
        Files[NFiles] := A;
      End;
    End;
    Inc(I);
  End;
  If Not HaveScript Then Usage;
  If OptZ Then Sep := #0;
  Parse;
  If NFiles = 0 Then
  Begin
    NFiles := 1;
    Files[1] := '-';
  End;
  FileIdx := 1;
  InFd := -1;
  LastRe := -1;
  If OptI Then
  Begin
    { chaque fichier est traite separement }
    J := 1;
    While (J <= NFiles) And (Not Quit) Do
    Begin
      FileIdx := J;
      Inc(J);
      If Not OpenNext Then Continue;
      OpenInPlace;
      LineNo := 0;
      PendNL := False;
      Prefetch;
      RunScript;
      CloseInPlace;
      For I := 1 To NCmd Do Cmds[I].Active := False;
    End;
  End
  Else If OptS Then
  Begin
    J := 1;
    While (J <= NFiles) And (Not Quit) Do
    Begin
      FileIdx := J;
      Inc(J);
      If Not OpenNext Then Continue;
      LineNo := 0;
      Prefetch;
      RunScript;
    End;
  End
  Else
  Begin
    If OpenNext Then Prefetch;
    RunScript;
  End;
  FlushOut;
  SysExit(ExitCode);
End.
