import Foundation

extension JVMProgramBuilder {
    func repeatableContainerName(_ symbol: SymbolID) throws -> String? {
        let records = sema.symbols.annotations(for: symbol)
        let automatic = records.contains { $0.annotationFQName == "kotlin.annotation.Repeatable" }
        let explicit = records.first { $0.annotationFQName == "kotlin.jvm.JvmRepeatable" }
        guard automatic || explicit != nil else { return nil }
        guard let plan = classes[symbol], plan.isAnnotation else { throw JVMFrontendError(message: "JVM repeatable requires an annotation class.") }
        if let explicit {
            var containerSymbol: SymbolID?
            if let expression = annotationConstruction(explicit) {
                let args: [CallArgument]
                switch ast.arena.expr(expression) { case let .call(_, _, a, _), let .memberCall(_, _, _, a, _): args = a; default: args = [] }
                if let arg = args.first, let type = sema.bindings.classRefTargetType(for: arg.expr), case let .classType(t) = sema.types.kind(of: type) { containerSymbol = t.classSymbol }
            }
            guard let containerSymbol, containerSymbol != symbol, let container = classes[containerSymbol], container.isAnnotation,
                  let parameter = container.declaration!.primaryConstructorParams.first(where: { context.interner.resolve($0.name) == "value" }),
                  let propertyID = container.declaration!.memberProperties.first(where: { id in if case let .propertyDecl(p) = ast.arena.decl(id) { return p.name == parameter.name }; return false }),
                  let propertySymbol = sema.bindings.declSymbol(for: propertyID), let semantic = sema.symbols.propertyType(for: propertySymbol),
                  try type(semantic).descriptor == "[L" + plan.name + ";",
                  container.declaration!.primaryConstructorParams.allSatisfy({ $0.name == parameter.name || $0.hasDefaultValue }) else {
                throw JVMFrontendError(message: "JVM @JvmRepeatable needs a source annotation container with value: Array<RepeatedAnnotation> and defaults for other elements.")
            }
            let ranks = ["SOURCE": 0, "BINARY": 1, "RUNTIME": 2]
            guard ranks[annotationRetention(containerSymbol)]! >= ranks[annotationRetention(symbol)]! else { throw JVMFrontendError(message: "JVM repeatable container retention is shorter than the annotation retention.") }
            guard repeatableTargets(containerSymbol).isSubset(of: repeatableTargets(symbol)) else {
                throw JVMFrontendError(message: "JVM repeatable container targets must be a subset of the annotation targets.")
            }
            return container.name
        }
        let name = plan.name + "$Container"
        guard !classes.values.contains(where: { $0.name == name }) else { throw JVMFrontendError(message: "JVM repeatable container name clashes with a source declaration: " + name) }
        return name
    }
    private func repeatableTargets(_ symbol: SymbolID) -> Set<String> {
        let names: Set<String> = ["CLASS", "ANNOTATION_CLASS", "TYPE_PARAMETER", "PROPERTY", "FIELD", "LOCAL_VARIABLE", "VALUE_PARAMETER", "CONSTRUCTOR", "FUNCTION", "PROPERTY_GETTER", "PROPERTY_SETTER", "TYPE", "EXPRESSION", "FILE", "TYPEALIAS"]
        guard let record = sema.symbols.annotations(for: symbol).first(where: { $0.annotationFQName == "kotlin.annotation.Target" }) else {
            return names.subtracting(["TYPE_PARAMETER", "TYPE", "EXPRESSION", "FILE", "TYPEALIAS"])
        }
        let words = record.arguments.flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted) }
        var targets = Set(words).intersection(names)
        if targets.contains("CLASS") { targets.insert("ANNOTATION_CLASS") }
        return targets
    }
    func groupedRepeatableAnnotations(_ annotations: [JVMAnnotation]) throws -> [JVMAnnotation] {
        var output: [JVMAnnotation] = [], seen: Set<String> = []
        for annotation in annotations where seen.insert(annotation.descriptor).inserted {
            let instances = annotations.filter { $0.descriptor == annotation.descriptor }
            if instances.count == 1 { output.append(annotation); continue }
            guard let plan = classes.values.first(where: { "L" + $0.name + ";" == annotation.descriptor }), let name = try repeatableContainerName(plan.symbol) else { throw JVMFrontendError(message: "Repeated JVM annotation is missing @Repeatable or @JvmRepeatable.") }
            guard !annotations.contains(where: { $0.descriptor == "L" + name + ";" }) else { throw JVMFrontendError(message: "A repeated annotation and its explicit container cannot be used together.") }
            output.append(JVMAnnotation(descriptor: "L" + name + ";", values: [("value", .array(instances.map { .annotation($0) }))], visible: annotation.visible))
        }
        return output
    }
    func repeatableContainers() throws -> [JVMClass] {
        var output: [JVMClass] = []
        for plan in classes.values.filter({ $0.isAnnotation && recordsContain($0.symbol, "kotlin.annotation.Repeatable") && !recordsContain($0.symbol, "kotlin.jvm.JvmRepeatable") }).sorted(by: { $0.name < $1.name }) {
            let name = try repeatableContainerName(plan.symbol)!
            let element = JVMValueType.reference("[L" + plan.name + ";", nullable: false)
            var method = rawFunction(name, name: "value", parameters: [], result: element, access: 0x0401, locals: [], instructions: [])
            method.isAbstract = true
            var container = rawClass(name, interfaces: ["java/lang/annotation/Annotation"], access: 0x2601, functions: [method])
            var policy = rawClass(plan.name)
            try decorateAnnotation(plan, result: &policy)
            let copied: Set<String> = ["Lkotlin/annotation/Retention;", "Lkotlin/annotation/Target;", "Lkotlin/annotation/MustBeDocumented;", "Ljava/lang/annotation/Retention;", "Ljava/lang/annotation/Target;", "Ljava/lang/annotation/Documented;"]
            container.annotations = policy.annotations.filter { copied.contains($0.descriptor) }
            container.annotations.append(JVMAnnotation(descriptor: "Lkotlin/jvm/internal/RepeatableContainer;"))
            container.annotations.append(JVMAnnotation(descriptor: "Lkotlin/Metadata;", values: [("k", .constant(.int(3))), ("mv", .array([2, 0, 0].map { .constant(.int($0)) })), ("xi", .constant(.int(816)))]))
            container.outerName = plan.name; container.innerName = "Container"
            output.append(container)
        }
        return output
    }
}
