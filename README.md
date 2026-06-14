# Golden-Path CI Scaffold (GitHub Actions + Copilot)

Committable reference implementation for the three PoC scenarios in `docs/scenario-pocs.md`. It encodes the **two-repo governance model**: a central governance repo publishes versioned reusable workflows/actions; consumer repos call them by pinned SHA and are constrained by enterprise policy + rulesets.

> ⚠️ **Before you commit:** every third-party action below is pinned to a **placeholder 40-char SHA** (`0a1b2c3d…`) with the intended version in a trailing comment. Replace each with the **real release SHA** (e.g. `gh api repos/actions/checkout/git/refs/tags/v4.2.2 --jq .object.sha`). The enterprise Actions policy enforces full-SHA pinning, so placeholder/tag refs will fail. Replace `acme`, `987654321` (governance repo ID), and `4242` (platform team ID) with your real values.

## Layout

```
src/
├── .github/workflows/
│   ├── reusable-ci.yml                  # GOVERNANCE repo: golden-path CI (workflow_call)
│   ├── reusable-security-compliance.yml # GOVERNANCE repo: mandatory compliance (nested, depth 2)
│   ├── self-healing-ci.yml              # CONSUMER repo / org `.github`: workflow_run self-healer
│   └── caller-example.yml               # CONSUMER repo: the ~6-line CI a team actually writes
├── actions/oidc-cloud-login/action.yml  # GOVERNANCE repo: composite — keyless OIDC cloud login
├── rulesets/
│   ├── org-require-golden-path.json      # Layer 1: require golden path (SHA-pinned, tier=production)
│   ├── protect-workflow-files.json       # Layer 2b: push lock on .github/workflows/**
│   └── repo-metadata-guardrails.json     # Layer 3: repo naming/metadata governance
└── policy/workflow-compliance.rego        # "workflow compilation" gate (OPA/conftest)
```

## Where each file lives

| File | Repo | Notes |
|---|---|---|
| `reusable-ci.yml`, `reusable-security-compliance.yml`, `actions/oidc-cloud-login/` | `acme/.github-governance` | Published artifacts; tag a release and pin consumers to its SHA. |
| `caller-example.yml` | each consumer repo (`.github/workflows/ci.yml`) | Seeded by the self-service provisioning governor. |
| `self-healing-ci.yml` | consumer repo, or org `.github` repo for fleet-wide reuse | Needs a user-scoped `SELF_HEAL_TOKEN` secret to assign Copilot. |
| `rulesets/*.json` | applied at the **org** via API | Not committed to consumer repos; managed centrally / via IaC. |
| `policy/*.rego` | `acme/.github-governance` | Pulled into the compliance job at the pinned SHA. |

## Deploy (one-time, platform team)

```bash
# 1. Enterprise/org action-catalog policy: verified-only + mandatory SHA pinning + read-only default token
gh api -X PUT /orgs/ACME/actions/permissions            -f allowed_actions='selected' -f enabled_repositories='all'
gh api -X PUT /orgs/ACME/actions/permissions/selected-actions -F github_owned_allowed=true -F verified_allowed=true -f 'patterns_allowed[]=acme/*'
gh api -X PUT /orgs/ACME/actions/permissions/workflow    -F default_workflow_permissions='read' -F can_approve_pull_request_reviews=false

# 2. Define the `tier` custom property once (sandbox|internal|production)
gh api -X PUT /orgs/ACME/properties/schema/tier \
  -f value_type='single_select' -f 'allowed_values[]=sandbox' -f 'allowed_values[]=internal' -f 'allowed_values[]=production'

# 3. Apply the rulesets (dry-run first: set "enforcement":"evaluate", inspect, then "active")
gh api -X POST /orgs/ACME/rulesets --input rulesets/org-require-golden-path.json
gh api -X POST /orgs/ACME/rulesets --input rulesets/protect-workflow-files.json
gh api -X POST /orgs/ACME/rulesets --input rulesets/repo-metadata-guardrails.json
```

## Wire-up checklist

- [ ] Replace all placeholder SHAs with real release SHAs (consider Dependabot / `pin-github-action` to maintain).
- [ ] Replace `acme`, governance `repository_id`, and platform `actor_id`.
- [ ] Create a CODEOWNERS in consumer repos: `/.github/** @acme/platform-team` (Layer 2a).
- [ ] Configure cloud trust policies scoping the OIDC `sub` to `repo:acme/<repo>:environment:production` (no wildcards).
- [ ] Add `SELF_HEAL_TOKEN` (user-scoped PAT or App user-to-server token) and enable the Copilot coding agent on target repos.
- [ ] Roll out rulesets in `evaluate` mode, review the dry-run, then switch to `active`.
- [ ] Stand up FinOps dashboards (Actions usage + Copilot AI Credit consumption) before enabling agentic features fleet-wide — see `../01-strategic-financial-evaluation.md` §3.

## Validate locally

```bash
# Workflow correctness + security:
actionlint .github/workflows/*.yml
pipx run zizmor .github/workflows/

# Policy gate:
conftest test --policy policy/ .github/workflows/

# Ruleset JSON parses:
for f in rulesets/*.json; do jq empty "$f" && echo "OK: $f"; done
```
