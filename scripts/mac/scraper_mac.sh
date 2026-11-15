#!/usr/bin/env bash
# =============================================================================
#  scraper_mac.sh  -  Scraping de palabras clave (versión macOS / Bash)
# -----------------------------------------------------------------------------
#  1. Pide palabras clave por consola hasta que se escriba "fin".
#  2. Cada palabra se amplía a español + inglés y singular + plural
#     (colegio -> colegio, colegios, school, schools) usando diccionario.csv
#     y reglas gramaticales.
#  3. Descarga la web (y las páginas enlazadas del mismo dominio, hasta
#     MAX_PAGINAS) y cuenta las apariciones de cada variante.
#  4. Guarda el resultado en resultados/scraping_mac_FECHA.xml
#
#  Uso:   doble clic en "Mac - Ejecutar scraper.command", o ./scripts/mac/scraper_mac.sh [URL] [MAX_PAGINAS]   (desde la raíz del proyecto)
#  Requisitos: bash, curl, sed, awk, grep, tr (vienen de serie en macOS, vale el bash 3.2 del sistema)
# =============================================================================

set -u
export LC_ALL=C          # procesado byte a byte, igual en cualquier distro

# Raíz del proyecto: este script está en scripts/linux (o scripts/mac)
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
DICCIONARIO="$RAIZ/config/diccionario.csv"
CONFIG="$RAIZ/config/config.txt"
RESULTADOS="$RAIZ/resultados"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ScraperClase/1.0"
PAUSA=1                  # segundos entre peticiones, para no saturar la web

mkdir -p "$RESULTADOS"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ----------------------------------------------------------------- utilidades
# Quita tildes y diéresis; la ñ se representa internamente como "N" (no
# puede confundirse con nada porque antes se pasa todo a minúsculas).
NORM_SED='s/á/a/g;s/à/a/g;s/â/a/g;s/ä/a/g;s/Á/a/g;s/À/a/g;s/Â/a/g;s/Ä/a/g;'
NORM_SED+='s/é/e/g;s/è/e/g;s/ê/e/g;s/ë/e/g;s/É/e/g;s/È/e/g;s/Ê/e/g;s/Ë/e/g;'
NORM_SED+='s/í/i/g;s/ì/i/g;s/î/i/g;s/ï/i/g;s/Í/i/g;s/Ì/i/g;s/Î/i/g;s/Ï/i/g;'
NORM_SED+='s/ó/o/g;s/ò/o/g;s/ô/o/g;s/ö/o/g;s/Ó/o/g;s/Ò/o/g;s/Ô/o/g;s/Ö/o/g;'
NORM_SED+='s/ú/u/g;s/ù/u/g;s/û/u/g;s/ü/u/g;s/Ú/u/g;s/Ù/u/g;s/Û/u/g;s/Ü/u/g;'
NORM_SED+='s/ñ/N/g;s/Ñ/N/g;s/ç/c/g;s/Ç/c/g'

# Texto libre -> clave normalizada ("Lápices  de Colores" -> "lapices de colores")
normalizar() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | sed "$NORM_SED" \
        | sed 's/[^a-z0-9N]/ /g; s/  */ /g; s/^ //; s/ $//'
}
# Minúsculas conservando tildes ("CANCIÓN " -> "canción")
minusculas() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed 's/Á/á/g;s/É/é/g;s/Í/í/g;s/Ó/ó/g;s/Ú/ú/g;s/Ü/ü/g;s/Ñ/ñ/g;s/^ *//;s/ *$//;s/  */ /g'
}
# Clave normalizada -> texto para mostrar (devuelve la ñ)
mostrar() { printf '%s' "$1" | sed 's/N/ñ/g'; }

xml_esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }

# ------------------------------------------------------ reglas singular/plural
es_plural() {
    case "$1" in
        *[aeiou]) echo "${1}s" ;;
        *z)       echo "${1%z}ces" ;;
        *)        echo "${1}es" ;;
    esac
}
es_singular() {
    case "$1" in
        *ces)        echo "${1%ces}z" ;;
        *[lrndjy]es) echo "${1%es}" ;;
        *s)          echo "${1%s}" ;;
        *)           echo "$1" ;;
    esac
}
en_plural() {
    case "$1" in
        *[!aeiou]y)              echo "${1%y}ies" ;;
        *s|*x|*z|*ch|*sh)        echo "${1}es" ;;
        *)                       echo "${1}s" ;;
    esac
}
en_singular() {
    case "$1" in
        *ies)                           echo "${1%ies}y" ;;
        *sses|*ches|*shes|*xes|*zes)    echo "${1%es}" ;;
        *s)                             echo "${1%s}" ;;
        *)                              echo "$1" ;;
    esac
}
# ¿Parece plural? (termina en s, pero no en -ss, -us, -is: class, bus, país)
parece_plural() {
    case "$1" in
        *ss|*us|*is) return 1 ;;
        *s) [ ${#1} -gt 3 ] ;;
        *) return 1 ;;
    esac
}
# Devuelve "singular;plural" para una clave en el idioma indicado (es|en)
par_sing_plur() {
    local w="$1" idioma="$2" s p
    if parece_plural "$w"; then
        p="$w"; s="$("${idioma}_singular" "$w")"
    else
        s="$w"; p="$("${idioma}_plural" "$w")"
    fi
    echo "$s;$p"
}

# ---------------------------------------------------------------- diccionario
[ -f "$DICCIONARIO" ] || printf '# es_singular;es_plural;en_singular;en_plural\n' > "$DICCIONARIO"

# Busca la clave en cualquier columna; imprime la fila original o nada
buscar_en_diccionario() {
    local clave="$1" n
    # Se normaliza el diccionario entero de una vez (mismas líneas que el original)
    tr -d '\r' < "$DICCIONARIO" | tr 'A-Z' 'a-z' | sed "$NORM_SED" \
        | sed 's/[^a-z0-9N;#]/ /g; s/  */ /g; s/ *; */;/g; s/^ //; s/ $//' > "$TMP/dic_norm"
    n="$(awk -F';' -v k="$clave" '
        /^#/ { next }
        { for (i = 1; i <= 4 && i <= NF; i++) if ($i == k) { print NR; exit } }' "$TMP/dic_norm")"
    [ -n "$n" ] && tr -d '\r' < "$DICCIONARIO" | sed -n "${n}p"
}

guardar_en_diccionario() {
    # Asegura salto de línea final antes de añadir
    if [ -s "$DICCIONARIO" ] && [ "$(tail -c1 "$DICCIONARIO" | od -An -c | tr -d ' ')" != '\n' ]; then
        printf '\n' >> "$DICCIONARIO"
    fi
    printf '%s\n' "$1" >> "$DICCIONARIO"
}

# --------------------------------------------- estructuras de términos/variantes
T_TERM=()                                   # término tal y como se muestra
V_TERM=(); V_TEXTO=(); V_CLAVE=(); V_IDIOMA=(); V_NUMERO=()

anadir_variante() {   # $1=índice término  $2=texto  $3=idioma  $4=número
    local t="$1" texto="$2" idioma="$3" numero="$4" clave i
    clave="$(normalizar "$texto")"
    [ -z "$clave" ] && return
    for i in "${!V_CLAVE[@]}"; do
        if [ "${V_TERM[$i]}" = "$t" ] && [ "${V_CLAVE[$i]}" = "$clave" ]; then
            [ "${V_IDIOMA[$i]}" != "$idioma" ] && V_IDIOMA[$i]="ambos"
            [ "${V_NUMERO[$i]}" != "$numero" ] && V_NUMERO[$i]="ambos"
            return
        fi
    done
    V_TERM+=("$t"); V_TEXTO+=("$texto"); V_CLAVE+=("$clave")
    V_IDIOMA+=("$idioma"); V_NUMERO+=("$numero")
}

# ------------------------------------------------- traducción automática
# Orden: 1) Wiktionary (diccionario libre, muy fiable con palabras sueltas)
#        2) MyMemory (traductor gratuito, de reserva)
#        3) preguntar al usuario
# Ninguno necesita registro ni clave. Solo se envía la palabra a traducir.
USER_AGENT_API="ScraperClase/1.0 (proyecto educativo de clase; macOS)"

urlenc_ruta() { printf '%s' "$1" | sed 's/ /_/g' | od -An -tx1 -v | tr -d ' \n' | sed 's/../%&/g'; }

limpiar_glosa() {   # "a <b>school</b> (institution), college" -> "school"
    sed 's#\\"#"#g; s#\\/#/#g; s/<[^>]*>//g; s/&[a-z]*;/ /g' | sed "$UNI_SED" \
        | sed -E 's/\([^)]*\)//g; s/[,;:].*//; s/^ +//; s/ +$//; s/  +/ /g' | tr 'A-Z' 'a-z' \
        | sed -E 's/^(a|an|the|to) //'
}

# $1 = palabra (minúsculas, con tildes). Imprime "es:<lema>|<inglés>" si es
# una palabra española, "en" si es inglesa, o falla si no la encuentra.
traducir_wikt() {
    local w="$1" prof="${2:-0}" r def lema=""
    r="$(curl -sS --max-time 8 -A "$USER_AGENT_API" \
          "https://en.wiktionary.org/api/rest_v1/page/definition/$(urlenc_ruta "$w")" 2>/dev/null | tr -d '\n')" || return 1
    case "$r" in
        *'"es":['*)
            def="$(printf '%s' "$r" | awk '{ i = index($0, "\"es\":["); if (i) print substr($0, i) }' \
                  | grep -oE '"definition":"([^"\\]|\\.)*"' | head -1 \
                  | sed 's/^"definition":"//; s/"$//' | limpiar_glosa)"
            # "plural of clarinete" -> se busca "clarinete"
            lema="$(printf '%s' "$def" | sed -nE 's/^(.*(plural|feminine|masculine|singular|form)) of (.+)$/\3/p')"
            if [ -n "$lema" ] && [ "$prof" -eq 0 ]; then traducir_wikt "$(minusculas "$lema")" 1; return; fi
            [ -n "$def" ] || return 1
            printf 'es:%s|%s' "$w" "$def" ;;
        *'"en":['*) printf 'en' ;;
        *) return 1 ;;
    esac
}

# MyMemory: devuelve la traducción normalizada, o falla si no hay internet / cuota.
UNI_SED='s/\\u00[eE]1/a/g;s/\\u00[eE]9/e/g;s/\\u00[eE][dD]/i/g;s/\\u00[fF]3/o/g;s/\\u00[fF][aA]/u/g;'
UNI_SED+='s/\\u00[fF][cC]/u/g;s/\\u00[fF]1/ñ/g;s/\\u00[dD]1/ñ/g;s/\\u00[cC]1/a/g;s/\\u00[cC]9/e/g;'
UNI_SED+='s/\\u00[cC][dD]/i/g;s/\\u00[dD]3/o/g;s/\\u00[dD][aA]/u/g;s/\\u0027/ /g;s/\\u[0-9a-fA-F]\{4\}/ /g'
traducir() {   # $1=texto  $2="es|en" o "en|es"
    local r
    r="$(curl -sS --max-time 8 -G -A "$USER_AGENT" \
          --data-urlencode "q=$1" --data-urlencode "langpair=$2" \
          "https://api.mymemory.translated.net/get" 2>/dev/null)" || return 1
    case "$r" in *'"responseStatus":200'*|*'"responseStatus":"200"'*) ;; *) return 1 ;; esac
    r="$(printf '%s' "$r" | sed -n 's/.*"translatedText":"\([^"]*\)".*/\1/p' | sed "$UNI_SED")"
    case "$r" in ''|*MYMEMORY*|*mymemory*) return 1 ;; esac
    r="$(normalizar "$r" | sed -E 's/^(the|a|an|el|la|los|las|un|una|unos|unas) //')"
    [ -n "$r" ] && printf '%s' "$r"
}

procesar_palabra() {
    local entrada="$1" clave fila es en t c1 c2 c3 c4 trad orig
    clave="$(normalizar "$entrada")"
    [ -z "$clave" ] && return

    fila="$(buscar_en_diccionario "$clave")"
    if [ -n "$fila" ]; then
        # El término se identifica por su singular en español (pinceles -> pincel)
        IFS=';' read -r c1 c2 c3 c4 <<EOF
$fila
EOF
        for t in "${T_TERM[@]+"${T_TERM[@]}"}"; do
            if [ "$(normalizar "$t")" = "$(normalizar "$c1")" ]; then
                echo "   ('$c1' ya estaba en la lista)"; return
            fi
        done
    else
        for t in "${T_TERM[@]+"${T_TERM[@]}"}"; do
            if [ "$(normalizar "$t")" = "$(normalizar "${clave%s}")" ] || [ "$(normalizar "$t")" = "$clave" ]; then
                echo "   ('$t' ya estaba en la lista)"; return
            fi
        done
    fi

    if [ -z "$fila" ]; then
        # disp_es = palabra española tal y como se mostrará; lado = lo que se ha traducido
        local disp_es="" pal_es="" pal_en="" lado="en" res ida vuelta corr
        orig="$(minusculas "$entrada")"
        if [ "$TRADUCTOR_ONLINE" = "si" ]; then
            echo "   Buscando la traducción de '$orig'..."
            if res="$(traducir_wikt "$orig")"; then
                case "$res" in
                    es:*) res="${res#es:}"; disp_es="${res%%|*}"; pal_en="$(normalizar "${res#*|}")" ;;
                    en)   pal_en="$clave"; lado="es"
                          disp_es="$(mostrar "$(traducir "$clave" "en|es")")" ;;
                esac
                # Palabra igual en los dos idiomas (test, hotel): ¿hay otra forma en español?
                if [ "$lado" = "en" ] && [ "$pal_en" = "$(normalizar "$disp_es")" ] \
                   && vuelta="$(traducir "$clave" "en|es")" && [ "$vuelta" != "$clave" ]; then
                    disp_es="$(mostrar "$vuelta")"; lado="es"
                fi
            elif ida="$(traducir "$clave" "es|en")"; then
                if [ "$ida" != "$clave" ]; then
                    disp_es="$orig"; pal_en="$ida"                            # era español
                elif vuelta="$(traducir "$clave" "en|es")" && [ "$vuelta" != "$clave" ]; then
                    disp_es="$(mostrar "$vuelta")"; pal_en="$clave"; lado="es"  # era inglés
                else
                    disp_es="$orig"; pal_en="$clave"                          # igual en ambos
                fi
            fi
        fi

        if [ -n "$disp_es" ] && [ -n "$pal_en" ]; then
            echo "   Traducción: $disp_es (español) = $(mostrar "$pal_en") (inglés)"
            if [ "$CONFIRMAR_TRADUCCION" = "si" ]; then
                if [ "$lado" = "es" ]; then printf '   Pulsa Enter si es correcta, o escribe la palabra correcta en español: '
                else printf '   Pulsa Enter si es correcta, o escribe la traducción correcta en inglés: '; fi
                IFS= read -r corr || corr=""
                if [ -n "$(normalizar "$corr")" ]; then
                    if [ "$lado" = "es" ]; then disp_es="$(minusculas "$corr")"; else pal_en="$(normalizar "$corr")"; fi
                fi
            fi
        else
            # Sin internet, traductor desactivado o palabra no encontrada: se pregunta
            [ "$TRADUCTOR_ONLINE" = "si" ] && echo "   No se ha encontrado traducción de '$orig' (¿sin internet o palabra rara?)."
            printf '   Escribe su traducción al inglés (Enter para buscarla tal cual): '
            IFS= read -r corr || corr=""
            disp_es="$orig"; pal_en="$(normalizar "$corr")"
        fi

        pal_es="$(normalizar "$disp_es")"
        es="$(par_sing_plur "$pal_es" es)"
        # Se respeta cómo se escribe en singular (canción, no cancion)
        if ! parece_plural "$pal_es"; then es="$(mostrar "$disp_es");${es#*;}"; fi
        for t in "${T_TERM[@]+"${T_TERM[@]}"}"; do
            if [ "$(normalizar "$t")" = "$(normalizar "${es%%;*}")" ]; then
                echo "   ('$t' ya estaba en la lista)"; return
            fi
        done
        if [ -n "$pal_en" ]; then
            en="$(par_sing_plur "$pal_en" en)"
            fila="$(mostrar "$es;$en")"
            # Se guarda como caché para no volver a traducirla (no si es igual en ambos idiomas)
            if [ "$pal_es" != "$pal_en" ]; then guardar_en_diccionario "$fila"; fi
        else
            fila="$(mostrar "$es");;"
        fi
    fi
    IFS=';' read -r c1 c2 c3 c4 <<EOF
$fila
EOF
    t=${#T_TERM[@]}
    T_TERM+=("$c1")
    anadir_variante "$t" "$c1" es singular
    anadir_variante "$t" "$c2" es plural
    anadir_variante "$t" "${c3:-}" en singular
    anadir_variante "$t" "${c4:-}" en plural

    local i lista=""
    for i in "${!V_TERM[@]}"; do
        [ "${V_TERM[$i]}" = "$t" ] && lista="$lista${lista:+, }${V_TEXTO[$i]}"
    done
    echo "   -> se buscará: $lista"
}

# ------------------------------------------------------------------ scraping
# Entidades HTML -> caracteres, conservando tildes y mayúsculas (para las frases)
DEC_SED='s/&nbsp;/ /g;s/&quot;/"/g;s/&lt;/</g;s/&gt;/>/g;s/&#39;/'"'"'/g;s/&apos;/'"'"'/g;'
DEC_SED+='s/&aacute;/á/g;s/&eacute;/é/g;s/&iacute;/í/g;s/&oacute;/ó/g;s/&uacute;/ú/g;s/&uuml;/ü/g;s/&ntilde;/ñ/g;'
DEC_SED+='s/&Aacute;/Á/g;s/&Eacute;/É/g;s/&Iacute;/Í/g;s/&Oacute;/Ó/g;s/&Uacute;/Ú/g;s/&Uuml;/Ü/g;s/&Ntilde;/Ñ/g;'
DEC_SED+='s/&ccedil;/ç/g;s/&iquest;/¿/g;s/&iexcl;/¡/g;s/&laquo;/«/g;s/&raquo;/»/g;s/&ordm;/º/g;s/&ordf;/ª/g;'
DEC_SED+='s/&#225;/á/g;s/&#233;/é/g;s/&#237;/í/g;s/&#243;/ó/g;s/&#250;/ú/g;s/&#252;/ü/g;s/&#241;/ñ/g;'
DEC_SED+='s/&#193;/Á/g;s/&#201;/É/g;s/&#205;/Í/g;s/&#211;/Ó/g;s/&#218;/Ú/g;s/&#220;/Ü/g;s/&#209;/Ñ/g;'
DEC_SED+='s/&#160;/ /g;s/&#171;/«/g;s/&#187;/»/g;s/&#191;/¿/g;s/&#161;/¡/g;s/&#8216;/‘/g;s/&#8217;/’/g;'
DEC_SED+='s/&#8220;/“/g;s/&#8221;/”/g;s/&#8211;/–/g;s/&#8212;/—/g;s/&[a-zA-Z][a-zA-Z0-9]*;/ /g;s/&#[0-9a-fA-FxX]*;/ /g'
AMP="$(printf '\001')"     # marcador temporal para &amp; (el texto no puede contenerlo)
NBSP="$(printf '\302\240')"

# Convierte un HTML ($1) en dos ficheros con el mismo prefijo ($2):
#   $2.orig -> palabras tal cual aparecen (mayúsculas, tildes, puntuación), una por línea
#   $2.tok  -> palabra normalizada <TAB> nº de línea de su palabra original
# Así se cuenta con las normalizadas y se muestran las frases con las originales.
html_a_palabras() {
    tr '\r\n\t' '   ' < "$1" | tr -d '\000-\010\013\014\016-\037' | awk '
        function quitar(s, a, b,    out, i, j) {
            out = ""
            while ((i = index(tolower(s), a)) > 0) {
                out = out substr(s, 1, i - 1) " "
                s = substr(s, i + length(a))
                j = index(tolower(s), b)
                if (j == 0) { s = ""; break }
                s = substr(s, j + length(b))
            }
            return out s
        }
        { s = quitar($0, "<!--", "-->")
          s = quitar(s, "<script", "</script>")
          s = quitar(s, "<style", "</style>")
          s = quitar(s, "<noscript", "</noscript>")
          s = quitar(s, "<svg", "</svg>")
          print s }' \
    | sed 's/<[^>]*>/ /g' | sed "s/$NBSP/ /g" \
    | sed -e "s/&amp;/$AMP/g" -e "$DEC_SED" -e "s/$AMP/\\&/g" \
    | tr -s ' ' '\n' | sed '/^$/d' > "$2.orig"
    tr 'A-Z' 'a-z' < "$2.orig" | sed "$NORM_SED" | sed 's/[^a-z0-9N]/ /g' \
        | awk '{ n = split($0, t, " "); for (i = 1; i <= n; i++) print t[i] "\t" NR }' > "$2.tok"
}

# Cuenta las variantes en una página y recoge el contexto de cada coincidencia.
#   $1 = fichero de variantes (id <TAB> clave <TAB> texto)   $2 = prefijo de la página
#   $3 = URL de la página
# Salida:  C <TAB> id <TAB> apariciones
#          F <TAB> id <TAB> <frase .../>   (como mucho MAX_FRASES por variante)
contar_y_contexto() {
    awk -F'\t' -v ctx="$PALABRAS_CONTEXTO" -v maxf="$MAX_FRASES" -v url="$3" '
        function xesc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
        function unir(desde, hasta,    w, r) { r = ""; for (w = desde; w <= hasta; w++) if (w >= 1 && w <= nw) r = r (r == "" ? "" : " ") orig[w]; return r }
        FILENAME == ARGV[1] { nv++; vid[nv] = $1; vtexto[nv] = $3; np[nv] = split($2, p, " "); for (k = 1; k <= np[nv]; k++) vp[nv, k] = p[k]; next }
        FILENAME == ARGV[2] { orig[FNR] = $0; nw = FNR; next }
        { nt++; tok[nt] = $1; idx[nt] = $2 }
        END {
            for (j = 1; j <= nt; j++) for (v = 1; v <= nv; v++) {
                if (tok[j] != vp[v, 1]) continue
                ok = 1; for (k = 2; k <= np[v]; k++) if (tok[j + k - 1] != vp[v, k]) { ok = 0; break }
                if (!ok) continue
                cnt[v]++
                if (maxf > 0 && cnt[v] > maxf) continue
                a = idx[j]; b = idx[j + np[v] - 1]
                printf "F\t%s\t      <frase variante=\"%s\" url=\"%s\" antes=\"%s\" coincidencia=\"%s\" despues=\"%s\"/>\n", \
                    vid[v], xesc(vtexto[v]), xesc(url), xesc(unir(a - ctx, a - 1)), xesc(unir(a, b)), xesc(unir(b + 1, b + ctx))
            }
            for (v = 1; v <= nv; v++) printf "C\t%s\t%d\n", vid[v], cnt[v]
        }' "$1" "$2.orig" "$2.tok"
}

origen_de() {   # http://host:puerto/a/b -> http://host:puerto
    printf '%s' "$1" | sed -E 's#^([a-zA-Z]+://[^/?]*).*#\1#'
}

resolver_url() {   # $1=URL base  $2=href
    local base="$1" href="$2" dir
    case "$href" in
        http://*|https://*) ;;
        //*)  href="$(printf '%s' "$base" | sed -E 's#^([a-zA-Z]+:).*#\1#')$href" ;;
        /*)   href="$(origen_de "$base")$href" ;;
        \?*)  href="${base%%\?*}$href" ;;
        *)    dir="${base%%\?*}"; dir="${dir%/*}/"
              case "$dir" in *://) dir="$base/" ;; esac
              href="$dir$href" ;;
    esac
    # limpia /./ y /carpeta/../
    printf '%s' "$href" | sed -E ':a
s#/\./#/#
s#/[^/.][^/]*/\.\./#/#
ta'
}

extraer_enlaces() {   # $1=fichero html  $2=URL base  $3=origen permitido
    # Solo enlaces <a href> (no hojas de estilo, iconos, etc.)
    tr '\r\n' '  ' < "$1" | grep -oiE "<a[[:space:]][^>]*href[[:space:]]*=[[:space:]]*[\"'][^\"'#]+" 2>/dev/null \
        | sed -E "s/.*[hH][rR][eE][fF][[:space:]]*=[[:space:]]*[\"']//" | sed 's/&amp;/\&/g' \
        | while IFS= read -r h; do
            case "$h" in mailto:*|javascript:*|tel:*|data:*) continue ;; esac
            u="$(resolver_url "$2" "$h")"
            case "$u" in "$3"*) ;; *) continue ;; esac
            case "$(printf '%s' "${u%%\?*}" | tr 'A-Z' 'a-z')" in
                *.pdf|*.jpg|*.jpeg|*.png|*.gif|*.svg|*.webp|*.ico|*.css|*.js|*.zip|*.mp3|*.mp4|*.doc|*.docx|*.xls|*.xlsx) continue ;;
            esac
            # Nunca seguir enlaces de cerrar sesión (te desconectarían) ni de edición/historial
            case "$(printf '%s' "$u" | tr 'A-Z' 'a-z')" in
                *logout*|*logoff*|*signout*|*sign-out*|*cerrar-sesion*|*cerrarsesion*|*desconectar*|*salir*) continue ;;
                *action=edit*|*action=history*|*oldid=*|*diff=*|*printable=*|*veaction=*) continue ;;
            esac
            echo "$u"
        done
}

# =============================================================== PROGRAMA
echo "============================================================"
echo "  SCRAPER DE PALABRAS CLAVE  (macOS)"
echo "============================================================"

URL_DEF="$(tr -d '\r' < "$CONFIG" 2>/dev/null | sed -n 's/^URL=//p' | head -1)"
MAX_DEF="$(tr -d '\r' < "$CONFIG" 2>/dev/null | sed -n 's/^MAX_PAGINAS=//p' | head -1)"
TRADUCTOR_ONLINE="$(tr -d '\r' < "$CONFIG" 2>/dev/null | sed -n 's/^TRADUCTOR_ONLINE=//p' | head -1 | tr 'A-Z' 'a-z' | tr -d ' ')"
[ "$TRADUCTOR_ONLINE" = "no" ] || TRADUCTOR_ONLINE="si"
CONFIRMAR_TRADUCCION="$(tr -d '\r' < "$CONFIG" 2>/dev/null | sed -n 's/^CONFIRMAR_TRADUCCION=//p' | head -1 | tr 'A-Z' 'a-z' | tr -d ' ')"
[ "$CONFIRMAR_TRADUCCION" = "no" ] || CONFIRMAR_TRADUCCION="si"
PALABRAS_CONTEXTO="$(tr -d '\r' < "$CONFIG" 2>/dev/null | sed -n 's/^PALABRAS_CONTEXTO=//p' | head -1 | tr -d ' ')"
case "$PALABRAS_CONTEXTO" in ''|*[!0-9]*) PALABRAS_CONTEXTO=5 ;; esac
MAX_FRASES="$(tr -d '\r' < "$CONFIG" 2>/dev/null | sed -n 's/^MAX_FRASES=//p' | head -1 | tr -d ' ')"
case "$MAX_FRASES" in ''|*[!0-9]*) MAX_FRASES=100 ;; esac

URL="${1:-}"
if [ -z "$URL" ]; then
    echo "Pulsa Enter para usar la URL que aparece entre corchetes (la de config/config.txt) o escribe otra."
    printf 'URL de la web [%s]: ' "$URL_DEF"
    IFS= read -r URL || URL=""
    URL="${URL:-$URL_DEF}"
fi
URL="$(printf '%s' "$URL" | sed 's/^ *//; s/ *$//')"
case "$URL" in
    http://*|https://*|file://*) ;;
    *) URL="http://$URL" ;;
esac
MAX_PAGINAS="${2:-${MAX_DEF:-10}}"
case "$MAX_PAGINAS" in ''|*[!0-9]*|0) MAX_PAGINAS=1 ;; esac

echo
echo "------------------------------------------------------------"
echo "  CÓMO INTRODUCIR LAS PALABRAS"
echo "   - Escribe una palabra y pulsa Enter, o varias separadas"
echo "     por comas en la misma línea:   colegio, pinceles, lápiz"
echo "   - Da igual mayúsculas o tildes: Tequila = TEQUILA = tequila"
echo "   - Cada palabra se busca en español e inglés, en singular"
echo "     y en plural (la traducción es automática)."
echo "   - Cuando termines, pulsa Enter con la línea vacía"
echo "     (o escribe fin) y empezará el scraping."
echo "------------------------------------------------------------"
while true; do
    if [ ${#T_TERM[@]} -eq 0 ]; then printf 'Palabras > '; else printf 'Más palabras (Enter vacío para empezar) > '; fi
    IFS= read -r linea || break
    if [ "$(normalizar "$linea")" = "fin" ]; then break; fi
    if [ -z "$(normalizar "$linea")" ]; then
        [ ${#T_TERM[@]} -gt 0 ] && break
        echo "   Escribe al menos una palabra."; continue
    fi
    IFS=',' read -r -a trozos <<EOF
$linea
EOF
    for p in "${trozos[@]+"${trozos[@]}"}"; do procesar_palabra "$p"; done
done

if [ ${#T_TERM[@]} -eq 0 ]; then
    echo "No se ha introducido ninguna palabra. Saliendo."; exit 1
fi

echo
echo "Analizando $URL (máximo $MAX_PAGINAS páginas)..."
ORIGEN="$(origen_de "$URL")"
COLA=("$URL")
P_URL=(); P_PALABRAS=()
i=0
while [ $i -lt ${#COLA[@]} ] && [ ${#P_URL[@]} -lt "$MAX_PAGINAS" ]; do
    u="${COLA[$i]}"; i=$((i + 1))
    n=${#P_URL[@]}
    f="$TMP/p$n.html"
    info="$(curl -sSL --max-time 20 --max-redirs 5 -A "$USER_AGENT" -o "$f" \
            -w '%{http_code}|%{content_type}|%{url_effective}' "$u" 2>"$TMP/err")"
    if [ $? -ne 0 ]; then
        echo "  [ERROR] $u -> $(head -1 "$TMP/err")"; continue
    fi
    codigo="${info%%|*}"; resto="${info#*|}"; tipo="${resto%%|*}"; final="${resto#*|}"
    case "$u" in file://*) codigo=200 ;; esac
    case "$codigo" in 2??) ;; *) echo "  [HTTP $codigo] $u (omitida)"; continue ;; esac
    case "$tipo" in ''|*html*|*text/plain*) ;; *) echo "  [$tipo] $u (no es HTML, omitida)"; continue ;; esac

    html_a_palabras "$f" "$TMP/p$n"
    palabras=$(wc -l < "$TMP/p$n.tok" | tr -d ' ')
    P_URL+=("$u"); P_PALABRAS+=("$palabras")
    echo "  [OK] $u ($palabras palabras)"

    if [ ${#COLA[@]} -lt $((MAX_PAGINAS * 5)) ]; then
        while IFS= read -r enlace; do
            [ -z "$enlace" ] && continue
            nuevo=1
            for c in "${COLA[@]}"; do [ "$c" = "$enlace" ] && { nuevo=0; break; }; done
            [ $nuevo -eq 1 ] && COLA+=("$enlace")
        done <<EOF
$(extraer_enlaces "$f" "${final:-$u}" "$ORIGEN")
EOF
    fi
    [ $i -lt ${#COLA[@]} ] && [ ${#P_URL[@]} -lt "$MAX_PAGINAS" ] && sleep "$PAUSA"
done

if [ ${#P_URL[@]} -eq 0 ]; then
    echo "No se ha podido descargar ninguna página. Revisa la URL y que la web esté arrancada."
    exit 1
fi

# ---------------------------------------------------------------- recuento
echo "Buscando coincidencias y guardando el contexto de cada una..."
: > "$TMP/variantes"
for v in "${!V_CLAVE[@]}"; do
    printf '%s\t%s\t%s\n' "$v" "${V_CLAVE[$v]}" "${V_TEXTO[$v]}" >> "$TMP/variantes"
done
: > "$TMP/por_pagina"
for n in "${!P_URL[@]}"; do
    contar_y_contexto "$TMP/variantes" "$TMP/p$n" "${P_URL[$n]}" > "$TMP/p$n.res"
    awk -F'\t' -v n="$n" '$1 == "C" { print $2, n, $3 }' "$TMP/p$n.res" >> "$TMP/por_pagina"
done
V_TOTAL=()
for v in "${!V_CLAVE[@]}"; do
    V_TOTAL+=("$(awk -v v="$v" '$1 == v { s += $3 } END { print s + 0 }' "$TMP/por_pagina")")
done
TOTAL_FRASES=0

# ------------------------------------------------------------- escribir XML
FECHA="$(date +%Y-%m-%dT%H:%M:%S)"
SALIDA="$RESULTADOS/scraping_mac_$(date +%Y%m%d_%H%M%S).xml"
TOTAL_PAL=0; for p in "${P_PALABRAS[@]}"; do TOTAL_PAL=$((TOTAL_PAL + p)); done

{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<informe_scraping version="1.0">'
    echo '  <metadatos>'
    echo "    <fecha>$FECHA</fecha>"
    echo '    <sistema>macOS</sistema>'
    echo '    <script>scraper_mac.sh</script>'
    echo "    <url_inicial>$(xml_esc "$URL")</url_inicial>"
    echo "    <paginas_analizadas>${#P_URL[@]}</paginas_analizadas>"
    echo "    <palabras_totales>$TOTAL_PAL</palabras_totales>"
    echo '  </metadatos>'
    echo '  <paginas>'
    for n in "${!P_URL[@]}"; do
        echo "    <pagina url=\"$(xml_esc "${P_URL[$n]}")\" palabras=\"${P_PALABRAS[$n]}\"/>"
    done
    echo '  </paginas>'
    echo "  <busqueda terminos=\"${#T_TERM[@]}\">"
    for t in "${!T_TERM[@]}"; do
        tot=0
        for v in "${!V_TERM[@]}"; do [ "${V_TERM[$v]}" = "$t" ] && tot=$((tot + V_TOTAL[v])); done
        [ $tot -gt 0 ] && enc=si || enc=no
        echo "    <palabra termino=\"$(xml_esc "${T_TERM[$t]}")\" total=\"$tot\" encontrada=\"$enc\">"
        for v in "${!V_TERM[@]}"; do
            [ "${V_TERM[$v]}" = "$t" ] || continue
            echo "      <variante texto=\"$(xml_esc "${V_TEXTO[$v]}")\" idioma=\"${V_IDIOMA[$v]}\" numero=\"${V_NUMERO[$v]}\" apariciones=\"${V_TOTAL[$v]}\"/>"
        done
        for n in "${!P_URL[@]}"; do
            c=0
            for v in "${!V_TERM[@]}"; do
                [ "${V_TERM[$v]}" = "$t" ] || continue
                x=$(awk -v v="$v" -v n="$n" '$1==v && $2==n {print $3}' "$TMP/por_pagina")
                c=$((c + ${x:-0}))
            done
            [ $c -gt 0 ] && echo "      <en_pagina url=\"$(xml_esc "${P_URL[$n]}")\" apariciones=\"$c\"/>"
        done
        # Frases de contexto de este término (como mucho MAX_FRASES por informe)
        ids=" "; for v in "${!V_TERM[@]}"; do [ "${V_TERM[$v]}" = "$t" ] && ids="$ids$v "; done
        for n in "${!P_URL[@]}"; do cat "$TMP/p$n.res"; done \
            | awk -F'\t' -v ids="$ids" -v maxf="$MAX_FRASES" \
                '$1 == "F" && index(ids, " " $2 " ") { if (maxf > 0 && ++k > maxf) exit; print $3 }' > "$TMP/frases_t"
        cat "$TMP/frases_t"
        TOTAL_FRASES=$((TOTAL_FRASES + $(wc -l < "$TMP/frases_t")))
        echo '    </palabra>'
    done
    echo '  </busqueda>'
    echo '</informe_scraping>'
} > "$SALIDA"

# ---------------------------------------------------------------- resumen
echo
echo "------------------------- RESULTADOS -------------------------"
for t in "${!T_TERM[@]}"; do
    tot=0; det=""
    for v in "${!V_TERM[@]}"; do
        [ "${V_TERM[$v]}" = "$t" ] || continue
        tot=$((tot + V_TOTAL[v])); det="$det${det:+, }${V_TEXTO[$v]}=${V_TOTAL[$v]}"
    done
    printf '  %-20s %5s   (%s)\n' "${T_TERM[$t]}" "$tot" "$det"
done
echo "--------------------------------------------------------------"
echo "Páginas analizadas: ${#P_URL[@]}   Palabras leídas: $TOTAL_PAL   Frases de contexto guardadas: $TOTAL_FRASES"
echo "Informe guardado en: $SALIDA"
