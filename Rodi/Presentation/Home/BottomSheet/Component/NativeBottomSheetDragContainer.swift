import SwiftUI
import UIKit

enum NativeBottomSheetDestination {
    case dismissed
    case resting
    case expanded
}

struct NativeBottomSheetDragContainer<Content: View>: UIViewControllerRepresentable {
    let restingHeight: CGFloat
    let maximumHeight: CGFloat
    let isEnabled: Bool
    let resetToRestingRequestID: Int
    let onVisibleHeightChanged: (CGFloat, Bool) -> Void
    let onSettled: (NativeBottomSheetDestination) -> Void
    private let content: Content

    init(
        restingHeight: CGFloat,
        maximumHeight: CGFloat,
        isEnabled: Bool = true,
        resetToRestingRequestID: Int = 0,
        onVisibleHeightChanged: @escaping (CGFloat, Bool) -> Void = { _, _ in },
        onSettled: @escaping (NativeBottomSheetDestination) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.restingHeight = restingHeight
        self.maximumHeight = maximumHeight
        self.isEnabled = isEnabled
        self.resetToRestingRequestID = resetToRestingRequestID
        self.onVisibleHeightChanged = onVisibleHeightChanged
        self.onSettled = onSettled
        self.content = content()
    }

    func makeUIViewController(context: Context) -> NativeBottomSheetDragViewController<Content> {
        NativeBottomSheetDragViewController(
            content: content,
            restingHeight: restingHeight,
            maximumHeight: maximumHeight,
            isEnabled: isEnabled,
            resetToRestingRequestID: resetToRestingRequestID,
            onVisibleHeightChanged: onVisibleHeightChanged,
            onSettled: onSettled
        )
    }

    func updateUIViewController(
        _ viewController: NativeBottomSheetDragViewController<Content>,
        context: Context
    ) {
        viewController.update(
            content: content,
            restingHeight: restingHeight,
            maximumHeight: maximumHeight,
            isEnabled: isEnabled,
            resetToRestingRequestID: resetToRestingRequestID,
            onVisibleHeightChanged: onVisibleHeightChanged,
            onSettled: onSettled
        )
    }
}

final class NativeBottomSheetDragViewController<Content: View>: UIViewController,
    UIGestureRecognizerDelegate {

    private let sheetContainer = UIView()
    private let panSurface = UIView()
    private let hostingController: UIHostingController<Content>

    private var restingHeight: CGFloat
    private var maximumHeight: CGFloat
    private var isEnabled: Bool
    private var resetToRestingRequestID: Int
    private var onVisibleHeightChanged: (CGFloat, Bool) -> Void
    private var onSettled: (NativeBottomSheetDestination) -> Void
    private var currentOffset: CGFloat = 0
    private var gestureStartOffset: CGFloat = 0
    private var hasAppliedInitialOffset = false
    private var isInteracting = false
    private var isSettling = false

    init(
        content: Content,
        restingHeight: CGFloat,
        maximumHeight: CGFloat,
        isEnabled: Bool,
        resetToRestingRequestID: Int,
        onVisibleHeightChanged: @escaping (CGFloat, Bool) -> Void,
        onSettled: @escaping (NativeBottomSheetDestination) -> Void
    ) {
        hostingController = UIHostingController(rootView: content)
        self.restingHeight = restingHeight
        self.maximumHeight = maximumHeight
        self.isEnabled = isEnabled
        self.resetToRestingRequestID = resetToRestingRequestID
        self.onVisibleHeightChanged = onVisibleHeightChanged
        self.onSettled = onSettled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NativeBottomSheetPassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        sheetContainer.backgroundColor = .clear
        sheetContainer.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        panSurface.backgroundColor = .clear
        panSurface.translatesAutoresizingMaskIntoConstraints = false
        sheetContainer.addSubview(panSurface)
        view.addSubview(sheetContainer)

        NSLayoutConstraint.activate([
            sheetContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetContainer.topAnchor.constraint(equalTo: view.topAnchor),
            sheetContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            hostingController.view.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: sheetContainer.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: sheetContainer.bottomAnchor),

            panSurface.leadingAnchor.constraint(equalTo: sheetContainer.leadingAnchor),
            panSurface.trailingAnchor.constraint(equalTo: sheetContainer.trailingAnchor),
            panSurface.topAnchor.constraint(equalTo: sheetContainer.topAnchor),
            panSurface.heightAnchor.constraint(equalToConstant: 24)
        ])

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        panSurface.addGestureRecognizer(panGesture)
        updateInteractionState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard !hasAppliedInitialOffset else { return }
        hasAppliedInitialOffset = true
        applyOffset(restingOffset)
    }

    func update(
        content: Content,
        restingHeight: CGFloat,
        maximumHeight: CGFloat,
        isEnabled: Bool,
        resetToRestingRequestID: Int,
        onVisibleHeightChanged: @escaping (CGFloat, Bool) -> Void,
        onSettled: @escaping (NativeBottomSheetDestination) -> Void
    ) {
        let shouldResetToResting = self.resetToRestingRequestID != resetToRestingRequestID
        let didGeometryChange = abs(self.restingHeight - restingHeight) > 0.5
            || abs(self.maximumHeight - maximumHeight) > 0.5
        hostingController.rootView = content
        self.restingHeight = restingHeight
        self.maximumHeight = maximumHeight
        self.isEnabled = isEnabled
        self.resetToRestingRequestID = resetToRestingRequestID
        self.onVisibleHeightChanged = onVisibleHeightChanged
        self.onSettled = onSettled

        if (shouldResetToResting || didGeometryChange),
           hasAppliedInitialOffset,
           !isInteracting,
           !isSettling {
            isSettling = false
            UIView.performWithoutAnimation {
                applyOffset(restingOffset)
            }
        }
        updateInteractionState()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isEnabled, !isSettling else { return }

        let translation = recognizer.translation(in: view).y

        switch recognizer.state {
        case .began:
            isInteracting = true
            gestureStartOffset = currentOffset
            reportVisibleHeight(isTransient: true)

        case .changed:
            applyOffset(clampedOffset(gestureStartOffset + translation))
            reportVisibleHeight(isTransient: true)

        case .ended, .cancelled, .failed:
            isInteracting = false
            settle(from: currentOffset)

        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isEnabled,
              !isSettling,
              let panGesture = gestureRecognizer as? UIPanGestureRecognizer
        else {
            return false
        }

        let velocity = panGesture.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    private var restingOffset: CGFloat {
        max(maximumHeight - restingHeight, 0)
    }

    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(max(offset, 0), maximumHeight)
    }

    private func applyOffset(_ offset: CGFloat) {
        currentOffset = clampedOffset(offset)
        sheetContainer.transform = CGAffineTransform(translationX: 0, y: currentOffset)
    }

    private func settle(from offset: CGFloat) {
        let visibleHeight = maximumHeight - offset
        let destination: NativeBottomSheetDestination
        let targetOffset: CGFloat
        let duration: TimeInterval

        if visibleHeight <= max(restingHeight - 48, 0) {
            destination = .dismissed
            targetOffset = maximumHeight
            duration = 0.25
        } else if visibleHeight >= maximumHeight * 0.55 {
            destination = .expanded
            targetOffset = 0
            duration = 0.24
        } else {
            destination = .resting
            targetOffset = restingOffset
            duration = 0.22
        }

        isSettling = true
        updateInteractionState()
        onVisibleHeightChanged(max(maximumHeight - targetOffset, 0), true)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.applyOffset(targetOffset)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isSettling = false
            self.updateInteractionState()
            self.onVisibleHeightChanged(0, false)
            self.onSettled(destination)
        }
    }

    private func reportVisibleHeight(isTransient: Bool) {
        onVisibleHeightChanged(max(maximumHeight - currentOffset, 0), isTransient)
    }

    private func updateInteractionState() {
        panSurface.isUserInteractionEnabled = isEnabled && !isSettling
    }
}

private final class NativeBottomSheetPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}
