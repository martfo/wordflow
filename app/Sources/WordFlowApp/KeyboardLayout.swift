// Whether the current keyboard has a § key, which decides the default hotkey:
// § on ISO/UK layouts, Right ⌘ on ANSI (AC-1.5-c). Uses UCKeyTranslate on the
// § key code; any failure defaults to assuming § is present.

import Carbon
import Foundation
import WordFlowCore

enum KeyboardLayout {
    static func hasSectionKey() -> Bool {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return true }
        let layoutData = unsafeBitCast(pointer, to: CFData.self) as Data
        return layoutData.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            let keyLayout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                keyLayout, HotkeyKind.section.keyCode, UInt16(kUCKeyActionDown), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return true }
            return String(utf16CodeUnits: chars, count: length) == "§"
        }
    }
}
