#!/bin/bash
# The checks CI's unit job runs, on this machine: build with tests, then the unit tests.
#
#   Scripts/ci-local.sh            run the checks
#   Scripts/ci-local.sh --install  run them automatically before every `git push`
#
# Same as CI's build, strict-concurrency and test jobs, minus the strict-concurrency build.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--install" ]; then
  hook="$(git rev-parse --git-path hooks/pre-push)"
  printf '#!/bin/bash\nexec "$(git rev-parse --show-toplevel)/Scripts/ci-local.sh"\n' > "$hook"
  chmod +x "$hook"
  echo "Installed $hook"
  exit 0
fi

swift build --build-tests
swift test
