$MODLP51RC2

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))

Button1 equ P2.1
OVEN_PIN equ P1.1

; Reset vector
org 0x000H
    ljmp myprogram

org 0x000B
	ljmp Timer0_ISR


$NOLIST
$include(Project1.inc) ; A library of LCD related functions and utility macros
$LIST

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
	
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	cpl OVEN_PIN ; Connect speaker to P1.1!
	reti

myprogram:
    mov SP, #7FH
    mov P3M0, #0 ; Configure P3 in bidirectional mode
    mov P3M1, #0 ; Configure P3 in bidirectional mode
    lcall Timer0_Init
    setb TR0
M0:
	;Checks for Button1 Press to toggle oven
	jb Button1, M0
	Wait_Milli_Seconds(#50)	
	jb Button1, M0
	jnb Button1, $
	
	cpl TR0 ;Turns on Oven
  	sjmp M0

END