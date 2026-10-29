import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case network(String)
    case unauthorized
    case notFound(String)
    case rateLimited
    case server(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL was invalid."
        case .invalidResponse:
            return "The server sent an unexpected response."
        case .network(let message):
            return "Network problem: \(message)"
        case .unauthorized:
            return "Your API keys were rejected. Make sure you pasted Alpaca paper-trading keys in Settings."
        case .notFound(let message):
            return message.isEmpty ? "Not found." : message
        case .rateLimited:
            return "Too many requests. Alpaca's free plan allows 200 per minute, so try again shortly."
        case .server(let status, let message):
            guard !message.isEmpty else { return "Server error (\(status))." }
            return message.prefix(1).uppercased() + message.dropFirst()
        case .decoding:
            return "Couldn't read the server response."
        }
    }
}

struct HTTPClient {
    let session: URLSession
    let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = .alpaca) {
        self.session = session
        self.decoder = decoder
    }

    func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let data = try await data(for: request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decoding \(T.self) failed: \(error)")
            #endif
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    func data(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound(Self.serverMessage(from: data))
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.server(status: http.statusCode, message: Self.serverMessage(from: data))
        }
    }

    private static func serverMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum AlpacaDate {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Alpaca sends RFC 3339 timestamps with up to nanosecond precision, which
    /// ISO8601DateFormatter can't parse, so the fractional part is dropped.
    static func parse(_ string: String) -> Date? {
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return formatter.date(from: trimmed)
    }

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

extension JSONDecoder {
    static var alpaca: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = AlpacaDate.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    static var alpaca: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
