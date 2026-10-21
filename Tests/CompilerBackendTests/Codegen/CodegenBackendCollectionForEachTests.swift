#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCollectionForEachTests {

    @Test(arguments: [false, true])
    func collectionForEachOnParametersAndMapValuesLinks(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun dump(c: Collection<Int>) {
            c.forEach { println(it) }
        }

        fun main() {
            dump(listOf(1))
            mapOf("a" to 2).values.forEach { println(it) }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionForEach",
            expected: "1\n2\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
