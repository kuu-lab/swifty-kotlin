import Foundation
@testable import Runtime
import XCTest

// MARK: - STDLIB-IO-PATH-FN-039: Path.walk runtime tests

private func rtpwStringRaw(_ value: String) -> Int {
    value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
            Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
        }
    }
}

private func rtpwPathHandle(_ path: String) -> Int {
    kk_path_new(rtpwStringRaw(path))
}

private func rtpwExtractString(_ raw: Int) -> String {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
}

private func rtpwPaths(_ sequenceRaw: Int) -> [String] {
    var thrown = 0
    let listRaw = kk_sequence_to_list(sequenceRaw, &thrown)
    let size = kk_unbox_int(kk_list_size(listRaw))
    return (0 ..< size).map { index in
        rtpwExtractString(kk_path_toString(kk_list_get(listRaw, index)))
    }
}

private func rtpwOptions(_ ordinals: [Int]) -> Int {
    let arrayRaw = kk_array_new(ordinals.count)
    for (index, ordinal) in ordinals.enumerated() {
        var thrown = 0
        _ = kk_array_set(arrayRaw, index, kk_box_int(ordinal), &thrown)
    }
    return arrayRaw
}

final class RuntimePathWalkTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    private func makeTempDirTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "alpha".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let subdir = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "beta".write(to: subdir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        return root
    }

    func testPathWalkDefaultUsesDepthFirstPreorderAndIncludesRoot() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = rtpwPaths(kk_path_walk(rtpwPathHandle(root.path), 0))

        XCTAssertEqual(
            paths,
            [
                root.path,
                root.appendingPathComponent("a.txt").path,
                root.appendingPathComponent("sub").path,
                root.appendingPathComponent("sub/b.txt").path,
            ]
        )
    }

    func testPathWalkBreadthFirstOptionVisitsDirectoryChildrenBeforeGrandchildren() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstDir = root.appendingPathComponent("aa")
        try FileManager.default.createDirectory(at: firstDir, withIntermediateDirectories: true)
        try "nested".write(to: firstDir.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)
        try "sibling".write(to: root.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = rtpwPaths(kk_path_walk(rtpwPathHandle(root.path), rtpwOptions([0])))

        XCTAssertEqual(
            paths,
            [
                root.path,
                firstDir.path,
                root.appendingPathComponent("z.txt").path,
                firstDir.appendingPathComponent("nested.txt").path,
            ]
        )
    }

    func testPathWalkDoesNotFollowDirectorySymlinkByDefault() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: root.appendingPathComponent("sub")
        )

        let paths = rtpwPaths(kk_path_walk(rtpwPathHandle(root.path), 0))

        XCTAssertTrue(paths.contains(link.path))
        XCTAssertFalse(paths.contains(link.appendingPathComponent("b.txt").path))
    }

    func testPathWalkFollowLinksOptionTraversesDirectorySymlinkOnce() throws {
        let root = try makeTempDirTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: root.appendingPathComponent("sub")
        )

        let paths = rtpwPaths(kk_path_walk(rtpwPathHandle(root.path), rtpwOptions([1])))

        XCTAssertTrue(paths.contains(link.path))
        XCTAssertTrue(paths.contains(link.appendingPathComponent("b.txt").path))
    }
}
