{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit STDLIB;

INTERFACE

Procedure Abort;
Function  Abs(a:Integer):Integer;
Procedure AtExit(Fonction:Pointer);
Function  AtoF(nptr:String):Real;
Function  AtoI(nptr:String):Integer;
Function  AtoL(nptr:String):LongInt;
Function  Calloc(N,size:Integer):Pointer;
Function  Div_(Numer,Denom:Integer):Integer;
Procedure Exit(Status:Integer);
Function  GetEnv(S:String):String;
Function  LAbs(a:LongInt):LongInt;
Function  Malloc(size:Integer):Pointer;
Function  Rand:Integer;
Function  StrToL(NPtr:PChar;Var EndPtr:PChar):LongInt;
Function  System_(Command:PChar):Integer;

IMPLEMENTATION

Uses DOS,Strings;

Var
 SaveExit:Pointer;

Procedure Abort;Begin
 Halt(255);
End;

Function Abs(a:Integer):Integer;Begin
 If a<0.0 Then a:=-a;
 Abs:=a;
End;

Procedure AtExit(Fonction:Pointer);Begin
 SaveExit:=ExitProc;
 ExitProc:=Fonction;
End;

Function AtoF(nptr:String):Real;
Var
 R:Real;
 Err:Word;
Begin
 Val(nptr,R,Err);
 AtoF:=R;
End;

Function AtoI(nptr:String):Integer;
Var
 I:Integer;
 Err:Word;
Begin
 Val(nptr,I,Err);
 AtoI:=I;
End;

Function AtoL(nptr:String):LongInt;
Var
 L:LongInt;
 Err:Word;
Begin
 Val(nptr,L,Err);
 AtoL:=L;
End;

Function Calloc(N,size:Integer):Pointer;
Var
 P:Pointer;
Begin
 GetMem(P,N*size);
 Calloc:=P;
End;

Function Div_(Numer,Denom:Integer):Integer;Begin
 Div_:=Numer div Denom;
End;

Procedure Exit(Status:Integer);Begin
 Halt(Status);
End;

Function GetEnv(S:String):String;Begin
 GetEnv:=DOS.GetEnv(S);
End;

Function LAbs(a:LongInt):LongInt;Begin
 If a<0.0 Then a:=-a;
 LAbs:=a;
End;

Function Malloc(size:Integer):Pointer;
Var
 P:Pointer;
Begin
 GetMem(P,size);
 Malloc:=P;
End;

Function Rand:Integer;Begin
 Rand:=Random(32767);
End;

Function StrToL(NPtr:PChar;Var EndPtr:PChar):LongInt;
Var
 R:LongInt;
 Err:Word;
 I:Integer;
Begin
 Val(StrPas(NPtr),R,Err);
 I:=0;
 While NPtr[I] in['0'..'9']do Begin
  Inc(I);
 End;
 EndPtr:=@NPtr[I];
 StrToL:=R;
End;

Function System_(Command:PChar):Integer;Begin
 SwapVectors;
 Exec(GetEnv('COMSPEC'),'/C '+StrPas(Command));
 SwapVectors;
End;

END.