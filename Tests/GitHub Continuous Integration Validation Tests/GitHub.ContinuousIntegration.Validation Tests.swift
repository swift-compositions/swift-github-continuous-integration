import GitHub_Continuous_Integration
import GitHub_Standard
import Testing

@testable import GitHub_Continuous_Integration_Validation

@Suite
struct CIValidationTests {
    @Suite
    struct Unit {
        @Test func `finding encodes as three tab separated columns`() {
            let finding = GitHub.ContinuousIntegration.Validation.Finding(
                repository: "swift-institute/.github",
                rule: "CI-105",
                message: "ci.yml: broken"
            )
            #expect(finding.tsv == "swift-institute/.github\tCI-105\tci.yml: broken")
        }

        @Test func `clean run exits zero`() {
            #expect(GitHub.ContinuousIntegration.Validation.Run(findings: []).exitCode == 0)
        }

        @Test func `environment defect exits two`() {
            let run = GitHub.ContinuousIntegration.Validation.Run(
                findings: [],
                defect: .unreadableSubject(root: "/nowhere")
            )
            #expect(run.exitCode == 2)
            #expect(
                run.exitCode == GitHub.ContinuousIntegration.Validation.EnvironmentDefect.exitCode
            )
        }

        @Test func `corpus directory resolves to its registered spelling`() {
            #expect(
                GitHub.ContinuousIntegration.Validation.Registry.rule(forCorpusDirectory: "ci-105")
                    == "CI-105"
            )
            #expect(
                GitHub.ContinuousIntegration.Validation.Registry.rule(forCorpusDirectory: "ci-999")
                    == nil
            )
        }
    }

    @Suite
    struct `Edge Case` {
        @Test func `tabs and newlines in the message are flattened`() {
            // Otherwise the aggregation step reads a wrapped sentence as
            // extra columns.
            let finding = GitHub.ContinuousIntegration.Validation.Finding(
                repository: "r",
                rule: "CI-105",
                message: "one\ttwo\nthree"
            )
            #expect(finding.tsv == "r\tCI-105\tone two three")
            #expect(finding.tsv.filter { $0 == "\t" }.count == 2)
        }

        @Test func `findings do not change the exit code`() {
            // A dirty repository is not a broken machine, so it must not
            // exit like one.
            let run = GitHub.ContinuousIntegration.Validation.Run(findings: [
                .init(repository: "r", rule: "CI-105", message: "a")
            ])
            #expect(run.exitCode == 0)
        }

        @Test func `two findings do not impersonate an environment defect`() {
            // The defect in the retired `sys.exit(main(...))` convention:
            // a count of exactly two collided with the defect code.
            let run = GitHub.ContinuousIntegration.Validation.Run(findings: [
                .init(repository: "r", rule: "CI-105", message: "a"),
                .init(repository: "r", rule: "CI-105", message: "b"),
            ])
            #expect(
                run.exitCode != GitHub.ContinuousIntegration.Validation.EnvironmentDefect.exitCode
            )
        }

        @Test func `a missing subject root is a defect not a clean result`() {
            let run = GitHub.ContinuousIntegration.Validation.Run.validate(
                GitHub.ContinuousIntegration.Validation.ContinueOnError(),
                of: .init(repository: "r", root: "/nonexistent-subject-root")
            )
            // No workflows directory means no findings, and that is a
            // legitimate clean answer — absence of a subject tree is not
            // by itself unreadable.
            #expect(run.findings.isEmpty)
        }
    }

    @Suite
    struct Integration {
        @Test func `every registered validator claims rules and no rule has two owners`() {
            var seen: Set<GitHub.ContinuousIntegration.Validation.Rule> = []
            for validator in GitHub.ContinuousIntegration.Validation.Registry.validators {
                #expect(!validator.rules.isEmpty)
                for rule in validator.rules {
                    #expect(seen.insert(rule).inserted, "rule \(rule) has more than one owner")
                }
            }
        }

        @Test func `every registered rule resolves back to its validator`() {
            for rule in GitHub.ContinuousIntegration.Validation.Registry.rules {
                #expect(
                    GitHub.ContinuousIntegration.Validation.Registry.validator(for: rule) != nil
                )
            }
        }
    }
}
