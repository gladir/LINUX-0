{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit ASSERT;

INTERFACE

Procedure Assert_(expression:Boolean);
Procedure Assert_PError(code_erreur:Integer);

IMPLEMENTATION

Procedure Assert_(expression:Boolean);Begin
 If Not expression Then Begin
  Writeln('êchec Assertion.');
  Halt(1); { Termine le programme avec un code d'erreur 1 }
 End;
End;

Procedure Assert_PError(code_erreur:Integer);Begin
 If code_erreur<>0 Then Begin
  Writeln('êchec Assertion: code d''erreur ', code_erreur);
  Halt(code_erreur); { Termine avec le code d'erreur }
 End;
End;

END.