extension CallTypeChecker {
    /// Kotlin checks explicit top-level imports before same-package functions.
    /// Keep the import tier when it has an applicable candidate so a more
    /// specific same-package overload cannot outrank it during final selection.
    func preferApplicableExplicitTopLevelImportTier(
        candidates: [SymbolID],
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        calleeName: InternedString?,
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]],
        hasApplicableImplicitMembers: Bool,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        guard !hasApplicableImplicitMembers,
              !args.contains(where: { ctx.ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }),
              let calleeName,
              let file = ctx.currentASTFile
        else {
            return candidates
        }

        let importedPaths = Set(file.imports.compactMap { importDecl -> [InternedString]? in
            guard !importDecl.isWildcard,
                  (importDecl.alias ?? importDecl.path.last) == calleeName
            else {
                return nil
            }
            return importDecl.path
        })
        guard !importedPaths.isEmpty else { return candidates }

        func isTopLevelNonExtensionFunction(_ candidate: SymbolID) -> Bool {
            guard let symbol = ctx.sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  !symbol.flags.contains(.localFunction),
                  let signature = ctx.sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            if let parent = ctx.sema.symbols.parentSymbol(for: candidate),
               ctx.sema.symbols.symbol(parent)?.kind != .package
            {
                return false
            }
            return signature.receiverType == nil
        }

        let importedCandidates = candidates.filter { candidate in
            guard isTopLevelNonExtensionFunction(candidate),
                  let symbol = ctx.sema.symbols.symbol(candidate)
            else {
                return false
            }
            return importedPaths.contains(symbol.fqName)
        }
        let samePackageCandidates = candidates.filter { candidate in
            guard isTopLevelNonExtensionFunction(candidate),
                  let symbol = ctx.sema.symbols.symbol(candidate)
            else {
                return false
            }
            return Array(symbol.fqName.dropLast()) == file.packageFQName
        }
        guard !importedCandidates.isEmpty,
              !samePackageCandidates.isEmpty,
              Set(importedCandidates + samePackageCandidates) == Set(candidates)
        else {
            return candidates
        }

        let callArgs = zip(args, argTypes).map { argument, type in
            let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
            return CallArg.source(
                argument,
                type: type,
                callRange: range,
                ast: ctx.ast,
                signedIntegerLiteral: literal.signed,
                unsignedIntegerLiteral: literal.unsigned
            )
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: callArgs,
            explicitTypeArgs: explicitTypeArgs,
            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
        )
        let probe = ctx.resolver.probeCall(
            candidates: importedCandidates,
            call: call,
            expectedType: overloadResolutionExpectedType(from: expectedType, sema: ctx.sema),
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: candidateArgumentTypes,
            ctx: ctx.sema
        )
        guard !probe.viableCandidates.isEmpty else { return candidates }
        return importedCandidates
    }
}
