import SwiftUI

// MARK: - Large Cover Card for the Grid View in "My Games"

struct GameCoverCardView: View {
    let game: InstalledGame
    let isSelected: Bool
    let coverWidth: CGFloat
    let onPlay: () -> Void
    let onSettings: () -> Void
    let onShowStatus: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Cover Image Box
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottom) {
                    Image(nsImage: game.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: coverWidth, height: coverWidth)
                        .clipped()
                        .background(Color.black.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                              lineWidth: isSelected ? 3 : 1)
                        )
                        .shadow(color: Color.black.opacity(isHovered ? 0.32 : 0.12),
                                radius: isHovered ? 10 : 4,
                                y: isHovered ? 6 : 2)

                    // Hover Action Overlay
                    if isHovered {
                        HStack(spacing: 14) {
                            Button(action: onPlay) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 6)
                            }
                            .buttonStyle(.plain)
                            .help(tr("Spielen", "Play"))

                            Button(action: onSettings) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(Circle().fill(Color.black.opacity(0.65)))
                            }
                            .buttonStyle(.plain)
                            .help(tr("Spiel-Einstellungen", "Game Settings"))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity)
                    }
                }

                // Top Badges
                HStack {
                    if SwitchTitleID.isSwitch2(game.titleId) {
                        BadgeView(text: "Switch 2", color: .red)
                            .padding(8)
                    }
                    Spacer()
                    if let badge = game.updateStatus.badge {
                        Button(action: onShowStatus) {
                            BadgeView(text: badge.text, systemImage: badge.icon, color: badge.color)
                        }
                        .buttonStyle(.plain)
                        .help(game.updateStatus.tooltip)
                        .padding(8)
                    }
                }
            }
            .frame(width: coverWidth, height: coverWidth)

            // Title and Metadata
            VStack(spacing: 3) {
                Text(game.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: coverWidth)

                Text("v\(game.version) · \(game.sizeFormatted)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Quick tags
                HStack(spacing: 4) {
                    if !game.fpsTarget.isEmpty {
                        Text("\(game.fpsTarget) FPS")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    Text(game.isDocked ? "Docked" : "Handheld")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.12))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                    if game.upscaling == "metalfx" {
                        Text("MetalFX")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(width: coverWidth)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
