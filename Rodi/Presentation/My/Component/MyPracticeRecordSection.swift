import SwiftUI

struct MyPracticeRecordSection: View {
    let records: [MyReviewItem]
    let isLoading: Bool
    let hasCompletedInitialLoad: Bool
    let errorMessage: String?
    let openAll: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
    }
}

private extension MyPracticeRecordSection {

    var header: some View {
        HStack(spacing: 0) {
            Text("연습기록")
                .rodiTypography(.body1Medium)
                .foregroundStyle(RodiColor.black)

            Spacer()

            Button(action: openAll) {
                HStack(spacing: 2) {
                    Text("전체보기")
                        .rodiTypography(.body3Medium)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(RodiColor.gray400)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("연습기록 전체보기")
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    var content: some View {
        if isLoading || !hasCompletedInitialLoad {
            ProgressView()
                .tint(RodiColor.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 141)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Text(errorMessage)
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
            .frame(height: 141)
        } else if records.isEmpty {
            MyPracticeRecordEmptyView()
                .frame(maxWidth: .infinity)
                .frame(height: 141)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(records) { record in
                        MyPracticeRecordPreviewCard(record: record)
                    }
                }
                .padding(.leading, 16)
            }
            .accessibilityLabel("연습기록 \(records.count)개")
        }
    }
}

struct MyPracticeRecordPreviewCard: View {
    let record: MyReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(record.placeName)
                .rodiTypography(.body3Medium)
                .fontWeight(.semibold)
                .foregroundStyle(RodiColor.black)
                .lineLimit(1)

            Text(Self.dateFormatter.string(from: record.createdAt))
                .rodiTypography(.caption1Medium)
                .foregroundStyle(RodiColor.gray600)
                .padding(.top, 4)

            Text(record.content)
                .rodiTypography(.caption1Medium)
                .foregroundStyle(RodiColor.gray700)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(width: 179, height: 141, alignment: .topLeading)
        .background(RodiColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(RodiColor.primary50, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.placeName), \(Self.dateFormatter.string(from: record.createdAt)), \(record.content)")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yy.MM.dd"
        return formatter
    }()
}

private struct MyPracticeRecordEmptyView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("아직 연습기록이 없어요!")
                .rodiTypography(.body3Medium)
                .foregroundStyle(RodiColor.gray600)

            Text("가까운 연습 장소부터 천천히 시작해볼까요?")
                .rodiTypography(.caption2Medium)
                .foregroundStyle(RodiColor.gray600)
        }
        .multilineTextAlignment(.center)
    }
}
