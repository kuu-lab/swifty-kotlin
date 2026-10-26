#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimitiveArrayConstructorCallableReferenceTests {
    @Test
    func genericUpcastPreservesSizeConstructorReferenceType() throws {
        let arrayNames = [
            "BooleanArray", "ByteArray", "CharArray", "DoubleArray", "FloatArray", "IntArray",
            "LongArray", "ShortArray", "UByteArray", "UIntArray", "ULongArray", "UShortArray",
        ]
        let factories = arrayNames.map { arrayName in
            "fun make\(arrayName)(): \(arrayName) = upcast<(Int) -> \(arrayName)>(::\(arrayName))(10)"
        }.joined(separator: "\n")
        let ctx = makeContextFromSource("""
        private fun <T> upcast(value: T): T = value
        \(factories)
        """)
        try runSema(ctx)

        let file = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[0]))
        let sourceErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.primaryRange?.start.file == file
        }
        #expect(sourceErrors.isEmpty, "Unexpected diagnostics: \(sourceErrors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let references = ast.arena.exprs.indices.compactMap { index -> (id: ExprID, name: String, offset: Int)? in
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id), range.start.file == file,
                  case let .callableRef(_, member, _)? = ast.arena.expr(id)
            else {
                return nil
            }
            return (id, ctx.interner.resolve(member), range.start.offset)
        }.sorted { $0.offset < $1.offset }
        #expect(references.map(\.name) == arrayNames)

        for reference in references {
            let arraySymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"), ctx.interner.intern(reference.name),
            ]))
            guard let type = sema.bindings.exprType(for: reference.id),
                  case let .functionType(function) = sema.types.kind(of: type)
            else {
                Issue.record("Expected a function type for ::\(reference.name).")
                continue
            }
            #expect(function.params == [sema.types.intType])
            guard case let .classType(returnType) = sema.types.kind(of: function.returnType) else {
                Issue.record("Expected ::\(reference.name) to return its primitive-array class.")
                continue
            }
            #expect(returnType.classSymbol == arraySymbol)

            guard let chosenCallee = sema.bindings.identifierSymbol(for: reference.id) else {
                Issue.record("Missing callable-reference target for ::\(reference.name).")
                continue
            }
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            #expect(signature.parameterTypes == [sema.types.intType])
            #expect(signature.returnType == function.returnType)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_array_new_checked")
        }
    }
}
#endif
