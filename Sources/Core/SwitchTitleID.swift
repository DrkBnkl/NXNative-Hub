import Foundation

// MARK: - Nintendo Switch title IDs
//
// Layout (64-bit, hex):
//   Base game = base ID (lower 13 bits are 0)
//   Update    = base ID + 0x800
//   DLC       = base ID + 0x1000 + index
//
// Masking only the lower 12 bits (`& ~0xFFF`) works for updates but maps DLC IDs
// to a wrong base ID, hence `& ~0x1FFF`.

enum SwitchTitleID {
    /// Returns the ID upper-cased if it consists of 16 hex characters.
    static func normalized(_ raw: String) -> String? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count == 16, UInt64(clean, radix: 16) != nil else { return nil }
        return clean
    }

    /// Base ID of the game for base, update and DLC IDs.
    static func baseID(of titleId: String) -> String? {
        guard let value = UInt64(titleId, radix: 16) else { return nil }
        return format(value & ~UInt64(0x1FFF))
    }

    /// Legacy calculation (lower 12 bits only), used as fallback for existing profiles.
    static func legacyBaseID(of titleId: String) -> String? {
        guard let value = UInt64(titleId, radix: 16) else { return nil }
        return format(value & ~UInt64(0xFFF))
    }

    static func format(_ value: UInt64) -> String {
        String(format: "%016llX", value)
    }
}
