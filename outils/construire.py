#!/usr/bin/env python3
"""construire.py -- construit et VERIFIE le pilote BASEXT-DRV.

  python C:\\Claude\\BASEXT-DRV\\outils\\construire.py

Etapes, toutes obligatoires (la table de relocation depend de BASEXT.ASM,
qui vit dans un autre depot : ne jamais assembler BASEXTDR.ASM seul) :

  1. reloc.inc absent : une table vide, pour que la source s'assemble ;
  2. reloc.py mesure les champs du bloc [block_top, block_bottom), verifie la
     table a trois origines et ecrit reloc.inc (format Kon) ;
  3. assemblage final : BASEXTDR.OBJ, .lst (SANS -K : le corps de BASEXT est un
     include, -K en masquerait commentaires et etiquettes), .UU ;
  4. controles sur l'objet final :
     - chargement en 0BE400h, bd_entree en 0BF000h, fin sous 0BFC00h ;
     - la table relue DANS L'OBJET, decodee, egale aux champs mesures ;
     - le bloc de l'objet final identique a celui qu'a mesure reloc.py ;
     - la relocation SIMULEE comme l'installateur la fait (ecart sur 24 bits,
       octet par octet) redonne l'objet assemble a une autre origine ;
  5. le moteur C xasm2026-1-2, s'il est la, assemble la meme source : les
     objets doivent etre identiques (garde-fou contre un defaut d'encodage de
     xasm2026-4, cf. RAPPORT-BUG-octet-pre.md). Un refus du moteur C est signale
     sans etre bloquant.
"""

import os
import shutil
import subprocess
import sys
import tempfile

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ICI)
import reloc  # noqa: E402

SRC = os.path.normpath(os.path.join(ICI, "..", "src"))
SOURCE = "BASEXTDR.ASM"
XASM4 = reloc.XASM_DEFAUT
XASM_C = r"C:\Claude\xasm2026-1-2\build\xasm2026-1-2.exe"
CHARGE, ENTREE, PLAFOND = 0x0BE400, 0x0BF000, 0x0BFC00


def etape(txt):
    print(f"\n== {txt}")


def ecrire_drvtest(sym):
    """essais/DRVTEST.BAS, GENERE : les decalages viennent du listing, jamais de la main.
    PEEK seulement (marche avec ou sans mots-cles) ; CRLF et MAJUSCULES (machine)."""
    top = sym["block_top"]
    kw, rep, taille = sym["kw_table"] - top, sym["bd_reprise"] - top, sym["block_bottom"] - top
    lignes = [
        "10 REM DRVTEST : ETAT DU PILOTE BASEXT-DRV, GENERE PAR CONSTRUIRE.PY",
        f"20 REM PEEK SEULEMENT. KW_TABLE +&{kw:X}, BD_REPRISE +&{rep:X}, BLOC {taille} OCTETS",
        f"30 CLEAR :K0=&{kw:X}:R0=&{rep:X}:B=0",
        "40 T=PEEK &BFC15+PEEK &BFC16*256+PEEK &BFC17*65536",
        "50 X=T+PEEK (T+18)+PEEK (T+19)*256+PEEK (T+20)*65536",
        "60 IF PEEK X<>&FB THEN 100",
        "70 N$=\"\":FOR I=1 TO 11:N$=N$+CHR$ PEEK (X+I):NEXT I",
        "80 IF N$=\"BASEXT  SYS\" THEN B=X:GOTO 100",
        "90 X=X+PEEK (X+17)+PEEK (X+18)*256+PEEK (X+19)*65536:GOTO 60",
        "100 IF B=0 THEN PRINT \"BASEXT.SYS ABSENT DE S1:\":END",
        "110 PRINT \"BLOC \";HEX$ B;\" REPRISE &\";HEX$ (B+R0)",
        "120 P=PEEK &BFCA2+PEEK &BFCA3*256+PEEK &BFCA4*65536:D=0",
        "130 IF P=&FFFFF THEN 160",
        "140 IF P=B+34 THEN D=1:GOTO 160",
        "150 P=PEEK P+PEEK (P+1)*256+PEEK (P+2)*65536:GOTO 130",
        "160 IF D=0 THEN PRINT \"D_LINK : ABSENT\":GOTO 180",
        "170 PRINT \"D_LINK : OK\"",
        "180 W=PEEK &BFD0E+PEEK &BFD0F*256+PEEK &BFD10*65536",
        "190 K=PEEK (W+&90)+PEEK (W+&91)*256+PEEK (W+&92)*65536",
        "200 IF K=B+K0 THEN PRINT \"CROCHETS : OK\":GOTO 220",
        "210 PRINT \"CROCHETS : \";HEX$ K",
        "220 IF D=0 OR K<>B+K0 THEN PRINT \"REPARER : CALL &\";HEX$ (B+R0)",
    ]
    for l in lignes:
        if l != l.upper():
            reloc.erreur("DRVTEST.BAS : minuscules")
    chemin = os.path.normpath(os.path.join(SRC, "..", "essais", "DRVTEST.BAS"))
    with open(chemin, "w", newline="", encoding="ascii") as f:
        f.write("\r\n".join(lignes) + "\r\n")
    print(f"essai       {chemin} (kw_table +{kw:X}h, bd_reprise +{rep:X}h)")


def main():
    os.chdir(SRC)
    inc = os.path.join(SRC, "reloc.inc")
    if not os.path.exists(inc):
        etape("reloc.inc absent : table vide provisoire")
        with open(inc, "w", newline="\r\n", encoding="ascii") as f:
            f.write("rel_table:\n        db      0FFH\nrel_table_end:\n        end\n")

    etape("mesure et generation de la table (reloc.py)")
    r = subprocess.run([sys.executable, os.path.join(ICI, "reloc.py"), SOURCE,
                        "--debut", "block_top", "--fin", "block_bottom", "--inc", "reloc.inc"])
    if r.returncode:
        reloc.erreur("reloc.py a echoue")

    etape("assemblage final")
    r = subprocess.run([XASM4, SOURCE, "-OBASEXTDR.OBJ", "-LBASEXTDR.lst", "-S", "-BBASEXTDR.UU"],
                       capture_output=True, text=True, errors="replace")
    sortie = r.stdout + r.stderr
    print(sortie.strip().splitlines()[-1])
    if "No fatal error" not in sortie:
        reloc.erreur("assemblage final en echec :\n" + sortie)

    etape("controles sur l'objet final")
    obj = open("BASEXTDR.OBJ", "rb").read()
    charge = int.from_bytes(obj[8:11], "little")
    image = obj[reloc.TETE_OBJ:]
    sym = {}
    dans = False
    for ligne in open("BASEXTDR.lst", encoding="latin-1"):
        if ligne.startswith(" - Symbols -"):
            dans = True
        elif dans:
            m = reloc.SYM_RE.match(ligne.rstrip("\r\n"))
            if m:
                sym[m.group(2).lower()] = int(m.group(1), 16)
    for nom in ("block_top", "block_bottom", "bd_entree", "rel_table", "rel_table_end", "bd_fin", "start",
                "bd_arret", "bd_reprise", "kw_table"):
        if nom not in sym:
            reloc.erreur(f"symbole {nom} absent du listing")
    fin = charge + len(image)
    print(f"objet       {charge:06X}h-{fin - 1:06X}h ({len(image)} octets)")
    print(f"bloc        {sym['block_top']:06X}h-{sym['block_bottom'] - 1:06X}h "
          f"({sym['block_bottom'] - sym['block_top']} octets)")
    print(f"installateur {sym['bd_entree']:06X}h ; start a +{sym['start'] - sym['block_top']:X}h ; "
          f"bd_arret a +{sym['bd_arret'] - sym['block_top']:X}h ; "
          f"bd_reprise a +{sym['bd_reprise'] - sym['block_top']:X}h")
    ecrire_drvtest(sym)
    if charge != CHARGE or sym["bd_entree"] != ENTREE or fin > PLAFOND:
        reloc.erreur("disposition : chargement 0BE400h, entree 0BF000h, fin <= 0BFC00h attendus")

    deb, fbloc = sym["block_top"] - charge, sym["block_bottom"] - charge
    t0, t1 = sym["rel_table"] - charge, sym["rel_table_end"] - charge
    table = list(image[t0:t1])
    lus = reloc.decoder_kon(table)
    if len(reloc.encoder_kon(lus)) != len(table):
        reloc.erreur("table de l'objet : longueur incoherente")

    a, _, oa = reloc.assembler(XASM4, SOURCE, None, "A", False)
    b, _, ob = reloc.assembler(XASM4, SOURCE, 0x0A1234, "B", False)
    if a != image:
        reloc.erreur("l'objet final differe d'un reassemblage de controle")
    champs, orph = reloc.classer(a, b, deb, fbloc, reloc.ecart_sur(oa, ob))
    if orph:
        reloc.erreur("octets orphelins dans le bloc")
    mesures = [(o - deb, l) for o, l in champs]
    if lus != mesures:
        reloc.erreur(f"la table DE L'OBJET ({len(lus)} champs) ne correspond pas a la mesure ({len(mesures)})")
    print(f"table       {len(table)} octets dans l'objet, {len(lus)} champs = la mesure")

    # relocation simulee comme l'installateur : ecart sur 24 bits, champ + ecart octet par octet
    for dest in (0x0B2345, 0x08F000, 0x0A0010):
        ecart24 = (dest - sym["block_top"]) & 0xFFFFFF
        bloc = bytearray(image[deb:fbloc])
        pos = 0
        for off, larg in lus:
            pos = off
            v = int.from_bytes(bloc[pos:pos + larg], "little")
            v = (v + (ecart24 & ((1 << (8 * larg)) - 1))) & ((1 << (8 * larg)) - 1)
            bloc[pos:pos + larg] = v.to_bytes(larg, "little")
        # reference : le meme source assemble avec block_top = dest
        ref, _, _ = reloc.assembler(XASM4, SOURCE, oa + (dest - sym["block_top"]), "R", False)
        if bytes(bloc) != ref[deb:fbloc]:
            faux = sum(1 for i in range(len(bloc)) if bloc[i] != ref[deb + i])
            reloc.erreur(f"relocation simulee vers {dest:06X}h : {faux} octets faux")
        print(f"simulation  bloc copie en {dest:06X}h : identique a l'assemblage a cette adresse")

    etape("confrontation au moteur C xasm2026-1-2")
    if not os.path.exists(XASM_C):
        print("moteur C absent : controle non fait")
        return
    tmp = tempfile.mkdtemp(prefix="bdrv_c_")
    try:
        dsrc = os.path.join(tmp, "BASEXT-DRV", "src")
        shutil.copytree(SRC, dsrc, ignore=shutil.ignore_patterns("_rlc_*", "*.OBJ", "*.lst", "*.UU"))
        shutil.copytree(os.path.normpath(os.path.join(SRC, "..", "..", "BASEXT", "src")),
                        os.path.join(tmp, "BASEXT", "src"))
        # le moteur C ne connait ni ASSERT ni <= : les assertions sont neutralisees
        # dans la COPIE (elles ont ete verifiees par xasm2026-4 ; elles n'emettent rien)
        chemin = os.path.join(dsrc, SOURCE)
        lignes = open(chemin, "rb").read().split(b"\n")
        lignes = [b";" + l if l.strip().lower().startswith(b"assert") else l for l in lignes]
        open(chemin, "wb").write(b"\n".join(lignes))
        r = subprocess.run([XASM_C, SOURCE, "-OC.OBJ"], cwd=dsrc, capture_output=True, text=True, errors="replace")
        sortie = (r.stdout + r.stderr).strip()
        cobj = os.path.join(dsrc, "C.OBJ")
        if "No fatal error" not in sortie or not os.path.exists(cobj):
            print("moteur C : refus (non bloquant) :")
            print("\n".join(sortie.splitlines()[-6:]))
            return
        c = open(cobj, "rb").read()
        if c == obj:
            print("moteur C : objet IDENTIQUE a l'octet")
        else:
            diffs = [i for i in range(min(len(c), len(obj))) if c[i] != obj[i]]
            print(f"moteur C : objet DIFFERENT ({len(c)} / {len(obj)} octets, {len(diffs)} differences)")
            for i in diffs[:12]:
                print(f"   {charge + i - reloc.TETE_OBJ:06X}h  xasm2026-4 {obj[i]:02X}  moteur C {c[i]:02X}")
            reloc.erreur("les deux assembleurs ne produisent pas le meme objet")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
