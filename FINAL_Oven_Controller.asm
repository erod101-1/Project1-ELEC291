$MODLP51RC2

org 0000H
   ljmp MainProgram1
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

;-------------------------------------------;
;              Pin Assignments              ;
;-------------------------------------------;
CLK  	            EQU 22118400
BAUD 	            equ 115200
BRG_VAL             equ (0x100-(CLK/(16*BAUD)))
TIMER1_RATE         EQU 22050     ; 22050Hz is the sampling rate of the wav file we are playing
TIMER1_RELOAD       EQU 0x10000-(CLK/TIMER1_RATE)
TIMER2_RATE         EQU 1000      ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD       EQU ((65536-(CLK/TIMER2_RATE)))

LOCK_PARAMETERS     equ P0.4 ; button to lock parameter / start FSM
NEXT_SCREEN         equ P2.6 ; next screen in parameter selection
INC_DEC             equ P2.4 ; increment / decrement parameters
SHIFT_BUTTON	    equ P0.6 ; hold to decrement
OVEN_PIN            equ P1.1 ; output pin connected to the SSR
START_BUTTON        equ P1.2 ; start button from state 0 -> 1

LCD_RS  equ P3.2
; LCD_RW equ Px.x ; Always grounded
LCD_E   equ P3.3
LCD_D4  equ P3.4
LCD_D5  equ P3.5
LCD_D6  equ P3.6
LCD_D7  equ P3.7

; They are used for Bit-Bang SPI, in Mode(0,0)
CE_ADC  EQU P2.0 ; Slave select / Enable
MY_MOSI EQU P2.1 ; Master out / Slave in
MY_MISO EQU P2.2 ; Master in / Slave out
MY_SCLK EQU P2.3 ; Serial Clock

; The pins used for SPI (SPEAKER)
SPEAKER_FLASH_CE  EQU  P2.5
SPEAKER_MY_MOSI   EQU  P2.4 
SPEAKER_MY_MISO   EQU  P2.1
SPEAKER_MY_SCLK   EQU  P2.0 

SPEAKER           EQU P2.6 ; Used with a MOSFET to turn off speaker when not in use

; Commands supported by the SPI flash memory according to the datasheet
WRITE_ENABLE      EQU 0x06  ; Address:0 Dummy:0 Num:0
WRITE_DISABLE     EQU 0x04  ; Address:0 Dummy:0 Num:0
READ_STATUS       EQU 0x05  ; Address:0 Dummy:0 Num:1 to infinite
READ_BYTES        EQU 0x03  ; Address:3 Dummy:0 Num:1 to infinite
READ_SILICON_ID   EQU 0xab  ; Address:0 Dummy:3 Num:1 to infinite
FAST_READ         EQU 0x0b  ; Address:3 Dummy:1 Num:1 to infinite
WRITE_STATUS      EQU 0x01  ; Address:0 Dummy:0 Num:1
WRITE_BYTES       EQU 0x02  ; Address:3 Dummy:0 Num:1 to 256
ERASE_ALL         EQU 0xc7  ; Address:0 Dummy:0 Num:0
ERASE_BLOCK       EQU 0xd8  ; Address:3 Dummy:0 Num:0
READ_DEVICE_ID    EQU 0x9f  ; Address:0 Dummy:2 Num:1 to infinite

;-------------------------------------------;
;               Libraries                   ;
;-------------------------------------------;
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc) ; A library of functions to perform 32-bit arithmetic
$LIST

;-------------------------------------------;
;               Variables                   ;
;-------------------------------------------;
; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
DSEG at 0x30
x:                  ds 4
y:                  ds 4
soak_temp:     	    ds 1 
soak_time:	        ds 1
refl_temp:	        ds 1
refl_time:	        ds 1
cool_temp:          ds 1
temp_result:        ds 4
state:              ds 1
bcd:                ds 5
channel_0_voltage:  ds 4

w:                  ds 3 ; 24-bit play counter.  Decremented in Timer 1 ISR.

Count1ms:           ds 2 ; Used to determine when 1/10 of a second has passed
tenth_seconds:      ds 1 ; Store tenth_seconds 
seconds:            ds 1 ; Stores seconds
PowerPercent:       ds 1 ; Power% for Oven, 1 = 10%, 2 = 20% ... 10 = 100%. Using PWM

BSEG
mf:                 dbit 1
tenth_seconds_flag: dbit 1 ; Set to one in the ISR every time 100 ms had passed
seconds_flag:       dbit 1 

CSEG ; start of code segment
;-------------------------------------------;
;          Timer 1 Initialization           ;
;-------------------------------------------;
Timer1_Init:
; Configure SPI pins and turn off speaker
	anl P2M0, #0b_1100_1110
	orl P2M1, #0b_0011_0001
	setb SPEAKER_MY_MISO  ; Configured as input
	setb SPEAKER_FLASH_CE ; CS=1 for SPI flash memory
	clr SPEAKER_MY_SCLK   ; Rest state of SCLK=0
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
	setb SPEAKER_FLASH_CE  ; Disable SPI Flash
	clr SPEAKER ; Turn off speaker.  Removes hissing noise when not playing sound.
	mov DADH, #0x80 ; middle of range
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1

Timer1_ISR_Done:	
	pop psw
	pop acc
	reti

;-------------------------------------------;
;       Macro to play BCD as sounds         ;
;         (wooooowoooo make noise)          ;
;-------------------------------------------;
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
	setb SPEAKER_FLASH_CE
	clr SPEAKER ; Turn off speaker.
	
	clr SPEAKER_FLASH_CE ; Enable SPI Flash
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

;---------------------------------;
; Sends AND receives a byte via   ;
; SPI.                            ;
;---------------------------------;
Send_SPI:
	SPIBIT MAC
	    ; Send/Receive bit %0
		rlc a
		mov SPEAKER_MY_MOSI, c
		setb SPEAKER_MY_SCLK
		mov c, SPEAKER_MY_MISO
		clr SPEAKER_MY_SCLK
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

;-------------------------------------------;
;          Timer 2 Initialization           ;
;-------------------------------------------;
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
;       ISR for timer 2           ;
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
	cjne a, #0x09, IncTenthSeconds
    mov a, #0 
    da a
    mov tenth_seconds, a

	;Seconds Increment
    setb seconds_flag
	mov 	a, Seconds
    cjne 	a, #0x99, IncSeconds ; if Seconds != 59, then seconds++
    mov 	a, #0
    da 		a
    mov 	seconds, a
    ljmp Inc_Done

	;jnb UPDOWN, Timer2_ISR_decrement ;;; TEST REMOVING THIS ;;;;
	;add a, #0x01 ; test this
	;sjmp Timer2_ISR_da
	
IncTenthSeconds:
	add a, #0x01
	da a
	mov tenth_seconds, a
	cjne a, PowerPercent, Inc_Done ;test jumping back into forever loop
	setb OVEN_PIN
	ljmp Inc_Done

IncSeconds:
	add a, #0x01
	da a
	mov seconds, a
	mov a, PowerPercent
    setb OVEN_PIN
	cjne a, #0x00, OvenOn
	ljmp Inc_Done

OvenOn:
	clr OVEN_PIN
	ljmp Inc_Done

Timer2_ISR_done:
	pop psw
	pop acc
	reti

Timer2_ISR_decrement:
	add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.

Timer2_ISR_da:
	da a
	mov tenth_seconds, a

;-------------------------------------------;
; Serial Peripheral Interface communication ; 
;     using Bit-Bang SPI in Mode (0,0)      ;
;-------------------------------------------;
INIT_SPI:
    setb MY_MISO   ; Make MISO an input pin
    clr MY_SCLK    ; For mode (0,0) SCLK is zero
    ret

DO_SPI_G:
    push acc
    mov R1, #0     ; Received byte stored in R1
    mov R2, #8     ; Loop counter (8-bits)

DO_SPI_G_LOOP:
    mov a, R0      ; Byte to write is in R0
    rlc a          ; Carry flag has bit to write
    mov R0, a
    mov MY_MOSI, c
    setb MY_SCLK   ; Transmit
    mov c, MY_MISO ; Read received bit
    mov a, R1      ; Save received bit in R1
    rlc a
    mov R1, a
    clr MY_SCLK
    djnz R2, DO_SPI_G_LOOP
    pop acc
    ret

;-------------------------------------------;
;       Serial Port Transmission and        ;
;         Baud Rate Configurations          ;
;-------------------------------------------;
; Configure the serial port and baud rate
InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can proceed with the configuration
	orl	PCON,#0x80
	mov	SCON,#0x52
	mov	BDRCON,#0x00
	mov	BRL,#BRG_VAL
	mov	BDRCON,#0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;
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

;-------------------------------------------;
;            Send To Serial Port            ;
;-------------------------------------------;
; Send eight bit number via serial port, passed in ’a’.
SendToSerialPort:
    mov b, #100
    div ab
    orl a, #0x30    ; Convert hundreds to ASCII
    lcall putchar   ; Send to PuTTY/Python/Matlab
    mov a, b        ; Remainder is in register b
    mov b, #10
    div ab
    orl a, #0x30    ; Convert tens to ASCII
    lcall putchar   ; Send to PuTTY/Python/Matlab
    mov a, b
    orl a, #0x30    ; Convert units to ASCII
    lcall putchar   ; Send to PuTTY/Python/Matlab
ret

;-------------------------------------------;
;        Macro to read ADC channel          ;
;       ( ex: Read_ADC_Channel(0) )         ;
;-------------------------------------------;
Read_ADC_Channel MAC
    mov b, #%0
    lcall _Read_ADC_Channel
ENDMAC

_Read_ADC_Channel:
    clr CE_ADC
    mov R0, #00000001B  ; Start bit:1
    lcall DO_SPI_G
    mov a, b
    swap a
    anl a, #0F0H
    setb acc.7          ; Single mode (bit 7).
    mov R0, a
    lcall DO_SPI_G
    mov a, R1           ; R1 contains bits 8 and 9
    anl a, #00000011B   ; We need only the two least significant bits
    mov R7, a           ; Save result high.
    mov R0, #55H        ; It doesn't matter what we transmit...
    lcall DO_SPI_G
    mov a, R1           ; R1 contains bits 0 to 7. Save result low.
    mov R6, a
    setb CE_ADC
    ret

;-------------------------------------------;
;   Send a BCD number to PuTTY in ASCIII    ;
;-------------------------------------------;
Send_BCD mac
	push ar0
	mov r0, %0
	lcall ?Send_BCD
	pop ar0
endmac

?Send_BCD:
	push acc
	; Write most significant digit
	mov a, r0
	swap a
	anl a, #0fh
	orl a, #30h
	lcall putchar
	; write least significant digit
	mov a, r0
	anl a, #0fh
	orl a, #30h
	lcall putchar
	pop acc
    ret

;-------------------------------------------;
;            Send To LCD Screen             ;
;-------------------------------------------;
; Eight bit number to display passed in ’a’.
; Sends result to LCD
SendToLCD:
    mov b, #100
    div ab
    orl a, #0x30        ; Convert hundreds to ASCII
    lcall ?WriteData    ; Send to LCD
    mov a, b            ; Remainder is in register b
    mov b, #10
    div ab
    orl a, #0x30        ; Convert tens to ASCII
    lcall ?WriteData    ; Send to LCD
    mov a, b
    orl a, #0x30        ; Convert units to ASCII
    lcall ?WriteData    ; Send to LCD
ret

;-------------------------------------------;
;        Save / Load Configurations         ;
;-------------------------------------------;
loadbyte mac
    mov a, %0
    movx @dptr, a
    inc dptr
endmac

Save_Configuration:
    mov FCON, #0x08         ; Page Buffer Mapping Enabled (FPS = 1)
    mov dptr, #0x7f80       ; Last page of flash memory
    ; Save variables
    loadbyte(soak_temp) ; @0x7f80
    loadbyte(soak_time) ; @0x7f81
    loadbyte(refl_temp) ; @0x7f82
    loadbyte(refl_time) ; @0x7f83
    loadbyte(#0x55)             ; First key value @0x7f84
    loadbyte(#0xAA)             ; Second key value @0x7f85
    mov FCON, #0x00             ; Page Buffer Mapping Disabled (FPS = 0)
    orl EECON, #0b01000000      ; Enable auto-erase on next write sequence
    mov FCON, #0x50             ; Write trigger first byte
    mov FCON, #0xA0             ; Write trigger second byte
    ; CPU idles until writing of flash completes.
    mov FCON, #0x00             ; Page Buffer Mapping Disabled (FPS = 0)
    anl EECON, #0b10111111      ; Disable auto-erase
ret    

Load_Defaults:
    mov soak_temp, #0x64 ;100 HEX
    mov soak_time, #0x60 ;60 DECIMAL
    mov refl_temp, #0xC8 ;200 HEX
    mov refl_time, #0x45 ;45 DECIMAL
ret

getbyte mac
    clr a
    movc a, @a+dptr
    mov %0, a
    inc dptr
Endmac

Load_Configuration:
    mov dptr, #0x7f84               ; First key value location.
    getbyte(R0)                     ; 0x7f84 should contain 0x55
    cjne R0, #0x55, Load_Defaults
    getbyte(R0)                     ; 0x7f85 should contain 0xAA
    cjne R0, #0xAA, Load_Defaults
    ; Keys are good. Get stored values.
    mov dptr, #0x7f80
    getbyte(soak_temp) ; 0x7f80
    getbyte(soak_time) ; 0x7f81
    getbyte(refl_temp) ; 0x7f82
    getbyte(refl_time) ; 0x7f83
ret    

;-------------------------------------------;
;                  Delay                    ;
;-------------------------------------------;
delay:
     mov R3, #10
L13: mov R2, #100
L12: mov R1, #45
L11: mov R0, #166
L10: djnz R0, L10     ; 3 cycles->3*45.21123ns*166=22.51519us
     djnz R1, L11     ; 22.51519us*45=1.013ms
     djnz R2, L12     ; number of millisecons to wait passed in R2
     djnz R3, L13
     ret

;-------------------------------------------;
;        Temperature Calculations           ;
;-------------------------------------------;
Wait10us:
	mov R0, #74
	djnz R0, $
	ret
Average_CH0:
	load_x(0)
	mov R5, #100
Sum_loop0:
    Read_ADC_Channel(0)
	mov y+3, #0
	mov y+2, #0
	mov y+1, R7
	mov y+0, R6
	lcall add32
	lcall Wait10us
	djnz R5, Sum_loop0
	load_y(100)
	lcall div32
	ret
	
Do_Something_With_Result:
mov x+0,channel_0_voltage+0
    mov x+1,channel_0_voltage+1
    mov x+2,#0
    mov x+3,#0
  	
	load_y(4096)
	lcall mul32

	load_y(13299)
	lcall div32
    
	load_y(22)
	lcall add32
   

    mov bcd,x ; move result into x
    mov a, x
    da a
    mov temp_result,a

    lcall hex2bcd ;convert x to BCD
    lcall Display_10_digit_BCD
    
	;lcall Delay
    Send_BCD(bcd+1)
    Send_BCD(bcd+0)
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

;-------------------------------------------;
;        Increment / Decrement Macro        ;
;-------------------------------------------;
Change_8bit_Variable MAC
    jb %0, %2
    Wait_Milli_Seconds(#100) ; de-bounce
    jb %0, %2
    jnb %0, $
    jb SHIFT_BUTTON, skip%Mb
    dec %1
    sjmp skip%Ma
skip%Mb:
    inc %1
    inc %1
    inc %1
    inc %1
    inc %1
skip%Ma:
ENDMAC

;-------------------------------------------;
;   Messages / strings to display on LCD    ;
;   and send to PuTTY via serial port       ;
;-------------------------------------------;
Hello_World: 
    DB  'Hello, World!', '\r', '\n', 0
Initial_Putty:      db  'Starting temperature measurements...', '\r', '\n', 0

Start_msg_1:            db  'Reflow Oven', 0
Start_msg_2:            db  'Controller', 0
Clear_msg:              db  '                ', 0
Parameter_Setting_1:    db  'Set Reflow Curve', 0
Parameter_Setting_2:    db  'Parameters      ', 0
Loading_msg:            db  '.   ', 0
Soak_temp_set_msg_1:    db  'Set Soak Temp   ', 0
Soak_temp_set_msg_2:    db  ' C              ', 0
Soak_time_set_msg_1:    db  'Set Soak Time   ', 0
Soak_time_set_msg_2:    db  ' Sec            ', 0
Refl_temp_set_msg_1:    db  'Set Reflow Temp ', 0
Refl_temp_set_msg_2:    db  ' C              ', 0
Refl_time_set_msg_1:    db  'Set Reflow Time ', 0
Refl_time_set_msg_2:    db  ' Sec            ', 0
FSM_msg:                db  'FSM not complete', 0
Confirmation_msg:       db  'Confirm Settings', 0

TEMPERATURE_MESSAGE:    db '  TEMP: xxx C    ', 0
TIME_MESSAGE:           db 'T:',0
POWER_MESSAGE:          db 'P:',0
STATE_MESSAGE:          db 'S:',0

;-------------------------------------------;
;              Main Program                 ;
;-------------------------------------------;

;-------------------------------------------;
;          Parameter Selection              ;
;-------------------------------------------;
MainProgram1:
    mov SP, #7FH
    ; configure all pins in bidirecitonal mode
    mov P0M0, #0
    mov P0M1, #0
    mov P2M0, #0
    mov P2M1, #0
    mov P3M0, #0
    mov P3M1, #0
    mov P4M0, #0
    mov P4M1, #0
    
    ;lcall Timer2_Init
    lcall LCD_4BIT
    lcall Load_Configuration

    Set_Cursor(1,3)
    Send_Constant_String(#Start_msg_1)
    Set_Cursor(2,3)
    Send_Constant_String(#Start_msg_2)
    lcall delay
    mov tenth_seconds, #0
	mov seconds, #0
    mov state, #0
    mov cool_temp, #60

loop1:

parameter_screen:
    Set_Cursor(1, 1)
    Send_Constant_String(#Parameter_Setting_1)
    Set_Cursor(2, 1)
    Send_Constant_String(#Parameter_Setting_2)
    lcall delay
    Set_Cursor(2, 11)
    Send_Constant_String(#Loading_msg)
    lcall delay
    Set_Cursor(2, 12)
    Send_Constant_String(#Loading_msg)
    lcall delay
    Set_Cursor(2, 13)
    Send_Constant_String(#Loading_msg)
    lcall delay

set_soak_temp:
    Set_Cursor(1, 1)
    Send_Constant_String(#Soak_temp_set_msg_1)
    Set_Cursor(2, 4)
    Send_Constant_String(#Soak_temp_set_msg_2)
    Set_Cursor(2, 1)
    mov a, soak_temp
    lcall SendToLCD
    Change_8bit_Variable(INC_DEC, soak_temp, lock_param1)
    lcall Save_Configuration
lock_param1:
    jb LOCK_PARAMETERS, check_next1
	Wait_Milli_Seconds(#100)
	jb LOCK_PARAMETERS, check_next1
	jnb LOCK_PARAMETERS, $
    ljmp loop2
check_next1:
	jb NEXT_SCREEN, relay1
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, relay1
	jnb NEXT_SCREEN, set_soak_time
relay1:
    ljmp set_soak_temp

set_soak_time:
    Set_Cursor(1, 1)
    Send_Constant_String(#Soak_time_set_msg_1)
    Set_Cursor(2, 4)
    Send_Constant_String(#Soak_time_set_msg_2)
    Set_Cursor(2, 1)
    mov a, soak_time
    lcall SendToLCD
    Change_8bit_Variable(INC_DEC, soak_time, lock_param2)
    lcall Save_Configuration
lock_param2:
    jb LOCK_PARAMETERS, check_next2
	Wait_Milli_Seconds(#100)
	jb LOCK_PARAMETERS, check_next2
	jnb LOCK_PARAMETERS, $
    ljmp loop2
check_next2:
	jb NEXT_SCREEN, relay2
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, relay2
	jnb NEXT_SCREEN, set_refl_temp
relay2:
    ljmp set_soak_time

set_refl_temp:
    Set_Cursor(1, 1)
    Send_Constant_String(#Refl_temp_set_msg_1)
    Set_Cursor(2, 4)
    Send_Constant_String(#Refl_temp_set_msg_2)
    Set_Cursor(2, 1)
    mov a, refl_temp
    lcall SendToLCD
    Change_8bit_Variable(INC_DEC, refl_temp, lock_param3)
    lcall Save_Configuration
lock_param3:
    jb LOCK_PARAMETERS, check_next3
	Wait_Milli_Seconds(#100)
	jb LOCK_PARAMETERS, check_next3
	jnb LOCK_PARAMETERS, $
    ljmp loop2
check_next3:
	jb NEXT_SCREEN, relay3
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, relay3
	jnb NEXT_SCREEN, set_refl_time
relay3:
    ljmp set_refl_temp

set_refl_time:
    Set_Cursor(1, 1)
    Send_Constant_String(#Refl_time_set_msg_1)
    Set_Cursor(2, 4)
    Send_Constant_String(#Refl_time_set_msg_2)
    Set_Cursor(2, 1)
    mov a, refl_time
    lcall SendToLCD
    Change_8bit_Variable(INC_DEC, refl_time, lock_param4)
    lcall Save_Configuration
lock_param4:
    jb LOCK_PARAMETERS, check_next4
	Wait_Milli_Seconds(#100)
	jb LOCK_PARAMETERS, check_next4
	jnb LOCK_PARAMETERS, loop2
check_next4:
	jb NEXT_SCREEN, relay4
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, relay4
	jnb NEXT_SCREEN, relay5
relay4:
    ljmp set_refl_time

relay5:
    ljmp set_soak_temp


;-------------------------------------------;
;         Confirmation before FSM           ;
;-------------------------------------------;
loop2:
    Set_Cursor(1,1)
    Send_Constant_String(#Confirmation_msg)
    Set_Cursor(2,1)
    mov a, soak_temp
    lcall SendToLCD
    Set_Cursor(2,5)
    mov a, soak_time
    lcall SendToLCD
    Set_Cursor(2,9)
    mov a, refl_temp
    lcall SendToLCD
    Set_Cursor(2,13)
    mov a, refl_time
    lcall SendToLCD
    
    jb LOCK_PARAMETERS, dont_start_FSM
	Wait_Milli_Seconds(#100)
	jb LOCK_PARAMETERS, dont_start_FSM
	jnb LOCK_PARAMETERS, start_FSM
dont_start_FSM:
    ljmp loop2

GoToState0:
    ljmp state0

start_FSM:
    ;lcall delay
    sjmp MainProgram2

;-------------------------------------------;
;         Finite State Machine              ;
;-------------------------------------------;
MainProgram2:
    ; Initialization
    ;mov SP, #7FH ; Set the stack pointer to the begining of idata
    lcall Timer2_Init
    ;lcall LCD_4bit ; initialized above in parameter selection
    lcall InitSerialPort

    mov tenth_seconds, #0
	mov seconds, #0
    mov state, #0
    ;;; TEST VALUES
    ;mov soak_temp, #0x64 ;100 HEX
    ;mov soak_time, #0x60 ;60 DECIMAL
    ;mov refl_temp, #0xC8 ;200 HEX
    ;mov refl_time, #0x45 ;45 DECIMAL
    ;mov cool_temp, #0x3C ;60 HEX
    ;;;
    setb EA   ; Enable Global interrupts
    
    Set_Cursor(1,1)
    Send_Constant_String(#TEMPERATURE_MESSAGE)
    lcall INIT_SPI

forever:
    jnb tenth_seconds_flag, GoToState0 

    Read_ADC_Channel(0)
    lcall Do_Something_With_Result

    mov channel_0_voltage+1, R7 ;low
    mov channel_0_voltage+0, R6 ;High
    
    clr tenth_seconds_flag
    Set_Cursor(2,1)
    Send_Constant_String(#TIME_MESSAGE)
	Set_Cursor(2,3)
	Display_BCD(seconds)
    Set_Cursor(2,5)
    Display_BCD(tenth_seconds)
    Set_Cursor(2,9)
    Send_Constant_String(#STATE_MESSAGE)
    Set_Cursor(2,12)
    Send_Constant_String(#POWER_MESSAGE)
    Set_Cursor(2,14)
    Display_BCD(PowerPercent)
    Set_Cursor(2,11)
    Display_BCD(state)
    
    ljmp state0

state0: ;Idle
    mov a, state
    cjne a, #0, state1

    mov PowerPercent, #0
    jb START_BUTTON, state0_done
    Wait_Milli_Seconds(#50)
	jb START_BUTTON, state0_done
	jnb START_BUTTON, $

    ;State Transition from 0 -> 1
    mov state, #1
    mov PowerPercent, #0x0A
    
state0_done: ;Ramp
    ljmp forever
    
state1:
    mov a, state
    cjne a, #1, state2

    mov x+0, soak_temp + 0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0

    mov y+0, temp_result + 0
    mov y+1, temp_result + 1
    mov y+2, temp_result + 2
    mov y+3, temp_result + 3

    lcall x_lt_y
    jnb mf, state1_done

    ;State Transition from 1 -> 2
    mov PowerPercent, #0x02
    mov seconds, #0
    mov state, #2
state1_done:
    ljmp forever

state2:
    mov a, state
    cjne a, #2, state3

    Set_Cursor(1,15)
    Display_BCD(soak_time)
    mov a, soak_time
    mov x+0, a
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0

    mov y+0, seconds + 0
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    lcall x_lt_y
    jnb mf, state2_done

    ;State transition from 2 -> 3
    mov PowerPercent, #0x0A
    mov state, #3
state2_done:
    ljmp forever
  
state3: 
    mov a, state
    cjne a, #3, state4

    mov x+0, refl_temp + 0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0

    mov y+0, temp_result + 0
    mov y+1, temp_result + 1
    mov y+2, temp_result + 2
    mov y+3, temp_result + 3

    lcall x_lt_y
    jnb mf, state3_done

    ;State transition from 3 -> 4
    mov Seconds, #0
    mov PowerPercent, #0x02
    mov state, #4
state3_done:
    ljmp forever
  
state4:
    mov a, state
    cjne a, #4, state5

    mov x+0, refl_time + 0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0

    mov y+0, seconds + 0
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    lcall x_lt_y
    jnb mf, state4_done

    ;State transition from 4 -> 5
    mov PowerPercent, #0x00    
    mov state, #5
state4_done:
    ljmp forever
  
state5:
    mov a, state
    cjne a, #5, state5_done

    mov x+0, cool_temp + 0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0

    mov y+0, temp_result + 0
    mov y+1, temp_result + 1
    mov y+2, temp_result + 2
    mov y+3, temp_result + 3

    lcall x_gt_y
    jnb mf, state5_done

    ;State transition from 5 -> 0
    mov state, #0
    mov PowerPercent, #0x00

state5_done:
    ljmp forever

END