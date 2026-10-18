//
//  CraftImageStore.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 03/08/2026.
//

import Combine
import Foundation
import SwiftUI
import UIKit

enum CraftImageAssetKey {
    static let recordType = "CraftImageAsset"
    static let assetKeyField = "assetKey"
    static let fileField = "file"
    static let versionField = "version"

    static func recordName(for assetKey: String) -> String {
        let encoded = Data(assetKey.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "asset-\(encoded)"
    }

    static func normalizedAssetKey(_ assetKey: String) -> String {
        assetKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
    }

    static func sanitizeVersionIdentifier(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default" }
        return trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }
}

@MainActor
final class CraftImageStore: ObservableObject {
    static let shared = CraftImageStore()

    @Published private(set) var activeVersion: String = ""

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let imageDirectory: URL
    private let versionIconsRootDirectory: URL
    private let legacyCacheDirectory: URL
    private let imageCache = NSCache<NSString, UIImage>()
    private var loadingKeys: Set<String> = []
    private var lastChecked: [String: Date] = [:]
    private var storageGeneration = 0

    private static let versionDefaultsPrefix = "craft-image.version."
    private static let activeVersionDefaultsKey = "craftify.activeRecipeVersion"
    private let queryBatchSize = 100
    private let refreshInterval: TimeInterval = 15 * 60

    init(
        containerIdentifier: String = "iCloud.craftifydb",
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        storageDirectory: URL? = nil,
        versionIconsDirectory: URL? = nil,
        legacyCacheDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults

        let applicationSupportRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.imageDirectory = storageDirectory ?? applicationSupportRoot
            .appendingPathComponent("CraftImageAssets", isDirectory: true)
        self.versionIconsRootDirectory = versionIconsDirectory ?? applicationSupportRoot
            .appendingPathComponent("CraftVersionIconPacks", isDirectory: true)

        let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.legacyCacheDirectory = legacyCacheDirectory ?? cachesRoot
            .appendingPathComponent("CraftImageAssets", isDirectory: true)

        self.activeVersion = defaults.string(forKey: Self.activeVersionDefaultsKey) ?? ""

        prepareStorage()
        imageCache.countLimit = 3000
    }

    // MARK: - Per-Version Icon Isolation

    func setActiveVersion(_ version: String) {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeVersion != trimmed else { return }
        activeVersion = trimmed
        objectWillChange.send()
    }

    func versionDirectory(for version: String) -> URL {
        let sanitized = CraftImageAssetKey.sanitizeVersionIdentifier(version)
        return versionIconsRootDirectory.appendingPathComponent(sanitized, isDirectory: true)
    }

    func hasVersionIcons(for version: String) -> Bool {
        versionIconCount(for: version) > 0
    }

    func versionIconCount(for version: String) -> Int {
        let dir = versionDirectory(for: version)
        guard fileManager.fileExists(atPath: dir.path),
              let contents = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return 0
        }
        return contents.count
    }

    @discardableResult
    func storeVersionIcons(_ icons: [String: String], for version: String) -> Int {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty, !icons.isEmpty else { return 0 }

        let dir = versionDirectory(for: trimmedVersion)
        try? fileManager.removeItem(at: dir)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        var dirURL = dir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? dirURL.setResourceValues(resourceValues)

        var storedCount = 0
        for (rawKey, base64String) in icons {
            let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty,
                  let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters),
                  !data.isEmpty else {
                continue
            }

            let normalizedKey = CraftImageAssetKey.normalizedAssetKey(trimmedKey)
            let fileURL = dir.appendingPathComponent(
                CraftImageAssetKey.recordName(for: normalizedKey),
                isDirectory: false
            )
            do {
                try data.write(to: fileURL, options: .atomic)
                storedCount += 1
            } catch {
                continue
            }
        }

        imageCache.removeAllObjects()
        storageGeneration += 1
        objectWillChange.send()
        return storedCount
    }

    func removeVersionIcons(for version: String) {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else { return }
        let dir = versionDirectory(for: trimmedVersion)
        if fileManager.fileExists(atPath: dir.path) {
            try? fileManager.removeItem(at: dir)
        }
        imageCache.removeAllObjects()
        objectWillChange.send()
    }

    // MARK: - Image Lookup

    func image(for assetKey: String, version: String? = nil) -> UIImage? {
        let trimmedKey = assetKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }

        let resolvedVersion = (version ?? activeVersion).trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = CraftImageAssetKey.normalizedAssetKey(trimmedKey)
        let cacheKey = "\(resolvedVersion)::\(normalizedKey)" as NSString

        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        // 1. Look up in the active version's isolated icon package first
        if !resolvedVersion.isEmpty {
            let verDir = versionDirectory(for: resolvedVersion)
            let normalizedFile = verDir.appendingPathComponent(
                CraftImageAssetKey.recordName(for: normalizedKey),
                isDirectory: false
            )
            if let image = UIImage(contentsOfFile: normalizedFile.path) {
                imageCache.setObject(image, forKey: cacheKey)
                return image
            }

            let exactFile = verDir.appendingPathComponent(
                CraftImageAssetKey.recordName(for: trimmedKey),
                isDirectory: false
            )
            if let image = UIImage(contentsOfFile: exactFile.path) {
                imageCache.setObject(image, forKey: cacheKey)
                return image
            }
        }

        // 2. Fallback to persistent downloaded image directory
        if let image = UIImage(contentsOfFile: cachedFileURL(for: trimmedKey).path) {
            imageCache.setObject(image, forKey: cacheKey)
            return image
        }

        // 3. Fallback to bundled Assets.xcassets
        if let bundled = UIImage(named: trimmedKey) {
            imageCache.setObject(bundled, forKey: cacheKey)
            return bundled
        }

        return nil
    }

    func prefetch(recipes: [Recipe]) {
        let keys = Self.imageKeys(in: recipes)
        let generation = storageGeneration
        Task { [weak self] in
            await self?.synchronize(keys: keys, generation: generation)
        }
    }

    func load(_ assetKey: String) async {
        let trimmed = assetKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let generation = storageGeneration
        await synchronize(keys: [assetKey], generation: generation)
    }

    func refresh(recipes: [Recipe]) async {
        let generation = storageGeneration
        await synchronize(
            keys: Self.imageKeys(in: recipes),
            force: true,
            generation: generation
        )
    }

    func prepare(
        recipes: [Recipe],
        progress: @escaping (Int, Int) -> Void
    ) async -> Bool {
        let generation = storageGeneration
        return await synchronize(
            keys: Self.imageKeys(in: recipes),
            force: true,
            generation: generation,
            stopOnFailure: true,
            progress: progress
        )
    }

    static func imageKeys(in recipes: [Recipe]) -> Set<String> {
        var keys: Set<String> = []

        func insert(_ value: String?) {
            guard let value,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            keys.insert(value)
        }

        for recipe in recipes {
            insert(recipe.image)
            insert(recipe.imageremark)
            for utility in recipe.craftingUtilities {
                insert(utility)
            }
            for ing in recipe.allIngredientNames {
                insert(ing)
            }
        }

        return keys
    }

    @discardableResult
    private func synchronize(
        keys: Set<String>,
        force: Bool = false,
        generation: Int,
        stopOnFailure: Bool = false,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> Bool {
        guard generation == storageGeneration else { return false }

        let usableKeys = Set(keys.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        let now = Date()
        let dueKeys = usableKeys.filter { key in
            guard !loadingKeys.contains(key) else { return false }
            if force { return true }
            guard let checked = lastChecked[key] else { return true }
            return now.timeIntervalSince(checked) >= refreshInterval
        }

        let total = usableKeys.count
        var prepared = total - dueKeys.count
        progress?(prepared, total)

        guard !dueKeys.isEmpty else { return true }

        let requestedKeys = Set(dueKeys)
        loadingKeys.formUnion(requestedKeys)
        defer { loadingKeys.subtract(requestedKeys) }

        var allSucceeded = true
        let sortedKeys = requestedKeys.sorted()
        for start in stride(from: 0, to: sortedKeys.count, by: queryBatchSize) {
            guard generation == storageGeneration else { return false }
            let end = min(start + queryBatchSize, sortedKeys.count)
            let batch = Array(sortedKeys[start..<end])
            let batchSucceeded = await synchronize(
                batch: batch,
                generation: generation
            )
            guard generation == storageGeneration else { return false }

            if !batchSucceeded {
                allSucceeded = false
                if stopOnFailure { return false }
            } else {
                prepared += batch.count
                progress?(prepared, total)
            }
        }
        return allSucceeded
    }

    private func synchronize(batch: [String], generation: Int) async -> Bool {
        guard generation == storageGeneration else { return false }
        let checkedAt = Date()
        batch.forEach { lastChecked[$0] = checkedAt }
        return true
    }

    private func cachedFileURL(for assetKey: String) -> URL {
        imageDirectory.appendingPathComponent(
            CraftImageAssetKey.recordName(for: assetKey),
            isDirectory: false
        )
    }

    private func localVersion(for assetKey: String) -> Int64 {
        Int64(defaults.integer(forKey: versionDefaultsKey(for: assetKey)))
    }

    private func versionDefaultsKey(for assetKey: String) -> String {
        Self.versionDefaultsPrefix + CraftImageAssetKey.recordName(for: assetKey)
    }

    func clearDownloadedImages() throws {
        storageGeneration += 1
        loadingKeys.removeAll()
        lastChecked.removeAll()
        imageCache.removeAllObjects()

        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.versionDefaultsPrefix) }
            .forEach { defaults.removeObject(forKey: $0) }

        objectWillChange.send()
        defer { try? createImageDirectory() }

        if fileManager.fileExists(atPath: imageDirectory.path) {
            try fileManager.removeItem(at: imageDirectory)
        }
        if legacyCacheDirectory != imageDirectory,
           fileManager.fileExists(atPath: legacyCacheDirectory.path) {
            try fileManager.removeItem(at: legacyCacheDirectory)
        }

        try createImageDirectory()
        objectWillChange.send()
    }

    private func prepareStorage() {
        do {
            try createImageDirectory()
            try createVersionIconsRootDirectory()
            migrateLegacyImagesIfNeeded()
        } catch {
            print("Unable to prepare persistent image storage: \(error.localizedDescription)")
        }
    }

    private func createImageDirectory() throws {
        try fileManager.createDirectory(
            at: imageDirectory,
            withIntermediateDirectories: true
        )

        var directoryURL = imageDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        do {
            try directoryURL.setResourceValues(resourceValues)
        } catch {
            print("Unable to exclude downloaded images from backup: \(error.localizedDescription)")
        }
    }

    private func createVersionIconsRootDirectory() throws {
        try fileManager.createDirectory(
            at: versionIconsRootDirectory,
            withIntermediateDirectories: true
        )

        var directoryURL = versionIconsRootDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? directoryURL.setResourceValues(resourceValues)
    }

    private func migrateLegacyImagesIfNeeded() {
        guard legacyCacheDirectory != imageDirectory,
              fileManager.fileExists(atPath: legacyCacheDirectory.path),
              let legacyFiles = try? fileManager.contentsOfDirectory(
                at: legacyCacheDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for sourceURL in legacyFiles {
            let destinationURL = imageDirectory.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: false
            )

            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: sourceURL)
                } else {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                print(
                    "Unable to migrate downloaded image \(sourceURL.lastPathComponent): "
                    + error.localizedDescription
                )
            }
        }

        if let remainingFiles = try? fileManager.contentsOfDirectory(
            at: legacyCacheDirectory,
            includingPropertiesForKeys: nil
        ), remainingFiles.isEmpty {
            try? fileManager.removeItem(at: legacyCacheDirectory)
        }
    }

    private func removeCachedRemoteImage(for assetKey: String) {
        try? fileManager.removeItem(at: cachedFileURL(for: assetKey))
        imageCache.removeAllObjects()
        defaults.removeObject(forKey: versionDefaultsKey(for: assetKey))
    }
}


@MainActor
struct CraftImage: View, Equatable {
    @ObservedObject private var store: CraftImageStore
    let key: String
    let fallbackSystemName: String

    nonisolated static func == (lhs: CraftImage, rhs: CraftImage) -> Bool {
        lhs.key == rhs.key && lhs.fallbackSystemName == rhs.fallbackSystemName
    }

    init(
        key: String,
        fallbackSystemName: String = "photo",
        store: CraftImageStore = .shared
    ) {
        self.key = key
        self.fallbackSystemName = fallbackSystemName
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        if let image = store.image(for: key, version: store.activeVersion) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
        } else {
            Image(systemName: fallbackSystemName)
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}
