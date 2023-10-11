#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

castle-engine compile --mode=debug # no need to make optimized build for this

# Trying to do scp when it is running ends with
#   dest open "/home/michalis/bin/jenkins_disk_cleanup": Failure
#   scp: failed to upload file jenkins_disk_cleanup to /home/michalis/bin/jenkins_disk_cleanup
ssh michalis@jenkins.castle-engine.io << EOF
killall jenkins_disk_cleanup || true
EOF

scp jenkins_disk_cleanup michalis@jenkins.castle-engine.io:/home/michalis/bin/jenkins_disk_cleanup

# ssh michalis@jenkins.castle-engine.io << EOF
# jenkins_disk_cleanup
# EOF
