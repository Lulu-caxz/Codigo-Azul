extends Node3D

func gerar_mapa() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

	if Global.seed != 0:
		noise.seed = Global.seed
	else:
		noise.seed = randi()
		Global.seed = noise.seed

	noise.frequency = 0.1
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4

	var alturas: Array = []
	var cores: Array = []

	# 1. Calcular os dados de cada coluna.
	for x in range(Global.largura):
		var linha_alturas: Array[int] = []
		var linha_cores: Array[Color] = []

		for z in range(Global.profundidade):
			var n: float = noise.get_noise_2d(x, z)
			var normalizado: float = remap(n, -1.0, 1.0, 0.0, 1.0)

			var altura: int = clampi(
				roundi(normalizado * Global.altura_maxima),
				1,
				Global.altura_maxima
			)

			linha_alturas.append(altura)
			linha_cores.append(obter_cor(normalizado))

		alturas.append(linha_alturas)
		cores.append(linha_cores)

	# 2. Construir uma única malha.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tamanho: float = Global.tamanho_cubo

	for x in range(Global.largura):
		for z in range(Global.profundidade):
			var h: int = alturas[x][z]
			var cor: Color = cores[x][z]

			var x0: float = x * tamanho
			var x1: float = (x + 1) * tamanho
			var z0: float = z * tamanho
			var z1: float = (z + 1) * tamanho
			var y: float = h * tamanho

			# Face superior.
			quad(
				st,
				Vector3(x0, y, z0),
				Vector3(x0, y, z1),
				Vector3(x1, y, z1),
				Vector3(x1, y, z0),
				Vector3.UP,
				cor
			)

			# Oeste (-X)
			var oeste: int = alturas[x - 1][z] if x > 0 else 0
			if oeste < h:
				quad(
					st,
					Vector3(x0, oeste * tamanho, z0),
					Vector3(x0, y, z0),
					Vector3(x0, y, z1),
					Vector3(x0, oeste * tamanho, z1),
					Vector3.LEFT,
					cor
				)

			# Leste (+X)
			var leste: int = alturas[x + 1][z] if x < Global.largura - 1 else 0
			if leste < h:
				quad(
					st,
					Vector3(x1, leste * tamanho, z1),
					Vector3(x1, y, z1),
					Vector3(x1, y, z0),
					Vector3(x1, leste * tamanho, z0),
					Vector3.RIGHT,
					cor
				)

			# Norte (-Z)
			var norte: int = alturas[x][z - 1] if z > 0 else 0
			if norte < h:
				quad(
					st,
					Vector3(x1, norte * tamanho, z0),
					Vector3(x1, y, z0),
					Vector3(x0, y, z0),
					Vector3(x0, norte * tamanho, z0),
					Vector3(0, 0, -1),
					cor
				)

			# Sul (+Z)
			var sul: int = alturas[x][z + 1] if z < Global.profundidade - 1 else 0
			if sul < h:
				quad(
					st,
					Vector3(x0, sul * tamanho, z1),
					Vector3(x0, y, z1),
					Vector3(x1, y, z1),
					Vector3(x1, sul * tamanho, z1),
					Vector3(0, 0, 1),
					cor
				)

	# 3. Finalizar a malha e criar o objeto visual.
	var malha: ArrayMesh = st.commit()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Desativa o corte de faces traseiras para evitar frestas e buracos no terreno
	material.cull_mode = StandardMaterial3D.CULL_DISABLED 

	var terreno := MeshInstance3D.new()
	terreno.name = "Terreno"
	terreno.mesh = malha
	terreno.material_override = material

	add_child(terreno)

	Global.mapa = alturas


func obter_cor(n: float) -> Color:
	if n < 0.35:
		return Color.CORNFLOWER_BLUE
	elif n < 0.45:
		return Color.SANDY_BROWN
	elif n < 0.7:
		return Color.FOREST_GREEN
	else:
		return Color.DARK_GRAY


func quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	normal: Vector3,
	cor: Color
) -> void:
	var vertices: Array[Vector3] = [a, b, c, d]

	# Verifica a orientação dos vértices de forma segura.
	if (b - a).cross(c - a).dot(normal) < 0.0:
		vertices = [a, d, c, b]

	# Primeiro triângulo.
	st.set_normal(normal)
	st.set_color(cor)
	st.add_vertex(vertices[0])

	st.set_normal(normal)
	st.set_color(cor)
	st.add_vertex(vertices[1])

	st.set_normal(normal)
	st.set_color(cor)
	st.add_vertex(vertices[2])

	# Segundo triângulo.
	st.set_normal(normal)
	st.set_color(cor)
	st.add_vertex(vertices[0])

	st.set_normal(normal)
	st.set_color(cor)
	st.add_vertex(vertices[2])

	st.set_normal(normal)
	st.set_color(cor)
	st.add_vertex(vertices[3])
