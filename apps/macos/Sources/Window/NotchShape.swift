import SwiftUI

/// Shape of the Dynamic Island: flat top edge flush with the screen top (like the physical MacBook notch)
/// and rounded bottom-left / bottom-right corners. Radii are animatable so expansion keeps the same top shape.
public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat = 0, bottomRadius: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let maxR = min(rect.width, rect.height) / 2.0
        let tr = max(0, min(topRadius, maxR))
        let br = max(0, min(bottomRadius, maxR))

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr), control: CGPoint(x: rect.maxX, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.minX + br, y: rect.maxY - br),
            radius: br, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        if tr > 0 {
            p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}
