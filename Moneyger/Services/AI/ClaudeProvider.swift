import Foundation

final class ClaudeProvider: AIProvider {
    let name = "Claude"
    // Smallest, cheapest Claude tier; plenty for structured extraction with a detailed prompt
    private let model = "claude-haiku-5-5"
    private let baseURL = "https://api.anthropic.com/v1/messages"

    var isConfigured: Bool { !apiKey.isEmpty }

    private var apiKey: String {
        KeychainService.load(key: KeychainKeys.claudeAPIKey) ?? ""
    }

    func complete(system: String, prompt: String) async throws -> String {
        guard isConfigured else { throw AIError.notConfigured(name) }

        let body: [String: Any] = [
            "model": model,
            // Statements with many transactions now come back in one response, so allow a larger output
            "max_tokens": 8192,
            // Instructions are identical for every email; marked cacheable to cut input cost on large syncs
            // (the API ignores this silently while the prompt is below the model's minimum cacheable size)
            "system": [
                ["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]
            ],
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AIError.httpError(provider: name, status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: String(data: data, encoding: .utf8) ?? "")
        }

        let result = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = result.content.first?.text else {
            throw AIError.emptyResponse
        }
        return text
    }
}

struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
}
