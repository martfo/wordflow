// The pill's contents: the current state, a live mic level while listening, and
// a tap target that cancels. Kept small and plain, in Polenta's visual key.

import SwiftUI

struct PillView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                if controller.pill == .listening || controller.pill == .locked {
                    LevelBar(level: controller.level)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 240, height: 56, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { controller.requestCancel() }
        .help("Click to cancel")
    }

    private var icon: some View {
        Group {
            switch controller.pill {
            case .starting: Image(systemName: "mic")
            case .listening: Image(systemName: "mic.fill").foregroundStyle(.red)
            case .locked: Image(systemName: "lock.fill").foregroundStyle(.orange)
            case .processing: ProgressView().controlSize(.small)
            case .hidden: EmptyView()
            }
        }
        .frame(width: 20)
    }

    private var title: String {
        switch controller.pill {
        case .starting: return "Getting the microphone ready…"
        case .listening: return "Listening"
        case .locked: return "Listening, hands-free"
        case .processing: return "Working on it…"
        case .hidden: return ""
        }
    }
}

private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, level * 3))))
            }
        }
        .frame(width: 150, height: 4)
    }
}
