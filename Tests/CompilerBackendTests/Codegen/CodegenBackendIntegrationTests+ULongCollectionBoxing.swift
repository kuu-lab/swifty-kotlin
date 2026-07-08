@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// Regression for a ULong boxed into a generic collection (List/Set/Map):
    /// boxing previously reused kk_box_long / RuntimeLongBox, so any ULong
    /// value above Int64.max was reinterpreted as a negative signed Long
    /// wherever it went through boxed-Any dispatch (toString, equals,
    /// contains, sorted). RuntimeULongBox now keeps ULong distinguishable
    /// from Long at every one of those dispatch points.
    func testULongBoxedInCollectionsRendersAndComparesAsUnsigned() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            val small: ULong = 5uL

            println(listOf(big, small))
            println(setOf(big, small))
            println(mapOf("big" to big, "small" to small))

            val list = listOf(big, small)
            println(list.contains(big))
            println(list.contains(6uL))
            println(list == listOf(big, small))

            println(listOf(small, big).sorted())
            println(listOf(big, small).sorted())

            val dedup = setOf(big, big, small)
            println(dedup.size)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ULongCollectionBoxing",
            expected:
                """
                [17663719463477156090, 5]
                [17663719463477156090, 5]
                {big=17663719463477156090, small=5}
                true
                false
                true
                [5, 17663719463477156090]
                [5, 17663719463477156090]
                2
                """
                + "\n"
        )
    }
}
