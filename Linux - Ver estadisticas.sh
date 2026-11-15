#!/usr/bin/env bash
# Lanza las estadísticas en Linux (el código está en scripts/linux).
# Desde la terminal:  ./"Linux - Ver estadisticas.sh"   o doble clic -> "Ejecutar en terminal"
cd "$(dirname "$0")" || exit 1
bash scripts/linux/estadisticas_linux.sh "$@"
estado=$?
echo
read -r -p "Pulsa ENTER para terminar..." _
exit $estado
