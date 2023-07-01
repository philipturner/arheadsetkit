//
//  SceneOcclusionTestingExecution.swift
//  ARHeadsetKit
//
//  Created by Philip Turner on 4/13/21.
//

#if !os(macOS)
import Metal
import simd

extension SceneOcclusionTester {
    
    func executeOcclusionTest() {
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Scene Occlusion Testing Command Buffer"
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = triangleIDTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(Double(UInt32.max), 0, 0, 0)
        renderPassDescriptor.depthAttachment.texture = renderDepthTexture
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.optLabel = "Scene Occlusion Testing - Render Pass"
        
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(.back)
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer,     layer: .occlusionVertex, index: 0)
        renderEncoder.setVertexBuffer(vertexDataBuffer, layer: .occlusionOffset, index: 1)
        renderEncoder.setVertexBuffer(reducedIndexBuffer,             offset: 0, index: 2)
        renderEncoder.setVertexBuffer(triangleIDBuffer,               offset: 0, index: 3)
        renderEncoder.drawPrimitives(type: .triangle, indirectBuffer: uniformBuffer,
                                     indirectBufferLayer: .occlusionTriangleInstanceCount)
        
        renderEncoder.endEncoding()
        
        
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Occlusion Testing - Compute Pass"
        
        computeEncoder.setComputePipelineState(checkSegmentationTexturePipelineState)
        computeEncoder.setTexture(triangleIDTexture, index: 0)
        
        sceneRenderer.segmentationTextureSemaphore.wait()
        guard let segmentationTexture = segmentationTexture else {
            return
        }
        computeEncoder.setTexture(segmentationTexture, index: 1)
        computeEncoder.dispatchThreads([ 256, 192 ], threadsPerThreadgroup: 1)
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
    }
    
    func executeColorUpdate() {
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Scene Color Update Command Buffer"
        
        var computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Color Update - Compute Pass 1"
        
        computeEncoder.setComputePipelineState(resampleColorTexturesPipelineState)
        sceneRenderer.colorTextureSemaphore.wait()
        
        guard let colorTextureY = colorTextureY,
              let colorTextureCbCr = colorTextureCbCr else {
            return
        }
        
        computeEncoder.setTexture(colorTextureY,             index: 0)
        computeEncoder.setTexture(colorTextureCbCr,          index: 1)
        
        computeEncoder.setTexture(resampledColorTextureY,    index: 2)
        computeEncoder.setTexture(resampledColorTextureCbCr, index: 3)
        computeEncoder.dispatchThreads([ 768, 576 ], threadsPerThreadgroup: [ 16, 16 ])
        
        computeEncoder.endEncoding()
        
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitEncoder.optLabel = "Scene Color Update - Generate Color Texture Mipmaps"
        
        blitEncoder.generateMipmaps(for: resampledColorTextureY_alias)
        blitEncoder.generateMipmaps(for: resampledColorTextureCbCr)
        blitEncoder.endEncoding()
        
        
        
        computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Color Update - Compute Pass 2"
        
        computeEncoder.setComputePipelineState(executeColorUpdatePipelineState)
        computeEncoder.setBuffer(vertexBuffer,             layer: .occlusionVertex,  index: 0)
        computeEncoder.setBuffer(vertexDataBuffer,         layer: .occlusionOffset,  index: 1)
        computeEncoder.setBuffer(reducedIndexBuffer,                      offset: 0, index: 2)
        computeEncoder.setBuffer(triangleIDBuffer,                        offset: 0, index: 3)
        
        computeEncoder.setBuffer(reducedColorBuffer,                      offset: 0, index: 4)
        computeEncoder.setBuffer(rasterizationComponentBuffer,            offset: 0, index: 5)
        computeEncoder.setBuffer(triangleMarkBuffer,       layer: .textureOffset,    index: 6)
        
        computeEncoder.setBuffer(triangleDataBuffer,       layer: .columnCount,      index: 7)
        computeEncoder.setBuffer(triangleDataBuffer,       layer: .columnOffset,     index: 8)
        computeEncoder.setBuffer(triangleDataBuffer,       layer: .columnOffsets256, index: 9)
        computeEncoder.setBuffer(expandedColumnOffsetBuffer,              offset: 0, index: 10)
        
        computeEncoder.setBuffer(smallTriangleColorBuffer, layer: .luma,             index: 11)
        computeEncoder.setBuffer(largeTriangleColorBuffer, layer: .luma,             index: 12)
        computeEncoder.setBuffer(smallTriangleColorBuffer, layer: .chroma,           index: 13)
        computeEncoder.setBuffer(largeTriangleColorBuffer, layer: .chroma,           index: 14)
        
        computeEncoder.setTexture(triangleIDTexture,         index: 0)
        computeEncoder.setTexture(resampledColorTextureY,    index: 1)
        computeEncoder.setTexture(resampledColorTextureCbCr, index: 2)
        computeEncoder.dispatchThreadgroups(indirectBuffer: uniformBuffer, indirectBufferLayer: .occlusionTriangleCount,
                                            threadsPerThreadgroup: 1)
        computeEncoder.endEncoding()
        commandBuffer.commit()
    }
    
}

// Since this declaration is `public`, it should be callable from any code that
// imports ARHeadsetKit as a Swift package. You could try calling it from the
// code in one of the tutorials (it will crash the tutorial though).
public func ARHK_InspectOcclusionTester() -> Data {
  // TODO: Fetch the framework's internal occlusion tester, and do it in a
  // thread-safe way. Then call `exportData`.
  let occlusionTester = 2 as Any as! SceneOcclusionTester
  
  // TODO: Find how many of the triangles are 'small', how many are 'large'.
  let numSmallTriangles = 1
  let numLargeTriangles = 1
  return occlusionTester.exportData(
    numSmallTriangles: numSmallTriangles, numLargeTriangles: numLargeTriangles)
}

extension SceneOcclusionTester {
  func exportData(numSmallTriangles: Int, numLargeTriangles: Int) -> Data {
    let bufferSize = numSmallTriangles * 320 + numLargeTriangles * 1280;
    let serializedBlocks = renderer.device.makeBuffer(length: bufferSize)!
    
    let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
    
    computeEncoder.setComputePipelineState(executeColorExportPipelineState)
    computeEncoder.setBuffer(vertexBuffer,             layer: .occlusionVertex,  index: 0)
    computeEncoder.setBuffer(vertexDataBuffer,         layer: .occlusionOffset,  index: 1)
    computeEncoder.setBuffer(reducedIndexBuffer,                      offset: 0, index: 2)
    
    computeEncoder.setBuffer(reducedColorBuffer,                      offset: 0, index: 4)
    computeEncoder.setBuffer(rasterizationComponentBuffer,            offset: 0, index: 5)
    computeEncoder.setBuffer(triangleMarkBuffer,       layer: .textureOffset,    index: 6)
    
    computeEncoder.setBuffer(triangleDataBuffer,       layer: .columnCount,      index: 7)
    computeEncoder.setBuffer(triangleDataBuffer,       layer: .columnOffset,     index: 8)
    computeEncoder.setBuffer(triangleDataBuffer,       layer: .columnOffsets256, index: 9)
    computeEncoder.setBuffer(expandedColumnOffsetBuffer,              offset: 0, index: 10)
    
    computeEncoder.setBuffer(smallTriangleColorBuffer, layer: .luma,             index: 11)
    computeEncoder.setBuffer(largeTriangleColorBuffer, layer: .luma,             index: 12)
    computeEncoder.setBuffer(smallTriangleColorBuffer, layer: .chroma,           index: 13)
    computeEncoder.setBuffer(largeTriangleColorBuffer, layer: .chroma,           index: 14)
    
    computeEncoder.setBuffer(serializedBlocks, offset: 0, index: 15)
    
    var _numSmallTriangles = UInt32(numSmallTriangles)
    computeEncoder.setBytes(&_numSmallTriangles, length: 4, index: 16)
    
    let numTriangles = numSmallTriangles + numLargeTriangles
    computeEncoder.dispatchThreads([ numTriangles, 1, 1 ], threadsPerThreadgroup: [ 128, 1, 1 ])
    
    computeEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    return Data(bytes: serializedBlocks.contents(), count: bufferSize)
  }
}
#endif
