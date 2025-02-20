section .bss
    buffer resb 65536 		 ; maksymalna długość danych
    dane resq 1 		 ; dane to maksymalnie 65 bitow,
				 ; ale najwyzszy stopien to zawsze 1
section .text

MAXLEN equ 64
OPEN equ 2
CLOSE equ 3
READ equ 0
LSEEK equ 8
WRITE equ 1
EXIT equ 60
NOWY_WIERSZ equ 10

global _start

; program oblicza sume kontrolną crc dla argumentów plik wielomian

_start:
    mov rcx, [rsp]               ; ładuj do rcx liczbę argumentów.
    cmp rcx, 3                   ; sprawdzenie poprawości liczby argumentów
    jne .error_bez_zamykania
    mov rbx, [rsp + 8*rcx]       ; ładuj do rbx adres ostatniego argumentu.

    xor al, al                   ; ten kod działa jak strnlen(rdi, MAXLEN).
    cld                          ; szukaj w kierunku większych adresów.
    mov ecx, MAXLEN + 1
    mov rdi, rbx
    repne scasb

    setz dl
    movzx rdx, dl

    sub rdi, rbx
    sub rdi, 1                   ; w rdi długość wielomianu
    mov r10, rdi                 ; ustawiamy r10 na długość wielomianu

    mov r8, [rsp + 24]
    cmp r8, 0                    ; sprawdzenie poprawności drugiego argumentu
    je .error

    xor r9, r9                   ; w r9 będziemy trzymać przekonwertowany wielomian
    xor r11, r11                 ; w r11 licznik długości wielomianu

.konwertowanie_wielomianu:       ; ustawia r9 na przekonwertowany wielomian
    cmp byte [r8 + r11], '1'
    je .przypadek_1              ; jeśli znak wielomianu to 1
    cmp byte [r8 + r11], '0'
    jne .error                   ; niepoprawny drugi argument
    inc r11
    cmp r11, rdi                 ; sprawdzenie czy cały wielomian został przekonwertowany
    je .otwarcie_pliku           ; jeśli tak otwieramy plik
    shl r9, 1
    jmp .konwertowanie_wielomianu
.przypadek_1:
    or r9, 1                     ; ustawia ostatni bit r9 na 1
    inc r11                      ; zwiększa licznik
    cmp r11, rdi                 ; sprawdzenie czy cały wielomian został przekonwertowany
    je .otwarcie_pliku           ; jeśli tak otwieramy plik
    shl r9, 1
    jmp .konwertowanie_wielomianu

.otwarcie_pliku: 
    ; w r9 znajduje sie przekonwertowany wielomian
    ; w r10 znajduje sie długość wielomianu (maksymalnie 64)

    ; przesunięcie wielomianu do lewej strony
    
    mov rax, r10
    mov cl, 64
    sub cl, al                   ; w cl ile razy trzeba przesunac (w al jest długość wielomianu)
    shl r9, cl                   ; przesuwamy przekonwertowany wielomian w r9 do lewej strony

    ; otwarcie pliku
    mov rdi, [rsp + 16]          ; w rdi adres pliku
    mov rax, OPEN
    mov rsi, 0
    mov rdx, 0
    syscall

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error_bez_zamykania

    mov rdi, rax                 ; ustawienie rdi na fd
    mov r12, rax                 ; ustawienie r12 na fd do końca programu
    
    xor r14, r14                 ; wyczyszczenie r14 (pojemnik)
    
.petla:
    ; w r14 pojemnik z aktualnie przetwarzanymi danymi
    ;   do którego wkładamy dane bit po bicie
    ; w r9 przekonwertowany wielomian przyklejony do lewej strony
    ; w rdi fd

    mov r15, -1                  ; ustawienie licznika przetworzonych bajtów z fragmentu

    mov rax, READ
    mov rsi, buffer
    mov rdx, 2
    syscall                      ; wczytanie do bufforu długości danych

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error

    
    movzx rdx, word [buffer]     ; ustawienie rdx na długość danych w bajtach
    jz .error

    xor r8, r8
    mov r8w, 6                   ; 2 bajty dlugosci + 4 bajty offset
    add r8w, dx                  ; w r8w długość fragmentu w bajtach

    mov rax, READ                ; w rdi - fd,  rsi - buffer, rdx - długość danych 

    syscall                      ; wczytanie do buffora danych z fragmentu

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error

    xor bl, bl                   ; bl aktualnie przetwarzany bajt danych
    mov bh, 8                    ; bh licznik dodanych bitów
    
.glowna_petla:
    ; w rdx długość danych w fragmencie
    ; w r15 licznik przetworzonych bajtów z fragmentu    
    ; w r9 jest przekonwertowany wielomian
    ; r14 miejsce (pojemnik) na dane

    cmp bh, 8                    ; sprawdzenie czy wszystkie bity zostały już dodane do pojemnika
    je .przynies_bajt            ; jeśli tak ładujemy do bl nowy bajt danych
    shl r14, 1                   ; przesunięcie w lewo
    jc .oblicz_xor               ; jeśli nastąpiło przeniesienie xorujemy
    shl bl, 1                    ; przesunięcie przetwarzanego bajtu
    adc r14, 0                   ; dodajemy do r14 nowy bit przeniesiony z bl
    inc bh                       ; zwiększenie licznika dodanych bajtów
    jmp .glowna_petla

.oblicz_xor:
    shl bl, 1                    ; przesunięcie przetwarzanego bajtu
    adc r14, 0                   ; dodajemy do r14nowy bit przeniesiony z bl
    xor r14, r9                  ; xoruje pojemnik z przekonwertowym wielomianem
    inc bh                       ; zwiększenie licznika dodanych bajtów
    jmp .glowna_petla

.przynies_bajt:
    inc r15                      ; zwiększenie licznika przetworzonych bajtów
    cmp r15, rdx                 ; sprawdzenie czy cały fragment został przetworzony
    je .nowy_fragment            ; jeśli tak pobieramy nowy fragment
    
    mov bl, byte [buffer + r15]  ; załadowanie do bl następnego bajtu z buffora
    xor bh, bh                   ; wyczyszczenie licznika dodanych bitów
    jmp .glowna_petla

.nowy_fragment:

    ; obliczanie offset

    ; w rdi - fd, rsi - buffer
    mov rax, READ
    mov rdx, 4                   ; cztery bajty offsetu

    syscall                      ; wczytanie do buffora offsetu

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error
    
    ; sprawdzenie czy koniec

    add r8w, [buffer]            ; sprawdzenie czy przesunięcie wskazuje początek
    jz .po_glownej_petli         ; jeśli tak to koniec wczytywania danych
    

    ; wykonanie przesunięcia
    
    ; w rdi - fd
    mov rax, LSEEK
    movsx rsi, dword [buffer]    ; ustawienie rsi na offset
    mov rdx, 1

    syscall                      ; wykonanie przesunięcia

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error

    jmp .petla


.po_glownej_petli: 
    ; już nie ma nowych danych, teraz trzeba przesunąc pojemnik do lewej
    
    mov rax, 65                  ; licznik bitów do przesunięcia

.wyrownanie_do_lewej_petla:      ; przesuwamy pojemnik w lewo, wykonujemy xor

    ; w pojemniku powinny zostac dane o dlugosci wielomianu
    ; r14 - pojemnik
    ; r9 - wielomian

    dec rax                      ; zmniejszenie licznika bitów
    cmp rax, 0                   ; sprawdzenie czy jeszcze przesuwamy
    je .wypisz                   ; jeśli nie to zaczynamy wypisywać
    shl r14, 1                   ; przesunięcie pojemnika w lewo
    jc .wykonaj_xor              ; jeśli wystąpiło przeniesienie to xor z wielomianem
    jmp .wyrownanie_do_lewej_petla
    
.wykonaj_xor:                    ; xor z zerami nie modyfikuje wielomianu
    xor r14, r9                  ; xor pojemnika z wielomianem
    jmp .wyrownanie_do_lewej_petla

    
.wypisz:                         ; wypisanie wyniku (pojemnika o długości wielomianu)

    ; w r10 długość wielomianu

    shl r14, 1                   ; przesunięcie pojemnika w lewo
    setc byte [buffer]           ; ustawienie wartości w bufforze na 0 lub 1
    add byte [buffer], 48        ; dodajemy 48, czyli zamieniamy liczbe na ascii
    
    mov rax, WRITE
    mov rdi, 1                   ; stdout
    mov rsi, buffer
    mov rdx, 1

    syscall                      ; wypisanie jednego bita z pojemnika

    cmp rax, 0                   ; sprawdzenie czy nie było błędu
    jl .error

    dec r10                      ; zmniejszenie liczby bitów do wypisania
    jnz .wypisz                  ; jeśli zostały bity to następny 

.exit:
    ; wypisanie \n, rdi - stdout, rsi - buffer, rdx - 1

    mov rax, WRITE
    mov byte [buffer], NOWY_WIERSZ

    syscall                      ; wypisanie \n

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error

    mov rax, CLOSE
    mov rdi, r12                 ; w r12 jest fd pliku
    syscall

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error_bez_zamykania

    mov rax, EXIT
    mov rdi, 0                   ; brak błędu - 0
    syscall
.error_bez_zamykania:
    mov rdi, 1                   ; ustawienie błędu na 1
    mov rax, EXIT
    
    syscall
.error:
    mov rax, CLOSE
    mov rdi, r12                 ; w r12 jest fd pliku
    syscall

    cmp rax, 0                   ; sprawdzenie czy wystąpił błąd
    jl .error_bez_zamykania

    mov rax, EXIT
    mov rdi, 1                   ; ustawienie błędu na 1
    syscall