package openfl.display._internal;

#if !flash
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.InstancedDisplayObjectShader;
import openfl.display.OpenGLRenderer;
import openfl.display.Shader;
import openfl.display.ShaderParameter;
import openfl.display3D.Context3D;
import openfl.display3D.Context3DBufferUsage;
import openfl.display3D.Context3DVertexBufferFormat;
import openfl.display3D.VertexBuffer3D;
import openfl.geom.ColorTransform;
import openfl.utils._internal.Float32Array;

/**
	[cne-instance] Batches consecutive Bitmap draws that share a BitmapData and blend
	state into one instanced draw.  OpenFL's bitmap channel already draws every bitmap as
	the same 4-vertex unit quad from BitmapData.getVertexBuffer, with the object transform,
	alpha and colour transform supplied through uniforms, so those uniforms become
	per-instance attributes (InstancedDisplayObjectShader) and the whole run is submitted
	with drawElementsInstanced.

	The batch is flushed before any other GL draw/state change (Context3D draw calls,
	clear/present, shader/blend/mask changes) so draw order is preserved.
**/
#if metal_instancing
@:access(openfl.display.Bitmap)
@:access(openfl.display.BitmapData)
@:access(openfl.display.DisplayObject)
@:access(openfl.display.DisplayObjectRenderer)
@:access(openfl.display.OpenGLRenderer)
@:access(openfl.display.Shader)
@:access(openfl.geom.ColorTransform)
class MetalInstanceBatch
{
	static inline var FLOATS_PER_INSTANCE = 28; // 7 float4
	static inline var MAX_INSTANCES = 512;

	/**
	 * Instanced bitmap batching is opt-in while its render-target/flip handling is still
	 * being validated: it skipped the late matrix flip used for offscreen passes, which
	 * rotated/fragmented filtered stages (Winter Horrorland / Senpai / Roses / Thorns).
	 * Enable with CNE_METAL_INSTANCING=1 or FlxG.metalInstancing = true.
	 */
	public static var enabled = #if sys (Sys.getEnv("CNE_METAL_INSTANCING") == "1" ? true : false) #else false #end;

	static var active = false;
	static var flushing = false;
	static var renderer:OpenGLRenderer;
	static var shader:InstancedDisplayObjectShader;
	static var bitmapData:BitmapData;
	static var blendMode:BlendMode;
	static var smooth:Bool;

	static var instanceCount = 0;
	static var data = new Array<Float>();

	static var __instanceBuffer:VertexBuffer3D;

	public static var activeShader(get, never):Shader;

	static function get_activeShader():Shader
	{
		return active ? shader : null;
	}

	public static function tryAdd(bitmap:Bitmap, renderer:OpenGLRenderer):Bool
	{
		if (flushing) return false;
		if (!enabled) { flush(); return false; }
		if (bitmap.__worldShader != null) { flush(); return false; }
		if (bitmap.filters != null && bitmap.filters.length > 0) { flush(); return false; }
		if (bitmap.scale9Grid != null) { flush(); return false; }
		if (renderer.__maskObjects.length > 0) { flush(); return false; }
		if (bitmap.__bitmapData == null || !bitmap.__bitmapData.__isValid) return false;

		var context = renderer.__context3D;
		if (context == null) return false;

		var bd = bitmap.__bitmapData;
		var blend = bitmap.__worldBlendMode;
		var isSmooth = renderer.__allowSmoothing && (bitmap.smoothing || renderer.__upscaled);

		if (active && (bd != bitmapData || blend != blendMode || isSmooth != smooth))
		{
			flush();
		}

		if (!active)
		{
			active = true;
			MetalInstanceBatch.renderer = renderer;
			bitmapData = bd;
			blendMode = blend;
			smooth = isSmooth;
			instanceCount = 0;
			data = [];
			if (shader == null) shader = new InstancedDisplayObjectShader();
		}

		var matrix = renderer.__getMatrix(bitmap.__renderTransform, bitmap.pixelSnapping);
		for (i in 0...16) data.push(matrix[i]);

		var alpha = bitmap.__worldAlpha * renderer.__worldAlpha;
		var hasColor = false;
		var mult = [1.0, 1.0, 1.0, 1.0];
		var off = [0.0, 0.0, 0.0, 0.0];
		var ct = bitmap.__worldColorTransform;
		if (ct != null
			&& (ct.redMultiplier != 1 || ct.greenMultiplier != 1 || ct.blueMultiplier != 1
				|| ct.alphaMultiplier != 1 || ct.redOffset != 0 || ct.greenOffset != 0
				|| ct.blueOffset != 0 || ct.alphaOffset != 0))
		{
			hasColor = true;
			mult = [ct.redMultiplier, ct.greenMultiplier, ct.blueMultiplier, ct.alphaMultiplier];
			off = [ct.redOffset, ct.greenOffset, ct.blueOffset, ct.alphaOffset];
		}
		data.push(alpha);
		data.push(hasColor ? 1.0 : 0.0);
		data.push(0.0);
		data.push(0.0);
		for (i in 0...4) data.push(mult[i]);
		for (i in 0...4) data.push(off[i]);

		instanceCount++;
		if (instanceCount >= MAX_INSTANCES) flush();
		return true;
	}

	public static function flush():Void
	{
		if (!active || instanceCount == 0) return;
		if (flushing) return;
		flushing = true;

		var count = instanceCount;
		var bytes = data;
		instanceCount = 0;
		active = false;

		var r = renderer;
		var bd = bitmapData;
		var sh = shader;
		var ctx = r.__context3D;
		try
		{
			r.__setBlendMode(blendMode);
			r.setShader(sh);
			r.applyBitmapData(bd, smooth);
			r.updateShader();

			var vertexBuffer = bd.getVertexBuffer(ctx);
			if (sh.__position != null) ctx.setVertexBufferAt(sh.__position.index, vertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			if (sh.__textureCoord != null) ctx.setVertexBufferAt(sh.__textureCoord.index, vertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);

			if (__instanceBuffer == null)
			{
				__instanceBuffer = ctx.createVertexBuffer(MAX_INSTANCES, FLOATS_PER_INSTANCE, Context3DBufferUsage.DYNAMIC_DRAW);
			}
			var f32 = new Float32Array(bytes.length);
			for (i in 0...bytes.length) f32[i] = bytes[i];
			__instanceBuffer.uploadFromTypedArray(f32);

			var attribs:Array<ShaderParameter<Float>> = [];
			for (n in 0...7)
			{
				var p = Reflect.field(sh.data, "i_data" + n);
				if (p != null)
				{
					var param:ShaderParameter<Float> = cast p;
					ctx.setInstanceBufferAt(param.index, __instanceBuffer, n * 4, Context3DVertexBufferFormat.FLOAT_4);
					attribs.push(param);
				}
			}

			var indexBuffer = bd.getIndexBuffer(ctx);
			ctx.drawTrianglesInstanced(indexBuffer, 0, count * 2, count);

			for (param in attribs)
			{
				ctx.clearInstanceBufferAt(param.index);
				ctx.setVertexBufferAt(param.index, null);
			}
			r.__clearShader();
		}
		catch (e:Dynamic)
		{
			try r.__clearShader() catch (e2:Dynamic) {}
		}

		flushing = false;
	}
}
#else
class MetalInstanceBatch
{
	public static var activeShader(get, never):Shader;
	static function get_activeShader():Shader return null;
	public static function tryAdd(bitmap:Bitmap, renderer:OpenGLRenderer):Bool return false;
	public static function flush():Void {}
}
#end
#end
