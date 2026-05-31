//!HOOK OUTPUT
//!BIND HOOKED
//!DESC ITM Saturation Restore

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    const vec3 luma_coeff = vec3(0.2627, 0.6780, 0.0593);

    float luma = dot(c.rgb, luma_coeff);
    vec3 chroma = c.rgb - luma;

    float lift_strength = pow(max(0.5 - luma, 0.0) * 2.0, 2.2);
    float extra_lift = exp(-200.0 * luma * luma);
    float luma_lift_factor = 0.5 * lift_strength;
    luma *= 1.0 + luma_lift_factor;

    float sigmoid = 1.0 / (1.0 + exp((0.5 - luma) * 12.0));
    float min_sig = 1.0 / (1.0 + exp(6.0));
    float max_sig = 1.0 / (1.0 + exp(-6.0));
    float chroma_lift_factor = 0.7 * (sigmoid - min_sig) / (max_sig - min_sig);
    chroma *= 1.0 + chroma_lift_factor;

    return clamp(vec4(luma + chroma, c.a), 0.0, 1.0);
}