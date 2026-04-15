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

*---------------------------- 2. IMPORTAR -------------------------------------*
* Cambia el nombre si tu archivo es distinto
local archivo "Rep_Inversiones_Inicio_Fin_ET_13ABR2026.xlsx"
local hoja    "INVERSIONES"   // usa "INI_FIN" si tu base viene con ese nombre

import excel using "$input\\`archivo'", ///
    sheet("`hoja'") firstrow clear allstring

* Estandarizar nombres a mayúsculas (por compatibilidad)
rename *, upper

*---------------------------- 3. LIMPIEZA -------------------------------------*
* Fechas: FEC_PROGRAM, FEC_ACTUALIZADA y FEC_REG_ET pueden venir como:
*   (a) texto "dd/mm/yyyy"        -> se parsea con date(v,"DMY")
*   (b) texto "yyyy-mm-dd hh:mm"  -> se parsea con date(v,"YMD##")
*   (c) serial Excel              -> real(v) + td(30dec1899)
foreach v in FEC_PROGRAM FEC_ACTUALIZADA FEC_REG_ET {
    capture confirm variable `v'
    if !_rc {
        replace `v' = strtrim(`v')
        replace `v' = "" if `v' == " " | `v' == "."
        gen double `v'_D = .
        * (a) dd/mm/yyyy
        replace `v'_D = date(`v', "DMY") if strpos(`v',"/") > 0
        * (b) yyyy-mm-dd  (con o sin hora)
        replace `v'_D = date(`v', "YMD##") ///
            if missing(`v'_D) & strpos(`v',"-") > 0
        * (c) serial Excel (número puro)
        replace `v'_D = real(`v') + td(30dec1899) ///
            if missing(`v'_D) & real(`v') < . & real(`v') > 10000
        format %td `v'_D
        drop `v'
        rename `v'_D `v'
    }
}

* Quitar espacios en blanco
foreach v of varlist DES_ETAPA DES_HITO {
    replace `v' = strtrim(`v')
}

destring COD_UNICO, replace force

* Variable dummy para contar registros en el collapse
gen byte UNO = 1

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

*---------------------------- 6. ARMAR FECHAS INI / FIN -----------------------*
* Regla:
*   - INI_ET: se toma CUALQUIER fecha disponible en las 3 fuentes, con
*             prioridad  Máx(FEC_REG_ET) > Mín(FEC_PROGRAM) > Máx(FEC_ACTUALIZADA).
*   - FIN_ET: idéntica prioridad.
*   - Si FIN_ET < INI_ET (fin anterior al inicio) se intercambian las fechas
*     y se registra el cambio en FUENTE_INI / FUENTE_FIN.
*   - Solo se descartan CUIs sin NINGUNA fecha de inicio o sin NINGUNA de fin.

* ---- FIN_ET por prioridad ----
gen double FIN_ET = MAX_REG_FIN
replace    FIN_ET = MIN_PROG_FIN if missing(FIN_ET)
replace    FIN_ET = MAX_ACT_FIN  if missing(FIN_ET)

gen str20 FUENTE_FIN = cond(!missing(MAX_REG_FIN),  "FEC_REG_ET",     ///
                       cond(!missing(MIN_PROG_FIN), "FEC_PROGRAM",    ///
                       cond(!missing(MAX_ACT_FIN),  "FEC_ACTUALIZADA","SIN_FECHA")))

* ---- INI_ET por prioridad ----
gen double INI_ET = MAX_REG_INI
replace    INI_ET = MIN_PROG_INI if missing(INI_ET)
replace    INI_ET = MAX_ACT_INI  if missing(INI_ET)

gen str20 FUENTE_INI = cond(!missing(MAX_REG_INI),  "FEC_REG_ET",     ///
                       cond(!missing(MIN_PROG_INI), "FEC_PROGRAM",    ///
                       cond(!missing(MAX_ACT_INI),  "FEC_ACTUALIZADA","SIN_FECHA")))

format %td INI_ET FIN_ET

* ---- Si FIN < INI, intercambiar ----
gen byte SWAP = (!missing(INI_ET) & !missing(FIN_ET) & FIN_ET < INI_ET)
count if SWAP == 1
local n_swap = r(N)

gen double _tmp = INI_ET if SWAP == 1
replace INI_ET = FIN_ET  if SWAP == 1
replace FIN_ET = _tmp    if SWAP == 1
drop _tmp

gen str20 _tmp_s = FUENTE_INI if SWAP == 1
replace FUENTE_INI = FUENTE_FIN + "_(swap)" if SWAP == 1
replace FUENTE_FIN = _tmp_s    + "_(swap)" if SWAP == 1
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

* Cantidad de obras = máximo entre nº de docs de inicio y de culminación
gen int CANT_OBRAS = max(CNT_INI, CNT_FIN)
replace CANT_OBRAS = . if missing(PLAZO_ET)

order COD_UNICO CNT_FIN MIN_PROG_FIN MAX_ACT_FIN MAX_REG_FIN FIN_ET FUENTE_FIN ///
      CNT_INI MIN_PROG_INI MAX_ACT_INI MAX_REG_INI INI_ET FUENTE_INI          ///
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

* datestring() convierte los %td en texto dd/mm/yyyy para Excel;
* keepcellfmt mantiene el formato aplicado con putexcel.
export excel using "`xlsx'", ///
    firstrow(variables) sheet("BDA") sheetreplace ///
    datestring("DD/NN/CCYY") keepcellfmt

* ----- Formatear columnas de fecha en Excel -----
* Con el nuevo orden de columnas:
*   C=MIN_PROG_FIN, D=MAX_ACT_FIN, E=MAX_REG_FIN, F=FIN_ET,
*   I=MIN_PROG_INI, J=MAX_ACT_INI, K=MAX_REG_INI, L=INI_ET
putexcel set "`xlsx'", sheet("BDA") modify
local nfil = _N + 1        // +1 por la fila de encabezado
foreach col in C D E F I J K L {
    putexcel `col'2:`col'`nfil', nformat("dd/mm/yyyy")
}

* ----- Fila de sumatoria + indicador -----
* Columnas: M=FUENTE_INI (etiqueta), N=PLAZO_ET, O=CANT_OBRAS
local r  = _N + 3
local r2 = `r' + 1
putexcel M`r'  = "Sumatoria"
putexcel N`r'  = (`sum_plazo'), nformat("#,##0.00")
putexcel O`r'  = (`sum_cant'),  nformat("#,##0")
putexcel M`r2' = "IND_ET_IITRIM_2026", bold
putexcel N`r2' = (`IND_ET'),    nformat("0.0000"), bold

* Guardar base final con PLAZO_ET e IND en .dta
save "$output\BDA_IND_ET_13ABR2026_final.dta", replace

di as res _n "Archivos guardados en $output"
log close

********************************************************************************
* FIN
********************************************************************************
