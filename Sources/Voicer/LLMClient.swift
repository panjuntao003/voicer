import Foundation

final class LLMClient {
    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
    }

    private static let systemPrompt = """
    你是语音转文字后处理助手。处理规则：

    1. 修正错别字和同音字错误
    2. 把语音识别错误的英文术语修正为正确形式（如LOOM→LLM，FM→Fn，配森→Python）
    3. 添加标点符号
    4. 长文本适当分段

    严格要求：
    - 只输出处理后的文字
    - 不要添加解释或说明
    - 不要输出英文注释
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
            "max_tokens": min(text.count * 3, 1000),
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
