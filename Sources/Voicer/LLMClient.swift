import Foundation

final class LLMClient {
    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
    }

    private static let systemPrompt = """
    You are a speech-to-text post-processor. The user just dictated text using voice input. Clean it up:

    - Fix Chinese homophone errors (wrong character with same sound)
    - Fix English technical terms mistakenly transcribed as Chinese (e.g., 配森→Python, 杰森→JSON, 阿皮艾→API)
    - Fix English words phonetically transcribed in Chinese and vice versa
    - Add proper punctuation (periods, commas, question marks) where natural pauses would be
    - Add paragraph breaks if the text is long enough to warrant them
    - Do NOT change the meaning or add content that was not spoken
    - Do NOT add explanations, quotes, or preamble
    - Return ONLY the processed text

    If the text is already clean, return it as-is with punctuation added.
    """

    func refine(text: String, config: Config) async throws -> String {
        guard !config.apiKey.isEmpty, !config.baseURL.isEmpty else { return text }

        var baseURL = config.baseURL.trimmingCharacters(in: .whitespaces)
        while baseURL.hasSuffix("/") { baseURL = String(baseURL.dropLast()) }
        guard let url = URL(string: baseURL + "/v1/chat/completions") else {
            throw LLMError.badURL
        }

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
            "max_tokens": 2000,
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
        case badURL

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "LLM API returned HTTP \(code)"
            case .malformedResponse: return "LLM response format unexpected"
            case .badURL: return "LLM API Base URL is invalid"
            }
        }
    }
}
