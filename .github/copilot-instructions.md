# LINUX-0 Directives de Codage IA

## Vue d'ensemble du projet
LINUX-0 est une collection de clones de commandes Linux écrites en Pascal (Turbo Pascal 7 / Free Pascal 3.2). Chaque fichier `.PAS` implémente une seule commande Unix/Linux avec support multi-plateforme pour DOS, Windows et Linux.

## Architecture et Structure

### Organisation des fichiers
- **Répertoire racine** : Implémentations individuelles des commandes (`CAT.PAS`, `AWK.PAS`, `SED.PAS`, etc.)
- **Répertoire `LIB/`** : Unités utilitaires partagées (`STDIO.PAS`, `STDLIB.PAS`, `MATH.PAS`, etc.)
- **`BIN16/` & `WIN32/`** : Exécutables compilés pour différentes plateformes

### Modèle de structure de code
Chaque commande suit ce modèle cohérent :
```pascal
{ @author: Sylvain Maltais (support@gladir.com)
  @created: YYYY
  @website(https://www.gladir.com/linux-0)
  @abstract(Target: Free Pascal 3.2, Turbo Pascal 7)
}

Program NOM_COMMANDE;
Uses DOS, [autres unités];

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('NOM_COMMANDE : Description...');
  WriteLn('Syntaxe : NOM_COMMANDE [options]');
 End
  Else
 Begin
  { Implémentation de la commande }
 End;
END.
```

## Conventions de développement

### Système d'aide
- **Toujours implémenter** : paramètres `/?`, `--help`, `-h`, `/h`, `/H`
- Afficher les descriptions en français par défaut, en anglais avec la variable d'environnement `LANGUAGE=EN`
- Utiliser un format cohérent : nom de commande, description, syntaxe, détails des paramètres

### Gestion des erreurs
- Utiliser les directives `{$I-}` et `{$I+}` autour des opérations de fichier
- Vérifier `IOResult` pour les erreurs d'opération de fichier
- Fournir des messages d'erreur clairs en français (ex: "Fichier introuvable !")

### Modèle d'opérations de fichier
```pascal
Assign(Handle, FileName);
{$I-}Reset(Handle);{$I+}
If IOResult=0 Then Begin
  { Traiter le fichier }
  Close(Handle);
End
 Else
WriteLn('Erreur de lecture du fichier');
```

### Compatibilité multi-plateforme
- Utiliser la compilation conditionnelle : `{$IFDEF WINDOWS}`, `{$IFDEF UNIX}`, `{$IFDEF DARWIN}`
- Inclure les unités spécifiques à la plateforme dans la clause Uses avec des conditions
- Gérer les séparateurs de chemin et les différences de système de fichiers

### Utilitaires de manipulation de chaînes
Fonctions utilitaires communes qui apparaissent dans plusieurs fichiers :
- `StrToUpper()` : Convertir en majuscules
- `StrToLower()` : Convertir en minuscules  
- `TrimL()` : Supprimer les espaces à gauche
- `PadRight()` : Compléter à droite avec des espaces

### Support multi-langue
- Vérifier la variable d'environnement `LANGUAGE`
- Support : Français (par défaut), Anglais (`EN`), Allemand (`GR`), Italien (`IT`), Espagnol (`SP`)
- Utiliser un type énuméré : `Language:(_French,_English,_Germany,_Italian,_Spain);`

## Modèles d'implémentation clés

### Analyse de ligne de commande
- Utiliser `ParamCount` et `ParamStr(i)` pour traiter les arguments
- Supporter les paramètres de style Unix (`-option`) et DOS (`/option`)
- Gérer plusieurs paramètres avec des boucles : `For I:=1 to ParamCount do`

### Commandes complexes (AWK, SED)
- Utiliser la tokenisation et l'analyse pour les langages de script
- Implémenter des évaluateurs d'expression avec une précédence appropriée
- Supporter les variables de champ (`$1`, `$2`, etc.) dans AWK
- Gérer la correspondance de motifs et la substitution dans SED

### Traitement de fichiers binaires
- Utiliser des fichiers non typés : `File {$IFDEF FPC}of Byte{$ENDIF}`
- BlockRead/BlockWrite pour des E/S efficaces
- Utilitaires d'affichage hexadécimal dans plusieurs commandes

## Construction et tests

### Compilation
- **Free Pascal** : `fpc NOMFICHIER.PAS`  
- **Turbo Pascal** : `tpc NOMFICHIER.PAS`
- Aucune dépendance externe - chaque fichier compile indépendamment
- Les unités de bibliothèque dans `LIB/` peuvent être utilisées avec la clause `Uses`

### Tests multi-plateforme
Tester sur les trois plateformes cibles :
- DOS (compatibilité 16-bit)
- Windows (32/64-bit)  
- Linux (compatibilité Unix)

## Considérations spéciales

### Gestion mémoire
- Utiliser une gestion appropriée des pointeurs pour les structures dynamiques (voir `SORT.PAS` tableau de pointeurs de chaînes)
- Être attentif aux contraintes mémoire DOS en mode 16-bit

### Performance
- Utiliser des algorithmes efficaces pour le traitement de fichiers
- Mettre en tampon les opérations E/S de manière appropriée
- Considérer la gestion de gros fichiers (voir `TAIL.PAS`, `LESS.PAS`)

### Compatibilité héritée
- Maintenir la compatibilité Turbo Pascal 7
- Éviter les fonctionnalités Pascal modernes qui cassent les anciens compilateurs
- Utiliser les modèles de syntaxe Pascal classiques

Lors de l'implémentation de nouvelles commandes ou de correction de commandes existantes, suivez ces modèles établis exactement pour maintenir la cohérence à travers la base de code.
