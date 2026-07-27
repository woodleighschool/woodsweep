import Foundation

nonisolated struct KopiaRepositoryConfig: Decodable {
    struct Storage: Decodable {
        struct S3: Decodable {
            let bucket: String
            let endpoint: String
            let accessKeyID: String
            let secretAccessKey: String
            let prefix: String?
            let region: String?
        }

        let type: String
        let config: S3
    }

    let storage: Storage
}
