import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func c(_ r: Double,_ g: Double,_ b: Double) -> CGColor { CGColor(red: r/255, green: g/255, blue: b/255, alpha: 1) }

func writeGradient(_ path: String, _ size: CGSize, _ colors: [CGColor], _ locs: [CGFloat], _ s: CGPoint, _ e: CGPoint) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(grad, start: CGPoint(x: s.x*size.width, y: s.y*size.height), end: CGPoint(x: e.x*size.width, y: e.y*size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

let sz = CGSize(width: 1170, height: 2532)
let dir = CommandLine.arguments[1]
// Aurora: teal -> green -> violet, diagonal
writeGradient("\(dir)/preset_bg_aurora.jpg", sz, [c(24,72,86), c(34,140,120), c(96,74,180)], [0,0.5,1], CGPoint(x:0,y:1), CGPoint(x:1,y:0))
// Dusk: deep indigo -> magenta -> warm orange, vertical
writeGradient("\(dir)/preset_bg_dusk.jpg", sz, [c(30,22,60), c(150,52,120), c(240,120,70)], [0,0.55,1], CGPoint(x:0.2,y:1), CGPoint(x:0.8,y:0))
// Nebula: near-black -> deep blue -> purple, diagonal
writeGradient("\(dir)/preset_bg_nebula.jpg", sz, [c(10,12,26), c(28,36,86), c(78,44,120)], [0,0.5,1], CGPoint(x:0,y:0), CGPoint(x:1,y:1))
