import SwiftUI

// MARK: - Game import & batch conversion (modal sheet)

struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ImportView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Schließen", "Close")) {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
        }
        .frame(minWidth: 720, idealWidth: 800, minHeight: 520, idealHeight: 580)
    }
}
