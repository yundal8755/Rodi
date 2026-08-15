import SwiftUI
import UIKit

/// 커스텀 navigation header에서도 시스템 interactive-pop을 유지합니다.
struct RodiInteractivePopGestureEnabler: UIViewControllerRepresentable {
    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func makeUIViewController(context: Context) -> RodiPopGestureHostingViewController {
        RodiPopGestureHostingViewController(isEnabled: isEnabled)
    }

    func updateUIViewController(
        _ viewController: RodiPopGestureHostingViewController,
        context: Context
    ) {
        viewController.update(isEnabled: isEnabled)
    }

    static func dismantleUIViewController(
        _ viewController: RodiPopGestureHostingViewController,
        coordinator: Void
    ) {
        viewController.restoreInteractivePopGesture()
    }
}

final class RodiPopGestureHostingViewController: UIViewController {
    private var isPopGestureEnabled: Bool

    init(isEnabled: Bool) {
        isPopGestureEnabled = isEnabled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        applyInteractivePopGesturePolicy()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyInteractivePopGesturePolicy()
    }

    func update(isEnabled: Bool) {
        guard isPopGestureEnabled != isEnabled else {
            applyInteractivePopGesturePolicy()
            return
        }
        isPopGestureEnabled = isEnabled
        applyInteractivePopGesturePolicy()
    }

    func restoreInteractivePopGesture() {
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    private func applyInteractivePopGesturePolicy() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let navigationController,
                  navigationController.viewControllers.count > 1,
                  let gestureRecognizer = navigationController.interactivePopGestureRecognizer
            else {
                return
            }

            gestureRecognizer.isEnabled = isPopGestureEnabled
            if isPopGestureEnabled {
                gestureRecognizer.delegate = nil
            }
        }
    }
}

private struct RodiEdgeSwipeBackModifier<Destination: Route>: ViewModifier {
    let isEnabled: Bool
    let isTopRoute: Bool
    let router: Router<Destination>

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard isEnabled,
                          value.startLocation.x <= 24,
                          value.translation.width >= 80,
                          abs(value.translation.height) <= 80,
                          isTopRoute
                    else {
                        return
                    }

                    router.pop()
                }
        )
    }
}

extension View {
    func rodiEdgeSwipeBack<Destination: Route>(
        isEnabled: Bool = true,
        isTopRoute: Bool,
        router: Router<Destination>
    ) -> some View {
        modifier(
            RodiEdgeSwipeBackModifier(
                isEnabled: isEnabled,
                isTopRoute: isTopRoute,
                router: router
            )
        )
    }
}
