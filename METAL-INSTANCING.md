# Metal instanced bitmap batching (Codename Metal fork)

This fork adds an opt-in (default-on with -Dmetal_instancing) instanced rendering path
for the OpenFL bitmap channel:

- openfl.display.InstancedDisplayObjectShader - DisplayObjectShader variant that reads the
  model-view-projection matrix, alpha and colour transform from the per-instance attributes
  i_data0..i_data6.
- openfl.display._internal.MetalInstanceBatch - batches consecutive Bitmap draws that share
  a BitmapData/blend state and submits them with one drawElementsInstanced call.  The batch
  is flushed on every Context3D draw/clear/present, shader/blend/mask change and render-target
  switch, so draw order is preserved.
- Context3D.drawTrianglesInstanced(), setInstanceBufferAt(), clearInstanceBufferAt() -
  public API for custom instanced rendering.
- Metal backend hooks: the backend maps i_dataN attributes to bgfx's instance data buffer
  (setInstanceDataBuffer, 16-byte float4 slots) and implements glVertexAttribDivisor.

Build with -Dmetal_instancing and the Metal backend from Codename-Metal.  Disable at runtime
from Flixel with FlxG.metalInstancing = false.
