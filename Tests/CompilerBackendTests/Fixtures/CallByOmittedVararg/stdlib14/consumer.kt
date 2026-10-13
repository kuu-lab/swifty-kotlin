import java.util.Locale
import kotlin.reflect.KFunction

fun main() {
    val reference = ::sourceWords
    val parameter = reference.parameters[0]
    val emptyListArray = emptyList<String>().toTypedArray()
    val listArray = listOf("list").toTypedArray()
    val emptyCollection: Collection<String> = emptyList<String>()
    val collection: Collection<String> = listOf("collection")
    val emptyCollectionArray = emptyCollection.toTypedArray()
    val collectionArray = collection.toTypedArray()
    println("list-empty:" + reference.callBy(mapOf(parameter to emptyListArray)).size)
    println("list-nonempty:" + reference.callBy(mapOf(parameter to listArray)).joinToString())
    println("collection-empty:" + reference.callBy(mapOf(parameter to emptyCollectionArray)).size)
    println("collection-nonempty:" + reference.callBy(mapOf(parameter to collectionArray)).joinToString())
    println("collection-identity:" + (reference.callBy(mapOf(parameter to collectionArray)) === collectionArray))
    println("inline-forward:" + forwardedWords("forward").joinToString())
    println("inline-empty:" + forwardedWords().size)
    val inlineReference = ::forwardedWords
    println("inline-reflection-identity:" + (inlineReference.callBy(mapOf(inlineReference.parameters[0] to collectionArray)) === collectionArray))
    val sliced = arrayOf("skip", "slice").sliceArray(listOf(1))
    println("slice-component:" + reference.callBy(mapOf(parameter to sliced)).joinToString())
    val reversed = arrayOf("a", "b").reversedArray()
    println("reverse-component:" + reference.callBy(mapOf(parameter to reversed)).joinToString())
    val locale = Locale("en", "US")
    println("format-extension:" + "%s".format("receiver"))
    println("format-extension-locale:" + "%s".format(locale, "receiver-locale"))
    println("format-companion:" + String.format("%s", "companion"))
    println("format-companion-locale:" + String.format(locale, "%s", "companion-locale"))
}
