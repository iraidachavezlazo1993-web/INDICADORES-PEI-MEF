********************************************************************************
* Proyecto : Indicador IND_AVANCE_FISICO (Avance físico real vs. programado F12)
* Base     : Rep_Avance_Fisico_programado_F12_13ABR2026.xlsx
* Autor    : DIPLAN - MEF
* Fecha    : 13/04/2026
*
* Replica el cálculo del archivo *_calc* (hoja BDA):
*   1) Pivot por (COD_UNICO, ID_NRO_SEG):
*        - POR_AVAN_PROG  = max por (CUI, SEG)
*        - POR_AVAN_REAL  = max por (CUI, SEG)
*        - MTO_AVAN_PROG  = max por (CUI, SEG)
*        - MTO_AVAN_REAL  = max por (CUI, SEG)
*   2) (Opcional) Merge con base auxiliar (Rep_Inversiones) para traer
*        NIVEL (GL/GN/GR), PIM_2025 y COSTO_ACTUALIZADO.
*   3) Indicador por NIVEL (N ∈ {GL, GN, GR}):
*        PORC_AVA_PROG_N = mean(POR_AVAN_PROG | Nivel=N)
*        PORC_AVA_REAL_N = mean(POR_AVAN_REAL | Nivel=N)
*        RATIO_N         = PORC_AVA_REAL_N / PORC_AVA_PROG_N
*        W_N             = Σ MTO_AVAN_REAL_N / Σ MTO_AVAN_REAL_total
*        INDICADOR_N     = RATIO_N * W_N
*   4) Indicador global:
*        IND_AVANCE_FISICO = Σ INDICADOR_N / (# Niveles)          (calc file)
*        IND_AVANCE_PONDERADO = Σ INDICADOR_N                     (alternativa)
*
* IMPORTANTE: las bases son pesadas, por eso CADA archivo Excel que se
* importa se guarda inmediatamente como .dta en $output.  Así se puede
* re-ejecutar desde cualquier bloque sin volver a leer el Excel.  Si el
* .dta ya existe, el bloque de importación se SALTA (basta borrar el .dta
* para forzar una reimportación).
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
log using "$output\log_IND_AVANCE_FISICO_13ABR2026.smcl", replace

* Rutas persistentes (todas son .dta, nunca tempfiles)
local raw_f12   "$output\RAW_F12_13ABR2026.dta"          // base F12 cruda
local raw_inv   "$output\RAW_INVERSIONES_13ABR2026.dta"  // base aux cruda
local meta_f12  "$output\META_F12_13ABR2026.dta"         // TIP_INVERSION / DES_MODALIDAD
local pivot_f12 "$output\PIVOT_F12_13ABR2026.dta"        // pivot por (CUI, SEG)
local aux_nivel "$output\AUX_NIVEL_13ABR2026.dta"        // NIVEL/PIM/COSTO por CUI
local bda       "$output\BDA_IND_AVANCE_FISICO_13ABR2026.dta"
local tabla     "$output\TABLA_IND_AVANCE_FISICO.dta"

*---------------------------- 2. IMPORTAR F12 ---------------------------------*
* Si el .dta ya existe no se vuelve a importar el Excel.
capture confirm file "`raw_f12'"
if _rc {
    local archivo "Rep_Avance_Fisico_programado_F12_13ABR2026.xlsx"
    local hoja    "INVERSIONES"
    di as txt "Importando `archivo' (primera vez) ..."
    import excel using "$input\\`archivo'", ///
        sheet("`hoja'") firstrow clear allstring
    rename *, upper
    save "`raw_f12'", replace
    di as res "  Guardado: `raw_f12'"
}
else {
    di as txt "Reutilizando `raw_f12' (ya existe)."
}

use "`raw_f12'", clear

*---------------------------- 3. LIMPIEZA -------------------------------------*
* Identificadores
destring COD_UNICO ID_NRO_SEG ID_HITO PERIODO, replace force

* Métricas numéricas
foreach v in POR_AVAN_PROG POR_AVAN_REAL MTO_AVAN_PROG MTO_AVAN_REAL POR_APROBADO {
    capture confirm variable `v'
    if !_rc {
        capture confirm string variable `v'
        if !_rc {
            replace `v' = strtrim(`v')
            replace `v' = "" if inlist(`v', " ", ".", "-", "--", "NA", "null")
        }
        destring `v', replace force
    }
}

* Fechas: FEC_INICIO, FEC_FINAL pueden venir como texto o serial Excel
foreach v in FEC_INICIO FEC_FINAL {
    capture confirm string variable `v'
    if !_rc {
        replace `v' = strtrim(`v')
        replace `v' = "" if inlist(`v', " ", ".", "-", "--", "NA", "null")
        gen double `v'_D = .
        replace `v'_D = date(`v', "DMY") if strpos(`v',"/") > 0
        replace `v'_D = date(`v', "YMD##") ///
            if missing(`v'_D) & strpos(`v',"-") > 0
        replace `v'_D = real(`v') + td(30dec1899) ///
            if missing(`v'_D) & real(`v') < . & real(`v') > 10000
        format %td `v'_D
        drop `v'
        rename `v'_D `v'
    }
}

* Depurar registros sin identificadores
drop if missing(COD_UNICO) | missing(ID_NRO_SEG)

*---------------------------- 4. PIVOT POR (CUI, SEG) -------------------------*
* Se guarda primero META (TIP_INVERSION / DES_MODALIDAD) en .dta persistente.
preserve
    keep COD_UNICO ID_NRO_SEG TIP_INVERSION DES_MODALIDAD
    duplicates drop
    bysort COD_UNICO ID_NRO_SEG (TIP_INVERSION DES_MODALIDAD): keep if _n == 1
    save "`meta_f12'", replace
    di as res "  Guardado: `meta_f12'"
restore

collapse (max) POR_AVAN_PROG POR_AVAN_REAL MTO_AVAN_PROG MTO_AVAN_REAL ///
         (count) N_PERIODOS = PERIODO, ///
         by(COD_UNICO ID_NRO_SEG)

merge 1:1 COD_UNICO ID_NRO_SEG using "`meta_f12'", nogen

save "`pivot_f12'", replace
di as res "  Guardado: `pivot_f12'"

*---------------------------- 5. BASE AUXILIAR (NIVEL / PIM / COSTO) ----------*
* Se intenta cruzar con Rep_Inversiones_13ABR2026.xlsx para obtener NIVEL
* de gobierno, PIM 2025 y Costo Actualizado por CUI.  Si no se encuentra
* el Excel se continúa sin desagregación por nivel.
local archivo2 "Rep_Inversiones_13ABR2026.xlsx"
local hoja2    "INVERSIONES"

* 5a) Importar (o reutilizar) la base auxiliar
capture confirm file "`aux_nivel'"
if _rc {
    capture confirm file "$input\\`archivo2'"
    if !_rc {
        di as txt "Importando `archivo2' (primera vez) ..."
        import excel using "$input\\`archivo2'", ///
            sheet("`hoja2'") firstrow clear allstring
        rename *, upper
        save "`raw_inv'", replace
        di as res "  Guardado: `raw_inv'"

        capture rename CODIGO_UNICO      COD_UNICO
        capture rename NIVEL_GOB         NIVEL
        capture rename PIM2026           PIM_AÑO_ACTUAL
        capture rename COSTO_ACTUALIZADO COSTO_ACT
        destring COD_UNICO, replace force
        foreach v in PIM_AÑO_ACTUAL COSTO_ACT {
            capture confirm variable `v'
            if !_rc destring `v', replace force
        }
        capture confirm variable NIVEL
        if !_rc {
            replace NIVEL = strtrim(upper(NIVEL))
            replace NIVEL = "GL" if inlist(NIVEL,"GOBIERNO LOCAL","LOCAL")
            replace NIVEL = "GN" if inlist(NIVEL,"GOBIERNO NACIONAL","NACIONAL")
            replace NIVEL = "GR" if inlist(NIVEL,"GOBIERNO REGIONAL","REGIONAL")
        }
        else {
            gen str2 NIVEL = ""
        }
        foreach v in PIM_AÑO_ACTUAL COSTO_ACT {
            capture confirm variable `v'
            if _rc gen double `v' = .
        }
        keep COD_UNICO NIVEL PIM_AÑO_ACTUAL COSTO_ACT
        duplicates drop COD_UNICO, force
        save "`aux_nivel'", replace
        di as res "  Guardado: `aux_nivel'"
    }
    else {
        di as err "NO SE ENCONTRÓ $input\\`archivo2' - se creará AUX vacío"
        clear
        set obs 0
        gen long   COD_UNICO      = .
        gen str2   NIVEL          = ""
        gen double PIM_AÑO_ACTUAL = .
        gen double COSTO_ACT      = .
        save "`aux_nivel'", replace
    }
}
else {
    di as txt "Reutilizando `aux_nivel' (ya existe)."
}

* 5b) Merge pivot F12 <-> base auxiliar
use "`pivot_f12'", clear
merge m:1 COD_UNICO using "`aux_nivel'", keep(master match) nogen

* Si NIVEL vino vacío o faltante, marcamos "--" para que el indicador
* se calcule sin descomposición por nivel.
capture confirm variable NIVEL
if _rc gen str2 NIVEL = ""
replace NIVEL = "--" if missing(NIVEL) | NIVEL == ""

foreach v in PIM_AÑO_ACTUAL COSTO_ACT {
    capture confirm variable `v'
    if _rc gen double `v' = .
}

*---------------------------- 6. GUARDAR BDA ----------------------------------*
order COD_UNICO ID_NRO_SEG NIVEL ///
      POR_AVAN_PROG POR_AVAN_REAL MTO_AVAN_PROG MTO_AVAN_REAL ///
      PIM_AÑO_ACTUAL COSTO_ACT N_PERIODOS TIP_INVERSION DES_MODALIDAD

save "`bda'", replace
di as res "  Pivot final guardado: `bda'"

*---------------------------- 7. INDICADOR ------------------------------------*
use "`bda'", clear

* Σ MTO_AVAN_REAL total (denominador del peso)
sum MTO_AVAN_REAL, meanonly
local TOT_MTO = r(sum)

* Tabla resumen por NIVEL con DOS variantes de numerador:
*   - NUMER_COSTO = COSTO_ACT_N  * RATIO * PESO   (fórmula usada en _calc)
*   - NUMER_PIM   = PIM_AÑO_AC_N * RATIO * PESO   (alternativa, para
*                   comparar con la ficha: a esta altura del año ≤ 10%)
* Indicadores globales:
*   - IND_PROM        = promedio de INDICADOR_N (fórmula _calc)
*   - IND_PONDE       = Σ INDICADOR_N = Σ ratio*peso
*   - IND_NUM_COSTO   = Σ NUMER_COSTO / Σ COSTO_ACT_N
*   - IND_NUM_PIM     = Σ NUMER_PIM   / Σ PIM_AÑO_AC_N
tempname P
postfile `P' str8 NIVEL_G CANT ///
    double PORC_PROG PORC_REAL RATIO PESO INDICADOR ///
           COSTO_N NUMER_COSTO PIM_N NUMER_PIM ///
    using "`tabla'", replace

levelsof NIVEL, local(niveles) clean
foreach n of local niveles {
    qui count if NIVEL == "`n'"
    local cant = r(N)

    qui sum POR_AVAN_PROG if NIVEL == "`n'", meanonly
    local pp = r(mean)
    qui sum POR_AVAN_REAL if NIVEL == "`n'", meanonly
    local pr = r(mean)

    qui sum MTO_AVAN_REAL if NIVEL == "`n'", meanonly
    local mreal_n = r(sum)

    qui sum COSTO_ACT if NIVEL == "`n'", meanonly
    local costo_n = r(sum)

    qui sum PIM_AÑO_ACTUAL if NIVEL == "`n'", meanonly
    local pim_n = r(sum)

    local ratio       = cond(`pp' > 0, `pr'/`pp', .)
    local peso        = cond(`TOT_MTO' > 0, `mreal_n'/`TOT_MTO', .)
    local ind_n       = cond(`ratio' < . & `peso' < ., `ratio'*`peso', .)
    local numer_costo = cond(`ind_n' < . & `costo_n' < ., `costo_n'*`ind_n', .)
    local numer_pim   = cond(`ind_n' < . & `pim_n'   < ., `pim_n'  *`ind_n', .)

    post `P' ("`n'") (`cant') (`pp') (`pr') (`ratio') (`peso') (`ind_n') ///
             (`costo_n') (`numer_costo') (`pim_n') (`numer_pim')
}
postclose `P'

* Leer la tabla y calcular los indicadores globales
use "`tabla'", clear
list, sep(0) noobs abbreviate(12)

sum INDICADOR, meanonly
scalar IND_PROM  = r(mean)
scalar IND_PONDE = r(sum)

sum NUMER_COSTO, meanonly
scalar NUM_COSTO_TOT = r(sum)
sum COSTO_N, meanonly
scalar COSTO_TOTAL = r(sum)
scalar IND_NUM_COSTO = cond(COSTO_TOTAL > 0, NUM_COSTO_TOT/COSTO_TOTAL, .)

sum NUMER_PIM, meanonly
scalar NUM_PIM_TOT = r(sum)
sum PIM_N, meanonly
scalar PIM_TOTAL = r(sum)
scalar IND_NUM_PIM = cond(PIM_TOTAL > 0, NUM_PIM_TOT/PIM_TOTAL, .)

di as txt _n(2) "================================================================"
di as txt "   IND_AVANCE_FISICO (promedio de niveles, fórmula _calc) = " %9.4f IND_PROM
di as txt "   IND_AVANCE_PONDERADO (Σ ratio_N * peso_N)              = " %9.4f IND_PONDE
di as txt "   IND_NUM_COSTO (Σ Numerador_COSTO / Σ COSTO_ACT)        = " %9.4f IND_NUM_COSTO
di as txt "   IND_NUM_PIM   (Σ Numerador_PIM   / Σ PIM_AÑO_ACTUAL)   = " %9.4f IND_NUM_PIM
di as txt "   Σ NUMER_COSTO                                          = " %16.2f NUM_COSTO_TOT
di as txt "   Σ COSTO_ACT                                            = " %16.2f COSTO_TOTAL
di as txt "   Σ NUMER_PIM                                            = " %16.2f NUM_PIM_TOT
di as txt "   Σ PIM_AÑO_ACTUAL                                       = " %16.2f PIM_TOTAL
di as txt "================================================================"

*---------------------------- 8. EXPORTAR A EXCEL -----------------------------*
local xlsx "$output\BDA_IND_AVANCE_FISICO_13ABR2026.xlsx"

* 8a) Hoja BDA (base pivotada con NIVEL)
use "`bda'", clear
export excel using "`xlsx'", ///
    firstrow(variables) sheet("BDA") sheetreplace

* 8b) Hoja TABLA (resumen por nivel + indicador global)
use "`tabla'", clear
export excel using "`xlsx'", ///
    firstrow(variables) sheet("TABLA") sheetreplace

* En putexcel las opciones van SEPARADAS POR ESPACIOS (no por comas).
putexcel set "`xlsx'", sheet("TABLA") modify
local r  = _N + 3
local r2 = `r' + 1
local r3 = `r' + 2
local r4 = `r' + 3
putexcel A`r'  = "IND_AVANCE_FISICO (prom. niveles)", bold
putexcel G`r'  = (IND_PROM),      nformat("0.0000") bold
putexcel A`r2' = "IND_AVANCE_PONDERADO (Σ ratio*peso)"
putexcel G`r2' = (IND_PONDE),     nformat("0.0000")
putexcel A`r3' = "IND_NUM_COSTO (Σ Numer_COSTO / Σ COSTO_ACT)"
putexcel G`r3' = (IND_NUM_COSTO), nformat("0.0000")
putexcel A`r4' = "IND_NUM_PIM   (Σ Numer_PIM / Σ PIM_AÑO_ACTUAL)", bold
putexcel G`r4' = (IND_NUM_PIM),   nformat("0.0000") bold

* 8c) Guardar BDA final con los mismos resultados
use "`bda'", clear
save "$output\BDA_IND_AVANCE_FISICO_13ABR2026_final.dta", replace

di as res _n "Archivos guardados en $output"
log close


********************************************************************************
* FIN
********************************************************************************
