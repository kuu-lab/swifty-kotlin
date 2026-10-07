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

    /// Syntactic owner a declaration is written inside.
    enum OwnerSite: Equatable {
        /// Top level of a Kotlin source file.
        case file
        /// A function/accessor/init body (a local declaration).
        case function
        /// Member of a nominal declaration.
        case nominal(NominalSite)

        /// Display name used in "not applicable inside 'X'" diagnostics.
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
        /// `true` for members of a local class / local named object.
        var isLocal: Bool
        /// Modifiers of the enclosing declaration (for expect-member rules).
        var ownerModifiers: Modifiers
        /// `true` when the owner has `init` blocks or secondary constructors
        /// that can assign stored member properties imperatively.
        var allowsImperativeInit: Bool = false

        var name: String {
            switch kind {
            case .class:
                return isLocal ? "local class" : "class"
            case .enum:
                return "enum class"
            case .interface:
                return "interface"
            case .object:
                return isLocal ? "local object" : "standalone object"
            case .companionObject:
                return "companion object"
            case .enumEntry:
                return "enum entry"
            case .annotationClass:
                return "annotation class"
            }
        }
    }

    // MARK: - Entry points

    /// Validate one declaration in the given syntactic site, then recurse
    /// into its members.
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

    /// Validate only the members of a nominal declaration. Used by the local
    /// nominal parser: the head modifiers are checked separately because the
    /// declaration itself is a local expression.
    func validateMembers(of declID: DeclID, site: OwnerSite) {
        guard let decl = astArena.decl(declID),
              case .nominal(let nominalSite) = site
        else {
            return
        }
        switch decl {
        case .classDecl(let classDecl):
            validateClassMembers(classDecl, site: nominalSite)
        case .objectDecl(let objectDecl):
            validateObjectMembers(objectDecl, site: nominalSite)
        case .interfaceDecl(let interfaceDecl):
            validateInterfaceMembers(interfaceDecl, site: nominalSite)
        case .funDecl, .propertyDecl, .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    // MARK: - Functions

    private func validateFunction(_ decl: FunDecl, site: OwnerSite) {
        let modifiers = decl.modifiers
        let target = functionTargetName(site: site)

        for (modifier, name) in Self.funImpossibleModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: target, range: decl.range)
        }

        switch site {
        case .file:
            for (modifier, name) in Self.topLevelFunForbidden where modifiers.contains(modifier) {
                emitNotApplicable(name, to: "top level function", range: decl.range)
            }
        case .function:
            break
        case .nominal(let nominal):
            validateInterfaceMemberModifiers(
                modifiers, site: nominal, range: decl.range
            )
            if nominal.kind == .object {
                if modifiers.contains(.protected) {
                    emitInside("protected", inside: nominal.name, range: decl.range)
                }
            }
            if modifiers.contains(.expect), !nominal.ownerModifiers.contains(.expect) {
                emitNotApplicable("expect", to: "member function", range: decl.range)
            }
            // `actual` members are covered by the orphan-actual symbol check
            // (KSWIFTK-SEMA-0410), which verifies expect-pairing directly.
        }

        if modifiers.contains(.operator),
           !Self.isLegalOperatorName(interner.resolve(decl.name))
        {
            diagnostics?.error(
                "KSWIFTK-SEMA-0416",
                "'operator' modifier is not applicable: illegal function name.",
                range: decl.range
            )
        }

        emitIncompatiblePairs(
            modifiers,
            pairs: [(.final, "final", .open, "open"), (.private, "private", .open, "open")],
            range: decl.range
        )

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

    // MARK: - Properties

    private func validateProperty(_ decl: PropertyDecl, site: OwnerSite) {
        // Primary-constructor `val`/`var` parameters are materialized as
        // member properties; their restrictions are checked on the class.
        if decl.isSynthesizedPrimaryConstructorProperty {
            return
        }
        let modifiers = decl.modifiers
        let target = propertyTargetName(site: site)

        for (modifier, name) in Self.propertyImpossibleModifiers where modifiers.contains(modifier) {
            if modifier == .inline, isTopLevelInlineGetterOnlyProperty(decl, site: site) {
                continue
            }
            emitNotApplicable(name, to: target, range: decl.range)
        }

        switch site {
        case .file:
            for (modifier, name) in Self.topLevelPropertyForbidden where modifiers.contains(modifier) {
                emitNotApplicable(name, to: "top level property", range: decl.range)
            }
        case .function:
            break
        case .nominal(let nominal):
            validateInterfaceMemberModifiers(
                modifiers, site: nominal, range: decl.range
            )
            if nominal.kind == .object, modifiers.contains(.protected) {
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

        emitIncompatiblePairs(
            modifiers,
            pairs: [(.final, "final", .open, "open"), (.private, "private", .open, "open")],
            range: decl.range
        )

        validatePropertyInitialization(decl, site: site)
    }

    private func isImplicitlyAbstractInterfaceProperty(_ decl: PropertyDecl) -> Bool {
        decl.initializer == nil && decl.getter == nil && decl.setter == nil
    }

    /// KUU-1459 covers top-level read-only properties with a custom getter and
    /// no declared storage. Keep this exception matched to that syntax.
    private func isTopLevelInlineGetterOnlyProperty(_ decl: PropertyDecl, site: OwnerSite) -> Bool {
        site == .file
            && !decl.isVar
            && decl.initializer == nil
            && decl.getter.map { $0.body != .unit } == true
            && decl.setter == nil
            && decl.delegateExpression == nil
            && decl.explicitBackingField == nil
    }

    private func validatePropertyInitialization(_ decl: PropertyDecl, site: OwnerSite) {
        let modifiers = decl.modifiers
        if modifiers.contains(.abstract)
            || modifiers.contains(.lateinit)
            || modifiers.contains(.expect)
            || modifiers.contains(.const)
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
            // Members of annotation classes are rejected wholesale elsewhere.
            if nominal.kind == .annotationClass {
                return
            }
            // Bodiless interface properties are implicitly abstract.
            if nominal.kind == .interface, isImplicitlyAbstractInterfaceProperty(decl) {
                return
            }
            // A class/object with init blocks or secondary constructors may
            // initialize stored properties imperatively.
            if nominal.allowsImperativeInit {
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
        let initialized = if decl.isVar {
            // A `var` is fieldless only when it has both a custom getter and
            // a non-empty custom setter; an empty setter acts as the default
            // (field-assigning) accessor and still needs an initializer.
            decl.getter != nil && decl.setter != nil && setterHasBody(decl.setter)
        } else {
            decl.getter != nil
        }
        if !initialized {
            let message = site == .file
                ? "property must be initialized."
                : "property must be initialized or be abstract."
            diagnostics?.error("KSWIFTK-SEMA-0424", message, range: decl.range)
        }
    }

    private func setterHasBody(_ setter: PropertyAccessorDecl?) -> Bool {
        guard let setter else {
            return false
        }
        switch setter.body {
        case .unit:
            return false
        case .expr:
            return true
        case .block(let exprs, _):
            return !exprs.isEmpty
        }
    }

    // MARK: - Classes

    private func validateClass(_ decl: ClassDecl, site: OwnerSite) {
        let modifiers = decl.modifiers
        let isEnum = modifiers.contains(.enumModifier)
        let isAnnotation = modifiers.contains(.annotationClass)
        let isValue = modifiers.contains(.value)
        let kindName: String
        if site == .function {
            kindName = "local class"
        } else if isEnum {
            kindName = "enum class"
        } else if isAnnotation {
            kindName = "annotation class"
        } else if isValue {
            kindName = "value class"
        } else {
            kindName = "class"
        }

        for (modifier, name) in Self.classImpossibleModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: kindName, range: decl.range)
        }
        if site == .function {
            for (modifier, name) in Self.localClassForbiddenModifiers where modifiers.contains(modifier) {
                emitNotApplicable(name, to: "local class", range: decl.range)
            }
            if modifiers.contains(.final) {
                emitInside("final", inside: "function", range: decl.range)
            }
            if isAnnotation {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0429",
                    "annotation class cannot be local.",
                    range: decl.range
                )
            }
        }
        if isEnum {
            for (modifier, name) in Self.enumForbiddenModifiers where modifiers.contains(modifier) {
                emitNotApplicable(name, to: "enum class", range: decl.range)
            }
        }
        if isAnnotation {
            for (modifier, name) in Self.annotationForbiddenModifiers where modifiers.contains(modifier) {
                emitNotApplicable(name, to: "annotation class", range: decl.range)
            }
        }
        if isValue {
            if modifiers.contains(.open)
                || modifiers.contains(.abstract)
                || modifiers.contains(.sealed)
            {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0420",
                    "value class can be only final.",
                    range: decl.range
                )
            }
        }

        if site == .file, modifiers.contains(.protected) {
            emitNotApplicable("protected", to: "top level class", range: decl.range)
        }

        validateInnerPosition(modifiers, site: site, target: kindName, range: decl.range)
        if case .nominal(let nominal) = site {
            validateMemberSiteModifiers(modifiers, site: nominal, target: "member class", range: decl.range)
        }

        emitIncompatiblePairs(
            modifiers,
            pairs: [
                (.final, "final", .open, "open"),
                (.data, "data", .inner, "inner"),
                (.data, "data", .open, "open"),
                (.data, "data", .abstract, "abstract"),
                (.data, "data", .sealed, "sealed"),
                (.data, "data", .value, "value"),
                (.sealed, "sealed", .open, "open"),
                (.sealed, "sealed", .inner, "inner"),
            ],
            range: decl.range
        )

        if modifiers.contains(.data), decl.primaryConstructorParams.isEmpty {
            diagnostics?.error(
                "KSWIFTK-SEMA-0404",
                "data class must have at least one primary constructor parameter.",
                range: decl.range
            )
        }

        if isValue {
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
                + decl.nestedClasses.count
                + decl.nestedObjects.count
                + decl.nestedTypeAliases.count
                + decl.initBlocks.count
                + decl.secondaryConstructors.count
                + (decl.companionObject == nil ? 0 : 1)
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
            allowsImperativeInit: !decl.initBlocks.isEmpty || !decl.secondaryConstructors.isEmpty
        )
        validateClassMembers(decl, site: memberSite)
    }

    private func validateClassMembers(_ decl: ClassDecl, site: NominalSite) {
        // Annotation-class members are already reported wholesale.
        guard site.kind != .annotationClass else {
            return
        }
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
        for entry in decl.enumEntries {
            let entrySite = OwnerSite.nominal(NominalSite(
                kind: .enumEntry,
                isLocal: site.isLocal,
                ownerModifiers: []
            ))
            for declID in entry.memberFunctions {
                validate(declID: declID, site: entrySite)
            }
            for declID in entry.memberProperties {
                validate(declID: declID, site: entrySite)
            }
        }
    }

    // MARK: - Interfaces

    private func validateInterface(_ decl: InterfaceDecl, site: OwnerSite) {
        let modifiers = decl.modifiers

        for (modifier, name) in Self.interfaceForbiddenModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: "interface", range: decl.range)
        }

        if site == .file, modifiers.contains(.protected) {
            emitNotApplicable("protected", to: "top level interface", range: decl.range)
        }
        validateInnerPosition(modifiers, site: site, target: "interface", range: decl.range)
        if case .nominal(let nominal) = site {
            validateMemberSiteModifiers(modifiers, site: nominal, target: "member interface", range: decl.range)
        }

        if decl.isFunInterface, decl.superTypes.isEmpty {
            let abstractFunctions = decl.memberFunctions.filter { declID in
                guard let memberDecl = astArena.decl(declID),
                      case .funDecl(let fun) = memberDecl
                else {
                    return false
                }
                return !fun.modifiers.contains(.override)
                    && (fun.modifiers.contains(.abstract) || fun.body == .unit)
            }
            if abstractFunctions.count != 1 {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0406",
                    "functional interface must have exactly one abstract function.",
                    range: decl.range
                )
            }
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

    // MARK: - Objects

    private func validateObject(_ decl: ObjectDecl, site: OwnerSite) {
        let modifiers = decl.modifiers
        let kindName = site == .function ? "local object" : "standalone object"

        for (modifier, name) in Self.objectImpossibleModifiers where modifiers.contains(modifier) {
            emitNotApplicable(name, to: kindName, range: decl.range)
        }
        if site == .function {
            for (modifier, name) in Self.localNominalForbiddenModifiers where modifiers.contains(modifier) {
                emitNotApplicable(name, to: "local object", range: decl.range)
            }
        }

        if modifiers.contains(.companion) {
            let allowed: Bool = switch site {
            case .nominal(let nominal):
                !nominal.isLocal
                    && (nominal.kind == .class || nominal.kind == .enum || nominal.kind == .interface)
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
            allowsImperativeInit: !decl.initBlocks.isEmpty
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

    // MARK: - Type aliases

    private func validateTypeAlias(_ decl: TypeAliasDecl, site: OwnerSite) {
        for (modifier, name) in Self.typeAliasForbiddenModifiers where decl.modifiers.contains(modifier) {
            emitNotApplicable(name, to: "typealias", range: decl.range)
        }
        if site == .file, decl.modifiers.contains(.protected) {
            emitNotApplicable("protected", to: "top level typealias", range: decl.range)
        }
    }

    // MARK: - Shared modifier checks

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
            emitNotApplicable("inner", to: "top level \(target)", range: range)
        case .function:
            emitInside("inner", inside: "function", range: range)
        case .nominal(let nominal):
            switch nominal.kind {
            case .class, .enum, .enumEntry:
                break
            case .interface, .object, .companionObject, .annotationClass:
                emitInside("inner", inside: nominal.name, range: range)
            }
        }
    }

    /// Interface-member and nominal-member modifier restrictions shared by
    /// functions, properties, classes and objects.
    private func validateInterfaceMemberModifiers(
        _ modifiers: Modifiers,
        site: NominalSite,
        range: SourceRange
    ) {
        guard site.kind == .interface else {
            return
        }
        // `protected` inside interfaces is diagnosed by the
        // open/final/override pass (KUU-1406) and intentionally not repeated.
        if modifiers.contains(.internal) {
            emitInside("internal", inside: "interface", range: range)
        }
        if modifiers.contains(.final) {
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

    /// Member-site restrictions applied to nested nominal declarations.
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

    private func emitIncompatiblePairs(
        _ modifiers: Modifiers,
        pairs: [(Modifiers, String, Modifiers, String)],
        range: SourceRange
    ) {
        for (first, firstName, second, secondName) in pairs {
            if modifiers.contains(first), modifiers.contains(second) {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0402",
                    "modifier '\(firstName)' is incompatible with '\(secondName)'.",
                    range: range
                )
            }
        }
    }

    // MARK: - Helpers

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

    // MARK: - Modifier tables

    /// Function names that legally carry the `operator` modifier.
    static func isLegalOperatorName(_ name: String) -> Bool {
        if legalOperatorNames.contains(name) {
            return true
        }
        if name.hasPrefix("component"),
           let suffix = Int(name.dropFirst("component".count)),
           suffix >= 1
        {
            return true
        }
        return false
    }

    private static let legalOperatorNames: Set<String> = [
        "unaryPlus", "unaryMinus", "not", "inc", "dec",
        "plus", "minus", "times", "div", "rem", "mod",
        "plusAssign", "minusAssign", "timesAssign", "divAssign", "remAssign", "modAssign",
        "rangeTo", "rangeUntil", "contains",
        "get", "set", "invoke", "iterator", "next", "hasNext",
        "compareTo", "equals", "provideDelegate", "getValue", "setValue",
    ]

    /// Modifier spellings keyed by bit, in declaration order, for iteration.
    private static let funImpossibleModifiers: [(Modifiers, String)] = [
        (.data, "data"), (.sealed, "sealed"), (.inner, "inner"),
        (.enumModifier, "enum"), (.value, "value"), (.annotationClass, "annotation"),
        (.companion, "companion"), (.const, "const"), (.lateinit, "lateinit"),
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
        (.companion, "companion"), (.suspend, "suspend"), (.tailrec, "tailrec"),
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
        (.tailrec, "tailrec"), (.inline, "inline"), (.operator, "operator"),
        (.infix, "infix"), (.vararg, "vararg"), (.crossinline, "crossinline"),
        (.noinline, "noinline"), (.funModifier, "fun"), (.external, "external"),
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
        (.infix, "infix"), (.external, "external"), (.override, "override"),
        (.vararg, "vararg"), (.crossinline, "crossinline"), (.noinline, "noinline"),
    ]

    private static let objectImpossibleModifiers: [(Modifiers, String)] = [
        (.open, "open"), (.abstract, "abstract"), (.sealed, "sealed"),
        (.inner, "inner"), (.enumModifier, "enum"), (.value, "value"),
        (.annotationClass, "annotation"), (.const, "const"), (.lateinit, "lateinit"),
        (.suspend, "suspend"), (.tailrec, "tailrec"), (.inline, "inline"),
        (.operator, "operator"), (.infix, "infix"), (.external, "external"),
        (.override, "override"), (.vararg, "vararg"), (.crossinline, "crossinline"),
        (.noinline, "noinline"), (.funModifier, "fun"),
    ]

    /// Position-restricted modifiers on a local class (`inside 'function'`
    /// diagnostics are emitted separately for `final`/`inner`).
    /// `actual` is omitted: the orphan-actual symbol check
    /// (KSWIFTK-SEMA-0410) reports it with better context.
    private static let localClassForbiddenModifiers: [(Modifiers, String)] = [
        (.public, "public"), (.private, "private"), (.internal, "internal"),
        (.protected, "protected"), (.expect, "expect"),
        (.sealed, "sealed"), (.enumModifier, "enum"),
    ]

    /// Position-restricted modifiers on a local named object. Kind-impossible
    /// modifiers are already covered by `objectImpossibleModifiers`.
    private static let localNominalForbiddenModifiers: [(Modifiers, String)] = [
        (.public, "public"), (.private, "private"), (.internal, "internal"),
        (.protected, "protected"), (.expect, "expect"),
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
}
