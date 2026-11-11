; @author: Sylvain Maltais (support@gladir.com)
; @created: 2026
; @website(https://www.gladir.com/linux-0)
; @abstract(Target: NASM, 8086)
; @description: Secteur de partition (MBR) du disque dur de LINUX-0. Se
;   recopie a 0000:0600, cherche la partition active et charge son secteur
;   d'amorce a 0000:7C00 (DL = unite, DS:SI = entree de la partition).
;   nasm -f bin -o MBR.BIN MBR.ASM

        bits 16
        org 0600h

        cli
        xor ax,ax
        mov ss,ax
        mov sp,7C00h
        mov ds,ax
        mov es,ax
        sti
        cld
        mov si,7C00h
        mov di,0600h
        mov cx,256
        rep movsw
        jmp 0:go
go:     mov si,07BEh            ; table des partitions
        mov cx,4
find:   cmp byte [si],80h
        je active
        add si,16
        loop find
        mov si,msgnone
        jmp short fatal
active: mov bp,5
again:  mov dh,[si+1]           ; tete
        mov cx,[si+2]           ; secteur / cylindre
        mov bx,7C00h
        mov ax,0201h
        int 13h
        jnc loaded
        xor ax,ax
        int 13h
        dec bp
        jnz again
        mov si,msgerr
        jmp short fatal
loaded: cmp word [7DFEh],0AA55h
        jne nosys
        jmp 0:7C00h
nosys:  mov si,msgsys
fatal:  lodsb
        or al,al
        jz halt
        mov ah,0Eh
        mov bx,7
        int 10h
        jmp short fatal
halt:   jmp short halt

msgnone db 'Aucune partition active',13,10,0
msgerr  db 'Erreur de lecture',13,10,0
msgsys  db 'Partition non amorcable',13,10,0

        times 446-($-$$) db 0
        times 64 db 0           ; table des partitions (remplie par MKIMAGE)
        dw 0AA55h
