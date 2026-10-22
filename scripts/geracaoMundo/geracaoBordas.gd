class_name GeracaoBordas
extends Node3D

## Preenche as bordas do mapa com mata fechada (arvores) densa ou nevoa sobre a agua.
## Altamente otimizado para maximo desempenho (FPS):
## - Agrupamento por tipo em MultiMeshInstance3D (pouquissimos draw calls).
## - Chunks espaciais grandes com culling por distancia do jogador.
## - Sombreamento rapido e descarte de pixels via alpha scissor.
## - Suporte a multiplos tipos de arvores misturados organicamente.
## - Aumento progressivo de tamanho conforme se afasta da cidade para vedar o horizonte.

@export_group("Arvores")
## Lista de texturas de arvores (todos os tipos sao sorteados e misturados de forma homogenea).
@export var texturas_arvores: Array[Texture2D] = [
]
## Faixa interna do mapa onde a floresta comeca (em blocos)
@export var largura_borda_interna: int = 2
## Extensao da floresta para fora dos limites do mapa (em blocos)
@export var extensao_externa: int = 28
## Distancia media entre arvores (quanto maior, mais leve)
@export var espacamento: float = 2.2
## Altura base da arvore mais proxima do jogador
@export var altura_arvore_base: float = 4.0
## Multiplicador de escala das arvores mais distantes (no horizonte)
@export var escala_maxima_distante: float = 3.2

@export_group("Nevoa (Agua)")
@export var textura_nevoa: Texture2D = preload("res://assets/props/nevoa.png")
@export var altura_nevoa_base: float = 4.0

@export_group("Otimizacao")
## Oculta chunks que estiverem longe da camera
@export var renderizar_so_proximo: bool = true
## Distancia maxima de visibilidade em metros
@export_range(40.0, 400.0, 5.0) var distancia_render: float = 100.0
## Margem extra para evitar ligar/desligar na fronteira
@export var histerese_render: float = 25.0
## Tamanho de cada setor/chunk de borda em metros
@export var tamanho_chunk: float = 48.0
## Intervalo em segundos entre verificacoes de distancia
@export var intervalo_verificacao: float = 0.2

var _container_chunks: Node3D
var _container_chao: Node3D
var _colisao_container: StaticBody3D

# Lista de chunks: { "no": Node3D, "centro": Vector3, "visivel": bool }
var _chunks: Array[Dictionary] = []
var _tempo_acumulado: float = 0.0

# Recursos compartilhados por tipo de arvore
var _materiais_arvores: Array[StandardMaterial3D] = []
var _meshes_arvores: Array[QuadMesh] = []
var _mat_nevoa: StandardMaterial3D
var _mesh_nevoa: QuadMesh
var _mat_chao: StandardMaterial3D


func _ready() -> void:
	_container_chao = Node3D.new()
	_container_chao.name = "ChaoBordas"
	add_child(_container_chao)

	_container_chunks = Node3D.new()
	_container_chunks.name = "ChunksBordas"
	add_child(_container_chunks)

	_colisao_container = StaticBody3D.new()
	_colisao_container.name = "ColisaoBordas"
	add_child(_colisao_container)


func _process(delta: float) -> void:
	if not renderizar_so_proximo or _chunks.is_empty():
		return

	_tempo_acumulado += delta
	if _tempo_acumulado < intervalo_verificacao:
		return
	_tempo_acumulado = 0.0

	_atualizar_visibilidade()


func _atualizar_visibilidade() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var pos := cam.global_position
	var d_on_sq := distancia_render * distancia_render
	var d_off_sq := (distancia_render + histerese_render) * (distancia_render + histerese_render)

	for c in _chunks:
		var centro: Vector3 = c["centro"]
		var dx := pos.x - centro.x
		var dz := pos.z - centro.z
		var dist_sq := dx * dx + dz * dz

		if c["visivel"]:
			if dist_sq > d_off_sq:
				c["visivel"] = false
				c["no"].visible = false
		else:
			if dist_sq <= d_on_sq:
				c["visivel"] = true
				c["no"].visible = true


func gerar_bordas() -> void:
	# Limpeza
	for ch in _container_chunks.get_children():
		ch.queue_free()
	for ch in _container_chao.get_children():
		ch.queue_free()
	for ch in _colisao_container.get_children():
		ch.queue_free()
	_chunks.clear()

	if texturas_arvores.is_empty():
		push_warning("GeracaoBordas: texturas_arvores esta vazio!")
		return

	_preparar_recursos_compartilhados()

	var larg: int = Global.largura
	var prof: int = Global.profundidade
	var s: float = Global.tamanho_cubo

	var rng := RandomNumberGenerator.new()
	rng.seed = Global.seed + 98765

	var li_x := float(largura_borda_interna) * s
	var li_z := float(largura_borda_interna) * s
	var min_x := -float(extensao_externa) * s
	var min_z := -float(extensao_externa) * s
	var map_w := float(larg) * s
	var map_d := float(prof) * s
	var max_x := (float(larg) + float(extensao_externa)) * s
	var max_z := (float(prof) + float(extensao_externa)) * s

	var prof_maxima := float(largura_borda_interna + extensao_externa) * s

	# Mapa de chunks: chave Vector2i -> { "arvores_por_tipo": Array[Array[Transform3D]], "nevoas": Array[Transform3D] }
	var num_tipos := texturas_arvores.size()
	var dados_chunks: Dictionary = {}

	# 1. Varredura com espacamento uniforme
	var z := min_z
	while z <= max_z:
		var x := min_x
		while x <= max_x:
			# Calcula a profundidade em direcao a borda externa
			var dist_x := 0.0
			if x < li_x:
				dist_x = li_x - x
			elif x > map_w - li_x:
				dist_x = x - (map_w - li_x)

			var dist_z := 0.0
			if z < li_z:
				dist_z = li_z - z
			elif z > map_d - li_z:
				dist_z = z - (map_d - li_z)

			var profundidade_borda := maxf(dist_x, dist_z)

			# So coloca se estiver dentro da faixa de floresta/borda
			if profundidade_borda > 0.0:
				var jx := x + rng.randf_range(-espacamento * 0.45, espacamento * 0.45)
				var jz := z + rng.randf_range(-espacamento * 0.45, espacamento * 0.45)

				# Amostra celula mais proxima para piso e altura
				var cx := clampi(int(jx / s), 0, larg - 1)
				var cz := clampi(int(jz / s), 0, prof - 1)
				var tipo_piso := Global.tipo_em(cx, cz)
				var alt := float(Global.altura_em(cx, cz)) * s

				# Fator de crescimento com a distancia: vai de 1.0 ate escala_maxima_distante (ex: 3.2x)
				var t_dist := clampf(profundidade_borda / maxf(prof_maxima, 1.0), 0.0, 1.0)
				var fator_crescimento := lerpf(1.0, escala_maxima_distante, t_dist)
				var escala_organica := fator_crescimento * rng.randf_range(0.88, 1.15)

				var chave_chunk := Vector2i(int(floor(jx / tamanho_chunk)), int(floor(jz / tamanho_chunk)))
				if not dados_chunks.has(chave_chunk):
					var lista_arvores_tipo: Array[Array] = []
					for _t in num_tipos:
						lista_arvores_tipo.append([])
					dados_chunks[chave_chunk] = {
						"arvores_por_tipo": lista_arvores_tipo,
						"nevoas": []
					}

				var transform_inst := Transform3D.IDENTITY.scaled(Vector3(escala_organica, escala_organica, escala_organica))

				if tipo_piso == 0:
					# Nevoa sobre a agua
					transform_inst.origin = Vector3(jx, alt + rng.randf_range(0.2, 1.4), jz)
					dados_chunks[chave_chunk]["nevoas"].append(transform_inst)
				else:
					# Arvore em terra/calcada/grama: sorteia um dos tipos disponiveis
					var tipo_sorteado := rng.randi() % num_tipos
					transform_inst.origin = Vector3(jx, alt, jz)
					dados_chunks[chave_chunk]["arvores_por_tipo"][tipo_sorteado].append(transform_inst)

			x += espacamento
		z += espacamento

	# 2. Cria os MultiMeshes por chunk (1 draw call por tipo presente)
	for chave in dados_chunks:
		var d: Dictionary = dados_chunks[chave]
		var chunk_no := Node3D.new()
		chunk_no.name = "Chunk_%d_%d" % [chave.x, chave.y]
		_container_chunks.add_child(chunk_no)

		var centro := Vector3((chave.x + 0.5) * tamanho_chunk, 0.0, (chave.y + 0.5) * tamanho_chunk)
		_chunks.append({"no": chunk_no, "centro": centro, "visivel": true})

		# MultiMeshes de arvores (um para cada tipo que tenha instâncias)
		var arvores_por_tipo: Array = d["arvores_por_tipo"]
		for t_idx in num_tipos:
			var lista_t: Array = arvores_por_tipo[t_idx]
			if not lista_t.is_empty():
				_instanciar_multimesh(chunk_no, _meshes_arvores[t_idx], _materiais_arvores[t_idx], lista_t)

		# MultiMesh de nevoa
		var nevoas: Array = d["nevoas"]
		if not nevoas.is_empty():
			_instanciar_multimesh(chunk_no, _mesh_nevoa, _mat_nevoa, nevoas)

	# 3. Chao estendido contiguo (placas estaticas grandes e leves que cobrem o void)
	_criar_chao_estendido(larg, prof, s)

	# 4. Barreira de colisao invisivel
	_gerar_colisoes_barreira(larg, prof, s, li_x, li_z)

	# 5. Primeira passada de culling
	if renderizar_so_proximo:
		for c in _chunks:
			c["no"].visible = false
			c["visivel"] = false
		_atualizar_visibilidade()


func _preparar_recursos_compartilhados() -> void:
	_materiais_arvores.clear()
	_meshes_arvores.clear()

	for tex in texturas_arvores:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Shading per-vertex e muito mais rapido que per-pixel para vegetacao
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_materiais_arvores.append(mat)

		var aspect := 1.0
		if tex:
			aspect = maxf(float(tex.get_width()) / maxf(float(tex.get_height()), 1.0), 0.2)

		var qm := QuadMesh.new()
		qm.size = Vector2(altura_arvore_base * aspect, altura_arvore_base)
		qm.center_offset = Vector3(0.0, altura_arvore_base * 0.5, 0.0)
		_meshes_arvores.append(qm)

	# Nevoa
	_mat_nevoa = StandardMaterial3D.new()
	_mat_nevoa.albedo_texture = textura_nevoa
	_mat_nevoa.albedo_color = Color(0.85, 0.9, 0.95, 0.7)
	_mat_nevoa.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_nevoa.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_mat_nevoa.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_nevoa.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_nevoa.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mesh_nevoa = QuadMesh.new()
	_mesh_nevoa.size = Vector2(altura_nevoa_base * 1.6, altura_nevoa_base)

	# Chao estendido
	_mat_chao = StandardMaterial3D.new()
	_mat_chao.albedo_color = Color(0.15, 0.26, 0.18)
	_mat_chao.roughness = 0.95


func _instanciar_multimesh(parent: Node3D, mesh: Mesh, mat: Material, transforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()

	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	# Desligar sombra nas arvores de borda economiza metade dos passes da GPU (ganho massivo de FPS)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _criar_chao_estendido(larg: int, prof: int, s: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ext_m := float(extensao_externa + 40) * s
	var w := float(larg) * s
	var d := float(prof) * s
	var alt := 0.0

	# 4 faixas principais que cobrem todas as bordas
	_quad(st, Vector3(-ext_m, alt, -ext_m), Vector3(w + ext_m, alt, -ext_m), Vector3(w + ext_m, alt, 0.0), Vector3(-ext_m, alt, 0.0))
	_quad(st, Vector3(-ext_m, alt, d), Vector3(w + ext_m, alt, d), Vector3(w + ext_m, alt, d + ext_m), Vector3(-ext_m, alt, d + ext_m))
	_quad(st, Vector3(-ext_m, alt, 0.0), Vector3(0.0, alt, 0.0), Vector3(0.0, alt, d), Vector3(-ext_m, alt, d))
	_quad(st, Vector3(w, alt, 0.0), Vector3(w + ext_m, alt, 0.0), Vector3(w + ext_m, alt, d), Vector3(w, alt, d))

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "PlanoChaoBordas"
	mi.mesh = st.commit()
	mi.material_override = _mat_chao
	_container_chao.add_child(mi)


func _quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p3)

	st.add_vertex(p1)
	st.add_vertex(p3)
	st.add_vertex(p4)


func _gerar_colisoes_barreira(larg: int, prof: int, s: float, bx: float, bz: float) -> void:
	var total_w := float(larg) * s
	var total_d := float(prof) * s
	var alt := 25.0

	_criar_caixa_colisao(Vector3(total_w * 0.5, 0.0, bz * 0.5), Vector3(total_w, alt, bz))
	_criar_caixa_colisao(Vector3(total_w * 0.5, 0.0, total_d - bz * 0.5), Vector3(total_w, alt, bz))
	_criar_caixa_colisao(Vector3(bx * 0.5, 0.0, total_d * 0.5), Vector3(bx, alt, total_d))
	_criar_caixa_colisao(Vector3(total_w - bx * 0.5, 0.0, total_d * 0.5), Vector3(bx, alt, total_d))


func _criar_caixa_colisao(pos: Vector3, tam: Vector3) -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = tam
	col.shape = box
	col.position = pos
	_colisao_container.add_child(col)
