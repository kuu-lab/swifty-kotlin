package java.lang

import java.io.File
import java.io.IOException
import kotlin.internal.KsSymbolName

public object Runtime {
    @KsSymbolName("__kk_runtime_getRuntime")
    private external fun __getRuntime(): Runtime

    @KsSymbolName("__kk_runtime_totalMemory")
    private external fun __totalMemory(): kotlin.Long

    @KsSymbolName("__kk_runtime_freeMemory")
    private external fun __freeMemory(): kotlin.Long

    @KsSymbolName("__kk_runtime_maxMemory")
    private external fun __maxMemory(): kotlin.Long

    @KsSymbolName("__kk_runtime_availableProcessors")
    private external fun __availableProcessors(): Int

    public fun getRuntime(): Runtime = __getRuntime()

    public fun totalMemory(): kotlin.Long = __totalMemory()

    public fun freeMemory(): kotlin.Long = __freeMemory()

    public fun maxMemory(): kotlin.Long = __maxMemory()

    public fun availableProcessors(): Int = __availableProcessors()

    /**
     * Executes the specified string command in a separate process.
     * The command string is tokenized like `java.lang.StringTokenizer` with
     * the default delimiters (space, tab, newline, carriage return, and form
     * feed): runs of delimiters count as one separator and leading or
     * trailing delimiters are ignored. Like the JDK, an empty command string
     * is rejected before any tokenization happens.
     */
    public fun exec(command: String): Process {
        if (command.isEmpty()) throw IllegalArgumentException("Empty command")
        return exec(tokenizeExecCommand(command), null, null)
    }

    /**
     * Executes the specified string command in a separate process with the
     * given environment. A `null` [envp] inherits the parent environment;
     * a non-null array fully replaces it (entries are `KEY=VALUE` strings),
     * matching the JDK.
     */
    public fun exec(command: String, envp: Array<String>?): Process =
        exec(command, envp, null)

    /**
     * Executes the specified string command in a separate process with the
     * given environment and working directory. `null` [envp]/[dir] inherit the
     * parent's environment and current directory, matching the JDK.
     */
    public fun exec(command: String, envp: Array<String>?, dir: File?): Process {
        if (command.isEmpty()) throw IllegalArgumentException("Empty command")
        return exec(tokenizeExecCommand(command), envp, dir)
    }

    /** Executes the specified command array in a separate process. */
    public fun exec(command: Array<String>): Process = exec(command, null, null)

    /**
     * Executes the specified command array in a separate process with the
     * given environment. A `null` [envp] inherits the parent environment;
     * a non-null array fully replaces it, matching the JDK.
     */
    public fun exec(command: Array<String>, envp: Array<String>?): Process =
        exec(command, envp, null)

    /**
     * Executes the specified command array in a separate process with the
     * given environment and working directory. `null` [envp]/[dir] inherit the
     * parent's environment and current directory, matching the JDK.
     */
    public fun exec(command: Array<String>, envp: Array<String>?, dir: File?): Process {
        // The JDK reaches this state through ProcessBuilder.start() and the
        // native launcher indexing argv[0]; surface the same exception.
        if (command.isEmpty()) {
            throw ArrayIndexOutOfBoundsException("Index 0 out of bounds for length 0")
        }
        if (command.any { it.contains('\u0000') }) {
            throw IllegalArgumentException("command contains a null character")
        }
        val handle = __startProcessEx(command.joinToString(separator = "\u0000"), envp, dir?.path)
        if (handle == 0L) throw IOException("Unable to start process")
        return Process(handle)
    }

    private fun tokenizeExecCommand(command: String): Array<String> {
        val tokens = mutableListOf<String>()
        var index = 0
        while (index < command.length) {
            while (index < command.length && isExecTokenDelimiter(command[index])) index += 1
            val start = index
            while (index < command.length && !isExecTokenDelimiter(command[index])) index += 1
            if (index > start) tokens.add(command.substring(start, index))
        }
        return tokens.toTypedArray()
    }

    private fun isExecTokenDelimiter(c: kotlin.Char): kotlin.Boolean =
        c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u000C'
}

@KsSymbolName("__kk_process_start_ex")
private external fun __startProcessEx(command: String, envp: Array<String>?, dir: String?): kotlin.Long
