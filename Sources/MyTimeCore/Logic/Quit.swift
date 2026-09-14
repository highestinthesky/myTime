import Foundation

extension EngineCore {
    /// Records a deliberate quit (spec §5.10). The app then stops its LaunchAgent,
    /// so myTime stays off until it's opened again from Applications.
    public mutating func quit(reason: String) throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Constants.minQuitReason else {
            throw EngineError.reasonTooShort
        }
        if state.focus != nil {
            endFocus()
        }
        record(.quit, "Quit myTime — “\(trimmed)”")
    }
}
