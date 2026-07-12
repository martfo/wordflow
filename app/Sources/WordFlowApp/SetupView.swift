// The first-run setup screen: it provisions the Python backend into Application
// Support and fetches the speech models, with plain progress, then hands over to
// the menu bar app.

import SwiftUI

struct SetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to WordFlow").font(.title2).bold()
            Text("WordFlow sets up its own private, on-device backend the first time it runs. "
                 + "This needs the network once; after that everything works offline.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            content
            Spacer()
        }
        .padding(24)
        .frame(width: 440, height: 300, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch model.setup {
        case .needsSetup:
            VStack(alignment: .leading, spacing: 12) {
                Text("Ready to set up. This takes a minute or two.")
                Button("Set up WordFlow") { model.runSetup() }
                    .buttonStyle(.borderedProminent)
            }
        case .working(let step):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(step)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.runSetup() }
                    .buttonStyle(.borderedProminent)
            }
        case .ready:
            Text("All set. WordFlow is now in your menu bar.")
        }
    }
}
