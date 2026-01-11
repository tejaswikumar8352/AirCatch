//
//  MetalVideoView.swift
//  AirCatchClient
//
//  High-performance Metal-based video renderer for zero-copy frame display.
//

import SwiftUI
import MetalKit
import VideoToolbox
import CoreVideo

/// SwiftUI wrapper for the Metal video view.
struct MetalVideoView: UIViewRepresentable {
    @Binding var pixelBuffer: CVPixelBuffer?
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator
        mtkView.framebufferOnly = false
        // Use sRGB render target so gamma is handled correctly.
        // Without this, video often looks “washed out” / less vibrant on iPad.
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        // Use Display P3 colorspace on iPad (wide gamut) to match Mac's P3 output
        if let metalLayer = mtkView.layer as? CAMetalLayer {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
            metalLayer.wantsExtendedDynamicRangeContent = true
        }
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true // Event-driven rendering (critical for power saving)
        mtkView.preferredFramesPerSecond = 60
        // Disable vsync wait for immediate frame display (lowest latency)
        mtkView.presentsWithTransaction = false
        context.coordinator.setupMetal(device: mtkView.device!, view: mtkView)
        
        // Subscribe to memory warnings for cache flushing
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.flushTextureCache()
        }
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.currentPixelBuffer = pixelBuffer
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> MetalVideoRenderer {
        MetalVideoRenderer()
    }
}

/// Metal renderer for displaying CVPixelBuffer frames.
class MetalVideoRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var textureCache: CVMetalTextureCache!
    private var samplerState: MTLSamplerState!
    
    var currentPixelBuffer: CVPixelBuffer?
    private var viewportSize: CGSize = .zero
    private var frameCount: Int = 0
    
    func setupMetal(device: MTLDevice, view: MTKView) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        // Create texture cache
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        textureCache = cache
        
        // Create sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        
        // Create pipeline
        setupPipeline(view: view)
    }
    
    /// Flush the texture cache to free memory (call on memory warning)
    func flushTextureCache() {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }
    
    private func setupPipeline(view: MTKView) {
        let library = device.makeDefaultLibrary() ?? makeShaderLibrary()
        
        guard let library = library else {
            AirCatchLog.error(" Failed to create shader library")
            return
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            AirCatchLog.error(" Failed to create pipeline: \(error)")
        }
    }
    
    private func makeShaderLibrary() -> MTLLibrary? {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                       constant float2 *vertices [[buffer(0)]],
                                       constant float2 *texCoords [[buffer(1)]]) {
            VertexOut out;
            out.position = float4(vertices[vertexID], 0.0, 1.0);
            out.texCoord = texCoords[vertexID];
            return out;
        }
        
        // Apply saturation boost to compensate for colorspace conversion losses
        float3 adjustSaturation(float3 color, float saturation) {
            float3 luminanceWeights = float3(0.2126, 0.7152, 0.0722);
            float luminance = dot(color, luminanceWeights);
            return mix(float3(luminance), color, saturation);
        }
        
        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                        texture2d<float> texture [[texture(0)]],
                                        sampler texSampler [[sampler(0)]]) {
            float4 color = texture.sample(texSampler, in.texCoord);
            // Boost saturation by ~8% to compensate for P3->sRGB conversion losses
            color.rgb = adjustSaturation(color.rgb, 1.08);
            return color;
        }
        """
        
        do {
            return try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            AirCatchLog.error(" Shader compilation failed: \(error)")
            return nil
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }
    
    func draw(in view: MTKView) {
        guard let pixelBuffer = currentPixelBuffer,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        frameCount += 1
        
        // Periodically flush texture cache to prevent memory buildup (every 300 frames ~5 seconds at 60fps)
        if frameCount % 300 == 0 {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
        
        // Create texture from pixel buffer
        guard let texture = createTexture(from: pixelBuffer) else {
            encoder.endEncoding()
            commandBuffer.commit()
            return
        }
        
        // Calculate fullscreen vertices
        let vertices = calculateFullscreenVertices()
        
        let texCoords: [SIMD2<Float>] = [
            SIMD2(0, 1), SIMD2(1, 1), SIMD2(0, 0),
            SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)
        ]
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(vertices, length: MemoryLayout<SIMD2<Float>>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(texCoords, length: MemoryLayout<SIMD2<Float>>.stride * texCoords.count, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        func makeTexture(_ pixelFormat: MTLPixelFormat) -> MTLTexture? {
            var cvTexture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(
                nil,
                textureCache,
                pixelBuffer,
                nil,
                pixelFormat,
                width,
                height,
                0,
                &cvTexture
            )
            guard status == kCVReturnSuccess, let cvTex = cvTexture else {
                return nil
            }
            return CVMetalTextureGetTexture(cvTex)
        }

        // Prefer sRGB texture so sampling converts to linear correctly.
        // Fall back to non-sRGB if the pixel buffer doesn't support sRGB views.
        return makeTexture(.bgra8Unorm_srgb) ?? makeTexture(.bgra8Unorm)
    }
    
    /// Returns fullscreen vertices - fills entire viewport
    private func calculateFullscreenVertices() -> [SIMD2<Float>] {
        return [
            SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1),
            SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)
        ]
    }
}
