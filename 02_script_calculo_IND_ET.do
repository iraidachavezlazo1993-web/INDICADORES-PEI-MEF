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
* Fechas: FEC_PROGRAM, FEC_ACTUALIZADA y FEC_REG_ET vienen como texto dd/mm/yyyy
foreach v in FEC_PROGRAM FEC_ACTUALIZADA FEC_REG_ET {
    capture confirm variable `v'
    if !_rc {
        gen double `v'_D = date(`v', "DMY")
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

*---------------------------- 6. INDICADORES ----------------------------------*
gen double INI_ET = MIN_PROG_INI
gen double FIN_ET = MIN_PROG_FIN
format %td INI_ET FIN_ET

* Plazo en meses (fórmula del calc: (FIN - INI) / 30)
gen double PLAZO_ET = (FIN_ET - INI_ET) / 30 if !missing(INI_ET, FIN_ET)

* Cantidad de obras = máximo entre nº de docs de inicio y de culminación
gen int CANT_OBRAS = max(CNT_INI, CNT_FIN)
replace CANT_OBRAS = . if missing(PLAZO_ET)

order COD_UNICO CNT_FIN MIN_PROG_FIN MAX_ACT_FIN MAX_REG_FIN FIN_ET ///
      CNT_INI MIN_PROG_INI MAX_ACT_INI MAX_REG_INI INI_ET PLAZO_ET CANT_OBRAS

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

*---------------------------- 7. EXPORTAR -------------------------------------*
* Guardar pivot
export excel using "$output\BDA_IND_ET_13ABR2026.xlsx", ///
    firstrow(variables) sheet("BDA") sheetreplace

* Agregar fila con el indicador
putexcel set  "$output\BDA_IND_ET_13ABR2026.xlsx", sheet("BDA") modify
local r = _N + 3
putexcel K`r' = "Sumatoria"
putexcel L`r' = `sum_plazo'
putexcel M`r' = `sum_cant'
local r2 = `r' + 1
putexcel K`r2' = "IND_ET_IITRIM_2026"
putexcel L`r2' = `IND_ET'

* Guardar base final en .dta
save "$output\BDA_IND_ET_13ABR2026.dta", replace

di as res _n "Archivos guardados en $output"
log close

********************************************************************************
* FIN
********************************************************************************
