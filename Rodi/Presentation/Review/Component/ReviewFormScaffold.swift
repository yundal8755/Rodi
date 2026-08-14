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
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity)
                .background(RodiColor.white)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
                .frame(maxWidth: .infinity)
                .background(RodiColor.white)
        }
        .padding(.top, screenSafeAreaInsets.top)
        .padding(.bottom, screenSafeAreaInsets.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RodiColor.white)
        .ignoresSafeArea()
    }
}
