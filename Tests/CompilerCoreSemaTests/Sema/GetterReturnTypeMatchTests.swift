#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// kotlinc requires an explicit getter return type to equal the property
/// type exactly ("getter return type must be equal to the type of the
/// property"), including nullability. The compiler must reject mismatches
/// instead of silently compiling them.
@Suite
struct GetterReturnTypeMatchTests {
    private func semaErrors(_ source: String) throws -> [Diagnostic] {
        var errors: [Diagnostic]?
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        }
        return try #require(errors)
    }

    @Test(arguments: [
        // Different nominal types.
        "class A { val x: Int get(): String = \"oops\" }",
        "class A { val x: Any get(): String = \"oops\" }",
        // Nullability must match exactly.
        "class A { val x: Int? get(): Int = 1 }",
        "class A { val x: Int get(): Int? = 1 }",
    ])
    func rejectsGetterReturnTypeMismatch(source: String) throws {
        let errors = try semaErrors(source)
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0469" }, "\(errors)")
    }

    @Test(arguments: [
        "class A { val x: Int get(): Int = 1 }",
        "class A { val x: Int? get(): Int? = null }",
        "class A { val x get(): String = \"ok\" }",
        "class A { val x: String get(): String = \"ok\" }",
    ])
    func acceptsMatchingGetterReturnType(source: String) throws {
        let errors = try semaErrors(source)
        #expect(errors.isEmpty, "\(errors)")
    }
}
#endif
