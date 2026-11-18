{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: VTVIEW.INC : fenetres Terminal sur pty (/dev/ptmx) :
      lancement d'un shell sur un pseudo-terminal, pompe des octets vers
      VTCORE, envoi des touches, dessin sur GFX (police de GFX.INC, 16
      couleurs, curseur bloc, historique avec Maj+PgHaut/PgBas).
      Plusieurs terminaux (T_MAX) coexistent : chaque fenetre a son ecran,
      donc VTCORE est "commute" par TermSelect (copie de l'etat : chaque
      terminal garde sa propre sauvegarde dans TmBuf). Inclure apres
      VTCORE.INC, GFX.INC et INPUT.INC. Noms Term... / Tm... }

Const
  T_MAX = 4;
  VT_PAL : Array[0..15] Of LongInt = (
    $2E3436, $CC0000, $4E9A06, $C4A000, $3465A4, $75507B, $06989A, $D3D7CF,
    $555753, $EF2929, $8AE234, $FCE94F, $729FCF, $AD7FA8, $34E2E2, $EEEEEC);

Type
  TTerm = Record
    Used, Alive : Boolean;
    Fd, Pid, Cols, Rows, Scroll : LongInt;
  End;

Var
  Terms : Array[0..T_MAX - 1] Of TTerm;
  TermCur : LongInt;                { terminal dont l'etat est dans VtCore }
  TmChB : Array[0..T_MAX - 1, 0..VT_MC * VT_MR - 1] Of Byte;
  TmAtB : Array[0..T_MAX - 1, 0..VT_MC * VT_MR - 1] Of Byte;
  TmFlB : Array[0..T_MAX - 1, 0..VT_MC * VT_MR - 1] Of Byte;
  TmVars : Array[0..T_MAX - 1, 0..15] Of LongInt;
  TmSbCh, TmSbAt, TmSbFl : Array[0..0] Of Byte;
  TermUid, TermGid : LongInt;       { utilisateur du shell (0 : root) }
  TermHome, TermUser, TermShell : String;
  TermEnv : Array[0..15] Of String;
  TermEnvN : LongInt;

{ ---- commutation entre terminaux (l'historique n'est pas conserve) ---- }

Procedure TermSave(N : LongInt);
Begin
  Move(VtCh, TmChB[N], SizeOf(VtCh));
  Move(VtAt, TmAtB[N], SizeOf(VtAt));
  Move(VtFl, TmFlB[N], SizeOf(VtFl));
  TmVars[N, 0] := VtCx;
  TmVars[N, 1] := VtCy;
  TmVars[N, 2] := VtTop;
  TmVars[N, 3] := VtBot;
  TmVars[N, 4] := VtCurAt;
  TmVars[N, 5] := VtCurFl;
  TmVars[N, 6] := Ord(VtWrapPend);
  TmVars[N, 7] := Ord(VtWrap);
  TmVars[N, 8] := Ord(VtCurOn);
  TmVars[N, 9] := Ord(VtAppKeys);
  TmVars[N, 10] := VtSt;
  TmVars[N, 11] := VtCols;
  TmVars[N, 12] := VtRows;
End;

Procedure TermLoad(N : LongInt);
Begin
  Move(TmChB[N], VtCh, SizeOf(VtCh));
  Move(TmAtB[N], VtAt, SizeOf(VtAt));
  Move(TmFlB[N], VtFl, SizeOf(VtFl));
  VtCx := TmVars[N, 0];
  VtCy := TmVars[N, 1];
  VtTop := TmVars[N, 2];
  VtBot := TmVars[N, 3];
  VtCurAt := TmVars[N, 4];
  VtCurFl := TmVars[N, 5];
  VtWrapPend := TmVars[N, 6] <> 0;
  VtWrap := TmVars[N, 7] <> 0;
  VtCurOn := TmVars[N, 8] <> 0;
  VtAppKeys := TmVars[N, 9] <> 0;
  VtSt := TmVars[N, 10];
  VtCols := TmVars[N, 11];
  VtRows := TmVars[N, 12];
  VtMarkAll;
End;

Procedure TermSelect(N : LongInt);
Begin
  If N = TermCur Then Exit;
  If Terms[TermCur].Used Then TermSave(TermCur);
  TermCur := N;
  If Terms[N].Used Then TermLoad(N);
End;

{ ---- pty ---- }

Function NStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  NStr := S;
End;

{ ouvre un terminal : Cmd = '' (shell de connexion) ou commande /bin/sh -c }
Function TermOpen(N, Cols, Rows : LongInt; Const Cmd : String) : Boolean;
Var M, Idx, Unl, K, Pid : LongInt; Slave : String; Ws : Array[0..1] Of LongInt;
    Fd : LongInt;
Begin
  TermOpen := False;
  M := SysOpen('/dev/ptmx', O_RDWR Or $800, 0);
  If M < 0 Then Exit;
  Unl := 0;
  SysIoctl(M, $40045431, Unl);
  If SysIoctl(M, $80045430, Idx) < 0 Then
  Begin
    SysClose(M);
    Exit;
  End;
  Slave := '/dev/pts/' + NStr(Idx);
  Ws[0] := Rows Or (Cols Shl 16);
  Ws[1] := 0;
  SysIoctl(M, $5414, Ws);
  Pid := SysFork;
  If Pid = 0 Then
  Begin
    SysClose(M);
    SysSetSid;
    Fd := SysOpen(Slave, O_RDWR, 0);
    If Fd < 0 Then SysExit(126);
    SysIoctlL(Fd, $540E, 1);
    SysDup2(Fd, 0);
    SysDup2(Fd, 1);
    SysDup2(Fd, 2);
    If Fd > 2 Then SysClose(Fd);
    SysArgReset;
    If Cmd = '' Then
    Begin
      SysArgAdd('sh');
      SysArgAdd('-l');
    End
    Else
    Begin
      SysArgAdd('sh');
      SysArgAdd('-c');
      SysArgAdd(Cmd);
    End;
    SysEnvAdd('TERM=linux');
    SysEnvAdd('PATH=/sbin:/bin:/usr/sbin:/usr/bin');
    SysEnvAdd('HOME=' + TermHome);
    SysEnvAdd('USER=' + TermUser);
    SysEnvAdd('LOGNAME=' + TermUser);
    SysEnvAdd('SHELL=/bin/sh');
    For K := 0 To TermEnvN - 1 Do SysEnvAdd(TermEnv[K]);
    SysChdir(TermHome);
    If TermUid <> 0 Then
    Begin
      SysSetGid(TermGid);
      SysSetUid(TermUid);
    End;
    SysArgExec('/bin/sh');
    SysExit(127);
  End;
  If Pid < 0 Then
  Begin
    SysClose(M);
    Exit;
  End;
  If TermCur <> N Then TermSelect(N);
  Terms[N].Used := True;
  Terms[N].Alive := True;
  Terms[N].Fd := M;
  Terms[N].Pid := Pid;
  Terms[N].Cols := Cols;
  Terms[N].Rows := Rows;
  Terms[N].Scroll := 0;
  VtInit(Cols, Rows);
  TermOpen := True;
End;

Procedure TermSend(N : LongInt; Const S : String);
Var R : LongInt;
Begin
  If (Not Terms[N].Used) Or (Not Terms[N].Alive) Or (S = '') Then Exit;
  R := LnxSys3(4, Terms[N].Fd, LongInt(@S[1]), Length(S));
End;

{ lit ce qui est disponible sur le pty N ; Vrai s'il y avait des donnees }
Function TermPump(N : LongInt) : Boolean;
Var Buf : Array[0..2047] Of Byte; R, K, Cnt : LongInt; St : LongInt;
Begin
  TermPump := False;
  If (Not Terms[N].Used) Or (Not Terms[N].Alive) Then Exit;
  If TermCur <> N Then TermSelect(N);
  Cnt := 0;
  While Cnt < 8 Do
  Begin
    R := LnxSys3(3, Terms[N].Fd, LongInt(@Buf), 2048);
    If R = -11 Then Break;
    If R <= 0 Then
    Begin
      { fin : le shell a quitte (EIO/0) }
      If SysWaitPid(Terms[N].Pid, St, 1) <> 0 Then Terms[N].Alive := False
      Else If R = 0 Then Terms[N].Alive := False
      Else If R < -1 Then Terms[N].Alive := False;
      Break;
    End;
    For K := 0 To R - 1 Do VtPut(Buf[K]);
    TermPump := True;
    Inc(Cnt);
  End;
  If VtOut <> '' Then
  Begin
    TermSend(N, VtOut);
    VtOut := '';
  End;
End;

Procedure TermClose(N : LongInt);
Var St : LongInt;
Begin
  If Not Terms[N].Used Then Exit;
  SysClose(Terms[N].Fd);
  If Terms[N].Alive Then
  Begin
    SysKill(Terms[N].Pid, 1);
    SysKill(Terms[N].Pid, 9);
  End;
  SysWaitPid(Terms[N].Pid, St, 1);
  Terms[N].Used := False;
  Terms[N].Alive := False;
End;

Procedure TermResize(N, Cols, Rows : LongInt);
Var Ws : Array[0..1] Of LongInt;
Begin
  If Not Terms[N].Used Then Exit;
  If TermCur <> N Then TermSelect(N);
  VtResize(Cols, Rows);
  Cols := VtCols;
  Rows := VtRows;
  Terms[N].Cols := Cols;
  Terms[N].Rows := Rows;
  Ws[0] := Rows Or (Cols Shl 16);
  Ws[1] := 0;
  SysIoctl(Terms[N].Fd, $5414, Ws);
  SysKill(-Terms[N].Pid, 28);
End;

{ envoie une touche (code de INPUT.INC) au terminal N ; defilement de
  l'historique avec Maj+PgHaut / Maj+PgBas }
Procedure TermKey(N, K : LongInt);
Begin
  If Not Terms[N].Used Then Exit;
  If InShift And (K = 307) Then
  Begin
    Terms[N].Scroll := Terms[N].Scroll + Terms[N].Rows Div 2;
    Exit;
  End;
  If InShift And (K = 308) Then
  Begin
    Terms[N].Scroll := Terms[N].Scroll - Terms[N].Rows Div 2;
    If Terms[N].Scroll < 0 Then Terms[N].Scroll := 0;
    Exit;
  End;
  Terms[N].Scroll := 0;
  If TermCur <> N Then TermSelect(N);
  TermSend(N, VtKeyStr(K, InCtrl, InAlt));
End;

{ dessin du terminal N a la position pixel X, Y ; cellules GCW x GCH }
Procedure TermDraw(N, X, Y : LongInt);
Var Row, Col, I, At, Fl, Fg, Bg, C, Sc, Src, B, T : LongInt; Cx, Cy : LongInt;
Begin
  If Not Terms[N].Used Then Exit;
  If TermCur <> N Then TermSelect(N);
  Sc := Terms[N].Scroll;
  If Sc > SbN Then Sc := SbN;
  Terms[N].Scroll := Sc;
  For Row := 0 To Terms[N].Rows - 1 Do
  Begin
    { ligne affichee : historique si Row < Sc }
    Src := Row - Sc;
    For Col := 0 To Terms[N].Cols - 1 Do
    Begin
      If Src >= 0 Then
      Begin
        I := VtIdx(Col, Src);
        C := VtCh[I]; At := VtAt[I]; Fl := VtFl[I];
      End
      Else
      Begin
        B := ((SbHead + Src + VT_SB * 2) Mod VT_SB) * VT_MC + Col;
        C := SbCh[B]; At := SbAt[B]; Fl := SbFl[B];
      End;
      Fg := At And 15;
      Bg := (At Shr 4) And 15;
      If (Fl And VF_BOLD) <> 0 Then
        If Fg < 8 Then Fg := Fg + 8;
      If (Fl And VF_REV) <> 0 Then
      Begin
        T := Fg;
        Fg := Bg;
        Bg := T;
      End;
      GChar(X + Col * GCW, Y + Row * GCH, C, VT_PAL[Fg], VT_PAL[Bg]);
      If (Fl And VF_UL) <> 0 Then
        GHLine(X + Col * GCW, Y + Row * GCH + GCH - 2, GCW, VT_PAL[Fg]);
    End;
  End;
  If VtCurOn And (Sc = 0) Then
  Begin
    Cx := VtCx;
    Cy := VtCy;
    I := VtIdx(Cx, Cy);
    GFillRect(X + Cx * GCW, Y + Cy * GCH + GCH - 3, GCW, 3, VT_PAL[15]);
  End;
End;
