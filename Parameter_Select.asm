$MODLP51RC2
org 0000H
   ljmp MainProgram

;-------------------------------------------;
;              Pin Assignments              ;
;-------------------------------------------;
CLK  	    EQU 22118400
BAUD 	    equ 115200
BRG_VAL     equ (0x100-(CLK/(16*BAUD)))

LOCK_PARAMETERS     equ P0.4
NEXT_SCREEN         equ P2.6
INC_DEC             equ P2.4
SHIFT_BUTTON	    equ P2.2

LCD_RS  equ P3.2
; LCD_RW equ Px.x ; Always grounded
LCD_E   equ P3.3
LCD_D4  equ P3.4
LCD_D5  equ P3.5
LCD_D6  equ P3.6
LCD_D7  equ P3.7

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
bcd:                ds 5
;soak_temp_BCD:     ds 1
;soak_time_BCD:	    ds 1
;reflow_temp_BCD:	ds 1
;reflow_time_BCD:	ds 1

BSEG
mf: dbit 1

CSEG ; start of code segment

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
    mov soak_temp, #150
	mov soak_time, #45
	mov refl_temp, #225
	mov refl_time, #30
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


;-------------------------------------------;
;              Main Program                 ;
;-------------------------------------------;
MainProgram:
    mov SP, #7FH
    mov P0M0, #0
    mov P0M1, #0
    mov P2M0, #0 ; Configure P2 in bidirectional mode
    mov P2M1, #0 ; Configure P2 in bidirectional mode
    lcall LCD_4BIT
    lcall Load_Configuration

    Set_Cursor(1,3)
    Send_Constant_String(#Start_msg_1)
    Set_Cursor(2,3)
    Send_Constant_String(#Start_msg_2)
    lcall delay
    ;mov soak_temp_BCD, #0x50
	;mov soak_time_BCD, #0x50
	;mov reflow_temp_BCD, #0x50
	;mov reflow_time_BCD, #0x50

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
    Change_8bit_Variable(INC_DEC, soak_temp, check_next1)
    lcall Save_Configuration
check_next1:
	jb NEXT_SCREEN, set_soak_temp
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, set_soak_temp
	jnb NEXT_SCREEN, set_soak_time

set_soak_time:
    Set_Cursor(1, 1)
    Send_Constant_String(#Soak_time_set_msg_1)
    Set_Cursor(2, 4)
    Send_Constant_String(#Soak_time_set_msg_2)
    Set_Cursor(2, 1)
    mov a, soak_time
    lcall SendToLCD
    Change_8bit_Variable(INC_DEC, soak_time, check_next2)
    lcall Save_Configuration
check_next2:
	jb NEXT_SCREEN, set_soak_time
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, set_soak_time
	jnb NEXT_SCREEN, set_refl_temp

set_refl_temp:
    Set_Cursor(1, 1)
    Send_Constant_String(#Refl_temp_set_msg_1)
    Set_Cursor(2, 4)
    Send_Constant_String(#Refl_temp_set_msg_2)
    Set_Cursor(2, 1)
    mov a, refl_temp
    lcall SendToLCD
    Change_8bit_Variable(INC_DEC, refl_temp, check_next3)
    lcall Save_Configuration
check_next3:
	jb NEXT_SCREEN, set_refl_temp
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, set_refl_temp
	jnb NEXT_SCREEN, set_refl_time

set_refl_time:
    Set_Cursor(1, 1)
    Send_Constant_String(#Refl_time_set_msg_1)
    Set_Cursor(2, 4)
    Send_Constant_String(#Refl_time_set_msg_2)
    Set_Cursor(2, 1)
    mov a, refl_time
    lcall SendToLCD
    Change_8bit_Variable(INC_DEC, refl_time, check_next4)
    lcall Save_Configuration
check_next4:
	jb NEXT_SCREEN, lock_param
	Wait_Milli_Seconds(#100)
	jb NEXT_SCREEN, lock_param
	jnb NEXT_SCREEN, relay1

lock_param:
    jb LOCK_PARAMETERS, relay2
	Wait_Milli_Seconds(#100)
	jb LOCK_PARAMETERS, relay2
	jnb LOCK_PARAMETERS, loop2

relay1:
    ljmp set_soak_temp
relay2:
    ljmp set_refl_time

; FSM loop starts here
loop2:
    Set_Cursor(1,1)
    Send_Constant_String(#FSM_msg)
    Set_Cursor(2,1)
    Send_Constant_String(#Clear_msg)
    sjmp loop2


END