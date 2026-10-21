shader_type canvas_item;

// ============================================================
//  SONAR / RADAR MELHORADO
//  - Ondas de pulso múltiplas com decaimento (fade) conforme se afastam
//  - Varredura rotativa com rastro (cauda) longo e suave
//  - "Ping": partes do mapa só ficam visíveis/brilhantes quando
//    atingidas pela onda ou pela varredura, e depois esmaecem
//  - Detecção de bordas do mapa (contornos acendem quando varridos)
//  - Grade polar com anéis de distância e marcações de ângulo
//  - Scanlines, vinheta e leve aberração cromática
// ============================================================

uniform vec4 cor_sonar : source_color = vec4(0.1, 1.0, 0.15, 1.0);
uniform vec2 centro = vec2(0.5, 0.5);
uniform float proporcao = 1.77778;

// --- Ondas de pulso ---
uniform float velocidade : hint_range(0.01, 1.0) = 0.1;
uniform float espessura : hint_range(0.002, 0.05) = 0.005;
uniform float intensidade : hint_range(0.0, 3.0) = 0.2;
uniform float brilho : hint_range(0.0, 2.0) = 0.1;
uniform int quantidade_ondas : hint_range(1, 5) = 2;
uniform float espacamento_ondas : hint_range(0.05, 0.6) = 0.5;

// --- Varredura rotativa ---
uniform float velocidade_varredura : hint_range(0.1, 3.0) = 0.2;
uniform float tamanho_rastro : hint_range(0.5, 8.0) = 0.5;
uniform float intensidade_facho : hint_range(0.0, 1.0) = 0.1;

// --- Mapa / visibilidade ---
// 0 = mapa sempre visível, 1 = mapa só aparece quando varrido
uniform float modo_ping : hint_range(0.0, 1.0) = 0.1;
uniform float visibilidade_minima : hint_range(0.0, 1.0) = 0.1;
uniform float tonalidade_verde : hint_range(0.0, 1.0) = 0.1;
uniform float forca_bordas : hint_range(0.0, 3.0) = 0.1;

// --- Grade ---
uniform float intensidade_grade : hint_range(0.0, 1.0) = 0.1;
uniform float aneis_grade : hint_range(2.0, 24.0) = 8.0;
uniform float divisoes_angulares : hint_range(4.0, 48.0) = 24.0;

// --- Pós-processamento ---
uniform float scanlines : hint_range(0.0, 1.0) = 0.05;
uniform float vinheta : hint_range(0.0, 1.0) = 0.2;
uniform float aberracao : hint_range(0.0, 0.01) = 0.0012;
uniform float ruido : hint_range(0.0, 0.2) = 0.03;



float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Diferença angular com sinal, no intervalo [-PI, PI]
float diff_angular(float a, float b) {
    return atan(sin(a - b), cos(a - b));
}

// Pulso em forma de anel com halo, retorna x = anel, y = halo
vec2 anel_pulso(float dist, float raio, float esp) {
    float d = abs(dist - raio);
    float anel = 1.0 - smoothstep(esp * 0.35, esp * 2.2, d);
    float halo = exp(-d / (esp * 6.0));
    return vec2(anel, halo);
}

void fragment() {
    vec2 uv = UV;

    // Aberração cromática radial leve
    vec2 dir_c = (uv - centro);
    float r_tex = texture(TEXTURE, uv + dir_c * aberracao * 8.0).r;
    float g_tex = texture(TEXTURE, uv).g;
    float b_tex = texture(TEXTURE, uv - dir_c * aberracao * 8.0).b;
    vec4 mapa_c = texture(TEXTURE, uv);
    vec3 mapa = vec3(r_tex, g_tex, b_tex);

    vec2 pos = (uv - centro) * vec2(proporcao, 1.0);
    float distancia = length(pos);
    float angulo = atan(pos.y, pos.x);

    float raio_maximo = length(vec2(
        proporcao * max(centro.x, 1.0 - centro.x),
        max(centro.y, 1.0 - centro.y)
    ));
    float dist_norm = clamp(distancia / raio_maximo, 0.0, 1.0);

    // ------------------------------------------------------------
    // Detecção de bordas do mapa (Sobel simplificado)
    // ------------------------------------------------------------
    vec2 px = TEXTURE_PIXEL_SIZE;
    float l00 = dot(texture(TEXTURE, uv + px * vec2(-1.0, -1.0)).rgb, vec3(0.333));
    float l10 = dot(texture(TEXTURE, uv + px * vec2( 0.0, -1.0)).rgb, vec3(0.333));
    float l20 = dot(texture(TEXTURE, uv + px * vec2( 1.0, -1.0)).rgb, vec3(0.333));
    float l01 = dot(texture(TEXTURE, uv + px * vec2(-1.0,  0.0)).rgb, vec3(0.333));
    float l21 = dot(texture(TEXTURE, uv + px * vec2( 1.0,  0.0)).rgb, vec3(0.333));
    float l02 = dot(texture(TEXTURE, uv + px * vec2(-1.0,  1.0)).rgb, vec3(0.333));
    float l12 = dot(texture(TEXTURE, uv + px * vec2( 0.0,  1.0)).rgb, vec3(0.333));
    float l22 = dot(texture(TEXTURE, uv + px * vec2( 1.0,  1.0)).rgb, vec3(0.333));
    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    float bordas = clamp(length(vec2(gx, gy)) * 3.0, 0.0, 1.0);

    // ------------------------------------------------------------
    // Ondas de pulso múltiplas, cada uma mais fraca que a anterior
    // ------------------------------------------------------------
    float t = TIME * velocidade;
    float soma_anel = 0.0;
    float soma_halo = 0.0;
    float soma_ping = 0.0; // quanto o pixel foi "iluminado" por ondas

    for (int i = 0; i < 5; i++) {
        if (i >= quantidade_ondas) break;
        float fi = float(i);
        float fase = t - fi * raio_maximo * espacamento_ondas;
        float raio = mod(fase, raio_maximo);
        float vida = raio / raio_maximo;               // 0 -> 1
        float fade = (1.0 - vida) * (1.0 - vida);      // some ao se afastar
        float peso = fade * (1.0 - fi * 0.25);

        vec2 a = anel_pulso(distancia, raio, espessura);
        soma_anel += a.x * peso;
        soma_halo += a.y * peso;

        // Região logo atrás da frente de onda continua "revelada"
        float atras = raio - distancia;
        float cauda = (atras > 0.0) ? exp(-atras / (raio_maximo * 0.12)) : 0.0;
        soma_ping += cauda * peso * a.y;
    }

    // ------------------------------------------------------------
    // Varredura rotativa com rastro
    // ------------------------------------------------------------
    float ang_facho = mod(TIME * velocidade_varredura, TAU) - PI;
    float da = diff_angular(angulo, ang_facho);
    // da > 0 => pixel está "à frente" do feixe; < 0 => atrás (rastro)
    float atras_ang = -da;
    float rastro = (atras_ang > 0.0)
        ? exp(-atras_ang * tamanho_rastro)
        : 0.0;
    float linha_facho = exp(-abs(da) * 90.0);
    float dentro = step(distancia, raio_maximo);
    // O feixe perde força nas bordas do alcance
    float alcance = 1.0 - smoothstep(0.85, 1.0, dist_norm);
    float facho = (rastro * 0.85 + linha_facho * 1.4) * dentro * alcance;

    // ------------------------------------------------------------
    // Visibilidade do mapa ("ping")
    // ------------------------------------------------------------
    float iluminacao = clamp(soma_ping * 1.4 + rastro * 0.9 * alcance + linha_facho, 0.0, 1.0);
    float visivel = mix(1.0, mix(visibilidade_minima, 1.0, iluminacao), modo_ping);

    // Cor base do mapa tingida de verde
    float lum = dot(mapa, vec3(0.299, 0.587, 0.114));
    vec3 mapa_verde = cor_sonar.rgb * (0.25 + lum * 0.9);
    vec3 base = mix(mapa, mapa_verde, tonalidade_verde);
    base *= visivel;

    vec3 resultado = base;

    // ------------------------------------------------------------
    // Contornos que acendem quando atingidos
    // ------------------------------------------------------------
    float acende_borda = bordas * forca_bordas * (0.25 + iluminacao * 1.2);
    resultado += cor_sonar.rgb * acende_borda * 0.55;

    // ------------------------------------------------------------
    // Grade polar
    // ------------------------------------------------------------
    float gr = abs(fract(dist_norm * aneis_grade) - 0.5);
    float aneis = 1.0 - smoothstep(0.47, 0.5, gr);
    // anel externo e a cada 4 anéis mais forte
    float idx_anel = floor(dist_norm * aneis_grade);
    float anel_forte = (mod(idx_anel, 4.0) < 0.5) ? 1.0 : 0.6;

    float ga = abs(sin(angulo * divisoes_angulares * 0.5));
    float raios = 1.0 - smoothstep(0.0, 0.02, ga);
    raios *= smoothstep(0.02, 0.06, dist_norm) * dentro;

    // Marcações finas nos anéis (tipo régua)
    float marc = abs(sin(angulo * divisoes_angulares * 2.5));
    float ticks = (1.0 - smoothstep(0.0, 0.05, marc)) * aneis * 0.6;

    float grade = max(aneis * anel_forte, raios * 0.7) + ticks;
    // grade mais visível perto do feixe
    grade *= 0.55 + iluminacao * 0.9;
    resultado = mix(resultado, cor_sonar.rgb, clamp(grade * intensidade_grade, 0.0, 1.0));

    // Cruz central
    float cruz = max(
        1.0 - smoothstep(0.0, 0.0015, abs(pos.x)),
        1.0 - smoothstep(0.0, 0.0015, abs(pos.y))
    ) * (1.0 - smoothstep(0.0, 0.04, distancia - 0.015));
    resultado = mix(resultado * 0.5, cor_sonar.rgb, cruz * 0.01);

    // ------------------------------------------------------------
    // Brilho do feixe e das ondas
    // ------------------------------------------------------------
    resultado = mix(resultado, cor_sonar.rgb, clamp(facho * intensidade_facho, 0.0, 1.0));
    resultado += cor_sonar.rgb * facho * intensidade_facho * 0.25;

    float efeito = clamp(
        soma_anel * intensidade + soma_halo * brilho,
        0.0, 1.0
    );
    resultado = mix(resultado, cor_sonar.rgb, efeito * 0.7);
    resultado += cor_sonar.rgb * soma_anel * 0.25;

    // Pulso no centro (origem do sonar)
    float pulso = 0.5 + 0.5 * sin(TIME * 4.0);
    float ponto = exp(-distancia * 120.0);
    float ponto_halo = exp(-distancia * 22.0) * (0.15 + 0.15 * pulso);
    resultado += cor_sonar.rgb * (ponto * 1.5 + ponto_halo);

    // ------------------------------------------------------------
    // Pós-processamento
    // ------------------------------------------------------------
    // Scanlines
    float sl = 0.5 + 0.5 * sin(uv.y / max(TEXTURE_PIXEL_SIZE.y, 0.0001) * PI);
    resultado *= 1.0 - scanlines * (1.0 - sl);

    // Ruído sutil animado
    float n = hash(uv * vec2(1000.0, 1000.0) + fract(TIME) * 37.0);
    resultado += (n - 0.5) * ruido;

    // Vinheta
    float vig = smoothstep(0.35, 1.05, length((uv - 0.5) * vec2(1.0, 1.0)) * 1.25);
    resultado *= 1.0 - vig * vinheta;

    COLOR = vec4(max(resultado, vec3(0.0)), mapa_c.a);
}
