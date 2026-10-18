//
//  ContentView.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//

import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
    @EnvironmentObject private var dataManager: DataManager
    @AppStorage("colorSchemePreference") private var colorSchemePreference = "system"
    @AppStorage("accentColorPreference") private var accentColorPreference = "default"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()

            TabView(selection: $selectedTab) {
                RecipesTabView(navigationPath: $navigationPath)
                    .tabItem { Label("Recipes", systemImage: "square.grid.2x2") }
                    .tag(0)
                    .accessibilityLabel("Recipes tab")
                    .accessibilityHint("Browse the Craftify recipe library")

                ChestsView()
                    .tabItem { Label("Chests", systemImage: "shippingbox.fill") }
                    .tag(1)
                    .accessibilityLabel("Chests tab")
                    .accessibilityHint("Organize recipes in synced chests")

                MoreView()
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
                    .tag(2)
                    .accessibilityLabel("More tab")
                    .accessibilityHint("Open Craftify tools, settings, and information")

                RecipeSearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(3)
                    .accessibilityLabel("Search tab")
                    .accessibilityHint("Search recipes by name or ingredient")
            }
            .tint(Color.userAccentColor(for: accentColorPreference))
            .preferredColorScheme(preferredColorScheme)

            if dataManager.isManualSyncing {
                SyncOverlayView(
                    horizontalSizeClass: horizontalSizeClass,
                    message: "Syncing Recipes…"
                )
                .transition(.opacity)
                .zIndex(2)
            }

            if !dataManager.isManualSyncing,
               let announcement = dataManager.newRecipeAnnouncement {
                NewRecipesOverlayView(
                    horizontalSizeClass: horizontalSizeClass,
                    recipes: announcement.recipes
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        dataManager.dismissNewRecipeAnnouncement()
                    }
                }
                .id(announcement.id)
                .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: dataManager.isManualSyncing)
        .sensoryFeedback(.success, trigger: dataManager.newRecipeAnnouncement?.id)
        .onChange(of: selectedTab) { _, newValue in
            HapticFeedback.selection()
            UIAccessibility.post(
                notification: .announcement,
                argument: "Selected tab: \(tabName(for: newValue))"
            )
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func tabName(for tag: Int) -> String {
        switch tag {
        case 0: "Recipes"
        case 1: "Chests"
        case 2: "More"
        case 3: "Search"
        default: "Unknown"
        }
    }
}

@MainActor
struct RecipesTabView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.craftifyAccentColor) private var accent
    @Binding var navigationPath: NavigationPath

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AppBackground().ignoresSafeArea()

                CategoryView()
                    .navigationTitle("Craftify")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .overlay {
                        if dataManager.isLoading && dataManager.recipes.isEmpty {
                            loadingState
                        }
                    }
                    .navigationDestination(for: Recipe.self) { recipe in
                        RecipeDetailView(recipe: recipe, navigationPath: $navigationPath)
                    }
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            CraftifyAppMark(size: 72)
            ProgressView()
                .controlSize(.large)
                .tint(accent)
                .accessibilityHidden(true)
            Text("Preparing Your Recipe Book")
                .font(.headline)
            Text("Loading recipes and crafting images…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppBackground().ignoresSafeArea() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing your recipe book. Loading recipes and crafting images.")
    }
}

@MainActor
struct CategoryView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("isCraftifyPicksExpanded") private var isCraftifyPicksExpanded = true
    @State private var selectedCategory: String?
    @State private var recommendedRecipes: [Recipe] = []
    @State private var filteredRecipes: [String: [Recipe]] = [:]

    var body: some View {
        VStack(spacing: 0) {
            CategoryFilterBar(
                selectedCategory: $selectedCategory,
                categories: dataManager.categories
            )

            RecipeListView(
                recommendedRecipes: $recommendedRecipes,
                isCraftifyPicksExpanded: $isCraftifyPicksExpanded,
                filteredRecipes: filteredRecipes
            )
        }
        .navigationTitle("Craftify")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            refreshRecommendations()
            updateFilteredRecipes()
        }
        .onChange(of: dataManager.recipes) { _, _ in
            refreshRecommendations()
            updateFilteredRecipes()
        }
        .onChange(of: selectedCategory) { _, _ in updateFilteredRecipes() }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }

    private func refreshRecommendations() {
        recommendedRecipes = Array(dataManager.recipes.shuffled().prefix(horizontalSizeClass == .regular ? 9 : 7))
    }

    private func updateFilteredRecipes() {
        let source = selectedCategory.map { category in
            dataManager.recipes.filter { $0.category == category }
        } ?? dataManager.recipes

        filteredRecipes = Dictionary(grouping: source) {
            String($0.name.prefix(1)).uppercased()
        }
        .mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    }
}

@MainActor
struct CategoryFilterBar: View {
    @Binding var selectedCategory: String?
    let categories: [String]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("accentColorPreference") private var accentColorPreference = "default"

    private var accent: Color {
        Color.userAccentColor(for: accentColorPreference)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(title: "All", symbol: "square.grid.2x2", category: nil)
                ForEach(categories, id: \.self) { category in
                    filterButton(title: category, symbol: DataManager.categorySymbol(for: category), category: category)
                }
            }
            .padding(7)
        }
        .craftifyFloatingSurface(cornerRadius: 18)
        .padding(.horizontal, CraftifyLayout.pagePadding(for: horizontalSizeClass))
        .padding(.bottom, 8)
        .accessibilityLabel("Recipe categories")
    }

    private func filterButton(title: String, symbol: String, category: String?) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            selectedCategory = category
            HapticFeedback.selection()
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, horizontalSizeClass == .regular ? 15 : 12)
                .padding(.vertical, 9)
                .background(
                    isSelected ? accent : Color.primary.opacity(0.055),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "\(title), selected" : title)
        .accessibilityHint("Filters the recipe library")
    }
}

@MainActor
struct RecipeListView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.craftifyAccentColor) private var accent
    @Binding var recommendedRecipes: [Recipe]
    @Binding var isCraftifyPicksExpanded: Bool
    let filteredRecipes: [String: [Recipe]]

    private static let alphabet: [String] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)

    private var sortedAvailableLetters: [String] {
        filteredRecipes.keys.sorted()
    }

    private var availableLettersSet: Set<String> {
        Set(filteredRecipes.keys)
    }

    private var isSingleColumn: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    private var recipeColumns: [GridItem] {
        if isSingleColumn {
            return [GridItem(.flexible())]
        }
        return CraftifyLayout.adaptiveColumns(
            minimum: 320,
            maximum: 520,
            spacing: 16,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    @State private var lastScrollTarget: String?

    var body: some View {
        Group {
            if dataManager.recipes.isEmpty {
                EmptyRecipeView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            if !recommendedRecipes.isEmpty {
                                picksSection
                            }

                            ForEach(sortedAvailableLetters, id: \.self) { letter in
                                recipeSection(letter)
                                    .id(letter)
                            }
                        }
                        .craftifyContentWidth()
                        .padding(.leading, CraftifyLayout.pagePadding(for: horizontalSizeClass))
                        .padding(.trailing, CraftifyLayout.pagePadding(for: horizontalSizeClass) + 26)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                    .overlay(alignment: .trailing) {
                        RecipeAlphabetIndexBar(
                            alphabet: Self.alphabet,
                            availableLetters: availableLettersSet,
                            accent: accent
                        ) { selectedLetter in
                            if let target = resolveScrollTarget(for: selectedLetter),
                               lastScrollTarget != target {
                                lastScrollTarget = target
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

    private var picksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CraftifyPicksHeader(isExpanded: isCraftifyPicksExpanded) {
                withAnimation(.snappy) { isCraftifyPicksExpanded.toggle() }
            }

            if isCraftifyPicksExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(recommendedRecipes) { recipe in
                            NavigationLink(value: recipe) {
                                RecipeCell(recipe: recipe, isCraftifyPick: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func recipeSection(_ letter: String) -> some View {
        let items = filteredRecipes[letter] ?? []
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
                LazyVGrid(columns: recipeColumns, alignment: .leading, spacing: 12) {
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
    }
}

@MainActor
private struct IndexBarStaticTrack: View, Equatable {
    let alphabet: [String]
    let availableLetters: Set<String>
    let accent: Color
    let showDots: Bool
    let letterHeight: CGFloat
    let dotHeight: CGFloat

    static func == (lhs: IndexBarStaticTrack, rhs: IndexBarStaticTrack) -> Bool {
        lhs.availableLetters == rhs.availableLetters
            && lhs.showDots == rhs.showDots
            && lhs.letterHeight == rhs.letterHeight
            && lhs.accent == rhs.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(alphabet.enumerated()), id: \.offset) { idx, letter in
                let isAvailable = availableLetters.contains(letter)

                Text(letter)
                    .font(.system(size: showDots ? 10 : 9.5, weight: isAvailable ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isAvailable ? accent : Color.secondary.opacity(0.38))
                    .frame(width: 18, height: letterHeight)

                if showDots && idx < alphabet.count - 1 {
                    Text("·")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.42))
                        .frame(width: 18, height: dotHeight)
                }
            }
        }
        .drawingGroup()
    }
}

@MainActor
struct RecipeAlphabetIndexBar: View {
    let alphabet: [String]
    let availableLetters: Set<String>
    let accent: Color
    let onSelectLetter: (String) -> Void

    @State private var activeIndex: Int?
    @State private var lastScrolledLetter: String?

    var body: some View {
        GeometryReader { geo in
            let totalHeight = max(geo.size.height, 260)
            let showDots = totalHeight >= 470
            let letterHeight: CGFloat = showDots ? 12 : max(9, min(14, (totalHeight - 16) / CGFloat(alphabet.count)))
            let dotHeight: CGFloat = 5
            let stepHeight: CGFloat = letterHeight + (showDots ? dotHeight : 0)
            let barContentHeight = CGFloat(alphabet.count) * letterHeight
                + (showDots ? CGFloat(alphabet.count - 1) * dotHeight : 0)
                + 12

            IndexBarStaticTrack(
                alphabet: alphabet,
                availableLetters: availableLetters,
                accent: accent,
                showDots: showDots,
                letterHeight: letterHeight,
                dotHeight: dotHeight
            )
            .equatable()
            .overlay(alignment: .top) {
                if let idx = activeIndex, alphabet.indices.contains(idx) {
                    let letter = alphabet[idx]
                    let yCenter = CGFloat(idx) * stepHeight + letterHeight * 0.5
                    ZStack {
                        Circle()
                            .fill(accent)
                            .frame(width: 16, height: 16)
                        Text(letter)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 18, height: 18)
                    .offset(y: yCenter - 9)
                    .allowsHitTesting(false)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .frame(width: 22, height: barContentHeight)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.leading, 6)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let usableHeight = max(barContentHeight - 12, 1)
                        let y = value.location.y - 6
                        let ratio = min(max(y / usableHeight, 0), 0.9999)
                        let index = Int(ratio * CGFloat(alphabet.count))
                        if activeIndex != index {
                            if activeIndex == nil {
                                HapticFeedback.prepareSelection()
                            }
                            activeIndex = index
                            let letter = alphabet[index]
                            HapticFeedback.selection()
                            if lastScrolledLetter != letter {
                                lastScrolledLetter = letter
                                onSelectLetter(letter)
                            }
                        }
                    }
                    .onEnded { _ in
                        activeIndex = nil
                        lastScrolledLetter = nil
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(width: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alphabetical recipe index, A to Z")
    }
}

@MainActor
struct RecipeCell: View, Equatable {
    let recipe: Recipe
    let isCraftifyPick: Bool

    nonisolated static func == (lhs: RecipeCell, rhs: RecipeCell) -> Bool {
        lhs.recipe.id == rhs.recipe.id
            && lhs.recipe.name == rhs.recipe.name
            && lhs.isCraftifyPick == rhs.isCraftifyPick
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.craftifyAccentColor) private var accent

    var body: some View {
        Group {
            if isCraftifyPick {
                pickContent
                    .craftifyAccentCard(cornerRadius: 18)
            } else {
                rowContent
                    .craftifyCard(cornerRadius: 18)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(recipe.name), \(recipe.category.isEmpty ? "recipe" : "\(recipe.category) recipe")")
        .accessibilityHint("Opens the crafting recipe")
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            recipeImage(size: dynamicTypeSize.isAccessibilitySize ? 72 : 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if !recipe.category.isEmpty {
                    Label(recipe.category, systemImage: "tag.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                if !recipe.craftingUtilities.isEmpty {
                    craftingUtilityIconsRow(iconSize: 20)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
    }

    private var pickContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                recipeImage(size: horizontalSizeClass == .regular ? 96 : 82)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
                CraftifyStatusPill(title: "Pick", symbol: "sparkles")
                    .padding(9)
            }
            .frame(height: horizontalSizeClass == .regular ? 142 : 124)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(recipe.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !recipe.craftingUtilities.isEmpty {
                    craftingUtilityIconsRow(iconSize: 18)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 280 : (horizontalSizeClass == .regular ? 220 : 188))
    }

    private func craftingUtilityIconsRow(iconSize: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(recipe.craftingUtilities, id: \.self) { utility in
                CraftImage(key: utility)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .padding(3)
                    .background(
                        accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
        }
        .padding(.top, 1)
        .accessibilityHidden(true)
    }

    private func recipeImage(size: CGFloat) -> some View {
        CraftImage(key: recipe.image)
            .scaledToFit()
            .frame(width: size, height: size)
            .padding(5)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .accessibilityHidden(true)
    }
}

@MainActor
struct CraftifyPicksHeader: View {
    let isExpanded: Bool
    let toggle: () -> Void
    @Environment(\.craftifyAccentColor) private var accent

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Craftify Picks")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text("A fresh handful from the recipe book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse Craftify Picks" : "Expand Craftify Picks")
        .accessibilityHint("Shows or hides recommended recipes")
    }
}
