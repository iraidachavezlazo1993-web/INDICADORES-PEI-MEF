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

*---------------------------- 2. IMPORTAR -------------------------------------*
local archivo "Rep_Avance_Fisico_programado_F12_13ABR2026.xlsx"
local hoja    "INVERSIONES"

import excel using "$input\\`archivo'", ///
    sheet("`hoja'") firstrow clear allstring

* Estandarizar nombres a mayúsculas (por compatibilidad)
rename *, upper

*---------------------------- 3. LIMPIEZA -------------------------------------*
* Identificadores
destring COD_UNICO ID_NRO_SEG ID_HITO PERIODO, replace force

* Métricas numéricas
foreach v in POR_AVAN_PROG POR_AVAN_REAL MTO_AVAN_PROG MTO_AVAN_REAL POR_APROBADO {
    capture confirm variable `v'
    if !_rc {
        replace `v' = strtrim(`v')
        replace `v' = "" if inlist(`v', " ", ".", "-", "--", "NA", "null")
        destring `v', replace force
    }
}

* Fechas: FEC_INICIO, FEC_FINAL pueden venir como texto o serial Excel
foreach v in FEC_INICIO FEC_FINAL {
    capture confirm variable `v'
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
* Replica el comportamiento observado en la hoja BDA del archivo _calc:
* una fila por combinación (COD_UNICO, ID_NRO_SEG) con el valor máximo
* de cada métrica.  TIP_INVERSION / DES_MODALIDAD se conservan (moda).
preserve
    keep COD_UNICO ID_NRO_SEG TIP_INVERSION DES_MODALIDAD
    duplicates drop
    bysort COD_UNICO ID_NRO_SEG (TIP_INVERSION DES_MODALIDAD): ///
        keep if _n == 1
    tempfile meta
    save `meta'
restore

collapse (max) POR_AVAN_PROG POR_AVAN_REAL MTO_AVAN_PROG MTO_AVAN_REAL ///
         (count) N_PERIODOS = PERIODO, ///
         by(COD_UNICO ID_NRO_SEG)

merge 1:1 COD_UNICO ID_NRO_SEG using `meta', nogen

tempfile pivot_f12
save `pivot_f12'

*---------------------------- 5. MERGE CON BASE AUXILIAR ----------------------*
* Base adicional con NIVEL (GL/GN/GR), PIM 2025 y COSTO_ACTUALIZADO, una
* fila por CUI.  Si no existe se continúa con el cálculo global sin la
* descomposición por nivel de gobierno.
local archivo2 "Rep_Inversiones_13ABR2026.xlsx"
local hoja2    "INVERSIONES"

capture confirm file "$input\\`archivo2'"
if !_rc {
    import excel using "$input\\`archivo2'", ///
        sheet("`hoja2'") firstrow clear allstring
    rename *, upper
    capture rename CODIGO_UNICO COD_UNICO
    capture rename NIVEL_GOB    NIVEL
    capture rename PIM2025      PIM_2025
    capture rename COSTO_ACTUALIZADO COSTO_ACT
    destring COD_UNICO, replace force
    foreach v in PIM_2025 COSTO_ACT {
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
    keep COD_UNICO NIVEL PIM_2025 COSTO_ACT
    duplicates drop COD_UNICO, force
    tempfile aux
    save `aux'

    use `pivot_f12', clear
    merge m:1 COD_UNICO using `aux', keep(master match) nogen
}
else {
    di as err "NO SE ENCONTRÓ $input\\`archivo2' - se omite el cruce con NIVEL/PIM/Costo"
    use `pivot_f12', clear
    gen str2  NIVEL     = ""
    gen double PIM_2025  = .
    gen double COSTO_ACT = .
}

* Si no se pudo recuperar NIVEL, marcamos TODO como "--" para que el
* indicador se calcule sin descomposición por nivel.
replace NIVEL = "--" if missing(NIVEL) | NIVEL == ""

*---------------------------- 6. GUARDAR BDA ----------------------------------*
order COD_UNICO ID_NRO_SEG NIVEL ///
      POR_AVAN_PROG POR_AVAN_REAL MTO_AVAN_PROG MTO_AVAN_REAL ///
      PIM_2025 COSTO_ACT N_PERIODOS TIP_INVERSION DES_MODALIDAD

save "$output\BDA_IND_AVANCE_FISICO_13ABR2026.dta", replace
di as res "  Pivot guardado: $output\BDA_IND_AVANCE_FISICO_13ABR2026.dta"

*---------------------------- 7. INDICADOR ------------------------------------*
use "$output\BDA_IND_AVANCE_FISICO_13ABR2026.dta", clear

* Σ MTO_AVAN_REAL total (denominador del peso)
sum MTO_AVAN_REAL, meanonly
local TOT_MTO = r(sum)

* Tabla resumen por NIVEL
tempname P
postfile `P' str8 NIVEL_G CANT double PORC_PROG PORC_REAL RATIO PESO INDICADOR ///
    using "$output\TABLA_IND_AVANCE_FISICO.dta", replace

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

    local ratio = cond(`pp' > 0, `pr'/`pp', .)
    local peso  = cond(`TOT_MTO' > 0, `mreal_n'/`TOT_MTO', .)
    local ind_n = cond(`ratio' < . & `peso' < ., `ratio'*`peso', .)

    post `P' ("`n'") (`cant') (`pp') (`pr') (`ratio') (`peso') (`ind_n')
}
postclose `P'

preserve
    use "$output\TABLA_IND_AVANCE_FISICO.dta", clear
    list, sep(0) noobs abbreviate(12)

    * Indicador global: promedio simple de los indicadores por nivel (fórmula
    * del archivo _calc).  Se reporta también la suma ponderada (coincide con
    * el ratio global cuando hay un solo nivel).
    sum INDICADOR, meanonly
    scalar IND_PROM = r(mean)
    scalar IND_PONDE = r(sum)
    di as txt _n(2) "================================================================"
    di as txt "   IND_AVANCE_FISICO (promedio de niveles, fórmula _calc) = " %9.4f IND_PROM
    di as txt "   IND_AVANCE_PONDERADO (Σ ratio_N * peso_N)              = " %9.4f IND_PONDE
    di as txt "================================================================"
restore

*---------------------------- 8. EXPORTAR -------------------------------------*
local xlsx "$output\BDA_IND_AVANCE_FISICO_13ABR2026.xlsx"

* Hoja BDA: base pivotada
export excel using "`xlsx'", ///
    firstrow(variables) sheet("BDA") sheetreplace

* Hoja TABLA: resumen por nivel + indicador
preserve
    use "$output\TABLA_IND_AVANCE_FISICO.dta", clear
    export excel using "`xlsx'", ///
        firstrow(variables) sheet("TABLA") sheetreplace

    putexcel set "`xlsx'", sheet("TABLA") modify
    local r = _N + 3
    putexcel A`r' = "IND_AVANCE_FISICO (prom. niveles)", bold
    putexcel G`r' = (IND_PROM),  nformat("0.0000"), bold
    local r2 = `r' + 1
    putexcel A`r2' = "IND_AVANCE_PONDERADO (Σ ratio*peso)"
    putexcel G`r2' = (IND_PONDE), nformat("0.0000")
restore

save "$output\BDA_IND_AVANCE_FISICO_13ABR2026_final.dta", replace

di as res _n "Archivos guardados en $output"
log close


********************************************************************************
* FIN
********************************************************************************
