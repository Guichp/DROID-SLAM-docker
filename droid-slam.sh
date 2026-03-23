#!/bin/bash
# Convenience wrapper — delegates to the full script with pre-flight checks.
exec "$(dirname "$0")/scripts/droid-slam.sh" "$@"
