{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Linux Pascal)
  @description: Exemple de segments-unites (SegmentUnit) d'Linux Pascal : deux
   segments-unites ont chacun leurs constantes A et B et leurs variables C et
   D, sans conflit, et chacun son segment de code.
   LPC SEGUNIT.PAS (MS-DOS) ou LPC /X SEGUNIT.PAS (LINUX-0)
}

Program MonProgramme;

SegmentUnit GestionFichiers;

Const A = 1;
      B = 1;

Var C,D:Integer;

SegmentInterface

Procedure OuvrirFichier(Nom: STRING);
Procedure FermerFichier;

SegmentImplementation

  Procedure OuvrirFichier(Nom: STRING);
  Begin
    C:=A;
    WriteLn('GestionFichiers.OuvrirFichier(',Nom,') A=',A,' C=',C);
  End;

  Procedure FermerFichier;
  Begin
    WriteLn('GestionFichiers.FermerFichier');
  End;

SegmentEnd;

SegmentUnit GestionDossier;

Const A = 10;
      B = 10;

Var C,D:Integer;

SegmentInterface
  Procedure OuvrirDossier(Nom: STRING);
  Procedure FermerDossier;

SubImplementation

  Procedure OuvrirDossier(Nom: STRING);
  Begin
    C:=A;
    WriteLn('GestionDossier.OuvrirDossier(',Nom,') A=',A,' C=',C);
  End;

  Procedure FermerDossier;
  Begin
    WriteLn('GestionDossier.FermerDossier');
  End;

SegmentEnd;

BEGIN
  GestionFichiers.OuvrirFichier('TEST.TXT');
  GestionDossier.OuvrirDossier('REP');
  GestionDossier.FermerDossier;
  GestionFichiers.FermerFichier;
END.
