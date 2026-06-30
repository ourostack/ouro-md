## Unit 0 Research

Branch: worker/ouro-md-harness-vendor-editor-extraction
HEAD: 766c4a40a331b130303912e0a30fb79c4c4d9a00

## main.swift flags
--accessibilityaudit
--alerttest
--bundleprobe
--codewrap-height
--codewrap-width
--codewraptest
--copyflavortest
--darkdiagramtest
--editorsurfacetest
--firstlaunchtest
--height
--help
--linktest
--list-themes
--live-update-destination
--live-update-from-version
--live-update-to-version
--liveupdatetest
--markdownparitytest
--mermaidcliptest
--out
--performanceprobe
--reloadrendertest
--render
--renderprobe
--roundtrip
--searchrevealtest
--selectionblurtest
--shoot
--tablewrap-file
--tablewrap-height
--tablewrap-width
--tablewraptest
--theme
--uisurfacetest
--undotest
--version
--visualqa-file
--visualqa-height
--visualqa-width
--visualqatest
--width
--wrapgluetest
--wraptest

## native scenarios flags
scripts/run-native-scenarios.sh:--accessibilityaudit
scripts/run-native-scenarios.sh:--codewraptest
scripts/run-native-scenarios.sh:--copyflavortest
scripts/run-native-scenarios.sh:--darkdiagramtest
scripts/run-native-scenarios.sh:--editorsurfacetest
scripts/run-native-scenarios.sh:--firstlaunchtest
scripts/run-native-scenarios.sh:--linktest
scripts/run-native-scenarios.sh:--markdownparitytest
scripts/run-native-scenarios.sh:--mermaidcliptest
scripts/run-native-scenarios.sh:--out
scripts/run-native-scenarios.sh:--performanceprobe
scripts/run-native-scenarios.sh:--reloadrendertest
scripts/run-native-scenarios.sh:--renderprobe
scripts/run-native-scenarios.sh:--roundtrip
scripts/run-native-scenarios.sh:--searchrevealtest
scripts/run-native-scenarios.sh:--selectionblurtest
scripts/run-native-scenarios.sh:--tablewrap-file
scripts/run-native-scenarios.sh:--tablewrap-height
scripts/run-native-scenarios.sh:--tablewrap-width
scripts/run-native-scenarios.sh:--tablewraptest
scripts/run-native-scenarios.sh:--uisurfacetest
scripts/run-native-scenarios.sh:--undotest
scripts/run-native-scenarios.sh:--wrapgluetest
scripts/run-native-scenarios.sh:--wraptest
scripts/run-visual-qa.sh:--height
scripts/run-visual-qa.sh:--out
scripts/run-visual-qa.sh:--shoot
scripts/run-visual-qa.sh:--theme
scripts/run-visual-qa.sh:--visualqa-file
scripts/run-visual-qa.sh:--visualqa-height
scripts/run-visual-qa.sh:--visualqa-width
scripts/run-visual-qa.sh:--visualqatest
scripts/run-visual-qa.sh:--width
scripts/verify-packaged-app.sh:--alerttest
scripts/verify-packaged-app.sh:--bundleprobe
scripts/verify-packaged-app.sh:--deep
scripts/verify-packaged-app.sh:--out
scripts/verify-packaged-app.sh:--roundtrip
scripts/verify-packaged-app.sh:--strict
scripts/verify-packaged-app.sh:--undotest
scripts/verify-packaged-app.sh:--verbose
scripts/verify-packaged-app.sh:--verify
scripts/verify-packaged-app.sh:--version

## vditor inventory
     529
 23M	Sources/OuroMD/web/vditor
6e8333cb5b48e06ecadc339132b04c30ff4b17c8b22563769076b937a2c020e8  -

## release policy hooks
scripts/pr-preflight.sh:20:./scripts/release-policy.sh selftest-package-guards
scripts/pr-preflight.sh:23:./scripts/release-policy.sh selftest-paths
scripts/pr-preflight.sh:29:OURO_MD_EXE="${OURO_MD_EXE:-.build/debug/ouro-md}" ./scripts/run-native-scenarios.sh
scripts/release-policy.sh:28:  scripts/release-policy.sh selftest-package-guards
scripts/release-policy.sh:102:release_relevant_path() {
scripts/release-policy.sh:112:    scripts/run-native-scenarios.sh|scripts/run-visual-qa.sh|scripts/swift-test-budget.sh) return 1 ;;
scripts/release-policy.sh:119:    scripts/check-hosted-installer.sh|scripts/check-live-update-path.sh|scripts/check-shell-dependency.sh|scripts/check-signing-readiness.sh|scripts/package-release.sh|scripts/pr-preflight.sh) return 0 ;;
scripts/release-policy.sh:131:    if release_relevant_path "$path"; then
scripts/release-policy.sh:644:# Locks the release_relevant_path classifier so the "test-only changes don't gate
scripts/release-policy.sh:669:    scripts/run-native-scenarios.sh
scripts/release-policy.sh:676:    release_relevant_path "$p" || fail "paths selftest: '$p' should gate a release but doesn't"
scripts/release-policy.sh:679:    ! release_relevant_path "$p" || fail "paths selftest: '$p' should NOT gate a release but does"
scripts/release-policy.sh:723:preflight = Path("scripts/pr-preflight.sh").read_text(encoding="utf-8")
scripts/release-policy.sh:733:        "pr-preflight.sh",
scripts/release-policy.sh:1065:  selftest-package-guards) selftest_package_guards_mode "$@" ;;
scripts/release-policy.sh:1068:  selftest-paths) selftest_paths_mode "$@" ;;
