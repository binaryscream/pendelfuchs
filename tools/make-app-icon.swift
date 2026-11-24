// SPDX-License-Identifier: GPL-3.0-or-later
//
// Erzeugt die App-Icons (1024 × 1024, vollflächig, ohne Transparenz) aus `design/app-icon-source.png`:
//   normal, dunkel (gleiches Bild – es ist ohnehin dunkel) und getönt (Graustufen, iOS färbt es ein).
//
// Die Vorlage hat abgerundete Ecken auf schwarzem Grund. iOS rundet selbst ab, deshalb wird das Quadrat
// ausgeschnitten, der hellere Rand entfernt und der Schwarzanteil in den Ecken mit der Nachbarfarbe gefüllt.
//
// Aufruf: swift tools/make-app-icon.swift design/app-icon-source.png App/Assets.xcassets/AppIcon.appiconset

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fatalError("Aufruf: make-app-icon.swift <Vorlage.png> <Ausgabeordner>") }
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Vorlage nicht lesbar") }

let width = image.width, height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let layout = CGImageAlphaInfo.noneSkipLast.rawValue

pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: rgb, bitmapInfo: layout)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
}

@inline(__always) func index(_ x: Int, _ y: Int) -> Int { y * width + x }
@inline(__always) func isBlack(_ i: Int) -> Bool {
    Int(pixels[i * 4]) + Int(pixels[i * 4 + 1]) + Int(pixels[i * 4 + 2]) < 24
}

let neighbours = [(1, 0), (-1, 0), (0, 1), (0, -1)]

// 1. Außenbereich: schwarz und mit dem Bildrand verbunden.
var outside = [Bool](repeating: false, count: width * height)
var queue: [Int] = []
func seed(_ x: Int, _ y: Int) {
    let i = index(x, y)
    if !outside[i], isBlack(i) { outside[i] = true; queue.append(i) }
}
for x in 0..<width { seed(x, 0); seed(x, height - 1) }
for y in 0..<height { seed(0, y); seed(width - 1, y) }
var head = 0
while head < queue.count {
    let i = queue[head]; head += 1
    let x = i % width, y = i / width
    for (dx, dy) in neighbours {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
        let j = index(nx, ny)
        if !outside[j], isBlack(j) { outside[j] = true; queue.append(j) }
    }
}

// 2. Rahmen der Form
var minX = width, maxX = 0, minY = height, maxY = 0
for y in 0..<height { for x in 0..<width where !outside[index(x, y)] {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }

// 3. Abstand zum Außenbereich (Schachbrett-Näherung) → „vertrauenswürdig“ = weit genug innen, ohne hellen Rand
let rim = 16
var distance = [Int](repeating: Int.max, count: width * height)
queue = []
for i in 0..<outside.count where outside[i] { distance[i] = 0; queue.append(i) }
head = 0
while head < queue.count {
    let i = queue[head]; head += 1
    if distance[i] >= rim + 1 { continue }
    let x = i % width, y = i / width
    for (dx, dy) in neighbours {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
        let j = index(nx, ny)
        if distance[j] == Int.max { distance[j] = distance[i] + 1; queue.append(j) }
    }
}
let trusted = distance.map { $0 > rim }

// 4. Alles Nicht-Vertrauenswürdige (Ecken, Rand) mit der Farbe des nächsten vertrauenswürdigen Pixels füllen
var filled = [Bool](repeating: false, count: width * height)
queue = []
for i in 0..<trusted.count where trusted[i] { filled[i] = true; queue.append(i) }
head = 0
while head < queue.count {
    let i = queue[head]; head += 1
    let x = i % width, y = i / width
    for (dx, dy) in neighbours {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
        let j = index(nx, ny)
        if !filled[j] {
            filled[j] = true
            for c in 0..<3 { pixels[j * 4 + c] = pixels[i * 4 + c] }
            queue.append(j)
        }
    }
}

// 5. Quadrat in der Mitte der Form ausschneiden
let side = min(maxX - minX, maxY - minY) + 1
let originX = minX + ((maxX - minX + 1) - side) / 2
let originY = minY + ((maxY - minY + 1) - side) / 2

func renderIcon(gray: Bool) -> CGImage {
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let full = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: rgb, bitmapInfo: CGBitmapInfo(rawValue: layout), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)!
    let crop = full.cropping(to: CGRect(x: originX, y: originY, width: side, height: side))!
    let space = gray ? CGColorSpaceCreateDeviceGray() : rgb
    let info = gray ? CGImageAlphaInfo.none.rawValue : layout
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: info)!
    context.interpolationQuality = .high
    context.draw(crop, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    return context.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = outputURL.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("\(name) nicht schreibbar") }
}

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
let color = renderIcon(gray: false)
write(color, "AppIcon.png")
write(color, "AppIcon-Dark.png")
write(renderIcon(gray: true), "AppIcon-Tinted.png")
print("Icons geschrieben nach \(outputURL.path) (Quadrat \(side) px aus \(width)×\(height))")
