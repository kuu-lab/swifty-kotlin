package java.lang

import java.io.File
import java.io.IOException
import java.util.Collections
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_process_start")
private external fun __startProcess(command: String): kotlin.Long

@KsSymbolName("__kk_process_start_ex")
private external fun __startProcessEx(command: String, envp: Array<String>?, dir: String?): kotlin.Long

@KsSymbolName("__kk_process_start_full")
private external fun __startProcessFull(
    command: String,
    envp: Array<String>?,
    dir: String?,
    redirects: Array<String>,
    errorStream: kotlin.Boolean
): kotlin.Long

/**
 * A process builder with the JDK `java.lang.ProcessBuilder` surface: command,
 * environment, working directory, and per-stream I/O redirection.
 *
 * Deviations from the JDK:
 * - `environment()` returns a [MutableMap] view initialized from the parent
 *   environment on first access; `put`/`putAll` validate names and values like
 *   `ProcessEnvironment` does (no '=' or NUL in names, no NUL in values).
 * - `Redirect.DISCARD.file()` reports `/dev/null`, matching the JDK null file.
 */
public class ProcessBuilder {
    private var commandArguments: MutableList<String>
    private var environmentMap: ProcessEnvironmentMap? = null
    private var directoryFile: File? = null
    private var redirectInputValue: Redirect = Redirect.PIPE
    private var redirectOutputValue: Redirect = Redirect.PIPE
    private var redirectErrorValue: Redirect = Redirect.PIPE
    private var mergeErrorStream = false

    public constructor(vararg command: String) {
        commandArguments = command.toMutableList()
    }

    public constructor(command: List<String>) {
        commandArguments = command.toMutableList()
    }

    public fun command(): MutableList<String> = Collections.unmodifiableList(commandArguments)

    public fun command(command: List<String>): ProcessBuilder {
        commandArguments = command.toMutableList()
        return this
    }

    public fun command(vararg command: String): ProcessBuilder {
        commandArguments = command.toMutableList()
        return this
    }

    public fun environment(): MutableMap<String, String> {
        val existing = environmentMap
        if (existing != null) return existing
        val backing = mutableMapOf<String, String>()
        backing.putAll(System.getenv())
        val created = ProcessEnvironmentMap(backing)
        environmentMap = created
        return created
    }

    public fun directory(): File? = directoryFile

    public fun directory(dir: File?): ProcessBuilder {
        directoryFile = dir
        return this
    }

    public fun redirectInput(source: Redirect): ProcessBuilder {
        if (source.type() == Redirect.Type.WRITE || source.type() == Redirect.Type.APPEND) {
            throw IllegalArgumentException("Redirect invalid for reading: ${source.type()}")
        }
        redirectInputValue = source
        return this
    }

    public fun redirectInput(file: File): ProcessBuilder = redirectInput(Redirect.from(file))

    public fun redirectOutput(destination: Redirect): ProcessBuilder {
        if (destination.type() == Redirect.Type.READ) {
            throw IllegalArgumentException("Redirect invalid for writing: ${destination.type()}")
        }
        redirectOutputValue = destination
        return this
    }

    public fun redirectOutput(file: File): ProcessBuilder = redirectOutput(Redirect.to(file))

    public fun redirectError(destination: Redirect): ProcessBuilder {
        if (destination.type() == Redirect.Type.READ) {
            throw IllegalArgumentException("Redirect invalid for writing: ${destination.type()}")
        }
        redirectErrorValue = destination
        return this
    }

    public fun redirectError(file: File): ProcessBuilder = redirectError(Redirect.to(file))

    public fun redirectInput(): Redirect = redirectInputValue

    public fun redirectOutput(): Redirect = redirectOutputValue

    public fun redirectError(): Redirect = redirectErrorValue

    public fun inheritIO(): ProcessBuilder {
        redirectInputValue = Redirect.INHERIT
        redirectOutputValue = Redirect.INHERIT
        redirectErrorValue = Redirect.INHERIT
        return this
    }

    public fun redirectErrorStream(): kotlin.Boolean = mergeErrorStream

    public fun redirectErrorStream(redirectErrorStream: kotlin.Boolean): ProcessBuilder {
        mergeErrorStream = redirectErrorStream
        return this
    }

    public fun start(): Process {
        if (commandArguments.isEmpty()) {
            throw ArrayIndexOutOfBoundsException("Index 0 out of bounds for length 0")
        }
        if (commandArguments.any { it.contains('\u0000') }) {
            throw IllegalArgumentException("command contains a null character")
        }
        val envMap = environmentMap
        val envp = envMap?.let { map ->
            map.entries.map { entry -> "${entry.key}=${entry.value}" }.toTypedArray()
        }
        val redirectSpecs = arrayOf(
            redirectInputValue.spec(),
            redirectOutputValue.spec(),
            redirectErrorValue.spec(),
        )
        val handle = __startProcessFull(
            commandArguments.joinToString(separator = "\u0000"),
            envp,
            directoryFile?.path,
            redirectSpecs,
            mergeErrorStream,
        )
        if (handle == 0L) throw IOException("Unable to start process")
        return Process(handle)
    }

    public abstract class Redirect internal constructor() {
        public enum class Type {
            PIPE,

            INHERIT,

            READ,

            WRITE,

            APPEND,
        }

        public abstract fun type(): Type

        public open fun file(): File? = null

        internal open fun append(): kotlin.Boolean = throw UnsupportedOperationException()

        internal open fun specKind(): Char = when (type()) {
            Type.PIPE -> 'P'
            Type.INHERIT -> 'I'
            Type.READ -> 'R'
            Type.WRITE -> 'W'
            Type.APPEND -> 'A'
        }

        internal open fun specPath(): String? = file()?.path

        internal fun spec(): String {
            val path = specPath()
            return if (path == null) specKind().toString() else specKind().toString() + path
        }

        override fun equals(other: Any?): kotlin.Boolean {
            if (this === other) return true
            if (other !is Redirect) return false
            if (other.type() != type()) return false
            val mine = file()
            val theirs = other.file()
            if (mine == null || theirs == null) return false
            return mine.path == theirs.path
        }

        override fun hashCode(): Int {
            val target = file()
            return if (target == null) type().hashCode() else target.path.hashCode()
        }

        public companion object {
            public val PIPE: Redirect = object : Redirect() {
                override fun type(): Type = Type.PIPE
                override fun toString(): String = "PIPE"
            }

            public val INHERIT: Redirect = object : Redirect() {
                override fun type(): Type = Type.INHERIT
                override fun toString(): String = "INHERIT"
            }

            public val DISCARD: Redirect = object : Redirect() {
                override fun type(): Type = Type.WRITE
                override fun file(): File = File("/dev/null")
                override fun append(): kotlin.Boolean = false
                override fun specKind(): Char = 'D'
                override fun specPath(): String? = null
                override fun toString(): String = type().toString()
            }

            public fun from(file: File): Redirect =
                FileRedirect(Type.READ, file, false, "redirect to read from file \"${file.path}\"")

            public fun to(file: File): Redirect =
                FileRedirect(Type.WRITE, file, false, "redirect to write to file \"${file.path}\"")

            public fun appendTo(file: File): Redirect =
                FileRedirect(Type.APPEND, file, true, "redirect to append to file \"${file.path}\"")

            private class FileRedirect(
                private val redirectType: Type,
                private val target: File,
                private val appendOutput: kotlin.Boolean,
                private val description: String,
            ) : Redirect() {
                override fun type(): Type = redirectType
                override fun file(): File = target
                override fun append(): kotlin.Boolean = appendOutput
                override fun toString(): String = description
            }
        }
    }
}

private class ProcessEnvironmentMap(
    private val backing: MutableMap<String, String>,
) : AbstractMutableMap<String, String>() {
    override fun put(key: String, value: String): String? {
        if (key.indexOf('=') >= 0 || key.indexOf('\u0000') >= 0) {
            throw IllegalArgumentException("Invalid environment variable name: \"$key\"")
        }
        if (value.indexOf('\u0000') >= 0) {
            throw IllegalArgumentException("Invalid environment variable value: \"$value\"")
        }
        return backing.put(key, value)
    }

    override val entries: MutableSet<MutableMap.MutableEntry<String, String>>
        get() = backing.entries
}
