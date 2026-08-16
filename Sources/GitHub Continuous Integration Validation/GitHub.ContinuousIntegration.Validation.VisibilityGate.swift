import GitHub_Continuous_Integration
import GitHub_Continuous_Integration_Workflow
import GitHub_Standard

extension GitHub.ContinuousIntegration.Validation {
    /// `[CI-032]` — every job in every intra-Institute `workflow_call`
    /// reusable must carry its explicit repository-visibility gate.
    ///
    /// Public package CI uses `!github.event.repository.private` appearing
    /// anywhere in the job's `if:`, so both the simple form
    /// (`if: ${{ !github.event.repository.private }}`) and the compound
    /// form (`if: ${{ always() && !github.event.repository.private }}`)
    /// satisfy it. The terminal `private-verification.yml` reusable has the
    /// inverse contract: every work and aggregate job must contain
    /// `github.event.repository.private` without its negated spelling. This
    /// keeps public package CI out of private repositories while admitting
    /// the separately owned private verification surface only there.
    ///
    /// Scope and carve-outs:
    ///
    /// - A workflow whose `on:` does not include `workflow_call` is out
    ///   of scope. A schedule- or dispatch-only orchestrator has no
    ///   consumer-callable surface and therefore no private-repository
    ///   concern.
    /// - A **pure routing job** — `uses:` at job level with no `steps:`
    ///   and no `runs-on:` — is exempt. The gate belongs on the called
    ///   workflow's real work job, not on the shim. The exemption is
    ///   narrow on purpose: a job carrying real work is never treated as
    ///   pure routing even when it also declares `uses:`, which is what
    ///   the `fail/routing-plus-ungated-work` fixture pins.
    /// - `if: false` is an explicitly disabled job, in either the boolean
    ///   or the string spelling.
    public struct VisibilityGate: Validator {
        public static let publicGate = "!github.event.repository.private"
        public static let privateGate = "github.event.repository.private"
        public static let privateVerificationDocument = "private-verification.yml"

        public let rules: [Rule] = ["CI-032"]
        public let retiredScript: String? = ".github/scripts/validate-visibility-gate.py"

        public init() {}

        public func findings(in subject: Subject) throws(EnvironmentDefect) -> [Finding] {
            let rule = rules[0]
            let (documents, refusals) = try subject.workflows(citing: rule)
            var findings = refusals
            for document in documents where Self.isReusable(document) {
                let gate = Self.gate(for: document)
                for job in document.jobs {
                    guard !Self.isPureRouting(job) else { continue }
                    let clause = Self.clause(job)
                    guard !Self.isDisabled(clause) else { continue }
                    let text = Self.text(of: clause)
                    guard !Self.contains(gate: gate, in: text) else { continue }
                    findings.append(
                        Finding(
                            repository: subject.repository,
                            rule: rule,
                            message: Self.message(
                                document: document.name,
                                job: job.name,
                                clause: text,
                                gate: gate
                            )
                        )
                    )
                }
            }
            return findings
        }

        static func gate(
            for document: GitHub.ContinuousIntegration.Workflow.Document
        ) -> String {
            document.name == privateVerificationDocument ? privateGate : publicGate
        }

        static func contains(gate: String, in clause: String) -> Bool {
            if gate == privateGate {
                return clause.contains(privateGate) && !clause.contains(publicGate)
            }
            return clause.contains(publicGate)
        }

        /// Whether the document declares a `workflow_call` trigger, in
        /// any of its three spellings: bare (`on: workflow_call`), list
        /// (`on: [workflow_call]`), and map.
        ///
        /// The `on:` key is read through the YAML 1.1 recovery — the
        /// boolean key first, the string second, matching the retired
        /// `get_on_block`.
        static func isReusable(_ document: GitHub.ContinuousIntegration.Workflow.Document) -> Bool {
            guard let body = document.body else { return false }
            guard let node = body[node: .boolean(true)] ?? body["on"] else { return false }
            switch node {
            case .text(let value): return value == "workflow_call"
            case .sequence(let elements): return elements.contains(.text("workflow_call"))
            case .mapping(let mapping): return mapping.textKeys.contains("workflow_call")
            default: return false
            }
        }

        /// A `workflow_call` routing job: `uses:` at job level, no
        /// `steps:` and no `runs-on:`.
        static func isPureRouting(_ job: GitHub.ContinuousIntegration.Workflow.Job) -> Bool {
            job.body["uses"] != nil && job.body["steps"] == nil && job.body["runs-on"] == nil
        }

        static func clause(
            _ job: GitHub.ContinuousIntegration.Workflow.Job
        ) -> GitHub.ContinuousIntegration.Workflow.YAML.Node? {
            job.body["if"]
        }

        /// Whether the job is explicitly disabled, in either spelling:
        /// the boolean `false`, or a string that reads `false` once
        /// trimmed and lower-cased.
        static func isDisabled(_ clause: GitHub.ContinuousIntegration.Workflow.YAML.Node?) -> Bool {
            if clause?.boolean == false { return true }
            return text(of: clause).trimmedForDisable == "false"
        }

        /// The clause as the retired validator saw it: Python's `str()`
        /// of the loaded value, with an absent or explicitly null key
        /// reading as the empty string.
        ///
        /// Booleans stringify Python-side with a leading capital, which
        /// is why `if: true` reports as `'True'` rather than `'true'`.
        /// That spelling reaches the finding message and the differential
        /// gate compares it.
        static func text(of clause: GitHub.ContinuousIntegration.Workflow.YAML.Node?) -> String {
            switch clause {
            case .none, .some(.null): ""
            case .some(.text(let value)): value
            case .some(.boolean(let value)): value ? "True" : "False"
            case .some(.integer(let value)): String(value)
            case .some(.number(let value)): String(value)
            case .some(.sequence), .some(.mapping): "\(clause!)"
            }
        }

        static func message(
            document: String,
            job: String,
            clause: String,
            gate: String
        ) -> String {
            """
            \(document): job \(job.pythonRepresentation) missing visibility gate \
            per [CI-032] — `if:` must contain `\(gate)` (simple or compound form); \
            got if=\(clause.pythonRepresentation)
            """
        }
    }
}

extension String {
    /// The value trimmed of ASCII whitespace and lower-cased — Python's
    /// `str.strip().lower()` over the spellings a workflow key can hold.
    fileprivate var trimmedForDisable: String {
        var value = Substring(self)
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        while let first = value.first, whitespace.contains(first) { value = value.dropFirst() }
        while let last = value.last, whitespace.contains(last) { value = value.dropLast() }
        return value.lowercased()
    }

    /// The value as Python's `repr()` writes it.
    ///
    /// Reproduced rather than approximated because it is *inside the
    /// finding message* the differential gate compares byte-for-byte:
    /// Python quotes with `'` unless the value contains a `'` and no `"`,
    /// in which case it switches to `"` rather than escaping.
    fileprivate var pythonRepresentation: String {
        let quote: Character = contains("'") && !contains("\"") ? "\"" : "'"
        var result = String(quote)
        for character in self {
            switch character {
            case "\\": result += "\\\\"
            case quote: result += "\\\(quote)"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(character)
            }
        }
        result.append(quote)
        return result
    }
}
