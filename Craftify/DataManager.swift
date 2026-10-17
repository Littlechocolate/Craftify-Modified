//
//  DataManager.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//

import Foundation
import Combine
import UIKit
import Network

protocol KeyValueStore: AnyObject {
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
    func object(forKey defaultName: String) -> Any?
    func data(forKey defaultName: String) -> Data?
    func array(forKey defaultName: String) -> [Any]?
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStore {}

@MainActor
final class DataManager: ObservableObject {
    enum RecipeBookLoadingPhase: Equatable {
        case idle
        case downloadingRecipes(downloaded: Int, total: Int?)
        case preparingImages(prepared: Int, total: Int, recipeTotal: Int)
    }

    struct NewRecipeAnnouncement: Identifiable, Equatable {
        let id = UUID()
        let recipes: [Recipe]

        var recipeCount: Int {
            recipes.count
        }
    }

    @Published var recipes: [Recipe] = []
    @Published private(set) var chests: [RecipeChest] = []
    @Published var recentSearchNames: [String] = []
    @Published var selectedCategory: String? = nil
    @Published var lastUpdated: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var cacheClearedMessage: String? = nil
    @Published var isLoading: Bool = false
    @Published var isManualSyncing: Bool = false
    @Published var accessibilityAnnouncement: String? = nil
    @Published var searchText: String = ""
    @Published var lastReportStatusFetchTime: Date?
    @Published var lastRecipeFetch: Date?
    @Published var isConnected: Bool = true
    @Published var consoleCommands: [ConsoleCommand] = []
    @Published private(set) var recipeBookLoadingPhase: RecipeBookLoadingPhase = .idle
    @Published private(set) var newRecipeAnnouncement: NewRecipeAnnouncement?

    private let iCloudFavoritesKey = "favoriteRecipes"
    private let iCloudChestsKey = "recipeChests.v1"
    private let iCloudRecentSearchesKey = "recentSearches"
    private var cancellables = Set<AnyCancellable>()
    private let reportStatusFetchInterval: TimeInterval = 30
    private let recipeFetchInterval: TimeInterval = 30
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    private let keyValueStore: any KeyValueStore
    private let imageStore: CraftImageStore
    private let defaults: UserDefaults
    private var recipeFetchGeneration = 0
    private var shouldPersistRecipeBookLoadingError = false

    private static let catalogRecordName = "craftify-catalog-current"
    private static let catalogRecipeCountField = "recipeCount"
    private static let knownRecipeIDsDefaultsKey = "knownRecipeIDs.v1"

    enum ErrorType: String {
        case network = "Network issue, please try again later."
        case permissions = "Permission denied, please enable iCloud access."
        case dataCorruption = "Data error, please try refreshing."
        case userIdentification = "Unable to identify user. Please ensure iCloud is enabled."
        case missingFields = "Report data is incomplete or corrupted."
        case unknown = "An unexpected error occurred. Please try again later."
    }

    init(
        keyValueStore: any KeyValueStore = NSUbiquitousKeyValueStore.default,
        imageStore: CraftImageStore = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.keyValueStore = keyValueStore
        self.imageStore = imageStore
        self.defaults = defaults
        keyValueStore.synchronize()

        setupNetworkMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(icloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: keyValueStore
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        $errorMessage
            .sink { [weak self] message in
                if message != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        guard self?.shouldPersistRecipeBookLoadingError != true else {
                            return
                        }
                        self?.errorMessage = nil
                    }
                }
            }
            .store(in: &cancellables)

        $cacheClearedMessage
            .sink { [weak self] message in
                if let message = message {
                    self?.accessibilityAnnouncement = message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self?.cacheClearedMessage = nil
                        self?.accessibilityAnnouncement = nil
                    }
                }
            }
            .store(in: &cancellables)

        reloadRecipesFromActiveVersion()

        RecipeVersionManager.shared.$activeVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadRecipesFromActiveVersion()
            }
            .store(in: &cancellables)

        fetchConsoleCommands()
        syncChests()
    }

    func reloadRecipesFromActiveVersion() {
        let loaded = RecipeVersionManager.shared.loadActiveRecipes()
        if !loaded.isEmpty {
            self.recipes = Recipe.mergedByItemName(loaded)
            self.lastUpdated = Date()
            self.syncRecentSearches()
            self.seedKnownRecipeIDsIfNeeded(from: self.recipes)
            self.imageStore.prefetch(recipes: self.recipes)
        } else if let cached = loadRecipesFromLocalCache(), !cached.isEmpty {
            self.recipes = Recipe.mergedByItemName(cached)
            self.lastUpdated = Date()
            self.syncRecentSearches()
            self.seedKnownRecipeIDsIfNeeded(from: self.recipes)
            self.imageStore.prefetch(recipes: self.recipes)
        }
    }

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = satisfied
                if !satisfied {
                    self.errorMessage = "No internet connection. Try again later."
                    self.accessibilityAnnouncement = self.errorMessage
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        networkMonitor.cancel()
    }

    @objc nonisolated private func appWillEnterForeground() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            keyValueStore.synchronize()
            syncChests()
            syncRecentSearches()
        }
    }

    var syncStatus: String {
        let active = RecipeVersionManager.shared.activeVersion
        if let info = RecipeVersionManager.shared.installedVersions.first(where: { $0.version == active }) {
            return "Active Version: Minecraft \(info.version) (\(info.recipeCount.formatted()) recipes)"
        } else if !recipes.isEmpty {
            return "\(recipes.count.formatted()) recipes available offline"
        } else {
            return "No recipe version active"
        }
    }

    func clearChestsAndLegacyFavorites() {
        chests = []
        // Preserve an explicit empty value so older clients observe the clear and
        // cannot upload favorites they still hold in memory.
        keyValueStore.set([Int](), forKey: iCloudFavoritesKey)
        keyValueStore.removeObject(forKey: iCloudChestsKey)
        keyValueStore.synchronize()
        print("Cleared chests and legacy favorites")
    }

    func createChest(name: String, size: RecipeChest.Size, symbol: String? = nil, adding recipe: Recipe? = nil) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipeIDs = recipe.map { [$0.id] } ?? []
        chests.append(RecipeChest(name: cleanedName.isEmpty ? "New Chest" : cleanedName, size: size, symbol: symbol, recipeIDs: recipeIDs))
        saveChests()
    }

    @discardableResult
    func updateChest(
        _ chest: RecipeChest,
        name: String,
        size: RecipeChest.Size,
        symbol: String?,
        removingOverflow: Bool = false
    ) -> Bool {
        guard let index = chests.firstIndex(where: { $0.id == chest.id }) else { return false }
        let overflowCount = max(0, chests[index].recipeIDs.count - size.rawValue)
        guard overflowCount == 0 || removingOverflow else { return false }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        chests[index].name = cleanedName.isEmpty ? chest.name : cleanedName
        chests[index].size = size
        chests[index].symbol = symbol
        if overflowCount > 0 {
            chests[index].recipeIDs.removeLast(overflowCount)
        }
        saveChests()
        return true
    }

    @discardableResult
    func add(_ recipe: Recipe, to chest: RecipeChest) -> Bool {
        guard let index = chests.firstIndex(where: { $0.id == chest.id }),
              !chests[index].recipeIDs.contains(recipe.id),
              chests[index].recipeIDs.count < chests[index].size.rawValue else { return false }
        chests[index].recipeIDs.append(recipe.id)
        saveChests()
        return true
    }

    func removeRecipes(withIDs recipeIDs: Set<Int>, from chestID: UUID) {
        guard let index = chests.firstIndex(where: { $0.id == chestID }) else { return }
        chests[index].recipeIDs.removeAll { recipeIDs.contains($0) }
        saveChests()
    }

    func deleteChests(at offsets: IndexSet) {
        chests.remove(atOffsets: offsets)
        saveChests()
    }

    func moveChests(from source: IndexSet, to destination: Int) {
        chests.move(fromOffsets: source, toOffset: destination)
        saveChests()
    }

    func recipes(in chest: RecipeChest) -> [Recipe] {
        chest.recipeIDs.compactMap { id in recipes.first { $0.id == id } }
    }

    func syncChests() {
        if let data = keyValueStore.data(forKey: iCloudChestsKey),
           let decoded = try? JSONDecoder().decode([RecipeChest].self, from: data) {
            chests = decoded
        }
    }

    private func saveChests() {
        guard let data = try? JSONEncoder().encode(chests) else { return }
        keyValueStore.set(data, forKey: iCloudChestsKey)
        keyValueStore.synchronize()
    }

    func saveRecentSearch(_ recipe: Recipe) {
        recentSearchNames.removeAll { $0 == recipe.name }
        recentSearchNames.insert(recipe.name, at: 0)
        recentSearchNames = Array(recentSearchNames.prefix(10))
        print("Updated recent search names: \(recentSearchNames)")

        keyValueStore.set(recentSearchNames, forKey: iCloudRecentSearchesKey)
        keyValueStore.synchronize()
    }

    func clearRecentSearches() {
        recentSearchNames = []
        keyValueStore.set(recentSearchNames, forKey: iCloudRecentSearchesKey)
        keyValueStore.synchronize()
        print("Cleared recent search names: \(recentSearchNames)")
    }

    func syncRecentSearches() {
        if let savedNames = keyValueStore.array(forKey: iCloudRecentSearchesKey) as? [String] {
            recentSearchNames = Array(savedNames.prefix(10)).filter { name in
                recipes.contains { $0.name == name }
            }
        }
    }

    @objc nonisolated private func icloudDidChange() {
        // iCloud posts this notification on the queue where the change arrives,
        // which is not guaranteed to be the main queue. Hop to the main actor
        // before reading iCloud values or updating observable state.
        Task { @MainActor [weak self] in
            self?.syncChests()
            self?.syncRecentSearches()
        }
    }

    func fetchRecipes(
        isManual: Bool = false,
        waitForImages: Bool = false,
        completion: @escaping () -> Void = {}
    ) {
        shouldPersistRecipeBookLoadingError = false
        isLoading = true
        if isManual { isManualSyncing = true }

        reloadRecipesFromActiveVersion()
        lastUpdated = Date()
        lastRecipeFetch = Date()
        isLoading = false
        isManualSyncing = false
        completion()
    }

    func loadData(
        isManual: Bool = false,
        waitForImages: Bool = false,
        completion: @escaping () -> Void
    ) {
        fetchRecipes(isManual: isManual, waitForImages: waitForImages, completion: completion)
    }

    func loadDataAsync(isManual: Bool = false, waitForImages: Bool = false) async {
        fetchRecipes(isManual: isManual, waitForImages: waitForImages)
    }

    func dismissNewRecipeAnnouncement() {
        newRecipeAnnouncement = nil
    }

    private func seedKnownRecipeIDsIfNeeded(from recipes: [Recipe]) {
        guard storedKnownRecipeIDs() == nil else { return }
        saveKnownRecipeIDs(Set(recipes.map(\.id)))
    }

    private func recordSuccessfulRecipeLibrary(_ recipes: [Recipe]) {
        let fetchedIDs = Set(recipes.map(\.id))
        defer { saveKnownRecipeIDs(fetchedIDs) }

        guard let knownIDs = storedKnownRecipeIDs() else { return }
        let addedRecipes = Self.newlyAddedRecipes(
            in: recipes,
            comparedTo: knownIDs
        )
        guard !addedRecipes.isEmpty else { return }

        newRecipeAnnouncement = NewRecipeAnnouncement(recipes: addedRecipes)
    }

    static func newlyAddedRecipes(
        in recipes: [Recipe],
        comparedTo knownIDs: Set<Int>
    ) -> [Recipe] {
        let addedIDs = Set(recipes.map(\.id)).subtracting(knownIDs)
        return recipes
            .filter { addedIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    private func storedKnownRecipeIDs() -> Set<Int>? {
        guard let data = defaults.data(forKey: Self.knownRecipeIDsDefaultsKey),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else {
            return nil
        }
        return Set(ids)
    }

    private func saveKnownRecipeIDs(_ ids: Set<Int>) {
        do {
            let data = try JSONEncoder().encode(ids.sorted())
            defaults.set(data, forKey: Self.knownRecipeIDsDefaultsKey)
        } catch {
            print("Could not save known recipe IDs: \(error.localizedDescription)")
        }
    }

    func isRecipeFetchOnCooldown() -> Bool {
        if let lastFetch = lastRecipeFetch {
            return Date().timeIntervalSince(lastFetch) < recipeFetchInterval
        }
        return false
    }

    func isReportStatusFetchOnCooldown() -> Bool {
        if let lastFetch = lastReportStatusFetchTime {
            return Date().timeIntervalSince(lastFetch) < reportStatusFetchInterval
        }
        return false
    }

    private let localReportsKey = "local-recipe-reports"

    private func loadLocalReports() -> [RecipeReport] {
        guard let data = UserDefaults.standard.data(forKey: localReportsKey),
              let reports = try? JSONDecoder().decode([RecipeReport].self, from: data) else {
            return []
        }
        return reports
    }

    private func saveLocalReports(_ reports: [RecipeReport]) {
        if let data = try? JSONEncoder().encode(reports) {
            UserDefaults.standard.set(data, forKey: localReportsKey)
        }
    }

    func submitRecipeReport(
        reportType: String,
        recipeName: String,
        category: String,
        recipeID: Int?,
        description: String,
        completion: @escaping @MainActor (Result<RecipeReport, Error>) -> Void
    ) {
        let localID = UUID().uuidString
        let timestamp = Date()
        let report = RecipeReport(
            id: localID,
            recordID: localID,
            localID: localID,
            reportType: reportType,
            recipeName: recipeName,
            category: category,
            recipeID: recipeID,
            description: description,
            timestamp: timestamp,
            status: "Saved Locally"
        )
        var reports = loadLocalReports()
        reports.append(report)
        saveLocalReports(reports)
        accessibilityAnnouncement = "Report saved locally"
        completion(.success(report))
    }

    func fetchRecipeReports(
        completion: @escaping @MainActor (Result<[RecipeReport], Error>) -> Void
    ) {
        let reports = loadLocalReports()
        completion(.success(reports))
    }

    func deleteRecipeReport(
        _ report: RecipeReport,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        var reports = loadLocalReports()
        reports.removeAll { $0.id == report.id || $0.recordID == report.recordID }
        saveLocalReports(reports)
        accessibilityAnnouncement = "Report deleted"
        completion(true)
    }

    func deleteAllRecipeReports(
        reports: [RecipeReport],
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        saveLocalReports([])
        accessibilityAnnouncement = "All reports deleted"
        completion(true)
    }

    func clearCache(completion: @escaping (Bool) -> Void) {
        recipeFetchGeneration += 1
        isLoading = false
        isManualSyncing = false

        let fileURL = getCacheDirectory().appendingPathComponent(localCacheFileName())

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try imageStore.clearDownloadedImages()

            recipes = []
            newRecipeAnnouncement = nil
            lastRecipeFetch = nil
            lastUpdated = nil
            cacheClearedMessage = "Recipe and image data cleared successfully."
            accessibilityAnnouncement = cacheClearedMessage
            completion(true)
        } catch {
            errorMessage = "Failed to clear local recipe and image data: \(error.localizedDescription)"
            cacheClearedMessage = "Failed to clear cache."
            accessibilityAnnouncement = errorMessage
            completion(false)
        }
    }

    func clearAllData(completion: @escaping (Bool) -> Void) {
        clearCache { cacheSuccess in
            self.clearChestsAndLegacyFavorites()
            self.clearRecentSearches()
            self.saveLocalReports([])
            self.lastReportStatusFetchTime = nil
            self.cacheClearedMessage = "All data cleared successfully."
            self.accessibilityAnnouncement = "All data cleared successfully."
            completion(true)
        }
    }

    private func localCacheFileName() -> String {
        return "recipes.json"
    }

    private func loadRecipesFromLocalCache() -> [Recipe]? {
        let fileURL = getCacheDirectory().appendingPathComponent(localCacheFileName())
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode([Recipe].self, from: data)
    }

    private func saveRecipesToLocalCache(_ recipes: [Recipe]) {
        let fileURL = getCacheDirectory().appendingPathComponent(localCacheFileName())
        if let data = try? JSONEncoder().encode(recipes) {
            do {
                try data.write(to: fileURL)
            } catch {
                print("Error saving recipes to local cache: \(error.localizedDescription)")
            }
        }
    }

    private func getCacheDirectory() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func fetchConsoleCommands(completion: @escaping @MainActor () -> Void = {}) {
        if consoleCommands.isEmpty {
            consoleCommands = ConsoleCommand.defaultCommands.sorted { $0.name < $1.name }
        }
        completion()
    }

    var categories: [String] {
        let unique = Set(recipes.map { $0.category }).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let canonicalOrder = [
            "Building Blocks",
            "Equipment",
            "Redstone",
            "Food & Cooking",
            "Miscellaneous"
        ]
        return unique.sorted { a, b in
            let idxA = canonicalOrder.firstIndex(of: a) ?? Int.max
            let idxB = canonicalOrder.firstIndex(of: b) ?? Int.max
            if idxA != idxB {
                return idxA < idxB
            }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    static func categorySymbol(for category: String) -> String {
        switch category.lowercased() {
        case "building blocks", "building", "blocks":
            return "cube.fill"
        case "equipment", "tools", "weapons", "armor":
            return "shield.fill"
        case "redstone", "mechanisms":
            return "bolt.fill"
        case "food & cooking", "food", "cooking":
            return "flame.fill"
        case "miscellaneous", "misc":
            return "shippingbox.fill"
        default:
            return "tag.fill"
        }
    }

    var filteredRecipes: [Recipe] {
        recipes.filter { recipe in
            let matchesCategory = selectedCategory == nil || recipe.category == selectedCategory
            let matchesSearch = searchText.isEmpty || recipe.name.lowercased().contains(searchText.lowercased())
            return matchesCategory && matchesSearch
        }
    }
}
