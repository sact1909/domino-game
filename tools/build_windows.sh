#!/usr/bin/env bash
#
# Genera el ejecutable de Windows, opcionalmente con la dirección del servidor adentro.
#
#   tools/build_windows.sh                      -> apunta a localhost (desarrollo)
#   tools/build_windows.sh wss://mi-servidor    -> apunta ahí, y el campo del servidor
#                                                  ni se le muestra a quien lo reciba
#
# La dirección se escribe en un archivo suelto que se empaqueta dentro del ejecutable, en
# vez de ponerla en el código. Así no queda publicada en el repositorio, que es abierto.
# El precio es que cambiar de servidor obliga a volver a generar el ejecutable.
#
# El archivo se borra al terminar, pase lo que pase: si quedara, las corridas de
# desarrollo apuntarían al servidor de producción sin que se note.
set -euo pipefail

PRESET="Windows"
OUT="build/windows/DominoDominicano.exe"
URL_FILE="server_url.txt"

cd "$(dirname "$0")/.."

cleanup() {
	rm -f "$URL_FILE"
}
trap cleanup EXIT

if [ $# -gt 1 ]; then
	echo "Uso: $0 [URL_DEL_SERVIDOR]" >&2
	exit 2
fi

URL="${1:-}"
if [ -n "$URL" ]; then
	# Sobre wss:// vs ws://: el navegador y muchos proxys rechazan una conexión sin TLS
	# desde una página segura, y en el escritorio un ws:// contra un servidor con TLS
	# falla sin mensaje claro. Se avisa en vez de dejar que se descubra jugando.
	case "$URL" in
		wss://*) ;;
		ws://*) echo "AVISO: '$URL' no usa TLS. Contra un servidor detrás de un proxy HTTPS esto falla sin error visible." >&2 ;;
		*) echo "ERROR: la dirección tiene que empezar con ws:// o wss:// (recibí '$URL')" >&2; exit 2 ;;
	esac
	printf '%s' "$URL" > "$URL_FILE"
	echo "Horneando servidor: $URL"
else
	echo "Sin dirección: el ejecutable apuntará a localhost y mostrará el campo del servidor."
fi

mkdir -p "$(dirname "$OUT")"

# Se borra el anterior ANTES de exportar, por dos motivos. Uno: si queda, Godot falla al
# renombrar su archivo temporal encima. Dos, y más importante: sin borrarlo, una
# exportación fallida deja el ejecutable viejo en su sitio y este guion lo daría por
# bueno — repartirías una compilación vieja creyendo que es la nueva.
#
# Windows bloquea un ejecutable mientras corre, así que si el juego está abierto esto
# falla. Se dice con todas las letras: el error del sistema no menciona el juego, y
# probar y volver a compilar es lo más natural del mundo.
if ! rm -f "$OUT" "${OUT%.exe}.tmp" "${OUT%.exe}.pck" 2>/dev/null; then
	echo "ERROR: no se pudo borrar $OUT." >&2
	echo "¿Está el juego abierto? Windows bloquea el ejecutable mientras corre." >&2
	echo "Ciérralo y vuelve a intentar." >&2
	exit 1
fi

# Se reimporta antes de exportar para que el archivo recién escrito entre al paquete.
echo "Importando recursos..."
godot --headless --import >/dev/null 2>&1 || true

echo "Exportando..."
# El error de exportación se va por stderr y el comando sale en silencio, así que se
# muestra todo. PIPESTATUS es el código de godot, no el del grep, que es lo que importa.
set +e
godot --headless --export-release "$PRESET" "$OUT" 2>&1 | grep -viE "savepack|first_scan|^$"
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ] || [ ! -f "$OUT" ]; then
	echo "" >&2
	echo "ERROR: la exportación falló (código $status) y no hay ejecutable nuevo." >&2
	echo "Lo más común es que falten las plantillas de exportación: en el editor," >&2
	echo "Editor -> Administrar plantillas de exportación -> Descargar e instalar." >&2
	exit 1
fi

echo "Listo: $OUT ($(du -h "$OUT" | cut -f1))"
