<!-- trackie:agent-context -->

## Trackie — shared issue tracker

Trackie is a local, menubar-resident issue tracker shared between the user and
every coding agent on this machine. Use it as a durable backlog for substantial
work that may span long sessions, multiple days, or handoffs between agents.

The `trackie` CLI is already installed on `PATH` (via
`brew install --cask swairshah/tap/trackie`).

### How to use Trackie

- Prefer reading first: run `trackie list --json` when starting substantial
  work so you know what is already tracked and avoid creating duplicates.
- Add items only for large, durable work: multi-session projects, investigations
  that may continue later, risky migrations, or decisions blocked on the user.
- Don't add routine tasks, small fixes, quick follow-ups, ordinary test runs,
  or anything you expect to finish in the current session.

Trackie is not a progress log. If you add an item, keep notes concise and mark
it `done` only when the tracked work is actually complete.

### Commands

```bash
trackie add "Investigate flaky login test" --project auth --note "see auth_test.py"
trackie list --json          # read existing items before adding new ones
trackie note 3f8a "root cause is likely token refresh timing"
trackie done 3f8a            # mark complete by id prefix
trackie scratch 3f8a         # drop without marking complete
```

Always tag `--project <name>` when you're inside a project directory, and
`--session-id <id>` with your agent session identifier when available.

Before finishing, update only the Trackie items you materially worked on.

<!-- /trackie:agent-context -->
