import OPDBKit

// Deutsche Bezeichnungen für die OPDB-Codes.

extension MachineType {
    var label: String {
        switch self {
        case .electroMechanical: return "Elektromechanisch"
        case .solidState: return "Solid State"
        case .pureMechanical: return "Mechanisch"
        default: return rawValue.uppercased()
        }
    }
}

extension DisplayType {
    var label: String {
        switch self {
        case .lights: return "Leuchten"
        case .reels: return "Zählwalzen"
        case .alphanumeric: return "Alphanumerisch"
        case .dmd: return "Dot-Matrix (DMD)"
        case .cga: return "CGA-Monitor"
        case .lcd: return "LCD"
        default: return rawValue
        }
    }
}

extension EntryType {
    var label: String {
        switch self {
        case .machineGroup: return "Gruppe"
        case .machine: return "Gerät"
        case .alias: return "Alias"
        default: return rawValue
        }
    }
}
