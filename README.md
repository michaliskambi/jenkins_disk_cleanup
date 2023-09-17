# Cleanup of old builds on Jenkins

Scan the jobs of Jenkins, delete old builds:

- Only deletes builds older than `DeleteWhenOlderThanDays = 40`.

- Keep some builds (the last `KeepLastBuilds = 10` builds, and the "last successful" etc. builds) always, regardless of age.

- Does the job only if not `DryRun`. You can run first with `DryRun = true` to see what would be deleted, and how much disk space would be freed.

 Implemented with [Pascal](https://castle-engine.io/why_pascal) using [Castle Game Engine units](https://castle-engine.io/).
