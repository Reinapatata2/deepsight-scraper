# DeepSight Scraper

Herramienta de clase para el proyecto **DeepSight**:
- **El scraper** busca palabras clave en una web, en español e inglés y en singular y plural. Guarda cuántas veces aparecen y la frase en la que sale cada una.
- **Las estadísticas** combinan esos informes en un informe HTML con gráficos.

## Cómo se usa

| Sistema | 1. Buscar palabras en una web | 2. Ver las estadísticas |
|---|---|---|
| macOS | Doble clic en `Mac - Ejecutar scraper.command` | Doble clic en `Mac - Ver estadisticas.command` |
| Windows | Doble clic en `Windows - Ejecutar scraper.bat` | Doble clic en `Windows - Ver estadisticas.bat` |
| Linux | `./"Linux - Ejecutar scraper.sh"` | `./"Linux - Ver estadisticas.sh"` |

- **URL por defecto:** se configura en `config/config.txt`.
- **Resultados:** los informes de cada búsqueda se guardan en `resultados/`.
- **Estadísticas:** se guardan en `estadisticas/` y se abren solas en el navegador.

## Carpetas

| Carpeta | Contenido |
|---|---|
| `config/` | `config.txt` (URL y opciones) y `diccionario.csv` (traducciones) |
| `docs/` | [Manual completo](docs/manual.md) |
| `estadisticas/` | Informes HTML y XML generados |
| `recursos/` | Logo y plantilla del informe de estadísticas |
| `resultados/` | Informes XML del scraper pendientes de estadísticas |
| `scripts/` | Código de cada sistema (`mac/`, `linux/`, `windows/`) |

Todo el detalle está en el **[manual](docs/manual.md)**: qué descarga y qué guarda, traducción, frases de contexto, opciones, formato XML y cómo personalizar el diseño.
