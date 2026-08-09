# swift-github-continuous-integration

The GitHub half of continuous integration: the sole owner of the relation
between continuous-integration semantics and GitHub's CI platform.

## Products

- **GitHub Continuous Integration** — the relation's namespace shell,
  `GitHub.ContinuousIntegration`, extending the `GitHub` namespace owned by
  [swift-github-standard](https://github.com/swift-standards/swift-github-standard).
- **GitHub Continuous Integration Workflow** — the *document* half of the
  relation: reading a GitHub Actions workflow file into a typed value
  (`GitHub.ContinuousIntegration.Workflow.Document` and its YAML reader).
- **GitHub Continuous Integration Validation** — the *predicate* half: the
  validation engine (`Validator`, `Rule`, `Finding`, `Subject`, `Corpus`,
  `Harness`, `Registry`) and the GitHub-Actions-mechanics validators that run
  rule predicates over a repository's shipped workflow bytes.

The generic continuous-integration contract (plans, requirements, legs,
tiers, aggregate verdicts) lives in
[swift-continuous-integration](https://github.com/swift-foundations/swift-continuous-integration);
this package owns only what is specific to GitHub's platform.
