// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallLowerer {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func tryLowerStringBuilderMemberCall(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        requireNonNullableReceiverForConstFold: Bool,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // StringBuilder member calls with 1 arg (STDLIB-255/256/257)
        if args.count == 1 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.append {
                    // Dispatch append(value) to the typed overload based on the argument type.
                    {
                        let argType = normalizedArgIDs.first.flatMap { arena.exprType($0) }
                        let nonNull = argType.map { sema.types.makeNonNullable($0) }
                        if nonNull == sema.types.booleanType { return "kk_string_builder_append_bool" }
                        if nonNull == sema.types.charType { return "kk_string_builder_append_char" }
                        if nonNull == sema.types.make(.primitive(.float, .nonNull)) { return "kk_string_builder_append_float" }
                        if nonNull == sema.types.make(.primitive(.double, .nonNull)) { return "kk_string_builder_append_double" }
                        return "kk_string_builder_append_obj"
                    }()
                } else if calleeName == sbNames.appendLine {
                    "kk_string_builder_append_line_obj"
                } else if calleeName == sbNames.deleteCharAt {
                    "kk_string_builder_deleteCharAt"
                } else if calleeName == sbNames.deleteAt {
                    "kk_string_builder_deleteAt"
                } else if calleeName == sbNames.get {
                    "kk_string_builder_get"
                } else if calleeName == sbNames.ensureCapacity {
                    "kk_string_builder_ensureCapacity"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder 2-arg member calls (STDLIB-255/256/257)
        if args.count == 2 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.insert {
                    {
                        let argType = normalizedArgIDs.dropFirst().first.flatMap { arena.exprType($0) }
                        let nonNull = argType.map { sema.types.makeNonNullable($0) }
                        if nonNull == sema.types.make(.primitive(.boolean, .nonNull)) { return "kk_string_builder_insert_bool" }
                        if nonNull == sema.types.make(.primitive(.char, .nonNull)) { return "kk_string_builder_insert_char" }
                        if nonNull == sema.types.make(.primitive(.float, .nonNull)) { return "kk_string_builder_insert_float" }
                        if nonNull == sema.types.make(.primitive(.double, .nonNull)) { return "kk_string_builder_insert_double" }
                        return "kk_string_builder_insert_obj"
                    }()
                } else if calleeName == sbNames.delete {
                    "kk_string_builder_delete_obj"
                } else if calleeName == sbNames.deleteRange {
                    "kk_string_builder_deleteRange"
                } else if calleeName == sbNames.sbSet {
                    // STDLIB-TEXT-FN-064: operator fun set(index, value) desugars to setCharAt
                    "kk_string_builder_setCharAt"
                } else if calleeName == sbNames.setCharAt {
                    "kk_string_builder_setCharAt"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder 3-arg member calls (STDLIB-580 / STDLIB-STR-123)
        if args.count == 3 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.appendRange {
                    "kk_string_builder_appendRange_obj_flat"
                } else if calleeName == sbNames.replace {
                    "kk_string_builder_replace_obj"
                } else if calleeName == sbNames.setRange {
                    "kk_string_builder_setRange"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder 4-arg member calls (STDLIB-TEXT-BUILDER-003)
        if args.count == 4 {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.insertRange {
                    "kk_string_builder_insertRange_obj"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID] + normalizedArgIDs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        if args.isEmpty {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            // StringBuilder 0-arg member calls and properties (STDLIB-255/256/257)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let sbNames = KnownCompilerNames(interner: interner)
                let runtimeCallee: String? = if calleeName == sbNames.toString {
                    "kk_string_builder_toString"
                } else if calleeName == sbNames.clear {
                    "kk_string_builder_clear"
                } else if calleeName == sbNames.reverse {
                    "kk_string_builder_reverse"
                } else if calleeName == sbNames.appendLine {
                    "kk_string_builder_append_line_noarg_obj"
                } else if calleeName == sbNames.length {
                    "kk_string_builder_length_prop"
                } else if calleeName == sbNames.capacity {
                    "kk_string_builder_capacity"
                } else if calleeName == sbNames.trimToSize {
                    "kk_string_builder_trimToSize"
                } else {
                    nil
                }
                if let runtimeCallee {
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern(runtimeCallee),
                        arguments: [loweredReceiverID],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
        }

        // StringBuilder: append(vararg value: String? / Any?) (STDLIB-TEXT-EDGE-012)
        if interner.resolve(calleeName) == "append",
           let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
           sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_builder_append_vararg_obj"
        {
            let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
            let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
            if isStringBuilderLikeType(nonNullReceiverType, sema: sema, interner: interner) {
                let intType = sema.types.make(.primitive(.int, .nonNull))
                let packedArgs: KIRExprID
                if loweredArgIDs.count == 1, args.first?.isSpread == true {
                    packedArgs = loweredArgIDs[0]
                } else {
                    packedArgs = driver.callSupportLowerer.packVarargArguments(
                        argIndices: Array(loweredArgIDs.indices),
                        providedArguments: loweredArgIDs,
                        spreadFlags: args.map(\.isSpread),
                        arena: arena,
                        interner: interner,
                        intType: intType,
                        anyType: sema.types.nullableAnyType,
                        instructions: &instructions
                    )
                }
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_string_builder_append_vararg_obj"),
                    arguments: [loweredReceiverID, packedArgs],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
        }

        return nil
    }
}
