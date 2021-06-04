//
//  MLPatchExtractor.swift
//  MLPatchExtractor
//
//  Created by Petr Bobák on 04/10/2019.
//  Copyright © 2019 Petr Bobák. All rights reserved.
//

import UIKit
import CoreML

public protocol MLPatchExtractorProtocol {
    /// Factory method that creates new instance of MLFeatureProvider
    static func create(image: CVPixelBuffer) -> MLFeatureProvider
}

public enum MLPatchSampling {
    case random
    case uniform
}

public class MLPatchExtractor<Element: MLPatchExtractorProtocol> {
    
    /**
     Extracts patches of size `patchSize` from `image` sampled equidistantly and uniformly from a predefined grid given by `patchDistribution` parameter.
     
     - Parameters:
        - image: The source image for patch extraction.
        - patchSize: The size of patches.
        - patchDistribution: The definition of patch distribution grid size.
        For example, `CGSize(width: 7, height: 10)` means that a total of 70 patches will be extracted from a grid of 7x10 equidistantly and uniformly positioned patches.
        - maskRectangle: The image area from which patches will be extracted.
     
     - Returns: A tuple (array of instances subclassed from `MLFeatureProvider`, array of rects of patches in `image` space).
     
     */
    static public func extract(image: UIImage, patchSize: CGSize, patchDistribution distribution: CGSize, maskRectangle: CGRect) -> ([Element]?, [CGRect]?) {
        if patchSize.width > maskRectangle.width {
            print("Height of the patch should be less than the height of the image.")
            return (nil, nil)
        }
        
        if patchSize.height > maskRectangle.height {
            print("Width of the patch should be less than the width of the image.")
            return (nil, nil)
        }
        
        let origins = uniformSampling(maskRect: maskRectangle, patchSize: patchSize, patchDistribution: distribution)
        return extract(image: image, patchSize: patchSize, origins: origins)
    }
    
    /**
     Extracts patches of size `patchSize` from `image` sampled at positions within image space given by `sampling` parameter.
     
     - Parameters:
        - image: The source image for patch extraction.
        - patchSize: The size of patches.
        - count: The number of patches to generate (in case of `uniform` the number of generated patches can be slightly larger or smaller in favor of uniform coverage).
        - sampling: The sampling method of patches' positions (`random` or `uniform`, for more details, see `MLPatchSampling`).
        - maskRectangle: The image area from which patches will be extracted.
     
     - Returns: A tuple (array of instances subclassed from `MLFeatureProvider`, array of rects of patches in `image` space).
     
     */
    static public func extract(image: UIImage, patchSize: CGSize, count: Int, sampling: MLPatchSampling = .random, maskRectangle: CGRect) -> ([Element]?, [CGRect]?) {

        if patchSize.width > maskRectangle.width {
            print("Height of the patch should be less than the height of the image.")
            return (nil, nil)
        }
        
        if patchSize.height > maskRectangle.height {
            print("Width of the patch should be less than the width of the image.")
            return (nil, nil)
        }
        
        let origins = getSamplingCoordinates(sampling: sampling, maskRect: maskRectangle, patchSize: patchSize, count: count)
        return extract(image: image, patchSize: patchSize, origins: origins)
    }
    
    /**
     Extracts `maxPatches` patches of size `patchSize` from `image` sampled at positions within image space given by `sampling` parameter.
     
     - Parameters:
        - image: The source image for patch extraction.
        - patchSize: The size of patch/es.
        - count: The number of patches to generate (in case of `uniform` the number of generated patches can be slightly larger or smaller in favor of uniform coverage).
        - sampling: The method to sample patches (`random` or `uniform`, for more details see `MLPatchSampling`).
        - maskFactor: The percent of the image area to generate from (centered to center o the input image).
     
     - Returns: A tuple (array of instances subclassed from `MLFeatureProvider`, array of rects of patches in `image` space).
     
     */
    static public func extract(image: UIImage, patchSize: CGSize, count: Int, sampling: MLPatchSampling = .random, maskFactor: CGFloat = 1.0) -> ([Element]?, [CGRect]?, CGRect?) {

        var maskRectangle = CGRect(origin: .zero, size: image.size)
        if maskFactor < 1.0 {
           maskRectangle = CGRect(x: image.size.width / 2 - (maskFactor * image.size.width) / 2,
                                  y: image.size.height / 2 - (maskFactor * image.size.height) / 2,
                                  width: maskFactor * image.size.width,
                                  height: maskFactor * image.size.height)
        }

        let (patches, rects) = extract(image: image, patchSize: patchSize, count: count, sampling: sampling, maskRectangle: maskRectangle)
        return (patches, rects, maskRectangle)
    }
    
    /**
     Extracts patches of size `patchSize` given by its `origins` from `image`.

     - Parameters:
        - image: The source image for patch extraction.
        - patchSize: The size of patches.
        - origins: The array of patches' origins (i.e., `[CGPoint]`). Patch origin is defined as the upper left corner in the coordinate system with its origin also in the upper left corner.

     - Returns: A tuple (array of instances subclassed from `MLFeatureProvider`, array of rects of patches in `image` space).

     */
    static public func extract(image: UIImage, patchSize: CGSize, origins: [CGPoint]) -> ([Element]?, [CGRect]?) {
        var patchArray: [Element] = []
        var patchRects: [CGRect] = []

        guard let cgimage = image.cgImage else {
            print("CGImage is not available.")
            return (nil, nil)
        }

        let ciimage = CIImage(cgImage: cgimage)
        let ciContext = CIContext()

        // Transform patch orgin coords with system origin at UL corner (UIKit) to coordinate system with origin at LL (Core Image)
        let ciImageSystemTransform = CGAffineTransform(translationX: 0, y: image.size.height).scaledBy(x: 1.0, y: -1.0)

        for origin in origins {
            // CIImage has origin in lower left corner
            let cropRect = CGRect(origin: origin, size: patchSize)
            var croppedCIImage = ciimage.cropped(to: cropRect.applying(ciImageSystemTransform))

            // Fix cropped extend
            // https://stackoverflow.com/questions/8170336/core-image-after-using-cicrop-applying-a-compositing-filter-doesnt-line-up
            let ciResetOrigin = CGAffineTransform(translationX: -croppedCIImage.extent.origin.x, y: -croppedCIImage.extent.origin.y)
            croppedCIImage = croppedCIImage.transformed(by: ciResetOrigin)
            
            if let pixelBuffer = croppedCIImage.pixelBuffer(width: Int(patchSize.width), height: Int(patchSize.height), in: ciContext) {
                patchArray.append(Element.create(image: pixelBuffer) as! Element)
                patchRects.append(cropRect)
            }
        }

        return (patchArray, patchRects)
    }
    
    static private func extract_old(image: UIImage, patchSize: CGSize, origins: [CGPoint]) -> ([Element]?, [CGRect]?) {
        var patchArray: [Element] = []
        var patchRects: [CGRect] = []
        
        guard let cgimage = image.cgImage else {
            print("CGImage is not available.")
            return (nil, nil)
        }
        
        let ciimage = CIImage(cgImage: cgimage)
        
//            // Sometime is present sharp memory peak when creating CIImage from UIImage
//            guard let ciimage = CIImage(image: image) else {
//                print("CIImage is not available.")
//                return nil
//            }
        
        let ciContext = CIContext()
        
        // Transform patch orgin coords with system origin at UL corner (UIKit) to coordinate system with origin at LL (Core Image)
        let ciImageSystemTransform = CGAffineTransform(translationX: 0, y: image.size.height).scaledBy(x: 1.0, y: -1.0)
        
        for origin in origins {
            // CIImage has origin in lower left corner
            
            let cropRect = CGRect(origin: origin, size: patchSize)
            
//            // When cropped in CGImage format reference is probably hold to whole image
//            // resulting patch array is small, but during draw in UICollectionView the memory grows rapidly
//            let croppedImage = UIImage(cgImage: cgimage.cropping(to: cropRect)!)
            
            
            let croppedCIImage = ciimage.cropped(to: cropRect.applying(ciImageSystemTransform))
//            let start = CACurrentMediaTime()
            let croppedCGImage = ciContext.createCGImage(croppedCIImage, from: croppedCIImage.extent)
//            let croppedCGImage = cgimage.cropping(to: cropRect)
//            let croppedImage = UIImage(cgImage: croppedCGImage!)
            
//            let pixelBuffer = croppedCGImage?.pixelBuffer()
//            let end = CACurrentMediaTime()
//            print("UIImage+CVPixelBuffer took: \(end - start) seconds")
            
            if let pixelBuffer = croppedCGImage?.pixelBuffer(width: Int(patchSize.width), height: Int(patchSize.height)) {
                patchArray.append(Element.create(image: pixelBuffer) as! Element)
                patchRects.append(cropRect)
            }
        }
        
        return (patchArray, patchRects)
    }
    
    static private func extract_pixelbuffer(image: UIImage, patchSize: CGSize, origins: [CGPoint]) -> ([Element]?, [CGRect]?) {
        var patchArray: [Element] = []
        var patchRects: [CGRect] = []

        guard let pixelBuffer = image.pixelBuffer(width: Int(image.size.width), height: Int(image.size.height)) else {
            print("CGImage is not available.")
            return (nil, nil)
        }

        for origin in origins {
            let cropRect = CGRect(origin: origin, size: patchSize)
            if let pixelBuffer = pixelBuffer.cropping(to: cropRect) {
                patchArray.append(Element.create(image: pixelBuffer) as! Element)
                patchRects.append(cropRect)
            }
        }

        return (patchArray, patchRects)
    }
    
    static private func extract_cgimage(image: UIImage, patchSize: CGSize, origins: [CGPoint]) -> ([Element]?, [CGRect]?) {
        var patchArray: [Element] = []
        var patchRects: [CGRect] = []
        
        guard let cgimage = image.cgImage else {
            print("CGImage is not available.")
            return (nil, nil)
        }
        
        for origin in origins {
            let cropRect = CGRect(origin: origin, size: patchSize)
            
            // When cropped in CGImage format reference is probably hold to whole image
            // resulting patch array is small, but during draw in UICollectionView the memory grows rapidly
            let croppedImageRef = cgimage.cropping(to: cropRect)
            
            if let pixelBuffer = croppedImageRef?.pixelBuffer(width: Int(patchSize.width), height: Int(patchSize.height)) {
                patchArray.append(Element.create(image: pixelBuffer) as! Element)
                patchRects.append(cropRect)
            }
        }
        
        return (patchArray, patchRects)
    }
    
    static private func getSamplingCoordinates(sampling: MLPatchSampling, maskRect: CGRect, patchSize: CGSize, count: Int) -> [CGPoint] {
        switch sampling {
        case .random:
            return randomSampling(maskRect: maskRect, patchSize: patchSize, count: count)
            
        case .uniform:
            return uniformSampling(maskRect: maskRect, patchSize: patchSize, patchDistribution: patchDistribution(maskRect: maskRect, patchSize: patchSize, count: count))
        }
    }
    
    static private func randomSampling(maskRect: CGRect, patchSize: CGSize, count: Int) -> [CGPoint] {
        var origins: [CGPoint] = []
        
        for _ in 0..<count {
            let randX = Int.random(in: Int(maskRect.minX) ... Int(maskRect.maxX-patchSize.width))
            let randY = Int.random(in: Int(maskRect.minY) ... Int(maskRect.maxY-patchSize.height))
            origins.append(CGPoint(x: randX, y: randY))
        }
        
        return origins
    }
    
    static private func patchDistribution(maskRect: CGRect, patchSize: CGSize, count: Int) -> CGSize {
        var numPatchesW = floor(maskRect.width / patchSize.width)
        var numPatchesH = floor(maskRect.height / patchSize.height)
        
        var w_dec = false;
        while numPatchesW * numPatchesH > CGFloat(count) {
            if w_dec {
                numPatchesW -= 1;
            } else {
                numPatchesH -= 1;
            }
            w_dec.toggle()
        }
        
        while numPatchesW * numPatchesH < CGFloat(count) {
            if w_dec {
                numPatchesW += 1;
            } else {
                numPatchesH += 1;
            }
            w_dec.toggle()
        }
        
        return CGSize(width: numPatchesW, height: numPatchesH)
    }
    
    static private func uniformSampling(maskRect: CGRect, patchSize: CGSize, patchDistribution distribution: CGSize) -> [CGPoint] {
        let offsetX = floor((maskRect.width - distribution.width * patchSize.width) / (distribution.width - 1));
        let offsetY = floor((maskRect.height - distribution.height * patchSize.height) / (distribution.height - 1));
        
        let step = CGPoint(x: patchSize.width + offsetX, y: patchSize.height + offsetY)
        var currentOrigin = maskRect.origin
        
        var origins: [CGPoint] = []
        for _ in 0..<Int(distribution.width * distribution.height) {
            origins.append(currentOrigin)
            
            if currentOrigin.x + step.x + patchSize.width <= maskRect.maxX {
                currentOrigin.x += step.x
            } else {
                currentOrigin.y += step.y
                currentOrigin.x = maskRect.origin.x
            }
        }
        
        return origins
    }
}

extension CVPixelBuffer {
    func cropping(to rect: CGRect) -> CVPixelBuffer? {
        let flags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0)) else {
          return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(self, flags) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(self) else {
          print("Error: could not get pixel buffer base address")
          return nil
        }
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(self)
        let offset = Int(rect.origin.y)*srcBytesPerRow + Int(rect.origin.x)*4

        let releaseCallback: CVPixelBufferReleaseBytesCallback = { _, baseAddress in
            guard let baseAddress = baseAddress else { return }
            free(UnsafeMutableRawPointer(mutating: baseAddress))
        }
        
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue]
        
        var croppedPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(nil,
                                                  Int(rect.size.width),
                                                  Int(rect.size.height),
                                                  CVPixelBufferGetPixelFormatType(self),
                                                  baseAddress.advanced(by: offset),
                                                  CVPixelBufferGetBytesPerRow(self),
                                                  releaseCallback,
                                                  nil, attrs as CFDictionary, &croppedPixelBuffer)
        if status != kCVReturnSuccess {
          print("Error: could not create new pixel buffer")
          return nil
        }
        
        return croppedPixelBuffer
    }
}
