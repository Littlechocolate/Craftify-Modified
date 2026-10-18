//
//  RecipeSearchView.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 15/05/2025.
//

import SwiftUI

struct RecipeSearchView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.craftifyAccentColor) private var accent
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var navigationPath = NavigationPath()
    @State private var searchFilter: SearchFilter = .names

    enum SearchFilter: String, CaseIterable, Identifiable {
        case names = "Recipe Names"
        case all = "Names & Ingredients"
        case ingredients = "Ingredients"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .names: "character.cursor.ibeam"
            case .all: "text.magnifyingglass"
            case .ingredients: "cube.fill"
            }
        }
    }

    private static let alphabet: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func strictSubstringMatch(_ target: String, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return target.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var matchingRecipes: [Recipe] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }

        return dataManager.recipes.filter { recipe in
            switch searchFilter {
            case .names:
                return strictSubstringMatch(recipe.name, query: query)
            case .all:
                return strictSubstringMatch(recipe.name, query: query)
                    || recipe.allIngredientNames.contains { strictSubstringMatch($0, query: query) }
            case .ingredients:
                return recipe.allIngredientNames.contains { strictSubstringMatch($0, query: query) }
            }
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var groupedMatchingRecipes: [String: [Recipe]] {
        Dictionary(grouping: matchingRecipes) {
            String($0.name.prefix(1)).uppercased()
        }
    }

    private var sortedAvailableLetters: [String] {
        groupedMatchingRecipes.keys.sorted()
    }

    private var availableLettersSet: Set<String> {
        Set(groupedMatchingRecipes.keys)
    }

    private var isSingleColumn: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    private var recentSearchRecipes: [Recipe] {
        var resolved: [Recipe] = []
        for name in dataManager.recentSearchNames {
            if let recipe = dataManager.recipes.first(where: { $0.name == name }),
               !resolved.contains(where: { $0.id == recipe.id }) {
                resolved.append(recipe)
            }
        }
        return Array(resolved.prefix(10))
    }

    private var resultColumns: [GridItem] {
        CraftifyLayout.adaptiveColumns(
            minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 320,
            maximum: 520,
            spacing: 14,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if trimmedQuery.isEmpty && !isSearchActive {
                            inactiveContent
                        } else if trimmedQuery.isEmpty {
                            searchState(
                                symbol: "text.cursor",
                                title: "Start Searching",
                                detail: "Enter an item or recipe name to find matching recipes."
                            )
                        } else if matchingRecipes.isEmpty {
                            searchState(
                                symbol: "magnifyingglass",
                                title: "No Recipes Found",
                                detail: "No recipes matched \"\(trimmedQuery)\"."
                            )
                        } else {
                            resultsContent
                        }
                    }
                    .craftifyContentWidth()
                    .padding(.leading, CraftifyLayout.pagePadding(for: horizontalSizeClass))
                    .padding(
                        .trailing,
                        CraftifyLayout.pagePadding(for: horizontalSizeClass) + (matchingRecipes.isEmpty ? 0 : 26)
                    )
                    .padding(.top, 12)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .trailing) {
                    if !matchingRecipes.isEmpty {
                        RecipeAlphabetIndexBar(
                            alphabet: Self.alphabet,
                            availableLetters: availableLettersSet,
                            accent: accent
                        ) { selectedLetter in
                            if let target = resolveScrollTarget(for: selectedLetter) {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    proxy.scrollTo(target, anchor: .top)
                                }
                            }
                        }
                        .padding(.trailing, 3)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search recipes by name"
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(SearchFilter.allCases) { filter in
                            Button {
                                searchFilter = filter
                                HapticFeedback.selection()
                            } label: {
                                Label(filter.rawValue, systemImage: searchFilter == filter ? "checkmark" : filter.symbol)
                            }
                        }
                    } label: {
                        Label("Search Field", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Search in \(searchFilter.rawValue)")
                    .accessibilityHint("Changes which recipe fields Craftify searches")
                }
            }
            .overlay {
                if dataManager.isLoading && dataManager.recipes.isEmpty {
                    loadingState
                }
            }
            .craftifyPage()
            .onAppear {
                dataManager.syncChests()
                dataManager.syncRecentSearches()
                dataManager.fetchRecipes(isManual: false)
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe, navigationPath: $navigationPath)
                    .onAppear {
                        dataManager.saveRecentSearch(recipe)
                        HapticFeedback.impact(.light)
                    }
            }
        }
    }

    private func resolveScrollTarget(for letter: String) -> String? {
        let sorted = sortedAvailableLetters
        guard !sorted.isEmpty else { return nil }
        if availableLettersSet.contains(letter) {
            return letter
        }
        if let next = sorted.first(where: { $0 >= letter }) {
            return next
        }
        return sorted.last
    }

    private var inactiveContent: some View {
        Group {
            CraftifyHero(
                eyebrow: "Find Anything",
                title: "Search Your Recipe Book",
                detail: "Search by recipe name, ingredient, or both. Your recent finds follow you through iCloud.",
                symbol: "magnifyingglass"
            )

            if recentSearchRecipes.isEmpty {
                searchState(
                    symbol: "magnifyingglass.circle.fill",
                    title: "What Are You Crafting?",
                    detail: "Tap the search field and start with a recipe name or ingredient."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        CraftifySectionHeader(
                            title: "Recent Searches",
                            detail: "Quickly return to recipes you opened before."
                        )
                        Spacer(minLength: 12)
                        Button("Clear All") {
                            dataManager.clearRecentSearches()
                            HapticFeedback.impact(.medium)
                        }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHint("Removes all recent recipe searches")
                    }

                    RecentSearchesList(
                        recipes: recentSearchRecipes,
                        navigationPath: $navigationPath
                    )
                }
            }
        }
    }

    private var resultsContent: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search Results")
                        .font(.title2.bold())
                    Text("Matching \"\(trimmedQuery)\" in \(searchFilter.rawValue.lowercased())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CraftifyStatusPill(
                    title: "\(resultCount) found",
                    symbol: "magnifyingglass"
                )
            }

            ForEach(sortedAvailableLetters, id: \.self) { letter in
                let items = groupedMatchingRecipes[letter] ?? []
                VStack(alignment: .leading, spacing: 10) {
                    Text(letter)
                        .font(.title2.bold())
                        .foregroundStyle(accent)
                        .accessibilityAddTraits(.isHeader)

                    if isSingleColumn {
                        LazyVStack(spacing: 12) {
                            ForEach(items) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeCell(recipe: recipe, isCraftifyPick: false)
                                        .equatable()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        LazyVGrid(columns: resultColumns, alignment: .leading, spacing: 12) {
                            ForEach(items) { recipe in
                                NavigationLink(value: recipe) {
                                    RecipeCell(recipe: recipe, isCraftifyPick: false)
                                        .equatable()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .id(letter)
            }
        }
    }

    private var resultCount: Int {
        matchingRecipes.count
    }

    private func searchState(symbol: String, title: String, detail: String) -> some View {
        CraftifyEmptyState(symbol: symbol, title: title, detail: detail)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(accent)
            Text("Loading Recipes…").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppBackground().ignoresSafeArea() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading recipes")
    }
}

struct RecentSearchItem: View {
    let recipe: Recipe
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.craftifyAccentColor) private var accent

    var body: some View {
        HStack(spacing: 13) {
            CraftImage(key: recipe.image)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .padding(5)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(recipe.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !recipe.craftingUtilities.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recipe.craftingUtilities, id: \.self) { utility in
                            CraftImage(key: utility)
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .padding(2)
                                .background(
                                    accent.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                )
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 3)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .craftifyCard(cornerRadius: 17)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(recipe.name), recent search")
        .accessibilityHint("Opens the crafting recipe")
    }
}

struct RecentSearchesList: View {
    let recipes: [Recipe]
    @Binding var navigationPath: NavigationPath
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        CraftifyLayout.adaptiveColumns(
            minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 280,
            maximum: 420,
            spacing: 12,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(recipes) { recipe in
                NavigationLink(value: recipe) {
                    RecentSearchItem(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
