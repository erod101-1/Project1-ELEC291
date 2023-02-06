DSEG ; Before the state machine!
state: ds 1
temp_soak: ds 1
Time_soak: ds 1
Temp_refl: ds 1
Time_refl: ds 1

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
