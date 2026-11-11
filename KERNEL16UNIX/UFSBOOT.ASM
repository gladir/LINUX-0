; @author: Sylvain Maltais (support@gladir.com)
; @created: 2026
; @website(https://www.gladir.com/linux-0)
; @abstract(Target: NASM, 8086)
; @description: Amorce UFS1 de LINUX-0 (comme boot1/boot2 de FreeBSD). Elle
;   occupe les 16 premiers secteurs (8 Ko) d'une partition UFS1, zone que le
;   systeme de fichiers reserve a l'amorce (le superbloc est a 8 Ko).
;   - secteur 0 (charge a 0000:7C00 par le MBR, DL = unite, DS:SI = entree
;     de la partition) : lit la geometrie du BIOS et charge les secteurs 1
;     a 15 a 0000:7E00;
;   - secteurs 1 a 15 : lisent le superbloc, l'inode 2 (racine), cherchent
;     "unix" dans le repertoire racine et chargent ce fichier (blocs directs
;     et indirection simple) a 1000:0000, puis lui donnent le controle.
;   Comme avec le secteur d'amorce FAT, le noyau trouve l'unite d'amorce en
;   0000:7C24 et le debut de la partition en 0000:7C1C (champ rempli par
;   l'installateur ou MKIMAGE, sinon pris dans l'entree de la partition).
;   nasm -f bin -o UFSBOOT.BIN UFSBOOT.ASM

        bits 16
        org 7C00h

KSEG    equ 1000h               ; paragraphe de chargement du noyau
SB      equ 0A000h              ; superbloc (2 Ko)
IBUF    equ 0A800h              ; bloc de repertoire (8 Ko au plus)
XBUF    equ 0C800h              ; bloc d'indirection (8 Ko au plus)
INO     equ 0E800h              ; inode courante (128 octets)
SBUF    equ 0EA00h              ; secteur de travail

        jmp short start
        nop
        db 'LINUX-0  '
        times 1Ch-($-$$) db 0
hidden  dd 0                    ; 1Ch debut de la partition (secteurs)
        dd 0
drive   db 80h                  ; 24h unite BIOS d'amorce
        times 3Eh-($-$$) db 0

start:  cli
        xor ax,ax
        mov ss,ax
        mov sp,7C00h
        sti
        cld
        mov ax,[si+8]           ; DS:SI = entree de la partition (MBR)
        mov bx,[si+10]
        xor cx,cx
        mov ds,cx
        mov es,cx
        cmp word [hidden],0
        jne .h
        cmp word [hidden+2],0
        jne .h
        mov [hidden],ax
        mov [hidden+2],bx
.h:     mov [drive],dl
        mov ah,8                ; geometrie du BIOS
        push es
        int 13h
        pop es
        jc .g
        and cx,3Fh
        jz .g
        mov [spt],cx
        mov dl,dh
        xor dh,dh
        inc dx
        mov [heads],dx
.g:     mov si,msgboot
        call print
        mov bx,7E00h            ; secteurs 1 a 15 -> 0000:7E00
        mov ax,1
        xor dx,dx
        mov cx,15
        call readn
        jmp boot2

; DX:AX = secteur relatif a la partition, CX secteurs, ES:BX tampon
; (ES avance de 512 octets par secteur; ES est rendu)
readn:  push es
.n:     push ax
        push dx
        push cx
        call readrel
        pop cx
        pop dx
        pop ax
        add ax,1
        adc dx,0
        mov si,es
        add si,20h
        mov es,si
        loop .n
        pop es
        ret

readrel: add ax,[hidden]
        adc dx,[hidden+2]
        push bx                 ; DX:AX = LBA -> cylindre, tete, secteur
        push ax
        mov ax,dx
        xor dx,dx
        div word [spt]
        mov cx,ax
        pop ax
        div word [spt]
        inc dx
        mov [csec],dl
        mov dx,cx
        div word [heads]
        mov dh,dl
        mov ch,al
        mov cl,ah
        ror cl,1
        ror cl,1
        and cl,0C0h
        or cl,[csec]
        mov dl,[drive]
        pop bx
        mov si,5
.r:     mov ax,0201h
        int 13h
        jnc .ok
        xor ax,ax
        int 13h
        dec si
        jnz .r
        mov si,msgio
        jmp fatal
.ok:    ret

fatal:  call print
.h:     jmp short .h

print:  lodsb
        or al,al
        jz .f
        mov ah,0Eh
        mov bx,7
        int 10h
        jmp short print
.f:     ret

spt     dw 63
heads   dw 16
csec    db 0
msgboot db 'LINUX-0 : amorce UFS',13,10,0
msgio   db 'Erreur de lecture',13,10,0

        times 510-($-$$) db 0
        dw 0AA55h

; ---------------------------------------------------------------------
; secteurs 1 a 15

boot2:  mov bx,SB               ; superbloc : secteurs 16 a 19
        mov ax,16
        xor dx,dx
        mov cx,4
        call readn
        mov si,msgfs
        cmp word [SB+1372],1954h
        jne fatal
        cmp word [SB+1374],1
        jne fatal
        mov ax,[SB+48]          ; taille d'un bloc
        mov cl,9
        shr ax,cl
        mov [spb],ax
        mov ax,2                ; inode 2 : la racine
        call iget
        call lookup
        mov si,msgnok
        or ax,ax
        jz fatal
        call iget
        mov si,msgload
        call print
        call loadfile
        mov si,msgnl
        call print
        mov dl,[drive]
        jmp KSEG:0000h

; fragment DX:AX -> secteur relatif DX:AX
frag2sec: mov cx,[SB+100]       ; fsbtodb
        jcxz .f
.s:     shl ax,1
        rcl dx,1
        loop .s
.f:     ret

; inode AX -> INO
iget:   mov byte [xok],0
        xor dx,dx
        div word [SB+184]       ; ipg : AX = groupe, DX = rang
        push dx
        mul word [SB+188]       ; fpg
        add ax,[SB+16]          ; iblkno
        adc dx,0
        mov [t0],ax
        mov [t1],dx
        pop ax
        xor dx,dx
        div word [SB+120]       ; inopb : AX = bloc, DX = rang dans le bloc
        push dx
        mul word [SB+56]        ; frag
        add ax,[t0]
        adc dx,[t1]
        call frag2sec
        pop cx
        push cx
        shr cx,1
        shr cx,1                ; 4 inodes de 128 octets par secteur
        add ax,cx
        adc dx,0
        mov bx,SBUF
        mov cx,1
        call readn
        pop si
        and si,3
        mov cl,7
        shl si,cl
        add si,SBUF
        mov di,INO
        mov cx,64
        rep movsw
        ret

; bloc logique AX de l'inode courante -> fragment DX:AX
bmap:   cmp ax,12
        jae .ind
        mov si,ax
        shl si,1
        shl si,1
        mov ax,[INO+40+si]
        mov dx,[INO+42+si]
        ret
.ind:   sub ax,12
        push ax
        cmp byte [xok],1
        je .x
        mov ax,[INO+88]         ; bloc d'indirection simple
        mov dx,[INO+90]
        call frag2sec
        mov bx,XBUF
        mov cx,[spb]
        call readn
        mov byte [xok],1
.x:     pop si
        shl si,1
        shl si,1
        mov ax,[XBUF+si]
        mov dx,[XBUF+si+2]
        ret

; repertoire courant (INO) : inode de "unix" dans AX, ou 0
lookup: mov word [lbn],0
.blk:   mov ax,[lbn]
        mul word [SB+48]
        cmp dx,[INO+10]
        jb .in
        ja .no
        cmp ax,[INO+8]
        jae .no
.in:    mov cx,[INO+8]          ; octets du repertoire dans ce bloc
        sub cx,ax
        cmp cx,[SB+48]
        jbe .c
        mov cx,[SB+48]
.c:     add cx,IBUF
        mov [dend],cx
        mov ax,[lbn]
        call bmap
        mov cx,ax
        or cx,dx
        jz .next
        call frag2sec
        mov bx,IBUF
        mov cx,[spb]
        call readn
        mov si,IBUF
.ent:   cmp si,[dend]
        jae .next
        mov ax,[si+4]           ; d_reclen
        or ax,ax
        jz .next
        cmp byte [si+7],4       ; d_namlen
        jne .nx
        cmp word [si+8],'un'
        jne .nx
        cmp word [si+10],'ix'
        jne .nx
        mov ax,[si]
        or ax,ax
        jnz .ret
.nx:    add si,[si+4]
        jmp short .ent
.next:  inc word [lbn]
        jmp .blk
.no:    xor ax,ax
.ret:   ret

; fichier de l'inode courante -> KSEG:0000
loadfile: mov ax,[INO+8]
        mov dx,[INO+10]
        add ax,[SB+48]
        adc dx,0
        sub ax,1
        sbb dx,0
        div word [SB+48]
        mov [nblk],ax
        mov word [lbn],0
        mov word [dseg],KSEG
.b:     mov ax,[lbn]
        cmp ax,[nblk]
        jae .f
        call bmap
        call frag2sec
        push es
        mov es,[dseg]
        xor bx,bx
        mov cx,[spb]
        call readn
        pop es
        mov ax,[SB+48]
        mov cl,4
        shr ax,cl
        add [dseg],ax
        inc word [lbn]
        mov si,msgdot
        call print
        jmp short .b
.f:     ret

spb     dw 16
t0      dw 0
t1      dw 0
lbn     dw 0
nblk    dw 0
dseg    dw 0
dend    dw 0
xok     db 0
msgfs   db 'Pas de systeme UFS1',13,10,0
msgnok  db '/unix introuvable',13,10,0
msgload db 'Chargement de /unix',0
msgdot  db '.',0
msgnl   db 13,10,0

        times 8192-($-$$) db 0
