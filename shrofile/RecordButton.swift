//
//  RecordButton.swift
//  shrofile
//
//  Created by Jatin Garg on 14/06/17.
//  Copyright © 2017 Jatin Garg. All rights reserved.
//

import UIKit

@IBDesignable class RecordButton: UIButton{
    
    var isRecording: Bool = false{
        didSet{
            setNeedsDisplay()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    func setup(){
        layer.masksToBounds = true
        layer.cornerRadius = bounds.width/2
        backgroundColor = .red
    }
    
    override func draw(_ rect: CGRect) {
        let scalingFactor: CGFloat = 0.9
        let center = CGPoint(x: bounds.width/2, y: bounds.height/2)
        let radius: CGFloat = bounds.width/2 - 5
        let innerCircle = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: 2*3.14, clockwise: true)
        
        innerCircle.lineWidth = 2
        UIColor.white.setStroke()
        innerCircle.stroke()
        
        if isRecording{
            //drawing inner square
            let smallerSide = min(rect.width, rect.height)
            let squareSize = 0.2 * smallerSide
            let originPoint = CGPoint(x: 0.4 * smallerSide, y: 0.4 * smallerSide)
            
            let square = UIBezierPath(rect: CGRect(x: originPoint.x, y: originPoint.y, width: squareSize, height: squareSize))
            UIColor.white.setFill()
            square.fill()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .allowUserInteraction, animations: {
            self.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        }) { (completed) in
            self.transform = CGAffineTransform.identity
        }
        
    }
}
