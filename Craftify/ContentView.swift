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

enum RecipeRowMetrics {
    static let headerHeight: CGFloat = 32
    static let headerBottomSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 24
    static let viewportBuffer: CGFloat = 720
    static let scrubBuffer: CGFloat = 360
    static let scrollUpdateThreshold: CGFloat = 140

    static func rowHeight(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 164
        } else if dynamicTypeSize >= .xxLarge {
            return 126
        } else {
            return 108
        }
    }
}

struct ScrollViewportSnapshot: Equatable {
    let offsetY: CGFloat
    let containerHeight: CGFloat
}

struct RecipeScrollViewportTracker: ViewModifier {
    let topContentHeight: CGFloat
    let onUpdate: (CGFloat, CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: ScrollViewportSnapshot.self) { geo in
                    ScrollViewportSnapshot(
                        offsetY: geo.contentOffset.y + geo.contentInsets.top,
                        containerHeight: geo.containerSize.height
                    )
                } action: { _, snapshot in
                    let sectionRelativeY = max(0, snapshot.offsetY - topContentHeight)
                    onUpdate(sectionRelativeY, snapshot.containerHeight)
                }
        } else {
            content
        }
    }
}

struct RecipeLegacyScrollOffsetReporter: ViewModifier {
    let scrollSpaceName: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
        } else {
            content.background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: RecipeSectionsScrollOffsetKey.self,
                        value: -geo.frame(in: .named(scrollSpaceName)).minY
                    )
                }
            )
        }
    }
}

struct RecipeSectionLayoutItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let letter: String
    let rows: [[Recipe]]
    let relMinY: CGFloat
    let height: CGFloat

    var relMaxY: CGFloat { relMinY + height }

    static func == (lhs: RecipeSectionLayoutItem, rhs: RecipeSectionLayoutItem) -> Bool {
        lhs.id == rhs.id
    }

    func visibleRowRange(
        minY: CGFloat,
        maxY: CGFloat,
        rowHeight: CGFloat
    ) -> Range<Int>? {
        guard !rows.isEmpty, relMaxY >= minY, relMinY <= maxY else { return nil }
        let rowsOriginY = relMinY + RecipeRowMetrics.headerHeight + RecipeRowMetrics.headerBottomSpacing
        let rowStride = rowHeight + RecipeRowMetrics.rowSpacing
        let first = max(0, Int(floor((minY - rowsOriginY) / rowStride)))
        let last = min(rows.count - 1, Int(floor((maxY - rowsOriginY) / rowStride)))
        guard first <= last else {
            return 0 ..< min(rows.count, 1)
        }
        return first ..< (last + 1)
    }
}

struct RecipeSectionsLayout: Equatable {
    let id: UUID = UUID()
    let sortedLetters: [String]
    let availableLettersSet: Set<String>
    let sections: [RecipeSectionLayoutItem]
    let sectionsByLetter: [String: RecipeSectionLayoutItem]
    let totalHeight: CGFloat
    let rowHeight: CGFloat
    let isSingleColumn: Bool

    static let empty = RecipeSectionsLayout(
        sortedLetters: [],
        groupedRecipes: [:],
        isSingleColumn: true,
        rowHeight: 108
    )

    static func == (lhs: RecipeSectionsLayout, rhs: RecipeSectionsLayout) -> Bool {
        lhs.id == rhs.id
    }

    init(
        sortedLetters: [String],
        groupedRecipes: [String: [Recipe]],
        isSingleColumn: Bool,
        rowHeight: CGFloat
    ) {
        self.sortedLetters = sortedLetters
        self.availableLettersSet = Set(sortedLetters)
        self.isSingleColumn = isSingleColumn
        self.rowHeight = rowHeight
        let columnsCount = isSingleColumn ? 1 : 2

        var builtSections: [RecipeSectionLayoutItem] = []
        builtSections.reserveCapacity(sortedLetters.count)
        var byLetter: [String: RecipeSectionLayoutItem] = [:]
        var currentY: CGFloat = 0

        for letter in sortedLetters {
            guard let items = groupedRecipes[letter], !items.isEmpty else { continue }
            var rows: [[Recipe]] = []
            rows.reserveCapacity((items.count + columnsCount - 1) / columnsCount)
            var idx = 0
            while idx < items.count {
                let end = min(idx + columnsCount, items.count)
                rows.append(Array(items[idx..<end]))
                idx = end
            }

            let rowCount = rows.count
            let rowsHeight = CGFloat(rowCount) * rowHeight
                + CGFloat(max(0, rowCount - 1)) * RecipeRowMetrics.rowSpacing
            let sectionHeight = RecipeRowMetrics.headerHeight
                + RecipeRowMetrics.headerBottomSpacing
                + rowsHeight

            let item = RecipeSectionLayoutItem(
                letter: letter,
                rows: rows,
                relMinY: currentY,
                height: sectionHeight
            )
            builtSections.append(item)
            byLetter[letter] = item
            currentY += sectionHeight + RecipeRowMetrics.sectionSpacing
        }

        self.sections = builtSections
        self.sectionsByLetter = byLetter
        self.totalHeight = builtSections.last?.relMaxY ?? 0
    }
}

struct RecipeSectionsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@MainActor
private struct RecipeVirtualizedRowView: View, Equatable {
    let rowIndex: Int
    let rowRecipes: [Recipe]
    let isSingleColumn: Bool
    let rowHeight: CGFloat

    static func == (lhs: RecipeVirtualizedRowView, rhs: RecipeVirtualizedRowView) -> Bool {
        lhs.rowIndex == rhs.rowIndex
            && lhs.isSingleColumn == rhs.isSingleColumn
            && lhs.rowHeight == rhs.rowHeight
            && lhs.rowRecipes == rhs.rowRecipes
    }

    var body: some View {
        Group {
            if isSingleColumn {
                if let recipe = rowRecipes.first {
                    NavigationLink(value: recipe) {
                        RecipeCell(recipe: recipe, isCraftifyPick: false)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(rowRecipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeCell(recipe: recipe, isCraftifyPick: false)
                                .equatable()
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                    if rowRecipes.count == 1 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: rowHeight)
    }
}

@MainActor
private struct RecipeVirtualizedSectionView: View, Equatable {
    let section: RecipeSectionLayoutItem
    let visibleRange: Range<Int>?
    let rowHeight: CGFloat
    let isSingleColumn: Bool
    let accent: Color

    static func == (lhs: RecipeVirtualizedSectionView, rhs: RecipeVirtualizedSectionView) -> Bool {
        lhs.section.id == rhs.section.id
            && lhs.visibleRange == rhs.visibleRange
            && lhs.rowHeight == rhs.rowHeight
            && lhs.isSingleColumn == rhs.isSingleColumn
            && lhs.accent == rhs.accent
    }

    var body: some View {
        let rowStride = rowHeight + RecipeRowMetrics.rowSpacing

        VStack(alignment: .leading, spacing: 0) {
            Text(section.letter)
                .font(.title2.bold())
                .foregroundStyle(accent)
                .frame(height: RecipeRowMetrics.headerHeight, alignment: .leading)
                .padding(.bottom, RecipeRowMetrics.headerBottomSpacing)
                .accessibilityAddTraits(.isHeader)

            if let visibleRange {
                if visibleRange.lowerBound > 0 {
                    Color.clear
                        .frame(height: CGFloat(visibleRange.lowerBound) * rowStride)
                }

                VStack(alignment: .leading, spacing: RecipeRowMetrics.rowSpacing) {
                    ForEach(visibleRange, id: \.self) { rowIdx in
                        RecipeVirtualizedRowView(
                            rowIndex: rowIdx,
                            rowRecipes: section.rows[rowIdx],
                            isSingleColumn: isSingleColumn,
                            rowHeight: rowHeight
                        )
                        .equatable()
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: section.height,
            maxHeight: section.height,
            alignment: .topLeading
        )
        .id(section.letter)
    }
}

@MainActor
struct RecipeVirtualizedSectionsView: View {
    let layout: RecipeSectionsLayout
    let measuredScrollY: CGFloat
    let jumpTargetY: CGFloat?
    let viewportHeight: CGFloat
    let accent: Color

    private var effectiveMeasuredY: CGFloat {
        let maxScroll = max(0, layout.totalHeight - viewportHeight)
        return min(max(0, measuredScrollY), maxScroll)
    }

    private var effectiveJumpY: CGFloat? {
        guard let jumpTargetY else { return nil }
        let maxScroll = max(0, layout.totalHeight - viewportHeight)
        return min(max(0, jumpTargetY), maxScroll)
    }

    private func activeRowRange(for section: RecipeSectionLayoutItem) -> Range<Int>? {
        let centerTopY = effectiveJumpY ?? effectiveMeasuredY
        let buffer = effectiveJumpY != nil ? RecipeRowMetrics.scrubBuffer : RecipeRowMetrics.viewportBuffer
        let minY = centerTopY - buffer
        let maxY = centerTopY + viewportHeight + buffer
        return section.visibleRowRange(minY: minY, maxY: maxY, rowHeight: layout.rowHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RecipeRowMetrics.sectionSpacing) {
            ForEach(layout.sections) { section in
                RecipeVirtualizedSectionView(
                    section: section,
                    visibleRange: activeRowRange(for: section),
                    rowHeight: layout.rowHeight,
                    isSingleColumn: layout.isSingleColumn,
                    accent: accent
                )
                .equatable()
            }
        }
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
    private static let scrollSpaceName = "CraftifyRecipeListScrollSpace"

    private var isSingleColumn: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    private var estimatedTopContentHeight: CGFloat {
        guard !recommendedRecipes.isEmpty else { return 8 }
        if isCraftifyPicksExpanded {
            return (horizontalSizeClass == .regular ? 280 : 250) + 88
        } else {
            return 52 + 24
        }
    }

    @State private var cachedLayout: RecipeSectionsLayout?
    @State private var measuredScrollY: CGFloat = 0
    @State private var jumpTargetY: CGFloat?
    @State private var viewportHeight: CGFloat = 850
    @State private var lastJumpTarget: String?

    private func buildLayout() -> RecipeSectionsLayout {
        let sorted = filteredRecipes.keys.sorted()
        return RecipeSectionsLayout(
            sortedLetters: sorted,
            groupedRecipes: filteredRecipes,
            isSingleColumn: isSingleColumn,
            rowHeight: RecipeRowMetrics.rowHeight(for: dynamicTypeSize)
        )
    }

    private func rebuildLayout() {
        let newLayout = buildLayout()
        cachedLayout = newLayout
        let maxScroll = max(0, newLayout.totalHeight - viewportHeight)
        if measuredScrollY > maxScroll {
            measuredScrollY = maxScroll
        }
        jumpTargetY = nil
        lastJumpTarget = nil
    }

    var body: some View {
        let layout = cachedLayout ?? buildLayout()

        Group {
            if dataManager.recipes.isEmpty {
                EmptyRecipeView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !recommendedRecipes.isEmpty {
                                picksSection
                            }

                            RecipeVirtualizedSectionsView(
                                layout: layout,
                                measuredScrollY: measuredScrollY,
                                jumpTargetY: jumpTargetY,
                                viewportHeight: viewportHeight,
                                accent: accent
                            )
                            .modifier(RecipeLegacyScrollOffsetReporter(scrollSpaceName: Self.scrollSpaceName))
                        }
                        .craftifyContentWidth()
                        .padding(.leading, CraftifyLayout.pagePadding(for: horizontalSizeClass))
                        .padding(.trailing, CraftifyLayout.pagePadding(for: horizontalSizeClass) + 26)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .coordinateSpace(name: Self.scrollSpaceName)
                    .scrollIndicators(.hidden)
                    .modifier(
                        RecipeScrollViewportTracker(topContentHeight: estimatedTopContentHeight) { newOffset, containerH in
                            if containerH > 100, abs(containerH - viewportHeight) > 1 {
                                viewportHeight = containerH
                            }
                            if jumpTargetY == nil, abs(newOffset - measuredScrollY) >= RecipeRowMetrics.scrollUpdateThreshold {
                                measuredScrollY = newOffset
                            }
                        }
                    )
                    .onPreferenceChange(RecipeSectionsScrollOffsetKey.self) { newOffset in
                        guard #unavailable(iOS 18.0) else { return }
                        if jumpTargetY == nil, abs(newOffset - measuredScrollY) >= RecipeRowMetrics.scrollUpdateThreshold {
                            measuredScrollY = newOffset
                        }
                    }
                    .overlay(alignment: .trailing) {
                        RecipeAlphabetIndexBar(
                            alphabet: Self.alphabet,
                            availableLetters: layout.availableLettersSet,
                            accent: accent,
                            onSelectLetter: { selectedLetter in
                                guard let target = resolveScrollTarget(for: selectedLetter, in: layout),
                                      lastJumpTarget != target,
                                      let section = layout.sectionsByLetter[target] else {
                                    return
                                }
                                lastJumpTarget = target
                                let clampedY = min(
                                    section.relMinY,
                                    max(0, layout.totalHeight - viewportHeight)
                                )
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    jumpTargetY = clampedY
                                    measuredScrollY = clampedY
                                    proxy.scrollTo(target, anchor: .top)
                                }
                            },
                            onEndScrubbing: {
                                if let targetY = jumpTargetY {
                                    measuredScrollY = targetY
                                }
                                jumpTargetY = nil
                                lastJumpTarget = nil
                            }
                        )
                        .padding(.trailing, 2)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .onAppear {
            if cachedLayout == nil {
                cachedLayout = buildLayout()
            }
        }
        .onChange(of: filteredRecipes) { _, _ in
            rebuildLayout()
        }
        .onChange(of: isSingleColumn) { _, _ in
            rebuildLayout()
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            rebuildLayout()
        }
    }

    private func resolveScrollTarget(for letter: String, in layout: RecipeSectionsLayout) -> String? {
        let sorted = layout.sortedLetters
        guard !sorted.isEmpty else { return nil }
        if layout.availableLettersSet.contains(letter) {
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isCraftifyPicksExpanded.toggle()
                }
            }

            if isCraftifyPicksExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(recommendedRecipes) { recipe in
                            NavigationLink(value: recipe) {
                                RecipeCell(recipe: recipe, isCraftifyPick: true)
                                    .equatable()
                            }
                            .buttonStyle(RecipeInteractiveButtonStyle())
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

@MainActor
private struct IndexBarStaticTrack: View, Equatable {
    let alphabet: [String]
    let availableLetters: Set<String>
    let accent: Color
    let letterHeight: CGFloat

    static func == (lhs: IndexBarStaticTrack, rhs: IndexBarStaticTrack) -> Bool {
        lhs.availableLetters == rhs.availableLetters
            && lhs.letterHeight == rhs.letterHeight
            && lhs.accent == rhs.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(alphabet, id: \.self) { letter in
                let isAvailable = availableLetters.contains(letter)

                Text(letter)
                    .font(.system(size: 10, weight: isAvailable ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isAvailable ? accent : Color.secondary.opacity(0.35))
                    .frame(width: 18, height: letterHeight)
            }
        }
    }
}

private struct IndexCalloutShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        let center = CGPoint(x: r, y: r)
        var path = Path()
        path.move(to: CGPoint(x: rect.width, y: r))
        path.addArc(
            center: center,
            radius: r,
            startAngle: .degrees(38),
            endAngle: .degrees(322),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

@MainActor
private struct IndexCalloutView: View {
    let letter: String
    let accent: Color

    var body: some View {
        ZStack {
            IndexCalloutShape()
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    IndexCalloutShape()
                        .strokeBorder(accent.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 8, x: -2, y: 3)

            Text(letter)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .offset(x: -3)
                .transaction { $0.animation = nil }
        }
        .frame(width: 50, height: 44)
    }
}

@MainActor
struct RecipeAlphabetIndexBar: View {
    let alphabet: [String]
    let availableLetters: Set<String>
    let accent: Color
    let onSelectLetter: (String) -> Void
    var onEndScrubbing: (() -> Void)? = nil

    @State private var activeIndex: Int = 0
    @State private var isTouching = false
    @State private var dragY: CGFloat = 0
    @State private var lastScrolledLetter: String?

    private let trackVerticalPadding: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let totalHeight = max(geo.size.height, 260)
            let letterHeight = max(11, min(14, floor((totalHeight - 16) / CGFloat(alphabet.count))))
            let barContentHeight = CGFloat(alphabet.count) * letterHeight + trackVerticalPadding * 2

            IndexBarStaticTrack(
                alphabet: alphabet,
                availableLetters: availableLetters,
                accent: accent,
                letterHeight: letterHeight
            )
            .equatable()
            .padding(.vertical, trackVerticalPadding)
            .frame(width: 18, height: barContentHeight)
            .overlay(alignment: .top) {
                if isTouching, alphabet.indices.contains(activeIndex) {
                    ZStack {
                        Circle()
                            .fill(accent)
                            .frame(width: 15, height: 15)

                        Text(alphabet[activeIndex])
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 18, height: letterHeight)
                    .offset(y: trackVerticalPadding + CGFloat(activeIndex) * letterHeight)
                    .transaction { $0.animation = nil }
                    .allowsHitTesting(false)
                }
            }
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(isTouching ? 0.96 : 0.84))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(isTouching ? 0.14 : 0.07), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(isTouching ? 0.10 : 0.04), radius: 3, x: -1, y: 1)
            .offset(x: isTouching ? 1.5 : 0)
            .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.84), value: isTouching)
            .overlay(alignment: .topLeading) {
                if isTouching {
                    let letter = alphabet.indices.contains(activeIndex) ? alphabet[activeIndex] : (alphabet.first ?? "A")
                    IndexCalloutView(letter: letter, accent: accent)
                        .offset(x: -54, y: dragY - 22)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.65, anchor: .trailing).combined(with: .opacity),
                                removal: .scale(scale: 0.8, anchor: .trailing).combined(with: .opacity)
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 34, height: barContentHeight, alignment: .trailing)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let usableHeight = max(barContentHeight - trackVerticalPadding * 2, 1)
                        let minCenterY = trackVerticalPadding + letterHeight * 0.5
                        let maxCenterY = barContentHeight - trackVerticalPadding - letterHeight * 0.5
                        let clampedY = max(minCenterY, min(value.location.y, maxCenterY))
                        let y = max(0, min(value.location.y - trackVerticalPadding, usableHeight - 0.001))
                        let ratio = y / usableHeight
                        let index = min(max(Int(ratio * CGFloat(alphabet.count)), 0), alphabet.count - 1)
                        let letter = alphabet[index]

                        if !isTouching {
                            HapticFeedback.prepareSelection()
                            var initTx = Transaction()
                            initTx.disablesAnimations = true
                            withTransaction(initTx) {
                                dragY = clampedY
                                activeIndex = index
                            }
                            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
                                isTouching = true
                            }
                            HapticFeedback.selection()
                            lastScrolledLetter = letter
                            onSelectLetter(letter)
                            return
                        }

                        dragY = clampedY

                        if activeIndex != index {
                            activeIndex = index
                            HapticFeedback.selection()
                            if lastScrolledLetter != letter {
                                lastScrolledLetter = letter
                                onSelectLetter(letter)
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.interactiveSpring(response: 0.20, dampingFraction: 0.86)) {
                            isTouching = false
                        }
                        lastScrolledLetter = nil
                        onEndScrubbing?()
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(width: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alphabetical recipe index, A to Z")
    }
}

struct RecipeInteractiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.78), value: configuration.isPressed)
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
        let fixedHeight = RecipeRowMetrics.rowHeight(for: dynamicTypeSize)

        return HStack(spacing: 14) {
            recipeImage(size: dynamicTypeSize.isAccessibilitySize ? 72 : 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .minimumScaleFactor(0.9)
                if !recipe.category.isEmpty {
                    Label(recipe.category, systemImage: "tag.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                if !recipe.craftingUtilities.isEmpty {
                    craftingUtilityIconsRow(iconSize: 18)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .leading)
    }

    private var threeLinesHeadlineHeight: CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .headline)
        return ceil(font.lineHeight * 3 + 2)
    }

    private var pickContent: some View {
        VStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .topLeading) {
                recipeImage(size: horizontalSizeClass == .regular ? 96 : 82)
                    .frame(maxWidth: .infinity, alignment: .center)
                CraftifyStatusPill(title: "Pick", symbol: "sparkles")
                    .padding(6)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .center, spacing: 3) {
                Text(recipe.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .frame(height: threeLinesHeadlineHeight, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)

                if !recipe.category.isEmpty {
                    Text(recipe.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if !recipe.craftingUtilities.isEmpty {
                    craftingUtilityIconsRow(iconSize: 18)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 280 : (horizontalSizeClass == .regular ? 220 : 188),
            height: horizontalSizeClass == .regular ? 280 : 250,
            alignment: .center
        )
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

struct CraftifyHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.80), value: configuration.isPressed)
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
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CraftifyHeaderButtonStyle())
        .accessibilityLabel(isExpanded ? "Collapse Craftify Picks" : "Expand Craftify Picks")
        .accessibilityHint("Shows or hides recommended recipes")
    }
}
