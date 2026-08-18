import SwiftUI

struct MyPostsRetryFooter: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .rodiTypography(.body3Medium)
                .foregroundStyle(RodiColor.gray600)

            Button(action: retry) {
                Text("다시 시도")
                    .rodiTypography(.body3Medium)
                    .foregroundStyle(RodiColor.primary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
