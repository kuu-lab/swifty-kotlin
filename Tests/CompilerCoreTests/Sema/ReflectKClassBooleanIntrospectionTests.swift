#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-REFLECT-067: Sema inference for KClass kind/modifier boolean members
/// (`isData` / `isSealed` / `isValue`) on both a class-literal receiver and a
/// stored `KClass<T>` variable receiver.
@Suite
struct ReflectKClassBooleanIntrospectionTests {
    @Test func testKClassBooleanIntrospectionSourceResolution() throws {
        let sources: [String] = [
            """
            package sample0
            data class Point(val x: Int)

            fun isDataOf(): Boolean = Point::class.isData
            fun isSealedOf(): Boolean = Point::class.isSealed
            fun isValueOf(): Boolean = Point::class.isValue
            """,
            """
            package sample1
            import kotlin.reflect.KClass
            data class Point(val x: Int)

            fun isDataOf(k: KClass<Point>): Boolean = k.isData
            fun isSealedOf(k: KClass<Point>): Boolean = k.isSealed
            fun isValueOf(k: KClass<Point>): Boolean = k.isValue
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for (index, _) in sources.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    !pathDiagnostics.contains(where: { $0.severity == .error }),
                    "Expected KClass boolean introspection source to type-check, got: \(pathDiagnostics)"
                )
            }

            for functionName in ["isDataOf", "isSealedOf", "isValueOf"] {
                let symbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern(functionName),
                ]))
                let symbolFromVariable = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample1"),
                    interner.intern(functionName),
                ]))
                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                let signatureFromVariable = try #require(sema.symbols.functionSignature(for: symbolFromVariable))
                #expect(
                    signature.returnType == sema.types.booleanType,
                    "\(functionName) should infer Boolean from a KClass boolean member"
                )
                #expect(
                    signatureFromVariable.returnType == sema.types.booleanType,
                    "\(functionName) should infer Boolean from a KClass<T> variable boolean member"
                )
            }
        }
    }
}
#endif
