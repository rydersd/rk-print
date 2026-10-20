import CoreText
import UIKit

/// One face of a font family, as the weight picker lists it.
struct FontFace: Hashable, Identifiable, Sendable {
    /// The `FontSpec.face` value: a PostScript name, or a weight name for system families.
    let id: String
    let name: String
}

/// The fonts the editor offers and how a `FontSpec` becomes a real font.
enum FontCatalog {
    nonisolated static let systemFamily = "System"
    nonisolated static let roundedFamily = "System Rounded"
    nonisolated static let monoFamily = "System Mono"
    private static let systemFamilies = [systemFamily, roundedFamily, monoFamily]

    private static let systemWeights: [(String, UIFont.Weight)] = [
        ("Ultralight", .ultraLight), ("Thin", .thin), ("Light", .light), ("Regular", .regular),
        ("Medium", .medium), ("Semibold", .semibold), ("Bold", .bold), ("Heavy", .heavy), ("Black", .black),
    ]

    /// The short list shown first in the font picker; installed families only.
    static let favourites: [String] = {
        let installed = Set(UIFont.familyNames)
        let named = ["Helvetica Neue", "Avenir Next", "Futura", "DIN Alternate", "Menlo"].filter(installed.contains)
        return systemFamilies + named
    }()

    /// Every family: the system families, then all installed families alphabetically.
    static let allFamilies: [String] = systemFamilies + UIFont.familyNames.sorted()

    static func faces(for family: String) -> [FontFace] {
        if systemFamilies.contains(family) {
            return systemWeights.map { FontFace(id: $0.0, name: $0.0) }
        }
        return UIFont.fontNames(forFamilyName: family)
            .map { name -> (FontFace, CGFloat) in
                let descriptor = UIFontDescriptor(name: name, size: 12)
                let faceName = descriptor.object(forKey: .face) as? String ?? name
                let traits = descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
                let weight = traits?[.weight] as? CGFloat ?? 0
                return (FontFace(id: name, name: faceName), weight)
            }
            .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
            .map(\.0)
    }

    /// The face to use when switching to `family`: the same weight name if the family has it, else its regular face.
    static func defaultFace(for family: String, matching current: FontSpec) -> String {
        let candidates = faces(for: family)
        let currentName = faces(for: current.family).first { $0.id == current.face }?.name ?? current.face
        return candidates.first { $0.name == currentName }?.id
            ?? candidates.first { $0.name == "Regular" || $0.name == "Roman" }?.id
            ?? candidates.first?.id
            ?? "Regular"
    }

    static func displayName(of spec: FontSpec) -> String {
        faces(for: spec.family).first { $0.id == spec.face }?.name ?? spec.face
    }

    static func uiFont(_ spec: FontSpec, pointSize: Double) -> UIFont {
        let size = CGFloat(pointSize)
        let weight = systemWeights.first { $0.0 == spec.face }?.1 ?? .regular
        switch spec.family {
        case systemFamily:
            return .systemFont(ofSize: size, weight: weight)
        case roundedFamily:
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
            return UIFont(descriptor: rounded, size: size)
        case monoFamily:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        default:
            return UIFont(name: spec.face, size: size) ?? .systemFont(ofSize: size, weight: weight)
        }
    }

    static func ctFont(_ spec: FontSpec, pointSize: Double) -> CTFont {
        uiFont(spec, pointSize: pointSize) as CTFont
    }
}
