//
//  RecipeExtractorService.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//  Extracts recipes directly from Minecraft server.jar using Java data generator or jar reading.
//

import Foundation
import Combine

@MainActor
final class RecipeExtractorService: ObservableObject {
    static let shared = RecipeExtractorService()

    @Published var isExtracting: Bool = false
    @Published var progress: Double = 0.0
    @Published var statusDescription: String = "Ready"
    @Published var consoleLogs: String = ""
    @Published var generatedRecipePackage: RecipePackage?
    @Published var outputFileURL: URL?

    // MARK: - Java Detection

    func findJavaExecutable() -> String? {
        let possibleJVMPaths = [
            "/Library/Java/JavaVirtualMachines",
            NSHomeDirectory() + "/Library/Java/JavaVirtualMachines"
        ]

        let fileManager = FileManager.default
        for root in possibleJVMPaths {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            // Sort to prefer newer JDKs like jdk-21
            for entry in entries.sorted().reversed() {
                let javaPath = "\(root)/\(entry)/Contents/Home/bin/java"
                if fileManager.isExecutableFile(atPath: javaPath) {
                    return javaPath
                }
            }
        }

        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            let candidate = "\(javaHome)/bin/java"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        if fileManager.isExecutableFile(atPath: "/usr/bin/java") {
            return "/usr/bin/java"
        }

        return nil
    }

    // MARK: - Extraction Routine

    func extractRecipes(
        from jarURL: URL,
        customVersion: String? = nil,
        useDataGenerator: Bool = true
    ) async {
        isExtracting = true
        progress = 0.05
        statusDescription = "Preparing extraction environment…"
        consoleLogs = "[Craftify Extractor] Starting extraction for: \(jarURL.lastPathComponent)\n"
        generatedRecipePackage = nil
        outputFileURL = nil

        let fileManager = FileManager.default
        let isSecurityScoped = jarURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped { jarURL.stopAccessingSecurityScopedResource() }
            isExtracting = false
        }

        // Detect version name
        let detectedVersion = customVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? customVersion!
            : detectVersionName(from: jarURL.lastPathComponent)

        log("Target Minecraft version: \(detectedVersion)")

        // 1. Check for Python extractor helper script in bundle / repo
        let projectScript = Bundle.main.path(forResource: "extract_recipes", ofType: "py")
            ?? findScriptInWorkspace()

        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("CraftifyExtract_\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let outputURL = tempDirectory.appendingPathComponent("\(detectedVersion).recipe")

        var success = false

        if let scriptPath = projectScript, fileManager.fileExists(atPath: scriptPath) {
            log("Running extraction engine via \(URL(fileURLWithPath: scriptPath).lastPathComponent)…")
            success = await runScriptExtraction(
                scriptPath: scriptPath,
                jarURL: jarURL,
                outputURL: outputURL,
                version: detectedVersion,
                useDataGenerator: useDataGenerator
            )
        } else {
            // Fallback: Swift jar unpacking
            log("Using built-in archive reader…")
            success = await runBuiltinExtraction(
                jarURL: jarURL,
                outputURL: outputURL,
                version: detectedVersion
            )
        }

        if success && fileManager.fileExists(atPath: outputURL.path) {
            if let data = try? Data(contentsOf: outputURL),
               let pkg = try? JSONDecoder().decode(RecipePackage.self, from: data) {
                progress = 1.0
                statusDescription = "Extraction complete! Generated \(pkg.recipeCount) recipes."
                log("🎉 Successfully created .recipe package: \(pkg.recipeCount) recipes across \(pkg.categories?.count ?? 0) categories!")
                self.generatedRecipePackage = pkg
                self.outputFileURL = outputURL
                return
            }
        }

        progress = 0.0
        statusDescription = "Extraction failed. See logs for details."
        log("❌ Extraction failed.")
    }

    // MARK: - Script Execution

    private func runScriptExtraction(
        scriptPath: String,
        jarURL: URL,
        outputURL: URL,
        version: String,
        useDataGenerator: Bool
    ) async -> Bool {
        let javaBin = findJavaExecutable() ?? "java"
        log("Detected Java Runtime: \(javaBin)")

        var env = ProcessInfo.processInfo.environment
        let javaParent = (javaBin as NSString).deletingLastPathComponent
        if !javaParent.isEmpty {
            let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
            env["PATH"] = "\(javaParent):\(currentPath)"
        }

        let pythonBin = "/usr/bin/python3"
        var args = [
            scriptPath,
            "--jar", jarURL.path,
            "--output", outputURL.path,
            "--version", version
        ]
        if useDataGenerator {
            args.append("--run-generator")
            log("Executing command: java -DbundlerRepoDir=. -cp \(jarURL.lastPathComponent) net.minecraft.data.Main --reports --all")
        }

        progress = 0.40
        statusDescription = "Processing Minecraft recipes…"

        let finalArgs = args
        let finalEnv = env
        let res = await Task.detached { () -> (Bool, String) in
            return Self.runDynamicTask(executablePath: pythonBin, arguments: finalArgs, environment: finalEnv)
        }.value

        if !res.1.isEmpty {
            log(res.1)
        }
        return res.0
    }

    // MARK: - Built-in Fallback Extraction

    private func runBuiltinExtraction(jarURL: URL, outputURL: URL, version: String) async -> Bool {
        log("Executing jar extraction via unzip command…")
        let tempExtractDir = outputURL.deletingLastPathComponent().appendingPathComponent("raw_jar", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)

        let unzipRes = await Task.detached { () -> (Bool, String) in
            return Self.runDynamicTask(
                executablePath: "/usr/bin/unzip",
                arguments: ["-q", "-o", jarURL.path, "data/minecraft/recipe/*", "data/minecraft/recipes/*", "-d", tempExtractDir.path],
                environment: nil
            )
        }.value

        if !unzipRes.1.isEmpty {
            log(unzipRes.1)
        }

        // Scan extracted json files
        let recipeDir = tempExtractDir.appendingPathComponent("data/minecraft/recipe")
        let legacyRecipeDir = tempExtractDir.appendingPathComponent("data/minecraft/recipes")
        let targetDir = FileManager.default.fileExists(atPath: recipeDir.path) ? recipeDir : legacyRecipeDir

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: targetDir.path) else {
            log("No recipe files found in jar.")
            return false
        }

        log("Found \(files.count) recipe files. Processing into Craftify format…")
        var recipes: [Recipe] = []
        var nextId = 1

        for file in files where file.hasSuffix(".json") {
            let fileURL = targetDir.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: fileURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let r = parseRawRecipe(json, id: nextId, version: version) {
                recipes.append(r)
                nextId += 1
            }
        }

        recipes.sort { $0.name < $1.name }
        let categories = Array(Set(recipes.map(\.category))).sorted()

        let package = RecipePackage(
            formatVersion: 1,
            gameVersion: version,
            edition: "Java",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            generator: "Craftify Builtin Extractor",
            recipeCount: recipes.count,
            categories: categories,
            recipes: recipes
        )

        if let encoded = try? JSONEncoder().encode(package) {
            try? encoded.write(to: outputURL)
            return true
        }

        return false
    }

    private func parseRawRecipe(_ json: [String: Any], id: Int, version: String) -> Recipe? {
        let type = json["type"] as? String ?? ""
        let catKey = (json["category"] as? String ?? "").lowercased()
        var category = "Miscellaneous"
        switch catKey {
        case "building", "blocks": category = "Building Blocks"
        case "equipment": category = "Equipment"
        case "redstone": category = "Redstone"
        case "food", "cooking": category = "Food & Cooking"
        case "misc": category = "Miscellaneous"
        default: break
        }

        var resultName = ""
        var count = 1
        if let resObj = json["result"] as? [String: Any] {
            let itemId = resObj["id"] as? String ?? resObj["item"] as? String ?? ""
            resultName = formatItemName(itemId)
            count = resObj["count"] as? Int ?? 1
        } else if let resStr = json["result"] as? String {
            resultName = formatItemName(resStr)
        }

        guard !resultName.isEmpty else { return nil }

        var ingredients = Array(repeating: "", count: 9)
        var imageremark = "Crafting Table"

        if type.contains("smelting") || type.contains("cooking") || type.contains("smoking") || type.contains("blasting") {
            imageremark = type.contains("smoking") ? "Smoker" : (type.contains("blasting") ? "Blast Furnace" : "Furnace")
            ingredients = ["Ingredient", ""]
        }

        return Recipe(
            id: id,
            name: resultName,
            image: resultName,
            ingredients: ingredients,
            alternateIngredients: nil,
            alternateIngredients1: nil,
            alternateIngredients2: nil,
            alternateIngredients3: nil,
            output: count,
            alternateOutput: nil,
            alternateOutput1: nil,
            alternateOutput2: nil,
            alternateOutput3: nil,
            category: category,
            imageremark: imageremark,
            remarks: nil
        )
    }

    private func formatItemName(_ itemId: String) -> String {
        let raw = itemId.components(separatedBy: ":").last ?? itemId
        return raw.split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func log(_ msg: String) {
        consoleLogs.append("\(msg)\n")
    }

    private func detectVersionName(from filename: String) -> String {
        let range = NSRange(location: 0, length: filename.utf16.count)
        let regex = try? NSRegularExpression(pattern: #"(\d+\.\d+(\.\d+)?)"#)
        if let match = regex?.firstMatch(in: filename, options: [], range: range),
           let r = Range(match.range(at: 1), in: filename) {
            return String(filename[r])
        }
        return "1.21.1"
    }

    private func findScriptInWorkspace() -> String? {
        let possible = [
            "scripts/extract_recipes.py",
            "../scripts/extract_recipes.py"
        ]
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        for p in possible {
            let full = "\(cwd)/\(p)"
            if fm.fileExists(atPath: full) {
                return full
            }
        }
        return nil
    }

    // MARK: - Dynamic Process Execution for Mac Catalyst

    nonisolated private static func runDynamicTask(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?
    ) -> (Bool, String) {
        guard let taskClass = NSClassFromString("NSTask") as? NSObject.Type else {
            return (false, "Subprocess execution is unavailable on this platform.")
        }
        let task = taskClass.init()
        let pipe = Pipe()
        task.setValue(executablePath, forKey: "launchPath")
        task.setValue(arguments, forKey: "arguments")
        if let env = environment {
            task.setValue(env, forKey: "environment")
        }
        task.setValue(pipe, forKey: "standardOutput")
        task.setValue(pipe, forKey: "standardError")
        _ = task.perform(NSSelectorFromString("launch"))
        _ = task.perform(NSSelectorFromString("waitUntilExit"))
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let status = (task.value(forKey: "terminationStatus") as? Int32) ?? 0
        return (status == 0, output)
    }
}

