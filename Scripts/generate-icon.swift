import AppKit
import CoreGraphics
import Foundation

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "build/Assets/AppIcon.png"

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [red / 255, green / 255, blue / 255, alpha])!
}

func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func line(_ context: CGContext, from start: CGPoint, to end: CGPoint,
          width: CGFloat, color: CGColor) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
}

func noteHead(_ context: CGContext, at point: CGPoint) {
    context.saveGState()
    context.translateBy(x: point.x, y: point.y)
    context.rotate(by: -.pi / 9)
    let rect = CGRect(x: -78, y: -47, width: 156, height: 94)
    context.setShadow(offset: .zero, blur: 23, color: color(90, 242, 224, 0.48))
    context.setFillColor(color(145, 248, 224))
    context.fillEllipse(in: rect)
    context.restoreGState()
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("아이콘 비트맵을 만들 수 없습니다.")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
context.clear(canvas)
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

let tile = rounded(CGRect(x: 68, y: 64, width: 888, height: 888), radius: 212)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 20), blur: 34,
                  color: color(3, 13, 33, 0.36))
context.addPath(tile)
context.setFillColor(color(17, 32, 64))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tile)
context.clip()
let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [color(15, 25, 57), color(31, 72, 105)] as CFArray,
                            locations: [0, 1])!
context.drawLinearGradient(background,
                           start: CGPoint(x: 180, y: 90), end: CGPoint(x: 850, y: 925),
                           options: [])

// A quiet piano-roll grid sits behind the score and stays visible at large sizes.
for x in stride(from: CGFloat(210), through: 850, by: 96) {
    line(context, from: CGPoint(x: x, y: 210), to: CGPoint(x: x, y: 817),
         width: 5, color: color(152, 209, 225, 0.10))
}
for y in stride(from: CGFloat(218), through: 818, by: 74) {
    line(context, from: CGPoint(x: 166, y: y), to: CGPoint(x: 856, y: y),
         width: 5, color: color(152, 209, 225, 0.10))
}

// Five lines make the notation legible even when the icon is reduced.
for y in [320, 402, 484, 566, 648] {
    line(context, from: CGPoint(x: 168, y: y), to: CGPoint(x: 848, y: y),
         width: 12, color: color(231, 247, 255, 0.34))
}

// Two joined notes form the main silhouette.
let stemColor = color(145, 248, 224)
line(context, from: CGPoint(x: 421, y: 506), to: CGPoint(x: 421, y: 279),
     width: 26, color: stemColor)
line(context, from: CGPoint(x: 656, y: 424), to: CGPoint(x: 656, y: 227),
     width: 26, color: stemColor)
context.move(to: CGPoint(x: 410, y: 271))
context.addLine(to: CGPoint(x: 669, y: 213))
context.addLine(to: CGPoint(x: 669, y: 260))
context.addLine(to: CGPoint(x: 410, y: 318))
context.closePath()
context.setFillColor(stemColor)
context.fillPath()
noteHead(context, at: CGPoint(x: 349, y: 548))
noteHead(context, at: CGPoint(x: 584, y: 466))

// Rectangles echo editable MIDI notes without competing with the music symbol.
context.setFillColor(color(130, 221, 231, 0.48))
context.addPath(rounded(CGRect(x: 220, y: 736, width: 210, height: 31), radius: 15))
context.fillPath()
context.addPath(rounded(CGRect(x: 481, y: 783, width: 188, height: 31), radius: 15))
context.fillPath()

// The warm vertical playhead is the editor's identifying accent.
context.setShadow(offset: .zero, blur: 22, color: color(255, 105, 97, 0.55))
line(context, from: CGPoint(x: 766, y: 254), to: CGPoint(x: 766, y: 822),
     width: 18, color: color(255, 121, 104))
context.setFillColor(color(255, 151, 122))
context.fillEllipse(in: CGRect(x: 742, y: 206, width: 48, height: 48))
context.setShadow(offset: .zero, blur: 0)
context.restoreGState()

context.addPath(tile)
context.setStrokeColor(color(195, 233, 255, 0.20))
context.setLineWidth(6)
context.strokePath()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("PNG를 만들 수 없습니다.")
}
let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try data.write(to: url)
print(url.path)
