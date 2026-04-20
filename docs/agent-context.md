<!-- trackie:agent-context -->

## Trackie — shared issue tracker

Trackie is a local, menubar-resident issue tracker shared between the user and
every coding agent on this machine. Items pushed here let the user see work
you've queued up, are working on, or completed — even after your session ends.

The `trackie` CLI is already installed on `PATH` (via
`brew install --cask swairshah/tap/trackie`).

### When to push to Trackie

- **Deferred work**: if you discover a follow-up while solving another task,
  file it instead of silently dropping it on the floor.
- **Non-trivial in-progress work**: when starting a task that will take more
  than a few tool calls, add it so the user can see what you're working on.
- **Questions / decisions pending the user**: add an item so it doesn't get
  buried in the transcript.

Don't push trivia ("ran the tests"). Push things the user genuinely benefits
from seeing later.

### Commands

```bash
# Add an item. --project and --note are optional but helpful.
trackie add "Investigate flaky login test" --project auth --note "see auth_test.py"

# Read what's already tracked before adding — avoid duplicates.
trackie list                 # open items
trackie list --json          # machine-readable for tool parsing

# Append progress notes as you go (appends, doesn't replace).
trackie note 3f8a "found it — race in the token refresh"

# Finish.
trackie done 3f8a            # id prefix (first 8 chars) is enough
trackie scratch 3f8a         # drop without marking complete
trackie rm 3f8a              # move to trash — user can restore it later
                             # (use `trackie purge <id>` to hard-delete)
```

Always tag `--project <name>` when you're inside a project directory, and
`--session-id <id>` with your agent session identifier when available so the
user can trace items back to the conversation that filed them.

Before opening a PR / finishing a coherent unit of work, run
`trackie list --json` and mark the items you actually completed as `done`.

<!-- /trackie:agent-context -->
