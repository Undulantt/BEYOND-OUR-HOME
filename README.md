# Beyond Our Home

Juego de gestión y supervivencia de una colonia marciana. Construye, investiga,
asigna tareas y administra las reservas durante una campaña de 42 soles.

## Jugar en Windows sin instalar Godot

1. Descarga el repositorio con **Code → Download ZIP** y descomprímelo completo.
2. Abre **JUGAR-WINDOWS.cmd**. Descomprime el paquete Windows localmente y abre el juego.
3. También puedes descomprimir **JUGAR-WINDOWS.zip** manualmente y abrir **BEYOND OUR HOME.exe**. Mantén junto a él su archivo `.pck` y los demás archivos del paquete.

El paquete es para Windows de 64 bits. No requiere Python, Node.js, servidor web
ni instalar el editor de Godot. El equipo necesita poder ejecutar los gráficos 3D
usados por el juego. La configuración y las partidas se guardan en la carpeta de
usuario de Godot, fuera de esta entrega.

## Primeros pasos y controles

- **Nueva partida**: elige cuatro tripulantes. El robot ofrece **Aprender conmigo**,
  un tutorial de 19 objetivos; **Objetivo** y **Ayuda** permiten retomarlo.
- El HUD muestra agua, comida, electricidad, oxígeno y presión. Las barras de
  reservas indican autonomía sin nueva producción, no capacidad máxima del almacén.
- **!** abre la ficha educativa de un edificio. **Eventos** explica causas,
  consecuencias y respuestas. El inspector ofrece las acciones del edificio.
- **WASD / flechas**: cámara. **Rueda**: zoom. **Clic izquierdo**: selección o colocación.
  **Clic derecho**: cancelar colocación. **R**: girar una construcción.
- **Espacio**: pausar/reanudar. **Esc**: cerrar panel o cancelar colocación.
  **Guardar partida** guarda; **Continuar** recupera el autoguardado.

## Abrir y editar el proyecto

Usa **Godot 4.7.2**, importa `project.godot` y pulsa **F5**.
La escena de entrada es `scenes/integration/main.tscn`.

| Carpeta | Contenido necesario |
| --- | --- |
| `assets` | Modelos, imágenes, música, efectos y licencia de la fuente. |
| `autoload` | Servicios globales, configuración, audio y guardado. |
| `data` | Balance, idiomas, tutorial, tripulación y fuentes científicas. |
| `domain` | Reglas de construcción, energía, tareas, eventos y supervivencia. |
| `scenes` | Menús, interfaz y representación del mundo. |

`export_presets.cfg` contiene el preset Windows Desktop x86_64 y el filtro
`*.json` que necesita el juego. Exporta mediante **Exportar proyecto**, sin
depuración, a `build/windows/BEYOND OUR HOME.exe`. Conserva todos los archivos
que genere Godot. El paquete jugable se distribuye comprimido para respetar el
límite de tamaño por archivo de GitHub.

## Documentación de entrega

- [Créditos y atribuciones](CREDITOS.md).
- [Referencias NASA y límites de la simulación](FUENTES_NASA.md).
- [Comprobaciones y correcciones finales](VERIFICACION.md).

Los informes extensos, pruebas automatizadas, capturas, prototipos, miniaturas
sin uso y exportaciones anteriores se conservan localmente en `archivo_local`;
no forman parte de la entrega. Las cachés y herramientas locales de desarrollo
tampoco son necesarias para ejecutar el juego descargado.
