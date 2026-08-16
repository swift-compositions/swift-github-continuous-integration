import Foundation

@testable import GitHub_Continuous_Integration_Validation

enum FixtureCorpus {
    struct File: Sendable {
        let path: String
        let base64: String
    }

    enum LineEndings: Sendable, Equatable {
        case lf
        case crlf
    }

    private static let materialized: (workspace: URL, corpus: URL) = {
        do {
            return try materialize(lineEndings: .lf)
        } catch {
            fatalError("could not materialize the generated fixture corpus: \(error)")
        }
    }()

    static var corpus: GitHub.ContinuousIntegration.Validation.Corpus {
        .init(root: materialized.corpus.path)
    }

    static var organizationsFile: String {
        materialized.workspace
            .appendingPathComponent(".github/actions/read-orgs/orgs.yaml")
            .path
    }

    static func materialize(
        lineEndings: LineEndings
    ) throws -> (workspace: URL, corpus: URL) {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-ci-fixtures-\(UUID().uuidString)")
        let corpus = workspace.appendingPathComponent(
            "Tests/GitHub Continuous Integration Validation Tests/Fixtures"
        )

        for file in generatedFiles {
            let destination = corpus.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard var data = Data(base64Encoded: file.base64, options: .ignoreUnknownCharacters)
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if lineEndings == .crlf,
                ["swift", "yaml", "yml"].contains(destination.pathExtension),
                let text = String(data: data, encoding: .utf8),
                !text.contains("\r")
            {
                data = Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
            }
            try data.write(to: destination)
        }

        let organizations = workspace.appendingPathComponent(
            ".github/actions/read-orgs/orgs.yaml"
        )
        try FileManager.default.createDirectory(
            at: organizations.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard
            let organizationsData = Data(
                base64Encoded: generatedOrganizationsManifest,
                options: .ignoreUnknownCharacters
            )
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try organizationsData.write(to: organizations)

        return (workspace, corpus)
    }
}
