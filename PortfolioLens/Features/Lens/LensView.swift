import SwiftUI

struct LensView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case exposure = "Exposure"
        case whatIf = "What-if"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .exposure

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch mode {
                case .exposure: ExposureView()
                case .whatIf: WhatIfView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Lens")
        }
    }
}
