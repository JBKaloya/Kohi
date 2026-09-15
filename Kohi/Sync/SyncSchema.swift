import Foundation

/// PostgREST answers "schema cache" when the app is ahead of the remote
/// migrations. That is a backend gap, not a sync bug: cards can still move.
nonisolated enum SyncSchema {
    /// The relation named in a PGRST204 / PGRST205 message, if this is one.
    static func missingRelation(in error: Error) -> String? {
        missingRelation(in: error.localizedDescription)
    }

    static func missingRelation(in message: String) -> String? {
        if let table = firstCapture(#"table 'public\.([^']+)' in the schema cache"#, in: message) {
            return table
        }
        return firstCapture(#"column of '([^']+)' in the schema cache"#, in: message)
    }

    static func message(missing tables: [String]) -> String {
        let names = tables.joined(separator: ", ")
        return "Backend is missing \(names). Cards can still sync; apply pending migrations."
    }

    private static func firstCapture(_ pattern: String, in message: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: message)
        else { return nil }
        return String(message[capture])
    }
}
