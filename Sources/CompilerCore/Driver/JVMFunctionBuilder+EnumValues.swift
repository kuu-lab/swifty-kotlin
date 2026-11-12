import Foundation

extension JVMFunctionBuilder {
    func enumValuesCall(_ args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard args.isEmpty,
              let type = program.sema.bindings.callBinding(for: id)?.substitutedTypeArguments.first else {
            return nil
        }
        let actual = program.specialized(type)
        if case let .classType(enumType) = program.sema.types.kind(of: actual),
           enumType.nullability == .nonNull,
           program.sema.symbols.symbol(enumType.classSymbol)?.kind == .enumClass {
            let owner = try program.className(enumType.classSymbol)
            let resultType = try program.expressionType(id)
            return JVMIntrinsicResult(value: try jdkCall(owner, "values", [], resultType, resolved: resultType))
        }

        // A generic inline body is emitted once with its reified parameter erased.
        // Let the normal inline path expand the intrinsic stub's unsupported body;
        // specialized call sites are expanded above.
        return nil
    }
}
