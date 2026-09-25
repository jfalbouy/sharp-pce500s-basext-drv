# BASEXT-DRV — conception

*Rédigé le 2026-09-16 — mis à jour le 2026-09-25*

**Rendre BASEXT résident** : ses mots-clés vivent dans un **bloc de pilote** de `S1:` au lieu
d'occuper la zone langage machine (`0BF000h`–`0BFC00h`), qui redevient libre pour d'autres
programmes.

> **Légende**, celle de `BASEXT/MODE-EMPLOI.md` : ✅ confirmé (mesuré sur machine, ou par l'outil
> sur les objets) · 📖 lu dans la ROM ou dans une documentation, pas éprouvé · ⚠️ piège ou point
> incertain · ⛔ erreur corrigée, gardée écrite avec ce qui l'a démentie.
>
> **Référents.** La création d'instructions BASIC relève de `C:\Claude\BASEXT\MODE-EMPLOI.md`.
> Pour les pilotes résidents, le référent est `C:\Claude\xasm2026-4\Exemples\DRIVER_TEMPLATE`. Ce
> document ne recopie ni l'un ni l'autre : il dit ce que leur **assemblage** pose de neuf.

---

## 1. Décisions prises (2026-09-16)

| # | Question | Décision |
|---|---|---|
| D1 | Nom | dossier `C:\Claude\BASEXT-DRV`, futur dépôt `sharp-pce500s-basext-drv` |
| D2 | D'où vient le code des mots-clés | **inclus depuis BASEXT** : une seule source, BASEXT reste le référent |
| D3 | Table de relocation | **générée** par double assemblage, puis **vérifiée** à une troisième origine (`outils/reloc.py`) ; émise au **format Kon** et relue par la boucle de PLINKC (§3.3, §3.4) |

---

## 2. Ce qu'on assemble

### 2.1 BASEXT aujourd'hui

✅ `BASEXT.ASM` (commit `9c8f3e2`) : 2709 octets en `0BF000h`–`0BFA94h`, 14 mots-clés,
`BEXTTEST.BAS` à 14/14 sur machine. Installé par `CALL &BF000` (étiquette `start`), qui :

1. débranche un éventuel filtre d'écriture resté sur le handle 0 (`call xf_off`) ;
2. sauve les crochets `[(basptr)+090h]` et `[(basptr)+093h]` dans `old_kw`/`old_disp`, **seulement**
   s'ils portent encore la sentinelle `0FFFFFh` ;
3. y écrit `kw_table` et `disp_table`.

Ses variables (`sv_bp0`, `xf_buf` de 240 octets, `old_kw`…) sont **dans** le module : elles
suivront le bloc, sans rien changer à leur usage.

### 2.2 Le DRIVER_TEMPLATE

✅ Validé sur émulateur (`README.md` du gabarit). Installateur transitoire assemblé en `0BE000h`,
lancé par `CALL &BE000` : compactage de `S1:` (IOCS device 6, commande `47h`), recherche d'un
doublon et de la **fin** de la chaîne des blocs, contrôle mémoire, chaînage en tête de `d_link`
(`0BFCA2h`), relocation **avant** la copie, copie en fin de chaîne. Désinstallation par
`CALL &BE000 "-u"`, puis `SET`/`KILL` tapés par l'utilisateur.

### 2.3 Le bloc résident visé

```
┌─ en-tete de bloc memoire   0FBh + 'BASEXT  SYS' + 25h + tailles        (gabarit)
├─ en-tete IOCS              lien + n° device + entree + 'BEXT:',0        (gabarit)
├─ entree IOCS               stub « commande non geree » pour commencer   (gabarit)
├─ corps BASEXT              start, mots-cles, filtre, tables, variables  (INCLUS depuis BASEXT)
└─ fin du bloc
   table de relocation       rel_table, HORS du bloc, dans l'installateur (GENEREE : reloc.inc)
```

Après la copie, l'installateur appelle **l'entrée `start` relogée** : c'est le code de BASEXT,
éprouvé, qui pose les crochets, et il sert aussi à les reposer plus tard (§4.2).

---

## 3. La relocation, mesurée

### 3.1 Combien de champs

✅ Mesure du 2026-09-16 : `BASEXT.ASM` assemblé en `0BF000h` (objet **identique à l'octet** à
`BASEXT.OBJ`) puis en `0A1234h`. 407 octets diffèrent, **tous** expliqués par :

| Largeur | Nombre | Ce que c'est |
|---|---|---|
| 3 octets | **119** | `mv y,kw_table`, les `[!sv_bp0]`…, `mv y,xf_entry`, `mv [!xf_call+1],y`, et les 14 entrées de `disp_table` dont le quartet haut porte le **drapeau** `4` ou `8` |
| 2 octets | **25** | `call`/`jp` proches : `call rd1str`, `jp ret_str`, `call xc_skip`, `call xf_pre`, `call xf_call`… |

Poser 144 paires `reldp`/`relref` à la main, au milieu des instructions, aurait été le point
faible du projet : d'où la décision D3.

### 3.2 L'outil — `outils/reloc.py`

1. assemble une **copie** de la source à son origine A, puis à B = `0A1234h` ;
2. dans la zone `[debut, fin)`, range chaque octet différent dans un champ de 3 octets (écart de
   la valeur sur 20 bits = B − A, **quartet haut identique**) ou de 2 octets (écart sur 16 bits) ;
3. **refuse** tout octet différent qui n'entre dans aucun champ ;
4. **vérifie** : applique la table à l'objet A avec l'écart C − A (C = `093579h`) et exige
   l'égalité à l'octet avec l'objet C ; de même pour B ;
5. écrit `rel_table`, par défaut **au format Kon** (§3.4), sinon en deux listes de `dw`
   (`--format listes`) ; l'encodage Kon est relu et comparé avant écriture.

Les écarts sont choisis pour que **chaque octet** d'un champ change quelle que soit la retenue
(octet bas non nul, octet médian ni `00h` ni `0FFh`, quartet haut ni `0` ni `F`) ; l'outil
refuse une origine qui ne le garantit pas.

✅ Éprouvé sur `BASEXT.ASM` le 2026-09-16 :

| Témoin | Attendu | Obtenu |
|---|---|---|
| positif : `BASEXT.ASM` tel quel | 119 + 25 champs, vérifié en B et en C | ✅ identique à la mesure du §3.1 |
| négatif : un `db kw_table/256` ajouté en fin | refus, octet orphelin | ✅ `0BFA95h` signalé, code de sortie 1 |
| négatif : table privée d'un champ | vérification en échec | ✅ 3 octets faux |
| `reloc.inc` inclus dans une source | assemblable | ✅ 292 octets en deux listes ; **147 octets** au format Kon, relus : 144 champs |

⚠️ **Une source dont un `assert` dépend de l'adresse absolue** (`assert kw_table < 0BFC00h`)
échouera aux origines B et C. Écrire les assertions en **différences** d'étiquettes.

⚠️ **La table doit suivre le bloc**, jamais le précéder : sa taille change quand la source
change, et elle ne doit pas décaler le bloc entre deux passes.

### 3.3 La relocation dans l'installateur

Pour chaque champ de 3 octets : `v ← v + (dest − block_top)`, **quartet haut conservé** ; pour
un champ de 2 octets, la même chose sur 16 bits. C'est ce que `reloc.py` applique pour vérifier
(`appliquer`) : ce qui passe la vérification sur PC passera sur la machine, **si** la boucle
assembleur fait la même chose. ⚠️ À vérifier sur l'objet par une relecture après installation
(§6, étape 3).

⚠️ **La boucle du gabarit ne convient pas telle quelle** : elle passe par `X`
(`mv x,[y]` / `sub x,y` / `add x,y` / `mv [y],x`). Or `X` et `Y` n'ont que **20 bits utiles**
(skill `pc-e500s`, `architecture.md` : « 3 octets stockés, 20 bits utiles »), et rien n'établit
que le quartet haut survive à l'aller-retour par le registre. Si ce n'est pas le cas, les 14
entrées de `disp_table` perdraient leur drapeau `4`/`8` : **erreur 10 sur chaque mot-clé**, le
reste du bloc paraissant sain.

✅ **La boucle de PLINKC 1.62 évite le registre** (`Exemples/PLINKC/A62/plinkc.a62.asm`,
« Relocaliser le traitement ») : elle recopie le champ en RAM interne et y fait la soustraction
**octet par octet**, sur la largeur lue dans la table (`IL` = 2 ou 3) :

```asm
        mvp     (mdf),[y]               ; les 3 octets du champ, en RAM interne
        sbcl    (mdf),(offset)          ; soustraction sur I octets : offset = btop - dest
        mvp     [y],(mdf)               ; recrits (sur 2 octets, le 3e revient intact)
```

Le quartet haut ne passe par aucun registre ; il ne change que si une retenue franchit le bit 20,
ce qu'une adresse de 20 bits relogée dans le Mo n'entraîne pas. ⚠️ `offset` est calculé dans `U`
(`mv u,btop` / `sub u,x`), donc sur 20 bits : il est juste tant que **`dest` < `btop`**, ce qui
est le cas quand l'installateur est chargé au-dessus des blocs de `S1:`. À contrôler par
l'installateur plutôt qu'à supposer. **On reprend cette boucle**, format de table compris
(§3.4). PLINKC s'installe sur PC-E500S réel (`Exemples/PLINKC/README.md`, `PLINKC-BF000.uu`).

### 3.4 Le préfixe `rel` de XASM — pourquoi on ne s'en sert pas (2026-09-16)

📖 Depuis le portage de PLINKC, XASM2026-4 reproduit le préprocesseur A62 : `rel <instruction>`
enregistre le champ d'adresse, et une **table au format Kon** est **ajoutée après le code**
(`Documentation_XASM2026-4_PC-E500S.md` §6.1.2). La source A62 de PLINKC s'assemble ainsi en un
objet identique à l'octet à `PLINKC.OBJ` (`Exemples/PLINKC/A62/`).

Le format Kon : un octet par champ, delta depuis le champ précédent (le premier depuis le début),
bit `080h` = 3 octets, `07Eh` = delta long sur 2 octets, `0FFh` = fin. `reloc.py` l'émet, avec
les offsets comptés depuis le **début du bloc** (PLINKC les compte depuis l'`org` de son fichier,
d'où son `sub y,btop-entry`).

⛔ **Mais `rel` se trompe de champ sur deux familles d'instructions.** `NativeAssembler.cs`
(l. 720-728) prend le champ dans les **derniers** octets de l'instruction, sur 2 octets pour
`CALL`/`JP` et sur 3 pour tout le reste. Mesuré :

| Essai | Résultat |
|---|---|
| `BASEXT.ASM` recopié avec `rel` devant les 130 instructions et les 14 `dp` de `disp_table` (réécrits en `dp routine+0400000h`, objet de code **identique** à `BASEXT.OBJ`) | table de 147 octets, 144 entrées, dont **12 décalées d'un octet** : tous les `mv [!sv_bp0],(bp_ram)`, `mv [!sv_bp1],(bp_ram)`, `mvp [!sv_a],(BP+n)` — l'adresse est suivie de l'opérande interne (`30 D8 B9 F6 0B EC`). Objet relogé par cette table : **48 octets faux** |
| `rel jpnz cible` (`15 12 F0`) | enregistré **3 octets en +0** au lieu de 2 octets en +1 : l'opcode serait écrasé |
| `rel jp cible`, `rel mv (0ECh),[!v]` | justes |

PLINKC ne rencontre aucun des deux cas, ce qui explique que son objet sorte juste. Pour BASEXT,
`rel` aurait en outre exigé 144 marques dans la source du référent et ajouté la table à
`BASEXT.OBJ`. **La décision D3 tient** : la table vient de la mesure, et `reloc.py` vérifie tout
ce qu'elle produit.

✅ **Signalé** le 2026-09-16, pour correction dans `xasm2026-4` :
`xasm2026-4/RAPPORT-BUG-rel-champ-adresse.md`. L'inventaire complet (27 formes à adresse absolue,
tirées de `OpcodeTable.json`) y montre **14 formes fausses** : les quatre sauts conditionnels
proches, `cmp/test/xor/and/or [lmn],n`, `mv/mvw/mvp/mvl [lmn],(n)` et `dw`. S'y ajoute
`rel` devant une instruction sans adresse, accepté, dont l'écart négatif s'encode `0FFh`, le
terminateur. L'inventaire a révélé un défaut indépendant de `rel` :
`xasm2026-4/RAPPORT-BUG-octet-pre.md` — `mvl (n),[lmn]` et `mvl [lmn],(n)` sous PRE sortent avec
l'octet PRE **après** l'opcode ou l'adresse (moteur C : en tête). BASEXT n'emploie pas `mvl`.

✅ **Corrigé dans xasm2026-4 le 2026-09-17** (commit `9e76984`, binaire `bin/` régénéré), et
**revérifié ici indépendamment**, avec les sources d'essai du 2026-09-16 et le binaire livré :

| Essai | Avant | Après |
|---|---|---|
| octet PRE : 158 lignes contre le moteur C | 27 lignes différentes (7 familles) | **0**, objets identiques à l'octet |
| `rel mv a,05H` | accepté, table commençant par `0FFh` | **refusé** : « l'instruction ne porte aucune adresse absolue » |
| `rel` sur 27 formes (`RELFORM.ASM`) | 14 entrées fausses | table **égale** aux champs mesurés ; objet relogé : 0 octet faux |
| `rel` sur les 144 sites de BASEXT | 12 entrées décalées, 48 octets faux | 144 entrées **égales** à `reloc.py` ; objet relogé : **0 octet faux** |
| `BASEXT.OBJ`, `BASEXTDR.OBJ` réassemblés | — | **identiques à l'octet** aux versions éprouvées (seule la date du `.UU` change) |

xasm2026-4 a élargi la mesure : 2520 formes sous `pre_on` et `pre_off`, neuf défauts et 289
divergences, tous corrigés (`xasm2026-4/PORTAGE.md`, 2026-09-17).

**Conséquences pour BASEXT-DRV.** La décision D3 tient : `reloc.py` mesure les champs sans poser
144 marques dans la source du référent. `rel` devient une **voie valable** pour un autre pilote,
et `reloc.py` un moyen de la vérifier. Le contournement de `mvp [y],(00BH)` dans l'installateur
est **conservé** : c'est le code éprouvé sur émulateur, et y revenir changerait l'objet.

---

## 4. Points ouverts — à trancher avant ou pendant l'écriture

> Les choix de la version 0.1 sur ces points sont au §5bis.

### 4.1 ⚠️ Les 25 champs proches imposent une seule page

Un `call`/`jp` proche garde la page du `PC`. Si le bloc chevauche une frontière de page de
64 Ko, la moitié du code appelle dans la mauvaise page. 📖 `S1:` couvre `080000h`–`0BFFFFh` sur un
PC-E500S (`SC62015Disassembler/Docs/Synthese/Fichiers-et-slot.md`) : les frontières `090000h`,
`0A0000h` et `0B0000h` sont atteignables selon la place occupée. Deux conduites :

- **refuser** l'installation si `dest` et `dest + taille − 1` ne sont pas dans la même page.
  ✅ C'est la conduite de PLINKC, qui a lui aussi des `call` proches relogés (macro `bsr`) :
  `mv ba,(dest)` / `add ba,i` (`I` = taille du code) / `jrc` vers « Over two pages. » ;
- ou **passer les 25 sites en `callf`/`jpf`** (et les `ret` correspondants en `retf`) : +25
  octets au moins, dans BASEXT lui-même. L'outil le confirmerait : 0 champ de 2 octets.

### 4.2 ⚠️ RESET : les crochets survivent-ils ?

C'est le point ouvert n° 3 de `MODE-EMPLOI.md` §12 : `0F93C3h` écrit la sentinelle dans les deux
crochets, **sans qu'on sache si c'est à chaque RESET ou au démarrage à froid**. Pour un module en
`0BF000h`, la perte se réparait par `CALL &BF000`. Pour un pilote, le bloc reste mais les crochets
peuvent partir, et l'installateur n'est plus en mémoire. Il faut donc **une voie de ré-accrochage
sans installateur**. Pistes, à lire dans la ROM avant d'en choisir une :

- 📖 la commande IOCS `40h`, « initialisation, commune à tous » (`Drivers-IOCS.md` §2) : la ROM
  l'envoie-t-elle aux pilotes chaînés au RESET ? Si oui, l'entrée IOCS du bloc rappelle `start` ;
- la même question pour `d_link` : la chaîne des devices est-elle reconstruite au RESET, et le
  bloc y est-il remis (champ « programme de contrôle » `+1Ch`) ?
- à défaut, un `CALL` à une adresse **lisible** depuis le BASIC (parcours de la chaîne des blocs).

### 4.3 ⚠️ Le bloc peut-il bouger ?

Le gabarit ajoute le bloc **en fin** de chaîne. Si un bloc placé **avant** lui est supprimé
(`KILL "S1:PLINKC.SYS"`), la ROM recompacte-t-elle en déplaçant le nôtre ? 📖
`Modele_Pilotes_Resident_PC-E500S.md` écrit que l'OS relocalise `SSFDC` par sa `relTbl` (`+1Fh`),
mais `Drivers-IOCS.md` §6 note que le sens de cette table n'est pas départagé, et rien n'est lu
dans la ROM. Même relogé par l'OS, le bloc laisserait **trois pointeurs extérieurs** périmés :
le lien dans `d_link`, les deux crochets du BASIC, et l'entrée du handle 0 si le filtre de
`XCONSOLE` est branché. **À mesurer sur émulateur** : installer, `KILL` un bloc antérieur,
relire l'adresse du bloc.

#### Le protocole, et pourquoi il tient en un seul `RUN` — `essais/KILLSOUS.BAS`

⛔ **On ne peut pas mesurer ceci en tapant quoi que ce soit après le `KILL`.** Si le bloc descend,
les crochets du BASIC désignent une table déplacée, et **la tokenisation de la première ligne
tapée ou chargée lit cette table périmée** — c'est exactement ce qui a arrêté PockEmul à la
version 0.1 (§5bis). Charger un programme de relevé *après* le `KILL` serait donc le meilleur moyen
de perdre la mesure.

D'où `essais/KILLSOUS.BAS`, qui fait tout dans **un seul `RUN`**, sans aucun mot-clé d'extension
(`PEEK`/`POKE` seulement, pour rester lisible même crochets perdus) :

1. il retrouve `BASEXT  SYS` **et** `PLINK   SYS` dans la chaîne des blocs, et refuse de continuer
   si PLINK est **au-dessus** de nous (il n'y aurait rien à mesurer) ;
2. il relève les **décalages** des deux crochets dans le bloc (`crochet − bloc`), plutôt que de les
   coder en dur : ils restent justes quelle que soit la version de BASEXT ;
3. il fait lui-même `SET` puis `KILL "S1:PLINK.SYS"` ;
4. il retrouve le bloc, dit s'il a bougé et de combien, et si les crochets ont suivi ;
5. **s'ils ne l'ont pas suivi, il les réécrit** aux nouvelles adresses (`POKE`, avec les décalages
   du point 2) et rechaîne au besoin notre en-tête en tête de `d_link` — la machine redevient donc
   saine avant qu'on retape quoi que ce soit ;
6. il affiche pour finir les crochets, `d_link`, `(txtbas)`/`(datbas)` et l'adresse de reprise
   (`bloc + 57h`) au cas où.

⚠️ Il ne rétablit **pas** le filtre d'écran de `XCONSOLE` : faire `XCONSOLE` (sans argument) avant
l'essai, ou accepter que le filtre soit à débrancher ensuite par `CALL` de la reprise.

Trois résultats possibles, et chacun est une réponse :

| Relevé | Ce qu'il établit |
|---|---|
| `BLOC IMMOBILE` | la ROM ne recompacte pas au `KILL` : la limite du §4.3 n'existe pas, et le point 5 du plan se clôt |
| `BLOC DESCENDU DE n` + `CROCHETS SUIVIS` | la ROM relogerait le bloc **et** ses pointeurs extérieurs — très improbable, à recouper avec `d_link` |
| `BLOC DESCENDU DE n` + `CROCHETS PERIMES` | la limite est **réelle et mesurée** : à écrire dans le `README` comme condition d'emploi (désinstaller avant de retirer un pilote installé sous le nôtre), et la réparation est faite par le programme lui-même |

### 4.4 ⚠️ Un BASEXT déjà installé en `0BF000h`

`start` ne sauve les crochets que s'ils portent la sentinelle. Si l'ancien module est installé
quand le pilote s'installe, `old_kw`/`old_disp` du bloc restent à **zéro**, et une
désinstallation écrirait `000000h` dans les crochets. L'installateur doit **refuser** tant que les
crochets ne sont pas la sentinelle (ou désignent le bloc lui-même : réinstallation), et le dire.

### 4.5 ⚠️ La désinstallation, dans l'ordre

`KILL` sans désinstallation laisserait les crochets et le filtre pointer dans de la mémoire
libérée : **plantage au prochain mot-clé ou au prochain `PRINT`**. L'ordre sera :

1. débrancher le filtre (`xf_off`, qui vérifie déjà que l'entrée du handle 0 est la sienne) ;
2. rendre les crochets depuis `old_kw`/`old_disp` — ⚠️ **jamais éprouvé** (`MODE-EMPLOI.md` §12,
   point 2), **seulement** s'ils désignent encore le bloc ;
3. délier le device de `d_link` (gabarit, `un_found`) ;
4. afficher `SET`/`KILL`.

### 4.6 Détails à fixer à l'écriture

- **Nom et numéro** : bloc `BASEXT  SYS`, device `BEXT:` (5 octets, la limite), numéro de device
  fixe (le gabarit met 20) ou premier libre ≥ 10 comme PLINKC (commande IOCS `01h` essayée sur
  `(cx)` croissant à partir de 10).
- **Modèle d'installation** : PLINKC **insère** son bloc en décalant les blocs suivants, puis
  recale `BTEXT$`/`BDATA$` (`linkbas`) — le modèle REGISTER. On garde **l'ajout en fin** du
  gabarit, qui ne touche pas au BASIC. De PLINKC, on reprend la boucle de relocation (§3.3), le
  contrôle de page (§4.1) et l'appel de sa propre commande d'initialisation après le chaînage
  (`mv x,dvname` / `mv il,04h` / IOCS), à examiner pour §4.2.
- **Où charger l'installateur** : `0BE000h` comme le gabarit, ou `0BF000h`, déjà réservée par la
  procédure de BASEXT. Dans les deux cas la zone doit être réservée **pendant** l'installation
  seulement ; la libérer ensuite passe par `CALL &FFFD8`, un petit reset : voir §4.2.
- **Appeler `start` relogé** : pas d'appel indirect lointain ; un `callf` dont l'opérande est
  écrit par l'installateur (l'idiome de `MEMCHECK`, `Drivers-IOCS.md` §3), ou `pushs` d'une
  adresse de retour puis saut calculé.
- **Les essais** : `BEXTTEST.BAS`, `TEST.BAS` et `BEXT.BAS` écrivent en `&BFBF0`, qui sera hors de
  toute zone réservée une fois BASEXT résident. Viser une zone **réservée** pour l'essai.

---

## 5. L'inclusion de BASEXT (décision D2) — ✅ faite le 2026-09-16

### 5.1 Ce qui a été fait

`BASEXT/src/BASEXT.ASM` **reste un seul fichier**. Trois lignes y sont gardées par un symbole :

```asm
        ifndef  basext_pilote
        include pce500.inc
        endif
        ...                             ; equivalences
        ifndef  basext_pilote
        org     0BF000H                 ; module autonome seulement
        pre_on
        endif
```

Le pilote s'écrit donc :

```asm
        include pce500.inc
        def     basext_pilote
        org     0BE000H                 ; (adresse a fixer, §4.6)
        pre_on
        ...                             ; en-tetes de bloc et IOCS
        include ..\..\BASEXT\src\BASEXT.ASM
block_bottom:
```

✅ Vérifié le 2026-09-16 :

| Contrôle | Résultat |
|---|---|
| `BASEXT.OBJ` réassemblé (`-O -L -S -B -K`) | **identique à l'octet** à `HEAD` (`9c8f3e2`) ; `.UU` différent par la seule date (`' Submitted`), laissé à sa version commitée |
| `BASEXT.lst` | seules différences : le nouveau commentaire d'en-tête, et le commentaire de la ligne `org` ; `kw_table` toujours en `0BF8E7h` |
| pilote d'essai dans un **autre dossier**, `include ..\..\BASEXT\src\BASEXT.ASM` | assemblé en `0BE000h`, 2709 octets ; `reloc.py --debut bloc --fin bloc_fin` : **119 + 25 champs, vérifiés** |
| témoin négatif : `basext_pilote: equ 1` au lieu de `def` | l'`org 0BF000H` **n'est pas** masqué (`Code: 0BE000h - 0BFA94h`) |

⛔ **`IFNDEF` teste un symbole posé par `DEF`, pas par `EQU`** (`Documentation_XASM2026-4` : « `DEF`,
`UNDEF` contrôlent les symboles conditionnels »). Le premier essai avec `equ` masquait l'include
de `pce500.inc` en apparence, mais laissait passer l'`org`.

### 5.2 ⛔ La proposition précédente, écartée par la mesure

Ce paragraphe proposait de couper `BASEXT.ASM` en une enveloppe (`org`, `pre_on`,
`include BASEXT.INC`) et un `BASEXT.INC` portant tout le code. L'objet sortait identique, mais
**le listing perdait 816 lignes sur 2429** avec `-K`, l'option de la commande d'assemblage de
BASEXT : `-K` retire d'un fichier **inclus** toute ligne qui n'émet pas d'octet
(`xasm2026-4/CLAUDE.md`). Tous les commentaires du corps disparaissaient, et les étiquettes seules
aussi, dont `kw_table:`, dont `MODE-EMPLOI.md` §3.4 fait relire l'adresse dans le `.lst`.

La conséquence demeure pour le **pilote** : son listing ne montrera le corps de BASEXT qu'**sans**
`-K`.

---

## 5bis. La version 0.1 (2026-09-16) — écrite, vérifiée sur PC, pas encore sur machine

### Disposition de l'objet

⛔ **« Installateur en `0BF000h`, bloc et table à sa suite » ne tient pas.** Le code et les tables de
BASEXT font 2440 octets et ses variables 269 : 2709 au total. Avec les en-têtes, l'installateur et
la table, on dépasse les 3072 octets entre `0BF000h` et le plafond `0BFC00h`. Or l'usage demandé est
`LOAD M` depuis `X:` ou `F:`, puis **`CALL &BF000`** (J.-F. Albouy, 2026-09-16). D'où :

```
0BE400h  block_top   l'IMAGE du bloc (2794 octets), relogee puis copiee dans S1:
0BEEEAh  ...         bourrage (ds bd_objet+0C00h-*, independant de l'origine)
0BF000h  bd_entree   l'installateur : CALL &BF000
0BF401h  rel_table   la table Kon (155 octets)
0BF49Bh              fin de l'objet (4252 octets) -- sous 0BFC00h
```

Réservation : **6144 octets**, `POKE &BFE03,&1A,&FD,&B,0,&18,0 : CALL &FFFD8`.

### Choix faits

| Point | Choix |
|---|---|
| §4.1 page | **refus** « Error: over two pages. » (`mv ba,(dest)` / `add ba,i` / carry), comme PLINKC |
| §3.3 boucle | écart `dest − block_top` calculé **sur 3 octets en RAM interne** (`sbcl`), ajouté à chaque champ par `adcl` sur `I` = 2 ou 3 octets : ni registre de 20 bits, ni contrainte `dest < btop` (celle de PLINKC, qui calcule son écart dans `U`) |
| §4.4 | refus « Error: BASIC extension in use. » si l'octet haut du crochet des noms n'est pas `0Fh` |
| double relocation | drapeau `bd_reloge` : un second `CALL` sans `LOAD M` est refusé (« LOAD M the .OBJ again ») |
| recouvrement | refus si `dest + taille > 0BE400h` (attendu impossible, vérifié plutôt que supposé) |
| §4.2 | à l'installation, affichage de **`Hooks: CALL &xxxxx`** : l'adresse relogée de `start`, qui repose les crochets **sans installateur**. Le vrai comportement au RESET reste à mesurer |
| §4.5 | `CALL &BF000 "-U"` : recherche de `BEXT:` dans `d_link`, contrôle signature + nom + **taille** du bloc, appel de **`bd_arret`** (dans le bloc : `xf_off`, puis crochets rendus s'ils désignent encore `kw_table`), déliage, `SET`/`KILL` |
| numéro de device | 20, fixe, comme le gabarit |
| `start` relogé | `callf` dont l'opérande est écrit par l'installateur (idiome de MEMCHECK) |

### ⛔ Deux défauts trouvés en l'écrivant

1. **BASEXT reconnaissait son filtre d'écran par une PLAGE d'adresses.** `xf_on` et `xf_off`
   tenaient pour « nôtre » toute entrée du handle 0 en `0BF000h`–`0BFFFFh` (octets `0Bh` et
   `≥ 0F0h`, qui ne sont pas des champs d'adresse : `reloc.py` ne pouvait pas les voir). Dans le
   pilote, `xf_off` n'aurait **jamais** débranché le filtre (plantage après `KILL`), et un second
   `XCONSOLE` l'aurait branché **sur lui-même**. Corrigé dans `BASEXT.ASM` **sous
   `ifdef basext_pilote`** : comparaison exacte à `xf_entry` (`xf_nous`). Le module autonome garde
   son test, et son objet reste identique à l'octet.
2. **xasm2026-4 assemblait `mvp [y],(00BH)` sans octet PRE** (`EA 05 0B` au lieu de
   `30 EA 05 0B`) : l'écriture de chaque champ relogé serait partie dans `(BP+0Bh)`. Trouvé en
   confrontant l'objet au moteur C, puis mesuré sur 157 formes : **sept familles** fautives,
   `xasm2026-4/RAPPORT-BUG-octet-pre.md`. Contourné par trois `mv [y+k],a`.

### Vérifié par `outils/construire.py` (2026-09-16)

| Contrôle | Résultat |
|---|---|
| mesure des champs du bloc | 124 champs de 3 octets, 28 de 2 (BASEXT : 119 + 25 ; le pilote ajoute `dp bd_iocs`, `kw_table`, `old_kw`, `old_disp`, `xf_entry` dans `xf_nous`, et trois `call` proches) |
| table relue **dans l'objet final** | 155 octets, 152 champs = la mesure |
| disposition | chargement `0BE400h`, `bd_entree` = `0BF000h`, fin `0BF49Bh` < `0BFC00h` |
| relocation simulée comme l'installateur (écart sur 24 bits, champ par champ) vers `0B2345h`, `08F000h`, `0A0010h` | bloc identique à l'assemblage à cette adresse |
| moteur C `xasm2026-1-2`, assertions neutralisées | objet **identique à l'octet** |
| désassemblage `e500dasm` de l'installateur | conforme à l'intention (contrôles, `sbcl`, boucle Kon, `adcl`) |

### ✅ Premier essai sur émulateur (J.-F. Albouy, 2026-09-16)

`LOAD M` puis `CALL &BF000` : `BASEXT-DRV 0.1 (BEXT:)` puis **`Installed. Hooks: CALL &807CD`**.
`FILES "S1:"` : **`BASEXT  .SYS P  2760  S1:`**.

Ce qui s'en déduit, par le calcul et pas encore par lecture de la mémoire :

| Grandeur | Valeur | D'où |
|---|---|---|
| `start` relogé | `0807CDh` | affiché |
| bloc (`dest`) | `080776h` | `807CDh − 57h` (`start` en `+57h`, `BASEXTDR.lst`) |
| en-tête IOCS | `080798h` | bloc + `22h` |
| `kw_table` attendu dans le crochet | `0810B2h` | bloc + `93Ch` |
| fin du bloc | `08125Fh` | bloc + `AEAh` − 1 : **une seule page** (`08`), le contrôle ne pouvait pas refuser |

✅ **`FILES` affiche 2760, pas 2794** : 2794 − 2760 = **34 = `22h`**, la taille de l'en-tête de
bloc. `FILES` compte donc le bloc **sans son en-tête**. Recoupé sur un second pilote : PLINKC 1.62
déclare `blen` = `0920h` = 2336 (`Exemples/PLINKC/A62/plinkc.a62.lst`, `dp blen` en `0BF1F0h`), et
`Fichiers-et-slot.md` relève `PLINK    .SYS P   2302` : 2336 − 2302 = **34** aussi.

### ⚠️ Deuxième essai : `BEXT:` absent de `d_link` (J.-F. Albouy, 2026-09-16)

`DRVTEST.BAS` répond **`BEXT: ABSENT DE D_LINK`** au premier `RUN` après l'installation, **avant**
le petit reset, puis encore après. Le bloc, lui, figurait dans `FILES`.

Vérifié sur PC : le parcours de `DRVTEST.BAS` est juste sur la chaîne réelle de `rom83`
(`0DF820h` → … → `SYSTM:` `0DF8A9h` → `0FFFFFh`, noms en `+8`, simulation Python).

📖 **La ROM remet `d_link` à sa table d'origine `0DF820h` en deux endroits**, lus dans `rom83` :

| Adresse | Contexte |
|---|---|
| `0F0D9Eh` (`SUB_F0D9A`, appelé en `0F121Bh`) | séquence d'amorçage : test d'écriture `5AA5h` en `0BE000h` (`0F11D1h`), `BP`, vecteurs `intv_ftimer`, puis `d_link` |
| `0F1665h` | initialisation complète : `usrwrk` ← `0BFC00h`, `s1_btm`, `swork`, pile `S`, puis `d_link` |

Dans la suite de l'amorçage, la seule recherche de bloc lue (`SUB_F1078`, appelée pour `010000h`,
`040000h` et `(datbas)`) cherche un bloc **`RESET   .KEY`** et lit son `+22h` ; rien de ce qui a
été lu ne **rechaîne** un pilote de `S1:`. Si cette séquence tourne à la mise sous tension, un
pilote chaîné à la main **perd son maillon à chaque amorçage**, tandis que son bloc reste. Quel
geste la déclenche (ON après OFF, petit reset, chargement d'un fichier…) n'est **pas établi**.

Conséquence probable pour la version 0.2, à confirmer par la mesure : ne plus dépendre de `d_link`
pour retrouver le bloc (parcours des blocs de `S1:` par le nom), et offrir le ré-accrochage **et**
le rechaînage sans installateur.

### ⛔ Troisième essai : PockEmul plante au chargement de `DRVTEST.BAS` (J.-F. Albouy, 2026-09-16)

`S1:` nettoyé, installation propre : `Installed. Hooks: CALL &80502` (bloc en **`0804ABh`**),
`FILES` : `BASEXT .SYS P 2760`. Puis `LOAD` de `DRVTEST.BAS` depuis `X:` : **le processus
`pockemul.exe` s'arrête** (« a cessé de fonctionner »).

**Hypothèse, non établie : le modèle « ajout en fin » du gabarit place le bloc APRÈS les blocs du
programme BASIC, qui grandissent.** Ce qui la fonde :

| Fait | Source |
|---|---|
| le programme BASIC vit dans des **blocs** `TEXT    BAS` et `DATA    BAS` de `S1:`, dont la ROM range l'adresse en `(txtbas)` `0CBh` et `(datbas)` `0CEh` | 📖 `rom83` : `0F9999h`/`0F99B1h` (`TEXT`), `0F990Fh`/`0F9925h` (`DATA`) ; `pce500.inc` |
| PLINKC 1.62, **validé sur matériel**, n'ajoute pas en fin : il s'insère **avant le premier bloc qui n'est pas un pilote**, décale les suivants vers le haut (« Bloc memoire Stagger »), puis **recale `BTEXT$`/`BDATA$`** (`linkbas`, recherche IOCS `41h` des noms rangés en `[baswrk]+72h`) | ✅ `Exemples/PLINKC/A62/plinkc.a62.asm` |
| un relevé de `FILES` montre `PLINK .SYS` **avant** `DATA .BAS` | `Fichiers-et-slot.md` |
| le `DRIVER_TEMPLATE` n'a été validé que jusqu'à « apparaît dans `FILES` » : aucun programme chargé ensuite | `DRIVER_TEMPLATE/README.md` |
| 1re séance : `DRVTEST` chargé **sans** plantage, mais `BEXT:` introuvable dans `d_link` ; 2e séance, crochets frais : plantage **pendant** le chargement | essais |

Si un bloc de programme grandit, les blocs qui le suivent sont déplacés (ou recouverts). Notre bloc
bouge sans être relogé : `d_link`, les deux crochets et le filtre désignent alors l'ancienne adresse.
Le chargement d'un `.BAS` texte **tokenise chaque ligne en lisant la table de mots-clés par le
crochet** : dès la première ligne stockée, le tokeniseur lit une table décalée. Cela rendrait compte
des deux séances ; cela n'explique pas, à soi seul, que ce soit l'émulateur qui s'arrête.

✅ **Écarté par lecture de la ROM** : une hypothèse de page. Tokeniseur (`0F441Eh`, `0F48B5h`),
répartition (`0F593Dh`) et résolveurs (`0F58ECh`, `0F591Fh`) manipulent les crochets sur 20 bits
(`X`/`Y`) : une extension en page `08h` leur convient. Et la commande IOCS `05h` (`0E0159h`), qui
envoie `40h` à tous les pilotes chaînés, **ignore la retenue** : le stub `sc`/`retf` y est inoffensif.

**Mesure proposée** (`essais/BLOCS.BAS`, PEEK seulement) : liste des blocs de `S1:` avec adresse,
nom, attribut, taille, puis `(txtbas)`/`(datbas)`. La charger **avant** l'installation, la lancer
avant et après `CALL &BF000`, puis taper une ligne `1 REM ABCDEFGHIJ` et relancer : si
`BASEXT  SYS` change d'adresse, l'hypothèse est établie.

#### ✅ `BLOCS.BAS`, 1re étape : après un RESET complet, sans pilote (J.-F. Albouy, 2026-09-16)

| Bloc | Adresse | Taille (`+11h`) | `FILES` | Écart |
|---|---|---|---|---|
| `DATA    BAS` | **`080018h`** (le premier) | **251 597** | 411 | 251 186 |
| `TEXT    BAS` | `0BD6E5h` | 650 | 616 | 34 |
| `FUNCKEY` | `0BD96Fh` | 110 | 76 | 34 |
| `AER` | `0BD9DDh` | 61 | 27 | 34 |

`FIN BDA1A`, `S1BTM BDA1B` ; `TXT BD6E5`, `DAT 80018`. Tous attributs `20h`. La chaîne est jointive :
chaque bloc commence où finit le précédent.

Ce que cela établit :

1. **`DATA.BAS` est le premier bloc, et il contient toute la mémoire libre** : 251 597 octets pour
   411 affichés. Hors des blocs, il ne reste **rien** : la fin de chaîne `0BDA1Ah` touche
   `[s1_btm]` − 1. La place libre n'est donc pas « après la chaîne », elle est **dans** `DATA.BAS`.
2. D'où le « not enough memory » qu'on aurait attendu, et qui n'est pas venu : l'installateur appelle
   d'abord **`47h` (condense)**, qui doit rendre la place de `DATA.BAS` en fin de chaîne. C'est ce qui
   a placé le bloc en `0804ABh`, juste après les petits blocs. Déduit de l'adresse obtenue ; non
   mesuré avant/après.
3. Ajouté en fin, notre bloc suit donc `DATA.BAS`, `TEXT.BAS`, `FUNCKEY` et `AER`. **Le premier
   besoin de place du BASIC** (variables, lignes, chargement) regrossit `DATA.BAS` ou `TEXT.BAS` et
   décale tout ce qui suit. PLINKC s'insère **avant le premier bloc non pilote**, c'est-à-dire avant
   `DATA.BAS` : rien ne le décale ensuite.

⛔ **« `FILES` affiche la taille du bloc moins `22h` » était trop court.** Vrai pour `TEXT`,
`FUNCKEY`, `AER`, `BASEXT.SYS` et PLINKC, faux pour `DATA.BAS` (251 597 contre 411). Ce que `FILES`
affiche est vraisemblablement **`[+16h]` − `22h`** : la taille du fichier (`Fichiers-et-slot.md`
§10), égale à `+11h` pour tous les blocs mesurés sauf `DATA.BAS`, dont le bloc est plus grand que
le fichier. `BLOCS.BAS` ne lit pas `+16h` : non vérifié.

Les étapes 2 et 3 (installation, puis une ligne tapée) restent à faire pour voir le bloc **bouger**.
Prédiction, pour qu'elle puisse être démentie : `BLOCS.BAS` lancé juste après `CALL &BF000` montrera
`DATA.BAS` réduit en tête, et `BASEXT  SYS` **en dernier** ; son adresse différera peut-être déjà de
« adresse `Hooks` − `57h` », puisque le `RUN` lui-même (`CLEAR`, variables) regrossit `DATA.BAS`.

#### ✅ `BLOCS.BAS`, étapes 2 et 3 : LE BLOC BOUGE (J.-F. Albouy, 2026-09-16)

| Moment | `BASEXT  SYS` | `DATA.BAS` |
|---|---|---|
| copié par l'installateur (`Hooks: CALL &8053C` − `57h`) | **`0804E5h`** | réduit par `47h` |
| `RUN` de `BLOCS.BAS` juste après | **`0BCF30h`**, dernier, attribut `25h`, 2794 octets | `080018h`, **248 803** octets = 251 597 − 2794 |
| `1 REM ABCDEFGHIJ` | **PockEmul s'arrête** ; FACTORY RESET nécessaire pour le relancer | — |

`DATA.BAS` a repris toute la place libre et poussé `TEXT`, `FUNCKEY`, `AER` et notre bloc vers le
haut. **L'hypothèse est établie** : ajouté en fin, le bloc bouge sans être relogé, et la ligne tapée
suivante, tokenisée par un crochet périmé, fait tomber l'émulateur. La prédiction écrite avant
l'essai (« dernier, et déjà déplacé au premier `RUN` ») s'est vérifiée.

⚠️ Non établi : **ce qui** regrossit `DATA.BAS`. Le retour à l'interpréteur après `CALL`, ou le
`RUN` (`CLEAR`, variables). Sans effet sur la conclusion.

⚠️ Un défaut de la 0.1 a pu y contribuer : après le compactage `47h`, qui déplace `TEXT.BAS`,
l'installateur ne recalait pas `(txtbas)`/`(datbas)`. PLINKC le fait sur **tous** les chemins
qui suivent le compactage, erreurs comprises.

**Version 0.2** (voir §5ter) : le modèle de PLINKC (insertion avant les blocs non pilotes,
décalage, `linkbas`), avec en plus une **auto-vérification de la relocation** avant copie (champ
IOCS `+5`, un `call` proche de `bd_arret`, drapeau `4` de la première entrée de `disp_table`) et la
recherche du bloc **par la chaîne des blocs** plutôt que par `d_link`.

⚠️ La simulation vérifie la **table** et l'**arithmétique** voulue ; elle ne vérifie pas que la
boucle assembleur exécute cette arithmétique. La version 0.2 ajoute ce témoin **sur la machine**
(§5ter, étape 10).

---

## 5ter. La version 0.2 (2026-09-16) — vérifiée sur PC, pas encore sur machine

Même disposition d'objet que la 0.1 (`0BE400h`, installateur en `0BF000h`, 4536 octets, bloc de
2839 octets). Ce qui change :

| # | Étape de l'installateur | Origine |
|---|---|---|
| 1 | refus si l'image est déjà relogée | 0.1 |
| 2 | **`BASEXT.SYS` déjà présent** (chaîne des blocs, nom + taille) : rien n'est touché, et l'adresse de `bd_reprise` est **réaffichée** (`Already installed. Hooks: CALL &xxxxx`) | nouveau |
| 3 | refus si les crochets ne portent pas la sentinelle | 0.1 |
| 4 | compactage `47h` ; **à partir d'ici, toute sortie passe par `bd_linkbas`** | PLINKC (`msend2`) |
| 5 | `dest` = **premier bloc qui n'est pas un pilote** (attribut, bits `0Ch`), fin = terminateur `0FFh` | PLINKC (`loop1`/`loop2`) |
| 6-8 | mémoire (`[s1_btm]` − 1 − fin ≥ taille), recouvrement de l'objet, page unique | 0.1, PLINKC |
| 9 | relocation de l'image (écart sur 3 octets, `adcl` sur 2 ou 3) | 0.1 |
| 10 | **auto-vérification sur la machine**, avant la copie : champ de 3 octets (entrée IOCS en `+27h`), champ de 2 octets (`call xf_off` de `bd_arret`), drapeau `4` + page (1re entrée de `disp_table`), chacun recalculé par les registres ; sinon `Error: relocation check.` | nouveau |
| 11 | **insertion** : interruptions masquées (`pushu imr`), les blocs de `dest` à la fin **montent** de la taille du bloc (copie depuis le haut, compteur 20 bits dans `U` sauvé sur `S`), puis copie de l'image en `dest` | PLINKC (« Bloc memoire Stagger ») |
| 12 | en-tête publié dans `d_link` | 0.1 |
| 13 | **`bd_linkbas`** : `(txtbas)`, `(datbas)` retrouvés par IOCS `41h` sur les noms de `[baswrk]+72h`/`+7Eh`, puis `[(iocsw)+3Ah]` ← 0 | PLINKC (`linkbas`) |
| 14-15 | `start` relogé pose les crochets ; affichage de l'adresse de **`bd_reprise`** | 0.1, modifié |

**`bd_reprise`**, résident, en `+57h` : remet notre en-tête en tête de `d_link` s'il n'y est plus,
puis saute dans `start`, qui repose les crochets. Il répond au §4.2 sans installateur : c'est
l'adresse affichée à l'installation, et `DRVTEST.BAS` la recalcule.

**Désinstallation** : le bloc est retrouvé par la **chaîne des blocs** (plus par `d_link`), le
maillon n'est délié que s'il est encore dans `d_link`.

**`essais/DRVTEST.BAS` est désormais GÉNÉRÉ** par `construire.py`, avec les décalages du listing
(`kw_table` `+969h`, `bd_reprise` `+57h`). Il retrouve le bloc par la chaîne des blocs, dit si
`d_link` et les crochets sont en place, et donne le `CALL` de réparation.

✅ `construire.py` : 126 champs de 3 octets et 29 de 2 (les 3 de plus : `iocs_header` deux fois et
`jp start` dans `bd_reprise`), table relue dans l'objet, relocation simulée vers trois adresses,
objet **identique à l'octet** à celui du moteur C.

### ✅ Essai sur émulateur de la 0.2 (J.-F. Albouy, 2026-09-16, après FACTORY RESET)

| Moment | `BASEXT  SYS` | `DATA.BAS` | `TEXT.BAS` | fin / `S1BTM` | `TXT` / `DAT` |
|---|---|---|---|---|---|
| avant | — | `080018h`, 251 597 | `0BD6E5h`, 650 | `0BDA1Ah` / `0BDA1Bh` | `BD6E5` / `80018` |
| `CALL &BF000` | `Installed. Hooks: CALL &8006F` | | | | |
| `RUN` suivant | **`080018h`**, en tête, `25h`, 2839 | `080B2Fh`, 408 | `080CC7h`, 650 | `080FFCh` / `0BDA1Bh` | `80CC7` / `80B2F` |
| `1 REM ABCDEFGHIJ`, `RUN` | **`080018h`**, inchangé | `080B2Fh`, **248 740** | `0BD6D3h`, **668** | `0BDA1Ah` / `0BDA1Bh` | `BD6D3` / `80B2F` |
| `DRVTEST.BAS` | `BLOC 80018 REPRISE &8006F`, `D_LINK : OK`, `CROCHETS : OK` | | | | |
| `BEXTTEST.BAS` | **`*** 14/14 OK ***`** | | | | |

Ce qui est établi :

- **l'insertion** : le bloc est en `080018h`, l'ancienne adresse de `DATA.BAS` ; `8006Fh` − `57h` =
  `080018h` ; les blocs suivants sont jointifs (`80018h` + 2839 = `80B2Fh`, + 408 = `80CC7h`) ;
- **le recalage du BASIC** : `TXT` et `DAT` désignent les blocs à leur nouvelle place ;
- **le bloc ne bouge plus** : la ligne tapée fait regrossir `DATA.BAS` (248 740 = 251 597 − 2839 −
  18) et `TEXT.BAS` (+ 18 octets), et tout ce qui les suit monte ; `BASEXT.SYS`, placé avant, reste ;
- **la relocation, à l'exécution** : les 14 mots-clés passent, filtre de `XCONSOLE` compris
  (`BEXTTEST.BAS` lignes 310-380). L'auto-vérification n'a rien refusé.

### ✅ Zone réservée rendue : `POKE &BFE03,&1A,&FD,&B,&10,0,0:CALL &FFFD8` (2026-09-16)

| | Avant (6144 réservés) | Après (16 réservés) |
|---|---|---|
| `DRVTEST.BAS` | OK / OK | **`BLOC 80018`, `D_LINK : OK`, `CROCHETS : OK`** |
| `BASEXT  SYS` | `080018h` | **`080018h`** |
| `DATA.BAS` | `080B2Fh`, 248 740 | `080B2Fh`, **254 886** |
| fin / `S1BTM` | `0BDA1Ah` / `0BDA1Bh` | `0BF20Ah` / **`0BF20Bh`** |

Ce qui est établi :

- **§4.2, pour le petit reset** : `CALL &FFFD8` **conserve** le maillon de `d_link` et les deux
  crochets. `bd_reprise` n'a pas servi. ⚠️ Non mesuré : `OFF`/`ON` et le RESET complet, pour lesquels
  la ROM remet `d_link` à zéro en `0F0D9Eh` (§5bis).
- **La mémoire est rendue au BASIC** : `S1BTM` monte de **6128 octets = 6144 − 16**, exactement la
  réduction demandée, et `DATA.BAS` les reprend (+ 6146 octets, dont les 18 de la ligne `1 REM`
  disparue avec le changement de programme). La chaîne reste jointive jusqu'à `0BF20Ah`.
- ⛔ **L'énigme de `S1BTM` inchangé est levée.** J'avais écrit que `S1BTM` n'avait pas bougé avec la
  réservation. Les deux relevés redonnent la **même** valeur sans réservation :
  `0BF20Bh` + 16 = `0BDA1Bh` + 6144 = **`0BF21Bh`**. La réservation de 6144 octets était donc déjà
  en place lors du premier relevé ; `S1BTM` suit la réservation octet pour octet.

### ✅ Désinstallation : `CALL &BF000 "-U"` puis `SET`/`KILL` (2026-09-16)

| Moment | Relevé |
|---|---|
| `CALL &BF000 "-U"` | `Uninstalled. To free memory :` et les deux commandes |
| `FILES "S1:"` avant `KILL` | `BASEXT .SYS P 2805` (= 2839 − 34 : la règle `FILES` = taille − `22h` tient), `DATA .BAS 495`, `TEXT .BAS 616`, `FUNCKEY 76` |
| `FILES "S1:"` après `KILL` | `DATA .BAS 495`, `TEXT .BAS 616`, `FUNCKEY 76`, `AER 27` |
| `BLOCS.BAS` après `KILL` | `DATA` **`080018h`** 250 313 ; `TEXT` `0BD1E1h` 650 ; `FUNCKEY` `0BD46Bh` ; `AER` `0BD4D9h` ; **`ENG     $$$`** `0BD516h`, attribut `20h`, 1284 ; fin `0BDA1Ah` / `S1BTM` `0BDA1Bh` ; `TXT BD1E1`, `DAT 80018` |

Ce qui est établi : le bloc a disparu, `DATA.BAS` est revenu en tête en `080018h`, et la ROM a
recalé elle-même `TEXT`/`DATA` après le `KILL`. `S1BTM` `0BDA1Bh` = `0BF21Bh` − 6144 : la réservation
reprise pour recharger l'installateur est toujours en place.

📖 **`ENG     $$$` n'est pas du pilote** : le nom complet `"S1:ENG     .$$$"` est une chaîne de la
ROM (`0DF995h`), employée par `SUB_DF9AB` (quatre appelants, `0DF9EEh`, `0DFB4Ah`, `0DFBD9h`,
`0DFC02h`), à côté des fiches du catalogue de formules (`ENG     3##` en `0C0D58h`, `ELEC`,
`MECH`…). Quelle action de l'utilisateur l'a créé n'est pas établi.

✅ **Crochets et maillon rendus** : entre `CALL &BF000 "-U"` et le `KILL`, tête de `d_link` =
**`DF820`** (la table de la ROM) et crochet des noms = **`FFFFF`** (la sentinelle), relevés par
J.-F. Albouy. `bd_arret` rend bien les crochets depuis `old_kw`/`old_disp`, et le déliage fonctionne
(`MODE-EMPLOI.md` §12, point 2).

### ✅ `OFF`/`ON`, zone à 0, RESET : aucun effet (J.-F. Albouy, 2026-09-16)

Rapporté par l'utilisateur : ni `OFF`/`ON`, ni la zone langage machine ramenée à 0
(`POKE &BFE03,&1A,&FD,&B,0,0,0:CALL &FFFD8`), ni un soft RESET (bouton seul) n'ont d'effet sur le pilote installé.
`bd_reprise` n'a donc jamais eu à servir ; il reste en place pour le cas d'une perte.

⚠️ Ce qui reste ouvert : **quel chemin** exécute la remise à zéro de `d_link` lue en `0F0D9Eh`
(`SUB_F0D9A`, appelé en `0F121Bh`, après un test d'écriture en `0BE000h`) et en `0F1665h`
(initialisation complète). Ce n'est ni `OFF`/`ON`, ni le **soft RESET** éprouvé (bouton RESET seul,
sans confirmation d'initialisation, précisé par J.-F. Albouy) : vraisemblablement l'initialisation
de la mémoire, qui efface `S1:` de toute façon.

### ✅ Sur PC-E500S réel, avec `PLINK.SYS` déjà installé (J.-F. Albouy, 2026-09-18)

Premier essai hors émulateur, sur une machine où `PLINK.SYS` (PLINKC) occupait déjà `S1:`. C'est
**par lui** que l'objet est arrivé : `COPY "L:BASEXTDR.OBJ" TO "F:"` depuis le PC (lecteur `L:` de
PLINKC, serveur `APLINKS`), puis `LOAD M "F:BASEXTDR.OBJ"` et `CALL &BF000`. `PLINK.SYS` était donc
chaîné et actif pendant l'installation.
`BLOCS.BAS` après l'installation :

| Bloc | Adresse | Attribut | Taille | Suivant = adresse + taille |
|---|---|---|---|---|
| `PLINK   SYS` | `080018h` | `25h` | 2336 | `080938h` ✓ |
| **`BASEXT  SYS`** | **`080938h`** | `25h` | 2839 | `08144Fh` ✓ |
| `DATA    BAS` | `08144Fh` | `20h` | 211 570 | `0B4EC1h` ✓ |
| `TEXT    BAS` | `0B4EC1h` | `20h` | 650 | `0B514Bh` ✓ |
| `FUNCKEY` | `0B514Bh` | `20h` | 104 | `0B51B3h` ✓ |
| `AER` | `0B51B3h` | `20h` | 39 | `0B51DAh` = fin ✓ |

Fin `0B51DAh`, `S1BTM` `0B51DBh` ; `TXT B4EC1`, `DAT 8144F`. Puis `BEXTTEST.BAS` : tout passe ;
`ON`/`OFF` sans effet ; aucun plantage.

Ce que cela établit, en plus de l'émulateur :

- **la règle d'insertion** (étape 5 de l'installateur) sur un cas qu'on n'avait pas eu : le pilote
  déjà présent (attribut `25h`, bits `0Ch`) est **sauté**, et `BASEXT.SYS` prend la place de
  `DATA.BAS`, **derrière `PLINK.SYS`** ;
- **la cohabitation** avec PLINKC : deux pilotes dans `d_link`, et une extension BASIC ;
- **le matériel réel** : relocation, décalage des blocs et recalage du BASIC s'y comportent comme
  sur PockEmul. `PLINK.SYS` fait bien 2336 octets, le `blen` lu dans `plinkc.a62.lst`.

⚠️ **La limite du §4.3 devient concrète sur cette machine.** `PLINK.SYS` est **sous**
`BASEXT.SYS`. Un `KILL "S1:PLINK.SYS"` recompacterait `S1:` et ferait **descendre** notre bloc de
2336 octets, sans relocation : crochets, `d_link` et filtre désigneraient l'ancienne adresse.
Déduit du modèle (le `KILL` recompacte, comme l'a montré la désinstallation), **non mesuré**, et à
ne pas mesurer sur le vrai Sharp. **Ordre à suivre** : désinstaller BASEXT-DRV
(`CALL &BF000 "-U"`, `SET`, `KILL`), retirer `PLINK.SYS`, puis réinstaller BASEXT-DRV. Dans
l'autre sens, rien à craindre : un pilote installé **après** BASEXT-DRV par le même modèle se place
derrière lui.

⚠️ **Limite connue, commune avec PLINKC** : un pilote inséré **sous** le nôtre puis supprimé par
`KILL` ferait descendre notre bloc, sans relocation (§4.3).

---

## 6. Plan par étapes

| # | Étape | Critère de fin |
|---|---|---|
| 1 | ✅ Rendre BASEXT incluable (§5) | `BASEXT.OBJ` identique à l'octet — fait le 2026-09-16, **non commité** |
| 2 | ✅ §4.1 tranché (refus) ; §4.2 mesuré : `OFF`/`ON`, zone à 0 et RESET conservent maillon et crochets | §5ter |
| 3 | ✅ 0.1 écrite ; ⛔ ajout en fin, le bloc bouge (§5bis) ; ✅ 0.2 écrite et éprouvée sur émulateur (§5ter) | installation, bloc immobile, `DRVTEST` OK, `BEXTTEST` 14/14 |
| 4 | ✅ Zone réservée rendue ; petit reset, `OFF`/`ON`, zone à 0, RESET : maillon et crochets conservés (§5ter) | `S1BTM` + 6128 ; `DRVTEST` OK |
| 5 | ✅ **PC-E500S réel**, avec `PLINK.SYS` déjà installé (§5ter) : insertion derrière `PLINK.SYS`, `BEXTTEST` OK, `ON`/`OFF` OK ; ⚠️ `KILL` d'un pilote **sous** le nôtre : non mesuré, ordre de retrait documenté | |
| 6 | ✅ Désinstallation puis `SET`/`KILL` (§5ter) | `d_link` `DF820`, crochets `FFFFF` ; bloc retiré, `DATA.BAS` en tête, BASIC recalé |
| 7 | Dépôt GitHub | poussé |

---

## 7. Sources

- `C:\Claude\BASEXT\MODE-EMPLOI.md` (§3 crochets, §9.2 zone réservée, §12 points ouverts) et
  `src/BASEXT.ASM`, commit `9c8f3e2`.
- `C:\Claude\xasm2026-4\Exemples\DRIVER_TEMPLATE\` (`README.md`, `driver_template.asm`).
- `C:\Claude\xasm2026-4\Documentation\Modele_Pilotes_Resident_PC-E500S.md`.
- `C:\Claude\xasm2026-4\Exemples\PLINKC\` (`README.md`) et `A62\` (`README.md`,
  `plinkc.a62.asm`) : boucle de relocation, format Kon, contrôle de page ;
  `Documentation_XASM2026-4_PC-E500S.md` §6.1.2 et `src/Assembly/NativeAssembler.cs`
  (l. 259-267, 720-728, 3035-3083) : le préfixe `rel`.
- `SC62015Disassembler/Docs/Synthese/Drivers-IOCS.md` (§1 bloc, §3 idiomes, §4 tables de
  relocalisation, §6 points ouverts) et `Fichiers-et-slot.md` (slot `S1:`).
- Mesures `outils/reloc.py` du 2026-09-16 (§3).
