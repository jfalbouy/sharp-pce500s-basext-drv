; ============================================================================
; TRAMF -- RAMFILE NAIT-IL SOUS LES PILOTES ?  POSE D'UN LEURRE EN TETE DE S1:
; ============================================================================
; Lu dans rom83 le 2026-09-27 (referentiel 03 §7bis, « EXTSLOT (1991) ») : le
; pilote MEMORY FILE (E:/F:) cree son bloc RAMFILE par la commande IOCS 48h du
; device 6 (0E4DBBh -> SUB_E4C4E), et 48h cree EN TETE du lecteur. Si c'est
; vrai, INIT "E:" apres l'installation de PLINK/BASEXT/HISTORY glisse RAMFILE
; SOUS eux, et ils montent sans relocation -- le plantage du KILL-sous.
;
; On ne le mesure PAS avec un vrai pilote : s'il bougeait, la machine tomberait.
; Cette sonde pose un LEURRE : un bloc « LEURRE  SYS » d'attribut 25h -- un
; pilote aux yeux de PLINKC, d'EXTSLOT et de BASEXTDR (bits 0Ch) -- mais RELIE
; A RIEN : ni maillon d_link, ni crochet du BASIC. Qu'il monte ou non, aucun
; pointeur ne devient faux. INIT "E:2K" ensuite, et TRAMF.BAS dit qui est
; dessous.
;
; Sequence, dans un seul CALL (le BASIC ne doit pas reprendre la main entre
; deux commandes qui deplacent) :
;   47h condense -> linkbas -> 48h « LEURRE  SYS » -> linkbas
;   -> 41h relit son adresse -> attribut +0Ch <- 25h
; 48h seul donne un bloc VIDE de 22h octets (T483) : c'est assez pour un leurre.
;
; ⚠️ Appel EN MODE DIRECT : le compactage deplace TEXT.BAS.
;
; Zone de resultat (signee, voir T484) :
;   0BFBDFh  1 octet   IDENTIFIANT 0A5H, ecrit en PREMIER
;   0BFBE0h  1 octet   etape : 1=47h 2=48h 4=41h 6=fini (leurre pose)
;   0BFBE1h  1 octet   code d'erreur rendu dans A
;   0BFBE2h  3 octets  adresse du leurre, relue par 41h
;
; Assemblage : xasm2026-4 TRAMF.ASM -OTRAMF.OBJ -L -S -B -K
; ============================================================================

        include pce500.inc

res_id:         equ     0BFBDFH         ; 0A5H = « c'est TRAMF qui a ecrit »
res_etape:      equ     0BFBE0H
res_err:        equ     0BFBE1H
res_adr:        equ     0BFBE2H

        org     0BF000H
        pre_on

start:
        mv      a,0A5H                  ; l'identifiant AVANT tout
        mv      [res_id],a
        mv      a,000H
        mv      [res_etape],a
        mv      [res_err],a
        mv      y,0FFFFFH
        mv      [res_adr],y

; --- etape 1 : 47h condense -------------------------------------------------
        mv      a,001H
        mv      [res_etape],a
        mvw     (cl),00006H             ; device 6, lecteur 0 (S1:)
        mv      il,d6_condense
        callf   iocs_call
        jrc     echec
        call    linkbas

; --- etape 2 : 48h block_create_top : le leurre, vide, en tete --------------
        mv      a,002H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      il,d6_blk_cre_top
        callf   iocs_call
        jrc     echec
        call    linkbas                 ; la chaine a monte de 22h octets

; --- etape 4 : 41h relit l'adresse, puis l'attribut de pilote ---------------
        mv      a,004H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      il,d6_search_phys
        callf   iocs_call
        jrc     echec
        mv      [res_adr],y
        mv      a,025H                  ; device + protege : bits 0Ch non nuls
        mv      [y+00CH],a

        mv      a,006H                  ; leurre pose
        mv      [res_etape],a
        rc
        retf

echec:
        mv      [res_err],a             ; le code AVANT tout autre usage de A
        call    linkbas                 ; meme en erreur : PLINKC fait de meme
        rc                              ; retour propre a BASIC
        retf

; ---------------------------------------------------------------------------
; linkbas -- (txtbas) et (datbas) retrouves par leur nom, puis drapeau a zero.
;            Repris de BASEXTDR.ASM (bd_linkbas), comme T482. Appel proche.
; ---------------------------------------------------------------------------
linkbas:
        mv      x,[baswrk]
        mv      a,072H
        add     x,a
        call    lb_chercher
        jrc     lb_perdu
        mv      (txtbas),y
        call    lb_chercher
        jrc     lb_perdu
        mv      (datbas),y
        mv      a,000H
        mv      [(iocsw)+03AH],a
        ret
lb_perdu:
        reset                           ; comme PLINKC : la memoire est incoherente
lb_chercher:
        mv      (ch),[x++]              ; numero de lecteur, puis X sur le nom
        mv      (cl),006H
        mv      il,041H
        callf   iocs_call
        ret

nom:    db      'LEURRE  SYS'

btm:
        assert  btm-start < 0300H       ; la sonde reste loin de la zone de resultat
        end
