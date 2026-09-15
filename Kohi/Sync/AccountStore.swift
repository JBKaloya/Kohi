import Foundation
import Observation
import Supabase
import Auth

@Observable
final class AccountStore {
    enum State: Sendable {
        case unavailable
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .unavailable
    @ObservationIgnored private var authListener: Task<Void, Never>?

    let client: SupabaseClient?

    init() {
        client = SupabaseConfig.current
        guard let client else {
            state = .unavailable
            return
        }

        state = .signedOut

        authListener = Task { @MainActor [weak self] in
            if let session = try? await client.auth.session {
                self?.state = .signedIn(session.user)
            }
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .signedIn, .tokenRefreshed:
                    if let user = session?.user {
                        self.state = .signedIn(user)
                    }
                case .signedOut:
                    self.state = .signedOut
                default:
                    break
                }
            }
        }
    }

    deinit {
        authListener?.cancel()
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var userID: UUID? {
        if case .signedIn(let user) = state { return user.id }
        return nil
    }

    var isAvailable: Bool {
        if case .unavailable = state { return false }
        return true
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
    }
}
