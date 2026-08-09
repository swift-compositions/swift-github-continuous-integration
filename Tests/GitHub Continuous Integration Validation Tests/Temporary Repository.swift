import GitHub_Continuous_Integration
import GitHub_Standard
import Foundation

@testable import GitHub_Continuous_Integration_Validation

/// The packaged copy of the canonical organization manifest.
///
/// `[BRANCH-PIN-001]` is scoped by the Institute organization set. The
/// suite reads the copy shipped at the package root, located from this
/// source file's own path, so it does not depend on the working
/// directory a test runner happens to use.
enum RepositoryUnderTest {
    /// `<package root>/.github/actions/read-orgs/orgs.yaml`.
    static let organizationsFile: String = {
        guard
            let path = GitHub.ContinuousIntegration.Validation.BranchPins.Organizations.locateManifest(
                startingAt: (#filePath as NSString).deletingLastPathComponent
            )
        else { fatalError("orgs manifest not found above \(#filePath)") }
        return path
    }()
}

/// A throwaway repository-shaped directory a validator can be asked
/// about.
///
/// The fixture corpus under `.github/scripts/tests/fixtures/` is the
/// contract's shared corpus and is **data** — it is read, never written.
/// A control that needs a shape the corpus does not carry (a baseline
/// ledger, a deliberately unpinned reference) builds it here instead of
/// adding to the corpus, so the differential gate keeps comparing two
/// implementations over identical bytes.
struct TemporaryRepository: ~Copyable {
    let repository: String
    let root: String

    init(repository: String = "swift-institute-test/fixture") {
        self.repository = repository
        self.root = NSTemporaryDirectory() + "institute-ci-tests/" + UUID().uuidString
        try? FileManager.default.createDirectory(
            atPath: root,
            withIntermediateDirectories: true
        )
    }

    var subject: GitHub.ContinuousIntegration.Validation.Subject {
        GitHub.ContinuousIntegration.Validation.Subject(repository: repository, root: root)
    }

    /// Write `contents` at a path relative to the root, creating
    /// intermediate directories.
    func write(_ contents: String, to relative: String) {
        let path = root + "/" + relative
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? Data(contents.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// The absolute path of a file written into this repository.
    func path(_ relative: String) -> String { root + "/" + relative }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }
}
