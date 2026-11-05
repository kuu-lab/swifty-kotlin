package java.lang

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
        val tokens = mutableListOf<String>()
        var index = 0
        while (index < command.length) {
            while (index < command.length && isExecTokenDelimiter(command[index])) index += 1
            val start = index
            while (index < command.length && !isExecTokenDelimiter(command[index])) index += 1
            if (index > start) tokens.add(command.substring(start, index))
        }
        return exec(tokens.toTypedArray())
    }

    /** Executes the specified command array in a separate process. */
    public fun exec(command: Array<String>): Process =
        ProcessBuilder(*command).start()

    private fun isExecTokenDelimiter(c: kotlin.Char): kotlin.Boolean =
        c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u000C'
}
