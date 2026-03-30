# Auto-Resume

Crontab (primary) and systemd timer (secondary) setup for fire-and-forget autonomous execution.

## Crontab (Primary — Portable)

Crontab is the default auto-resume mechanism. It works in containers, bare metal, and VMs.

### Setup

When `/pilot run` starts, add a crontab entry:

```bash
# Parse interval (e.g., "15m" → "*/15 * * * *")
CRON_SCHEDULE="*/15 * * * *"  # default for 15m interval
PROJECT_PATH="$(pwd)"
CLAUDE_BIN="$(which claude)"

# Add crontab entry with unique comment marker
(crontab -l 2>/dev/null | grep -v '# pilot-resume'; \
 echo "$CRON_SCHEDULE PATH=$PATH $CLAUDE_BIN -p \"/pilot resume\" --project $PROJECT_PATH # pilot-resume") | crontab -
```

### Interval Parsing

| User Input | Cron Schedule |
|-----------|---------------|
| `5m` | `*/5 * * * *` |
| `10m` | `*/10 * * * *` |
| `15m` (default) | `*/15 * * * *` |
| `30m` | `*/30 * * * *` |
| `1h` | `0 * * * *` |

### Teardown

Remove the crontab entry on `/pilot stop` or completion:

```bash
crontab -l 2>/dev/null | grep -v '# pilot-resume' | crontab -
```

### Validation

Before enabling auto-resume, validate the environment:

1. Run `claude -p "/pilot resume" --project <path>` from a non-interactive shell
2. Check that:
   - `claude` binary is in PATH
   - API authentication token is available
   - Project path resolves correctly
3. If validation fails → log requirements and abort with clear message

## Systemd Timer (Secondary)

For systems with user-level systemd (not typical in containers).

### Setup

Create two unit files in `~/.config/systemd/user/`:

**pilot-resume.service**:
```ini
[Unit]
Description=Work auto-resume

[Service]
Type=oneshot
ExecStart=/usr/local/bin/claude -p "/pilot resume" --project %h/project-path
Environment=PATH=/usr/local/bin:/usr/bin
```

**pilot-resume.timer**:
```ini
[Unit]
Description=Work auto-resume timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
```

### Enable/Disable
```bash
systemctl --user enable --now pilot-resume.timer
systemctl --user disable --now pilot-resume.timer
```

## Container Considerations

- Container environments (like agentsmith) typically lack user-level systemd
- Crontab is the default for this reason
- Ensure PATH includes the directory containing the `claude` binary
- Auth tokens must be available in the cron environment (not just the interactive shell)
- Working directory must be the project root

## Trigger Behavior

1. Timer fires at configured interval
2. `claude` starts a new session
3. SessionStart hook detects pilot state → injects context
4. `/pilot resume` checks lock:
   - Heartbeat fresh → exit (pilot is running)
   - State is `paused` → acquire lock, continue loop
   - State is `complete` → remove trigger, exit
5. When all stories done → pilot removes its own trigger

## Safety

- Trigger removed on `/pilot stop` (graceful) and on completion
- If pilot crashes without cleanup → next trigger sees `paused` + stale lock → resumes
- Runaway safeguards (`max_sessions`, `max_total_retries`) prevent unbounded execution even if trigger keeps firing
