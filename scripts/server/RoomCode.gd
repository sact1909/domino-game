class_name RoomCode
extends RefCounted

## Códigos de sala: lo que una persona le pasa a otra por mensaje o dictándolo.
##
## El alfabeto está elegido para que no haya manera de equivocarse al leerlo:
##
## - Sin 0/O ni 1/I/L. Son las confusiones clásicas al teclear un código ajeno.
## - Solo letras. Mezclar letras y números obliga a aclarar si es la B o el 8, la S o
##   el 5, cada vez que alguien lo dicta.
## - Sin vocales. Con vocales, cinco caracteres al azar tarde o temprano forman una
##   palabra, y algunas no se le mandan a nadie. Sin ellas es imposible.
##
## Quedan 20 letras. Con cinco caracteres son 3.2 millones de códigos, muchísimo más
## de los que van a existir a la vez, así que las colisiones son rarísimas y el
## registro las resuelve reintentando.
##
## El precio es que el código se ve feo y no se puede pronunciar como palabra. Vale la
## pena: se comparte copiando y pegando mucho más de lo que se dicta, y un código que
## se teclea mal es un jugador que no entra.
const ALPHABET := "BCDFGHJKMNPQRSTVWXYZ"
const LENGTH := 5


static func generate(rng: RandomNumberGenerator) -> String:
	var out: String = ""
	for i in range(LENGTH):
		out += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return out


## Deja el código como lo espera el registro. La gente lo escribe en minúscula, lo
## pega con espacios de sobra o le mete guiones para leerlo mejor: nada de eso debería
## impedirle entrar a la sala.
static func normalize(raw: String) -> String:
	var out: String = ""
	for ch in raw.to_upper():
		if ALPHABET.contains(ch):
			out += ch
	return out


static func is_valid(code: String) -> bool:
	if code.length() != LENGTH:
		return false
	for ch in code:
		if not ALPHABET.contains(ch):
			return false
	return true
