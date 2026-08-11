import GitHub_Continuous_Integration
import GitHub_Standard
import Foundation
import Testing

@testable import GitHub_Continuous_Integration_Validation

/// Regression coverage for the Windows-only CRLF-collapse defect class
/// (institute-continuous-integration#13) as it reaches the *validation*
/// harness, not only the YAML reader fixed in
/// `GitHub_Continuous_Integration_Workflow`.
///
/// `ThinCallers.Line.all`, `CompositeActionPins.lines(of:)`, and
/// `BranchPins.strippingComments` each read raw, unparsed file bytes —
/// none of them route through the typed `YAML.Document` reader — and
/// each independently split or scanned on `"\n"` the same
/// grapheme-cluster-unsafe way the original YAML `Line.scan` did. On a
/// Windows checkout (CRLF, via `core.autocrlf`) every one of them
/// silently stops finding anything, which is indistinguishable from "no
/// violations" for a validator whose job is to report violations.
///
/// This suite proves the fix the same way the original bug was
/// reproduced: take the real, unmodified fixture corpus, convert every
/// file's line endings to CRLF, and run the harness against the copy. No
/// Windows machine required — the defect (and the fix) is a Unicode-model
/// fact about `Character`, not an OS fact.
@Suite
struct CIValidationCRLFTests {
    /// A CRLF-converted copy of the real fixture corpus. Every
    /// `.swift`/`.yml`/`.yaml` file's `\n` is rewritten to `\r\n`;
    /// everything else (directory shape, non-text files) is copied
    /// verbatim.
    ///
    /// Placed *inside* the checked-out repository tree (a sibling of
    /// `Fixtures`, not a system temp directory) rather than than in
    /// `FileManager.default.temporaryDirectory`: `BranchPins` locates its
    /// organizations manifest by walking up from the corpus root, and
    /// that walk only reaches the real `.github/actions/read-orgs/orgs.yaml`
    /// when the copy stays under the same checkout — exactly like the
    /// unmodified `Fixtures` directory this mirrors.
    static func makeCRLFCorpusDirectory() throws -> URL {
        var testDirectory = URL(fileURLWithPath: #filePath)
        testDirectory.deleteLastPathComponent()
        let source = testDirectory.appendingPathComponent("Fixtures")

        let destination = testDirectory.appendingPathComponent(
            "Fixtures-CRLF-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: destination)

        let enumerator = FileManager.default.enumerator(
            at: destination, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            let isRegular = try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false
            guard isRegular else { continue }
            let ext = url.pathExtension
            guard ext == "swift" || ext == "yml" || ext == "yaml" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.contains("\r") else { continue }
            let crlf = text.replacingOccurrences(of: "\n", with: "\r\n")
            try crlf.write(to: url, atomically: true, encoding: .utf8)
        }

        return destination
    }

    @Test func `the CRLF-converted corpus satisfies every scenario, matching the LF original`() throws
    {
        let destination = try Self.makeCRLFCorpusDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let lfReport = try GitHub.ContinuousIntegration.Validation.Harness(
            corpus: CIValidationHarnessTests.corpus
        ).run()
        let crlfReport = try GitHub.ContinuousIntegration.Validation.Harness(
            corpus: .init(root: destination.path)
        ).run()

        for outcome in crlfReport.unsatisfied { Issue.record("\(outcome.summary)") }
        #expect(crlfReport.isSatisfied)
        #expect(crlfReport.outcomes.count == lfReport.outcomes.count)

        let violating = crlfReport.outcomes.filter { $0.scenario.expectation == .violating }
        #expect(!violating.isEmpty)
        for outcome in violating {
            #expect(
                !outcome.findings.isEmpty, "\(outcome.rule) \(outcome.scenario.name)")
        }
    }
}
