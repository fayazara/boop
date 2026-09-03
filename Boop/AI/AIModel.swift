//
//  AIModel.swift
//  Boop
//

import Foundation

enum Provider: String, CaseIterable, Identifiable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Google"

    var id: String { rawValue }
}

struct AIModel: Identifiable, Hashable {
    /// The slug sent to the gateway, e.g. `anthropic/claude-sonnet-5`.
    let id: String
    let name: String
    let provider: Provider

    static let all: [AIModel] = [
        AIModel(id: "anthropic/claude-opus-5", name: "Claude Opus 5", provider: .anthropic),
        AIModel(id: "anthropic/claude-sonnet-5", name: "Claude Sonnet 5", provider: .anthropic),
        AIModel(id: "anthropic/claude-fable-5", name: "Claude Fable 5", provider: .anthropic),
        AIModel(id: "google/gemini-3.8-flash", name: "Gemini 3.8 Flash", provider: .google),
        AIModel(id: "google/gemini-3.5-flash-lite", name: "Gemini 3.5 Flash Lite", provider: .google),
        AIModel(id: "openai/gpt-5.6-luna", name: "GPT-5.6 Luna", provider: .openai),
        AIModel(id: "openai/gpt-5.6-sol", name: "GPT-5.6 Sol", provider: .openai),
        AIModel(id: "openai/gpt-5.6-terra", name: "GPT-5.6 Terra", provider: .openai),
    ]

    static let defaultID = "openai/gpt-5.6-luna"

    static var fallback: AIModel { named(defaultID) ?? all[0] }

    static func named(_ id: String) -> AIModel? { all.first { $0.id == id } }

    static func models(for provider: Provider) -> [AIModel] { all.filter { $0.provider == provider } }
}

/// How much the model should think before answering.
///
/// Sent as OpenAI's `reasoning_effort` field, which the gateway's compat endpoint
/// forwards upstream. Not every model accepts it, so `.default` — which omits the
/// field entirely — is what Boop ships with.
enum ReasoningEffort: String, CaseIterable, Identifiable {
    case `default`
    case minimal
    case low
    case medium
    case high

    var id: String { rawValue }

    /// The value to send, or nil to leave the parameter out.
    var wireValue: String? { self == .default ? nil : rawValue }

    var label: String {
        switch self {
        case .default: return "Provider default"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
