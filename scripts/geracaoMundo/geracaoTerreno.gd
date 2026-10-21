extends Node3D

## Emitido quando TODOS os chunks (malha + colisao) estiverem prontos.
signal terreno_pronto

# ---------------------------------------------------------------------------
# TEXTURAS (todas opcionais). Se deixar vazio, usa uma cor solida padrao.
# Podem ter qualquer tamanho (ex: 16x16 pixel art); sao ajustadas
# automaticamente para o tamanho da primeira textura atribuida.
# ---------------------------------------------------------------------------
@export_group("Texturas (indice = tipo: 0 agua, 1 areia, 2 grama, 3 pedra)")
@export var texturas_topo: Array[Texture2D] = []
@export var texturas_lateral: Array[Texture2D] = []

# Cor usada quando a textura nao foi atribuida (um item por tipo)
var _cores_topo: Array[Color] = [
	Color.CORNFLOWER_BLUE,   # 0 agua
	Color.SANDY_BROWN,       # 1 areia
	Color.FOREST_GREEN,      # 2 grama
	Color.DARK_GRAY,         # 3 pedra
	Color("4a4a50"),         # 4 rua
	Color("8b6b4a"),         # 5 ponte
	Color("b0a898"),         # 6 calcada
	Color("a09888"),         # 7 quadra
]

@export_group("Opcoes")
@export var gerar_colisao: bool = true

@export_group("Renderizacao por Distancia")
## Esconde os chunks de terreno longe da camera.
@export var renderizar_so_proximo := true
## Distancia (unidades do mundo) ate a qual os chunks de terreno ficam visiveis.
@export_range(30.0, 800.0, 1.0) var distancia_render := 160.0
## Intervalo (segundos) entre verificacoes da posicao da camera.
@export_range(0.05, 2.0, 0.05) var intervalo_atualizacao := 0.2

const CHUNK := 32            # tamanho do chunk em blocos (16, 32, 64...)
const CAMADA_LATERAL := 4    # indice da textura lateral no Texture2DArray

const SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2DArray texturas : source_color, filter_nearest_mipmap, repeat_enable;

varying flat float camada;

void vertex() {
	camada = UV2.x;
}

void fragment() {
	ALBEDO = texture(texturas, vec3(UV, camada)).rgb;
	ROUGHNESS = 1.0;
}
"""

# Dados compartilhados (somente leitura durante as threads)
var _alturas: PackedInt32Array = PackedInt32Array()
var _tipos: PackedByteArray = PackedByteArray()
var _largura: int = 0
var _profundidade: int = 0
var _tamanho: float = 1.0
var _chunks_x: int = 0
var _resultados: Array = []

var _raiz: Node3D
var _material: ShaderMaterial

# Chunks montados: [{"mi": MeshInstance3D, "rect": Rect2}] (rect em x,z do mundo)
var _chunks_vis: Array = []
var _tempo_vis := 0.0


# Acumulador de geometria de um chunk
class DadosMalha:
	var vertices := PackedVector3Array()
	var normais := PackedVector3Array()
	var uvs := PackedVector2Array()
	var camadas := PackedVector2Array()
	var indices := PackedInt32Array()

	# Quad definido por origem + dois vetores de aresta (du, dv).
	# O sentido dos triangulos e ajustado automaticamente para que a
	# face frontal (horario no Godot) aponte para a normal informada.
	func quad(origem: Vector3, du: Vector3, dv: Vector3, normal: Vector3, w: float, h: float, camada: int) -> void:
		var base := vertices.size()
		vertices.append(origem)
		vertices.append(origem + du)
		vertices.append(origem + du + dv)
		vertices.append(origem + dv)

		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(w, 0.0))
		uvs.append(Vector2(w, h))
		uvs.append(Vector2(0.0, h))

		var c := Vector2(camada, 0.0)
		for i in 4:
			normais.append(normal)
			camadas.append(c)

		if du.cross(dv).dot(normal) > 0.0:
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
		else:
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


# ---------------------------------------------------------------------------
# API PUBLICA
# Global.mapa / Global.tipos ficam prontos ANTES do primeiro await.
# Para esperar malha + colisao:  await terreno.gerar_terreno()
# ---------------------------------------------------------------------------
func gerar_terreno() -> void:   # continua funcionando sozinho
	gerar_alturas()
	await gerar_malha()


func gerar_alturas() -> void:
	_largura = Global.largura
	_profundidade = Global.profundidade
	_tamanho = Global.tamanho_cubo
	_calcular_alturas()
	Global.mapa = _alturas
	Global.tipos = _tipos


func gerar_malha() -> void:
	_alturas = Global.mapa   # relê, já com as ruas aplicadas
	_tipos = Global.tipos
	_chunks_vis.clear()
	if _raiz:
		_raiz.queue_free()
	_raiz = Node3D.new()
	_raiz.name = "Chunks"
	add_child(_raiz)

	_material = _criar_material()

	_chunks_x = ceili(_largura / float(CHUNK))
	var chunks_z := ceili(_profundidade / float(CHUNK))
	var total := _chunks_x * chunks_z
	_resultados.clear()
	_resultados.resize(total)

	# Malhas geradas em paralelo nas threads do WorkerThreadPool
	var grupo := WorkerThreadPool.add_group_task(_gerar_chunk, total, -1, true, "Gerar terreno")
	while not WorkerThreadPool.is_group_task_completed(grupo):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(grupo)

	# Criacao dos nos precisa ser na thread principal; espalha em varios frames
	for i in total:
		_montar_chunk(_resultados[i], i)
		if i % 8 == 7:
			await get_tree().process_frame

	_resultados.clear()
	_tempo_vis = intervalo_atualizacao   # atualiza visibilidade no proximo frame
	terreno_pronto.emit()


# ---------------------------------------------------------------------------
# VISIBILIDADE POR DISTANCIA (so malha; a colisao continua ativa)
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not renderizar_so_proximo or _chunks_vis.is_empty():
		return
	_tempo_vis += delta
	if _tempo_vis < intervalo_atualizacao:
		return
	_tempo_vis = 0.0

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := to_local(cam.global_position)
	for item in _chunks_vis:
		var r: Rect2 = item["rect"]
		var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - p.z, p.z - r.end.y), 0.0)
		var mi: MeshInstance3D = item["mi"]
		mi.visible = (dx * dx + dz * dz) <= distancia_render * distancia_render


# ---------------------------------------------------------------------------
# ALTURAS (mesmo resultado do codigo original)
# ---------------------------------------------------------------------------
func _calcular_alturas() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = Global.seed if Global.seed != 0 else randi()
	if Global.seed == 0:
		Global.seed = noise.seed
	noise.frequency = 0.01
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 1

	_alturas.resize(_largura * _profundidade)
	_tipos.resize(_largura * _profundidade)

	var altura_max: int = Global.altura_maxima
	var i := 0
	for x in _largura:
		for z in _profundidade:
			var normalizado := remap(noise.get_noise_2d(x, z), -1.0, 1.0, 0.0, 1.0)
			_alturas[i] = clampi(roundi(normalizado * altura_max), 1, altura_max)
			_tipos[i] = _tipo_para(normalizado)
			i += 1


func _tipo_para(n: float) -> int:
	if n < 0.25:
		return 0   # agua
	elif n < 0.3:
		return 1   # areia
	elif n < 0.7:
		return 2   # grama
	return 2       # pedra


# ---------------------------------------------------------------------------
# MATERIAL: Texture2DArray + shader simples (1 amostra de textura por pixel)
# ---------------------------------------------------------------------------
func _criar_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("texturas", _criar_array_texturas())
	return mat


func _criar_array_texturas() -> Texture2DArray:
	var tam := 16
	var todas: Array[Texture2D] = []
	todas.append_array(texturas_topo)
	todas.append_array(texturas_lateral)
	for t in todas:
		if t:
			tam = t.get_width()
			break

	var imagens: Array[Image] = []
	for i in _cores_topo.size():
		imagens.append(_imagem(_pegar(texturas_topo, i), tam, _cores_topo[i]))
		imagens.append(_imagem(_pegar(texturas_lateral, i), tam, _cores_topo[i].darkened(0.35)))

	var arr := Texture2DArray.new()
	arr.create_from_images(imagens)
	return arr


func _pegar(lista: Array[Texture2D], i: int) -> Texture2D:
	return lista[i] if i < lista.size() else null


func _imagem(tex: Texture2D, tam: int, cor_padrao: Color) -> Image:
	var img: Image
	if tex:
		img = tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != tam or img.get_height() != tam:
			img.resize(tam, tam, Image.INTERPOLATE_NEAREST)
	else:
		img = Image.create(tam, tam, false, Image.FORMAT_RGBA8)
		img.fill(cor_padrao)
	img.generate_mipmaps()
	return img


# ---------------------------------------------------------------------------
# GERACAO DA MALHA DE UM CHUNK (roda em thread)
# ---------------------------------------------------------------------------
@warning_ignore("integer_division")
func _gerar_chunk(indice: int) -> void:
	var cx := indice % _chunks_x
	var cz := indice / _chunks_x
	var x_ini := cx * CHUNK
	var z_ini := cz * CHUNK
	var x_fim := mini(x_ini + CHUNK, _largura)
	var z_fim := mini(z_ini + CHUNK, _profundidade)
	var larg := x_fim - x_ini
	var prof := z_fim - z_ini
	var s := _tamanho
	var P := _profundidade

	var d := DadosMalha.new()

	# ---- TOPOS: greedy meshing (junta retangulos de mesma altura e tipo) ----
	var visitado := PackedByteArray()
	visitado.resize(CHUNK * CHUNK)
	for lx in larg:
		for lz in prof:
			if visitado[lx * CHUNK + lz] != 0:
				continue
			var gx := x_ini + lx
			var gz := z_ini + lz
			var i := gx * P + gz
			var h := _alturas[i]
			var t := _tipos[i]

			# expande em Z
			var dz := 1
			while lz + dz < prof \
					and visitado[lx * CHUNK + lz + dz] == 0 \
					and _alturas[i + dz] == h and _tipos[i + dz] == t:
				dz += 1

			# expande em X (linhas inteiras de largura dz)
			var dx := 1
			var ok := true
			while lx + dx < larg and ok:
				var j := (gx + dx) * P + gz
				for k in dz:
					if visitado[(lx + dx) * CHUNK + lz + k] != 0 \
							or _alturas[j + k] != h or _tipos[j + k] != t:
						ok = false
						break
				if ok:
					dx += 1

			for a in dx:
				for b in dz:
					visitado[(lx + a) * CHUNK + lz + b] = 1

			d.quad(
				Vector3(gx * s, h * s, gz * s),
				Vector3(dx * s, 0.0, 0.0),
				Vector3(0.0, 0.0, dz * s),
				Vector3.UP, dx, dz, t * 2)

	# ---- LATERAIS: so onde o vizinho e mais baixo ----
	_laterais(d, Vector2i(-1, 0), x_ini, x_fim, z_ini, z_fim)  # Oeste
	_laterais(d, Vector2i(1, 0), x_ini, x_fim, z_ini, z_fim)   # Leste
	_laterais(d, Vector2i(0, -1), x_ini, x_fim, z_ini, z_fim)  # Norte
	_laterais(d, Vector2i(0, 1), x_ini, x_fim, z_ini, z_fim)   # Sul

	# ---- Triangulos para colisao (lista simples de faces) ----
	var faces := PackedVector3Array()
	if gerar_colisao:
		faces.resize(d.indices.size())
		for k in d.indices.size():
			faces[k] = d.vertices[d.indices[k]]

	_resultados[indice] = {
		"vertices": d.vertices,
		"normais": d.normais,
		"uvs": d.uvs,
		"camadas": d.camadas,
		"indices": d.indices,
		"faces": faces,
	}


func _h(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= _largura or z >= _profundidade:
		return 0
	return _alturas[x * _profundidade + z]


func _laterais(d: DadosMalha, dir: Vector2i, x_ini: int, x_fim: int, z_ini: int, z_fim: int) -> void:
	var s := _tamanho
	var corre_em_z := dir.x != 0   # Oeste/Leste correm em Z; Norte/Sul em X
	var a_ini := x_ini if corre_em_z else z_ini
	var a_fim := x_fim if corre_em_z else z_fim
	var b_ini := z_ini if corre_em_z else x_ini
	var b_fim := z_fim if corre_em_z else x_fim
	var normal := Vector3(dir.x, 0.0, dir.y)

	for a in range(a_ini, a_fim):
		var b := b_ini
		while b < b_fim:
			var gx := a if corre_em_z else b
			var gz := b if corre_em_z else a
			var h := _h(gx, gz)
			var viz := _h(gx + dir.x, gz + dir.y)
			var t := _tipos[gx * _profundidade + gz]
			if viz >= h:
				b += 1
				continue

			# estende a parede enquanto altura e vizinho forem iguais
			var fim := b + 1
			while fim < b_fim:
				var fx := a if corre_em_z else fim
				var fz := fim if corre_em_z else a
				if _h(fx, fz) != h or _h(fx + dir.x, fz + dir.y) != viz \
						or _tipos[fx * _profundidade + fz] != t:
					break
				fim += 1

			var comp := fim - b
			var alt := h - viz
			var topo := h * s
			var origem: Vector3
			var du: Vector3
			if dir.x < 0:      # Oeste
				origem = Vector3(gx * s, topo, b * s)
				du = Vector3(0.0, 0.0, comp * s)
			elif dir.x > 0:    # Leste
				origem = Vector3((gx + 1) * s, topo, fim * s)
				du = Vector3(0.0, 0.0, -comp * s)
			elif dir.y < 0:    # Norte
				origem = Vector3(fim * s, topo, gz * s)
				du = Vector3(-comp * s, 0.0, 0.0)
			else:              # Sul
				origem = Vector3(b * s, topo, (gz + 1) * s)
				du = Vector3(comp * s, 0.0, 0.0)

			d.quad(origem, du, Vector3(0.0, -alt * s, 0.0), normal, comp, alt, t * 2 + 1)
			b = fim


# ---------------------------------------------------------------------------
# CRIACAO DOS NOS (thread principal)
# ---------------------------------------------------------------------------
@warning_ignore("integer_division")
func _montar_chunk(r: Dictionary, indice: int) -> void:
	if r["vertices"].is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = r["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = r["normais"]
	arrays[Mesh.ARRAY_TEX_UV] = r["uvs"]
	arrays[Mesh.ARRAY_TEX_UV2] = r["camadas"]
	arrays[Mesh.ARRAY_INDEX] = r["indices"]

	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = _material
	_raiz.add_child(mi)

	# registra para o corte por distancia (retangulo do chunk em x,z do mundo)
	var cx := indice % _chunks_x
	var cz := indice / _chunks_x
	var lado := CHUNK * _tamanho
	_chunks_vis.append({
		"mi": mi,
		"rect": Rect2(cx * lado, cz * lado, lado, lado),
	})

	if gerar_colisao:
		var forma := ConcavePolygonShape3D.new()
		forma.backface_collision = true
		forma.set_faces(r["faces"])
		var col := CollisionShape3D.new()
		col.shape = forma
		var corpo := StaticBody3D.new()
		corpo.add_child(col)
		_raiz.add_child(corpo)
