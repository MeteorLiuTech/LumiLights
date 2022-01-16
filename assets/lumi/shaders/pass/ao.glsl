#include lumi:shaders/pass/header.glsl

#include lumi:shaders/prog/tile_noise.glsl

#ifdef SSAO_OVERRIDE

const int RADIAL_STEPS	= clamp(SSAO_NUM_STEPS, 1, 10);
const int DIRECTIONS	= clamp(SSAO_NUM_DIRECTIONS, 1, 10);
const float ANGLE_BIAS	= SSAO_BIAS;

#else

const int RADIAL_STEPS	= 3;
const int DIRECTIONS	= 5;
const float ANGLE_BIAS	= 0.3;

#endif

const float VIEW_RADIUS	= float(clamp(SSAO_RADIUS_INT, 1, 20)) / 10.;
const float INTENSITY	= float(clamp(SSAO_INTENSITY_INT, 1, 20)) / 2.;
const float CENTER_BIAS_POW = clamp(VIEW_RADIUS, 1.0, 2.0);

#ifdef VERTEX_SHADER

out mat2 v_deltaRotator;

void calcDeltaRotator() {
	float theta    = (2.0 * PI) / float(DIRECTIONS);
	float cosTheta = cos(theta);
	float sinTheta = sin(theta);

	v_deltaRotator = mat2(
		cosTheta, -sinTheta,
		sinTheta, cosTheta
	);
}

void main()
{
	calcDeltaRotator();
	basicFrameSetup();
}

#else

uniform sampler2D u_vanilla_depth;
uniform sampler2DArray u_gbuffer_lightnormal;
uniform sampler2D u_tex_noise;

in mat2 v_deltaRotator;

out float ao_result;

vec3 getViewPos(vec2 texcoord, in sampler2D target)
{
	float depth = texture(target, texcoord).r;
	vec3  clip	= vec3(2.0 * texcoord - 1.0, 2.0 * depth - 1.0);
	vec4  view	= frx_inverseProjectionMatrix * vec4(clip, 1.0);

	return view.xyz / view.w;
}

void main()
{
	/* NOTE: using reconstructed normals doesn't really help reduce artifacts.
	         and as minecraft is blocky the interpolated normals should be accurate anyway. */
	vec3  viewPos = getViewPos(v_texcoord, u_vanilla_depth);
	vec3  viewNormal = frx_normalModelMatrix * normalize(texture(u_gbuffer_lightnormal, vec3(v_texcoord, ID_SOLID_NORM)).xyz);

	vec3 rightPos = viewPos + vec3(VIEW_RADIUS, 0.0, 0.0);
	vec4 temp = frx_projectionMatrix * vec4(rightPos, 1.0);
	temp.x /= temp.w;
	float screenRadius = (temp.x * 0.5 + 0.5) - v_texcoord.x;

	// exclude last step here too
	vec2 deltaUV = vec2(float(RADIAL_STEPS - 1) / float(RADIAL_STEPS), 0.0) * (screenRadius / float(RADIAL_STEPS));
	vec3 fragNoise = normalize(2.0 * getRandomVec(u_tex_noise, v_texcoord, frxu_size) - 1.0);
	mat2 randomRotation = mat2(
		fragNoise.x, -fragNoise.y,
		fragNoise.y,  fragNoise.x
	);

	deltaUV = randomRotation * deltaUV;

	vec2 aspectNormalizer = v_invSize * min(frxu_size.x, frxu_size.y);

	float occlusion = 0.0;
	for (int i = 0; i < DIRECTIONS; ++i) {
		deltaUV = v_deltaRotator * deltaUV;
		float prevPhi = ANGLE_BIAS;
		vec2 deltaUVnormalized = deltaUV * aspectNormalizer;

		for (int j = 1; j < RADIAL_STEPS; ++j) {
			// bias towards center
			float samplingBias = pow(float(j) / RADIAL_STEPS, CENTER_BIAS_POW) / (float(j) / RADIAL_STEPS);
			vec2 sampleUV	   = v_texcoord + deltaUVnormalized * (float(j) + fragNoise.z) * samplingBias;
			vec3 sampleViewPos = getViewPos(sampleUV, u_vanilla_depth);
			vec3 horizonVec	   = sampleViewPos - viewPos;
			float phi = (PI / 2.0) - acos(dot(viewNormal, normalize(horizonVec)));

			if (phi > prevPhi) {
				float r2 = dot(horizonVec, horizonVec) / (VIEW_RADIUS * VIEW_RADIUS); // optimized pow(len/rad, 2)
				float attenuation = clamp(1.0 - r2, 0.0, 1.0);
				float value		  = sin(phi) - sin(prevPhi);
				occlusion += attenuation * value;
				prevPhi = phi;
			}
		}
	}

	float fade = l2_clampScale(256.0, 64.0, length(viewPos)); // distant result are rather inaccurate, and I'm lazy
	occlusion  = 1.0 - occlusion / float(DIRECTIONS) * fade;

	// apply intensity before blurring
	ao_result = pow(clamp(occlusion, 0.0, 1.0), INTENSITY);
}

#endif
