//
//  FaceOverlayView.swift
//  KYC
//
//  Created by Sanjay Krishnamurthy on 11/4/24.
//

import UIKit

class FaceOverlayView: UIView {
    private var ovalPath: UIBezierPath?
    private var silhouettePath: UIBezierPath?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false  // Allow touch events to pass through
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Calculate oval dimensions
        let ovalWidth = bounds.width * 0.7 // 70% of the view width
        let ovalHeight = bounds.height * 0.8 // 80% of the view height
        let ovalX = (bounds.width - ovalWidth) / 2
        let ovalY: CGFloat = 20 // Top margin
        
        // Draw oval
        let ovalRect = CGRect(x: ovalX, y: ovalY, width: ovalWidth, height: ovalHeight)
        ovalPath = UIBezierPath(ovalIn: ovalRect)
        
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [10, 5])
        ovalPath?.stroke()
        
        // Draw face silhouette (only the neck)
        silhouettePath = UIBezierPath()
        
        // Neck
        let neckY = ovalRect.maxY - 30
        let neckWidth: CGFloat = 30
        silhouettePath?.move(to: CGPoint(x: ovalRect.midX - neckWidth/2, y: neckY))
        silhouettePath?.addLine(to: CGPoint(x: ovalRect.midX + neckWidth/2, y: neckY))
        
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(2)
        silhouettePath?.stroke()
    }
}
