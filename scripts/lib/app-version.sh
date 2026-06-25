#!/usr/bin/env bash
#
# Single owner of "read the app version from its source of truth".
#
# OuroMDRelease.swift is the source of truth (make-app.sh derives from it, the
# README mirrors it). Several scripts need just that raw version WITHOUT the full
# release-coherence check — e.g. make-app.sh must build even while a release bump
# is mid-flight and the README hasn't caught up — so they source this and call
# `ouro_md_source_version` instead of each re-implementing the extraction.
#
# Source it, don't execute it:  source "<repo>/scripts/lib/app-version.sh"

# Prints the version string from OuroMDRelease.swift. Optional $1 = repo root
# (defaults to the current directory).
ouro_md_source_version() {
    sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' \
        "${1:-.}/Sources/OuroMDCore/OuroMDRelease.swift" | head -1
}
