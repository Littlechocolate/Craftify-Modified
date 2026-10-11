//
//  RecipeVersionManager.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//  Optimized for local multi-version recipe import and management.
//

import Foundation
import Combine

@MainActor
final class RecipeVersionManager: ObservableObject {
    static let shared = RecipeVersionManager()

    enum ImportOutcome {
        case success(RecipeVersionInfo)
        case duplicate(existing: RecipeVersionInfo, package: RecipePackage, rawData: Data)
        case failure(String)
    }

    @Published private(set) var installedVersions: [RecipeVersionInfo] = []
    @Published var activeVersion: String = "" {
        didSet {
            if oldValue != activeVersion && !activeVersion.isEmpty {
                defaults.set(activeVersion, forKey: activeVersionKey)
            }
        }
    }

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let activeVersionKey = "craftify.activeRecipeVersion"
    private let metadataFileName = "installed_recipe_versions.json"

    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("RecipeVersions", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        loadInstalledVersions()
        seedBundledVersionsIfNeeded()
    }

    // MARK: - Version Loading

    func loadInstalledVersions() {
        let metadataURL = storageDirectory.appendingPathComponent(metadataFileName)
        if let data = try? Data(contentsOf: metadataURL),
           let list = try? JSONDecoder().decode([RecipeVersionInfo].self, from: data) {
            installedVersions = list
        }

        let savedActive = defaults.string(forKey: activeVersionKey) ?? ""
        if !savedActive.isEmpty && installedVersions.contains(where: { $0.version == savedActive }) {
            activeVersion = savedActive
        } else if let first = installedVersions.first {
            activeVersion = first.version
        }
    }

    private func saveMetadata() {
        let metadataURL = storageDirectory.appendingPathComponent(metadataFileName)
        if let data = try? JSONEncoder().encode(installedVersions) {
            try? data.write(to: metadataURL)
        }
    }

    // MARK: - Bundled Defaults

    private func seedBundledVersionsIfNeeded() {
        // Find all bundled .recipe files
        let bundleRecipes = Bundle.main.urls(forResourcesWithExtension: "recipe", subdirectory: nil) ?? []
        for url in bundleRecipes {
            let verName = url.deletingPathExtension().lastPathComponent
            if !installedVersions.contains(where: { $0.version == verName }) {
                _ = importBundledRecipe(from: url, isDefault: true)
            }
        }

        // Also check in Resources subfolder if needed
        if installedVersions.isEmpty {
            if let defaultURL = Bundle.main.url(forResource: "1.21.1", withExtension: "recipe") {
                _ = importBundledRecipe(from: defaultURL, isDefault: true)
            }
        }

        if activeVersion.isEmpty, let first = installedVersions.first {
            activeVersion = first.version
        }
    }

    private func importBundledRecipe(from url: URL, isDefault: Bool) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let package = try? decodeRecipePackage(from: data) else {
            return false
        }

        let fileName = "\(package.gameVersion).recipe"
        let destURL = storageDirectory.appendingPathComponent(fileName)
        try? data.write(to: destURL)

        let info = RecipeVersionInfo(
            version: package.gameVersion,
            displayName: "Minecraft \(package.gameVersion)",
            edition: package.edition,
            recipeCount: package.recipeCount,
            categories: package.categories ?? [],
            importedAt: Date(),
            isDefault: isDefault,
            fileName: fileName
        )

        installedVersions.removeAll { $0.version == info.version }
        installedVersions.append(info)
        saveMetadata()
        return true
    }

    // MARK: - Active Recipes Provider

    func loadActiveRecipes() -> [Recipe] {
        guard !activeVersion.isEmpty else { return [] }
        return loadRecipes(forVersion: activeVersion)
    }

    func loadRecipes(forVersion version: String) -> [Recipe] {
        guard let info = installedVersions.first(where: { $0.version == version }) else {
            return []
        }
        let fileURL = storageDirectory.appendingPathComponent(info.fileName)
        guard let data = try? Data(contentsOf: fileURL),
              let package = try? decodeRecipePackage(from: data) else {
            return []
        }
        return package.recipes
    }

    // MARK: - Import Handling

    func prepareImport(from url: URL) -> ImportOutcome {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url) else {
            return .failure("Unable to read selected recipe file.")
        }

        guard let package = try? decodeRecipePackage(from: data) else {
            return .failure("Invalid .recipe file format. Please ensure it is a valid Craftify recipe package.")
        }

        let candidateVersion = package.gameVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidateVersion.isEmpty else {
            return .failure("Recipe package does not contain a valid version identifier.")
        }

        // Check if version is duplicate
        if let existing = installedVersions.first(where: { $0.version.caseInsensitiveCompare(candidateVersion) == .orderedSame }) {
            return .duplicate(existing: existing, package: package, rawData: data)
        }

        // Fresh import
        return completeSave(package: package, rawData: data, asVersion: candidateVersion)
    }

    func resolveDuplicate(
        package: RecipePackage,
        rawData: Data,
        resolution: DuplicateResolution
    ) -> ImportOutcome {
        switch resolution {
        case .cancel:
            return .failure("Import cancelled.")

        case .replace:
            return completeSave(package: package, rawData: rawData, asVersion: package.gameVersion, overwrite: true)

        case .keepBoth:
            // Generate a unique version string: e.g. "1.21.1 (2)"
            let newVersion = generateUniqueVersionName(base: package.gameVersion)
            return completeSave(package: package, rawData: rawData, asVersion: newVersion, overwrite: false)
        }
    }

    private func completeSave(
        package: RecipePackage,
        rawData: Data,
        asVersion targetVersion: String,
        overwrite: Bool = false
    ) -> ImportOutcome {
        let sanitized = targetVersion.replacingOccurrences(of: "/", with: "-")
        let fileName = "\(sanitized).recipe"
        let destURL = storageDirectory.appendingPathComponent(fileName)

        var finalData = rawData
        // If version name was altered for "keep both", patch version in json
        if targetVersion != package.gameVersion {
            let modifiedPackage = RecipePackage(
                formatVersion: package.formatVersion,
                gameVersion: targetVersion,
                edition: package.edition,
                createdAt: package.createdAt,
                generator: package.generator,
                recipeCount: package.recipeCount,
                categories: package.categories,
                recipes: package.recipes
            )
            if let encoded = try? JSONEncoder().encode(modifiedPackage) {
                finalData = encoded
            }
        }

        do {
            try finalData.write(to: destURL)
        } catch {
            return .failure("Failed to save recipe file: \(error.localizedDescription)")
        }

        let info = RecipeVersionInfo(
            version: targetVersion,
            displayName: "Minecraft \(targetVersion)",
            edition: package.edition,
            recipeCount: package.recipeCount,
            categories: package.categories ?? [],
            importedAt: Date(),
            isDefault: false,
            fileName: fileName
        )

        if overwrite {
            installedVersions.removeAll { $0.version == targetVersion }
        }
        installedVersions.append(info)
        saveMetadata()

        // Set as active
        activeVersion = targetVersion
        return .success(info)
    }

    // MARK: - Version Operations

    func deleteVersion(_ version: String) {
        guard let index = installedVersions.firstIndex(where: { $0.version == version }) else { return }
        let info = installedVersions[index]
        let fileURL = storageDirectory.appendingPathComponent(info.fileName)
        try? fileManager.removeItem(at: fileURL)

        installedVersions.remove(at: index)
        saveMetadata()

        if activeVersion == version {
            activeVersion = installedVersions.first?.version ?? ""
        }
    }

    func exportFileURL(for version: String) -> URL? {
        guard let info = installedVersions.first(where: { $0.version == version }) else { return nil }
        let fileURL = storageDirectory.appendingPathComponent(info.fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    // MARK: - Helpers

    private func generateUniqueVersionName(base: String) -> String {
        var counter = 1
        var candidate = "\(base) (\(counter))"
        while installedVersions.contains(where: { $0.version.caseInsensitiveCompare(candidate) == .orderedSame }) {
            counter += 1
            candidate = "\(base) (\(counter))"
        }
        return candidate
    }

    private func decodeRecipePackage(from data: Data) throws -> RecipePackage {
        // Try standard RecipePackage format
        if let pkg = try? JSONDecoder().decode(RecipePackage.self, from: data) {
            return pkg
        }
        // Fallback: try raw array of Recipe
        if let recipes = try? JSONDecoder().decode([Recipe].self, from: data) {
            let cats = Array(Set(recipes.map(\.category))).sorted()
            return RecipePackage(
                formatVersion: 1,
                gameVersion: "Custom",
                edition: "Java",
                createdAt: nil,
                generator: "Imported Array",
                recipeCount: recipes.count,
                categories: cats,
                recipes: recipes
            )
        }
        throw NSError(domain: "RecipeVersionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid recipe format"])
    }
}
