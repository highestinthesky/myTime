import SwiftUI
import MyTimeCore
struct PopoverView: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("myTime").font(.headline)
            HStack {
                Text("◆ \(model.core.state.tokens) \(model.core.state.tokens == 1 ? "token" : "tokens")")
                Spacer()
                Text("Resets at \(DurationFormat.hourOfDay(model.core.setting(.dayStartHour), locale: .current))")
                    .foregroundStyle(.secondary)
            }
            #if DEV_TIMESCALE
                HStack {
                    Button("+1 token") { model.perform { $0.devAddToken() } }
                    Button("+5 min progress") { model.perform { $0.devAddProgress(seconds: 300) } }
                    Button("New day") { model.perform { $0.devSimulateNewDay() } }
                    Button("Reset state") { model.devReset() }
                }
            #endif
        }.padding(16).frame(width: 320).onAppear { model.panelDidOpen() }.onDisappear { model.panelDidClose() }
    }
}
