#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendKUU603CharCollectionTests {
    private let source = """
    fun main() {
        println("hello".toList())
        println("hello".toList().toSet().sorted())
        println("hello".toList().associateWith { it.code })
        println("hello".groupBy { it }.mapValues { it.value.size })
    }
    """

    private let expectedOutput = """
    [h, e, l, l, o]
    [e, h, l, o]
    {h=104, e=101, l=108, o=111}
    {h=1, e=1, l=2, o=1}
    """ + "\n"

    @Test
    func testCharCollectionsFromBundledStdlibPreserveTextRepresentation() throws {
        try assertKotlinOutput(
            source,
            moduleName: "KUU603CharCollectionsSource",
            expected: expectedOutput,
            allowDefaultStdlibLibrary: false
        )
    }

    @Test
    func testCharCollectionsFromPrecompiledStdlibPreserveTextRepresentation() throws {
        try assertKotlinOutput(
            source,
            moduleName: "KUU603CharCollectionsArtifact",
            expected: expectedOutput,
            allowDefaultStdlibLibrary: true
        )
    }
}
#endif
