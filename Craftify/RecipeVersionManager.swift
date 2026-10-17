//
//  RecipeVersionManager.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//  Optimized for local multi-version recipe import, management, and per-version isolated icon packaging.
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
            if !activeVersion.isEmpty {
                if oldValue != activeVersion {
                    defaults.set(activeVersion, forKey: activeVersionKey)
                }
                ensureVersionIconsUnpacked(for: activeVersion)
                CraftImageStore.shared.setActiveVersion(activeVersion)
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
        if !activeVersion.isEmpty {
            ensureVersionIconsUnpacked(for: activeVersion)
            CraftImageStore.shared.setActiveVersion(activeVersion)
        }
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

    private func bundledStampKey(for version: String) -> String {
        "craftify.bundledRecipeStamp.\(version)"
    }

    private func seedBundledVersionsIfNeeded() {
        // Find all bundled .recipe files
        let bundleRecipes = Bundle.main.urls(forResourcesWithExtension: "recipe", subdirectory: nil) ?? []
        for url in bundleRecipes {
            let verName = url.deletingPathExtension().lastPathComponent
            let bundleFileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let storedStamp = defaults.string(forKey: bundledStampKey(for: verName)) ?? ""
            let existing = installedVersions.first(where: { $0.version == verName })
            let needsIconUpgrade = existing != nil && existing!.isDefault && (
                existing!.iconCount == 0
                || !CraftImageStore.shared.hasVersionIcons(for: verName)
                || !storedStamp.hasPrefix("\(bundleFileSize):")
            )
            if existing == nil || needsIconUpgrade {
                _ = importBundledRecipe(from: url, isDefault: true)
            }
        }

        // Also check in Resources subfolder if needed
        if installedVersions.isEmpty {
            if let defaultURL = Bundle.main.url(forResource: "1.21.1", withExtension: "recipe") {
                _ = importBundledRecipe(from: defaultURL, isDefault: true)
            }
        }

        // Ensure all installed versions have their bundled icons unpacked
        for info in installedVersions {
            ensureVersionIconsUnpacked(for: info.version)
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

        var storedIcons = package.iconCount ?? 0
        if let icons = package.icons, !icons.isEmpty {
            storedIcons = CraftImageStore.shared.storeVersionIcons(icons, for: package.gameVersion)
        }

        let info = RecipeVersionInfo(
            version: package.gameVersion,
            displayName: "Minecraft \(package.gameVersion)",
            edition: package.edition,
            recipeCount: package.recipeCount,
            iconCount: storedIcons,
            categories: package.categories ?? [],
            importedAt: Date(),
            isDefault: isDefault,
            fileName: fileName
        )

        defaults.set("\(data.count):\(package.createdAt ?? "")", forKey: bundledStampKey(for: package.gameVersion))
        installedVersions.removeAll { $0.version == info.version }
        installedVersions.append(info)
        saveMetadata()
        return true
    }

    func ensureVersionIconsUnpacked(for version: String) {
        guard !CraftImageStore.shared.hasVersionIcons(for: version),
              let idx = installedVersions.firstIndex(where: { $0.version == version }) else {
            return
        }
        let info = installedVersions[idx]
        let fileURL = storageDirectory.appendingPathComponent(info.fileName)
        guard let data = try? Data(contentsOf: fileURL),
              let package = try? decodeRecipePackage(from: data),
              let icons = package.icons,
              !icons.isEmpty else {
            return
        }

        let count = CraftImageStore.shared.storeVersionIcons(icons, for: version)
        if count > 0 && installedVersions[idx].iconCount != count {
            installedVersions[idx].iconCount = count
            saveMetadata()
        }
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
        if let icons = package.icons, !icons.isEmpty, !CraftImageStore.shared.hasVersionIcons(for: version) {
            _ = CraftImageStore.shared.storeVersionIcons(icons, for: version)
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
            // Generate a unique version string: e.g. "1.21.1 (1)"
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
        let sanitized = CraftImageAssetKey.sanitizeVersionIdentifier(targetVersion)
        let fileName = "\(sanitized).recipe"
        let destURL = storageDirectory.appendingPathComponent(fileName)

        var finalData = rawData
        // If version name was altered for "keep both", patch version in json while preserving bundled icons
        if targetVersion != package.gameVersion {
            let modifiedPackage = RecipePackage(
                formatVersion: package.formatVersion,
                gameVersion: targetVersion,
                edition: package.edition,
                createdAt: package.createdAt,
                generator: package.generator,
                recipeCount: package.recipeCount,
                iconCount: package.iconCount,
                categories: package.categories,
                recipes: package.recipes,
                icons: package.icons
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

        var storedIcons = package.iconCount ?? 0
        if let icons = package.icons, !icons.isEmpty {
            storedIcons = CraftImageStore.shared.storeVersionIcons(icons, for: targetVersion)
        } else if overwrite {
            CraftImageStore.shared.removeVersionIcons(for: targetVersion)
        }

        let info = RecipeVersionInfo(
            version: targetVersion,
            displayName: "Minecraft \(targetVersion)",
            edition: package.edition,
            recipeCount: package.recipeCount,
            iconCount: storedIcons,
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
        CraftImageStore.shared.removeVersionIcons(for: version)

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
                iconCount: 0,
                categories: cats,
                recipes: recipes,
                icons: nil
            )
        }
        throw NSError(domain: "RecipeVersionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid recipe format"])
    }
}
