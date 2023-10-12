# Cleanup of old builds on Jenkins

Scan the jobs of Jenkins, delete old builds:

- Only deletes builds older than `DeleteWhenOlderThanDays = 40`.

- Keep some builds (the last `KeepLastBuilds = 10` builds since any "permalink" build like "last successful" etc. builds) always, regardless of age.

- Does the job only if not `DryRun`. On the command-line, pass `--really-remove` to set `DryRun := false`. First run without it (make dry run) to see what would be deleted, and how much disk space would be freed.

## How and why

This program does the removals in "direct" way, i.e. just accesses the filesystem, not using any official Jenkins API.

So it is light-weight and will work reliably regardless of what Jenkins is doing and how much is Jenkins responsive over www. And still you can run this process *while Jenkins is running in parallel* because this script will only change (remove) really old directories (older than `DeleteWhenOlderThanDays = 40`). So the Jenkins process should not be doing anything in these dirs.

## Usage

- Make sure you like defaults at the beginning of the code in `jenkins_disk_cleanup.dpr`. Adjust them as needed, esp. `BaseJenkinsJobsDir`.

- Compile with [Castle Game Engine](https://castle-engine.io/). Use build tool (command-line) or editor.

- Copy the binary to your server. You can adjust and use `deploy.sh` to have a ready script to build + copy.

- Run on the server. Do a first run without any arguments. Do it as any user that has at least read access to builds dir (so, likely you don't need `sudo`).

- Then run as a user that can actually delete, and add `--really-remove` argument. So, likely with `sudo`.

    I recommend to run in Emacs shell buffer (have easily scrollable and as-long-as-necessary command history) inside Tmux (kill the terminal freely, go back to it later to check task progress).

- Once you're confident it works nicely, add executing it to cron. E.g. to `/etc/cron.weekly/cag-jenkins-cleanup` .

## Implementation

Implemented with [Pascal](https://castle-engine.io/why_pascal) using [Castle Game Engine units](https://castle-engine.io/).
