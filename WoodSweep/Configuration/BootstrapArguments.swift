import ArgumentParser

struct BootstrapArguments: ParsableArguments {
    @Option(name: .customLong("server-url"))
    var serverURL: String

    @Option(name: .customLong("bootstrap-user"))
    var bootstrapUser: String

    @Option(name: .customLong("bootstrap-password"))
    var bootstrapPassword: String

    mutating func validate() throws {
        guard KopiaUser(bootstrapUser) != nil else {
            throw ValidationError(
                "Bootstrap user must be a lowercase username@hostname."
            )
        }
    }

    var user: KopiaUser {
        guard let user = KopiaUser(bootstrapUser) else {
            preconditionFailure("Validated bootstrap user became invalid")
        }
        return user
    }
}
