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
        case category, imageremark, remarks
    }

    static func == (lhs: Recipe, rhs: Recipe) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.image == rhs.image &&
               lhs.ingredients == rhs.ingredients &&
               lhs.alternateIngredients == rhs.alternateIngredients &&
               lhs.alternateIngredients1 == rhs.alternateIngredients1 &&
               lhs.alternateIngredients2 == rhs.alternateIngredients2 &&
               lhs.alternateIngredients3 == rhs.alternateIngredients3 &&
               lhs.output == rhs.output &&
               lhs.alternateOutput == rhs.alternateOutput &&
               lhs.alternateOutput1 == rhs.alternateOutput1 &&
               lhs.alternateOutput2 == rhs.alternateOutput2 &&
               lhs.alternateOutput3 == rhs.alternateOutput3 &&
               lhs.category == rhs.category &&
               lhs.imageremark == rhs.imageremark &&
               lhs.remarks == rhs.remarks
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(image)
        hasher.combine(ingredients)
        hasher.combine(alternateIngredients)
        hasher.combine(alternateIngredients1)
        hasher.combine(alternateIngredients2)
        hasher.combine(alternateIngredients3)
        hasher.combine(output)
        hasher.combine(alternateOutput)
        hasher.combine(alternateOutput1)
        hasher.combine(alternateOutput2)
        hasher.combine(alternateOutput3)
        hasher.combine(category)
        hasher.combine(imageremark)
        hasher.combine(remarks)
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
