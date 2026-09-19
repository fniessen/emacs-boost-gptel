# Rules

- Don't be too verbose.
- Never use bold (**text**) or italic (*text*) emphasis in responses.
- Avoid using em-dash, prefer simpler hyphens instead.
- Don't excessively create "reports", focus on solutions, not reporting
- Avoid any VC/git modification operations unless specifically asked
- Do not modify or push pull-requests unless explicitly commanded
- When modifying Emacs hooks, advice, or other global state in config files,
  also update the live Emacs session to match (e.g., remove old hooks/advice
  before adding new ones) so the running instance stays consistent

# CLI tools

- To explore jira tickets (typically look like 'SAC-12345') - you can use jira
  CLI - (e.g., 'jira view SAC-12345'), fetch comments, subtasks and linked
  items. Request more info whenever it makes sense.

- prefer `rg` and `fd` instead of `grep` and `find`

# Code

- All code should be properly linted. After done with all the edits in every
  relevant file, apply linting tool(s) for changesets:

  - SQL: sqlfluff
  - Python: ruff
  - Elisp: check-paren; package-lint (for packages)

- Avoid using `>` in Lisps for comparison, always preferring `<`, unless it
  makes the code unreasonably difficult to understand.

- Always provide pointers when speaking about code. They must be in the easily
  browsable, respective forge format, i.e.,

  - https://github.com/ORG/REPO/blob/BRANCH/FILE.EXT#L1-L10
  - https://gitlab.com/ORG/REPO/-/blob/BRANCH/FILE.EXT?ref_type=heads#L1-L10
  - https://codeberg.org/ORG/REPO/src/branch/BRANCH/FILE.EXT#L1-L10
  - https://git.sr.ht/~ORG/REPO/tree/BRANCH/item/FILE.EXT#L1-L10

- When the forge is unknown or it's about files on local drive - use absolute
  file paths in the format of:

  /path/to/file.ext:L1-L10
