// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-github-continuous-integration",
    platforms: [
        .macOS("27")
    ],
    products: [
        .library(
            name: "GitHub Continuous Integration",
            targets: ["GitHub Continuous Integration"]
        ),
        .library(
            name: "GitHub Continuous Integration Workflow",
            targets: ["GitHub Continuous Integration Workflow"]
        ),
        .library(
            name: "GitHub Continuous Integration Validation",
            targets: ["GitHub Continuous Integration Validation"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-standards/swift-github-standard.git",
            branch: "main"
        )
    ],
    targets: [
        // The relation's namespace shell: `GitHub.ContinuousIntegration`,
        // extending the `GitHub` namespace owned by swift-github-standard.
        .target(
            name: "GitHub Continuous Integration",
            dependencies: [
                .product(name: "GitHub Standard", package: "swift-github-standard")
            ]
        ),
        // The *document* half of the relation: reading a GitHub Actions
        // workflow file into a typed value.
        .target(
            name: "GitHub Continuous Integration Workflow",
            dependencies: [
                "GitHub Continuous Integration",
                .product(name: "GitHub Standard", package: "swift-github-standard"),
            ]
        ),
        // The *predicate* half: the validation engine and the
        // GitHub-Actions-mechanics validators that run rule predicates
        // over a repository's shipped workflow bytes.
        .target(
            name: "GitHub Continuous Integration Validation",
            dependencies: [
                "GitHub Continuous Integration",
                "GitHub Continuous Integration Workflow",
                .product(name: "GitHub Standard", package: "swift-github-standard"),
            ]
        ),
        .testTarget(
            name: "GitHub Continuous Integration Workflow Tests",
            dependencies: ["GitHub Continuous Integration Workflow"]
        ),
        .testTarget(
            name: "GitHub Continuous Integration Validation Tests",
            dependencies: ["GitHub Continuous Integration Validation"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
