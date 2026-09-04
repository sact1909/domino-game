class_name DominoAI
extends RefCounted

## Jugador automático.
##
## Recibe la VISTA PRIVADA de un puesto y nada más: las mismas fichas y las mismas
## jugadas posibles que vería una persona sentada en esa silla. Aunque corra del lado
## de la autoridad, no puede mirar las manos ajenas ni el estado completo — y eso
## importa para cuando tenga que relevar a alguien que se desconecte, porque de lo
## contrario el reemplazo jugaría mejor que el jugador al que sustituye.
##
## Sencilla a propósito: suelta primero los dobles y, entre fichas parecidas, la de
## más puntos, que es lo que haría cualquiera para no quedarse con peso muerto. No
## cuenta pases ni deduce qué tiene la pareja.

## La jugada elegida como {"idx": n, "end": "L"|"R"}, o un diccionario VACÍO si no hay
## ninguna posible. En ese caso al puesto le toca pasar, y el pase lo aplica la
## autoridad: la IA no decide pasar, igual que no lo decide una persona.
static func choose(view: Dictionary) -> Dictionary:
	var moves: Array = view.legal_moves
	if moves.is_empty():
		return {}

	var hand: Array = view.tiles
	var best: Dictionary = moves[0]
	for m in moves:
		var t: Domino = hand[m.idx]
		var bt: Domino = hand[best.idx]
		if t.is_double() and not bt.is_double():
			best = m
		elif t.is_double() == bt.is_double() and t.pips() > bt.pips():
			best = m

	# Si la ficha calza en las dos puntas, cualquiera sirve para las reglas: se elige
	# al azar para que la IA no sea predecible en algo que no le cuesta nada.
	var ends: Array = best.ends
	var chosen_end: String = str(ends[0])
	if ends.size() > 1:
		chosen_end = str(ends[randi() % ends.size()])
	return {"idx": int(best.idx), "end": chosen_end}
