@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-CINTEROP-FN-039: typeOf<T>() from kotlinx.cinterop
    func testCodegenCinteropTypeOfNonNullable() throws {
        let source = """
        import kotlinx.cinterop.typeOf
        import kotlin.reflect.KType

        fun getStringType(): KType = typeOf<String>()

        fun main() {
            val t = getStringType()
            println(t.isMarkedNullable)
        }
        """
        try assertKotlinOutput(source, moduleName: "CinteropTypeOf", expected: "false\n")
    }

    func testCodegenCinteropTypeOfNullable() throws {
        let source = """
        import kotlinx.cinterop.typeOf
        import kotlin.reflect.KType

        fun getNullableIntType(): KType = typeOf<Int?>()

        fun main() {
            val t = getNullableIntType()
            println(t.isMarkedNullable)
        }
        """
        try assertKotlinOutput(source, moduleName: "CinteropTypeOfNullable", expected: "true\n")
    }
}

