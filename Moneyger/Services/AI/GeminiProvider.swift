import Foundation

final class GeminiProvider: AIProvider {
    let name = "Gemini"
    // Cheapest Flash tier; the alias tracks the current Flash-Lite so retired versions don't break requests.
    // Extraction is well-specified by the prompt, so the full Flash model isn't needed.
    private let model = "gemini-flash-lite-latest"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    var isConfigured: Bool { !apiKey.isEmpty }

    private var apiKey: String {
        (KeychainService.load(key: KeychainKeys.geminiAPIKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func complete(system: String, prompt: String) async throws -> String {
        guard isConfigured else { throw AIError.notConfigured(name) }
        guard let url = URL(string: "\(baseURL)/\(model):generateContent") else {
            throw AIError.requestFailed("Invalid Gemini URL")
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.1
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Surface Google's error message (e.g. invalid key, model not found, quota exceeded)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let apiMessage = (try? JSONDecoder().decode(GeminiErrorResponse.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(provider: name, status: status, message: apiMessage)
        }

        let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = result.candidates.first?.content.parts.first?.text else {
            throw AIError.emptyResponse
        }
        return text
    }
}

struct GeminiResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }
    struct Content: Decodable {
        let parts: [Part]
    }
    struct Part: Decodable {
        let text: String
    }
}

struct GeminiErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let code: Int?
        let message: String
        let status: String?
    }
}

enum AIError: LocalizedError {
    case requestFailed(String)
    case httpError(provider: String, status: Int, message: String)
    case emptyResponse
    case notConfigured(String)

    /// Temporary server-side errors (overload, rate limit) that are worth retrying.
    var isTransient: Bool {
        if case .httpError(_, let status, _) = self {
            return [408, 429, 500, 502, 503, 504].contains(status)
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .requestFailed(let msg): return "AI request failed: \(msg)"
        case .httpError(let provider, let status, let message):
            return "AI request failed: \(provider) HTTP \(status): \(message)"
        case .emptyResponse: return "AI returned empty response"
        case .notConfigured(let provider): return "\(provider) API key not configured"
        }
    }
}
