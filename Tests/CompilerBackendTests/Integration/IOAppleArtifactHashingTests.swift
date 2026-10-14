#if os(macOS)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IOAppleArtifactHashingTests {
    @Test
    func relativeKeysRemainStableThroughDirectoryAliases() throws {
        let files = FileManager.default
        let owner = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? files.removeItem(at: owner) }
        let target = owner.appendingPathComponent("actual", isDirectory: true)
        try files.createDirectory(at: target.appendingPathComponent("objects"), withIntermediateDirectories: true)
        let metadata = Data([0, 1, 2])
        let object = Data([3, 4, 5])
        try metadata.write(to: target.appendingPathComponent("metadata.bin"))
        try object.write(to: target.appendingPathComponent("objects/library.o"))
        let alias = owner.appendingPathComponent("alias", isDirectory: true)
        try files.createSymbolicLink(at: alias, withDestinationURL: target)
        let expected = [
            "metadata.bin": FileFingerprint.sha256Hex(metadata),
            "objects/library.o": FileFingerprint.sha256Hex(object)
        ]
        #expect(try io1763ArtifactHashes(target) == expected)
        #expect(try io1763ArtifactHashes(alias) == expected)
    }
}

#endif
