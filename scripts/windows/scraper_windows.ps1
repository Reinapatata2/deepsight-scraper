# =============================================================================
#  scraper_windows.ps1  -  Scraping de palabras clave (versión Windows / PowerShell)
# -----------------------------------------------------------------------------
#  1. Pide palabras clave por consola hasta que se escriba "fin".
#  2. Cada palabra se amplía a español + inglés y singular + plural
#     (colegio -> colegio, colegios, school, schools) usando diccionario.csv
#     y reglas gramaticales.
#  3. Descarga la web (y las páginas enlazadas del mismo dominio, hasta
#     MAX_PAGINAS) y cuenta las apariciones de cada variante.
#  4. Guarda el resultado en resultados\scraping_windows_FECHA.xml
#
#  Uso:   .\scraper_windows.ps1 [-Url <url>] [-MaxPaginas <n>]
#         (o doble clic en "Windows - Ejecutar scraper.bat")
#  Requisitos: Windows PowerShell 5.1 (viene con Windows 10/11) o PowerShell 7
# =============================================================================

param(
    [string]$Url = "",
    [int]$MaxPaginas = 0
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
# Windows PowerShell 5.1 no activa TLS 1.2 por defecto
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$DIR         = Split-Path -Parent $MyInvocation.MyCommand.Path
$RAIZ        = Split-Path -Parent (Split-Path -Parent $DIR)   # este script está en scripts\windows
$DICCIONARIO = Join-Path (Join-Path $RAIZ "config") "diccionario.csv"
$CONFIG      = Join-Path (Join-Path $RAIZ "config") "config.txt"
$RESULTADOS  = Join-Path $RAIZ "resultados"
$USER_AGENT  = "Mozilla/5.0 (Windows NT 10.0) ScraperClase/1.0"
$PAUSA       = 1          # segundos entre peticiones, para no saturar la web
$UTF8        = New-Object System.Text.UTF8Encoding $false   # UTF-8 sin BOM

if (-not (Test-Path $RESULTADOS)) { New-Item -ItemType Directory -Path $RESULTADOS | Out-Null }

# ----------------------------------------------------------------- utilidades
# Mapa de tildes -> letra sin tilde (la ñ se conserva). Se usan códigos de
# carácter para que el script no dependa de la codificación del fichero.
$MAPA_TILDES = @{}
foreach ($par in @(
    @('a', 0xE1,0xE0,0xE2,0xE4), @('e', 0xE9,0xE8,0xEA,0xEB), @('i', 0xED,0xEC,0xEE,0xEF),
    @('o', 0xF3,0xF2,0xF4,0xF6), @('u', 0xFA,0xF9,0xFB,0xFC), @('c', 0xE7))) {
    for ($k = 1; $k -lt $par.Count; $k++) { $MAPA_TILDES[[string][char]$par[$k]] = $par[0] }
}
$ENYE = [string][char]0xF1

function Quitar-Tildes([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [string]$ch
        if ($MAPA_TILDES.ContainsKey($c)) { [void]$sb.Append($MAPA_TILDES[$c]) } else { [void]$sb.Append($c) }
    }
    $sb.ToString()
}

# Texto libre -> clave normalizada ("Lápices  de Colores" -> "lapices de colores")
function Normalizar([string]$s) {
    if ($null -eq $s) { return "" }
    $s = Quitar-Tildes ($s.ToLowerInvariant())
    $s = $s -creplace "[^a-z0-9$ENYE]", " "
    ($s -creplace " +", " ").Trim()
}

function Xml-Esc([string]$s) { [System.Security.SecurityElement]::Escape($s) }

# ------------------------------------------------------ reglas singular/plural
function Es-Plural([string]$w) {
    if ($w -cmatch '[aeiou]$') { return "${w}s" }
    if ($w -cmatch 'z$')       { return ($w -creplace 'z$', 'ces') }
    return "${w}es"
}
function Es-Singular([string]$w) {
    if ($w -cmatch 'ces$')        { return ($w -creplace 'ces$', 'z') }
    if ($w -cmatch '[lrndjy]es$') { return ($w -creplace 'es$', '') }
    if ($w -cmatch 's$')          { return ($w -creplace 's$', '') }
    return $w
}
function En-Plural([string]$w) {
    if ($w -cmatch '[^aeiou]y$')     { return ($w -creplace 'y$', 'ies') }
    if ($w -cmatch '(s|x|z|ch|sh)$') { return "${w}es" }
    return "${w}s"
}
function En-Singular([string]$w) {
    if ($w -cmatch 'ies$')               { return ($w -creplace 'ies$', 'y') }
    if ($w -cmatch '(ss|ch|sh|x|z)es$')  { return ($w -creplace 'es$', '') }
    if ($w -cmatch 's$')                 { return ($w -creplace 's$', '') }
    return $w
}
# ¿Parece plural? (termina en s, pero no en -ss, -us, -is: class, bus, país)
function Parece-Plural([string]$w) {
    if ($w -cmatch '(ss|us|is)$') { return $false }
    return ($w -cmatch 's$' -and $w.Length -gt 3)
}
function Par-SingPlur([string]$w, [string]$idioma) {
    if (Parece-Plural $w) {
        $s = if ($idioma -eq 'es') { Es-Singular $w } else { En-Singular $w }
        return @($s, $w)
    }
    $p = if ($idioma -eq 'es') { Es-Plural $w } else { En-Plural $w }
    return @($w, $p)
}

# ------------------------------------------- singular/plural español con tildes
# En el código se escribe A E I O U W N en lugar de á é í ó ú ü ñ (Tildes las
# cambia), para que el script no dependa de la codificación del fichero.
function Tildes([string]$s) {
    $mapa = @{ 'A' = 0xE1; 'E' = 0xE9; 'I' = 0xED; 'O' = 0xF3; 'U' = 0xFA; 'W' = 0xFC; 'N' = 0xF1 }
    foreach ($k in $mapa.Keys) { $s = $s.Replace($k, [string][char]$mapa[$k]) }
    return $s
}
$V_TILDE  = Tildes 'AEIOU'
$V_PLANA  = 'aeiou'
$VOCALES  = Tildes 'aeiouAEIOUW'
$FUERTES  = Tildes 'aeoAEO'
$D_TILDE  = Tildes 'IU'                       # í ú: siempre forman sílaba aparte (país)
$CON_TILDE = Tildes 'AEIOUWN'
$ESPECIALES_P = @{ (Tildes 'carActer') = 'caracteres'; (Tildes 'rEgimen') = (Tildes 'regImenes'); (Tildes 'espEcimen') = (Tildes 'especImenes') }
$ESPECIALES_S = @{}; foreach ($k in $ESPECIALES_P.Keys) { $ESPECIALES_S[$ESPECIALES_P[$k]] = $k }
$RX_ES1 = Tildes '[aeuAEU]des$'
$RX_ES2 = Tildes '[aeiouAEIOUW][lrn]es$'
$RX_ES3 = Tildes '[eiouEIOU]ses$'
$RX_AGUDA_S = Tildes '[AEIOU]s$'

# Minúsculas conservando tildes y ñ, sin signos ("¡Canción!" -> "canción")
function Limpiar([string]$s) {
    if ($null -eq $s) { return "" }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToLowerInvariant().ToCharArray()) {
        $c = [string]$ch
        if ($CON_TILDE.Contains($c)) { [void]$sb.Append($c) }
        elseif ($MAPA_TILDES.ContainsKey($c)) { [void]$sb.Append($MAPA_TILDES[$c]) }
        elseif ($c -cmatch '^[a-z0-9]$') { [void]$sb.Append($c) }
        else { [void]$sb.Append(' ') }
    }
    ($sb.ToString() -creplace ' +', ' ').Trim()
}

function Es-Vocal([string]$c)  { $c.Length -eq 1 -and $VOCALES.Contains($c) }
function Es-Fuerte([string]$c) { $c.Length -eq 1 -and $FUERTES.Contains($c) }
function Vocal-En([string]$w, [int]$i) { $i -ge 0 -and $i -lt $w.Length -and (Es-Vocal ([string]$w[$i])) }
function Cambiar([string]$w, [int]$i, [string]$c) { $w.Substring(0, $i) + $c + $w.Substring($i + 1) }
function Quitar-Tilde([string]$c) { $k = $V_TILDE.IndexOf($c, [StringComparison]::Ordinal); if ($k -ge 0) { [string]$V_PLANA[$k] } else { $c } }
function Poner-Tilde([string]$c)  { $k = $V_PLANA.IndexOf($c, [StringComparison]::Ordinal); if ($k -ge 0) { [string]$V_TILDE[$k] } else { $c } }

# Grupos de vocales que forman sílaba: lista de @(inicio, fin)
function Grupos-Vocales([string]$w) {
    $g = New-Object System.Collections.ArrayList; $ant = ""
    for ($i = 0; $i -lt $w.Length; $i++) {
        $c = [string]$w[$i]
        if (-not (Es-Vocal $c)) { $ant = ""; continue }
        if ($ant -ne "" -and -not ((Es-Fuerte $ant) -and (Es-Fuerte $c)) -and -not $D_TILDE.Contains($ant) -and -not $D_TILDE.Contains($c)) {
            $g[$g.Count - 1][1] = $i
        } else { [void]$g.Add(@($i, $i)) }
        $ant = $c
    }
    return ,$g
}
function Grupo-De($g, [int]$pos) {   # nº de grupo (desde 1) que contiene la posición, o 0
    for ($k = 0; $k -lt $g.Count; $k++) { if ($pos -ge $g[$k][0] -and $pos -le $g[$k][1]) { return $k + 1 } }
    return 0
}
# Pone la tilde en el grupo k: en la vocal fuerte, o en la última si son dos débiles
function Acentuar([string]$w, $g, [int]$k) {
    $ini = $g[$k - 1][0]; $pos = $g[$k - 1][1]
    for ($i = $ini; $i -le $g[$k - 1][1]; $i++) { if (Es-Fuerte ([string]$w[$i])) { $pos = $i; break } }
    return (Cambiar $w $pos (Poner-Tilde ([string]$w[$pos])))
}

function Es-PluralTildes([string]$s) {
    if ($s -eq "") { return "" }
    if ($ESPECIALES_P.ContainsKey($s)) { return $ESPECIALES_P[$s] }
    $u = [string]$s[$s.Length - 1]
    $g = Grupos-Vocales $s; $n = $g.Count
    $pos = $s.IndexOfAny($V_TILDE.ToCharArray())
    $k = if ($pos -ge 0) { Grupo-De $g $pos } else { 0 }
    # Llanas o esdrújulas en -s/-x no cambian: crisis, virus, análisis, tórax
    if (($u -eq 's' -or $u -eq 'x') -and $n -ge 2 -and $k -ne $n) { return $s }
    if (Es-Vocal $u)    { $p = $s + 's'; $suf = 's' }
    elseif ($u -eq 'z') { $p = $s.Substring(0, $s.Length - 1) + 'ces'; $suf = 'ces' }
    else                { $p = $s + 'es'; $suf = 'es' }
    if ($pos -ge 0) {
        # Agudas en -n/-s pierden la tilde (canción -> canciones), salvo hiato (país -> países)
        $c = [string]$s[$pos]
        $hiato = $D_TILDE.Contains($c) -and ((Vocal-En $s ($pos - 1)) -or (Vocal-En $s ($pos + 1)))
        if ($suf -eq 'es' -and ($u -eq 'n' -or $u -eq 's') -and $k -eq $n -and -not $hiato) { $p = Cambiar $p $pos (Quitar-Tilde $c) }
    } elseif ($suf -eq 'es' -and $u -eq 'n' -and $n -ge 2) {
        $p = Acentuar $p $g ($n - 1)          # examen -> exámenes, joven -> jóvenes
    }
    return $p
}

function Es-SingularTildes([string]$p) {
    if ($ESPECIALES_S.ContainsKey($p)) { return $ESPECIALES_S[$p] }
    # ¿Se quita "-es" (ciudades, papeles, flores, canciones, ingleses) o solo
    # "-s" (pirámides, calles, padres, carnes, viajes, clases)?
    if ($p -cmatch 'ces$') { $s = $p.Substring(0, $p.Length - 3) + 'z'; $suf = 'ces' }
    elseif ($p -cmatch $RX_ES1 -or ($p -cmatch $RX_ES2 -and $p -cnotmatch 'lles$') -or $p -cmatch 'yes$' -or
            $p -cmatch 'relojes$' -or $p -cmatch $RX_ES3) { $s = $p.Substring(0, $p.Length - 2); $suf = 'es' }
    elseif ($p -cmatch 's$') { $s = $p.Substring(0, $p.Length - 1); $suf = 's' }
    else { return $p }
    $u = [string]$s[$s.Length - 1]
    $g = Grupos-Vocales $s; $n = $g.Count
    $pos = $s.IndexOfAny($V_TILDE.ToCharArray())
    $k = if ($pos -ge 0) { Grupo-De $g $pos } else { 0 }
    if ($pos -ge 0) {
        if ($suf -eq 'es' -and $u -eq 'n' -and $n -ge 2 -and $k -eq $n - 1) {
            $s = Cambiar $s $pos (Quitar-Tilde ([string]$s[$pos]))      # exámenes -> examen
        }
    } elseif ($suf -eq 'es' -and ($u -eq 'n' -or $u -eq 's') -and $n -ge 2) {
        $s = Acentuar $s $g $n                                          # canciones -> canción
    }
    return $s
}

# Como Par-SingPlur, pero para una palabra española escrita con sus tildes, que
# se conservan o se ajustan según las reglas de acentuación:
#   pirámide -> pirámides    canción -> canciones    examen -> exámenes
#   país -> países           lápiz -> lápices        crisis -> crisis
#   canciones -> canción     jóvenes -> joven
function Es-ParTildes([string]$palabra) {
    $w = Limpiar $palabra
    $modo = if (Parece-Plural (Normalizar $w)) { 's' } else { 'p' }
    if ($w -cmatch $RX_AGUDA_S) { $modo = 'p' }       # inglés, compás, interés: singular
    $pre = ""; $i = $w.LastIndexOf(' ')
    if ($i -ge 0) { $pre = $w.Substring(0, $i + 1); $w = $w.Substring($i + 1) }   # solo la última palabra
    if ($modo -eq 's') { return @(($pre + (Es-SingularTildes $w)), ($pre + $w)) }
    return @(($pre + $w), ($pre + (Es-PluralTildes $w)))
}

# ---------------------------------------------------------------- diccionario
if (-not (Test-Path $DICCIONARIO)) {
    [IO.File]::WriteAllText($DICCIONARIO, "# es_singular;es_plural;en_singular;en_plural`n", $UTF8)
}

function Buscar-EnDiccionario([string]$clave) {
    foreach ($linea in [IO.File]::ReadAllLines($DICCIONARIO, $UTF8)) {
        $linea = $linea.Trim()
        if ($linea -eq "" -or $linea.StartsWith("#")) { continue }
        $campos = $linea.Split(';')
        for ($k = 0; $k -lt [Math]::Min(4, $campos.Count); $k++) {
            if ((Normalizar $campos[$k]) -ceq $clave) { return $linea }
        }
    }
    return $null
}

function Guardar-EnDiccionario([string]$fila) {
    $bytes = [IO.File]::ReadAllBytes($DICCIONARIO)
    $prefijo = if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -ne 10) { "`n" } else { "" }
    [IO.File]::AppendAllText($DICCIONARIO, "$prefijo$fila`n", $UTF8)
}

# --------------------------------------------- estructuras de términos/variantes
$TERMINOS  = New-Object System.Collections.ArrayList   # objetos {Termino; Variantes}

function Anadir-Variante($term, [string]$texto, [string]$idioma, [string]$numero) {
    $clave = Normalizar $texto
    if ($clave -eq "") { return }
    foreach ($v in $term.Variantes) {
        if ($v.Clave -ceq $clave) {
            if ($v.Idioma -ne $idioma) { $v.Idioma = "ambos" }
            if ($v.Numero -ne $numero) { $v.Numero = "ambos" }
            return
        }
    }
    [void]$term.Variantes.Add([pscustomobject]@{
        Texto = $texto; Clave = $clave; Idioma = $idioma; Numero = $numero; Total = 0; PorPagina = @{}
        Frases = (New-Object System.Collections.ArrayList) })
}

function Procesar-Palabra([string]$entrada) {
    $clave = Normalizar $entrada
    if ($clave -eq "") { return }

    $fila = Buscar-EnDiccionario $clave
    if ($fila) {
        $c1 = $fila.Split(';')[0]
        foreach ($t in $TERMINOS) {
            if ((Normalizar $t.Termino) -ceq (Normalizar $c1)) { Write-Host "   ('$c1' ya estaba en la lista)"; return }
        }
    } else {
        foreach ($t in $TERMINOS) {
            $tn = Normalizar $t.Termino
            if ($tn -ceq $clave -or $tn -ceq ($clave -creplace 's$', '')) { Write-Host "   ('$($t.Termino)' ya estaba en la lista)"; return }
        }
        # $dispEs = palabra española tal y como se mostrará; $lado = lo que se ha traducido
        $orig = ($entrada.Trim().ToLowerInvariant() -creplace ' +', ' ')
        $dispEs = ""; $palEn = ""; $lado = "en"
        if ($script:TRADUCTOR_ONLINE) {
            Write-Host "   Buscando la traducción de '$orig'..."
            $res = Traducir-Wikt $orig
            if ($res) {
                if ($res.Idioma -eq 'es') { $dispEs = $res.Lema; $palEn = Normalizar $res.Glosa }
                else { $palEn = $clave; $lado = "es"; $dispEs = [string](Traducir $clave 'en|es') }
                # Palabra igual en los dos idiomas (test, hotel): ¿hay otra forma en español?
                if ($lado -eq "en" -and $palEn -ceq (Normalizar $dispEs)) {
                    $vuelta = Traducir $clave 'en|es'
                    if ($vuelta -and (Normalizar $vuelta) -cne $clave) { $dispEs = $vuelta; $lado = "es" }
                }
            } else {
                $ida = Traducir $clave 'es|en'
                if ($ida) {
                    $ida = Normalizar $ida
                    if ($ida -cne $clave) { $dispEs = $orig; $palEn = $ida }                       # era español
                    else {
                        $vuelta = Traducir $clave 'en|es'
                        if ($vuelta -and (Normalizar $vuelta) -cne $clave) { $dispEs = $vuelta; $palEn = $clave; $lado = "es" }  # era inglés
                        else { $dispEs = $orig; $palEn = $clave }                                 # igual en ambos
                    }
                }
            }
        }

        if ($dispEs -ne "" -and $palEn -ne "") {
            Write-Host "   Traducción: $dispEs (español) = $palEn (inglés)"
            if ($script:CONFIRMAR_TRADUCCION) {
                if ($lado -eq "es") { $corr = Read-Host "   Pulsa Enter si es correcta, o escribe la palabra correcta en español" }
                else { $corr = Read-Host "   Pulsa Enter si es correcta, o escribe la traducción correcta en inglés" }
                if ((Normalizar $corr) -ne "") {
                    if ($lado -eq "es") { $dispEs = $corr.Trim().ToLowerInvariant() } else { $palEn = Normalizar $corr }
                }
            }
        } else {
            # Sin internet, traductor desactivado o palabra no encontrada: se pregunta
            if ($script:TRADUCTOR_ONLINE) { Write-Host "   No se ha encontrado traducción de '$orig' (¿sin internet o palabra rara?)." }
            $dispEs = $orig
            $palEn = Normalizar (Read-Host "   Escribe su traducción al inglés (Enter para buscarla tal cual)")
        }

        $palEs = Normalizar $dispEs
        # Singular y plural con sus tildes (pirámide -> pirámides, canción -> canciones)
        $es = Es-ParTildes $dispEs
        foreach ($t in $TERMINOS) {
            if ((Normalizar $t.Termino) -ceq (Normalizar $es[0])) { Write-Host "   ('$($t.Termino)' ya estaba en la lista)"; return }
        }
        if ($palEn -ne "") {
            $en = Par-SingPlur $palEn 'en'
            $fila = "$($es[0]);$($es[1]);$($en[0]);$($en[1])"
            # Se guarda como caché para no volver a traducirla (no si es igual en ambos idiomas)
            if ($palEs -cne $palEn) { Guardar-EnDiccionario $fila }
        } else {
            $fila = "$($es[0]);$($es[1]);;"
        }
    }

    $c = $fila.Split(';')
    while ($c.Count -lt 4) { $c += "" }
    $term = [pscustomobject]@{ Termino = $c[0]; Variantes = (New-Object System.Collections.ArrayList) }
    Anadir-Variante $term $c[0] 'es' 'singular'
    Anadir-Variante $term $c[1] 'es' 'plural'
    Anadir-Variante $term $c[2] 'en' 'singular'
    Anadir-Variante $term $c[3] 'en' 'plural'
    [void]$TERMINOS.Add($term)
    Write-Host ("   -> se buscará: " + (($term.Variantes | ForEach-Object { $_.Texto }) -join ", "))
}

# ------------------------------------------------- traducción automática
# Orden: 1) Wiktionary (diccionario libre, muy fiable con palabras sueltas)
#        2) MyMemory (traductor gratuito, de reserva)
#        3) preguntar al usuario
# Ninguno necesita registro ni clave. Solo se envía la palabra a traducir.
$USER_AGENT_API = "ScraperClase/1.0 (proyecto educativo de clase; PowerShell)"

function Limpiar-Glosa([string]$s) {   # "a <b>school</b> (institution), college" -> "school"
    $s = [regex]::Replace($s, '<[^>]*>', '')
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    $s = [regex]::Replace($s, '\([^)]*\)', '')
    $s = ($s -split '[,;:]')[0].Trim().ToLowerInvariant() -creplace ' +', ' '
    return ($s -creplace '^(a|an|the|to) ', '').Trim()
}

# Devuelve @{Idioma='es'; Lema; Glosa} si es palabra española, @{Idioma='en'} si es inglesa, o $null
function Traducir-Wikt([string]$w, [int]$prof = 0) {
    try {
        $u = "https://en.wiktionary.org/api/rest_v1/page/definition/" + [Uri]::EscapeDataString(($w -replace ' ', '_'))
        $r = Invoke-RestMethod -Uri $u -UserAgent $USER_AGENT_API -TimeoutSec 8
    } catch { return $null }
    $idiomas = @($r.PSObject.Properties | ForEach-Object { $_.Name })
    if ($idiomas -contains 'es') {
        $def = ""
        foreach ($item in $r.es) { if ($item.definitions) { $def = [string]$item.definitions[0].definition; break } }
        $def = Limpiar-Glosa $def
        # "plural of clarinete" -> se busca "clarinete"
        if ($prof -eq 0 -and $def -match '^(.*(plural|feminine|masculine|singular|form)) of (.+)$') {
            return (Traducir-Wikt ($Matches[3].Trim().ToLowerInvariant()) 1)
        }
        if ($def -eq "") { return $null }
        return @{ Idioma = 'es'; Lema = $w; Glosa = $def }
    }
    if ($idiomas -contains 'en') { return @{ Idioma = 'en' } }
    return $null
}

# MyMemory: devuelve la traducción en minúsculas y con sus tildes, o $null si no
# hay internet / cuota.
function Traducir([string]$texto, [string]$par) {
    if (-not $script:TRADUCTOR_ONLINE) { return $null }
    try {
        $u = "https://api.mymemory.translated.net/get?q=" + [Uri]::EscapeDataString($texto) +
             "&langpair=" + [Uri]::EscapeDataString($par)
        $r = Invoke-RestMethod -Uri $u -UserAgent $USER_AGENT -TimeoutSec 8
        if ([string]$r.responseStatus -ne "200") { return $null }
        $t = [string]$r.responseData.translatedText
        if ($t -eq "" -or $t -match 'mymemory') { return $null }
        $t = (Limpiar $t) -creplace '^(the|a|an|el|la|los|las|un|una|unos|unas) ', ''
        if ($t -eq "") { return $null }
        return $t
    } catch { return $null }
}

# ------------------------------------------------------------------ scraping
function Descargar([string]$u) {
    # Devuelve @{ Html; UrlFinal } o lanza una excepción
    $uri = [Uri]$u
    if ($uri.Scheme -eq 'file') {
        return @{ Html = [IO.File]::ReadAllText($uri.LocalPath, $UTF8); UrlFinal = $u }
    }
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $USER_AGENT -TimeoutSec 20 -MaximumRedirection 5
    $tipo = [string]($r.Headers['Content-Type'] -join ';')
    # Se lee cualquier página de texto: HTML, XML (como los informes de DeepSight), JSON, texto...
    if ($tipo -and $tipo -notmatch 'html|xml|json|text/') { throw "no es una página de texto ($tipo)" }
    # Decodificar respetando el charset (UTF-8 por defecto)
    $enc = $UTF8
    if ($tipo -match 'charset=([\w-]+)') { try { $enc = [Text.Encoding]::GetEncoding($Matches[1]) } catch {} }
    $html = $enc.GetString($r.RawContentStream.ToArray())
    $final = $u
    try {
        if ($r.BaseResponse.ResponseUri) { $final = $r.BaseResponse.ResponseUri.AbsoluteUri }                       # PS 5.1
        elseif ($r.BaseResponse.RequestMessage) { $final = $r.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }  # PS 7
    } catch {}
    return @{ Html = $html; UrlFinal = $final }
}

# HTML -> palabras de la página:
#   Orig = palabras tal cual aparecen (mayúsculas, tildes, puntuación), para las frases
#   Tok  = palabras normalizadas, para contar;  Idx = nº de la palabra original de cada Tok
function Html-APalabras([string]$html) {
    $op = [Text.RegularExpressions.RegexOptions]'Singleline, IgnoreCase'
    $t = [regex]::Replace($html, '<!--.*?(-->|$)', ' ', $op)
    foreach ($etiqueta in 'script', 'style', 'noscript', 'svg') {
        $t = [regex]::Replace($t, "<$etiqueta.*?(</$etiqueta>|$)", ' ', $op)
    }
    $t = [regex]::Replace($t, '<[^>]*>', ' ')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = [regex]::Replace($t, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Trim()
    # Minúsculas y sin tildes carácter a carácter: las dos versiones quedan alineadas
    $norm = Quitar-Tildes ($t.ToLowerInvariant())
    $orig = @(); $normPal = @()
    if ($t -ne "") { $orig = [regex]::Split($t, '\s+'); $normPal = [regex]::Split($norm, '\s+') }
    $tok = New-Object System.Collections.Generic.List[string]
    $idx = New-Object System.Collections.Generic.List[int]
    for ($w = 0; $w -lt $normPal.Count; $w++) {
        foreach ($m in [regex]::Matches($normPal[$w], "[a-z0-9$ENYE]+")) { $tok.Add($m.Value); $idx.Add($w) }
    }
    return @{ Orig = $orig; Tok = $tok; Idx = $idx }
}

function Unir-Palabras($orig, [int]$desde, [int]$hasta) {
    if ($desde -lt 0) { $desde = 0 }
    if ($hasta -ge $orig.Count) { $hasta = $orig.Count - 1 }
    if ($hasta -lt $desde) { return "" }
    return ($orig[$desde..$hasta] -join ' ')
}

function Extraer-Enlaces([string]$html, [string]$base, [string]$origen) {
    $salida = New-Object System.Collections.Generic.List[string]
    # Solo enlaces <a href> (no hojas de estilo, iconos, etc.)
    foreach ($m in [regex]::Matches($html, '<a\s[^>]*?href\s*=\s*["'']([^"''#]+)', 'IgnoreCase')) {
        $h = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value.Trim())
        if ($h -match '^(mailto|javascript|tel|data):') { continue }
        # Otros esquemas que no son páginas web (whatsapp:, skype:, sms:...)
        if ($h -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -and $h -notmatch '://') { continue }
        try { $abs = New-Object Uri ((New-Object Uri $base), $h) } catch { continue }
        if ($abs.GetLeftPart([UriPartial]::Authority) -ne $origen) { continue }
        if ($abs.AbsolutePath -match '\.(pdf|jpe?g|png|gif|svg|webp|ico|css|js|zip|mp3|mp4|docx?|xlsx?)$') { continue }
        # Nunca seguir enlaces de cerrar sesión (te desconectarían) ni de edición/historial
        if ($abs.AbsoluteUri -match 'logout|logoff|signout|sign-out|cerrar-?sesion|desconectar|salir') { continue }
        if ($abs.AbsoluteUri -match 'action=(edit|history)|oldid=|diff=|printable=|veaction=') { continue }
        $salida.Add($abs.AbsoluteUri)
    }
    return ,$salida
}

# Acepta la URL tal y como la escriba el usuario y la deja lista para descargar:
#   "  https://web.com/mi página "  ->  https://web.com/mi%20p%C3%A1gina
#   localhost:3000/informes         ->  http://localhost:3000/informes
#   C:\carpeta\pagina.html          ->  file:///C:/carpeta/pagina.html
# Devuelve "" si no hay URL o no se puede interpretar.
function Preparar-Url([string]$u) {
    if ($null -eq $u) { return "" }
    # Fuera espacios, comillas y < > de los extremos (al copiar y pegar)
    $u = $u.Trim().Trim('"', "'", '<', '>').Trim()
    if ($u -eq "") { return "" }
    if ($u.StartsWith("~/") -or $u.StartsWith("~\")) { $u = Join-Path $HOME $u.Substring(2) }
    if ($u -match '^[a-zA-Z]:[\\/]' -or $u.StartsWith('\\') -or ($u.StartsWith('/') -and -not $u.StartsWith('//'))) {
        try { return (New-Object Uri ([IO.Path]::GetFullPath($u))).AbsoluteUri } catch { return "" }
    }
    if ($u -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        if ($u.StartsWith('//')) { $u = "http:$u" } else { $u = "http://$u" }
    }
    $r = $null
    if ([Uri]::TryCreate($u, [UriKind]::Absolute, [ref]$r)) { return $r.AbsoluteUri }
    return ""
}

# =============================================================== PROGRAMA
Write-Host "============================================================"
Write-Host "  SCRAPER DE PALABRAS CLAVE  (Windows)"
Write-Host "============================================================"

$URL_DEF = ""; $MAX_DEF = 10; $script:TRADUCTOR_ONLINE = $true; $script:CONFIRMAR_TRADUCCION = $true
$PALABRAS_CONTEXTO = 5; $MAX_FRASES = 100
# Lee CLAVE=valor de config.txt sin exigir un formato estricto: da igual
# mayúsculas/minúsculas, espacios alrededor del "=" o comillas en el valor.
$VISTAS = @{}
if (Test-Path $CONFIG) {
    foreach ($l in [IO.File]::ReadAllLines($CONFIG, $UTF8)) {
        $l = $l.Trim()
        if ($l -eq "" -or $l.StartsWith("#")) { continue }
        $p = $l.IndexOf("=")
        if ($p -lt 1) { continue }
        $clave = $l.Substring(0, $p).Trim().ToUpperInvariant()
        if ($VISTAS.ContainsKey($clave)) { continue }          # vale la primera aparición
        $VISTAS[$clave] = $true
        $v = $l.Substring($p + 1).Trim()
        if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $num = $v -replace '\s', ''
        switch ($clave) {
            'URL'                  { $URL_DEF = $v }
            'MAX_PAGINAS'          { if ($num -match '^\d+$') { $MAX_DEF = [int]$num } }
            'TRADUCTOR_ONLINE'     { if ($num -ieq 'no') { $script:TRADUCTOR_ONLINE = $false } }
            'CONFIRMAR_TRADUCCION' { if ($num -ieq 'no') { $script:CONFIRMAR_TRADUCCION = $false } }
            'PALABRAS_CONTEXTO'    { if ($num -match '^\d+$') { $PALABRAS_CONTEXTO = [int]$num } }
            'MAX_FRASES'           { if ($num -match '^\d+$') { $MAX_FRASES = [int]$num } }
        }
    }
}

$Url = Preparar-Url $Url
if ($Url -eq "") {
    Write-Host "Pulsa Enter para usar la URL que aparece entre corchetes (la de config\config.txt) o escribe otra."
    Write-Host "Vale cualquier dirección: con o sin http://, con espacios o tildes, localhost:3000, una IP..."
    while ($Url -eq "") {
        $escrita = Read-Host "URL de la web [$URL_DEF]"
        if ($null -eq $escrita -or $escrita.Trim() -eq "") {
            if ($URL_DEF.Trim() -eq "") {
                if ($null -eq $escrita) { break }
                Write-Host "   No hay ninguna URL en config\config.txt: escribe una."; continue
            }
            $escrita = $URL_DEF
        }
        $Url = Preparar-Url $escrita
        if ($Url -eq "") { Write-Host "   No se entiende '$escrita' como dirección web. Prueba otra vez." }
    }
    if ($Url -eq "") { Write-Host "No se ha indicado ninguna URL. Saliendo."; exit 1 }
}
if ($MaxPaginas -le 0) { $MaxPaginas = $MAX_DEF }
if ($MaxPaginas -le 0) { $MaxPaginas = 1 }

Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host "  CÓMO INTRODUCIR LAS PALABRAS"
Write-Host "   - Escribe una palabra y pulsa Enter, o varias separadas"
Write-Host "     por comas en la misma línea:   colegio, pinceles, lápiz"
Write-Host "   - Da igual mayúsculas o tildes: Tequila = TEQUILA = tequila"
Write-Host "   - Cada palabra se busca en español e inglés, en singular"
Write-Host "     y en plural (la traducción es automática)."
Write-Host "   - Cuando termines, pulsa Enter con la línea vacía"
Write-Host "     (o escribe fin) y empezará el scraping."
Write-Host "------------------------------------------------------------"
while ($true) {
    $prompt = if ($TERMINOS.Count -eq 0) { "Palabras" } else { "Más palabras (Enter vacío para empezar)" }
    $linea = Read-Host $prompt
    if ($null -eq $linea -or (Normalizar $linea) -eq "fin") { break }
    if ((Normalizar $linea) -eq "") {
        if ($TERMINOS.Count -gt 0) { break }
        Write-Host "   Escribe al menos una palabra."; continue
    }
    foreach ($p in $linea.Split(',')) { Procesar-Palabra $p }
}

if ($TERMINOS.Count -eq 0) { Write-Host "No se ha introducido ninguna palabra. Saliendo."; exit 1 }

Write-Host ""
Write-Host "Analizando $Url (máximo $MaxPaginas páginas)..."
$origen = ([Uri]$Url).GetLeftPart([UriPartial]::Authority)
$cola = New-Object System.Collections.Generic.List[string]
$cola.Add($Url)
$PAGINAS = New-Object System.Collections.ArrayList     # {Url; Palabras; Orig; Tok; Idx; Pos}
$i = 0
while ($i -lt $cola.Count -and $PAGINAS.Count -lt $MaxPaginas) {
    $u = $cola[$i]; $i++
    try { $d = Descargar $u }
    catch { Write-Host "  [ERROR] $u -> $($_.Exception.Message)"; continue }

    $p = Html-APalabras $d.Html
    # Índice: palabra normalizada -> posiciones donde aparece
    $pos = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[int]]'
    for ($j = 0; $j -lt $p.Tok.Count; $j++) {
        $tk = $p.Tok[$j]
        if (-not $pos.ContainsKey($tk)) { $pos[$tk] = New-Object System.Collections.Generic.List[int] }
        $pos[$tk].Add($j)
    }
    [void]$PAGINAS.Add([pscustomobject]@{ Url = $u; Palabras = $p.Tok.Count; Orig = $p.Orig; Tok = $p.Tok; Idx = $p.Idx; Pos = $pos })
    Write-Host "  [OK] $u ($($p.Tok.Count) palabras)"

    if ($cola.Count -lt $MaxPaginas * 5) {
        foreach ($e in (Extraer-Enlaces $d.Html $d.UrlFinal $origen)) { if (-not $cola.Contains($e)) { $cola.Add($e) } }
    }
    if ($i -lt $cola.Count -and $PAGINAS.Count -lt $MaxPaginas) { Start-Sleep -Seconds $PAUSA }
}

if ($PAGINAS.Count -eq 0) {
    Write-Host "No se ha podido descargar ninguna página. Revisa la URL y que la web esté arrancada."
    exit 1
}

# ---------------------------------------------------------------- recuento
Write-Host "Buscando coincidencias y guardando el contexto de cada una..."
for ($n = 0; $n -lt $PAGINAS.Count; $n++) {
    $pg = $PAGINAS[$n]
    foreach ($term in $TERMINOS) {
        foreach ($v in $term.Variantes) {
            $partes = $v.Clave.Split(' ')
            $c = 0
            if ($pg.Pos.ContainsKey($partes[0])) {
                foreach ($j in $pg.Pos[$partes[0]]) {
                    $ok = $true
                    for ($k = 1; $k -lt $partes.Count; $k++) {
                        if ($j + $k -ge $pg.Tok.Count -or $pg.Tok[$j + $k] -cne $partes[$k]) { $ok = $false; break }
                    }
                    if (-not $ok) { continue }
                    $c++
                    if ($MAX_FRASES -gt 0 -and $c -gt $MAX_FRASES) { continue }
                    # Contexto: PALABRAS_CONTEXTO palabras originales antes y después
                    $a = $pg.Idx[$j]; $b = $pg.Idx[$j + $partes.Count - 1]
                    [void]$v.Frases.Add([pscustomobject]@{
                        Pagina = $n; Posicion = $j; Url = $pg.Url
                        Antes = Unir-Palabras $pg.Orig ($a - $PALABRAS_CONTEXTO) ($a - 1)
                        Coincidencia = Unir-Palabras $pg.Orig $a $b
                        Despues = Unir-Palabras $pg.Orig ($b + 1) ($b + $PALABRAS_CONTEXTO) })
                }
            }
            $v.PorPagina[$n] = $c
            $v.Total += $c
        }
    }
}
$totalFrases = 0

# ------------------------------------------------------------- escribir XML
$fecha  = Get-Date -Format "yyyy-MM-dd'T'HH:mm:ss"
$salida = Join-Path $RESULTADOS ("scraping_windows_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".xml")
$totalPal = 0; foreach ($pg in $PAGINAS) { $totalPal += $pg.Palabras }

$x = New-Object System.Text.StringBuilder
function L([string]$s) { [void]$x.Append($s).Append("`n") }
L '<?xml version="1.0" encoding="UTF-8"?>'
L '<informe_scraping version="1.0">'
L '  <metadatos>'
L "    <fecha>$fecha</fecha>"
L '    <sistema>Windows</sistema>'
L '    <script>scraper_windows.ps1</script>'
L "    <url_inicial>$(Xml-Esc $Url)</url_inicial>"
L "    <paginas_analizadas>$($PAGINAS.Count)</paginas_analizadas>"
L "    <palabras_totales>$totalPal</palabras_totales>"
L '  </metadatos>'
L '  <paginas>'
foreach ($pg in $PAGINAS) { L "    <pagina url=`"$(Xml-Esc $pg.Url)`" palabras=`"$($pg.Palabras)`"/>" }
L '  </paginas>'
L "  <busqueda terminos=`"$($TERMINOS.Count)`">"
foreach ($term in $TERMINOS) {
    $tot = 0; foreach ($v in $term.Variantes) { $tot += $v.Total }
    $enc = if ($tot -gt 0) { "si" } else { "no" }
    L "    <palabra termino=`"$(Xml-Esc $term.Termino)`" total=`"$tot`" encontrada=`"$enc`">"
    foreach ($v in $term.Variantes) {
        L "      <variante texto=`"$(Xml-Esc $v.Texto)`" idioma=`"$($v.Idioma)`" numero=`"$($v.Numero)`" apariciones=`"$($v.Total)`"/>"
    }
    for ($n = 0; $n -lt $PAGINAS.Count; $n++) {
        $c = 0; foreach ($v in $term.Variantes) { $c += $v.PorPagina[$n] }
        if ($c -gt 0) { L "      <en_pagina url=`"$(Xml-Esc $PAGINAS[$n].Url)`" apariciones=`"$c`"/>" }
    }
    # Frases de contexto de este término (como mucho MAX_FRASES por informe)
    $lista = @($term.Variantes | ForEach-Object { $vv = $_; $vv.Frases | ForEach-Object { $_ | Add-Member -NotePropertyName Variante -NotePropertyValue $vv.Texto -PassThru -Force } } |
               Sort-Object Pagina, Posicion)
    if ($MAX_FRASES -gt 0) { $lista = @($lista | Select-Object -First $MAX_FRASES) }
    foreach ($f in $lista) {
        L "      <frase variante=`"$(Xml-Esc $f.Variante)`" url=`"$(Xml-Esc $f.Url)`" antes=`"$(Xml-Esc $f.Antes)`" coincidencia=`"$(Xml-Esc $f.Coincidencia)`" despues=`"$(Xml-Esc $f.Despues)`"/>"
    }
    $totalFrases += $lista.Count
    L '    </palabra>'
}
L '  </busqueda>'
L '</informe_scraping>'
[IO.File]::WriteAllText($salida, $x.ToString(), $UTF8)

# ---------------------------------------------------------------- resumen
Write-Host ""
Write-Host "------------------------- RESULTADOS -------------------------"
foreach ($term in $TERMINOS) {
    $tot = 0; foreach ($v in $term.Variantes) { $tot += $v.Total }
    $det = ($term.Variantes | ForEach-Object { "$($_.Texto)=$($_.Total)" }) -join ", "
    Write-Host ("  {0,-20} {1,5}   ({2})" -f $term.Termino, $tot, $det)
}
Write-Host "--------------------------------------------------------------"
Write-Host "Páginas analizadas: $($PAGINAS.Count)   Palabras leídas: $totalPal   Frases de contexto guardadas: $totalFrases"
Write-Host "Informe guardado en: $salida"
