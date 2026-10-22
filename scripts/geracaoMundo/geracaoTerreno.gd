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

@export_group("Agua")
@export var cor_agua_funda := Color("2e6ed1")
@export var cor_agua_linha := Color("6cb2ee")
## Quantos "pixels" da agua cabem em 1 bloco (combine com a resolucao das suas texturas, ex: 16).
@export var pixels_por_bloco := 8.0
## Tamanho das manchas: menor = manchas maiores.
@export var escala_agua := 0.05
## Velocidade da correnteza.
@export var velocidade_agua := 0.02
## Quadros por segundo da animacao (baixo = efeito retro).
@export var fps_agua := 6.0
## Espessura das linhas (0.02 fino, 0.05 grosso).
@export_range(0.005, 0.1, 0.005) var espessura_linha := 0.03
## Quanto a superficie da agua fica abaixo do topo do bloco (0.25 = 75% de bloco).
@export_range(0.0, 0.9, 0.05) var rebaixo_agua := 0.25
@export var cor_espuma := Color("eaf6ff")
## Largura da faixa de espuma, em blocos.
@export_range(0.05, 1.5, 0.05) var largura_espuma := 0.45

@export_group("Renderizacao por Distancia")
## Esconde os chunks de terreno longe da camera.
@export var renderizar_so_proximo := true
## Distancia (unidades do mundo) ate a qual os chunks de terreno ficam visiveis.
@export_range(30.0, 800.0, 1.0) var distancia_render := 160.0
## Intervalo (segundos) entre verificacoes da posicao da camera.
@export_range(0.05, 2.0, 0.05) var intervalo_atualizacao := 0.2

const DIST_COSTA := 4.0   # distancia maxima (em blocos) guardada no mapa da costa
const CHUNK := 32
const CAMADA_LATERAL := 4

const SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2DArray texturas : source_color, filter_nearest_mipmap, repeat_enable;

uniform sampler2D ruido_agua : filter_linear, repeat_enable;
uniform sampler2D mapa_costa : filter_linear, repeat_disable;
uniform vec2 tam_mapa = vec2(320.0, 180.0);
uniform float dist_max = 4.0;

uniform vec3 cor_funda : source_color = vec3(0.18, 0.43, 0.82);
uniform vec3 cor_linha : source_color = vec3(0.42, 0.70, 0.93);
uniform vec3 cor_espuma : source_color = vec3(0.92, 0.96, 1.0);
uniform float largura_espuma = 0.45;
uniform float pixels_por_bloco = 8.0;
uniform float escala_agua = 0.05;
uniform float velocidade_agua = 0.02;
uniform float fps_agua = 6.0;
uniform float nivel_a = 0.5;
uniform float nivel_b = 0.68;
uniform float espessura = 0.03;

varying flat float camada;
varying vec3 pos_mundo;

void vertex() {
	camada = UV2.x;
	pos_mundo = VERTEX;   // coordenadas locais do terreno (casam com o mapa_costa)
}

void fragment() {
	if (camada < 0.5) {
		vec2 p = (floor(pos_mundo.xz * pixels_por_bloco) + 0.5) / pixels_por_bloco;
		float te = floor(TIME * fps_agua) / fps_agua;
		float t = te * velocidade_agua;

		vec2 uv = p * escala_agua;
		float n1 = textureLod(ruido_agua, uv + vec2(t, t * 0.6), 0.0).r;
		float n2 = textureLod(ruido_agua, uv * 1.7 + vec2(-t * 0.8, t * 0.5), 0.0).r;
		float n = clamp(((n1 + n2) * 0.5 - 0.5) * 1.6 + 0.5, 0.0, 1.0);

		float linha = max(step(abs(n - nivel_a), espessura), step(abs(n - nivel_b), espessura));
		vec3 cor = mix(cor_funda, cor_linha, linha);

		// ESPUMA: distancia (em blocos) ate a margem mais proxima
		float d_borda = textureLod(mapa_costa, p / tam_mapa, 0.0).r * dist_max - 0.5;
		float onda = (n - 0.5) * 0.5 + 0.25 * sin(te * 1.6 + (p.x + p.y) * 0.5);
		float limite = largura_espuma * (1.0 + onda);
		float espuma = step(d_borda, limite);
		float anel = step(abs(d_borda - (limite + 0.35 + 0.15 * sin(te * 1.2))), 0.08);
		cor = mix(cor, cor_espuma, max(espuma, anel * 0.6));

		ALBEDO = cor;
	} else {
		ALBEDO = texture(texturas, vec3(UV, camada)).rgb;
	}
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
	# Nivel unico para toda a agua (sem degraus nem buracos dentro dos lagos)
	var nivel_agua := clampi(roundi(altura_max * 0.25 - 0.01), 1, altura_max)
	var i := 0
	for x in _largura:
		for z in _profundidade:
			var normalizado := remap(noise.get_noise_2d(x, z), -1.0, 1.0, 0.0, 1.0)
			var tipo := _tipo_para(normalizado)
			_tipos[i] = tipo
			if tipo == 0:
				_alturas[i] = nivel_agua
			else:
				_alturas[i] = clampi(roundi(normalizado * altura_max), 1, altura_max)
			i += 1


func _tipo_para(n: float) -> int:
	if n < 0.25:
		return 0   # agua
	elif n < 0.3:
		return 1   # areia
	elif n < 0.7:
		return 2   # grama
	return 2       # pedra

# Textura R8 (1 pixel por celula): distancia ate o bloco nao-agua mais proximo
func _criar_textura_costa() -> ImageTexture:
	var L := _largura
	var P := _profundidade
	var d := PackedFloat32Array()
	d.resize(L * P)
	for i in L * P:
		d[i] = 0.0 if _tipos[i] != 0 else 99.0

	# transformada de distancia em duas passadas
	for x in L:
		for z in P:
			var i := x * P + z
			var v := d[i]
			if x > 0:
				v = minf(v, d[i - P] + 1.0)
				if z > 0:
					v = minf(v, d[i - P - 1] + 1.414)
				if z < P - 1:
					v = minf(v, d[i - P + 1] + 1.414)
			if z > 0:
				v = minf(v, d[i - 1] + 1.0)
			d[i] = v
	for x in range(L - 1, -1, -1):
		for z in range(P - 1, -1, -1):
			var i := x * P + z
			var v := d[i]
			if x < L - 1:
				v = minf(v, d[i + P] + 1.0)
				if z < P - 1:
					v = minf(v, d[i + P + 1] + 1.414)
				if z > 0:
					v = minf(v, d[i + P - 1] + 1.414)
			if z < P - 1:
				v = minf(v, d[i + 1] + 1.0)
			d[i] = v

	# imagem: largura = X, altura = Z
	var bytes := PackedByteArray()
	bytes.resize(L * P)
	for x in L:
		for z in P:
			bytes[z * L + x] = int(clampf(d[x * P + z] / DIST_COSTA, 0.0, 1.0) * 255.0)

	var img := Image.create_from_data(L, P, false, Image.FORMAT_R8, bytes)
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------
# MATERIAL: Texture2DArray + shader simples (1 amostra de textura por pixel)
# ---------------------------------------------------------------------------
func _criar_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("texturas", _criar_array_texturas())
	mat.set_shader_parameter("ruido_agua", _criar_textura_ruido())
	mat.set_shader_parameter("cor_funda", cor_agua_funda)
	mat.set_shader_parameter("cor_linha", cor_agua_linha)
	mat.set_shader_parameter("pixels_por_bloco", pixels_por_bloco)
	mat.set_shader_parameter("escala_agua", escala_agua)
	mat.set_shader_parameter("velocidade_agua", velocidade_agua)
	mat.set_shader_parameter("fps_agua", fps_agua)
	mat.set_shader_parameter("espessura", espessura_linha)
	mat.set_shader_parameter("mapa_costa", _criar_textura_costa())
	mat.set_shader_parameter("tam_mapa", Vector2(_largura * _tamanho, _profundidade * _tamanho))
	mat.set_shader_parameter("dist_max", DIST_COSTA)
	mat.set_shader_parameter("cor_espuma", cor_espuma)
	mat.set_shader_parameter("largura_espuma", largura_espuma)
	return mat


# Perlin sem emendas (tileable), gerado uma vez
func _criar_textura_ruido() -> ImageTexture:
	var ruido := FastNoiseLite.new()
	ruido.noise_type = FastNoiseLite.TYPE_PERLIN
	ruido.fractal_type = FastNoiseLite.FRACTAL_FBM
	ruido.fractal_octaves = 3
	ruido.frequency = 0.015
	ruido.seed = Global.seed
	var img := ruido.get_seamless_image(256, 256)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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

			var y_topo := (h - rebaixo_agua) * s if t == 0 else h * s
			d.quad(
				Vector3(gx * s, y_topo, gz * s),
				Vector3(dx * s, 0.0, 0.0),
				Vector3(0.0, 0.0, dz * s),
				Vector3.UP, dx, dz, t * 2)

	# ---- LATERAIS: so onde o vizinho e mais baixo ----
	_laterais(d, Vector2i(-1, 0), x_ini, x_fim, z_ini, z_fim)  # Oeste
	_laterais(d, Vector2i(1, 0), x_ini, x_fim, z_ini, z_fim)   # Leste
	_laterais(d, Vector2i(0, -1), x_ini, x_fim, z_ini, z_fim)  # Norte
	_laterais(d, Vector2i(0, 1), x_ini, x_fim, z_ini, z_fim)   # Sul

	# ---- Barreiras invisiveis entre agua e outros blocos ----
	var barreiras_pos := PackedVector3Array()
	var barreiras_tipo := PackedInt32Array()
	for lx in larg:
		for lz in prof:
			var gx := x_ini + lx
			var gz := z_ini + lz
			var i := gx * P + gz
			var t := _tipos[i]
			var eh_agua := t == 0
			if gx + 1 < _largura:
				var t2 := _tipos[(gx + 1) * P + gz]
				if eh_agua != (t2 == 0):
					barreiras_pos.append(Vector3((gx + 1) * s, 0.0, (gz + 0.5) * s))
					barreiras_tipo.append(0)
			if gz + 1 < _profundidade:
				var t2 := _tipos[gx * P + (gz + 1)]
				if eh_agua != (t2 == 0):
					barreiras_pos.append(Vector3((gx + 0.5) * s, 0.0, (gz + 1) * s))
					barreiras_tipo.append(1)

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
		"barreiras_pos": barreiras_pos,
		"barreiras_tipo": barreiras_tipo,
	}

# Altura "efetiva" da superficie: a agua fica rebaixada
func _hef(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= _largura or z >= _profundidade:
		return 0.0
	var i := x * _profundidade + z
	if _tipos[i] == 0:
		return _alturas[i] - rebaixo_agua
	return float(_alturas[i])

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
			var h := _hef(gx, gz)
			var viz := _hef(gx + dir.x, gz + dir.y)
			var t := _tipos[gx * _profundidade + gz]
			if viz >= h:
				b += 1
				continue

			# estende a parede enquanto altura e vizinho forem iguais
			var fim := b + 1
			while fim < b_fim:
				var fx := a if corre_em_z else fim
				var fz := fim if corre_em_z else a
				if _hef(fx, fz) != h or _hef(fx + dir.x, fz + dir.y) != viz \
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

		# Barreiras invisiveis entre agua e outros blocos.
		var barreiras_pos: PackedVector3Array = r.get("barreiras_pos", PackedVector3Array())
		var barreiras_tipo: PackedInt32Array = r.get("barreiras_tipo", PackedInt32Array())
		if barreiras_pos.size() > 0:
			var corpo_bar := StaticBody3D.new()
			corpo_bar.name = "BarreiraAgua"
			for k in barreiras_pos.size():
				var col_bar := CollisionShape3D.new()
				var box := BoxShape3D.new()
				if barreiras_tipo[k] == 0:
					box.size = Vector3(0.2, 1000.0, _tamanho)
				else:
					box.size = Vector3(_tamanho, 1000.0, 0.2)
				col_bar.shape = box
				col_bar.position = barreiras_pos[k] + Vector3(0.0, 500.0, 0.0)
				corpo_bar.add_child(col_bar)
			_raiz.add_child(corpo_bar)
