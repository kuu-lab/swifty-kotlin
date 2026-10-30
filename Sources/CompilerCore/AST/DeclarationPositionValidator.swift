/// KUU-1407: shared validation for declaration positions and modifier
/// combinations that Kotlin/JVM rejects but KSwiftK previously accepted
/// silently. The DataFlow sema pass drives this for file-scope and member
/// declarations; the AST builder reuses it for members of local nominal
/// declarations (a local declaration itself is an expression, so its own
/// modifiers are validated while parsing).
struct DeclarationPositionValidator {
    let astArena: ASTArena
    let interner: StringInterner
    let diagnostics: DiagnosticEngine?
    var fullValueClassesEnabled: Bool = false
    var jvmInlineAnnotationNames: Set<String> = ["JvmInline", "kotlin.jvm.JvmInline"]

    static func validateMultipleVarargParameters(
        _ parameters: [ValueParamDecl],
        fallbackRange: SourceRange,
        diagnostics: DiagnosticEngine?
    ) {
        let varargParameters = parameters.filter(\.isVararg)
        guard varargParameters.count > 1 else {
            return
        }
        for parameter in varargParameters {
            diagnostics?.error(
                "KSWIFTK-SEMA-0441",
                "multiple vararg parameters are prohibited.",
                range: parameter.varargRange ?? fallbackRange
            )
        }
    }

    enum OwnerSite: Equatable {
        case file
        case function
        case nominal(NominalSite)

        var insideName: String {
            switch self {
            case .file:
                return "file"
            case .function:
                return "function"
            case .nominal(let site):
                return site.name
            }
        }

        /// `true` when the declaration is a nominal member, i.e. has a
        /// dispatch receiver in kotlinc's operator-eligibility terms.
        var isNominalMemberSite: Bool {
            if case .nominal = self {
                return true
            }
            return false
        }
    }

    struct NominalSite: Equatable {
        enum Kind: Equatable {
            case `class`
            case `enum`
            case `interface`
            case object
            case companionObject
            case enumEntry
            case annotationClass
        }

        var kind: Kind
        var isLocal: Bool
        /// `true` for an anonymous `object : ... { }` expression — unlike a
        /// named object, the anonymous instance can serve as the enclosing
        /// receiver of an `inner` member (Kotlin/JVM accepts that form).
        var isAnonymousObjectLiteral: Bool = false
        var ownerModifiers: Modifiers
        /// `true` when the owner has `init` blocks or secondary constructors
        /// that can assign stored member properties imperatively.
        var allowsImperativeInit: Bool = false
        /// `true` when member property initialization needs flow analysis,
        /// including initializers that may prevent later declarations from
        /// being reached.
        var defersPropertyInitialization: Bool = false

        var name: String {
            switch kind {
            case .class:
                return isLocal ? "local class" : "class"
            case .enum:
                return "enum class"
            case .interface:
                return "interface"
            case .object:
                return "standalone object"
            case .companionObject:
                return "companion object"
            case .enumEntry:
                return "enum entry"
            case .annotationClass:
                return "annotation class"
            }
        }
    }

    func validate(declID: DeclID, site: OwnerSite) {
        guard let decl = astArena.decl(declID) else {
            return
        }
        validate(decl, site: site)
    }

    func validate(_ decl: Decl, site: OwnerSite) {
        switch decl {
        case .classDecl(let classDecl):
            validateClass(classDecl, site: site)
        case .interfaceDecl(let interfaceDecl):
            validateInterface(interfaceDecl, site: site)
        case .objectDecl(let objectDecl):
            validateObject(objectDecl, site: site)
        case .funDecl(let funDecl):
            validateFunction(funDecl, site: site)
        case .propertyDecl(let propertyDecl):
            validateProperty(propertyDecl, site: site)
        case .typeAliasDecl(let typeAliasDecl):
            validateTypeAlias(typeAliasDecl, site: site)
        case .enumEntryDecl:
            // Enum entries are reached through the parent enum's
            // `enumEntries`, not through standalone DeclIDs.
            break
        }
    }

    static func validateFunctionValueParameters(
        _ valueParams: [ValueParamDecl],
        range: SourceRange,
        diagnostics: DiagnosticEngine?
    ) {
        for parameter in valueParams where parameter.isProperty {
            let modifier = parameter.isMutableProperty ? "var" : "val"
            diagnostics?.error(
                "KSWIFTK-SEMA-0444",
                "'\(modifier)' on function parameter is prohibited.",
                range: range
            )
        }
    }

    private func validateFunction(_ decl: FunDecl, site: OwnerSite) {
        Self.validateFunctionValueParameters(
            decl.valueParams,
            range: decl.range,
            diagnostics: diagnostics
        )

        let modifiers = decl.modifiers
        let pairPlan = incompatiblePairEmissions(
            modifiers,
            pairs: Self.memberConflictPairs,
            invalidModifiers: Self.memberSiteInvalidModifiers(site)
        )
        let conflictCovered = validateVisibilityModifierConflicts(modifiers, range: decl.range)
            .union(pairPlan.covered)
        let target = functionTargetName(site: site)

        validateDuplicateTypeParamNames(decl.typeParams, range: decl.range)

        if let whereClauseRange = decl.whereClauseRange, decl.typeParams.isEmpty {
            diagnostics?.error(
                "KSWIFTK-SEMA-0445",
                "Type constraints are not allowed when no type parameters declared.",
                range: whereClauseRange
            )
        }

        for (modifier, name) in Self.funImpossibleModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: target, range: decl.range)
        }

        if modifiers.contains(.companion) {
            let isCompanionExtension = if case .file = site { decl.receiverType != nil } else { false }
            if !isCompanionExtension {
                emitNotApplicable("companion", to: target, range: decl.range)
            }
        }

        switch site {
        case .file:
            for (modifier, name) in Self.topLevelFunForbidden
            where modifiers.contains(modifier) && !conflictCovered.contains(modifier) {
                emitNotApplicable(name, to: "top level function", range: decl.range)
            }
        case .function:
            break
        case .nominal(let nominal):
            validateInterfaceMemberModifiers(
                modifiers, site: nominal, excluding: conflictCovered, range: decl.range
            )
            if nominal.kind == .object {
                if modifiers.contains(.protected), !conflictCovered.contains(.protected) {
                    emitInside("protected", inside: nominal.name, range: decl.range)
                }
            }
            if modifiers.contains(.expect), !nominal.ownerModifiers.contains(.expect) {
                emitNotApplicable("expect", to: "member function", range: decl.range)
            }
            // `actual` members are covered by the orphan-actual symbol check
            // (KSWIFTK-SEMA-0410), which verifies expect-pairing directly.
        }

        if modifiers.contains(.operator) {
            let name = interner.resolve(decl.name)
            if !Self.isLegalOperatorName(name) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0416",
                    "'operator' modifier is not applicable: illegal function name.",
                    range: decl.range
                )
            } else if let violation = Self.operatorEligibilityViolation(
                name: name,
                isMember: site.isNominalMemberSite,
                isExtension: decl.receiverType != nil,
                isSuspend: decl.isSuspend,
                valueParams: decl.valueParams
            ) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0439",
                    "'operator' modifier is not applicable: \(violation).",
                    range: decl.range
                )
            }
        }

        if modifiers.contains(.infix) {
            // kotlinc requires `infix` functions to be members or extension
            // functions with exactly one non-vararg value parameter. A
            // default value on that parameter is accepted.
            let hasReceiver: Bool
            switch site {
            case .nominal:
                hasReceiver = true
            case .file, .function:
                hasReceiver = decl.receiverType != nil
            }
            if !hasReceiver
                || decl.valueParams.count != 1
                || decl.valueParams[0].isVararg
            {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0431",
                    "'infix' modifier is inapplicable to this function.",
                    range: decl.range
                )
            }
        }

        emitPairConflicts(pairPlan.emissions, range: decl.range)

        // Other bodyless-function cases are already covered by
        // KSWIFTK-SEMA-0009; only the interface-private combination is a gap.
        if decl.body == .unit,
           modifiers.contains(.private),
           !modifiers.contains(.abstract),
           !modifiers.contains(.expect),
           !modifiers.contains(.external),
           case .nominal(let nominal) = site,
           nominal.kind == .interface
        {
            diagnostics?.error(
                "KSWIFTK-SEMA-0426",
                "function '\(interner.resolve(decl.name))' without a body cannot be private.",
                range: decl.range
            )
        }
    }

    private func validateProperty(_ decl: PropertyDecl, site: OwnerSite) {
        let visibilityCovered = validateVisibilityModifierConflicts(decl.modifiers, range: decl.range)
        // Primary-constructor `val`/`var` parameters are materialized as
        // member properties; their restrictions are checked on the class.
        if decl.isSynthesizedPrimaryConstructorProperty {
            return
        }
        let modifiers = decl.modifiers
        let pairPlan = incompatiblePairEmissions(
            modifiers,
            pairs: Self.memberConflictPairs,
            invalidModifiers: Self.memberSiteInvalidModifiers(site)
        )
        let conflictCovered = visibilityCovered.union(pairPlan.covered)
        let target = propertyTargetName(site: site)

        for (modifier, name) in Self.propertyImpossibleModifiers where modifiers.contains(modifier) {
            if modifier == .inline, isInlinePropertyWithCustomAccessors(decl, site: site) {
                continue
            }
            emitNotApplicable(name, to: target, range: decl.range)
        }

        if modifiers.contains(.companion) {
            let isCompanionExtension = if case .file = site { decl.receiverType != nil } else { false }
            if !isCompanionExtension {
                emitNotApplicable("companion", to: target, range: decl.range)
            }
        }

        switch site {
        case .file:
            let topLevelTarget = decl.getter == nil
                ? "top level property with backing field"
                : "top level property"
            for (modifier, name) in Self.topLevelPropertyForbidden
            where modifiers.contains(modifier) && !conflictCovered.contains(modifier) {
                emitNotApplicable(name, to: topLevelTarget, range: decl.range)
            }
        case .function:
            break
        case .nominal(let nominal):
            validateInterfaceMemberModifiers(
                modifiers, site: nominal, excluding: conflictCovered, range: decl.range
            )
            if nominal.kind == .object, modifiers.contains(.protected),
               !conflictCovered.contains(.protected)
            {
                emitInside("protected", inside: nominal.name, range: decl.range)
            }
            if modifiers.contains(.expect), !nominal.ownerModifiers.contains(.expect) {
                emitNotApplicable("expect", to: "member property", range: decl.range)
            }
            if nominal.kind == .interface {
                if modifiers.contains(.lateinit) {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0418",
                        "'lateinit' modifier is not allowed on abstract properties.",
                        range: decl.range
                    )
                }
                if modifiers.contains(.private), isImplicitlyAbstractInterfaceProperty(decl) {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0428",
                        "abstract property in interface cannot be private.",
                        range: decl.range
                    )
                }
            }
        }

        if modifiers.contains(.const) {
            let constAllowed: Bool = switch site {
            case .file:
                true
            case .function:
                // Local `const` is diagnosed as a misplaced modifier by the
                // statement parser already; keep silent here.
                false
            case .nominal(let nominal):
                nominal.kind == .object || nominal.kind == .companionObject
            }
            if !constAllowed {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0403",
                    "const 'val' is only allowed on top level, in named objects, in companion objects or companion blocks.",
                    range: decl.range
                )
            }
            if decl.isVar {
                emitNotApplicable("const", to: "vars", range: decl.range)
            }
        }

        emitPairConflicts(pairPlan.emissions, range: decl.range)

        validatePropertyInitialization(decl, site: site)
    }

    private func isImplicitlyAbstractInterfaceProperty(_ decl: PropertyDecl) -> Bool {
        decl.initializer == nil && decl.getter == nil && decl.setter == nil
    }

    /// KUU-2879: inline properties need explicit, implemented accessors so
    /// they have no backing field. Mutable properties need both accessors;
    /// inline member accessors must not be virtual.
    private func isInlinePropertyWithCustomAccessors(_ decl: PropertyDecl, site: OwnerSite) -> Bool {
        switch site {
        case .file:
            break
        case .function:
            return false
        case .nominal(let nominal):
            guard nominal.kind != .interface else { return false }
        }

        let modifiers = decl.modifiers
        guard !modifiers.contains(.open),
              !modifiers.contains(.abstract),
              !(modifiers.contains(.override) && !modifiers.contains(.final)),
              decl.initializer == nil,
              decl.delegateExpression == nil,
              decl.explicitBackingField == nil,
              decl.getter.map({ $0.body != .unit }) == true
        else {
            return false
        }

        if decl.isVar {
            return decl.setter.map { $0.body != .unit } == true
        }
        return decl.setter == nil
    }

    private func hasPropertyInitializationExpression(_ properties: [DeclID]) -> Bool {
        properties.contains { id in
            guard case let .propertyDecl(property) = astArena.decl(id) else { return false }
            return property.initializer != nil
                || property.delegateExpression != nil
                || property.explicitBackingField != nil
        }
    }

    private func validatePropertyInitialization(_ decl: PropertyDecl, site: OwnerSite) {
        let modifiers = decl.modifiers
        if modifiers.contains(.abstract)
            || modifiers.contains(.lateinit)
            || modifiers.contains(.expect)
            || decl.initializer != nil
            || decl.delegateExpression != nil
            || decl.explicitBackingField != nil
        {
            return
        }
        if case .nominal(let nominal) = site {
            // Members of `expect` declarations declare signatures only.
            if nominal.ownerModifiers.contains(.expect) {
                return
            }
            // Instance members of annotation classes are rejected elsewhere.
            if nominal.kind == .annotationClass {
                return
            }
            // Bodiless interface properties are implicitly abstract.
            if nominal.kind == .interface, isImplicitlyAbstractInterfaceProperty(decl) {
                return
            }
            // Property initializers, init blocks, and secondary constructors
            // require flow analysis before missing storage can be diagnosed.
            if nominal.allowsImperativeInit || nominal.defersPropertyInitialization {
                return
            }
        }
        if decl.receiverType != nil,
           decl.getter == nil || (decl.isVar && decl.setter == nil)
        {
            diagnostics?.error(
                "KSWIFTK-SEMA-0425",
                "extension property must have accessors or be abstract.",
                range: decl.range
            )
            return
        }
        let usesBackingField = accessorUsesBackingField(decl.getter)
            || accessorUsesBackingField(decl.setter)
        let initialized = if decl.isVar {
            // An explicit empty body is still a custom accessor. The property
            // is fieldless only when both accessors have bodies and neither
            // uses `field`; a bodiless/default accessor still needs storage.
            accessorHasBody(decl.getter)
                && accessorHasBody(decl.setter)
                && !usesBackingField
        } else {
            accessorHasBody(decl.getter) && !usesBackingField
        }
        if !initialized {
            // A property with custom accessor bodies is concrete — kotlinc
            // drops the "or be abstract" hint in that shape.
            let hasAccessorBody = accessorHasBody(decl.getter) || accessorHasBody(decl.setter)
            let message = switch site {
            case .file:
                "property must be initialized."
            case .nominal(let nominal) where nominal.kind == .interface:
                "property in interface cannot have a backing field."
            default:
                hasAccessorBody
                    ? "property must be initialized."
                    : "property must be initialized or be abstract."
            }
            diagnostics?.error("KSWIFTK-SEMA-0424", message, range: decl.range)
        }
    }

    func accessorHasBody(_ accessor: PropertyAccessorDecl?) -> Bool {
        guard let accessor else {
            return false
        }
        switch accessor.body {
        case .unit:
            return false
        case .expr, .block:
            return true
        }
    }

    func accessorUsesBackingField(
        _ accessor: PropertyAccessorDecl?,
        isBackingFieldReference: (ExprID) -> Bool = { _ in true }
    ) -> Bool {
        guard let accessor else { return false }
        let roots: [ExprID] = switch accessor.body {
        case .unit:
            []
        case .expr(let exprID, _):
            [exprID]
        case .block(let exprIDs, _):
            exprIDs
        }
        var visited: Set<ExprID> = []
        let fieldName = interner.intern("field")
        for root in roots {
            if expressionUsesBackingField(root, fieldName: fieldName, visited: &visited,
                                          isBackingFieldReference: isBackingFieldReference) {
                return true
            }
        }
        return false
    }

    private func expressionUsesBackingField(
        _ exprID: ExprID,
        fieldName: InternedString,
        visited: inout Set<ExprID>,
        isBackingFieldReference: (ExprID) -> Bool
    ) -> Bool {
        guard visited.insert(exprID).inserted,
              let expr = astArena.expr(exprID)
        else {
            return false
        }
        switch expr {
        case .nameRef(let name, _) where name == fieldName,
             .localAssign(let name, _, _) where name == fieldName,
             .compoundAssign(_, let name, _, _) where name == fieldName:
            if isBackingFieldReference(exprID) { return true }
        default:
            break
        }
        for child in expressionChildren(of: expr) {
            if expressionUsesBackingField(child, fieldName: fieldName, visited: &visited,
                                          isBackingFieldReference: isBackingFieldReference) {
                return true
            }
        }
        return false
    }

    private func expressionChildren(of expr: Expr) -> [ExprID] {
        switch expr {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .nullLiteral,
             .boolLiteral, .stringLiteral, .nameRef, .breakExpr, .continueExpr,
             .superRef, .thisRef, .localNominalDecl, .objectLiteral:
            []
        case .stringTemplate(let parts, _):
            parts.compactMap { part in
                if case .expression(let exprID) = part { return exprID }
                return nil
            }
        case .forExpr(_, let iterable, let body, _, _),
             .forDestructuringExpr(_, let iterable, let body, _, _):
            [iterable, body]
        case .whileExpr(let condition, let body, _, _):
            [condition, body]
        case .doWhileExpr(let body, let condition, _, _):
            [body, condition]
        case .localDecl(_, _, _, let initializer, _, _, _):
            initializer.map { [$0] } ?? []
        case .localAssign(_, let value, _), .compoundAssign(_, _, let value, _),
             .throwExpr(let value, _):
            [value]
        case .memberAssign(let receiver, _, let value, _),
             .safeMemberAssign(let receiver, _, let value, _),
             .memberCompoundAssign(_, let receiver, _, let value, _):
            [receiver, value]
        case .indexedAssign(let receiver, let indices, let value, _),
             .indexedCompoundAssign(_, let receiver, let indices, let value, _):
            [receiver] + indices + [value]
        case .call(let callee, _, let args, _):
            [callee] + args.map(\.expr)
        case .memberCall(let receiver, _, _, let args, _),
             .safeMemberCall(let receiver, _, _, let args, _):
            [receiver] + args.map(\.expr)
        case .indexedAccess(let receiver, let indices, _):
            [receiver] + indices
        case .binary(_, let lhs, let rhs, _),
             .inExpr(let lhs, let rhs, _), .notInExpr(let lhs, let rhs, _):
            [lhs, rhs]
        case .whenExpr(let subject, let branches, let elseExpr, _):
            (subject.map { [$0] } ?? [])
                + branches.flatMap { $0.conditions + ($0.guard_.map { [$0] } ?? []) + [$0.body] }
                + (elseExpr.map { [$0] } ?? [])
        case .returnExpr(let value, _, _):
            value.map { [$0] } ?? []
        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            [condition, thenExpr] + (elseExpr.map { [$0] } ?? [])
        case .tryExpr(let body, let catchClauses, let finallyExpr, _):
            [body] + catchClauses.map(\.body) + (finallyExpr.map { [$0] } ?? [])
        case .unaryExpr(_, let operand, _), .isCheck(let operand, _, _, _),
             .asCast(let operand, _, _, _), .nullAssert(let operand, _):
            [operand]
        case .lambdaLiteral(_, let body, _, _):
            [body]
        case .callableRef(let receiver, _, _):
            receiver.map { [$0] } ?? []
        case .localFunDecl(_, _, _, _, let body, _, _, _, _):
            expressionIDs(in: body)
        case .blockExpr(let statements, let trailingExpr, _):
            statements + (trailingExpr.map { [$0] } ?? [])
        case .destructuringDecl(_, _, let initializer, _):
            [initializer]
        }
    }

    private func expressionIDs(in body: FunctionBody) -> [ExprID] {
        switch body {
        case .unit:
            []
        case .expr(let exprID, _):
            [exprID]
        case .block(let exprIDs, _):
            exprIDs
        }
    }

    private func validateClass(_ decl: ClassDecl, site: OwnerSite) {
        validateDuplicateTypeParamNames(decl.typeParams, range: decl.range)

        let modifiers = decl.modifiers
        let visibilityCovered = validateVisibilityModifierConflicts(modifiers, range: decl.range)
        validateVisibilityModifierConflicts(decl.primaryConstructorModifiers, range: decl.range)
        for constructor in decl.secondaryConstructors {
            validateVisibilityModifierConflicts(constructor.modifiers, range: constructor.range)
        }
        let isEnum = modifiers.contains(.enumModifier)
        // `annotation enum class` resolves to an enum: the annotation modifier
        // is kind-invalid on it rather than making it an annotation class.
        let isAnnotation = modifiers.contains(.annotationClass) && !isEnum
        // `inline class` is the deprecated spelling of `value class`, so it
        // obeys the same position/finality constraints (SEMA-0420/0422).
        let isValue = modifiers.contains(.value)
            || (modifiers.contains(.inline) && !isEnum && !isAnnotation)
        let kindName: String
        if isAnnotation {
            // kotlinc keeps the 'annotation class' kind name for local
            // annotation classes; only class and enum become 'local class'.
            kindName = "annotation class"
        } else if site == .function {
            kindName = "local class"
        } else if isEnum {
            kindName = "enum class"
        } else if isValue {
            kindName = "value class"
        } else {
            kindName = "class"
        }

        var classInvalid: Modifiers = site == .file ? [.inner, .protected] : []
        if site == .function {
            classInvalid.formUnion(Self.modifierSet(Self.localClassForbiddenModifiers))
            classInvalid.formUnion([.inner, .final])
        }
        if isEnum {
            classInvalid.formUnion(Self.modifierSet(Self.enumForbiddenModifiers))
        }
        if isAnnotation {
            classInvalid.formUnion(Self.modifierSet(Self.annotationForbiddenModifiers))
        }
        if isValue {
            classInvalid.formUnion([.open, .abstract, .sealed])
        }
        let pairPlan = incompatiblePairEmissions(
            modifiers,
            pairs: Self.classConflictPairs,
            invalidModifiers: classInvalid
        )
        let conflictCovered = visibilityCovered.union(pairPlan.covered)

        for (modifier, name) in Self.classImpossibleModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: kindName, range: decl.range)
        }
        // `inline class` is the deprecated spelling of `value class`: kotlinc
        // accepts it with a deprecation warning and the class is still treated
        // as a value class downstream (isValueClassDeclaration covers .inline).
        // Enum and annotation classes cannot be value classes, so `inline`
        // stays impossible there.
        if modifiers.contains(.inline) {
            if isEnum {
                emitNotApplicable("inline", to: "enum class", range: decl.range)
            } else if isAnnotation {
                emitNotApplicable("inline", to: "annotation class", range: decl.range)
            } else {
                diagnostics?.warning(
                    "KSWIFTK-SEMA-DEPRECATED",
                    "'inline' modifier is deprecated. Use 'value' instead.",
                    range: decl.range
                )
            }
        }
        if site == .function {
            if isAnnotation {
                // A local annotation class still takes its kind-forbidden
                // diagnostics below, but kotlinc phrases visibility
                // positionally and never emits the local-class set.
                for (modifier, name) in Self.localNominalVisibilityModifiers
                where modifiers.contains(modifier) {
                    emitInside(name, inside: "function", range: decl.range)
                }
                diagnostics?.error(
                    "KSWIFTK-SEMA-0429",
                    "annotation class cannot be local.",
                    range: decl.range
                )
            } else {
                for (modifier, name) in Self.localClassForbiddenModifiers
                where modifiers.contains(modifier) && !conflictCovered.contains(modifier) {
                    emitNotApplicable(name, to: "local class", range: decl.range)
                }
                if modifiers.contains(.final), !conflictCovered.contains(.final) {
                    emitInside("final", inside: "function", range: decl.range)
                }
            }
        }
        if modifiers.contains(.external) {
            // kotlinc calls every nominal 'class' for the external check.
            emitNotApplicable("external", to: "class", range: decl.range)
        }
        if isEnum {
            let enumKindName = site == .function ? "local class" : "enum class"
            for (modifier, name) in Self.enumForbiddenModifiers
            where modifiers.contains(modifier) && !conflictCovered.contains(modifier) {
                if site == .function {
                    // A locally declared 'enum' is only diagnosed for its
                    // nominal-kind conflicts: modality modifiers and `data`
                    // are subsumed by the 'enum to local class' error, and
                    // local-class-forbidden modifiers already fired above.
                    if modifier == .open || modifier == .abstract || modifier == .data
                        || Self.localClassForbiddenModifiers.contains(where: { $0.0 == modifier })
                    {
                        continue
                    }
                }
                emitNotApplicable(name, to: enumKindName, range: decl.range)
            }
        }
        if isAnnotation {
            for (modifier, name) in Self.annotationForbiddenModifiers
            where modifiers.contains(modifier) && !conflictCovered.contains(modifier) {
                emitNotApplicable(name, to: "annotation class", range: decl.range)
            }
        }
        if isValue {
            let hasInheritableModality = modifiers.contains(.open)
                || modifiers.contains(.abstract)
                || modifiers.contains(.sealed)
            let isFullValueClass = fullValueClassesEnabled
                && modifiers.contains(.value)
                && !modifiers.contains(.inline)
                && !decl.annotations.contains { jvmInlineAnnotationNames.contains($0.name) }
            let allowsFullValueClassInheritance = isFullValueClass
                && !modifiers.contains(.open)
                && (modifiers.contains(.abstract) || modifiers.contains(.sealed))
            if hasInheritableModality && !allowsFullValueClassInheritance {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0420",
                    "value class can be only final.",
                    range: decl.range
                )
            }
        }

        if site == .file, modifiers.contains(.protected), !conflictCovered.contains(.protected) {
            emitNotApplicable("protected", to: "top level class", range: decl.range)
        }

        // Visibility modifiers apply to constructor parameters only when they declare a property.
        for param in decl.primaryConstructorParams where !param.isProperty {
            let parameterModifiers = param.propertyVisibilityModifiers ?? []
            for (modifier, name) in Self.constructorParameterVisibilityModifiers
            where parameterModifiers.contains(modifier) {
                emitNotApplicable(name, to: "value parameter", range: decl.range)
            }
        }

        // `inner` is kind-invalid on enum and annotation classes, so the
        // not-applicable-to diagnostic owns it without a positional duplicate.
        if !conflictCovered.contains(.inner), !isEnum, !isAnnotation {
            validateInnerPosition(modifiers, site: site, target: kindName, range: decl.range)
        }
        if case .nominal(let nominal) = site {
            validateMemberSiteModifiers(modifiers, site: nominal, target: "member class", range: decl.range)
        }

        emitPairConflicts(pairPlan.emissions, range: decl.range)

        if modifiers.contains(.data), !isEnum, !isAnnotation, decl.primaryConstructorParams.isEmpty {
            diagnostics?.error(
                "KSWIFTK-SEMA-0404",
                "data class must have at least one primary constructor parameter.",
                range: decl.range
            )
        }

        if isValue, !isEnum, !isAnnotation {
            if site == .function || modifiers.contains(.inner) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0422",
                    "value class cannot be local or inner.",
                    range: decl.range
                )
            }
            for param in decl.primaryConstructorParams where !param.isProperty || param.isMutableProperty {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0423",
                    "value class primary constructor must only have final read-only ('val') property parameters.",
                    range: decl.range
                )
            }
        }

        if isAnnotation {
            for param in decl.primaryConstructorParams {
                if param.isMutableProperty {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0427",
                        "an annotation parameter cannot be 'var'.",
                        range: decl.range
                    )
                } else if !param.isProperty {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0421",
                        "'val' keyword is missing in annotation parameter.",
                        range: decl.range
                    )
                }
            }
            let memberCount =
                decl.memberFunctions.count
                + decl.memberProperties.filter { propID in
                    guard let memberDecl = astArena.decl(propID),
                          case .propertyDecl(let prop) = memberDecl
                    else {
                        return false
                    }
                    return !prop.isSynthesizedPrimaryConstructorProperty
                }.count
                + decl.nestedTypeAliases.count
                + decl.initBlocks.count
                + decl.secondaryConstructors.count
            if memberCount > 0 {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0419",
                    "members are prohibited in annotation classes.",
                    range: decl.range
                )
            }
        }

        let memberSite = NominalSite(
            kind: isEnum ? .enum : (isAnnotation ? .annotationClass : .class),
            isLocal: site == .function,
            ownerModifiers: modifiers,
            allowsImperativeInit: !decl.initBlocks.isEmpty
                || !decl.secondaryConstructors.isEmpty,
            defersPropertyInitialization: !decl.initBlocks.isEmpty
                || !decl.secondaryConstructors.isEmpty
                || hasPropertyInitializationExpression(decl.memberProperties)
        )
        validateClassMembers(decl, site: memberSite)
    }

    private func validateClassMembers(_ decl: ClassDecl, site: NominalSite) {
        let memberSite = OwnerSite.nominal(site)
        // Annotation instance members are reported wholesale above. Nested
        // types and companion objects are legal and still need validation.
        if site.kind != .annotationClass {
            for declID in decl.memberFunctions {
                validate(declID: declID, site: memberSite)
            }
            for declID in decl.memberProperties {
                validate(declID: declID, site: memberSite)
            }
        }
        for declID in decl.nestedClasses {
            validate(declID: declID, site: memberSite)
        }
        for declID in decl.nestedObjects {
            validate(declID: declID, site: memberSite)
        }
        for typeAlias in decl.nestedTypeAliases {
            validateTypeAlias(typeAlias, site: memberSite)
        }
        if let companionID = decl.companionObject {
            validate(declID: companionID, site: memberSite)
        }
        for entry in decl.enumEntries {
            let entrySite = OwnerSite.nominal(NominalSite(
                kind: .enumEntry,
                isLocal: site.isLocal,
                ownerModifiers: [],
                allowsImperativeInit: !entry.initBlocks.isEmpty,
                defersPropertyInitialization: !entry.initBlocks.isEmpty
            ))
            for declID in entry.memberFunctions {
                validate(declID: declID, site: entrySite)
            }
            for declID in entry.memberProperties {
                validate(declID: declID, site: entrySite)
            }
            for declID in entry.nestedClasses {
                validate(declID: declID, site: entrySite)
            }
        }
    }

    private func validateInterface(_ decl: InterfaceDecl, site: OwnerSite) {
        validateDuplicateTypeParamNames(decl.typeParams, range: decl.range)

        let modifiers = decl.modifiers
        validateVisibilityModifierConflicts(modifiers, range: decl.range)

        for (modifier, name) in Self.interfaceForbiddenModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: "interface", range: decl.range)
        }
        if modifiers.contains(.external) {
            emitNotApplicable("external", to: "class", range: decl.range)
        }

        if site == .file, modifiers.contains(.protected) {
            emitNotApplicable("protected", to: "top level interface", range: decl.range)
        }
        // `inner` is always kind-invalid on interfaces, so validateInnerPosition
        // would double-report; the not-applicable-to diagnostic owns it.
        if case .nominal(let nominal) = site {
            validateMemberSiteModifiers(modifiers, site: nominal, target: "member interface", range: decl.range)
        }

        if decl.isFunInterface, decl.superTypes.isEmpty {
            for declID in decl.memberProperties {
                guard let memberDecl = astArena.decl(declID),
                      case .propertyDecl(let prop) = memberDecl,
                      prop.modifiers.contains(.abstract)
                        || (prop.initializer == nil && prop.getter == nil && prop.setter == nil)
                else {
                    continue
                }
                diagnostics?.error(
                    "KSWIFTK-SEMA-0407",
                    "functional interface cannot have abstract properties.",
                    range: prop.range
                )
            }
        }

        let memberSite = NominalSite(
            kind: .interface,
            isLocal: site == .function,
            ownerModifiers: modifiers
        )
        validateInterfaceMembers(decl, site: memberSite)
    }

    private func validateInterfaceMembers(_ decl: InterfaceDecl, site: NominalSite) {
        let memberSite = OwnerSite.nominal(site)
        for declID in decl.memberFunctions {
            validate(declID: declID, site: memberSite)
        }
        for declID in decl.memberProperties {
            validate(declID: declID, site: memberSite)
        }
        for declID in decl.nestedClasses {
            validate(declID: declID, site: memberSite)
        }
        for declID in decl.nestedObjects {
            validate(declID: declID, site: memberSite)
        }
        for typeAlias in decl.nestedTypeAliases {
            validateTypeAlias(typeAlias, site: memberSite)
        }
        if let companionID = decl.companionObject {
            validate(declID: companionID, site: memberSite)
        }
    }

    private func validateObject(_ decl: ObjectDecl, site: OwnerSite) {
        let modifiers = decl.modifiers
        validateVisibilityModifierConflicts(modifiers, range: decl.range)
        // kotlinc calls every named object a 'standalone object' in modifier
        // diagnostics, including function-local ones.
        let kindName = "standalone object"

        for (modifier, name) in Self.objectImpossibleModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: kindName, range: decl.range)
        }
        if modifiers.contains(.external) {
            emitNotApplicable("external", to: "class", range: decl.range)
        }
        if site == .function {
            // kotlinc phrases visibility on local objects positionally and
            // skips `public`/`expect` entirely.
            for (modifier, name) in Self.localNominalVisibilityModifiers where modifiers.contains(modifier) {
                emitInside(name, inside: "function", range: decl.range)
            }
        }

        // A named object can only be a top-level or member declaration — in
        // any local position (function body, member of a local/anonymous
        // nominal, enum entry) kotlinc reports "named object 'X' cannot be
        // local". `companion object` takes its own not-applicable check below.
        let isLocalSite = switch site {
        case .file:
            false
        case .function:
            true
        case .nominal(let nominal):
            nominal.isLocal || nominal.kind == .enumEntry
        }
        if isLocalSite, !modifiers.contains(.companion) {
            diagnostics?.error(
                "KSWIFTK-SEMA-0429",
                "named object '\(interner.resolve(decl.name))' cannot be local. Try to use an anonymous object instead.",
                range: decl.range
            )
        }

        if modifiers.contains(.companion) {
            let allowed: Bool = switch site {
            case .nominal(let nominal):
                !nominal.isLocal
                    && (nominal.kind == .class || nominal.kind == .enum || nominal.kind == .interface
                        || nominal.kind == .annotationClass)
            case .file, .function:
                false
            }
            if !allowed {
                emitInside("companion", inside: site.insideName, range: decl.range)
            }
        }

        if site == .file, modifiers.contains(.protected) {
            emitNotApplicable("protected", to: "top level object", range: decl.range)
        }
        if case .nominal(let nominal) = site {
            validateMemberSiteModifiers(modifiers, site: nominal, target: "member object", range: decl.range)
        }

        let isCompanion = modifiers.contains(.companion)
        let memberSite = NominalSite(
            kind: isCompanion ? .companionObject : .object,
            isLocal: site == .function,
            ownerModifiers: modifiers,
            allowsImperativeInit: !decl.initBlocks.isEmpty,
            defersPropertyInitialization: !decl.initBlocks.isEmpty
                || hasPropertyInitializationExpression(decl.memberProperties)
        )
        validateObjectMembers(decl, site: memberSite)
    }

    /// Anonymous object expressions carry no source modifiers of their own,
    /// so only their members are checked — at the same member site a named
    /// local object would produce, except that `inner` members are legal
    /// (the anonymous object instance acts as their enclosing receiver).
    func validateAnonymousObjectLiteralMembers(_ decl: ObjectDecl) {
        let memberSite = NominalSite(
            kind: .object,
            isLocal: true,
            isAnonymousObjectLiteral: true,
            ownerModifiers: decl.modifiers,
            allowsImperativeInit: !decl.initBlocks.isEmpty,
            defersPropertyInitialization: !decl.initBlocks.isEmpty
                || hasPropertyInitializationExpression(decl.memberProperties)
        )
        validateObjectMembers(decl, site: memberSite)
    }

    private func validateObjectMembers(_ decl: ObjectDecl, site: NominalSite) {
        let memberSite = OwnerSite.nominal(site)
        for declID in decl.memberFunctions {
            validate(declID: declID, site: memberSite)
        }
        for declID in decl.memberProperties {
            validate(declID: declID, site: memberSite)
        }
        for declID in decl.nestedClasses {
            validate(declID: declID, site: memberSite)
        }
        for declID in decl.nestedObjects {
            validate(declID: declID, site: memberSite)
        }
        for typeAlias in decl.nestedTypeAliases {
            validateTypeAlias(typeAlias, site: memberSite)
        }
    }

    private func validateTypeAlias(_ decl: TypeAliasDecl, site: OwnerSite) {
        validateVisibilityModifierConflicts(decl.modifiers, range: decl.range)
        validateDuplicateTypeParamNames(decl.typeParams, range: decl.range)
        for (modifier, name) in Self.typeAliasForbiddenModifiers where decl.modifiers.contains(modifier) {
            emitNotApplicable(name, to: "typealias", range: decl.range)
        }
        if site == .file, decl.modifiers.contains(.protected) {
            emitNotApplicable("protected", to: "top level typealias", range: decl.range)
        }
    }

    /// `inner` is only legal inside a non-local class-like body (a class,
    /// enum, or enum entry — including members of local classes).
    private func validateInnerPosition(
        _ modifiers: Modifiers,
        site: OwnerSite,
        target: String,
        range: SourceRange
    ) {
        guard modifiers.contains(.inner) else {
            return
        }
        switch site {
        case .file:
            emitInside("inner", inside: "file", range: range)
        case .function:
            emitInside("inner", inside: "function", range: range)
        case .nominal(let nominal):
            switch nominal.kind {
            case .class, .enum, .enumEntry:
                break
            case .object where nominal.isAnonymousObjectLiteral:
                break
            case .interface, .object, .companionObject, .annotationClass:
                emitInside("inner", inside: nominal.name, range: range)
            }
        }
    }

    private func validateInterfaceMemberModifiers(
        _ modifiers: Modifiers,
        site: NominalSite,
        excluding conflictCovered: Modifiers = [],
        range: SourceRange
    ) {
        guard site.kind == .interface else {
            return
        }
        // `protected` inside interfaces is diagnosed by the
        // open/final/override pass (KUU-1406) and intentionally not repeated.
        if modifiers.contains(.internal), !conflictCovered.contains(.internal) {
            emitInside("internal", inside: "interface", range: range)
        }
        if modifiers.contains(.final), !conflictCovered.contains(.final) {
            emitInside("final", inside: "interface", range: range)
        }
        if modifiers.contains(.external) {
            diagnostics?.error(
                "KSWIFTK-SEMA-0401",
                "members of interfaces cannot be external.",
                range: range
            )
        }
    }

    private func validateMemberSiteModifiers(
        _ modifiers: Modifiers,
        site: NominalSite,
        target: String,
        range: SourceRange
    ) {
        validateInterfaceMemberModifiers(modifiers, site: site, range: range)
        if site.kind == .object, modifiers.contains(.protected) {
            emitInside("protected", inside: site.name, range: range)
        }
        if modifiers.contains(.expect), !site.ownerModifiers.contains(.expect) {
            emitNotApplicable("expect", to: target, range: range)
        }
    }

    /// kotlinc reports an incompatible-modifier pair once per modifier: each
    /// modifier names its first conflicting partner. A modifier that is invalid
    /// at this site only reports a conflict when an earlier pair entry claims
    /// it; otherwise the site's not-applicable diagnostic owns it. Returns the
    /// modifiers that emitted a conflict so callers can suppress redundant
    /// applicability diagnostics for them.
    @discardableResult
    private func emitIncompatiblePairs(
        _ modifiers: Modifiers,
        pairs: [(Modifiers, String, Modifiers, String)],
        invalidModifiers: Modifiers = [],
        range: SourceRange
    ) -> Modifiers {
        let plan = incompatiblePairEmissions(
            modifiers, pairs: pairs, invalidModifiers: invalidModifiers
        )
        emitPairConflicts(plan.emissions, range: range)
        return plan.covered
    }

    private func incompatiblePairEmissions(
        _ modifiers: Modifiers,
        pairs: [(Modifiers, String, Modifiers, String)],
        invalidModifiers: Modifiers
    ) -> (emissions: [(String, String)], covered: Modifiers) {
        var partner: [Modifiers: String] = [:]
        var hasEarlierPartner: Modifiers = []
        for (first, firstName, second, secondName) in pairs
        where modifiers.contains(first) && modifiers.contains(second) {
            if partner[first] == nil { partner[first] = secondName }
            if partner[second] == nil { partner[second] = firstName }
            hasEarlierPartner.insert(second)
        }
        var emissions: [(String, String)] = []
        var covered: Modifiers = []
        var emitted: Modifiers = []
        for (first, firstName, second, secondName) in pairs
        where modifiers.contains(first) && modifiers.contains(second) {
            for (modifier, name) in [(first, firstName), (second, secondName)]
            where !emitted.contains(modifier) {
                if invalidModifiers.contains(modifier), !hasEarlierPartner.contains(modifier) {
                    continue
                }
                emissions.append((name, partner[modifier]!))
                emitted.insert(modifier)
                covered.insert(modifier)
            }
        }
        return (emissions, covered)
    }

    private func emitPairConflicts(_ emissions: [(String, String)], range: SourceRange) {
        for (name, partner) in emissions {
            diagnostics?.error(
                "KSWIFTK-SEMA-0402",
                "modifier '\(name)' is incompatible with '\(partner)'.",
                range: range
            )
        }
    }

    @discardableResult
    private func validateVisibilityModifierConflicts(_ modifiers: Modifiers, range: SourceRange) -> Modifiers {
        emitIncompatiblePairs(
            modifiers,
            pairs: [
                (.private, "private", .public, "public"),
                (.private, "private", .internal, "internal"),
                (.private, "private", .protected, "protected"),
                (.public, "public", .internal, "internal"),
                (.public, "public", .protected, "protected"),
                (.internal, "internal", .protected, "protected"),
            ],
            range: range
        )
    }

    private func validateDuplicateTypeParamNames(_ typeParams: [TypeParamDecl], range: SourceRange) {
        var seen: Set<InternedString> = []
        var reported: Set<InternedString> = []
        for param in typeParams where !seen.insert(param.name).inserted {
            if reported.insert(param.name).inserted {
                let name = interner.resolve(param.name)
                diagnostics?.error(
                    "KSWIFTK-SEMA-0436",
                    "conflicting declarations: \(name), \(name).",
                    range: range
                )
            }
        }
    }

    private func emitNotApplicable(_ name: String, to target: String, range: SourceRange) {
        diagnostics?.error(
            "KSWIFTK-SEMA-0400",
            "modifier '\(name)' is not applicable to '\(target)'.",
            range: range
        )
    }

    private func emitInside(_ name: String, inside site: String, range: SourceRange) {
        diagnostics?.error(
            "KSWIFTK-SEMA-0401",
            "modifier '\(name)' is not applicable inside '\(site)'.",
            range: range
        )
    }

    private func functionTargetName(site: OwnerSite) -> String {
        switch site {
        case .file:
            return "top level function"
        case .function:
            return "local function"
        case .nominal:
            return "member function"
        }
    }

    private func propertyTargetName(site: OwnerSite) -> String {
        switch site {
        case .file:
            return "top level property"
        case .function:
            return "local variable"
        case .nominal:
            return "member property"
        }
    }

    /// Function names that legally carry the `operator` modifier.
    static func isLegalOperatorName(_ name: String) -> Bool {
        if legalOperatorNames.contains(name) {
            return true
        }
        // kotlinc's component convention accepts `component\d+`, so
        // `component0` and arbitrarily large suffixes are legal names.
        return isLegalComponentName(name)
    }

    private static let legalOperatorNames: Set<String> = [
        "unaryPlus", "unaryMinus", "not", "inv", "inc", "dec",
        "plus", "minus", "times", "div", "rem",
        "plusAssign", "minusAssign", "timesAssign", "divAssign", "remAssign",
        "rangeTo", "rangeUntil", "contains",
        "get", "set", "invoke", "iterator", "next", "hasNext",
        "compareTo", "equals", "provideDelegate", "getValue", "setValue",
    ]

    /// KUU-3149: per-name `operator` eligibility rules mirroring the check
    /// order of kotlinc 2.4.20's `OperatorFunctionChecks`, so the first
    /// reported violation matches the JVM diagnostic. Legs that need resolved
    /// types (return-type predicates, the `KProperty` parameter of the
    /// delegate operators, the inc/dec receiver-subsumption check) are not
    /// reproduced here.
    static func operatorEligibilityViolation(
        name: String,
        isMember: Bool,
        isExtension: Bool,
        isSuspend: Bool,
        valueParams: [ValueParamDecl]
    ) -> String? {
        guard let rules = operatorEligibilityRules(for: name) else {
            return nil
        }
        for rule in rules {
            if let violation = rule.violation(
                isMember: isMember,
                isExtension: isExtension,
                isSuspend: isSuspend,
                valueParams: valueParams
            ) {
                return violation
            }
        }
        return nil
    }

    private static func operatorEligibilityRules(for name: String) -> [OperatorEligibilityRule]? {
        switch name {
        case "get":
            [.memberOrExtension, .atLeast(1)]
        case "set":
            [.memberOrExtension, .atLeast(2), .lastParamNoDefaultOrVararg]
        case "getValue":
            [.memberOrExtension, .noDefaultAndVarargs, .atLeast(2), .atMost(2), .nonSuspend]
        case "setValue":
            [.memberOrExtension, .noDefaultAndVarargs, .atLeast(3), .atMost(3), .nonSuspend]
        case "provideDelegate":
            [.memberOrExtension, .noDefaultAndVarargs, .exactly(2), .nonSuspend]
        case "invoke":
            [.memberOrExtension]
        case "contains":
            [.memberOrExtension, .singleParam, .noDefaultAndVarargs]
        case "iterator", "next", "hasNext":
            [.memberOrExtension, .noParams]
        case "rangeTo", "rangeUntil", "compareTo",
             "plus", "minus", "times", "div", "rem",
             "plusAssign", "minusAssign", "timesAssign", "divAssign", "remAssign":
            [.memberOrExtension, .singleParam, .noDefaultAndVarargs]
        case "unaryPlus", "unaryMinus", "not", "inv":
            [.memberOrExtension, .noParams]
        case "inc", "dec":
            [.memberOrExtension]
        case "equals":
            [.member, .overridesAnyEquals]
        default:
            isLegalComponentName(name) ? [.memberOrExtension, .noParams] : nil
        }
    }

    private static func isLegalComponentName(_ name: String) -> Bool {
        guard name.hasPrefix("component") else {
            return false
        }
        let suffix = name.dropFirst("component".count)
        return !suffix.isEmpty && suffix.allSatisfy { ("0" ... "9").contains($0) }
    }

    enum OperatorEligibilityRule {
        case memberOrExtension
        case member
        case noParams
        case singleParam
        case atLeast(Int)
        case atMost(Int)
        case exactly(Int)
        case noDefaultAndVarargs
        case lastParamNoDefaultOrVararg
        case nonSuspend
        /// kotlinc verifies that `equals` overrides `Any.equals`; the
        /// arity-visible half of that check needs exactly one value
        /// parameter — any other count can never override it.
        case overridesAnyEquals

        func violation(
            isMember: Bool,
            isExtension: Bool,
            isSuspend: Bool,
            valueParams: [ValueParamDecl]
        ) -> String? {
            switch self {
            case .memberOrExtension:
                return (isMember || isExtension) ? nil : "must be a member or an extension function"
            case .member:
                return isMember ? nil : "must be a member function"
            case .noParams:
                return valueParams.isEmpty ? nil : "must have no value parameters"
            case .singleParam:
                return valueParams.count == 1 ? nil : "must have a single value parameter"
            case .atLeast(let minimum):
                return valueParams.count >= minimum
                    ? nil
                    : "must have at least \(minimum) value parameter" + (minimum > 1 ? "s" : "")
            case .atMost(let maximum):
                return valueParams.count <= maximum
                    ? nil
                    : "must have at most \(maximum) value parameter" + (maximum > 1 ? "s" : "")
            case .exactly(let count):
                return valueParams.count == count ? nil : "must have exactly \(count) value parameters"
            case .noDefaultAndVarargs:
                for param in valueParams {
                    if param.hasDefaultValue {
                        return "must not have parameters with default values"
                    }
                    if param.isVararg {
                        return "must not have varargs"
                    }
                }
                return nil
            case .lastParamNoDefaultOrVararg:
                if let last = valueParams.last, last.hasDefaultValue || last.isVararg {
                    return "last parameter must not have a default value or be a vararg"
                }
                return nil
            case .nonSuspend:
                return isSuspend ? "must not be suspend" : nil
            case .overridesAnyEquals:
                return valueParams.count == 1 ? nil : "must override 'equals()' in Any"
            }
        }
    }

    private static let memberConflictPairs: [(Modifiers, String, Modifiers, String)] = [
        (.abstract, "abstract", .final, "final"),
        (.final, "final", .open, "open"),
        (.private, "private", .open, "open"),
    ]

    private static let classConflictPairs: [(Modifiers, String, Modifiers, String)] = [
        (.abstract, "abstract", .final, "final"),
        (.sealed, "sealed", .final, "final"),
        (.final, "final", .open, "open"),
        (.data, "data", .inner, "inner"),
        (.data, "data", .open, "open"),
        (.data, "data", .abstract, "abstract"),
        (.data, "data", .sealed, "sealed"),
        (.data, "data", .value, "value"),
        (.inline, "inline", .data, "data"),
        (.sealed, "sealed", .open, "open"),
        (.sealed, "sealed", .inner, "inner"),
    ]

    /// Modifiers whose site diagnostic owns the error unless an earlier pair
    /// partner claims them — used as `invalidModifiers` for member pairs.
    private static func memberSiteInvalidModifiers(_ site: OwnerSite) -> Modifiers {
        switch site {
        case .file:
            [.abstract, .open, .final, .override, .protected]
        case .nominal(let nominal) where nominal.kind == .interface:
            [.final]
        default:
            []
        }
    }

    private static func modifierSet(_ list: [(Modifiers, String)]) -> Modifiers {
        list.reduce(Modifiers()) { $0.union($1.0) }
    }

    private static let funImpossibleModifiers: [(Modifiers, String)] = [
        (.data, "data"), (.sealed, "sealed"), (.inner, "inner"),
        (.enumModifier, "enum"), (.value, "value"), (.annotationClass, "annotation"),
        (.const, "const"), (.lateinit, "lateinit"),
        (.vararg, "vararg"), (.crossinline, "crossinline"), (.noinline, "noinline"),
        (.funModifier, "fun"),
    ]

    private static let topLevelFunForbidden: [(Modifiers, String)] = [
        (.abstract, "abstract"), (.open, "open"), (.final, "final"),
        (.override, "override"), (.protected, "protected"),
    ]

    private static let propertyImpossibleModifiers: [(Modifiers, String)] = [
        (.data, "data"), (.sealed, "sealed"), (.inner, "inner"),
        (.enumModifier, "enum"), (.value, "value"), (.annotationClass, "annotation"),
        (.suspend, "suspend"), (.tailrec, "tailrec"),
        (.inline, "inline"), (.operator, "operator"), (.infix, "infix"),
        (.external, "external"), (.vararg, "vararg"), (.crossinline, "crossinline"),
        (.noinline, "noinline"), (.funModifier, "fun"),
    ]

    private static let topLevelPropertyForbidden: [(Modifiers, String)] = [
        (.abstract, "abstract"), (.open, "open"), (.final, "final"),
        (.override, "override"), (.protected, "protected"),
    ]

    private static let classImpossibleModifiers: [(Modifiers, String)] = [
        (.const, "const"), (.lateinit, "lateinit"), (.suspend, "suspend"),
        (.tailrec, "tailrec"), (.operator, "operator"),
        (.infix, "infix"), (.vararg, "vararg"), (.crossinline, "crossinline"),
        (.noinline, "noinline"), (.funModifier, "fun"),
        (.companion, "companion"), (.override, "override"),
    ]

    private static let enumForbiddenModifiers: [(Modifiers, String)] = [
        (.open, "open"), (.abstract, "abstract"), (.sealed, "sealed"),
        (.data, "data"), (.inner, "inner"), (.value, "value"),
        (.annotationClass, "annotation"),
    ]

    private static let annotationForbiddenModifiers: [(Modifiers, String)] = [
        (.open, "open"), (.final, "final"), (.abstract, "abstract"),
        (.sealed, "sealed"), (.data, "data"), (.inner, "inner"),
        (.value, "value"), (.enumModifier, "enum"), (.companion, "companion"),
    ]

    private static let interfaceForbiddenModifiers: [(Modifiers, String)] = [
        (.open, "open"), (.final, "final"), (.inner, "inner"),
        (.data, "data"), (.value, "value"), (.enumModifier, "enum"),
        (.annotationClass, "annotation"), (.companion, "companion"),
        (.const, "const"), (.lateinit, "lateinit"), (.suspend, "suspend"),
        (.tailrec, "tailrec"), (.inline, "inline"), (.operator, "operator"),
        (.infix, "infix"), (.override, "override"),
        (.vararg, "vararg"), (.crossinline, "crossinline"), (.noinline, "noinline"),
    ]

    private static let objectImpossibleModifiers: [(Modifiers, String)] = [
        (.open, "open"), (.abstract, "abstract"), (.sealed, "sealed"),
        (.inner, "inner"), (.enumModifier, "enum"), (.value, "value"),
        (.annotationClass, "annotation"), (.const, "const"), (.lateinit, "lateinit"),
        (.suspend, "suspend"), (.tailrec, "tailrec"), (.inline, "inline"),
        (.operator, "operator"), (.infix, "infix"),
        (.override, "override"), (.vararg, "vararg"), (.crossinline, "crossinline"),
        (.noinline, "noinline"), (.funModifier, "fun"),
    ]

    /// `actual` is omitted: the orphan-actual symbol check
    /// (KSWIFTK-SEMA-0410) reports it with better context.
    private static let localClassForbiddenModifiers: [(Modifiers, String)] = [
        (.public, "public"), (.private, "private"), (.internal, "internal"),
        (.protected, "protected"), (.expect, "expect"),
        (.sealed, "sealed"), (.enumModifier, "enum"),
    ]

    /// On local objects (and, separately, local interfaces) kotlinc phrases
    /// non-default visibility positionally rather than as a kind conflict;
    /// `public` and `expect` go unreported there.
    private static let localNominalVisibilityModifiers: [(Modifiers, String)] = [
        (.private, "private"), (.internal, "internal"), (.protected, "protected"),
    ]

    private static let typeAliasForbiddenModifiers: [(Modifiers, String)] = [
        (.open, "open"), (.final, "final"), (.abstract, "abstract"),
        (.sealed, "sealed"), (.data, "data"), (.inner, "inner"),
        (.enumModifier, "enum"), (.value, "value"), (.annotationClass, "annotation"),
        (.companion, "companion"), (.const, "const"), (.lateinit, "lateinit"),
        (.suspend, "suspend"), (.tailrec, "tailrec"), (.inline, "inline"),
        (.operator, "operator"), (.infix, "infix"), (.external, "external"),
        (.override, "override"), (.funModifier, "fun"), (.vararg, "vararg"),
        (.crossinline, "crossinline"), (.noinline, "noinline"),
    ]

    private static let constructorParameterVisibilityModifiers: [(Modifiers, String)] = [
        (.public, "public"), (.private, "private"), (.internal, "internal"), (.protected, "protected"),
    ]
}
