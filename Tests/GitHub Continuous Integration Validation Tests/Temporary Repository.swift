import Foundation
import GitHub_Continuous_Integration
import GitHub_Standard

@testable import GitHub_Continuous_Integration_Validation

/// The generated synthetic organization manifest.
///
/// `[BRANCH-PIN-001]` is scoped by the Institute organization set. The
/// The suite reads the same materialized bytes as the fixture corpus, so
/// it does not depend on the working directory a test runner uses.
enum RepositoryUnderTest {
    static let organizationsFile = FixtureCorpus.organizationsFile
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
