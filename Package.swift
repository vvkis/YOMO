// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "YOMO",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "YOMO", targets: ["YOMO"])
    ],
    targets: [
        .target(
            name: "CoreKit",
            path: "Sources/CoreKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .target(
            name: "DisplayHiDPIModule",
            dependencies: ["CoreKit"],
            path: "Sources/DisplayHiDPIModule",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .target(
            name: "KeepAwakeModule",
            dependencies: ["CoreKit"],
            path: "Sources/KeepAwakeModule",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "AudioBluetoothModule",
            dependencies: ["CoreKit"],
            path: "Sources/AudioBluetoothModule",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("IOBluetooth")
            ]
        ),
        .target(
            name: "ScrollReverserModule",
            dependencies: ["CoreKit"],
            path: "Sources/ScrollReverserModule",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .target(
            name: "DuoBarModule",
            dependencies: ["CoreKit", "DisplayHiDPIModule", "KeepAwakeModule", "AudioBluetoothModule", "ScrollReverserModule"],
            path: "Sources/DuoBarModule",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "YOMO",
            dependencies: ["CoreKit", "DuoBarModule", "DisplayHiDPIModule", "KeepAwakeModule", "AudioBluetoothModule", "ScrollReverserModule"],
            path: "Sources/YOMO",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
