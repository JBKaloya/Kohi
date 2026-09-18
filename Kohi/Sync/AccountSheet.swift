import Auth
import AuthenticationServices
import SwiftUI

struct AccountSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(CardStore.self) private var store
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(\.dismiss) private var dismiss

    @State private var nonce: String?
    @State private var error: String?
    @State private var isBusy = false
    @State private var posterBackfillProgress: (done: Int, total: Int)?
    @State private var posterBackfillTask: Task<Void, Never>?
    @State private var isRestoringPosters = false
    @State private var restoredPosterCount: Int?
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

                    if CardPoster.isAvailable {
                        posterSection
                    }

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

    @ViewBuilder
    private var posterSection: some View {
        let missing = store.cards.filter { $0.poster != .ready && $0.poster != .pending }
        Section {
            if let progress = posterBackfillProgress {
                HStack {
                    Text("Generating posters…")
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .foregroundStyle(.secondary)
                }
            } else if missing.isEmpty {
                Label("All cards have posters", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    startPosterBackfill(cards: missing)
                } label: {
                    HStack {
                        Label("Generate \(missing.count) posters", systemImage: "stamp")
                        Spacer()
                        Text("~$\(String(format: "%.2f", Double(missing.count) * 0.22))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                Task {
                    isRestoringPosters = true
                    restoredPosterCount = await sync.restorePosters()
                    isRestoringPosters = false
                }
            } label: {
                if isRestoringPosters {
                    HStack {
                        Text("Restoring…")
                        Spacer()
                        ProgressView()
                    }
                } else if let count = restoredPosterCount {
                    Label(
                        count == 0 ? "No remote posters to restore" : "Restored \(count) posters",
                        systemImage: count == 0 ? "icloud.slash" : "checkmark.icloud"
                    )
                } else {
                    Label("Restore posters from cloud", systemImage: "icloud.and.arrow.down")
                }
            }
            .disabled(isRestoringPosters)
        } header: {
            Text("Posters")
        } footer: {
            Text("Restore pulls posters already saved in Supabase. Generate creates new ones (~$0.22 each, ~2.5 min for 5 cards at Tier 1).")
        }
    }

    private func startPosterBackfill(cards: [CoffeeCard]) {
        posterBackfillProgress = (done: 0, total: cards.count)
        posterBackfillTask = Task {
            for (index, card) in cards.enumerated() {
                guard !Task.isCancelled else { break }
                var pending = card
                pending.poster = .pending
                store.update(pending)

                let success = await Task.detached(priority: .utility) {
                    await CardPoster.generate(cardID: card.id)
                }.value

                guard var latest = store.card(id: card.id) else { continue }
                latest.poster = success ? .ready : .failed
                store.update(latest)
                if success {
                    ThumbnailCache.shared.warm(latest, buckets: ThumbnailCache.buckets)
                }
                posterBackfillProgress = (done: index + 1, total: cards.count)
            }
            posterBackfillProgress = nil
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
