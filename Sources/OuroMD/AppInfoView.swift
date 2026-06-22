import AppKit
import OuroMDCore
import SwiftUI

struct OuroMDAboutView: View {
    @ObservedObject var updateCoordinator: OuroMDUpdateCoordinator
    var onDismiss: () -> Void = {}
    @State private var copiedVersion = false

    private var buildLine: String {
        if let gitSHA = OuroCLI.gitSHA {
            return "Build \(gitSHA)"
        }
        if let bundleBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !bundleBuild.isEmpty,
           bundleBuild != OuroMDRelease.version {
            return "Build \(bundleBuild)"
        }
        return "Source build"
    }

    private var versionLine: String {
        "Version \(OuroMDRelease.version) - \(buildLine)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(OuroMDRelease.appName)
                        .font(.title2.weight(.semibold))
                    Text(versionLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Text("Independent Markdown editor for fast local writing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ReleaseUpdateControls(updateCoordinator: updateCoordinator, showTitle: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("What's New in \(OuroMDRelease.version)", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("Released \(OuroMDRelease.releaseDate)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(OuroMDRelease.releaseHighlights, id: \.self) { highlight in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("-")
                                .foregroundStyle(.secondary)
                            Text(highlight)
                        }
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                if let notes = updateCoordinator.releaseNotesPreview {
                    Divider()
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(OuroMDRelease.repository)")!)
                } label: {
                    Label("Open Repo", systemImage: "arrow.up.right.square")
                }
                Button {
                    copyVersion()
                } label: {
                    Label(copiedVersion ? "Copied" : "Copy Version", systemImage: copiedVersion ? "checkmark" : "doc.on.doc")
                }
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About Ouro MD")
    }

    private func copyVersion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(versionLine, forType: .string)
        copiedVersion = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedVersion = false
        }
    }
}

struct ReleaseUpdateControls: View {
    @ObservedObject var updateCoordinator: OuroMDUpdateCoordinator
    var showTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle {
                HStack(spacing: 8) {
                    Label("Software Updates", systemImage: "arrow.down.app")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    statusPill
                }
            } else {
                statusPill
            }

            Text(updateCoordinator.releaseUpdateStatusLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Update status")

            HStack(spacing: 8) {
                if let latest = updateCoordinator.latestKnownVersion {
                    metadata("Latest", latest)
                }
                if let published = updateCoordinator.releasePublishedAtText {
                    metadata("Published", published)
                }
                metadata("Channel", "Direct download")
            }

            if let snapshot = updateCoordinator.releaseSnapshot, snapshot.status == .updateAvailable {
                Text(snapshot.hasInstallableAssets ? "Before installing, Ouro MD verifies the release manifest, SHA-256 checksum, byte count, bundle identity, and newer version." : "A newer release exists, but the app archive or manifest is missing.")
                    .font(.system(size: 11))
                    .foregroundColor(snapshot.hasInstallableAssets ? .secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await updateCoordinator.checkForUpdatesAndPromptInstall() }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(updateCoordinator.isChecking)
                .accessibilityLabel("Check for updates")

                if updateCoordinator.updateBadgeText != nil {
                    Button {
                        updateCoordinator.presentUpdatePrompt()
                    } label: {
                        Label("Review Update", systemImage: "arrow.down.circle")
                    }
                    .controlSize(.small)
                    .disabled(updateCoordinator.isInstalling)
                    .accessibilityLabel("Review update")
                }

                if let url = updateCoordinator.releasePageURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open Release", systemImage: "safari")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Open release")
                }
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("Update state")
        .accessibilityValue(statusText)
    }

    private func metadata(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 11))
    }

    private var statusText: String {
        if updateCoordinator.isChecking { return "Checking" }
        if updateCoordinator.stagedUpdateVersion != nil { return "Ready" }
        if let status = updateCoordinator.releaseUpdateStatusKind {
            switch status {
            case .current: return "Current"
            case .updateAvailable: return "Available"
            case .unavailable: return "Unavailable"
            }
        }
        if updateCoordinator.recentlyInstalledVersion != nil { return "Installed" }
        return "Not Checked"
    }

    private var statusColor: Color {
        if updateCoordinator.isChecking { return .secondary }
        if updateCoordinator.stagedUpdateVersion != nil { return .orange }
        switch updateCoordinator.releaseUpdateStatusKind {
        case .current: return .green
        case .updateAvailable: return .orange
        case .unavailable: return .secondary
        case nil:
            if updateCoordinator.recentlyInstalledVersion != nil { return .green }
            return .secondary
        }
    }
}

struct UpdateInstalledConfirmationView: View {
    let version: String
    let onOpenAbout: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 26))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ouro MD \(version) is installed")
                        .font(.system(size: 14, weight: .semibold))
                    Text("The latest version is now running on this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("What's New") { onOpenAbout() }
                Button("OK") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ouro MD \(version) is installed")
    }
}
