; ============================================================================
; BASEXTDR.ASM -- BASEXT residant : un pilote de S1: (projet BASEXT-DRV)
; ============================================================================
; Version 0.2 du 2026-09-16 -- NON EPROUVEE SUR MACHINE.
;
; Les 14 mots-cles de BASEXT (LPEEK ... XCLS) vivent dans un bloc protege de
; S1: (BASEXT.SYS) au lieu de la zone langage machine. Le code des mots-cles
; n'est PAS recopie : il est INCLUS depuis C:\Claude\BASEXT\src\BASEXT.ASM.
;
; SUR LA MACHINE
;   POKE &BFE03,&1A,&FD,&B,0,&18,0:CALL &FFFD8   reserver 6144 octets (0BE400h)
;   LOAD M "X:BASEXTDR.OBJ"                      (ou F:)
;   CALL &BF000                                  installer
;   CALL &xxxxx                                  reposer crochets et maillon
;                                                (adresse affichee a l'installation)
;   CALL &BF000 "-U"                             desinstaller (puis SET/KILL)
;
; ⛔ LA VERSION 0.1 AJOUTAIT LE BLOC EN FIN DE CHAINE, et il BOUGEAIT. Mesure
;    sur emulateur le 2026-09-16 (essais/BLOCS.BAS) : copie en 0804E5h, relue en
;    0BCF30h au RUN suivant. DATA.BAS est le PREMIER bloc de S1: et contient la
;    memoire libre ; en regrossissant, il pousse tout ce qui le suit, et le bloc
;    deplace sans relocation laissait crochets, d_link et filtre sur l'ancienne
;    adresse (plantage de PockEmul a la ligne tapee suivante). Le DRIVER_TEMPLATE
;    n'avait ete valide que jusqu'a « apparait dans FILES ».
;    La 0.2 reprend le modele de PLINKC 1.62, VALIDE SUR MATERIEL : insertion
;    AVANT le premier bloc qui n'est pas un pilote, decalage des blocs suivants,
;    puis recalage de TEXT.BAS/DATA.BAS (linkbas).
;
; OU EST LE CODE DES MOTS-CLES : PAS ICI. Une seule ligne l'apporte,
;   « include ..\..\BASEXT\src\BASEXT.ASM », dans le bloc residant (bandeau
;   #### plus bas). Ce fichier n'ecrit que ce qui fait de ce code un pilote :
;   en-tetes, bd_arret, bd_reprise, installateur, desinstallateur.
;
; L'OBJET (charge en 0BE400h)
;   0BE400h  block_top    l'IMAGE du bloc, relogee puis copiee dans S1:
;            ...          bourrage jusqu'a 0BF000h
;   0BF000h  bd_entree    l'installateur (CALL &BF000)
;            rel_table    la table de relocation, GENEREE (reloc.inc)
;
; CONSTRUIRE : python ..\outils\construire.py   (jamais xasm seul : la table
; de relocation doit etre regeneree a chaque modification, ici OU dans BASEXT)
;
; SOURCES : xasm2026-4/Exemples/DRIVER_TEMPLATE (en-tetes, desinstallation) ;
; xasm2026-4/Exemples/PLINKC/A62 (insertion, decalage, linkbas, table Kon,
; controle de page) ; BASEXT-DRV/CONCEPTION.md (decisions, mesures).
; ============================================================================

        include pce500.inc

; BASEXT.ASM, inclus plus bas, n'emet alors ni son include de pce500.inc, ni
; son org, ni son pre_on. ⛔ DEF, pas EQU : IFNDEF ne voit que DEF.
        def     basext_pilote

        org     0BE400H
        pre_on                          ; INDISPENSABLE (skill pc-e500s §2.2)

bd_objet:

; ============================================================================
;  LE BLOC RESIDANT -- de block_top a block_bottom
; ============================================================================
;  Tout ce qui est ici est RELOGE : toute adresse absolue interne au bloc est
;  un champ de 2 ou 3 octets que reloc.py mesure. Le bloc ne doit JAMAIS citer
;  une adresse de l'installateur (elle serait relogee a tort).
block_top:
; -- en-tete de bloc memoire (disposition du DRIVER_TEMPLATE) --
        db      0FBH                    ; signature de bloc
        db      'BASEXT  SYS'           ; nom 8.3, 8 + 3, sans point
        db      025H                    ; attributs : device + protege (bits 0Ch : pilote)
        dw      0,0                     ; date, heure
        dp      block_bottom-block_top  ; +11h : taille du bloc (lien vers le suivant)
        dw      0
        dp      block_bottom-block_top  ; +16h : taille du fichier (FILES affiche +16h - 22h)
        dp      block_bottom-block_top
        dp      0,0
; -- en-tete IOCS (maillon de la chaine d_link), en +22h --
iocs_header:
bd_lien:
        dp      0                       ; lien suivant : ecrit par l'installateur
        db      20                      ; numero de device (celui du gabarit)
        db      063H                    ; attribut de device (celui du gabarit)
        dp      bd_iocs                 ; point d'entree IOCS (reloge)
bd_nom:
        db      'BEXT:'
bd_nom_f:
        db      0
; -- entree IOCS : aucune commande geree. La commande IOCS 05h (0E0159h) envoie
;    40h a tous les pilotes chaines et IGNORE la retenue : ce stub y suffit. --
bd_iocs:
        sc
        retf

; bd_arret -- appele par le desinstallateur, par callf a l'adresse relogee.
;   1. debranche le filtre d'ecran de XCONSOLE s'il est le notre (xf_off) ;
;   2. rend les crochets du BASIC sauves par start, SEULEMENT s'ils designent
;      encore ce bloc (sinon une autre extension s'est installee depuis).
;   Detruit A, I, X, Y, (bl), (014H)-(016H). Preserve (00EH)-(013H), (017H)-(019H).
;   ⚠️ Son premier octet d'operande (le call proche) sert a l'AUTO-VERIFICATION
;   de la relocation (bi_verif) : garder « call xf_off » en tete.
bd_arret:
        call    xf_off
        mv      x,(basptr)              ; objet : 30 84 D1
        mv      y,[x+090H]
        mv      (014H),y
        mv      y,kw_table
        cmpp    (014H),y
        jrnz    ba_fin                  ; pas nos tables : ne rien rendre
        mv      y,[old_kw]
        mv      [x+090H],y
        mv      y,[old_disp]
        mv      [x+093H],y
ba_fin:
        retf

; bd_reprise -- CALL &xxxxx depuis le BASIC, SANS installateur.
;   La ROM remet d_link a sa table d'origine a l'amorcage (0F0D9Eh), et les
;   crochets peuvent partir avec : le bloc reste, le reste se repare ici.
;   1. remet notre en-tete en tete de d_link s'il n'y est plus ;
;   2. saute dans start, qui repose les crochets (idempotent).
;   Registres seulement (aucune RAM interne) ; X rendu tel quel par start.
bd_reprise:
        pushu   x
        mv      y,iocs_header           ; notre en-tete, a son adresse relogee
        mv      x,[d_link]
bd_rp_lp:
        pushu   x
        inc     x                       ; 0FFFFFh : fin de chaine (idiome du gabarit)
        popu    x                       ; POPU ne touche pas les drapeaux
        jrz     bd_rp_absent
        pushu   x
        sub     x,y
        dec     x
        inc     x                       ; Z = en-tete courant = le notre
        popu    x
        jrz     bd_rp_present
        mv      x,[x]
        jr      bd_rp_lp
bd_rp_absent:
        mv      x,[d_link]
        mv      [iocs_header],x         ; notre lien <- la tete actuelle
        mv      [d_link],y              ; la tete <- notre en-tete
bd_rp_present:
        popu    x
        jp      start                   ; start rend la main au BASIC (rc / retf)

; ############################################################################
; ##                                                                        ##
; ##   LE CODE DES 14 MOTS-CLES N'EST PAS ECRIT DANS CE FICHIER :           ##
; ##   IL EST INCLUS ICI, DEPUIS C:\Claude\BASEXT\src\BASEXT.ASM            ##
; ##                                                                        ##
; ##   start, LPEEK, WPEEK, LPOKE, MOD, INSTR, TRIM$, LTRIM$, RTRIM$,       ##
; ##   UCASE$, LCASE$, REPT$, SREPT$, XCONSOLE, XCLS, le filtre d'ecran,    ##
; ##   kw_table, disp_table et les variables : environ 2700 octets.         ##
; ##   Le code assemble se lit dans BASEXTDR.lst (sans -K).                 ##
; ##                                                                        ##
; ############################################################################
        include ..\..\BASEXT\src\BASEXT.ASM
; ############################################################################
; ##   FIN DU CODE INCLUS DEPUIS BASEXT.ASM                                 ##
; ############################################################################
block_bottom:

; ============================================================================
;  BOURRAGE : l'installateur commence en 0BF000h (CALL &BF000)
; ============================================================================
        ds      bd_objet+00C00H-*

; ============================================================================
;  L'INSTALLATEUR -- CALL &BF000 installe, CALL &BF000 "-U" desinstalle
; ============================================================================
;  RAM interne de travail (adresses directes, sous pre_on), comme le gabarit :
;    (000H)        drapeau d'argument, puis octet de comparaison
;    (001H)-(004H) conversion hexadecimale
;    (005H)-(007H) block_top          (008H)-(00AH) ecart = dest - block_top
;    (00BH)-(00DH) champ en cours     (00EH)-(010H) dest, ou notre en-tete
;    (011H)-(013H) fin de chaine, ou predecesseur
;    (014H)-(016H) comparaisons       (017H)-(019H) bloc trouve
bd_entree:
;  (0) l'argument de CALL : "-U" ou "-u" desinstalle. Pointeur de ligne rendu
;      AVANCE au-dela de l'argument (gabarit : sinon Syntax error au retour).
        popu    x
        mv      (000H),000H
bd_arg:
        mv      a,[x++]
        cmp     a,000H
        jrz     bd_arg_f
        cmp     a,00DH
        jrz     bd_arg_f
        cmp     a,01AH
        jrz     bd_arg_f
        cmp     a,0FFH
        jrz     bd_arg_f
        cmp     a,'-'
        jrnz    bd_arg
        mv      a,[x]
        cmp     a,'u'
        jrz     bd_arg_u
        cmp     a,'U'
        jrnz    bd_arg
bd_arg_u:
        mv      (000H),001H
        jr      bd_arg
bd_arg_f:
        dec     x
        pushu   x
        mv      x,bd_m_titre
        mv      y,bd_m_titre_f-bd_m_titre
        call    bd_ecrire
        mv      a,(000H)
        cmp     a,000H
        jrz     bi_image
        jp      bd_desinst

; ----------------------------------------------------------------------------
;  INSTALLATION
; ----------------------------------------------------------------------------
;  (1) l'image a-t-elle deja ete relogee (CALL precedent sans LOAD M) ?
bi_image:
        mv      a,[bd_reloge]
        cmp     a,000H
        jrz     bi_doublon
        mv      x,bd_m_recharger
        mv      y,bd_m_recharger_f-bd_m_recharger
        jp      bd_erreur

;  (2) deja installe ? Alors ne rien toucher, et REDONNER l'adresse de reprise
;      (le cas normal apres un amorcage qui a perdu crochets et maillon).
bi_doublon:
        call    bd_trouver
        jrc     bi_crochets
        mv      y,[x+011H]
        mv      (014H),y
        mv      y,block_bottom-block_top
        cmpp    (014H),y
        jrz     bi_deja
        mv      x,bd_m_autre
        mv      y,bd_m_autre_f-bd_m_autre
        jp      bd_erreur
bi_deja:
        mv      y,bd_reprise-block_top
        add     x,y
        mv      y,bd_m_hex_d
        call    bd_hexa
        mv      x,bd_m_deja
        mv      y,bd_m_deja_f-bd_m_deja
        jp      bd_erreur

;  (3) les crochets du BASIC doivent porter la sentinelle 0FFFFFh : sinon une
;      extension est deja active (BASEXT en 0BF000h, BASCOM...), et start ne
;      sauverait pas les crochets d'origine (CONCEPTION.md §4.4).
bi_crochets:
        mv      x,(basptr)              ; objet : 30 84 D1
        mv      a,[x+092H]
        cmp     a,00FH
        jrz     bi_compacter
        mv      x,bd_m_crochets
        mv      y,bd_m_crochets_f-bd_m_crochets
        jp      bd_erreur

;  (4) compacter S1: (IOCS device 6, commande 47h). ⚠️ LES BLOCS BOUGENT : a
;      partir d'ici, tout chemin de sortie passe par bd_linkbas (bd_erreur_lb),
;      comme PLINKC (msend2).
bi_compacter:
        mv      (cl),006H
        mv      (ch),000H
        mv      i,00047H
        callf   iocs_call

;  (5) dest = premier bloc qui n'est PAS un pilote (attribut, bits 0Ch : regle
;      de register.lst) ; fin = le terminateur 0FFh de la chaine.
        mv      x,[s1_top]
        mv      y,[x+012H]
        add     x,y
        mv      (00EH),x
bi_pilotes:
        mv      a,[x]
        cmp     a,0FBH
        jrnz    bi_fin_chaine
        mv      a,[x+00CH]
        test    a,00CH
        jrz     bi_autres
        mv      y,[x+011H]
        add     x,y
        mv      (00EH),x                ; apres ce pilote
        jr      bi_pilotes
bi_autres:
        mv      y,[x+011H]
        add     x,y
        mv      a,[x]
        cmp     a,0FBH
        jrz     bi_autres
bi_fin_chaine:
        mv      (011H),x                ; fin = le terminateur

;  (6) memoire : [s1_btm] - 1 - fin >= taille du bloc
        mv      y,[s1_btm]
        dec     y
        sub     y,x
        mv      (014H),y
        mv      y,block_bottom-block_top
        cmpp    (014H),y
        jrnc    bi_recouvre
        mv      x,bd_m_memoire
        mv      y,bd_m_memoire_f-bd_m_memoire
        jp      bd_erreur_lb

;  (7) la chaine decalee ne doit pas atteindre l'objet charge : fin + taille <
;      bd_objet. Attendu toujours vrai ; verifie plutot que suppose.
bi_recouvre:
        mv      y,block_bottom-block_top
        add     y,x
        mv      (014H),y
        mv      y,bd_objet
        cmpp    (014H),y
        jrc     bi_page
        mv      x,bd_m_recouvre
        mv      y,bd_m_recouvre_f-bd_m_recouvre
        jp      bd_erreur_lb

;  (8) une seule page de 64 Ko pour le bloc (call/jp PROCHES) : PLINKC 1.62.
bi_page:
        mv      ba,(00EH)               ; les 16 bits bas de dest
        mv      i,block_bottom-block_top
        add     ba,i
        jrnc    bi_reloger
        mv      x,bd_m_pages
        mv      y,bd_m_pages_f-bd_m_pages
        jp      bd_erreur_lb

;  (9) RELOGER l'image avant la copie. Ecart = dest - block_top sur 3 octets, en
;      RAM interne ; chaque champ augmente de l'ecart OCTET PAR OCTET (adcl sur 2
;      ou 3 octets) : le drapeau 4/8 de disp_table ne passe par aucun registre.
;      Table au format Kon, offsets depuis block_top (reloc.inc).
bi_reloger:
        mv      x,block_top
        mv      (005H),x
        mv      x,(00EH)
        mv      (008H),x
        mv      i,00003H
        rc
        sbcl    (008H),(005H)           ; (008H) = dest - block_top, modulo 2^24
        mv      a,001H
        mv      [bd_reloge],a           ; a partir d'ici, l'image est engagee
        mv      x,rel_table
        mv      y,block_top
br_lp:
        mv      a,[x++]
        cmp     a,0FFH
        jrz     bi_verif
        mv      i,00002H
        test    a,080H
        jrz     br_larg
        mv      i,00003H
br_larg:
        and     a,07FH
        cmp     a,07EH
        jrnz    br_court
        mv      ba,[x]                  ; ecart long, 2 octets
        inc     x
        inc     x
        add     y,ba
        jr      br_champ
br_court:
        add     y,a
br_champ:
        mvp     (00BH),[y]
        rc
        adcl    (00BH),(008H)           ; I octets : 2 ou 3
; ⛔ PAS « mvp [y],(00BH) » : xasm2026-4 l'assemble EA 05 0B, SANS l'octet PRE
;    (moteur C : 30 EA 05 0B), et l'ecriture partirait de (BP+0Bh). Voir
;    xasm2026-4/RAPPORT-BUG-octet-pre.md. Trois octets recrits un par un (un
;    champ de 2 octets recrit son 3e intact).
        mv      a,(00BH)
        mv      [y],a
        mv      a,(00CH)
        mv      [y+001H],a
        mv      a,(00DH)
        mv      [y+002H],a
        jr      br_lp

;  (10) AUTO-VERIFICATION de la relocation, SUR LA MACHINE, avant la copie : trois
;       champs dont la valeur relogee se calcule autrement, par les registres.
;       La simulation de construire.py verifie la table ; ceci verifie que la
;       boucle ci-dessus a fait, sur ce CPU, ce que la simulation suppose.
bi_verif:
;       (a) champ de 3 octets : le point d'entree IOCS de l'en-tete
        mv      x,(00EH)
        mv      y,bd_iocs-block_top
        add     x,y
        mv      y,[iocs_header+005H]
        sub     y,x
        dec     y
        inc     y
        jrnz    bi_faux
;       (b) champ de 2 octets : l'operande du « call xf_off » de bd_arret
        mv      x,(00EH)
        mv      y,xf_off-block_top
        add     x,y
        mv      (014H),x
        mv      ba,(014H)
        mv      i,[bd_arret+001H]
        sub     ba,i
        jrnz    bi_faux
;       (c) drapeau : 3e octet de la 1re entree de disp_table = 40h + page
        mv      x,(00EH)
        mv      y,lpeek_m3-block_top
        add     x,y
        mv      (014H),x
        mv      a,(016H)
        add     a,040H
        mv      (014H),a
        mv      a,[disp_table+003H]
        cmp     (014H),a
        jrz     bi_inserer
bi_faux:
        mv      x,bd_m_verif
        mv      y,bd_m_verif_f-bd_m_verif
        jp      bd_erreur_lb

;  (11) INSERER : lien ecrit dans l'image ; interruptions masquees ; les blocs de
;       dest a la fin (terminateur compris) montent de la taille du bloc, octet
;       par octet depuis le haut ; l'image est copiee en dest. U sert de compteur
;       20 bits, sauve sur S (PLINKC : « pushs u »).
bi_inserer:
        mv      x,[d_link]
        mv      [bd_lien],x
        pushu   imr                     ; IMR bit 7 <- 0 : interruptions masquees
        mv      [--s],u
        mv      x,(011H)
        mv      y,(00EH)
        sub     x,y
        inc     x                       ; fin - dest + 1 octets a deplacer
        mv      u,x
        mv      x,(011H)
        inc     x                       ; source : juste apres le terminateur
        mv      y,x
        mv      i,block_bottom-block_top
        add     y,i                     ; destination : taille du bloc plus haut
bd_monter:
        mv      a,[--x]
        mv      [--y],a
        dec     u
        jrnz    bd_monter
        mv      x,block_top
        mv      y,(00EH)
        mv      i,block_bottom-block_top
bd_copier:
        mv      a,[x++]
        mv      [y++],a
        dec     i
        jrnz    bd_copier
        mv      u,[s++]
        popu    imr

;  (12) publier l'en-tete dans d_link
        mv      x,(00EH)
        mv      il,iocs_header-block_top
        add     x,il
        mv      [d_link],x

;  (13) les blocs du BASIC ont bouge : recaler TEXT.BAS et DATA.BAS
        call    bd_linkbas

;  (14) poser les crochets du BASIC : le start de BASEXT, a son adresse relogee
;       (operande du callf ecrit ici, idiome de MEMCHECK)
        mv      x,(00EH)
        mv      y,start-block_top
        add     x,y
        mv      [bi_start+1],x
bi_start:
        callf   000000H                 ; OPERANDE REECRIT ci-dessus

;  (15) succes, et l'adresse de bd_reprise
        mv      x,(00EH)
        mv      y,bd_reprise-block_top
        add     x,y
        mv      y,bd_m_hex
        call    bd_hexa
        mv      x,bd_m_ok
        mv      y,bd_m_ok_f-bd_m_ok
        call    bd_ecrire
        rc
        retf

; ----------------------------------------------------------------------------
;  DESINSTALLATION -- CALL &BF000 "-U"
; ----------------------------------------------------------------------------
;  Le bloc se retrouve par la CHAINE DES BLOCS, pas par d_link : l'amorcage
;  remet d_link a zero, le bloc reste.
bd_desinst:
        call    bd_trouver
        jrnc    bu_taille
        mv      x,bd_m_absent
        mv      y,bd_m_absent_f-bd_m_absent
        jp      bd_erreur
bu_taille:
        mv      y,[x+011H]
        mv      (014H),y
        mv      y,block_bottom-block_top
        cmpp    (014H),y
        jrz     bu_arreter
        mv      x,bd_m_autre
        mv      y,bd_m_autre_f-bd_m_autre
        jp      bd_erreur

;  filtre et crochets rendus PAR LE BLOC (bd_arret), AVANT de delier
bu_arreter:
        mv      x,(017H)
        mv      y,bd_arret-block_top
        add     x,y
        mv      [bu_arret+1],x
bu_arret:
        callf   000000H                 ; OPERANDE REECRIT ci-dessus

;  delier notre en-tete de d_link, s'il y est encore
        mv      x,(017H)
        mv      il,iocs_header-block_top
        add     x,il
        mv      (00EH),x
        mv      y,d_link
bu_chaine:
        mv      x,[y]
        inc     x
        jrz     bu_fin                  ; plus dans la chaine : rien a delier
        dec     x
        mv      (011H),y
        mv      (014H),x
        cmpp    (014H),(00EH)
        jrz     bu_delier
        mv      y,x
        jr      bu_chaine
bu_delier:
        mv      x,[x]
        mv      y,(011H)
        mv      [y],x
bu_fin:
        mv      x,bd_m_desinst
        mv      y,bd_m_desinst_f-bd_m_desinst
        call    bd_ecrire
        rc
        retf

; ----------------------------------------------------------------------------
;  SOUS-PROGRAMMES (appels proches, installateur seulement)
; ----------------------------------------------------------------------------
; bd_erreur_lb -- sortie en erreur APRES le compactage : recaler le BASIC d'abord
bd_erreur_lb:
        pushu   x
        pushu   y
        call    bd_linkbas
        popu    y
        popu    x
; bd_erreur -- affiche le message X (longueur Y) et rend la main, carry CLAIR
bd_erreur:
        call    bd_ecrire
        rc                              ; carry arme -> Syntax error au retour
        retf

; bd_ecrire -- X = texte, Y = longueur, sur l'ecran (handle 0)
bd_ecrire:
        mv      (cl),000H
        mv      il,fcs_write_block
        callf   fcs_call
        ret

; bd_trouver -- cherche BASEXT.SYS dans la chaine des blocs de S1:.
;   CY=0 : X = (017H) = le bloc. CY=1 : absent. Detruit A, IL, Y, (000H).
bd_trouver:
        mv      x,[s1_top]
        mv      y,[x+012H]
        add     x,y
bt_lp:
        mv      a,[x]
        cmp     a,0FBH
        jrnz    bt_absent
        mv      (017H),x
        mv      y,block_top             ; le nom de l'image (jamais reloge)
        mv      il,12
        call    bd_compare
        mv      x,(017H)
        jrz     bt_trouve
        mv      y,[x+011H]
        add     x,y
        jr      bt_lp
bt_trouve:
        rc
        ret
bt_absent:
        sc
        ret

; bd_linkbas -- recale (txtbas) et (datbas) apres un deplacement des blocs.
;   Recopie de linkbas (PLINKC 1.62) : [baswrk]+72h porte le n° de lecteur puis
;   le nom de TEXT.BAS, +7Eh ceux de DATA.BAS (la ROM les lit la : 0F996Bh) ;
;   IOCS device 6, commande 41h, cherche le bloc et rend Y. Puis « Detachez
;   RAMFILE » : [(iocsw)+3Ah] <- 0.
bd_linkbas:
        mv      x,[baswrk]
        mv      a,072H
        add     x,a
        call    bd_chercher
        jrc     bd_perdu
        mv      (txtbas),y
        call    bd_chercher
        jrc     bd_perdu
        mv      (datbas),y
        mv      a,000H
        mv      [(iocsw)+03AH],a
        ret
; Les blocs du BASIC introuvables : la memoire est incoherente. PLINKC fait de
; meme (« bomb: reset »).
bd_perdu:
        reset
bd_chercher:
        mv      (ch),[x++]
        mv      (cl),006H
        mv      il,041H
        callf   iocs_call
        ret

; bd_compare -- compare IL octets de [X] et [Y] ; Z=1 si egaux (stricmp du
;               gabarit, en appel proche). Detruit (000H), A, IL, X, Y.
bd_compare:
        mv      (000H),[x++]
        mv      a,[y++]
        cmp     (000H),000H
        jrz     bdc_nul
        cmp     (000H),a
        jrnz    bdc_ret
        dec     il
        jrnz    bd_compare
        ret
bdc_nul:
        cmp     (000H),a
bdc_ret:
        ret

; bd_hexa -- ecrit X (20 bits) en 5 chiffres hexadecimaux a partir de Y
bd_hexa:
        mv      (001H),x
        mv      a,(003H)
        call    bh_chiffre
        mv      a,(002H)
        call    bh_octet
        mv      a,(001H)
bh_octet:
        mv      (004H),a
        swap    a
        call    bh_chiffre
        mv      a,(004H)
bh_chiffre:
        and     a,00FH
        cmp     a,00AH
        jrc     bh_dec
        add     a,007H
bh_dec:
        add     a,030H
        mv      [y++],a
        ret

; ----------------------------------------------------------------------------
;  DONNEES DE L'INSTALLATEUR
; ----------------------------------------------------------------------------
bd_reloge:      db      0               ; 1 : image deja relogee

bd_m_titre:     db      'BASEXT-DRV 0.2 (BEXT:)',13,10
bd_m_titre_f:
bd_m_ok:        db      'Installed. Hooks: CALL &'
bd_m_hex:       db      '00000',13,10
bd_m_ok_f:
bd_m_deja:      db      'Already installed.',13,10
                db      'Hooks: CALL &'
bd_m_hex_d:     db      '00000',13,10
bd_m_deja_f:
bd_m_recharger: db      'Error: LOAD M the .OBJ again.',13,10
bd_m_recharger_f:
bd_m_crochets:  db      'Error: BASIC extension in use.',13,10
bd_m_crochets_f:
bd_m_memoire:   db      'Error: not enough memory.',13,10
bd_m_memoire_f:
bd_m_recouvre:  db      'Error: block over loader.',13,10
bd_m_recouvre_f:
bd_m_pages:     db      'Error: over two pages.',13,10
bd_m_pages_f:
bd_m_verif:     db      'Error: relocation check.',13,10
bd_m_verif_f:
bd_m_absent:    db      'BASEXT.SYS not in S1:.',13,10
bd_m_absent_f:
bd_m_autre:     db      'Error: other BASEXT.SYS.',13,10
bd_m_autre_f:
bd_m_desinst:   db      'Uninstalled. To free memory :',13,10
                db      'SET  "S1:BASEXT.SYS"," "',13,10
                db      'KILL "S1:BASEXT.SYS"',13,10
bd_m_desinst_f:

; ============================================================================
;  LA TABLE DE RELOCATION -- GENEREE par outils/reloc.py (via construire.py)
; ============================================================================
;  APRES le bloc : sa taille change avec la source, elle ne doit rien decaler.
        include reloc.inc
bd_fin:

; ============================================================================
;  VERIFICATIONS A L'ASSEMBLAGE -- en DIFFERENCES d'etiquettes seulement (une
;  adresse absolue ferait echouer reloc.py aux origines B et C)
; ============================================================================
        assert  iocs_header-block_top = 022H,'en-tete IOCS hors de +22h'
        assert  block_bottom-bd_objet <= 00C00H,'bloc trop grand : il deborde sur 0BF000h'
        assert  bd_entree-bd_objet = 00C00H,'installateur hors de 0BF000h'
        assert  bd_fin-bd_objet <= 01800H,'objet au-dela du plafond 0BFC00h'
        assert  bd_nom_f-bd_nom <= 5,'nom de device de plus de 5 octets'
        end
