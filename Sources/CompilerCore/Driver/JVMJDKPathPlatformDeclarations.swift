import Foundation

extension JVMClasspathIndex {
    /// Supplies the java.nio.file contracts used by the JVM stdlib path helpers.
    func injectJDKPathPlatformDeclarations(into context: CompilationContext) throws {
        let path = "java/nio/file/Path"
        let paths = "java/nio/file/Paths"
        let files = "java/nio/file/Files"
        let linkOption = "java/nio/file/LinkOption"

        func method(
            _ owner: String, _ name: String, _ descriptor: String,
            isStatic: Bool, isVarargs: Bool = false
        ) throws -> JVMForeignMethod {
            let (parameters, result) = try JVMDescriptor.parse(descriptor)
            var method = JVMForeignMethod(
                owner: owner, name: name, descriptor: descriptor, parameters: parameters, result: result,
                isStatic: isStatic, isInterface: !isStatic, isAbstract: !isStatic
            )
            method.isVarargs = isVarargs
            return method
        }

        func inject(_ name: String, source: String, flags: UInt16, methods: [JVMForeignMethod]) {
            guard classes[name] == nil else { return }
            let info = JVMClassInfo(name: name, flags: flags, superclass: "java/lang/Object", interfaces: [], methods: methods)
            let file = context.sourceManager.addFile(
                path: "<kswiftk-jvm>/platform/" + name + ".kt",
                contents: Data(source.utf8), origin: .residualStdlib
            )
            classes[name] = info
            sourceClasses[file] = info
        }

        inject(path, source: """
        package java.nio.file
        interface Path {
            fun toAbsolutePath(): Path
        }
        """, flags: 0x0601, methods: [
            try method(path, "toAbsolutePath", "()Ljava/nio/file/Path;", isStatic: false),
        ])
        inject(paths, source: """
        package java.nio.file
        class Paths private constructor() {
            companion object {
                external fun get(first: String, vararg more: String): Path
            }
        }
        """, flags: 0x0011, methods: [
            try method(paths, "get", "(Ljava/lang/String;[Ljava/lang/String;)Ljava/nio/file/Path;",
                       isStatic: true, isVarargs: true),
        ])
        inject(linkOption, source: """
        package java.nio.file
        enum class LinkOption { NOFOLLOW_LINKS }
        """, flags: 0x4011, methods: [])
        let filePredicate = "(Ljava/nio/file/Path;[Ljava/nio/file/LinkOption;)Z"
        inject(files, source: """
        package java.nio.file
        class Files private constructor() {
            companion object {
                external fun isRegularFile(path: Path, vararg options: LinkOption): Boolean
                external fun notExists(path: Path, vararg options: LinkOption): Boolean
            }
        }
        """, flags: 0x0011, methods: [
            try method(files, "isRegularFile", filePredicate, isStatic: true, isVarargs: true),
            try method(files, "notExists", filePredicate, isStatic: true, isVarargs: true),
        ])
    }
}
