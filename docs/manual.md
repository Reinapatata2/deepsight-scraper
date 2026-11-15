# Manual de uso

Scraper de palabras clave para webs y generador de estadísticas, con una versión para macOS, Linux y Windows. Todas hacen exactamente lo mismo y sus informes se pueden mezclar.

## Estructura del proyecto

```
deepsight-scraper/
├── Mac - Ejecutar scraper.command       ┐
├── Mac - Ver estadisticas.command       │
├── Windows - Ejecutar scraper.bat       │  Lanzadores: lo único que hay que abrir
├── Windows - Ver estadisticas.bat       │
├── Linux - Ejecutar scraper.sh          │
├── Linux - Ver estadisticas.sh          ┘
├── README.md                            Portada del proyecto
├── config/
│   ├── config.txt                       URL por defecto y opciones
│   └── diccionario.csv                  Traducciones ya conocidas (caché)
├── docs/
│   └── manual.md                        Este manual
├── estadisticas/                        Informes HTML y XML generados (no se borran)
├── recursos/
│   ├── logo.svg                         Símbolo de DeepSight
│   └── plantilla_estadisticas.html      Diseño del informe de estadísticas
├── resultados/                          XML del scraper pendientes de estadísticas
└── scripts/                             Código de cada sistema
    ├── mac/        scraper_mac.sh, estadisticas_mac.sh
    ├── linux/      scraper_linux.sh, estadisticas_linux.sh
    └── windows/    scraper_windows.ps1, estadisticas_windows.ps1
```

Los lanzadores de la raíz llaman al código de `scripts/`. Los scripts localizan solos `config/`, `recursos/`, `resultados/` y `estadisticas/`, así que funcionan aunque la carpeta del proyecto se mueva o se clone en otro sitio.

## Uso

### macOS
1. Doble clic en **`Mac - Ejecutar scraper.command`**. Se abre Terminal con las instrucciones.
2. Pulsa Enter para usar la URL de `config/config.txt`, o escribe otra.
3. Escribe las palabras (varias separadas por comas). Para empezar el scraping, pulsa **Enter con la línea vacía**.
4. Cuando tengas varios informes, doble clic en **`Mac - Ver estadisticas.command`**.

Al terminar, pulsa Enter y la ventana se cierra sola.

La primera vez pueden salir avisos:
- **"desarrollador no identificado"**: clic derecho en el fichero → Abrir → Abrir.
- **"Terminal quiere acceder a Escritorio"** o **"Terminal quiere controlar Terminal"**: pulsa Permitir.

### Windows
Doble clic en **`Windows - Ejecutar scraper.bat`** y, después, en **`Windows - Ver estadisticas.bat`**. Requiere Windows PowerShell 5.1, que viene con Windows 10/11, o PowerShell 7.

### Linux
```bash
chmod +x *.sh                              # solo la primera vez
./"Linux - Ejecutar scraper.sh"            # usa la URL de config/config.txt
./"Linux - Ejecutar scraper.sh" http://localhost/mi-web 5
./"Linux - Ver estadisticas.sh"
```
Requiere `bash`, `curl`, `sed`, `awk`, `grep` y `tr`, que vienen en cualquier distribución. Para abrir el navegador usa `xdg-open`.

### Ejemplo de sesión
```
URL de la web [http://localhost/]:                      <- Enter = la de config.txt
Palabras > Colegio, Clarinete
   -> se buscará: colegio, colegios, school, schools
   Buscando la traducción de 'clarinete'...
   Traducción: clarinete (español) = clarinet (inglés)
   Pulsa Enter si es correcta, o escribe la traducción correcta en inglés:
   -> se buscará: clarinete, clarinetes, clarinet, clarinets
Más palabras (Enter vacío para empezar) > Test
   Buscando la traducción de 'test'...
   Traducción: prueba (español) = test (inglés)
   Pulsa Enter si es correcta, o escribe la palabra correcta en español:
   -> se buscará: prueba, pruebas, test, tests
Más palabras (Enter vacío para empezar) >               <- Enter vacío: empieza
```

## Qué descarga y qué guarda

El scraper **no** lee la pestaña que tengas abierta en el navegador. Descarga él mismo la página por HTTP desde la URL indicada.

**Descarga**
- El HTML de la URL y de las páginas a las que enlaza **dentro de la misma web**, hasta `MAX_PAGINAS`, con 1 segundo de pausa entre páginas.

**No descarga**
- Imágenes, vídeos, CSS, JavaScript ni PDF.
- Enlaces a otras webs, enlaces de cerrar sesión (te desconectarían) ni páginas de edición o historial.

**Guarda**
- En `resultados/`, solo los resultados: páginas visitadas, apariciones de cada variante y frases de contexto.
- El HTML completo **no se guarda**: se procesa en una carpeta temporal o en memoria y se descarta.

**Limitaciones**
- No inicia sesión: en una web con login verá la pantalla de acceso.
- No ejecuta JavaScript: no verá el texto que la página pinta después de cargar.

Si la web es local (XAMPP, `localhost`…), tiene que estar arrancada. También acepta `file:///ruta/pagina.html`.

## Cómo se amplían las palabras

1. Para comparar se pasa todo a minúsculas y se quitan las tildes, tanto lo que escribes como el texto de la web: `Tequila` = `TEQUILA` = `tequila`, y `Lápiz` = `lapiz`. La `ñ` se mantiene.
2. Primero se busca la palabra en `config/diccionario.csv`, en cualquier columna, así que vale `pinceles`, `pincel` o `brush`.
3. Si no está, se traduce por internet:
   - **Wiktionary** primero: es fiable con palabras sueltas, reconoce plurales y detecta palabras inglesas (`test` → prueba).
   - **MyMemory** de reserva.
   - Sin conexión, te pregunta la traducción.
4. Te enseña la traducción: la aceptas con Enter o escribes la correcta. Después se guarda en el diccionario y no vuelve a preguntar por esa palabra.
5. El singular y el plural se generan con reglas del español y del inglés (`lápiz` → lápices, `city` → cities).
6. Solo cuentan palabras completas (`colegio` no cuenta dentro de `colegiodemo`). También funcionan expresiones como `high school`.
7. Cuando una variante es igual en los dos idiomas (`color`) o en singular y plural (`data`), se marca como `ambos` y se cuenta una vez.

## Frases de contexto

De cada coincidencia se guardan las palabras de antes y de después, tal cual aparecen en la web:

> …El profesor realizó un **Test** con la herramienta Claude. Después,…

## Estadísticas

Al ejecutar el lanzador de estadísticas, la consola muestra cada paso:

1. Busca los informes nuevos en `resultados/`, de cualquier sistema.
2. Los combina y calcula las estadísticas.
3. Muestra el resumen por consola.
4. Genera `estadisticas/estadisticas_<fecha>.html` con el diseño de DeepSight. Incluye:
   - cifras clave;
   - coincidencias por término, separadas por idioma;
   - reparto por idioma y por singular/plural;
   - variantes y páginas con más coincidencias;
   - tabla por término;
   - registro de frases desplegable, con buscador;
   - lista de informes incluidos.
5. Guarda `estadisticas/estadisticas_<fecha>.xml`, con los mismos datos y todas las frases.
6. **Vacía `resultados/`**: borra solo los XML que acaba de procesar, y solo si el HTML y el XML se han generado bien.
7. Abre el HTML en el navegador. Para no abrirlo, usa `--no-abrir` en Mac/Linux o `-NoAbrir` en Windows.

El HTML es un único fichero autónomo: lleva el logo y los datos dentro, así que se puede enviar o abrir sin conexión.

## Configuración (`config/config.txt`)

| Opción | Por defecto | Qué hace |
|---|---|---|
| `URL` | — | Web que se propone al arrancar el scraper |
| `MAX_PAGINAS` | `10` | Páginas de la misma web que se recorren (`1` = solo la indicada) |
| `TRADUCTOR_ONLINE` | `si` | `no` = no se conecta a ningún traductor |
| `CONFIRMAR_TRADUCCION` | `si` | `no` = acepta las traducciones sin preguntar |
| `PALABRAS_CONTEXTO` | `5` | Palabras guardadas a cada lado de una coincidencia |
| `MAX_FRASES` | `100` | Frases por palabra en cada informe (`0` = sin límite) |

## Formato del informe XML (`resultados/`)

```xml
<informe_scraping version="1.0">
  <metadatos>
    <fecha>2026-11-15T09:34:25</fecha>
    <sistema>macOS</sistema>
    <url_inicial>http://localhost/</url_inicial>
    <paginas_analizadas>2</paginas_analizadas>
    <palabras_totales>59</palabras_totales>
  </metadatos>
  <paginas>
    <pagina url="http://localhost/" palabras="44"/>
  </paginas>
  <busqueda terminos="1">
    <palabra termino="colegio" total="7" encontrada="si">
      <variante texto="colegio"  idioma="es" numero="singular" apariciones="3"/>
      <variante texto="colegios" idioma="es" numero="plural"   apariciones="1"/>
      <variante texto="school"   idioma="en" numero="singular" apariciones="2"/>
      <variante texto="schools"  idioma="en" numero="plural"   apariciones="1"/>
      <en_pagina url="http://localhost/" apariciones="6"/>
      <frase variante="colegio" url="http://localhost/" antes="El profesor del"
             coincidencia="Colegio" despues="realizó un test con la"/>
    </palabra>
  </busqueda>
</informe_scraping>
```

## Personalizar el diseño

- **Colores:** están en el bloque `:root` al principio de `recursos/plantilla_estadisticas.html`. Los tres sistemas usan esa plantilla. Los colores de los gráficos están validados para distinguirse sobre el fondo azul marino, también con daltonismo.
- **Logo:** `recursos/logo.svg` es una recreación del símbolo de DeepSight. Si guardas el original como `recursos/logo.png`, se usará ese en su lugar. Solo afecta a los informes que se generen a partir de entonces.

## Notas para desarrollar

- `scripts/mac/` se genera a partir de `scripts/linux/`: es el mismo código y solo cambian el nombre del sistema y los textos. Si cambias uno, aplica el mismo cambio al otro.
- Los `.ps1` de Windows deben guardarse en **UTF-8 con BOM**. Sin él, Windows PowerShell 5.1 muestra mal las tildes.
- Los `.bat` deben tener finales de línea **CRLF**.
