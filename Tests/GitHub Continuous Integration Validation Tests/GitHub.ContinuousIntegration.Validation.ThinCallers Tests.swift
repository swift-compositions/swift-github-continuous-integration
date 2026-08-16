import Foundation
import GitHub_Continuous_Integration
import GitHub_Continuous_Integration_Validation
import GitHub_Standard
import Testing

/// The fixture corpus is the differential gate's subject and covers the
/// registered shapes. These tests prove the terminal credential-free
/// caller and the diagnostic-precedence behavior directly.
@Suite
struct CIValidationThinCallersTests {
    /// A subject built from text written into a scratch tree, since every
    /// predicate reads a real repository layout.
    static func subject(
        _ repository: String,
        ci: String? = nil,
        files: [String: String] = [:]
    ) throws -> (GitHub.ContinuousIntegration.Validation.Subject, URL) {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "c3-\(UUID().uuidString)")
        var contents = files
        contents["Package.swift"] = files["Package.swift"] ?? "// swift-tools-version: 6.3\n"
        if let ci { contents[".github/workflows/ci.yml"] = ci }
        for (path, text) in contents {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return (
            GitHub.ContinuousIntegration.Validation.Subject(
                repository: repository,
                root: root.path
            ), root
        )
    }

    static func findings(
        _ repository: String,
        ci: String? = nil,
        files: [String: String] = [:]
    ) throws -> [GitHub.ContinuousIntegration.Validation.Finding] {
        let (subject, root) = try subject(repository, ci: ci, files: files)
        defer { try? FileManager.default.removeItem(at: root) }
        return try GitHub.ContinuousIntegration.Validation.ThinCallers().findings(in: subject)
    }

    static let terminalCaller = """
        name: CI

        on:
          push:
            branches:
              - main

        jobs:
          ci:
            uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
        """

    @Test
    func theTerminalCallerNeedsNoCredentialSurface() throws {
        #expect(try Self.findings("swift-standards/swift-x", ci: Self.terminalCaller).isEmpty)
        #expect(try Self.findings("swift-iso/swift-x", ci: Self.terminalCaller).isEmpty)
    }

    // MARK: - File-level carve-out

    /// A workflow declaring `workflow_call:` *is* a reusable, and every
    /// rule here constrains callers. Tool-host packages ([GH-REPO-077])
    /// carry action refs and inline steps on purpose.
    @Test
    func aReusableIsExemptFromEveryRule() throws {
        let reusable = """
            name: Tool
            on:
              workflow_call:
            jobs:
              build:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
            """
        #expect(try Self.findings("swift-standards/swift-x", ci: reusable).isEmpty)
    }

    // MARK: - [CI-030]

    /// The discriminator is the `.github/.github/workflows/` double
    /// infix. A third-party action pinned at a tag is `[CI-107]`
    /// discipline, not a `[CI-030]` violation, and must not fire.
    @Test
    func onlyIntraInstituteReferencesAreHeldToTheMainPin() throws {
        let caller = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@v1.0.0
              other:
                uses: some-vendor/some-repo/.github/workflows/thing.yml@v3
            """
        let pins = try Self.findings("swift-standards/swift-x", ci: caller)
            .filter { $0.rule.rawValue == "CI-030" }
        #expect(pins.count == 1)
        #expect(
            pins[0].message.contains(
                "swift-standards/.github/.github/workflows/swift-ci.yml@v1.0.0"
            )
        )
        #expect(!pins[0].message.contains("some-vendor"))
    }

    // MARK: - Diagnostic precedence

    /// When every job is inline and none delegates, the missing-reusable
    /// finding is the root: repairing it necessarily removes those jobs'
    /// `runs-on:` and `steps:`. Reporting all three describes one repair
    /// three times, so the two secondaries are omitted.
    @Test
    func theMissingReusableRootSupersedesTheInlineDiagnostics() throws {
        let allInline = """
            name: CI
            on:
              push:
                branches:
                  - main
            jobs:
              build:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
            """
        let findings = try Self.findings("swift-standards/swift-x", ci: allInline)
        #expect(findings.count == 1)
        #expect(findings[0].message.contains("does not reference any reusable"))
    }

    /// A *mixed* workflow keeps all three. The precedence proof is not a
    /// heuristic about how many findings there are: with one delegating
    /// job present, removing the inline job is a separate repair from
    /// adding a caller, so the diagnostics are independent again.
    @Test
    func aMixedWorkflowKeepsEveryDiagnostic() throws {
        let mixed = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
              extra:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
            """
        let messages = try Self.findings("swift-standards/swift-x", ci: mixed)
            .filter { $0.rule.rawValue == "GH-REPO-074" }
            .map(\.message)
        #expect(messages.count == 2)
        #expect(messages.contains { $0.contains("inline `runs-on:`") })
        #expect(messages.contains { $0.contains("inline `steps:`") })
    }

    /// An unparseable workflow must still be diagnosed. Reporting nothing
    /// on a broken caller is the worst available answer, and it is why
    /// these predicates read lines rather than the typed document: the
    /// precedence *proof* needs parseability and fails closed without it,
    /// which is the opposite obligation.
    @Test
    func anUnparseableWorkflowStillProducesDiagnostics() throws {
        let broken = """
            jobs:
              build:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v6
                 bad-indent: [unclosed
            """
        let findings = try Self.findings("swift-standards/swift-x", ci: broken)
        #expect(findings.count == 3)
    }

    // MARK: - Scope

    /// `[GH-REPO-074]` scopes to per-package repositories. No root
    /// manifest, no obligation — an inline workflow in a non-package
    /// repository is not a thin-caller violation.
    @Test
    func aRepositoryWithoutARootManifestIsOutOfScope() throws {
        let (subject, root) = try Self.subject(
            "swift-standards/swift-x",
            ci: "jobs:\n  a:\n    runs-on: ubuntu-latest\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appending(path: "Package.swift"))
        #expect(
            try GitHub.ContinuousIntegration.Validation.ThinCallers().findings(in: subject).isEmpty
        )
    }

    /// The consolidated legs must not come back as standalone files, and
    /// this fires independently of `ci.yml` — including when `ci.yml` is
    /// perfectly conforming.
    @Test
    func standaloneFormatAndLintWorkflowsFireOnTheirOwn() throws {
        let findings = try Self.findings(
            "swift-standards/swift-x",
            ci: Self.terminalCaller,
            files: [
                ".github/workflows/swift-format.yml": "name: fmt\n",
                ".github/workflows/swiftlint.yml": "name: lint\n",
            ]
        )
        #expect(findings.count == 2)
        #expect(findings.allSatisfy { $0.message.contains("exists as a standalone file") })
    }

    // MARK: - INTEGRATED-DOCS-ADMISSION

    /// TX10 deleted the input, so any value is a live undeclared-input
    /// breakage; absence is the terminal shape and is not a finding. The
    /// rule reads the `ci` job only.
    @Test
    func theDeletedBridgeInputFiresOnAnyValueAndOnlyOnTheCiJob() throws {
        let caller = """
            jobs:
              ci:
                uses: swift-standards/.github/.github/workflows/swift-ci.yml@main
                with:
                  integrated-docs: true
            """
        let findings = try Self.findings("swift-standards/swift-x", ci: caller)
            .filter { $0.rule.rawValue == "INTEGRATED-DOCS-ADMISSION" }
        #expect(findings.count == 1)
        #expect(findings[0].message.contains("integrated-docs: true"))
        #expect(try Self.findings("swift-standards/swift-x", ci: Self.terminalCaller).isEmpty)
    }

    // MARK: - Registration

    /// Every retained rule resolves to this validator.
    @Test
    func everyRuleResolvesToThisValidator() {
        for rule in ["CI-030", "GH-REPO-074", "INTEGRATED-DOCS-ADMISSION"] {
            let validator = GitHub.ContinuousIntegration.Validation.Registry.validator(
                for: .init(rule)
            )
            #expect(validator is GitHub.ContinuousIntegration.Validation.ThinCallers, "\(rule)")
        }
    }
}
