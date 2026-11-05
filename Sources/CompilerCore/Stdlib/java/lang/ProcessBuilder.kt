package java.lang

import java.io.IOException
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_process_start")
private external fun __startProcess(command: String): kotlin.Long

public class ProcessBuilder(vararg command: String) {
    private var commandArguments: MutableList<String> = command.toMutableList()

    public fun command(): MutableList<String> = commandArguments

    public fun command(command: List<String>): ProcessBuilder {
        commandArguments = command.toMutableList()
        return this
    }

    public fun command(vararg command: String): ProcessBuilder {
        commandArguments = command.toMutableList()
        return this
    }

    public fun start(): Process {
        // The JDK reaches this state through the native launcher indexing
        // argv[0] of an empty command; surface the same exception.
        if (commandArguments.isEmpty()) {
            throw ArrayIndexOutOfBoundsException("Index 0 out of bounds for length 0")
        }
        if (commandArguments.any { it.contains('\u0000') }) {
            throw IllegalArgumentException("command contains a null character")
        }
        val handle = __startProcess(commandArguments.joinToString(separator = "\u0000"))
        if (handle == 0L) throw IOException("Unable to start process")
        return Process(handle)
    }
}
