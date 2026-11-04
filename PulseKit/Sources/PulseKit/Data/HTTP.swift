import Foundation

public enum SourceError: Error, LocalizedError, Sendable {
    case notConfigured(String)
    case http(Int, String)
    case auth(String)
    case decoding(String)
    case noSystem
    case noContainers

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let what): "Missing setting: \(what)"
        case .http(let code, let url): "HTTP \(code) from \(url)"
        case .auth(let why): "Sign-in failed: \(why)"
        case .decoding(let why): "Unexpected response: \(why)"
        case .noSystem: "No matching system on the Beszel hub"
        case .noContainers: "Could not read the container list"
        }
    }
}

/// Thin URLSession wrapper. `insecureHost` accepts a self-signed certificate for that one host
/// (Proxmox ships with one); every other host gets normal validation.
public final class HTTP: NSObject, URLSessionDelegate, Sendable {
    private let insecureHost: String?
    private nonisolated(unsafe) var session: URLSession!

    public init(insecureHost: String? = nil, timeout: TimeInterval = 8) {
        self.insecureHost = insecureHost
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout * 2
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    public func data(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw SourceError.http(code, url.path()) }
        return data
    }

    public func json<T: Decodable & Sendable>(_ type: T.Type, _ url: URL, method: String = "GET",
                                   headers: [String: String] = [:], body: Data? = nil) async throws -> T {
        let d = try await data(url, method: method, headers: headers, body: body)
        do { return try JSONDecoder.pulse.decode(T.self, from: d) }
        catch { throw SourceError.decoding("\(url.path()): \(error)") }
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let host = insecureHost, challenge.protectionSpace.host == host,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

extension JSONDecoder {
    static let pulse: JSONDecoder = JSONDecoder()
}

extension URL {
    func appending(path: String, query: [String: String]) -> URL {
        var u = appending(path: path)
        u.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        return u
    }
}

enum Dates {
    /// PocketBase "2026-11-04 14:46:36.319Z" and Docker RFC 3339 with nanoseconds.
    static func parse(_ s: String) -> Date? {
        let iso = s.replacingOccurrences(of: " ", with: "T")
        let trimmed = iso.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: trimmed) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: trimmed)
    }
}
