import AppKit
import CoreGraphics
import CoreKit

public enum StatusBadgeRenderer {
    private static let capsuleTextX: CGFloat = 22.2
    private static let capsuleArrowCenterOffsetX: CGFloat = 2.1
    private static let capsuleSpeedTextOffsetX: CGFloat = 5.8

    private static let topValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .semibold)
    private static let topPercentFont = NSFont.systemFont(ofSize: 8.2, weight: .semibold)
    private static let bottomValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.2, weight: .medium)
    private static let bottomUnitFont = NSFont.systemFont(ofSize: 8.0, weight: .semibold)

    /// Invariant width reserving worst-case bounds ("100%" / "↓ 99.9 M") so the menu bar icon never shifts horizontally.
    private static let fixedCapsuleWidth: CGFloat = {
        let maxTop = NSMutableAttributedString(
            string: "100",
            attributes: [.font: topValueFont, .kern: -0.2]
        )
        maxTop.append(NSAttributedString(
            string: "%",
            attributes: [.font: topPercentFont]
        ))

        let maxBot = NSMutableAttributedString(
            string: "99.9",
            attributes: [.font: bottomValueFont, .kern: -0.15]
        )
        maxBot.append(NSAttributedString(
            string: "\u{2009}M",
            attributes: [.font: bottomUnitFont]
        ))

        let maxTextColWidth = max(maxTop.size().width, capsuleSpeedTextOffsetX + maxBot.size().width)
        return ceil(capsuleTextX + maxTextColWidth)
    }()

    public static func render(
        battery: BatteryStats,
        wifi: WiFiState,
        cpu: CPUStats,
        memory: MemoryStats,
        network: NetworkStats,
        style: BadgeStyle,
        semanticColor: Bool,
        showBatteryPercentInRing: Bool = false,
        isDarkMenuBar: Bool
    ) -> NSImage {
        let height: CGFloat = 24.0
        let fg: NSColor = isDarkMenuBar ? .white : NSColor(white: 0.08, alpha: 1.0)
        let trackColor = fg.withAlphaComponent(isDarkMenuBar ? 0.28 : 0.22)

        let batColor: NSColor = {
            guard semanticColor else { return fg }
            if battery.isLowPowerMode {
                return .systemOrange
            }
            if battery.isCharging {
                return .systemGreen
            }
            if battery.percentage <= 20 {
                return .systemRed
            }
            if battery.percentage <= 35 {
                return .systemOrange
            }
            return .systemGreen
        }()

        let topPct = memory.usagePercent
        let memoryTextColor: NSColor = {
            guard semanticColor else { return fg }
            switch memory.pressureLevel {
            case .critical:
                return .systemRed
            case .warning:
                return .systemOrange
            case .normal:
                return fg
            }
        }()

        let memoryArcColor: NSColor = {
            guard semanticColor else { return fg }
            switch memory.pressureLevel {
            case .critical:
                return .systemRed
            case .warning:
                return .systemOrange
            case .normal:
                return .systemYellow
            }
        }()

        let cpuColor: NSColor = {
            guard semanticColor else { return fg }
            if cpu.totalUsage >= 80 {
                return .systemRed
            }
            return .systemBlue
        }()

        // Build left-aligned attributed strings rendered inside the invariant fixedCapsuleWidth slot
        let numStr = String(format: "%.0f", topPct)
        let topAttr = NSMutableAttributedString(
            string: numStr,
            attributes: [
                .font: topValueFont,
                .foregroundColor: memoryTextColor,
                .kern: -0.2
            ]
        )
        topAttr.append(NSAttributedString(
            string: "%",
            attributes: [
                .font: topPercentFont,
                .foregroundColor: memoryTextColor.withAlphaComponent(0.88)
            ]
        ))

        let dominantIsUp = network.dominantIsUpload
        let (valText, unitText) = Formatters.splitSpeed(network.dominantSpeedBytesPerSec)
        let subFg = fg.withAlphaComponent(0.92)
        let botAttr = NSMutableAttributedString(
            string: valText,
            attributes: [
                .font: bottomValueFont,
                .foregroundColor: subFg,
                .kern: -0.15
            ]
        )
        botAttr.append(NSAttributedString(
            string: "\u{2009}\(unitText)",
            attributes: [
                .font: bottomUnitFont,
                .foregroundColor: fg.withAlphaComponent(0.84)
            ]
        ))

        let width: CGFloat = (style == .capsule) ? fixedCapsuleWidth : 22.0
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setAllowsFontSmoothing(false)
            ctx.setShouldSmoothFonts(false)
            ctx.setAllowsFontSubpixelPositioning(true)
            ctx.setShouldSubpixelPositionFonts(true)

            switch style {
            case .capsule:
                if showBatteryPercentInRing {
                    let center = CGPoint(x: 10.5, y: 11.8)
                    let radius: CGFloat = 8.9
                    drawOpenTopBatteryRing(
                        ctx: ctx,
                        center: center,
                        radius: radius,
                        lineWidth: 2.1,
                        percentage: battery.percentage,
                        track: trackColor,
                        ringColor: batColor,
                        textColor: (semanticColor && (battery.isCharging || battery.isLowPowerMode || battery.percentage <= 20)) ? batColor : fg
                    )
                    drawWiFiGlyph(
                        ctx: ctx,
                        center: CGPoint(x: center.x, y: center.y - 0.95),
                        scale: 0.85,
                        signalBars: wifi.signalBars,
                        poweredOn: wifi.isPoweredOn,
                        color: fg
                    )
                } else {
                    let center = CGPoint(x: 10.5, y: 12.0)
                    let radius: CGFloat = 8.9
                    drawFullRing(ctx: ctx, center: center, radius: radius, lineWidth: 2.25, progress: Double(battery.percentage) / 100.0, track: trackColor, color: batColor)
                    drawWiFiGlyph(ctx: ctx, center: CGPoint(x: center.x, y: center.y - 0.35), scale: 0.96, signalBars: wifi.signalBars, poweredOn: wifi.isPoweredOn, color: fg)
                    if battery.isCharging && semanticColor {
                        drawChargingDot(ctx: ctx, center: CGPoint(x: center.x, y: center.y + radius), color: batColor, borderColor: isDarkMenuBar ? .black : .white)
                    }
                }

                // Tightly group the 2 rows so their total visual height matches the 18pt left ring
                let topDrawY: CGFloat = 11.4
                let botDrawY: CGFloat = 2.1
                topAttr.draw(at: NSPoint(x: capsuleTextX, y: topDrawY))

                // Optical center of bottom row capHeight so the arrow aligns with "0.5 K"
                let botBaselineY = botDrawY - bottomValueFont.descender
                let arrowCenterY = botBaselineY + (bottomValueFont.capHeight * 0.5)
                drawMicroArrow(
                    ctx: ctx,
                    origin: CGPoint(x: capsuleTextX + capsuleArrowCenterOffsetX, y: arrowCenterY),
                    pointingUp: dominantIsUp,
                    color: subFg
                )
                botAttr.draw(at: NSPoint(x: capsuleTextX + capsuleSpeedTextOffsetX, y: botDrawY))

            case .dualRing:
                let center = CGPoint(x: 11.0, y: 12.0)
                drawFullRing(ctx: ctx, center: center, radius: 9.3, lineWidth: 2.15, progress: Double(battery.percentage) / 100.0, track: trackColor, color: batColor)
                drawFullRing(ctx: ctx, center: center, radius: 6.5, lineWidth: 1.55, progress: cpu.totalUsage / 100.0, track: trackColor.withAlphaComponent(0.18), color: cpuColor)
                let numText = String(format: "%.0f", topPct)
                let font = NSFont.monospacedDigitSystemFont(ofSize: 7.4, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
                let textSize = (numText as NSString).size(withAttributes: attrs)
                (numText as NSString).draw(
                    at: NSPoint(x: center.x - textSize.width / 2.0, y: center.y - textSize.height / 2.0 - 0.2),
                    withAttributes: attrs
                )

            case .triArc:
                let center = CGPoint(x: 11.0, y: 12.0)
                let radius: CGFloat = 9.2
                drawSegmentArc(ctx: ctx, center: center, radius: radius, lineWidth: 2.25, startCW: 8, spanCW: 104, progress: Double(battery.percentage) / 100.0, track: trackColor, color: batColor)
                drawSegmentArc(ctx: ctx, center: center, radius: radius, lineWidth: 2.25, startCW: 128, spanCW: 104, progress: topPct / 100.0, track: trackColor, color: memoryArcColor)
                drawSegmentArc(ctx: ctx, center: center, radius: radius, lineWidth: 2.25, startCW: 248, spanCW: 104, progress: cpu.totalUsage / 100.0, track: trackColor, color: cpuColor)
                drawWiFiGlyph(ctx: ctx, center: CGPoint(x: center.x, y: center.y - 0.3), scale: 0.96, signalBars: wifi.signalBars, poweredOn: wifi.isPoweredOn, color: fg)

            case .splitArc:
                let center = CGPoint(x: 11.0, y: 12.0)
                let radius: CGFloat = 9.2
                drawBottomUpRightArc(ctx: ctx, center: center, radius: radius, lineWidth: 2.25, progress: Double(battery.percentage) / 100.0, track: trackColor, color: batColor)
                drawSegmentArc(ctx: ctx, center: center, radius: radius, lineWidth: 2.25, startCW: 190, spanCW: 160, progress: topPct / 100.0, track: trackColor, color: memoryArcColor)
                drawWiFiGlyph(ctx: ctx, center: CGPoint(x: center.x, y: center.y - 0.3), scale: 0.98, signalBars: wifi.signalBars, poweredOn: wifi.isPoweredOn, color: fg)
            }
            return true
        }

        image.isTemplate = !semanticColor
        return image
    }

    private static func drawMicroArrow(ctx: CGContext, origin: CGPoint, pointingUp: Bool, color: NSColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let halfH: CGFloat = 2.65
        let wingW: CGFloat = 1.85
        let wingH: CGFloat = 1.85

        ctx.move(to: CGPoint(x: origin.x, y: origin.y - halfH))
        ctx.addLine(to: CGPoint(x: origin.x, y: origin.y + halfH))

        if pointingUp {
            ctx.move(to: CGPoint(x: origin.x - wingW, y: origin.y + halfH - wingH))
            ctx.addLine(to: CGPoint(x: origin.x, y: origin.y + halfH))
            ctx.addLine(to: CGPoint(x: origin.x + wingW, y: origin.y + halfH - wingH))
        } else {
            ctx.move(to: CGPoint(x: origin.x - wingW, y: origin.y - halfH + wingH))
            ctx.addLine(to: CGPoint(x: origin.x, y: origin.y - halfH))
            ctx.addLine(to: CGPoint(x: origin.x + wingW, y: origin.y - halfH + wingH))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - CoreGraphics Primitives (NSImage flipped:false has +Y UP, 90° = 12 o'clock)

    private static func cwDegreesToCGRad(_ cwDegFromTop: Double) -> CGFloat {
        return CGFloat((90.0 - cwDegFromTop) * .pi / 180.0)
    }

    private static func drawFullRing(
        ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        progress: Double,
        track: NSColor,
        color: NSColor
    ) {
        let clamped = max(0.03, min(1.0, progress))
        ctx.saveGState()
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        ctx.setStrokeColor(track.cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        ctx.setStrokeColor(color.cgColor)
        if clamped >= 0.995 {
            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        } else {
            let start = cwDegreesToCGRad(0)
            let end = cwDegreesToCGRad(clamped * 360.0)
            ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Open-top battery gauge ring (iPhone Duo style): opens a centered gap at 12 o'clock
    /// sized dynamically to the battery percentage digits and draws the digits flush along the top arc.
    private static func drawOpenTopBatteryRing(
        ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        percentage: Int,
        track: NSColor,
        ringColor: NSColor,
        textColor: NSColor
    ) {
        let clampedPct = min(100, max(0, percentage))
        let pctText = "\(clampedPct)"
        let isThreeDigits = clampedPct >= 100
        let fontSize: CGFloat = isThreeDigits ? 5.8 : 6.5
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let kern: CGFloat = isThreeDigits ? -0.45 : -0.15
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: kern
        ]
        let attrStr = NSAttributedString(string: pctText, attributes: attrs)
        let textSize = attrStr.size()

        // Tight angular gap sized to actual inked width + round-cap clearance
        let halfChord = (textSize.width / 2.0) + (lineWidth * 0.5) + 0.75
        let sinVal = min(0.76, max(0.30, halfChord / radius))
        let gapHalfDeg = Double(asin(sinVal)) * 180.0 / .pi
        let arcSpan = max(180.0, 360.0 - 2.0 * gapHalfDeg)

        drawSegmentArc(
            ctx: ctx,
            center: center,
            radius: radius,
            lineWidth: lineWidth,
            startCW: gapHalfDeg,
            spanCW: arcSpan,
            progress: Double(clampedPct) / 100.0,
            track: track,
            color: ringColor
        )

        // Nestle digits cleanly along the upper chord between the two arc endpoints (tucked 0.35pt inward to follow ring curvature)
        let arcEndY = center.y + radius * CGFloat(cos(gapHalfDeg * .pi / 180.0))
        let targetMidY = (arcEndY * 0.65) + ((center.y + radius) * 0.35)
        let textX = center.x - textSize.width / 2.0
        let textY = targetMidY - (font.capHeight / 2.0) + font.descender
        attrStr.draw(at: NSPoint(x: textX, y: textY))
    }

    private static func drawSegmentArc(
        ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        startCW: Double,
        spanCW: Double,
        progress: Double,
        track: NSColor,
        color: NSColor
    ) {
        let clamped = max(0.05, min(1.0, progress))
        ctx.saveGState()
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        ctx.setStrokeColor(track.cgColor)
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: cwDegreesToCGRad(startCW),
            endAngle: cwDegreesToCGRad(startCW + spanCW),
            clockwise: true
        )
        ctx.strokePath()

        ctx.setStrokeColor(color.cgColor)
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: cwDegreesToCGRad(startCW),
            endAngle: cwDegreesToCGRad(startCW + spanCW * clamped),
            clockwise: true
        )
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawBottomUpRightArc(
        ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        progress: Double,
        track: NSColor,
        color: NSColor
    ) {
        let clamped = max(0.05, min(1.0, progress))
        ctx.saveGState()
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        ctx.setStrokeColor(track.cgColor)
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: cwDegreesToCGRad(10),
            endAngle: cwDegreesToCGRad(170),
            clockwise: true
        )
        ctx.strokePath()

        let topDeg = 170.0 - 160.0 * clamped
        ctx.setStrokeColor(color.cgColor)
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: cwDegreesToCGRad(topDeg),
            endAngle: cwDegreesToCGRad(170),
            clockwise: true
        )
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawWiFiGlyph(
        ctx: CGContext,
        center: CGPoint,
        scale: CGFloat,
        signalBars: Int,
        poweredOn: Bool,
        color: NSColor
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: scale, y: scale)

        let dotCenter = CGPoint(x: 0, y: -2.5)
        let activeAlpha: CGFloat = poweredOn ? 1.0 : 0.30
        let dimAlpha: CGFloat = 0.28

        ctx.setLineCap(.round)

        let r2: CGFloat = 6.1
        ctx.setLineWidth(1.85)
        ctx.setStrokeColor(color.withAlphaComponent(signalBars >= 3 ? activeAlpha : dimAlpha).cgColor)
        ctx.addArc(center: dotCenter, radius: r2, startAngle: CGFloat(45.0 * .pi / 180.0), endAngle: CGFloat(135.0 * .pi / 180.0), clockwise: false)
        ctx.strokePath()

        let r1: CGFloat = 3.55
        ctx.setLineWidth(1.85)
        ctx.setStrokeColor(color.withAlphaComponent(signalBars >= 2 ? activeAlpha : dimAlpha).cgColor)
        ctx.addArc(center: dotCenter, radius: r1, startAngle: CGFloat(42.0 * .pi / 180.0), endAngle: CGFloat(138.0 * .pi / 180.0), clockwise: false)
        ctx.strokePath()

        ctx.setFillColor(color.withAlphaComponent(signalBars >= 1 ? activeAlpha : dimAlpha).cgColor)
        ctx.fillEllipse(in: CGRect(x: dotCenter.x - 1.35, y: dotCenter.y - 0.75, width: 2.7, height: 2.7))

        if !poweredOn {
            ctx.setLineWidth(1.15)
            ctx.setStrokeColor(color.withAlphaComponent(0.75).cgColor)
            ctx.move(to: CGPoint(x: -4.2, y: -3.2))
            ctx.addLine(to: CGPoint(x: 4.2, y: 4.4))
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    private static func drawChargingDot(ctx: CGContext, center: CGPoint, color: NSColor, borderColor: NSColor) {
        ctx.saveGState()
        let r: CGFloat = 1.5
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(borderColor.cgColor)
        ctx.fillEllipse(in: rect.insetBy(dx: -0.5, dy: -0.5))
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()
    }
}
