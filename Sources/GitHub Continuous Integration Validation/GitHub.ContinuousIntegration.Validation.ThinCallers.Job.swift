import GitHub_Continuous_Integration
import GitHub_Standard

extension GitHub.ContinuousIntegration.Validation.ThinCallers {
    /// One top-level job under `jobs:`, with its body lines.
    ///
    /// Job boundaries support diagnostic precedence and the deleted-input
    /// check even when the typed parser refuses a malformed caller.
    public struct Job: Sendable, Equatable {
        public let name: String
        public let lines: [Line]
    }
}

extension GitHub.ContinuousIntegration.Validation.ThinCallers {
    /// Every top-level job, in document order.
    ///
    /// `jobs:` at column 0, a job boundary at indent 2 with `<name>:`
    /// shape, everything deeper (and blank or comment lines between jobs)
    /// belonging to the current job, and the first column-0 key after the
    /// block ending it. Non-canonical shapes are recovered
    /// best-effort — that is the point, since a malformed caller is
    /// exactly the one that needs diagnosing — and the precedence proof
    /// separately refuses to rely on a walk it cannot verify.
    static func jobs(in text: String) -> [Job] {
        let lines = Line.all(text)
        guard let start = lines.firstIndex(where: \.isJobsKey) else { return [] }

        var jobs: [Job] = []
        var name: String?
        var body: [Line] = []
        for line in lines[lines.index(after: start)...] {
            if line.isTopLevelKey { break }
            guard !line.trimmed.isEmpty else {
                if name != nil { body.append(line) }
                continue
            }
            if line.indent == 2, line.isJobNameLine, let key = line.keyWithNoValue {
                if let name { jobs.append(Job(name: name, lines: body)) }
                name = key
                body = []
                continue
            }
            if name != nil { body.append(line) }
        }
        if let name { jobs.append(Job(name: name, lines: body)) }
        return jobs
    }
}

extension GitHub.ContinuousIntegration.Validation.ThinCallers.Job {
    /// The value of `key` inside the job's block-form `with:` mapping, as
    /// raw text with any trailing comment removed, or `nil` when `with:`
    /// or the key is absent.
    public func withBlockValue(_ key: String) -> String? {
        var openerIndent: Int?
        for line in lines {
            if let indent = openerIndent {
                if line.isBlankOrComment { continue }
                if line.indent > indent {
                    if let value = line.value(after: "\(key):"),
                        !value.beforeComment.trimmed.isEmpty
                    {
                        return value.beforeComment.trimmed
                    }
                    continue
                }
                openerIndent = nil
            }
            if line.indent > 0, line.keyWithNoValue == "with" { openerIndent = line.indent }
        }
        return nil
    }
}

extension StringProtocol {
    fileprivate var trimmed: String {
        var value = self[...]
        while let first = value.first, first == " " || first == "\t" { value = value.dropFirst() }
        while let last = value.last, last == " " || last == "\t" { value = value.dropLast() }
        return String(value)
    }

    fileprivate var beforeComment: String {
        var kept = ""
        var previous: Character?
        for character in self {
            if character == "#", previous == nil || previous == " " || previous == "\t" { break }
            kept.append(character)
            previous = character
        }
        return kept
    }
}
