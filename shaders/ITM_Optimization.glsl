//!HOOK OUTPUT
//!BIND HOOKED
//!DESC ITM Optimization

vec4 hook() {
  vec4 color = HOOKED_tex(HOOKED_pos);
  const vec3 luma_coeff = vec3(0.2627, 0.6780, 0.0593);

  float luma = dot(color.rgb, luma_coeff);
  vec3 chroma = color.rgb - luma;

  float luma_factor = 2.8 * pow(1.0 - min(luma / 0.5, 1.0), 8.0) + 1.0;
  luma *= luma_factor;

  float chroma_factor = 0.6 / (1.0 + exp((0.5 - luma) * 12)) + 1.0;
  chroma *= chroma_factor;

  return vec4(luma + chroma, color.a);
}