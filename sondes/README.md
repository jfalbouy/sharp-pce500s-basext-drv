# Sondes — mesurer ce que la ROM fait déjà

*Rédigé le 2026-09-25 — mis à jour le 2026-09-25*

Ce dossier porte des **sondes** : de petits programmes qui posent **une** question à la machine et
rendent sa réponse, sans rien installer de durable. Ils ne font pas partie du pilote.

> **Légende**, celle de `BASEXT/MODE-EMPLOI.md` : ✅ confirmé (mesuré sur machine) · 📖 lu dans la
> ROM ou une documentation, pas éprouvé · ⚠️ piège ou point incertain · ⛔ erreur corrigée, gardée
> écrite avec ce qui l'a démentie.

---

## T48 — la commande IOCS `48h` crée-t-elle vraiment un bloc en tête ?

### Pourquoi la question vaut d'être posée

L'installateur de ce dépôt fait **à la main** ce qu'une commande du device 6 semble faire seule :
il compacte (`47h`), cherche le premier bloc qui n'est pas un pilote, **décale vers le haut** tous
les blocs suivants, recale `(txtbas)`/`(datbas)` et remet à zéro `[(iocsw)+3Ah]`. Or le carnet du
désassembleur donne, pour le même device : `48h` `block_create_top`, « création d'un bloc mémoire
**en tête** des blocs, propre au PC-E500 » — `(ch)` = lecteur, `X` = nom, `Y` = taille, retour
`Y` = adresse du bloc créé.

📖 **Ce que la ROM en dit** (`rom83`, lu le 2026-09-25, traitement de `48h` en `0F034Bh`) :

| Ce que fait `0F034Bh` | Où |
|---|---|
| contrôle de place, puis `Y ← Y − 22h` (la taille demandée inclut donc l'en-tête) | `SUB_F0244`, `SUB_F02AF` |
| refus si le nom existe déjà — c'est la commande `41h` `search_phys` | `callf SUB_F0063` |
| lit `[(iocsw)+03Ah]` et **efface le bit du lecteur** (bit 1 pour `S1:`, bit 2 pour `S2:`) | `call SUB_F0330` |
| **déplace la mémoire** : `mv (si),y` puis la commande `43h` `block_transfer` | `callf 0F01C1h` |
| copie un gabarit d'en-tête de `22h` octets dans le bloc | `DB_F041C` |

Autrement dit, trois des gestes de notre installateur sont **déjà dans la ROM** — dont la remise à
zéro de l'octet que `bd_linkbas` remet à zéro lui aussi. La commande `45h` (`0F039Eh`) est la même
routine **sans** le déplacement.

⚠️ Ce que la lecture ne dit **pas** : si `48h` recale `(txtbas)`/`(datbas)`, ou s'il se contente
d'effacer le drapeau pour que la ROM les retrouve plus tard. C'est ce que la sonde doit montrer.

### Ce que la sonde fait

`T48.ASM` (68 octets, assemblé en `0BF000h`) appelle `48h` **une seule fois**, sans compactage
préalable, pour un bloc `T48     SYS` de 256 octets sur `S1:`, et range la réponse hors de son
code :

| Adresse | Contenu |
|---|---|
| `0BFBF0h` | adresse du bloc créé (`Y` rendu), `0FFFFFh` si refus |
| `0BFBF3h` | code d'erreur rendu dans `A` |
| `0BFBF4h` | `1` si la retenue était armée au retour |

Elle rend **toujours** la main retenue claire (`rc`), erreur comprise : pas de « Syntax error »
côté BASIC.

`T48.BAS` relève, par `PEEK` seulement, la chaîne des blocs de `S1:` (adresse, nom, attribut,
taille), `FIN`/`S1BTM`, `(txtbas)`/`(datbas)`, `[(iocsw)+3Ah]`, puis la zone de résultat.

### Protocole

⚠️ **Sur un `S1:` dont on peut se passer** : la sonde crée un bloc et déplace de la mémoire. Un
RESET complet remet tout en ordre, mais il efface `S1:`.

1. `POKE &BFE03,&1A,&FD,&B,0,&C,0 : CALL &FFFD8` — réserver 3072 octets ;
2. `LOAD M "X:T48.OBJ"` (ou `F:`), puis charger `T48.BAS` ;
3. **`RUN`** : c'est le relevé **avant**. Noter la chaîne, `TXT`, `DAT`, `+3A`. La sonde répond
   « SONDE PAS ENCORE APPELEE » ;
4. en **mode direct**, `CALL &BF000` — l'appel à `48h` ;
5. **`RUN`** de nouveau : relevé **après**, plus l'adresse rendue.

L'appel se fait en mode direct, et non depuis le programme, pour que le déplacement de mémoire ne
tombe pas au milieu de l'exécution du programme qui vit, lui, dans `TEXT.BAS`.

6. Nettoyer : `SET "S1:T48.SYS"," "` puis `KILL "S1:T48.SYS"`.

### Comment lire le résultat

| Observation | Ce qu'elle établit |
|---|---|
| le bloc `T48     SYS` apparaît **en tête** de la chaîne, `DATA.BAS` et les autres décalés vers le haut | `48h` fait bien l'insertion **et** le décalage : nos installateurs peuvent perdre leur boucle de montée des blocs |
| `TXT` et `DAT` désignent encore les bons blocs après l'appel | `48h` recale le BASIC : `bd_linkbas` devient inutile |
| `TXT`/`DAT` périmés mais la machine se porte bien, `+3A` changé | la ROM **revalide plus tard** grâce au drapeau : c'est le drapeau qui compte, pas le recalage |
| refus, code d'erreur dans `0BFBF3h` | lire le code dans `04-fcs-iocs.md` §2.2 ; un refus « pas de place » signifierait que `47h` reste nécessaire avant |
| le bloc apparaît **ailleurs** qu'en tête | le carnet et la ROM se lisent autrement qu'on l'a cru : garder la mesure, corriger le référentiel |

Quoi qu'il arrive, le résultat va dans
`Referentiel PC-E500S SC62015/03-memoire-et-systeme-pc-e500s.md` §7bis, qui porte aujourd'hui la
question, et dans `CONCEPTION.md` §4.1 s'il change l'installateur.

### Construire

```powershell
cd C:\Claude\BASEXT-DRV\sondes
C:\Claude\xasm2026-4\bin\xasm2026-4.exe T48.ASM -OT48.OBJ -L -S -B -K
```

`pce500.inc` est une **copie** de `../src/pce500.inc`, elle-même générée : ne pas l'éditer. Le `.uu`
a été renommé en `.UU` en deux temps, comme le veut la règle de casse de Windows
(`05-format-fichiers-et-xasm.md` §4).
