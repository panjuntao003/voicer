import Foundation

final class SpeechAPIClient {
    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
    }

    func transcribe(audioFileURL: URL, config: Config) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw SpeechAPIError.missingAPIKey
        }

        var baseURL = config.baseURL.trimmingCharacters(in: .whitespaces)
        while baseURL.hasSuffix("/") { baseURL = String(baseURL.dropLast()) }

        guard let url = URL(string: baseURL + "/v1/audio/transcriptions") else {
            throw SpeechAPIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = createMultipartBody(fileURL: audioFileURL, model: config.model, boundary: boundary)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpeechAPIError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = json?["text"] as? String else {
            throw SpeechAPIError.malformedResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createMultipartBody(fileURL: URL, model: String, boundary: String) -> Data {
        var body = Data()
        let fileData = (try? Data(contentsOf: fileURL)) ?? Data()

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString("\(model)\r\n")

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")

        body.appendString("--\(boundary)--\r\n")
        return body
    }

    enum SpeechAPIError: LocalizedError {
        case missingAPIKey
        case badURL
        case badResponse(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "API Key is empty"
            case .badURL: return "Speech API Base URL is invalid"
            case .badResponse(let code): return "Speech API returned HTTP \(code)"
            case .malformedResponse: return "Speech API response format unexpected"
            }
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
