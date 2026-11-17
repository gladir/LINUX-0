; @author: Sylvain Maltais (support@gladir.com)
; @created: 2026
; @website(https://www.gladir.com/linux-0)
; @abstract(Target: NASM, 80386 mode protege)
; @description: Noyau de test MULTIBOOT 1 pour le chargeur de KERNEL32
;   (BOOT/). Image plate liee a 100000h, enveloppee en ELF32 par MKELF.PY.
;   Ecrit sur COM1 (3F8h) : "BOOT OK eax=... ebx=... cmdline=...", les champs
;   de la structure Multiboot, la carte memoire, puis les controles du
;   contenu charge (-DPADLEN=n -DPADHASH=h : zone de remplissage a hachage
;   connu ; -DZLEN=n : zone (zone) qui doit avoir ete mise a zero ;
;   -DFADDR=a -DFLEN=n : zone chargee depuis un decalage lointain du fichier,
;   indirection triple). Il s'arrete par l'extinction ACPI de QEMU (port 604h)
;   ou par HLT.
;   nasm -f bin -DPADLEN=... -o TESTK.BIN TESTK.ASM

        bits 32
        org 100000h

%ifndef PADLEN
%define PADLEN 0
%endif

mbhdr:  dd 1BADB002h, 3, -(1BADB002h+3)

_start: cli
        mov esp,90000h
        mov [save_eax],eax
        mov [save_ebx],ebx
        call serinit
        mov esi,m_boot
        call puts
        mov eax,[save_eax]
        call puthex
        mov esi,m_ebx
        call puts
        mov eax,[save_ebx]
        call puthex
        mov esi,m_cmd
        call puts
        mov ebx,[save_ebx]
        test dword [ebx],4
        jz .nocmd
        mov esi,[ebx+16]
        call puts
.nocmd: call crlf
        cmp dword [save_eax],2BADB002h
        je .magic
        mov esi,m_badmagic
        call puts
        jmp .mb
.magic: mov esi,m_magic
        call puts
.mb:    mov ebx,[save_ebx]
        mov esi,m_flags
        call puts
        mov eax,[ebx]
        call puthex
        call crlf
        test dword [ebx],1
        jz .nomem
        mov esi,m_low
        call puts
        mov eax,[ebx+4]
        call putdec
        mov esi,m_up
        call puts
        mov eax,[ebx+8]
        call putdec
        call crlf
.nomem: test dword [ebx],2
        jz .nobd
        mov esi,m_bd
        call puts
        mov eax,[ebx+12]
        call puthex
        call crlf
.nobd:  test dword [ebx],200h
        jz .noname
        mov esi,m_name
        call puts
        mov esi,[ebx+64]
        call puts
        call crlf
.noname: test dword [ebx],40h
        jz .nommap
        mov ecx,[ebx+44]        ; longueur
        mov edx,[ebx+48]        ; adresse
.mm:    test ecx,ecx
        jle .nommap
        mov esi,m_mmap
        call puts
        mov eax,[edx+8]
        call puthex
        mov eax,[edx+4]
        call puthex
        mov esi,m_len
        call puts
        mov eax,[edx+16]
        call puthex
        mov eax,[edx+12]
        call puthex
        mov esi,m_type
        call puts
        mov eax,[edx+20]
        call putdec
        call crlf
        mov eax,[edx]
        add eax,4
        add edx,eax
        sub ecx,eax
        jmp .mm
.nommap:
%if PADLEN
        ; hachage de la zone de remplissage : h = h*31 + dword
        mov esi,pad
        mov ecx,PADLEN/4
        xor eax,eax
.hash:  imul eax,eax,31
        add eax,[esi]
        add esi,4
        loop .hash
        mov [save_eax],eax
        mov esi,m_pad
        call puts
        call puthex
        cmp dword [save_eax],PADHASH
        je .padok
        mov esi,m_bad
        call puts
        jmp .padend
.padok: mov esi,m_ok
        call puts
.padend: call crlf
%endif
%ifdef ZLEN
        mov esi,zone
        mov ecx,ZLEN
.z:     cmp byte [esi],0
        jne .zbad
        inc esi
        loop .z
        cmp byte [esi],0AAh     ; l'octet suivant ne doit pas avoir change
        jne .zbad
        mov esi,m_zero
        call puts
        mov esi,m_ok
        call puts
        jmp .zend
.zbad:  mov esi,m_zero
        call puts
        mov esi,m_bad
        call puts
.zend:  call crlf
%endif
%ifdef FLEN
        mov esi,FADDR
        mov ecx,FLEN
        xor edx,edx
.f:     mov al,dl
        imul eax,eax,7
        add al,3
        cmp [esi],al
        jne .fbad
        inc esi
        inc edx
        loop .f
        mov esi,m_far
        call puts
        mov esi,m_ok
        call puts
        jmp .fend
.fbad:  mov esi,m_far
        call puts
        mov esi,m_bad
        call puts
.fend:  call crlf
%endif
        mov esi,m_end
        call puts
        mov dx,604h             ; extinction ACPI de QEMU
        mov ax,2000h
        out dx,ax
.hlt:   hlt
        jmp .hlt

serinit: mov dx,3F9h
        xor al,al
        out dx,al
        mov dx,3FBh
        mov al,80h
        out dx,al
        mov dx,3F8h
        mov al,1
        out dx,al
        inc dx
        xor al,al
        out dx,al
        mov dx,3FBh
        mov al,3
        out dx,al
        mov dx,3FCh
        mov al,3
        out dx,al
        ret

putc:   push eax
        push edx
        mov ah,al
.w:     mov dx,3FDh
        in al,dx
        test al,20h
        jz .w
        mov dx,3F8h
        mov al,ah
        out dx,al
        pop edx
        pop eax
        ret

puts:   push eax
.l:     lodsb
        test al,al
        jz .e
        call putc
        jmp .l
.e:     pop eax
        ret

crlf:   push eax
        mov al,13
        call putc
        mov al,10
        call putc
        pop eax
        ret

puthex: push eax
        push ecx
        mov ecx,8
.l:     rol eax,4
        push eax
        and al,0Fh
        add al,'0'
        cmp al,'9'
        jbe .d
        add al,7
.d:     call putc
        pop eax
        loop .l
        pop ecx
        pop eax
        ret

putdec: push eax
        push ebx
        push ecx
        push edx
        mov ebx,10
        xor ecx,ecx
.d:     xor edx,edx
        div ebx
        push edx
        inc ecx
        test eax,eax
        jnz .d
.p:     pop eax
        add al,'0'
        call putc
        loop .p
        pop edx
        pop ecx
        pop ebx
        pop eax
        ret

m_boot  db 'BOOT OK eax=',0
m_ebx   db ' ebx=',0
m_cmd   db ' cmdline=',0
m_magic db 'MAGIC OK',13,10,0
m_badmagic db 'MAGIC BAD',13,10,0
m_flags db 'flags=',0
m_low   db 'mem_lower=',0
m_up    db ' mem_upper=',0
m_bd    db 'boot_device=',0
m_name  db 'loader=',0
m_mmap  db 'mmap base=',0
m_len   db ' len=',0
m_type  db ' type=',0
m_pad   db 'CHK pad hash=',0
m_zero  db 'CHK zero ',0
m_far   db 'CHK far ',0
m_ok    db ' OK',0
m_bad   db ' BAD',0
m_end   db 'TESTK END',13,10,0

save_eax dd 0
save_ebx dd 0
%ifdef ZLEN
        times 1001h-($-$$) db 0
zone:   times ZLEN+16 db 0AAh   ; zone sale (adresse impaire), mise a zero
%endif                          ; par un segment ELF sans donnees
        align 16, db 0
pad:
%if PADLEN
        incbin "PAD.BIN", 0, PADLEN
%endif
