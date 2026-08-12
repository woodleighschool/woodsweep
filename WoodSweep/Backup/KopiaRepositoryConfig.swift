import Foundation

nonisolated struct KopiaRepositoryConfig: Decodable {
    struct APIServer: Decodable {
        let url: String
        let serverCertFingerprint: String?
    }

    let apiServer: APIServer?
    let hostname: String
    let username: String
}
