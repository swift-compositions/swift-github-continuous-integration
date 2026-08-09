// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        .package(url: "https://github.com/example-organization-one/swift-example.git", .branch("develop")),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
