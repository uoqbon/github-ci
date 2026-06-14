# =============================================================================
# Policy-as-code "workflow compilation" / compliance gate (OPA / conftest)
# Run:  conftest test --policy policy/ .github/workflows/
# conftest parses each workflow YAML into `input`. These are STARTER rules —
# extend per your compliance baseline.
# =============================================================================
package main

import future.keywords

# --- 1. All non-local actions must be pinned to a full 40-char commit SHA. ----
deny contains msg if {
	some job_name, job in input.jobs
	some step in job.steps
	uses := step.uses
	not startswith(uses, "./")
	not regex.match(`@[0-9a-f]{40}$`, uses)
	msg := sprintf("job '%s': action '%s' must be pinned to a full 40-char SHA", [job_name, uses])
}

# --- 2. pull_request_target is forbidden (privilege-escalation foot-gun). -----
deny contains msg if {
	input.on.pull_request_target
	msg := "pull_request_target is forbidden by policy (use pull_request + a workflow_run orchestrator)"
}

# --- 3. An explicit top-level permissions block is mandatory (least priv). ----
deny contains msg if {
	not input.permissions
	msg := "workflow must declare an explicit top-level 'permissions' block"
}

# --- 4. runs-on must be on the cost allow-list (string form). -----------------
allowed_runners := {"ubuntu-latest", "ubuntu-24.04", "ubuntu-22.04"}

deny contains msg if {
	some job_name, job in input.jobs
	is_string(job["runs-on"])
	not startswith(job["runs-on"], "${{") # allow expression-driven; validated at runtime
	not allowed_runners[job["runs-on"]]
	msg := sprintf("job '%s': runner '%s' is not on the cost allow-list", [job_name, job["runs-on"]])
}
