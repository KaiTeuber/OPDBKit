import Foundation

/// Dekodiert einen Wert und liefert `nil`, statt einen Fehler zu werfen.
/// Wird für Listen genutzt, damit ein fehlerhafter Eintrag nicht den ganzen Import scheitern lässt.
struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Keywords sind in den bisherigen Daten leer; akzeptiert werden Strings
/// oder Objekte mit `name` / `keyword` / `title`.
struct KeywordValue: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            value = string
            return
        }
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        value = ["name", "keyword", "title"]
            .lazy
            .compactMap { try? c.decode(String.self, forKey: AnyCodingKey($0)) }
            .first
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer {
    func lossy<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }

    func lossyString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    func lossyInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func lossyBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return ["true", "1", "yes"].contains(value.lowercased())
        }
        return nil
    }

    func lossyArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        guard let items = try? decodeIfPresent([Lossy<T>].self, forKey: key) else { return [] }
        return items.compactMap(\.value)
    }
}

extension Optional where Wrapped == String {
    /// `nil` für leere oder nur aus Leerzeichen bestehende Strings.
    var nonEmpty: String? {
        guard let self else { return nil }
        return self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

enum OPDBDate {
    /// Parst Zeitstempel wie `2024-06-25T02:07:10.000000Z` (auch mit Mikrosekunden).
    static func timestamp(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // Fallback: Nachkommastellen entfernen (ältere OS-Versionen kennen nur 3 Stellen).
        let stripped = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: stripped)
    }

    /// Parst Datumswerte im Format `yyyy-MM-dd` (UTC).
    static func day(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
