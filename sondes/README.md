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

### ✅ Résultat — PC-E500S réel, J.-F. Albouy, 2026-09-25

**`48h` a refusé : `REFUS : ERR C CY 1`** — erreur `0Ch`, retenue armée, et **rien n'a bougé**.

| Relevé | Avant | Après |
|---|---|---|
| chaîne de `S1:` | `80018` PLINK SYS 25 2336 · `80938` BASEXT SYS 25 2839 · `8144F` DATA BAS 20 240798 · `BC0ED` TEXT BAS 20 1119 · `BC54C` FUNCKEY · `BC5B4` AER | la même, aux deux octets que le BASIC déplace de `TEXT` vers `DATA` près |
| `FIN` / `S1BTM` | `BC61A` / `BC61B` | `BC61A` / `BC61B` |
| `TXT` / `DAT` | `BC0EF` / `8144F` | `BC0EF` / `8144F` |
| `[(iocsw)+3Ah]` | `0` | `0` |

**Pourquoi, et c'est la ROM qui le dit.** Le traitement commence par `call SUB_F0244`, qui rend
dans `Y` **l'espace libre après la chaîne** (`[s1_btm]` − fin de chaîne) — écrasant au passage la
taille qu'on lui a passée. Vient ensuite `sub y,22h` / `jrc LOC_F040E`, et `LOC_F040E` fait
`mv a,00Ch`. Or la chaîne est **jointive et complète** : `S1BTM` − `FIN` = **1 octet**. Donc
`1 − 34` emprunte, et la commande rend `0Ch`. Le carnet confirme le sens du code : pour la commande
voisine `45h`, il documente « erreur a = `009h` nom déjà pris, **`00Ch` mémoire insuffisante** ».

**Ce que la mesure établit :**

1. ✅ **`47h` condense avant `48h` est obligatoire**, et pas seulement prudent. La place libre
   n'est jamais « après la chaîne » sur une machine en ordre de marche : `DATA.BAS` la détient
   toute (`Referentiel … 03` §7bis). Notre installateur compacte déjà d'abord — il avait raison.
2. ✅ **Un refus de `48h` ne casse rien** : chaîne, `TXT`/`DAT` et drapeau identiques. La commande
   vérifie avant d'agir.
3. ⚠️ **Le carnet prête à `48h` un paramètre que la ROM n'utilise pas.** Il annonce « `Y` = taille » ;
   or `Y` est écrasé par `SUB_F0244` dès la deuxième instruction, la chaîne n'est décalée que de
   **`22h` octets**, et le gabarit écrit donne une taille de `22h` et un attribut **`20h`**.
   📖 Lecture : `48h` crée un bloc **vide** en tête, et la taille se donnerait ensuite par **`42h`
   `block_resize`** (`(ch)` = lecteur, `a` = 0/1, `X` = nom, `Y` = taille ; erreurs `000h` carte
   protégée, `005h` bloc protégé, `00Ch` mémoire insuffisante, et `Y` = taille possible).

**Conséquence pour l'installateur** : la voie ROM complète serait `47h` → `48h` → `42h`, plus la
pose de l'attribut `25h`. Elle remplacerait notre montée des blocs à la main, pas le reste. Tant
qu'elle n'est pas mesurée, **l'installateur ne bouge pas**.

---

## T482 — la voie ROM complète : `47h` → `48h` → `42h`

⛔ **Une v2 ne peut pas se contenter d'ajouter `47h`.** Le compactage déplace `TEXT.BAS` et
`DATA.BAS`, et **la ROM ne recale rien** : `0F0A19h` appelle `42h` deux fois par bloc puis
`SUB_F029D`, qui ne met à jour que `[0BFC1Bh]` — il n'efface même pas le bit du lecteur de
`[(iocsw)+3Ah]`, contrairement à `48h`. Après un compactage nu, `(txtbas)` et `(datbas)` désignent
l'ancienne place des blocs du BASIC. D'où la règle de PLINKC, reprise ici : **`linkbas` derrière
chaque commande qui déplace, sur tous les chemins, erreurs comprises**. C'est pour cela que la
séquence ne peut pas s'essayer depuis le BASIC, qui reprendrait la main entre deux commandes avec
des pointeurs faux.

`T482.ASM` (279 octets) enchaîne donc, dans un seul `CALL` :

| Étape | Commande | Ce qu'on en retient |
|---|---|---|
| 1 | `47h` `condense` | rend la place à la fin de la chaîne — puis `linkbas` |
| 2 | `48h` `block_create_top`, nom `T48     SYS`, `Y` = 2839 | `Y` rendu = adresse du bloc créé — puis `linkbas` |
| 3 | `42h` `block_resize`, `a` = 0 **puis** `a` = 1 si refus | lequel des deux « pointeurs de zone libre » fait grandir un bloc n'est pas établi : la sonde essaie les deux et dit lequel a marché — puis `linkbas` |
| 4 | `41h` `search_phys` | relit l'adresse du bloc, pour voir s'il a bougé entre-temps |

`linkbas` est repris **mot pour mot** de `bd_linkbas` (`src/BASEXTDR.ASM`) : les noms des deux
blocs du BASIC sont rangés en `[baswrk]+72h`, chacun précédé de son numéro de lecteur, et `41h`
rend l'adresse tout en avançant `X` sur l'entrée suivante. Comme PLINKC, il finit par `reset` si
les blocs du BASIC sont introuvables — la mémoire serait alors incohérente.

Zone de résultat en `0BFBE0h` (étape atteinte, code d'erreur, adresse rendue par `48h`, adresse
relue par `41h`, `Y` rendu par `42h`) et **signature `T42`** en `0BFBEBh`, que `T482.BAS` efface
après lecture.

### Protocole

⚠️ **Sur un `S1:` dont on peut se passer**, et de préférence **sans pilote installé** : la
séquence compacte, crée un bloc de 2839 octets et déplace tout le reste.

1. `POKE &BFE03,&1A,&FD,&B,0,&C,0 : CALL &FFFD8` — réserver 3072 octets ;
2. `LOAD M "X:T482.OBJ"`, puis charger `T482.BAS` ;
3. **`RUN`** : relevé **avant** (chaîne, `TXT`/`DAT`, `+3A`) ;
4. ⚠️ **en mode direct**, `CALL &BF000` — jamais depuis le programme, qui vit dans `TEXT.BAS` et
   que le compactage déplace sous ses pieds ;
5. **`RUN`** : relevé **après**, plus l'étape atteinte et les adresses ;
6. nettoyer : `SET "S1:T48.SYS"," "` puis `KILL "S1:T48.SYS"` — **tapés en mode direct**, ce sont
   des commandes que le BASIC refuse dans un programme (mesuré le 2026-09-25).

### Ce que chaque issue apprendrait

| Étape atteinte | Lecture |
|---|---|
| **6**, bloc en tête et `TXT`/`DAT` justes | la voie ROM fait le travail : `47h` → `48h` → `42h` remplacerait la montée des blocs **et** l'insertion de l'installateur, qui n'aurait plus qu'à copier son image et poser l'attribut `25h` |
| **6**, mais bloc **ailleurs** qu'en tête | `48h` ne place pas là où son nom le dit : le gain se réduit à éviter le décalage manuel |
| 3 ou 5 avec un refus `0Ch`, `Y` = taille possible | `42h` ne sait pas agrandir autant d'un coup : la taille est plafonnée par la zone libre du bloc, à lire dans `Y` |
| **2** (`48h` refuse après `47h`) | le compactage ne rend pas la place là où `48h` la cherche — la voie ROM serait alors sans issue, et notre insertion manuelle définitivement justifiée |
| **1** (`47h` refuse) | à lire dans le code d'erreur ; `47h` est pourtant la première chose que fait notre installateur, qui n'a jamais échoué |

⚠️ **`TXT`/`DAT` justes après coup ne prouvent pas que la ROM les recale** : c'est `linkbas`, dans
la sonde, qui les repose. Ce que la mesure dira, c'est si la séquence **peut** se faire avec un
`linkbas` derrière — pas si elle s'en passerait.

### ⛔ Ce que la première version de la sonde a raté

`T48.BAS` tenait « zone de résultat à zéro » pour « sonde pas encore appelée ». La zone langage
machine n'est pas remise à zéro : le relevé **avant** appel a donc affiché `BLOC CREE EN 9F9F00`,
de la mémoire quelconque lue comme un résultat. La sonde écrit désormais une **signature `T48`**
en `0BFBF5h`, que le BASIC efface après l'avoir lue : ce qui s'affiche vient du dernier appel, et
de lui seul.

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
