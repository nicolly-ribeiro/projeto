list P=16F818
	radix dec
	include <p16f818.inc>
	__config _WDT_OFF & _PWRTE_OFF & _INTRC_IO & _MCLR_ON & _BODEN_ON & _LVP_OFF & _CPD_OFF & _WRT_ENABLE_OFF & _DEBUG_OFF & _CCP1_RB2 & _CP_OFF

#define Timer1Div	1000	; Divide a freq do Timer1, obtendo 250Hz. Essa ÃƒÂ© a freqÃƒÂ¼ÃƒÂªncia
#define	Timer1Value	(65536-Timer1Div) ; de atualizaÃƒÂ§ÃƒÂµes do display (bastante confortÃƒÂ¡vel)
#define eAtraso		10	; Atraso entre visualizaÃƒÂ§ÃƒÂµes sucessivas (em dÃƒÂ©cimos de seg.)

#define DebConst	5	; Valor de recarga do contador debouncer
#define InitConst	(3*72)	; Valor de recarga do contador de inicializaÃƒÂ§ÃƒÂ£o
#define aInterConst	3	; Valor de recarga do timer de visualizaÃƒÂ§ÃƒÂ£o alternativa
;
#define DS0_ON	PORTA,4		; HabilitaÃƒÂ§ÃƒÂ£o para displays
#define DS1_ON	PORTA,6
#define DS2_ON	PORTA,7

#define Chave	PORTA,2		; Porta digital ligada a uma chave

#define LED0_ON	LEDS,0		; Aciona led 0
#define LED1_ON	LEDS,1		; Aciona led 1

#define LED0_ON	LEDS,2		; Aciona led 2
#define LED1_ON	LEDS,3		; Aciona led 3

#define MostraMax Estado,1	; Exibe a temperatura mÃƒÂ¡xima
#define MostraMin Estado,0	; Exibe a temperatura mÃƒÂ­nima
#define Chave_ON  Estado,4	; Indica que a chave estÃƒÂ¡ pressionada
#define Init_ON	  Estado,5	; Flag indicando pedido de inicializaÃƒÂ§ÃƒÂ£o
#define Go_ON	  Estado,6	; Indica que deve interromper o atraso em Main

#define EESignature	0xAB0A	; Assinatura da EEPROM, indicando estar inicializada
#define EESig		0	; Local da assinatura da EEPROM
#define EESigh		1
#define EETempMin	2	; PosiÃƒÂ§ÃƒÂµes da EEPROM onde vamos
#define EETempMinh	3	; guardar as temperaturas
#define EETempMax	4	; mÃƒÂ­nima e mÃƒÂ¡xima
#define EETempMaxh	5

#define EEConfBits	6	; Bits de configuraÃƒÂ§ÃƒÂ£o:
#define EEEscala	0	; bit0: 0=Celsius, 1=Farenheit

#define _carry	STATUS,C
#define _zero   STATUS,Z

; 
; ------------------------------------------------------------------------------
; Ajustes de calibraÃƒÂ§ÃƒÂ£o
;
      ifdef BREAD_BOARD
; VersÃƒÂ£o 1 (proto-board)
#define TensaoRef 1600					; em milivolts, Vdd=5.00V
#define AjusteOff 0					; ajuste
      else
; VersÃƒÂ£o 2 (circuito impresso)
#define TensaoRef 918					; em milivolts
#define AjustePer (1+0/100)				; ajuste percentual
#define AjusteAms 0					; ajuste de deslocamento amostragem
      endif
#define Multiplicador ((AjustePer*TensaoRef*100+512)/1023+AjusteAms) ; fator amostra->temperatura
#define AjusteTempPer	(100+0)				; ajuste percentual da temperatura
#define AjusteTempOff	0				; deslocamento em milesimos de graus Celsius

;
; Esta macro realiza multiplicaÃƒÂ§ÃƒÂ£o rÃƒÂ¡pida em precisÃƒÂ£o dupla de h:l por uma constante,
; uilizando B2:B1:B0 como area de trabalho.

Mult24k	macro	u,h,l,k
	local step, i
step 	set 0
i	set k
	movf	l,W		; Salva u:h:l em B2:B1:B0
	movwf	B0
	movf	h,W
	movwf	B1
	movf	u,W
	movwf	B2
  while i!=0
    if (i&1)==1
      if step==0
	movf	B0,W	; Primeira vez: move B2:B1:B0 para u:h:l
	movwf	l
	movf	B1,W
	movwf	h
	movf	B2,W
	movwf	u
      else
	movf	B0,W	; Demais vezes: soma B2:B1:B0 em u:h:l
	addwf	l,F
	movlw	1
	btfsc	_carry
	addwf	h,F
	btfsc	_carry
	incf	u,F
	movf	B1,W
	addwf	h,F
	btfsc	_carry
	incf	u,F
	movf	B2,W
	addwf	u,F
      endif
step 	set step+1
    endif
	bcf	_carry	; Faz B2:B1:B0 = 2 * B2:B1:B0
	rlf	B0,F
	rlf	B1,F
	rlf	B2,F
i 	set i>>1
  endw
 	endm

;
; Macro para comparar dois inteiros em precisÃƒÂ£o dupla sem sinal
Comp16U macro	Xhi,Xlo,Yhi,Ylo
	movf	Xhi,W
	subwf	Yhi,W			; subtract Y-X
	btfss	_zero			; Are they equal ?
	goto	$+3			; No, they are not
	movf	Xlo,W			; yes, they are equal, compare lo
	subwf	Ylo,W			; subtract Y-X
; results:
	; if X=Y then now Z=1.
	; if Y<X then now C=0.
	; if X<=Y then now C=1.
	endm

;
; Macro usada pelo algoritmo de divisÃƒÂ£o
; -------------------------------------
; Este mÃƒÂ©todo ÃƒÂ© similar ao de divisÃƒÂ£o realizada com lÃƒÂ¡pis e papel.

divMac  macro
	bcf	_carry
	rlf	D0,F		; Desloca o dividendo para a esquerda,
	rlf	D1,F
	rlf	D2,F
	rlf	C0,F		; e para dentro do resto c.
	movf	B0,W		; Faz W=c-b
	subwf	C0,W		
	btfsc	_carry		; O carry serÃƒÂ¡ igual a 1 se c>=b
	movwf	C0		; Nesse caso c=c-b
	rlf	A0,F		; Deslocamos o carry para dentro do quociente
	rlf	A1,F
	rlf	A2,F
	endm
	
; Macros para selecionar o bloco de memÃƒÂ³ria
;
BANK0	macro
	bcf	STATUS,RP0 	; SELECIONA BANK1 DA MEMORIA RAM
	bcf	STATUS,RP1	; SELECIONA BANK0 DA MEMORIA RAM
	endm
BANK1	macro
	bsf	STATUS,RP0 	; SELECIONA BANK1 DA MEMORIA RAM
	bcf	STATUS,RP1	; SELECIONA BANK0 DA MEMORIA RAM
	endm
BANK2	macro
	bcf	STATUS,RP0 	; SELECIONA BANK1 DA MEMORIA RAM
	bsf	STATUS,RP1	; SELECIONA BANK0 DA MEMORIA RAM
	endm
BANK3	macro
	bsf	STATUS,RP0 	; SELECIONA BANK1 DA MEMORIA RAM
	bsf	STATUS,RP1	; SELECIONA BANK0 DA MEMORIA RAM
	endm
;
;
; Variaveis em memÃƒÂ³ria RAM
;
	cblock	0x20
	W_T1		; backup do registro W durante a interrupcao T1 (tambÃƒÂ©m no banco1)
	A0		; Registradores de uso geral
	A1
	A2
	A3
	B0
	B1
	B2
	B3
	C0
	C1
	C2
	C3
	D0
	D1
	D2
	D3
	D4
	D5
	DS0		; cache para display de dezenas
	DS1		; idem, para unidades
	DS2		; idem, para decimos de unidade
	LEDS		; cache para os LEDs externos
	eData		; Dado a gravar na EEPROM
	eInterval	; Tempo de modo de visualizaÃƒÂ§ÃƒÂ£o alternativo
	Estado		; Estado do display Temp atual/Temp maxima/Temp Minima/Chave
	STATUS_T1 	; idem para o registro STATUS
	TEMPO0		; Usados pelo Delay_MS e Delay_S
	TEMPO1
	TEMPO2
	DebCounter	; Contador para key debounce
	InitCounter	; Contador para iniciazaÃƒÂ§ÃƒÂ£o via chave
	TempMin		; Temperatura minima registrada (Passar isto para a EEPROM)
	TempMinh
	TempMax		; Temperatura maxima registrada
	TempMaxh
;
	TopOfBank0	; Marca o topo do banco0 da RAM: nÃƒÂ£o usar!
	endc
;
; Alerta o programador para estouro do banco0
    if	TopOfBank0>0x80
	error "Estouro do banco0 da RAM"
    endif

	cblock	0xa0
	W_T1a		; backup do registro W durante a interrupcao T1 (tambÃƒÂ©m no banco0)
;
; Armazena as leituras mais recentes de temperatura a fim de calcular a temperatura mÃƒÂ©dia
;
	CurTemp		; indice indicando a temperatura atual (0:max-1)
	Temps00L	; Tabela de leituras de temperaturas (em nÃƒÂºmero de amostras)
	Temps00H
	Temps01L
	Temps01H
	Temps02L
	Temps02H
	Temps03L
	Temps03H
	Temps04L
	Temps04H
	Temps05L
	Temps05H
	Temps06L
	Temps06H
	Temps07L
	Temps07H
	Temps08L
	Temps08H
	Temps09L
	Temps09H
	TempsTopL
	TempsTopH
;
	TopOfBank1	; Marca o topo do banco1 da RAM: nÃƒÂ£o usar!
	endc
;
; Alerta o programador para estouro do banco1
    if	TopOfBank0>0xc0
	error "Estouro do banco1 da RAM"
    endif

#define TempsSize (1+(TempsTopL-Temps00L)/2)

; ---------------------------------------------------------------------
; Ponto de inÃƒÂ­cio de execuÃƒÂ§ÃƒÂ£o
;
	ORG	0
	nop
	movlw   high Inicializa
	movwf   PCLATH         	; Inicializa o PCLATH. NecessÃƒÂ¡rio pois usamos jump-table
	goto	Inicializa

; ---------------------------------------------------------------------
; Ponto de entrada de interrupÃƒÂ§ÃƒÂµes
	org	4
	movwf	W_T1		; Salva o status do processo durante a interrupcao (bancoX)
	swapf	STATUS,W	; Salva status do processo em W (movf estraga o flag Z!)
	clrf	STATUS		; Volta ao banco0, independentemente do banco selecionado
	movwf	STATUS_T1	; Guarda o status do processo na variÃƒÂ¡vel STATUS_T1
	
; --------------------------------------------------------------------
; Recarga do Timer1. Como estamos no inÃƒÂ­cio da rotina de interrupÃƒÂ§ÃƒÂ£o,
; passaram-se poucos ciclos desde que o Timer1 estourou de 0xFFFF para
; 0x0000. Por causa disso, TMR1H deve estar zerado e TMR1L contÃƒÂ©m
; algum valor baixo (pois a contagem nÃƒÂ£o pÃƒÂ¡ra). Nessas condiÃƒÂ§ÃƒÂµes, nÃƒÂ£o
; hÃƒÂ¡ problema em recarregar TMR1H com outro valor, mas escrever no
; TMR1L pode causar erros de temporizaÃƒÂ§ÃƒÂ£o. Por exemplo, escrever nesse
; registrador causa a perda de 2 ciclos na contagem. Para procurar
; manter a precisÃƒÂ£o, vamos contabilizar os dois ciclos perdidos somando
; 2 ao valor da recarga, e vamos tambÃƒÂ©m somar ao registrador TMR1L
; ao invÃƒÂ©s de escrever nele diretamente.

	movlw	high (Timer1Value+2)
	movwf	TMR1H			; Escreve na parte alta do Registrador Timer1
	movlw	low (Timer1Value+2)
	addwf	TMR1L,F			; Soma na parte baixa do Registrador Timer1
	btfsc	_carry			; Se estourou, entÃƒÂ£o
	incf	TMR1H,F			; soma 1 na parte alta desse registrador.
	bcf	PIR1,TMR1IF		; Limpa o flag de estouro do Timer1

; -------------------------------------------------------
; Usa a presente interrupcao para atualizar o display.
; Isto eh feito alternando-se para o proximo digito,
; pois somente um pde ser exibido por vez. Primeiro
; apagamos todos os digitos. Depois de identificarmos
; qual estava aceso, habilitamos o proximo digito.
; Por fim, lemos a posicao de memoria contendo aquele
; digito, o transformamos em codificacao 7-segmentos
; e o acendemos atravez da porta B.
;
AtualizaDisplay
	clrf	PORTB			; apaga o display durante a atualizaÃƒÂ§ÃƒÂ£o
	btfsc	DS0_ON
	goto	HabilitaDS1
	btfsc	DS1_ON
	goto	HabilitaDS2

HabilitaDS0
	bcf	DS1_ON
	bcf	DS2_ON
	bsf	DS0_ON			; habilita display 0
	movf	DS0,W
	addlw	0
	btfss	_zero
	call	bcd27
	btfsc	LED0_ON			; Vai acender o led 0?
	iorlw	1
	goto	AcendeDisplay

HabilitaDS1
	bcf	DS0_ON
	bcf	DS2_ON
	bsf	DS1_ON			; habilita display 1
	movf	DS1,W
	call	bcd27
	btfsc	LED1_ON			; Vai acender o led 1?
	iorlw	1
	goto	AcendeDisplay

HabilitaDS2
	bcf	DS0_ON
	bcf	DS1_ON
	bsf	DS2_ON			; habilita display 2
	movf	DS2,W
	call	bcd27

AcendeDisplay
	movwf	PORTB			; acende o digito habilitado

; -------------------------------------
; Faz o tratamento debounce da chave
	movf	DebCounter,F
	btfss	_zero		; Contador debouncer chegou a zero?
	goto	DecDebouncer	; Ainda nÃƒÂ£o, salta o processamento de chave

	btfsc	Chave		; A chave ainda estÃƒÂ¡ pressionada? (ativa em zero)
	bcf	Chave_ON	; NÃƒÂ£o, agora nÃƒÂ£o estÃƒÂ¡ mais
	btfsc	Chave_ON	; A chave estava pressionada antes?
	goto	TestarInit	; A chave nÃƒÂ£o foi liberada e podemos sair
	btfsc	Chave		; A chave nÃƒÂ£o estava pressionada, mas agora estÃƒÂ¡?
	goto	RetornaIE		; NÃƒÂ£o estÃƒÂ¡ pressionada. Podemos sair

; Detectamos o momento de pressÃƒÂ£o da chave: vamos alternar o estado
;
	movlw	DebConst	; Inicia o contador debouncer
	movwf	DebCounter
	movlw	InitConst	; Inicia o contador de inicializaÃƒÂ§ÃƒÂ£o
	movwf	InitCounter
	bsf	Go_ON		; Interrompe o atraso em Main
	bsf	Chave_ON	; Sinaliza chave pressionada
	btfsc	MostraMin	; Estamos mostrando a temp minima?
	goto	VaiMostrarMax	; Sim, estamos.
	btfsc	MostraMax	; Estamos mostrando a temp mÃƒÂ¡xima?
	goto	VaiMostrarAtual	; Sim, estamos.

; Vamos passar a mostrar a temperatura mÃƒÂ­nima
;
VaiMostrarMin
	movlw	aInterConst
	movwf	eInterval
	bsf	MostraMin
	bcf	MostraMax
	goto	RetornaIE

; Vamos passar a mostrar a temperatura MÃƒÂ¡xima
;
VaiMostrarMax
	movlw	aInterConst
	movwf	eInterval
	bsf	MostraMax
	bcf	MostraMin
	goto	RetornaIE

; Vamos passar a mostrar a temperatura atual
;
VaiMostrarAtual
	bcf	MostraMax
	bcf	MostraMin
	clrf	LEDS
	goto	RetornaIE

TestarInit				; Chave_ON estÃƒÂ¡ ligado
	btfsc	Chave			; A chave ainda estÃƒÂ¡ pressionada? (ativa em zero)
	goto	RetornaIE		; NÃƒÂ£o, agora nÃƒÂ£o estÃƒÂ¡ mais

	movf	InitCounter,F		; O contador de inicializaÃƒÂ§ÃƒÂ£o jÃƒÂ¡ chegou a zero?
	btfsc	_zero
	goto	RetornaIE		; Sim, jÃƒÂ¡ chegou: nada a fazer

	decfsz	InitCounter,F		; Decrementamos o contador de Init
	goto	RetornaIE		; se ainda nÃƒÂ£o zerou, seguimos adiante

	bsf	Init_ON			; ligamos o flag de inicializaÃƒÂ§ÃƒÂ£o
	goto	RetornaIE
	
DecDebouncer
	decf	DebCounter,F

; Restaura o contexto e retorna da interrupÃƒÂ§ÃƒÂ£o
;
RetornaIE
	swapf	STATUS_T1,W		; Recupera o status do processo
	movwf	STATUS			; e o restaura. Estamos de volta ao bancoX
	swapf	W_T1,F			; Recupera o registrador W (movf estraga o flag Z,
	swapf	W_T1,W			; por isso usamos swapf, que ÃƒÂ© inerte)
	retfie

; -------------------------------------
; Converte o numero em W para codificaÃƒÂ§ÃƒÂ£o 7-segmentos
bcd27
	andlw	0fh		; garante que o digito esteja entre 0 e 15
	addwf	PCL,F		; salta para dentro da tabela
	;         gfedcbaL	; L = LED externo
	retlw	B'01111110'	; 0
	retlw	B'00001100'	; 1
	retlw	B'10110110'	; 2
	retlw	B'10011110'	; 3
	retlw	B'11001100'	; 4
	retlw	B'11011010'	; 5
	retlw	B'11111010'	; 6
	retlw	B'00001110'	; 7
	retlw	B'11111110'	; 8
	retlw	B'11011110'	; 9
	retlw	B'11101110'	; A
	retlw	B'11111000'	; b
	retlw	B'01110010'	; C
	retlw	B'10111100'	; d
	retlw	B'11110010'	; E
	retlw	B'11100010'	; F


; ------------------------------------------------------------------
; Faz a inicializaÃƒÂ§ÃƒÂ£o do hardware, atribuindo valores para os
; vÃƒÂ¡rios registradores de controle da CPU e dos perifÃƒÂ©ricos,
; zera o banco 0 da RAM, e inicia o timer TMR1
;
Inicializa
;
; ConfiguraÃƒÂ§ÃƒÂ£o do oscilador, do clock do sistema e da fonte
; de clock para o TMR1
	banksel	OSCCON
	movlw	B'01110000'	; Oscilador interno, freqÃƒÂ¼ÃƒÂªncia de 8Mhz
	movwf	OSCCON
	banksel	T1CON
	movlw	B'00110000'	; Timer1, clock interno, f/8
	movwf	T1CON		
;
; ConfiguraÃƒÂ§ÃƒÂ£o do registro de controle de interrupÃƒÂ§ÃƒÂµes
	movlw	B'01000000'	; habilita interrupÃƒÂ§ÃƒÂµes de perifÃƒÂ©ricos
	movwf	INTCON
;
; PÃƒÂµe as portas A e B em nivel lÃƒÂ³gico zero
	clrf	PORTB
	clrf	PORTA
;
; Determina quais perifÃƒÂ©ricos podem gerar interrupÃƒÂ§ÃƒÂµes
	banksel	PIE1
	movlw	B'00000001'	; Habilita interrupcao TMR1
	movwf	PIE1		; PIE1 controla interrupÃƒÂ§ÃƒÂµes dos perifÃƒÂ©ricos
;
; Configura os bits das portas A e B
	movlw	B'00101111'	; RA3 Vref+, RA2 Vref-, RA4,RA6 e RA7 sao saidas
	movwf	TRISA
	movlw	B'00000000'	; all inputs
	movwf	TRISB	
;
; Determina quais portas de entrada sÃƒÂ£o digitais e quais sÃƒÂ£o analÃƒÂ³gicas
	movlw	B'11000101'	; Entradas analogicas RA0 e RA1, Vref+, Vref-, I/O RA4, f/2 
	movwf	ADCON1

	banksel	CCP1CON		; ConfiguraÃƒÂ§ÃƒÂ£o da Captura/ComparaÃƒÂ§ÃƒÂ£o/PWM (nÃƒÂ£o usados)
	movlw	00
	movwf	CCP1CON		; Desabilita captura, comparaÃƒÂ§ÃƒÂ£o e pwm

	movlw	B'01000000'	; Desliga o mÃƒÂ³dulo A/D. SerÃƒÂ¡ ligado quando necessÃƒÂ¡rio
	movwf	ADCON0
;
	banksel	OPTION_REG
	movlw	B'10000000'	; Desabilita pull-ups (usamos resistores externos)
	movwf	OPTION_REG	; Configura opÃƒÂ§ÃƒÂµes

	banksel	PORTA
	clrf	PORTB
	clrf	PORTA

; -----------------------------------------------------
; Inicializacao da RAM - zera os blocos 0 e 1
	bcf	STATUS,IRP	; Seleciona bancos 0-1

	banksel	0x20		; Liga o banco0
	movlw	0x20		; Carrega o endereÃƒÂ§o da primeira posiÃƒÂ§ÃƒÂ£o do bloco0
	movwf	FSR		; no registrador de endereÃƒÂ§amento indireto
	movwf	0x7f		; Valor nÃƒÂ£o-nulo na ÃƒÂºltima posiÃƒÂ§ÃƒÂ£o do bloco0
	clrf	INDF
	incf	FSR,F
	movf	0x7f,F		; Zerou a ÃƒÂºltima posiÃƒÂ§ÃƒÂ£o?
	btfss	_zero		; Sim, zerou; pode sair do laÃƒÂ§o
	goto	$-4		; Ainda nÃƒÂ£o acabou; continua no laÃƒÂ§o

	banksel	0xa0		; Liga o banco1
	movlw	0xa0		; Carrega o endereÃƒÂ§o da primeira posiÃƒÂ§ÃƒÂ£o do bloco1
	movwf	FSR		; no registrador de endereÃƒÂ§amento indireto
	movwf	0xbf		; Valor nÃƒÂ£o-nulo na ÃƒÂºltima posiÃƒÂ§ÃƒÂ£o do bloco1
	clrf	INDF
	incf	FSR,F
	movf	0xbf,F		; Zerou a ÃƒÂºltima posiÃƒÂ§ÃƒÂ£o?
	btfss	_zero		; Sim, zerou; pode sair do laÃƒÂ§o
	goto	$-4		; Ainda nÃƒÂ£o acabou; continua no laÃƒÂ§o

	clrf	STATUS		; volta ao banco0

; -----------------------------------------------------
; Aguarda a estabilizaÃƒÂ§ÃƒÂ£o dos perifÃƒÂ©ricos

	movlw	250
	call	Delay_ms

; -----------------------------------------------------
; Inicializa e liga o TMR1
	movlw	high Timer1Value
	movwf	TMR1H
	movlw	low Timer1Value		
	movwf	TMR1L			; RECARREGA CONTADOR DO TMR1
	bsf	T1CON,TMR1ON		; liga tmr1
	
	bcf	PIR1,TMR1IF		; Habilita interrupcao do TMR1
	bsf	INTCON,GIE		; Habilita interrupcoes

; Inicializa a tabela de temperaturas com medidas reais
;
	movlw	TempsSize
	movwf	B0
	call	FazMedida	; Faz a conversao A/D em A1:A0
	call	ArmazenaTemp	; Poe na tabela
	decfsz	B0,F
	goto	$-3

	movf	A0,W		; Inicializa temperaturas mÃƒÂ¡xima e mÃƒÂ­nima
	movwf	TempMin		; Por fazer: estas devem ser guardadas da EEPROM
	movwf	TempMax
	movf	A1,W
	movwf	TempMinh
	movwf	TempMaxh

;
; Inicializa a EEPROM, caso necessÃƒÂ¡rio
	movlw	EESig		; A EEPROM estÃƒÂ¡ assinada?
	call	EERead
	sublw	low EESignature
	btfss	_zero
	call	EEInit		; Inicializa a EEPROM, se nÃƒÂ£o estiver assinada

	movlw	EESigh
	call	EERead
	sublw	high EESignature
	btfss	_zero
	call	EEInit		; Inicializa a EEPROM, se nÃƒÂ£o estiver assinada
;
	call	EEReadTemps	; Recupera as temperaturas registradas na EEPROM

; --------------------------------------------------------------------------------
;
; MÃƒÂ³dulo principal - Permanece em loop realizando as
; sucessivas tarefas do termÃƒÂ´metro. Exibe o resultado.
;
; --------------------------------------------------------------------------------
;
MainLoop
	call	FazMedida	; Faz a conversao A/D em A1:A0
	call	ArmazenaTemp	; Poe A1:A0 na tabela

	call	MediaTemp	; Calcula a media da tabela e poe em A2:A1:A0

	btfsc	Init_ON		; O usuÃƒÂ¡rio quer apagar tudo?
	call	ApagaTudo	; sim, entÃƒÂ£o vamos apagar

	call	MaxMin		; Registra temperaturas mÃƒÂ¡xima e mÃƒÂ­nima

; Alterna para o modo de exibiÃƒÂ§ÃƒÂ£o escolhido pelo usuÃƒÂ¡rio: normal/max/min
;
	btfss	MostraMin	; Mostra temperatura mÃƒÂ­nima?
	goto	Main1		; NÃƒÂ£o, siga adiante.

	decfsz	eInterval,F	; Decrementa o contador de exibiÃƒÂ§ÃƒÂ£o alternativa
	goto	MainMostraMin
	goto	MainMostraNormal

MainMostraMin
	movf	TempMin,W	; Vamos exibir a temperatura mÃƒÂ­nima
	movwf	A0
	movf	TempMinh,W
	movwf	A1
	bsf	LED0_ON
	bcf	LED1_ON
	goto	MainMostra

Main1	btfss	MostraMax	; Mostra a temperatura mÃƒÂ¡xima?
	goto	Main3		; NÃƒÂ£o, siga adiante.

	decfsz	eInterval,F	; Decrementa o contador de exibiÃƒÂ§ÃƒÂ£o alternativa
	goto	MainMostraMax
	goto	MainMostraNormal

MainMostraMax
	movf	TempMax,W	; Vamos exibir a temperatura mÃƒÂ¡xima
	movwf	A0
	movf	TempMaxh,W
	movwf	A1
	bcf	LED0_ON
	bsf	LED1_ON
	goto	MainMostra
	
MainMostraNormal
	clrf	LEDS
	bcf	MostraMax
	bcf	MostraMin

Main3				; Mostrando a temperatura normal
	comf	LEDS,F		; Alternamos os leds para indicar funcionamento

MainMostra
	call	ComputeTemp	; Transforma a medida em temperatura em A2:A1:A0

	call	EEReadScale	; Estamos usando Celsius ou Ferenheit?
	btfsc	_zero
	goto	MainMostraCelsius

; Converte a temperatura de Celsius para Ferenheit
	Mult24k	A2,A1,A0,9	; Multiplica A2:A1:A0 por 9
	movlw	5
	movwf	B0
	call	Divisao248	; Depois divide A2:A1:A0 por 5
	movlw	low 32000	; Soma 32.000
	call	Soma248		; A2:A1:A0 = A2:A1:A0 + 32000
	movlw	high 32000
	addwf	A1,F
	btfsc	_carry
	incf	A2,F

MainMostraCelsius
	movlw	50		; Soma 0.05 ao resultado para arredondar
	call	Soma248		; A2:A1:A0 = A2:A1:A0 + 50
	call	BinDec		; Converte de binÃƒÂ¡rio para decimal
	call	MostraTemp	; Copia a temperatura para a cache do display

	movlw	eAtraso		; Atraso de 1 segundo
	call	Delay_ds
	goto	MainLoop	; Volta o ponto inicial

; ----------------------------------------------------------------
; Inicializa as temperaturas mÃƒÂ­nima e mÃƒÂ¡xima e troca a escala
; de exibiÃƒÂ§ÃƒÂ£o entre Celsius e Farenheit
; --------------------------------
; Assume que A1:A0 tem uma temperatura inicial
;
ApagaTudo
	movf	A0,W
	movwf	TempMin
	movwf	TempMax
	movf	A1,W
	movwf	TempMinh
	movwf	TempMaxh
	call	EEWriteTemps
	movlw	EEConfBits
	call	EERead
	xorlw	(1<<EEEscala)
	movwf	eData
	movlw	EEConfBits
	call	EEWrite
	bcf	Init_ON
	bcf	MostraMax
	bcf	MostraMin
	clrf	LEDS
	return

; ----------------------------------------------------------------
; Atraso de milisegundos
; ----------------------
; Entrada: W=nÃƒÂºmero de milisegundos
;
Delay_ms
	movwf	TEMPO1

Delay_ms_loop	
	movlw	1+10*(250-3+8)/15	; Atraso de 250 microsegundos
	call	Delay_us
	movlw	1+10*(250-3+8)/15	; Atraso de 250 microsegundos
	call	Delay_us
	movlw	1+10*(250-3+8)/15	; Atraso de 250 microsegundos
	call	Delay_us
	movlw	1+10*(250-3+8)/15	; Atraso de 250 microsegundos
	call	Delay_us

	decfsz	TEMPO1,F
	goto	Delay_ms_loop
	return				; RETORNA

;
; Atraso de segundos
; Entrada: W=nÃƒÂºmero de segundos do atraso
Delay_ss
	movwf	TEMPO0

Delay_ss_loop
	movlw	250			; 250 ms
	call	Delay_ms
	movlw	250			; 250 ms
	call	Delay_ms
	movlw	250			; 250 ms
	call	Delay_ms
	movlw	250			; 250 ms
	call	Delay_ms

	decfsz	TEMPO0,F
	goto	Delay_ss_loop
	return		

; Atraso de dÃƒÂ©cimos de segundos com interrupÃƒÂ§ÃƒÂ£o
; ---------------------------------------------
Delay_ds
	movwf	TEMPO0
	btfsc	Init_ON			; Estamos inicializando?
	goto	$+3			; sim, atraso normal
	btfsc	Go_ON			; Devemos interromper o atraso normal?
	goto	Delay_dsInt		; Sim, devemos interromper
	movlw	100			; 100ms
	call	Delay_ms
	decfsz	TEMPO0,F
	goto	$-5
	return
Delay_dsInt
	bcf	Go_ON			; Eh, mas somente esta vez.
	return

; Atraso de microsegundos
; -----------------------
; Entrada: W=n, ÃƒÂ© o nÃƒÂºmero de repetiÃƒÂ§ÃƒÂµes do laÃƒÂ§o interno.
; Com clock de 8MHz, o perÃƒÂ­odo de uma instruÃƒÂ§ÃƒÂ£o simples ÃƒÂ© de 500ns 
; (pois o clock ÃƒÂ© internamente divido por 4). InstruÃƒÂ§ÃƒÂµes de saltos
; tomam 1.0us. O tempo total desta rotina ÃƒÂ© dado por:
; 3.0 + 1.5*(n-1) microsegundos. Para um atraso de t microsegundos,
; devemos escolher n do seguinte modo: n>=1+(t-3)/1.5, onde
; 3us <= t <= 385us (n<=256).
;
Delay_us
	movwf	TEMPO2			; 0.5us
	nop				; 0.5us
	decfsz	TEMPO2,F		; n*0.5us
	goto	$-1			; (n-1)*1.0us + 0.5us
	return				; 1.0us
;					Total: 3.0 + 1.5*(n-1) us

; ---------------------------------------------------------------
; Copia a temperatura em D4:D3 para a cache do display DS0-DS2
; As interrupÃƒÂ§ÃƒÂµes sÃƒÂ£o desabilitadas durante esta operaÃƒÂ§ÃƒÂ£o
;
MostraTemp
	bcf	INTCON,GIE		; Desabilita interrupÃƒÂ§ÃƒÂµes
	movf	D4,W			
	movwf	DS0
	movf	D3,W
	movwf	DS1
	movf	D2,W
	movwf	DS2
	bsf	INTCON,GIE		; Habilita interrupÃƒÂ§ÃƒÂµes
	return

; ---------------------------------------------------------------
; Usa o conversor A/D para medir a temperatura (voltagem) do LM35DZ
; Retorna o resultado em nÃƒÂºmero de amostras em A1:A0
FazMedida
	banksel	ADCON0
	movlw	B'00000001'		; Seleciona clock f/4, canal 0=AN0, ativa o modulo A/D 
	movwf	ADCON0
	bcf	PIR1,ADIF		; Desabilita interrupcao do conversor A/D
	movlw	1+10*(40-3+8)/15	; Aguarda 40us para carga do capacitor (11.5us min.)
	call	Delay_us		; permitindo a carga do capacitor interno C_hold
	bsf	ADCON0,GO		; Inicia a conversao A/D

EsperaMedida
					; Monitora o bit GO, aguardando termino da conversao
	btfsc	ADCON0,GO		; Chegou ao final da conversao
	goto	EsperaMedida		; Ainda nao, continua esperando
	nop
	movf	ADRESH,W
	movwf	A1
	banksel	ADRESL
	movf	ADRESL,W
	banksel A0
	movwf	A0
	bcf	PIR1,ADIF		; Limpa interrupcao do conversor A/D
	bcf	ADCON0,ADON		; Desliga o modulo A/D, poupando energia
	return

; ------------------------------------------------------------
; Armazena a temperatura atual (medida em amostras) em uma
; tabela.
; Entrada: A1:A0
;
ArmazenaTemp
	bcf	STATUS,IRP	; Seleciona bancos 0-1
	movlw	CurTemp		; Carrega o endereÃƒÂ§o de CurTemp em W
	movwf	FSR		; e de W para o registrador de endereÃƒÂ§amento indireto
	movf	INDF,W		; Este ÃƒÂ© o valor atual de CurTemp
	incf	FSR,F		; AvanÃƒÂ§a para o primeiro elemento da tabela (entrada 0)
	addwf	FSR,F		; Acessa o elemento da tabela Temps apontado
	addwf	FSR,F		; por CurTemp (dois bytes por elemento)
	movf	A0,W
	movwf	INDF		; Armazena na proxima entrada da tabela	
	incf	FSR,F
	movf	A1,W
	movwf	INDF
	movlw	CurTemp
	movwf	FSR
	incf	INDF,F		; Incrementa o ÃƒÂ­ndice CurTemp
	movlw	TempsSize ; NÃƒÂºmero de elementos na tabela
	subwf	INDF,W
	btfsc	_zero
	clrf	INDF		; Quando chegar ao final da tabela, volta ao inÃƒÂ­cio
	return

; ------------------------------------------------------------
; Calcula a media das temperaturas armazenadas (medidas em amostras).
; O resultado sera armazenado em A1:A0.
; Resultados intermediarios em A2:A1:A0, B0
;
MediaTemp
	bcf	STATUS,IRP	; seleciona bancos 0-1
	movlw	Temps00L	; Carrega o endereÃƒÂ§o de Temps00L em W
	movwf	FSR
	movlw	TempsSize
	movwf	B0
	clrf	A0		; Soma as temperaturas em A2:A1:A0
	clrf	A1
	clrf	A2

CalcMedia
	movf	INDF,W		; Carrega LSB da temperatura
	incf	FSR,F
	call	Soma248		; Soma o LSB
	movf	INDF,W		; Carrega o MSB da temperatura
	incf	FSR,F
	addwf	A1,F		; soma o MSB
	btfsc	_carry
	incf	A2,F		; contabiliza o carry

	decfsz	B0,F
	goto	CalcMedia

	movlw	TempsSize/2	; Soma isto a A2:A1:A0 a fim de que a divisÃƒÂ£o abaixo
	call	Soma248		; possa ser arredondada para o inteiro mais prÃƒÂ³ximo.

	movlw	TempsSize
	movwf	B0
	goto	Divisao248	; Divide pelo nÃƒÂºmero de elementos da tabela!!!
;	A temperatura mÃƒÂ©dia deve agora estar em A2:A1:A0, mas A2 deve ser 0

; ------------------------------------------------------------
; Converte a medida do conversor A/D em temperatura Celsius
; ----------
; Entrada: 0:A1:A0 = amostragem do conversor A/D
; SaÃƒÂ­da: A2:A1:A0 = temperatura em milesimos de grau Celsius
;
; Teoria
; ------
; A tensao, medida em milivolts, informada pelo LM35DZ pode
; ser imediatamente interpretada como temperatura. Por
; exemplo, uma tensÃƒÂ£o de 245 mV equivale a 24.5 graus
; Celsius. Assim cada incremento de 10mV equivale a um grau.
;
; Por outro lado, se a tensao de referÃƒÂªncia ÃƒÂ© de 901.639344mV
; via ponte consistindo de um resistor de 10k em sÃƒÂ©rie com
; um de 2k2, o primeiro ligado Ãƒ  Vdd e o segundo a Vss, e
; a tomada central ligada a Vref+. Alem disso, o
; conversor opera com 10 bits, logo cada bit da amostra
; vale 901.639344mV/1023 = 0.881367883mV
;
; NOTA: a tensÃƒÂ£o de referÃƒÂªncia obtida desse modo depende
; fortemente da estabilidade da tensÃƒÂ£o de alimentaÃƒÂ§ÃƒÂ£o e
; da tolerÃƒÂ¢ncia dos resistores. Esta pode ser melhorada
; usando-se uma referÃƒÂªncia mais estÃƒÂ¡vel como um diodo
; zener. No meu caso, a tensÃƒÂ£o medida efetiva foi de 
; aproximadamente 885mV
;
; Desse modo, para converter as amostras em temperatura
; basta multiplica-las por 88. O resultado eh medido em
; milÃƒÂ©simos de grau Celsius. Por exemplo, se a amostra
; eh igual a 278, entÃƒÂ£o:
;   278 * 88 = 24464x10^(-2)mV = 24.4 graus Celsius
;
; Como o resultado deve caber em 16 bits, o topo da
; escala serÃƒÂ¡ 65.5 graus. Em valor de amostragem isto eh
; 65536/88 ~ 744. Para um termometro residencial, esta
; escala deve ser mais do que suficiene. Enquanto
; escrevo isto, meu novo termometro marca confortÃƒÂ¡veis
; 26.5 graus.
;
; Para uma medida precisa, tome a medida exata da tensÃƒÂ£o
; de referÃƒÂªncia presente no seu circuito e modifique o
; valor da variÃƒÂ¡vel TensaoRef. O valor deve ser inteiro
; e medido em milivolts. Para compensar erros de truncamento,
; vocÃƒÂª pode modificar a variÃƒÂ¡vel AjusteOff para
; um dos valores -1, 0 ou 1. ApÃƒÂ³s qualquer ajuste, compare
; a leitura do termÃƒÂ´metro com a tensÃƒÂ£o apresentada pelo
; LM35DZ e faÃƒÂ§a novos ajustes caso seja necessÃƒÂ¡rio.

; AtenÃƒÂ§ÃƒÂ£o: use os valores abaixo apenas como referÃƒÂªncia. VocÃƒÂª
; deve ajustÃƒÂ¡-los para o seu circuÃƒÂ­to em particular.

ComputeTemp
	clrf	A2
	Mult24k	A2,A1,A0,Multiplicador
;
; Se necessÃƒÂ¡rio, aplica deslocamento de temperatura
     if AjusteTempOff>0
	movlw	low AjusteTempOff
	call	Soma248
	movlw	high AjusteTempOff
	call	Soma248H	
     endif
     if AjusteTempOff<0
	movlw	low AjusteTempOff
	call	Soma248
	movlw	high AjusteTempOff
	call	Soma248H
	movlw	0xff
	addwf	A2,F
     endif
;
; Se necessÃƒÂ¡rio, aplica ajuste percentual
     if AjusteTempPer!=100
	Mult24k	A2,A1,A0,AjusteTempPer
	movlw	100
	call	Divisao248
     endif
	return

; Nota: como o resistor de 10k estÃƒÂ¡ fixo e a alimentaÃƒÂ§ÃƒÂ£o ÃƒÂ© de 5V
; entÃƒÂ£o tensÃƒÂ£o de referÃƒÂªncia ÃƒÂ© dada por Vref = 5R/(10^4+R)
; Alguns valores tÃƒÂ­picos para R e Vref:
;	1K0 - 0.456V - 0.446mV/bit ~ 0.05graus/bit
;	2K2 - 0.902V - 0.882mV/bit ~ 0.1graus/bit
;	3K3 - 1.241V - 1.213mV/bit ~ 0.1graus/bit
;	4K7 - 1.599V - 1.563mV/bit ~ 0.2graus/bit
;	5K6 - 1.795V - 1.755mV/bit ~ 0.2graus/bit
;	6K8 - 2.024V - 1.978mV/bit ~ 0.2graus/bit
;	10K - 2.500V - 2.444mV/bit ~ 0.2graus/bit (ideal para o LM35DZ)
; Aqui usamos a conversÃƒÂ£o 10mV=1grau do LM35DZ

; ------------------------------------------------------------
; Registra Maximas e Minimas na EEPROM
; Temperatura a ser registrada em A1:A0
; ----------
MaxMin
; if A1:A0 > TempMax, then TempMax = A1:A0
; Comp16U macro	Xhi,Xlo,Yhi,Ylo
; if X=Y then now Z=1.
; if Y<X then now C=0.
; if X<=Y then now C=1.
	Comp16U	A1,A0,TempMaxh,TempMax
	btfsc	_carry
	goto	MaxMin_TestMin

MaxMin_SetMax
	movf	A0,W			; Armazena nova temperatura mÃƒÂ¡xima
	movwf	TempMax
	movf	A1,W
	movwf	TempMaxh
	call	EEWriteTemps		; Registra na EEPROM
	return

MaxMin_TestMin
; if TempMin > A1:A0 then TempMin = A1:A0
; Comp16U macro	Xhi,Xlo,Yhi,Ylo
; if X=Y then now Z=1.
; if Y<X then now C=0.
; if X<=Y then now C=1.
	Comp16U	TempMinh,TempMin,A1,A0
	btfsc	_carry
	return

MaxMin_SetMin
	movf	A0,W			; Armazena nova temperatura mÃƒÂ­nima
	movwf	TempMin
	movf	A1,W
	movwf	TempMinh
	call	EEWriteTemps		; Registra na EEPROM
	return
	
; -----------------------------------------------
; Converte um numero de binario para decimal.
; -------------------------
; Entrada: A2:A1:A0
; Saida: D4:D0 (um dÃƒÂ­gito por byte) -- valor mÃƒÂ¡ximo 99999
; Usa B3:B2:B1:B0
;
; DescriÃƒÂ§ÃƒÂ£o: 
; Sejam A_15,...,A_0 os bits de A1:A0. Para convertermos o nÃƒÂºmero em A1:A0
; para decimal basta avaliarmos o polinÃƒÂ´mio
;              2^15 A_15 + 2^14 A_14 + ... + 2 A_1 + A_0
; sÃƒÂ³ que usando aritmÃƒÂ©tica decimal. Isto parece complicado, mas usando o
; dispositivo prÃƒÂ¡tico de Briot-Ruffini, pode ser feito de modo bastante
; eficiente:
;             2(... 2(2 A_15 + A_14) + A_13) + ... ) + A_0
;
BinDec
	movlw	24			; Inicializa o contador de dÃƒÂ­gitos binÃƒÂ¡rios
	movwf	B3

	movf	A0,w			; Copia o nÃƒÂºmero para uma ÃƒÂ¡rea temporÃƒÂ¡ria B2:B1:B0
	movwf	B0
	movf	A1,w
	movwf	B1
	movf	A2,w
	movwf	B2

	clrf	D0			; Zera a ÃƒÂ¡rea que vai conter o resultado
	clrf	D1
	clrf	D2
	clrf	D3
	clrf	D4

BinDecAjuste
	bcf	_carry			; Alinha o nÃƒÂºmero B1:B0 Ãƒ  esquerda,
	rlf	B0,f			; permitindo a entrada dos bits mais significativos
	rlf	B1,f			; para dentro do carry C.
	rlf	B2,f
	btfsc	_carry			; Efetivamente, estamos evitando considerar
	goto	BinDecLoop		; os zeros Ãƒ  esquerda em B2:B1:B0
	decfsz	B3,f
	goto	BinDecAjuste
	return

BinDecLoop
	rlf	D0,f			; Este bloco multiplica D0 por 2.
	movf	D0,W			; Se o resultado for maior do que 10
	addlw	-10			; entÃƒÂ£o subtrai 10
	btfsc	_carry			; e soma um no prÃƒÂ³ximo digito (antes que
	movwf	D0			; este seja multiplicado por 2).

	rlf	D1,f			; Idem ao bloco acima, para D1
	movf	D1,W
	addlw	-10
	btfsc	_carry
	movwf	D1

	rlf	D2,f			; Idem ao bloco acima, para D2
	movf	D2,W
	addlw	-10
	btfsc	_carry
	movwf	D2

	rlf	D3,f			; Idem ao bloco acima, para D3
	movf	D3,W
	addlw	-10
	btfsc	_carry
	movwf	D3

	rlf	D4,f			; Idem ao bloco acima, para D4
	movf	D4,W
	addlw	-10
	btfsc	_carry
	movwf	D4

	rlf	B0,f			; Alimentamos o prÃƒÂ³ximo dÃƒÂ­gito binÃƒÂ¡rio para
	rlf	B1,f			; dentro do carry C
	rlf	B2,f

	decfsz	B3,f			; Decrementa o contador de dÃƒÂ­gitos binÃƒÂ¡rios
	goto	BinDecLoop

	return				; Retorna quando o contador chegar a zero

; --------------------------------------------------------
; Soma nÃƒÂ£o-sinalizada de um nÃƒÂºmero de 24 bits com outro
; de 8 bits.
; Entrada: A2:A1:A0 = primeiro termo
;                 W = segundo termo
; SaÃƒÂ­da:   A2:A1:A0 = soma, C=1 se houve estouro
; Obs: o valor em W ÃƒÂ© destruÃƒÂ­do

Soma248
	addwf	A0,F
	movlw	1
	btfsc	_carry
	addwf	A1,F
	btfsc	_carry
	addwf	A2,F
	return

; Mesmo que a anterior, mas soma na parte alta
Soma248H
	addwf	A1,F
	btfsc	_carry
	incf	A2,F
	return

; --------------------------------------------------------
; DivisÃƒÂ£o nÃƒÂ£o-sinalizada de um nÃƒÂºmero 24bits por outro
; de 8 bits.
; Entrada: A2:A1:A0=dividendo
;	         B0=divisor
; SaÃƒÂ­da:   A2:A1:A0=quociente
;                C0=resto
; Usa: D3:D2:D1:D0 - ÃƒÂ¡rea de trabalho
Divisao248
;
	movf	A0,W	; Copia A2:A1:A0 para a ÃƒÂ¡rea de trabalho D2:D1:D0
	movwf	D0
	movf	A1,W
	movwf	D1
	movf	A2,W
	movwf	D2

	clrf	C0	; Zera o campo que conterÃƒÂ¡ o resto da divisÃƒÂ£o

	movlw	24	; Inicializa o contador de 24 bits
	movwf	D3
;
; Executa a macro divMac 24 vezes
Divisao248Loop
	divMac
	decfsz	D3,F
	goto	Divisao248Loop
;
; O quociente agora estÃƒÂ¡ em A2:A1:A0 e o resto em C0
	return

; -----------------------------------------------
; Le uma posicao da EEPROM
; ------------------------
; Entrada: W = posiÃƒÂ§ÃƒÂ£o da EEPROM
; SaÃƒÂ­da: W = valor armazenado naquela posiÃƒÂ§ÃƒÂ£o
;
EERead	banksel	EECON1	
	btfsc	EECON1,WR		; Aguarda a conclusÃƒÂ£o de uma operaÃƒÂ§ÃƒÂ£o de escrita
	goto	$-1			; anterior.

	banksel EEADR
	movwf	EEADR
	banksel EECON1
	bcf	EECON1,EEPGD
	bsf	EECON1,RD
	banksel EEDATA
	nop				; just in case
	movf	EEDATA,W
	banksel A0
	return

; -----------------------------------------------
; Escreve uma posicao da EEPROM
; -----------------------------
; Entrada: W = posiÃƒÂ§ÃƒÂ£o da EEPROM, eData = dado a gravar
;
EEWrite	banksel	EECON1
	btfsc	EECON1,WR		; Aguarda a conclusÃƒÂ£o de uma operaÃƒÂ§ÃƒÂ£o de escrita
	goto	$-1			; anterior.
	banksel EEADR
	movwf	EEADR			; Especifica o endereÃƒÂ§o a gravar
	banksel eData
	movf	eData,W
	banksel EEDATA
	movwf	EEDATA
	banksel	EECON1
	bcf	EECON1,EEPGD
	bsf	EECON1,WREN		; Liga a habilitaÃƒÂ§ÃƒÂ£o de escrita
	bcf	INTCON,GIE		; Desabilita as interrupÃƒÂ§ÃƒÂµes
	movlw	0x55			; para dar o comando de gravaÃƒÂ§ÃƒÂ£o
	movwf	EECON2
	movlw	0xAA
	movwf	EECON2
	bsf	EECON1,WR
	bsf	INTCON,GIE		; Habilita as interrupÃƒÂ§ÃƒÂµes
	bcf	EECON1,WREN		; Desabilita a escrita, sem interromper a escrita atual
	banksel	A0
	return
		
; -----------------------------------------------
; Inicializa a EEPROM
; -------------------
; Assume que as temperaturas mÃƒÂ¡xima e mÃƒÂ­nima jÃƒÂ¡ foram determinadas.
;
EEInit	call	EEWriteTemps		; Registra as temperaturas
	clrf	eData
	movlw	EEConfBits		; Bits de configuraÃƒÂ§ÃƒÂ£o
	call	EEWrite
	movlw	low EESignature
	movwf	eData			; Assina a EEPROM
	movlw	EESig
	call	EEWrite
	movlw	high EESignature
	movwf	eData
	movlw	EESigh
	call	EEWrite
	return

; -----------------------------------------------
; Escala de exibiÃƒÂ§ÃƒÂ£o da temperatura
; Saida: Z=1 Celsius, Z=0 Farenheit
; -------------------

EEReadScale
	movlw	EEConfBits
	call	EERead
	andlw	(1<<EEEscala)
	return

; -----------------------------------------------
; Grava as temperaturas na EEPROM
; -------------------
;
EEWriteTemps
	banksel	TempMin
	movf	TempMin,W		; Registra a Temperatura MÃƒÂ­nima
	movwf	eData
	movlw	EETempMin
	call	EEWrite
	movf	TempMinh,W
	movwf	eData
	movlw	EETempMinh
	call	EEWrite

	movf	TempMax,W		; Registra a Temperatura MÃƒÂ¡xima
	movwf	eData
	movlw	EETempMax
	call	EEWrite
	movf	TempMaxh,W
	movwf	eData
	movlw	EETempMaxh
	call	EEWrite
	
	return

; -----------------------------------------------
; Grava as temperaturas na EEPROM
; -------------------
;
EEReadTemps
	movlw	EETempMin
	call	EERead
	movwf	TempMin
	movlw	EETempMinh
	call	EERead
	movwf	TempMinh
	movlw	EETempMax
	call	EERead
	movwf	TempMax
	movlw	EETempMaxh
	call	EERead
	movwf	TempMaxh
	return

; ------------------------------------------------------------
; 
	dt	"termometro.asm 14/07/2007 R1.0, "
	dt	"(c) Waldeck Schutzer 2007, "
	dt	"waldeck@dm.ufscar.br"
EndOfProg

   if EndOfProg>1023
	error "Programa muito grande!"
   endif
	end