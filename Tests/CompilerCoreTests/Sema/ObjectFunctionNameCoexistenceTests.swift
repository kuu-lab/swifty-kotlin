#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// Kotlin lets an object share its name with a top-level function; Compose
/// pairs `object MaterialTheme` with `fun MaterialTheme(...)`. The symbol
/// table let functions coexist with classes but not with objects, so the
/// second declaration reused the first one's symbol and both
/// `Theme { ... }` (KSWIFTK-SEMA-0023) and `Theme.member` (KSWIFTK-SEMA-0024)
/// failed to resolve.
@Suite
struct ObjectFunctionNameCoexistenceTests {
    @Test(arguments: [true, false])
    func objectAndSameNamedFunctionBothResolve(objectFirst: Bool) throws {
        let object = """
            object Theme {
                val computed: String get() = "computed"
            }
            """
        let function = "fun Theme(content: () -> Unit) { content() }"
        _ = try semaContext(from: """
            package fixture
            \(objectFirst ? object : function)
            \(objectFirst ? function : object)
            fun use(): String {
                var result = ""
                Theme { result = Theme.computed }
                return result
            }
            """)
    }

    @Test
    func annotationClassAndSameNamedFunctionBothResolve() throws {
        _ = try semaContext(from: """
            annotation class Marker
            fun Marker(value: Int): Int = value
            @Marker fun use(): Int = Marker(1)
            """)
    }
}
#endif
