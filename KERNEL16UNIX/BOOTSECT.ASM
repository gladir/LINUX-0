; @author: Sylvain Maltais (support@gladir.com)
; @created: 2026
; @website(https://www.gladir.com/linux-0)
; @abstract(Target: NASM, 8086)
; @description: Secteur d'amorce FAT12/FAT16 de LINUX-0. Cherche le fichier
;   UNIX (noyau produit par "LPC /K KERNEL16UNIX\UNIX.PAS" puis renomme) dans le
;   repertoire racine, le charge a 1000:0000 en suivant la chaine de la FAT et
;   lui donne le controle. Le numero de l'unite d'amorce est conserve dans le
;   BPB (0000:7C24), que le noyau relit; le champ "secteurs caches" (7C1C)
;   donne le debut de la partition.
;   nasm -f bin -o BOOTSECT.BIN BOOTSECT.ASM

        bits 16
        org 7C00h

KSEG    equ 1000h               ; paragraphe de chargement du noyau
BUF     equ 0500h               ; tampon 2 secteurs (repertoire, FAT)
VARS    equ 0900h
rootlba equ VARS+0              ; 1er secteur du repertoire racine
rootsec equ VARS+2              ; nombre de secteurs du repertoire racine
datalba equ VARS+4              ; 1er secteur de la zone de donnees
fatsec  equ VARS+6              ; secteur de FAT dans BUF (FFFFh = aucun)

        jmp short start
        nop
oem     db 'LINUX-0  '
bps     dw 512                  ; 0Bh octets par secteur
spc     db 1                    ; 0Dh secteurs par cluster
rsv     dw 1                    ; 0Eh secteurs reserves
nfats   db 2                    ; 10h nombre de FAT
rootent dw 224                  ; 11h entrees du repertoire racine
totsec  dw 2880                 ; 13h
media   db 0F0h                 ; 15h
spf     dw 9                    ; 16h secteurs par FAT
spt     dw 18                   ; 18h secteurs par piste
heads   dw 2                    ; 1Ah nombre de tetes
hidden  dd 0                    ; 1Ch secteurs caches (debut de partition)
totsec32 dd 0                   ; 20h
drive   db 0                    ; 24h unite BIOS
        db 0
        db 29h                  ; 26h signature du BPB etendu
        dd 20260101h            ; 27h numero de serie
        db 'LINUX-0     '        ; 2Bh nom de volume
fstype  db 'FAT12   '           ; 36h

start:  cli
        xor ax,ax
        mov ds,ax
        mov es,ax
        mov ss,ax
        mov sp,7C00h
        sti
        cld
        mov [drive],dl
        mov word [fatsec],0FFFFh
        mov al,[nfats]
        cbw
        mul word [spf]
        add ax,[rsv]
        mov [rootlba],ax
        mov bx,[rootent]
        mov cl,4
        shr bx,cl
        mov [rootsec],bx
        add ax,bx
        mov [datalba],ax
        mov ax,[rootlba]
dirsec: mov bx,BUF
        call readsec
        mov di,bx
        mov dx,16
dirent: mov si,kname
        mov cx,11
        push di
        repe cmpsb
        pop di
        je found
        add di,32
        dec dx
        jnz dirent
        inc ax
        dec word [rootsec]
        jnz dirsec
        mov si,msgnf
        jmp fatal

found:  mov ax,[di+1Ah]         ; premier cluster
        mov bx,KSEG
        mov es,bx
clus:   push ax
        dec ax
        dec ax
        mov cl,[spc]
        xor ch,ch
        mul cx
        add ax,[datalba]
csec:   xor bx,bx
        call readsec
        mov bx,es
        add bx,20h
        mov es,bx
        inc ax
        loop csec
        pop ax
        call nextcl
        cmp byte [fstype+4],'6'
        je f16
        cmp ax,0FF8h
        jmp short ftst
f16:    cmp ax,0FFF8h
ftst:   jb clus
        mov dl,[drive]
        jmp KSEG:0000h

; AX = cluster -> AX = cluster suivant
nextcl: push es
        push cx
        xor dx,dx
        mov es,dx
        mov di,ax               ; cluster demande (parite pour FAT12)
        mov bx,ax
        cmp byte [fstype+4],'6'
        je n16
        shr bx,1
        add ax,bx               ; FAT12 : decalage = cluster*3/2
        jmp short noff
n16:    shl ax,1                ; FAT16 : decalage = cluster*2
        rcl dx,1
noff:   mov cx,512
        div cx                  ; AX = secteur dans la FAT, DX = decalage
        add ax,[rsv]
        mov si,dx
        cmp ax,[fatsec]
        je nhave
        mov [fatsec],ax
        mov bx,BUF
        call readsec
        inc ax
        add bx,512
        call readsec
nhave:  mov ax,[BUF+si]
        cmp byte [fstype+4],'6'
        je ndone
        test di,1
        jz neven
        mov cl,4
        shr ax,cl
neven:  and ax,0FFFh
ndone:  pop cx
        pop es
        ret

; AX = secteur relatif a la partition, ES:BX = destination
readsec: push ax
        push cx
        push dx
        push si
        xor dx,dx
        add ax,[hidden]
        adc dx,[hidden+2]
        div word [spt]
        mov cx,dx
        inc cx                  ; secteur 1..spt
        xor dx,dx
        div word [heads]        ; AX = cylindre, DX = tete
        mov dh,dl
        mov ch,al
        ror ah,1
        ror ah,1
        or cl,ah
        mov dl,[drive]
        mov si,4
rretry: mov ax,0201h
        int 13h
        jnc rok
        xor ax,ax
        int 13h
        dec si
        jnz rretry
        mov si,msgerr
        jmp short fatal
rok:    pop si
        pop dx
        pop cx
        pop ax
        ret

fatal:  lodsb
        or al,al
        jz halt
        mov ah,0Eh
        mov bx,7
        int 10h
        jmp short fatal
halt:   xor ax,ax
        int 16h
        int 19h

kname   db 'UNIX       '
msgnf   db 'UNIX introuvable',13,10,0
msgerr  db 'Erreur disque',13,10,0

        times 510-($-$$) db 0
        dw 0AA55h
