import GitHub_Continuous_Integration
import GitHub_Standard

// Nest.Name namespace shell.
//
// `GitHub.ContinuousIntegration.Validation` owns the *predicate* half of the validator contract —
// what a rule is, what it is run against, what it emits, and how an
// implementation is proved. It is the Swift expression of the contract
// that `.github/scripts/validate_lib.py` held for the retired Python
// corpus:
//
//   emit()                       → `Finding` and its TSV encoding
//   require_yaml() / exit 2      → `EnvironmentDefect`
//   load_workflow_yaml_or_emit() → `Subject.workflows()`
//   parse_on_block/iter_jobs     → `GitHub.ContinuousIntegration.Workflow.Document` accessors
//
// A rule implementation declares a `Validator`; it never prints, never
// exits, and never reads argv.
extension GitHub.ContinuousIntegration {
    public enum Validation {}
}
