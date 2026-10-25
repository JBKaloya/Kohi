import Auth
import AuthenticationServices
import SwiftUI

struct AccountSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(\.dismiss) private var dismiss

    @State private var nonce: String?
    @State private var error: String?
    @State private var isBusy = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                switch account.state {
                case .unavailable:
                    Section {
                        Label("Supabase is not configured.", systemImage: "icloud.slash")
                            .foregroundStyle(.secondary)
                    }

                case .signedOut:
                    Section {
                        SignInWithAppleButton(.signIn) { request in
                            let raw = AppleSignIn.makeNonce()
                            nonce = raw
                            request.requestedScopes = [.email, .fullName]
                            request.nonce = AppleSignIn.sha256(raw)
                        } onCompletion: { result in
                            handleAppleResult(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                    } footer: {
                        Text("Sign in to sync your coffee cards across devices.")
                    }

                case .signedIn(let user):
                    Section("Account") {
                        if let email = user.email {
                            DetailRow("Email", detail: email)
                        }
                        DetailRow("User ID", detail: String(user.id.uuidString.prefix(8)) + "…")
                    }

                    syncSection

                    Section {
                        Button("Export AI feedback") {
                            exportFeedback()
                        }
                    }

                    Section {
                        Button("Sign Out", role: .destructive) {
                            Task {
                                await account.signOut()
                                dismiss()
                            }
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .disabled(isBusy)
            .overlay { if isBusy { ProgressView() } }
            .sheet(item: Binding(
                get: { exportURL.map(ExportFile.init) },
                set: { exportURL = $0?.url }
            )) { file in
                ShareLink(item: file.url) {
                    Text("Share CSV")
                }
            }
        }
    }

    private struct ExportFile: Identifiable {
        var id: String { url.path }
        let url: URL
    }

    private func exportFeedback() {
        let url = FileManager.default.temporaryDirectory.appending(path: "kohi-ai-feedback.csv")
        try? feedback.csv.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
    }

    private var lastSyncText: String {
        guard let date = sync.lastSyncDate else { return "Never" }
        return CatalogueDate.happened(date)
    }

    @ViewBuilder
    private var syncSection: some View {
        Section {
            DetailRow("Last sync", detail: lastSyncText)
            pendingRow

            syncErrorRow

            Button(action: { sync.syncNow() }) {
                HStack {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if sync.isSyncing { ProgressView() }
                }
            }
            .disabled(sync.isSyncing)

            Button(action: { sync.forceBackup() }) {
                Label("Force Full Backup", systemImage: "arrow.clockwise.icloud")
            }
            .disabled(sync.isSyncing)
        } header: {
            Text("Sync")
        } footer: {
            Text("Force Full Backup re-uploads all cards and images, even those already synced.")
        }
    }

    /// What is still waiting to be pushed, per entity. The point of "we push
    /// everything" is being able to see that nothing is left behind.
    @ViewBuilder
    private var pendingRow: some View {
        let pending = sync.outbox.pendingCounts
        if pending.isEmpty {
            DetailRow("Pending", detail: "Nothing")
        } else {
            DetailRow(
                "Pending",
                detail: pending
                    .map { "\($0.count) \($0.kind.label.lowercased())" }
                    .joined(separator: " · ")
            )
        }
    }

    @ViewBuilder
    private var syncErrorRow: some View {
        if let err = sync.lastError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private struct DetailRow: View {
        let title: String
        let detail: String
        init(_ title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let err):
            if (err as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            error = err.localizedDescription
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce
            else {
                error = "Could not read Apple credential."
                return
            }
            let fullName = credential.fullName
            isBusy = true
            Task {
                do {
                    guard let client = account.client else { return }
                    try await AppleSignIn.signIn(
                        result: .init(idToken: idToken, nonce: nonce, fullName: fullName),
                        client: client
                    )
                } catch {
                    self.error = error.localizedDescription
                }
                isBusy = false
            }
        }
    }
}
