import GitHub_Continuous_Integration
import GitHub_Continuous_Integration_Workflow
import GitHub_Standard

extension GitHub.ContinuousIntegration.Validation {
    /// `[GH-REPO-074]`, `[CI-030]`, and
    /// `INTEGRATED-DOCS-ADMISSION` — a per-package `ci.yml` is a thin
    /// caller pinned at `@main`.
    ///
    /// - **`[GH-REPO-074]`** — no inline `runs-on:` or `steps:` in any
    ///   job, at least one job delegating via `uses:`, and no standalone
    ///   `swift-format.yml` / `swiftlint.yml` (the format and lint legs
    ///   were absorbed into the universal matrix on 2026-05-10).
    /// - **`[CI-030]`** — an intra-Institute reusable ref pins to `@main`
    ///   while the surface is pre-`v1`. The discriminator is the
    ///   `.github/.github/workflows/` double infix, unique to
    ///   org-`.github` reusables; a third-party ref
    ///   (`actions/checkout@v6`) has a different shape and is exempt
    ///   under `[CI-107]`.
    /// - **`INTEGRATED-DOCS-ADMISSION`** — TX10 deleted the temporary
    ///   `integrated-docs` input, so a caller still sending it fails at
    ///   run time on an undeclared input. A live breakage, not a style
    ///   nit; absence is the terminal shape and is not a finding.
    ///
    /// Reusables are exempt from all four at file level: a workflow
    /// declaring `on: workflow_call:` *is* the reusable, and these rules
    /// constrain callers.
    ///
    /// **Why this reads lines rather than the typed document.** Every
    /// predicate here is line-anchored by design, and deliberately so:
    /// the rules must still produce diagnostics on a workflow the parser
    /// refuses, because an unparseable `ci.yml` is a broken caller and
    /// reporting nothing would be the worst possible answer. The typed
    /// reader is used for the one predicate that genuinely needs
    /// parseability — the diagnostic-precedence proof below — where
    /// failing closed is correct.
    ///
    /// It also does not consume `Repository.Policy.Caller.Parse`, and
    /// that is not an oversight. `Parse` is `Render`'s inverse and fails
    /// closed on anything the renderer cannot emit; this validator's
    /// subjects are arbitrary repository workflows, most of which are
    /// exactly the non-canonical shapes `Parse` refuses. Routing them
    /// through `Parse` would collapse every distinct diagnostic into one
    /// "unknown customization", which is the opposite of what the rule
    /// is for.
    public struct ThinCallers: Validator {
        public let rules: [Rule] = [
            "CI-030", "GH-REPO-074", "INTEGRATED-DOCS-ADMISSION",
        ]
        public let retiredScript: String? = ".github/scripts/validate-thin-callers.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            // `[GH-REPO-074]` scopes to per-package repositories. No root
            // manifest, no obligation.
            guard try subject.text(at: "Package.swift") != nil else { return [] }
            var findings: [Finding] = []
            if let text = try subject.text(at: ".github/workflows/ci.yml") {
                findings += try Self.findings(in: text, subject: subject)
            }
            findings += try Self.standaloneWorkflowFindings(in: subject)
            return findings
        }

        static func findings(
            in text: String,
            subject: Subject
        ) throws(EnvironmentDefect) -> [Finding] {
            // File-level carve-out for every rule here: a workflow that
            // declares `workflow_call:` *is* a reusable. Tool-host
            // packages ([GH-REPO-077]) host action refs on purpose.
            guard !Line.all(text).contains(where: { $0.declaresWorkflowCall }) else { return [] }

            let repository = subject.repository
            var findings: [Finding] = []
            let supersedes = supersedesInlineDiagnostics(text)

            if Line.all(text).contains(where: \.isInlineRunsOn), !supersedes {
                findings.append(
                    Finding(
                        repository: repository,
                        rule: "GH-REPO-074",
                        message: Message.inlineRunsOn
                    )
                )
            }
            if Line.all(text).contains(where: \.isInlineSteps), !supersedes {
                findings.append(
                    Finding(
                        repository: repository,
                        rule: "GH-REPO-074",
                        message: Message.inlineSteps
                    )
                )
            }
            if !Line.all(text).contains(where: \.isJobUses) {
                findings.append(
                    Finding(
                        repository: repository,
                        rule: "GH-REPO-074",
                        message: Message.noReusable
                    )
                )
            }
            findings += pinFindings(in: text, repository: repository)
            findings += integratedDocsFindings(in: text, repository: repository)
            return findings
        }

        // MARK: - [GH-REPO-074]

        static func standaloneWorkflowFindings(
            in subject: Subject
        ) throws(EnvironmentDefect) -> [Finding] {
            var findings: [Finding] = []
            for name in ["swift-format.yml", "swiftlint.yml"] {
                guard try subject.text(at: ".github/workflows/\(name)") != nil else { continue }
                findings.append(
                    Finding(
                        repository: subject.repository,
                        rule: "GH-REPO-074",
                        message: Message.standaloneWorkflow(name)
                    )
                )
            }
            return findings
        }

        /// Whether the missing-reusable finding is the root the two
        /// inline findings would only restate.
        ///
        /// This is diagnostic factoring, not a narrowing of
        /// `[GH-REPO-074]`: correcting the root — replacing every inline
        /// job with a reusable caller — necessarily removes those same
        /// jobs' `runs-on:` and `steps:`, so reporting all three describes
        /// one repair three times. Suppression requires *proof*: one
        /// canonical `jobs:` mapping, the typed reader agreeing on the
        /// same job set, no job-level `uses:` anywhere, every job inline,
        /// and every broad match accounted for as a direct key of a
        /// parsed job. Mixed, partial, non-canonical, and unparseable
        /// shapes keep all three findings. Prevalence and repository
        /// identity are not inputs.
        static func supersedesInlineDiagnostics(_ text: String) -> Bool {
            let jobs = self.jobs(in: text)
            guard hasOneCanonicalJobsMapping(text, jobs: jobs) else { return false }
            guard readerAgrees(text, jobs: jobs) else { return false }
            guard !Line.all(text).contains(where: \.isJobUses) else { return false }
            guard !jobs.contains(where: { $0.lines.contains(where: \.isDirectJobUses) }) else {
                return false
            }
            guard
                jobs.allSatisfy({ job in
                    job.lines.contains(where: \.isDirectJobRunsOn)
                        && job.lines.contains(where: \.isDirectJobSteps)
                })
            else { return false }

            let directRunsOn = jobs.reduce(0) { $0 + $1.lines.count(where: \.isDirectJobRunsOn) }
            let directSteps = jobs.reduce(0) { $0 + $1.lines.count(where: \.isDirectJobSteps) }
            let allRunsOn = Line.all(text).count(where: \.isInlineRunsOn)
            let allSteps = Line.all(text).count(where: \.isInlineSteps)
            return directRunsOn + directSteps > 0
                && directRunsOn == allRunsOn && directSteps == allSteps
        }

        /// Whether the line walk accounted for exactly one canonical
        /// `jobs:` mapping. Any alias, inline mapping, malformed
        /// boundary, non-canonical indent, duplicate `jobs:` key, or
        /// content before the first job fails the proof closed.
        static func hasOneCanonicalJobsMapping(_ text: String, jobs: [Job]) -> Bool {
            let lines = Line.all(text)
            let starts = lines.indices.filter { lines[$0].isJobsKey }
            guard starts.count == 1, !jobs.isEmpty else { return false }

            var parsed = 0
            var inJob = false
            for line in lines[lines.index(after: starts[0])...] {
                if line.isTopLevelKey { break }
                if line.isBlankOrComment { continue }
                guard line.indent != 2 else {
                    guard line.isJobNameLine else { return false }
                    parsed += 1
                    inJob = true
                    continue
                }
                if line.indent < 4 || !inJob { return false }
            }
            return parsed == jobs.count
        }

        /// Whether the typed reader confirms the same job mapping.
        ///
        /// Textual indentation alone cannot establish parseability. This
        /// second gate fails closed on a refused document, a non-mapping
        /// root or job, a duplicate job name, or any disagreement between
        /// the line walk and the reader about the job set.
        static func readerAgrees(_ text: String, jobs: [Job]) -> Bool {
            let document: GitHub.ContinuousIntegration.Workflow.Document
            do throws(GitHub.ContinuousIntegration.Workflow.YAML.Error) {
                document = try GitHub.ContinuousIntegration.Workflow.Document(
                    name: "ci.yml",
                    text: text
                )
            } catch {
                // A document the reader refuses proves nothing, and this
                // is the one predicate here that must fail closed: the
                // suppression it gates would otherwise be granted on an
                // unverified walk.
                return false
            }
            guard let mapping = document.body?["jobs"]?.mapping else { return false }
            let read = mapping.entries.compactMap { entry -> String? in
                guard entry.value.mapping != nil else { return nil }
                return entry.key.text
            }
            return read.count == mapping.entries.count && read == jobs.map(\.name)
        }

        // MARK: - [CI-030]

        static func pinFindings(in text: String, repository: String) -> [Finding] {
            Line.all(text).compactMap { line in
                guard let reference = line.intraInstituteReference, reference.ref != "main"
                else { return nil }
                return Finding(
                    repository: repository,
                    rule: "CI-030",
                    message: Message.unpinnedReference(reference)
                )
            }
        }

        // MARK: - INTEGRATED-DOCS-ADMISSION

        static func integratedDocsFindings(in text: String, repository: String) -> [Finding] {
            jobs(in: text).compactMap { job in
                guard job.name == "ci",
                    let value = job.withBlockValue("integrated-docs")
                else { return nil }
                return Finding(
                    repository: repository,
                    rule: "INTEGRATED-DOCS-ADMISSION",
                    message: Message.integratedDocs(value)
                )
            }
        }
    }
}
