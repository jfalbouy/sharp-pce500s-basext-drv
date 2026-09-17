#!/usr/bin/env python3
"""reloc.py -- table de relocation d'un pilote SC62015, GENEREE puis VERIFIEE.

Plutot que de marquer a la main chaque champ absolu (144 champs dans BASEXT,
mesure du 2026-09-16), par « reldp »/« relref » ou par le prefixe « rel » (voir
plus bas pourquoi on ne s'y fie pas), on fait dire a l'assembleur lui-meme ou
sont les adresses :

  1. assembler la source a son origine A, puis a une origine B ;
  2. dans l'intervalle [debut, fin), chaque octet qui differe appartient a un
     champ relogeable ; sa largeur (3 octets : pointeur 20 bits, drapeau de
     quartet haut conserve ; 2 octets : call/jp proche) se lit sur l'ecart des
     valeurs, qui doit valoir exactement B - A ;
  3. VERIFIER : assembler a une troisieme origine C, appliquer la table a
     l'objet A avec l'ecart C - A, et exiger l'egalite a l'octet avec l'objet C.

Un octet qui differe sans entrer dans un champ (par exemple un « label/256 »
isole) est une ERREUR : l'installateur ne saurait pas le reloger.

Les assemblages se font sur une COPIE temporaire de la source, ecrite dans le
meme dossier (les « include » relatifs restent valables), puis effacee. La
source doit contenir exactement une directive org.

La table s'ecrit par defaut au FORMAT KON (A62), celui qu'emet le prefixe
« rel » de XASM et que lit l'installateur de PLINKC 1.62. On ne s'est pas servi
de « rel » : mesure du 2026-09-16, XASM supposait le champ d'adresse en FIN
d'instruction, faux pour 14 formes sur 27 (xasm2026-4/RAPPORT-BUG-rel-champ-
adresse.md). CORRIGE dans xasm2026-4 le 2026-09-17 et reverifie : sur BASEXT,
la table « rel » egale celle de cet outil. Cet outil reste la voie de BASEXT-DRV
(aucune marque dans la source du referent) et devient un VERIFICATEUR de « rel ».

Usage :
  python reloc.py SOURCE.ASM [--debut SYM|HEX] [--fin SYM|HEX] [--inc reloc.inc]
                  [--format kon|listes] [--origines B,C] [--xasm chemin] [--garder]

Sans --debut/--fin, tout l'objet est pris. Sans --inc, la table n'est pas
ecrite : l'outil mesure et verifie seulement.
"""

import argparse
import os
import re
import subprocess
import sys

XASM_DEFAUT = r"C:\Claude\xasm2026-4\bin\xasm2026-4.exe"
ORG_RE = re.compile(rb"^([ \t]+org[ \t]+)([0-9A-Fa-f]+[Hh]|[0-9]+)([^\r\n]*)$",
                    re.IGNORECASE | re.MULTILINE)
SYM_RE = re.compile(r"^([0-9A-Fa-f]{6})h\s+(\S+)\s*$")
TETE_OBJ = 16           # FF 00 06 01 10 / taille / charge / exec FFFFFF / 00 0F


def erreur(msg):
    print("ERREUR : " + msg, file=sys.stderr)
    sys.exit(1)


def lire_nombre(txt):
    t = txt.strip()
    if t[-1:] in "hH":
        return int(t[:-1], 16)
    return int(t, 0)


def assembler(xasm, source, origine, marque, garder):
    """Assemble une copie de SOURCE a ORIGINE ; rend (octets, symboles, org)."""
    dossier = os.path.dirname(os.path.abspath(source))
    texte = open(source, "rb").read()
    orgs = ORG_RE.findall(texte)
    if len(orgs) != 1:
        erreur(f"{source} : {len(orgs)} directive(s) org, il en faut exactement une")
    org_source = lire_nombre(orgs[0][1].decode())
    if origine is None:
        origine = org_source
    copie = ORG_RE.sub(lambda m: m.group(1) + f"0{origine:05X}H".encode() + m.group(3), texte)
    base = f"_rlc_{marque}"
    chemins = {e: os.path.join(dossier, base + e) for e in (".asm", ".obj", ".lst")}
    open(chemins[".asm"], "wb").write(copie)
    try:
        res = subprocess.run([xasm, base + ".asm", "-O" + base + ".obj", "-L" + base + ".lst", "-S"],
                             cwd=dossier, capture_output=True, text=True, errors="replace")
        sortie = res.stdout + res.stderr
        if "No fatal error" not in sortie:
            erreur(f"assemblage a {origine:06X}h en echec :\n{sortie}")
        obj = open(chemins[".obj"], "rb").read()
        symboles = {}
        dans_symboles = False
        for ligne in open(chemins[".lst"], encoding="latin-1"):
            if ligne.startswith(" - Symbols -"):
                dans_symboles = True
                continue
            if dans_symboles:
                m = SYM_RE.match(ligne.rstrip("\r\n"))
                if m:
                    symboles[m.group(2).lower()] = int(m.group(1), 16)
    finally:
        if not garder:
            for c in chemins.values():
                if os.path.exists(c):
                    os.remove(c)
    if len(obj) < TETE_OBJ or obj[:5] != b"\xFF\x00\x06\x01\x10":
        erreur(f"objet a {origine:06X}h : en-tete inattendu {obj[:5].hex(' ')}")
    taille = obj[5] | obj[6] << 8 | obj[7] << 16
    charge = obj[8] | obj[9] << 8 | obj[10] << 16
    if charge != origine or len(obj) != TETE_OBJ + taille:
        erreur(f"objet a {origine:06X}h : charge {charge:06X}h, taille {taille} "
               f"pour {len(obj) - TETE_OBJ} octets lus")
    return obj[TETE_OBJ:], symboles, origine


def borne(valeur, symboles, org, defaut):
    """Offset depuis l'origine : symbole ou nombre absolu."""
    if valeur is None:
        return defaut
    cle = valeur.lower()
    if cle in symboles:
        return symboles[cle] - org
    try:
        return lire_nombre(valeur) - org
    except ValueError:
        erreur(f"borne {valeur!r} : ni symbole de la source, ni nombre")


def classer(a, b, deb, fin, ecart):
    """Rend la liste triee des (offset, largeur) et la liste des octets orphelins."""
    champs, orphelins = [], []
    p = deb
    while p < fin:
        if a[p] == b[p]:
            p += 1
            continue
        if p + 3 <= fin and all(a[q] != b[q] for q in range(p, p + 3)):
            va = int.from_bytes(a[p:p + 3], "little")
            vb = int.from_bytes(b[p:p + 3], "little")
            if (vb - va) & 0xFFFFF == ecart & 0xFFFFF and va >> 20 == vb >> 20:
                champs.append((p, 3))
                p += 3
                continue
        if p + 2 <= fin and a[p + 1] != b[p + 1]:
            va = int.from_bytes(a[p:p + 2], "little")
            vb = int.from_bytes(b[p:p + 2], "little")
            if (vb - va) & 0xFFFF == ecart & 0xFFFF:
                champs.append((p, 2))
                p += 2
                continue
        orphelins.append(p)
        p += 1
    return champs, orphelins


def appliquer(image, champs, ecart):
    """Reloge une copie de IMAGE comme le fera l'installateur."""
    img = bytearray(image)
    for off, larg in champs:
        v = int.from_bytes(img[off:off + larg], "little")
        if larg == 3:
            v = (v & 0xF00000) | ((v + ecart) & 0xFFFFF)
        else:
            v = (v + ecart) & 0xFFFF
        img[off:off + larg] = v.to_bytes(larg, "little")
    return bytes(img)


def encoder_kon(champs):
    """Format de la table A62 (N. Kon), tel que le lit l'installateur de PLINKC 1.62 :
    delta depuis le champ precedent (le premier depuis 0), bit 080h = 3 octets,
    07Eh = delta long sur 2 octets petit-boutiens, 0FFh = fin."""
    octets, precedent = [], 0
    for off, larg in champs:
        delta = off - precedent
        precedent = off
        bit = 0x80 if larg == 3 else 0x00
        if delta < 0x7E:
            octets.append(delta | bit)
        elif delta <= 0xFFFF:
            octets += [0x7E | bit, delta & 0xFF, delta >> 8]
        else:
            erreur(f"delta de {delta} octets : hors du format Kon")
    return octets + [0xFF]


def decoder_kon(octets):
    champs, pos, i = [], 0, 0
    while octets[i] != 0xFF:
        v = octets[i]
        i += 1
        d = v & 0x7F
        if d == 0x7E:
            d = octets[i] | octets[i + 1] << 8
            i += 2
        pos += d
        champs.append((pos, 3 if v & 0x80 else 2))
    return champs


def ecart_sur(origine_a, origine_x):
    """Un ecart qui fait changer TOUS les octets d'un champ, quelle que soit la retenue."""
    e = (origine_x - origine_a) & 0xFFFFF
    bas, milieu, haut = e & 0xFF, (e >> 8) & 0xFF, e >> 16
    if bas == 0 or milieu in (0x00, 0xFF) or haut in (0x0, 0xF):
        erreur(f"origine {origine_x:06X}h : ecart {e:05X}h inutilisable "
               "(octet bas nul, octet median 00/FF ou quartet haut 0/F)")
    return e


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("--debut", help="premier octet relogeable (symbole ou adresse)")
    ap.add_argument("--fin", help="premier octet APRES la zone relogeable (symbole ou adresse)")
    ap.add_argument("--inc", help="fichier include a ecrire (table rel_table)")
    ap.add_argument("--format", choices=("kon", "listes"), default="kon",
                    help="kon : table A62 lue par PLINKC (defaut) ; listes : deux listes de dw")
    ap.add_argument("--origines", default="0A1234,093579", help="origines B,C en hexadecimal")
    ap.add_argument("--xasm", default=XASM_DEFAUT)
    ap.add_argument("--garder", action="store_true", help="garder les copies temporaires")
    args = ap.parse_args()

    ob, oc = (int(x.rstrip("hH"), 16) for x in args.origines.split(","))
    a, sym_a, org_a = assembler(args.xasm, args.source, None, "A", args.garder)
    b, sym_b, _ = assembler(args.xasm, args.source, ob, "B", args.garder)
    c, _, _ = assembler(args.xasm, args.source, oc, "C", args.garder)
    eb, ec = ecart_sur(org_a, ob), ecart_sur(org_a, oc)

    if not (len(a) == len(b) == len(c)):
        erreur(f"la taille depend de l'origine : {len(a)}, {len(b)}, {len(c)} octets")
    deb = borne(args.debut, sym_a, org_a, 0)
    fin = borne(args.fin, sym_a, org_a, len(a))
    if not 0 <= deb < fin <= len(a):
        erreur(f"intervalle [{deb:X}h, {fin:X}h) hors de l'objet ({len(a):X}h octets)")
    for nom in (args.debut, args.fin):
        if nom and nom.lower() in sym_a and sym_b.get(nom.lower()) != sym_a[nom.lower()] - org_a + ob:
            erreur(f"le symbole {nom} ne suit pas l'origine")

    champs, orphelins = classer(a, b, deb, fin, eb)
    if orphelins:
        erreur("octets relogeables hors de tout champ de 2 ou 3 octets : "
               + ", ".join(f"{org_a + o:06X}h" for o in orphelins[:20]))
    for nom, autre, e in (("B", b, eb), ("C", c, ec)):
        reloge = appliquer(a, champs, e)
        faux = [o for o in range(deb, fin) if reloge[o] != autre[o]]
        if faux:
            erreur(f"la table ne reloge pas A en {nom} : "
                   + ", ".join(f"{org_a + o:06X}h" for o in faux[:20]))

    n3 = [o - deb for o, l in champs if l == 3]
    n2 = [o - deb for o, l in champs if l == 2]
    print(f"source      {args.source}")
    print(f"origines    A={org_a:06X}h  B={ob:06X}h  C={oc:06X}h")
    print(f"zone        {org_a + deb:06X}h-{org_a + fin - 1:06X}h  ({fin - deb} octets)")
    print(f"champs      {len(n3)} de 3 octets, {len(n2)} de 2 octets (call/jp proches)")
    print("verifie     la table reloge A en B et en C, a l'octet")

    if args.inc:
        tete = [
            "; ============================================================================",
            f"; {os.path.basename(args.inc)} -- GENERE par outils/reloc.py, NE PAS EDITER",
            f"; source {os.path.basename(args.source)}, zone {org_a + deb:06X}h-{org_a + fin - 1:06X}h"
            f" ({fin - deb} octets), {len(n3)} champs de 3 octets, {len(n2)} de 2",
            "; verifie par assemblage a trois origines",
        ]
        if args.format == "kon":
            kon = encoder_kon([(o - deb, l) for o, l in champs])
            if decoder_kon(kon) != [(o - deb, l) for o, l in champs]:
                erreur("l'encodage Kon ne se relit pas a l'identique")
            lignes = tete + [
                "; format Kon/A62 (celui de PLINKC) : delta depuis le champ precedent, le",
                "; premier depuis le DEBUT DE LA ZONE ; bit 080h = 3 octets ; 07Eh = delta",
                "; long sur 2 octets ; 0FFh = fin",
                "; ============================================================================",
                "rel_table:",
            ]
            for i in range(0, len(kon), 12):
                lignes.append("        db      " + ",".join(f"0{x:02X}H" for x in kon[i:i + 12]))
        else:
            lignes = tete + [
                "; deux listes de dw : offsets depuis le debut de la zone",
                "; ============================================================================",
                "rel_table:",
                f"        dw      {len(n3)}              ; champs de 3 octets (quartet haut conserve)",
            ]
            for i in range(0, len(n3), 8):
                lignes.append("        dw      " + ",".join(f"0{o:04X}H" for o in n3[i:i + 8]))
            lignes.append(f"        dw      {len(n2)}              ; champs de 2 octets (call/jp proches)")
            for i in range(0, len(n2), 8):
                lignes.append("        dw      " + ",".join(f"0{o:04X}H" for o in n2[i:i + 8]))
        lignes += ["rel_table_end:", "        end", ""]
        with open(args.inc, "w", newline="\r\n", encoding="ascii") as f:
            f.write("\n".join(lignes))
        print(f"ecrit       {args.inc}")


if __name__ == "__main__":
    main()
