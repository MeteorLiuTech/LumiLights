#include lumi:shaders/common/atmosphere.glsl

/*******************************************************
 *  lumi:shaders/post/prog/fog.glsl
 *******************************************************/

#ifdef VERTEX_SHADER
out float v_blindness;

void blindnessSetup() {
	// capture vanilla transition which happens when blindness happens/stops naturally (without milk, command, etc) 
	v_blindness = l2_clampScale(1.0, 0.0, frx_luminance(frx_vanillaClearColor)) * float(frx_effectBlindness);
}
#else
in float v_blindness;

vec4 blindnessFog(vec4 color, float distToEye)
{
	// unlike normal fog, this also applies to the sky and doesn't mess with atmospheric fog
	float blindFactor = min(1.0, distToEye / 2.0) * v_blindness;
	vec4 blended = mix(color, vec4(0.0, 0.0, 0.0, 1.0), blindFactor);
	return blended;
}

const float FOG_FAR				   = FOG_FAR_CHUNKS * 16.0;
const float FOG_DENSITY			   = FOG_DENSITY_RELATIVE / 20.0;
const float UNDERWATER_FOG_FAR	   = UNDERWATER_FOG_FAR_CHUNKS * 16.0;
const float UNDERWATER_FOG_DENSITY = UNDERWATER_FOG_DENSITY_RELATIVE / 20.0;

float invThickener(bool isUnderwater) {
	if (isUnderwater || frx_worldHasSkylight != 1) {
		return 1.0;
	}

	float invThickener = 1.0;
	float night = max(frx_worldIsMoonlit, 1.0 - frx_skyLightTransitionFactor);
	invThickener *= 1.0 - 0.6 * frx_rainGradient;
	invThickener *= 1.0 - 0.5 * frx_thunderGradient;
	invThickener = mix(1.0, invThickener, frx_smoothedEyeBrightness.y);

	return invThickener;
}

float fogFactor(float distToEye, bool isUnderwater, float invThickener)
{
	// only when absolutely underwater
	bool submerged = isUnderwater && frx_cameraInFluid == 1;

	float pFogDensity = submerged ? UNDERWATER_FOG_DENSITY : FOG_DENSITY;
	float pFogFar     = submerged ? UNDERWATER_FOG_FAR     : FOG_FAR;

	if (!isUnderwater && frx_worldHasSkylight == 1) {
		pFogFar *= invThickener;
		pFogDensity = mix(min(1.0, pFogDensity * 2.0), min(0.8, pFogDensity), invThickener);
	}

	float density = pFogDensity;

	// resolve lava
	pFogFar = mix(pFogFar, float(frx_effectFireResistance) * 2.0 + 0.5, float(frx_cameraInLava));
	density = max(density, float(frx_cameraInLava));

	float distFactor = min(1.0, distToEye / pFogFar);

	return clamp(density * distFactor, 0.0, 1.0);
}

float fogFactor(float distToEye, bool isUnderwater) {
	return fogFactor(distToEye, isUnderwater, invThickener(isUnderwater));
}

vec4 fog(vec4 color, float distToEye, vec3 toFrag, bool isUnderwater, bool doSkyBlend)
{
	float invThickener = invThickener(isUnderwater);
	float fogFactor = fogFactor(distToEye, isUnderwater, invThickener);

	vec3 fogColor = isUnderwater ? atmosv_ClearRadiance : atmos_OWFogRadiance(toFrag);

	// resolve sky blend
	if (doSkyBlend) {
		float blendStart = max(0.0, frx_viewDistance - 16.0) * invThickener;
		float blendEnd	 = max(1.0, frx_viewDistance - 8.0);
		float skyBlend	 = frx_cameraInFluid == 1 ? 0.0 : l2_clampScale(blendStart, blendEnd, distToEye);
		fogFactor = max(fogFactor, skyBlend);
	}

	// resolve height fog
	if (!isUnderwater && frx_cameraInLava != 1) {
		float eyeY = toFrag.y * distToEye;
		// for terrain
		float yFactor = l2_clampScale(-128.0, 128.0, eyeY);

		// for sky, has curve... 1.0 is equivalent to y=1024
		float rdMult = min(1.0, frx_viewDistance / 512.0);
		float cameraAt = mix(0.0, -0.75, l2_clampScale(64.0 + 64.0 * rdMult, 256.0 + 256.0 * rdMult, frx_cameraPos.y));
		float extraViewBlend = l2_clampScale(frx_viewDistance * 2.0, frx_viewDistance * 4.0, distToEye);
		yFactor = mix(yFactor, l2_clampScale(-0.125 + cameraAt, 0.5 + cameraAt, toFrag.y), extraViewBlend);

		float invYFactor = 1.0 - yFactor;
		fogFactor *= invYFactor * invYFactor;
	}

	// resolve cave fog
	if (!isUnderwater || frx_cameraInFluid == 0) {
		float invEyeY = (1.0 - frx_smoothedEyeBrightness.y);
		fogColor = mix(fogColor, atmosv_CaveFogRadiance, invEyeY * invEyeY);
	}

	vec4 blended = mix(color, vec4(fogColor, 1.0), fogFactor);
	
	return blended;
}

vec4 fog(vec4 color, float distToEye, vec3 toFrag, bool isUnderwater)
{
	return fog(color, distToEye, toFrag, isUnderwater, true);
}
#endif
