//
//  VLShapes.swift
//  Madeira
//
//  VLTouch: Vector shapes for the six VoidLink SVG assets, emitted as CGPath builders so the port needs no SVGKit (D2).
//  Generated once from the original SVGs; coordinates are in each asset's SVG viewBox space (y down), colours and
//  opacities come from the SVG attributes. SVG filters (blur / drop shadow) are not reproduced.
//

import UIKit
import CoreGraphics

/// Fill/stroke description of one SVG shape, in SVG paint order.
public struct VLStyle {
    public var fill: UIColor?
    public var stroke: UIColor?
    public var strokeWidth: CGFloat
    public var opacity: Float

    public init(fill: UIColor? = nil, stroke: UIColor? = nil, strokeWidth: CGFloat = 0, opacity: Float = 1) {
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.opacity = opacity
    }
}

/// One drawing primitive of a converted SVG.
public struct VLShape {
    public let path: CGPath
    public let style: VLStyle

    public init(path: CGPath, style: VLStyle = VLStyle()) {
        self.path = path
        self.style = style
    }
}

/// CGPath builders replacing the VoidLink SVG assets.
public enum VLShapes {

    /// SVG viewBox size of an asset, i.e. the coordinate space the paths are expressed in.
    public static func canvasSize(named name: String) -> CGSize {
        switch name {
        case "StickWheel", "StickWheelSmall":
            return CGSize(width: 120, height: 120)
        case "StickWheelAxis", "StickWheelAxis-0.75", "StickWheelAxis-0.15":
            return CGSize(width: 860, height: 860)
        case "sprintSign":
            return CGSize(width: 17.3579, height: 10.6133)
        case "walkSign":
            return CGSize(width: 17.5852, height: 6.4292)
        default:
            return .zero
        }
    }

    /// Shapes of a known asset name, in paint order; empty when the name is unknown.
    public static func shapes(named name: String) -> [VLShape] {
        switch name {
        case "StickWheel": return stickWheel()
        case "StickWheelSmall": return stickWheelSmall()
        case "StickWheelAxis": return stickWheelAxis()
        case "StickWheelAxis-0.75": return stickWheelAxis075()
        case "StickWheelAxis-0.15": return stickWheelAxis(opacity: 0.15)
        case "sprintSign": return sprintSign()
        case "walkSign": return walkSign()
        default: return []
        }
    }

    /// StickWheel.svg (120x120): outer ring with thumb notch, plus inner ring.
    public static func stickWheel() -> [VLShape] {
        return [
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 67.25, y: 10.437))
                p.addCurve(to: CGPoint(x: 67.588, y: 10.579), control1: CGPoint(x: 67.349, y: 10.512), control2: CGPoint(x: 67.465, y: 10.56))
                p.addCurve(to: CGPoint(x: 94.821, y: 24.119), control1: CGPoint(x: 77.8514, y: 12.155), control2: CGPoint(x: 87.3695, y: 16.8874))
                p.addCurve(to: CGPoint(x: 95.0445, y: 24.6462), control1: CGPoint(x: 94.9632, y: 24.2576), control2: CGPoint(x: 95.0438, y: 24.4476))
                p.addCurve(to: CGPoint(x: 94.825, y: 25.175), control1: CGPoint(x: 95.0453, y: 24.8448), control2: CGPoint(x: 94.9662, y: 25.0353))
                p.addLine(to: CGPoint(x: 94.049, y: 25.95))
                p.addCurve(to: CGPoint(x: 92.984, y: 25.954), control1: CGPoint(x: 93.7544, y: 26.2414), control2: CGPoint(x: 93.2807, y: 26.2432))
                p.addCurve(to: CGPoint(x: 27.014, y: 25.954), control1: CGPoint(x: 74.6002, y: 8.1438), control2: CGPoint(x: 45.3978, y: 8.1438))
                p.addCurve(to: CGPoint(x: 25.95, y: 25.95), control1: CGPoint(x: 26.7174, y: 26.2426), control2: CGPoint(x: 26.2444, y: 26.2408))
                p.addLine(to: CGPoint(x: 25.174, y: 25.175))
                p.addCurve(to: CGPoint(x: 24.954, y: 24.6457), control1: CGPoint(x: 25.0325, y: 25.0353), control2: CGPoint(x: 24.9532, y: 24.8445))
                p.addCurve(to: CGPoint(x: 25.178, y: 24.118), control1: CGPoint(x: 24.9547, y: 24.4468), control2: CGPoint(x: 25.0355, y: 24.2566))
                p.addCurve(to: CGPoint(x: 52.41, y: 10.58), control1: CGPoint(x: 32.6295, y: 16.8873), control2: CGPoint(x: 42.1472, y: 12.1557))
                p.addCurve(to: CGPoint(x: 52.749, y: 10.438), control1: CGPoint(x: 52.5329, y: 10.5611), control2: CGPoint(x: 52.6493, y: 10.5124))
                p.addLine(to: CGPoint(x: 59.549, y: 5.338))
                p.addCurve(to: CGPoint(x: 60.449, y: 5.338), control1: CGPoint(x: 59.8157, y: 5.138), control2: CGPoint(x: 60.1823, y: 5.138))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: UIColor(red: 1, green: 1, blue: 1, alpha: 1.0))),
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 61.955, y: 6.804))
                p.addCurve(to: CGPoint(x: 70.915, y: 11.206), control1: CGPoint(x: 64.442, y: 9.099), control2: CGPoint(x: 67.612, y: 10.467))
                p.addCurve(to: CGPoint(x: 94.425, y: 23.739), control1: CGPoint(x: 79.7409, y: 13.1805), control2: CGPoint(x: 87.8661, y: 17.5119))
                p.addCurve(to: CGPoint(x: 94.438, y: 25.562), control1: CGPoint(x: 94.945, y: 24.232), control2: CGPoint(x: 94.945, y: 25.055))
                p.addCurve(to: CGPoint(x: 92.589, y: 25.575), control1: CGPoint(x: 93.9268, y: 26.0662), control2: CGPoint(x: 93.1072, y: 26.072))
                p.addCurve(to: CGPoint(x: 27.41, y: 25.575), control1: CGPoint(x: 74.309, y: 8.2688), control2: CGPoint(x: 45.69, y: 8.2688))
                p.addCurve(to: CGPoint(x: 25.562, y: 25.562), control1: CGPoint(x: 26.8919, y: 26.0713), control2: CGPoint(x: 26.073, y: 26.0656))
                p.addCurve(to: CGPoint(x: 25.1823, y: 24.648), control1: CGPoint(x: 25.317, y: 25.3212), control2: CGPoint(x: 25.1801, y: 24.9914))
                p.addCurve(to: CGPoint(x: 25.574, y: 23.739), control1: CGPoint(x: 25.1846, y: 24.3045), control2: CGPoint(x: 25.3259, y: 23.9766))
                p.addCurve(to: CGPoint(x: 49.086, y: 11.206), control1: CGPoint(x: 32.1335, y: 17.5116), control2: CGPoint(x: 40.2593, y: 13.1802))
                p.addCurve(to: CGPoint(x: 58.044, y: 6.805), control1: CGPoint(x: 52.388, y: 10.467), control2: CGPoint(x: 55.556, y: 9.1))
                p.addLine(to: CGPoint(x: 60, y: 5))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: UIColor(red: 1, green: 1, blue: 1, alpha: 1.0))),
        ]
    }

    /// StickWheelSmall.svg: same artwork as StickWheel, sized by the caller.
    public static func stickWheelSmall() -> [VLShape] {
        return stickWheel()
    }

    /// StickWheelAxis.svg (860x860): dashed-direction ring and four triangles.
    public static func stickWheelAxis(opacity: Float = 0.25) -> [VLShape] {
        return [
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 430, y: 45.3164))
                p.addCurve(to: CGPoint(x: 814.471, y: 430), control1: CGPoint(x: 642.136, y: 45.3164), control2: CGPoint(x: 814.471, y: 217.345))
                p.addCurve(to: CGPoint(x: 430, y: 814.684), control1: CGPoint(x: 814.471, y: 642.656), control2: CGPoint(x: 642.136, y: 814.684))
                p.addCurve(to: CGPoint(x: 45.5294, y: 430), control1: CGPoint(x: 217.864, y: 814.684), control2: CGPoint(x: 45.5294, y: 642.656))
                p.addCurve(to: CGPoint(x: 430, y: 45.3164), control1: CGPoint(x: 45.5294, y: 217.345), control2: CGPoint(x: 217.864, y: 45.3164))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: nil, stroke: .white, strokeWidth: 90, opacity: opacity)),
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 430, y: 122.855))
                p.addLine(to: CGPoint(x: 508.859, y: 213.488))
                p.addLine(to: CGPoint(x: 351.141, y: 213.488))
                p.addLine(to: CGPoint(x: 430, y: 122.855))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: UIColor(red: 0.851, green: 0.851, blue: 0.851, alpha: 1.0), opacity: opacity)),
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 430, y: 737.144))
                p.addLine(to: CGPoint(x: 351.141, y: 646.512))
                p.addLine(to: CGPoint(x: 508.859, y: 646.512))
                p.addLine(to: CGPoint(x: 430, y: 737.144))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: UIColor(red: 0.851, green: 0.851, blue: 0.851, alpha: 1.0), opacity: opacity)),
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 738.588, y: 430.001))
                p.addLine(to: CGPoint(x: 647.529, y: 508.491))
                p.addLine(to: CGPoint(x: 647.529, y: 351.512))
                p.addLine(to: CGPoint(x: 738.588, y: 430.001))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: UIColor(red: 0.851, green: 0.851, blue: 0.851, alpha: 1.0), opacity: opacity)),
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 121.412, y: 430.001))
                p.addLine(to: CGPoint(x: 212.471, y: 351.512))
                p.addLine(to: CGPoint(x: 212.471, y: 508.491))
                p.addLine(to: CGPoint(x: 121.412, y: 430.001))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: UIColor(red: 0.851, green: 0.851, blue: 0.851, alpha: 1.0), opacity: opacity)),
        ]
    }

    /// StickWheelAxis-0.75.svg: the axis ring at 75% opacity.
    public static func stickWheelAxis075() -> [VLShape] {
        return stickWheelAxis(opacity: 0.75)
    }

    /// sprintSign.svg (17.3579x10.6133): chevron pointing up.
    public static func sprintSign() -> [VLShape] {
        return [
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0.4175, y: 7.575))
                p.addCurve(to: CGPoint(x: 0, y: 8.6001), control1: CGPoint(x: 0.1438, y: 7.8533), control2: CGPoint(x: 0, y: 8.1965))
                p.addCurve(to: CGPoint(x: 1.4751, y: 10.0891), control1: CGPoint(x: 0, y: 9.4211), control2: CGPoint(x: 0.6587, y: 10.0891))
                p.addCurve(to: CGPoint(x: 2.5652, y: 9.616), control1: CGPoint(x: 1.8879, y: 10.0891), control2: CGPoint(x: 2.2683, y: 9.9221))
                p.addLine(to: CGPoint(x: 8.8877, y: 3.1126))
                p.addLine(to: CGPoint(x: 8.1316, y: 3.1126))
                p.addLine(to: CGPoint(x: 14.4355, y: 9.616))
                p.addCurve(to: CGPoint(x: 15.521, y: 10.0891), control1: CGPoint(x: 14.7324, y: 9.9268), control2: CGPoint(x: 15.1174, y: 10.0891))
                p.addCurve(to: CGPoint(x: 16.9961, y: 8.6001), control1: CGPoint(x: 16.3328, y: 10.0891), control2: CGPoint(x: 16.9961, y: 9.4211))
                p.addCurve(to: CGPoint(x: 16.574, y: 7.575), control1: CGPoint(x: 16.9961, y: 8.1919), control2: CGPoint(x: 16.8569, y: 7.8486))
                p.addLine(to: CGPoint(x: 9.718, y: 0.5566))
                p.addCurve(to: CGPoint(x: 8.5027, y: 0), control1: CGPoint(x: 9.3469, y: 0.1809), control2: CGPoint(x: 8.9665, y: 0.0093))
                p.addCurve(to: CGPoint(x: 7.2827, y: 0.5566), control1: CGPoint(x: 8.0388, y: 0), control2: CGPoint(x: 7.6585, y: 0.1763))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: .white)),
        ]
    }

    /// walkSign.svg (17.5852x6.4292): chevron pointing down.
    public static func walkSign() -> [VLShape] {
        return [
            VLShape(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0.8535, y: 3.1172))
                p.addCurve(to: CGPoint(x: 0, y: 4.3325), control1: CGPoint(x: 0.3572, y: 3.3398), control2: CGPoint(x: 0, y: 3.7759))
                p.addCurve(to: CGPoint(x: 1.4473, y: 5.8586), control1: CGPoint(x: 0, y: 5.251), control2: CGPoint(x: 0.6772, y: 5.8586))
                p.addCurve(to: CGPoint(x: 2.8899, y: 5.3948), control1: CGPoint(x: 1.8879, y: 5.8586), control2: CGPoint(x: 2.4353, y: 5.6035))
                p.addLine(to: CGPoint(x: 9.0825, y: 2.7507))
                p.addLine(to: CGPoint(x: 8.1455, y: 2.7507))
                p.addLine(to: CGPoint(x: 14.3381, y: 5.3948))
                p.addCurve(to: CGPoint(x: 15.7761, y: 5.8586), control1: CGPoint(x: 14.7881, y: 5.6035), control2: CGPoint(x: 15.3401, y: 5.8586))
                p.addCurve(to: CGPoint(x: 17.2234, y: 4.3325), control1: CGPoint(x: 16.5508, y: 5.8586), control2: CGPoint(x: 17.2234, y: 5.251))
                p.addCurve(to: CGPoint(x: 16.3699, y: 3.1172), control1: CGPoint(x: 17.2234, y: 3.7759), control2: CGPoint(x: 16.8708, y: 3.3398))
                p.addLine(to: CGPoint(x: 10.2283, y: 0.4639))
                p.addCurve(to: CGPoint(x: 8.614, y: 0), control1: CGPoint(x: 9.6299, y: 0.1995), control2: CGPoint(x: 9.1707, y: 0))
                p.addCurve(to: CGPoint(x: 6.9998, y: 0.4639), control1: CGPoint(x: 8.0527, y: 0), control2: CGPoint(x: 7.5981, y: 0.1995))
                p.closeSubpath()
                return p
            }(), style: VLStyle(fill: .white)),
        ]
    }
}
