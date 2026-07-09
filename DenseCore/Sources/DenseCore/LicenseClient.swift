import Foundation

public struct LicenseClient {
    public enum LicenseError: Error { case badResponse, rejected(String) }
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func activate(key: String, instanceName: String) async throws -> String {
        let body = ["license_key": key, "instance_name": instanceName]
        let json = try await post(path: "activate", form: body)
        guard let activated = json["activated"] as? Bool, activated,
              let instance = json["instance"] as? [String: Any],
              let id = instance["id"] as? String else {
            throw LicenseError.rejected((json["error"] as? String) ?? "activation refused")
        }
        return id
    }

    public func validate(key: String, instanceID: String) async throws -> Bool {
        let json = try await post(path: "validate", form: ["license_key": key, "instance_id": instanceID])
        return (json["valid"] as? Bool) ?? false
    }

    private func post(path: String, form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.badResponse
        }
        return json
    }
}
