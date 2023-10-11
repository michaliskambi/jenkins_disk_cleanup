# Cleanup of old builds on Jenkins

Scan the jobs of Jenkins, delete old builds:

- Only deletes builds older than `DeleteWhenOlderThanDays = 40`.

- Keep some builds (the last `KeepLastBuilds = 10` builds since any "permalink" build like "last successful" etc. builds) always, regardless of age.

- Does the job only if not `DryRun`. On the command-line, pass `--really-remove` to set `DryRun := false`. First run without it (make dry run) to see what would be deleted, and how much disk space would be freed.

## Usage

Make sure you like defaults at the beginning of the code in `jenkins_disk_cleanup.dpr`. Adjust them as needed, esp. `BaseJenkinsJobsDir`.

Compile with [Castle Game Engine](https://castle-engine.io/).

Copy the binary to your server. You can adjust and use `deploy.sh` to have a ready script to build + copy.

Run on server. First without any arguments, as any user that has at least read access to builds dir.

Then run as a user that can actually delete, and add `--really-remove` argument.

I recommend to run in Emacs shell buffer (have easily scrollable and as-long-as-necessary command history) inside Tmux (kill the terminal freely, go back to it later to check task progress).

## Implementation

Implemented with [Pascal](https://castle-engine.io/why_pascal) using [Castle Game Engine units](https://castle-engine.io/).

