;---------------------------------------
; MyCos 1.0 by AsCrNet 25/12/2022
;--------------------------------------- 
;
COPEN   = $3
CGETREC = $5
CGETCHR = $7 
CPUTREC = $9
CPUTCHR = $B
CCLOSE  = $C
EOL     = $9B

BOOT    = $9
DOSVEC  = $A
DOSINI  = $C
APPMHI  = $F
ATRACT  = $4D
LOMEM   = $80
FR0     = $D4
INBUFF  = $F3

COLDST  = $244
CH      = $2FC
RUNAD   = $2E0
INITAD  = $2E2
MEMLO   = $2E7

ICCOM   = $342
ICBAL   = $344
ICBAH   = $345
ICBLL   = $348
ICBLH   = $349
ICAX1   = $34A
ICAX2   = $34B
CASBUF  = $3FD
BASICF  = $3F8

PACTL   = $D302
FASC    = $D8E6
IFP     = $D9AA

WARMSV  = $E474
COLDSV  = $E477  
CIOV    = $E456

CLEN   = [end-start]
CBLOCK = [CLEN+127]/128

	org $700

; Boot cassette
start 
	.byte $0
	.byte CBLOCK
	.word start,set_memory
	
	lda #$3C
	sta PACTL
	
	lda #<set_memory
	sta DOSINI 
	lda #>set_memory
	sta DOSINI+1
	
	lda #<init
	sta DOSVEC
	lda #>init
	sta DOSVEC+1
	
	lda #$0
	sta COLDST
	lda #$1
	sta BOOT
	clc
	rts

set_memory
	lda #<end 
	sta MEMLO
	sta LOMEM
	lda #>end 
	sta MEMLO+1
	sta LOMEM+1
	rts

; Print menu ---------------------------------------------------------
init
	close #$10
	print #menu1
	print #menu2
	jsr keypress
	cmp #$3F
	bne cmd0
	jmp cmd_basic
cmd0
	cmp #$2A
	bne cmd1
	jmp cmd_save
cmd1
	cmp #$15
	bne cmd2
	jmp cmd_motor
cmd2
	cmp #$12
	bne cmd3
	jmp cmd_verify
cmd3
	cmp #$3A
	bne cmd4
	jmp cmd_loader
cmd4
	cmp #$38
	bne cmdf
	jmp cmd_restart
cmdf
	jmp init

; Menu - Restart ----------------------------------------------------
cmd_restart
	jmp COLDSV

; Menu - Run Basic	-------------------------------------------------
cmd_basic
	lda BASICF  
	beq on_basic
	print #nobasic
	jsr keypress
	jmp init
on_basic
	jmp WARMSV
	
; Menu - Activates or deactivates motor ------------------------------
cmd_motor
	lda PACTL 
	cmp #$3C
	beq motor_cas
	lda #$3C
	sta PACTL 
	mwa motor_off,y msg_motor,y
	jmp init
motor_cas
	lda #$34
	sta PACTL 
	mwa motor_on,y msg_motor,y
	jmp init
	
; Menu - Saving COS ---------------------------------------------------
cmd_save
	print #save_cos
	jsr keypress
	cmp #$0C
	bne cmd_save_end
	open #$10, #$8, #$80, #drive
	send #$10, #CPUTCHR, #start, #CLEN
cmd_save_end
	jmp init

; Menu - Check load ---------------------------------------------------
cmd_verify
	print #load_cas
	jsr keypress
	cmp #$0C
	beq read_cont
	jmp init
read_cont
	open #$10, #$4, #$80, #drive
	bmi error_verify
read_verify
	send #$10, #CGETCHR, #CASBUF, #$7F
	tya
	bpl read_verify
	cmp #$88
	bne error_verify
	print #verify_ok
	jsr keypress
	jmp init
error_verify
	jsr cio_error
	jsr keypress
	jmp init
	
; Menu - Loader binary ------------------------------------------------
cmd_loader
	print #load_cas
	jsr keypress
	cmp #$0C
	beq onload
	jmp init
onload
	open #$10, #$4, #$80, #drive
; Read a segment 
getseg
	lda #$FF                
	sta INITAD
	sta INITAD+1
    lda #$0
	sta ATRACT     
; Get segment header
gs_strta  
	ldy #<BL_SEG_HEAD    
	lda #>BL_SEG_HEAD
	jsr getblk_2         
	lda BL_SEG_HEAD      
	and BL_SEG_HEAD+1
	cmp #$FF
	bne gs_enda        
	sta BL_HDR_FOUND 
	beq gs_strta         
; Get rest of the segment header
gs_enda   
	ldy #<[BL_SEG_HEAD+2]
	lda #>[BL_SEG_HEAD+2]
	jsr getblk_2
; Header (255 255) check 
	lda BL_HDR_FOUND
	bne gs_calcln
	jmp errnobin
; Calculate length of the segment
gs_calcln 
	sec
	lda BL_SEG_HEAD+2        
	sbc BL_SEG_HEAD+0
	sta ICBLL+$10
	lda BL_SEG_HEAD+3
	sbc BL_SEG_HEAD+1
	sta ICBLH+$10
	inc ICBLL+$10
	bne gs_getd
	inc ICBLH+$10
; Read segment data to its location in the memory
gs_getd   
	ldy BL_SEG_HEAD
	lda BL_SEG_HEAD+1
	jsr getblk
; Perform jump through INITAD if needed
	lda INITAD
	and INITAD+1
	cmp #$FF
	beq postini
realini
	lda #$3C
	sta PACTL
	jsr DOINIT
	lda #$34
	sta PACTL
postini
	jmp getseg            
; Handle errors in GETBLK.
gberr
	cpy #$88
	bne errhndl             
	ldx #$FF                
	txs                      
	jsr fclose            
; Run the program          
	jmp (RUNAD)             
; Calls GETBLK with a length of 2 bytes.
getblk_2
	ldx #$2
	stx ICBLL+$10
	ldx #$0
	stx ICBLH+$10
; Subroutine that gets a blocks using CIO.
getblk    
	sta ICBAH+$10
	sty ICBAL+$10
	lda #$7
	jsr cio_op1
	bmi gberr
	rts
; Emulation of JSR(738)
DOINIT    
	jmp (INITAD)
; 
BL_SEG_HEAD
	.BYTE $0,$0,$0,$0
BL_HDR_FOUND 
	.BYTE $0
; Subroutine that closes file
fclose
	lda #$C
cio_op1
	ldx #$10
	sta ICCOM+$10  
	jmp CIOV
;Not a binary file
errnobin 
	print #loader_errorbin
	bne errsig
;I/O error 
errhndl  
	jsr cio_error
errsig   
	jsr keypress
	jmp init

; Subroutine Read key pressed
keypress
	lda #$FF
	sta CH
onkey
	lda CH
	cmp #$FF
	beq onkey
	rts

; Subroutine Error CIO
cio_error
	sty FR0
	lda #$0
	sta FR0+1
	jsr IFP
	jsr FASC
	ldy #$0
	sty $AE
	ldx #$8
cio_loop
	lda (INBUFF),y
	bmi cio_end
	sta error_number,x
	inx
	ldy $AE
	iny
	sty $AE
	jmp cio_loop
cio_end
	and #$7F
	sta error_number,x
	print #error_number
	rts

; Procedure open cio
.proc open (.byte chn+1, aux1+1, aux2+1 .word fname) .var
chn	
	ldx #$0
aux1
	mva #$0 ICAX1,x
aux2
	mva #$0 ICAX2,x
    mva #COPEN ICCOM,x
    mwa fname ICBAL,x
    jsr CIOV
	rts
fname
    .word 
.endp

; Procedure close cio
.proc close (.byte x) .reg
    mva #CCLOSE ICCOM,x
    jsr CIOV
	rts
.endp

; Procedure send cio
.proc send (.byte chn+1, type+1 .word buffer, length) .var
chn
	ldx #$0
type
    mva #$0 ICCOM,x
	mwa buffer ICBAL,x
    mwa length ICBLL,x
	jsr CIOV
	rts
buffer
	.word	
length
	.word
.endp

; Procedure print 
.proc print (.word text) .var
    ldx #$0
	mva #CPUTREC ICCOM,x
    mwa text ICBAL,x
	mwa #$A0 ICBLL,x
	jsr CIOV
	rts
text
	.word
.endp


; Text messages for screen ----------------------------------------------------------
menu1
	dta $7D,c" CASSETTE OPERATING SYSTEM  (MyCos) "*
:3	dta $7F
	dta c" By AsCrNet 2022 - V.1.0",$1D,$1D,$9D,$1D
	dta c"A. Return to BASIC",$1D,$9D
	dta c"B. Cassette deck motor "
msg_motor
	dta c"OFF"*,EOL	
menu2
	dta c"C. Verify saved to tape",$1D,$9D
	dta c"D. Loader binary file",$1D,$9D
	dta c"E. Recording MyCos on tape",$1D,$9D
	dta c"F. Reboot",$1D,$1D,$9D,$1D
	dta c"Select a letter",EOL
save_cos
	dta $1C,c"Press ",c"RECORD"*,c" + ",c"PLAY"*,c" and ",c"RETURN"*,c" to",$7F,$7F
	dta c"start recording",EOL
load_cas
	dta $1C,c"Press ",c"PLAY"*,c" + ",c"RETURN"*,c" to start reading",EOL
nobasic
	dta $1C,c"BASIC is deactivated",$FD,EOL
motor_on 
	dta c"ON"*,c" "
motor_off
	dta c"OFF"*
verify_ok
	dta $1D,c"Read smoothly from the tape",EOL
loader_errorbin
	dta $1D,c"Not file binary",$FD,EOL
error_number
	dta c"Error -     ",$FD,$FD,EOL


; Drive letter
drive 
	dta c"C:",EOL
	
:37 dta $0
	
; The end
end
;
;	run init