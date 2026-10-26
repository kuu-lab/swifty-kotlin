import Foundation
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ReifiedTypeParameterPlacementTests {
    private func check(_ source: String) throws -> CompilationContext {
        let input = "/virtual/reified-placement.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data(source.utf8))
        try runSema(context)
        return context
    }

    @Test(arguments: [
        "class Generic<reified T>",
        "interface Iface<reified T> { fun f(): T }",
        "annotation class Ann<reified T>",
        "enum class E<reified T> { A }",
        "class Outer { class Nested<reified T> }",
        "interface Outer { class Nested<reified T> }",
        "fun main() { class Local<reified T> }",
        "typealias Alias<reified T> = (T) -> T",
        "class Outer { typealias Alias<reified T> = (T) -> T }",
        "fun <reified T> nonInline(value: T): T = value",
    ])
    func reifiedOutsideInlineFunctionIsRejected(source: String) throws {
        let context = try check(source)
        #expect(
            context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0020" },
            "\(source): \(context.diagnostics.diagnostics)"
        )
    }

    @Test(arguments: [
        "inline fun <reified T> id(value: T): T = value",
        "class Box<T>(var value: T)\ninline val <reified T> Box<T>.same: T get() = value",
        "class Plain<out T>(val value: T)",
        "interface Iface<in T> { fun accept(value: T) }",
        "typealias Alias<T> = (T) -> T",
    ])
    func validTypeParameterPlacementsAreAccepted(source: String) throws {
        let context = try check(source)
        #expect(!context.diagnostics.hasError, "\(source): \(context.diagnostics.diagnostics)")
    }
}
