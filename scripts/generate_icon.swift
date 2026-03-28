#!/usr/bin/env swift
import AppKit

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift generate_icon.swift <output_directory>")
    exit(1)
}
let outputDir = CommandLine.arguments[1]

let S = 1024.0
let cx = S / 2, cy = S * 0.50
let R = S * 0.27
let maxHW = S * 0.046
let minHW = S * 0.001

// Gap at upper-left (~10:30 position)
// SVG y-down: 0°=right, 90°=down, 180°=left, 270°=up
// 10:30 ≈ 225° in SVG coords
let gapCenter = 5.0 * Double.pi / 4.0
let halfGap = 14.0 * .pi / 180

let arcStart = gapCenter + halfGap   // bold brush lands (~11 o'clock)
let arcEnd = gapCenter + 2 * .pi - halfGap  // thin tail fades (~10 o'clock)

// Asymmetric width: bold start, long gradual taper to wispy thin tail
func hw(_ t: Double) -> Double {
    if t < 0.04 {
        // Quick bold landing
        let e = t / 0.04
        let smooth = e * e * (3 - 2 * e)
        return maxHW * (0.65 + 0.35 * smooth)
    } else if t < 0.50 {
        // Full bold section with slight natural variation
        let wobble = 1.0 + 0.018 * sin(t * .pi * 6)
        return maxHW * wobble
    } else {
        // Long taper: thick → thin over remaining 50%
        let taperT = (t - 0.50) / 0.50
        let curve = (1.0 - taperT) * (1.0 - taperT) * (1.0 - taperT * 0.3)
        let wobble = 1.0 + 0.012 * sin(t * .pi * 8)
        return (minHW + (maxHW - minHW) * curve) * wobble
    }
}

let N = 400
var outer = [(Double, Double)]()
var inner = [(Double, Double)]()

for i in 0...N {
    let t = Double(i) / Double(N)
    let a = arcStart + (arcEnd - arcStart) * t
    let w = hw(t)
    outer.append((cx + (R + w) * cos(a), cy + (R + w) * sin(a)))
    inner.append((cx + (R - w) * cos(a), cy + (R - w) * sin(a)))
}

func f(_ v: Double) -> String { String(format: "%.1f", v) }

func shapePath(_ from: Int, _ to: Int) -> String {
    var d = "M \(f(outer[from].0)) \(f(outer[from].1))"
    for i in (from+1)...to { d += " L \(f(outer[i].0)) \(f(outer[i].1))" }
    for i in stride(from: to, through: from, by: -1) { d += " L \(f(inner[i].0)) \(f(inner[i].1))" }
    return d + " Z"
}

// Start tip: short bold fade-in (3%)
let startTipLen = N * 3 / 100
let startTipSegs = 8

// End tip: long wispy fade-out (25%)
let endTipLen = N * 25 / 100
let endTipSegs = 30

let bodyFrom = startTipLen - 1
let bodyTo = N - endTipLen + 2

var tips = ""

// Start tip: bold quick fade-in
for i in 0..<startTipSegs {
    let s0 = i * startTipLen / startTipSegs
    let s1 = min((i + 1) * startTipLen / startTipSegs, startTipLen)
    guard s0 < s1 else { continue }
    let t = Double(i + 1) / Double(startTipSegs)
    let op = sqrt(t)
    tips += "    <path d=\"\(shapePath(s0, s1))\" fill=\"#1a1a1a\" opacity=\"\(String(format: "%.3f", op))\"/>\n"
}

// End tip: long gradual wispy fade-out
for i in 0..<endTipSegs {
    let s0 = N - endTipLen + i * endTipLen / endTipSegs
    let s1 = min(N - endTipLen + (i + 1) * endTipLen / endTipSegs, N)
    guard s0 < s1 else { continue }
    let t = Double(endTipSegs - i) / Double(endTipSegs)
    let op = t * t * t
    tips += "    <path d=\"\(shapePath(s0, s1))\" fill=\"#1a1a1a\" opacity=\"\(String(format: "%.3f", op))\"/>\n"
}

let svg = """
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- White background with subtle border -->
  <rect width="1024" height="1024" rx="225" fill="white"/>
  <rect width="1024" height="1024" rx="225" fill="none" stroke="#d0d0d0" stroke-width="1.5"/>

  <!-- Enso brushstroke -->
  <g opacity="0.95">
\(tips)
    <path d="\(shapePath(bodyFrom, bodyTo))" fill="#1a1a1a"/>
  </g>
</svg>
"""

let svgPath = outputDir + "/icon.svg"
try! svg.write(toFile: svgPath, atomically: true, encoding: .utf8)
print("SVG saved: \(svgPath)")

// ── SVG → PNG ──
let iconSizes: [(pt: Int, sc: Int)] = [
    (16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)
]

guard let svgImage = NSImage(contentsOfFile: svgPath) else {
    print("ERROR: Could not load SVG"); exit(1)
}

for (pt, sc) in iconSizes {
    let px = pt * sc
    let name = "icon_\(pt)x\(pt)@\(sc)x.png"
    let sz = NSSize(width: px, height: px)

    let img = NSImage(size: sz)
    img.lockFocus()
    svgImage.draw(in: NSRect(origin: .zero, size: sz),
                  from: .zero, operation: .copy, fraction: 1.0)
    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { print("FAIL: \(name)"); continue }

    try! png.write(to: URL(fileURLWithPath: outputDir + "/" + name))
    print("OK: \(name) (\(px)px)")
}
print("Done!")
