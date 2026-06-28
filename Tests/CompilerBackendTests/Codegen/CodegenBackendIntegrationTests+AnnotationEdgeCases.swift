@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesAnnotationEdgeCases() throws {
        let source = """
        @Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class RuntimeMark(val label: String = "default")

        @Target(AnnotationTarget.FIELD)
        annotation class FieldMark

        @RuntimeMark("box")
        class Box(
            @field:FieldMark
            val value: Int,
        )

        @RuntimeMark
        class DefaultBox(
            val name: String,
        )

        fun main() {
            val box = Box(10)
            val defaultBox = DefaultBox("ok")
            println(box.value)
            println(defaultBox.name)
            println("annotation-edge-ok")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AnnotationEdgeCases",
            expected:
                """
                10
                ok
                annotation-edge-ok
                """
                + "\n"
        )
    }
}

