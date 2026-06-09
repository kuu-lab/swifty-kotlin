@testable import CompilerCore
import XCTest

/// STDLIB-REFLECT-067: Sema inference for KClass kind/modifier boolean members
/// (`isData` / `isSealed` / `isValue`) on both a class-literal receiver and a
/// stored `KClass<T>` variable receiver.
final class ReflectKClassBooleanIntrospectionTests: XCTestCase {
    private func makeSema(source: String) throws -> (SemaModule, StringInterner, CompilationContext) {
        var result: (SemaModule, StringInterner, CompilationContext)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected KClass boolean introspection source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner, ctx)
        }
        return try XCTUnwrap(result)
    }

    func testClassLiteralBooleanMembersInferBoolean() throws {
        let source = """
        data class Point(val x: Int)
        fun isDataOf(): Boolean = Point::class.isData
        fun isSealedOf(): Boolean = Point::class.isSealed
        fun isValueOf(): Boolean = Point::class.isValue
        """
        let (sema, interner, _) = try makeSema(source: source)
        for functionName in ["isDataOf", "isSealedOf", "isValueOf"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(
                signature.returnType,
                sema.types.booleanType,
                "\(functionName) should infer Boolean from a KClass boolean member"
            )
        }
    }

    func testVariableReceiverBooleanMembersInferBoolean() throws {
        let source = """
        import kotlin.reflect.KClass
        data class Point(val x: Int)
        fun isDataOf(k: KClass<Point>): Boolean = k.isData
        fun isSealedOf(k: KClass<Point>): Boolean = k.isSealed
        fun isValueOf(k: KClass<Point>): Boolean = k.isValue
        """
        let (sema, interner, _) = try makeSema(source: source)
        for functionName in ["isDataOf", "isSealedOf", "isValueOf"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(
                signature.returnType,
                sema.types.booleanType,
                "\(functionName) should infer Boolean from a KClass<T> variable boolean member"
            )
        }
    }
}
