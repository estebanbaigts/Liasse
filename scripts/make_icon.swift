// Génère l'icône de l'app (enveloppes premium) et le logo du widget.
// Usage : swift scripts/make_icon.swift   (depuis la racine du dépôt)
import SwiftUI
import AppKit

func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
let squircle = RoundedRectangle(cornerRadius: 186, style: .continuous)
let graphite = LinearGradient(colors: [c(44, 45, 54), c(22, 23, 29)], startPoint: .top, endPoint: .bottom)
let navy = LinearGradient(colors: [c(30, 36, 58), c(14, 17, 30)], startPoint: .top, endPoint: .bottom)
let gold = LinearGradient(colors: [c(244, 226, 186), c(206, 172, 112), c(242, 220, 172), c(176, 140, 84)], startPoint: .topLeading, endPoint: .bottomTrailing)
let ivory = LinearGradient(colors: [c(250, 247, 240), c(226, 220, 207)], startPoint: .top, endPoint: .bottom)
let sand = LinearGradient(colors: [c(214, 200, 176), c(178, 160, 132)], startPoint: .top, endPoint: .bottom)
let sage = LinearGradient(colors: [c(150, 176, 160), c(104, 132, 116)], startPoint: .top, endPoint: .bottom)

struct Frame<Content: View>: View {
    let bg: LinearGradient
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            squircle.fill(bg).frame(width: 824, height: 824)
                .overlay(squircle.fill(RadialGradient(colors: [.white.opacity(0.10), .clear], center: .init(x: 0.3, y: 0.1), startRadius: 0, endRadius: 560)).frame(width: 824, height: 824))
                .overlay(squircle.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 3).frame(width: 824, height: 824))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            content()
        }
        .frame(width: 1024, height: 1024)
    }
}

struct Medal: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(gold).frame(width: size, height: size).shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.05)
            Circle().strokeBorder(c(255, 244, 214).opacity(0.7), lineWidth: size * 0.04).frame(width: size * 0.84, height: size * 0.84)
            Text("€").font(.system(size: size * 0.56, weight: .semibold, design: .serif)).foregroundStyle(c(92, 70, 36)).offset(y: -size * 0.01)
        }
    }
}

/// B premium — enveloppes ivoire/sable/sauge, médaille dorée
struct EnvelopesPremium: View {
    func card(_ fill: LinearGradient, _ rot: Double, _ x: CGFloat, _ y: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 48, style: .continuous).fill(fill).frame(width: 440, height: 290)
            .overlay(RoundedRectangle(cornerRadius: 48, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 2))
            .shadow(color: .black.opacity(0.40), radius: 22, y: 14).rotationEffect(.degrees(rot)).offset(x: x, y: y)
    }
    var body: some View {
        Frame(bg: graphite) {
            ZStack {
                card(sage, -13, -36, -72)
                card(sand, 5, 26, -14)
                card(ivory, -2, -8, 66)
                // rabat d'enveloppe sur la carte du dessus
                Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 200, y: 110)); p.addLine(to: .init(x: 400, y: 0)) }
                    .stroke(c(200, 190, 170), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    .frame(width: 400, height: 110).rotationEffect(.degrees(-2)).offset(x: -8, y: -6)
                Medal(size: 170).offset(x: 130, y: 120)
            }
        }
    }
}


/// Logo compact du widget : la médaille seule.
struct Mark: View {
    var body: some View { Medal(size: 460).frame(width: 512, height: 512) }
}

@MainActor
func write<V: View>(_ view: V, size: CGFloat, to path: String) {
    let r = ImageRenderer(content: view.frame(width: size, height: size))
    r.scale = 1
    guard let cg = r.cgImage else { fatalError("rendu impossible") }
    try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("✓ \(path)")
}

let iconDir = "App/Assets.xcassets/AppIcon.appiconset"
let markDir = "Shared/Brand.xcassets/CockpitMark.imageset"
try! FileManager.default.createDirectory(atPath: iconDir, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(atPath: markDir, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    write(EnvelopesPremium(), size: 1024, to: "\(iconDir)/icon_1024.png")
    write(Mark(), size: 512, to: "\(markDir)/mark.png")
}
