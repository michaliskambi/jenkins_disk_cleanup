#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

castle-engine compile --mode=debug # no need to make optimized build for this

scp jenkins_disk_cleanup michalis@jenkins.castle-engine.io:/home/michalis/bin/jenkins_disk_cleanup

ssh michalis@jenkins.castle-engine.io << EOF
jenkins_disk_cleanup
EOF
