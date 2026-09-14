import MyTimeCore
import SwiftUI

/// The Quit window (spec §5.10, §7.11): a reason, a wait, then Quit. Closing the window starts over.
@MainActor
struct QuitView: View {
    let model: AppModel
    let onCancel: () -> Void
    @State private var reason = ""
    @State private var waitEndsAt: Date?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quit myTime?")
                .font(.headline)
            Text("Blocked apps stay unlocked until you open myTime again from the Applications folder.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Why are you quitting?", text: $reason)
                .textFieldStyle(.roundedBorder)
                .disabled(waitEndsAt != nil)
            Text(errorMessage ?? " ")
                .foregroundStyle(.secondary)
                .frame(height: 16)
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                if let waitEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = Int(ceil(waitEndsAt.timeIntervalSince(context.date)))
                        if left > 0 {
                            Button("Quit in \(left)s") {}
                                .disabled(true)
                                .monospacedDigit()
                        } else {
                            Button("Quit myTime") {
                                quit()
                            }
                        }
                    }
                } else {
                    Button("Start \(Int(Constants.quitWait))-second wait") {
                        waitEndsAt = Date().addingTimeInterval(Constants.quitWait)
                    }
                    .disabled(trimmedReason.count < Constants.minQuitReason)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func quit() {
        do {
            try model.quit(reason: reason)
        } catch let error as EngineError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = nil
        }
    }
}
