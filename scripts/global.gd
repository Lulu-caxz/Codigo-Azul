extends Node

var largura: int = 320
var profundidade: int = 180

var tamanho_cubo: float = 1.0
var altura_maxima: int = 5

var seed: int

var mapa: PackedInt32Array = PackedInt32Array()

# 0 = agua, 1 = areia, 2 = grama, 3 = pedra
var tipos: PackedByteArray = PackedByteArray()


func altura_em(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= largura or z >= profundidade:
		return 0
	return mapa[x * profundidade + z]


func tipo_em(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= largura or z >= profundidade:
		return 0
	return tipos[x * profundidade + z]

var salaID: String

var funcao: String
