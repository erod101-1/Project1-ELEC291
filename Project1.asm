$NOLIST
$MODLP51RC2
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

BOOT_BUTTON   equ P4.5
UPDOWN        equ P0.0

; Reset vector
org 0x0000
    ljmp main
; External interrupt 0 vector (not used in this code)
org 0x0003
	reti
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

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when 1/10 of a second has passed
tenth_seconds: ds 1 ; Store tenth_seconds 
seconds: ds 1 ; Stores seconds

PowerPercent: ds 1 ; Power% for Oven, 1 = 10%, 2 = 20% ... 10 = 100%. Using PWM

; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
tenth_seconds_flag: dbit 1 ; Set to one in the ISR every time 100 ms had passed

cseg

LCD_RS equ P3.2
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7
OvenPin equ p2.2

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;    1234567890123456    <- This helps determine the location of the counter
Initial_Message:  db ':', 0

; Routine to initialize the ISR
; for timer 2 
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
	cjne a, #low(100), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(100), Timer2_ISR_done
	
	; 100 milliseconds have passed.  Set a flag so the main program knows
	
	setb tenth_seconds_flag ; Let the main program know 100 milliseconds have passed
	
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a


	;1/10 Seconds Increment
	mov a, tenth_seconds
	cjne a, #0x9, IncTenthSeconds
    mov a, #0 
    da a
    mov tenth_seconds, a

	;Seconds Increment
	mov 	a, Seconds
    cjne 	a, #0x59, IncSeconds ; if Seconds != 59, then seconds++
    mov 	a, #0 
    da 		a
    mov 	seconds, a
   
	jnb UPDOWN, Timer2_ISR_decrement
	add a, #0x01
	sjmp Timer2_ISR_da
	
IncTenthSeconds:
	add a, #0x01
	da a
	mov tenth_seconds, a
	cjne a, PowerPercent, Inc_Done
	setb OvenPin
	ljmp Inc_Done

IncSeconds:
	clr OvenPin
	add a, #0x01
	da a
	mov seconds, a
	ljmp Inc_Done

Timer2_ISR_decrement:
	add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.

Timer2_ISR_da:
	da a
	mov tenth_seconds, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti


; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
main:
	; Initialization
    mov SP, #0x7F
    lcall Timer2_Init
    ; In case you decide to use the pins of P0, configure the port in bidirectional mode:
    mov P0M0, #0
    mov P0M1, #0

	mov PowerPercent, #1 ;Power Percent Mode set, 0 = 0%, 1 = 10% ... 10 = 100%
	mov tenth_seconds, #0
	mov seconds, #0

    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT

    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
	Set_Cursor(1, 1)
    setb tenth_seconds_flag
	
	
	; After initialization the program stays in this 'forever' loop
loop:
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	jnb BOOT_BUTTON, $		; Wait for button release.  The '$' means: jump to same instruction.
	; A valid press of the 'BOOT' button has been detected, reset the BCD counter.
	; But first stop timer 2 and reset the milli-tenth_seconds counter, to resync everything.
	clr TR2                 ; Stop timer 2
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Now clear the BCD counter
	mov tenth_seconds, a
	setb TR2                ; Start timer 2
	sjmp loop_b             ; Display the new value
loop_a:
	jnb tenth_seconds_flag, loop
loop_b:
    clr tenth_seconds_flag
    
   	Set_Cursor(1, 8)
	Display_BCD(tenth_seconds)
	Set_Cursor(1, 6)
	Display_BCD(seconds)
	Set_Cursor(1, 8)
    Send_Constant_String(#Initial_Message)

    ljmp loop
END
