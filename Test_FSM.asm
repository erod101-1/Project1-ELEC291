DSEG ; Before the state machine!
state:     ds 1
temp_soak: ds 1
time_soak: ds 1
temp_refl: ds 1
time_refl: ds 1
temp_cool: ds 1

; setting parameters with inputs on LCD
; defining inputs (buttons)
; second incrementing (using lab 2 timer?)
; pwm to SSR (Pulse Width Modulation, 100% for ramping, 20% for keeping constant temp)/
; PS: may need to change to non-volatile memory (EEPROM) to set and save parameters
; Current stage, temperature, time on LCD

clr a
mov state, a // start from state 0, start/rest state

forever: 
  mov a, state // to check which state its in
state0: ;start/rest state
  cjne a, #0, state1 //for every state, it checks, is this the state were in? if not move to the next state, otherwise continue.
  mov pwm, #0
  jb PB6, state0_done
  jnb PB6, $ ; Wait for key release
  mov state, #1
state0_done:
  ljmp forever

state1: ;Ramp to soak (heating up)
  cjne a, #1, state2
  mov pwm, #100
  mov sec, #0
  mov a, temp_soak
  clr c
  subb a, temp // a = a - c - temp, c is a carry flag. If temp is greater than a, then c is set to something other than 0, moving on to state 2. 
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
