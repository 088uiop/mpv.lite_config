//!HOOK OUTPUT
//!BIND HOOKED
//!DESC ITM Saturation Restore

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    const vec3 luma_coeff = vec3(0.2627, 0.6780, 0.0593);
    float luma = dot(c.rgb, luma_coeff);
    vec3 chroma = c.rgb - luma;

    // Maximum luma enhancement of dark areas
    float llf_max = 0.5;
    // Maximum chroma enhancement of bright areas
    float clf_max = 0.7;

    float sigmoid = 1.0 / (1.0 + exp((0.5 - luma) * 12.0));
    float min_sig = 1.0 / (1.0 + exp(6.0));
    float max_sig = 1.0 / (1.0 + exp(-6.0));

    float luma_lift_factor = llf_max * pow(max(0.5 - luma, 0.0) * 2, 2.2);
    float chroma_lift_factor = clf_max * (sigmoid - min_sig) / (max_sig - min_sig);

    vec3 result = (luma * (1.0 + luma_lift_factor)) + (chroma * (1.0 + chroma_lift_factor));

    return clamp(vec4(result, c.a), 0.0, 1.0);
}