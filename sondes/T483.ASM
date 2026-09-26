; ============================================================================
; T483 -- 47h PUIS 48h SEULS : QUELLE TAILLE A LE BLOC CREE ?
; ============================================================================
; T482 a mesure (2026-09-25) que la suite 47h -> 48h -> 42h passe entierement
; et donne un bloc de 2873 octets = 2839 + 22h. Mais elle enchainait les deux
; commandes : impossible de dire LAQUELLE a donne sa taille au bloc.
;
;   - le carnet dit de 48h « (ch) = slot, X = nom, Y = taille » ;
;   - la lecture de la ROM dit le contraire : en 0F0351h, « call SUB_F0244 »
;     ECRASE Y par l'espace libre, la chaine n'est decalee que de 22h octets
;     (0F0394h : « mv a,022h / add y,a ») et le gabarit copie (DB_F041C) porte
;     une taille de 22h. 48h creerait donc un bloc VIDE.
;
; Cette sonde s'arrete apres 48h et LIT LA TAILLE DU BLOC dans son en-tete
; (champ +11h, comme BLOCS.BAS). Une minute de machine pour trancher.
;
;   taille lue = 22h (34)    -> 48h cree un bloc vide, le carnet est a corriger
;   taille lue = 0B39h (2873) -> 48h prend bien Y, ma lecture de la ROM est fausse
;   autre valeur              -> a ecrire telle quelle, et a comprendre
;
; ⚠️ MEME PRECAUTION QUE T482 : le compactage deplace TEXT.BAS et DATA.BAS, et
;    la ROM ne recale rien -- d'ou linkbas derriere chaque commande qui deplace,
;    erreurs comprises. Et l'appel se fait EN MODE DIRECT.
;
; ⛔ PLUS DE SIGNATURE. T482 a montre qu'elle n'arrivait pas a destination, sans
;    qu'on sache pourquoi, alors que les valeurs qui la precedent y etaient.
;    L'octet d'ETAPE fait le meme travail avec une variable de moins : 0 = sonde
;    pas appelee, 1..5 = appelee. Le programme BASIC le remet a zero apres l'avoir
;    lu, de sorte que ce qu'il affiche vient toujours du dernier appel.
;
; Zone de resultat :
;   0BFBE0h  1 octet   etape : 1=47h 2=48h 3=41h 5=fini
;   0BFBE1h  1 octet   code d'erreur rendu dans A
;   0BFBE2h  3 octets  Y rendu par 48h
;   0BFBE5h  3 octets  adresse relue par 41h
;   0BFBE8h  3 octets  TAILLE du bloc, lue dans son en-tete (+11h)
;
; Assemblage : xasm2026-4 T483.ASM -OT483.OBJ -L -S -B -K
; ============================================================================

        include pce500.inc

res_id:         equ     0BFBDFH         ; 083H = « c'est T483 qui a ecrit »
res_etape:      equ     0BFBE0H
res_err:        equ     0BFBE1H
res_adr48:      equ     0BFBE2H
res_adr41:      equ     0BFBE5H
res_taille:     equ     0BFBE8H

demande:        equ     000B17H         ; 2839 octets, comme T482

        org     0BF000H
        pre_on

start:
        mv      a,083H                  ; T483 signe ses octets (voir T484.ASM)
        mv      [res_id],a
        mv      a,000H
        mv      [res_etape],a
        mv      [res_err],a
        mv      y,0FFFFFH
        mv      [res_adr48],y
        mv      [res_adr41],y
        mv      [res_taille],y

; --- etape 1 : 47h condense -------------------------------------------------
        mv      a,001H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      il,d6_condense
        callf   iocs_call
        jrc     echec
        call    linkbas

; --- etape 2 : 48h block_create_top, ET RIEN D'AUTRE ------------------------
        mv      a,002H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      y,demande
        mv      il,d6_blk_cre_top
        callf   iocs_call
        jrc     echec
        mv      [res_adr48],y
        call    linkbas

; --- etape 3 : relire l'adresse, puis la TAILLE dans l'en-tete --------------
        mv      a,003H
        mv      [res_etape],a
        mvw     (cl),00006H
        mv      x,nom
        mv      il,d6_search_phys
        callf   iocs_call
        jrc     echec
        mv      [res_adr41],y

        mv      a,011H                  ; champ « taille du bloc » de l'en-tete
        add     y,a
        mv      y,[y]                   ; les 3 octets de la taille
        mv      [res_taille],y

        mv      a,005H                  ; sequence complete
        mv      [res_etape],a
        jr      fini

echec:
        mv      [res_err],a
        call    linkbas

fini:
        rc
        retf

; ---------------------------------------------------------------------------
; linkbas -- repris de BASEXTDR.ASM (bd_linkbas). Appel proche.
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
        reset
lb_chercher:
        mv      (ch),[x++]
        mv      (cl),006H
        mv      il,041H
        callf   iocs_call
        ret

nom:    db      'T48     SYS'

btm:
        assert  btm-start < 0300H
        end
