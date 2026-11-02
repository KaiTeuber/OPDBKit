import Foundation

// Lokalisierte Bezeichnungen für die OPDB-Codes (Englisch und Deutsch).
// Die Texte stehen in `Resources/Localizable.xcstrings`; Ausgangssprache ist Englisch.
// Unbekannte Codes werden unverändert als `rawValue` zurückgegeben.

public extension MachineType {
    /// Lesbare Bezeichnung der Bauart in der Sprache der App, z. B. „Elektromechanisch“.
    var localizedName: String {
        switch self {
        case .electroMechanical: return String(localized: "Electro-mechanical", bundle: .module)
        case .solidState: return String(localized: "Solid state", bundle: .module)
        case .pureMechanical: return String(localized: "Mechanical", bundle: .module)
        default: return rawValue.uppercased()
        }
    }
}

public extension DisplayType {
    /// Lesbare Bezeichnung der Anzeige in der Sprache der App, z. B. „Zählwalzen“.
    var localizedName: String {
        switch self {
        case .lights: return String(localized: "Lights", bundle: .module)
        case .reels: return String(localized: "Reels", bundle: .module)
        case .alphanumeric: return String(localized: "Alphanumeric", bundle: .module)
        case .dmd: return String(localized: "Dot matrix (DMD)", bundle: .module)
        case .cga: return String(localized: "CGA monitor", bundle: .module)
        case .lcd: return String(localized: "LCD", bundle: .module)
        default: return rawValue
        }
    }
}

public extension EntryType {
    /// Lesbare Bezeichnung der Eintragsart in der Sprache der App, z. B. „Gerät“.
    var localizedName: String {
        switch self {
        case .machineGroup: return String(localized: "Group", bundle: .module)
        case .machine: return String(localized: "Machine", bundle: .module)
        case .alias: return String(localized: "Alias", bundle: .module)
        default: return rawValue
        }
    }
}
