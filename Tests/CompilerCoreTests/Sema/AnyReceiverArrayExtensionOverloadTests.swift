#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AnyReceiverArrayExtensionOverloadTests {
    @Test
    func staticallyAnyReceiverSelectsAnyExtension() throws {
        let source = """
        fun <T> Array<T>.getLength(): Int = size
        fun Any.getLength(): Int = if (this is Array<*>) size else -1

        fun check(array1: Array<String>, array2: Any): Int =
            array1.getLength() + array2.getLength()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var calls: [(offset: Int, receiverType: TypeID, declaredReceiverType: TypeID)] = []
            var sizeReceiverTypes: [(offset: Int, type: TypeID)] = []
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                if case let .nameRef(name, _) = ast.arena.expr(id),
                   ctx.interner.resolve(name) == "size",
                   let receiverType = sema.bindings.implicitReceiverMemberReceiverType(for: id),
                   let range = ast.arena.exprRange(id),
                   ctx.sourceManager.origin(of: range.start.file) == .user
                {
                    sizeReceiverTypes.append((range.start.offset, receiverType))
                }
                guard case let .memberCall(receiver, callee, _, _, _) = ast.arena.expr(id),
                      ctx.interner.resolve(callee) == "getLength",
                      let range = ast.arena.exprRange(id),
                      ctx.sourceManager.origin(of: range.start.file) == .user,
                      let receiverType = sema.bindings.exprType(for: receiver),
                      let chosen = sema.bindings.callBinding(for: id)?.chosenCallee,
                      let declaredReceiverType = sema.symbols.functionSignature(for: chosen)?.receiverType
                else {
                    continue
                }
                calls.append((range.start.offset, receiverType, declaredReceiverType))
            }
            calls.sort { $0.offset < $1.offset }

            #expect(calls.count == 2)
            guard calls.count == 2 else { return }
            #expect(calls[0].receiverType != sema.types.anyType)
            #expect(calls[0].declaredReceiverType != sema.types.anyType)
            #expect(calls[1].receiverType == sema.types.anyType)
            #expect(calls[1].declaredReceiverType == sema.types.anyType)

            sizeReceiverTypes.sort { $0.offset < $1.offset }
            #expect(sizeReceiverTypes.count == 2)
            guard sizeReceiverTypes.count == 2 else { return }
            let classifier = ReceiverClassifier(sema: sema, interner: ctx.interner)
            #expect(classifier.isArrayLikeType(sizeReceiverTypes[0].type))
            #expect(classifier.isArrayLikeType(sizeReceiverTypes[1].type))
        }
    }
}
#endif
