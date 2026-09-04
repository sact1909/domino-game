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
3. En la pantalla inicial elige la meta de puntos (100, 150 o 200) y el valor de las
   tres bonificaciones (pase seguido, capicúa y pase de salida; 30 por defecto cada
   una). Luego pulsa **Comenzar partida**.
4. Cuando sea tu turno, las fichas jugables de tu mano se ven en color normal y las
   que no puedes jugar se ven grises. Haz clic en la ficha que quieras jugar.
5. Si la ficha calza en las dos puntas, aparece un aviso para que elijas en cuál
   jugarla (izquierda o derecha).
6. Al terminar cada mano aparece una pantalla con el resultado: quién ganó, las
   fichas que se cuentan (con los puntos de cada jugador y el total de la pareja) y
   el marcador. La partida sigue cuando pulsas **Continuar**.

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
| Puntuación | La pareja ganadora suma los puntos de **todas** las fichas que quedaron en la mesa, las de su propia pareja incluidas |
| Meta | 100, 150 o 200 puntos (se elige antes de empezar) |

### Tranque

Cuando nadie puede continuar (cuatro pases seguidos), la mano se decide **cara a
cara** entre dos jugadores:

1. Se toma a quien puso la última ficha (el que trancó) y al jugador que le seguía
   en el turno. Como los puestos se alternan, esos dos son siempre de parejas
   contrarias.
2. Se comparan los puntos que le quedan a esos dos: gana la mano la pareja de quien
   tenga **menos** puntos.
3. Esa pareja suma los puntos de **todas** las fichas que quedaron en la mesa —
   incluidas las dos manos que se compararon y las de su propia pareja.
4. **Empate entre los dos:** gana la pareja que tiene la mano (la del jugador que
   salió en esa mano).
5. En la mano siguiente sale, dentro de la pareja ganadora, quien se quedó con menos
   puntos en la mano.

Los puntos 4 y 5 son **reglas de casa** que la guía deja a criterio de la mesa, así
que se eligió una convención razonable. Si tu mesa lo hace distinto, se cambian en
`_resolve_tranque()`.

### Bonificaciones

Se configuran antes de empezar (30 por defecto cada una) y se acreditan al equipo en
el momento en que se ganan; el resumen de fin de mano las lista aparte de los puntos
de la mesa.

| Bonificación | Cuándo se gana |
|---|---|
| **Pase seguido** | Un jugador pone una ficha que deja sin jugada a los otros **tres** (rivales y compañero), y él sí puede seguir jugando. Es acumulativo: cada vez que lo consigue vuelve a sumar. No es lo mismo que un tranque — en el tranque tampoco puede jugar él. |
| **Capicúa** | Un jugador se pega con una ficha que cierra las dos puntas **usando una cara en cada una**. Con un 6-5 aplica si las puntas son 5 y 6 (en cualquier orden), pero **no** si las dos puntas son 6 o las dos son 5 — ahí cerraría con la misma cara. Los dobles nunca cuentan. Se suma sobre los puntos que recoge de la mesa. |
| **Pase de salida** | Quien sale de la mano deja sin jugada al jugador que le sigue en el turno. Se **anula** si su propio compañero tampoco puede jugar en su primer turno. |

### Indicadores en la mesa

- Una **bolita** junto al nombre de cada puesto se enciende en amarillo cuando es su
  turno.
- El puesto que salió en la mano lleva la marca **· salió**, para tener siempre la
  referencia de quién jugó primero en esa ronda.
- Un **aviso flotante** aparece y se desvanece cuando alguien pasa el turno o cuando
  se gana una bonificación.

## Estructura del proyecto

```
project.godot              Configuración (ventana 1280x900, escena principal)
scenes/Boot.tscn           Punto de entrada: decide entre juego y servidor
scenes/Main.tscn           El juego (la interfaz se crea por código)
scenes/Server.tscn         El servidor dedicado
scripts/Boot.gd            Detección de modo servidor
scripts/Domino.gd          Clase de ficha: valores, dobles, puntos y su textura
scripts/rules/GameState.gd Estado y reglas, sin interfaz (corre igual en el servidor)
scripts/Main.gd            Interfaz, entrada del usuario y ritmo de los turnos
scripts/server/ServerMain.gd  Servidor WebSocket
docker/Dockerfile          Build del servidor dedicado
DominoTiles/*.png          Las 28 imágenes de fichas (128x256 cada una)
```

## Servidor dedicado (en construcción)

El mismo binario sirve para las dos cosas: `scenes/Boot.tscn` arranca el juego con
interfaz, salvo que detecte modo servidor (plantilla *dedicated server* o el
argumento `--server`).

Por ahora el servidor solo valida la cadena de despliegue: acepta conexiones
WebSocket, saluda al conectar y responde a un `ping`. Las salas con código y el
juego en red vienen después.

**Probar en local**, sin exportar nada:

```bash
godot --headless -- --server
```

**Construir la imagen:**

```bash
docker build -f docker/Dockerfile -t domino-server .
```

**Correrla:**

```bash
docker run --rm -p 8090:8090 domino-server
```

### Puerto

El servidor escucha en el puerto de la variable de entorno `PORT`, y usa 8090 si no
está definida. Para correrlo en otro puerto:

```bash
docker run --rm -p 3000:3000 -e PORT=3000 domino-server
```

Si `PORT` trae un valor que no es número, el servidor avisa en el log y cae al
puerto por defecto — así el problema se ve, en vez de que el proxy no encuentre a
nadie escuchando.

### Notas de despliegue en Coolify

- Build pack **Dockerfile**, ruta `docker/Dockerfile`, contexto en la raíz del repo.
- Definir la variable de entorno **`PORT`** con el puerto que quieras y asegurarte de
  que el proxy apunte al mismo. Por defecto es 8090, elegido a propósito para no
  chocar con el 8080 que suelen usar otros servicios.
- **Health check a nivel TCP, no HTTP:** un servidor WebSocket rechaza un `GET`
  normal, así que un chequeo HTTP daría falsos negativos aunque el servidor esté
  sano.
- **Una sola instancia.** Las salas viven en memoria: si se escala horizontalmente,
  un jugador que caiga en otra instancia no encontraría la sala.
- Los redespliegues reinician el contenedor y se pierden las partidas en curso.
- `export_presets.cfg` **debe estar versionado** — el build lo necesita para
  exportar dentro del contenedor. El preset se llama `Linux` y tiene
  `dedicated_server=true`; si se le cambia el nombre, hay que actualizar el
  `ARG EXPORT_PRESET` del Dockerfile.

### Nombres de las imágenes de fichas

Las texturas no usan números sino los nombres en español, siempre **del valor mayor
al menor** (`Domino.texture_path()` construye el nombre):

- Valores: `Blanco`=0, `Uno`=1, `Dos`=2, `Tres`=3, `Cuatro`=4, `Cinco`=5, `Seis`=6
- Fichas normales: `SeisCuatro.png` = 6-4, `TresUno.png` = 3-1
- Dobles: `DobleSeis.png`, `DobleCinco.png`, …
- Excepción: el **0-0** se llama `CajaBlanca.png` (es la única sin puntos)

En la imagen sin girar, la mitad de **arriba** siempre es el valor mayor y la de
**abajo** el menor. De eso depende el cálculo de rotación al dibujar el tablero.

## Separación de reglas e interfaz

`GameState` guarda todo el estado de la partida y responde las consultas de reglas
(jugadas legales, puntos por puesto y por pareja, reparto). No conoce nodos, no
dibuja, no escribe en el registro y no usa `await`. `Main.gd` solo dibuja, atiende
al usuario y lleva el ritmo de los turnos.

Esa separación es la que va a permitir correr las mismas reglas en el servidor
dedicado, en vez de reimplementarlas en otro lenguaje y tener dos motores de reglas
que mantener sincronizados.

El reparto es **determinista por semilla** (`GameState.deal(seed)`): la misma semilla
da siempre el mismo reparto, así se puede reproducir una mano exacta para depurar, y
cuando se juegue en red el servidor será la única fuente del azar. No se usa
`Array.shuffle()` porque toma el generador global y no se puede fijar por semilla.

### Transiciones por eventos

`apply_play()` y `apply_pass()` aplican la jugada y devuelven una **lista de eventos**
que describe lo que pasó (`played`, `passed`, `bonus`, `hand_won`, `tranque`,
`rejected`…), en vez de escribir en pantalla. `Main.gd` los traduce a texto, avisos y
pantallas en `_handle_event()`.

Los eventos llevan datos estructurados, no texto: una bonificación viaja como
`{"kind": "capicua", "seat": 2, "pts": 30}` y el idioma se resuelve en la interfaz.
Cuando el juego sea en red, esos mismos eventos llegarán del servidor y esa capa de
traducción no cambia.

`apply_play()` **valida** la jugada contra las jugadas legales y devuelve `rejected`
si no calza. Jugando en local no debería ocurrir nunca, pero es la base de la
autoridad del servidor: un cliente modificado no podrá inventar una jugada, una
capicúa ni un turno ajeno.

### Vistas: separar lo público de lo privado

`GameState` expone tres vistas, y el **dibujado lee solo de ellas**, nunca del
estado directamente:

- **`public_view()`** — lo que cualquiera puede ver: el tablero, las puntas, los
  marcadores, de quién es el turno, quién salió, los bonos. De las manos ajenas solo
  viaja la **cantidad** de fichas, nunca cuáles son.
- **`private_view(seat)`** — las fichas de ese puesto y sus jugadas posibles.
- **`reveal_view()`** — las cuatro manos, para el resumen de fin de mano. Se pide
  únicamente con la mano ya cerrada.

Esto es lo que hace posible jugar en red sin filtrar información: el servidor
difundirá la vista pública a los cuatro jugadores y le mandará a cada uno solo su
vista privada. Un cliente modificado no puede mostrar lo que nunca le llegó.

La IA también recibe la vista privada de su puesto en vez del estado completo, así
solo puede usar lo que un jugador de verdad vería. Eso importa para cuando releve a
alguien que se desconecte.

**Lo que sí accede al estado con autoridad** son las dos otras funciones que hoy
cumple `Main.gd`, y que pasarán al servidor: aplicar jugadas y decidir un pase
forzado. Está marcado con comentarios en el código.

## Pruebas

Como las reglas son puras, se pueden probar sin abrir la ventana:

```bash
godot --headless -- --test
```

Juega cientos de partidas completas eligiendo jugadas legales al azar y, después de
cada acción, verifica invariantes:

- Las 28 fichas están siempre contabilizadas entre las manos y la mesa, sin
  repetirse ni perderse.
- La mesa es una cadena válida: cada ficha calza con la anterior y las puntas
  guardadas coinciden con las caras libres reales. Es justo lo que el dibujado del
  tablero da por sentado.
- El turno avanza exactamente un puesto por acción.
- Toda mano termina (alguien se pega o hay tranque), con un tope de acciones para
  detectar un cuelgue.
- Los marcadores solo suben.
- Los puntos de la mano son la suma de todas las fichas de la mesa.
- En un tranque, los dos jugadores comparados son siempre de parejas contrarias, y
  gana quien tenga menos puntos.
- La primera mano de la partida abre con el 6-6.
- **La vista pública no contiene ninguna ficha que no esté en la mesa.** Se recorre
  la vista entera buscando fichas, en vez de mirar solo las claves conocidas: si
  alguien agrega un campo que sin darse cuenta arrastra manos ajenas, la prueba lo
  caza. En red, ese descuido es que un cliente modificado te vea la mano.
- Las vistas entregan copias, no referencias: modificarlas no toca el estado.

También prueba lo que **no** debe poderse: jugar fuera de turno, pasar teniendo
jugada, abrir la primera mano sin el 6-6, y pedir una punta donde la ficha no calza.
Y que un rechazo no altere el estado.

Sale con código 0 si todo pasa y 1 si algo falla, así sirve tal cual en CI. Cuando
algo falla informa la semilla del reparto, para poder reproducir esa mano exacta.

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
