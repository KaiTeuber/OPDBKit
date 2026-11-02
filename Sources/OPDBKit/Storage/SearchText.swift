import Foundation

/// Normalisierung für die Suche: klein geschrieben, ohne Diakritika, Wörter durch Leerzeichen getrennt.
/// „Pokémon“ → „pokemon“, „AC/DC“ → „ac dc“.
enum SearchText {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    static func fold(_ text: String) -> String {
        tokens(text).joined(separator: " ")
    }

    /// Suchindex eines Eintrags. Beginnt und endet mit einem Leerzeichen, damit Wortanfänge
    /// per `contains(" " + begriff)` gefunden werden können.
    static func index(for machine: Machine) -> String {
        var parts: [String?] = [
            machine.name,
            machine.shortName,
            machine.commonName,
            machine.manufacturer?.name,
            machine.manufacturer?.fullName,
            machine.opdbId,
            machine.ipdbId.map { String($0) },
            machine.year.map { String($0) }
        ]
        parts += machine.people.map(\.name)
        parts += machine.features.map(\.name)
        parts += machine.keywords
        let text = parts.compactMap { $0 }.joined(separator: " ")
        return " " + fold(text) + " "
    }
}
