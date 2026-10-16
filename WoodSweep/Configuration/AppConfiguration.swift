import Foundation

nonisolated struct AppConfiguration: Codable, Equatable, Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidServerURL
        case emptyPassword
        case notBootstrapped

        var errorDescription: String? {
            switch self {
            case .invalidServerURL:
                "The Kopia server must be an HTTPS URL with a valid port."
            case .emptyPassword:
                "The machine repository password is empty."
            case .notBootstrapped:
                "This Mac has not been configured. Run WoodSweep bootstrap as root."
            }
        }
    }

    let serverURL: String
    let serverPassword: String
    let deviceID: UUID

    init(serverURL: String, serverPassword: String, deviceID: UUID) throws {
        guard var components = URLComponents(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              (1 ... 65535).contains(components.port ?? 443)
        else {
            throw Error.invalidServerURL
        }
        components.scheme = "https"
        components.port = components.port ?? 443
        components.path = ""
        guard let url = components.url else {
            throw Error.invalidServerURL
        }
        guard serverPassword.isEmpty == false else {
            throw Error.emptyPassword
        }
        self.serverURL = url.absoluteString
        self.serverPassword = serverPassword
        self.deviceID = deviceID
    }

    var user: KopiaUser {
        guard let user = KopiaUser("\(deviceID.uuidString.lowercased())@woodsweep") else {
            preconditionFailure("Device ID must form a valid Kopia user")
        }
        return user
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            serverURL: values.decode(String.self, forKey: .serverURL),
            serverPassword: values.decode(String.self, forKey: .serverPassword),
            deviceID: values.decode(UUID.self, forKey: .deviceID)
        )
    }
}

nonisolated protocol ConfigurationLoading: Sendable {
    func load() throws -> AppConfiguration
}

nonisolated struct AppConfigurationStore: ConfigurationLoading {
    private let credentials: any CredentialStoring

    init(credentials: any CredentialStoring = KeychainCredentialStore()) {
        self.credentials = credentials
    }

    func load() throws -> AppConfiguration {
        guard let configuration = try credentials.load() else {
            throw AppConfiguration.Error.notBootstrapped
        }
        return configuration
    }
}
