; ============================================================================
; TS1T -- s1_tail (0BFC1Bh) SUIT-IL LA VRAIE FIN DE CHAINE ?  UN INSTANTANE
; ============================================================================
; s1_tail est la fin de la chaine des blocs de S1: + 1. La ROM la tient a jour
; dans SUB_F029D, que seules appellent les commandes du device 6 qui changent la
; chaine (42h, 45h, 46h, 47h, 48h). Elle la compare a s1_btm en 0E0571h,
; vraisemblablement pour qu'une reservation ne morde pas sur la chaine.
;
; Nos installateurs (et PLINKC, et EXTSLOT) compactent par 47h -- qui la met a
; jour -- puis MONTENT les blocs a la main, de la taille du pilote, sans la
; toucher. Question : juste apres, s1_tail est-elle en retard de cette taille ?
; Et qui la rattrape ?
;
; ⛔ LE PIEGE DE LA MESURE (2026-09-26) : lancer un programme BASIC fait grandir
;    DATA.BAS par 42h, donc appelle SUB_F029D, donc CORRIGE s1_tail. Un releve en
;    BASIC effacerait ce qu'il cherche. D'ou cette sonde : un CALL en mode direct
;    ne cree aucune variable, et l'instantane fige FIN, s1_tail et s1_btm AU MEME
;    INSTANT. TS1T.BAS ne fait que relire les instantanes, plus tard.
;
; Chaque appel ajoute un instantane (4 au plus). La serie repart de zero des que
; l'identifiant n'est plus le sien (autre sonde, ou POKE &BFBDF,0).
;
; Zone de resultat (signee, voir T484) :
;   0BFBDFh  1 octet   IDENTIFIANT 0A6H
;   0BFBE0h  1 octet   nombre d'instantanes (0..4)
;   0BFB80h  4 x 9     par instantane : FIN (1er octet hors chaine, 3 o),
;                      [s1_tail] (3 o), [s1_btm] (3 o). En phase : s1_tail = FIN + 1
;
; Chargee en 0BF800h : BASEXTDR occupe 0BE400h-0BF5B7h dans la meme reservation
; de 6144 octets, et les deux doivent etre en memoire avant l'installation.
;
; Assemblage : xasm2026-4 TS1T.ASM -OTS1T.OBJ -L -S -B -K
; ============================================================================

        include pce500.inc

res_id:         equ     0BFBDFH         ; 0A6H = « c'est TS1T qui a ecrit »
res_n:          equ     0BFBE0H
res_tab:        equ     0BFB80H

        org     0BF800H
        pre_on

start:
        mv      a,[res_id]
        cmp     a,0A6H
        jrz     suite
        mv      a,0A6H                  ; nouvelle serie
        mv      [res_id],a
        mv      a,000H
        mv      [res_n],a
suite:
        mv      a,[res_n]
        cmp     a,004H
        jrnc    plein                   ; quatre instantanes : on n'ecrase rien

        mv      y,res_tab               ; Y = res_tab + 9 * n
        mv      il,009H
rang:   cmp     a,000H
        jrz     rang_ok
        add     y,il
        sub     a,001H
        jr      rang
rang_ok:
        pushu   y                       ; destination de l'instantane

; --- la vraie fin de chaine : meme parcours que SUB_F0278, SANS y ecrire ----
        mv      y,[s1_top]
        mv      x,[y+012H]
        add     y,x
parc:   mv      a,[y]
        cmp     a,0FBH
        jrnz    fin
        mv      x,[y+011H]              ; taille du bloc
        inc     x
        dec     x
        jrz     fin                     ; taille nulle : chaine abimee, on s'arrete
        add     y,x
        jrnc    parc
fin:
        popu    x
        mv      [x++],y                 ; FIN
        mv      y,[s1_tail]
        mv      [x++],y                 ; s1_tail
        mv      y,[s1_btm]
        mv      [x++],y                 ; s1_btm

        mv      a,[res_n]
        add     a,001H
        mv      [res_n],a
plein:
        rc                              ; retour propre a BASIC
        retf

btm:
        assert  res_tab+4*9 <= res_id   ; les instantanes n'atteignent pas l'identifiant
        assert  btm < res_tab           ; la sonde reste sous sa zone de resultat
        end
