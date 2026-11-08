import Foundation

/// Stores clothing photos as files on device. Records keep only the relative path.
struct LocalImageStore: Sendable {
    let baseDirectory: URL

    static func appDefault() throws -> LocalImageStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return LocalImageStore(baseDirectory: support.appending(path: "ClothingImages", directoryHint: .isDirectory))
    }

    /// Saves data under `fileName` and returns the relative path.
    func save(_ data: Data, fileName: String) throws -> String {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try data.write(to: url(for: fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return fileName
    }

    func load(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(for: relativePath))
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: relativePath).path(percentEncoded: false))
    }

    /// Deleting a missing file is not an error.
    func delete(_ relativePath: String) throws {
        let fileURL = url(for: relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func url(for relativePath: String) -> URL {
        baseDirectory.appending(path: relativePath)
    }
}
