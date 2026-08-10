import SwiftUI

struct ReviewModalBackground<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .overlay { content }
    }
}
