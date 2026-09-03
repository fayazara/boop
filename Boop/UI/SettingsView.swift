//
//  SettingsView.swift
//  Boop
//

import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            GatewaySettings()
                .tabItem { Label("Gateway", systemImage: "key") }
            PromptSettings()
                .tabItem { Label("Prompt", systemImage: "text.quote") }
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable private var settings = BoopSettings.shared
    @State private var hasAccessibility = AccessibilityPermission.isGranted

    /// Re-checked when the app comes forward rather than on a timer: the window is
    /// never released, so a `Timer.publish` here would keep firing for the life of
    /// the app even with Settings closed.
    private let becameActive = NotificationCenter.default
        .publisher(for: NSApplication.didBecomeActiveNotification)

    var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    HotKeyRecorder(settings: settings)
                }
                Text("Defaults to Hyper + A (⌃ ⌥ ⇧ ⌘ A) — what a caps-lock Hyper key sends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hot Key")
            }

            Section {
                Picker("Model", selection: $settings.modelID) {
                    ForEach(Provider.allCases) { provider in
                        Section(provider.rawValue) {
                            ForEach(AIModel.models(for: provider)) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                }
                Picker("Reasoning effort", selection: $settings.reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.label).tag(effort)
                    }
                }
                Text("Higher effort means slower, more considered rewrites. Models that don't support reasoning ignore this and fall back to their default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Model")
            }

            Section {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Label(
                            hasAccessibility ? "Granted" : "Not granted",
                            systemImage: hasAccessibility
                                ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(hasAccessibility ? Color.green : Color.orange)
                        if !hasAccessibility {
                            Button("Open Settings…") { AccessibilityPermission.openSettings() }
                        }
                    }
                }
                Text("Boop needs Accessibility access to read the selected text and to paste the result back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .onAppear { hasAccessibility = AccessibilityPermission.isGranted }
        .onReceive(becameActive) { _ in
            hasAccessibility = AccessibilityPermission.isGranted
        }
    }
}

// MARK: - Gateway

private struct GatewaySettings: View {
    @Bindable private var settings = BoopSettings.shared

    var body: some View {
        Form {
            Section {
                TextField("Account ID", text: $settings.accountID, prompt: Text("a1b2c3…"))
                TextField("Gateway name", text: $settings.gatewayID, prompt: Text("boop"))
                SecureField("Gateway token", text: $settings.token)
            } header: {
                Text("Cloudflare AI Gateway")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Boop sends every request through your own Cloudflare AI Gateway, so provider keys stay in your Cloudflare account and never touch this app.")
                    Text("Store your OpenAI / Anthropic / Google keys in the gateway's provider settings, then create a gateway authentication token and paste it above.")
                    Link(
                        "Open the AI Gateway dashboard",
                        destination: URL(string: "https://dash.cloudflare.com/?to=/:account/ai/ai-gateway")!
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            Section {
                LabeledContent("Status") {
                    Label(
                        settings.isConfigured ? "Configured" : "Incomplete",
                        systemImage: settings.isConfigured
                            ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(settings.isConfigured ? Color.green : Color.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Prompt

private struct PromptSettings: View {
    @Bindable private var settings = BoopSettings.shared

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 260)
                Button("Reset to default") {
                    settings.prompt = BoopSettings.defaultPrompt
                }
            } header: {
                Text("System Prompt")
            } footer: {
                Text("The selected text is sent as the user message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }
}
