// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MabrookTrack",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "MabrookTrack", targets: ["MabrookTrack"]),
    ],
    targets: [
        .target(
            name: "MabrookTrack",
            path: "Sources/MabrookTrack",
            resources: [.copy("PrivacyInfo.xcprivacy")],
            linkerSettings: [
                .linkedFramework("AdSupport"),
                .linkedFramework("AppTrackingTransparency"),
                .linkedFramework("StoreKit"),
            ]
        ),
    ]
)
