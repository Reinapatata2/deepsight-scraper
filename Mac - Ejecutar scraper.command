#!/bin/bash
# Doble clic en Finder para abrir el scraper en Terminal (el código está en scripts/mac)
cd "$(dirname "$0")" || exit 1
bash scripts/mac/scraper_mac.sh "$@"
echo
echo "============================================================"
read -r -p "  Pulsa ENTER para cerrar esta ventana..." _

# Cierra esta ventana de Terminal (si no se pudiera, ciérrala con Cmd+W).
# El cierre se lanza separado de la terminal para que Terminal no pregunte
# "¿terminar procesos?" y espera 1 s a que este script haya terminado.
CIERRE="delay 1
tell application \"Terminal\"
    repeat with w in windows
        try
            if (count of tabs of w) is 1 and (tty of tab 1 of w) is \"$(tty)\" then
                close w
                exit repeat
            end if
        end try
    end repeat
end tell"
if command -v perl >/dev/null 2>&1; then
    perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' osascript -e "$CIERRE" </dev/null >/dev/null 2>&1 &
else
    nohup osascript -e "$CIERRE" </dev/null >/dev/null 2>&1 &
fi
exit 0
