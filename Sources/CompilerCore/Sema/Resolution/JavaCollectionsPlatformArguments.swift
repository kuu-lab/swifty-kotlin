extension OverloadResolver {
    func warnJavaCollectionsNullableArguments(
        _ call: CallExpr, expectedType: TypeID?, chosen: SymbolID, ctx: SemaModule
    ) {
        guard let symbol = ctx.symbols.symbol(chosen),
              let signature = ctx.symbols.functionSignature(for: chosen),
              isJavaCollectionsPlatformSignature(symbol.fqName, signature: signature, ctx: ctx),
              let expectedType, case let .classType(expected) = ctx.types.kind(of: expectedType),
              expected.args.count == call.explicitTypeArgs.count
        else { return }
        let narrowsNullableArgument = zip(call.explicitTypeArgs, expected.args).contains { argument, expected in
            guard ctx.types.nullability(of: argument) == .nullable else { return false }
            switch expected {
            case let .invariant(type), let .out(type): return ctx.types.nullability(of: type) == .nonNull
            case .in, .star: return false
            }
        }
        guard narrowsNullableArgument else { return }
        ctx.diagnostics.warning(
            "KSWIFTK-SEMA-0431",
            "Java type mismatch: a nullable type argument is used where a non-null collection element is expected.",
            range: call.range
        )
    }

    /// Kotlin/JVM 2.3.10 keeps these Java mapped arguments flexible even
    /// when a caller explicitly supplies a nullable type argument.
    func javaCollectionsCall(
        _ call: CallExpr, fqName: [InternedString], signature: FunctionSignature, ctx: SemaModule
    ) -> CallExpr {
        guard isJavaCollectionsPlatformSignature(fqName, signature: signature, ctx: ctx) else { return call }
        return CallExpr(
            range: call.range, calleeName: call.calleeName, args: call.args,
            explicitTypeArgs: call.explicitTypeArgs.map { javaCollectionsFlexibleArgument($0, types: ctx.types) },
            dispatchReceiverTypes: call.dispatchReceiverTypes,
            elvisLhsExpectedTypeHint: call.elvisLhsExpectedTypeHint,
            elvisRhsCallResultTypeHint: call.elvisRhsCallResultTypeHint,
            isOperatorCall: call.isOperatorCall
        )
    }

    func javaCollectionsSubstitution(
        _ substitution: [TypeVarID: TypeID], fqName: [InternedString], signature: FunctionSignature, ctx: SemaModule
    ) -> [TypeVarID: TypeID] {
        guard isJavaCollectionsPlatformSignature(fqName, signature: signature, ctx: ctx) else { return substitution }
        return substitution.mapValues { javaCollectionsFlexibleArgument($0, types: ctx.types) }
    }

    private func javaCollectionsFlexibleArgument(_ type: TypeID, types: TypeSystem) -> TypeID {
        guard types.nullability(of: type) == .nullable else { return type }
        if case let .typeParam(parameter) = types.kind(of: type), parameter.capture != nil { return type }
        return types.withNullability(.platformType, for: type)
    }

    private func isJavaCollectionsPlatformSignature(
        _ fqName: [InternedString], signature: FunctionSignature, ctx: SemaModule
    ) -> Bool {
        guard fqName.count == 4, let interner = ctx.interner,
              fqName.prefix(3).map({ interner.resolve($0) }) == ["java", "util", "Collections"],
              ["unmodifiableList", "unmodifiableSet", "unmodifiableMap", "newSetFromMap"].contains(interner.resolve(fqName[3])),
              case let .classType(result) = ctx.types.kind(of: signature.returnType)
        else { return false }
        return result.args.contains { argument in
            guard case let .invariant(type) = argument,
                  case let .typeParam(parameter) = ctx.types.kind(of: type) else { return false }
            return parameter.nullability == .platformType
        }
    }
}
