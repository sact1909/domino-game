# Dominó Dominicano

Juego de dominó dominicano hecho en **Godot 4.7** (GDScript). Partida de 4 jugadores
en 2 parejas, con dominó doble-seis de 28 fichas. Tú juegas en el Sur; los otros tres
puestos los maneja la IA.

## Requisitos

- [Godot 4.7](https://godotengine.org/) o superior (rama 4.x).
- No hace falta nada más: el proyecto no usa plugins ni dependencias externas.

## Cómo jugar

1. Abre Godot y usa **Importar** apuntando a `project.godot`.
2. Dale **Play** (F5).
3. En la pantalla inicial elige la meta de puntos (100, 150 o 200) y pulsa
   **Comenzar partida**.
4. Cuando sea tu turno, las fichas jugables de tu mano se ven en color normal y las
   que no puedes jugar se ven grises. Haz clic en la ficha que quieras jugar.
5. Si la ficha calza en las dos puntas, aparece un aviso para que elijas en cuál
   jugarla (izquierda o derecha).

> Si cambias el código con el juego abierto, detén la ejecución (**Stop**) y dale
> **Play** de nuevo: Godot no siempre aplica cambios de GDScript a una escena que ya
> está corriendo.

## Reglas implementadas

Basadas en la guía del dominó dominicano (formato estándar de 4 jugadores):

| Regla | Implementación |
|---|---|
| Jugadores | 4 (Sur = humano, Este/Norte/Oeste = IA) |
| Parejas | Sur-Norte contra Este-Oeste (se sientan enfrentados) |
| Fichas | 28 (doble-seis), 7 por jugador |
| Pozo | No existe: se reparten las 28 fichas completas |
| Dirección | Contraria a las agujas del reloj (Sur → Este → Norte → Oeste) |
| Primera salida | Sale quien tiene el **6-6** (el burro), y está obligado a jugarlo |
| Salidas siguientes | Sale quien ganó la mano anterior |
| Si puedes jugar | Debes jugarla: no se puede pasar voluntariamente |
| Si no puedes jugar | Se pasa automáticamente (no hay que pulsar nada) |
| Dobles | Se colocan cruzados respecto a la cadena |
| Fin de mano | Quien coloca su última ficha gana la mano |
| Puntuación | La pareja ganadora suma los puntos de las fichas que le quedaron a la pareja contraria |
| Meta | 100, 150 o 200 puntos (se elige antes de empezar) |

### Tranque

Cuando nadie puede continuar (cuatro pases seguidos):

1. Se suman los puntos de las fichas que le quedan a cada pareja.
2. Gana la mano la pareja con **menos** puntos.
3. La pareja ganadora suma los puntos de la pareja perdedora.
4. **Empate:** gana la pareja que tiene la mano (la del jugador que salió en esa mano).
5. En la mano siguiente sale, dentro de la pareja ganadora, quien se quedó con menos
   puntos en la mano.

Los puntos 3 y 5 son **reglas de casa**: la guía deja esos detalles a criterio de la
mesa, así que se eligió una convención razonable. Si tu mesa lo hace distinto, se
cambia en `_resolve_tranque()`.

## Estructura del proyecto

```
project.godot          Configuración (ventana 1280x900, escena principal)
scenes/Main.tscn       Escena raíz (solo el nodo raíz; la interfaz se crea por código)
scripts/Domino.gd      Clase de ficha: valores, dobles, puntos y su textura
scripts/Main.gd        Toda la lógica del juego y la interfaz
DominoTiles/*.png      Las 28 imágenes de fichas (128x256 cada una)
```

### Nombres de las imágenes de fichas

Las texturas no usan números sino los nombres en español, siempre **del valor mayor
al menor** (`Domino.texture_path()` construye el nombre):

- Valores: `Blanco`=0, `Uno`=1, `Dos`=2, `Tres`=3, `Cuatro`=4, `Cinco`=5, `Seis`=6
- Fichas normales: `SeisCuatro.png` = 6-4, `TresUno.png` = 3-1
- Dobles: `DobleSeis.png`, `DobleCinco.png`, …
- Excepción: el **0-0** se llama `CajaBlanca.png` (es la única sin puntos)

En la imagen sin girar, la mitad de **arriba** siempre es el valor mayor y la de
**abajo** el menor. De eso depende el cálculo de rotación al dibujar el tablero.

## Cómo se dibuja el tablero

Esta parte es la que tiene más lógica no obvia, en `_layout_chain()` y
`_render_board()`:

- **La ficha inicial nunca se mueve:** queda anclada exactamente en el centro del
  tablero durante toda la mano, sin importar hacia dónde crezca la cadena.
- **Cada ficha se orienta según con qué número conecta:** se calcula qué mitad debe
  quedar hacia el vecino y se gira la textura (0°/90°/180°/270°) para que las caras
  siempre calcen.
- **Los dobles siempre se dibujan en su orientación natural** (angostos y altos): eso
  los hace cruzar una fila horizontal, y alinearse con la columna cuando la cadena va
  en vertical.
- **Cada lado dobla una sola vez:** avanza recto hasta `ROW_LENGTH` (5) fichas, dobla
  90° una vez (el lado derecho hacia arriba, el izquierdo hacia abajo) y desde ahí
  sigue derecho en sentido contrario el resto de la mano. En la esquina, la ficha que
  dobla cae justo sobre la última mitad de la ficha anterior, compartiendo un borde
  completo.
- **Se encoge para caber:** si el trazado no cabe en el área central, todas las fichas
  se escalan por igual alrededor del mismo centro (mínimo 0.28), así la cadena nunca
  se desplaza — solo se hace más chica.

## La IA

Sencilla a propósito: entre sus jugadas legales prefiere los dobles y, si no hay,
la ficha de más puntos, para soltar las pesadas primero. No cuenta pases ni deduce
qué tiene la pareja.

Ideas para mejorarla: aprovechar la información de los pases (la guía insiste en que
"cada pase habla"), llevar cuenta de números muertos, y jugar pensando en la pareja.
