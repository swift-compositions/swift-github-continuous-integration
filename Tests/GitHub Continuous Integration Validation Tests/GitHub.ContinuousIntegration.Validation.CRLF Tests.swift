import Foundation
import GitHub_Continuous_Integration
import GitHub_Standard
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
/// reproduced: materialize the exact generated fixture bytes with CRLF
/// line endings, and run the harness against that tree. No
/// Windows machine required — the defect (and the fix) is a Unicode-model
/// fact about `Character`, not an OS fact.
@Suite
struct CIValidationCRLFTests {
    /// A CRLF materialization of the generated fixture corpus. Every
    /// `.swift`/`.yml`/`.yaml` file's `\n` is rewritten to `\r\n`;
    /// everything else (directory shape, non-text files) is preserved
    /// byte-for-byte. The generated workspace also materializes the
    /// synthetic organization manifest that `BranchPins` locates by
    /// walking upward from the corpus root.

    @Test func `the CRLF-converted corpus satisfies every scenario, matching the LF original`()
        throws
    {
        let materialized = try FixtureCorpus.materialize(lineEndings: .crlf)
        defer { try? FileManager.default.removeItem(at: materialized.workspace) }

        let lfReport = try GitHub.ContinuousIntegration.Validation.Harness(
            corpus: CIValidationHarnessTests.corpus
        ).run()
        let crlfReport = try GitHub.ContinuousIntegration.Validation.Harness(
            corpus: .init(root: materialized.corpus.path)
        ).run()

        for outcome in crlfReport.unsatisfied { Issue.record("\(outcome.summary)") }
        #expect(crlfReport.isSatisfied)
        #expect(crlfReport.outcomes.count == lfReport.outcomes.count)

        let violating = crlfReport.outcomes.filter { $0.scenario.expectation == .violating }
        #expect(!violating.isEmpty)
        for outcome in violating {
            #expect(
                !outcome.findings.isEmpty,
                "\(outcome.rule) \(outcome.scenario.name)"
            )
        }
    }
}
