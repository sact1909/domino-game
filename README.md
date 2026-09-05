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
   jugarla (izquierda o derecha). Mientras está abierto el resto de tu mano queda
   apagada: la decisión pendiente es esa. Si te arrepientes, **No jugar** lo cierra y
   te deja elegir otra ficha.
6. Al terminar cada mano aparece una pantalla con el resultado: quién ganó, las
   fichas que se cuentan (con los puntos de cada jugador y el total de la pareja) y
   el marcador. La partida sigue cuando pulsas **Continuar**.

> Si cambias el código con el juego abierto, detén la ejecución (**Stop**) y dale
> **Play** de nuevo: Godot no siempre aplica cambios de GDScript a una escena que ya
> está corriendo.

## Jugar en línea

Desde la pantalla de inicio, **Jugar en línea con amigos**. O directo, sin pasar por la
configuración local:

```bash
godot -- --online
```

Uno crea la sala y comparte el código de cinco letras; los demás entran con ese código.
Cada uno pone su nombre.

En la sala **el anfitrión arma los equipos**: toca dos sillas y se intercambian. Los
demás ven la mesa pero no la pueden tocar.

Es a propósito que no elija cada quien. Antes cada uno escogía su lado, y eso trae una
negociación que el juego no puede mediar: dos personas apuntando al mismo sitio, y una
llevándose un rechazo por algo que no hizo mal. Con una sola persona repartiendo no hay
nada que ganarle a nadie, que es como funciona en una mesa de verdad — quien invita dice
quién se sienta con quién. El costo es que los demás quedan pasivos, y eso entre amigos
se arregla hablando.

Se intercambian **sillas** y no "lados" porque con la mesa llena mover a alguien de lado
obliga a que otro salga, y el intercambio dice exactamente quién. Con eso se llega a
cualquier reparto de equipos, cosa que un botón de "pasar al otro lado" no garantiza.

Las sillas se listan agrupadas por lado —`Sur-Norte` primero, `Este-Oeste` después— para
que se lea de un vistazo quién juega con quién. Las que queden vacías las juega la
máquina, así que dos o tres amigos pueden jugar sin esperar un cuarto.

El anfitrión es también el único que ve los ajustes (meta y las tres bonificaciones) y el
único que puede arrancar. Si se va, lo hereda el puesto ocupado más bajo, para que la
sala no quede viva sin nadie que pueda empezar.

### Al terminar una partida, la sala sigue viva

Terminar una partida no cierra la sala. Cada uno decide, y las opciones dependen de quién
seas:

| | Anfitrión | Los demás |
|---|---|---|
| Seguir | **Volver a jugar** — la sala se mantiene y espera a los demás | **Volver a jugar** — sigues en la misma sala y en la misma silla |
| Salir | **Cerrar sala** — saca a todos y la borra | **Salir de la sala** |

La revancha la puede pedir cualquiera, igual que "Continuar" tras una mano: esperar a los
cuatro deja la sala colgada en cuanto alguien se distrae, y quien todavía esté mirando el
resultado se entera por la difusión del lobby. El marcador arranca en cero, pero la gente
y las sillas se quedan como estaban.

Cerrar la sala es potestad del anfitrión porque es quien la creó. Es distinto de que se
vaya el último: eso deja la sala vencer sola por si alguien vuelve, y esto la termina a
propósito.

El campo de servidor está prellenado y se puede cambiar sin recompilar. También se puede
fijar por línea de comandos:

```bash
godot -- --online --server-url=wss://mi-servidor
```

### El socket tiene que sobrevivir al cambio de escena

Es la única parte del modo en red que no es obvia. El lobby abre el socket, se sienta en
una sala y espera; cuando la partida arranca hay que llevar **ese mismo socket** a la
mesa, porque reconectar significaría perder la silla. Y al pedir revancha el socket hace
el viaje de vuelta, por el mismo buzón.

Cambiar de escena en Godot destruye el árbol entero, y con él cualquier nodo que cuelgue
de la escena vieja. Así que el lobby lo saca del árbol y lo deja en
`TransportHandoff`, un buzón de un solo casillero: una variable estática vive con el
script, no con el nodo, y sobrevive el cambio. La mesa lo retira al arrancar, el
casillero queda vacío, y si no había nada arranca en modo local — que es exactamente lo
que hacía antes de que el lobby existiera.

Y hay una trampa que costó una tarde. Los paquetes se drenan TODOS los que llegaron en
el mismo `poll()`, y el servidor difunde el aviso de "arrancó la partida" y el primer
snapshot en el mismo cuadro, así que casi siempre llegan juntos. El lobby procesaba el
primero, soltaba el socket para el traspaso, y el bucle seguía emitiendo el snapshot **a
nadie**: la mesa todavía no existía. Resultado: tablero en blanco, y de forma
intermitente según cómo cayera el momento — con cuatro ventanas, dos funcionaban y dos
no.

El arreglo es que **el transporte recuerda lo último que anunció** —en qué puesto
quedaste, quién está en cada silla, el último estado de la mesa y si hay una mano en
curso— y lo repite cuando la mesa lo reengancha. Así la pantalla no tiene que distinguir
un reengancho de una partida que empieza, y no depende de llegar a tiempo a un mensaje
que ya pasó.

Lo único que se puede perder en esa ventana es alguna línea del registro de la mesa: el
estado del tablero viene del snapshot, que sí se repite.

## Repartir el juego a los amigos (Windows)

El proyecto trae dos presets de exportación en `export_presets.cfg`, que **se versiona a
propósito**:

| Preset | Para qué | Notas |
|---|---|---|
| `Linux` | El servidor dedicado | `dedicated_server=true`, sin las imágenes de fichas |
| `Windows` | El juego | Un solo `.exe`, con todo adentro |

### Una sola vez: las plantillas

Sin ellas la exportación falla. En el editor: **Editor → Administrar plantillas de
exportación → Descargar y instalar**, de la misma versión de Godot que el proyecto.

**El error no se ve si no se pide.** Godot lo manda a *stderr* y sale con código 1, pero
en la salida normal solo aparecen las líneas del escaneo y parece que no pasó nada. Si
el comando "no hace nada", correrlo así dice exactamente qué falta:

```bash
godot --headless --export-release "Windows" build/windows/DominoDominicano.exe 2>&1
```

**Ojo con las instalaciones portables.** Si junto al ejecutable de Godot hay un archivo
`._sc_`, está en *modo autocontenido*: ignora `%APPDATA%` y busca las plantillas en su
propio `editor_data`. Con scoop eso pasa, y las plantillas bajadas a la ruta de siempre
no las encuentra. La ruta buena es la que dice el propio error.

### Exportar

```bash
tools/build_windows.sh wss://mi-servidor
```

Sale un `.exe` único —el preset lleva `embed_pck=true`— que se copia y se manda tal cual.
`build/` está en el `.gitignore`, así que no se sube al repositorio.

Sin argumento genera una compilación de desarrollo que apunta a `localhost` y **muestra**
el campo del servidor. Con una dirección la **hornea** dentro del ejecutable y **esconde**
el campo: quien lo recibe no tiene nada que escribir ni que romper sin querer.

También se puede exportar desde el editor (**Proyecto → Exportar → Windows**), pero eso
no hornea nada: sale la versión de desarrollo.

La dirección del servidor **no está en el repositorio a propósito**, así que hay que
tenerla a mano: es la URL pública del servicio en Coolify, con `wss://` en vez de
`https://`. Conviene guardarla donde no se pierda, porque sin ella no se puede generar
un ejecutable repartible.

#### Por qué la dirección se hornea y no se escribe en el código

El guion la deja en un archivo suelto que se empaqueta dentro del ejecutable y **se borra
al terminar**, pase lo que pase. Así la dirección del servidor no queda publicada en el
repositorio, que es abierto, y las corridas de desarrollo no heredan sin querer el
servidor de producción. El precio es que cambiar de servidor obliga a volver a generar el
ejecutable.

Quién gana cuando hay varias:

| Prioridad | De dónde sale | Para qué |
|---|---|---|
| 1 | `--server-url=...` | Apuntar a otro sitio en una corrida concreta |
| 2 | Lo que el jugador guardó en el lobby | Solo si el campo está visible |
| 3 | La horneada al compilar | Lo que usan quienes reciben el juego |
| 4 | `localhost` | Desarrollo |

El lobby escribe en el registro a qué servidor apunta al arrancar. En un ejecutable
repartido, sin el campo a la vista, es la única forma de averiguarlo cuando alguien dice
que no conecta.

### Lo que van a ver tus amigos

Dos cosas que conviene avisarles de antemano:

- **Windows va a mostrar "Windows protegió su PC"** porque el ejecutable no está firmado.
  Hay que darle a *Más información → Ejecutar de todas formas*. No hay forma de evitarlo
  sin un certificado de firma de código, que se paga.
- **El servidor tiene que estar corriendo** y ser el mismo que se horneó. Si no, van a
  ver "No se pudo conectar" sin más pistas: el registro dice a cuál está apuntando.

El nombre que escriban se guarda en `user://lobby.cfg` y vuelve solo la próxima vez.

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
scenes/Lobby.tscn          La pantalla de entrada y sala para jugar en red
scripts/Boot.gd            Detección de modo servidor
scripts/Domino.gd          Clase de ficha: valores, dobles, puntos y su textura
scripts/rules/GameState.gd Estado y reglas, sin interfaz (corre igual en el servidor)
scripts/rules/GameSession.gd  Secuencia autoritativa de la mano, sin nodos ni relojes
scripts/rules/DominoAI.gd  Jugador automático (solo ve la vista privada de su puesto)
scripts/Main.gd            Interfaz de la mesa: dibuja y manda acciones
scripts/Lobby.gd           Nombre, crear o entrar por código, elegir silla, arrancar
scripts/net/Transport.gd   Contrato entre la interfaz y quien tiene la autoridad
scripts/net/LocalTransport.gd  Autoridad en este proceso: ritmo, IA y un solo puesto
scripts/net/WsClientTransport.gd  El mismo contrato, pero hablando con el servidor
scripts/net/TransportHandoff.gd  Buzón para pasar el socket entre escenas
scripts/net/Protocol.gd    Formato de los mensajes y traducción a/desde JSON
scripts/server/ServerMain.gd  Puerto, JSON y enrutado (el borde del sistema)
scripts/server/RoomCode.gd Alfabeto y generación de códigos de sala
scripts/server/Room.gd     Una sala: cuatro puestos alrededor de una GameSession
scripts/server/RoomRegistry.gd  Todas las salas vivas, y su recolección al vencer
scripts/tests/RulesTest.gd Arnés de reglas y de la secuencia de la sesión
scripts/tests/ServerTest.gd  Arnés de salas, códigos y protocolo (sin abrir puertos)
scripts/tests/NetTest.gd   Prueba de red con dos clientes reales (necesita el servidor)
tools/build_windows.sh     Genera el .exe, con la dirección del servidor adentro
docker/Dockerfile          Build del servidor dedicado
DominoTiles/*.png          Las 28 imágenes de fichas (128x256 cada una)
```

## Servidor de salas

El mismo binario sirve para las dos cosas: `scenes/Boot.tscn` arranca el juego con
interfaz, salvo que detecte modo servidor (plantilla *dedicated server* o el argumento
`--server`).

El servidor tiene tres capas, y la de arriba es a propósito la más delgada:

| Archivo | Qué hace |
|---|---|
| `ServerMain.gd` | Abre el puerto, desempaqueta JSON, comprueba que cada campo tenga la forma que dice tener, y despacha. Nada de reglas. |
| `RoomRegistry.gd` | Crea y encuentra salas por código, y recoge las que vencen. |
| `Room.gd` | Una sala: hasta cuatro jugadores alrededor de una `GameSession`. Es la autoridad. |

`ServerMain` es el **borde del sistema**: todo lo que entra por el socket viene de un
cliente que no controlamos y podría estar modificado, así que ahí se valida y se acota
todo. La meta se recorta entre 50 y 1000 y las bonificaciones a 500, porque un cliente
modificado podría pedir una meta de mil millones y dejar la mesa jugando para siempre.

### Códigos de sala

Cinco letras del alfabeto `BCDFGHJKMNPQRSTVWXYZ`, elegido para que no haya manera de
equivocarse al leerlo:

- **Sin 0/O ni 1/I/L**, las confusiones clásicas al teclear un código ajeno.
- **Solo letras**, porque mezclar letras y números obliga a aclarar si es la B o el 8.
- **Sin vocales**, porque con vocales cinco caracteres al azar tarde o temprano forman
  una palabra, y algunas no se le mandan a nadie.

Quedan 3.2 millones de códigos, muchísimos más de los que van a existir a la vez. El
precio es que se ven feos y no se pronuncian; vale la pena, porque se comparten
copiando y pegando mucho más de lo que se dictan, y un código mal tecleado es un
jugador que no entra. Al entrar se normaliza, así que `bcd-fg` y `BCDFG` son la misma
sala.

### Dos decisiones que vale explicar

**El reloj va por `tick(delta)`, no por `await`.** Es la diferencia con
`LocalTransport`, y no es un detalle: un servidor tiene que poder adelantar su reloj.
Así las pruebas comprueban en un instante lo que en la vida real tarda minutos, y no
quedan corrutinas sueltas cuando una sala muere.

**Los puestos que nadie ocupa los juega la IA.** Dos o tres amigos pueden jugar sin
esperar un cuarto, y es la misma maquinaria que hará falta para relevar a quien se
desconecte.

### El nombre de los demás es contenido que no controlamos

El registro de la mesa se dibuja con BBCode, así que un nombre con corchetes adentro le
cambiaría colores y texto a **todos** los otros jugadores. El servidor los quita al
entrar, recorta a 16 caracteres y pone `Jugador` si queda vacío. Se limpia en el
servidor y no en la pantalla porque es el único lugar por el que pasan todos.

### Salas que vencen

Una sala **no** se destruye al quedar vacía: se deja vencer sola a los 5 minutos, así
quien se cayó y vuelve enseguida encuentra su mesa donde estaba. Una con gente adentro
aguanta una hora, porque "sin actividad" muchas veces es que están conversando antes de
empezar. Hay un tope de 200 salas: sin él, mandar `create_room` en bucle llena la
memoria del servidor.

Lo que falta de robustez —limitar cuántas veces se puede pedir por minuto, reloj de
turno y reconexión guardando el puesto— viene con el resto de la fase de red.

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

El proyecto está en cuatro capas y ninguna se mete en la de al lado:

| Capa | Archivo | Qué hace |
|---|---|---|
| Reglas | `scripts/rules/GameState.gd` | Estado y reglas. No conoce nodos, no dibuja, no escribe en el registro y no usa `await`. |
| Autoridad | `scripts/rules/GameSession.gd` | La secuencia de una mano: repartir, aplicar, cerrar, seguir. Decide **qué** pasa y **en qué orden** se anuncia. Sin nodos ni temporizadores. |
| Reparto | `scripts/net/LocalTransport.gd` | Le pone ritmo a los turnos, mueve las tres IA y le manda todo a un solo puesto. Es lo único que cambia al pasar a red. |
| Interfaz | `scripts/Main.gd` | Dibuja, atiende al usuario y redacta los mensajes. **No conoce `GameState`.** |

Esa separación es la que permite correr las mismas reglas en el servidor dedicado, en
vez de reimplementarlas en otro lenguaje y tener dos motores que mantener
sincronizados. La frontera exacta está en `GameSession`: el servidor de salas la va a
usar tal cual, y lo único que escribe de nuevo es la capa de reparto — porque ahí sí
cambia todo (cuatro jugadores en vez de uno, un reloj de turno en vez de una pausa
para que se vea).

El reparto es **determinista por semilla** (`GameState.deal(seed)`): la misma semilla
da siempre el mismo reparto, así se puede reproducir una mano exacta para depurar, y
cuando se juegue en red el servidor será la única fuente del azar. No se usa
`Array.shuffle()` porque toma el generador global y no se puede fijar por semilla.

### Transiciones por eventos

`apply_play()` y `apply_pass()` aplican la jugada y devuelven una **lista de eventos**
que describe lo que pasó (`played`, `passed`, `bonus`, `hand_won`, `tranque`,
`rejected`…), en vez de escribir en pantalla. Esa lista viaja por el transporte hasta
`Main.gd`, que la traduce a texto, avisos y pantallas en `_handle_event()`.

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

**Nada de la interfaz llega al estado con autoridad.** Repartir, aplicar jugadas,
decidir un pase forzado y saber si la partida terminó están del otro lado del
transporte.

### El transporte: la interfaz no sabe quién decide

`Main.gd` no conoce `GameState`. Lo único que tiene es un `Transport`, y ese contrato
es corto a propósito: es la superficie del protocolo de red, y todo lo que se le
agregue hay que validarlo del lado del servidor.

| Del servidor al cliente | Del cliente al servidor |
|---|---|
| `seat_assigned(seat)` | `begin()` |
| `snapshot(pub, mine)` | `start_match(config)` |
| `events(list)` | `request_play(idx, end)` |
| `hand_started()` | `request_continue()` |
| `hand_ended(closing, reveal)` | |
| `match_ended(winner_team)` | |

Dos detalles del contrato que son de seguridad, no de estilo:

- **`request_play()` no lleva puesto.** El cliente no dice en nombre de quién juega;
  eso lo sabe la autoridad por la conexión. Es lo que impide mandar jugadas por otro.
- **No existe `request_pass()`.** En el dominó dominicano no se pasa por voluntad, se
  pasa porque no hay ficha que calce, y eso lo determina la autoridad mirando la
  mano. El pase nunca es una acción del cliente: llega como evento.

El destape de fin de mano viaja únicamente dentro de `hand_ended`, junto con el
cierre. La interfaz no lo puede pedir antes porque no tiene a quién pedírselo.

Hay dos implementaciones del mismo contrato, y la pantalla no distingue una de otra:

| | Quién decide | Ritmo | Destinatarios |
|---|---|---|---|
| `LocalTransport` | Este proceso | Pausa de 0.9 s | Uno |
| `WsClientTransport` | El servidor, al otro lado de un socket | El del servidor | Cuatro |

`WsClientTransport` es notable por lo que **no** hace: no aplica reglas, no valida
jugadas, no decide turnos, no reparte, y de las fichas ajenas no recibe ninguna.
Empaqueta lo que la pantalla pide y desempaqueta lo que baja. Modificarlo no sirve de
nada, porque el servidor no le cree nada.

Además del contrato expone la parte de **sala** —conectar, crear, entrar, elegir
silla—, que en el modo local no existe porque no hay a quién esperar. Eso lo usa la
pantalla del lobby; la de juego sigue viendo solo el contrato.

#### Dos cosas que aparecieron al conectar de verdad

**JSON tiene un solo tipo numérico.** Un puesto `2` vuelve como `2.0`, y en GDScript
indexar un arreglo con un flotante es un error — justo el uso que tienen esos números
(`SEAT_NAMES[pub.current_player]`). Se arregla en `Protocol.to_ints()`, no en la
pantalla: la pantalla no debería enterarse nunca de que el dato pasó por un cable, y
poner `int()` en cada uso son decenas de lugares donde olvidarse de uno. Vale porque en
estas vistas no hay ni un número fraccionario, y el arnés comprueba que siga siendo
cierto: si alguien agrega un campo con decimales, la prueba avisa que necesita una
excepción ahí.

**Una jugada tarda en viajar.** Entre el clic y el estado nuevo pasan cientos de
milisegundos con la mano todavía habilitada, así que un segundo clic manda una jugada
duplicada. El servidor la rechaza —eso está bien— pero el jugador ve un error que no
entiende. La pantalla apaga la mano desde que manda hasta que le contestan. Salió a la
luz en la prueba de red: mandaba 67 jugadas donde el máximo posible eran 28, y ahora la
prueba falla si se pasa de ese techo.

### Perspectiva: el jugador local siempre abajo

Los nombres de brújula son la **identidad** del puesto, no su lugar en pantalla: el
asiento 0 es Sur siempre, aunque quien esté jugando sea Norte. Lo que cambia es
desde dónde se mira la mesa.

`local_seat` dice qué puesto juega en esta pantalla, y su mano va siempre abajo. Los
otros tres se acomodan con `_screen_pos(seat) = (seat - local_seat) mod 4`:

| Posición | Quién es |
|---|---|
| Abajo | uno mismo |
| Derecha | quien juega justo después |
| Arriba | el compañero (se sientan enfrentados) |
| Izquierda | quien juega justo antes |

Sale de que el orden de turno es `0 → 1 → 2 → 3`, así que la posición 2 es siempre
la pareja. Los nodos de los paneles se llaman por posición (`top_`, `own_`, `left_`,
`right_`), no por brújula, y las bolitas de turno están indexadas por posición.

Para probarlo sin red, se puede elegir el puesto por línea de comandos:

```bash
godot -- --seat=2
```

Con eso la partida se juega desde Norte: tu mano abajo, tu compañero Sur arriba, y
Este y Oeste a los lados. El argumento es el puesto que se **pide**; el definitivo
llega siempre en `seat_assigned`, y en red lo decidirá la sala.

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

Después juega 60 partidas más **a través de `GameSession`**, con los cuatro puestos en
manos de la IA, para verificar el **orden de los anuncios**, que es contrato aparte:

- Cada acción anuncia `events` → `state_changed` → (`turn_ready` o `hand_ended`), y
  cada reparto `state_changed` → `hand_started` → `turn_ready`. Nada más y nada menos.
- El `must_pass` de `turn_ready` coincide con lo que dice la vista privada de ese
  puesto, que es otra manera de llegar al mismo dato.
- Una acción rechazada anuncia `events` y nada más: no cambió nada, así que no hay
  estado que difundir ni turno que anunciar de nuevo. En red, lo contrario significaría
  que alguien mandando jugadas inválidas en bucle hace que el servidor le difunda el
  estado a los cuatro jugadores por cada intento.
- El destape llega **solo** con `hand_ended`, y con la mano marcada como cerrada.
- `match_ended` no sale nunca con el supuesto campeón por debajo de la meta.
- El número de mano sube con cada reparto, que es lo que permite descartar una espera
  vieja cuando hay pausas o latencia.

Esa segunda pasada existe porque romper el orden **no rompe ninguna regla**: al
invertir `events` y `state_changed` a propósito, los números de la primera pasada
salen idénticos y solo falla la segunda. En pantalla se vería como un resumen dibujado
sobre la mesa vieja.

También prueba lo que **no** debe poderse: jugar fuera de turno, pasar teniendo jugada,
abrir la primera mano sin el 6-6, y pedir una punta donde la ficha no calza. Y que un
rechazo no altere el estado.

Y al final corre `ServerTest`, que prueba el lado del servidor **sin abrir ningún
puerto**. Se puede porque ni `Room` ni `RoomRegistry` saben qué es un socket (lo que
quieren mandar sale por una señal) y porque su reloj va por `tick(delta)`: una partida
entera se juega en un instante adelantando el tiempo a mano.

Lo que más importa de esa parte son las dos cosas que **solo existen en red** y que no
se pueden comprobar jugando, porque en una sola pantalla la información nunca sale del
proceso:

- **A nadie le llegan las fichas de otro.** Se juntan las cuatro manos tal como se
  mandaron y se verifica que sumen 28 sin una sola repetida: si el servidor le mandara
  la mano de alguien a los cuatro, aparecería una ficha con dos dueños.
- **Nadie puede jugar en nombre ajeno.** Una jugada fuera de turno se rechaza, no toca
  la mesa, y el rechazo le llega **solo a quien se equivocó** — al resto no le aparece
  nada.

Lo demás: el alfabeto de los códigos (que no se le cuele un cero ni una vocal), que el
sorteo use las 20 letras, que un código escrito a mano con minúsculas y guiones entre
igual, las 28 fichas de ida y vuelta por JSON de verdad, que en lo codificado no quede
ningún objeto que JSON no pueda mandar, la herencia del anfitrión cuando se va, el tope
de salas, la limpieza de los nombres, y que una sala vacía venza pronto mientras una
con gente aguanta.

Sale con código 0 si todo pasa y 1 si algo falla, así sirve tal cual en CI. Cuando algo
falla informa la semilla del reparto, para poder reproducir esa mano exacta.

### La prueba de red

Necesita un servidor escuchando, así que va aparte: un arnés que depende de otro
proceso no sirve para CI. Dos terminales:

```bash
godot --headless -- --server
```

```bash
godot --headless -- --test-net
```

Levanta **dos clientes de verdad, con sockets de verdad**, y hace lo que harían dos
personas: uno crea la sala, el otro entra con el código escrito a mano, se cambia de
silla para quedar de pareja, y juegan una **partida completa** hasta que alguien llega a
la meta, usando solo lo que les llegó. Los otros dos puestos los mueve la IA del
servidor.

La meta es 50 —el mínimo que acepta el servidor— a propósito: así la partida termina en
dos o tres manos y `match_ended` **queda probado**. Con metas altas la prueba tardaría
minutos y ese mensaje, que es el que dispara la pantalla de fin de partida, no llegaría
nunca. Al final se comprueba que la pareja ganadora de verdad haya alcanzado la meta
según el marcador que ya viajó.

Comprueba lo que ningún arnés en un solo proceso puede: que el JSON sobreviva el viaje,
que los puestos los asigne el servidor, que a cada cliente le lleguen **solo** sus
fichas, que jugar fuera de turno rebote, y que los números vuelvan como enteros. Con
`--server-url=wss://...` apunta a otro servidor, por ejemplo el desplegado.

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

`scripts/rules/DominoAI.gd`. Sencilla a propósito: entre sus jugadas legales prefiere
los dobles y, si no hay, la ficha de más puntos, para soltar las pesadas primero. No
cuenta pases ni deduce qué tiene la pareja.

Recibe **la vista privada de su puesto y nada más**, aunque corra del lado de la
autoridad: las mismas fichas y las mismas jugadas que vería una persona en esa silla.
Sin esa restricción, el reemplazo de alguien que se desconecte jugaría mejor que el
jugador al que sustituye. Tampoco decide pasar — devuelve "no tengo jugada" y el pase
lo aplica la autoridad, igual que con una persona.

Ideas para mejorarla: aprovechar la información de los pases (la guía insiste en que
"cada pase habla"), llevar cuenta de números muertos, y jugar pensando en la pareja.
