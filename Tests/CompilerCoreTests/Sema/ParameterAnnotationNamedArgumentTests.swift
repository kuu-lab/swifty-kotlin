#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// OpenAPI-generated models annotate constructor properties with
/// `@SerialName(value = "id")`. The parameter modifier check scanned the
/// annotation's argument list and reported the named argument `value` as the
/// `value` modifier: "modifier 'value' is not applicable to 'value parameter'".
@Suite
struct ParameterAnnotationNamedArgumentTests {
    @Test
    func annotationArgumentsAreNotParameterModifiers() throws {
        _ = try semaContext(from: """
            annotation class Label(val value: String)

            class Item(
                @Label(value = "id") val id: String,
                @property:Label(value = "name") val name: String,
                @Label(value = "plain") plain: Int,
            )

            fun top(@Label(value = "p") p: Int, @Label(value = "q") vararg rest: Int): Int = p + rest.size
            """)
    }

    @Test
    func modifiersAfterAnnotationArgumentsAreStillChecked() throws {
        _ = try semaContext(
            from: """
                annotation class Label(val value: String)
                fun top(@Label(value = "p") private p: Int): Int = p
                """,
            expecting: [.error("KSWIFTK-SEMA-0400", containing: "modifier 'private' is not applicable to 'value parameter'")]
        )
    }
}
#endif
