$NOLIST
$MODLP51RC2
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

SYSCLK         EQU 22118400  ; Microcontroller system clock frequency in Hz
TIMER1_RATE    EQU 22050     ; 22050Hz is the sampling rate of the wav file we are playing
TIMER1_RELOAD  EQU 0x10000-(SYSCLK/TIMER1_RATE)
BAUDRATE       EQU 115200
BRG_VAL        EQU (0x100-(SYSCLK/(16*BAUDRATE)))

BOOT_BUTTON   equ P4.5
UPDOWN        equ P0.0

SPEAKER  EQU P2.6 ; Used with a MOSFET to turn off speaker when not in use

; The pins used for SPI
FLASH_CE  EQU  P2.5
MY_MOSI   EQU  P2.4 
MY_MISO   EQU  P2.1
MY_SCLK   EQU  P2.0 

; Commands supported by the SPI flash memory according to the datasheet
WRITE_ENABLE     EQU 0x06  ; Address:0 Dummy:0 Num:0
WRITE_DISABLE    EQU 0x04  ; Address:0 Dummy:0 Num:0
READ_STATUS      EQU 0x05  ; Address:0 Dummy:0 Num:1 to infinite
READ_BYTES       EQU 0x03  ; Address:3 Dummy:0 Num:1 to infinite
READ_SILICON_ID  EQU 0xab  ; Address:0 Dummy:3 Num:1 to infinite
FAST_READ        EQU 0x0b  ; Address:3 Dummy:1 Num:1 to infinite
WRITE_STATUS     EQU 0x01  ; Address:0 Dummy:0 Num:1
WRITE_BYTES      EQU 0x02  ; Address:3 Dummy:0 Num:1 to 256
ERASE_ALL        EQU 0xc7  ; Address:0 Dummy:0 Num:0
ERASE_BLOCK      EQU 0xd8  ; Address:3 Dummy:0 Num:0
READ_DEVICE_ID   EQU 0x9f  ; Address:0 Dummy:2 Num:1 to infinite

; Reset vector
org 0x0000
    ljmp main
; External interrupt 0 vector (not used in this code)
org 0x0003
	reti
; External interrupt 1 vector (not used in this code)
org 0x0013
	reti
org 0x001B ; Timer/Counter 1 overflow interrupt vector. Used in this code to replay the wave file.
	ljmp Timer1_ISR
; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
w:   ds 3 ; 24-bit play counter.  Decremented in Timer 1 ISR.
Count1ms:     ds 2 ; Used to determine when 1/10 of a second has passed
tenth_seconds: ds 1 ; Store tenth_seconds 
seconds: ds 1 ; Stores seconds
; These register definitions needed by 'math32.inc'
	x:   ds 4
	y:   ds 4
	bcd: ds 5
	result: ds 2
	
PowerPercent: ds 1 ; Power% for Oven, 1 = 10%, 2 = 20% ... 10 = 100%. Using PWM

; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
tenth_seconds_flag: dbit 1 ; Set to one in the ISR every time 100 ms had passed
mf: dbit 1

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

$NOLIST
$include(math32.inc) ; A library of LCD related functions and utility macros
$LIST

;    1234567890123456    <- This helps determine the location of the counter
Initial_Message:  db ':', 0


;---------------------------------;
; Sends AND receives a byte via   ;
; SPI.                            ;
;---------------------------------;
Send_SPI:
	SPIBIT MAC
	    ; Send/Receive bit %0
		rlc a
		mov MY_MOSI, c
		setb MY_SCLK
		mov c, MY_MISO
		clr MY_SCLK
		mov acc.0, c
	ENDMAC
	
	SPIBIT(7)
	SPIBIT(6)
	SPIBIT(5)
	SPIBIT(4)
	SPIBIT(3)
	SPIBIT(2)
	SPIBIT(1)
	SPIBIT(0)

	ret

Timer1_Init:
; Configure SPI pins and turn off speaker
	anl P2M0, #0b_1100_1110
	orl P2M1, #0b_0011_0001
	setb MY_MISO  ; Configured as input
	setb FLASH_CE ; CS=1 for SPI flash memory
	clr MY_SCLK   ; Rest state of SCLK=0
	clr SPEAKER   ; Turn off speaker.
	
	; Configure timer 1
	anl	TMOD, #0x0F ; Clear the bits of timer 1 in TMOD
	orl	TMOD, #0x10 ; Set timer 1 in 16-bit timer mode.  Don't change the bits of timer 0
	mov TH1, #high(TIMER1_RELOAD)
	mov TL1, #low(TIMER1_RELOAD)
	; Set autoreload value
	mov RH1, #high(TIMER1_RELOAD)
	mov RL1, #low(TIMER1_RELOAD)

	; Enable the timer and interrupts
    setb ET1  ; Enable timer 1 interrupt
	; setb TR1 ; Timer 1 is only enabled to play stored sound

	; Configure the DAC.  The DAC output we are using is P2.3, but P2.2 is also reserved.
	mov DADI, #0b_1010_0000 ; ACON=1
	mov DADC, #0b_0011_1010 ; Enabled, DAC mode, Left adjusted, CLK/4
	mov DADH, #0x80 ; Middle of scale
	mov DADL, #0
	orl DADC, #0b_0100_0000 ; Start DAC by GO/BSY=1
check_DAC_init:
	mov a, DADC
	jb acc.6, check_DAC_init ; Wait for DAC to finish
	
	setb EA ; Enable interrupts

	; Not necesary if using internal DAC.
	; If using an R-2R DAC connected to P0, configure the pins of P0
	; (An external R-2R produces much better quality sound)
	mov P0M0, #0b_0000_0000
	mov P0M1, #0b_1111_1111
	
	ret

Play_Sound MAC 
	lcall ?Play_Sound
ENDMAC

?Play_Sound:
	lcall bcd2hex
    ;Multiply by 22050 / 5 bytes
    load_y(5)
    lcall div32 
    load_Y(22050)
    lcall mul32
    
    clr TR1 ; Stop Timer 1 ISR from playing previous request
	setb FLASH_CE
	clr SPEAKER ; Turn off speaker.
	
	clr FLASH_CE ; Enable SPI Flash
	mov a, #READ_BYTES
	lcall Send_SPI
	; Set the initial position in memory where to start playing
	mov a, x+2
	lcall Send_SPI
	mov a, x+1
	lcall Send_SPI
	mov a, x+0
	lcall Send_SPI
	
	;Plays a second, the length of time to say 1 digit
	mov w+2, #0x00
	mov w+1, #0x56
	mov w+0, #0x20
	
	setb SPEAKER ; Turn on speaker.
	setb TR1 ; Start playback by enabling Timer 1
ret
	
;-------------------------------------;
; ISR for Timer 1.  Used to playback  ;
; the WAV file stored in the SPI      ;
; flash memory.                       ;
;-------------------------------------;
Timer1_ISR:
	; The registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Check if the play counter is zero.  If so, stop playing sound.
	mov a, w+0
	orl a, w+1
	orl a, w+2
	jz stop_playing
	
	; Decrement play counter 'w'.  In this implementation 'w' is a 24-bit counter.
	mov a, #0xff
	dec w+0
	cjne a, w+0, keep_playing
	dec w+1
	cjne a, w+1, keep_playing
	dec w+2
	
keep_playing:
	setb SPEAKER
	lcall Send_SPI ; Read the next byte from the SPI Flash...
	mov P0, a ; WARNING: Remove this if not using an external DAC to use the pins of P0 as GPIO
	add a, #0x80
	mov DADH, a ; Output to DAC. DAC output is pin P2.3
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1
	sjmp Timer1_ISR_Done

stop_playing:
	clr TR1 ; Stop timer 1
	setb FLASH_CE  ; Disable SPI Flash
	clr SPEAKER ; Turn off speaker.  Removes hissing noise when not playing sound.
	mov DADH, #0x80 ; middle of range
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1

Timer1_ISR_Done:	
	pop psw
	pop acc
	reti

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
    cjne 	a, #0x99, IncSeconds ; if Seconds != 59, then seconds++
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
    lcall Timer1_Init
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
	
	
	 mov a, seconds
	mov b, #0x1
	div ab
	mov a, b
	cjne a, #0x0, no_sound
		mov a, tenth_seconds
		cjne a, #0x0, no_sound
			mov bcd, seconds
			play_sound
	no_sound:
	
	
    ljmp loop
END
