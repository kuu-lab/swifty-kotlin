import com.intellij.openapi.util.Disposer
import com.intellij.psi.PsiErrorElement
import com.intellij.psi.util.PsiTreeUtil
import org.jetbrains.kotlin.cli.jvm.compiler.EnvironmentConfigFiles
import org.jetbrains.kotlin.cli.jvm.compiler.KotlinCoreEnvironment
import org.jetbrains.kotlin.config.CompilerConfiguration
import org.jetbrains.kotlin.lexer.KtTokens
import org.jetbrains.kotlin.psi.*
import java.io.File
import java.security.MessageDigest

internal fun json(value: Any?): String = when (value) {
    null -> "null"
    is String -> buildString {
        append('"')
        for (character in value) when (character) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> if (character.code < 32) append("\\u%04x".format(character.code)) else append(character)
        }
        append('"')
    }
    is Boolean, is Number -> value.toString()
    is Map<*, *> -> value.entries.joinToString(",", "{", "}") { json(it.key.toString()) + ":" + json(it.value) }
    is Iterable<*> -> value.joinToString(",", "[", "]") { json(it) }
    else -> error("Unsupported JSON value ${value.javaClass}")
}

private fun visibility(declaration: KtModifierListOwner): String = when {
    declaration.hasModifier(KtTokens.PRIVATE_KEYWORD) -> "private"
    declaration.hasModifier(KtTokens.INTERNAL_KEYWORD) -> "internal"
    declaration.hasModifier(KtTokens.PROTECTED_KEYWORD) -> "protected"
    else -> "public"
}

private fun annotations(declaration: KtModifierListOwner) = declaration.annotationEntries.map { entry ->
    linkedMapOf(
        "name" to entry.typeReference?.text,
        "target" to entry.useSiteTarget?.text,
        "arguments" to entry.valueArguments.map { argument ->
            linkedMapOf("name" to argument.getArgumentName()?.asName?.asString(), "expression" to argument.getArgumentExpression()?.text)
        },
        "source" to entry.text
    )
}

private fun typeShape(reference: KtTypeReference?): Map<String, Any?>? {
    fun elementShape(element: KtTypeElement?): Map<String, Any?>? = when (element) {
        null -> null
        is KtNullableType -> linkedMapOf("kind" to "nullable", "inner" to elementShape(element.innerType))
        is KtUserType -> {
            fun qualifiedName(type: KtUserType): String = type.qualifier?.let { qualifiedName(it) + "." }.orEmpty() + type.referencedName
            linkedMapOf("kind" to "user", "name" to qualifiedName(element), "arguments" to element.typeArguments.map { projection ->
                linkedMapOf("variance" to projection.projectionKind.toString(), "type" to typeShape(projection.typeReference))
            })
        }
        is KtFunctionType -> linkedMapOf(
            "kind" to "function", "receiver" to typeShape(element.receiverTypeReference),
            "parameters" to element.parameters.map { typeShape(it.typeReference) },
            "result" to typeShape(element.returnTypeReference)
        )
        else -> linkedMapOf("kind" to "unsupported", "source" to element.text)
    }
    return elementShape(reference?.typeElement)
}

private fun parameters(declaration: KtCallableDeclaration) = declaration.valueParameters.map { parameter ->
    linkedMapOf(
        "name" to parameter.name,
        "type" to parameter.typeReference?.text,
        "typeShape" to typeShape(parameter.typeReference),
        "vararg" to parameter.isVarArg,
        "default" to parameter.defaultValue?.text,
        "annotations" to annotations(parameter)
    )
}

private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
    .joinToString("") { "%02x".format(it.toInt() and 255) }

fun main(arguments: Array<String>) {
    require(arguments.size == 1) { "Usage: ExtractSourceDeclarationsKt <repository-root>" }
    val repository = File(arguments[0]).canonicalFile
    val upstream = File(repository, "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1")
    val local = File(repository, "Sources/CompilerCore/Stdlib/kotlinx/io")
    val disposable = Disposer.newDisposable()
    try {
        val environment = KotlinCoreEnvironment.createForProduction(
            disposable, CompilerConfiguration(), EnvironmentConfigFiles.JVM_CONFIG_FILES
        )
        val factory = KtPsiFactory(environment.project, false)
        val records = mutableListOf<Map<String, Any?>>()
        val files = mutableListOf<Map<String, Any?>>()
        for ((origin, root) in listOf("upstream" to upstream, "local" to local)) {
            for (source in root.walkTopDown().filter { it.isFile && it.extension == "kt" }.sortedBy { it.relativeTo(root).invariantSeparatorsPath }) {
                val bytes = source.readBytes()
                val text = bytes.toString(Charsets.UTF_8)
                val path = if (origin == "upstream") source.relativeTo(upstream).invariantSeparatorsPath
                    else source.relativeTo(repository).invariantSeparatorsPath
                val file = factory.createFile(source.name, text)
                val errors = PsiTreeUtil.findChildrenOfType(file, PsiErrorElement::class.java)
                check(errors.isEmpty()) { "$path: ${errors.joinToString { it.errorDescription }}" }
                val packageName = file.packageFqName.asString()
                files.add(linkedMapOf(
                    "origin" to origin, "path" to path, "sha256" to sha256(bytes),
                    "package" to packageName, "imports" to file.importDirectives.map {
                        linkedMapOf("name" to it.importedFqName?.asString(), "alias" to it.aliasName, "wildcard" to it.isAllUnder)
                    },
                    "fileAnnotations" to file.annotationEntries.map { it.text }
                ))

                fun add(declaration: KtDeclaration, kind: String, name: String,
                        owners: List<String>, enclosingVisibility: String,
                        callable: KtCallableDeclaration? = null, implicit: Boolean = false) {
                    val ownVisibility = visibility(declaration)
                    val effectiveVisibility = if (enclosingVisibility != "public") enclosingVisibility else ownVisibility
                    val fqName = (listOf(packageName) + owners + name).filter { it.isNotEmpty() }.joinToString(".")
                    val header = when (kind) {
                        "function", "constructor" -> "$kind ${callable?.receiverTypeReference?.text?.let { "$it." } ?: ""}$name${callable?.valueParameterList?.text ?: "()"}${callable?.typeReference?.text?.let { ": $it" } ?: ""}"
                        "property" -> "${if ((declaration as? KtProperty)?.isVar == true || (declaration as? KtParameter)?.isMutable == true) "var" else "val"} $name${callable?.typeReference?.text?.let { ": $it" } ?: ""}"
                        else -> "$kind $name"
                    }
                    records.add(linkedMapOf(
                        "origin" to origin, "path" to path,
                        "line" to (text.take(declaration.textOffset).count { it == '\n' } + 1),
                        "kind" to kind, "name" to name, "owner" to (listOf(packageName) + owners).filter { it.isNotEmpty() }.joinToString("."),
                        "fqName" to fqName, "declaredVisibility" to ownVisibility, "visibility" to effectiveVisibility,
                        "actual" to declaration.hasModifier(KtTokens.ACTUAL_KEYWORD),
                        "expect" to declaration.hasModifier(KtTokens.EXPECT_KEYWORD),
                        "external" to declaration.hasModifier(KtTokens.EXTERNAL_KEYWORD),
                        "hasBody" to when (declaration) {
                            is KtNamedFunction -> declaration.bodyExpression != null
                            is KtProperty -> declaration.initializer != null || declaration.getter?.bodyExpression != null || declaration.setter?.bodyExpression != null
                            // Constructors also execute delegation and class/property
                            // initializers when there is no explicit body expression.
                            is KtConstructor<*> -> !declaration.getContainingClassOrObject().hasModifier(KtTokens.EXPECT_KEYWORD)
                                && !declaration.getContainingClassOrObject().hasModifier(KtTokens.EXTERNAL_KEYWORD)
                            is KtClassOrObject -> if (kind == "constructor")
                                !declaration.hasModifier(KtTokens.EXPECT_KEYWORD)
                                    && !declaration.hasModifier(KtTokens.EXTERNAL_KEYWORD)
                                else declaration.body != null
                            else -> false
                        },
                        "receiver" to callable?.receiverTypeReference?.text,
                        "receiverShape" to typeShape(callable?.receiverTypeReference),
                        "parameters" to (callable?.let { parameters(it) } ?: emptyList<Map<String, Any?>>()),
                        "returnType" to callable?.typeReference?.text,
                        "returnShape" to typeShape(callable?.typeReference),
                        "aliasTarget" to (declaration as? KtTypeAlias)?.getTypeReference()?.text,
                        "aliasTargetShape" to typeShape((declaration as? KtTypeAlias)?.getTypeReference()),
                        "typeParameters" to (declaration as? KtTypeParameterListOwner)?.typeParameters?.map {
                            linkedMapOf("name" to it.name, "bound" to typeShape(it.extendsBound), "source" to it.text)
                        },
                        "annotations" to annotations(declaration), "doc" to declaration.docComment?.text,
                        "signature" to header, "implicit" to implicit
                    ))
                }

                fun visit(declarations: List<KtDeclaration>, owners: List<String>, enclosingVisibility: String) {
                    for (declaration in declarations) when (declaration) {
                        is KtClassOrObject -> {
                            val name = declaration.name ?: if (declaration is KtObjectDeclaration && declaration.isCompanion()) "Companion" else continue
                            val kind = when {
                                declaration.isAnnotation() -> "annotation class"
                                declaration is KtClass && declaration.isInterface() -> "interface"
                                declaration is KtObjectDeclaration -> "object"
                                else -> "class"
                            }
                            add(declaration, kind, name, owners, enclosingVisibility)
                            val nestedVisibility = if (enclosingVisibility != "public") enclosingVisibility else visibility(declaration)
                            val nestedOwners = owners + name
                            if (declaration is KtClass && !declaration.isInterface() && declaration.hasPrimaryConstructor()) {
                                val constructor = declaration.primaryConstructor
                                add(constructor ?: declaration, "constructor", "<init>", nestedOwners, nestedVisibility, constructor, constructor == null)
                            }
                            for (parameter in declaration.primaryConstructorParameters.filter { it.hasValOrVar() }) {
                                add(parameter, "property", parameter.name ?: error("Unnamed constructor property"), nestedOwners, nestedVisibility, parameter)
                            }
                            visit(declaration.declarations, nestedOwners, nestedVisibility)
                        }
                        is KtNamedFunction -> add(declaration, "function", declaration.name ?: continue, owners, enclosingVisibility, declaration)
                        is KtProperty -> add(declaration, "property", declaration.name ?: continue, owners, enclosingVisibility, declaration)
                        is KtSecondaryConstructor -> add(declaration, "constructor", "<init>", owners, enclosingVisibility, declaration)
                        is KtTypeAlias -> add(declaration, "typealias", declaration.name ?: continue, owners, enclosingVisibility)
                    }
                }
                visit(file.declarations, emptyList(), "public")
            }
        }
        println(json(linkedMapOf("schemaVersion" to 1, "parser" to "Kotlin 2.3.10 PSI", "files" to files, "declarations" to records)))
    } finally {
        Disposer.dispose(disposable)
    }
}
