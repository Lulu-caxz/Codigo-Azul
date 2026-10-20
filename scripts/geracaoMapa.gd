extends Node3D

func gerar_mapa() -> void:
	
	Global.altura_maxima *= Global.tamanho_cubo
	
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = Global.seed
	noise.frequency = 0.1
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4 
	
	var malha = BoxMesh.new()
	malha.size = Vector3(Global.tamanho_cubo, Global.tamanho_cubo, Global.tamanho_cubo)
	
	Global.mapa.resize(Global.largura)
	for x in range(Global.largura):
		Global.mapa[x] = []
		Global.mapa[x].resize(Global.profundidade)
		
	for x in range(Global.largura):
		for z in range(Global.profundidade):
			
			var raw_noise: float = noise.get_noise_2d(x, z)
			var noise_normalizado: float = remap(raw_noise, -1.0, 1.0, 0.0, 1.0)
			
			var altura_final: float = noise_normalizado * Global.altura_maxima
			
			var cubo = MeshInstance3D.new()
			cubo.mesh = malha
			
			var cor := StandardMaterial3D.new()
			if noise_normalizado < 0.35:
				cor.albedo_color = Color.CORNFLOWER_BLUE # Água
			elif noise_normalizado < 0.45:
				cor.albedo_color = Color.SANDY_BROWN     # Areia
			elif noise_normalizado < 0.7:
				cor.albedo_color = Color.FOREST_GREEN    # Grama / Floresta
			else:
				cor.albedo_color = Color.DARK_GRAY       # Montanha / Pedra
			
			cubo.set_surface_override_material(0, cor)
			
			cubo.position = Vector3(x * Global.tamanho_cubo, altura_final, z * Global.tamanho_cubo)
			
			add_child(cubo)
			
			Global.mapa[x][z] = cubo
