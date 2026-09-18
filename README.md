# BASEXT-DRV — BASEXT résident, sous forme de pilote

*Rédigé le 2026-09-16 — mis à jour le 2026-09-18*

Les mots-clés de [BASEXT](../BASEXT) (`LPEEK`, `MOD`, `TRIM$`, `XCONSOLE`…) installés dans un
**bloc de pilote** de `S1:` (`BASEXT.SYS`, device `BEXT:`), protégé comme un fichier `.SYS`, au
lieu de la zone langage machine. Cette zone redevient libre pour d'autres programmes, qui peuvent
alors employer les nouvelles instructions.

Le projet assemble deux référents sans les recopier :

| Référent | Ce qu'il apporte |
|---|---|
| `C:\Claude\BASEXT` (`MODE-EMPLOI.md`) | le code des 14 mots-clés, **inclus** tel quel (`src/BASEXT.ASM`) |
| `C:\Claude\xasm2026-4\Exemples\DRIVER_TEMPLATE` | l'installateur, les en-têtes de bloc et IOCS, la désinstallation |

## Une source, deux objets

Le code des 14 mots-clés n'existe qu'**une fois** : `C:\Claude\BASEXT\src\BASEXT.ASM`. Il donne
deux objets, qui sont deux **façons de l'installer**, et jamais deux extensions à charger ensemble.

```
                      BASEXT/src/BASEXT.ASM   (les 14 mots-cles, UNE source)
                         |                              |
          assemble SEUL  |                              |  INCLUS par BASEXT-DRV/src/BASEXTDR.ASM
          (xasm2026-4)   |                              |  (outils/construire.py)
                         v                              v
                   BASEXT.OBJ                     BASEXTDR.OBJ
          org 0BF000h, 2709 octets        org 0BE400h, 4536 octets :
          = le code lui-meme              image du bloc (en-tetes + bd_arret + bd_reprise
                                          + le MEME code) + installateur en 0BF000h + table
```

| | `BASEXT.OBJ` (module autonome) | `BASEXTDR.OBJ` (pilote) |
|---|---|---|
| Réservation avant `LOAD M` | 3072 octets | 6144 octets |
| Ce que fait `CALL &BF000` | exécute `start` : le code **reste** en `0BF000h`, les crochets y pointent | exécute l'**installateur** : copie le code dans `S1:` (`BASEXT.SYS`), puis appelle `start` **dans le bloc** |
| Où vivent les mots-clés ensuite | dans la zone langage machine | dans `S1:`, en tête des blocs |
| La zone langage machine | **doit rester réservée** | **peut être rendue** au BASIC |
| Ce qui diffère dans le code | rien : c'est le module éprouvé | trois lignes masquées (`include pce500.inc`, `org`, `pre_on`) et le test du filtre d'écran de `XCONSOLE`, le tout sous `ifdef basext_pilote` |
| Tokens des mots-clés | `07h`, `0Ah`, `0Eh`, `0Fh`, `C2h`–`CAh`, `CFh` | les **mêmes** : un programme tokenisé sous l'un se lit sous l'autre |
| Désinstallation | aucune entrée | `CALL &BF000 "-U"`, puis `SET`/`KILL` |

**On emploie l'un OU l'autre.** Le BASIC n'a qu'un crochet par table : si un `BASEXT.OBJ` est
installé, l'installateur du pilote refuse (`Error: BASIC extension in use.`).

### Où est le code des mots-clés dans `BASEXTDR.ASM`

**Il n'y est pas écrit : une seule ligne l'apporte**, `include ..\..\BASEXT\src\BASEXT.ASM`, entre deux
bandeaux `####`. À l'assemblage, XASM la remplace par tout `BASEXT.ASM`. Le reste du fichier est ce
qui fait de ce code un pilote :

| Partie de `BASEXTDR.ASM` | Contenu | Écrit où |
|---|---|---|
| `block_top` | en-tête de bloc (`0FBh`, `BASEXT  SYS`) et en-tête IOCS (`BEXT:`), entrée IOCS | ici |
| `bd_arret` | rend le filtre d'écran et les crochets, pour la désinstallation | ici |
| `bd_reprise` | remet le maillon `d_link` et les crochets (`CALL &xxxxx`) | ici |
| **`include ..\..\BASEXT\src\BASEXT.ASM`** | **les 14 mots-clés, le filtre, `kw_table`, `disp_table`, les variables** | **`BASEXT/src`** |
| `block_bottom` | fin du bloc résidant | ici |
| `bd_entree` (`0BF000h`) | installateur, désinstallateur, messages | ici |
| `include reloc.inc` | table de relocation | générée par `construire.py` |

**Le code assemblé se lit dans `src/BASEXTDR.lst`**, que `construire.py` produit sans `-K` pour
que le contenu inclus y figure en entier, commentaires compris. Exemples, relevés dans ce listing
(les adresses changent à chaque modification : les relire, ne pas s'y fier de mémoire) :

| Étiquette de BASEXT | Adresse dans l'image (chargée en `0BE400h`) | Décalage dans le bloc |
|---|---|---|
| `start` | `0BE484h` | `+084h` |
| `lpeek` | `0BE4B6h` | `+0B6h` |
| `xconsole` | `0BEAB3h` | `+6B3h` |
| `kw_table` | `0BED69h` | `+969h` |

Une fois l'image copiée dans `S1:`, chaque adresse devient **adresse du bloc + décalage**. Lors
de l'essai du 2026-09-16, le bloc était en `080018h` : `LPEEK` en `0800CEh`, `kw_table` en `080981h`.

**Une modification de `BASEXT.ASM` se reporte dans les deux** : réassembler `BASEXT.OBJ` dans
`BASEXT/src`, puis relancer `outils/construire.py` ici, qui régénère aussi la table de relocation
et `essais/DRVTEST.BAS`.

## État

**Version 0.2 : ✅ éprouvée sur PC-E500S réel le 2026-09-18**, avec `PLINK.SYS` déjà installé (insertion derrière lui, `BEXTTEST.BAS` OK, `ON`/`OFF` sans effet), après l'émulateur le 2026-09-16 (bloc immobile, zone rendue, soft RESET sans effet, désinstallation qui rend crochets et maillon).

⛔ **La version 0.1 est à proscrire** : elle ajoutait le bloc en fin de chaîne, derrière
`DATA.BAS`, qui contient la mémoire libre ; au premier besoin de place du BASIC le bloc était
déplacé sans relocation, et PockEmul s'arrêtait (mesuré, `CONCEPTION.md` §5bis). La 0.2 reprend
le modèle de PLINKC 1.62, validé sur matériel : insertion **avant** `DATA.BAS`, décalage des blocs
suivants, recalage de `TEXT.BAS`/`DATA.BAS` (§5ter).

- `src/BASEXTDR.ASM` → `BASEXTDR.OBJ` (4536 octets, chargé en `0BE400h`, installateur en
  `0BF000h`) et `BASEXTDR.UU`. `outils/construire.py` : table de relocation relue dans l'objet
  (155 champs), relocation simulée, objet **identique à l'octet** à celui du moteur C.
- L'installateur **vérifie sa relocation sur la machine** avant de copier le bloc.
- `BASEXT/src/BASEXT.ASM` est **incluable** (`def basext_pilote`) ; son module autonome reste
  identique à l'octet.
- Défauts de xasm2026-4 signalés (`xasm2026-4/RAPPORT-BUG-rel-champ-adresse.md`,
  `RAPPORT-BUG-octet-pre.md`), ✅ **corrigés le 2026-09-17** et revérifiés ici (`CONCEPTION.md` §3.4).

## Porter l'objet sur le Sharp

- **Par PLINKC**, si `PLINK.SYS` est installé (✅ éprouvé le 2026-09-18) : sur le Sharp,
  `COPY "L:BASEXTDR.OBJ" TO "F:"`, puis `LOAD M "F:BASEXTDR.OBJ"`. Le fichier reste sur `F:` :
  il resservira pour `CALL &BF000 "-U"` sans nouveau transfert.
- **Par l'auto-décodeur** `src/BASEXTDR.UU`, un programme BASIC qui recrée `BASEXTDR.OBJ` sur `E:`
  ou `F:` (c'est la voie employée sur l'émulateur).

## Essai sur l'émulateur

Partir d'une machine propre (RESET complet). Le fichier objet se range sur `X:` ou `F:`.

1. Charger `essais/BLOCS.BAS`, `RUN` : la liste des blocs **avant** (`DATA.BAS` en tête).
2. Installer :

   ```basic
   POKE &BFE03,&1A,&FD,&B,0,&18,0:CALL &FFFD8   ' reserver 6144 octets (petit reset)
   LOAD M "X:BASEXTDR.OBJ"                      ' ou "F:BASEXTDR.OBJ"
   CALL &BF000
   ```

   Attendu : `BASEXT-DRV 0.2 (BEXT:)` puis `Installed. Hooks: CALL &xxxxx`. **Noter l'adresse.**
   Refus possibles, sans rien modifier : `already installed` (l'adresse est réaffichée),
   `BASIC extension in use`, `not enough memory`, `over two pages`, `block over loader`,
   `relocation check` (la relocation a mal tourné : rien n'a été copié), `LOAD M the .OBJ again`.
3. `RUN` de `BLOCS.BAS` : `BASEXT  SYS` doit être **en tête**, ou juste **derrière les pilotes
   déjà présents** (`PLINK.SYS` par exemple), à l'ancienne adresse de `DATA.BAS`, et y **rester**
   aux `RUN` suivants.
4. Taper `1 REM ABCDEFGHIJ`, `RUN` : l'adresse de `BASEXT  SYS` ne doit **pas** changer.
5. Charger `essais/DRVTEST.BAS`, `RUN` : `BLOC …`, `D_LINK : OK`, `CROCHETS : OK`.
6. Seulement alors, charger `BASEXT/essais/BEXTTEST.BAS` : `*** 14/14 OK ***`. Ses `LPOKE &BFBF0`
   tombent dans la zone réservée à l'étape 2.
7. Libérer la grande zone en gardant 16 octets pour les essais, puis relancer `DRVTEST.BAS` :

   ```basic
   POKE &BFE03,&1A,&FD,&B,&10,0,0:CALL &FFFD8
   ```

   S'il répond `REPARER : CALL &xxxxx`, taper ce `CALL`, et **noter** ce qui manquait
   (`d_link`, crochets) : c'est la mesure du §4.2.

**Désinstaller** (l'installateur doit être rechargé) :

```basic
POKE &BFE03,&1A,&FD,&B,0,&18,0:CALL &FFFD8
LOAD M "X:BASEXTDR.OBJ"
CALL &BF000 "-U"
SET "S1:BASEXT.SYS"," "
KILL "S1:BASEXT.SYS"
```

⚠️ **Ne jamais `KILL` sans `CALL &BF000 "-U"` avant** : les crochets du BASIC et le filtre de
`XCONSOLE` pointeraient dans de la mémoire libérée.

⚠️ **Ne pas `KILL` un autre pilote installé AVANT BASEXT-DRV** (par exemple `PLINK.SYS`, placé
sous lui dans `S1:`) tant que BASEXT-DRV est en place : le recompactage ferait descendre
`BASEXT.SYS` sans relocation. D'abord désinstaller BASEXT-DRV, ensuite retirer l'autre pilote,
puis réinstaller BASEXT-DRV (`CONCEPTION.md` §5ter).

## Arborescence

```
BASEXT-DRV/
├── README.md             ce fichier
├── CONCEPTION.md         decisions, mesures, versions 0.1 et 0.2, plan
├── src/
│   ├── BASEXTDR.ASM      le pilote (inclut ..\..\BASEXT\src\BASEXT.ASM)
│   ├── BASEXTDR.OBJ/.lst/.UU   produits par construire.py
│   ├── reloc.inc         table de relocation GENEREE (ne pas editer)
│   └── pce500.inc        constantes systeme, GENEREES (copie de BASEXT/src)
├── essais/
│   ├── DRVTEST.BAS       etat du pilote, GENERE par construire.py (PEEK seulement)
│   └── BLOCS.BAS         la chaine des blocs de S1: (PEEK seulement)
└── outils/
    ├── construire.py     table, assemblage, controles, moteur C
    └── reloc.py          mesure et verification de la table de relocation
```

## Construire

```powershell
python C:\Claude\BASEXT-DRV\outils\construire.py
```

**Jamais `xasm2026-4` seul** : la table de relocation dépend aussi de `BASEXT.ASM`, qui vit dans
un autre dépôt. `construire.py` la régénère, assemble **sans `-K`** (avec `-K`, le corps inclus de
BASEXT perdrait ses commentaires dans le listing), puis vérifie tout. Code de sortie 1 au premier
écart.

Le préfixe `rel` de xasm2026-4 produit aussi une table au format Kon. Faux sur 14 formes jusqu'au
2026-09-16, ✅ corrigé le 2026-09-17 : sur BASEXT, sa table égale celle de `reloc.py`
(`CONCEPTION.md` §3.4). BASEXT-DRV garde `reloc.py`, qui n'impose aucune marque dans la source
de BASEXT.

## Règles de maintenance

- Français partout ; sources assembleur sans accents.
- **Une adresse se vérifie dans la ROM ou dans le `.lst`, jamais de mémoire.** `DRVTEST.BAS` est
  régénéré par `construire.py` avec les décalages du listing : ne pas l'éditer.
- Le bloc ne cite **jamais** une adresse de l'installateur, et aucune assertion ne porte sur une
  adresse absolue (`CONCEPTION.md` §3.2).
- `reloc.inc` et `pce500.inc` sont **générés** : ils ne s'éditent pas.
- Fichiers `.BAS` pour la machine : CRLF et MAJUSCULES ASCII ; noms de fichier Sharp en 8.3.
