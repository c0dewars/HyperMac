import AppKit
import HyperMacCore

enum ScreenCatalog {
    static func current() -> [Display] {
        let screens = NSScreen.screens
        // AppKit's origin is bottom-left; Accessibility uses top-left of the primary display.
        let primaryTop = screens.first?.frame.maxY ?? 0
        func convert(_ r: NSRect) -> Rect {
            Rect(x: r.minX, y: primaryTop - r.maxY, width: r.width, height: r.height)
        }
        return screens.enumerated().compactMap { index, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
            let id = CFUUIDCreateString(nil, uuid) as String
            return Display(id: id, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(displayID) != 0,
                           primary: index == 0, frame: convert(screen.frame), usable: convert(screen.visibleFrame))
        }
    }
}
