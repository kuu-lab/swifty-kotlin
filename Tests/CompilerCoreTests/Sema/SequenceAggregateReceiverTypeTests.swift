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
        fun doubleSum(values: Sequence<Double>): Double = values.sum()
        fun floatSum(values: Sequence<Float>): Float = values.sum()
        fun longSum(values: Sequence<Long>): Long = values.sum()
        fun doubleAverage(values: Sequence<Double>): Double = values.average()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0024"
        }
        #expect(
            diagnostics.count == 4,
            "Expected one unresolved aggregate diagnostic per unsupported call, got \(ctx.diagnostics.diagnostics)"
        )

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
        #expect(calls.count == 4, "Expected four user Sequence aggregate calls, got \(calls)")
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
