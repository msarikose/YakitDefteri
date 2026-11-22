import Foundation

/// Never permits writes until a complete database has been successfully read
/// (or its absence confirmed while protected data is available).
final class DatabaseDisk {
    let file: URL
    private(set) var writable = false
    private let read: (URL) throws -> Data
    private let write: (Data, URL) throws -> Void

    init(file: URL,
         read: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
         write: @escaping (Data, URL) throws -> Void = DatabaseDisk.writeProtected) {
        self.file = file; self.read = read; self.write = write
    }
    func load(allowMissing: Bool) throws -> Database {
        writable = false
        let data: Data
        do {
            data = try read(file)
        } catch {
            let e = error as NSError
            let missing = e.domain == NSCocoaErrorDomain &&
                (e.code == CocoaError.fileReadNoSuchFile.rawValue || e.code == CocoaError.fileNoSuchFile.rawValue)
            guard missing && allowMissing else { throw error }
            writable = true
            return Database()
        }
        let database = try JSONDecoder().decode(Database.self, from: data)
        try DataValidation.validate(database)
        writable = true
        return database
    }
    func save(_ database: Database) throws {
        guard writable else { throw CocoaError(.fileWriteNoPermission) }
        try DataValidation.validate(database)
        try write(JSONEncoder().encode(database), file)
    }
    static func writeProtected(_ data: Data, to file: URL) throws {
        #if os(iOS)
        // Allows a new CarPlay process to read after the first unlock since boot.
        // Still encrypted, and unavailable before that first authentication.
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
}
