$MODLP51RC2
org 0000H
   ljmp MainProgram
CLK  EQU 22118400
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

; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
temp_result: ds 4
channel_0_voltage: ds 4
BCD_counter: ds 4
BSEG
mf: dbit 1

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
 
Hello_World:
    DB  'Hello, World!', '\r', '\n', 0

;                        1234567890123456 ;
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
	
	load_y(300)
	lcall mul32
	;load_y(10)
	;lcall mul32
	
	;load_y(10)
	;lcall div32
	load_y(1023)
	lcall div32
	load_y(3900)
	lcall div32
	
	load_y(22)
	lcall add32
	
    

    
   
   

    ; We have T_disp = T_adc + T_ambient

    mov bcd,x ; move result into x
    mov a, x
    da a
    mov temp_result,a

    lcall hex2bcd ;convert x to BCD
    lcall Display_10_digit_BCD
    
	lcall Delay
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



MainProgram:
    mov SP, #7FH ; Set the stack pointer to the begining of idata
    lcall LCD_4bit
    lcall InitSerialPort
    Set_Cursor(1,1)
    Send_Constant_String(#TEMPERATURE_MESSAGE)
    lcall INI_SPI

Forever:
    Read_ADC_Channel(0)

    lcall Wait10us
    lcall Average_CH0

    Set_Cursor(2,1)
    mov x+1, R7
    mov x+0, R6
   lcall hex2bcd
    Display_BCD(bcd+1)
    Display_BCD(bcd+0)
    
    mov channel_0_voltage+1, R7 ;low
    mov channel_0_voltage+0,R6 ;High
    
    
    
    lcall Do_Something_With_Result
    sjmp Forever

END
