// SPDX-License-Identifier: GPL-3.0-or-later
//
// Zeichnet das App-Icon von Fahrplan XL (1024 × 1024) in drei Varianten:
// normal, dunkel und getönt (iOS 18). Aufruf:
//   swift tools/make-app-icon.swift App/Assets.xcassets/AppIcon.appiconset
//
// Motiv: eine Abfahrtstafel – weiße Karte mit drei Zeilen (Linienkennung + Ziel + Minuten)
// in den Linienfarben der App (S-Bahn grün, Straßenbahn rot, Bus orange).

import AppKit
import CoreGraphics

let size = 1024.0

struct Palette {
    var backgroundTop: CGColor
    var backgroundBottom: CGColor
    var card: CGColor
    var bar: CGColor
    var badges: [CGColor]
    var badgeText: CGColor
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let light = Palette(
    backgroundTop: rgb(40, 140, 255), backgroundBottom: rgb(0, 72, 186),
    card: rgb(255, 255, 255), bar: rgb(203, 211, 224),
    badges: [rgb(0, 150, 80), rgb(215, 26, 33), rgb(245, 140, 0)],
    badgeText: rgb(255, 255, 255))

let dark = Palette(
    backgroundTop: rgb(30, 34, 44), backgroundBottom: rgb(10, 12, 18),
    card: rgb(44, 48, 58), bar: rgb(92, 99, 114),
    badges: [rgb(20, 170, 95), rgb(230, 52, 58), rgb(250, 155, 20)],
    badgeText: rgb(255, 255, 255))

// Getönt: Graustufen auf Schwarz – iOS färbt nach Helligkeit ein.
let tinted = Palette(
    backgroundTop: rgb(0, 0, 0), backgroundBottom: rgb(0, 0, 0),
    card: rgb(255, 255, 255, 0.22), bar: rgb(255, 255, 255, 0.55),
    badges: [rgb(255, 255, 255), rgb(255, 255, 255, 0.85), rgb(255, 255, 255, 0.7)],
    badgeText: rgb(0, 0, 0))

func draw(_ p: Palette, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError() }

    // Hintergrund (iOS rundet die Ecken selbst ab – Icon muss vollflächig sein).
    let gradient = CGGradient(colorsSpace: space, colors: [p.backgroundTop, p.backgroundBottom] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    // Karte
    let card = CGRect(x: 102, y: 172, width: 820, height: 680)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0, 0, 0, 0.28))
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 96, cornerHeight: 96, transform: nil))
    ctx.setFillColor(p.card)
    ctx.fillPath()
    ctx.restoreGState()

    // Drei Zeilen: Linienkennung, Ziel-Balken, Minuten-Balken
    let rowHeight = 136.0
    let gap = 56.0
    let totalHeight = 3 * rowHeight + 2 * gap
    var y = card.midY + totalHeight / 2 - rowHeight
    let destinationWidths = [270.0, 215.0, 245.0]
    let labels = ["S1", "7", "62"]

    for row in 0..<3 {
        // Linienkennung (Straßenbahn eckiger, wie in der App)
        let badge = CGRect(x: card.minX + 64, y: y, width: 230, height: rowHeight)
        let radius = row == 1 ? 30.0 : rowHeight / 2
        ctx.addPath(CGPath(roundedRect: badge, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(p.badges[row])
        ctx.fillPath()

        // Beschriftung der Linienkennung
        let font = NSFont.systemFont(ofSize: 92, weight: .heavy)
        let attributed = NSAttributedString(string: labels[row], attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: p.badgeText)!,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: badge.midX - bounds.width / 2 - bounds.minX,
                                   y: badge.midY - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)

        // Ziel-Balken
        let barHeight = 48.0
        let destination = CGRect(x: badge.maxX + 46, y: y + (rowHeight - barHeight) / 2,
                                 width: destinationWidths[row], height: barHeight)
        ctx.addPath(CGPath(roundedRect: destination, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
        ctx.setFillColor(p.bar)
        ctx.fillPath()

        // Minuten-Balken (rechtsbündig, kräftiger)
        let minutes = CGRect(x: card.maxX - 64 - 84, y: y + (rowHeight - 68) / 2, width: 84, height: 68)
        ctx.addPath(CGPath(roundedRect: minutes, cornerWidth: 24, cornerHeight: 24, transform: nil))
        ctx.setFillColor(p.badges[row])
        ctx.fillPath()

        y -= rowHeight + gap
    }

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try draw(light, to: out.appending(path: "AppIcon.png"))
try draw(dark, to: out.appending(path: "AppIcon-Dark.png"))
try draw(tinted, to: out.appending(path: "AppIcon-Tinted.png"))
print("Icons geschrieben nach \(out.path)")
