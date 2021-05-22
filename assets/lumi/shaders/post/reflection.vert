#include lumi:shaders/post/common/header.glsl
#include frex:shaders/api/world.glsl
#include frex:shaders/api/view.glsl
#include frex:shaders/lib/math.glsl
#include lumi:shaders/common/atmosphere.glsl
#include lumi:shaders/common/lightsource.glsl
#include lumi:shaders/lib/util.glsl

/*******************************************************
 *  lumi:shaders/post/hdr_half.vert                    *
 *******************************************************/

out vec2 v_invSize;
out float v_blindness;

void main()
{
    basicFrameSetup();
    atmos_generateAtmosphereModel();

#ifdef HALF_REFLECTION_RESOLUTION
    gl_Position.xy -= (gl_Position.xy - vec2(-1., -1.)) * .5;
#endif

    v_invSize = 1.0/frxu_size;
    v_blindness = frx_playerHasEffect(FRX_EFFECT_BLINDNESS)
        ? l2_clampScale(0.5, 1.0, 1.0 - frx_luminance(frx_vanillaClearColor()))
        : 0.0;
}