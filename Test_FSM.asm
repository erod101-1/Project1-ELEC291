DSEG ; Before the state machine!
state:     ds 1
temp_soak: ds 1
time_soak: ds 1
temp_refl: ds 1
time_refl: ds 1
temp_cool: ds 1

// setting parameters with inputs on LCD
// defining inputs (buttons)
// second incrementing (using lab 2 timer?)
// pwm to SSR (Pulse Width Modulation, 100% for ramping, 20% for keeping constant temp)
// PS: may need to change to non-volatile memory (EEPROM) to set and save parameters

clr a
mov state, a

forever:
  mov a, state
state0:
  cjne a, #0, state1
  mov pwm, #0
  jb PB6, state0_done
  jnb PB6, $ ; Wait for key release
  mov state, #1
state0_done:
  ljmp forever

state1:
  cjne a, #1, state2
  mov pwm, #100
  mov sec, #0
  mov a, temp_soak
  clr c
  subb a, temp
  jnc state1_done
  mov state, #2
state1_done:
  ljmp forever

state2:
  cjne a, #2, state3
  mov pwm, #20
  mov a, time_soak
  clr c
  subb a, sec
  jnc state2_done
  mov state, #3
state2_done:
  ljmp forever
  
state3:
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
  
state4:
  cjne a, #4, state5
  mov pwm, #20
  mov a, time_refl
  clr c
  subb a, sec
  jnc state4_done
  mov state, #5
state4_done:
  ljmp forever
  
state5:
  cjne a, #5, state0
  mov pwm, #0
  mov a, temp_cool
  clr c
  subb a, temp
  jc state5_done
  mov state, #0
state5_done:
  ljmp forever