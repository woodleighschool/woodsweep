import Foundation

nonisolated enum ConfigurationArguments {
    enum Error: Swift.Error, Equatable {
        case unknownOption(String)
        case missingValue(String)
        case emptyValue(String)
        case duplicateOption(String)
    }

    static func parse(_ arguments: [String]) throws -> ConfigurationUpdate {
        var username: String?
        var endpoint: String?
        var bucket: String?
        var region: String?
        var prefix: String?
        var accessKeyID: String?
        var secretAccessKey: String?
        var repositoryPassword: String?
        var seenOptions = Set<String>()
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let option = arguments[index]
            guard supportedOptions.contains(option) else {
                throw Error.unknownOption(option)
            }
            guard seenOptions.insert(option).inserted else {
                throw Error.duplicateOption(option)
            }

            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else {
                throw Error.missingValue(option)
            }

            let rawValue = arguments[valueIndex]
            guard rawValue.hasPrefix("--") == false else {
                throw Error.missingValue(option)
            }

            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else {
                throw Error.emptyValue(option)
            }

            switch option {
            case "--username":
                username = value
            case "--endpoint":
                endpoint = value
            case "--bucket":
                bucket = value
            case "--region":
                region = value
            case "--prefix":
                prefix = value
            case "--access-key":
                accessKeyID = value
            case "--secret-access-key":
                secretAccessKey = value
            case "--repository-password":
                repositoryPassword = value
            default:
                preconditionFailure("Supported option has no destination")
            }

            index = arguments.index(valueIndex, offsetBy: 1)
        }

        return ConfigurationUpdate(
            username: username,
            endpoint: endpoint,
            bucket: bucket,
            region: region,
            prefix: prefix,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            repositoryPassword: repositoryPassword
        )
    }

    private static let supportedOptions: Set<String> = [
        "--username",
        "--endpoint",
        "--bucket",
        "--region",
        "--prefix",
        "--access-key",
        "--secret-access-key",
        "--repository-password",
    ]
}
