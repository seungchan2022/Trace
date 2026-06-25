import SwiftUI
import UIKit

struct DrawingOverlay: UIViewRepresentable {
    let isActive: Bool
    let onStrokePoint: (CGPoint) -> Void
    let onStrokeEnd: () -> Void

    func makeUIView(context: Context) -> DrawingUIView {
        let view = DrawingUIView()
        view.backgroundColor = .clear
        view.onStrokePoint = onStrokePoint
        view.onStrokeEnd = onStrokeEnd
        return view
    }

    func updateUIView(_ uiView: DrawingUIView, context: Context) {
        uiView.isDrawingActive = isActive
        uiView.onStrokePoint = onStrokePoint
        uiView.onStrokeEnd = onStrokeEnd
    }
}

final class DrawingUIView: UIView {
    var isDrawingActive = false
    var onStrokePoint: ((CGPoint) -> Void)?
    var onStrokeEnd: (() -> Void)?
    private var currentPath: [CGPoint] = []
    private let shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        shapeLayer.strokeColor = UIColor.orange.cgColor
        shapeLayer.fillColor = nil
        shapeLayer.lineWidth = 4
        layer.addSublayer(shapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isDrawingActive else { return }
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began, .changed:
            currentPath.append(point)
            onStrokePoint?(point)
            redrawPath()
        case .ended, .cancelled:
            onStrokeEnd?()
            currentPath = []
            redrawPath()
        default: break
        }
    }

    private func redrawPath() {
        let bezier = UIBezierPath()
        guard let first = currentPath.first else {
            shapeLayer.path = nil
            return
        }
        bezier.move(to: first)
        for point in currentPath.dropFirst() {
            bezier.addLine(to: point)
        }
        shapeLayer.path = bezier.cgPath
    }
}
