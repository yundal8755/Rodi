import SwiftUI

struct ReviewFormScaffold<Content: View, BottomBar: View>: View {
    @Environment(\.screenSafeAreaInsets) private var screenSafeAreaInsets

    private let header: ReviewFormHeader
    private let content: Content
    private let bottomBar: BottomBar

    init(
        header: ReviewFormHeader,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.header = header
        self.content = content()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RodiColor.white
                    .ignoresSafeArea()
            }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .frame(maxWidth: .infinity)
                .padding(.top, topInset)
                .background(RodiColor.white)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
                .frame(maxWidth: .infinity)
                .padding(.bottom, bottomInset)
                .background(RodiColor.white)
        }
    }

    private var topInset: CGFloat {
        max(screenSafeAreaInsets.top, 20)
    }

    private var bottomInset: CGFloat {
        max(screenSafeAreaInsets.bottom, 34)
    }
}
