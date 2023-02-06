$MODLP51RC2

Button1 equ P2.1



; Reset vector
org 0x000H
    ljmp myprogram

$NOLIST
$include(Project1.inc) ; A library of LCD related functions and utility macros
$LIST

myprogram:
    mov SP, #7FH
    mov P3M0, #0 ; Configure P3 in bidirectional mode
    mov P3M1, #0 ; Configure P3 in bidirectional mode
M0:
	;Checks for Button1 Press to toggle oven
	jb Button1, M0
	Wait_Milli_Seconds(#50)	
	jb Button1, M0
	jnb Button1, $
	
	cpl p3.7 ;Turns on Oven
  	sjmp M0

END