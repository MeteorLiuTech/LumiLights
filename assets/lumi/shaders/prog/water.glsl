#include lumi:shaders/common/texconst.glsl

/*******************************************************
 *  lumi:shaders/prog/water.glsl
 *******************************************************/

#ifndef VERTEX_SHADER
float textureWater(sampler2D natureTexture, vec4 uvuv, vec2 uvMove)
{
	uvuv *= WATER_SAMPLING_ZOOM * WATER_BLOCK_RES / WATER_TEXSIZE;

	float A = texture(natureTexture, uvuv.xy + uvMove).g;
	float B = texture(natureTexture, uvuv.zw + uvMove).b;

	return A * 0.75 + B * 0.25;
}

#ifdef POST_SHADER
bool decideUnderwater(float depth, float dTrans, bool transIsWater, bool translucent) {
	if (frx_cameraInWater == 1) {
		if (translucent) {
			return true;
		} else {
			return dTrans >= depth;
		}
	} else {
		return dTrans < depth && transIsWater; 
	}
}

vec2 refractSolidUV(sampler2DArray normalBuffer, sampler2D solidDepthBuffer, float dSolid, float dTrans) {
	if (dTrans < dSolid) {
		const float refractStr = .1;

		float ldepth_range = ldepth(dSolid) - ldepth(dTrans);

		vec3 viewVNormal = frx_normalModelMatrix * (texture(normalBuffer, vec3(v_texcoord, ID_TRANS_NORM)).xyz * 2.0 - 1.0);
		vec3 viewMNormal = frx_normalModelMatrix * (texture(normalBuffer, vec3(v_texcoord, ID_TRANS_MNORM)).xyz * 2.0 - 1.0);

		vec2 refractUV = refractStr * l2_clampScale(0.0, 0.005, ldepth_range) * (viewMNormal.xy - viewVNormal.xy);
		refractUV = clamp(v_texcoord + refractUV, 0.0, 1.0);

		float newDepth = texture(solidDepthBuffer, refractUV).r;

		if (newDepth < dTrans) refractUV = v_texcoord;

		return refractUV;
	} else {
		return v_texcoord;
	}
}

float caustics(sampler2D natureTexture, vec3 worldPos, float vertexNormaly)
{
	float yMove = 1.0 - vertexNormaly;
	vec2 moveA = vec2(1. + yMove, 1. - yMove) * frx_renderSeconds;
	vec2 moveB = vec2(1. + yMove, -1. - yMove) * frx_renderSeconds;

	vec2 uv = worldPos.xz;
	uv += vec2(-1.0, 1.0) * worldPos.y;

	vec4 uvuv = vec4(uv + moveA, uv + moveB);

	float e = textureWater(natureTexture, uvuv, vec2(0.0));
		  e = smoothstep(-1.0, 1.0, e);

	return e;
}
#else

float sampleWaterNoise(sampler2D natureTexture, vec3 worldPos, vec2 uvMove, float vertexNormaly)
{
	float yMove = 1.0 - vertexNormaly;
	vec2 moveA = vec2(1. + yMove * 5., 1. - yMove) * frx_renderSeconds;
	vec2 moveB = vec2(1. + yMove * 5., -1. + yMove) * frx_renderSeconds;

	vec2 uv = worldPos.xz;
	uv.x += worldPos.y;

	vec4 uvuv = vec4(uv + moveA, uv + moveB);

	return textureWater(natureTexture, uvuv, uvMove);
}

vec3 sampleWaterNormal(sampler2D natureTexture, vec3 fragWorldPos, float vertexNormaly)
{
	const vec3 normal = vec3(0.0, 0.0, 1.0);
	const vec3 tangent = vec3(1.0, 0.0, 0.0);
	const vec3 bitangent = vec3(0.0, 1.0, 0.0);

	const float slope = 1. / 32.;
	const float oneBlock = WATER_BLOCK_RES / WATER_TEXSIZE;
	const float amplitude = 0.02;

	vec3 tmove = tangent * slope;
	vec3 bmove = bitangent * slope;
	vec2 uvMove = vec2(0.0, oneBlock * slope);

	vec3 origin = amplitude * sampleWaterNoise(natureTexture, fragWorldPos, uvMove.xx, vertexNormaly) * normal;
	vec3 tside  = amplitude * sampleWaterNoise(natureTexture, fragWorldPos, uvMove.yx, vertexNormaly) * normal + tmove - origin;
	vec3 bside  = amplitude * sampleWaterNoise(natureTexture, fragWorldPos, uvMove.xy, vertexNormaly) * normal + bmove - origin;

	vec3 eyePos = fragWorldPos - frx_cameraPos;
	float farBlend = l2_clampScale(0., 512. * 512., dot(eyePos, eyePos));
	vec3 noisyNormal = normalize(mix(cross(tside, bside), normal, farBlend));

	return noisyNormal;
}
#endif
#endif