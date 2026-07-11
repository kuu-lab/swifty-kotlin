enum CollectionLiteralTrackedStaticTypeKind {
    case list
    case set
    case map
    case array
    case sequence
    case string
}

extension CollectionLiteralLoweringSupport {
    func makeWindowedTransformBridgeArguments(
        receiver: KIRExprID,
        windowedArguments: [KIRExprID],
        module: KIRModule,
        sema: SemaModule?,
        loweredBody: inout [KIRInstruction]
    ) -> [KIRExprID]? {
        guard windowedArguments.count >= 2 else {
            return nil
        }

        func zeroLiteral() -> KIRExprID {
            let expr = module.arena.appendExpr(.intLiteral(0), type: nil)
            loweredBody.append(.constValue(result: expr, value: .intLiteral(0)))
            return expr
        }

        func oneLiteral() -> KIRExprID {
            let expr = module.arena.appendExpr(.intLiteral(1), type: nil)
            loweredBody.append(.constValue(result: expr, value: .intLiteral(1)))
            return expr
        }

        func isCallableArgument(_ exprID: KIRExprID) -> Bool {
            if module.arena.callableValueInfoByExprID[exprID] != nil {
                return true
            }
            if let sema,
               let type = module.arena.exprType(exprID),
               case .functionType = sema.types.kind(of: sema.types.makeNonNullable(type))
            {
                return true
            }
            if case .externSymbolAddress? = module.arena.expr(exprID) {
                return true
            }
            return false
        }

        guard let lambdaIndex = windowedArguments.indices.reversed().first(where: {
            $0 > 0 && isCallableArgument(windowedArguments[$0])
        }) else {
            return nil
        }

        let valueArguments = Array(windowedArguments[..<lambdaIndex])
        guard (1...3).contains(valueArguments.count) else {
            return nil
        }

        let closureRawID = if lambdaIndex + 1 < windowedArguments.count {
            windowedArguments[lambdaIndex + 1]
        } else {
            zeroLiteral()
        }

        let sizeID = valueArguments[0]
        let stepID = valueArguments.count >= 2 ? valueArguments[1] : oneLiteral()
        let partialID = valueArguments.count >= 3 ? valueArguments[2] : zeroLiteral()

        return [receiver, sizeID, stepID, partialID, windowedArguments[lambdaIndex], closureRawID]
    }

    func classifyTrackedExprByStaticType(
        _ expr: KIRExprID,
        module: KIRModule,
        sema: SemaModule?,
        interner: StringInterner,
        state: inout CollectionRewriteState
    ) {
        let raw = expr.rawValue
        if state.listExprIDs.contains(raw) || state.setExprIDs.contains(raw)
            || state.mapExprIDs.contains(raw) || state.arrayExprIDs.contains(raw)
            || state.sequenceExprIDs.contains(raw) || state.stringExprIDs.contains(raw)
        {
            return
        }
        guard let sema,
              let typeID = module.arena.exprType(expr)
        else {
            return
        }
        let nonNullType = sema.types.makeNonNullable(typeID)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return
        }
        switch trackedStaticTypeKind(of: symbol, interner: interner) {
        case .list:
            state.listExprIDs.insert(raw)
        case .set:
            state.setExprIDs.insert(raw)
        case .map:
            state.mapExprIDs.insert(raw)
        case .array:
            state.arrayExprIDs.insert(raw)
        case .sequence:
            state.sequenceExprIDs.insert(raw)
        case .string:
            state.stringExprIDs.insert(raw)
        case nil:
            break
        }
    }

    func trackedStaticTypeKind(
        of symbol: SemanticSymbol,
        interner: StringInterner
    ) -> CollectionLiteralTrackedStaticTypeKind? {
        let kotlinPackage = [interner.intern("kotlin")]
        let collectionsPackage = kotlinPackage + [interner.intern("collections")]
        let sequencesPackage = kotlinPackage + [interner.intern("sequences")]

        let listNames = [
            interner.intern("List"),
            interner.intern("MutableList"),
            interner.intern("ArrayList"),
            interner.intern("AbstractList"),
            interner.intern("AbstractMutableList"),
        ]
        if matchesStdlibType(symbol, package: collectionsPackage, simpleNames: listNames) {
            return .list
        }

        let setNames = [
            interner.intern("Set"),
            interner.intern("MutableSet"),
            interner.intern("HashSet"),
            interner.intern("LinkedHashSet"),
            interner.intern("AbstractSet"),
            interner.intern("AbstractMutableSet"),
        ]
        if matchesStdlibType(symbol, package: collectionsPackage, simpleNames: setNames) {
            return .set
        }

        let mapNames = [
            interner.intern("Map"),
            interner.intern("MutableMap"),
            interner.intern("HashMap"),
            interner.intern("LinkedHashMap"),
            interner.intern("AbstractMap"),
            interner.intern("AbstractMutableMap"),
        ]
        if matchesStdlibType(symbol, package: collectionsPackage, simpleNames: mapNames) {
            return .map
        }

        let arrayNames = [
            interner.intern("Array"),
            interner.intern("IntArray"),
            interner.intern("LongArray"),
            interner.intern("DoubleArray"),
            interner.intern("FloatArray"),
            interner.intern("BooleanArray"),
            interner.intern("CharArray"),
            interner.intern("ByteArray"),
            interner.intern("ShortArray"),
            interner.intern("UByteArray"),
            interner.intern("UShortArray"),
            interner.intern("UIntArray"),
            interner.intern("ULongArray"),
        ]
        if matchesStdlibType(symbol, package: kotlinPackage, simpleNames: arrayNames) {
            return .array
        }

        if matchesStdlibType(symbol, package: sequencesPackage, simpleNames: [interner.intern("Sequence")]) {
            return .sequence
        }

        if matchesStdlibType(symbol, package: kotlinPackage, simpleNames: [interner.intern("String")]) {
            return .string
        }

        return nil
    }

    private func matchesStdlibType(
        _ symbol: SemanticSymbol,
        package: [InternedString],
        simpleNames: [InternedString]
    ) -> Bool {
        if symbol.fqName.isEmpty {
            return symbol.flags.contains(.synthetic) && simpleNames.contains(symbol.name)
        }
        guard symbol.fqName.count == package.count + 1,
              let simpleName = symbol.fqName.last,
              simpleNames.contains(simpleName)
        else {
            return false
        }
        return Array(symbol.fqName.dropLast()) == package
    }
}
