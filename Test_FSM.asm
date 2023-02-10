$NOLIST
$MODLP51RC2
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

SOUND_OUT     equ P1.1
MENU_SWITCH   equ ... // Switches between parameter select screen and diplay screen (for running time, temperature, etc.)
START_STOP    equ ... // Starts reflow process after the parameters have been set. 
PARAM_SELECT  equ ... // Choose whatever parameter you want to increment or decrement
INC           equ ... // Increments selected parameter
DEC           equ ... // Decrements selected parameter

; Reset vector
org 0x0000
  ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
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
	reti



DSEG at 0x30; Before the state machine!
state:     ds 1
temp_soak: ds 1
time_soak: ds 1
temp_refl: ds 1
time_refl: ds 1
temp_cool: ds 1

bseg

cseg

LCD_RS equ P3.2
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

Launch_Message_1: db 'SCel:xxx C'
Launch_Message_2: db 'SSec:xxx'
Second_Display_1: db 'RCel:xxx C'
Second_Display_2: db 'RSec:xxx'
Third_Display_1:  db '' // for running time, temp, reflow stage, etc. 
Third_Display_2:  db ''

; 
Increment_Parameter MAC
	mov b,#%0
	lcall _Increment_Parameter
ENDMAC

_Increment_Parameter:
	mov a, b
	add a, #0x01
	da a 
	mov b, a
	mov a, b
	cjne a, #0x400, 
	clr a 
	mov Minute_counter, a


; setting parameters with inputs on LCD
; defining inputs (buttons)
; second incrementing (using lab 2 timer?)
; pwm to SSR (Pulse Width Modulation, 100% for ramping, 20% for keeping constant temp)/
; PS: may need to change to non-volatile memory (EEPROM) to set and save parameters
; Current stage, temperature, time on LCD

main:
  mov SP, #0x7F
  mov P0M0, #0
  mov P0M1, #0
  setb EA
  lcall LCD_4BIT
display_1:
  Set_Cursor(1,1)
  Send_Constant_String(#Launch_Message_1)
  Set_Cursor(2,1)
  Send_Constant_String(#Launch_Message_2)
  
  Wait_Milli_Seconds(#250)
  
display_1_changed:
  
  clr a
  mov state, a ; start from state 0, start/rest state
  
  jnb INC, inc_soak_temp
  Wait_Milli_Seconds(#50)
 
 inc_soak_temp: 
   mov a, soak_temp
   add a, #0x01
   mov soak_temp,a
   ljmp display_1
  
  forever: 
    mov a, state ; to check which state its in
  state0: ;start/rest state
    cjne a, #0, state1 //for every state, it checks, is this the state were in? if not move to the next state, otherwise continue.
    mov pwm, #0
    jb PB6, state0_done
    jnb PB6, $ ; Wait for key release
    mov state, #1
  state0_done:
    ljmp forever

  state1: ; Ramp to soak (heating up)
    cjne a, #1, state2
    mov pwm, #100
    mov sec, #0
    mov a, temp_soak
    clr c
    subb a, temp ; a = a - c - temp, c is a carry flag. If temp is greater than a, then c is set to something other than 0, moving on to state 2. 
    jnc state1_done //if state is 0, finish state_1 and repeat it. 
    mov state, #2
  state1_done:
    ljmp forever

  state2: ; preheat/soak 
    cjne a, #2, state3
    mov pwm, #20
    mov a, time_soak
    clr c
    subb a, sec
    jnc state2_done
    mov state, #3
  state2_done:
    ljmp forever

  state3: ;ramp_to_peak
    cjne a, #3, state4
    mov pwm, #100
    mov sec, #0
    mov a, temp_refl
    clr c
    subb a, temp
    jnc state3_done
    mov state, #4
  state3_done:
    ljmp forever

  state4: ;constant temperature, reflow stage
    cjne a, #4, state5
    mov pwm, #20
    mov a, time_refl
    clr c
    subb a, sec
    jnc state4_done
    mov state, #5
  state4_done: 
    ljmp forever

  state5: ;cooling stage, still need to figure out what temperature were gonna let it cool to.
    cjne a, #5, state0
    mov pwm, #0
    mov a, temp_cool
    clr c
    subb a, temp
    jc state5_done
    mov state, #0
  state5_done:
    ljmp forever
