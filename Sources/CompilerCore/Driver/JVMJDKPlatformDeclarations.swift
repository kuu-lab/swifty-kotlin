import Foundation

extension JVMClasspathIndex {
    /// A small source profile preserves Kotlin generics at JDK boundaries.
    /// Bodies remain in the JDK; no java.* classes are emitted into our stdlib.
    func injectJDKPlatformDeclarations(into ctx: CompilationContext) throws {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let comparator: JVMValueType = .reference("java/util/Comparator", nullable: false)
        let extractor: JVMValueType = .reference("java/util/function/ToIntFunction", nullable: false)
        func method(_ owner: String, _ name: String, _ parameters: [JVMValueType], _ result: JVMValueType, staticMember: Bool = false, interface: Bool = false) -> JVMForeignMethod {
            JVMForeignMethod(owner: owner, name: name, descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + (name == "<init>" ? "V" : result.descriptor), parameters: parameters, result: result, isStatic: staticMember, isInterface: interface, isAbstract: interface && !staticMember)
        }
        let declarations: [(String, String, UInt16, String?, [JVMForeignMethod])] = [
            ("java/util/Arrays", """
            package java.util
            class Arrays private constructor() {
                companion object { external fun sort(a: IntArray): Unit }
            }
            """, 0x0031, "java/lang/Object", [method("java/util/Arrays", "sort", [.reference("[I", nullable: false)], .unit, staticMember: true)]),
            ("java/util/function/ToIntFunction", """
            package java.util.function
            fun interface ToIntFunction<T> { fun applyAsInt(value: T): Int }
            """, 0x0601, "java/lang/Object", [method("java/util/function/ToIntFunction", "applyAsInt", [object], .int, interface: true)]),
            ("java/util/Comparator", """
            package java.util
            fun interface Comparator<T> {
                fun compare(first: T, second: T): Int
                companion object {
                    external fun <T> comparingInt(keyExtractor: java.util.function.ToIntFunction<in T>): java.util.Comparator<T>
                }
            }
            """, 0x0601, "java/lang/Object", [method("java/util/Comparator", "compare", [object, object], .int, interface: true), method("java/util/Comparator", "comparingInt", [extractor], comparator, staticMember: true, interface: true)]),
            ("java/util/Collections", """
            package java.util
            class Collections private constructor() {
                companion object { external fun <T> sort(list: List<T>, c: java.util.Comparator<in T>): Unit }
            }
            """, 0x0031, "java/lang/Object", [method("java/util/Collections", "sort", [.reference("java/util/List", nullable: false), comparator], .unit, staticMember: true)]),
            ("java/security/InvalidParameterException", """
            package java.security
            open class InvalidParameterException: kotlin.IllegalArgumentException {
                constructor(): super()
                constructor(msg: String?): super(msg)
            }
            """, 0x0001, "java/lang/IllegalArgumentException", [method("java/security/InvalidParameterException", "<init>", [], .reference("java/security/InvalidParameterException", nullable: false)), method("java/security/InvalidParameterException", "<init>", [.reference("java/lang/String", nullable: true)], .reference("java/security/InvalidParameterException", nullable: false))]),
        ]
        for (name, source, flags, superclass, methods) in declarations {
            let info = JVMClassInfo(name: name, flags: flags, superclass: superclass, interfaces: [], methods: methods)
            let path = "<kswiftk-jvm>/platform/" + name + ".kt"
            let file = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8), origin: .residualStdlib)
            sourceClasses[file] = info
            classes[name] = info
        }
    }
}
