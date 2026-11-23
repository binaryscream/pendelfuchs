// swift-tools-version: 6.0
// Fahrplan XL – gemeinsame Logik für App, Widgets und Live-Aktivitäten.
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "FahrplanKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "FahrplanKit", targets: ["FahrplanKit"]),
    ],
    targets: [
        .target(name: "FahrplanKit"),
        .testTarget(
            name: "FahrplanKitTests",
            dependencies: ["FahrplanKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
