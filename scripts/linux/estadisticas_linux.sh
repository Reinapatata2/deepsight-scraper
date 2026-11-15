#!/usr/bin/env bash
# =============================================================================
#  estadisticas_linux.sh  -  Estadísticas de los informes de scraping (Linux)
# -----------------------------------------------------------------------------
#  1. Lee todos los XML nuevos de resultados/ (de Linux, macOS o Windows).
#  2. Calcula las estadísticas y las muestra por consola.
#  3. Genera estadisticas/estadisticas_FECHA.html (gráficos + registro de
#     frases) con el diseño de DeepSight, usando recursos/plantilla_estadisticas.html
#  4. Guarda también estadisticas/estadisticas_FECHA.xml
#  5. Vacía resultados/ (borra los XML ya procesados) para el siguiente periodo.
#  6. Abre el HTML en el navegador.
#
#  Uso:   ./"Linux - Ver estadisticas.sh"   (--no-abrir: no abre el navegador)
# =============================================================================

set -u
export LC_ALL=C

# Raíz del proyecto: este script está en scripts/linux (o scripts/mac)
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
RESULTADOS="$RAIZ/resultados"
CARPETA_EST="$RAIZ/estadisticas"
RECURSOS="$RAIZ/recursos"
PLANTILLA="$RECURSOS/plantilla_estadisticas.html"
NOMBRE_SCRIPT="$(basename "$0")"
case "$(uname)" in Darwin) SISTEMA="macOS" ;; *) SISTEMA="Linux" ;; esac
TOP=10
ABRIR=1; [ "${1:-}" = "--no-abrir" ] && ABRIR=0

paso() { printf '\n[%s/6] %s\n' "$1" "$2"; }

echo "============================================================"
echo "  ESTADÍSTICAS DE SCRAPING  ($SISTEMA)"
echo "============================================================"

# ------------------------------------------------ 1. Buscar informes
paso 1 "Buscando informes nuevos en resultados/ ..."
shopt -s nullglob
FICHEROS=("$RESULTADOS"/*.xml)
if [ ${#FICHEROS[@]} -eq 0 ]; then
    echo "   No hay informes nuevos desde las últimas estadísticas."
    echo "   Ejecuta antes el scraper para generar alguno."
    exit 1
fi
for f in "${FICHEROS[@]}"; do echo "   - $(basename "$f")"; done
echo "   ${#FICHEROS[@]} informe(s) encontrado(s)."
if [ ! -f "$PLANTILLA" ]; then
    echo "   ERROR: falta la plantilla $PLANTILLA"; exit 1
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------ 2. Leer y combinar
paso 2 "Leyendo y combinando los informes ..."
# Genera:  $TMP/datos (líneas tabuladas para consola/XML) y las partes del JSON
awk -v dir="$TMP" '
function attr(l, n) {
    if (match(l, " " n "=\"[^\"]*\""))
        return substr(l, RSTART + length(n) + 3, RLENGTH - length(n) - 4)
    return ""
}
function texto(l,   r) { r = l; sub(/^[^>]*>/, "", r); sub(/<.*$/, "", r); return r }
# Sustitución literal (sin caracteres especiales, igual en cualquier awk)
function rep(s, a, b,   r, i) { r = ""; while ((i = index(s, a)) > 0) { r = r substr(s, 1, i - 1) b; s = substr(s, i + length(a)) } return r s }
function xun(s) { s = rep(s, "&lt;", "<"); s = rep(s, "&gt;", ">"); s = rep(s, "&quot;", "\""); s = rep(s, "&apos;", "\047"); s = rep(s, "&#39;", "\047"); return rep(s, "&amp;", "&") }
# Texto ya escapado en XML -> cadena JSON (segura dentro de <script>)
function js(s) { s = xun(s); s = rep(s, "\\", "\\\\"); s = rep(s, "\"", "\\\""); s = rep(s, "\t", " "); s = rep(s, "\r", ""); s = rep(s, "<", "\\u003c"); return "\"" s "\"" }
function base(p) { sub(/.*\//, "", p); return p }
FNR == 1 { F = FILENAME; nf++; orden[nf] = F }
{ sub(/\r$/, "") }
/<informe_scraping/  { informes++ }
/<fecha>/            { f = texto($0); ifecha[F] = f; if (desde == "" || f < desde) desde = f; if (f > hasta) hasta = f }
/<sistema>/          { isist[F] = texto($0); sist[texto($0)]++ }
/<url_inicial>/      { iurl[F] = texto($0); web[texto($0)]++ }
/<paginas_analizadas>/ { ipag[F] = texto($0) + 0 }
/<palabras_totales>/ { ipal[F] = texto($0) + 0 }
/<palabra / {
    t = attr($0, "termino"); tot = attr($0, "total") + 0
    busq[t]++; total[t] += tot
    if (tot > 0) enc[t]++
    if (!(t in maxi) || tot > maxi[t]) maxi[t] = tot
}
/<variante / {
    ap = attr($0, "apariciones") + 0
    tx = attr($0, "texto"); id = attr($0, "idioma"); nu = attr($0, "numero")
    k = tx "\t" id "\t" nu
    vtot[k] += ap; idioma[id] += ap; numero[nu] += ap
    kt = t SUBSEP tx SUBSEP id SUBSEP nu
    if (!(kt in tv)) { nvt[t]++; tvorden[t, nvt[t]] = kt }
    tv[kt] += ap
}
/<en_pagina / { pag[attr($0, "url")] += attr($0, "apariciones") + 0 }
/<frase / {
    nfr++
    printf "%s{\"termino\":%s,\"variante\":%s,\"url\":%s,\"fecha\":%s,\"antes\":%s,\"coincidencia\":%s,\"despues\":%s}", \
        (nfr > 1 ? "," : ""), js(t), js(attr($0, "variante")), js(attr($0, "url")), js(ifecha[F]), \
        js(attr($0, "antes")), js(attr($0, "coincidencia")), js(attr($0, "despues")) > (dir "/j_frases")
    printf "    <frase termino=\"%s\" variante=\"%s\" fecha=\"%s\" url=\"%s\" antes=\"%s\" coincidencia=\"%s\" despues=\"%s\"/>\n", \
        t, attr($0, "variante"), ifecha[F], attr($0, "url"), attr($0, "antes"), attr($0, "coincidencia"), attr($0, "despues") > (dir "/x_frases")
}
END {
    printf "N\t%d\t%s\t%s\t%d\n", informes, desde, hasta, nfr
    for (s in sist)   printf "S\t%s\t%d\n", s, sist[s]
    for (w in web)    printf "W\t%s\t%d\n", w, web[w]
    for (t in busq)   printf "T\t%s\t%d\t%d\t%d\t%.2f\t%d\n", t, busq[t], enc[t] + 0, total[t], total[t] / busq[t], maxi[t]
    for (i in idioma) printf "I\t%s\t%d\n", i, idioma[i]
    for (u in numero) printf "U\t%s\t%d\n", u, numero[u]
    for (k in vtot)   if (vtot[k] > 0) printf "V\t%s\t%d\n", k, vtot[k]

    # ---- partes del JSON para el HTML
    for (i = 1; i <= nf; i++) {
        F = orden[i]
        printf "%s{\"fichero\":%s,\"fecha\":%s,\"sistema\":%s,\"url\":%s,\"paginas\":%d,\"palabras\":%d}", \
            (i > 1 ? "," : ""), js(base(F)), js(ifecha[F]), js(isist[F]), js(iurl[F]), ipag[F], ipal[F] > (dir "/j_informes")
    }
    n = 0
    for (t in busq) {
        vs = ""
        for (j = 1; j <= nvt[t]; j++) {
            kt = tvorden[t, j]; split(kt, p, SUBSEP)
            vs = vs (j > 1 ? "," : "") "{\"texto\":" js(p[2]) ",\"idioma\":" js(p[3]) ",\"numero\":" js(p[4]) ",\"apariciones\":" tv[kt] "}"
        }
        printf "%s{\"termino\":%s,\"buscado\":%d,\"encontrado\":%d,\"total\":%d,\"maximo\":%d,\"variantes\":[%s]}", \
            (n++ ? "," : ""), js(t), busq[t], enc[t] + 0, total[t], maxi[t], vs > (dir "/j_terminos")
    }
    n = 0
    for (u in pag) printf "%s{\"url\":%s,\"apariciones\":%d}", (n++ ? "," : ""), js(u), pag[u] > (dir "/j_paginas")
}' "${FICHEROS[@]}" > "$TMP/datos"
for p in j_frases x_frases j_informes j_terminos j_paginas; do [ -f "$TMP/$p" ] || : > "$TMP/$p"; done

seccion() { grep "^$1	" "$TMP/datos" | cut -f2-; }
seccion S | sort -t'	' -k2,2nr        > "$TMP/S"
seccion W | sort -t'	' -k2,2nr        > "$TMP/W"
seccion T | sort -t'	' -k4,4nr -k2,2nr -k1,1 > "$TMP/T"
seccion I | sort -t'	' -k2,2nr        > "$TMP/I"
seccion U | sort -t'	' -k2,2nr        > "$TMP/U"
seccion V | sort -t'	' -k4,4nr -k1,1 | head -n "$TOP" > "$TMP/V"
IFS='	' read -r N DESDE HASTA NFRASES <<EOF
$(seccion N)
EOF
echo "   $N informe(s), $(wc -l < "$TMP/T" | tr -d ' ') término(s), $NFRASES frase(s) de contexto."

des() { sed 's/&quot;/"/g; s/&lt;/</g; s/&gt;/>/g; s/&apos;/'"'"'/g; s/&amp;/\&/g'; }

# ------------------------------------------------ 3. Resumen en consola
paso 3 "Resumen de las estadísticas"
{
echo "Periodo             : $DESDE  ->  $HASTA"
printf 'Sistemas            : '; awk -F'\t' '{ printf "%s%s (%d)", (NR > 1 ? ", " : ""), $1, $2 } END { print "" }' "$TMP/S"
echo "Webs analizadas     :"
awk -F'\t' '{ printf "   %3d informe(s)  %s\n", $2, $1 }' "$TMP/W"
echo
echo "TÉRMINOS (ordenados por apariciones totales)"
awk -F'\t' '
    NR == FNR { if ($4 > m) m = $4; next }
    FNR == 1 { printf "  %-18s %9s %10s %8s %8s %6s\n", "termino", "buscado", "encontrado", "total", "media", "max" }
    { n = (m > 0) ? int($4 * 25 / m + 0.5) : 0; barra = ""; for (i = 0; i < n; i++) barra = barra "#"
      printf "  %-18s %9d %10d %8d %8s %6d  %s\n", $1, $2, $3, $4, $5, $6, barra }' "$TMP/T" "$TMP/T"
echo
echo "APARICIONES POR IDIOMA"
awk -F'\t' 'NR == FNR { s += $2; next } { printf "  %-10s %8d  (%5.1f%%)\n", $1, $2, (s ? 100 * $2 / s : 0) }' "$TMP/I" "$TMP/I"
echo
echo "APARICIONES POR NÚMERO"
awk -F'\t' 'NR == FNR { s += $2; next } { printf "  %-10s %8d  (%5.1f%%)\n", $1, $2, (s ? 100 * $2 / s : 0) }' "$TMP/U" "$TMP/U"
echo
echo "TOP $TOP VARIANTES MÁS ENCONTRADAS"
awk -F'\t' '{ printf "  %2d. %-20s %-6s %-9s %6d\n", NR, $1, $2, $3, $4 }' "$TMP/V"
} | des | sed 's/^/   /'

# ------------------------------------------------ 4. HTML
paso 4 "Generando el informe HTML con gráficos ..."
mkdir -p "$CARPETA_EST"
SELLO="$(date +%Y%m%d_%H%M%S)"
GENERADO="$(date +%Y-%m-%dT%H:%M:%S)"
HTML="$CARPETA_EST/estadisticas_$SELLO.html"
XMLS="$CARPETA_EST/estadisticas_$SELLO.xml"

LOGO=""
if [ -f "$RECURSOS/logo.png" ]; then
    LOGO="data:image/png;base64,$(base64 < "$RECURSOS/logo.png" | tr -d '\r\n')"
elif [ -f "$RECURSOS/logo.svg" ]; then
    LOGO="data:image/svg+xml;base64,$(base64 < "$RECURSOS/logo.svg" | tr -d '\r\n')"
fi
[ -n "$LOGO" ] && echo "   Logo incrustado desde recursos/." || echo "   (No hay logo en recursos/: se genera sin él.)"

{
    printf '{"generado":"%s","sistema":"%s","script":"%s","periodo":{"desde":"%s","hasta":"%s"},"logo":"%s",' \
        "$GENERADO" "$SISTEMA" "$NOMBRE_SCRIPT" "$DESDE" "$HASTA" "$LOGO"
    printf '"informes":['; cat "$TMP/j_informes"
    printf '],"terminos":['; cat "$TMP/j_terminos"
    printf '],"paginas":['; cat "$TMP/j_paginas"
    printf '],"frases":['; cat "$TMP/j_frases"
    printf ']}'
} > "$TMP/datos.json"

awk -v datos="$TMP/datos.json" '{
    i = index($0, "/*__DATOS__*/null")
    if (i) {
        printf "%s", substr($0, 1, i - 1)
        while ((getline l < datos) > 0) printf "%s\n", l
        close(datos)
        print substr($0, i + 17)
    } else print
}' "$PLANTILLA" > "$HTML"
echo "   -> estadisticas/$(basename "$HTML")"

# ------------------------------------------------ 5. XML
paso 5 "Guardando las estadísticas en XML ..."
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo "<estadisticas generado=\"$GENERADO\" sistema=\"$SISTEMA\" informes=\"$N\">"
    echo "  <periodo desde=\"$DESDE\" hasta=\"$HASTA\"/>"
    echo '  <sistemas>'
    awk -F'\t' '{ printf "    <sistema nombre=\"%s\" informes=\"%d\"/>\n", $1, $2 }' "$TMP/S"
    echo '  </sistemas>'
    echo '  <webs>'
    awk -F'\t' '{ printf "    <web url=\"%s\" informes=\"%d\"/>\n", $1, $2 }' "$TMP/W"
    echo '  </webs>'
    echo '  <terminos>'
    awk -F'\t' '{ printf "    <termino nombre=\"%s\" veces_buscado=\"%d\" veces_encontrado=\"%d\" apariciones_totales=\"%d\" media=\"%s\" maximo=\"%d\"/>\n", $1, $2, $3, $4, $5, $6 }' "$TMP/T"
    echo '  </terminos>'
    echo '  <idiomas>'
    awk -F'\t' 'NR == FNR { s += $2; next } { printf "    <idioma nombre=\"%s\" apariciones=\"%d\" porcentaje=\"%.1f\"/>\n", $1, $2, (s ? 100 * $2 / s : 0) }' "$TMP/I" "$TMP/I"
    echo '  </idiomas>'
    echo '  <numeros>'
    awk -F'\t' 'NR == FNR { s += $2; next } { printf "    <numero nombre=\"%s\" apariciones=\"%d\" porcentaje=\"%.1f\"/>\n", $1, $2, (s ? 100 * $2 / s : 0) }' "$TMP/U" "$TMP/U"
    echo '  </numeros>'
    echo "  <variantes_top limite=\"$TOP\">"
    awk -F'\t' '{ printf "    <variante posicion=\"%d\" texto=\"%s\" idioma=\"%s\" numero=\"%s\" apariciones=\"%d\"/>\n", NR, $1, $2, $3, $4 }' "$TMP/V"
    echo '  </variantes_top>'
    echo "  <frases total=\"$NFRASES\">"
    cat "$TMP/x_frases"
    echo '  </frases>'
    echo '</estadisticas>'
} > "$XMLS"
echo "   -> estadisticas/$(basename "$XMLS")"

# ------------------------------------------------ 6. Vaciar resultados
paso 6 "Vaciando resultados/ para los próximos scrapings ..."
if [ -s "$HTML" ] && [ -s "$XMLS" ] && ! grep -q '/\*__DATOS__\*/' "$HTML"; then
    rm -f -- "${FICHEROS[@]}"
    echo "   ${#FICHEROS[@]} informe(s) borrado(s). Las próximas estadísticas solo usarán scrapings nuevos."
else
    echo "   ATENCIÓN: el HTML o el XML no se han generado bien; NO se borra nada de resultados/."
    exit 1
fi

echo
echo "============================================================"
echo "  Informe listo: estadisticas/$(basename "$HTML")"
echo "============================================================"
if [ $ABRIR -eq 1 ]; then
    echo "Abriendo el informe en el navegador ..."
    if [ "$SISTEMA" = "macOS" ]; then
        open "$HTML"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$HTML" >/dev/null 2>&1 &
    else
        echo "No se ha encontrado cómo abrir el navegador. Ábrelo tú: $HTML"
    fi
fi
