/// Translates one file-local AST into the module namespace. Negative sentinel
/// IDs stay invalid; source locations, declaration order and literal data stay intact.
struct ASTIDRemapper {
    let declOffset: Int32
    let exprOffset: Int32
    let typeRefOffset: Int32
    let sharedStringCount: Int
    let addedStrings: [InternedString]

    func remap(_ id: DeclID) -> DeclID {
        id.rawValue < 0 ? id : DeclID(rawValue: id.rawValue + declOffset)
    }

    func remap(_ id: ExprID) -> ExprID {
        id.rawValue < 0 ? id : ExprID(rawValue: id.rawValue + exprOffset)
    }

    func remap(_ id: TypeRefID) -> TypeRefID {
        id.rawValue < 0 ? id : TypeRefID(rawValue: id.rawValue + typeRefOffset)
    }

    func remap(_ id: InternedString) -> InternedString {
        let index = Int(id.rawValue)
        return index < sharedStringCount ? id : addedStrings[index - sharedStringCount]
    }

    func remap(_ token: Token) -> Token {
        Token(kind: remap(token.kind), range: token.range,
              leadingTrivia: token.leadingTrivia, trailingTrivia: token.trailingTrivia)
    }

    private func remap(_ kind: TokenKind) -> TokenKind {
        switch kind {
        case let .identifier(name): .identifier(remap(name))
        case let .backtickedIdentifier(name): .backtickedIdentifier(remap(name))
        case let .stringSegment(value): .stringSegment(remap(value))
        case let .missing(expected): .missing(expected: remap(expected))
        default: kind
        }
    }

    func remap(_ value: AnnotationNode) -> AnnotationNode {
        AnnotationNode(
            name: value.name,
            arguments: value.arguments,
            useSiteTarget: value.useSiteTarget,
            constructionTokens: value.constructionTokens.map { $0.map { remap($0) } }
        )
    }

    func remap(_ value: ImportDecl) -> ImportDecl {
        ImportDecl(
            range: value.range,
            path: value.path.map { remap($0) },
            alias: value.alias.map { remap($0) },
            isWildcard: value.isWildcard
        )
    }

    func remap(_ value: ConstructorDelegationCall) -> ConstructorDelegationCall {
        ConstructorDelegationCall(
            kind: value.kind,
            args: value.args.map { remap($0) },
            range: value.range
        )
    }

    func remap(_ value: ConstructorDecl) -> ConstructorDecl {
        ConstructorDecl(
            range: value.range,
            modifiers: value.modifiers,
            annotations: value.annotations.map { remap($0) },
            valueParams: value.valueParams.map { remap($0) },
            delegationCall: value.delegationCall.map { remap($0) },
            body: remap(value.body)
        )
    }

    func remap(_ value: SuperTypeEntry) -> SuperTypeEntry {
        SuperTypeEntry(
            typeRef: remap(value.typeRef),
            delegateExpression: value.delegateExpression.map { remap($0) },
            constructorArgs: value.constructorArgs.map { remap($0) },
            hasConstructorCallSyntax: value.hasConstructorCallSyntax,
            range: value.range
        )
    }

    func remap(_ value: ClassDecl) -> ClassDecl {
        ClassDecl(
            range: value.range,
            name: remap(value.name),
            modifiers: value.modifiers,
            annotations: value.annotations.map { remap($0) },
            isInner: value.isInner,
            typeParams: value.typeParams.map { remap($0) },
            primaryConstructorParams: value.primaryConstructorParams.map { remap($0) },
            primaryConstructorModifiers: value.primaryConstructorModifiers,
            primaryConstructorAnnotations: value.primaryConstructorAnnotations.map { remap($0) },
            hasPrimaryConstructorSyntax: value.hasPrimaryConstructorSyntax,
            superTypeEntries: value.superTypeEntries.map { remap($0) },
            nestedTypeAliases: value.nestedTypeAliases.map { remap($0) },
            enumEntries: value.enumEntries.map { remap($0) },
            initBlocks: value.initBlocks.map { remap($0) },
            classBodyInitOrder: value.classBodyInitOrder,
            secondaryConstructors: value.secondaryConstructors.map { remap($0) },
            memberFunctions: value.memberFunctions.map { remap($0) },
            memberProperties: value.memberProperties.map { remap($0) },
            nestedClasses: value.nestedClasses.map { remap($0) },
            nestedObjects: value.nestedObjects.map { remap($0) },
            companionObject: value.companionObject.map { remap($0) },
            companionBlockObject: value.companionBlockObject.map { remap($0) }
        )
    }

    func remap(_ value: InterfaceDecl) -> InterfaceDecl {
        InterfaceDecl(
            range: value.range,
            name: remap(value.name),
            modifiers: value.modifiers,
            annotations: value.annotations.map { remap($0) },
            isFunInterface: value.isFunInterface,
            typeParams: value.typeParams.map { remap($0) },
            superTypes: value.superTypes.map { remap($0) },
            superTypeEntries: value.superTypeEntries.map { remap($0) },
            nestedTypeAliases: value.nestedTypeAliases.map { remap($0) },
            memberFunctions: value.memberFunctions.map { remap($0) },
            memberProperties: value.memberProperties.map { remap($0) },
            nestedClasses: value.nestedClasses.map { remap($0) },
            nestedObjects: value.nestedObjects.map { remap($0) },
            companionObject: value.companionObject.map { remap($0) },
            companionBlockObject: value.companionBlockObject.map { remap($0) }
        )
    }

    func remap(_ value: ObjectDecl) -> ObjectDecl {
        ObjectDecl(
            range: value.range,
            name: remap(value.name),
            modifiers: value.modifiers,
            annotations: value.annotations.map { remap($0) },
            superTypes: value.superTypes.map { remap($0) },
            superTypeEntries: value.superTypeEntries.map { remap($0) },
            superTypeConstructorArgs: value.superTypeConstructorArgs.map { remap($0) },
            nestedTypeAliases: value.nestedTypeAliases.map { remap($0) },
            initBlocks: value.initBlocks.map { remap($0) },
            classBodyInitOrder: value.classBodyInitOrder,
            memberFunctions: value.memberFunctions.map { remap($0) },
            memberProperties: value.memberProperties.map { remap($0) },
            nestedClasses: value.nestedClasses.map { remap($0) },
            nestedObjects: value.nestedObjects.map { remap($0) }
        )
    }

    func remap(_ value: FunDecl) -> FunDecl {
        FunDecl(
            range: value.range,
            name: remap(value.name),
            modifiers: value.modifiers,
            annotations: value.annotations.map { remap($0) },
            typeParams: value.typeParams.map { remap($0) },
            whereClauseRange: value.whereClauseRange,
            receiverType: value.receiverType.map { remap($0) },
            contextReceivers: value.contextReceivers.map { remap($0) },
            valueParams: value.valueParams.map { remap($0) },
            returnType: value.returnType.map { remap($0) },
            body: remap(value.body),
            isSuspend: value.isSuspend,
            isInline: value.isInline,
            isTailrec: value.isTailrec,
            isScriptEntryPoint: value.isScriptEntryPoint
        )
    }

    func remap(_ value: ContextReceiverDecl) -> ContextReceiverDecl {
        ContextReceiverDecl(
            name: value.name.map { remap($0) },
            type: remap(value.type),
            isContextParameter: value.isContextParameter,
            isCrossinline: value.isCrossinline,
            isNoinline: value.isNoinline
        )
    }

    func remap(_ value: PropertyAccessorDecl) -> PropertyAccessorDecl {
        PropertyAccessorDecl(
            range: value.range,
            kind: value.kind,
            annotations: value.annotations.map { remap($0) },
            visibility: value.visibility,
            isInline: value.isInline,
            parameterName: value.parameterName.map { remap($0) },
            returnType: value.returnType.map { remap($0) },
            body: remap(value.body)
        )
    }

    func remap(_ value: ExplicitBackingField) -> ExplicitBackingField {
        ExplicitBackingField(
            type: value.type.map { remap($0) },
            initializer: value.initializer.map { remap($0) }
        )
    }

    func remap(_ value: PropertyDecl) -> PropertyDecl {
        PropertyDecl(
            range: value.range,
            name: remap(value.name),
            modifiers: value.modifiers,
            annotations: value.annotations.map { remap($0) },
            typeParams: value.typeParams.map { remap($0) },
            type: value.type.map { remap($0) },
            isVar: value.isVar,
            initializer: value.initializer.map { remap($0) },
            getter: value.getter.map { remap($0) },
            setter: value.setter.map { remap($0) },
            delegateExpression: value.delegateExpression.map { remap($0) },
            delegateBody: value.delegateBody.map { remap($0) },
            delegateBodyParams: value.delegateBodyParams.map { remap($0) },
            receiverType: value.receiverType.map { remap($0) },
            contextReceivers: value.contextReceivers.map { remap($0) },
            isSynthesizedPrimaryConstructorProperty: value.isSynthesizedPrimaryConstructorProperty,
            explicitBackingField: value.explicitBackingField.map { remap($0) }
        )
    }

    func remap(_ value: TypeAliasDecl) -> TypeAliasDecl {
        TypeAliasDecl(
            range: value.range,
            name: remap(value.name),
            modifiers: value.modifiers,
            annotations: value.annotations.map { remap($0) },
            typeParams: value.typeParams.map { remap($0) },
            underlyingType: value.underlyingType.map { remap($0) }
        )
    }

    func remap(_ value: EnumEntryDecl) -> EnumEntryDecl {
        EnumEntryDecl(
            range: value.range,
            name: remap(value.name),
            annotations: value.annotations.map { remap($0) },
            constructorArgs: value.constructorArgs.map { remap($0) },
            initBlocks: value.initBlocks.map { remap($0) },
            classBodyInitOrder: value.classBodyInitOrder,
            memberFunctions: value.memberFunctions.map { remap($0) },
            memberProperties: value.memberProperties.map { remap($0) },
            nestedClasses: value.nestedClasses.map { remap($0) }
        )
    }

    func remap(_ value: TypeParamDecl) -> TypeParamDecl {
        TypeParamDecl(
            name: remap(value.name),
            variance: value.variance,
            isReified: value.isReified,
            upperBounds: value.upperBounds.map { remap($0) },
            annotations: value.annotations.map { remap($0) }
        )
    }

    func remap(_ value: ValueParamDecl) -> ValueParamDecl {
        ValueParamDecl(
            name: remap(value.name),
            type: value.type.map { remap($0) },
            isProperty: value.isProperty,
            isMutableProperty: value.isMutableProperty,
            isOverrideProperty: value.isOverrideProperty,
            isOpenProperty: value.isOpenProperty,
            isActualProperty: value.isActualProperty,
            propertyVisibilityModifiers: value.propertyVisibilityModifiers,
            hasDefaultValue: value.hasDefaultValue,
            isVararg: value.isVararg,
            varargRange: value.varargRange,
            isCrossinline: value.isCrossinline,
            isNoinline: value.isNoinline,
            defaultValue: value.defaultValue.map { remap($0) },
            annotations: value.annotations.map { remap($0) }
        )
    }

    func remap(_ value: WhenBranch) -> WhenBranch {
        WhenBranch(
            conditions: value.conditions.map { remap($0) },
            guard: value.guard_.map { remap($0) },
            body: remap(value.body),
            range: value.range
        )
    }

    func remap(_ value: CallArgument) -> CallArgument {
        CallArgument(
            label: value.label.map { remap($0) },
            isSpread: value.isSpread,
            isTrailingLambda: value.isTrailingLambda,
            expr: remap(value.expr)
        )
    }

    func remap(_ value: CatchClause) -> CatchClause {
        CatchClause(
            paramName: value.paramName.map { remap($0) },
            paramType: value.paramType.map { remap($0) },
            body: remap(value.body),
            range: value.range
        )
    }

    func remap(_ value: TypeArgRef) -> TypeArgRef {
        switch value {
        case let .invariant(type):
            .invariant(remap(type))
        case let .out(type):
            .out(remap(type))
        case let .`in`(type):
            .`in`(remap(type))
        case .star: value
        }
    }

    func remap(_ value: TypeRef) -> TypeRef {
        switch value {
        case let .named(path, args, nullable):
            .named(path: path.map { remap($0) }, args: args.map { remap($0) }, nullable: nullable)
        case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable):
            .functionType(contextReceivers: contextReceivers.map { remap($0) }, receiver: receiver.map { remap($0) }, params: params.map { remap($0) }, returnType: remap(returnType), isSuspend: isSuspend, nullable: nullable)
        case let .intersection(parts):
            .intersection(parts: parts.map { remap($0) })
        case let .annotated(base, annotations):
            .annotated(base: remap(base), annotations: annotations.map { remap($0) })
        }
    }

    func remap(_ value: StringTemplatePart) -> StringTemplatePart {
        switch value {
        case let .literal(name):
            .literal(remap(name))
        case let .expression(expr):
            .expression(remap(expr))
        }
    }

    func remap(_ value: FunctionBody) -> FunctionBody {
        switch value {
        case let .block(expr, range):
            .block(expr.map { remap($0) }, range)
        case let .expr(expr, range):
            .expr(remap(expr), range)
        case .unit: value
        }
    }

    func remap(_ value: Decl) -> Decl {
        switch value {
        case let .classDecl(decl):
            .classDecl(remap(decl))
        case let .interfaceDecl(decl):
            .interfaceDecl(remap(decl))
        case let .funDecl(decl):
            .funDecl(remap(decl))
        case let .propertyDecl(decl):
            .propertyDecl(remap(decl))
        case let .typeAliasDecl(decl):
            .typeAliasDecl(remap(decl))
        case let .objectDecl(decl):
            .objectDecl(remap(decl))
        case let .enumEntryDecl(decl):
            .enumEntryDecl(remap(decl))
        }
    }

    func remap(_ value: Expr) -> Expr {
        switch value {
        case .intLiteral: value
        case .longLiteral: value
        case .uintLiteral: value
        case .ulongLiteral: value
        case .floatLiteral: value
        case .doubleLiteral: value
        case .charLiteral: value
        case .nullLiteral: value
        case .boolLiteral: value
        case let .stringLiteral(name, range):
            .stringLiteral(remap(name), range)
        case let .stringTemplate(parts, range):
            .stringTemplate(parts: parts.map { remap($0) }, range: range)
        case let .nameRef(name, range):
            .nameRef(remap(name), range)
        case let .forExpr(loopVariable, iterable, body, label, range):
            .forExpr(loopVariable: loopVariable.map { remap($0) }, iterable: remap(iterable), body: remap(body), label: label.map { remap($0) }, range: range)
        case let .whileExpr(condition, body, label, range):
            .whileExpr(condition: remap(condition), body: remap(body), label: label.map { remap($0) }, range: range)
        case let .doWhileExpr(body, condition, label, range):
            .doWhileExpr(body: remap(body), condition: remap(condition), label: label.map { remap($0) }, range: range)
        case let .breakExpr(label, range):
            .breakExpr(label: label.map { remap($0) }, range: range)
        case let .continueExpr(label, range):
            .continueExpr(label: label.map { remap($0) }, range: range)
        case let .localDecl(name, isMutable, typeAnnotation, initializer, isDelegated, isLateinit, range):
            .localDecl(name: remap(name), isMutable: isMutable, typeAnnotation: typeAnnotation.map { remap($0) }, initializer: initializer.map { remap($0) }, isDelegated: isDelegated, isLateinit: isLateinit, range: range)
        case let .localAssign(name, value, range):
            .localAssign(name: remap(name), value: remap(value), range: range)
        case let .memberAssign(receiver, callee, value, range):
            .memberAssign(receiver: remap(receiver), callee: remap(callee), value: remap(value), range: range)
        case let .safeMemberAssign(receiver, callee, value, range):
            .safeMemberAssign(receiver: remap(receiver), callee: remap(callee), value: remap(value), range: range)
        case let .indexedAssign(receiver, indices, value, range):
            .indexedAssign(receiver: remap(receiver), indices: indices.map { remap($0) }, value: remap(value), range: range)
        case let .call(callee, typeArgs, args, range):
            .call(callee: remap(callee), typeArgs: typeArgs.map { remap($0) }, args: args.map { remap($0) }, range: range)
        case let .memberCall(receiver, callee, typeArgs, args, range):
            .memberCall(receiver: remap(receiver), callee: remap(callee), typeArgs: typeArgs.map { remap($0) }, args: args.map { remap($0) }, range: range)
        case let .indexedAccess(receiver, indices, range):
            .indexedAccess(receiver: remap(receiver), indices: indices.map { remap($0) }, range: range)
        case let .binary(op, lhs, rhs, range):
            .binary(op: op, lhs: remap(lhs), rhs: remap(rhs), range: range)
        case let .whenExpr(subject, branches, elseExpr, range):
            .whenExpr(subject: subject.map { remap($0) }, branches: branches.map { remap($0) }, elseExpr: elseExpr.map { remap($0) }, range: range)
        case let .returnExpr(value, label, range):
            .returnExpr(value: value.map { remap($0) }, label: label.map { remap($0) }, range: range)
        case let .ifExpr(condition, thenExpr, elseExpr, range):
            .ifExpr(condition: remap(condition), thenExpr: remap(thenExpr), elseExpr: elseExpr.map { remap($0) }, range: range)
        case let .tryExpr(body, catchClauses, finallyExpr, range):
            .tryExpr(body: remap(body), catchClauses: catchClauses.map { remap($0) }, finallyExpr: finallyExpr.map { remap($0) }, range: range)
        case let .unaryExpr(op, operand, range):
            .unaryExpr(op: op, operand: remap(operand), range: range)
        case let .isCheck(expr, type, negated, range):
            .isCheck(expr: remap(expr), type: remap(type), negated: negated, range: range)
        case let .asCast(expr, type, isSafe, range):
            .asCast(expr: remap(expr), type: remap(type), isSafe: isSafe, range: range)
        case let .nullAssert(expr, range):
            .nullAssert(expr: remap(expr), range: range)
        case let .safeMemberCall(receiver, callee, typeArgs, args, range):
            .safeMemberCall(receiver: remap(receiver), callee: remap(callee), typeArgs: typeArgs.map { remap($0) }, args: args.map { remap($0) }, range: range)
        case let .compoundAssign(op, name, value, range):
            .compoundAssign(op: op, name: remap(name), value: remap(value), range: range)
        case let .indexedCompoundAssign(op, receiver, indices, value, range):
            .indexedCompoundAssign(op: op, receiver: remap(receiver), indices: indices.map { remap($0) }, value: remap(value), range: range)
        case let .memberCompoundAssign(op, receiver, callee, value, range):
            .memberCompoundAssign(op: op, receiver: remap(receiver), callee: remap(callee), value: remap(value), range: range)
        case let .throwExpr(value, range):
            .throwExpr(value: remap(value), range: range)
        case let .lambdaLiteral(params, body, label, range):
            .lambdaLiteral(params: params.map { remap($0) }, body: remap(body), label: label.map { remap($0) }, range: range)
        case let .objectLiteral(superTypes, decl, range):
            .objectLiteral(superTypes: superTypes.map { remap($0) }, decl: decl.map { remap($0) }, range: range)
        case let .callableRef(receiver, member, range):
            .callableRef(receiver: receiver.map { remap($0) }, member: remap(member), range: range)
        case let .localFunDecl(name, receiverType, valueParams, returnType, body, isSuspend, range, typeParams, isTailrec):
            .localFunDecl(name: remap(name), receiverType: receiverType.map { remap($0) }, valueParams: valueParams.map { remap($0) }, returnType: returnType.map { remap($0) }, body: remap(body), isSuspend: isSuspend, range: range, typeParams: typeParams.map { remap($0) }, isTailrec: isTailrec)
        case let .localNominalDecl(declID, range):
            .localNominalDecl(declID: remap(declID), range: range)
        case let .blockExpr(statements, trailingExpr, range):
            .blockExpr(statements: statements.map { remap($0) }, trailingExpr: trailingExpr.map { remap($0) }, range: range)
        case let .superRef(interfaceQualifier, label, range):
            .superRef(
                interfaceQualifier: interfaceQualifier.map { remap($0) },
                label: label.map { remap($0) },
                range
            )
        case let .thisRef(label, range):
            .thisRef(label: label.map { remap($0) }, range)
        case let .inExpr(lhs, rhs, range):
            .inExpr(lhs: remap(lhs), rhs: remap(rhs), range: range)
        case let .notInExpr(lhs, rhs, range):
            .notInExpr(lhs: remap(lhs), rhs: remap(rhs), range: range)
        case let .destructuringDecl(names, isMutable, initializer, range):
            .destructuringDecl(names: names.map { $0.map { remap($0) } }, isMutable: isMutable, initializer: remap(initializer), range: range)
        case let .forDestructuringExpr(names, iterable, body, syntax, range):
            .forDestructuringExpr(
                names: names.map { $0.map { remap($0) } },
                iterable: remap(iterable),
                body: remap(body),
                syntax: syntax,
                range: range
            )
        }
    }
}
