import AppKit

/// Receives the selected text through the Services pasteboard, never the general clipboard.
@MainActor final class SelectionTranslationService: NSObject {
    private let receive: (String) -> Void

    init(receive: @escaping (String) -> Void) {
        self.receive = receive
        super.init()
    }

    @objc(translateSelection:userData:error:)
    func translateSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        error.pointee = nil
        let text = pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: NSPasteboard.PasteboardType("NSStringPboardType"))
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "请先选中需要翻译的文字。"
            return
        }
        // Return immediately; AppStore handles the network operation asynchronously.
        receive(text)
    }
}
