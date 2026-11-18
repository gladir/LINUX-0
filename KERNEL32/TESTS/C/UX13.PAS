{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: LPC -3X)
  @description: UX13 : clavier (Crt.ReadKey et KeyPressed de l'unite Graph
    integree). Les octets de UX13.IN sont ceux que le noyau met dans le
    terminal (sequences ESC [ ...) ; chaque touche est affichee avec le code
    de Turbo Pascal : caractere, ou 0 suivi du code etendu. }

Program UX13;

Uses Crt, Graph;

Var C : Char;

Begin
  While KeyPressed Do
  Begin
    C := ReadKey;
    If C = #0 Then
    Begin
      C := ReadKey;
      WriteLn('ext ', Ord(C));
    End
    Else WriteLn('car ', Ord(C));
  End;
  WriteLn('fin');
End.
