********************************************************************************
* Proyecto : Indicador IND_ET (Plazo de elaboración de Expedientes Técnicos)
* Base     : Rep_Inversiones_Inicio_Fin_ET_13ABR2026.xlsx
* Autor    : DIPLAN - MEF
* Fecha    : 13/04/2026
*
* Replica el cálculo del archivo *_calc*:
*   - Pivot por CUI de los hitos INICIO y CULMINACIÓN de la elaboración del ET
*   - FIN_ET  = Min(FEC_PROGRAM) de hitos CULMINACIÓN
*   - INI_ET  = Min(FEC_PROGRAM) de hitos INICIO
*   - PLAZO_ET    = (FIN_ET - INI_ET) / 30
*   - CANT_OBRAS  = max(count_inicio, count_culminacion) por CUI
*   - IND_ET      = SUM(PLAZO_ET) / SUM(CANT_OBRAS)
********************************************************************************

clear all
set more off
version 15

*---------------------------- 1. RUTAS ----------------------------------------*
global ruta   "C:\Users\diplan11\Documents\MEF"
global input  "$ruta\01_input"
global script "$ruta\02_script"
global output "$ruta\03_output"

cd "$script"
cap log close
log using "$output\log_IND_ET_13ABR2026.smcl", replace

* FORZAR_REIMPORT = 1 para reimportar los .xlsx aunque exista el .dta cacheado
global FORZAR_REIMPORT = 0

*---------------------------- 2. IMPORTAR (con caché) -------------------------*
* Los imports de Excel son lentos, así que se cachean en .dta dentro de
* $output.  Si el .dta existe y FORZAR_REIMPORT=0, se reutiliza con "use".
local archivo "Rep_Inversiones_Inicio_Fin_ET_13ABR2026.xlsx"
local hoja    "INVERSIONES"   // usa "INI_FIN" si tu base viene con ese nombre
local cache1  "$output\01_raw_inversiones_hitos.dta"

capture confirm file "`cache1'"
if _rc | $FORZAR_REIMPORT == 1 {
    di as txt "  Importando `archivo' ..."
    import excel using "$input\\`archivo'", ///
        sheet("`hoja'") firstrow clear allstring
    rename *, upper

    *---- LIMPIEZA DE FECHAS ----
    foreach v in FEC_PROGRAM FEC_ACTUALIZADA FEC_REG_ET {
        capture confirm variable `v'
        if !_rc {
            replace `v' = strtrim(`v')
            replace `v' = "" if `v' == " " | `v' == "."
            gen double `v'_D = .
            replace `v'_D = date(`v', "DMY") ///
                if missing(`v'_D) & strpos(`v',"/") > 0
            replace `v'_D = date(`v', "YMD##") ///
                if missing(`v'_D) & strpos(`v',"-") > 0
            replace `v'_D = real(`v') + td(30dec1899) ///
                if missing(`v'_D) & real(`v') < . & real(`v') > 10000
            format %td `v'_D
            drop `v'
            rename `v'_D `v'
        }
    }
    foreach v of varlist DES_ETAPA DES_HITO {
        replace `v' = strtrim(`v')
    }
    destring COD_UNICO, replace force
    save "`cache1'", replace
    di as res "  Caché guardado: `cache1'"
}
else {
    di as txt "  Usando caché: `cache1'"
    use "`cache1'", clear
}

* Variable dummy para contar registros en el collapse
gen byte UNO = 1

*---------------------------- 3b. CANT_OBRAS (expedientes únicos) -------------*
* CANT_OBRAS = número distinto de ID_EXP_TECNICO por CUI, calculado ANTES
* de filtrar por hitos (cada expediente = una obra).
preserve
    keep COD_UNICO ID_EXP_TECNICO
    keep if !missing(COD_UNICO) & !missing(ID_EXP_TECNICO) & ID_EXP_TECNICO != ""
    duplicates drop
    bysort COD_UNICO: gen int CANT_OBRAS = _N
    bysort COD_UNICO: keep if _n == 1
    drop ID_EXP_TECNICO
    tempfile obras
    save `obras'
restore

*---------------------------- 4. MARCAR HITOS ---------------------------------*
* Hitos que delimitan el plazo de elaboración del ET / Documento Equivalente
* (cubre las dos convenciones observadas: versión larga y versión corta)
gen byte ES_INICIO = ///
    inlist(DES_HITO, "INICIO", "INICIO DE PLAZO PARA LA ELABORACIÓN DEL ET")

gen byte ES_FIN = ///
    inlist(DES_HITO, "CULMINACIÓN", "CULMINACIÓN DE LA ELABORACIÓN DEL ET")

* Se consideran solo hitos de la etapa de ELABORACIÓN del documento
* (ELABDE para IOARR/DE y 05ELABET/10ELABET para ET).  Si tu base usa
* otros acronimos agrégalos en la lista.
gen byte ES_ELAB = ///
    inlist(DES_ETAPA, "ELABDE", "05ELABET", "10ELABET")

replace ES_INICIO = 0 if ES_ELAB==0
replace ES_FIN    = 0 if ES_ELAB==0

keep if ES_INICIO==1 | ES_FIN==1

*---------------------------- 5. PIVOT POR CUI --------------------------------*
preserve
    keep if ES_INICIO==1
    collapse (sum)    CNT_INI      = UNO             ///
             (min)    MIN_PROG_INI = FEC_PROGRAM     ///
             (max)    MAX_ACT_INI  = FEC_ACTUALIZADA ///
             (max)    MAX_REG_INI  = FEC_REG_ET,     ///
             by(COD_UNICO)
    tempfile ini
    save `ini'
restore

preserve
    keep if ES_FIN==1
    collapse (sum)    CNT_FIN      = UNO             ///
             (min)    MIN_PROG_FIN = FEC_PROGRAM     ///
             (max)    MAX_ACT_FIN  = FEC_ACTUALIZADA ///
             (max)    MAX_REG_FIN  = FEC_REG_ET,     ///
             by(COD_UNICO)
    tempfile fin
    save `fin'
restore

use `fin', clear
merge 1:1 COD_UNICO using `ini', nogen

* Re-aplicar formato %td (collapse lo pierde)
format %td MIN_PROG_FIN MAX_ACT_FIN MAX_REG_FIN ///
           MIN_PROG_INI MAX_ACT_INI MAX_REG_INI

tempfile pivot_hitos
save `pivot_hitos'

*---------------------------- 5b. BASE Rep_Inversiones_13ABR2026 --------------*
* Base adicional con FEC_INI_EXPE_TEC / FEC_FIN_EXPE_TEC (una fila por CUI).
* Se cachea también en $output para no reimportar cada vez.
local archivo2 "Rep_Inversiones_13ABR2026.xlsx"
local hoja2    "INVERSIONES"
local cache2   "$output\02_raw_inversiones_13abr.dta"

capture confirm file "`cache2'"
if _rc | $FORZAR_REIMPORT == 1 {
    capture confirm file "$input\\`archivo2'"
    if !_rc {
        di as txt "  Importando `archivo2' ..."
        import excel using "$input\\`archivo2'", ///
            sheet("`hoja2'") firstrow clear allstring
        rename *, upper
        capture rename CODIGO_UNICO COD_UNICO
        destring COD_UNICO, replace force

        foreach v in FEC_INI_EXPE_TEC FEC_FIN_EXPE_TEC {
            capture confirm variable `v'
            if !_rc {
                replace `v' = strtrim(`v')
                replace `v' = "" if inlist(`v', " ", ".", "-", "--", "NA", "null")
                gen double `v'_D = .
                replace `v'_D = date(`v', "DMY") ///
                    if missing(`v'_D) & (strpos(`v',"/") > 0 | ///
                        regexm(`v', "^[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}"))
                replace `v'_D = date(`v', "YMD##") ///
                    if missing(`v'_D) & regexm(`v', "^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}")
                replace `v'_D = real(`v') + td(30dec1899) ///
                    if missing(`v'_D) & real(`v') < . & real(`v') > 10000
                format %td `v'_D
                drop `v'
                rename `v'_D `v'
            }
            else {
                gen double `v' = .
                format %td `v'
            }
        }
        keep COD_UNICO FEC_INI_EXPE_TEC FEC_FIN_EXPE_TEC
        duplicates drop COD_UNICO, force
        save "`cache2'", replace
        di as res "  Caché guardado: `cache2'"
    }
    else {
        di as err "NO SE ENCONTRÓ $input\\`archivo2'"
    }
}
else {
    di as txt "  Usando caché: `cache2'"
}

capture confirm file "`cache2'"
if !_rc {
    use `pivot_hitos', clear
    merge 1:1 COD_UNICO using "`cache2'"
    * _merge==1: solo en pivot hitos; 2: solo en base2; 3: ambos
    drop _merge
}
else {
    use `pivot_hitos', clear
    gen double FEC_INI_EXPE_TEC = .
    gen double FEC_FIN_EXPE_TEC = .
    format %td FEC_INI_EXPE_TEC FEC_FIN_EXPE_TEC
}

* Rellenar contadores para CUIs que solo vienen de la base2
replace CNT_INI = 0 if missing(CNT_INI)
replace CNT_FIN = 0 if missing(CNT_FIN)

* ---- Anexar CANT_OBRAS calculado al inicio (expedientes únicos) ----
merge 1:1 COD_UNICO using `obras', keep(master match) nogen
replace CANT_OBRAS = 0 if missing(CANT_OBRAS)

*---------------------------- 6. ARMAR FECHAS INI / FIN -----------------------*
* Regla actualizada (con la nueva base como 1ª fuente):
*   - INI_ET: FEC_INI_EXPE_TEC -> Máx(FEC_REG_ET) -> Mín(FEC_PROGRAM) -> Máx(FEC_ACTUALIZADA)
*   - FIN_ET: FEC_FIN_EXPE_TEC -> Máx(FEC_REG_ET) -> Mín(FEC_PROGRAM) -> Máx(FEC_ACTUALIZADA)
*   - Si FIN_ET < INI_ET (fin anterior al inicio) se intercambian las fechas
*     y se registra el cambio en FUENTE_INI / FUENTE_FIN.
*   - Solo se descartan CUIs sin NINGUNA fecha de inicio o sin NINGUNA de fin.

* ---- FIN_ET por prioridad ----
gen double FIN_ET = FEC_FIN_EXPE_TEC
replace    FIN_ET = MAX_REG_FIN  if missing(FIN_ET)
replace    FIN_ET = MIN_PROG_FIN if missing(FIN_ET)
replace    FIN_ET = MAX_ACT_FIN  if missing(FIN_ET)

gen str25 FUENTE_FIN = cond(!missing(FEC_FIN_EXPE_TEC),"FEC_FIN_EXPE_TEC", ///
                       cond(!missing(MAX_REG_FIN),     "FEC_REG_ET",      ///
                       cond(!missing(MIN_PROG_FIN),    "FEC_PROGRAM",     ///
                       cond(!missing(MAX_ACT_FIN),     "FEC_ACTUALIZADA","SIN_FECHA"))))

* ---- INI_ET por prioridad ----
gen double INI_ET = FEC_INI_EXPE_TEC
replace    INI_ET = MAX_REG_INI  if missing(INI_ET)
replace    INI_ET = MIN_PROG_INI if missing(INI_ET)
replace    INI_ET = MAX_ACT_INI  if missing(INI_ET)

gen str25 FUENTE_INI = cond(!missing(FEC_INI_EXPE_TEC),"FEC_INI_EXPE_TEC", ///
                       cond(!missing(MAX_REG_INI),     "FEC_REG_ET",      ///
                       cond(!missing(MIN_PROG_INI),    "FEC_PROGRAM",     ///
                       cond(!missing(MAX_ACT_INI),     "FEC_ACTUALIZADA","SIN_FECHA"))))

format %td INI_ET FIN_ET

* ---- Si FIN < INI, intercambiar ----
gen byte SWAP = (!missing(INI_ET) & !missing(FIN_ET) & FIN_ET < INI_ET)
count if SWAP == 1
local n_swap = r(N)

gen double _tmp = INI_ET if SWAP == 1
replace INI_ET = FIN_ET  if SWAP == 1
replace FIN_ET = _tmp    if SWAP == 1
drop _tmp

gen str25 _tmp_s = FUENTE_INI if SWAP == 1
replace FUENTE_INI = FUENTE_FIN + "_(swap)" if SWAP == 1
replace FUENTE_FIN = _tmp_s    + "_(swap)" if SWAP == 1
drop _tmp_s

* ---- Si INI == FIN (plazo 0), intentar separarlas ----
* Regla: cuando ambas fechas coinciden se busca una fecha alternativa
*   1º  FIN_ET = máx de todas las candidatas de fin disponibles
*   2º  si sigue coincidiendo, INI_ET = mín de todas las candidatas de inicio
gen byte COINC = (!missing(INI_ET) & INI_ET == FIN_ET)
count if COINC == 1
local n_coinc = r(N)

egen double FIN_MAX_ALL = rowmax(FEC_FIN_EXPE_TEC MAX_REG_FIN MIN_PROG_FIN MAX_ACT_FIN)
egen double INI_MIN_ALL = rowmin(FEC_INI_EXPE_TEC MAX_REG_INI MIN_PROG_INI MAX_ACT_INI)

* 1) Empujar FIN_ET al máximo posible si con eso deja de coincidir
replace FUENTE_FIN = "MAX_FIN_AJUSTE" ///
    if COINC == 1 & !missing(FIN_MAX_ALL) & FIN_MAX_ALL > INI_ET
replace FIN_ET     = FIN_MAX_ALL ///
    if COINC == 1 & !missing(FIN_MAX_ALL) & FIN_MAX_ALL > INI_ET

* 2) Si tras lo anterior aún INI == FIN, jalar INI_ET al mínimo posible
replace FUENTE_INI = "MIN_INI_AJUSTE" ///
    if COINC == 1 & INI_ET == FIN_ET & !missing(INI_MIN_ALL) & INI_MIN_ALL < FIN_ET
replace INI_ET     = INI_MIN_ALL ///
    if COINC == 1 & INI_ET == FIN_ET & !missing(INI_MIN_ALL) & INI_MIN_ALL < FIN_ET

drop FIN_MAX_ALL INI_MIN_ALL COINC

* ---- Si PLAZO_ET > 2 meses: usar mínimas de candidatas en ambos lados ----
* Regla: si con la prioridad anterior el plazo del CUI supera 2 meses,
* se reemplazan INI_ET y FIN_ET por la fecha MÍNIMA disponible en cada
* conjunto de candidatas (rowmin ignora missings).  Esto reduce el plazo
* hacia el valor temporalmente más temprano disponible.
gen double _plazo_tmp = (FIN_ET - INI_ET) / 30 if !missing(INI_ET, FIN_ET)
gen byte   MAYOR2     = (_plazo_tmp > 2 & !missing(_plazo_tmp))
count if MAYOR2 == 1
local n_mayor2 = r(N)

egen double FIN_MIN_ALL = rowmin(FEC_FIN_EXPE_TEC MAX_REG_FIN MIN_PROG_FIN MAX_ACT_FIN)
egen double INI_MIN_CAND = rowmin(FEC_INI_EXPE_TEC MAX_REG_INI MIN_PROG_INI MAX_ACT_INI)

replace FUENTE_FIN = "MIN_FIN_(>2m)" if MAYOR2 == 1 & !missing(FIN_MIN_ALL)
replace FIN_ET     = FIN_MIN_ALL    if MAYOR2 == 1 & !missing(FIN_MIN_ALL)
replace FUENTE_INI = "MIN_INI_(>2m)" if MAYOR2 == 1 & !missing(INI_MIN_CAND)
replace INI_ET     = INI_MIN_CAND   if MAYOR2 == 1 & !missing(INI_MIN_CAND)

drop _plazo_tmp FIN_MIN_ALL INI_MIN_CAND MAYOR2

* ---- Re-swap de seguridad: si tras los ajustes FIN < INI, intercambiar ----
replace SWAP = 0
replace SWAP = 1 if !missing(INI_ET) & !missing(FIN_ET) & FIN_ET < INI_ET
count if SWAP == 1
local n_swap2 = r(N)

gen double _tmp = INI_ET if SWAP == 1
replace INI_ET = FIN_ET  if SWAP == 1
replace FIN_ET = _tmp    if SWAP == 1
drop _tmp

gen str25 _tmp_s = FUENTE_INI if SWAP == 1
replace FUENTE_INI = FUENTE_FIN + "_(reswap)" if SWAP == 1
replace FUENTE_FIN = _tmp_s    + "_(reswap)" if SWAP == 1
drop _tmp_s

* ---- Eliminar solo los CUIs sin ninguna fecha en alguno de los lados ----
count if missing(INI_ET)
local exc_sin_ini = r(N)
count if missing(FIN_ET)
local exc_sin_fin = r(N)

drop if missing(INI_ET) | missing(FIN_ET)
count
local cuis_ok = r(N)

di as txt _n(2) "------------- DEPURACIÓN -----------------"
di as txt "  CUIs sin NINGUNA fecha de FIN (drop): " `exc_sin_fin'
di as txt "  CUIs sin NINGUNA fecha de INI (drop): " `exc_sin_ini'
di as txt "  CUIs con INI/FIN intercambiados     : " `n_swap'
di as txt "  CUIs con INI==FIN (ajustados)       : " `n_coinc'
di as txt "  CUIs con PLAZO > 2m (ajust. a MIN)  : " `n_mayor2'
di as txt "  Re-swaps tras el ajuste >2m         : " `n_swap2'
di as res "  CUIs válidos para el cálculo        : " `cuis_ok'
di as txt "------------------------------------------"

drop SWAP

*---------------------------- 7. GUARDAR PIVOT BDA ----------------------------*
* Se guarda el dataset pivotado antes de calcular el indicador.
save "$output\BDA_IND_ET_13ABR2026.dta", replace
di as res "  Pivot guardado: $output\BDA_IND_ET_13ABR2026.dta"

*---------------------------- 8. INDICADOR ------------------------------------*
* Se recarga la base recién guardada y a partir de ahí se calcula el IND_ET.
use "$output\BDA_IND_ET_13ABR2026.dta", clear

* Plazo en meses (fórmula del calc: (FIN - INI) / 30)
gen double PLAZO_ET = (FIN_ET - INI_ET) / 30 if !missing(INI_ET, FIN_ET)

* CANT_OBRAS ya viene de la base original (expedientes únicos por CUI);
* si el CUI no tiene plazo (falta INI o FIN) lo excluimos del cálculo.
replace CANT_OBRAS = . if missing(PLAZO_ET)

order COD_UNICO                                                       ///
      CNT_FIN MIN_PROG_FIN MAX_ACT_FIN MAX_REG_FIN FEC_FIN_EXPE_TEC   ///
      FIN_ET FUENTE_FIN                                               ///
      CNT_INI MIN_PROG_INI MAX_ACT_INI MAX_REG_INI FEC_INI_EXPE_TEC   ///
      INI_ET FUENTE_INI                                               ///
      PLAZO_ET CANT_OBRAS

* --- Indicador agregado ---
sum PLAZO_ET, meanonly
local sum_plazo = r(sum)
sum CANT_OBRAS, meanonly
local sum_cant  = r(sum)

local IND_ET = cond(`sum_cant' > 0, `sum_plazo'/`sum_cant', .)

di as txt _n(2) "============================================================="
di as txt "   Σ PLAZO_ET   = " %12.4f `sum_plazo'
di as txt "   Σ CANT_OBRAS = " %12.0f `sum_cant'
di as res "   IND_ET       = " %12.4f `IND_ET'
di as txt "============================================================="

*---------------------------- 9. EXPORTAR -------------------------------------*
local xlsx "$output\BDA_IND_ET_13ABR2026.xlsx"

* Las variables %td se exportan como número de serie de Excel; el formato
* visible se aplica después con putexcel ... nformat("dd/mm/yyyy").
export excel using "`xlsx'", ///
    firstrow(variables) sheet("BDA") sheetreplace

* ----- Formatear columnas de fecha en Excel -----
* Con el nuevo orden de columnas:
*   C=MIN_PROG_FIN, D=MAX_ACT_FIN, E=MAX_REG_FIN, F=FEC_FIN_EXPE_TEC, G=FIN_ET
*   J=MIN_PROG_INI, K=MAX_ACT_INI, L=MAX_REG_INI, M=FEC_INI_EXPE_TEC, N=INI_ET
putexcel set "`xlsx'", sheet("BDA") modify
local nfil = _N + 1        // +1 por la fila de encabezado
foreach col in C D E F G J K L M N {
    putexcel `col'2:`col'`nfil', nformat("dd/mm/yyyy")
}

* ----- Fila de sumatoria + indicador -----
* Columnas: O=FUENTE_INI (etiqueta), P=PLAZO_ET, Q=CANT_OBRAS
local r  = _N + 3
local r2 = `r' + 1
putexcel O`r'  = "Sumatoria"
putexcel P`r'  = (`sum_plazo'), nformat("#,##0.00")
putexcel Q`r'  = (`sum_cant'),  nformat("#,##0")
putexcel O`r2' = "IND_ET_IITRIM_2026", bold
putexcel P`r2' = (`IND_ET'),    nformat("0.0000"), bold

* Guardar base final con PLAZO_ET e IND en .dta
save "$output\BDA_IND_ET_13ABR2026_final.dta", replace

di as res _n "Archivos guardados en $output"
log close

********************************************************************************
* FIN
********************************************************************************
