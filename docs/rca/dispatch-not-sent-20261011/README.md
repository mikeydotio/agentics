# Reviewed reconciliation of an unsent dispatch

An interrupted owner can leave `dispatch-attempted` recorded even when no native transport call occurred. The previous helper rejected reconciliation forever because it had no supported way to record reviewed evidence of that exact no-send case. This repair adds `dispatch-not-sent`, preserving the interrupted task and original history instead of manufacturing a worker ID or successful result.

The attestation requires the original owner session, batch, task, digest and attempt, a nonempty reason/evidence/reviewer and a SHA-256. It rejects dispatch confirmation, native identity, result payload, shutdown/integrity claims, malformed evidence, conflicting duplicates and unsupported terminal histories. Finish and reload use the same unresolved-dispatch calculation. Existing surviving-worker, artifact-review and integrity gates remain.

This is a trusted-owner attestation, not authentication or automatic proof of no transport. The helper validates the record shape and history; it does not fetch the evidence or authenticate the reviewer. Cross-owner recovery remains unsupported.

The canonical Agents implementation and RCA/Forge copies are byte-identical. [Focused results](engineering/focused-results-final.json), raw logs and [independent review](nosend_independent_review_a11-delivery.json) are sealed in [MANIFEST.json](MANIFEST.json). The owner reproduction changed from one failure to zero; the focused Agents, RCA and Forge suites and mutation controls passed. The [sibling sweep](nosend_sibling_sweep_a11-delivery.json) found no uncovered in-scope copy. These results are not a full repository or release-readiness claim.

The reviewed candidate was applied through its CLI to the preserved BDocs case. [Exact application result](application/RESULT.json): revision 4 became 6; the task remains interrupted, original history is unchanged, no identity/result was added, and all 5,067 BDocs source files and the installed plugin remain unchanged. Only the no-send and reconciliation events were appended. Private authorization and historical conversation transcripts are intentionally not part of this public source packet; their hashes/references remain in the local audit trail.

Implementation commit: `9f71d47aba745dde8e2bbfac30b6abe4a4ac8b18`. Draft publication does not install or release this candidate. Normal version-keyed installation still requires a version bump and repository release validation. No shared plugin, security setting, merge or deployment is part of this repair. Tracking: AGE-114.
