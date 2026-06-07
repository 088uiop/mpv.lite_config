//!DESC Anime4K-v4.0-AutoScalePost-Soft
//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w 1.2 *
//!HEIGHT OUTPUT.h 1.2 *

vec4 hook() {
	return HOOKED_tex(HOOKED_pos);
}
