import Foundation

final class LLMClient {
    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
    }

    private static let systemPrompt = """
    You are a speech recognition error corrector. Fix ONLY obvious errors:
    - Chinese homophone mistakes (wrong character with same sound)
    - English technical terms mistakenly transcribed as Chinese (e.g., 配森→Python, 杰森→JSON, 阿皮艾→API, 布尔→bool, 阿里→Array)
    - Clear mishearings or recognition glitches

    Rules (STRICTLY follow):
    - If the text looks correct, return it EXACTLY as-is, character for character
    - Do NOT rewrite, restructure, add punctuation, or improve style
    - Do NOT remove any content
    - Preserve all original punctuation, capitalization, spacing, and line breaks
    - Return ONLY the corrected text — no explanations, no quotes, no preamble
    """

    func refine(text: String, config: Config) async throws -> String {
        guard !config.apiKey.isEmpty, !config.baseURL.isEmpty else { return text }

        var baseURL = config.baseURL.trimmingCharacters(in: .whitespaces)
        while baseURL.hasSuffix("/") { baseURL = String(baseURL.dropLast()) }
        guard let url = URL(string: baseURL + "/v1/chat/completions") else { return text }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 500,
            "temperature": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.malformedResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum LLMError: LocalizedError {
        case badResponse(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "LLM API returned HTTP \(code)"
            case .malformedResponse: return "LLM response format unexpected"
            }
        }
    }
}
