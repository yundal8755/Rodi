import SwiftUI

struct ReviewDialog<Content: View>: View {
    @ViewBuilder let content: Content
    var closeAction: (() -> Void)?
    private let contentInsets: EdgeInsets

    init(
        contentInsets: EdgeInsets = .init(top: 16, leading: 20, bottom: 16, trailing: 20),
        @ViewBuilder content: () -> Content,
        closeAction: (() -> Void)? = nil
    ) {
        self.content = content()
        self.closeAction = closeAction
        self.contentInsets = contentInsets
    }

    var body: some View {
        VStack(spacing: 0) {
            if let closeAction {
                HStack {
                    Spacer()
                    Button(action: closeAction) {
                        Image("ic_close")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("닫기")
                }
            }
            content
        }
        .padding(.top, contentInsets.top)
        .padding(.horizontal, contentInsets.leading)
        .padding(.bottom, contentInsets.bottom)
        .frame(maxWidth: 280)
        .background(RodiColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
