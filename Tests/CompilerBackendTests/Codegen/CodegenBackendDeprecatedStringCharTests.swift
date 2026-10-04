@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendDeprecatedStringCharTests {

    @Test
    func testDeprecatedStringAndCharMembersRemainCallable() throws {
        let source = """
        fun main() {
            println("ABC".decapitalize())
            println("abc".decapitalize())
            println("".decapitalize())
            println('a'.inc())
            println('z'.dec())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DeprecatedStringCharMembers",
            expected: "aBC\nabc\n\nb\ny\n"
        )
    }
}
#endif
