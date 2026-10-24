//
//  Recipes.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//

import Foundation

/// A complete package of recipes for a specific Minecraft version (.recipe file format)
struct RecipePackage: Codable, Identifiable {
    var id: String { gameVersion }
    let formatVersion: Int
    let gameVersion: String
    let edition: String
    let createdAt: String?
    let generator: String?
    let recipeCount: Int
    let iconCount: Int?
    let categories: [String]?
    let recipes: [Recipe]
    /// Bundled inventory-style PNG icons (keyed by item display name, value is base64-encoded PNG data)
    let icons: [String: String]?

    init(
        formatVersion: Int,
        gameVersion: String,
        edition: String,
        createdAt: String?,
        generator: String?,
        recipeCount: Int,
        iconCount: Int? = nil,
        categories: [String]?,
        recipes: [Recipe],
        icons: [String: String]? = nil
    ) {
        self.formatVersion = formatVersion
        self.gameVersion = gameVersion
        self.edition = edition
        self.createdAt = createdAt
        self.generator = generator
        self.recipeCount = recipeCount
        self.iconCount = iconCount ?? icons?.count
        self.categories = categories
        self.recipes = recipes
        self.icons = icons
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case gameVersion = "game_version"
        case edition
        case createdAt = "created_at"
        case generator
        case recipeCount = "recipe_count"
        case iconCount = "icon_count"
        case categories
        case recipes
        case icons
    }
}

/// Metadata describing an installed recipe version
struct RecipeVersionInfo: Identifiable, Codable, Equatable, Hashable {
    var id: String { version }
    var version: String
    var displayName: String
    var edition: String
    var recipeCount: Int
    var iconCount: Int
    var categories: [String]
    var importedAt: Date
    var isDefault: Bool
    var fileName: String

    init(
        version: String,
        displayName: String,
        edition: String,
        recipeCount: Int,
        iconCount: Int = 0,
        categories: [String],
        importedAt: Date,
        isDefault: Bool,
        fileName: String
    ) {
        self.version = version
        self.displayName = displayName
        self.edition = edition
        self.recipeCount = recipeCount
        self.iconCount = iconCount
        self.categories = categories
        self.importedAt = importedAt
        self.isDefault = isDefault
        self.fileName = fileName
    }

    enum CodingKeys: String, CodingKey {
        case version, displayName, edition, recipeCount, iconCount, categories, importedAt, isDefault, fileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(String.self, forKey: .version)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.edition = try container.decode(String.self, forKey: .edition)
        self.recipeCount = try container.decode(Int.self, forKey: .recipeCount)
        self.iconCount = try container.decodeIfPresent(Int.self, forKey: .iconCount) ?? 0
        self.categories = try container.decode([String].self, forKey: .categories)
        self.importedAt = try container.decode(Date.self, forKey: .importedAt)
        self.isDefault = try container.decode(Bool.self, forKey: .isDefault)
        self.fileName = try container.decode(String.self, forKey: .fileName)
    }

    var subtitle: String {
        if iconCount > 0 {
            return "\(edition) • \(recipeCount.formatted()) recipes • \(iconCount.formatted()) icons"
        }
        return "\(edition) • \(recipeCount.formatted()) recipes"
    }
}

/// User choice when importing a recipe file with a duplicate version number
enum DuplicateResolution: String, CaseIterable, Identifiable {
    case replace = "replace"
    case keepBoth = "keep_both"
    case cancel = "cancel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .replace: return "Replace"
        case .keepBoth: return "Keep Both"
        case .cancel: return "Cancel"
        }
    }

    var localizedTitle: String {
        switch self {
        case .replace: return "替换现有版本"
        case .keepBoth: return "同时保留两个版本"
        case .cancel: return "取消导入"
        }
    }
}

/// Detailed cooking and smelting station metrics for distinguishing furnace types
struct CookingStationInfo: Identifiable, Codable, Equatable, Hashable {
    var id: String { station }
    let station: String            // "Furnace", "Blast Furnace", "Smoker", "Campfire"
    let displayName: String        // "Furnace", "Blast Furnace", "Smoker", "Campfire"
    let ticks: Int                 // e.g. 200, 100, 600
    let seconds: Double            // e.g. 10.0, 5.0, 30.0
    let speedMultiplier: Double    // 1.0, 2.0, 0.33
    let speedBadge: String         // "1× Speed", "2× Speed", "No Fuel Needed"
    let fuelDescription: String    // "Requires standard furnace fuel", "Consumes fuel 2× faster", "No fuel required"
    let stationDescription: String // Helper text
    let xp: Double?                // e.g. 0.7, 0.35

    init(
        station: String,
        baseTicks: Int = 200,
        xp: Double? = nil
    ) {
        self.station = station
        self.displayName = station
        self.xp = xp

        switch station {
        case "Blast Furnace":
            let actualTicks = max(1, baseTicks / 2)
            self.ticks = actualTicks
            self.seconds = Double(actualTicks) / 20.0
            self.speedMultiplier = 2.0
            self.speedBadge = "2× Speed"
            self.fuelDescription = "Consumes fuel 2× faster"
            self.stationDescription = "Smelts ores, raw metals, and metallic gear at double speed."

        case "Smoker":
            let actualTicks = max(1, baseTicks / 2)
            self.ticks = actualTicks
            self.seconds = Double(actualTicks) / 20.0
            self.speedMultiplier = 2.0
            self.speedBadge = "2× Speed"
            self.fuelDescription = "Consumes fuel 2× faster"
            self.stationDescription = "Cooks food items at double speed."

        case "Campfire":
            let actualTicks = 600
            self.ticks = actualTicks
            self.seconds = Double(actualTicks) / 20.0
            self.speedMultiplier = 1.0 / 3.0
            self.speedBadge = "No Fuel Needed"
            self.fuelDescription = "Infinite cooking without fuel"
            self.stationDescription = "Cooks up to 4 food items simultaneously over an open flame without fuel."

        default: // "Furnace"
            self.ticks = baseTicks
            self.seconds = Double(baseTicks) / 20.0
            self.speedMultiplier = 1.0
            self.speedBadge = "Standard Speed"
            self.fuelDescription = "Requires standard furnace fuel"
            self.stationDescription = "Versatile smelting and cooking for ores, blocks, and food."
        }
    }
}

struct CraftingVariant: Codable, Equatable, Hashable {
    let ingredients: [String]
    let output: Int
    let imageremark: String?
    let remarks: String?
    let stations: [String]?

    init(
        ingredients: [String],
        output: Int,
        imageremark: String?,
        remarks: String?,
        stations: [String]? = nil
    ) {
        self.ingredients = ingredients
        self.output = output
        self.imageremark = imageremark
        self.remarks = remarks
        self.stations = stations
    }

    enum CodingKeys: String, CodingKey {
        case ingredients, output, imageremark, remarks, stations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ingredients = try container.decode([String].self, forKey: .ingredients)
        self.output = try container.decode(Int.self, forKey: .output)
        self.imageremark = try container.decodeIfPresent(String.self, forKey: .imageremark)
        self.remarks = try container.decodeIfPresent(String.self, forKey: .remarks)
        self.stations = try container.decodeIfPresent([String].self, forKey: .stations)
    }

    var resolvedStations: [String] {
        if let stations, !stations.isEmpty {
            return stations
        }
        if let st = imageremark?.trimmingCharacters(in: .whitespacesAndNewlines), !st.isEmpty {
            return [st]
        }
        return []
    }

    var isCookingLayout: Bool {
        let cookingSet: Set<String> = ["Furnace", "Blast Furnace", "Smoker", "Campfire"]
        if let imageremark, cookingSet.contains(imageremark) {
            return true
        }
        for st in resolvedStations {
            if cookingSet.contains(st) {
                return true
            }
        }
        return false
    }

    var normalizedIngredients: [String] {
        let maximum = isCookingLayout ? 2 : 9
        if ingredients.count < maximum {
            return ingredients + Array(repeating: "", count: maximum - ingredients.count)
        }
        return Array(ingredients.prefix(maximum))
    }

    var parsedXP: Double? {
        guard let remarks else { return nil }
        if let match = remarks.range(of: #"XP:\s*([\d\.]+)"#, options: .regularExpression) {
            let str = remarks[match].replacingOccurrences(of: "XP:", with: "").trimmingCharacters(in: .whitespaces)
            return Double(str)
        }
        return nil
    }

    var parsedBaseTicks: Int {
        guard let remarks else { return 200 }
        if let match = remarks.range(of: #"Cooking Time:\s*(\d+)\s*ticks"#, options: .regularExpression) {
            let digits = remarks[match].filter { $0.isNumber }
            if let val = Int(digits), val > 0 {
                if val == 600 { return 200 }
                return val
            }
        }
        return 200
    }

    var cookingStationInfos: [CookingStationInfo] {
        guard isCookingLayout else { return [] }
        let baseTicks = parsedBaseTicks
        let xp = parsedXP
        var list = resolvedStations.filter {
            ["Furnace", "Blast Furnace", "Smoker", "Campfire"].contains($0)
        }
        if list.isEmpty, let imageremark, ["Furnace", "Blast Furnace", "Smoker", "Campfire"].contains(imageremark) {
            list = [imageremark]
        }
        list.sort { (Recipe.stationPriority[$0] ?? 99) < (Recipe.stationPriority[$1] ?? 99) }
        return list.map {
            CookingStationInfo(station: $0, baseTicks: baseTicks, xp: $0 == "Campfire" ? nil : xp)
        }
    }
}

struct Recipe: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let image: String
    let ingredients: [String]
    let alternateIngredients: [String]?
    let alternateIngredients1: [String]?
    let alternateIngredients2: [String]?
    let alternateIngredients3: [String]?
    let output: Int
    let alternateOutput: Int?
    let alternateOutput1: Int?
    let alternateOutput2: Int?
    let alternateOutput3: Int?
    let category: String
    let imageremark: String?
    let remarks: String?
    let variants: [CraftingVariant]?

    let resolvedVariants: [CraftingVariant]
    let craftingUtilities: [String]
    let allIngredientNames: [String]

    init(
        id: Int,
        name: String,
        image: String,
        ingredients: [String],
        alternateIngredients: [String]? = nil,
        alternateIngredients1: [String]? = nil,
        alternateIngredients2: [String]? = nil,
        alternateIngredients3: [String]? = nil,
        output: Int,
        alternateOutput: Int? = nil,
        alternateOutput1: Int? = nil,
        alternateOutput2: Int? = nil,
        alternateOutput3: Int? = nil,
        category: String,
        imageremark: String? = nil,
        remarks: String? = nil,
        variants: [CraftingVariant]? = nil
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.ingredients = ingredients
        self.alternateIngredients = alternateIngredients
        self.alternateIngredients1 = alternateIngredients1
        self.alternateIngredients2 = alternateIngredients2
        self.alternateIngredients3 = alternateIngredients3
        self.output = output
        self.alternateOutput = alternateOutput
        self.alternateOutput1 = alternateOutput1
        self.alternateOutput2 = alternateOutput2
        self.alternateOutput3 = alternateOutput3
        self.category = category
        self.imageremark = imageremark
        self.remarks = remarks
        self.variants = variants

        let resolved = Self.computeResolvedVariants(
            ingredients: ingredients,
            output: output,
            imageremark: imageremark,
            remarks: remarks,
            alternateIngredients: alternateIngredients,
            alternateOutput: alternateOutput,
            alternateIngredients1: alternateIngredients1,
            alternateOutput1: alternateOutput1,
            alternateIngredients2: alternateIngredients2,
            alternateOutput2: alternateOutput2,
            alternateIngredients3: alternateIngredients3,
            alternateOutput3: alternateOutput3,
            variants: variants
        )
        self.resolvedVariants = resolved
        self.craftingUtilities = Self.computeCraftingUtilities(from: resolved, fallbackImageremark: imageremark)
        self.allIngredientNames = Self.computeAllIngredientNames(from: resolved)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let image = try container.decode(String.self, forKey: .image)
        let ingredients = try container.decode([String].self, forKey: .ingredients)
        let alternateIngredients = try container.decodeIfPresent([String].self, forKey: .alternateIngredients)
        let alternateIngredients1 = try container.decodeIfPresent([String].self, forKey: .alternateIngredients1)
        let alternateIngredients2 = try container.decodeIfPresent([String].self, forKey: .alternateIngredients2)
        let alternateIngredients3 = try container.decodeIfPresent([String].self, forKey: .alternateIngredients3)
        let output = try container.decode(Int.self, forKey: .output)
        let alternateOutput = try container.decodeIfPresent(Int.self, forKey: .alternateOutput)
        let alternateOutput1 = try container.decodeIfPresent(Int.self, forKey: .alternateOutput1)
        let alternateOutput2 = try container.decodeIfPresent(Int.self, forKey: .alternateOutput2)
        let alternateOutput3 = try container.decodeIfPresent(Int.self, forKey: .alternateOutput3)
        let category = try container.decode(String.self, forKey: .category)
        let imageremark = try container.decodeIfPresent(String.self, forKey: .imageremark)
        let remarks = try container.decodeIfPresent(String.self, forKey: .remarks)
        let variants = try container.decodeIfPresent([CraftingVariant].self, forKey: .variants)

        self.init(
            id: id,
            name: name,
            image: image,
            ingredients: ingredients,
            alternateIngredients: alternateIngredients,
            alternateIngredients1: alternateIngredients1,
            alternateIngredients2: alternateIngredients2,
            alternateIngredients3: alternateIngredients3,
            output: output,
            alternateOutput: alternateOutput,
            alternateOutput1: alternateOutput1,
            alternateOutput2: alternateOutput2,
            alternateOutput3: alternateOutput3,
            category: category,
            imageremark: imageremark,
            remarks: remarks,
            variants: variants
        )
    }

    static func == (lhs: Recipe, rhs: Recipe) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.category == rhs.category
            && lhs.variants?.count == rhs.variants?.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, image, ingredients
        case alternateIngredients,
             alternateIngredients1,
             alternateIngredients2,
             alternateIngredients3
        case output,
             alternateOutput,
             alternateOutput1,
             alternateOutput2,
             alternateOutput3
        case category, imageremark, remarks, variants
    }

    static let stationPriority: [String: Int] = [
        "Crafting Table": 0,
        "Stonecutter": 1,
        "Smithing Table": 2,
        "Furnace": 3,
        "Blast Furnace": 4,
        "Smoker": 5,
        "Campfire": 6
    ]

    static func mergeCookingVariants(_ variants: [CraftingVariant]) -> [CraftingVariant] {
        var nonCooking: [CraftingVariant] = []
        var cookingMap: [String: (variant: CraftingVariant, stations: [String], remarks: String?)] = [:]
        var cookingOrder: [String] = []

        for v in variants {
            if v.isCookingLayout {
                let key = v.normalizedIngredients.prefix(2).joined(separator: "|") + "@\(v.output)"
                if var entry = cookingMap[key] {
                    for st in v.resolvedStations {
                        if !entry.stations.contains(st) {
                            entry.stations.append(st)
                        }
                    }
                    entry.stations.sort { (stationPriority[$0] ?? 99) < (stationPriority[$1] ?? 99) }
                    if entry.remarks == nil || entry.remarks?.isEmpty == true {
                        entry.remarks = v.remarks
                    }
                    cookingMap[key] = entry
                } else {
                    var initialStations = v.resolvedStations
                    if initialStations.isEmpty, let st = v.imageremark {
                        initialStations = [st]
                    }
                    initialStations.sort { (stationPriority[$0] ?? 99) < (stationPriority[$1] ?? 99) }
                    cookingMap[key] = (variant: v, stations: initialStations, remarks: v.remarks)
                    cookingOrder.append(key)
                }
            } else {
                if !nonCooking.contains(v) {
                    nonCooking.append(v)
                }
            }
        }

        var result = nonCooking
        for key in cookingOrder {
            if let entry = cookingMap[key] {
                let primaryStation = entry.stations.first ?? entry.variant.imageremark ?? "Furnace"
                let merged = CraftingVariant(
                    ingredients: entry.variant.ingredients,
                    output: entry.variant.output,
                    imageremark: primaryStation,
                    remarks: entry.remarks ?? entry.variant.remarks,
                    stations: entry.stations
                )
                result.append(merged)
            }
        }
        return result
    }

    private static func computeResolvedVariants(
        ingredients: [String],
        output: Int,
        imageremark: String?,
        remarks: String?,
        alternateIngredients: [String]?,
        alternateOutput: Int?,
        alternateIngredients1: [String]?,
        alternateOutput1: Int?,
        alternateIngredients2: [String]?,
        alternateOutput2: Int?,
        alternateIngredients3: [String]?,
        alternateOutput3: Int?,
        variants: [CraftingVariant]?
    ) -> [CraftingVariant] {
        let baseList: [CraftingVariant]
        if let variants, !variants.isEmpty {
            baseList = variants
        } else {
            var list: [CraftingVariant] = [
                CraftingVariant(
                    ingredients: ingredients,
                    output: output,
                    imageremark: imageremark,
                    remarks: remarks
                )
            ]
            let altPairs: [([String]?, Int?)] = [
                (alternateIngredients, alternateOutput),
                (alternateIngredients1, alternateOutput1),
                (alternateIngredients2, alternateOutput2),
                (alternateIngredients3, alternateOutput3)
            ]
            for (altIngs, altOut) in altPairs {
                if let altIngs, !altIngs.isEmpty {
                    list.append(
                        CraftingVariant(
                            ingredients: altIngs,
                            output: altOut ?? output,
                            imageremark: imageremark,
                            remarks: remarks
                        )
                    )
                }
            }
            baseList = list
        }

        return Self.mergeCookingVariants(baseList)
    }

    private static func computeCraftingUtilities(
        from resolvedVariants: [CraftingVariant],
        fallbackImageremark: String?
    ) -> [String] {
        var seen = Set<String>()
        var utilities: [String] = []
        for variant in resolvedVariants {
            for station in variant.resolvedStations {
                let trimmed = station.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !seen.contains(trimmed) {
                    seen.insert(trimmed)
                    utilities.append(trimmed)
                }
            }
        }
        if utilities.isEmpty,
           let fallback = fallbackImageremark?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            utilities.append(fallback)
        }
        return utilities.sorted {
            (Self.stationPriority[$0] ?? 99) < (Self.stationPriority[$1] ?? 99)
        }
    }

    private static func computeAllIngredientNames(from resolvedVariants: [CraftingVariant]) -> [String] {
        var result: [String] = []
        for variant in resolvedVariants {
            for ing in variant.ingredients where !ing.isEmpty {
                result.append(ing)
            }
        }
        return result
    }

    static func mergedByItemName(_ recipes: [Recipe]) -> [Recipe] {
        var grouped: [String: [Recipe]] = [:]
        for recipe in recipes {
            grouped[recipe.name, default: []].append(recipe)
        }

        var mergedList: [Recipe] = []
        let sortedNames = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        for (index, itemName) in sortedNames.enumerated() {
            guard let group = grouped[itemName], !group.isEmpty else { continue }
            if group.count == 1, let single = group.first, single.variants != nil {
                let mergedVariants = mergeCookingVariants(single.resolvedVariants)
                let firstVar = mergedVariants.first ?? CraftingVariant(
                    ingredients: single.ingredients,
                    output: single.output,
                    imageremark: single.imageremark,
                    remarks: single.remarks
                )
                mergedList.append(
                    Recipe(
                        id: single.id,
                        name: single.name,
                        image: single.image,
                        ingredients: firstVar.ingredients,
                        output: firstVar.output,
                        category: single.category,
                        imageremark: firstVar.imageremark,
                        remarks: firstVar.remarks,
                        variants: mergedVariants
                    )
                )
                continue
            }

            let sortedGroup = group.sorted { a, b in
                let pA = stationPriority[a.imageremark ?? ""] ?? 99
                let pB = stationPriority[b.imageremark ?? ""] ?? 99
                if pA != pB { return pA < pB }
                return a.output > b.output
            }
            let primary = sortedGroup[0]

            var allVariants: [CraftingVariant] = []
            for r in sortedGroup {
                for v in r.resolvedVariants {
                    allVariants.append(v)
                }
            }
            let uniqueVariants = mergeCookingVariants(allVariants)

            let firstVar = uniqueVariants.first ?? CraftingVariant(
                ingredients: primary.ingredients,
                output: primary.output,
                imageremark: primary.imageremark,
                remarks: primary.remarks
            )

            mergedList.append(
                Recipe(
                    id: primary.id > 0 ? primary.id : (index + 1),
                    name: primary.name,
                    image: primary.image,
                    ingredients: firstVar.ingredients,
                    alternateIngredients: uniqueVariants.count > 1 ? uniqueVariants[1].ingredients : nil,
                    alternateIngredients1: uniqueVariants.count > 2 ? uniqueVariants[2].ingredients : nil,
                    alternateIngredients2: uniqueVariants.count > 3 ? uniqueVariants[3].ingredients : nil,
                    alternateIngredients3: uniqueVariants.count > 4 ? uniqueVariants[4].ingredients : nil,
                    output: firstVar.output,
                    alternateOutput: uniqueVariants.count > 1 ? uniqueVariants[1].output : nil,
                    alternateOutput1: uniqueVariants.count > 2 ? uniqueVariants[2].output : nil,
                    alternateOutput2: uniqueVariants.count > 3 ? uniqueVariants[3].output : nil,
                    alternateOutput3: uniqueVariants.count > 4 ? uniqueVariants[4].output : nil,
                    category: primary.category,
                    imageremark: firstVar.imageremark,
                    remarks: firstVar.remarks,
                    variants: uniqueVariants
                )
            )
        }

        return mergedList
    }
}

/// A user-created, iCloud-synced collection of crafting recipes.
struct RecipeChest: Codable, Identifiable, Equatable, Hashable {
    enum Size: Int, Codable, CaseIterable, Identifiable {
        case small = 27
        case large = 54

        var id: Int { rawValue }
        var title: String { self == .small ? "Small Chest" : "Large Chest" }
    }

    let id: UUID
    var name: String
    var size: Size
    var symbol: String?
    var recipeIDs: [Int]

    init(id: UUID = UUID(), name: String, size: Size, symbol: String? = nil, recipeIDs: [Int] = []) {
        self.id = id
        self.name = name
        self.size = size
        self.symbol = symbol
        self.recipeIDs = Array(recipeIDs.prefix(size.rawValue))
    }

    var displaySymbol: String { symbol ?? (size == .large ? "shippingbox.fill" : "shippingbox") }
}

struct RecipeReport: Identifiable, Codable {
    let id: String
    let recordID: String?
    let localID: String
    let reportType: String
    let recipeName: String
    let category: String
    let recipeID: Int?
    let description: String
    let timestamp: Date
    var status: String

    enum CodingKeys: String, CodingKey {
        case id, recordID, localID, reportType, recipeName, category, recipeID, description, timestamp, status
    }

    init(id: String, recordID: String?, localID: String, reportType: String, recipeName: String, category: String, recipeID: Int?, description: String, timestamp: Date, status: String) {
        self.id = id
        self.recordID = recordID
        self.localID = localID
        self.reportType = reportType
        self.recipeName = recipeName
        self.category = category
        self.recipeID = recipeID
        self.description = description
        self.timestamp = timestamp
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.recordID = try container.decodeIfPresent(String.self, forKey: .recordID)
        self.localID = try container.decode(String.self, forKey: .localID)
        self.reportType = try container.decode(String.self, forKey: .reportType)
        self.recipeName = try container.decode(String.self, forKey: .recipeName)
        self.category = try container.decode(String.self, forKey: .category)
        self.recipeID = try container.decodeIfPresent(Int.self, forKey: .recipeID)
        self.description = try container.decode(String.self, forKey: .description)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.status = try container.decode(String.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(recordID, forKey: .recordID)
        try container.encode(localID, forKey: .localID)
        try container.encode(reportType, forKey: .reportType)
        try container.encode(recipeName, forKey: .recipeName)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(recipeID, forKey: .recipeID)
        try container.encode(description, forKey: .description)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(status, forKey: .status)
    }
}

struct ConsoleCommand: Identifiable, Codable, Equatable {
    /// CloudKit recordName
    let id: String

    /// fields
    let name: String
    let description: String
    let worksInBedrock: Bool
    let worksInJava: Bool

    /// optional OP levels
    let opLevelBedrock: Int64?
    let opLevelJava: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, description, worksInBedrock, worksInJava, opLevelBedrock, opLevelJava
    }

    /// Designated initializer
    init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        worksInBedrock: Bool,
        worksInJava: Bool,
        opLevelBedrock: Int64? = nil,
        opLevelJava: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.worksInBedrock = worksInBedrock
        self.worksInJava = worksInJava
        self.opLevelBedrock = opLevelBedrock
        self.opLevelJava = opLevelJava
    }

    static let defaultCommands: [ConsoleCommand] = [
        ConsoleCommand(name: "/gamemode", description: "Sets a player's game mode (survival, creative, adventure, spectator).", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/give", description: "Gives an item to a player.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/tp", description: "Teleports entities (players, mobs, etc.).", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/time", description: "Changes or queries the world's game time.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/weather", description: "Sets the weather (clear, rain, thunder).", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/kill", description: "Kills entities (players, mobs, etc.).", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/clear", description: "Clears items from player inventory.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/locate", description: "Locates the nearest structure or biome.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/difficulty", description: "Sets the game difficulty level.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/effect", description: "Applies or clears status effects.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/enchant", description: "Enchants an item held by a player.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/xp", description: "Adds or removes player experience.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/summon", description: "Summons an entity.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/setblock", description: "Changes a block to another block.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2),
        ConsoleCommand(name: "/fill", description: "Fills a region with a specific block.", worksInBedrock: true, worksInJava: true, opLevelBedrock: 2, opLevelJava: 2)
    ]
}
