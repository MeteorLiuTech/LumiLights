#include lumi:shaders/post/common/header.glsl
#include frex:shaders/lib/math.glsl
#include frex:shaders/lib/color.glsl
#include frex:shaders/api/world.glsl
#include lumi:shaders/func/tile_noise.glsl
#include lumi:shaders/func/tonemap.glsl
#include lumi:shaders/lib/util.glsl
#include lumi:shaders/lib/fast_gaussian_blur.glsl
#include lumi:shaders/common/userconfig.glsl
#include lumi:shaders/post/common/clouds.glsl

/******************************************************
  lumi:shaders/post/composite.frag
******************************************************/

uniform sampler2D u_combine_solid;
uniform sampler2D u_solid_depth;

uniform sampler2D u_combine_translucent;
uniform sampler2D u_translucent_depth;

uniform sampler2D u_particles;
uniform sampler2D u_particles_depth;

uniform sampler2D u_clouds;
uniform sampler2D u_clouds_depth;

uniform sampler2D u_weather;
uniform sampler2D u_weather_depth;

uniform sampler2D u_emissive_solid;
uniform sampler2D u_emissive_transparent;
uniform sampler2D u_light_particles;
uniform sampler2D u_refraction_uv;

in vec2 v_invSize;

out vec4[3] fragColor;

#define NUM_LAYERS 5

vec4 color_layers[NUM_LAYERS];
float depth_layers[NUM_LAYERS];
int active_layers = 0;

void try_insert(vec4 color, float depth)
{
	if (color.a == 0.0) {
		return;
	}

	color_layers[active_layers] = color;
	depth_layers[active_layers] = depth;

	int target = active_layers++;
	int probe = target - 1;

	while (target > 0 && depth_layers[target] > depth_layers[probe]) {
		float probeDepth = depth_layers[probe];
		depth_layers[probe] = depth_layers[target];
		depth_layers[target] = probeDepth;

		vec4 probeColor = color_layers[probe];
		color_layers[probe] = color_layers[target];
		color_layers[target] = probeColor;

		target = probe--;
	}
}

vec3 blend(vec3 dst, vec4 src)
{
	return (dst * (1.0 - src.a)) + src.rgb * src.a;
}

void computeDistorted(in sampler2D sdepth, in sampler2D scolor, in vec2 origUV, in float translucentDepth, out float depth, out vec4 color) {
	depth = texture(sdepth, origUV).r;
	vec2 trueUV = origUV;

#ifdef REFRACTION_EFFECT
	if (translucentDepth <= depth) {
		trueUV = origUV + (texture(u_refraction_uv, origUV).rg * 2.0 - 1.0);
		depth = texture(sdepth, trueUV).r;

		if (translucentDepth > depth) {
			// impossible refraction. abort!
			trueUV = origUV;
			depth = texture(sdepth, trueUV).r;
		}
	}
#endif

	color = texture(scolor, trueUV);
}

void main()
{
	float depth_translucent = texture(u_translucent_depth, v_texcoord).r;
	vec4 translucent = texture(u_combine_translucent, v_texcoord);

	float depth_solid;// = texture(u_solid_depth, v_texcoord).r;
	vec4 solid;// texture(u_combine_solid, v_texcoord);

	float depth_particles;// = texture(u_particles_depth, v_texcoord).r;
	vec4 particles;// = texture(u_particles, v_texcoord);

	float depth_clouds;// = texture(u_clouds_depth, v_texcoord).r;
	vec4 clouds;// = texture(u_clouds, v_texcoord);

	computeDistorted(u_solid_depth,	u_combine_solid, v_texcoord, depth_translucent, depth_solid, solid);
	computeDistorted(u_particles_depth,	u_particles, v_texcoord, depth_translucent, depth_particles, particles);
	computeDistorted(u_clouds_depth,	u_clouds, v_texcoord, depth_translucent, depth_clouds, clouds);

	float depth_weather = texture(u_weather_depth, v_texcoord).r;
	vec4 weather = texture(u_weather, v_texcoord);
	 weather.rgb = ldr_tonemap3(hdr_fromGamma(weather.rgb));

	color_layers[0] = vec4(solid. rgb, 1.0);
	depth_layers[0] = depth_solid;
	active_layers = 1;

	try_insert(translucent, depth_translucent);
	try_insert(particles, depth_particles);
	try_insert(clouds, depth_clouds);
	try_insert(weather, depth_weather);

	vec3 c = color_layers[0].rgb;

	for (int i = 1; i < active_layers; ++i) {
		c = blend(c, color_layers[i]);
	}

	float min_depth = min(depth_translucent, depth_particles);

	fragColor[0] = vec4(c, 1.0); //frx_luminance(c.rgb)); // FXAA 3 would need this
	fragColor[1] = vec4(min_depth, 0., 0., 1.);

#ifdef TOON_OUTLINE
	float d1      = ldepth(min_depth);
	float maxDiff = 0.;
	float maxD    = 0;
	const vec2[4] check = vec2[](vec2( 1.,  1.), vec2( 1., -1.), vec2(-1.,  1.), vec2(-1., -1.));

	for (int i = 0; i < 4; i++) {
		vec2 coord = v_texcoord + v_invSize * check[i];
		float minD = ldepth(min(texture(u_translucent_depth, coord).x, texture(u_particles_depth, coord).x));
		float diff = d1 - minD;
		if (diff > maxDiff) {
			maxDiff = diff;
			maxD = minD;
		}
	}

	float threshold = mix(.0, .3, d1);
	float lineness = l2_clampScale(threshold, threshold * .5, maxDiff);
		 lineness += (1.0 - lineness) * min(1.0, maxD * 2.0);
		 lineness += (1.0 - lineness) * (maxD > ldepth(depth_layers[active_layers-1]) ? color_layers[active_layers-1].a : 0.0);

	fragColor[0] *= lineness;
#endif

	// no need to check for solid depth because translucent behind solid are culled in GL depth test
	float bloom = max(texture(u_emissive_solid, v_texcoord).r, texture(u_emissive_transparent, v_texcoord).r);

	if (depth_particles <= min_depth) {
		bloom = max(bloom, texture(u_light_particles, v_texcoord).z);
	}

	float min_occluder   = min(depth_clouds, depth_weather);
	float occluder_alpha = min_occluder == depth_clouds ? clouds.a : weather.a;
		  occluder_alpha = min_occluder <= min_depth ? occluder_alpha : 0.0;

	bloom *= max(0.0, 1.0 - occluder_alpha);

	fragColor[2].r = bloom;
}
