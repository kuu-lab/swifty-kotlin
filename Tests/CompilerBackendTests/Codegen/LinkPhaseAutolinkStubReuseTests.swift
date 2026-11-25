@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LinkPhaseAutolinkStubReuseTests {
    @Test
    func testReusedLinkPhaseRecreatesStubAfterPreviousLinkRemovedItsDirectory() throws {
        let linuxTarget = TargetTriple(arch: "x86_64", vendor: "kswiftkstubtest", os: "linux-gnu", osVersion: nil)
        let linkPhase = LinkPhase()

        let firstStub = try #require(try linkPhase.emitSwiftAutolinkStubIfNeeded(target: linuxTarget))
        try FileManager.default.removeItem(atPath: URL(fileURLWithPath: firstStub).deletingLastPathComponent().path)

        let secondStub = try #require(try linkPhase.emitSwiftAutolinkStubIfNeeded(target: linuxTarget))
        defer {
            try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: secondStub).deletingLastPathComponent().path)
        }

        let contents = try String(contentsOfFile: secondStub, encoding: .utf8)
        #expect(contents.contains("_kswiftkRuntimeAutolinkAnchor"))
    }
}
