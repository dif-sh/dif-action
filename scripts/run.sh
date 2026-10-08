#!/usr/bin/env bash
# Run a dif verb in the project directory and turn its diagnostics into
# GitHub annotations. Exits with dif's own exit code.
#
# Inputs (environment):
#   DIF_COMMAND            verb to run, default "build"
#   DIF_ARGS               extra arguments, split on whitespace
#   DIF_WORKING_DIRECTORY  directory that contains the dif/ folder, default "."
#   DIF_ANNOTATIONS        "true" (default) to emit ::error / ::warning lines

set -uo pipefail

COMMAND="${DIF_COMMAND:-build}"
ARGS="${DIF_ARGS:-}"
WORKDIR="${DIF_WORKING_DIRECTORY:-.}"
ANNOTATIONS="${DIF_ANNOTATIONS:-true}"

if ! command -v dif >/dev/null 2>&1; then
  echo "::error title=dif::the dif binary is not on PATH. The install step did not run or failed."
  exit 127
fi

if [ ! -d "$WORKDIR" ]; then
  echo "::error title=dif::working-directory '${WORKDIR}' does not exist"
  exit 1
fi
cd "$WORKDIR" || exit 1

if [ ! -d dif ]; then
  echo "::error title=dif::no dif/ folder in '${WORKDIR}'. Set working-directory to the folder that contains dif/config.yaml, and run actions/checkout first."
  exit 1
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

echo "\$ dif ${COMMAND}${ARGS:+ ${ARGS}}"
# ARGS is split on whitespace on purpose: one input, many flags.
# shellcheck disable=SC2086
dif $COMMAND $ARGS 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"

if [ "$ANNOTATIONS" = "true" ]; then
  # Annotation paths are relative to the repository root, dif's are relative
  # to the working directory.
  prefix=""
  case "$WORKDIR" in
    . | ./ | "") ;;
    *)
      prefix="${WORKDIR#./}"
      prefix="${prefix%/}/"
      ;;
  esac
  # dif validate, and dif build on failure, print:
  #   error E007 dif/experiments/active/x.md:1:1: message
  # dif build on success prints warnings as:
  #   ⚠ W001 src/app.ts: message
  # Colour codes and carriage returns are stripped before matching.
  esc="$(printf '\033')"
  tr -d '\r' <"$log" | sed -E "s/${esc}\\[[0-9;]*m//g" | sed -n -E \
    -e "s#^(error|warning) ([EW][0-9]{3}) ([^:]+):([0-9]+):([0-9]+): (.*)\$#::\\1 file=${prefix}\\3,line=\\4,col=\\5,title=dif \\2::\\6#p" \
    -e "s#^⚠ (W[0-9]{3}) ([^:]+): (.*)\$#::warning file=${prefix}\\2,title=dif \\1::\\3#p"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "exit-code=${status}" >>"$GITHUB_OUTPUT"
fi

exit "$status"
