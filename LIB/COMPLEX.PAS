{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit COMPLEX;

{$N+}

INTERFACE

Type
 TComplex=Record
  Re:Double; { Partie r‚elle }
  Im:Double; { Partie imaginaire }
 End;

 PTComplex=^TComplex;

 TComplexF = Record
  Re:Single; { Partie r‚elle }
  Im:Single; { Partie imaginaire }
 End;

 TComplexL=Record
  Re:Double; { Partie r‚elle }
  Im:Double; { Partie imaginaire }
 End;

Function CAbs(z:TComplex):Double;
Function CAbsf(z:TComplexF):Single;
Function CAbsl(z:TComplexL):Double;

IMPLEMENTATION

Uses Math;

{ Cette fonction permet de calculer la magnitude (module) d'un nombre
complexe }

Function CAbs(z:TComplex):Double;Begin
 CAbs:=Sqrt(Sqr(z.Re)+Sqr(z.Im));
End;

{ Cette fonction permet de calculer la magnitude (module) d'un nombre
complexe en simple pr‚cision }

Function CAbsf(z:TComplexF):Single;Begin
 CAbsf:=Sqrt(Sqr(z.Re)+Sqr(z.Im));
End;

{ Cette fonction permet de calculer la magnitude (module) d'un nombre
complexe en double pr‚cision }

Function CAbsl(z:TComplexL):Double;Begin
 CAbsl:=Sqrt(Sqr(z.Re)+Sqr(z.Im));
End;

{ Cette fonction permet de calculer le cacos d'un nombre complexe }

Function cacos(z:TComplex):PTComplex;
Var
 sqrtTerm:TComplex;
 temp1,temp2:Double;
 R:TComplex;
 PC:PTComplex;
Begin
 temp1:=Sqr(z.Re)-Sqr(z.Im);
 temp2:=2*z.Re*z.Im;
 sqrtTerm.Re:=Sqrt(Sqr(temp1)+Sqr(temp2));
 sqrtTerm.Im:=0;
 R.Re:=-Ln(Sqrt(Sqr(z.Re+sqrtTerm.Re)+Sqr(z.Im + sqrtTerm.Im)));
 R.Im:=ATan2(z.Im+sqrtTerm.Im, z.Re+sqrtTerm.Re);
 GetMem(PC,SizeOf(TComplex));
 PC^:=R;
 cacos:=PC;
End;


END.