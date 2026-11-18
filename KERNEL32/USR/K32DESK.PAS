{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: k32-gnome / k32-kde : environnements de bureau "compatibles
   GNOME" (Adwaita) et "compatibles KDE" (Breeze) de KERNEL32 (voir
   DESKTOP.INC). Un seul programme : le nom (argv[0]) choisit l'environnement :
     k32-gnome, gnome-session            bureau GNOME
     k32-kde, startplasma-x11, startkde  bureau KDE
     gnome-terminal, konsole, dolphin    une seule fenetre Terminal (-e cmd)
   Variables lues : K32_USER, K32_UID, K32_GID, K32_HOME, K32_TTY, K32_SESSION.
   Codes de sortie : 0 deconnexion, 100 redemarrer, 101 eteindre, 10 /dev/fb0
   indisponible, 12 echec. Phase 2 : serveur X. }

Program K32Desk;

{$I FONTS.INC}
{$I GFX.INC}
{$I UIBASE.INC}
{$I LAYOUTS.INC}
{$I INPUT.INC}
{$I VTCORE.INC}
{$I VTVIEW.INC}
{$I DESKTOP.INC}

Function BaseName(Const P : String) : String;
Var K : LongInt;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  BaseName := Copy(P, K + 1, 60);
End;

Function KbdIndex : LongInt;
Var Fd, K : LongInt; L, Id : String; I : LongInt;
Begin
  KbdIndex := 0;
  Fd := SysOpen('/etc/default/keyboard', O_RDONLY, 0);
  If Fd < 0 Then Exit;
  While SysReadLine(Fd, L) Do
    If Copy(L, 1, 10) = 'XKBLAYOUT=' Then
    Begin
      Id := Copy(L, 12, 10);
      K := Pos('"', Id);
      If K > 0 Then Id := Copy(Id, 1, K - 1);
      For I := 0 To LayCount - 1 Do
        If LayId[I] = Id Then KbdIndex := I;
    End;
  SysClose(Fd);
End;

Var
  Nm, Cmd, Tty : String;
  Kind, I : LongInt;
Begin
  Nm := BaseName(SysArgStr(0));
  TermOnly := False;
  Kind := KD_GNOME;
  If (Nm = 'k32-kde') Or (Nm = 'startplasma-x11') Or (Nm = 'startkde') Then
    Kind := KD_KDE
  Else If (Nm = 'konsole') Or (Nm = 'dolphin') Then
  Begin
    Kind := KD_KDE;
    TermOnly := True;
  End
  Else If Nm = 'gnome-terminal' Then TermOnly := True;
  Cmd := '';
  I := 1;
  While I < SysArgCount Do
  Begin
    If (SysArgStr(I) = '-e') And (I + 1 < SysArgCount) Then
    Begin
      Inc(I);
      Cmd := SysArgStr(I);
    End
    Else If (SysArgStr(I) = '--help') Or (SysArgStr(I) = '-h') Then
    Begin
      SysPut(1, 'Usage: ' + Nm + ' [-e commande]' + #10);
      SysExit(0);
    End;
    Inc(I);
  End;
  If (Nm = 'dolphin') And (Cmd = '') Then Cmd := 'ls -l; exec sh -l';
  If Not GOpen(1024, 768) Then
  Begin
    SysPut(2, Nm + ': graphique indisponible : ' + GWhy + #10);
    SysExit(10);
  End;
  UiGfx := True;
  Tty := SysGetEnv('K32_TTY');
  If Tty = '' Then Tty := '/dev/tty1';
  InOpen(Tty, True);
  InSetLayout(KbdIndex);
  DeskInit(Kind);
  If Kind = KD_KDE Then
  Begin
    SysEnvAdd('XDG_CURRENT_DESKTOP=KDE');
    SysEnvAdd('XDG_SESSION_DESKTOP=KDE');
    SysEnvAdd('DESKTOP_SESSION=plasma');
    SysEnvAdd('KDE_FULL_SESSION=true');
  End
  Else
  Begin
    SysEnvAdd('XDG_CURRENT_DESKTOP=GNOME');
    SysEnvAdd('XDG_SESSION_DESKTOP=gnome');
    SysEnvAdd('DESKTOP_SESSION=gnome');
    SysEnvAdd('GDMSESSION=gnome');
  End;
  SysEnvAdd('XDG_SESSION_TYPE=tty');
  SysEnvAdd('XDG_DATA_DIRS=/usr/share');
  SysEnvAdd('XDG_CONFIG_DIRS=/etc/xdg');
  SysEnvAdd('XDG_DATA_HOME=' + TermHome + '/.local/share');
  SysEnvAdd('XDG_CONFIG_HOME=' + TermHome + '/.config');
  SysEnvAdd('XDG_RUNTIME_DIR=/tmp/run-' + UserName_);
  SysEnvAdd('LANGUAGE=' + SysGetEnv('LANGUAGE'));
  TermEnvN := 0;
  For I := 0 To LnxXEnvN - 1 Do
    If TermEnvN < 16 Then
    Begin
      TermEnv[TermEnvN] := SysZStr(LnxXEnv[I]);
      Inc(TermEnvN);
    End;
  SysMkdir('/tmp/run-' + UserName_, 448);
  SysChown('/tmp/run-' + UserName_, TermUid, TermGid);
  DeskRun(Cmd);
  InClose;
  GClose;
  UiTextClose;
  SysExit(ExitCode_);
End.
