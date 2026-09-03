//
//  GatewayClient.swift
//  Boop
//

import Foundation

enum GatewayError: LocalizedError {
    case notConfigured
    case http(status: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Cloudflare account ID, gateway name and token in Settings."
        case let .http(status, message):
            switch status {
            case 401, 403:
                return "Gateway rejected the token (\(status)). Check the token and its permissions."
            case 404:
                return "Gateway not found (404). Check the account ID and gateway name."
            case 429:
                return "Rate limited by the provider (429). Try again in a moment."
            default:
                return message.isEmpty ? "Gateway returned HTTP \(status)." : message
            }
        case let .transport(message):
            return message
        }
    }
}

/// Talks to Cloudflare AI Gateway's OpenAI-compatible endpoint, which accepts
/// `provider/model` slugs and streams standard SSE deltas back.
struct GatewayClient {
    let accountID: String
    let gatewayID: String
    let token: String

    init(settings: BoopSettings = .shared) {
        accountID = settings.accountID.trimmingCharacters(in: .whitespaces)
        gatewayID = settings.gatewayID.trimmingCharacters(in: .whitespaces)
        token = settings.token.trimmingCharacters(in: .whitespaces)
    }

    var isConfigured: Bool { !accountID.isEmpty && !gatewayID.isEmpty && !token.isEmpty }

    private var endpoint: URL? {
        URL(string: "https://gateway.ai.cloudflare.com/v1/\(accountID)/\(gatewayID)/compat/chat/completions")
    }

    /// Streams the improved text back one delta at a time.
    func stream(
        model: String,
        system: String,
        user: String,
        effort: ReasoningEffort = .default
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    do {
                        try await run(
                            model: model, system: system, user: user, effort: effort.wireValue
                        ) { continuation.yield($0) }
                    } catch GatewayError.http(400, _) where effort != .default {
                        // `reasoning_effort` isn't accepted by every model behind the
                        // gateway. The status is checked before any delta is read, so
                        // nothing has been yielded yet and a clean retry is safe.
                        try await run(
                            model: model, system: system, user: user, effort: nil
                        ) { continuation.yield($0) }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        model: String,
        system: String,
        user: String,
        effort: String?,
        onDelta: @escaping (String) -> Void
    ) async throws {
        guard isConfigured, let endpoint else { throw GatewayError.notConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "cf-aig-authorization")

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if let effort { body["reasoning_effort"] = effort }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw GatewayError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GatewayError.http(status: status, message: await errorMessage(from: bytes))
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data)
            else { continue }
            for choice in chunk.choices ?? [] {
                if let content = choice.delta?.content, !content.isEmpty { onDelta(content) }
            }
        }
    }

    /// Cloudflare returns a JSON error body; surface the useful part of it.
    private func errorMessage(from bytes: URLSession.AsyncBytes) async -> String {
        var raw = ""
        do {
            for try await line in bytes.lines { raw += line }
        } catch {
            // A partial body is still more useful than nothing.
        }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return String(raw.prefix(300)) }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let errors = object["errors"] as? [[String: Any]],
           let message = errors.first?["message"] as? String {
            return message
        }
        return String(raw.prefix(300))
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]?
    }
}
