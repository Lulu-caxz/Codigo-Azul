class_name ObjetivoSprite
extends Node3D

## Representacao visual 3D dos objetivos no mundo.
## Inicialmente exibe o ponto simples (flutuando e emitindo sombra).
## Ao ser concluido (interacao com 'E'), o ponto desaparece e surge no chao o sprite
## correspondente ao tipo (ou um visual representativo no chao com sombra caso nao haja textura).

const COR_PADRAO := Color("ffd23f")
const CORES := {
	"radar": Color("2ec4ff"),
	"bueiro": Color("c9c9c9"),
	"pluviometro": Color("4f7dff"),
}

static var _cache_pontos: Dictionary = {}
static var _cache_chao: Dictionary = {}

var tipo: String = ""
var completo: bool = false

var _sprite_ponto: Sprite3D
var _sprite_objeto: SpriteBase3D
var _frames_objeto: SpriteFrames

var _altura_ponto: float = 0.8
var _tamanho_sprite: float = 0.8
var _offset_fase: float = 0.0
var _textura_objeto: Texture2D


func _ready() -> void:
	_offset_fase = randf() * TAU


func _process(_delta: float) -> void:
	if not completo and is_instance_valid(_sprite_ponto):
		# Flutuacao do ponto enquanto nao ativado
		var tempo := Time.get_ticks_msec() / 1000.0
		_sprite_ponto.position.y = _altura_ponto + sin(tempo * 3.0 + _offset_fase) * 0.12


## Configura o visual e propriedades fisicas/visuais do objetivo.
func configurar(p_tipo: String, textura: Texture2D, frames: SpriteFrames = null, tamanho: float = 0.8, altura: float = 0.8, _ocultar: bool = false) -> void:
	tipo = p_tipo
	_textura_objeto = textura
	_frames_objeto = frames
	_tamanho_sprite = tamanho
	_altura_ponto = altura

	_criar_sprite_ponto()
	_criar_sprite_objeto()


func _criar_sprite_ponto() -> void:
	var cor: Color = CORES.get(tipo, COR_PADRAO)
	var tex_ponto := _ponto_simples(cor)

	_sprite_ponto = Sprite3D.new()
	_sprite_ponto.name = "SpritePonto"
	_sprite_ponto.texture = tex_ponto
	_sprite_ponto.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite_ponto.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite_ponto.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite_ponto.shaded = true
	_sprite_ponto.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	_sprite_ponto.pixel_size = _tamanho_sprite / maxf(float(tex_ponto.get_width()), 1.0)
	_sprite_ponto.position = Vector3(0.0, _altura_ponto, 0.0)
	add_child(_sprite_ponto)


func _criar_sprite_objeto() -> void:
	var orientacao_chao := false
	if tipo == "bueiro" or (_textura_objeto == null and _frames_objeto == null):
		orientacao_chao = true

	if _frames_objeto != null:
		var anim := AnimatedSprite3D.new()
		anim.name = "SpriteObjeto"
		anim.visible = false
		anim.sprite_frames = _frames_objeto
		anim.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		anim.shaded = true
		anim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var anim_nome := &"default"
		if not _frames_objeto.has_animation("default") and not _frames_objeto.get_animation_names().is_empty():
			anim_nome = _frames_objeto.get_animation_names()[0]
		var tex_frame: Texture2D = _frames_objeto.get_frame_texture(anim_nome, 0)
		var frame_w := float(tex_frame.get_width()) if tex_frame != null else 32.0
		var frame_h := float(tex_frame.get_height()) if tex_frame != null else 32.0
		anim.pixel_size = _tamanho_sprite / maxf(frame_w, 1.0)
		var altura_mundo := anim.pixel_size * frame_h

		anim.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y if not orientacao_chao else BaseMaterial3D.BILLBOARD_DISABLED
		if orientacao_chao:
			anim.axis = Vector3.AXIS_Y
			anim.position = Vector3(0.0, 0.03, 0.0)
		else:
			# A base da imagem encosta no chao (pivot no centro -> sobe metade da altura).
			anim.position = Vector3(0.0, altura_mundo * 0.5, 0.0)
		if _frames_objeto.has_animation("default"):
			anim.animation = &"default"
		elif not _frames_objeto.get_animation_names().is_empty():
			anim.animation = _frames_objeto.get_animation_names()[0]
		anim.play()
		_sprite_objeto = anim
	else:
		var sprite := Sprite3D.new()
		sprite.name = "SpriteObjeto"
		sprite.visible = false
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.shaded = true
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		var tex := _textura_objeto
		if tex == null:
			var cor: Color = CORES.get(tipo, COR_PADRAO)
			tex = _textura_provisoria_chao(tipo, cor)

		sprite.texture = tex

		if orientacao_chao:
			sprite.axis = Vector3.AXIS_Y
			sprite.position = Vector3(0.0, 0.03, 0.0)
			sprite.pixel_size = (_tamanho_sprite * 1.2) / maxf(float(tex.get_width()), 1.0)
		else:
			sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sprite.pixel_size = (_tamanho_sprite * 1.1) / maxf(float(tex.get_width()), 1.0)
			var altura_mundo := sprite.pixel_size * float(tex.get_height())
			# A base da imagem encosta no chao.
			sprite.position = Vector3(0.0, altura_mundo * 0.5, 0.0)

		_sprite_objeto = sprite

	add_child(_sprite_objeto)


## Executa a transicao: o ponto some com animacao e o objeto correspondente surge.
func marcar_completo() -> void:
	if completo:
		return
	completo = true

	# Some com o ponto simples
	if is_instance_valid(_sprite_ponto):
		var tween_ponto := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween_ponto.tween_property(_sprite_ponto, "scale", _sprite_ponto.scale * 1.3, 0.1)
		tween_ponto.tween_property(_sprite_ponto, "scale", Vector3.ZERO, 0.15)
		tween_ponto.parallel().tween_property(_sprite_ponto, "modulate:a", 0.0, 0.15)
		tween_ponto.tween_callback(func():
			if is_instance_valid(_sprite_ponto):
				_sprite_ponto.visible = false
		)

	# Revela o sprite do objeto colocado
	if is_instance_valid(_sprite_objeto):
		_sprite_objeto.visible = true
		var escala_final := _sprite_objeto.scale
		_sprite_objeto.scale = Vector3.ZERO
		_sprite_objeto.modulate.a = 0.0

		var tween_obj := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween_obj.tween_interval(0.1)
		tween_obj.parallel().tween_property(_sprite_objeto, "scale", escala_final, 0.25)
		tween_obj.parallel().tween_property(_sprite_objeto, "modulate:a", 1.0, 0.2)


## Ponto simples 16x16: esferico, colorido com borda e sombra.
static func _ponto_simples(cor: Color) -> ImageTexture:
	var chave := cor.to_html()
	if _cache_pontos.has(chave):
		return _cache_pontos[chave]

	var tam := 16
	var img := Image.create_empty(tam, tam, false, Image.FORMAT_RGBA8)
	var centro := (tam - 1) * 0.5
	for x in tam:
		for y in tam:
			var d := Vector2(x - centro, y - centro).length()
			if d <= 4.8:
				img.set_pixel(x, y, cor)
			elif d <= 6.8:
				img.set_pixel(x, y, Color(0.08, 0.08, 0.1, 1.0))

	var brilho := cor.lightened(0.6)
	img.set_pixel(5, 5, brilho)
	img.set_pixel(6, 5, brilho)
	img.set_pixel(5, 6, brilho)

	var tex := ImageTexture.create_from_image(img)
	_cache_pontos[chave] = tex
	return tex


## Cria textura provisoria estilizada para colocar no chao caso ainda nao haja asset.
static func _textura_provisoria_chao(p_tipo: String, cor: Color) -> ImageTexture:
	var chave := p_tipo + "_" + cor.to_html()
	if _cache_chao.has(chave):
		return _cache_chao[chave]

	var tam := 32
	var img := Image.create_empty(tam, tam, false, Image.FORMAT_RGBA8)
	var centro := (tam - 1) * 0.5

	for x in tam:
		for y in tam:
			var d := Vector2(x - centro, y - centro).length()
			if p_tipo == "bueiro":
				# Formato de tampa de bueiro circular com grelha
				if d <= 13.5:
					var cor_grade := Color(0.18, 0.18, 0.2)
					if int(x) % 4 == 0 or int(y) % 4 == 0:
						cor_grade = Color(0.1, 0.1, 0.12)
					img.set_pixel(x, y, cor_grade)
				elif d <= 15.0:
					img.set_pixel(x, y, Color(0.35, 0.35, 0.38))
			else:
				# Base quadrada ou circular com borda e cor de identificacao
				var borda := maxf(absf(x - centro), absf(y - centro))
				if borda <= 12.0:
					img.set_pixel(x, y, cor.darkened(0.15))
					if borda <= 5.0:
						img.set_pixel(x, y, cor.lightened(0.3))
				elif borda <= 14.0:
					img.set_pixel(x, y, Color(0.12, 0.14, 0.18))

	var tex := ImageTexture.create_from_image(img)
	_cache_chao[chave] = tex
	return tex
