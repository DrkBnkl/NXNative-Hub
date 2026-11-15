import SwiftUI

// MARK: - Save sync between Astris and nxnative (game settings sheet)

struct SaveSyncSection: View {
    @ObservedObject private var sync = SaveSyncManager.shared
    let titleId: String

    private var rows: [SaveSyncRow] { sync.rows[titleId] ?? [] }

    var body: some View {
        Section {
            ForEach(rows) { row in
                SaveSyncRowView(row: row)
            }
            if let message = sync.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        } header: {
            Text(tr("Astris-Abgleich", "Astris Sync"))
        } footer: {
            Text(tr("Vor jedem Abgleich werden beide Seiten nach ~/NXNative/SaveBackups gesichert, die letzten 10 je Seite bleiben.",
                    "Before every sync both sides are backed up to ~/NXNative/SaveBackups; the last 10 of each side are kept."))
        }
        .onAppear { sync.refresh(titleId: titleId) }
    }
}

private struct SaveSyncRowView: View {
    @ObservedObject private var sync = SaveSyncManager.shared
    let row: SaveSyncRow
    @State private var pending: SyncDirection?
    @State private var confirmApproval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if row.pair.kind == .device {
                Text(tr("Geräte-Spielstand", "Device save")).font(.headline)
            }
            sideLine(tr("Astris", "Astris"), row.pair.slot == nil ? nil : row.astris)
            sideLine("nxnative", row.nxnative)
            Label(statusText, systemImage: statusIcon)
                .foregroundStyle(statusColor)
                .font(.callout)
            if let reason = row.blockedReason {
                Label(reason, systemImage: "pause.circle").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(tr("Nach Astris kopieren …", "Copy to Astris…")) { pending = .toAstris }
                    .disabled(!canCopy || row.nxnative.isEmpty)
                Button(tr("Nach nxnative kopieren …", "Copy to nxnative…")) { pending = .toNXNative }
                    .disabled(!canCopy || row.astris.isEmpty)
                Spacer()
                Toggle(tr("Automatisch", "Automatic"), isOn: autoBinding)
                    .disabled(row.pair.slot == nil || !canTurnOnAuto)
                    .help(tr("Erst einschalten, wenn du getestet hast, dass beide Seiten denselben Stand laden.",
                             "Turn on only after testing that both sides load the same save."))
            }
        }
        .padding(.vertical, 2)
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(tr("Kopieren", "Copy")) {
                if let pending { sync.apply(row, direction: pending) }
            }
            Button(tr("Abbrechen", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Der Stand auf der Zielseite wird ersetzt. Beide Seiten werden vorher gesichert.",
                    "The save on the target side is replaced. Both sides are backed up first."))
        }
        .confirmationDialog(tr("Automatisch abgleichen?", "Sync automatically?"), isPresented: $confirmApproval) {
            Button(tr("Getestet, einschalten", "Tested, turn on")) { sync.approve(row) }
            Button(tr("Abbrechen", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Hast du das Spiel in Astris und in nxnative gestartet und denselben Spielstand gesehen? Die Freigabe gilt für die aktuelle Astris- und Spielversion.",
                    "Did you start the game in Astris and in nxnative and see the same save? The approval applies to the current Astris and game versions."))
        }
    }

    private var dialogTitle: String {
        pending == .toAstris
            ? tr("Stand von nxnative nach Astris kopieren?", "Copy nxnative's save to Astris?")
            : tr("Stand von Astris nach nxnative kopieren?", "Copy Astris's save to nxnative?")
    }

    private var canCopy: Bool { row.pair.slot != nil && row.blockedReason == nil && !sync.isBusy }
    private var canTurnOnAuto: Bool { row.state.autoEnabled || (row.decision == .inSync && row.blockedReason == nil && !sync.isBusy) }

    private var autoBinding: Binding<Bool> {
        Binding {
            row.state.autoEnabled && !row.needsNewApproval
        } set: { turnOn in
            if turnOn { confirmApproval = true } else { sync.disableAuto(row) }
        }
    }

    private func sideLine(_ name: String, _ snapshot: SaveSnapshot?) -> some View {
        LabeledContent(name) {
            if let snapshot, !snapshot.isEmpty {
                Text(verbatim: "\(tr("\(snapshot.files) Datei(en)", "\(snapshot.files) file(s)")) · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.bytes), countStyle: .file)) · \(snapshot.newest?.formatted(date: .abbreviated, time: .shortened) ?? "–")")
                    .monospacedDigit()
            } else {
                Text(tr("Kein Spielstand", "No save")).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        if row.pair.slot == nil {
            return tr("Starte das Spiel einmal in Astris und beende es. Die App legt dort keinen Spielstand selbst an.",
                      "Start the game once in Astris and quit it. The app does not create a save there itself.")
        }
        if row.needsNewApproval {
            return tr("Astris oder das Spiel wurde aktualisiert. Bitte neu testen und freigeben.", "Astris or the game was updated. Please test and approve again.")
        }
        switch row.decision {
        case .inSync: return tr("Beide Seiten sind gleich.", "Both sides are the same.")
        case .noSaves: return tr("Noch kein Spielstand.", "No save yet.")
        case .setupNeeded: return tr("Die Stände unterscheiden sich. Wähle, welcher gilt.", "The saves differ. Choose which one counts.")
        case .copy(let direction):
            return direction == .toAstris
                ? tr("nxnative ist neuer.", "nxnative is newer.")
                : tr("Astris ist neuer.", "Astris is newer.")
        case .conflict(let reason): return reason
        }
    }

    private var statusIcon: String {
        switch row.decision {
        case .inSync: return "checkmark.circle"
        case .conflict: return "exclamationmark.triangle"
        default: return "arrow.left.arrow.right.circle"
        }
    }

    private var statusColor: Color {
        switch row.decision {
        case .inSync: return .green
        case .conflict: return .orange
        default: return .secondary
        }
    }
}
