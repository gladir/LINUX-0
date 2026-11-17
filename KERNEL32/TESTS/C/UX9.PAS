Program UX9;
{ lot E5 : litteraux #nn'texte'#nn'texte' (avant : tronques apres le
  deuxieme #nn) et fuseaux horaires de L32API (formes TZ sans fichier) }
Var S : String; I : LongInt;
Begin
  S := #27'[0m'#27'[2J'#27'[H';
  WriteLn(Length(S));
  For I := 1 To Length(S) Do Write(Ord(S[I]), ' ');
  WriteLn;
  S := #65'bc'#68'ef'#71;
  WriteLn(S, ' ', Length(S));
  S := 'a'#10'b'#10'c';
  WriteLn(Length(S));
  S := #27'[1;1H'#27'[0;1;37;44m LINUX';
  WriteLn(Length(S), ' ', Ord(S[8]), ' ', Copy(S, 18, 6));
  LnxTzSelect('EST5');
  WriteLn(LnxTzAt(0), ' ', LnxTzAt(1700000000), ' ', LnxTzUtcOf(3600));
  LnxTzSelect('UTC');
  WriteLn(LnxTzAt(0));
  LnxTzSelect('CET-1');
  WriteLn(LnxTzAt(1700000000), ' ', LnxTzUtcOf(1700003600));
  LnxTzSelect('IST-5:30');
  WriteLn(LnxTzAt(5), ' ', LnxTzUtcOf(19800));
End.
