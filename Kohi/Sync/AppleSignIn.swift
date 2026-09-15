import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

nonisolated enum AppleSignIn: Sendable {
    struct Result: Sendable {
        let idToken: String
        let nonce: String
        let fullName: PersonNameComponents?
    }

    static func makeNonce() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func signIn(result: Result, client: SupabaseClient) async throws {
        try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: result.idToken,
                nonce: result.nonce
            )
        )

        if let fullName = result.fullName {
            var parts: [String] = []
            if let given = fullName.givenName { parts.append(given) }
            if let family = fullName.familyName { parts.append(family) }
            let name = parts.joined(separator: " ")
            if !name.isEmpty {
                try? await client.auth.update(
                    user: UserAttributes(
                        data: [
                            "full_name": .string(name),
                            "given_name": .string(fullName.givenName ?? ""),
                            "family_name": .string(fullName.familyName ?? ""),
                        ]
                    )
                )
            }
        }
    }
}
