//
//  RecipeDetailView.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//

import SwiftUI

enum SelectedItem: Equatable {
    case grid(index: Int)
    case output
}

struct RecipeDetailView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let recipe: Recipe
    @Binding var navigationPath: NavigationPath

    @State private var selectedDetail: String?
    @State private var selectedItem: SelectedItem?
    @State private var showingChestPicker = false
    @State private var selectedCraftingOption = 0
    private var variants: [CraftingVariant] {
        recipe.resolvedVariants
    }

    private var safeSelectedOption: Int {
        guard !variants.isEmpty else { return 0 }
        return min(max(selectedCraftingOption, 0), variants.count - 1)
    }

    private var currentVariant: CraftingVariant {
        let list = variants
        guard list.indices.contains(safeSelectedOption) else {
            return CraftingVariant(
                ingredients: recipe.ingredients,
                output: recipe.output,
                imageremark: recipe.imageremark,
                remarks: recipe.remarks
            )
        }
        return list[safeSelectedOption]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                RecipeIdentityHeader(recipe: recipe, output: currentVariant.output)

                CraftingRecipeCard(
                    recipe: recipe,
                    variants: variants,
                    selectedCraftingOption: $selectedCraftingOption,
                    selectedItem: $selectedItem,
                    selectedDetail: $selectedDetail
                )

                if let selectedDetail {
                    IngredientDetailPopup(
                        detail: selectedDetail,
                        selectedDetail: $selectedDetail,
                        selectedItem: $selectedItem,
                        navigationPath: $navigationPath
                    )
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                }
            }
            .craftifyContentWidth()
            .padding(.horizontal, CraftifyLayout.pagePadding(for: horizontalSizeClass))
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add to Chest", systemImage: "plus") {
                    HapticFeedback.impact()
                    showingChestPicker = true
                }
                .labelStyle(.iconOnly)
                .accessibilityHint("Opens your chests")
            }
        }
        .sheet(isPresented: $showingChestPicker) {
            AddRecipeToChestView(recipe: recipe)
                .environmentObject(dataManager)
        }
        .craftifyPage()
        .onChange(of: selectedCraftingOption) { _, _ in
            selectedDetail = nil
            selectedItem = nil
            HapticFeedback.selection()
        }
        .onChange(of: dataManager.isLoading) { _, isLoading in
            if !isLoading && dataManager.isManualSyncing { dataManager.syncChests() }
        }
        .animation(reduceMotion ? nil : .snappy, value: selectedDetail)
    }
}

@MainActor
private struct RecipeIdentityHeader: View {
    let recipe: Recipe
    let output: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.craftifyAccentColor) private var accent

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 16) {
                    recipeImage
                    details(alignment: .center)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        recipeImage
                        details(alignment: .leading)
                    }
                    VStack(spacing: 16) {
                        recipeImage
                        details(alignment: .center)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .craftifyCard(cornerRadius: 26)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.name), \(recipe.category)")
    }

    private var recipeImage: some View {
        ZStack {
            AppBackground()
            CraftImage(key: recipe.image)
                .scaledToFit()
                .padding(16)
        }
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(0.24), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private func details(alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 7) {
            Text("CRAFTING RECIPE")
                .font(.caption.bold())
                .tracking(1.1)
                .foregroundStyle(accent)
            Text(recipe.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(alignment)
            if !recipe.category.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { metadata }
                    VStack(alignment: alignment == .center ? .center : .leading, spacing: 8) { metadata }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    @ViewBuilder
    private var metadata: some View {
        if !recipe.category.isEmpty {
            CraftifyStatusPill(title: recipe.category, symbol: "tag.fill")
        }
    }
}

@MainActor
private struct AddRecipeToChestView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.craftifyAccentColor) private var accent
    let recipe: Recipe
    @State private var creatingChest = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Create New Chest", systemImage: "plus.rectangle.on.folder") {
                        creatingChest = true
                    }
                    .fontWeight(.semibold)
                }

                if !dataManager.chests.isEmpty {
                    Section("Choose a Chest") {
                        ForEach(dataManager.chests) { chest in
                            Button {
                                add(to: chest)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: chest.displaySymbol)
                                        .foregroundStyle(accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(chest.name).foregroundStyle(.primary)
                                        ProgressView(
                                            value: Double(chest.recipeIDs.count),
                                            total: Double(chest.size.rawValue)
                                        )
                                        .tint(accent)
                                    }
                                    Text("\(chest.recipeIDs.count)/\(chest.size.rawValue)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(chest.recipeIDs.count >= chest.size.rawValue || chest.recipeIDs.contains(recipe.id))
                            .accessibilityHint(chest.recipeIDs.contains(recipe.id) ? "Recipe already stored here" : "Adds recipe to this chest")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Store \(recipe.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $creatingChest) {
                ChestEditorView(context: .new, recipeToAdd: recipe) {
                    creatingChest = false
                    dismiss()
                }
                .environmentObject(dataManager)
                .presentationDetents([.medium])
            }
            .alert("Couldn’t Add Recipe", isPresented: messageBinding) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "Please try another chest.")
            }
            .craftifyPage()
        }
        .presentationDetents([.medium, .large])
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func add(to chest: RecipeChest) {
        if dataManager.add(recipe, to: chest) {
            HapticFeedback.notification(.success)
            dismiss()
        } else {
            HapticFeedback.notification(.warning)
            message = chest.recipeIDs.contains(recipe.id)
                ? "This recipe is already in \(chest.name)."
                : "\(chest.name) is full."
        }
    }
}

@MainActor
private struct CraftingRecipeCard: View {
    let recipe: Recipe
    let variants: [CraftingVariant]
    @Binding var selectedCraftingOption: Int
    @Binding var selectedItem: SelectedItem?
    @Binding var selectedDetail: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftifyAccentColor) private var accent

    private var cellSize: CGFloat {
        horizontalSizeClass == .regular ? 76 : 64
    }

    private var safeIndex: Int {
        guard !variants.isEmpty else { return 0 }
        return min(max(selectedCraftingOption, 0), variants.count - 1)
    }

    private var activeVariant: CraftingVariant {
        guard variants.indices.contains(safeIndex) else {
            return CraftingVariant(
                ingredients: recipe.ingredients,
                output: recipe.output,
                imageremark: recipe.imageremark,
                remarks: recipe.remarks
            )
        }
        return variants[safeIndex]
    }

    private var layoutPageHeight: CGFloat {
        let gridHeight = 3 * cellSize + 46
        let usesVerticalFor3x3 = dynamicTypeSize.isAccessibilitySize || horizontalSizeClass != .regular
        let has3x3Variant = variants.contains { !$0.isCookingLayout }
        if usesVerticalFor3x3 && (has3x3Variant || dynamicTypeSize.isAccessibilitySize) {
            let outputHeight = cellSize + 44
            return gridHeight + 54 + outputHeight + 12
        }
        return gridHeight + 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                CraftifySectionHeader(
                    title: activeVariant.isCookingLayout ? "Smelting Layout" : "Crafting Layout",
                    detail: variants.count > 1
                        ? "Swipe left or right to switch layouts (\(safeIndex + 1) of \(variants.count))."
                        : "Tap an ingredient or the output to inspect it.",
                    symbol: activeVariant.isCookingLayout ? "flame.fill" : "square.grid.3x3.fill"
                )
                .contentTransition(.interpolate)

                if variants.count > 1 {
                    Spacer(minLength: 4)
                    CraftifyStatusPill(
                        title: "\(safeIndex + 1) / \(variants.count)",
                        symbol: "square.stack.3d.hor.right.fill"
                    )
                    .contentTransition(.numericText())
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: safeIndex)

            if variants.count > 1 {
                TabView(selection: $selectedCraftingOption) {
                    ForEach(Array(variants.enumerated()), id: \.offset) { idx, variant in
                        variantLayoutView(for: variant)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: layoutPageHeight)

                HStack(spacing: 8) {
                    Spacer()
                    ForEach(variants.indices, id: \.self) { idx in
                        Button {
                            withAnimation(.snappy(duration: 0.24)) {
                                selectedCraftingOption = idx
                            }
                        } label: {
                            Capsule()
                                .fill(idx == safeIndex ? accent : Color.primary.opacity(0.18))
                                .frame(width: idx == safeIndex ? 20 : 7, height: 7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Layout \(idx + 1) of \(variants.count)")
                    }
                    Spacer()
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: safeIndex)
            } else {
                variantLayoutView(for: activeVariant)
            }

            let resolvedImageRemark = (activeVariant.imageremark ?? recipe.imageremark)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedRemarks = (activeVariant.remarks ?? recipe.remarks)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !resolvedImageRemark.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.08))

                requiredUtilityFooter(
                    imageRemark: resolvedImageRemark,
                    remarks: resolvedRemarks.isEmpty ? nil : resolvedRemarks
                )
            } else if !resolvedRemarks.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.08))

                Text(resolvedRemarks)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .craftifyCard(cornerRadius: 24)
    }

    @ViewBuilder
    private func variantLayoutView(for variant: CraftingVariant) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalLayout(for: variant)
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalLayout(for: variant)
                verticalLayout(for: variant)
            }
        }
    }

    private func horizontalLayout(for variant: CraftingVariant) -> some View {
        HStack(spacing: horizontalSizeClass == .regular ? 28 : 20) {
            craftingGrid(for: variant)
            Image(systemName: "arrow.right")
                .font(.title.bold())
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            outputTile(output: variant.output)
        }
        .frame(maxWidth: .infinity)
    }

    private func verticalLayout(for variant: CraftingVariant) -> some View {
        VStack(spacing: 15) {
            craftingGrid(for: variant)
            Image(systemName: "arrow.down")
                .font(.title2.bold())
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            outputTile(output: variant.output)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func craftingGrid(for variant: CraftingVariant) -> some View {
        let normalized = variant.normalizedIngredients
        if variant.isCookingLayout {
            FurnaceGridView(
                ingredients: normalized,
                selectedItem: $selectedItem,
                selectedDetail: $selectedDetail,
                cellSize: cellSize
            )
        } else {
            DefaultGridView(
                ingredients: normalized,
                selectedItem: $selectedItem,
                selectedDetail: $selectedDetail,
                cellSize: cellSize
            )
        }
    }

    private func outputTile(output: Int) -> some View {
        Button {
            selectedDetail = recipe.name
            selectedItem = .output
            HapticFeedback.impact()
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(accent.opacity(0.09))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(
                                    selectedItem == .output ? accent : accent.opacity(0.18),
                                    lineWidth: selectedItem == .output ? 2 : 1
                                )
                        }
                    CraftImage(key: recipe.image)
                        .scaledToFit()
                        .padding(9)
                }
                .frame(width: cellSize + 12, height: cellSize + 12)

                Text("×\(output)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Output: \(recipe.name), quantity \(output)")
        .accessibilityHint("Shows output details")
    }

    private func requiredUtilityFooter(imageRemark: String, remarks: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                    .font(.caption.bold())
                    .foregroundStyle(accent)
                Text("REQUIRED CRAFTING UTILITY")
                    .font(.caption.bold())
                    .tracking(0.8)
                    .foregroundStyle(accent)
            }

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    CraftImage(key: imageRemark)
                        .scaledToFit()
                        .id(imageRemark)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.92))
                        )
                }
                .frame(width: 54, height: 54)
                .padding(6)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .leading) {
                        Text(imageRemark)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .id(imageRemark)
                            .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Use this utility for the crafting layout shown above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let remarks, !remarks.isEmpty {
                        Text(remarks)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                            .id(remarks)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .move(edge: .top))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .geometryGroup()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .geometryGroup()
        .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: imageRemark)
        .animation(reduceMotion ? nil : .snappy(duration: 0.26), value: remarks)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Required Crafting Utility: \(imageRemark)")
    }
}

@MainActor
struct IngredientDetailPopup: View {
    let detail: String
    @Binding var selectedDetail: String?
    @Binding var selectedItem: SelectedItem?
    @Binding var navigationPath: NavigationPath
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.craftifyAccentColor) private var accent

    private var subRecipe: Recipe? {
        guard case .grid(_) = selectedItem else { return nil }
        return dataManager.recipes.first { $0.name == detail }
    }

    private var descriptor: String {
        switch selectedItem {
        case .output: "Crafting output"
        case .grid: "Crafting ingredient"
        case nil: "Recipe detail"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text(descriptor.uppercased())
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(accent)

                Spacer(minLength: 8)

                Button("Close", systemImage: "xmark.circle.fill") {
                    selectedDetail = nil
                    selectedItem = nil
                    HapticFeedback.impact(.light)
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .accessibilityHint("Dismisses these details")
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        detailImage
                        detailTitle
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 16) {
                            detailImage
                            detailTitle
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            detailImage
                            detailTitle
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let subRecipe {
                Button {
                    navigationPath.append(subRecipe)
                } label: {
                    Label("View \(subRecipe.name) Recipe", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .craftifyButtonBorder(cornerRadius: 16)
            }
        }
        .padding(18)
        .craftifyCard(cornerRadius: 22)
        .accessibilityElement(children: .contain)
    }

    private var detailImage: some View {
        CraftImage(key: detail)
            .scaledToFit()
            .frame(width: 76, height: 76)
            .padding(8)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
    }

    private var detailTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(detail)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(selectedItem == .output ? "The item produced by this recipe." : "An item required in the crafting layout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
struct FurnaceGridView: View {
    let ingredients: [String]
    @Binding var selectedItem: SelectedItem?
    @Binding var selectedDetail: String?
    let cellSize: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ingredientCell(index: 0)
            Image("Furnace Fire")
                .resizable()
                .scaledToFit()
                .padding(cellSize * 0.28)
                .frame(width: cellSize, height: cellSize)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Furnace fire")
            ingredientCell(index: 1)
        }
    }

    private func ingredientCell(index: Int) -> some View {
        GridCell(
            index: index,
            ingredient: ingredients.indices.contains(index) ? ingredients[index] : "",
            isSelected: selectedItem == .grid(index: index),
            cellSize: cellSize
        ) {
            selectedDetail = ingredients[index]
            selectedItem = .grid(index: index)
        }
    }
}

@MainActor
struct DefaultGridView: View {
    let ingredients: [String]
    @Binding var selectedItem: SelectedItem?
    @Binding var selectedDetail: String?
    let cellSize: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3) { column in
                        let index = row * 3 + column
                        GridCell(
                            index: index,
                            ingredient: ingredients.indices.contains(index) ? ingredients[index] : "",
                            isSelected: selectedItem == .grid(index: index),
                            cellSize: cellSize
                        ) {
                            selectedDetail = ingredients[index]
                            selectedItem = .grid(index: index)
                        }
                    }
                }
            }
        }
    }
}

@MainActor
struct GridCell: View {
    let index: Int
    let ingredient: String
    let isSelected: Bool
    let cellSize: CGFloat
    let onTap: () -> Void
    @Environment(\.craftifyAccentColor) private var accent

    var body: some View {
        Button {
            guard !ingredient.isEmpty else { return }
            HapticFeedback.impact()
            onTap()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ingredient.isEmpty ? Color.primary.opacity(0.035) : accent.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? accent : Color.primary.opacity(ingredient.isEmpty ? 0.05 : 0.10),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }

                if !ingredient.isEmpty {
                    CraftImage(key: ingredient)
                        .scaledToFit()
                        .padding(7)
                }
            }
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .disabled(ingredient.isEmpty)
        .accessibilityLabel(ingredient.isEmpty ? "Empty crafting slot" : "Ingredient: \(ingredient)")
        .accessibilityHint(ingredient.isEmpty ? "" : "Shows ingredient details")
    }
}
