; ============================================================================
; reloc.inc -- GENERE par outils/reloc.py, NE PAS EDITER
; source BASEXTDR.ASM, zone 0BE400h-0BEF16h (2839 octets), 126 champs de 3 octets, 29 de 2
; verifie par assemblage a trois origines
; format Kon/A62 (celui de PLINKC) : delta depuis le champ precedent, le
; premier depuis le DEBUT DE LA ZONE ; bit 080h = 3 octets ; 07Eh = delta
; long sur 2 octets ; 0FFh = fin
; ============================================================================
rel_table:
        db      0A7H,00CH,08CH,08AH,087H,089H,0A0H,009H,005H,090H,087H,084H
        db      087H,0FEH,0EDH,000H,091H,090H,0B1H,0ABH,087H,088H,093H,088H
        db      08AH,08AH,08AH,099H,098H,08AH,018H,025H,006H,025H,096H,004H
        db      087H,0A4H,054H,091H,091H,098H,0A3H,08AH,0B3H,08EH,004H,08CH
        db      088H,08AH,08AH,08CH,096H,08CH,09DH,09FH,0B1H,095H,086H,084H
        db      088H,08EH,086H,08CH,004H,08CH,088H,08AH,08AH,08CH,096H,08CH
        db      0A1H,099H,086H,09BH,08AH,086H,084H,090H,0A0H,08AH,086H,088H
        db      088H,088H,087H,09BH,088H,08AH,08AH,089H,087H,086H,004H,00FH
        db      085H,004H,011H,00BH,085H,084H,08AH,09CH,00CH,005H,087H,08EH
        db      0B1H,08EH,088H,084H,084H,09BH,086H,099H,02CH,016H,006H,094H
        db      0DFH,004H,089H,08BH,084H,084H,092H,006H,083H,087H,006H,083H
        db      086H,011H,036H,005H,088H,084H,084H,008H,005H,085H,08CH,0F4H
        db      084H,084H,084H,084H,084H,084H,084H,084H,084H,084H,084H,084H
        db      084H,0FFH
rel_table_end:
        end
