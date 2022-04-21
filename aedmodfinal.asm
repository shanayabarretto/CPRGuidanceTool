;Author: Shanaya Baretto
;Date: November 15th 2020
;Pupose: This project uses a pressure sensor that will eventually be hooked up to a CPR Annie to tell the user whether compressions are at the correct pressure and well seperated.
;There is also a buzzer included that can be used as reference for compressions as beeps come at 100 bpm
#include <p16F690.inc>        ; includes header file
     __config (_INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _BOR_OFF & _IESO_OFF & _FCMEN_OFF) 

     cblock    0x20           ; all varriables are stored in the cblock
clockstate                    ; informs the main program whether Timer0 has rolled over
btwnbeep                      ; counts the number of time units between beeps and rests
time                          ; counts the number of time units between pressure sensor readings
timecurr                      ; time valued transferred in here for comparisions
pvalue                        ; value read from the pressure sensor
     endc
          
     cblock 0x70              ; put these up in unbanked RAM, variables used for seamless interrupts
W_Save                        ; holds value in w register pre interrupt
STATUS_Save                   ; holds value in status register pre interrupt
     endc

     org 0
     goto      Start          ; goes to initialization
     nop
     nop
     nop
ISR:                          ; used for interrupts
     movwf     W_Save         ; holds w reg and status register values
     movf      STATUS,w
     movwf     STATUS_Save
     
     btfsc     INTCON,T0IF    ; tests to see if timer rolled over
     goto      ServiceTimer0  ; goes to ServiceTimer0 if it did, ExitISR if it didnt
     goto      ExitISR   
          
     
ServiceTimer0:
     bcf       INTCON,T0IF    ; clear the interrupt flag. (must be done in software)
     bsf       clockstate, 0  ; signal the main routine that the Timer has expired
     clrf      TMR0           ; Also clears the prescaler
     goto      ExitISR        ; Exits
               
ExitISR:
     movf      STATUS_Save,w  ; restores values to the W and Status registers
     movwf     STATUS
     swapf     W_Save,f
     swapf     W_Save,w
     retfie                   ; returns from interrupt

Start:
     banksel   OPTION_REG
     movlw     b'10000111'    ; configure Timer0.  Sourced from the Processor clock, uses maximum prescaler
     movwf     OPTION_REG     ;
	 
     banksel   TRISA
     movlw     b'00010001'
     movwf     TRISA          ; RA4 is an input (push buttom) as is RA0 (pressure sensor)
     movlw     b'10100000'    ; GIE bit is set- enables interrupts, and T0IE bit is set enabling Timer0 interrupt enable bit
     movwf     INTCON
     clrf      TRISC          ; Make PORTC all output
	 clrf      TRISB          ; Make PORTB all output
	 banksel   ADCON1
     movlw     0x10           ; A2D Clock Fosc/8 0x10
     movwf     ADCON1
    
     banksel   ANSEL
     movlw     b'00000001'    ; Make RA0 analog for the pressure sensor
     movwf     ANSEL
	 banksel   ANSELH 
	 movlw     b'00000000'    ; Make all ANSELH pins digital
	 movwf     ANSELH

     banksel   ADCON0
     movlw     b'00000001'    ; For analog to digital conversion, uses VDD, lt is left justified, chose channel 0, is enabled etc.
     movwf     ADCON0         

Initialize:
     banksel   PORTC
     clrf      PORTC          ; clears outputs in PORTB, and PORTC
     clrf      PORTB

	 clrf      clockstate     ; makes sure variables are set to 0
     clrf      btwnbeep
     clrf      time
     clrf      pvalue
     clrf      timecurr

     btfss     PORTA, 4       ; Checks to see if the button is pressed, does not continue on until it is pressed
     goto      $-1 
     nop                      ; clears PORTC only with nop for some reason
     clrf      PORTC          ; clears PORTC
ForeverLoop:
     btfss     clockstate, 0  ; checks to see if clockstate was set
     goto      $-1            ; if it is still 0 it keeps checking until it is not
     bcf       clockstate, 0  ; resets the pin so the program can be notified again when it resets
     incf      time, w        ; increments time
     movwf     time
	 sublw     .20            ; clears PORTC after a while since no readings taken, after 20 time units have passed
	 BTFSS     STATUS, 0      ; btfss STATUS, 0 works because that bit is 0 if the w register is bigger than the literal value
	 clrf      PORTC

     incf      btwnbeep, w    ; increments variable
     movwf     btwnbeep
	 btfss     PORTB, 7       ; chooses where to go based on buzzer status
     goto      checkon        ; if off, checks to see if it should turn on and vice versa
     goto      checkoff

checkon:                     
  	 goto      reading        ; takes a reading at every check and returns
realoff:
	 movf      btwnbeep, w    ; moves variable into wreg to compare it
	 sublw     .4
	 BTFSS     STATUS, 0
	 goto      turnon         ; if bigger than 4, turns buzzer on
     goto      ForeverLoop    ; if not, waits for timer to roll again
	 
checkoff:
	 goto      reading        ; takes a reading at every check and returns
realon:
	 movf      btwnbeep, w    ; moves it into wreg to compare it
	 sublw     .3
	 BTFSS     STATUS, 0
	 goto      turnoff        ; if variable is bigger than 3 it turns the buzzer off
     goto      ForeverLoop    ; if not it waits for the timer to roll again

turnon:
	 bsf       PORTB, 7       ; turns on the buzzer
     clrf      btwnbeep       ; clears the buzzer time variable
	 goto      ForeverLoop    ; waits for next rollover   

turnoff:
     bcf       PORTB, 7       ; turns off the buzzer
     clrf      btwnbeep       ; clears the buzzer time variable
	 goto      ForeverLoop    ; waits for next rollover

reading:
    nop
    nop
    nop
    nop
    nop

    bsf        ADCON0, GO     ; takes pressure reading
	btfss 	   ADCON0, GO
	goto       $-1

   	movf       ADRESH, w      ; stores it in variable pvalue
	movwf      pvalue

	sublw     .12             ; only if its bigger than 12 (guaranteed not fluke reading) does it go into compare loop
	BTFSS      STATUS, 0
    goto       stopclock
    goto       leavee         ; otherwise it goes back to where it was called

stopclock: 
    clrf       PORTC          ; new reading taken, so clear display
	movf       time, w        ; puts time into timecurr so it can be compared without changes
    movwf      timecurr
	movf       pvalue, w      ; if more than 70, too much pressure
	sublw      .70
	BTFSS      STATUS, 0
	goto       highv

	movf       pvalue, w      ; if between 54-70, okay amount of pressure
	sublw      .54
	BTFSS      STATUS, 0
	goto       good
    goto       lowv           ; if less, too little pressure

highv:
     bsf       PORTC, 2       ; turns on LED to signal result
     goto      timesense      ; goes onto compare time between compressions
good:
     bsf       PORTC, 1       ; turns on LED to signal result
     goto      timesense      ; goes onto compare time between compressions
lowv:
     bsf       PORTC, 0       ; turns on LED to signal result
     goto      timesense      ; goes onto compare time between compressions

timesense:
	 movf      timecurr, w    ; if more than 8 time units between compressions- too slow
     sublw     .8
	 btfss     STATUS, 0
     goto      tooslow
   
     movf      timecurr, w    ; if time units is between 4-8, speed is okay
	 sublw     .4
	 btfss     STATUS, 0
     goto      okspeed

	 movf      timecurr, w    ; if between 1-4, speed is too fast
	 sublw     .1
	 btfss     STATUS, 0
 	 goto      toofast

okspeed:
	 bsf       PORTC, 4       ; turns on LED to signal result
	 clrf      time           ; clears both time variables
     clrf      timecurr       
     goto      leavee         ; goes to leave loop

toofast:
	 bsf       PORTC, 5       ; turns on LED to signal result
	 clrf      time           ; clears both time variables
     clrf      timecurr
     goto      leavee         ; goes to leave loop

tooslow: 
	 bsf       PORTC, 3       ; turns on LED to signal result
	 clrf      time           ; clears both time variables
     clrf      timecurr
	 goto      leavee         ; goes to leave loop
     
leavee:
     btfss     PORTB, 7       ; goes back to part of code from where it was called based on the state of the buzzer
     goto      realoff
     goto      realon


	end                       