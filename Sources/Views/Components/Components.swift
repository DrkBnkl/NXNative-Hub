import SwiftUI

// MARK: - Log console
//
// Shared by the builder, external build, import and live log views.
// Uses system colors so light/dark mode and Increase Contrast work (HIG).

struct LogConsoleView: View {
    let lines: [String]
    var minHeight: CGFloat = 160
    var placeholder: String = tr("Noch keine Ausgabe.", "No output yet.")

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if lines.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .foregroundStyle(Self.color(for: line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
            }
            .frame(minHeight: minHeight)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            .onChange(of: lines.count) {
                if let last = lines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = lines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .accessibilityLabel(tr("Protokoll", "Log"))
        }
    }

    static func color(for line: String) -> Color {
        if line.hasPrefix("[Error]") || line.hasPrefix("✗") || line.contains("❌") {
            return .red
        } else if line.hasPrefix("✓") || line.contains("✅") {
            return .green
        } else if line.hasPrefix("▶") {
            return .accentColor
        } else if line.hasPrefix("  ↳") || line.hasPrefix("⚠︎") {
            return .orange
        }
        return .primary
    }
}

// MARK: - Small status badge (FPS, Docked, MetalFX …)

struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Hint for phase 7/8 (metal-tt runs for minutes without output)

struct PipelinePhaseHint: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Schritt 7 von 8: GPU-Pipeline-Archiv wird erstellt", "Step 7 of 8: Creating GPU pipeline archive"))
                    .font(.callout.weight(.semibold))
                Text(tr("Apples Metal-Compiler verknüpft alle Shader. Das dauert einige Minuten ohne Ausgabe – die App hängt nicht.",
                        "Apple's Metal compiler links all shaders. This takes a few minutes without output – the app is not frozen."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            ProgressView().controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Banner for running builds (above the content)

struct ActiveBuildBanner: View {
    let build: ActiveBuildInfo
    let stageOverride: String?
    let onShowLog: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(tr("Build läuft", "Build running")): \(build.gameName)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(stageOverride ?? build.currentStageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button(tr("Live-Protokoll", "Live Log"), action: onShowLog)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}
