// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ViaView",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ViaView", targets: ["ViaView"]),
               .executable(name: "ViewerChecks", targets: ["ViewerChecks"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.target(name: "ViewerCore"),
              .executableTarget(name: "ViaView", dependencies: ["ViewerCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/Lucide")],
                                linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
              .executableTarget(name: "ViewerChecks", dependencies: ["ViewerCore"])],
    swiftLanguageModes: [.v5]
)
