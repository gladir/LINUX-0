{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit MATH;

{$N+}

INTERFACE

Function ACos(a:Double):Double;
Function ACosf(a:Single):Single;
Function ACosH(x:Double):Double;
Function ACosHf(x:Single):Single;
Function ACosHl(x:Extended):Extended;
Function ACosl(a:Extended):Extended;
Function ASin(a:Double):Double;
Function ASinf(a:Single):Single;
Function Asinh(x:Double):Double;
Function Asinhf(x:Single):Single;
Function Asinhl(x:Extended):Extended;
Function ASinl(a:Extended):Extended;
Function Atan(X:Double):Double;
Function ATan2(y,x:Double):Double;
Function ATan2f(y,x:Single):Single;
Function ATan2l(y,x:Double):Double;
Function Atanf(X:Single):Single;
Function Atanh(x:Double):Double;
Function Atanhf(x:Single):Single;
Function Atanhl(x:Extended):Extended;
Function Atanl(X:Extended):Extended;
Function cbrt(x:Double):Double;
Function Ceil(d:Real):Integer;
Function CopySign(x,y:Double):Double;
Function Cos(X:Real):Real;
Function Cosh(x:Real):Real;
Function DRem(x,y:Double):Double;
Function Erf(x:Double):Double;
Function Erfc(x:Double):Double;
Function Exp(x:Real):Real;
Function Expm1(x:Double):Double;
Function FAbs(a:Real):Real;
Function Floor(d:Real):Real;
Function FMod(X,Y:Real):Real;
Function FrExp(X:Real;Var Exponent:Integer):Real;
Function LDExp(x:Real;p:Integer):Real;
Function LDiv(Numer,Denom:LongInt):LongInt;
Function Log(x:Real):Real;
Function Log10(x:Real):Real;
Function Log1p(x:Double):Double;
Function Modf(X:Real;Var IPtr:Real):Real;
Function POW(a,b:Real):Real;
Function Round(x:Double):Double;
Function Sin(X:Real):Real;
Function SinH(X:Real):Real;
Function Sqrt(X:Real):Real;
Function Tan(X:Real):Real;
Function TanH(X:Real):Real;
Function y0(x:Double):Double;
Function y0f(x:Single):Single;
Function y0l(x:Extended):Extended;
Function y1(x:Double):Double;
Function y1f(x:Single):Single;
Function y1l(x:Extended):Extended;
Function yn(n:Integer;x:Double):Double;
Function ynf(n:Integer;x:Single):Single;
Function ynl(n:Integer;x:Extended):Extended;

IMPLEMENTATION

Function ACos(a:Double):Double;Begin
 If FAbs(a)=1.0 Then ACos := (1-a)*PI/2.0
                Else ACos := Atan(-a/Sqrt(1-a*a))+2*Atan(1);
End;

Function ACosf(a:Single):Single;Begin
 If FAbs(a)=1.0 Then ACosf:=(1-a)*PI/2.0
                Else ACosf:=Atanf(-a/Sqrt(1-a*a))+2*Atan(1);
End;

Function ACosH(x:Double):Double;Begin
 If x<1 Then Begin
  Writeln('Erreur: x doit ˆtre sup‚rieur ou ‚gal … 1');
  Halt(1); { On arrˆte le programme si x est inf‚rieur … 1 }
 End;
 ACosH:=Ln(x+Sqrt(x*x-1)); { Calcul de acosh(x) = ln(x + sqrt(x^2-1)) }
End;

Function ACosHf(x:Single):Single;Begin
 If x<1 Then Begin
  Writeln('Erreur: x doit ˆtre sup‚rieur ou ‚gal … 1');
  Halt(1);
 End;
 ACosHf:=Ln(x+Sqrt(x*x-1));
End;

Function ACosHl(x:Extended):Extended;Begin
 If x<1 Then Begin
  Writeln('Erreur: x doit ˆtre sup‚rieur ou ‚gal … 1');
  Halt(1);
 End;
 ACosHl:=Ln(x+Sqrt(x*x-1));
End;

Function ACosl(a:Extended):Extended;Begin
 If FAbs(a)=1.0 Then ACosl:=(1-a)*PI/2.0
                Else ACosl:=Atanf(-a/Sqrt(1-a*a))+2*Atan(1);
End;

Function ASin(a:Double):Double;Begin
 If FAbs(a)=1.0Then ASin:=PI/2.0
               Else ASin:=ATan(a/Sqrt(1.0-a*a));
End;

Function ASinf(a:Single):Single;Begin
 If FAbs(a)=1.0Then ASinf:=PI/2.0
               Else ASinf:=ATanf(a/Sqrt(1.0-a*a));
End;

Function Asinh(x:Double):Double;Begin
 If x=0Then asinh:=0
       Else asinh:=Ln(x + Sqrt(x*x+1));
End;

Function Asinhf(x:Single):Single;Begin
 If x=0Then asinhf:=0
       Else asinhf:=Ln(x + Sqrt(x*x+1));
End;

Function Asinhl(x:Extended):Extended;Begin
 If x=0Then asinhl:=0
       Else asinhl:=Ln(x + Sqrt(x*x+1));
End;

Function ASinl(a:Extended):Extended;Begin
 If FAbs(a)=1.0Then ASinl:=PI/2.0
               Else ASinl:=ATanl(a/Sqrt(1.0-a*a));
End;

Function Atan(X:Double):Double;
Var
 A,B:Real;
 N:Integer;
Begin
 A := 1.0 / Sqrt(1.0 + (X * X));
 B := 1.0;
 For N:=1 to 11 do Begin
  A := (A + B) / 2.0;
  B := Sqrt(A * B);
 End;
 Atan:=X/(Sqrt(1.0+(X*X))*A);
End;

Function ATan2(y,x:Double):Double;
Var
 R:Real;
Begin
 If(x=0)Then Begin
  If y=0 Then R:=0.0 Else
  If y>0 Then R:=pi/2 Else
  If y<0 Then R:=-pi/2;
 End
  Else
 R:=ArcTan(y/x);
 If x<0.0 Then R:=R+PI;
 If R>PI Then R:=R-2*PI;
 ATan2:=R;
End;

Function ATan2f(y,x:Single):Single;
Var
 R:Real;
Begin
 If(x=0)Then Begin
  If y=0 Then R:=0.0 Else
  If y>0 Then R:=pi/2 Else
  If y<0 Then R:=-pi/2;
 End
  Else
 R:=ArcTan(y/x);
 If x<0.0 Then R:=R+PI;
 If R>PI Then R:=R-2*PI;
 ATan2f:=R;
End;

Function ATan2l(y,x:Double):Double;
Var
 R:Real;
Begin
 If(x=0)Then Begin
  If y=0 Then R:=0.0 Else
  If y>0 Then R:=pi/2 Else
  If y<0 Then R:=-pi/2;
 End
  Else
 R:=ArcTan(y/x);
 If x<0.0 Then R:=R+PI;
 If R>PI Then R:=R-2*PI;
 ATan2l:=R;
End;

Function Atanf(X:Single):Single;
Var
 A,B:Real;
 N:Integer;
Begin
 A := 1.0 / Sqrt(1.0 + (X * X));
 B := 1.0;
 For N:=1 to 11 do Begin
  A := (A + B) / 2.0;
  B := Sqrt(A * B);
 End;
 Atanf:=X/(Sqrt(1.0+(X*X))*A);
End;

Function Atanh(x:Double):Double;Begin
 If(x<=-1)or(x>=1)Then Begin
  WriteLn('Erreur : atanh(x) n''est d‚fini que pour -1 < x < 1');
  Halt;
 End;
 Atanh:=0.5*Ln((1+x)/(1-x));
End;

Function Atanhf(x:Single):Single;Begin
 If(x<=-1)or(x>=1)Then Begin
  WriteLn('Erreur : atanh(x) n''est d‚fini que pour -1 < x < 1');
  Halt;
 End;
 Atanhf:=0.5*Ln((1+x)/(1-x));
End;

Function Atanhl(x:Extended):Extended;Begin
 If(x<=-1)or(x>=1)Then Begin
  WriteLn('Erreur : atanh(x) n''est d‚fini que pour -1 < x < 1');
  Halt;
 End;
 Atanhl:=0.5*Ln((1+x)/(1-x));
End;

Function Atanl(X:Extended):Extended;
Var
 A,B:Real;
 N:Integer;
Begin
 A := 1.0 / Sqrt(1.0 + (X * X));
 B := 1.0;
 For N:=1 to 11 do Begin
  A := (A + B) / 2.0;
  B := Sqrt(A * B);
 End;
 Atanl:=X/(Sqrt(1.0+(X*X))*A);
End;

Function cbrt(x:Double):Double;Begin
 If x<0 Then cbrt:=-POW(-x, 1/3)
        Else cbrt:=POW(x, 1/3);
End;

Function Ceil(d:Real):Integer;
Var
 R:Integer;
Begin
 R:=Trunc(d);
 If Frac(d)>0 Then R:=R+1;
 Ceil:=R;
End;

Function CopySign(x,y:Double):Double;
Begin
 If y<0 Then CopySign:=-Abs(x)
        Else CopySign:=Abs(x);
End;

Function Cos(X:Real):Real;
Var
 R,S:Real;
 I:Byte;
Begin
 R:=X*X;
 S:=42.0;
 For I:=10 downto 1 do S:=4.0*I-2.0+(-R)/S;
 S:=S*S;
 Cos:=(S-R)/(S+R);
End;

Function Cosh(x:Real):Real;Begin
 x:=FAbs(x);
 If x > 88.029691931 Then
  Cosh:=0 { Infini }
 Else
  Cosh:=(Exp(x)+Exp(-x))/ 2.0;
End;

Function DRem(x,y:Double):Double;
Var
 quotient,remainder:Double;
Begin
 If y=0 Then Begin
  WriteLn('Erreur: division par z‚ro.');
  Halt; { Arrˆt du programme en cas de division par z‚ro }
 End;
 quotient:=x/y;
 remainder:=x-(Trunc(quotient)*y);
  { Ajuster le reste pour qu'il soit dans l'intervalle [-y/2, y/2) }
 If Abs(remainder)>=y/2 Then Begin
  If remainder>0 Then Remainder:=Remainder-y
                 Else Remainder:=Remainder+y;
 End;
 DRem:=remainder;
End;

Function Erf(x:Double):Double;
Var
 t,sum,term:Double;
 i:Integer;
Begin
 If x<0 Then erf:=-erf(-x) { Sym‚trie de la fonction }
  Else
 Begin
  Sum:=0;
  term:=x;  { Premier terme de la s‚rie }
  For i:=1 To 15 do Begin
   sum:=sum+term;             { Ajout du terme actuel … la somme }
   term:=term*(x*x)/(2*i+1);  { Calcul du terme suivant }
  End;
  erf:=2/Sqrt(Pi)*Sum;        { Multiplication par le facteur constant }
 End;
End;

Function Erfc(x:Double):Double;Begin
 Erfc:=1-erf(x);
End;

Function Exp(x:Real):Real;
Var
 Inverse:Boolean;
 n,i:Integer;
 dl,q:Real;
Begin
 Inverse := False;
 n := 0;
 dl := 1;
 i := 1;
 If x < 0 Then Begin
  Inverse := True;
  x := -x;
 End;
 While x >= 2 do Begin
  x := x / 2;
  n := n + 1;
 End;
 x := x / 16;
 n := n + 4;
 q := x;
 While q > 1.0E-15 do Begin
  dl := dl + q;
  i := i + 1;
  q := q * x / i;
 End;
 For i := 1 to n do dl := dl * dl;
 If Inverse Then dl := 1 / dl;
 Exp := dl;
End;

Function Expm1(x:Double):Double;Begin
 Expm1:=Exp(x)-1;
End;


Function FAbs(a:Real):Real;Begin
 If a<0.0 Then a:=-a;
 FAbs:=a;
End;

Function Floor(d:Real):Real;
Var
 R:Real;
Begin
 R:=Trunc(d);
 If Frac(d)<0 then R:=R-1;
 Floor:=R;
End;

Function FMod(X,Y:Real):Real;Begin
 FMod:=Trunc(X) mod Trunc(Y);
End;

Function FrExp(X:Real;Var Exponent:Integer):Real;
Var
 Mantissa:Real;
Begin
 Exponent:=0;
 If (X<>0)Then
  If (FAbs(X)<0.5)Then Repeat
   X:=X*2;
   Dec(Exponent);
  Until (FAbs(X)>=0.5)
   Else
  While (FAbs(X)>=1) do Begin
   X:=X/2;
   Inc(Exponent);
  End;
 Mantissa:=X;
End;

Function LAbs(a:LongInt):LongInt;Begin
 If a<0.0 Then a:=-a;
 LAbs:=a;
End;

Function LDExp(x:Real;p:Integer):Real;

 Function IntPower(base:Real;Exponent:Integer):Real;
 Var
  i:LongInt;
  R:Real;
 Begin
  If(Base = 0.0)and(Exponent = 0)Then R:=1
   Else
  Begin
   i:=LAbs(Exponent);
   R:=1.0;
   While i>0 do Begin
    While (i and 1)=0 do Begin
     i:=i shr 1;
     Base:=Sqr(base);
    End;
    i:=i-1;
    R:=R*Base;
   End;
   If Exponent<0 Then R:=1.0/R;
  End;
  IntPower:=R;
 End;

Begin
 LDExp:=x*IntPower(2.0,p);
End;

Function LDiv(Numer,Denom:LongInt):LongInt;Begin
 LDiv:=Numer div Denom;
End;

Function Log(x:Real):Real;
Var
 negatif:Boolean;
 fois,i:Integer;
 ajout,savx,xp,quotient,dl:Real;
Begin
 negatif := False;
 fois := 1;
 ajout := 0;
 If x <= 0.0 Then Begin
  Log:=0;
  System.Exit;
 End;
 If x < 1.0 Then Begin
  negatif := True;
  x := 1.0 / x;
 End;
 While x >= 10.0 do Begin
  x := x / 10.0;
  ajout := ajout + 2.302585092994046;
 End;
 While x >= 1.1 do Begin
  x := Sqrt(x);
  fois := fois * 2;
 End;
 x := x - 1;
 savx := x;
 i := 2;
 xp := x * x;
 quotient := (xp / i);
 dl := x - quotient;
 While 1.0E-15 < quotient do Begin
  i := i + 1;
  xp := xp * x;
  dl := dl + (xp / i);
  i := i + 1;
  xp := xp * x;
  quotient := (xp / i);
  dl := dl - quotient;
 End;
 dl := dl * fois;
 dl := dl + ajout;
 If(negatif)Then dl := - dl;
 Log:=dl;
End;

Function Log10(x:Real):Real;Begin
 Log10:=Log(x)/2.3025850930;
End;

Function Log1p(x:Double):Double;Begin
 If x<=-1 Then Begin
  Writeln('Erreur: x doit ˆtre sup‚rieur … -1');
  Halt(1);
 End;
 Log1p:=Ln(1+x);
End;

Function Modf(X:Real;Var IPtr:Real):Real;Begin
 Modf:=Frac(X);
 IPtr:=X-Frac(X);
End;

Function POW(a,b:Real):Real;
Var
 p:Real;
 I:Integer;
Begin
 p:=1;
 For i:=1 to Trunc(b) do Begin
  p:=p*a;
 End;
 Pow:=p;
End;

Function Round(x:Double):Double;Begin
 Round:=System.Round(x);
End;

Function Sin(X:Real):Real;
Var
 R,S:Real;
 I:Byte;
Begin
 R:=X*X;
 S:=42.0;
 For I:=10 downto 1 do S:=4.0*I-2.0+(-R)/S;
 Sin:=2.0*X*S/(R+S*S);
End;

Function SinH(X:Real):Real;Begin
 SinH:=(Exp(X)-Exp(-X))/2;
End;

Function Sqrt(X:Real):Real;
Var
 A,B,M,XN:Real;
Begin
 If X=0.0Then Begin
  Sqrt:=0.0;
 End
  Else
 Begin
  M := 1.0;
  XN := X;
  While XN >= 2.0 do Begin
   XN := 0.25 * XN;
   M := 2.0 * M;
  End;
  While XN < 0.5 do Begin
   XN:=4.0 * XN;
   M:=0.5 * M;
  End;
  A:=XN;
  B:=1.0-XN;
  Repeat
   A:=A*(1.0+0.5*B);
   B:=0.25*(3.0+B)*B*B;
  Until B<1.0E-15;
  Sqrt:=A*M;
 End;
End;

Function Tan(X:Real):Real;Begin
 Tan:=Sin(X)/Cos(X);
End;

Function TanH(X:Real):Real;Begin
 TanH:=(Exp(X)-Exp(-X))/(Exp(X)+Exp(-X));
End;

Function y0(x:Double):Double;
Const
 P1=-0.4900604943;
 P2= 0.1275274390;
 P3=-0.5153438139;
 P4= 0.7349264552;
 P5=-0.4257927570;
 P6= 0.1424062210;
 Q1= 0.2499580570;
 Q2= 0.2325802611;
 Q3= 0.3865479267;
 Q4= 0.9897861946;
 Q5= 1.0000000000;
Var
 z:Double;
Begin
 If x<0 Then Begin
  Writeln('Erreur: x doit ˆtre positif.');
  Halt(1);
 End;
 If x<8.0 Then Begin
  z:=x*x;
  y0 := (P1 + z * (P2 + z * (P3 + z * (P4 + z * (P5 + z * P6))))) /
        (Q1 + z * (Q2 + z * (Q3 + z * (Q4 + z * Q5))));
 End
  Else
 Begin
   { Approximation pour x >= 8 bas‚e sur sin(x) et cos(x) }
  y0 := Sqrt(2 / (Pi*x))*(Sin(x)+Cos(x));
 End;
End;

Function y0f(x:Single):Single;
Const
 P1=-0.4900604943;
 P2= 0.1275274390;
 P3=-0.5153438139;
 P4= 0.7349264552;
 P5=-0.4257927570;
 P6= 0.1424062210;
 Q1= 0.2499580570;
 Q2= 0.2325802611;
 Q3= 0.3865479267;
 Q4= 0.9897861946;
 Q5= 1.0000000000;
Var
 z:Single;
Begin
 If x<0 Then Begin
  Writeln('Erreur: x doit ˆtre positif.');
  Halt(1);
 End;
 If x<8.0 Then Begin
  z:=x*x;
  y0f:=(P1 + z * (P2 + z * (P3 + z * (P4 + z * (P5 + z * P6))))) /
       (Q1 + z * (Q2 + z * (Q3 + z * (Q4 + z * Q5))));
 End
  Else
 Begin
   { Approximation pour x >= 8 bas‚e sur sin(x) et cos(x) }
  y0f := Sqrt(2 / (Pi * x)) * (Sin(x) + Cos(x));
 End;
End;

Function y0l(x:Extended):Extended;
Const
 P1=-0.4900604943;
 P2= 0.1275274390;
 P3=-0.5153438139;
 P4= 0.7349264552;
 P5=-0.4257927570;
 P6= 0.1424062210;
 Q1= 0.2499580570;
 Q2= 0.2325802611;
 Q3= 0.3865479267;
 Q4= 0.9897861946;
 Q5= 1.0000000000;
Var
 z:Extended;
Begin
 If x<0 Then Begin
  Writeln('Erreur: x doit ˆtre positif.');
  Halt(1);
 End;
 If x<8.0 Then Begin
  z := x * x;
  y0l := (P1 + z * (P2 + z * (P3 + z * (P4 + z * (P5 + z * P6))))) /
         (Q1 + z * (Q2 + z * (Q3 + z * (Q4 + z * Q5))));
 End
  Else
 Begin
   { Approximation pour x >= 8 bas‚e sur sin(x) et cos(x) }
  y0l := Sqrt(2 / (Pi * x)) * (Sin(x) + Cos(x));
 End;
End;

Function y1(x:Double):Double;
Var
 term,sum,x2:Double;
 n:Integer;
Begin
 If x <= 0 Then Begin
  WriteLn('La fonction y1(x) n''est pas d‚finie pour x <= 0.');
  Halt(1)
 End;
 x2:=x/2;
 sum:=0;
 term:=x2;
 For n:=1 to 20 do Begin
  Sum:=Sum+Term;
  Term:=-Term*x2*x2/((2*n)*(2*n+1));
 End;
 y1:=(2/Pi)*Sum;
End;

Function y1f(x:Single):Single;
Var
 term,sum,x2:Single;
 n:Integer;
Begin
 If x <= 0 Then Begin
  WriteLn('La fonction y1(x) n''est pas d‚finie pour x <= 0.');
  Halt(1)
 End;
 x2:=x/2;
 sum:=0;
 term:=x2;
 For n:=1 to 20 do Begin
  Sum:=Sum+Term;
  Term:=-Term*x2*x2/((2*n)*(2*n+1));
 End;
 y1f:=(2/Pi)*Sum;
End;

Function y1l(x:Extended):Extended;
Var
 term,sum,x2:Extended;
 n:Integer;
Begin
 If x <= 0 Then Begin
  WriteLn('La fonction y1(x) n''est pas d‚finie pour x <= 0.');
  Halt(1)
 End;
 x2:=x/2;
 sum:=0;
 term:=x2;
 For n:=1 to 20 do Begin
  Sum:=Sum+Term;
  Term:=-Term*x2*x2/((2*n)*(2*n+1));
 End;
 y1l:=(2/Pi)*Sum;
End;

Function yn(n:Integer;x:Double):Double;
Var
 ynm1,ynm2,temp:Double;
 i:Integer;
Begin
 If n=0 Then yn:=y0(x) Else
 If n=1 Then yn:=y1(x)
  Else
 Begin
  ynm2:=y0(x);
  ynm1:=y1(x);
  For i:=2 to n do Begin
   temp:=(2*i-1)/x*ynm1-ynm2;
   ynm2:=ynm1;
   ynm1:=temp;
  End;
  yn:=ynm1;
 End;
End;

Function ynf(n:Integer;x:Single):Single;
Var
 ynm1,ynm2,temp:Single;
 i:Integer;
Begin
 If n=0 Then ynf:=y0(x) Else
 If n=1 Then ynf:=y1(x)
  Else
 Begin
  ynm2:=y0(x);
  ynm1:=y1(x);
  For i:=2 to n do Begin
   temp:=(2*i-1)/x*ynm1-ynm2;
   ynm2:=ynm1;
   ynm1:=temp;
  End;
  ynf:=ynm1;
 End;
End;

Function ynl(n:Integer;x:Extended):Extended;
Var
 ynm1,ynm2,temp:Extended;
 i:Integer;
Begin
 If n=0 Then ynl:=y0(x) Else
 If n=1 Then ynl:=y1(x)
  Else
 Begin
  ynm2:=y0(x);
  ynm1:=y1(x);
  For i:=2 to n do Begin
   temp:=(2*i-1)/x*ynm1-ynm2;
   ynm2:=ynm1;
   ynm1:=temp;
  End;
  ynl:=ynm1;
 End;
End;

END.