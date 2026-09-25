; ============================================================================
; T484 -- OU (txtbas) DECROCHE-T-IL ? LA TRACE DE linkbas, PAS A PAS
; ============================================================================
; T482 a laisse une anomalie que rien n'explique : apres la sequence complete,
; (datbas) designait le bon bloc et (txtbas) l'ANCIEN -- TXT BD852 alors que
; TEXT.BAS etait en 80CF5. Or linkbas ecrit les deux a la suite, et il a
; forcement tourne : l'etape 6 vient apres lui, et une recherche en echec serait
; partie sur « reset ».
;
; C'est le geste meme dont depend un installateur : tant qu'on ne sait pas
; pourquoi, on ne touche pas au sien. Cette sonde refait la sequence de T482 en
; ECRIVANT CE QU'ELLE VOIT, a chaque etape :
;
;   - (txtbas) et (datbas) a l'entree, avant toute commande ;
;   - pour CHACUN des trois linkbas : la valeur rendue par la 1re recherche 41h,
;     celle rendue par la 2e, puis (txtbas) et (datbas) une fois ecrits ;
;   - (txtbas) et (datbas) a la sortie.
;
; Seize valeurs de 3 octets, dans l'ordre. Elles diront si la recherche rend une
; adresse fausse, si l'ecriture n'a pas lieu, ou si quelque chose ecrase
; (txtbas) APRES coup -- trois causes que T482 ne savait pas distinguer.
;
; ⚠️ Appel EN MODE DIRECT, comme T482 : le compactage deplace TEXT.BAS.
;
; Zone de resultat :
;   0BFBE0h  1 octet   etape (0 = sonde pas appelee) : 1=47h 2=48h 3=42h(a=0)
;                      5=42h(a=1) 4=41h 6=fini
;   0BFBE1h  1 octet   code d'erreur rendu dans A
;   0BFB7Dh  3 octets  pointeur d'ecriture de la trace (interne a la sonde)
;   0BFB80h  48 octets LA TRACE : 16 valeurs de 3 octets, dans l'ordre ci-dessus
;
; Assemblage : xasm2026-4 T484.ASM -OT484.OBJ -L -S -B -K
; ============================================================================

        include pce500.inc

res_etape:      equ     0BFBE0H
res_err:        equ     0BFBE1H
tr_ptr:         equ     0BFB7DH
tr_base:        equ     0BFB80H

demande:        equ     000B17H         ; 2839 octets, comme T482

        org     0BF000H
        pre_on

start:
        mv      a,000H
        mv      [res_etape],a
        mv      [res_err],a
        mv      y,tr_base               ; la trace repart du debut a chaque appel
        mv      [tr_ptr],y
        call    tr_pair                 ; (1)(2) l'etat d'entree

; --- etape 1 : 47h condense -------------------------------------------------
        mv      a,001H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      il,d6_condense
        callf   iocs_call
        jrc     echec
        call    linkbas                 ; (3)(4)(5)(6)

; --- etape 2 : 48h block_create_top -----------------------------------------
        mv      a,002H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      y,demande
        mv      il,d6_blk_cre_top
        callf   iocs_call
        jrc     echec
        call    linkbas                 ; (7)(8)(9)(10)

; --- etape 3 : 42h block_resize, a=0 puis a=1 -------------------------------
        mv      a,003H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      y,demande
        mv      a,000H
        mv      il,d6_block_resize
        callf   iocs_call
        jrnc    t42_ok

        mv      [res_err],a
        mv      a,005H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      y,demande
        mv      a,001H
        mv      il,d6_block_resize
        callf   iocs_call
        jrc     echec

t42_ok:
        call    linkbas                 ; (11)(12)(13)(14)

; --- etape 4 : relecture 41h, pour memoire ----------------------------------
        mv      a,004H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      il,d6_search_phys
        callf   iocs_call
        jrc     echec

        mv      a,006H
        mv      [res_etape],a
        jr      fini

echec:
        mv      [res_err],a
        call    linkbas

fini:
        call    tr_pair                 ; (15)(16) l'etat de sortie
        rc
        retf

; ---------------------------------------------------------------------------
; linkbas -- celui de BASEXTDR.ASM, AUGMENTE DE LA TRACE et de rien d'autre :
;            l'ordre des instructions, les registres et les chemins d'erreur
;            sont ceux du pilote, sans quoi la mesure ne vaudrait pas pour lui.
; ---------------------------------------------------------------------------
linkbas:
        mv      x,[baswrk]
        mv      a,072H
        add     x,a
        call    lb_chercher
        jrc     lb_perdu
        pushu   x                       ; tr_y detruit X, que l'idiome fait avancer
        call    tr_y                    ; ce que la 1re recherche a rendu
        popu    x
        mv      (txtbas),y
        call    lb_chercher
        jrc     lb_perdu
        pushu   x
        call    tr_y                    ; ce que la 2e recherche a rendu
        popu    x
        mv      (datbas),y
        mv      a,000H
        mv      [(iocsw)+03AH],a
        call    tr_pair                 ; (txtbas) et (datbas) tels qu'ils sont
        ret
lb_perdu:
        reset
lb_chercher:
        mv      (ch),[x++]
        mv      (cl),006H
        mv      il,041H
        callf   iocs_call
        ret

; ---------------------------------------------------------------------------
; tr_y    -- ajoute Y a la trace. Detruit A et X ; PRESERVE Y.
; tr_pair -- ajoute (txtbas) puis (datbas). Detruit A, X et Y.
; ---------------------------------------------------------------------------
tr_y:
        mv      x,[tr_ptr]
        mv      [x],y
        mv      a,003H
        add     x,a
        mv      [tr_ptr],x
        ret

tr_pair:
        mv      y,(txtbas)
        call    tr_y
        mv      y,(datbas)
        call    tr_y
        ret

nom:    db      'T48     SYS'

btm:
        assert  btm-start < 0300H
        end
