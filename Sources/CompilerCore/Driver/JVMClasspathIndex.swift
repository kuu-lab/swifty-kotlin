import Foundation

/// Classpath lookup follows the caller's entry order. ZIP decoding is shared
/// with KLIB, including bounded entry reads and CRC validation.
final class JVMClasspathIndex {
    var classes: [String: JVMClassInfo] = [:]
    var sourceClasses: [FileID: JVMClassInfo] = [:]
    var methods: [SymbolID: JVMForeignMethod] = [:]
    var extensionSymbols: Set<SymbolID> = []
    /// Classes loaded from `lazilyInjecting` classpath entries (the Android
    /// `android.jar`). They stay indexed for signature mapping and d8 input,
    /// but `inject(into:)` only emits Kotlin stubs for the subset reachable
    /// from user sources — injecting the whole framework would create
    /// hundreds of thousands of symbols.
    private(set) var lazyClassNames: Set<String> = []
    private var hierarchyClasses: [String: JVMClassInfo] = [:]
    private var innerClassMetadata: [String: JVMInnerClassInfo] = [:]
    /// Covered names for the `inject(into:)` run in progress; supertypes that
    /// resolve to bundled/synthetic Kotlin declarations rather than stubs.
    private var activeCoveredNames: Set<String> = []

    static func load(_ paths: [String], lazilyInjecting lazyPaths: Set<String> = []) throws -> JVMClasspathIndex {
        let result = JVMClasspathIndex()
        var seen: Set<String> = []
        func insert(_ bytes: [UInt8], path: String) throws {
            var reader = JVMClassReader(bytes: bytes)
            let info = try reader.read()
            guard info.name + ".class" == path else { throw JVMFrontendError(message: "JVM class name does not match entry path: \(info.name) in \(path)") }
            guard seen.insert(info.name).inserted else { return }
            result.hierarchyClasses[info.name] = info
        }
        for path in paths {
            let isLazy = lazyPaths.contains(URL(fileURLWithPath: path).standardizedFileURL.path)
            let priorKeys = isLazy ? Set(result.hierarchyClasses.keys) : []
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else {
                throw JVMFrontendError(message: "JVM classpath entry does not exist: \(path)")
            }
            if directory.boolValue {
                let base = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
                guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { throw JVMClassReader.Invalid() }
                let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "class" }.sorted { $0.path < $1.path }
                for file in files {
                    let relative = file.resolvingSymlinksInPath().pathComponents.dropFirst(base.pathComponents.count).joined(separator: "/")
                    guard !relative.hasPrefix("META-INF/"), !relative.hasSuffix("module-info.class"), !relative.hasSuffix("package-info.class") else { continue }
                    try insert(Array(Data(contentsOf: file)), path: relative)
                }
            } else {
                let archive = try ZipArchive(data: Data(contentsOf: URL(fileURLWithPath: path)))
                for entry in archive.entries.sorted(by: { $0.name < $1.name }) {
                    guard entry.name.hasSuffix(".class"), !entry.name.hasPrefix("META-INF/"),
                          !entry.name.hasSuffix("module-info.class"), !entry.name.hasSuffix("package-info.class") else { continue }
                    try insert(archive.contents(of: entry), path: entry.name)
                }
            }
            if isLazy {
                result.lazyClassNames.formUnion(
                    result.hierarchyClasses.keys.filter { !priorKeys.contains($0) }
                )
            }
        }
        result.indexInnerClasses()
        for info in result.hierarchyClasses.values where result.isImportableClassifier(info.name, visited: []) {
            result.classes[info.name] = info
        }
        result.importInheritedMembers()
        return result
    }

    private func indexInnerClasses() {
        var ownersWithAuthoritativeMetadata: Set<String> = []
        for info in hierarchyClasses.values where info.hasInnerClassesAttribute {
            ownersWithAuthoritativeMetadata.insert(info.name)
            for entry in info.innerClasses where entry.outerName == info.name {
                innerClassMetadata[entry.name] = entry
            }
        }
        for info in hierarchyClasses.values {
            guard let selfEntry = info.innerClasses.first(where: { $0.name == info.name }),
                  let outer = selfEntry.outerName,
                  !ownersWithAuthoritativeMetadata.contains(outer),
                  innerClassMetadata[selfEntry.name] == nil else { continue }
            innerClassMetadata[selfEntry.name] = selfEntry
        }
    }

    private func isImportableClassifier(_ name: String, visited: Set<String>) -> Bool {
        guard !visited.contains(name), let info = hierarchyClasses[name],
              info.flags & 0x1000 == 0, !info.hasEnclosingMethod else { return false }
        if let entry = innerClassMetadata[name] {
            guard let outer = entry.outerName, let shortName = entry.innerName,
                  [UInt16(1), UInt16(4)].contains(entry.access & 0x0007), entry.access & 0x1000 == 0,
                  JVMProgramBuilder.isIdentifier(shortName), name.hasPrefix(outer + "$"),
                  isImportableClassifier(outer, visited: visited.union([name])) else { return false }
            return true
        }
        guard info.flags & 1 != 0, !name.contains("$"),
              name.split(separator: "/").allSatisfy({ JVMProgramBuilder.isIdentifier(String($0)) }) else { return false }
        return true
    }

    private func nestedClassDeclarations(of owner: String, indentation: String = "    ") -> String {
        let children = innerClassMetadata.values
            .filter { $0.outerName == owner && classes[$0.name] != nil }
            .sorted { ($0.innerName ?? "") < ($1.innerName ?? "") }
        var source = ""
        for entry in children {
            guard let name = entry.innerName, let info = classes[entry.name] else { continue }
            let typeParameters = info.classTypeParameterNames.isEmpty
                ? ""
                : "<" + info.classTypeParameterNames.map { "`\($0)`" }.joined(separator: ", ") + ">"
            let visibility = entry.access & 0x0007 == 0x0004 ? "protected " : ""
            if info.flags & 0x2000 != 0 {
                source += indentation + visibility + "annotation class `\(name)`\(typeParameters)\n"
                continue
            }
            if info.flags & 0x4000 != 0 {
                source += indentation + visibility + "enum class `\(name)`\(typeParameters) { }\n"
                continue
            }
            if info.isInterface {
                source += indentation + visibility + "interface `\(name)`\(typeParameters)"
            } else {
                let classKind = info.flags & 0x0400 != 0 ? "abstract class " : (info.flags & 0x0010 != 0 ? "class " : "open class ")
                let isInner = entry.access & 0x0008 == 0
                source += indentation + visibility + (isInner ? "inner " : "") + classKind + "`\(name)`\(typeParameters) private constructor()"
            }
            var parents: [String] = []
            if !info.isInterface, let base = info.superclass, classes[base] != nil,
               let mapped = supertypeReference(base, childParams: info.classTypeParameterNames) {
                parents.append(mapped + "()")
            }
            parents += info.interfaces.filter { classes[$0] != nil }.compactMap { supertypeReference($0, childParams: info.classTypeParameterNames) }
            if !parents.isEmpty { source += " : " + parents.joined(separator: ", ") }
            source += " {\n"
            // Kotlin forbids companion objects inside inner (non-static
            // member) classes; their statics are unreachable anyway.
            source += memberDeclarations(info: info, members: info.methods,
                                         allowsCompanion: entry.access & 0x0008 != 0)
            source += nestedClassDeclarations(of: entry.name, indentation: indentation + "    ")
            source += indentation + "}\n"
        }
        return source
    }

    private func importInheritedMembers() {
        func key(_ method: JVMForeignMethod) -> String {
            method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
        }
        func accessibleMethod(_ method: JVMForeignMethod, on info: JVMClassInfo) -> JVMForeignMethod {
            var result = JVMForeignMethod(owner: info.name, name: method.name, descriptor: method.descriptor, parameters: method.parameters,
                                          result: method.result, isStatic: method.isStatic, isInterface: info.isInterface, isAbstract: method.isAbstract)
            result.isFinal = method.isFinal; result.isSpecial = method.isSpecial; result.isSuspend = method.isSuspend
            return result
        }
        func interfaceInherits(_ subtype: String, _ supertype: String, visited: Set<String> = []) -> Bool {
            if subtype == supertype { return true }
            guard !visited.contains(subtype), let info = hierarchyClasses[subtype] else { return false }
            return info.interfaces.contains { interfaceInherits($0, supertype, visited: visited.union([subtype])) }
        }
        for info in classes.values {
            var methods = info.methods
            var bridges = info.bridgeMethods
            var interfaces: [String] = []
            var inheritedInterfaces = info.interfaces
            var interfaceVisited: Set<String> = []
            var interfaceMethods: [String: JVMForeignMethod] = [:]
            func inheritInterface(_ name: String) {
                guard interfaceVisited.insert(name).inserted, let base = hierarchyClasses[name] else { return }
                if classes[name] != nil { interfaces.append(name); return }
                bridges += base.bridgeMethods
                for method in base.methods where !method.isStatic && !method.isConstructor {
                    let signature = key(method)
                    if !methods.contains(where: { key($0) == signature }),
                       interfaceMethods[signature].map({ interfaceInherits(method.owner, $0.owner) }) ?? true {
                        // The most specific interface wins independently of the
                        // order of redundant interfaces in the classfile.
                        interfaceMethods[signature] = method
                    }
                }
                for parent in base.interfaces { inheritInterface(parent) }
            }
            var visited: Set<String> = [info.name]
            var next = info.superclass
            var superclass: String?
            var hiddenSegment = true
            while let name = next, visited.insert(name).inserted, let base = hierarchyClasses[name] {
                let visible = classes[name] != nil
                if visible && superclass == nil { superclass = name; hiddenSegment = false }
                for method in base.methods where !method.isConstructor && (method.isStatic || hiddenSegment) {
                    if !methods.contains(where: { key($0) == key(method) }) {
                        // A method reference must name an accessible class even
                        // when its implementation is inherited from a hidden base.
                        methods.append(visible ? method : accessibleMethod(method, on: info))
                    }
                }
                if hiddenSegment {
                    bridges += base.bridgeMethods
                    inheritedInterfaces += base.interfaces
                }
                next = base.superclass
            }
            for name in inheritedInterfaces { inheritInterface(name) }
            methods += interfaceMethods.keys.sorted().map { accessibleMethod(interfaceMethods[$0]!, on: info) }
            var abstractMethods: Set<String> = []
            var abstractVisited: Set<String> = []
            func collectAbstract(_ name: String) {
                guard abstractVisited.insert(name).inserted, let base = hierarchyClasses[name] else { return }
                for method in base.methods where method.isAbstract { abstractMethods.insert(key(method)) }
                for parent in base.interfaces { collectAbstract(parent) }
                if let parent = base.superclass { collectAbstract(parent) }
            }
            for name in interfaces { collectAbstract(name) }
            if let superclass { collectAbstract(superclass) }
            // Erased imports need a real bridge when an inherited raw method
            // has different parameters from the specialized implementation.
            for bridge in bridges where abstractMethods.contains(key(bridge)) && !methods.contains(where: { key($0) == key(bridge) }) {
                methods.append(accessibleMethod(bridge, on: info))
            }
            var imported = JVMClassInfo(name: info.name, flags: info.flags, superclass: superclass, interfaces: interfaces, methods: methods, fields: info.fields)
            imported.bridgeMethods = bridges
            imported.classTypeParameterNames = info.classTypeParameterNames
            imported.innerClasses = info.innerClasses
            imported.hasInnerClassesAttribute = info.hasInnerClassesAttribute
            imported.hasEnclosingMethod = info.hasEnclosingMethod
            classes[info.name] = imported
        }
    }
    func expose(_ type: JVMValueType) -> Bool {
        guard let name = type.referenceName else { return true }
        // Erased function interfaces require Kotlin function-type metadata;
        // their raw Java signatures are not importable declarations.
        if name.hasPrefix("kotlin/jvm/functions/Function") { return false }
        if name.hasPrefix("["), let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 { return expose(element) }
        return name == "java/lang/String" || name == "java/lang/Object" || classes[name] != nil
    }
    func hasClassFile(_ name: String) -> Bool { hierarchyClasses[name] != nil }
    func kotlinType(_ type: JVMValueType) -> String {
        switch type {
        case .byte: return "kotlin.Byte"
        case .short: return "kotlin.Short"
        case .char: return "kotlin.Char"
        case .uint: return "kotlin.UInt"
        case .ulong: return "kotlin.ULong"
        case .ubyte: return "kotlin.UByte"
        case .ushort: return "kotlin.UShort"
        case let .unsignedArray(p, nullable): return "kotlin." + p.kotlinName + "Array" + (nullable ? "?" : "")
        case .int: return "kotlin.Int"
        case .long: return "kotlin.Long"
        case .float: return "kotlin.Float"
        case .double: return "kotlin.Double"
        case .boolean: return "kotlin.Boolean"
        case .unit: return "kotlin.Unit"
        case .string: return "kotlin.String"
        case let .reference(name, _, _):
            let base: String
            if name.hasPrefix("["), let element = try? JVMDescriptor.parse("()" + String(name.dropFirst())).1 {
                if let primitive = Self.primitiveArrays.first(where: { $0.value == element }) { return "kotlin." + primitive.key }
                return "kotlin.Array<" + kotlinType(element) + ">"
            }
            switch name {
            case "java/lang/String": return "kotlin.String"
            case "java/lang/Object": return "kotlin.Any"
            default:
                // Mirror kotlinc's JDK->Kotlin mapped types so foreign
                // signatures render as the Kotlin declarations users expect
                // (and so lazy classpath entries don't need java.* stubs for
                // types the Kotlin standard library already covers).
                if let mapped = Self.jdkToKotlinTypeNames[name] { return mapped }
                base = Self.dottedTypeName(name)
            }
            // Classfiles do not retain Kotlin nullability without metadata. Use
            // non-null source declarations as the current platform-type approximation.
            return base
        }
    }
    /// Supertype positions keep the erased JDK name: Kotlin mapped types
    /// declare property-style members that Java method stubs cannot satisfy,
    /// so `extends`/`implements` clauses must name the interface the
    /// classfile actually declares. Only `java.lang.Object`/`String` still
    /// collapse to their Kotlin aliases, and `Enum`/`Record` cannot be
    /// extended directly.
    func kotlinSupertypeName(_ name: String) -> String? {
        switch name {
        case "java/lang/Object": return "kotlin.Any"
        case "java/lang/String": return "kotlin.String"
        case "java/lang/Enum", "java/lang/Record": return nil
        default:
            // Covered classes get no stub, so an erased `java.*` supertype
            // would not resolve. When the JDK->Kotlin mapped-type table names
            // a provided Kotlin counterpart (kotlin.Number, kotlin.text
            // .Appendable, ...), emit that instead; generic arguments are
            // appended by `supertypeReference`.
            if activeCoveredNames.contains(name),
               let mapped = Self.jdkToKotlinTypeNames[name] {
                return mapped.split(separator: "<").first.map(String.init) ?? mapped
            }
            return Self.dottedTypeName(name)
        }
    }
    /// Binary names use `$` for nested classes; Kotlin source spells them
    /// with dots (`a/b/C$D` -> `a.b.C.D`).
    private static func dottedTypeName(_ name: String) -> String {
        name.split(separator: "/").flatMap { $0.split(separator: "$") }
            .map { "`\($0)`" }.joined(separator: ".")
    }
    /// Supertype reference with type arguments: classfiles erase generic
    /// arguments, so the child's own type parameters are reused when the
    /// arity matches (the usual Java convention) and `kotlin.Any` fills the
    /// rest. `Any` keeps erased bridge members (e.g. `compare(Object, Object)`)
    /// valid overrides, unlike star projections whose captured types cannot
    /// be overridden at all.
    private func supertypeReference(_ name: String, childParams: [String]) -> String? {
        guard let base = kotlinSupertypeName(name) else { return nil }
        let arity = hierarchyClasses[name]?.classTypeParameterNames.count ?? 0
        guard arity > 0 else { return base }
        let args = arity == childParams.count && arity > 0
            ? childParams
            : Array(repeating: "kotlin.Any", count: arity)
        return base + "<" + args.joined(separator: ", ") + ">"
    }
    private func isSAM(_ name: String) -> Bool {
        var members: [String: JVMForeignMethod] = [:], visited: Set<String> = []
        func visit(_ name: String) {
            guard visited.insert(name).inserted, let info = classes[name] else { return }
            for parent in info.interfaces { visit(parent) }
            for method in info.methods where !method.isStatic && !method.isConstructor {
                if ["equals(Ljava/lang/Object;)Z", "hashCode()I", "toString()Ljava/lang/String;"].contains(method.name + method.descriptor) { continue }
                let key = method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
                members[key] = method
            }
        }
        visit(name)
        let abstracts = members.values.filter(\.isAbstract)
        guard abstracts.count == 1, let sam = abstracts.first else { return false }
        // Getter-shaped members are also emitted as `val` properties; when
        // the single abstract member has that shape the `fun interface`
        // form is rejected, so emit a plain interface instead.
        if sam.parameters.isEmpty,
           (sam.name.hasPrefix("get") && sam.name.count > 3
               || sam.name.hasPrefix("is") && sam.name.count > 2 && sam.result == .boolean) {
            return false
        }
        return true
    }
    /// Binary class names the frontend already provides: bundled JVM stdlib
    /// sources (which include the JDK platform declarations, scanned after
    /// they are injected) plus synthetic java.* compatibility decls that
    /// `nominalNames` cannot see, and the String/Object anchors `kotlinType`
    /// maps onto kotlin.String/kotlin.Any. kotlin.*-mapped JDK names are
    /// deliberately NOT covered: the Kotlin declarations are compile-time
    /// views, so the erased classfile still has to come from a stub.
    private func coveredClassNames(in ctx: CompilationContext) throws -> Set<String> {
        var covered = try JVMStdlibCatalog.nominalNames(in: ctx)
        covered.formUnion(Self.syntheticJavaNames)
        covered.insert("java/lang/String")
        covered.insert("java/lang/Object")
        // kotlin.CharSequence is the mapped-type counterpart of
        // java.lang.CharSequence; covering it keeps stub signatures and
        // supertypes on the same Kotlin nominal.
        covered.insert("java/lang/CharSequence")
        return covered
    }

    private func isCovered(_ name: String, covered: Set<String>) -> Bool {
        name.hasPrefix("kotlin/") || covered.contains(name)
    }

    func inject(into ctx: CompilationContext) throws {
        let covered = try coveredClassNames(in: ctx)
        activeCoveredNames = covered
        let neededLazy = lazyClassNames.isEmpty ? nil : referencedLazyClasses(into: ctx, covered: covered)
        for info in classes.values.sorted(by: { $0.name < $1.name }) {
            guard innerClassMetadata[info.name] == nil else { continue }
            // The frontend's Kotlin/JDK mapped declarations carry generic source
            // types. Importing the same erased class again would shadow them.
            if isCovered(info.name, covered: covered) { continue }
            let isLazy = lazyClassNames.contains(info.name)
            if isLazy, neededLazy?.contains(info.name) != true { continue }
            let parts = info.name.split(separator: "/").map(String.init)
            guard let short = parts.last else { throw JVMClassReader.Invalid() }
            let package = parts.dropLast().map { "`\($0)`" }.joined(separator: ".")
            var source = package.isEmpty ? "" : "package \(package)\n"
            let own = info.methods.filter { $0.parameters.allSatisfy(expose) && expose($0.result) && ($0.isConstructor || JVMProgramBuilder.isIdentifier($0.name)) }
            let statics = own.filter(\.isStatic)
            let isFileFacade = short.hasSuffix("Kt")
            if isFileFacade {
                // The facade class itself stays importable: `import api.HelloKt`
                // resolves the nominal and `HelloKt.member(...)` reaches its
                // statics through the companion, matching Kotlin/JVM.
                source += "class `\(short)` private constructor() {\n"
                if !statics.isEmpty {
                    source += "companion object {\n"
                    for method in statics {
                        source += "external fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result) + "\n"
                    }
                    source += "}\n"
                }
                source += "}\n"
                for method in statics {
                    source += "external fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result) + "\n"
                    // A JVM file-facade descriptor does not distinguish a
                    // top-level function from an extension receiver. Expose
                    // the receiver form as well so Kotlin member syntax binds
                    // to the same static method.
                    if let receiver = method.parameters.first,
                       case .reference = receiver, receiver.referenceName?.hasPrefix("[") != true {
                        let rest = method.parameters.dropFirst().enumerated().map {
                            "p\($0.offset): " + kotlinType($0.element)
                        }.joined(separator: ", ")
                        source += "external fun \(kotlinType(receiver)).`\(method.name)`(\(rest)): \(kotlinType(method.result))\n"
                    }
                }
            } else {
                if info.isInterface {
                    source += isSAM(info.name) ? "fun interface `\(short)`" : "interface `\(short)`"
                    if !info.classTypeParameterNames.isEmpty {
                        source += "<" + info.classTypeParameterNames.map { "`\($0)`" }.joined(separator: ", ") + ">"
                    }
                }
                else {
                    source += info.flags & 0x0400 != 0 ? "abstract class " : (info.flags & 0x0010 != 0 ? "class " : "open class ")
                    source += "`\(short)`"
                    if !info.classTypeParameterNames.isEmpty {
                        source += "<" + info.classTypeParameterNames.map { "`\($0)`" }.joined(separator: ", ") + ">"
                    }
                    source += " "
                    source += own.contains(where: { $0.isConstructor && $0.parameters.isEmpty && !$0.isProtected })
                        ? "()" : "protected constructor()"
                }
                var parents: [String] = []
                if !info.isInterface, let base = info.superclass, classes[base] != nil,
                   let mapped = supertypeReference(base, childParams: info.classTypeParameterNames) {
                    parents.append(mapped + "()")
                }
                parents += info.interfaces.filter { classes[$0] != nil }.compactMap { supertypeReference($0, childParams: info.classTypeParameterNames) }
                if !parents.isEmpty { source += " : " + parents.joined(separator: ", ") }
                source += " {\n"
                source += memberDeclarations(info: info, members: info.methods)
                source += nestedClassDeclarations(of: info.name)
                source += "}\n"
            }
            let path = "<kswiftk-jvm-import>/" + info.name + ".kt"
            guard !ctx.sourceManager.containsFile(path: path) else { throw JVMClassReader.Invalid() }
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
        }
    }

    /// Member declarations shared by top-level stubs and nested-class shells:
    /// constructors, methods, synthesized properties, and the statics
    /// companion. Emitted without indentation; Kotlin is brace-delimited.
    private func memberDeclarations(info: JVMClassInfo, members: [JVMForeignMethod], allowsCompanion: Bool = true) -> String {
        let own = members.filter { $0.parameters.allSatisfy(expose) && expose($0.result) && ($0.isConstructor || JVMProgramBuilder.isIdentifier($0.name)) }
        let statics = own.filter(\.isStatic)
        // Covered Java supertypes render as Kotlin mapped types whose
        // member names differ from the erased classfile signatures; bridge
        // the differences explicitly (see kotlinSupertypeName).
        let numberBridged = !info.isInterface && inheritsJavaType(info, "java/lang/Number")
        let charSequenceBridged = inheritsJavaType(info, "java/lang/CharSequence")
        let appendableBridged = inheritsJavaType(info, "java/lang/Appendable")
        /// kotlin.CharSequence's `get(index: Int): Char` member: either the
        /// classfile's own `get(int)` or a synthesized delegate over `charAt`.
        func isCharSequenceGet(_ method: JVMForeignMethod) -> Bool {
            method.name == "get" && method.parameters.count == 1
                && kotlinType(method.parameters[0]) == "kotlin.Int"
                && kotlinType(method.result) == "kotlin.Char"
        }
        /// The three kotlin.text.Appendable members, matched on erased
        /// parameter types so unrelated `append` overloads stay plain.
        func isAppendableMember(_ method: JVMForeignMethod) -> Bool {
            let types = method.parameters.map { kotlinType($0) }
            return (types.count == 1 && ["kotlin.Char", "kotlin.CharSequence"].contains(types[0]))
                || (types.count == 3 && types[0] == "kotlin.CharSequence" && types[1] == "kotlin.Int" && types[2] == "kotlin.Int")
        }
        var source = ""
        for method in own where method.isConstructor && !method.parameters.isEmpty {
            source += (method.isProtected ? "protected " : "") + "constructor(" + parameters(method) + ") : this() {}\n"
        }
        for method in own where !method.isConstructor && !method.isStatic {
            var overrides = overridesParent(method, in: info, visited: [])
            if charSequenceBridged, method.name == "subSequence" { overrides = true }
            if charSequenceBridged, isCharSequenceGet(method) { overrides = true }
            if appendableBridged, isAppendableMember(method) { overrides = true }
            if method.isProtected { source += "protected " }
            if !info.isInterface && method.isFinal { source += "final " }
            source += overrides ? "override " : ""
            if !info.isInterface { source += overrides || method.isFinal ? "" : "open " }
            if method.name == "get", method.parameters.count == 1 { source += "operator " }
            if !info.isInterface { source += "external " }
            source += "fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result)
            if info.isInterface, !method.isAbstract {
                source += method.result == .unit ? " {}" : " = null!!"
                // A default method with a primitive result still has a
                // Nothing-typed stub body; it is never emitted or executed.
            }
            source += "\n"
        }
        for getter in own where !getter.isConstructor && !getter.isStatic && getter.parameters.isEmpty {
            let propertyName: String
            if getter.name.hasPrefix("get"), getter.name.count > 3 {
                let suffix = String(getter.name.dropFirst(3))
                propertyName = String(suffix.prefix(1)).lowercased() + suffix.dropFirst()
            } else if getter.name.hasPrefix("is"), getter.name.count > 2, getter.result == .boolean {
                propertyName = getter.name
            } else { continue }
            guard JVMProgramBuilder.isIdentifier(propertyName),
                  !own.contains(where: { !$0.isStatic && !$0.isConstructor && $0.name == propertyName }) else { continue }
            if getter.isProtected { source += "protected " }
            if !info.isInterface && getter.isFinal { source += "final " }
            if overridesParent(getter, in: info, visited: []) { source += "override " }
            else if !info.isInterface && !getter.isFinal { source += "open " }
            source += "val `\(propertyName)`: \(kotlinType(getter.result)) get() = `\(getter.name)`()\n"
        }
        if charSequenceBridged, !own.contains(where: { isCharSequenceGet($0) && !$0.isStatic }),
           let charAt = own.first(where: {
               $0.name == "charAt" && $0.parameters.count == 1 && !$0.isStatic
           }) {
            source += "override operator fun `get`(" + parameters(charAt) + "): "
                + kotlinType(charAt.result) + " = `charAt`(p0)\n"
        }
        if charSequenceBridged {
            let hasLengthProperty = own.contains {
                ($0.name == "getLength" || $0.name == "isLength")
                    && $0.parameters.isEmpty && !$0.isStatic
            }
            if !hasLengthProperty, own.contains(where: {
                $0.name == "length" && $0.parameters.isEmpty && !$0.isStatic && kotlinType($0.result) == "kotlin.Int"
            }) {
                source += "override val `length`: kotlin.Int get() = `length`()\n"
            }
        }
        if numberBridged {
            // kotlin.Number spells Java's *Value methods as to*(); each
            // Kotlin member delegates to its erased classfile counterpart.
            let bridges: [(String, String, String)] = [
                ("toByte", "byteValue", "kotlin.Byte"),
                ("toShort", "shortValue", "kotlin.Short"),
                ("toInt", "intValue", "kotlin.Int"),
                ("toLong", "longValue", "kotlin.Long"),
                ("toFloat", "floatValue", "kotlin.Float"),
                ("toDouble", "doubleValue", "kotlin.Double"),
            ]
            for (toName, javaName, returnType) in bridges {
                let hasJavaMethod = own.contains {
                    $0.name == javaName && $0.parameters.isEmpty && !$0.isStatic
                }
                source += "override fun `\(toName)`(): \(returnType) = "
                    + (hasJavaMethod ? "`\(javaName)`()" : "null!!") + "\n"
            }
        }
        if allowsCompanion, !statics.isEmpty {
            source += "companion object {\n"
            for method in statics {
                source += "external fun `\(method.name)`(" + parameters(method) + "): " + kotlinType(method.result) + "\n"
            }
            source += "}\n"
        }
        return source
    }

    // MARK: - Lazy classpath injection

    /// Packages Kotlin auto-imports on the JVM. Only `java.lang` can contain
    /// lazy classes in practice (the Android `android.jar` ships `java.*`
    /// stubs); `kotlin.*` entries are never injected anyway.
    private static let autoImportedPackages: Set<String> = [
        "java.lang", "kotlin.jvm",
    ]

    /// JDK binary names that Kotlin maps onto standard-library declarations,
    /// matching kotlinc's mapped types (java.util.List <-> kotlin.collections.List
    /// etc.). Generic targets use star projections because classfiles carry no
    /// type arguments. Only types whose Kotlin counterpart is provided by the
    /// frontend's stdlib catalog belong here.
    private static let jdkToKotlinTypeNames: [String: String] = [
        "java/lang/CharSequence": "kotlin.CharSequence",
        "java/lang/Comparable": "kotlin.Comparable<*>",
        "java/lang/Cloneable": "kotlin.Cloneable",
        "java/lang/Throwable": "kotlin.Throwable",
        "java/lang/Exception": "kotlin.Exception",
        "java/lang/RuntimeException": "kotlin.RuntimeException",
        "java/lang/Error": "kotlin.Error",
        "java/lang/Integer": "kotlin.Int",
        "java/lang/Long": "kotlin.Long",
        "java/lang/Double": "kotlin.Double",
        "java/lang/Float": "kotlin.Float",
        "java/lang/Boolean": "kotlin.Boolean",
        "java/lang/Byte": "kotlin.Byte",
        "java/lang/Short": "kotlin.Short",
        "java/lang/Character": "kotlin.Char",
        "java/lang/Void": "kotlin.Unit",
        "java/lang/Number": "kotlin.Number",
        "java/lang/StringBuilder": "kotlin.text.StringBuilder",
        "java/lang/Appendable": "kotlin.text.Appendable",
        "java/lang/Deprecated": "kotlin.Deprecated",
        "java/lang/Enum": "kotlin.Enum<*>",
        "java/lang/Iterable": "kotlin.collections.Iterable<*>",
        "java/util/Iterator": "kotlin.collections.Iterator<*>",
        "java/util/Collection": "kotlin.collections.Collection<*>",
        "java/util/List": "kotlin.collections.List<*>",
        "java/util/Set": "kotlin.collections.Set<*>",
        "java/util/Map": "kotlin.collections.Map<*, *>",
        "java/util/ListIterator": "kotlin.collections.ListIterator<*>",
        "java/util/Map$Entry": "kotlin.collections.Map.Entry<*, *>",
        // SequencedCollection.reversed() covariantly returns List while its
        // own signature erases to SequencedCollection; mapping the erased
        // name to Collection keeps the stub override return-compatible.
        "java/util/SequencedCollection": "kotlin.collections.Collection<*>",
        "java/util/SequencedSet": "kotlin.collections.Set<*>",
    ]

    /// java.* classpath entries that the frontend already provides through
    /// synthetic HeaderHelpers declarations rather than bundled sources, so
    /// `nominalNames` cannot see them. Injecting stubs for these would
    /// redeclare the same nominal and fail semantic analysis.
    private static let syntheticJavaNames: Set<String> = [
        // java.io stream/file surface synthesized for kotlin.io interop
        // (HeaderHelpers+SyntheticJavaIOStreamStubs).
        "java/io/Closeable", "java/io/File", "java/io/InputStream",
        "java/io/OutputStream", "java/io/ByteArrayInputStream",
        "java/io/ByteArrayOutputStream", "java/io/BufferedInputStream",
        "java/io/Reader", "java/io/SequenceInputStream", "java/io/Writer",
        // java.lang compatibility anchors.
        "java/lang/AutoCloseable", "java/lang/ClassLoader",
        // java.util.concurrent.atomic scalar/reference family
        // (HeaderHelpers+SyntheticAtomicResidualRegistry).
        "java/util/concurrent/atomic/AtomicInteger",
        "java/util/concurrent/atomic/AtomicLong",
        "java/util/concurrent/atomic/AtomicBoolean",
        "java/util/concurrent/atomic/AtomicReference",
        "java/util/concurrent/atomic/AtomicReferenceArray",
        // java.lang names that would shadow Kotlin declarations through the
        // java.lang auto-import or same-package resolution. Other java.lang
        // classes (CharSequence, Comparable, exceptions, ...) are still
        // injected: stubs need them as resolvable supertypes, and Kotlin's
        // own declarations win unqualified lookups.
        "java/lang/Boolean", "java/lang/Byte", "java/lang/Short",
        "java/lang/Integer", "java/lang/Long", "java/lang/Float",
        "java/lang/Double", "java/lang/Void", "java/lang/Number",
        "java/lang/StringBuilder", "java/lang/Appendable",
        "java/lang/Deprecated",
    ]

    private static let identifierPattern = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*"#)
    private static let dottedPattern = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+"#)
    private static let starImportPattern = try! NSRegularExpression(pattern: #"import\s+([A-Za-z_][A-Za-z0-9_.]*?)\.\*"#)
    private static let packagePattern = try! NSRegularExpression(pattern: #"^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)"#, options: [.anchorsMatchLines])

    /// Computes the set of lazy classpath classes that must be injected:
    /// classes named by user sources (imports, qualified references,
    /// star/auto/same-package lookups) plus the transitive closure over
    /// supertypes and emitted method signature types.
    private func referencedLazyClasses(into ctx: CompilationContext, covered: Set<String>) -> Set<String> {
        // normalized dotted name -> binary class names ("a.b.C.D" may come
        // from either a/b/C$D or a/b/C/D, so keep every candidate).
        var normalizedToBinary: [String: [String]] = [:]
        // "package|ShortName" -> binary names, for identifier-based lookups.
        var byPackageAndShortName: [String: [String]] = [:]
        var lazyTopLevelByPackage: [String: [(short: String, name: String)]] = [:]
        for name in lazyClassNames {
            let normalized = name.split(separator: "/")
                .map(String.init).joined(separator: ".")
                .replacingOccurrences(of: "$", with: ".")
            normalizedToBinary[normalized, default: []].append(name)
            let parts = name.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { continue }
            let package = parts.dropLast().joined(separator: ".")
            let short = parts.last!.split(separator: "$").last.map(String.init) ?? parts.last!
            byPackageAndShortName[package + "|" + short, default: []].append(name)
            if !name.contains("$") {
                lazyTopLevelByPackage[package, default: []].append((short, name))
            }
        }

        var matched = Set<String>()
        func matchTokenPrefixes(_ token: String) {
            let parts = token.split(separator: ".").map(String.init)
            for end in 1...parts.count {
                let prefix = parts.prefix(end).joined(separator: ".")
                if let binaries = normalizedToBinary[prefix] { matched.formUnion(binaries) }
            }
        }
        func identifierMatches(_ filePackage: String?, identifiers: Set<String>, packages: Set<String>) {
            for package in packages {
                for entry in lazyTopLevelByPackage[package] ?? [] where identifiers.contains(entry.short) {
                    matched.insert(entry.name)
                }
            }
            if let filePackage {
                for entry in lazyTopLevelByPackage[filePackage] ?? [] where identifiers.contains(entry.short) {
                    matched.insert(entry.name)
                }
            }
        }

        for file in ctx.sourceManager.fileIDs() where ctx.sourceManager.origin(of: file) == .user {
            let text = String(decoding: ctx.sourceManager.contents(of: file), as: UTF8.self)
            let range = NSRange(text.startIndex..., in: text)
            var identifiers = Set<String>()
            for match in Self.identifierPattern.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) { identifiers.insert(String(text[r])) }
            }
            var filePackage: String?
            if let match = Self.packagePattern.firstMatch(in: text, range: range),
               let r = Range(match.range(at: 1), in: text) {
                filePackage = String(text[r])
            }
            var starPackages = Self.autoImportedPackages
            for match in Self.starImportPattern.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) { starPackages.insert(String(text[r])) }
            }
            for match in Self.dottedPattern.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) { matchTokenPrefixes(String(text[r])) }
            }
            identifierMatches(filePackage, identifiers: identifiers, packages: starPackages)
        }

        // Map every matched name (inner classes included) to its top-level
        // owner; only top-level classes are emitted by inject(into:).
        var needed = Set<String>()
        var queue: [String] = []
        func isInjected(_ name: String) -> Bool {
            guard let info = classes[name] else { return false }
            return !isCovered(info.name, covered: covered)
        }
        func markNeeded(_ name: String) {
            var top = name
            while let outer = innerClassMetadata[top]?.outerName { top = outer }
            if lazyClassNames.contains(top), isInjected(top), needed.insert(top).inserted { queue.append(top) }
        }
        for name in matched { markNeeded(name) }
        func signatureNames(_ type: JVMValueType) -> [String] {
            guard let name = type.referenceName else { return [] }
            var n = name
            while n.hasPrefix("[") { n.removeFirst() }
            if n.hasPrefix("L"), n.hasSuffix(";") { n = String(n.dropFirst().dropLast()) }
            return n.contains("/") ? [n] : []
        }
        var edgeProcessed = Set<String>()
        func processEdges(_ name: String) {
            guard edgeProcessed.insert(name).inserted, let info = classes[name] else { return }
            for parent in [info.superclass].compactMap({ $0 }) + info.interfaces {
                // Covered supertypes render as Kotlin/platform names and need
                // no stub; every other lazy supertype joins the closure.
                if lazyClassNames.contains(parent), isInjected(parent) {
                    markNeeded(parent)
                }
            }
            for method in info.methods where method.parameters.allSatisfy(expose)
                && expose(method.result)
                && (method.isConstructor || JVMProgramBuilder.isIdentifier(method.name)) {
                for type in method.parameters + [method.result] {
                    for ref in signatureNames(type)
                    where lazyClassNames.contains(ref) && isInjected(ref) {
                        markNeeded(ref)
                    }
                }
            }
            // Nested classes are emitted inside their owner's stub but are
            // not worklist items themselves; their signature types still
            // need to join the closure.
            for entry in innerClassMetadata.values where entry.outerName == name {
                if classes[entry.name] != nil { processEdges(entry.name) }
            }
        }
        // Every eagerly injected class can reference lazy types in its own
        // emitted signatures, so their edges seed the closure as well.
        for name in classes.keys where !lazyClassNames.contains(name) && isInjected(name) {
            processEdges(name)
        }
        while let name = queue.popLast() { processEdges(name) }
        return needed
    }

    /// Whether a classpath parent renders as a Kotlin declaration rather
    /// than an injected stub, i.e. `kotlinSupertypeName` maps it onto a
    /// provided kotlin.* nominal. Such parents' members cannot be matched
    /// against erased classfile signatures for `override` purposes.
    private func resolvesToKotlinDecl(_ name: String) -> Bool {
        activeCoveredNames.contains(name) && Self.jdkToKotlinTypeNames[name] != nil
    }

    /// Whether `info` inherits the given Java class through its superclass
    /// or interface chain (erased classfile names).
    private func inheritsJavaType(_ info: JVMClassInfo, _ target: String) -> Bool {
        var visited = Set<String>()
        var queue = [info.superclass].compactMap { $0 } + info.interfaces
        while let name = queue.popLast() {
            if name == target { return true }
            guard visited.insert(name).inserted, let parent = hierarchyClasses[name] else { continue }
            queue.append(contentsOf: [parent.superclass].compactMap { $0 } + parent.interfaces)
        }
        return false
    }

    private func parameters(_ method: JVMForeignMethod) -> String {
        method.parameters.enumerated().map { "p\($0.offset): " + kotlinType($0.element) }.joined(separator: ", ")
    }
    private func overridesParent(_ method: JVMForeignMethod, in info: JVMClassInfo, visited: Set<String>) -> Bool {
        guard !visited.contains(info.name) else { return false }
        if ["toString()Ljava/lang/String;", "hashCode()I", "equals(Ljava/lang/Object;)Z"].contains(method.name + method.descriptor) { return true }
        let key = method.name + method.descriptor.prefix(through: method.descriptor.firstIndex(of: ")")!)
        for parentName in ([info.superclass].compactMap { $0 } + info.interfaces) {
            // java.lang.Object maps to kotlin.Any, which only provides
            // toString/hashCode/equals (already handled above). Its other
            // members (clone, finalize, wait, ...) have no Kotlin
            // counterpart, so treating them as overridden parents would
            // emit `override` for declarations that resolve to nothing.
            // The same applies to covered parents that render as Kotlin
            // mapped types (kotlin.Number, kotlin.CharSequence,
            // kotlin.text.Appendable): their Kotlin member sets differ
            // from the erased classfile signatures, so memberDeclarations
            // bridges the differences explicitly instead.
            if parentName == "java/lang/Object" || resolvesToKotlinDecl(parentName) { continue }
            guard let parent = classes[parentName] else { continue }
            if parent.methods.contains(where: { !$0.isStatic && !$0.isConstructor && $0.name + $0.descriptor.prefix(through: $0.descriptor.firstIndex(of: ")")!) == key }) { return true }
            if overridesParent(method, in: parent, visited: visited.union([info.name])) { return true }
        }
        return false
    }
    /// Converts foreign reference signatures to Kotlin platform types after
    /// header collection and before any user body is checked.
    func bind(in ctx: CompilationContext, sema: SemaModule) throws {
        func platform(_ type: TypeID) -> TypeID {
            switch sema.types.kind(of: type) {
            case .classType, .stringStruct, .any, .typeParam: return sema.types.withNullability(.platformType, for: type)
            default: return type
            }
        }
        for symbol in sema.symbols.allSymbols() {
            guard let site = symbol.declSite, let info = sourceClasses[site.start.file],
                  symbol.kind == .function || symbol.kind == .constructor,
                  let signature = sema.symbols.functionSignature(for: symbol.id) else { continue }
            let name = symbol.kind == .constructor ? "<init>" : ctx.interner.resolve(symbol.name)
            let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol)
            let isTopLevel = parent?.kind == .package
            let isExtension = hasExtensionReceiver(symbol, in: ctx)
            if isExtension { extensionSymbols.insert(symbol.id) }
            let receiverTypes = isExtension ? signature.receiverType.map { [$0] } ?? [] : []
            let descriptorTypes = receiverTypes + signature.parameterTypes
            let descriptor = "(" + (try descriptorTypes.map { try Self.type($0, sema: sema, ctx: ctx).descriptor }).joined() + ")"
            let staticMember = isTopLevel || isExtension || (parent.map { ctx.interner.resolve($0.name) == "Companion" } ?? false)
            guard let method = info.methods.first(where: { $0.name == name && $0.descriptor.hasPrefix(descriptor) && $0.isStatic == staticMember }) else { continue }
            methods[symbol.id] = method
            let returnType = method.isConstructor ? signature.returnType : platform(signature.returnType)
            sema.symbols.setFunctionSignature(FunctionSignature(
                receiverType: signature.receiverType.map(platform),
                contextReceiverTypes: signature.contextReceiverTypes, contextParameterSymbols: signature.contextParameterSymbols,
                contextParameterTypes: signature.contextParameterTypes, parameterTypes: signature.parameterTypes.map(platform),
                returnType: returnType, isSuspend: signature.isSuspend, canThrow: false,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterUnsafeVarianceTypeParameterSymbols: signature.valueParameterUnsafeVarianceTypeParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                hasStableParameterNames: signature.hasStableParameterNames,
                typeParameterSymbols: signature.typeParameterSymbols, reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList, classTypeParameterCount: signature.classTypeParameterCount
            ), for: symbol.id)
        }
        for symbol in sema.symbols.allSymbols() where symbol.kind == .function {
            guard let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol),
                  parent.fqName.map(ctx.interner.resolve) == ["kotlin", "Any"],
                  let signature = sema.symbols.functionSignature(for: symbol.id) else { continue }
            let name = ctx.interner.resolve(symbol.name)
            guard ["toString", "hashCode", "equals"].contains(name) else { continue }
            let parameters = try signature.parameterTypes.map { try Self.type($0, sema: sema, ctx: ctx) }
            let result = try Self.type(signature.returnType, sema: sema, ctx: ctx)
            let descriptor = "(" + parameters.map(\.descriptor).joined() + ")" + result.descriptor
            methods[symbol.id] = JVMForeignMethod(owner: "java/lang/Object", name: name, descriptor: descriptor, parameters: parameters, result: result, isStatic: false, isInterface: false, isAbstract: false)
        }
    }
    private func hasExtensionReceiver(_ symbol: SemanticSymbol, in ctx: CompilationContext) -> Bool {
        guard let site = symbol.declSite, let ast = ctx.ast,
              let file = ast.files.first(where: { $0.fileID == site.start.file }) else { return false }
        for declaration in file.topLevelDecls {
            guard case let .funDecl(function) = ast.arena.decl(declaration), function.range == site else { continue }
            return function.receiverType != nil
        }
        return false
    }
    static func type(_ id: TypeID, sema: SemaModule, ctx: CompilationContext) throws -> JVMValueType {
        switch sema.types.kind(of: id) {
        case let .intersection(parts):
            let concrete = parts.first { part in
                switch sema.types.kind(of: part) { case .primitive, .stringStruct: return true; case let .classType(t): return sema.symbols.symbol(t.classSymbol)?.kind != .interface; default: return false }
            } ?? parts.first { part in
                switch sema.types.kind(of: part) { case .typeParam, .any: return false; default: return true }
            } ?? parts.first
            guard let concrete else { throw JVMFrontendError(message: "Empty JVM intersection type.") }
            return try Self.type(concrete, sema: sema, ctx: ctx)
        case let .kClassType(t): return .reference("kotlin/reflect/KClass", nullable: t.nullability != .nonNull)
        case .unit: return .unit
        case .nothing(.nonNull): return .reference("java/lang/Void", nullable: false)
        case .nullableUnit: return .reference("kotlin/Unit", nullable: true)
        case .nothing(.nullable): return .reference("java/lang/Object", nullable: true)
        case let .any(nullability): return .reference("java/lang/Object", nullable: nullability != .nonNull, platform: nullability == .platformType)
        case let .stringStruct(nullability): return nullability == .nonNull ? .string : .reference("java/lang/String", nullable: true, platform: nullability == .platformType)
        case let .functionType(function):
            guard !function.params.contains(where: { if case .unit = sema.types.kind(of: $0) { return true }; return false }), function.contextReceivers.isEmpty, function.params.count + (function.receiver == nil ? 0 : 1) + (function.isSuspend ? 1 : 0) <= 22 else { throw JVMFrontendError(message: "JVM M7 supports Function0 through Function22, including a suspend continuation, without context receivers or Unit parameters.") }
            return .reference("kotlin/jvm/functions/Function" + String(function.params.count + (function.receiver == nil ? 0 : 1) + (function.isSuspend ? 1 : 0)), nullable: function.nullability != .nonNull)
        case let .typeParam(parameter):
            if let bound = sema.symbols.typeParameterUpperBound(for: parameter.symbol) {
                if case let .typeParam(other) = sema.types.kind(of: bound), other.symbol == parameter.symbol { return .reference("java/lang/Object", nullable: true) }
                let upper = try Self.type(bound, sema: sema, ctx: ctx)
                // Final primitive bounds use primitive JVM descriptors. A
                // nullable use or nullable bound still requires its wrapper.
                let erased = parameter.nullability == .nonNull && (upper.isNumeric || upper == .boolean)
                    ? upper : boxed(upper)
                if parameter.nullability == .nullable, let name = erased.referenceName { return .reference(name, nullable: true) }
                return erased
            }
            return .reference("java/lang/Object", nullable: true)
        case let .primitive(p, n) where n != .nonNull:
            if let name = JVMValueType.primitive(p).unsignedName { return .reference(name, nullable: true) }
            guard let wrapper = wrappers[p.kotlinName] else { throw JVMFrontendError(message: "Unsupported boxed JVM primitive.") }
            return .reference("java/lang/" + wrapper, nullable: true, platform: n == .platformType)
        case let .classType(type):
            guard let symbol = sema.symbols.symbol(type.classSymbol) else { throw JVMClassReader.Invalid() }
            let name = Self.binaryName(symbol.id, sema: sema, ctx: ctx)
            // Sema keeps `Any()` typed as the nominal kotlin.Any disguise
            // symbol rather than `.any`; it is still java.lang.Object here.
            if name == "kotlin/Any" { return .reference("java/lang/Object", nullable: type.nullability != .nonNull, platform: type.nullability == .platformType) }
            if symbol.kind == .object,
               let site = symbol.declSite, ctx.sourceManager.origin(of: site.start.file) == .residualStdlib,
               let parent = sema.symbols.parentSymbol(for: symbol.id).flatMap(sema.symbols.symbol), parent.kind == .class,
               name.hasSuffix("$Companion") {
                let outer = String(name.dropLast("$Companion".count))
                if ctx.jvmImports?.classes[outer] != nil {
                    let importedName = ctx.jvmImports?.hasClassFile(name) == true ? name : outer
                    return .reference(importedName, nullable: type.nullability != .nonNull)
                }
            }
            if name == "kotlin/Array" {
                guard let arg = type.args.first else { throw JVMFrontendError(message: "JVM Array needs an element type.") }
                let element = try argumentType(arg, sema: sema, ctx: ctx)
                let descriptor = "[" + element.descriptor
                guard descriptor.prefix(while: { $0 == "[" }).count <= 255 else { throw JVMFrontendError(message: "JVM arrays support at most 255 dimensions.") }
                return .reference(descriptor, nullable: type.nullability != .nonNull)
            }
            if ctx.jvmRuntimeClassAliases[symbol.fqName.map(ctx.interner.resolve).joined(separator: "/")] == nil, name.hasPrefix("kotlin/"), let p = [PrimitiveType.uint, .ulong, .ubyte, .ushort].first(where: { name == "kotlin/" + $0.kotlinName + "Array" }) { return .unsignedArray(p, nullable: type.nullability != .nonNull) }
            if let element = primitiveArrays[String(name.dropFirst(7))], name.hasPrefix("kotlin/") { return .reference("[" + element.descriptor, nullable: type.nullability != .nonNull) }
            // Result's non-null logical value may carry a successful null.
            if name == "kotlin/Result" { return ctx.options.stdlibOnly ? .reference(name, nullable: type.nullability != .nonNull) : .reference("java/lang/Object", nullable: true) }
            if let mapped = builtinName(name) { return .reference(mapped, nullable: type.nullability != .nonNull) }
            // `.user` and `.residualStdlib` files both carry real JVM class
            // contracts (declarations injected for consumer compiles describe
            // stdlib-jar ABI types), so either origin may produce a reference.
            guard ctx.jvmImports?.classes[name] != nil || symbol.declSite.map({ [.user, .residualStdlib].contains(ctx.sourceManager.origin(of: $0.start.file)) && (symbol.kind == .class || symbol.kind == .interface || symbol.kind == .object || symbol.kind == .enumClass || symbol.kind == .annotationClass) }) == true else {
                let owner = symbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
                throw JVMFrontendError(message: "Unsupported JVM reference type: \(name) used by \(owner)")
            }
            return .reference(name, nullable: type.nullability != .nonNull, platform: type.nullability == .platformType)
        case let .primitive(p, .nonNull):
            return .primitive(p)
        default: break
        }
        throw JVMFrontendError(message: "Unsupported JVM value type: \(sema.types.kind(of: id))")
    }
}
