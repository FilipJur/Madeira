// VLTouch: SVGKit-free reimplementation; assets become CAShapeLayer trees from VLShapes.
//
//  GraphicUtils.swift
//  VoidLink
//
//  Created by True砖家 on 2025/12/24.
//  Copyright © 2025 True砖家@Bilibili. All rights reserved.
//

import Foundation
import UIKit

@objc public class GraphicUtils: NSObject {

    /// Builds a shape-layer tree for the named bundled asset and adds it to `container`.
    @objc public static func makeSVGLayer(
        from file: String,
        in container: CALayer,
        at normalizedPosition: CGPoint = .zero,
        targetSize: CGSize
    ) -> CALayer {
        // VLTouch: previously loaded `<file>.svg` through SVGKit; the assets are CGPath builders now.
        return _makeSVGLayer(
            from: file,
            in: container,
            at: normalizedPosition,
            targetSize: targetSize
        )
    }

    public static func makeCenteredSVGLayer(
        from file: String,
        in container: CALayer,
        targetSize: CGSize
    ) -> CALayer {
        // VLTouch: takes the asset name instead of an SVGKImage (SVGKit removed).
        return _makeSVGLayer(
            from: file,
            in: container,
            targetSize: targetSize
        )
    }

    // VLTouch: `svg` became the asset name; the layer tree is built from VLShapes.
    @objc public static func _makeSVGLayer(
        from file: String,
        in container: CALayer,
        at normalizedPosition: CGPoint = .zero,
        targetSize: CGSize,
        getWrapperLayer: Bool = true
    ) -> CALayer {
        let shapes = VLShapes.shapes(named: file)
        guard !shapes.isEmpty else {
            return CALayer()
        }

        // VLTouch: the SVGKit layer tree is replaced by one canvas-sized layer holding one
        // CAShapeLayer per source path, all drawn in the asset's viewBox coordinates.
        let canvasSize = VLShapes.canvasSize(named: file)
        let svgLayer = CALayer()
        svgLayer.bounds = CGRect(origin: .zero, size: canvasSize)
        svgLayer.anchorPoint = .zero
        svgLayer.position = .zero

        for shape in shapes {
            let pathLayer = CAShapeLayer()
            pathLayer.bounds = CGRect(origin: .zero, size: canvasSize)
            pathLayer.anchorPoint = .zero
            pathLayer.position = .zero
            pathLayer.path = shape.path
            pathLayer.fillColor = shape.style.fill?.cgColor
            pathLayer.strokeColor = shape.style.stroke?.cgColor
            pathLayer.lineWidth = shape.style.strokeWidth
            pathLayer.opacity = shape.style.opacity
            svgLayer.addSublayer(pathLayer)
        }

        svgLayer.transform = CATransform3DIdentity

        var unionRect = CGRect.null
        func accumulateBounds(_ layer: CALayer) {
            unionRect = unionRect.union(layer.frame)
            layer.sublayers?.forEach { accumulateBounds($0) }
        }
        accumulateBounds(svgLayer)

        svgLayer.setAffineTransform(
            CGAffineTransform(
                translationX: -unionRect.origin.x,
                y: -unionRect.origin.y
            )
        )

        let realPosition = (normalizedPosition == .zero
                            ? CGPoint(x: container.bounds.midX, y: container.bounds.midY)
                            : CGPoint(x: container.bounds.width * normalizedPosition.x, y: container.bounds.height * normalizedPosition.y))

        let wrapper = CALayer()
        wrapper.bounds = CGRect(origin: .zero, size: unionRect.size)
        wrapper.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        wrapper.position = realPosition

        let scale = min(
            targetSize.width / unionRect.width,
            targetSize.height / unionRect.height
        )

        wrapper.setAffineTransform(
            CGAffineTransform(scaleX: scale, y: scale)
        )

        wrapper.addSublayer(svgLayer)

        if !getWrapperLayer {
            return wrapper
        }

        let wrappedLayer = CALayer()
        wrappedLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        wrappedLayer.bounds = CGRect(x: 0, y: 0, width: container.bounds.size.width, height: container.bounds.size.height)
        wrappedLayer.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        wrappedLayer.insertSublayer(wrapper, at: 0)

        return wrappedLayer
    }

    // VLTouch: unchanged contract; the tree now contains CAShapeLayers only.
    @objc public static func changeColor(layer: CALayer, color: UIColor) {
        if let shape = layer as? CAShapeLayer {
            shape.fillColor = color.cgColor
            shape.strokeColor = color.cgColor
        }
        layer.sublayers?.forEach { changeColor(layer: $0, color: color) }
    }

    @objc public static func makeTouchTrackpoint(in view: UIView) -> CAShapeLayer {
        let path = UIBezierPath(
            arcCenter: CGPoint(x: 0, y: 0),
            radius: PublicUtils.isIPhone ? 12 : 15,
            startAngle: 0,
            endAngle: CGFloat.pi * 2,
            clockwise: true
        )

        let trackPoint = CAShapeLayer()
        trackPoint.path = path.cgPath

        trackPoint.fillColor = UIColor.white.withAlphaComponent(0.3).cgColor
        trackPoint.strokeColor = UIColor.clear.cgColor
        trackPoint.lineWidth = 0

        view.layer.addSublayer(trackPoint)
        trackPoint.position = view.center
        trackPoint.isHidden = true

        return trackPoint
    }
}
