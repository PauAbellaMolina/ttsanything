import Foundation

enum TTSError: LocalizedError {
    case noAPIKey
    case invalidResponse(String)
    case networkError(Error)
    case textTooLong

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured"
        case .invalidResponse(let msg): return msg
        case .networkError(let err): return err.localizedDescription
        case .textTooLong: return "Text exceeds 4096 character limit"
        }
    }
}

class TTSService: ObservableObject {
    @Published var isLoading = false

    func synthesize(text: String, voice: Voice, apiKey: String) async throws -> Data {
        let trimmed = String(text.prefix(4096))
        if trimmed.isEmpty { throw TTSError.invalidResponse("No text to read") }

        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "tts-1",
            "voice": voice.rawValue,
            "input": trimmed,
            "response_format": "wav"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TTSError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJSON["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw TTSError.invalidResponse(message)
            }
            throw TTSError.invalidResponse("API error (HTTP \(httpResponse.statusCode))")
        }

        return data
    }
}
