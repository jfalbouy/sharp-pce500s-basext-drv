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

### ✅ Résultat — PC-E500S réel, J.-F. Albouy, 2026-09-25

**La séquence entière passe.** Les quatorze octets de la zone de résultat, relus en mode direct :

```
6 0 18 0 8 18 0 8 17 B 0 0 0 0
```

| Octet | Valeur | Sens |
|---|---|---|
| étape | **6** | la séquence est allée **jusqu'au bout** |
| erreur | **0** | aucune commande n'a refusé |
| `48h` | **`080018h`** | le bloc a été créé **en tête de chaîne**, à l'ancienne adresse de `DATA.BAS` |
| `41h` | **`080018h`** | après le redimensionnement, le bloc est **toujours là** : il n'a pas été déplacé |
| `42h` | **`000B17h` = 2839** | la taille demandée, accordée d'un coup |

Et la chaîne, relevée par `T482.BAS` :

| Avant | Après |
|---|---|
| `80018` DATA 251962 · `BD852` TEXT 1696 · `BDEF2` FUNCKEY · `BDF5A` AER | **`80018` T48 SYS `20` 2873** · `80B51` DATA 420 · `80CF5` TEXT 1696 · `81395` FUNCKEY · … · `BDF5A` AER · `BDFC0` ENG $$$ |

**Ce que cela établit :**

1. ✅ **`48h` crée bien EN TÊTE**, et les blocs suivants montent — c'est la ROM qui fait le
   décalage que notre installateur fait à la main.
2. ✅ **`42h` agrandit le bloc sur place**, sans le déplacer, et accorde 2839 octets d'un coup ;
   le bloc final fait **2873 = 2839 + 22h**, en-tête compris.
3. ✅ **Le premier « pointeur de zone libre » (`a` = 0) suffit** : `res_err` vaut 0, or la sonde y
   écrit le code du refus de `a` = 0 avant d'essayer `a` = 1. ⚠️ Réserve : le code `000h` existe
   (« carte protégée »), donc la preuve n'est pas absolue.
4. ✅ **L'attribut du bloc créé est `20h`**, celui du gabarit de la ROM (`DB_F041C`) : un pilote
   devra poser son `25h` lui-même.
5. ✅ **`47h` rend vraiment la place** : `DATA.BAS` retombe de 251 962 à 420 octets, sa taille réelle.

⚠️ **Ce que la mesure NE tranche pas** : lequel, de `48h` ou de `42h`, a donné sa taille au bloc.
Mon relevé de la ROM disait `48h` crée un bloc vide de `22h` octets (`Y` écrasé par `SUB_F0244`),
et le carnet dit « `Y` = taille ». Ici les deux commandes se sont enchaînées, donc les deux lectures
restent debout. **Une sonde `47h` + `48h` seuls, qui lirait la taille du bloc créé, trancherait en
une minute.**

### ⚠️ Deux anomalies, non expliquées

1. **`(txtbas)` est resté périmé.** Après la séquence : `TXT BD852` alors que `TEXT.BAS` est en
   `80CF5` — tandis que `DAT 80B51` est juste. `linkbas` écrit pourtant les deux à la suite, et il
   a forcément tourné (l'étape 6 est après lui). Une recherche qui échouerait partirait sur
   `lb_perdu` → `reset`, ce qui aurait empêché l'étape 6 : ce n'est donc pas cela. **À comprendre
   avant de toucher à l'installateur**, puisque c'est exactement le geste qu'il fait.
2. **La signature n'est jamais arrivée** en `0BFBEBh` (relue à zéro), alors que les cinq valeurs
   qui la précèdent y sont. `T482.BAS` a donc répondu « SONDE PAS ENCORE APPELEE » après un appel
   réussi. Défaut du banc d'essai, pas de la machine — et la parade est plus simple que la
   signature : **l'octet d'étape suffit** (`0` = pas appelée, `1`-`6` = appelée), et c'est lui que
   la prochaine version lira, en le remettant à zéro après lecture.

---

## T483 — `47h` puis `48h` SEULS : quelle taille a le bloc ?

C'est la sonde d'une minute qui tranche le point laissé ouvert par T482. Elle s'arrête après `48h`
et **lit la taille dans l'en-tête du bloc** (champ `+11h`, celui que lit `BLOCS.BAS`) :

| Taille lue | Conclusion |
|---|---|
| **`22h` = 34** | `48h` crée un bloc **vide** : c'est la lecture de la ROM qui a raison, et le carnet est à corriger (`Y` y est donné comme la taille) |
| **`0B39h` = 2873** | `48h` prend bien `Y` : c'est **ma lecture de la ROM** qui est fausse, et il faudra dire où |
| autre | à écrire telle quelle, et à comprendre |

Même protocole que T482 (réserver, `LOAD M "X:T483.OBJ"`, `RUN`, `CALL &BF000` **en mode direct**,
`RUN`), même nettoyage `SET`/`KILL` **tapé**. La sonde compacte, donc elle appelle `linkbas`
derrière chaque commande qui déplace, erreurs comprises.

### ✅ Résultat — PC-E500S réel, J.-F. Albouy, 2026-09-26

**`48h` crée un bloc VIDE.** `FILES "S1:"` après l'appel :

```
T48     .SYS        0    S1:
DATA    .BAS      367
TEXT    .BAS     1300
FUNCKEY .          70
```

`FILES` affiche la taille du bloc **moins `22h`** (`03` §7bis) : **0 affiché = bloc de 34 octets**,
l'en-tête et rien d'autre. La taille demandée — 2839 octets dans `Y` — **a été ignorée**.

✅ **Recoupé par la sonde elle-même** : `PEEK` de sa zone de résultat donne `5 0` (séquence
complète, aucune erreur) et **`000022`** pour la taille qu'elle a lue dans l'en-tête à `+11h`.
Deux chemins indépendants, la même valeur.

**Ce que cela tranche :**

1. ✅ **La lecture de la ROM avait raison, et le carnet est à corriger.** `Data/FCSFunctions.json`
   décrit `48h` comme « `(ch)` = slot, `X` = nom, **`Y` = taille** ; retour `Y` = adresse du bloc
   créé ». `Y` n'est pas une taille : il est **écrasé** dès la deuxième instruction du traitement
   (`call SUB_F0244`, `0F0351h`), et le gabarit copié donne au bloc une taille de `22h`.
2. ✅ **La séquence `48h` → `42h` n'est donc pas un confort, c'est une obligation** : la ROM crée
   le bloc vide, puis le dimensionne. C'est bien ce que faisait T482, et c'est ce qui explique son
   bloc de 2873 octets — **c'est `42h` qui l'a donné**, pas `48h`.

**Et un effet de bord qu'il fallait voir** : la sonde s'est arrêtée sur **`Out of memory in 80`**,
c'est-à-dire à la création de sa quatrième variable. Après le compactage, `DATA.BAS` est retombée
de **253 958 à 367 octets** — sa taille réelle. ⚠️ **Le compactage retire donc au BASIC sa réserve
de variables**, et un programme qui appelle `47h` peut mourir juste après, non pas d'un défaut de
la commande mais de la place qu'elle a reprise. L'installateur, lui, ne fait que passer : il
compacte, insère, et rend la main une fois le bloc en place.

## T484 — la trace de `linkbas` : où `(txtbas)` décroche-t-il ?

T482 a laissé une anomalie que rien n'explique : `(datbas)` juste, `(txtbas)` périmé. C'est le
geste même dont dépend un installateur — tant qu'on ne sait pas pourquoi, on ne touche pas au sien.

Cette sonde **refait la séquence de T482 en écrivant ce qu'elle voit**. Son `linkbas` est celui du
pilote, augmenté de la trace **et de rien d'autre** : mêmes instructions, mêmes registres, mêmes
chemins d'erreur, sans quoi la mesure ne vaudrait pas pour lui.

Seize valeurs de 3 octets en `0BFB80h`, dans l'ordre :

| # | Contenu |
|---|---|
| 1-2 | `(txtbas)`, `(datbas)` **à l'entrée**, avant toute commande |
| 3-6 | `linkbas` n° 1 (après `47h`) : ce que rend la **1ʳᵉ** recherche `41h`, ce que rend la **2ᵉ**, puis `(txtbas)` et `(datbas)` une fois écrits |
| 7-10 | `linkbas` n° 2 (après `48h`), mêmes quatre valeurs |
| 11-14 | `linkbas` n° 3 (après `42h`), mêmes quatre valeurs |
| 15-16 | `(txtbas)`, `(datbas)` **à la sortie** |

Elles distinguent les trois causes que T482 ne savait pas départager : une **recherche** qui rend
une adresse fausse, une **écriture** qui n'a pas lieu, ou quelque chose qui **écrase** `(txtbas)`
après coup. `T484.BAS` les affiche étiquetées, puis rappelle l'état courant et la chaîne.

### ⛔ Un marqueur doit dire QUI a écrit, pas seulement qu'on a écrit

Trois fois de suite, le même piège a coûté une mesure — et chaque fois sous un autre déguisement :

| Version | Ce qui a été cru | Ce qui était vrai |
|---|---|---|
| T48 v1 | « zone de résultat à zéro = sonde pas appelée » | la zone langage machine **n'est pas remise à zéro** : `BLOC CREE EN 9F9F00`, de la mémoire quelconque lue comme un résultat |
| T482 | « une signature écrite en dernier prouve l'appel » | la signature **n'est jamais arrivée**, alors que les cinq valeurs qui la précédaient y étaient : la sonde a été déclarée non appelée après un succès complet |
| T484 | « l'octet d'étape suffit : `0` = pas appelée » | l'étape **`5` restait de T483**, qui partage la même zone et n'avait pas pu l'effacer (il était mort sur `Out of memory`). Lancé **avant** le `LOAD M`, `T484.BAS` a affiché `ETAPE 5 ERR 0` et des adresses de fantaisie — `544F52`, `495349` : du texte, pas des adresses |

La leçon, à la troisième : **une zone de résultat persistante n'est pas un canal**. Il y faut une
marque qui dise **qui** a écrit. Chaque sonde **signe** donc désormais ses octets, en `0BFBDFh` et
dès sa première instruction — `083h` pour T483, `084h` pour T484 —, et son programme BASIC refuse
les octets d'une autre (« T484 PAS ENCORE APPELEE (ID 83) »), puis efface la signature après
lecture. Une sonde interrompue en route reste reconnaissable : c'est tout l'intérêt d'écrire
l'identifiant **avant** le travail, et non après.

### Le relevé passe par un fichier, pas par des photos d'écran

Un écran de quatre lignes et vingt-cinq valeurs ne font pas bon ménage : on photographie ce qu'on
peut, et ce qu'on rate manque à l'analyse. `T484.BAS` écrit donc **tout** dans
**`F:T484RES.BAS`** en même temps qu'à l'écran, par l'idiome éprouvé de `BASEXT/essais/MODDIAG.BAS` :

```basic
 80 CLS :OPEN "F:T484RES.BAS" FOR OUTPUT AS #1
910 PRINT L$:PRINT #1, L$:RETURN
```

Le fichier se récupère ensuite de l'émulateur et se lit d'un bloc. Il porte les seize valeurs de
la trace **étiquetées** (`L1-CHERCHE1`, `L1-TXT`…), l'état courant de `(txtbas)`/`(datbas)`, puis
la chaîne des blocs.

Les étiquettes sont écrites **en toutes lettres, une ligne par valeur** : c'est plus lisible dans
le fichier, et cela évite d'avoir à découper une chaîne de libellés.

⛔ **Ma première rédaction disait « sans `MID$` ni `STR$`, aucun des deux n'apparaît dans le
corpus, donc rien ne garantit leur syntaxe ».** C'est faux, et c'est le piège que la méthode du
projet nomme : **une absence n'est une information que si la recherche sait trouver une
présence.** Le témoin positif existait à deux pas — la table des 168 mots-clés de la ROM :
`MID$` = `0EAh`, `LEFT$` = `0EBh`, `RIGHT$` = `0ECh`, `STR$` = `0F1h`, `VAL` = `0D1h`
(`Renum Basic Sharp/Documentation/Codes_BASIC_PC-E500S_corrige.csv`). Signalé par
J.-F. Albouy le 2026-09-26. Les quelques programmes d'essai du corpus ne s'en servaient pas,
voilà tout.

**Pour revoir le relevé sans rappeler la sonde** — le programme efface la signature après lecture,
mais la trace, elle, reste :

```basic
POKE &BFBDF,&84
RUN
```

### ✅ Résultat — PC-E500S réel, J.-F. Albouy, 2026-09-26

Relevé complet, écrit par le programme dans `F:T484RES.BAS` :

```
ETAPE 6 ERR 0
E-TXT BDF12        E-DAT 80018          <- a l'entree
L1-CHERCHE1 8019C  L1-CHERCHE2 80018    <- apres 47h condense
L1-TXT 8019C       L1-DAT 80018
L2-CHERCHE1 801BE  L2-CHERCHE2 8003A    <- apres 48h
L2-TXT 801BE       L2-DAT 8003A
L3-CHERCHE1 80CD5  L3-CHERCHE2 80B51    <- apres 42h
L3-TXT 80CD5       L3-DAT 80B51
S-TXT 80CD5        S-DAT 80B51          <- a la sortie de la sonde
MAINTENANT-TXT BDF12   MAINTENANT-DAT 80B51
```

**Les écarts disent tout :**

| Entre | Écart | Ce que cela prouve |
|---|---|---|
| L1 → L2 (`48h`) | **+34** sur les deux | `48h` insère **exactement son en-tête** (`22h`) en tête et pousse le reste |
| L2 → L3 (`42h`) | **+2839** sur les deux | `42h` **agrandit bien** le bloc de la taille demandée, et décale tout ce qui suit |

1. ✅ **`linkbas` est innocenté, et proprement.** Aux trois passages, les deux recherches `41h`
   rendent l'adresse juste et les deux écritures ont lieu : `L1`, `L2`, `L3` suivent le mouvement
   au bon moment, et à la sortie de la sonde `S-TXT`/`S-DAT` sont exacts.
2. ⛔ **L'anomalie est APRÈS le retour du `CALL`** : `MAINTENANT-TXT` vaut `BDF12`, c'est-à-dire
   **la valeur d'entrée**, celle d'avant le compactage — tandis que `MAINTENANT-DAT` garde la
   nouvelle. Quelque chose, entre le `retf` de la sonde et la lecture par le programme BASIC,
   **remet `(txtbas)` à son ancienne valeur**. Ce n'est ni notre code, ni `linkbas`.
   📖 La ROM n'écrit `(txtbas)` qu'en trois endroits — `0F9984h`, `0F99B1h`, `0F9D28h`, tous
   `mv (txtbas),y`. Lequel s'exécute, et d'où il tire une adresse périmée, reste à lire.
3. ⚠️ **Conséquence pour l'installateur, à établir avant d'y toucher** : l'écriture de `(txtbas)`
   par `bd_linkbas` peut donc être **défaite** au retour du `CALL`. Or `PLINKC` et `BASEXT-DRV`
   fonctionnent sur matériel réel depuis longtemps — la ROM retrouve donc `TEXT.BAS` autrement
   quand elle en a besoin. Tant qu'on ne sait pas comment, on ne change rien.

### ⛔ Et une erreur de lecture, la mienne

J'ai écrit que `42h` n'avait « rien fait », parce que `FILES` affichait `T48 .SYS 0` alors que T482
avait donné 2873. **Les deux relevés sont justes et disent deux choses différentes** :

| Ce qu'on lit | Où | Valeur ici |
|---|---|---|
| taille du **bloc** | champ `+11h` de l'en-tête, ce que liste `BLOCS.BAS` | **2873** = 34 + 2839 |
| taille du **fichier** | ce qu'affiche `FILES` (`[+16h]` − `22h`) | **0** |

`48h` crée un bloc **et** un fichier vides ; `42h` ajoute de la **zone libre au bloc** — c'est le
sens de son paramètre « numéro de pointeur de zone libre » — sans rien écrire dans le fichier.
D'où un bloc de 2873 octets contenant un fichier de 0. C'est exactement la situation de
`DATA.BAS`, que le référentiel avait déjà relevée (`03` §7bis) et que je n'ai pas su appliquer.

**Pour un pilote, c'est le bloc qui compte** : la place est là. Reste à savoir qui doit renseigner
`+16h` — l'installateur lui-même, vraisemblablement, comme il pose déjà l'attribut `25h`.

### Et ensuite

La question qui vaut le détour, et qu'on ne posera qu'une fois ces deux-là répondues :
**l'installateur peut-il passer de « compacter, décaler, insérer, recaler » à « `47h`, `48h`,
`42h`, recaler » ?** T482 dit que la voie existe ; elle ne dit pas encore qu'elle est sûre.

### Construire

```powershell
cd C:\Claude\BASEXT-DRV\sondes
C:\Claude\xasm2026-4\bin\xasm2026-4.exe T48.ASM -OT48.OBJ -L -S -B -K
C:\Claude\xasm2026-4\bin\xasm2026-4.exe T482.ASM -OT482.OBJ -L -S -B -K
C:\Claude\xasm2026-4\bin\xasm2026-4.exe T483.ASM -OT483.OBJ -L -S -B -K
C:\Claude\xasm2026-4\bin\xasm2026-4.exe T484.ASM -OT484.OBJ -L -S -B -K
```

`pce500.inc` est une **copie** de `../src/pce500.inc`, elle-même générée : ne pas l'éditer. Le `.uu`
a été renommé en `.UU` en deux temps, comme le veut la règle de casse de Windows
(`05-format-fichiers-et-xasm.md` §4).
