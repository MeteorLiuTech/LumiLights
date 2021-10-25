#include lumi:shaders/post/common/header.glsl
#include lumi:shaders/lib/taa.glsl
#include lumi:shaders/lib/taa_velocity.glsl

/*******************************************************
 *  lumi:shaders/post/reflection_merge.frag
 *******************************************************
 *  Copyright (c) 2020-2021 spiralhalo
 *  Released WITHOUT WARRANTY under the terms of the
 *  GNU Lesser General Public License version 3 as
 *  published by the Free Software Foundation, Inc.
 *******************************************************/

uniform sampler2D u_input;
uniform sampler2D u_depth;
uniform sampler2D u_history;

in vec2 v_invSize;

out vec4 fragColor;

void main()
{
#if REFLECTION_PROFILE != REFLECTION_PROFILE_NONE
	vec2 deltaRes  = v_invSize;
	vec2 currentUv = v_texcoord;
	vec2 velocity  = fastVelocity(u_depth, v_texcoord) * 0.75; // magic anti-ghosting hack

	#ifdef HALF_REFLECTION_RESOLUTION
	deltaRes *= 4.;
	currentUv *= 0.5;
	velocity *= 0.5;
	#endif

	vec4 current = texture(u_input, currentUv);
	vec4 history = texture(u_history, currentUv - velocity);

	const float ROUGHNESS_TOLERANCE = 0.03;

	if (abs(history.a - current.a) < ROUGHNESS_TOLERANCE) {
		vec4 current2x2Colors[neighborCount2x2];
		for(int iter = 0; iter < neighborCount2x2; iter++)
		{
			current2x2Colors[iter] = texture(u_input, currentUv + (kOffsets2x2[iter] * deltaRes));
		}
		vec4 min2 = MinColors(current2x2Colors);
		vec4 max2 = MaxColors(current2x2Colors);

		//NB: clips history.a to current.a if outside of bounding box
		history = clip_aabb(min2.rgb, max2.rgb, current, history);
	} else {
		history = current;
	}

	fragColor = mix(current, history, 0.9);
#else
	fragColor = texture(u_input, v_texcoord);
#endif
}
