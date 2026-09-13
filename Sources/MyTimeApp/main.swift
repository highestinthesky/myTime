import AppKit
let arguments = CommandLine.arguments
#if DEV_TIMESCALE
    let runInForeground = arguments.contains("--foreground")
#else
    let runInForeground = false
#endif
if arguments.contains("--agent") || runInForeground { MyTimeScene.main() } else { Installer.installAndStart() }
