import SwiftUI

struct CourseRegistrationHeader: View {
    let title: String
    let closeAction: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .rodiTypography(.headline1)
                .foregroundStyle(RodiColor.black)

            HStack {
                Button(action: closeAction) {
                    Image("ic_chevron_left_24")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel("뒤로 가기")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }
}
