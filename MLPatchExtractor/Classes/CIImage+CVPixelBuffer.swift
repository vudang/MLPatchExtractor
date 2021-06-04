//
//  CIImage+CVPixelBuffer.swift
//  PatchExtractor
//
//  Created by Petr Bobák on 09/05/2019.
//  Copyright © 2019 Petr Bobák. All rights reserved.
//
import UIKit

extension CIImage {
    public func pixelBuffer(width: Int, height: Int, in context: CIContext) -> CVPixelBuffer? {
        var maybePixelBuffer: CVPixelBuffer?
        
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue]
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32ARGB,
                                         attrs as CFDictionary,
                                         &maybePixelBuffer)
        
        guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
            return nil
        }
        
        let flags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, flags) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, flags) }
        
        context.render(self,
                       to: pixelBuffer,
                       bounds: CGRect(origin: CGPoint(x: 0, y: 0), size: extent.size),
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return pixelBuffer
    }
    
    public func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let context = CIContext()
        return pixelBuffer(width: width, height: height, in: context)
    }
}
