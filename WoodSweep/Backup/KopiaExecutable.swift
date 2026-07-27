import Foundation

nonisolated enum KopiaExecutable {
    enum Error: LocalizedError {
        case missing

        var errorDescription: String? {
            "The bundled Kopia executable is missing."
        }
    }

    static func bundled(in bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(forAuxiliaryExecutable: "kopia") else {
            throw Error.missing
        }
        return url
    }
}
