class_name ObjetivoPlaceholder
extends Node3D

# Visual provisorio de um objetivo, usado enquanto nao existe cena propria do tipo.
# A origem do no fica na superficie da calcada. Contrato igual ao de uma cena real:
#   configurar(tipo: String)  e  marcar_completo()

const COR_FEIXE := Color(1.0, 0.8, 0.2, 0.30)
const COR_FEIXE_OK := Color(0.25, 0.86, 0.5, 0.12)
const COR_OK := Color("3ddc84")
const CORES := {
	"radar": Color("2ec4ff"),
	"bueiro": Color("8a8f98"),
	"pluviometro": Color("4f7dff"),
}

var _tipo := ""
var _materiais_corpo: Array[StandardMaterial3D] = []
var _mat_feixe: StandardMaterial3D
var _rotulo: Label3D


func configurar(tipo: String) -> void:
	_tipo = tipo
	for filho in get_children():
		filho.queue_free()
	_materiais_corpo.clear()

	var cor: Color = CORES.get(tipo, Color("c9c9c9"))
	match tipo:
		"radar":
			_cilindro(0.5, 0.5, 0.3, 0.15, cor)
			_cilindro(0.08, 0.08, 1.6, 1.1, cor)
			_esfera(0.35, 2.0, cor)
		"bueiro":
			_cilindro(0.65, 0.65, 0.08, 0.04, Color("3a3d42"))
			_cilindro(0.45, 0.45, 0.1, 0.05, cor)
		"pluviometro":
			_cilindro(0.18, 0.18, 1.0, 0.5, cor)
			_cilindro(0.38, 0.18, 0.3, 1.15, cor.lightened(0.3))
		_:
			_cilindro(0.3, 0.3, 0.9, 0.45, cor)

	_montar_feixe()
	_montar_rotulo()


func marcar_completo() -> void:
	for mat in _materiais_corpo:
		mat.albedo_color = COR_OK
	if _mat_feixe != null:
		_mat_feixe.albedo_color = COR_FEIXE_OK
	if _rotulo != null:
		_rotulo.text = _tipo + " (ok)"


func _cilindro(raio_topo: float, raio_base: float, altura: float, y: float, cor: Color) -> void:
	var malha := CylinderMesh.new()
	malha.top_radius = raio_topo
	malha.bottom_radius = raio_base
	malha.height = altura
	malha.radial_segments = 12
	malha.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cor
	malha.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.position = Vector3(0.0, y, 0.0)
	add_child(mi)
	_materiais_corpo.append(mat)


func _esfera(raio: float, y: float, cor: Color) -> void:
	var malha := SphereMesh.new()
	malha.radius = raio
	malha.height = raio * 2.0
	malha.radial_segments = 12
	malha.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cor
	malha.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.position = Vector3(0.0, y, 0.0)
	add_child(mi)
	_materiais_corpo.append(mat)


# Feixe de luz alto e translucido, para achar o objetivo de longe.
func _montar_feixe() -> void:
	var malha := CylinderMesh.new()
	malha.top_radius = 0.22
	malha.bottom_radius = 0.22
	malha.height = 10.0
	malha.radial_segments = 8
	malha.rings = 1
	_mat_feixe = StandardMaterial3D.new()
	_mat_feixe.albedo_color = COR_FEIXE
	_mat_feixe.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_feixe.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_feixe.cull_mode = BaseMaterial3D.CULL_DISABLED
	malha.material = _mat_feixe
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.position = Vector3(0.0, 5.0, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _montar_rotulo() -> void:
	_rotulo = Label3D.new()
	_rotulo.text = _tipo
	_rotulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_rotulo.font_size = 40
	_rotulo.pixel_size = 0.01
	_rotulo.outline_size = 10
	_rotulo.position = Vector3(0.0, 3.0, 0.0)
	add_child(_rotulo)
