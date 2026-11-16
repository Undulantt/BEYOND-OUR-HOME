# Verificación de la entrega final

## Funcionamiento y correcciones

- Robot visible durante el tutorial, con identificación S.I.
- Barras de agua, comida, oxígeno y electricidad, con presión y carga de batería.
- Fichas de doce edificios y explicaciones de los eventos con fuentes NASA.
- Iconos amarillos anclados al edificio, sin desplazamiento al alejar la cámara.
- Selección sobre el volumen visible de los modelos.
- Exposición por ubicación, regreso al refugio y daño por dosis acumulada.
- Correcciones de baterías, carga en pausa y progreso del tutorial.
- Los cortes de energía actualizan materiales sin reconstruir todo el mundo.

Antes de empaquetar pasaron 176 comprobaciones de iconos, 166 integradas y 213 del
tutorial completo, además de las siete suites de regresión de lógica. Después de
separar archivos se repitió la suite integrada: 166 comprobaciones sin fallos.
Los informes extensos y resultados originales permanecen en el archivo local.

## Archivos conservados

Se mantienen todos los scripts, datos JSON, modelos, texturas, fuentes y audios
que usa el juego. Las imágenes pequeñas de los modelos se conservan porque el
importador de Godot las utiliza como texturas, aunque parezcan miniaturas.

Se apartaron pruebas automatizadas, informes históricos, capturas, paquetes de
prototipo, escenas de diagnóstico y exportaciones anteriores. No se borraron sus
contenidos: están en `archivo_local`, excluido del repositorio. Las herramientas
MCP y sus dependencias siguen disponibles localmente sin incluirse en la entrega.

## Validación del paquete Windows

La entrega se exporta como Windows Desktop x86_64, sin depuración, incluyendo
los JSON necesarios. El paquete de datos se comprobó con una partida nueva,
construcción de túnel/laboratorio, investigación con dos trabajadores, ficha
educativa y guardado/carga. El ejecutable exportado arrancó con gráficos D3D12
y terminó la prueba de inicio sin errores.

También se creó una copia exacta del contenido preparado para Git, sin cachés,
pruebas ni herramientas locales. Su importación desde cero y el recorrido de
construcción, investigación y guardado finalizaron correctamente. El ZIP Windows
de esa copia se descomprimió y su ejecutable gráfico arrancó con código de salida 0.
El paquete incluye las licencias de Godot, sus bibliotecas y la tipografía Jura.

La evaluación se realiza en el equipo Windows disponible. No sustituye una prueba
en otros equipos ni certifica una exportación web. Los tiempos, dosis y costes del
juego son reglas de simulación; no representan resultados médicos o físicos NASA.
