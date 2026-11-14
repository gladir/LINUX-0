; @author: Sylvain Maltais (support@gladir.com)
; @created: 2026
; @website(https://www.gladir.com/linux-0)
; @abstract(Target: NASM, 80386)
; @description: Tete du chargeur (stage2) de KERNEL32, 2 secteurs charges par
;   le MBR a 0000:8000 (le corps du chargeur, ecrit en Pascal et compile par
;   LPC -K0840, suit immediatement en 0000:8400). La tete fournit au corps
;   Pascal ce que l'assembleur 8086 de LPC ne sait pas faire : activation de
;   A20, carte memoire INT 15h E820/E801/88h (registres 32 bits) et passage
;   en mode protege plat avec saut au noyau. Table de saut (appels FAR depuis
;   le Pascal) : 0000:8040 A20, 0000:8043 memoire, 0000:8046 mode protege.
;   Variables aux adresses fixes (lues et ecrites par le Pascal) : voir plus
;   bas. nasm -f bin -o STAGE2H.BIN STAGE2.ASM

        bits 16
        cpu 386
        org 8000h

MBI     equ 7E000h              ; structure Multiboot (voir README.md)
MBISEG  equ 7E00h
MMAPOFS equ 0200h               ; carte memoire dans la structure

        jmp near entry          ; 8000h
        db 'L232'               ; 8003h signature (verifiee par le MBR)
bootdrv db 0                    ; 8007h unite BIOS d'amorce
partidx db 0                    ; 8008h numero de la partition (0 a 3)
parttyp db 0                    ; 8009h type de la partition
partlba dd 0                    ; 800Ah premier secteur de la partition
partsiz dd 0                    ; 800Eh nombre de secteurs de la partition
        dw 0                    ; 8012h (reserve)
entry32 dd 0                    ; 8014h point d'entree du noyau (physique)
mbiaddr dd 0                    ; 8018h valeur remise dans EBX
        dd 0                    ; 801Ch (reserve)
memlow  dw 0                    ; 8020h Ko sous 1 Mo (INT 12h)
mmapcnt dw 0                    ; 8022h nombre d'entrees E820
mmaplen dd 0                    ; 8024h octets de la carte (format Multiboot)
fbupper dd 0                    ; 8028h Ko au-dessus de 1 Mo (E801 ou 88h)
a20ok   db 0                    ; 802Ch 1 si A20 actif
        times 40h-($-$$) db 0
        jmp near f_a20          ; 8040h
        jmp near f_mem          ; 8043h
        jmp near f_go32         ; 8046h

entry:  cli
        xor ax,ax
        mov ds,ax
        mov es,ax
        mov ss,ax
        mov sp,7C00h
        sti
        cld
        mov [bootdrv],dl
        mov al,[si+4]
        mov [parttyp],al
        mov eax,[si+8]
        mov [partlba],eax
        mov eax,[si+12]
        mov [partsiz],eax
        mov ax,si
        sub ax,7DBEh
        shr ax,4
        mov [partidx],al
        jmp 0840h:0000h         ; corps du chargeur (Pascal)

; ---------------------------------------------------------------- A20
; teste A20 : ZF = 0 si actif
a20test: push ds
        push es
        xor ax,ax
        mov ds,ax
        dec ax
        mov es,ax
        mov si,0500h
        mov di,0510h
        mov al,[ds:si]
        push ax
        mov al,[es:di]
        push ax
        mov byte [ds:si],0
        mov byte [es:di],0FFh
        cmp byte [ds:si],0FFh   ; egaux : l'adresse boucle, A20 coupe
        pop ax
        mov [es:di],al
        pop ax
        mov [ds:si],al
        pop es
        pop ds
        ret

kbwi:   mov cx,0FFFFh
.l:     in al,64h
        test al,2
        loopnz .l
        ret

a20try: call a20test
        jnz .ok
        mov ax,2401h            ; BIOS
        int 15h
        call a20test
        jnz .ok
        in al,92h               ; porte rapide
        test al,2
        jnz .kbd
        or al,2
        and al,0FEh
        out 92h,al
        call a20test
        jnz .ok
.kbd:   call kbwi               ; controleur de clavier 8042
        mov al,0D1h
        out 64h,al
        call kbwi
        mov al,0DFh
        out 60h,al
        call kbwi
        call a20test
.ok:    ret

f_a20:  pushad
        push ds
        push es
        xor ax,ax
        mov ds,ax
        mov es,ax
        mov byte [a20ok],0
        mov bp,8                ; quelques essais
.t:     call a20try
        jnz .on
        dec bp
        jnz .t
        jmp short .end
.on:    mov byte [a20ok],1
.end:   pop es
        pop ds
        popad
        retf

; ---------------------------------------------------------------- memoire
f_mem:  pushad
        push ds
        push es
        xor ax,ax
        mov ds,ax
        int 12h
        mov [memlow],ax
        mov word [mmapcnt],0
        mov dword [mmaplen],0
        mov dword [fbupper],0
        mov ax,MBISEG
        mov es,ax
        xor ebx,ebx
        mov di,MMAPOFS+4
        xor bp,bp
.e820:  mov dword [es:di+14h],1 ; attribut ACPI par defaut
        mov eax,0E820h
        mov edx,534D4150h
        mov ecx,24
        int 15h
        jc .e820end
        cmp eax,534D4150h
        jne .e820end
        cmp ecx,20
        jb .next
        test byte [es:di+14h],1 ; entree ACPI 3 desactivee : ignoree
        jz .next
        mov [es:di-4],ecx       ; taille de l'entree (Multiboot)
        add di,cx
        add di,4
        inc bp
        cmp di,0F80h
        jae .e820end
.next:  test ebx,ebx
        jnz .e820
.e820end:
        mov [mmapcnt],bp
        test bp,bp
        jz .fb
        movzx eax,di
        sub eax,MMAPOFS+4
        mov [mmaplen],eax
        jmp short .done
.fb:    mov ax,0E801h           ; repli : E801 puis 88h
        xor cx,cx
        xor dx,dx
        int 15h
        jc .k88
        test ax,ax
        jnz .e801
        mov ax,cx
        mov bx,dx
.e801:  movzx eax,ax
        movzx ebx,bx
        shl ebx,6               ; blocs de 64 Ko -> Ko
        add eax,ebx
        mov [fbupper],eax
        jmp short .done
.k88:   mov ah,88h
        int 15h
        jc .done
        movzx eax,ax
        mov [fbupper],eax
.done:  pop es
        pop ds
        popad
        retf

; ---------------------------------------------------------------- mode protege
f_go32: cli
        cld
        xor ax,ax
        mov ds,ax
        lgdt [gdtr]
        mov eax,cr0
        or al,1
        mov cr0,eax
        jmp dword 08h:pm32

        align 8
gdt:    dq 0
        dq 00CF9A000000FFFFh    ; 08h code plat 4 Go
        dq 00CF92000000FFFFh    ; 10h donnees plates 4 Go
gdtr:   dw 23
        dd gdt

        bits 32
pm32:   mov ax,10h
        mov ds,ax
        mov es,ax
        mov fs,ax
        mov gs,ax
        mov ss,ax
        mov esp,90000h
        mov eax,2BADB002h
        mov ebx,[mbiaddr]
        jmp dword [entry32]

        times 1024-($-$$) db 0
