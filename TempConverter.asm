$MODLP51RC2
org 0000H
   ljmp MainProgram

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR
CLK  EQU 22118400

TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
CSEG

; These 'equ' must match the hardware wiring
; They are used by 'LCD_4bit.inc'
LCD_RS equ P3.2
; LCD_RW equ Px.x ; Always grounded
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7
OvenPin equ P2.2
UPDOWN equ P0.0



; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
temp_result: ds 4
channel_0_voltage: ds 4
BCD_counter: ds 4
Count1ms:     ds 2 ; Used to determine when 1/10 of a second has passed
tenth_seconds: ds 1 ; Store tenth_seconds 
seconds: ds 1 ; Stores seconds
PowerPercent: ds 1 ; Power% for Oven, 1 = 10%, 2 = 20% ... 10 = 100%. Using PWM

BSEG
mf: dbit 1
tenth_seconds_flag: dbit 1 ; Set to one in the ISR every time 100 ms had passed
cseg

;********** CONFIGURATION **********;
; Configure the serial port and baud rate
InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can proceed with the configuration
orl PCON,#0x80
mov SCON,#0x52
mov BDRCON,#0x00
mov BRL,#BRG_VAL
mov BDRCON,#0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;
    ret
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
 

; 1234567890123456 ;
TEMPERATURE_MESSAGE: db '  TEMP: xxx C    ', 0


;***********************************;
; DELAY MODULE ;
delay:
    mov R2, #200
L12: mov R1, #100
L11: mov R0, #100
L10: djnz R0, L10
    djnz R1, L11
    djnz R2, L12
    ret
;**************;
$LIST
$include(LCD_4bit.inc)
$NOLIST

$LIST
$include(math32.inc)
$NOLIST





;********* SPI **********;
CE_ADC EQU P2.0
MY_MOSI   EQU  P2.1
MY_MISO   EQU  P2.2
MY_SCLK   EQU  P2.3



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
;************************;

;********** MACRO FOR READING CHANNELS **********;
Read_ADC_Channel MAC
    mov b, #%0 
    lcall _Read_ADC_Channel
ENDMAC

_Read_ADC_Channel:
    clr CE_ADC
    mov R0, #00000001B ; Start bit:1
    lcall DO_SPI_G
    mov a, b
    swap a
    anl a, #0F0H
    setb acc.7 ; Single mode (bit 7).
    mov R0, a
    lcall DO_SPI_G
    mov a, R1 ; R1 contains bits 8 and 9
    anl a, #00000011B  ; We need only the two least significant bits
    mov R7, a ; Save result high.
    mov R0, #55H ; It doesn't matter what we transmit...
    lcall DO_SPI_G
    mov a,R1
    mov R6, a ; R1 contains bits 0 to 7.  Save result low.
    setb CE_ADC
    ret
;************************************************;

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
print2lcd:
	mov BCD_counter, temp_result
	Set_Cursor(1, 9)
	Display_BCD(BCD_counter)
	ret

Do_Something_With_Result:
    mov x+0,channel_0_voltage+0
    mov x+1,channel_0_voltage+1
    mov x+2,#0
    mov x+3,#0
    load_y(81)
    lcall mul32
    load_y(22)
    lcall add32
    mov bcd,x
    mov a, x
    da a
    mov temp_result,a

    lcall hex2bcd ;convert x to BCD
    lcall Display_10_digit_BCD
    
	lcall Delay
    Send_BCD(bcd+0)
    Send_BCD(bcd+1)
    mov a,#'\r'
    lcall putchar
    mov a,#'\n'
    lcall putchar
    ret
    ;takes voltage and give temperature

Display_10_digit_BCD:
    Set_Cursor(1,9)
    Display_BCD(bcd+1)
    Display_BCD(bcd+0)
    ret

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
	add a, #0x01
	da a
	mov seconds, a
	mov a, PowerPercent
	cjne a, #0x00, OvenOn
	ljmp Inc_Done

OvenOn:
	clr OvenPin
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

MainProgram:
    ; Initialization
    mov SP, #0x7F
    lcall Timer2_Init

    mov tenth_seconds, #0
	mov seconds, #0

    setb EA   ; Enable Global interrupts


    mov SP, #7FH ; Set the stack pointer to the begining of idata
    lcall LCD_4bit
    lcall InitSerialPort
    Set_Cursor(1,1)
    Send_Constant_String(#TEMPERATURE_MESSAGE)
    lcall INI_SPI

Forever:
    Read_ADC_Channel(0)
    mov channel_0_voltage+1, R6 ;low
    mov channel_0_voltage+0, R7 ;High
    lcall Do_Something_With_Result
    
    jnb tenth_seconds_flag, Forever
loop_timer:
    clr tenth_seconds_flag
    
    
    Set_Cursor(2, 8)
	Display_BCD(tenth_seconds)
    
	Set_Cursor(2, 6)
	Display_BCD(seconds)
    ljmp Forever

END