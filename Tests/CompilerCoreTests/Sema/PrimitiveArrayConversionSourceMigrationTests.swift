#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-1512/KSP-1513: primitive-array and generic-array conversions are bundled
/// Kotlin declarations with private runtime bridges.
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
    func unsignedAndGenericArrayMembersResolveToBundledSource() throws {
        let source = """
        fun exercise(
            ubytes: UByteArray,
            ushorts: UShortArray,
            uints: UIntArray,
            ulongs: ULongArray,
            objects: Array<Int>
        ) {
            val ubyteSize: Int = ubytes.size
            val ubyteCopy: List<UByte> = ubytes.toList()
            val ubyteView: List<UByte> = ubytes.asList()
            val ushortSize: Int = ushorts.size
            val ushortCopy: List<UShort> = ushorts.toList()
            val ushortView: List<UShort> = ushorts.asList()
            val uintSize: Int = uints.size
            val uintCopy: List<UInt> = uints.toList()
            val uintView: List<UInt> = uints.asList()
            val ulongSize: Int = ulongs.size
            val ulongCopy: List<ULong> = ulongs.toList()
            val ulongView: List<ULong> = ulongs.asList()
            val objectSize: Int = objects.size
            val objectCopy: List<Int> = objects.toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected unsigned and generic array members to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let expectedMembers: Set<String> = [
                "UByteArray.size", "UByteArray.toList", "UByteArray.asList",
                "UShortArray.size", "UShortArray.toList", "UShortArray.asList",
                "UIntArray.size", "UIntArray.toList", "UIntArray.asList",
                "ULongArray.size", "ULongArray.toList", "ULongArray.asList",
                "Array.size", "Array.toList",
            ]
            var observedMembers: Set<String> = []

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
                guard expectedMembers.contains(key) else { continue }
                observedMembers.insert(key)
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee), "Expected \(key) to resolve to bundled source")
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected \(key) to have no public runtime link")
                if ctx.interner.resolve(callee) == "size" {
                    #expect(sema.bindings.exprType(for: exprID) == sema.types.intType)
                }
            }

            #expect(observedMembers == expectedMembers, "Unexpected unsigned/generic array members: \(observedMembers)")
        }
    }
}
#endif
