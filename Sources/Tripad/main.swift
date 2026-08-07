import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
// Menu-bar only: no Dock icon, no main window. Matches LSUIElement in Info.plist.
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
