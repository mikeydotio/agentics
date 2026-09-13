# Codex automatic resumption

Every orchestrated step writes its handoff, then calls
`bash "<plugin-root>/bin/forge-step-exit.sh" --host codex` with the step, summary
and next command. End the turn afterward. Preserve transition_id correlation.
The helper commits artifacts, persists a paused resume pointer and queues Freshen.
A successful queue is not proof of a reset or accepted continuation.

Freshen owns the Codex reset journal, nonce bootstrap, SessionStart acknowledgement
and consumption at continuation Stop. Forge emergency Stop first checkpoints state
and releases its lock, then queues its source and calls Freshen's Codex Stop adapter.
Either plugin hook may run first; Freshen's claim/journal prevents duplicate workers.
An in-flight signal must never be overwritten by a same-source next-cycle signal.

No tmux, disabled Freshen, missing dependency, or cross-source conflict leaves a
paused Forge session and visible diagnostics. Follow the returned manual continuation
message. Do not manipulate terminal keys or journal files to pretend recovery worked.
Graceful stop cancels only Forge's queued and in-flight signal through Freshen's
Codex CLI. Terminal step exit also cancels that source.

SessionStart reports the durable resume summary and handoff path, never handoff body.
Legacy Forge commands are translated only when recognized at this host boundary.
Transition audit entries retain the existing .freshen/transitions.log format.
Heartbeat and crash-recovery limits remain defined by session-locking.md and
recovery-protocol.md. Preserve verifier-owned work during recovery.
