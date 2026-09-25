; ============================================================================
; T48 v2 -- LA VOIE ROM COMPLETE : 47h condense -> 48h cre_top -> 42h resize
; ============================================================================
; La v1 a mesure (2026-09-25, PC-E500S reel) que 48h REFUSE, erreur 0Ch, tant
; que la chaine est jointive : il exige de la place APRES la chaine, et il n'y
; en a jamais -- DATA.BAS la detient toute. 47h condense la rend. Cette sonde
; enchaine donc les trois commandes que la ROM offre, et regarde si elles font
; le travail que notre installateur fait a la main.
;
; ⛔ LE COMPACTAGE DEPLACE TEXT.BAS ET DATA.BAS, ET LA ROM NE RECALE RIEN.
;    47h (0F0A19h) appelle 42h deux fois par bloc puis SUB_F029D, qui ne met a
;    jour que [0BFC1Bh] ; il n'efface meme pas le bit du lecteur de
;    [(iocsw)+3Ah], contrairement a 48h (0F0330h). Apres un compactage nu,
;    (txtbas) et (datbas) designent donc l'ancienne place des blocs du BASIC.
;    D'ou la regle de PLINKC, reprise ici : APPELER linkbas DERRIERE CHAQUE
;    COMMANDE QUI DEPLACE, SUR TOUS LES CHEMINS, ERREURS COMPRISES. C'est la
;    raison d'etre de cette sonde : la sequence ne peut pas s'essayer depuis le
;    BASIC, qui reprendrait la main entre deux commandes avec des pointeurs faux.
;
; ⚠️ A APPELER EN MODE DIRECT, jamais depuis un programme : le programme vit
;    dans TEXT.BAS, que le compactage deplace sous ses pieds.
;
; linkbas est repris mot pour mot de BASEXTDR.ASM (bd_linkbas) : les noms des
; deux blocs du BASIC sont ranges en [baswrk]+72h, chacun precede de son numero
; de lecteur ; 41h search_phys rend l'adresse et avance X sur l'entree suivante.
;
; Zone de resultat, hors du code, dans la zone reservee :
;   0BFBE0h  1 octet   derniere etape atteinte : 1=47h 2=48h 3=42h(a=0)
;                      5=42h(a=1) 4=41h relecture, 6=fini
;   0BFBE1h  1 octet   code d'erreur rendu dans A
;   0BFBE2h  3 octets  Y rendu par 48h : l'adresse du bloc cree
;   0BFBE5h  3 octets  adresse du bloc apres 42h, relue par 41h
;   0BFBE8h  3 octets  Y rendu par 42h (taille possible, s'il refuse)
;   0BFBEBh  3 octets  SIGNATURE 'T42', ecrite en dernier (voir T48.ASM)
;
; Assemblage : xasm2026-4 T482.ASM -OT482.OBJ -L -S -B -K
; ============================================================================

        include pce500.inc

res_etape:      equ     0BFBE0H
res_err:        equ     0BFBE1H
res_adr48:      equ     0BFBE2H
res_adr42:      equ     0BFBE5H
res_y42:        equ     0BFBE8H
res_sig:        equ     0BFBEBH

taille:         equ     000B17H         ; 2839 octets : la taille du bloc de BASEXT-DRV

        org     0BF000H
        pre_on

start:
        mv      a,000H
        mv      [res_etape],a
        mv      [res_err],a
        mv      y,0FFFFFH
        mv      [res_adr48],y
        mv      [res_adr42],y
        mv      [res_y42],y

; --- etape 1 : 47h condense -------------------------------------------------
        mv      a,001H
        mv      [res_etape],a
        mvw     (cl),00006H             ; device 6, lecteur 0 (S1:)
        mv      il,d6_condense
        callf   iocs_call
        jrc     echec
        call    linkbas                 ; il a deplace TEXT.BAS et DATA.BAS

; --- etape 2 : 48h block_create_top -----------------------------------------
        mv      a,002H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      y,taille
        mv      il,d6_blk_cre_top
        callf   iocs_call
        jrc     echec
        mv      [res_adr48],y           ; adresse du bloc cree
        call    linkbas                 ; il a decale la chaine de 22h octets

; --- etape 3 : 42h block_resize, d'abord avec a=0 ---------------------------
; Le carnet : « a = numero de pointeur de zone libre 0/1, X = nom, Y = taille
; demandee ; erreur a = 000h carte protegee, 005h bloc protege, 00Ch memoire
; insuffisante, Y = taille possible ». Lequel des deux pointeurs fait grandir
; un bloc n'est pas etabli : on essaie 0, puis 1.
        mv      a,003H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      y,taille
        mv      a,000H                  ; pointeur de zone libre 0
        mv      il,d6_block_resize
        callf   iocs_call
        jrnc    t42_ok

        mv      [res_y42],y             ; ce que 42h dit possible
        mv      [res_err],a
        mv      a,005H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      y,taille
        mv      a,001H                  ; pointeur de zone libre 1
        mv      il,d6_block_resize
        callf   iocs_call
        jrc     echec

t42_ok:
        mv      [res_y42],y
        call    linkbas                 ; il a decale les blocs suivants

; --- etape 4 : relire l'adresse du bloc par 41h -----------------------------
        mv      a,004H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      il,d6_search_phys
        callf   iocs_call
        jrc     echec
        mv      [res_adr42],y

        mv      a,006H                  ; sequence complete
        mv      [res_etape],a
        jr      fini

echec:
        mv      [res_err],a             ; le code AVANT tout autre usage de A
        call    linkbas                 ; meme en erreur : PLINKC fait de meme

fini:
        mv      x,sig
        mv      y,res_sig
        mv      il,003H
sig_cp: mv      a,[x++]
        mv      [y++],a
        dec     il
        jrnz    sig_cp
        rc                              ; retour propre a BASIC
        retf

; ---------------------------------------------------------------------------
; linkbas -- (txtbas) et (datbas) retrouves par leur nom, puis drapeau a zero.
;            Repris de BASEXTDR.ASM (bd_linkbas). Appel proche.
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

nom:    db      'T48     SYS'
sig:    db      'T42'

btm:
        assert  btm-start < 0300H       ; la sonde reste loin de res_etape
        end
