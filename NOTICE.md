# NOTICE — droits d'auteur, licences et crédits

*Rédigé le 2026-09-24 — mis à jour le 2026-09-24*

Ce dépôt est une **œuvre originale**, mais son installateur **dérive** de travaux plus anciens.
Ce fichier dit lesquels, et à quelles conditions. En cas de doute, la règle la plus restrictive
s'applique : **usage non commercial uniquement**.

---

## 1. BASEXT-DRV (œuvre originale de ce dépôt)

**BASEXT-DRV** — BASEXT résident dans un bloc de pilote de `S1:`, écrit par
**Jean-François Albouy** (2026).

- Périmètre : `src/BASEXTDR.ASM`, `outils/`, `essais/`, `README.md`, `CONCEPTION.md`, et les
  fichiers produits par la construction (`.OBJ`, `.lst`, `.UU`, `reloc.inc`).
- Licence : **PolyForm Noncommercial License 1.0.0** ([`LICENSE`](LICENSE)).

---

## 2. Le code des mots-clés BASIC — inclus, pas recopié

Le corps du bloc résidant vient de **BASEXT** (`BASEXT/src/BASEXT.ASM`), du même auteur, par une
directive `include`. Ce dépôt n'en contient **aucune copie** : seul l'objet assemblé
(`src/BASEXTDR.OBJ`) l'incorpore.

- Dépôt : <https://github.com/jfalbouy/sharp-pce500s-basext>, même licence.

---

## 3. Ce dont l'installateur dérive

L'installateur n'a pas été inventé de rien. Il reprend deux travaux, dans leur structure comme
dans leur méthode :

| Œuvre | Auteurs | Ce que BASEXT-DRV en reprend |
|---|---|---|
| **DRIVER_TEMPLATE** (`XASM2026-4/Exemples/DRIVER_TEMPLATE`) | Jean-François Albouy, **généralisé à partir de REGISTER2** d'**E. Kako** (1990-1992) | l'ossature de l'installateur, les deux en-têtes (bloc mémoire et IOCS), la routine de comparaison de noms, les libellés de messages, la désinstallation par `"-u"` puis `SET`/`KILL` |
| **PLINKC 1.62** | **D. Mizobata** (1996-1999), d'après **PLINK** de **N. Kon** (1990-1994) | le modèle d'insertion avant le premier bloc non pilote, le décalage des blocs suivants, le recalage de `TEXT.BAS`/`DATA.BAS` (`linkbas`), la boucle de relocation octet par octet, le format de table de relocation (Kon), le contrôle « une seule page » |

Ces œuvres amont sont des **freewares dont les termes interdisent l'usage commercial**. C'est la
raison du choix de licence, le même que celui de `XASM2026_CSharp`
(<https://github.com/jfalbouy/XASM2026_CSharp>), dont le `NOTICE.md` détaille les termes d'origine
de XASM, de REGISTER et des programmes d'exemple.

⚠️ Aucun octet de REGISTER2 ni de PLINKC n'est **distribué** ici : ni source, ni binaire. Ce qui
est repris est la **structure** et la **méthode**, écrites à neuf pour ce projet. La licence non
commerciale est retenue par prudence, et par cohérence avec les autres dépôts de l'auteur.

---

## 4. La machine

Les adresses de la ROM, les tables du BASIC et les structures du système citées dans
`CONCEPTION.md` sont des **constats** sur le Sharp PC-E500S, relevés par désassemblage et par la
mesure. Aucune image ROM, ni aucun extrait de la ROM de Sharp, n'est distribué dans ce dépôt.
