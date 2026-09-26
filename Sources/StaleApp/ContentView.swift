import SwiftUI
import StaleCore

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()

            switch state.phase {
            case .idle:
                LandingView()
            case .scanning:
                ScanningView()
            case .results:
                ResultsView()
            }
        }
        .background(Theme.background)
        .alert(
            state.alertTitle,
            isPresented: Binding(
                get: { state.alertMessage != nil },
                set: { if !$0 { state.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { state.alertMessage = nil }
        } message: {
            Text(state.alertMessage ?? "")
        }
    }
}

struct TitleBarView: View {
    var body: some View {
        HStack {
            Spacer()
            Text("Stale")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(height: 38)
        .background(Color.clear)
    }
}
