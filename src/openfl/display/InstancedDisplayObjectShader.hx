package openfl.display;

import openfl.utils.ByteArray;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
/**
	[cne-instance] Vertex-shader variant of DisplayObjectShader for the Metal instanced
	bitmap batch: the per-object matrix, alpha and colour transform are read from the
	per-instance attributes i_data0..i_data6 instead of uniforms, so consecutive bitmaps
	that share a BitmapData/batch state can be drawn with one drawElementsInstanced call.

	Per instance (7 x float4 = 28 floats):
	  i_data0..i_data3 : model-view-projection matrix (row major)
	  i_data4          : (alpha, hasColorTransform, 0, 0)
	  i_data5          : colour multiplier (rgba)
	  i_data6          : colour offset (rgba, 0..255)
**/
class InstancedDisplayObjectShader extends Shader
{
	@:glVertexHeader("attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;

		attribute vec4 i_data0;
		attribute vec4 i_data1;
		attribute vec4 i_data2;
		attribute vec4 i_data3;
		attribute vec4 i_data4;
		attribute vec4 i_data5;
		attribute vec4 i_data6;

		varying float openfl_Alphav;
		varying float openfl_HasColorTransformv;
		varying vec4 openfl_ColorMultiplierv;
		varying vec4 openfl_ColorOffsetv;
		varying vec2 openfl_TextureCoordv;")
	@:glVertexBody("openfl_Alphav = i_data4.x;
		openfl_TextureCoordv = openfl_TextureCoord;
		openfl_HasColorTransformv = i_data4.y;

		if (openfl_HasColorTransformv > 0.5) {
			openfl_ColorMultiplierv = i_data5;
			openfl_ColorOffsetv = i_data6 / 255.0;
		}

		mat4 openfl_Matrix = mat4 (i_data0, i_data1, i_data2, i_data3);
		gl_Position = openfl_Matrix * openfl_Position;")
	@:glVertexSource("#pragma header

		void main(void) {

			#pragma body

		}")
	@:glFragmentHeader("varying float openfl_Alphav;
		varying float openfl_HasColorTransformv;
		varying vec4 openfl_ColorMultiplierv;
		varying vec4 openfl_ColorOffsetv;
		varying vec2 openfl_TextureCoordv;

		uniform sampler2D openfl_Texture;
		uniform vec2 openfl_TextureSize;")
	@:glFragmentBody("vec4 color = texture2D (openfl_Texture, openfl_TextureCoordv);

		if (color.a == 0.0) {

			gl_FragColor = vec4 (0.0, 0.0, 0.0, 0.0);

		} else if (openfl_HasColorTransformv > 0.5) {

			color = vec4 (color.rgb / color.a, color.a);

			mat4 colorMultiplier = mat4 (0);
			colorMultiplier[0][0] = openfl_ColorMultiplierv.x;
			colorMultiplier[1][1] = openfl_ColorMultiplierv.y;
			colorMultiplier[2][2] = openfl_ColorMultiplierv.z;
			colorMultiplier[3][3] = 1.0;

			color = clamp (openfl_ColorOffsetv + (color * colorMultiplier), 0.0, 1.0);

			if (color.a > 0.0) {

				gl_FragColor = vec4 (color.rgb * color.a * openfl_Alphav, color.a * openfl_Alphav);

			} else {

				gl_FragColor = vec4 (0.0, 0.0, 0.0, 0.0);

			}

		} else {

			gl_FragColor = color * openfl_Alphav;

		}")
	#if emscripten
	@:glFragmentSource("#pragma header

		void main(void) {

			#pragma body

			gl_FragColor = gl_FragColor.bgra;

		}")
	#else
	@:glFragmentSource("#pragma header

		void main(void) {

			#pragma body

		}")
	#end
	public function new(code:ByteArray = null)
	{
		super(code);
	}
}
