import Foundation
import os

/// Generates a stamp-on-parchment poster for a card by sending its flat scan to
/// the `card-poster` edge function (OpenAI gpt-image-2 behind the scenes).
/// The API key never leaves the server; the client only sends a base64 image.
nonisolated enum CardPoster {
    static var isAvailable: Bool {
        guard let path = Bundle.main.path(forResource: "Supabase", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let url = dict["SUPABASE_URL"] as? String, !url.isEmpty,
              let key = dict["SUPABASE_KEY"] as? String, !key.isEmpty
        else { return false }
        return true
    }

    private static let uploadMaxPixel = 1024
    /// gpt-image-2 sits silent for ~2 minutes before the first byte comes back.
    /// `URLSession.shared` defaults to a 60 s idle timeout, which is why every
    /// previous attempt marked the card `failed` while the edge function was
    /// still running.
    private static let requestTimeout: TimeInterval = 300

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private static func log(_ message: String) {
        print("[card-poster] \(message)")
    }

    /// Generates and persists the poster. Returns `true` on success.
    @discardableResult
    static func generate(cardID: UUID) async -> Bool {
        log("start \(cardID)")

        guard let path = Bundle.main.path(forResource: "Supabase", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let baseURL = dict["SUPABASE_URL"] as? String, !baseURL.isEmpty,
              let apiKey = dict["SUPABASE_KEY"] as? String, !apiKey.isEmpty
        else {
            log("ERROR: Supabase.plist missing or incomplete")
            return false
        }

        let flatURL = ImageStore.shared.url(for: cardID, kind: .flat)
        guard ImageStore.shared.exists(cardID, kind: .flat) else {
            log("ERROR: flat.heic does not exist for \(cardID)")
            return false
        }
        guard let image = ImageCodec.downsample(flatURL, maxPixel: uploadMaxPixel) else {
            log("ERROR: could not downsample flat.heic for \(cardID)")
            return false
        }
        guard let jpeg = ImageCodec.encodeJPEG(image, quality: 0.8) else {
            log("ERROR: JPEG encode failed for \(cardID)")
            return false
        }
        log("uploading \(jpeg.count) byte JPEG")

        guard let endpoint = URL(string: "\(baseURL)/functions/v1/card-poster") else {
            log("ERROR: bad endpoint URL")
            return false
        }

        struct Payload: Encodable {
            let image: String
            let mime: String
            let card_id: String
        }
        struct PosterResponse: Decodable {
            let image: String?
            let mime: String?
            let error: String?
        }

        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")

        do {
            request.httpBody = try JSONEncoder().encode(
                Payload(
                    image: jpeg.base64EncodedString(),
                    mime: "image/jpeg",
                    card_id: cardID.uuidString
                )
            )
        } catch {
            log("ERROR: JSON encode — \(error)")
            return false
        }

        let start = ContinuousClock.now
        do {
            log("waiting for edge function (timeout \(Int(requestTimeout))s)…")
            let (data, urlResponse) = try await session.data(for: request)
            let elapsed = start.duration(to: .now)
            let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
            log("HTTP \(statusCode), \(data.count) bytes, \(elapsed)")

            guard 200..<300 ~= statusCode else {
                let body = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
                log("ERROR: HTTP \(statusCode) — \(body)")
                return false
            }

            let response: PosterResponse
            do {
                response = try JSONDecoder().decode(PosterResponse.self, from: data)
            } catch {
                log("ERROR: JSON decode — \(error)")
                return false
            }

            if let err = response.error {
                log("ERROR: edge function — \(err)")
                return false
            }

            guard let b64 = response.image, let pngData = Data(base64Encoded: b64) else {
                log("ERROR: missing or invalid image in response")
                return false
            }
            guard ImagePipeline.installPoster(id: cardID, data: pngData) else {
                log("ERROR: could not install poster.heic")
                return false
            }
            log("SUCCESS: saved poster.heic for \(cardID)")
            return true
        } catch {
            log("ERROR: network failed after \(start.duration(to: .now)) — \(error)")
            return false
        }
    }
}
