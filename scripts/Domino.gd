class_name Domino
extends RefCounted

## Nombres en español usados para construir el nombre de archivo de cada ficha.
## El orden importa: define el valor numérico de cada palabra (Blanco = 0 ... Seis = 6).
const NAMES := ["Blanco", "Uno", "Dos", "Tres", "Cuatro", "Cinco", "Seis"]

var a: int
var b: int

func _init(x: int, y: int) -> void:
	a = x
	b = y

func is_double() -> bool:
	return a == b

func pips() -> int:
	return a + b

func has_value(v: int) -> bool:
	return a == v or b == v

## Dado un valor presente en la ficha, devuelve el otro valor.
func other(v: int) -> int:
	return b if a == v else a

## La ficha 0-0 no sigue el patrón "MayorMenor.png": es la única sin puntos, "CajaBlanca".
static func texture_path(x: int, y: int) -> String:
	if x == 0 and y == 0:
		return "res://DominoTiles/CajaBlanca.png"
	if x == y:
		return "res://DominoTiles/Doble%s.png" % NAMES[x]
	var hi: int = max(x, y)
	var lo: int = min(x, y)
	return "res://DominoTiles/%s%s.png" % [NAMES[hi], NAMES[lo]]

func texture() -> String:
	return Domino.texture_path(a, b)

func _to_string() -> String:
	return "%d-%d" % [a, b]
