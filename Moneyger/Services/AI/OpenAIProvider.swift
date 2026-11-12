import Foundation

final class OpenAIProvider: AIProvider {
    let name = "OpenAI"
    // Small, low-cost tier; extraction doesn't need a frontier model
    private let model = "gpt-5-mini"
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    var isConfigured: Bool { !apiKey.isEmpty }

    private var apiKey: String {
        KeychainService.load(key: KeychainKeys.openAIAPIKey) ?? ""
    }

    func complete(system: String, prompt: String) async throws -> String {
        guard isConfigured else { throw AIError.notConfigured(name) }

        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ],
            // GPT-5 models reject custom temperature; low reasoning keeps latency and cost down
            "reasoning_effort": "low"
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AIError.httpError(provider: name, status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: String(data: data, encoding: .utf8) ?? "")
        }

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = result.choices.first?.message.content else {
            throw AIError.emptyResponse
        }
        return text
    }
}

struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }
    struct Message: Decodable {
        let content: String
    }
}
