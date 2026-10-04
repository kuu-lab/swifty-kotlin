#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-597: Sequence aggregate source binding must not select a monomorphic
/// overload for a receiver with a different element type.
@Suite
struct SequenceAggregateReceiverTypeTests {
    @Test
    func unsupportedNumericSequenceAggregatesProduceDiagnostics() throws {
        let source = """
        fun byteSum(values: Sequence<Byte>): Int = values.sum()
        fun shortSum(values: Sequence<Short>): Int = values.sum()
        fun doubleAverage(values: Sequence<Double>): Double = values.average()
        fun floatAverage(values: Sequence<Float>): Float = values.average()
        fun badSumOfSelector(values: Sequence<String>): String = values.sumOf { it }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0024"
        }
        #expect(
            diagnostics.count == 5,
            "Expected one unresolved aggregate diagnostic per unsupported call, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let calls = memberCalls(
            named: ["sum", "average", "sumOf"],
            in: ast,
            interner: ctx.interner,
            userFileID: userFileID
        )
        #expect(calls.count == 5, "Expected five user Sequence aggregate calls, got \(calls)")
        #expect(calls.allSatisfy { sema.bindings.callBinding(for: $0) == nil })
    }

    @Test
    func intSequenceAggregatesKeepTheirSourceBindings() throws {
        let source = """
        fun intSum(values: Sequence<Int>): Int = values.sum()
        fun intAverage(values: Sequence<Int>): Double = values.average()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected Int Sequence aggregates to resolve, got \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let calls = memberCalls(
            named: ["sum", "average"],
            in: ast,
            interner: ctx.interner,
            userFileID: userFileID
        )
        #expect(calls.count == 2, "Expected two user Sequence aggregate calls, got \(calls)")

        for callID in calls {
            let binding = try #require(sema.bindings.callBinding(for: callID))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)

            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            let name = try #require(memberCallName(callID, in: ast, interner: ctx.interner))
            #expect(signature.returnType == (
                name == "sum"
                    ? sema.types.intType
                    : sema.types.doubleType
            ))
            let receiver = try #require(signature.receiverType)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver),
                  let firstArgument = receiverClass.args.first
            else {
                Issue.record("Expected a concrete Sequence receiver on the selected aggregate overload.")
                continue
            }
            let receiverElement: TypeID? = switch firstArgument {
            case let .invariant(type), let .out(type), let .in(type): type
            case .star: nil
            }
            #expect(receiverElement == sema.types.intType)
        }
    }

    /// KSP-1359: every monomorphic Sequence sum() overload and the three
    /// sumOf selector-return-type overloads resolve to bundled Kotlin source
    /// declarations, each with its declared return type.
    @Test
    func sequenceSumFamilyBindsSourceOverloadsWithDeclaredReturnTypes() throws {
        let source = """
        fun doubleSum(values: Sequence<Double>): Double = values.sum()
        fun floatSum(values: Sequence<Float>): Float = values.sum()
        fun longSum(values: Sequence<Long>): Long = values.sum()
        fun ubyteSum(values: Sequence<UByte>): UInt = values.sum()
        fun ushortSum(values: Sequence<UShort>): UInt = values.sum()
        fun uintSum(values: Sequence<UInt>): UInt = values.sum()
        fun ulongSum(values: Sequence<ULong>): ULong = values.sum()
        fun sumOfLong(values: Sequence<String>): Long = values.sumOf { it.length.toLong() }
        fun sumOfUInt(values: Sequence<String>): UInt = values.sumOf { it.length.toUInt() }
        fun sumOfULong(values: Sequence<String>): ULong = values.sumOf { it.length.toULong() }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected the Sequence sum-family to resolve, got \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let userFileID = try #require(ctx.sourceManager.fileIDs().first {
            ctx.sourceManager.origin(of: $0) == .user
        })
        let calls = memberCalls(
            named: ["sum", "sumOf"],
            in: ast,
            interner: ctx.interner,
            userFileID: userFileID
        )
        #expect(calls.count == 10, "Expected ten user Sequence sum-family calls, got \(calls)")

        let expectedReturns: [TypeID] = [
            sema.types.doubleType,
            sema.types.floatType,
            sema.types.longType,
            sema.types.uintType,
            sema.types.uintType,
            sema.types.uintType,
            sema.types.ulongType,
            sema.types.longType,
            sema.types.uintType,
            sema.types.ulongType
        ]
        for (callID, expectedReturn) in zip(calls, expectedReturns) {
            let binding = try #require(sema.bindings.callBinding(for: callID))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)

            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.returnType == expectedReturn)
        }
    }
}

private func memberCalls(
    named names: Set<String>,
    in ast: ASTModule,
    interner: StringInterner,
    userFileID: FileID
) -> [ExprID] {
    ast.arena.exprs.indices.compactMap { index in
        let id = ExprID(rawValue: Int32(index))
        guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id),
              names.contains(interner.resolve(callee)),
              let range = ast.arena.exprRange(id),
              range.start.file == userFileID
        else {
            return nil
        }
        return id
    }
}

private func memberCallName(_ id: ExprID, in ast: ASTModule, interner: StringInterner) -> String? {
    guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id) else {
        return nil
    }
    return interner.resolve(callee)
}
#endif
