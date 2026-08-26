#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1512: signed primitive-array `size` / `toList` are bundled Kotlin
/// declarations, while unsigned primitive arrays and Array<T> retain their
/// synthetic runtime-backed members for KSP-1513.
@Suite(.serialized)
struct PrimitiveArrayConversionSourceMigrationTests {
    @Test
    func signedPrimitiveArraySizeAndToListResolveToBundledSource() throws {
        let source = """
        fun exercise(
            ints: IntArray,
            longs: LongArray,
            shorts: ShortArray,
            bytes: ByteArray,
            chars: CharArray,
            booleans: BooleanArray,
            doubles: DoubleArray,
            floats: FloatArray
        ) {
            ints.size
            ints.toList()
            longs.size
            longs.toList()
            shorts.size
            shorts.toList()
            bytes.size
            bytes.toList()
            chars.size
            chars.toList()
            booleans.size
            booleans.toList()
            doubles.size
            doubles.toList()
            floats.size
            floats.toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected signed primitive-array members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let signedTypes: Set<String> = [
                "IntArray", "LongArray", "ShortArray", "ByteArray",
                "CharArray", "BooleanArray", "DoubleArray", "FloatArray",
            ]

            for memberName in ["size", "toList"] {
                var calls: [(ExprID, SymbolID, String)] = []
                for index in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(index))
                    guard case let .memberCall(receiver, callee, _, args, range) = ast.arena.expr(exprID),
                          ctx.interner.resolve(callee) == memberName,
                          args.isEmpty,
                          ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") == false,
                          let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                          let receiverType = sema.bindings.exprType(for: receiver),
                          let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                    else { continue }
                    calls.append((exprID, chosenCallee, ctx.interner.resolve(receiverSymbol.name)))
                }

                #expect(calls.count == signedTypes.count, "Expected one user call for each signed array type: \(memberName)")
                let receiverNames = Set(calls.map { $0.2 })
                #expect(receiverNames == signedTypes, "Expected all signed array receiver types for \(memberName), got: \(receiverNames)")
                for (exprID, chosenCallee, _) in calls {
                    #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected \(memberName) call \(exprID) to be source-backed")
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected \(memberName) call \(exprID) to have no public runtime link")
                    if memberName == "size" {
                        #expect(sema.bindings.exprType(for: exprID) == sema.types.intType)
                    }
                }
            }
        }
    }

    @Test
    func unsignedAndGenericArrayMembersRetainSyntheticRuntimeLinks() throws {
        let source = """
        fun exercise(unsigned: UIntArray, objects: Array<Int>) {
            unsigned.size
            unsigned.toList()
            objects.size
            objects.toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected residual synthetic array members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedLinks: [String: String] = [
                "UIntArray.size": "kk_uIntArray_size",
                "UIntArray.toList": "kk_uIntArray_toList",
                "Array.size": "kk_array_size",
                "Array.toList": "kk_array_toList",
            ]
            var observedLinks: [String: String] = [:]

            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard case let .memberCall(receiver, callee, _, args, range) = ast.arena.expr(exprID),
                      args.isEmpty,
                      ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_") == false,
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                          ?? sema.bindings.identifierSymbol(for: exprID),
                      let receiverType = sema.bindings.exprType(for: receiver),
                      let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema)
                else { continue }
                let key = "\(ctx.interner.resolve(receiverSymbol.name)).\(ctx.interner.resolve(callee))"
                guard expectedLinks[key] != nil else { continue }
                observedLinks[key] = sema.symbols.externalLinkName(for: chosenCallee)
                #expect(!sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected \(key) to retain its synthetic declaration")
            }

            #expect(observedLinks == expectedLinks, "Unexpected residual array links: \(observedLinks)")
        }
    }
}
#endif
