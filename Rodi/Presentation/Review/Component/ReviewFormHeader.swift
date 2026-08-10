import SwiftUI

struct ReviewFormHeader: View {
    let title: String
    let showsBack: Bool
    var backAction: (() -> Void)?
    let closeAction: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .rodiTypography(.headline1)
                .foregroundStyle(RodiColor.black)
            HStack {
                if showsBack, let backAction {
                    Button(action: backAction) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(RodiColor.black)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("이전 화면")
                }
                Spacer()
                Button(action: closeAction) {
                    Image("ic_close")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("닫기")
            }
        }
        .frame(height: 56)
    }
}
