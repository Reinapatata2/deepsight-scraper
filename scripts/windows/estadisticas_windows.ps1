﻿# =============================================================================
#  estadisticas_windows.ps1  -  Estadísticas de los informes de scraping (Windows)
# -----------------------------------------------------------------------------
#  1. Lee todos los XML nuevos de resultados\ (de Windows, Linux o macOS).
#  2. Calcula las estadísticas y las muestra por consola.
#  3. Genera estadisticas\estadisticas_FECHA.html (gráficos + registro de
#     frases) con el diseño de DeepSight, usando recursos\plantilla_estadisticas.html
#  4. Guarda también estadisticas\estadisticas_FECHA.xml
#  5. Vacía resultados\ (borra los XML ya procesados) para el siguiente periodo.
#  6. Abre el HTML en el navegador.
#
#  Uso:   .\estadisticas_windows.ps1      (o doble clic en "Windows - Ver estadisticas.bat")
#         -NoAbrir : no abre el navegador al terminar
# =============================================================================

param([switch]$NoAbrir)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$DIR         = Split-Path -Parent $MyInvocation.MyCommand.Path
$RAIZ        = Split-Path -Parent (Split-Path -Parent $DIR)   # este script está en scripts\windows
$RESULTADOS  = Join-Path $RAIZ "resultados"
$CARPETA_EST = Join-Path $RAIZ "estadisticas"
$RECURSOS    = Join-Path $RAIZ "recursos"
$PLANTILLA   = Join-Path $RECURSOS "plantilla_estadisticas.html"
$TOP         = 10
$UTF8        = New-Object System.Text.UTF8Encoding $false
$INV         = [Globalization.CultureInfo]::InvariantCulture

function Paso($n, $texto) { Write-Host ""; Write-Host "[$n/6] $texto" }
function Sumar($tabla, $clave, $n) { if ($tabla.ContainsKey($clave)) { $tabla[$clave] += $n } else { $tabla[$clave] = $n } }

Write-Host "============================================================"
Write-Host "  ESTADÍSTICAS DE SCRAPING  (Windows)"
Write-Host "============================================================"

# ------------------------------------------------ 1. Buscar informes
Paso 1 "Buscando informes nuevos en resultados\ ..."
$ficheros = @(Get-ChildItem -Path $RESULTADOS -Filter *.xml -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($ficheros.Count -eq 0) {
    Write-Host "   No hay informes nuevos desde las últimas estadísticas."
    Write-Host "   Ejecuta antes el scraper para generar alguno."
    exit 1
}
foreach ($f in $ficheros) { Write-Host "   - $($f.Name)" }
Write-Host "   $($ficheros.Count) informe(s) encontrado(s)."
if (-not (Test-Path $PLANTILLA)) { Write-Host "   ERROR: falta la plantilla $PLANTILLA"; exit 1 }

# ------------------------------------------------ 2. Leer y combinar
Paso 2 "Leyendo y combinando los informes ..."
$procesados = New-Object System.Collections.ArrayList
$informes   = New-Object System.Collections.ArrayList
$frases     = New-Object System.Collections.ArrayList
$terminos   = [ordered]@{}
$sist = @{}; $web = @{}; $idioma = @{}; $numero = @{}; $vtot = @{}; $pag = @{}
$desde = ""; $hasta = ""

foreach ($f in $ficheros) {
    try { $xml = New-Object xml; $xml.Load($f.FullName) } catch { Write-Host "   (se ignora $($f.Name): XML no válido)"; continue }
    $raiz = $xml.informe_scraping
    if ($null -eq $raiz) { Write-Host "   (se ignora $($f.Name): no es un informe de scraping)"; continue }
    [void]$procesados.Add($f.FullName)
    $m = $raiz.metadatos
    $fecha = [string]$m.fecha
    if ($desde -eq "" -or [string]::CompareOrdinal($fecha, $desde) -lt 0) { $desde = $fecha }
    if ([string]::CompareOrdinal($fecha, $hasta) -gt 0) { $hasta = $fecha }
    Sumar $sist ([string]$m.sistema) 1
    Sumar $web  ([string]$m.url_inicial) 1
    [void]$informes.Add([ordered]@{ fichero = $f.Name; fecha = $fecha; sistema = [string]$m.sistema; url = [string]$m.url_inicial
                                    paginas = [int]$m.paginas_analizadas; palabras = [int]$m.palabras_totales })

    foreach ($p in @($raiz.busqueda.palabra)) {
        if ($null -eq $p) { continue }
        $t = $p.termino; $tot = [int]$p.total
        if (-not $terminos.Contains($t)) {
            $terminos[$t] = [pscustomobject]@{ Termino = $t; Buscado = 0; Encontrado = 0; Total = 0; Max = 0; Variantes = [ordered]@{} }
        }
        $e = $terminos[$t]
        $e.Buscado++; $e.Total += $tot
        if ($tot -gt 0) { $e.Encontrado++ }
        if ($tot -gt $e.Max) { $e.Max = $tot }
        foreach ($v in @($p.variante)) {
            if ($null -eq $v) { continue }
            $ap = [int]$v.apariciones
            $k = "$($v.texto)`t$($v.idioma)`t$($v.numero)"
            Sumar $vtot $k $ap; Sumar $idioma $v.idioma $ap; Sumar $numero $v.numero $ap
            if (-not $e.Variantes.Contains($k)) { $e.Variantes[$k] = [ordered]@{ texto = $v.texto; idioma = $v.idioma; numero = $v.numero; apariciones = 0 } }
            $e.Variantes[$k].apariciones += $ap
        }
        foreach ($ep in @($p.en_pagina)) { if ($ep) { Sumar $pag $ep.url ([int]$ep.apariciones) } }
        foreach ($fr in @($p.frase)) {
            if ($null -eq $fr) { continue }
            [void]$frases.Add([ordered]@{ termino = $t; variante = $fr.variante; url = $fr.url; fecha = $fecha
                                          antes = $fr.antes; coincidencia = $fr.coincidencia; despues = $fr.despues })
        }
    }
}
if ($procesados.Count -eq 0) { Write-Host "   Ningún informe válido. No se genera nada."; exit 1 }
Write-Host "   $($procesados.Count) informe(s), $($terminos.Count) término(s), $($frases.Count) frase(s) de contexto."

$listaT = @($terminos.Values | Sort-Object @{e = 'Total'; Descending = $true }, @{e = 'Buscado'; Descending = $true }, Termino)
$listaV = @($vtot.GetEnumerator() | Where-Object { $_.Value -gt 0 } |
            Sort-Object @{e = { $_.Value }; Descending = $true }, @{e = { $_.Key } } | Select-Object -First $TOP |
            ForEach-Object { $k = $_.Key.Split("`t"); [pscustomobject]@{ Texto = $k[0]; Idioma = $k[1]; Numero = $k[2]; Ap = $_.Value } })
function Ordenada($tabla) { @($tabla.GetEnumerator() | Sort-Object @{e = { $_.Value }; Descending = $true }) }
function Pct($n, $total) { if ($total -gt 0) { 100.0 * $n / $total } else { 0 } }
$sumI = 0; foreach ($n in $idioma.Values) { $sumI += $n }
$sumU = 0; foreach ($n in $numero.Values) { $sumU += $n }

# ------------------------------------------------ 3. Resumen en consola
Paso 3 "Resumen de las estadísticas"
Write-Host "   Periodo             : $desde  ->  $hasta"
Write-Host ("   Sistemas            : " + ((Ordenada $sist | ForEach-Object { "$($_.Key) ($($_.Value))" }) -join ", "))
Write-Host "   Webs analizadas     :"
foreach ($w in (Ordenada $web)) { Write-Host ("      {0,3} informe(s)  {1}" -f $w.Value, $w.Key) }
Write-Host ""
Write-Host "   TÉRMINOS (ordenados por apariciones totales)"
Write-Host ("     {0,-18} {1,9} {2,10} {3,8} {4,8} {5,6}" -f "termino", "buscado", "encontrado", "total", "media", "max")
$maxT = 0; foreach ($e in $listaT) { if ($e.Total -gt $maxT) { $maxT = $e.Total } }
foreach ($e in $listaT) {
    $barra = if ($maxT -gt 0) { "#" * [int][Math]::Floor($e.Total * 25 / $maxT + 0.5) } else { "" }
    $media = ($e.Total / $e.Buscado).ToString("0.00", $INV)
    Write-Host ("     {0,-18} {1,9} {2,10} {3,8} {4,8} {5,6}  {6}" -f $e.Termino, $e.Buscado, $e.Encontrado, $e.Total, $media, $e.Max, $barra)
}
Write-Host ""
Write-Host "   APARICIONES POR IDIOMA"
foreach ($i in (Ordenada $idioma)) { Write-Host ("     {0,-10} {1,8}  ({2,5}%)" -f $i.Key, $i.Value, (Pct $i.Value $sumI).ToString("0.0", $INV)) }
Write-Host ""
Write-Host "   APARICIONES POR NÚMERO"
foreach ($u in (Ordenada $numero)) { Write-Host ("     {0,-10} {1,8}  ({2,5}%)" -f $u.Key, $u.Value, (Pct $u.Value $sumU).ToString("0.0", $INV)) }
Write-Host ""
Write-Host "   TOP $TOP VARIANTES MÁS ENCONTRADAS"
$pos = 0
foreach ($v in $listaV) { $pos++; Write-Host ("     {0,2}. {1,-20} {2,-6} {3,-9} {4,6}" -f $pos, $v.Texto, $v.Idioma, $v.Numero, $v.Ap) }

# ------------------------------------------------ 4. HTML
Paso 4 "Generando el informe HTML con gráficos ..."
if (-not (Test-Path $CARPETA_EST)) { New-Item -ItemType Directory -Path $CARPETA_EST | Out-Null }
$sello    = Get-Date -Format "yyyyMMdd_HHmmss"
$generado = Get-Date -Format "yyyy-MM-dd'T'HH:mm:ss"
$html     = Join-Path $CARPETA_EST "estadisticas_$sello.html"
$xmlSal   = Join-Path $CARPETA_EST "estadisticas_$sello.xml"

$logo = ""
$png = Join-Path $RECURSOS "logo.png"; $svg = Join-Path $RECURSOS "logo.svg"
if (Test-Path $png)     { $logo = "data:image/png;base64," + [Convert]::ToBase64String([IO.File]::ReadAllBytes($png)) }
elseif (Test-Path $svg) { $logo = "data:image/svg+xml;base64," + [Convert]::ToBase64String([IO.File]::ReadAllBytes($svg)) }
if ($logo) { Write-Host "   Logo incrustado desde recursos\." } else { Write-Host "   (No hay logo en recursos\: se genera sin él.)" }

$datos = [ordered]@{
    generado = $generado; sistema = "Windows"; script = "estadisticas_windows.ps1"
    periodo  = [ordered]@{ desde = $desde; hasta = $hasta }
    logo     = $logo
    informes = $informes
    terminos = @($listaT | ForEach-Object { [ordered]@{ termino = $_.Termino; buscado = $_.Buscado; encontrado = $_.Encontrado
                                                       total = $_.Total; maximo = $_.Max; variantes = @($_.Variantes.Values) } })
    paginas  = @($pag.GetEnumerator() | ForEach-Object { [ordered]@{ url = $_.Key; apariciones = $_.Value } })
    frases   = $frases
}
$json = ConvertTo-Json -InputObject $datos -Depth 6 -Compress
$json = $json.Replace('<', '<')   # nada de "</script>" dentro del JSON
$plantilla = [IO.File]::ReadAllText($PLANTILLA, $UTF8)
[IO.File]::WriteAllText($html, $plantilla.Replace('/*__DATOS__*/null', $json), $UTF8)
Write-Host "   -> estadisticas\$(Split-Path $html -Leaf)"

# ------------------------------------------------ 5. XML
Paso 5 "Guardando las estadísticas en XML ..."
function E([string]$s) { [System.Security.SecurityElement]::Escape($s) }
$x = New-Object System.Text.StringBuilder
function L([string]$s) { [void]$x.Append($s).Append("`n") }
L '<?xml version="1.0" encoding="UTF-8"?>'
L "<estadisticas generado=`"$generado`" sistema=`"Windows`" informes=`"$($procesados.Count)`">"
L "  <periodo desde=`"$desde`" hasta=`"$hasta`"/>"
L '  <sistemas>'
foreach ($s in (Ordenada $sist)) { L "    <sistema nombre=`"$(E $s.Key)`" informes=`"$($s.Value)`"/>" }
L '  </sistemas>'
L '  <webs>'
foreach ($w in (Ordenada $web)) { L "    <web url=`"$(E $w.Key)`" informes=`"$($w.Value)`"/>" }
L '  </webs>'
L '  <terminos>'
foreach ($e in $listaT) {
    $media = ($e.Total / $e.Buscado).ToString("0.00", $INV)
    L "    <termino nombre=`"$(E $e.Termino)`" veces_buscado=`"$($e.Buscado)`" veces_encontrado=`"$($e.Encontrado)`" apariciones_totales=`"$($e.Total)`" media=`"$media`" maximo=`"$($e.Max)`"/>"
}
L '  </terminos>'
L '  <idiomas>'
foreach ($i in (Ordenada $idioma)) { L "    <idioma nombre=`"$(E $i.Key)`" apariciones=`"$($i.Value)`" porcentaje=`"$((Pct $i.Value $sumI).ToString("0.0", $INV))`"/>" }
L '  </idiomas>'
L '  <numeros>'
foreach ($u in (Ordenada $numero)) { L "    <numero nombre=`"$(E $u.Key)`" apariciones=`"$($u.Value)`" porcentaje=`"$((Pct $u.Value $sumU).ToString("0.0", $INV))`"/>" }
L '  </numeros>'
L "  <variantes_top limite=`"$TOP`">"
$pos = 0
foreach ($v in $listaV) { $pos++; L "    <variante posicion=`"$pos`" texto=`"$(E $v.Texto)`" idioma=`"$($v.Idioma)`" numero=`"$($v.Numero)`" apariciones=`"$($v.Ap)`"/>" }
L '  </variantes_top>'
L "  <frases total=`"$($frases.Count)`">"
foreach ($fr in $frases) {
    L "    <frase termino=`"$(E $fr.termino)`" variante=`"$(E $fr.variante)`" fecha=`"$($fr.fecha)`" url=`"$(E $fr.url)`" antes=`"$(E $fr.antes)`" coincidencia=`"$(E $fr.coincidencia)`" despues=`"$(E $fr.despues)`"/>"
}
L '  </frases>'
L '</estadisticas>'
[IO.File]::WriteAllText($xmlSal, $x.ToString(), $UTF8)
Write-Host "   -> estadisticas\$(Split-Path $xmlSal -Leaf)"

# ------------------------------------------------ 6. Vaciar resultados
Paso 6 "Vaciando resultados\ para los próximos scrapings ..."
$okHtml = (Test-Path $html) -and (Get-Item $html).Length -gt 0 -and -not ([IO.File]::ReadAllText($html, $UTF8).Contains('/*__DATOS__*/'))
$okXml  = (Test-Path $xmlSal) -and (Get-Item $xmlSal).Length -gt 0
if ($okHtml -and $okXml) {
    foreach ($p in $procesados) { Remove-Item -LiteralPath $p -Force }
    Write-Host "   $($procesados.Count) informe(s) borrado(s). Las próximas estadísticas solo usarán scrapings nuevos."
} else {
    Write-Host "   ATENCIÓN: el HTML o el XML no se han generado bien; NO se borra nada de resultados\."
    exit 1
}

Write-Host ""
Write-Host "============================================================"
Write-Host "  Informe listo: estadisticas\$(Split-Path $html -Leaf)"
Write-Host "============================================================"
if (-not $NoAbrir) {
    Write-Host "Abriendo el informe en el navegador ..."
    Start-Process $html
}
