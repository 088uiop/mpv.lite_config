//!HOOK MAIN
//!BIND HOOKED
//!DESC ITM Gamma Correction

vec4 hook() {
  vec4 color = HOOKED_tex(HOOKED_pos);
  const vec3 luma_coeff = vec3(0.2126, 0.7152, 0.0722);

  float luma = dot(color.rgb, luma_coeff);

  float dark_mask = pow(1.0 - luma, 5);
  vec3 corrected = pow(color.rgb, vec3(1.0 / (1.0 + dark_mask * 0.3)));

  return vec4(corrected, color.a);
}

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC ITM Chroma Correction

vec4 hook() {
  vec4 color = HOOKED_tex(HOOKED_pos);
  const vec3 luma_coeff = vec3(0.2627, 0.6780, 0.0593);

  float luma = dot(color.rgb, luma_coeff);
  vec3 chroma = color.rgb - luma;

  float sigmoid = 1.0 / (1.0 + exp((0.5 - luma) * 12.0));
  float min_sig = 1.0 / (1.0 + exp(6.0));
  float max_sig = 1.0 / (1.0 + exp(-6.0));
  float chroma_lift_factor = 0.6 * (sigmoid - min_sig) / (max_sig - min_sig);
  chroma *= 1.0 + chroma_lift_factor;

  return clamp(vec4(luma + chroma, color.a), 0.0, 1.0);
}