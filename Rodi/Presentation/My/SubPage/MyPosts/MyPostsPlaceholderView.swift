import SwiftUI

struct MyPostsPlaceholderView: View {
    let backAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MySubpageHeader(title: "내 게시글", backAction: backAction)

            Text("내 게시글 기능을 준비 중이에요.")
                .rodiTypography(.body3Medium)
                .foregroundStyle(RodiColor.gray600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RodiColor.white)
        .toolbar(.hidden, for: .navigationBar)
    }
}
