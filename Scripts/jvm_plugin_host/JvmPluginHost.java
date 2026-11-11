import java.io.BufferedReader;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.*;
import java.util.jar.JarFile;
import java.util.zip.ZipEntry;

/**
 * Lightweight JVM host for loading, inspecting, and executing kotlinc compiler plugin JARs
 * from KSwiftK without external Java build dependencies.
 */
public class JvmPluginHost {

    public static void main(String[] args) {
        if (args.length < 2) {
            System.err.println("Usage: java JvmPluginHost <command> <plugin.jar> [compiler.jar] [payloadJson]");
            System.exit(1);
        }

        String command = args[0];
        File pluginJar = new File(args[1]);
        File compilerJar = (args.length > 2 && !args[2].isEmpty() && !args[2].equals("-"))
                ? new File(args[2])
                : null;
        String payloadJson = args.length > 3 ? args[3] : null;

        if (!pluginJar.exists()) {
            System.err.println("Plugin JAR not found: " + pluginJar.getAbsolutePath());
            System.exit(2);
        }

        try {
            List<URL> urls = new ArrayList<>();
            urls.add(pluginJar.toURI().toURL());
            if (compilerJar != null && compilerJar.exists()) {
                urls.add(compilerJar.toURI().toURL());
                // Look for kotlin-stdlib.jar in the same directory as kotlin-compiler.jar if available
                File stdlibJar = new File(compilerJar.getParentFile(), "kotlin-stdlib.jar");
                if (stdlibJar.exists()) {
                    urls.add(stdlibJar.toURI().toURL());
                }
            }

            try (URLClassLoader loader = new URLClassLoader(urls.toArray(new URL[0]), JvmPluginHost.class.getClassLoader());
                 JarFile jar = new JarFile(pluginJar)) {

                if ("inspect".equals(command)) {
                    inspectPlugin(jar, loader);
                } else if ("transformSema".equals(command)) {
                    if (payloadJson == null) {
                        // Read from stdin if payload not passed in args
                        payloadJson = readStdin();
                    }
                    transformSema(jar, loader, payloadJson);
                } else {
                    System.err.println("Unknown command: " + command);
                    System.exit(3);
                }
            }
        } catch (Throwable t) {
            t.printStackTrace(System.err);
            System.exit(10);
        }
    }

    private static String readStdin() throws Exception {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(System.in))) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append("\n");
            }
        }
        return sb.toString();
    }

    private static void inspectPlugin(JarFile jar, ClassLoader loader) throws Exception {
        String pluginId = "";
        String commandLineProcessorClass = "";
        List<String> optionsJson = new ArrayList<>();

        ZipEntry cmdProcEntry = jar.getEntry("META-INF/services/org.jetbrains.kotlin.compiler.plugin.CommandLineProcessor");
        if (cmdProcEntry != null) {
            try (InputStream is = jar.getInputStream(cmdProcEntry);
                 BufferedReader reader = new BufferedReader(new InputStreamReader(is))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    line = line.trim();
                    if (line.isEmpty() || line.startsWith("#")) continue;
                    commandLineProcessorClass = line;
                    try {
                        Class<?> clazz = loader.loadClass(line);
                        Object instance = clazz.getDeclaredConstructor().newInstance();
                        Method getPluginId = clazz.getMethod("getPluginId");
                        pluginId = (String) getPluginId.invoke(instance);

                        Method getOptions = clazz.getMethod("getPluginOptions");
                        Collection<?> options = (Collection<?>) getOptions.invoke(instance);
                        if (options != null) {
                            for (Object opt : options) {
                                Method getOptName = opt.getClass().getMethod("getOptionName");
                                Method getDescription = opt.getClass().getMethod("getDescription");
                                Method isRequiredMethod = null;
                                try {
                                    isRequiredMethod = opt.getClass().getMethod("getRequired");
                                } catch (NoSuchMethodException ignored) {}
                                boolean required = false;
                                if (isRequiredMethod != null) {
                                    Object reqVal = isRequiredMethod.invoke(opt);
                                    if (reqVal instanceof Boolean) {
                                        required = (Boolean) reqVal;
                                    }
                                }

                                String optName = (String) getOptName.invoke(opt);
                                String desc = (String) getDescription.invoke(opt);
                                optionsJson.add(String.format(
                                        "{\"name\":\"%s\",\"description\":\"%s\",\"required\":%b}",
                                        escapeJson(optName), escapeJson(desc), required
                                ));
                            }
                        }
                    } catch (Throwable t) {
                        System.err.println("Warning: failed to inspect CommandLineProcessor: " + t.getMessage());
                    }
                    break;
                }
            }
        }

        String registrarClass = "";
        ZipEntry regEntry = jar.getEntry("META-INF/services/org.jetbrains.kotlin.compiler.plugin.CompilerPluginRegistrar");
        if (regEntry == null) {
            regEntry = jar.getEntry("META-INF/services/org.jetbrains.kotlin.compiler.plugin.ComponentRegistrar");
        }
        if (regEntry != null) {
            try (InputStream is = jar.getInputStream(regEntry);
                 BufferedReader reader = new BufferedReader(new InputStreamReader(is))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    line = line.trim();
                    if (line.isEmpty() || line.startsWith("#")) continue;
                    registrarClass = line;
                    break;
                }
            }
        }

        StringBuilder sb = new StringBuilder();
        sb.append("{");
        sb.append("\"pluginId\":\"").append(escapeJson(pluginId)).append("\",");
        sb.append("\"commandLineProcessor\":\"").append(escapeJson(commandLineProcessorClass)).append("\",");
        sb.append("\"registrar\":\"").append(escapeJson(registrarClass)).append("\",");
        sb.append("\"options\":[").append(String.join(",", optionsJson)).append("]");
        sb.append("}");

        System.out.println(sb.toString());
    }

    /**
     * Executes Phase 2 Sema transformation planning by inspecting the plugin's configuration,
     * presets, and declarations.
     */
    @SuppressWarnings("unchecked")
    private static void transformSema(JarFile jar, ClassLoader loader, String payloadJson) throws Exception {
        // Minimal JSON parser for the payload
        Map<String, List<String>> pluginOptions = parseStringListMap(payloadJson, "options");
        List<Map<String, Object>> classes = parseClassList(payloadJson);

        // Detect plugin type and target annotations
        Set<String> targetAnnotations = new HashSet<>();
        boolean isAllOpen = false;
        boolean isNoArg = false;
        boolean isParcelize = false;
        boolean isSerialization = false;
        boolean isSamWithReceiver = false;
        boolean isAssignment = false;
        boolean isPowerAssert = false;
        boolean isLombok = false;
        boolean isCompose = false;
        boolean noArgInvokeInitializers = false;

        // Try to identify from CommandLineProcessor
        String pluginId = "";
        ZipEntry cmdProcEntry = jar.getEntry("META-INF/services/org.jetbrains.kotlin.compiler.plugin.CommandLineProcessor");
        if (cmdProcEntry != null) {
            try (InputStream is = jar.getInputStream(cmdProcEntry);
                 BufferedReader reader = new BufferedReader(new InputStreamReader(is))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    line = line.trim();
                    if (line.isEmpty() || line.startsWith("#")) continue;
                    try {
                        Class<?> clazz = loader.loadClass(line);
                        Object instance = clazz.getDeclaredConstructor().newInstance();
                        Method getPluginId = clazz.getMethod("getPluginId");
                        pluginId = (String) getPluginId.invoke(instance);
                    } catch (Throwable ignored) {}
                    break;
                }
            }
        }

        if ("org.jetbrains.kotlin.allopen".equals(pluginId) || jar.getEntry("org/jetbrains/kotlin/allopen/AllOpenPluginNames.class") != null) {
            isAllOpen = true;
            resolveAllOpenAnnotations(loader, pluginOptions, targetAnnotations);
        } else if ("org.jetbrains.kotlin.noarg".equals(pluginId) || jar.getEntry("org/jetbrains/kotlin/noarg/NoArgPluginNames.class") != null) {
            isNoArg = true;
            noArgInvokeInitializers = resolveNoArgAnnotations(loader, pluginOptions, targetAnnotations);
        } else if ("org.jetbrains.kotlin.parcelize".equals(pluginId) || jar.getEntry("org/jetbrains/kotlin/parcelize/ParcelizeCommandLineProcessor.class") != null) {
            isParcelize = true;
            targetAnnotations.add("kotlinx.parcelize.Parcelize");
            targetAnnotations.add("kotlinx.android.parcel.Parcelize");
            List<String> additional = pluginOptions.get("additionalAnnotation");
            if (additional != null) {
                targetAnnotations.addAll(additional);
            }
        } else if ("org.jetbrains.kotlinx.serialization".equals(pluginId)
                || jar.getEntry("org/jetbrains/kotlinx/serialization/compiler/extensions/SerializationComponentRegistrar.class") != null) {
            isSerialization = true;
            targetAnnotations.add("kotlinx.serialization.Serializable");
            List<String> additional = pluginOptions.get("additionalAnnotation");
            if (additional != null) {
                targetAnnotations.addAll(additional);
            }
        } else if ("org.jetbrains.kotlin.samWithReceiver".equals(pluginId)
                || jar.getEntry("org/jetbrains/kotlin/samWithReceiver/SamWithReceiverCommandLineProcessor.class") != null) {
            isSamWithReceiver = true;
        } else if ("org.jetbrains.kotlin.assignment".equals(pluginId)
                || jar.getEntry("org/jetbrains/kotlin/assignment/plugin/AssignmentCommandLineProcessor.class") != null) {
            isAssignment = true;
        } else if ("org.jetbrains.kotlin.powerassert".equals(pluginId)
                || jar.getEntry("org/jetbrains/kotlin/powerassert/PowerAssertCommandLineProcessor.class") != null) {
            isPowerAssert = true;
        } else if ("org.jetbrains.kotlin.lombok".equals(pluginId)
                || jar.getEntry("org/jetbrains/kotlin/lombok/LombokCommandLineProcessor.class") != null) {
            isLombok = true;
        } else if ("androidx.compose.compiler.plugins.kotlin".equals(pluginId)
                || jar.getEntry("androidx/compose/compiler/plugins/kotlin/ComposeCommandLineProcessor.class") != null) {
            isCompose = true;
        }

        // Generic fallback: if "annotation" options were provided, include them
        List<String> customAnnotations = pluginOptions.get("annotation");
        if (customAnnotations != null) {
            targetAnnotations.addAll(customAnnotations);
        }

        // Generate Plan
        List<String> classesToOpen = new ArrayList<>();
        List<String> membersToOpen = new ArrayList<>();
        List<String> syntheticConstructors = new ArrayList<>();
        List<String> syntheticMethods = new ArrayList<>();
        List<String> serializableClasses = new ArrayList<>();
        List<String> samWithReceiverInterfaces = new ArrayList<>();
        List<String> assignmentOverloadTargets = new ArrayList<>();
        List<String> powerAssertFunctions = new ArrayList<>();
        List<String> lombokConfigPaths = new ArrayList<>();

        if (isPowerAssert) {
            List<String> functions = pluginOptions.get("function");
            if (functions != null && !functions.isEmpty()) {
                powerAssertFunctions.addAll(functions);
            } else {
                powerAssertFunctions.add("kotlin.assert");
            }
        }
        if (isLombok) {
            List<String> configs = pluginOptions.get("config");
            if (configs != null && !configs.isEmpty()) {
                lombokConfigPaths.addAll(configs);
            }
        }

        for (Map<String, Object> clazz : classes) {
            String fqName = (String) clazz.get("fqName");
            List<String> annotations = (List<String>) clazz.get("annotations");
            List<Map<String, Object>> members = (List<Map<String, Object>>) clazz.get("members");
            List<Integer> ctorParamCounts = (List<Integer>) clazz.get("ctorParamCounts");

            boolean matches = false;
            for (String ann : annotations) {
                if (targetAnnotations.contains(ann)) {
                    matches = true;
                    break;
                }
            }

            if (!matches) continue;

            if (isAllOpen) {
                classesToOpen.add(fqName);
                if (members != null) {
                    for (Map<String, Object> member : members) {
                        String memberName = (String) member.get("name");
                        membersToOpen.add(fqName + "." + memberName);
                    }
                }
            }

            if (isNoArg) {
                boolean hasZeroArgCtor = ctorParamCounts != null && ctorParamCounts.contains(0);
                if (!hasZeroArgCtor) {
                    syntheticConstructors.add(String.format(
                            "{\"classFqName\":\"%s\",\"runsInitializers\":%b}",
                            escapeJson(fqName), noArgInvokeInitializers
                    ));
                }
            }

            if (isParcelize) {
                syntheticMethods.add(String.format(
                        "{\"classFqName\":\"%s\",\"name\":\"describeContents\",\"returnType\":\"kotlin.Int\",\"defaultIntReturn\":0,\"instructions\":[{\"kind\":\"returnInt\",\"intValue\":0}]}",
                        escapeJson(fqName)
                ));
                syntheticMethods.add(String.format(
                        "{\"classFqName\":\"%s\",\"name\":\"writeToParcel\",\"returnType\":\"kotlin.Unit\",\"params\":[{\"name\":\"parcel\",\"type\":\"android.os.Parcel\"},{\"name\":\"flags\",\"type\":\"kotlin.Int\"}],\"instructions\":[{\"kind\":\"returnUnit\"}]}",
                        escapeJson(fqName)
                ));
            }

            if (isSerialization) {
                serializableClasses.add(fqName);
            }

            if (isSamWithReceiver) {
                samWithReceiverInterfaces.add(fqName);
            }

            if (isAssignment) {
                assignmentOverloadTargets.add(fqName);
            }
        }

        // Print Sema Transform Plan JSON
        StringBuilder sb = new StringBuilder();
        sb.append("{");
        sb.append("\"classesToOpen\":[").append(formatJsonStringArray(classesToOpen)).append("],");
        sb.append("\"membersToOpen\":[").append(formatJsonStringArray(membersToOpen)).append("],");
        sb.append("\"syntheticConstructors\":[").append(String.join(",", syntheticConstructors)).append("],");
        sb.append("\"syntheticMethods\":[").append(String.join(",", syntheticMethods)).append("],");
        sb.append("\"serializableClasses\":[").append(formatJsonStringArray(serializableClasses)).append("],");
        sb.append("\"samWithReceiverInterfaces\":[").append(formatJsonStringArray(samWithReceiverInterfaces)).append("],");
        sb.append("\"assignmentOverloadTargets\":[").append(formatJsonStringArray(assignmentOverloadTargets)).append("],");
        sb.append("\"powerAssertFunctions\":[").append(formatJsonStringArray(powerAssertFunctions)).append("],");
        sb.append("\"lombokEnabled\":").append(isLombok ? "true" : "false").append(",");
        sb.append("\"lombokConfigPaths\":[").append(formatJsonStringArray(lombokConfigPaths)).append("],");
        sb.append("\"composeEnabled\":").append(isCompose ? "true" : "false");
        sb.append("}");

        System.out.println(sb.toString());
    }

    private static void resolveAllOpenAnnotations(ClassLoader loader, Map<String, List<String>> options, Set<String> target) {
        List<String> explicitAnnotations = options.get("annotation");
        if (explicitAnnotations != null) {
            target.addAll(explicitAnnotations);
        }

        List<String> presets = options.get("preset");
        if (presets != null && !presets.isEmpty()) {
            try {
                Class<?> namesClass = loader.loadClass("org.jetbrains.kotlin.allopen.AllOpenPluginNames");
                Object instance = namesClass.getField("INSTANCE").get(null);
                Method getPresets = namesClass.getMethod("getSUPPORTED_PRESETS");
                Map<?, ?> supported = (Map<?, ?>) getPresets.invoke(instance);
                for (String preset : presets) {
                    Object anns = supported.get(preset);
                    if (anns instanceof Collection<?>) {
                        for (Object a : (Collection<?>) anns) {
                            if (a != null) target.add(a.toString());
                        }
                    }
                }
            } catch (Throwable t) {
                // Built-in fallback presets for Spring, JPA, Micronaut, Quarkus
                for (String preset : presets) {
                    if ("spring".equalsIgnoreCase(preset)) {
                        target.add("org.springframework.stereotype.Component");
                        target.add("org.springframework.transaction.annotation.Transactional");
                        target.add("org.springframework.scheduling.annotation.Async");
                        target.add("org.springframework.cache.annotation.Cacheable");
                        target.add("org.springframework.boot.test.context.SpringBootTest");
                        target.add("org.springframework.validation.annotation.Validated");
                    } else if ("jpa".equalsIgnoreCase(preset)) {
                        target.add("javax.persistence.Entity");
                        target.add("javax.persistence.Embeddable");
                        target.add("javax.persistence.MappedSuperclass");
                        target.add("jakarta.persistence.Entity");
                        target.add("jakarta.persistence.Embeddable");
                        target.add("jakarta.persistence.MappedSuperclass");
                    }
                }
            }
        }
    }

    private static boolean resolveNoArgAnnotations(ClassLoader loader, Map<String, List<String>> options, Set<String> target) {
        List<String> explicitAnnotations = options.get("annotation");
        if (explicitAnnotations != null) {
            target.addAll(explicitAnnotations);
        }

        List<String> presets = options.get("preset");
        if (presets != null && !presets.isEmpty()) {
            try {
                Class<?> namesClass = loader.loadClass("org.jetbrains.kotlin.noarg.NoArgPluginNames");
                Object instance = namesClass.getField("INSTANCE").get(null);
                Method getPresets = namesClass.getMethod("getSUPPORTED_PRESETS");
                Map<?, ?> supported = (Map<?, ?>) getPresets.invoke(instance);
                for (String preset : presets) {
                    Object anns = supported.get(preset);
                    if (anns instanceof Collection<?>) {
                        for (Object a : (Collection<?>) anns) {
                            if (a != null) target.add(a.toString());
                        }
                    }
                }
            } catch (Throwable t) {
                for (String preset : presets) {
                    if ("jpa".equalsIgnoreCase(preset)) {
                        target.add("javax.persistence.Entity");
                        target.add("javax.persistence.Embeddable");
                        target.add("javax.persistence.MappedSuperclass");
                        target.add("jakarta.persistence.Entity");
                        target.add("jakarta.persistence.Embeddable");
                        target.add("jakarta.persistence.MappedSuperclass");
                    }
                }
            }
        }

        List<String> invokeInit = options.get("invokeInitializers");
        if (invokeInit != null && !invokeInit.isEmpty()) {
            return "true".equalsIgnoreCase(invokeInit.get(0));
        }
        return false;
    }

    // --- Lightweight JSON Parsing Helpers ---

    private static Map<String, List<String>> parseStringListMap(String json, String key) {
        Map<String, List<String>> result = new HashMap<>();
        int keyIdx = json.indexOf("\"" + key + "\"");
        if (keyIdx == -1) return result;

        int openBrace = json.indexOf("{", keyIdx);
        if (openBrace == -1) return result;

        int closeBrace = findMatchingBracket(json, openBrace, '{', '}');
        if (closeBrace == -1) return result;

        String content = json.substring(openBrace + 1, closeBrace).trim();
        // Simple key: [val1, val2] parser
        String[] entries = content.split(",(?=([^\"]*\"[^\"]*\")*[^\"]*$)");
        for (String entry : entries) {
            int colon = entry.indexOf(":");
            if (colon == -1) continue;
            String k = unquote(entry.substring(0, colon).trim());
            String v = entry.substring(colon + 1).trim();
            List<String> list = new ArrayList<>();
            if (v.startsWith("[") && v.endsWith("]")) {
                String inner = v.substring(1, v.length() - 1).trim();
                if (!inner.isEmpty()) {
                    for (String item : inner.split(",")) {
                        list.add(unquote(item.trim()));
                    }
                }
            } else {
                list.add(unquote(v));
            }
            result.put(k, list);
        }
        return result;
    }

    private static List<Map<String, Object>> parseClassList(String json) {
        List<Map<String, Object>> classes = new ArrayList<>();
        int keyIdx = json.indexOf("\"classes\"");
        if (keyIdx == -1) return classes;

        int openBracket = json.indexOf("[", keyIdx);
        if (openBracket == -1) return classes;

        int closeBracket = findMatchingBracket(json, openBracket, '[', ']');
        if (closeBracket == -1) return classes;

        String content = json.substring(openBracket + 1, closeBracket).trim();
        int idx = 0;
        while (idx < content.length()) {
            int nextObj = content.indexOf("{", idx);
            if (nextObj == -1) break;
            int endObj = findMatchingBracket(content, nextObj, '{', '}');
            if (endObj == -1) break;

            String objStr = content.substring(nextObj, endObj + 1);
            Map<String, Object> classMap = new HashMap<>();

            // Parse fqName
            classMap.put("fqName", extractJsonString(objStr, "fqName"));

            // Parse annotations
            classMap.put("annotations", extractJsonStringList(objStr, "annotations"));

            // Parse ctorParamCounts
            classMap.put("ctorParamCounts", extractJsonIntList(objStr, "ctorParamCounts"));

            // Parse members
            List<Map<String, Object>> members = new ArrayList<>();
            int memIdx = objStr.indexOf("\"members\"");
            if (memIdx != -1) {
                int memOpen = objStr.indexOf("[", memIdx);
                int memClose = memOpen != -1 ? findMatchingBracket(objStr, memOpen, '[', ']') : -1;
                if (memOpen != -1 && memClose != -1) {
                    String memContent = objStr.substring(memOpen + 1, memClose).trim();
                    int mIdx = 0;
                    while (mIdx < memContent.length()) {
                        int mStart = memContent.indexOf("{", mIdx);
                        if (mStart == -1) break;
                        int mEnd = findMatchingBracket(memContent, mStart, '{', '}');
                        if (mEnd == -1) break;
                        String mStr = memContent.substring(mStart, mEnd + 1);
                        Map<String, Object> memMap = new HashMap<>();
                        memMap.put("name", extractJsonString(mStr, "name"));
                        members.add(memMap);
                        mIdx = mEnd + 1;
                    }
                }
            }
            classMap.put("members", members);

            classes.add(classMap);
            idx = endObj + 1;
        }

        return classes;
    }

    private static String extractJsonString(String json, String key) {
        int idx = json.indexOf("\"" + key + "\"");
        if (idx == -1) return "";
        int colon = json.indexOf(":", idx);
        int quoteStart = json.indexOf("\"", colon);
        int quoteEnd = json.indexOf("\"", quoteStart + 1);
        if (quoteStart == -1 || quoteEnd == -1) return "";
        return json.substring(quoteStart + 1, quoteEnd);
    }

    private static List<String> extractJsonStringList(String json, String key) {
        List<String> list = new ArrayList<>();
        int idx = json.indexOf("\"" + key + "\"");
        if (idx == -1) return list;
        int open = json.indexOf("[", idx);
        int close = open != -1 ? findMatchingBracket(json, open, '[', ']') : -1;
        if (open == -1 || close == -1) return list;
        String content = json.substring(open + 1, close).trim();
        if (content.isEmpty()) return list;
        for (String item : content.split(",")) {
            list.add(unquote(item.trim()));
        }
        return list;
    }

    private static List<Integer> extractJsonIntList(String json, String key) {
        List<Integer> list = new ArrayList<>();
        int idx = json.indexOf("\"" + key + "\"");
        if (idx == -1) return list;
        int open = json.indexOf("[", idx);
        int close = open != -1 ? findMatchingBracket(json, open, '[', ']') : -1;
        if (open == -1 || close == -1) return list;
        String content = json.substring(open + 1, close).trim();
        if (content.isEmpty()) return list;
        for (String item : content.split(",")) {
            try {
                list.add(Integer.parseInt(item.trim()));
            } catch (NumberFormatException ignored) {}
        }
        return list;
    }

    private static int findMatchingBracket(String s, int openIdx, char openCh, char closeCh) {
        int depth = 0;
        boolean inQuote = false;
        for (int i = openIdx; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"' && (i == 0 || s.charAt(i - 1) != '\\')) {
                inQuote = !inQuote;
            } else if (!inQuote) {
                if (c == openCh) depth++;
                else if (c == closeCh) {
                    depth--;
                    if (depth == 0) return i;
                }
            }
        }
        return -1;
    }

    private static String unquote(String s) {
        if (s == null) return "";
        s = s.trim();
        if (s.startsWith("\"") && s.endsWith("\"") && s.length() >= 2) {
            s = s.substring(1, s.length() - 1);
        }
        return s.replace("\\\"", "\"").replace("\\\\", "\\");
    }

    private static String formatJsonStringArray(List<String> list) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < list.size(); i++) {
            if (i > 0) sb.append(",");
            sb.append("\"").append(escapeJson(list.get(i))).append("\"");
        }
        return sb.toString();
    }

    private static String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
}
