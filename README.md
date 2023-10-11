# Cleanup of old builds on Jenkins

Scan the jobs of Jenkins, delete old builds:

- Only deletes builds older than `DeleteWhenOlderThanDays = 40`.

- Keep some builds (the last `KeepLastBuilds = 10` builds since any "permalink" build like "last successful" etc. builds) always, regardless of age.

- Does the job only if not `DryRun`. On the command-line, pass `--really-remove` to set `DryRun := false`. First run without it (make dry run) to see what would be deleted, and how much disk space would be freed.

Implemented with [Pascal](https://castle-engine.io/why_pascal) using [Castle Game Engine units](https://castle-engine.io/).
