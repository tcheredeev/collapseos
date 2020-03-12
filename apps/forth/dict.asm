; A dictionary entry has this structure:
; - 7b name (zero-padded)
; - 2b prev pointer
; - 1b flags (bit 0: IMMEDIATE. bit 1: UNWORD)
; - 2b code pointer
; - Parameter field (PF)
;
; The code pointer point to "word routines". These routines expect to be called
; with IY pointing to the PF. They themselves are expected to end by jumping
; to the address at the top of the Return Stack. They will usually do so with
; "jp exit".
;
; That's for "regular" words (words that are part of the dict chain). There are
; also "special words", for example NUMBER, LIT, BRANCH, that have a slightly
; different structure. They're also a pointer to an executable, but as for the
; other fields, the only one they have is the "flags" field.

; Execute a word containing native code at its PF address (PFA)
nativeWord:
	jp	(iy)

; Execute a list of atoms, which usually ends with EXIT.
; IY points to that list.
compiledWord:
	push	iy \ pop hl
	inc	hl
	inc	hl
	; HL points to next Interpreter pointer.
	call	pushRS
	ld	l, (iy)
	ld	h, (iy+1)
	push	hl \ pop iy
	; IY points to code link
	jp	executeCodeLink

; Pushes the PFA directly
cellWord:
	push	iy
	jp	exit

; Pushes the address in the first word of the PF
sysvarWord:
	ld	l, (iy)
	ld	h, (iy+1)
	push	hl
	jp	exit

; The word was spawned from a definition word that has a DOES>. PFA+2 (right
; after the actual cell) is a link to the slot right after that DOES>.
; Therefore, what we need to do push the cell addr like a regular cell, then
; follow the link from the PFA, and then continue as a regular compiledWord.
doesWord:
	push	iy	; like a regular cell
	ld	l, (iy+2)
	ld	h, (iy+3)
	push	hl \ pop iy
	jr	compiledWord

; This word is followed by 1b *relative* offset (to the cell's addr) to where to
; branch to. For example, The branching cell of "IF THEN" would contain 3. Add
; this value to RS.
branchWord:
	push	de
	ld	l, (ix)
	ld	h, (ix+1)
	ld	a, (hl)
	call	addHL
	ld	(ix), l
	ld	(ix+1), h
	pop	de
	jp	exit

	.db	0b10		; Flags
BRANCH:
	.dw	branchWord

; Conditional branch, only branch if TOS is zero
cbranchWord:
	pop	hl
	ld	a, h
	or	l
	jr	z, branchWord
	; skip next byte in RS
	ld	l, (ix)
	ld	h, (ix+1)
	inc	hl
	ld	(ix), l
	ld	(ix+1), h
	jp	exit

	.db	0b10		; Flags
CBRANCH:
	.dw	cbranchWord

; This is not a word, but a number literal. This works a bit differently than
; others: PF means nothing and the actual number is placed next to the
; numberWord reference in the compiled word list. What we need to do to fetch
; that number is to play with the Return stack: We pop it, read the number, push
; it to the Parameter stack and then push an increase Interpreter Pointer back
; to RS.
numberWord:
	ld	l, (ix)
	ld	h, (ix+1)
	ld	e, (hl)
	inc	hl
	ld	d, (hl)
	inc	hl
	ld	(ix), l
	ld	(ix+1), h
	push	de
	jp	exit

	.db	0b10		; Flags
NUMBER:
	.dw	numberWord

; Similarly to numberWord, this is not a real word, but a string literal.
; Instead of being followed by a 2 bytes number, it's followed by a
; null-terminated string. This is not expected to be called in a regular
; context. Only words expecting those literals will look for them. This is why
; the litWord triggers abort.
litWord:
	call	popRS
	call	intoHL
	call	printstr	; let's print the word before abort.
	ld	hl, .msg
	call	printstr
	jp	abort
.msg:
	.db "undefined word", 0

	.db	0b10		; Flags
LIT:
	.dw	litWord

; ( R:I -- )
	.db ";"
	.fill 7
	.dw 0
EXIT:
	.dw nativeWord
; When we call the EXIT word, we have to do a "double exit" because our current
; Interpreter pointer is pointing to the word *next* to our EXIT reference when,
; in fact, we want to continue processing the one above it.
	call	popRS
exit:
	; Before we continue: is SP within bounds?
	call	chkPS
	; we're good
	call	popRS
	; We have a pointer to a word
	push	hl \ pop iy
	jp	compiledWord

; ( R:I -- )
	.db "QUIT"
	.fill 3
	.dw EXIT
	.db 0
QUIT:
	.dw nativeWord
quit:
	jp	forthRdLine

	.db "ABORT"
	.fill 2
	.dw QUIT
	.db 0
ABORT:
	.dw nativeWord
abort:
	; Reinitialize PS (RS is reinitialized in forthInterpret
	ld	sp, (INITIAL_SP)
	jp	forthRdLine
ABORTREF:
	.dw ABORT

	.db "BYE"
	.fill 4
	.dw ABORT
	.db 0
BYE:
	.dw nativeWord
	; Goodbye Forth! Before we go, let's restore the stack
	ld	sp, (INITIAL_SP)
	; unwind stack underflow buffer
	pop	af \ pop af \ pop af
	; success
	xor	a
	ret

; ( c -- )
	.db "EMIT"
	.fill 3
	.dw BYE
	.db 0
EMIT:
	.dw nativeWord
	pop	hl
	ld	a, l
	call	stdioPutC
	jp	exit

; ( c port -- )
	.db "PC!"
	.fill 4
	.dw EMIT
	.db 0
PSTORE:
	.dw nativeWord
	pop	bc
	pop	hl
	out	(c), l
	jp	exit

; ( port -- c )
	.db "PC@"
	.fill 4
	.dw PSTORE
	.db 0
PFETCH:
	.dw nativeWord
	pop	bc
	ld	h, 0
	in	l, (c)
	push	hl
	jp	exit

; ( addr -- )
	.db "EXECUTE"
	.dw PFETCH
	.db 0
EXECUTE:
	.dw nativeWord
	pop	iy	; is a wordref
executeCodeLink:
	ld	l, (iy)
	ld	h, (iy+1)
	; HL points to code pointer
	inc	iy
	inc	iy
	; IY points to PFA
	jp	(hl)	; go!

	.db ":"
	.fill 6
	.dw EXECUTE
	.db 0
DEFINE:
	.dw nativeWord
	call	entryhead
	ld	de, compiledWord
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	; At this point, we've processed the name literal following the ':'.
	; What's next? We have, in IP, a pointer to words that *have already
	; been compiled by INTERPRET*. All those bytes will be copied as-is.
	; All we need to do is to know how many bytes to copy. To do so, we
	; skip compwords until EXIT is reached.
	ex	de, hl		; DE is our dest
	ld	(HERE), de	; update HERE
	ld	l, (ix)
	ld	h, (ix+1)
.loop:
	call	HLPointsEXIT
	jr	z, .loopend
	call	compSkip
	jr	.loop
.loopend:
	; skip EXIT
	inc	hl \ inc hl
	; We have out end offset. Let's get our offset
	ld	e, (ix)
	ld	d, (ix+1)
	or	a		; clear carry
	sbc	hl, de
	; HL is our copy count.
	ld	b, h
	ld	c, l
	ld	l, (ix)
	ld	h, (ix+1)
	ld	de, (HERE)	; recall dest
	; copy!
	ldir
	ld	(ix), l
	ld	(ix+1), h
	ld	(HERE), de
	jp	exit


	.db "DOES>"
	.fill 2
	.dw DEFINE
	.db 0
DOES:
	.dw nativeWord
	; We run this when we're in an entry creation context. Many things we
	; need to do.
	; 1. Change the code link to doesWord
	; 2. Leave 2 bytes for regular cell variable.
	; 3. Get the Interpreter pointer from the stack and write this down to
	;    entry PFA+2.
	; 3. exit. Because we've already popped RS, a regular exit will abort
	;    colon definition, so we're good.
	ld	iy, (CURRENT)
	ld	hl, doesWord
	call	wrCompHL
	inc	iy \ inc iy		; cell variable space
	call	popRS
	call	wrCompHL
	ld	(HERE), iy
	jp	exit


	.db "IMMEDIA"
	.dw DOES
	.db 0
IMMEDIATE:
	.dw nativeWord
	ld	hl, (CURRENT)
	dec	hl
	dec	hl
	dec	hl
	set	FLAG_IMMED, (hl)
	jp	exit

; ( n -- )
	.db "LITERAL"
	.dw IMMEDIATE
	.db 1		; IMMEDIATE
LITERAL:
	.dw nativeWord
	ld	hl, (HERE)
	ld	de, NUMBER
	call	DEinHL
	pop	de		; number from stack
	call	DEinHL
	ld	(HERE), hl
	jp	exit

; ( -- c )
	.db "KEY"
	.fill 4
	.dw LITERAL
	.db 0
KEY:
	.dw nativeWord
	call	stdioGetC
	ld	h, 0
	ld	l, a
	push	hl
	jp	exit

	.db "CREATE"
	.fill 1
	.dw KEY
	.db 0
CREATE:
	.dw nativeWord
	call	entryhead
	jp	nz, quit
	ld	de, cellWord
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	ld	(HERE), hl
	jp	exit

	.db "HERE"
	.fill 3
	.dw CREATE
	.db 0
HERE_:	; Caution: conflicts with actual variable name
	.dw sysvarWord
	.dw HERE

	.db "CURRENT"
	.dw HERE_
	.db 0
CURRENT_:
	.dw sysvarWord
	.dw CURRENT

; ( n -- )
	.db "."
	.fill 6
	.dw CURRENT_
	.db 0
DOT:
	.dw nativeWord
	pop	de
	; We check PS explicitly because it doesn't look nice to spew gibberish
	; before aborting the stack underflow.
	call	chkPS
	call	pad
	call	fmtDecimalS
	call	printstr
	jp	exit

; ( n a -- )
	.db "!"
	.fill 6
	.dw DOT
	.db 0
STORE:
	.dw nativeWord
	pop	iy
	pop	hl
	ld	(iy), l
	ld	(iy+1), h
	jp	exit

; ( n a -- )
	.db "C!"
	.fill 5
	.dw STORE
	.db 0
CSTORE:
	.dw nativeWord
	pop	hl
	pop	de
	ld	(hl), e
	jp	exit

; ( a -- n )
	.db "@"
	.fill 6
	.dw CSTORE
	.db 0
FETCH:
	.dw nativeWord
	pop	hl
	call	intoHL
	push	hl
	jp	exit

; ( a -- c )
	.db "C@"
	.fill 5
	.dw FETCH
	.db 0
CFETCH:
	.dw nativeWord
	pop	hl
	ld	l, (hl)
	ld	h, 0
	push	hl
	jp	exit

; ( -- a )
	.db "LIT@"
	.fill 3
	.dw CFETCH
	.db 0
LITFETCH:
	.dw nativeWord
	call	readLITTOS
	push	hl
	jp	exit

; ( a b -- b a )
	.db "SWAP"
	.fill 3
	.dw LITFETCH
	.db 0
SWAP:
	.dw nativeWord
	pop	hl
	ex	(sp), hl
	push	hl
	jp	exit

; ( a b c d -- c d a b )
	.db "2SWAP"
	.fill 2
	.dw SWAP
	.db 0
SWAP2:
	.dw nativeWord
	pop	de		; D
	pop	hl		; C
	pop	bc		; B

	ex	(sp), hl	; A in HL
	push	de		; D
	push	hl		; A
	push	bc		; B
	jp	exit

; ( a -- a a )
	.db "DUP"
	.fill 4
	.dw SWAP2
	.db 0
DUP:
	.dw nativeWord
	pop	hl
	push	hl
	push	hl
	jp	exit

; ( a b -- a b a b )
	.db "2DUP"
	.fill 3
	.dw DUP
	.db 0
DUP2:
	.dw nativeWord
	pop	hl	; B
	pop	de	; A
	push	de
	push	hl
	push	de
	push	hl
	jp	exit

; ( a b -- a b a )
	.db "OVER"
	.fill 3
	.dw DUP2
	.db 0
OVER:
	.dw nativeWord
	pop	hl	; B
	pop	de	; A
	push	de
	push	hl
	push	de
	jp	exit

; ( a b c d -- a b c d a b )
	.db "2OVER"
	.fill 2
	.dw OVER
	.db 0
OVER2:
	.dw nativeWord
	pop	hl	; D
	pop	de	; C
	pop	bc	; B
	pop	iy	; A
	push	iy	; A
	push	bc	; B
	push	de	; C
	push	hl	; D
	push	iy	; A
	push	bc	; B
	jp	exit

; ( a b -- c ) A + B
	.db "+"
	.fill 6
	.dw OVER2
	.db 0
PLUS:
	.dw nativeWord
	pop	hl
	pop	de
	add	hl, de
	push	hl
	jp	exit

; ( a b -- c ) A - B
	.db "-"
	.fill 6
	.dw PLUS
	.db 0
MINUS:
	.dw nativeWord
	pop	de		; B
	pop	hl		; A
	or	a		; reset carry
	sbc	hl, de
	push	hl
	jp	exit

; ( a b -- c ) A * B
	.db "*"
	.fill 6
	.dw MINUS
	.db 0
MULT:
	.dw nativeWord
	pop	de
	pop	bc
	call	multDEBC
	push	hl
	jp	exit

; ( a b -- c ) A / B
	.db "/"
	.fill 6
	.dw MULT
	.db 0
DIV:
	.dw nativeWord
	pop	de
	pop	hl
	call	divide
	push	bc
	jp	exit

; ( a1 a2 -- b )
	.db "SCMP"
	.fill 3
	.dw DIV
	.db 0
SCMP:
	.dw nativeWord
	pop	de
	pop	hl
	call	strcmp
	call	flagsToBC
	push	bc
	jp	exit

; ( n1 n2 -- f )
	.db "CMP"
	.fill 4
	.dw SCMP
	.db 0
CMP:
	.dw nativeWord
	pop	hl
	pop	de
	or	a	; clear carry
	sbc	hl, de
	call	flagsToBC
	push	bc
	jp	exit

	.db "IF"
	.fill 5
	.dw CMP
	.db 1		; IMMEDIATE
IF:
	.dw nativeWord
	; Spit a conditional branching atom, followed by an empty 1b cell. Then,
	; push the address of that cell on the PS. ELSE or THEN will pick
	; them up and set the offset.
	ld	hl, (HERE)
	ld	de, CBRANCH
	call	DEinHL
	push	hl		; address of cell to fill
	inc	hl		; empty 1b cell
	ld	(HERE), hl
	jp	exit

	.db "ELSE"
	.fill 3
	.dw IF
	.db 1		; IMMEDIATE
ELSE:
	.dw nativeWord
	; First, let's set IF's branching cell.
	pop	de		; cell's address
	ld	hl, (HERE)
	; also skip ELSE word.
	inc	hl \ inc hl \ inc hl
	or	a		; clear carry
	sbc	hl, de		; HL now has relative offset
	ld	a, l
	ld	(de), a
	; Set IF's branching cell to current atom address and spit our own
	; uncondition branching cell, which will then be picked up by THEN.
	; First, let's spit our 4 bytes
	ld	hl, (HERE)
	ld	de, BRANCH
	call	DEinHL
	push	hl		; address of cell to fill
	inc	hl		; empty 1b cell
	ld	(HERE), hl
	jp	exit

	.db "THEN"
	.fill 3
	.dw ELSE
	.db 1		; IMMEDIATE
THEN:
	.dw nativeWord
	; See comments in IF and ELSE
	pop	de		; cell's address
	ld	hl, (HERE)
	; There is nothing to skip because THEN leaves nothing.
	or	a		; clear carry
	sbc	hl, de		; HL now has relative offset
	ld	a, l
	ld	(de), a
	jp	exit

	.db "RECURSE"
	.dw THEN
	.db 0
RECURSE:
	.dw nativeWord
	call	popRS
	ld	l, (ix)
	ld	h, (ix+1)
	dec	hl \ dec hl
	push	hl \ pop iy
	jp	compiledWord

LATEST:
	.dw RECURSE