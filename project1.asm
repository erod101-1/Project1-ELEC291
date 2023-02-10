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
INC_ONE         equ ... // Increments selected parameter by 1
INC_TEN        equ ... // Increments selected parameter by 10
INC_HUNDRED         equ ... // Increments selected parameter by 100

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

//a display for each parameter select. To move onto the next screen, press the MENU_SWITCH button. We're gonna have 3 buttons for incrementing the digits (assuming all parameters have max 3 digits), one that adds 100 to the number, one that adds 10...

Soak_Temp_Select:   db 'Soak Temp', 
Soak_Temp_Select_1: db 'x   Celsius', 0
Soak_Time_Select:   db 'Soak Time', 0
Soak_Time_Select_1: db 'x   Seconds', 0
Refl_Temp_Select:   db 'Reflow Temp', 0
Refl_Temp_Select_1: db 'x   Celsius', 0
Refl_Time_Select:   db 'Reflow Time', 0
Refl_Time_Select_1: db 'x   Seconds', 0
Cool_Temp_Select:   db 'Cooling Temp', 0
Cool_Temp_Select_1: db 'x   Seconds', 0
Live_Display:       db '' // We can decide the format after



Increment_Parameter MAC ; Increment_Parameter(temp_soak)
	mov b, #%0
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
	mov b, a
  ret

/*Decrement_Parameter MAC
    mov b, #%0
    lcall _Decrement_Parameter
ENDMAC

_Decrement_Parameter:
    mov a, b
    clr c
    DEC a, #0x01
    cjne a, #0x00,
    mov a, #0x00
    da a
    mov b, a
    mov a, b
    cjne a, #0,
    clr a
*/
; setting parameters with inputs on LCD
; defining inputs (buttons)
; second incrementing (using lab 2 timer?)
; pwm to SSR (Pulse Width Modulation, 100% for ramping, 20% for keeping constant temp)/
; PS: may need to change to non-volatile memory (EEPROM) to set and save parameters
; Current stage, temperature, time on LCD
; Need to implement inc_1,inc_10,inc_100 and parameter increment macros still, but I implemented all the menu switching logic

main:
  mov SP, #0x7F
  mov P0M0, #0
  mov P0M1, #0
  setb EA
  lcall LCD_4BIT
  // here we should set all the default parameters, so the user can't start the state machine without any set parameters 
  mov temp_soak, #0x50
  mov time_soak, #0x50
  mov temp_refl, #0x50
  mov time_refl, #0x50
  mov temp_cool, #0x50

  Set_Cursor(1,1)
  Send_Constant_String(#Soak_Temp_Select)
  Set_Cursor(2,1)
  Send_Constant_String(#Soak_Temp_Select_1)
  Wait_Milli_Seconds(#250)
  
display_1:

  Set_Cursor(2,1)
  display_BCD(temp_soak)

  Wait_Milli_Seconds(#50)

increment_one_button_check:
	jb INC_ONE, increment_ten_button_check  	; if the 'INC_ONE' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_ONE, increment_ten_button_check      ; if the 'INC_ONE' button is not pressed skip
	jnb INC_ONE, inc_1	                        ; Wait for button release.
increment_ten_button_check:
	jb INC_TEN, increment_hundred_button_check  ; if the 'INC_TEN' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_TEN, increment_hundred_button_check  ; if the 'INC_TEN' button is not pressed skip
	jnb INC_TEN, inc_10	                        ; Wait for button release.
increment_hundred_button_check:
	jb INC_HUNDRED, lock_parameters  	        ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_HUNDRED, lock_parameters             ; if the 'INC_HUNDRED' button is not pressed skip
	jnb INC_HUNDRED, inc_100		            ; Wait for button release. Increment second
lock_parameters:
  jb START_STOP, next  	                    ; if the 'START_STOP' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb START_STOP, next                  	    ; if the 'START_STOP' button is not pressed skip
	jnb START_STOP, FSM_START	                ; Wait for button release. Increment second
next:
	jb MENU_SWITCH, display_1  	                    ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb MENU_SWITCH, display_1                  	    ; if the 'INC_HUNDRED' button is not pressed skip
	jnb MENU_SWITCH, $			                ; Wait for button release. Increment second

  Set_Cursor(1,1)
  Send_Constant_String(#Soak_Time_Select)
  Set_Cursor(2,1)
  Send_Constant_String(#Soak_Time_Select_1)

  Wait_Milli_Seconds(#250)
  
display_2:
  Set_Cursor(2,1)
  display_BCD(time_soak)

  Wait_Milli_Seconds(#50)
  
increment_one_button_check_1:
	jb INC_ONE, increment_ten_button_check_1  	; if the 'INC_ONE' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_ONE, increment_ten_button_check_1      ; if the 'INC_ONE' button is not pressed skip
	jnb INC_ONE, inc_1	                        ; Wait for button release.
increment_ten_button_check_1:
	jb INC_TEN, increment_hundred_button_check_1  ; if the 'INC_TEN' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_TEN, increment_hundred_button_check_1  ; if the 'INC_TEN' button is not pressed skip
	jnb INC_TEN, inc_10	                        ; Wait for button release.
increment_hundred_button_check_1:
	jb INC_HUNDRED, lock_parameters_1  	        ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_HUNDRED, lock_parameters_1             ; if the 'INC_HUNDRED' button is not pressed skip
	jnb INC_HUNDRED, inc_100		            ; Wait for button release. Increment second
lock_parameters_1:
  jb START_STOP, next_1  	                    ; if the 'START_STOP' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb START_STOP, next_1                  	    ; if the 'START_STOP' button is not pressed skip
	jnb START_STOP, FSM_START	                ; Wait for button release. Increment second
next_1:
	jb MENU_SWITCH, display_2  	                    ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb MENU_SWITCH, display_2                  	    ; if the 'INC_HUNDRED' button is not pressed skip
	jnb MENU_SWITCH, $			                ; Wait for button release. Increment second

  Set_Cursor(1,1)
  Send_Constant_String(#Refl_Temp_Select)
  Set_Cursor(2,1)
  Send_Constant_String(#Refl_Temp_Select_1)

  Wait_Milli_Seconds(#250)

display_3:
  Set_Cursor(2,1)
  display_BCD(temp_refl)

  Wait_Milli_Seconds(#50)
    
increment_one_button_check_2:
	jb INC_ONE, increment_ten_button_check_2  	; if the 'INC_ONE' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_ONE, increment_ten_button_check_2      ; if the 'INC_ONE' button is not pressed skip
	jnb INC_ONE, inc_1	                        ; Wait for button release.
increment_ten_button_check_2:
	jb INC_TEN, increment_hundred_button_check_2  ; if the 'INC_TEN' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_TEN, increment_hundred_button_check_2  ; if the 'INC_TEN' button is not pressed skip
	jnb INC_TEN, inc_10	                        ; Wait for button release.
increment_hundred_button_check_2:
	jb INC_HUNDRED, lock_parameters_2  	        ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_HUNDRED, lock_parameters_2             ; if the 'INC_HUNDRED' button is not pressed skip
	jnb INC_HUNDRED, inc_100		            ; Wait for button release. Increment second
lock_parameters_2:
  jb START_STOP, next_2  	                    ; if the 'START_STOP' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb START_STOP, next_2                  	    ; if the 'START_STOP' button is not pressed skip
	jnb START_STOP, FSM_START	                ; Wait for button release. Increment second
next_2:
	jb MENU_SWITCH, display_3                    ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb MENU_SWITCH, display_3                 	    ; if the 'INC_HUNDRED' button is not pressed skip
	jnb MENU_SWITCH, $			                ; Wait for button release. Increment second		

  Set_Cursor(1,1)
  Send_Constant_String(#Refl_Time_Select)
  Set_Cursor(2,1)
  Send_Constant_String(#Refl_Time_Select_1)

  Wait_Milli_Seconds(#250)

display_4:
  Set_Cursor(2,1)
  display_BCD(time_refl)

  Wait_Milli_Seconds(#50)

increment_one_button_check_3:
	jb INC_ONE, increment_ten_button_check_3 	; if the 'INC_ONE' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_ONE, increment_ten_button_check_3      ; if the 'INC_ONE' button is not pressed skip
	jnb INC_ONE, inc_1	                        ; Wait for button release.
increment_ten_button_check_3:
	jb INC_TEN, increment_hundred_button_check_3  ; if the 'INC_TEN' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_TEN, increment_hundred_button_check_3 ; if the 'INC_TEN' button is not pressed skip
	jnb INC_TEN, inc_10	                        ; Wait for button release.
increment_hundred_button_check_3:
	jb INC_HUNDRED, lock_parameters_3  	        ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_HUNDRED, lock_parameters_3             ; if the 'INC_HUNDRED' button is not pressed skip
	jnb INC_HUNDRED, inc_100		            ; Wait for button release. Increment second
lock_parameters_3:
  jb START_STOP, next_3  	                    ; if the 'START_STOP' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb START_STOP, next_3                  	    ; if the 'START_STOP' button is not pressed skip
	jnb START_STOP, FSM_START	                ; Wait for button release. Increment second
next_3:
	jb MENU_SWITCH, display_4  	                    ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb MENU_SWITCH, display_4                  	    ; if the 'INC_HUNDRED' button is not pressed skip
	jnb MENU_SWITCH, $	

  Set_Cursor(1,1)
  Send_Constant_String(#Cool_Temp_Select)
  Set_Cursor(2,1)
  Send_Constant_String(#Cool_Temp_Select_1)

  Wait_Milli_Seconds(#250)

display_5:
  Set_Cursor(2,1)
  display_BCD(temp_cool)

  Wait_Milli_Seconds(#50)

increment_one_button_check_4:
	jb INC_ONE, increment_ten_button_check_4 	; if the 'INC_ONE' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_ONE, increment_ten_button_check_4      ; if the 'INC_ONE' button is not pressed skip
	jnb INC_ONE, inc_1	                        ; Wait for button release.
increment_ten_button_check_4:
	jb INC_TEN, increment_hundred_button_check_4  ; if the 'INC_TEN' button is not pressed skip
	Wait_Milli_Seconds(#100)					; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_TEN, increment_hundred_button_check_4 ; if the 'INC_TEN' button is not pressed skip
	jnb INC_TEN, inc_10	                        ; Wait for button release.
increment_hundred_button_check_4:
	jb INC_HUNDRED, lock_parameters_4  	        ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb INC_HUNDRED, lock_parameters_4             ; if the 'INC_HUNDRED' button is not pressed skip
	jnb INC_HUNDRED, inc_100		            ; Wait for button release. Increment second
lock_parameters_4:
  jb START_STOP, next_4 	                    ; if the 'START_STOP' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb START_STOP, next_4                  	    ; if the 'START_STOP' button is not pressed skip
	jnb START_STOP, FSM_START	                ; Wait for button release. Increment second
next_3:
	jb MENU_SWITCH, display_5  	                    ; if the 'INC_HUNDRED' button is not pressed skip
	Wait_Milli_Seconds(#100)				    ; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb MENU_SWITCH, display_5                 	    ; if the 'INC_HUNDRED' button is not pressed skip
	jnb MENU_SWITCH, $	

  Set_Cursor(1,1)
  Send_Constant_String(#Soak_Temp_Select)
  Set_Cursor(2,1)
  Send_Constant_String(#Soak_Temp_Select_1)

  Wait_Milli_Seconds(#50)

  ljmp display_1

  FSM_START:
    clr a
    mov state, a ; start from state 0, start/rest state
  forever: 
    mov a, state ; to check which state its in
  state0: ;start/rest state
    cjne a, #0, state1 //for every state, it checks, is this the state were in? if not move to the next state, otherwise continue.
    mov pwm, #0

    jb START_STOP, state0_done
    Wait_Milli_Seconds(#50)
    jb START_STOP, state0_done
    jnb START_STOP, $ ; Wait for key release

    mov sec, #0
    mov state, #1
  
  state0_done:
    ljmp forever

  state1: ; Ramp to soak (heating up)
    cjne a, #1, state2
    mov pwm, #100
    
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