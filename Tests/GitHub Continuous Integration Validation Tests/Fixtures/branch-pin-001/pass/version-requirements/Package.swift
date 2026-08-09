// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "fixture",
    dependencies: [
        .package(url: "https://github.com/example-organization-one/swift-example.git", from: "1.0.0"),
        .package(url: "https://github.com/example-organization-two/swift-other.git", exact: "2.1.3"),
        .package(url: "https://github.com/example-organization-meta/swift-third.git", .upToNextMajor(from: "0.3.0")),
    ],
    targets: [
        .target(name: "Fixture")
    ]
)
