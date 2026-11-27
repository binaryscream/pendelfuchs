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
    dependencies: [
        // Regionale Verbünde (EFA-Schnittstellen) – MIT-Lizenz, Swift-Port von public-transport-enabler.
        .package(url: "https://github.com/alexander-albers/tripkit.git", revision: "01ad2f0e5e6b859fefc3ed512096663478405751"),
    ],
    targets: [
        // Nur Typ-Aliase: TripKit hat eine Klasse gleichen Namens wie das Modul und Typen wie `Trip` oder `Stop`,
        // die mit unseren kollidieren. Über die Aliase bleiben sie in FahrplanKit eindeutig.
        .target(name: "TripKitBridge", dependencies: [.product(name: "TripKit", package: "tripkit")]),
        .target(name: "FahrplanKit", dependencies: ["TripKitBridge", .product(name: "TripKit", package: "tripkit")]),
        .testTarget(
            name: "FahrplanKitTests",
            dependencies: ["FahrplanKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
