import SwiftUI

// MARK: - Library row for a single game

struct GameRowView: View {
    let game: InstalledGame
    let onPlay: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: game.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(game.titleId)
                        .font(.caption.monospaced())
                    Text("·")
                    Text(game.sizeFormatted)
                    Text("·")
                    Text("v\(game.version)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    BadgeView(text: "\(game.fpsTarget) FPS", color: game.fpsTarget == "60" ? .green : .blue)
                    BadgeView(text: game.isDocked ? "Docked 1080p" : "Handheld 720p", color: .purple)
                    if game.upscaling == "metalfx" {
                        BadgeView(text: "MetalFX", color: .orange)
                    }
                    if game.isFullscreen {
                        BadgeView(text: tr("Vollbild", "Full Screen"), color: .teal)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: onSettings) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(tr("Spiel-Einstellungen", "Game Settings"))
            .accessibilityLabel(tr("Spiel-Einstellungen", "Game Settings"))

            Button(tr("Spielen", "Play"), action: onPlay)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
