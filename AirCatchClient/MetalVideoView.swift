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
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1) // Black background for letterboxing
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true // Event-driven rendering (critical for power saving)
        mtkView.preferredFramesPerSecond = 60
        context.coordinator.setupMetal(device: mtkView.device!, view: mtkView)
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
    
    private func setupPipeline(view: MTKView) {
        let library = device.makeDefaultLibrary() ?? makeShaderLibrary()
        
        guard let library = library else {
            NSLog("[MetalVideoRenderer] Failed to create shader library")
            return
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("[MetalVideoRenderer] Failed to create pipeline: \(error)")
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
        
        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                        texture2d<float> texture [[texture(0)]],
                                        sampler texSampler [[sampler(0)]]) {
            return texture.sample(texSampler, in.texCoord);
        }
        """
        
        do {
            return try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            NSLog("[MetalVideoRenderer] Shader compilation failed: \(error)")
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
        
        // Create texture from pixel buffer
        guard let texture = createTexture(from: pixelBuffer) else {
            encoder.endEncoding()
            commandBuffer.commit()
            return
        }
        
        // Calculate aspect-fit vertices
        let vertices = calculateAspectFitVertices(
            textureSize: CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer)),
            viewSize: viewportSize
        )
        
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
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
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
    
    private func calculateAspectFitVertices(textureSize: CGSize, viewSize: CGSize) -> [SIMD2<Float>] {
        guard viewSize.width > 0 && viewSize.height > 0 else {
            return [
                SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1),
                SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)
            ]
        }
        
        let textureAspect = textureSize.width / textureSize.height
        let viewAspect = viewSize.width / viewSize.height
        
        var scaleX: Float = 1.0
        var scaleY: Float = 1.0
        
        if textureAspect > viewAspect {
            // Texture is wider - fit to width, letterbox top/bottom
            scaleY = Float(viewAspect / textureAspect)
        } else {
            // Texture is taller - fit to height, pillarbox sides
            scaleX = Float(textureAspect / viewAspect)
        }
        
        return [
            SIMD2(-scaleX, -scaleY), SIMD2(scaleX, -scaleY), SIMD2(-scaleX, scaleY),
            SIMD2(scaleX, -scaleY), SIMD2(scaleX, scaleY), SIMD2(-scaleX, scaleY)
        ]
    }
}
