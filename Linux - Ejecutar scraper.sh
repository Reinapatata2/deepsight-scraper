#!/usr/bin/env bash
# Lanza el scraper en Linux (el código está en scripts/linux).
# Desde la terminal:  ./"Linux - Ejecutar scraper.sh"   o doble clic -> "Ejecutar en terminal"
cd "$(dirname "$0")" || exit 1
bash scripts/linux/scraper_linux.sh "$@"
estado=$?
echo
read -r -p "Pulsa ENTER para terminar..." _
exit $estado
