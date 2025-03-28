{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit ctype;

INTERFACE

Const
  _U   = $01;  { Majuscule }
  _L   = $02;  { Minuscule }
  _D   = $04;  { Chiffre }
  _C   = $08;  { CaractŠre de contr“le }
  _P   = $10;  { Ponctuation }
  _S   = $20;  { Espace blanc (espace, saut de ligne, tabulation) }
  _X   = $40;  { Chiffre hexad‚cimal }
  _SP  = $80;  { Espace dur ($20) }

Function IsAlNum(C:Char):Boolean;
Function IsAlpha(C:Char):Boolean;
Function IsATTY(Desc:Integer):Boolean;
Function IsCntrl(C:Char):Boolean;
Function IsDigit(C:Char):Boolean;
Function IsGraph(C:Char):Boolean;
Function IsLower(C:Char):Boolean;
Function IsPrint(C:Char):Boolean;
Function IsPunct(C:Char):Boolean;
Function IsSpace(C:Char):Boolean;
Function IsUpper(C:Char):Boolean;
Function IsXDigit(C:Char):Boolean;

IMPLEMENTATION

Function IsAlNum(C:Char):Boolean;Begin
 IsAlNum:=C in ['A'..'Z','a'..'z','0'..'9'];
End;

Function IsAlpha(C:Char):Boolean;Begin
 IsAlpha:=C in ['A'..'Z','a'..'z'];
End;

Function IsATTY(Desc:Integer):Boolean;Begin
 IsATTY:=Desc in [0, 1, 2];  { V‚rifie si Desc est un descripteur standard }
End;

Function IsCntrl(C:Char):Boolean;Begin
 IsCntrl:=C in [#1..#31,#127];
End;

Function IsDigit(C:Char):Boolean;Begin
 IsDigit:=C in ['0'..'9'];
End;

Function IsGraph(C:Char):Boolean;Begin
 IsGraph:=C in [#33..#255];
End;

Function IsLower(C:Char):Boolean;Begin
 IsLower:=C in ['a'..'z'];
End;

Function IsPrint(C:Char):Boolean;Begin
 IsPrint:=C in [#32..#255];
End;

Function IsPunct(C:Char):Boolean;Begin
 IsPunct:=C in ['!','"','#','$','%','&','''','(',')','*','+',',','-','.','/','{','}','~'];
End;

Function IsSpace(C:Char):Boolean;Begin
 IsSpace:=C in [#0,#8,' '];
End;

Function IsUpper(C:Char):Boolean;Begin
 IsUpper:=C in ['A'..'Z'];
End;

Function IsXDigit(C:Char):Boolean;Begin
 IsXDigit:=C in ['0'..'9','A'..'F','a'..'f'];
End;

END.