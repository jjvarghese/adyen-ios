//
// Copyright (c) 2024 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import UIKit

/// A view representing a value item.
@_spi(AdyenInternal)
open class FormValueItemView<ValueType, Style, ItemType: FormValueItem<ValueType, Style>>:
    FormItemView<ItemType>,
    AnyFormValueItemView {

    // MARK: - Title Label

    /// The top label view.
    public lazy var titleLabel: UILabel = {
        let titleLabel = UILabel(style: item.style.title)
        titleLabel.text = item.title
        titleLabel.numberOfLines = 0
        titleLabel.isAccessibilityElement = false
        titleLabel.accessibilityIdentifier = item.identifier.map { ViewIdentifierBuilder.build(scopeInstance: $0, postfix: "titleLabel") }

        return titleLabel
    }()

    /// Initializes the value item view.
    ///
    /// - Parameter item: The item represented by the view.
    public required init(item: ItemType) {
        super.init(item: item)
        addSubview(separatorView)
        configureSeparatorView()

        bind(item.$title, to: self.titleLabel, at: \.text)
        
        tintColor = item.style.tintColor
        backgroundColor = item.style.backgroundColor
        gestureRecognizers = [UITapGestureRecognizer(target: self, action: #selector(becomeFirstResponder))]
    }
    
    override open func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        bringSubviewToFront(separatorView)
    }
    
    // MARK: - Editing
    
    /// Indicates if the item is currently being edited.
    open var isEditing = false {
        didSet {
            if let parentItemView = parentItemView as? AnyFormValueItemView {
                parentItemView.isEditing = isEditing
            }
            
            if isEditing != oldValue {
                didChangeEditingStatus()
            }
        }
    }
    
    internal func didChangeEditingStatus() {
        isEditing ? highlightSeparatorView(color: tintColor) : unhighlightSeparatorView()
    }
    
    // MARK: - Separator View
    
    internal lazy var separatorView: UIView = {
        let separatorView = UIView()
        separatorView.backgroundColor = defaultSeparatorColor
        separatorView.isUserInteractionEnabled = false
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        
        return separatorView
    }()
    
    internal var defaultSeparatorColor: UIColor {
        if isEditing {
            return tintColor
        } else {
            return item.style.separatorColor ?? UIColor.Adyen.componentSeparator
        }
    }
    
    internal var defaultTitleColor: UIColor {
        if isEditing {
            return tintColor
        } else {
            return item.style.title.color
        }
    }
    
    internal func highlightSeparatorView(color: UIColor) {
        
        if window == nil {
            // We don't want to animate the separator if the view is not visible yet
            // as this can cause glitches on first appearance with a prefilled value
            self.separatorView.backgroundColor = color
            adyen.cancelAnimations(with: Animation.separatorHighlighting.rawValue)
            return
        }
        
        let transitionView = UIView()
        transitionView.backgroundColor = color
        transitionView.frame = separatorView.frame
        transitionView.frame.size.width = 0.0
        addSubview(transitionView)
        
        let context = AnimationContext(
            animationKey: Animation.separatorHighlighting.rawValue,
            duration: 0.25,
            delay: 0.0,
            options: [.curveEaseInOut],
            animations: { [weak self] in
                guard let self else { return }
                transitionView.frame = self.separatorView.frame
            },
            completion: { [weak self] _ in
                guard let self else { return }
                self.separatorView.backgroundColor = color
                transitionView.removeFromSuperview()
            }
        )
        
        adyen.animate(context: context)
    }
    
    private enum Animation: String {
        case separatorHighlighting = "separator_highlighting"
    }
    
    internal func unhighlightSeparatorView() {
        
        if window == nil {
            // We don't want to animate the separator if the view is not visible yet
            // as this can cause glitches on first appearance with a prefilled value
            self.separatorView.backgroundColor = self.item.style.separatorColor
            adyen.cancelAnimations(with: Animation.separatorHighlighting.rawValue)
            return
        }
        
        let context = AnimationContext(
            animationKey: Animation.separatorHighlighting.rawValue,
            duration: 0.0,
            delay: 0.0,
            animations: { [weak self] in
                self?.separatorView.backgroundColor = self?.item.style.separatorColor
            },
            completion: { [weak self] _ in
                self?.separatorView.backgroundColor = self?.item.style.separatorColor
            }
        )
        
        adyen.animate(context: context)
        
    }
    
    // MARK: - Layout
    
    /// This method places separatorView at the bottom of a view.
    /// Subclasses can override this method to setup alternative placement for a separatorView.
    open func configureSeparatorView() {
        let constraints = [
            separatorView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0)
        ]
        
        NSLayoutConstraint.activate(constraints)
    }
    
}

/// A type-erased form value item view.
@_spi(AdyenInternal)
public protocol AnyFormValueItemView: AnyFormItemView {
    
    /// Indicates if the item is currently being edited.
    var isEditing: Bool { get set }
}
