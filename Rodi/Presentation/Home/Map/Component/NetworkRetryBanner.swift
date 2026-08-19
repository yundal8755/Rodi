//
//  NetworkRetryBanner.swift
//  Rodi
//

import SwiftUI

/// 사용자가 직접 재시도할 때까지 유지되는 지도 네트워크 오류 배너입니다.
struct NetworkRetryBanner: View {
    let retryAction: () -> Void

    var body: some View {
        NetworkConnectionSnackbar(refreshAction: retryAction)
    }
}
