import SwiftUI

// MARK: - Adaptive Glass Effect Container
public struct AdaptiveGlassContainer<Content: View>: View {
    public var spacing: CGFloat
    @ViewBuilder public var content: () -> Content

    public init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(macOS 26, iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

// MARK: - Liquid Glass Pill Modifier
public struct LiquidGlassPill: ViewModifier {
    public var cornerRadius: CGFloat = 28
    public var isHighlighted: Bool = false
    public var glowAccent: Color? = nil
    public var isInteractive: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    public init(
        cornerRadius: CGFloat = 28,
        isHighlighted: Bool = false,
        glowAccent: Color? = nil,
        isInteractive: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.isHighlighted = isHighlighted
        self.glowAccent = glowAccent
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            if cornerRadius >= 26 {
                content
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.65)
                                    : Color(white: 0.98).opacity(0.75)
                            )
                    }
                    .glassEffect(
                        glassConfig(isHighlighted: isHighlighted, glowAccent: glowAccent, isInteractive: isInteractive),
                        in: .capsule
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.16),
                        radius: 18,
                        x: 0,
                        y: 8
                    )
            } else {
                content
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.65)
                                    : Color(white: 0.98).opacity(0.75)
                            )
                    }
                    .glassEffect(
                        glassConfig(isHighlighted: isHighlighted, glowAccent: glowAccent, isInteractive: isInteractive),
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.16),
                        radius: 18,
                        x: 0,
                        y: 8
                    )
            }
        } else {
            // High-fidelity material fallback: rich frosted glass with reduced transparency
            content
                .background {
                    ZStack {
                        // 1. Apple frosted material foundation (dense backdrop blur)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)

                        // 2. Base semi-opaque backing to significantly reduce transparency
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color(red: 0.11, green: 0.11, blue: 0.14).opacity(isHighlighted ? 0.88 : 0.80)
                                    : Color(white: 0.98).opacity(isHighlighted ? 0.92 : 0.85)
                            )

                        // 3. Subtle specular highlight to preserve glass feel
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(isHighlighted ? 0.08 : 0.04)
                                    : Color.white.opacity(0.12)
                            )

                        if let glow = glowAccent {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(glow.opacity(0.4), lineWidth: 1.5)
                                .blur(radius: 4)
                        }

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.32 : 0.70), location: 0.0),
                                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.10 : 0.30), location: 0.3),
                                        .init(color: Color.white.opacity(0.02), location: 0.6),
                                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.18 : 0.40), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    }
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.42 : 0.16),
                    radius: 20,
                    x: 0,
                    y: 9
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08),
                    radius: 5,
                    x: 0,
                    y: 2
                )
        }
    }

    @available(macOS 26, iOS 26, *)
    private func glassConfig(isHighlighted: Bool, glowAccent: Color?, isInteractive: Bool) -> Glass {
        var g = Glass.regular
        if let glow = glowAccent {
            g = g.tint(glow)
        }
        if isInteractive {
            g = g.interactive()
        }
        return g
    }
}

// MARK: - Liquid Glass Chip Modifier (Small Pills)
public struct LiquidGlassChip: ViewModifier {
    public var isSelected: Bool = false
    public var isInteractive: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    public init(isSelected: Bool = false, isInteractive: Bool = true) {
        self.isSelected = isSelected
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color(red: 0.14, green: 0.14, blue: 0.17).opacity(isSelected ? 0.75 : 0.55)
                                : Color(white: 0.98).opacity(isSelected ? 0.85 : 0.65)
                        )
                }
                .glassEffect(
                    glassConfig(isSelected: isSelected, isInteractive: isInteractive),
                    in: .capsule
                )
                .clipShape(Capsule())
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                    radius: 5,
                    x: 0,
                    y: 2
                )
        } else {
            // High-fidelity neutral fallback with reduced transparency
            content
                .background {
                    ZStack {
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)

                        Capsule(style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color(red: 0.15, green: 0.15, blue: 0.19).opacity(isSelected ? 0.88 : 0.74)
                                    : Color(white: 0.98).opacity(isSelected ? 0.92 : 0.80)
                            )

                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.28 : 0.65),
                                        Color.white.opacity(0.06),
                                        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.35)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }
                }
                .clipShape(Capsule())
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                    radius: 5,
                    x: 0,
                    y: 2
                )
        }
    }

    @available(macOS 26, iOS 26, *)
    private func glassConfig(isSelected: Bool, isInteractive: Bool) -> Glass {
        var g = Glass.regular
        if isInteractive {
            g = g.interactive()
        }
        return g
    }
}

// MARK: - Liquid Glass Card Modifier
public struct LiquidGlassCard: ViewModifier {
    public var cornerRadius: CGFloat = 28
    public var tint: Color? = nil
    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat = 28, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            colorScheme == .dark
                                ? Color(red: 0.11, green: 0.11, blue: 0.14).opacity(0.70)
                                : Color(white: 0.98).opacity(0.80)
                        )
                }
                .glassEffect(
                    glassConfig(tint: tint),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.18),
                    radius: 24,
                    x: 0,
                    y: 12
                )
        } else {
            // High-fidelity fallback with reduced transparency
            content
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color(red: 0.11, green: 0.11, blue: 0.14).opacity(0.82)
                                    : Color(white: 0.98).opacity(0.88)
                            )

                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.28 : 0.65),
                                        Color.white.opacity(0.04),
                                        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.30)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    }
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.18),
                    radius: 24,
                    x: 0,
                    y: 12
                )
        }
    }

    @available(macOS 26, iOS 26, *)
    private func glassConfig(tint: Color?) -> Glass {
        var g = Glass.regular
        if let t = tint {
            g = g.tint(t)
        }
        return g
    }
}

// MARK: - View Extensions
public extension View {
    func liquidGlassPill(
        cornerRadius: CGFloat = 28,
        isHighlighted: Bool = false,
        glowAccent: Color? = nil,
        isInteractive: Bool = true
    ) -> some View {
        modifier(LiquidGlassPill(
            cornerRadius: cornerRadius,
            isHighlighted: isHighlighted,
            glowAccent: glowAccent,
            isInteractive: isInteractive
        ))
    }

    func liquidGlassChip(isSelected: Bool = false, isInteractive: Bool = true) -> some View {
        modifier(LiquidGlassChip(isSelected: isSelected, isInteractive: isInteractive))
    }

    func liquidGlassCard(cornerRadius: CGFloat = 28, tint: Color? = nil) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, tint: tint))
    }

    @ViewBuilder
    func inGlassContainer(spacing: CGFloat = 16) -> some View {
        AdaptiveGlassContainer(spacing: spacing) {
            self
        }
    }

    func adaptiveGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(GlassEffectIDModifier(id: id, namespace: namespace))
    }

    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(AdaptiveGlassButtonStyleModifier(prominent: prominent))
    }
}

public struct AdaptiveGlassButtonStyleModifier: ViewModifier {
    public let prominent: Bool

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

// MARK: - Glass Effect ID Modifier for Morphing Transitions
public struct GlassEffectIDModifier: ViewModifier {
    public let id: String
    public let namespace: Namespace.ID

    public init(id: String, namespace: Namespace.ID) {
        self.id = id
        self.namespace = namespace
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26, iOS 26, *) {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}
