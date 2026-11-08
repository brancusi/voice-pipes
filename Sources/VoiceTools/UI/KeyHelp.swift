import AppKit
import SwiftUI

/// The website's step-by-step key guides (stable anchors: website/src/pages/setup.astro).
enum KeyGuide {
    static let openRouter = URL(string: "https://voicepipes.app/setup#openrouter")!
    static let jev = URL(string: "https://voicepipes.app/setup#jev")!
}

/// "Sign in with OpenRouter": the browser opens on OpenRouter (sign up there if need be), you approve, and the key
/// comes back and is saved without copying anything. The same login as `vp auth login openrouter`.
struct OpenRouterSignIn: View {
    let app: AppState
    var compact = false
    @State private var waiting = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(app.hasOpenRouterKey ? "Sign in again…" : "Sign in with OpenRouter…", action: signIn)
                    .buttonStyle(app.hasOpenRouterKey || compact ? VPButtonStyle(kind: .secondary) : VPButtonStyle(kind: .primary))
                    .disabled(waiting)
                if waiting {
                    ProgressView().controlSize(.small)
                    Text("Finish in your browser…").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    Button { waiting = false } label: { Text("Cancel").foregroundStyle(Palette.fgMuted) }.buttonStyle(.vpGhost)
                } else if !compact {
                    Text("New to OpenRouter? Sign up in the same window; add a few dollars of credit to use cloud models.")
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let failure {
                Text(failure).font(VPFont.caption).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func signIn() {
        waiting = true
        failure = nil
        Task {
            do {
                if let key = try await OpenRouterLogin.shared.run(headless: false, code: nil, announce: { _ in }), waiting {
                    app.setOpenRouterKey(key)
                    if let error = app.keyErrors[SecretKey.openRouter] { failure = "The Keychain didn't save the key: \(error)" }
                    NSApp.activate(ignoringOtherApps: true)
                }
            } catch {
                if waiting { failure = "Sign-in didn't finish: \(error.localizedDescription) Try again, or paste a key below." }
            }
            waiting = false
        }
    }
}

/// "Step-by-step guide →": the website's walkthrough for getting a key.
struct KeyGuideLink: View {
    let title: String
    let url: URL

    var body: some View {
        Link("\(title) →", destination: url)
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.purple)
    }
}
