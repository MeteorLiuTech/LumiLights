#include lumi:shaders/post/common/header.glsl

#include frex:shaders/api/world.glsl
#include frex:shaders/api/view.glsl
#include frex:shaders/lib/math.glsl
#include lumi:shaders/common/atmosphere.glsl
#include lumi:shaders/lib/celest_adapter.glsl
#include lumi:shaders/lib/rectangle.glsl
#include lumi:shaders/lib/taa_jitter.glsl
#include lumi:shaders/lib/util.glsl

/*******************************************************
 *  lumi:shaders/post/shading.vert
 *******************************************************/

out vec3 v_celest1;
out vec3 v_celest2;
out vec3 v_celest3;
out vec2 v_invSize;
out mat4 v_star_rotator;
out float v_fov;
out float v_night;
out float v_not_in_void;
out float v_near_void_core;
out float v_blindness;

void main()
{
	basicFrameSetup();
	atmos_generateAtmosphereModel();
	Rect theCelest = celestSetup();

	v_celest1 = theCelest.bottomLeft;
	v_celest2 = theCelest.bottomRight;
	v_celest3 = theCelest.topLeft;

	v_invSize = 1.0 / frxu_size;

	v_star_rotator = l2_rotationMatrix(vec3(1.0, 0.0, 1.0), frx_worldTime() * PI);
	v_fov		   = 2.0 * atan(1.0 / frx_projectionMatrix()[1][1]) * 180.0 / PI;
	v_night		   = min(smoothstep(0.50, 0.54, frx_worldTime()), smoothstep(1.0, 0.96, frx_worldTime()));

	v_not_in_void	 = l2_clampScale(-1.0,   0.0, frx_cameraPos().y);
	v_near_void_core = l2_clampScale(10.0, -90.0, frx_cameraPos().y) * 1.8;

	// TODO: multiple instances found; make common?
	v_blindness = frx_playerHasEffect(FRX_EFFECT_BLINDNESS)
				? l2_clampScale(0.5, 1.0, 1.0 - frx_luminance(frx_vanillaClearColor()))
				: 0.0;

	// jitter celest
	#ifdef TAA_ENABLED
		vec2 taa_jitterValue = taa_jitter(v_invSize);
		vec4 celest_clip = frx_projectionMatrix() * vec4(v_celest1, 1.0);
		v_celest1.xy += taa_jitterValue * celest_clip.w;
		v_celest2.xy += taa_jitterValue * celest_clip.w;
		v_celest3.xy += taa_jitterValue * celest_clip.w;
	#endif
}
