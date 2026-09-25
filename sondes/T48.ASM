; ============================================================================
; T48 -- SONDE : la commande IOCS 48h cree-t-elle vraiment un bloc EN TETE ?
; ============================================================================
; Referentiel PC-E500S SC62015, 03 §7bis : nos installateurs (BASEXT-DRV,
; HISTDRV) compactent par 47h puis inserent le bloc A LA MAIN -- decalage des
; blocs suivants, recalage de (txtbas)/(datbas), remise a zero du drapeau
; [(iocsw)+3Ah]. Or le device 6 porte une commande 48h, block_create_top,
; « creation d'un bloc memoire EN TETE des blocs, propre au PC-E500 ».
;
; CE QUE LA ROM EN DIT (rom83, lu le 2026-09-25, NON eprouve) :
;   0F034Bh est le traitement de 48h. Il fait, dans cet ordre :
;     - controle de place (SUB_F0244, SUB_F02AF) puis Y = Y - 22h ;
;     - refus si le nom existe deja (SUB_F0063 = 41h search_phys) ;
;     - call SUB_F0330 : lit [(iocsw)+03Ah] et EFFACE le bit du lecteur
;       (bit 1 pour S1:, bit 2 pour S2:) -- c'est l'octet que bd_linkbas de
;       BASEXT-DRV remet a zero ;
;     - mv (si),y puis callf 0F01C1h (43h block_transfer) : il DEPLACE la
;       memoire, donc il fait lui-meme le decalage ;
;     - copie d'un gabarit d'en-tete de 22h octets (DB_F041C) dans le bloc.
;   La commande 45h (0F039Eh) est la meme routine SANS le deplacement.
;
; CE QUE CETTE SONDE MESURE, et elle ne fait que cela : appeler 48h une fois,
; sans compactage prealable, et rendre ce que la machine repond. Le programme
; T48.BAS releve la chaine des blocs, (txtbas), (datbas) et le drapeau AVANT
; et APRES, puis affiche le resultat.
;
; Assemblage :
;   xasm2026-4 T48.ASM -OT48.OBJ -L -S -B -K
; Emploi :
;   POKE &BFE03,&1A,&FD,&B,0,&C,0 : CALL &FFFD8   ' reserver 3072 octets
;   LOAD M "X:T48.OBJ"                            ' ou F:
;   RUN "T48.BAS"                                 ' qui fait CALL &BF000
;
; La zone de resultat est HORS du code, en 0BFBF0h, comme les essais de BASEXT :
;   0BFBF0h  3 octets  adresse du bloc cree (Y rendu), 0FFFFFh si refus
;   0BFBF3h  1 octet   code d'erreur rendu dans A, 0 si succes
;   0BFBF4h  1 octet   1 si la retenue etait armee au retour, 0 sinon
; ============================================================================

        include pce500.inc

res_adr:        equ     0BFBF0H         ; hors du module, dans la zone reservee
res_err:        equ     0BFBF3H
res_carry:      equ     0BFBF4H

taille:         equ     000100H         ; 256 octets demandes, en-tete comprise

        org     0BF000H
        pre_on

start:
        mv      y,0FFFFFH               ; zone de resultat en etat « rien »
        mv      [res_adr],y
        mv      a,000H
        mv      [res_err],a
        mv      [res_carry],a

        mvw     (cl),00006H             ; (cl) = 6 device carte memoire, (ch) = 0 slot S1:
        mv      x,nom                   ; X = nom du bloc, 11 caracteres
        mv      y,taille                ; Y = taille voulue
        mv      il,d6_blk_cre_top       ; 48h
        callf   iocs_call
        jrc     echec

        mv      [res_adr],y             ; Y = adresse du bloc cree
        rc                              ; retour propre a BASIC
        retf

echec:
        mv      [res_err],a             ; code d'erreur du device
        mv      a,001H
        mv      [res_carry],a
        rc                              ; la sonde rend TOUJOURS la main proprement
        retf

; Le nom occupe 11 octets, 8 + 3, complete par des espaces -- le format des
; en-tetes de bloc (DRVTEST.BAS lit 11 caracteres en +1).
nom:    db      'T48     SYS'

btm:
        assert  btm-start < 0100H       ; la sonde reste loin de res_adr
        end
