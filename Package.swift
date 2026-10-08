// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ViaView",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ViaView", targets: ["ViaView"]),
               .executable(name: "ViewerChecks", targets: ["ViewerChecks"])],
    targets: [.target(name: "ViewerCore"),
              .executableTarget(name: "ViaView", dependencies: ["ViewerCore"], resources: [.copy("Resources/Lucide")]),
              .executableTarget(name: "ViewerChecks", dependencies: ["ViewerCore"])],
    swiftLanguageModes: [.v5]
)
