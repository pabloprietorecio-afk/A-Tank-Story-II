// Común a los shaders de efectos.
// Los efectos calculan sus colores en espacio lineal. Los renderizadores con Vulkan trabajan
// así; el de compatibilidad (OpenGL, teléfonos sin Vulkan) espera el color en sRGB y lo pasa a
// lineal él mismo, de modo que allí hay que entregárselo ya convertido.
vec3 fx_out(vec3 linear_color) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return pow(max(linear_color, vec3(0.0)), vec3(0.4545));
#else
	return linear_color;
#endif
}
