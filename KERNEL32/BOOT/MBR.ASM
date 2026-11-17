; @author: Sylvain Maltais (support@gladir.com)
; @created: 2026
; @website(https://www.gladir.com/linux-0)
; @abstract(Target: NASM, 80386)
; @description: Secteur de partition (MBR) de KERNEL32. Il reste a 0000:7C00,
;   cherche la partition active, verifie que le chargeur (stage2, secteurs
;   consecutifs apres le MBR, comme GRUB) tient avant elle, le charge a
;   0000:8000 (INT 13h extensions AH=42h, repli CHS AH=02h) puis lui donne la
;   main : DL = unite BIOS, DS:SI = entree de la partition active dans la
;   table (0000:7DBE...). Les 4 champs de parametres (offsets 3 a 8) sont
;   remplis par MKIMAGE : LBA du premier secteur du chargeur (defaut 1) et
;   nombre de secteurs du chargeur.
;   nasm -f bin -o MBR.BIN MBR.ASM

        bits 16
        cpu 386
        org 7C00h

S2ADDR  equ 8000h               ; adresse de chargement du chargeur

        jmp short start         ; 00h
        nop                     ; 02h
s2lba   dd 1                    ; 03h LBA du chargeur (rempli par MKIMAGE)
s2cnt   dw 0                    ; 07h nombre de secteurs (rempli par MKIMAGE)
drive   db 80h                  ; 09h unite d'amorce
spt     dw 63                   ; 0Ah secteurs par piste (BIOS)
heads   dw 255                  ; 0Ch tetes (BIOS)
useext  db 0                    ; 0Eh 0 = auto, 1 = extensions, 2 = CHS force

dap     dw 16, 1                ; DAP : taille, nombre de secteurs
dapofs  dw 0, 0                 ;       offset, segment
daplba  dd 0, 0                 ;       LBA 64 bits

start:  cli
        xor ax,ax
        mov ds,ax
        mov es,ax
        mov ss,ax
        mov sp,7C00h
        sti
        cld
        mov [drive],dl
        ; partition active
        mov si,7DBEh
        mov cx,4
find:   cmp byte [si],80h
        je active
        add si,16
        loop find
        mov si,msgnone
        jmp fatal
active: push si
        ; le chargeur doit tenir entre le MBR et la partition
        mov ax,[s2cnt]
        or ax,ax
        jz nostage
        movzx eax,ax
        add eax,[s2lba]
        cmp eax,[si+8]
        ja nospace
        ; extensions INT 13h ?
        cmp byte [useext],2     ; 2 : CHS impose (essais)
        je chs
        mov dl,[drive]
        mov ah,41h
        mov bx,55AAh
        int 13h
        jc chs
        cmp bx,0AA55h
        jne chs
        test cl,1
        jz chs
        mov byte [useext],1
        jmp short load
chs:    mov dl,[drive]          ; geometrie du BIOS
        mov ah,8
        push es
        int 13h
        pop es
        jc load
        and cx,3Fh
        jz load
        mov [spt],cx
        movzx dx,dh
        inc dx
        mov [heads],dx
load:   mov eax,[s2lba]
        mov cx,[s2cnt]
        mov bx,S2ADDR/16        ; segment de destination
nextsec: push cx
        push bx
        mov bp,5                ; 5 essais
retry:  call rdsec              ; EAX = LBA, BX = segment destination
        jnc okread
        push ax
        xor ax,ax
        mov dl,[drive]
        int 13h
        pop ax
        dec bp
        jnz retry
        mov si,msgerr
        jmp fatal
okread: pop bx
        pop cx
        inc eax
        add bx,20h
        loop nextsec
        ; signature du chargeur ('L232' en 8003h)
        cmp dword [S2ADDR+3],'L232'
        jne nostage
        pop si                  ; entree de la partition
        mov dl,[drive]
        jmp 0:S2ADDR

nostage: mov si,msgstage
        jmp short fatal
nospace: mov si,msgspace
fatal:  call print
halt:   hlt
        jmp short halt

; lit 1 secteur : EAX = LBA, BX = segment, destination BX:0000 ; CF si erreur
; (EAX conserve)
rdsec:  push eax
        push bx
        mov dl,[drive]
        cmp byte [useext],1
        jne .chs
        mov [daplba],eax
        mov [dapofs+2],bx
        mov word [dapofs],0
        mov si,dap
        mov ah,42h
        int 13h
        jmp short .out
.chs:   push es
        mov es,bx
        xor edx,edx
        movzx ecx,word [spt]
        div ecx                 ; EAX = LBA / spt, EDX = secteur - 1
        mov cl,dl
        inc cl                  ; secteur
        xor edx,edx
        movzx ebx,word [heads]
        div ebx                 ; EAX = cylindre, EDX = tete
        mov dh,dl
        mov ch,al
        shl ah,6
        or cl,ah
        mov dl,[drive]
        xor bx,bx
        mov ax,0201h
        int 13h
        pop es
.out:   pop bx
        pop eax
        ret

print:  lodsb
        or al,al
        jz .e
        mov ah,0Eh
        mov bx,7
        int 10h
        jmp short print
.e:     ret

msgnone  db 'Aucune partition active',13,10,0
msgerr   db 'Erreur disque',13,10,0
msgstage db 'Chargeur absent',13,10,0
msgspace db 'Pas de place',13,10,0

        times 446-($-$$) db 0
        times 64 db 0           ; table des partitions (remplie par MKIMAGE)
        dw 0AA55h
