//!DESC Anime4K-v4.0-AutoScalePost
//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h

vec4 hook() {
	return HOOKED_tex(HOOKED_pos);
}
