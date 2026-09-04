class_name TransportHandoff
extends RefCounted

## Buzón de un solo casillero para pasarle un transporte YA CONECTADO de una escena a la
## siguiente.
##
## Existe por una restricción concreta: cambiar de escena destruye el árbol entero, y con
## él cualquier nodo que colgara de la escena vieja. El lobby abre el socket, se sienta
## en una sala y espera a que arranque la partida; cuando arranca hay que llevar ese
## mismo socket a la pantalla de juego, y no se puede volver a conectar sin perder la
## silla.
##
## Una variable estática vive con el script y no con el nodo, así que sobrevive al cambio
## de escena. Es un global, con todo lo que eso implica, y por eso el casillero es uno
## solo y se vacía al retirarlo: dos partidas a la vez no tienen sentido, y un transporte
## olvidado acá sería un socket cerrado que la próxima pantalla creería vivo.
##
## Vive en su propia clase en vez de como estática de Main o de Transport para que se vea
## qué es: un mecanismo de traspaso, no parte del contrato ni de la pantalla.
static var _pending: Transport = null


## Deja el transporte para la escena siguiente. Quien llama tiene que haberlo sacado ya
## del árbol (remove_child): si sigue colgando de la escena vieja, se destruye con ella.
static func put(transport: Transport) -> void:
	_pending = transport


## Retira lo que hubiera y deja el casillero vacío. Devuelve null si no hay nada, que es
## el caso normal cuando el juego arranca en modo local.
static func take() -> Transport:
	var transport: Transport = _pending
	_pending = null
	return transport


static func has_pending() -> bool:
	return _pending != null
