$NOLIST
$MODLP51RC2
$LIST

BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))


;Interupts
; Reset vector
org 0x0000
    ljmp MainProgram
; External interrupt 0 vector (not used in this code)
org 0x0003
reti
; Timer/Counter 0 overflow interrupt vector
org 0x000B
ljmp Timer0_ISR
; External interrupt 1 vector (not used in this code)
org 0x0013
reti
; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
reti
; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
reti
; Timer/Counter 2 overflow interrupt vector
org 0x002B
ljmp Timer2_ISR
;**********


;Libaries
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

$LIST
$include(math32.inc) ; Math libary
$NOLIST

; Might have to include other include files to modulize the code more ?

;*********

; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret
; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret


; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
temp_result: ds 4
channel_0_voltage: ds 4
BCD_counter: ds 4
Count1ms:     ds 2
;Other Variable definitions

BSEG
mf: dbit 1
half_seconds_flag: dbit 1 

CSEG
;                        1234567890123456 ;
Test:       db ' Test',0

;Pin Assignments
; These 'equ' must match the hardware wiring
; They are used by 'LCD_4bit.inc'
LCD_RS equ P3.2
; LCD_RW equ Px.x ; Always grounded
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7
CE_ADC EQU P2.0
UPDOWN EQU P0
SOUND_OUT     equ P1.1
MY_MOSI   EQU  P2.1 
MY_MISO   EQU  P2.2
MY_SCLK   EQU  P2.3 
;**********


;**********



;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
mov a, TMOD
anl a, #0xf0 ; 11110000 Clear the bits for timer 0
orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
mov TMOD, a
mov TH0, #high(TIMER0_RELOAD)
mov TL0, #low(TIMER0_RELOAD)
; Set autoreload value
mov RH0, #high(TIMER0_RELOAD)
mov RL0, #low(TIMER0_RELOAD)
; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
ret
;**********

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P1.1 ;
;---------------------------------;
Timer0_ISR:
;clr TF0  ; According to the data sheet this is done for us already.
cpl SOUND_OUT ; Connect speaker to P1.1!
reti
;**********

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;

Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P1.0 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(500), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(500), Timer2_ISR_done
	
	; 500 milliseconds have passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know half second had passed
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, BCD_counter
	jnb UPDOWN, Timer2_ISR_decrement
	add a, #0x01
	sjmp Timer2_ISR_da
Timer2_ISR_decrement:
	add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.
Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov BCD_counter, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti
;**********

;SPI
INI_SPI:
    setb MY_MISO ; Make MISO an input pin
    clr MY_SCLK           ; Mode 0,0 default
    ret

DO_SPI_G:
    mov R1, #0 ; Received byte stored in R1
    mov R2, #8            ; Loop counter (8-bits)

DO_SPI_G_LOOP:
    mov a, R0             ; Byte to write is in R0
    rlc a                 ; Carry flag has bit to write
    mov R0, a
    mov MY_MOSI, c
    setb MY_SCLK          ; Transmit
    mov c, MY_MISO        ; Read received bit
    mov a, R1             ; Save received bit in R1
    rlc a
    mov R1, a
    clr MY_SCLK
    djnz R2, DO_SPI_G_LOOP
    ret
;**********

;---------------------------------------;
; Send a BCD number to PuTTY in ASCIII ;
;---------------------------------------;
Send_BCD mac
    push ar0
    mov r0, %0
    lcall ?Send_BCD
    pop ar0
    endmac

?Send_BCD:
    push acc
    ; Send most significant digit
    mov a, r0
    swap a
    anl a, #0fh
    orl a, #30h
    lcall putchar
    ; Send least significant digit
    mov a, r0
    anl a, #0fh
    orl a, #30h
    lcall putchar
    pop acc
    ret
;**********

; Main Program
MainProgram:
   sjmp $ 
