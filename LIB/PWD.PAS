{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
  @type: Library
}

Unit PWD;

INTERFACE

Type
 TPasswd=Record
  pw_name:String[255];   { Le nom d'utilisateur }
  pw_passwd:String[255]; { Le mot de passe crypt‚ (ou une valeur de remplacement) }
  pw_uid:Integer;        { L'UID de l'utilisateur }
  pw_gid:Integer;        { Le GID de l'utilisateur }
  pw_gecos:String[255];  { Le champ GECOS (nom complet ou autre) }
  pw_dir:String[255];    { Le r‚pertoire home }
  pw_shell:String[255];  { Le shell par d‚faut }
 End;
 PPasswd=^TPasswd;

Function GetPwnam(Const Name:String):PPasswd;

IMPLEMENTATION

Function GetPwnam(Const Name:String):PPasswd;
Var
 F:Text;
 Line:String;
 Fields:Array[1..7] of String;
 ValCode:Integer;
 R:TPasswd;
 PR:PPasswd;
Begin
 Assign(F,'/etc/passwd');
 Reset(F);
 While Not Eof(F) do Begin
  ReadLn(F,Line);
  Fields[1] := Copy(Line, 1, Pos(':', Line) - 1);
  Line := Copy(Line, Pos(':', Line) + 1, Length(Line));
  Fields[2] := Copy(Line, 1, Pos(':', Line) - 1);
  Line := Copy(Line, Pos(':', Line) + 1, Length(Line));
  Fields[3] := Copy(Line, 1, Pos(':', Line) - 1);
  Line := Copy(Line, Pos(':', Line) + 1, Length(Line));
  Fields[4] := Copy(Line, 1, Pos(':', Line) - 1);
  Line := Copy(Line, Pos(':', Line) + 1, Length(Line));
  Fields[5] := Copy(Line, 1, Pos(':', Line) - 1);
  Line := Copy(Line, Pos(':', Line) + 1, Length(Line));
  Fields[6] := Copy(Line, 1, Pos(':', Line) - 1);
  Fields[7] := Copy(Line, Pos(':', Line) + 1, Length(Line));
  If Fields[1]=Name Then Begin
   R.pw_name:=Fields[1];
   R.pw_passwd:=Fields[2];
   Val(Fields[3], R.pw_uid, ValCode);
   If ValCode<>0 Then R.pw_uid:=-1;
   Val(Fields[4], R.pw_gid, ValCode);
   If ValCode<>0 Then R.pw_gid:=-1;
   R.pw_gecos := Fields[5];
   R.pw_dir := Fields[6];
   R.pw_shell := Fields[7];
   Close(F);
   GetMem(PR,SizeOf(TPasswd));
   PR^:=R;
   GetPwnam:=PR;
   Exit;
  End;
 End;
 Close(F);
 R.pw_name:='';
 GetMem(PR,SizeOf(TPasswd));
 PR^:=R;
 GetPwnam:=PR;
End;


END.