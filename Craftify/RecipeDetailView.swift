//
//  RecipeDetailView.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//

import SwiftUI
import UIKit

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
    @State private var isDraggingLayoutPager = false

    private var variants: [CraftingVariant] {
        recipe.resolvedVariants
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                RecipeIdentityHeader(recipe: recipe)

                CraftingRecipeCard(
                    recipe: recipe,
                    variants: variants,
                    selectedCraftingOption: $selectedCraftingOption,
                    selectedItem: $selectedItem,
                    selectedDetail: $selectedDetail,
                    isHorizontalDragging: $isDraggingLayoutPager
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
        .scrollDisabled(isDraggingLayoutPager)
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
            if selectedDetail != nil { selectedDetail = nil }
            if selectedItem != nil { selectedItem = nil }
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
            LinearGradient(
                colors: [accent.opacity(0.16), accent.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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

private final class PagerPanGestureRecognizer: UIPanGestureRecognizer {}

@MainActor
private struct HorizontalPagerGestureBridge: UIViewRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        context.coordinator.bridgeView = view
        return view
    }

    func updateUIView(_ uiView: BridgeView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        uiView.attachGestureIfNeeded()
    }

    static func dismantleUIView(_ uiView: BridgeView, coordinator: Coordinator) {
        uiView.detachGesture()
    }

    final class BridgeView: UIView {
        weak var coordinator: Coordinator?
        private weak var attachedView: UIView?
        private var panGesture: PagerPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                attachGestureIfNeeded()
            } else {
                detachGesture()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if window != nil && panGesture == nil {
                attachGestureIfNeeded()
            }
        }

        func attachGestureIfNeeded() {
            guard let coordinator else { return }
            var candidate: UIView? = superview
            var targetScrollView: UIScrollView?
            while let current = candidate {
                if let sv = current as? UIScrollView {
                    targetScrollView = sv
                    break
                }
                candidate = current.superview
            }
            guard let target = targetScrollView ?? superview else { return }

            if let scrollView = target as? UIScrollView {
                scrollView.isDirectionalLockEnabled = true
                scrollView.alwaysBounceHorizontal = false
                scrollView.showsHorizontalScrollIndicator = false
                if scrollView.contentSize.width > scrollView.bounds.width && scrollView.bounds.width > 0 {
                    scrollView.contentSize.width = scrollView.bounds.width
                }
            }

            if attachedView === target, panGesture != nil {
                return
            }
            detachGesture()

            let pan = PagerPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
            pan.delegate = coordinator
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            target.addGestureRecognizer(pan)

            attachedView = target
            panGesture = pan
        }

        func detachGesture() {
            if let pan = panGesture, let attached = attachedView {
                attached.removeGestureRecognizer(pan)
            }
            panGesture = nil
            attachedView = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: Bool = true
        var onChanged: (CGFloat) -> Void
        var onEnded: (CGFloat, CGFloat) -> Void
        weak var bridgeView: BridgeView?

        init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping (CGFloat, CGFloat) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let bridgeView else { return }
            let translation = gesture.translation(in: bridgeView).x
            let velocity = gesture.velocity(in: bridgeView).x

            switch gesture.state {
            case .began, .changed:
                onChanged(translation)
            case .ended, .cancelled, .failed:
                onEnded(translation, velocity)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let bridgeView,
                  bridgeView.window != nil else {
                return false
            }

            if let window = bridgeView.window {
                let windowLoc = pan.location(in: window)
                let winVel = pan.velocity(in: window)
                if windowLoc.x < 22 && winVel.x > 0 {
                    return false
                }
            }

            let localPoint = pan.location(in: bridgeView)
            guard bridgeView.bounds.insetBy(dx: -4, dy: -4).contains(localPoint) else {
                return false
            }

            let velocity = pan.velocity(in: bridgeView)
            return abs(velocity.x) > abs(velocity.y) * 0.72
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard gestureRecognizer is PagerPanGestureRecognizer else { return false }
            if otherGestureRecognizer is UIScreenEdgePanGestureRecognizer {
                return false
            }
            if otherGestureRecognizer is UIPanGestureRecognizer {
                return true
            }
            return false
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
    @Binding var isHorizontalDragging: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftifyAccentColor) private var accent

    @State private var dragOffset: CGFloat = 0
    @State private var measuredPageWidth: CGFloat = 320
    @State private var lastSwitchTimestamp: TimeInterval = 0
    @State private var lastSwitchDirection: Int = 0
    @State private var consecutiveSwitchStreak: Int = 0

    private var cellSize: CGFloat {
        horizontalSizeClass == .regular ? 72 : 56
    }

    private var gridDimension: CGFloat {
        3 * cellSize + 12
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
        if dynamicTypeSize.isAccessibilitySize {
            let outputHeight = cellSize + 44
            return gridDimension + 54 + outputHeight + 48
        }
        return gridDimension + 56
    }

    private func switchAnimation(initialVelocity: CGFloat, streak: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let stiffness = 340.0 + min(Double(streak) * 60.0, 180.0)
        let damping = 29.0 + min(Double(streak) * 2.4, 7.2)
        return .interpolatingSpring(
            mass: 0.78,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        )
    }

    private func commitVariantSwitch(to targetIndex: Int, rawVelocity: CGFloat = 0) {
        let clamped = min(max(targetIndex, 0), max(variants.count - 1, 0))
        let now = ProcessInfo.processInfo.systemUptime
        let direction = clamped > safeIndex ? 1 : (clamped < safeIndex ? -1 : 0)

        if direction != 0 {
            if direction == lastSwitchDirection && (now - lastSwitchTimestamp) < 0.50 {
                consecutiveSwitchStreak = min(consecutiveSwitchStreak + 1, 4)
            } else {
                consecutiveSwitchStreak = 0
            }
            lastSwitchDirection = direction
            lastSwitchTimestamp = now
        } else {
            consecutiveSwitchStreak = 0
        }

        let pageW = max(measuredPageWidth, 1)
        let remainingDistance = max(abs(CGFloat(clamped - safeIndex) * pageW - dragOffset), 28)
        let baseVelocity = abs(rawVelocity) / remainingDistance
        let streakBoost = 1.0 + CGFloat(consecutiveSwitchStreak) * 0.42
        let boostedVelocity = min(max(baseVelocity * streakBoost, direction != 0 ? 2.4 + CGFloat(consecutiveSwitchStreak) * 1.4 : 1.2), 32.0)

        withAnimation(switchAnimation(initialVelocity: boostedVelocity, streak: consecutiveSwitchStreak)) {
            selectedCraftingOption = clamped
            dragOffset = 0
        }
    }

    private func handleHorizontalPanChanged(_ dx: CGFloat) {
        guard variants.count > 1 else { return }
        if !isHorizontalDragging {
            isHorizontalDragging = true
        }
        let atLeadingEdge = safeIndex == 0 && dx > 0
        let atTrailingEdge = safeIndex == variants.count - 1 && dx < 0
        let effectiveDx = (atLeadingEdge || atTrailingEdge) ? dx * 0.24 : dx

        var transaction = Transaction(
            animation: .interactiveSpring(response: 0.08, dampingFraction: 0.94, blendDuration: 0.08)
        )
        transaction.isContinuous = true
        withTransaction(transaction) {
            dragOffset = effectiveDx
        }
    }

    private func handleHorizontalPanEnded(_ dx: CGFloat, velocity vx: CGFloat) {
        if isHorizontalDragging {
            isHorizontalDragging = false
        }
        guard variants.count > 1 else {
            if dragOffset != 0 {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    dragOffset = 0
                }
            }
            return
        }

        let pageW = max(measuredPageWidth, 1)
        let projectedDx = dx + vx * 0.16
        let distanceThreshold = pageW * 0.14
        let velocityThreshold: CGFloat = 130

        var targetIndex = safeIndex
        if dx < -distanceThreshold || vx < -velocityThreshold || projectedDx < -pageW * 0.24 {
            targetIndex = min(variants.count - 1, safeIndex + 1)
        } else if dx > distanceThreshold || vx > velocityThreshold || projectedDx > pageW * 0.24 {
            targetIndex = max(0, safeIndex - 1)
        }

        commitVariantSwitch(to: targetIndex, rawVelocity: vx)
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

                if variants.count > 1 {
                    Spacer(minLength: 4)
                    CraftifyStatusPill(
                        title: "\(safeIndex + 1) / \(variants.count)",
                        symbol: "square.stack.3d.hor.right.fill"
                    )
                    .contentTransition(.numericText())
                }
            }

            if variants.count > 1 {
                GeometryReader { proxy in
                    let pageWidth = max(proxy.size.width, 1)
                    HStack(spacing: 0) {
                        ForEach(Array(variants.enumerated()), id: \.offset) { _, variant in
                            variantLayoutView(for: variant)
                                .padding(.vertical, 6)
                                .frame(width: pageWidth, height: layoutPageHeight, alignment: .center)
                        }
                    }
                    .offset(x: -CGFloat(safeIndex) * pageWidth + dragOffset)
                    .onAppear {
                        measuredPageWidth = pageWidth
                    }
                    .onChange(of: pageWidth) { _, newWidth in
                        measuredPageWidth = newWidth
                    }
                }
                .frame(height: layoutPageHeight)
                .clipped()

                HStack(spacing: 8) {
                    Spacer()
                    ForEach(variants.indices, id: \.self) { idx in
                        Capsule()
                            .fill(idx == safeIndex ? accent : Color.primary.opacity(0.18))
                            .frame(width: idx == safeIndex ? 20 : 7, height: 7)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                commitVariantSwitch(to: idx, rawVelocity: 520)
                            }
                            .accessibilityLabel("Layout \(idx + 1) of \(variants.count)")
                            .accessibilityAddTraits(.isButton)
                    }
                    Spacer()
                }
            } else {
                variantLayoutView(for: activeVariant)
            }

            let hasUtilities = !activeVariant.resolvedStations.isEmpty ||
                (activeVariant.imageremark?.isEmpty == false) ||
                (recipe.imageremark?.isEmpty == false)

            if hasUtilities {
                Divider()
                    .overlay(Color.primary.opacity(0.08))

                requiredUtilitiesSection(for: activeVariant)
            } else if let remarks = (activeVariant.remarks ?? recipe.remarks)?.trimmingCharacters(in: .whitespacesAndNewlines), !remarks.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.08))

                Text(remarks)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            HorizontalPagerGestureBridge(
                isEnabled: variants.count > 1,
                onChanged: { dx in
                    handleHorizontalPanChanged(dx)
                },
                onEnded: { dx, vx in
                    handleHorizontalPanEnded(dx, velocity: vx)
                }
            )
        }
        .craftifyCard(cornerRadius: 24)
    }

    @ViewBuilder
    private func variantLayoutView(for variant: CraftingVariant) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalLayout(for: variant)
        } else {
            horizontalLayout(for: variant)
        }
    }

    private func horizontalLayout(for variant: CraftingVariant) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: horizontalSizeClass == .regular ? 24 : 14) {
                craftingGrid(for: variant)
                    .frame(width: gridDimension, height: gridDimension)
                Image(systemName: "arrow.right")
                    .font(.title2.bold())
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                outputTile(output: variant.output)
            }
            .frame(maxWidth: .infinity)

            variantSummaryBar(for: variant)
        }
        .frame(maxWidth: .infinity)
    }

    private func verticalLayout(for variant: CraftingVariant) -> some View {
        VStack(spacing: 14) {
            craftingGrid(for: variant)
                .frame(width: gridDimension, height: gridDimension)
            Image(systemName: "arrow.down")
                .font(.title2.bold())
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            outputTile(output: variant.output)

            variantSummaryBar(for: variant)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func variantSummaryBar(for variant: CraftingVariant) -> some View {
        if variant.isCookingLayout {
            cookingTimesComparisonBar(for: variant)
                .frame(height: 28)
        } else {
            craftingStationSummaryBar(for: variant)
                .frame(height: 28)
        }
    }

    private func craftingStationSummaryBar(for variant: CraftingVariant) -> some View {
        let station = variant.resolvedStations.first ?? variant.imageremark ?? recipe.imageremark ?? "Crafting Table"
        let isDyeing = variant.ingredients.contains { $0.hasPrefix("Any ") } && variant.ingredients.contains { $0.hasSuffix(" Dye") }
        let modeBadge: (label: String, icon: String) = {
            if isDyeing {
                return ("Dyeing", "paintbrush.pointed.fill")
            }
            switch station {
            case "Stonecutter":
                return ("1:1 Cut", "scissors")
            case "Smithing Table":
                return ("Upgrade", "hammer.fill")
            default:
                return ("Direct Craft", "square.grid.3x3.fill")
            }
        }()

        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                CraftImage(key: station)
                    .scaledToFit()
                    .frame(width: 18, height: 18)

                Text(station)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            HStack(spacing: 4) {
                Image(systemName: modeBadge.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(modeBadge.label)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accent.opacity(0.09), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private func cookingTimesComparisonBar(for variant: CraftingVariant) -> some View {
        let infos = variant.cookingStationInfos
        return HStack(spacing: 8) {
            ForEach(infos) { info in
                HStack(spacing: 5) {
                    CraftImage(key: info.station)
                        .scaledToFit()
                        .frame(width: 18, height: 18)

                    Text(String(format: "%.0fs", info.seconds))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }

            if let xp = variant.parsedXP {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "+%.2g XP", xp))
                        .font(.caption2.bold())
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.10), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
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
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onTapGesture {
            guard !isHorizontalDragging else { return }
            selectedDetail = recipe.name
            selectedItem = .output
            HapticFeedback.impact()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Output: \(recipe.name), quantity \(output)")
        .accessibilityHint("Shows output details")
    }

    private func utilityItems(for variant: CraftingVariant) -> [RecipeUtilityItem] {
        if variant.isCookingLayout {
            return variant.cookingStationInfos.map { .cooking(info: $0) }
        } else {
            let stations = variant.resolvedStations.isEmpty
                ? [(variant.imageremark ?? recipe.imageremark ?? "Crafting Table")]
                : variant.resolvedStations
            return stations.map { .standard(station: $0, remarks: variant.remarks ?? recipe.remarks) }
        }
    }

    @ViewBuilder
    private func requiredUtilitiesSection(for variant: CraftingVariant) -> some View {
        let items = utilityItems(for: variant)
        if let primary = items.first {
            let extraItems = Array(items.dropFirst())

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.caption.bold())
                        .foregroundStyle(accent)
                    Text(items.count > 1 ? "REQUIRED CRAFTING UTILITIES" : "REQUIRED CRAFTING UTILITY")
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(accent)
                }

                VStack(spacing: 10) {
                    // Slot 0: Primary Utility Card (Permanent structural identity, zero view destruction during switches)
                    UtilityCardView(item: primary)

                    // Extra utilities (e.g. Blast Furnace, Smoker, Campfire) with reversible symmetric spring transition
                    ForEach(extraItems) { item in
                        UtilityCardView(item: item)
                            .allowsHitTesting(false)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Required Crafting Utilities")
        }
    }
}

enum RecipeUtilityItem: Identifiable, Equatable {
    case standard(station: String, remarks: String?)
    case cooking(info: CookingStationInfo)

    var id: String {
        switch self {
        case .standard(let station, _):
            return "std-\(station)"
        case .cooking(let info):
            return "cook-\(info.station)"
        }
    }

    var stationKey: String {
        switch self {
        case .standard(let station, _):
            return station
        case .cooking(let info):
            return info.station
        }
    }

    var displayName: String {
        switch self {
        case .standard(let station, _):
            return station
        case .cooking(let info):
            return info.displayName
        }
    }

    var descriptionText: String {
        switch self {
        case .cooking(let info):
            return info.stationDescription
        case .standard(let station, _):
            switch station {
            case "Crafting Table":
                return "Standard 3×3 crafting grid for assembling blocks, tools, and items."
            case "Stonecutter":
                return "Precision masonry cutting with exact 1:1 ingredient yield."
            case "Smithing Table":
                return "Upgrades armor and tools using smithing templates and materials."
            default:
                return "Use this utility for the crafting layout shown above."
            }
        }
    }

    var badgeIcon: String {
        switch self {
        case .cooking:
            return "clock.fill"
        case .standard(let station, _):
            switch station {
            case "Stonecutter": return "scissors"
            case "Smithing Table": return "hammer.fill"
            default: return "square.grid.3x3.fill"
            }
        }
    }

    var badgePrimaryText: String {
        switch self {
        case .cooking(let info):
            return String(format: "%.0fs", info.seconds)
        case .standard(let station, _):
            switch station {
            case "Stonecutter": return "1:1 Cut"
            case "Smithing Table": return "Upgrade"
            default: return "3×3 Grid"
            }
        }
    }

    var badgeSecondaryText: String? {
        switch self {
        case .cooking(let info):
            return "(\(info.ticks)t)"
        case .standard:
            return nil
        }
    }

    var footerIcon: String {
        switch self {
        case .cooking(let info):
            return info.station == "Campfire" ? "leaf.fill" : "flame.fill"
        case .standard(let station, _):
            switch station {
            case "Stonecutter": return "cube.fill"
            case "Smithing Table": return "sparkles"
            default: return "checkmark.circle.fill"
            }
        }
    }

    var footerText: String {
        switch self {
        case .cooking(let info):
            return info.fuelDescription
        case .standard(let station, let remarks):
            if let remarks = remarks?.trimmingCharacters(in: .whitespacesAndNewlines), !remarks.isEmpty {
                return remarks
            }
            switch station {
            case "Stonecutter": return "Instant stone & copper cutting"
            case "Smithing Table": return "Preserves enchantments & trims"
            default: return "Instant crafting • No fuel required"
            }
        }
    }

    var xpValue: Double? {
        switch self {
        case .cooking(let info):
            return info.xp
        case .standard:
            return nil
        }
    }
}

@MainActor
struct UtilityCardView: View {
    let item: RecipeUtilityItem
    @Environment(\.craftifyAccentColor) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CraftImage(key: item.stationKey)
                .scaledToFit()
                .frame(width: 54, height: 54)
                .padding(6)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(item.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Image(systemName: item.badgeIcon)
                            .font(.caption2)
                            .foregroundStyle(accent)
                        Text(item.badgePrimaryText)
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                        if let secondary = item.badgeSecondaryText {
                            Text(secondary)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.09), in: Capsule())
                }

                Text(item.descriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(item.footerText, systemImage: item.footerIcon)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let xp = item.xpValue {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Label(String(format: "+%.2g XP", xp), systemImage: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@MainActor
struct CookingUtilityCard: View {
    let info: CookingStationInfo
    var body: some View {
        UtilityCardView(item: .cooking(info: info))
    }
}

@MainActor
struct StandardUtilityCard: View {
    let station: String
    let remarks: String?
    var body: some View {
        UtilityCardView(item: .standard(station: station, remarks: remarks))
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
        if let exact = dataManager.recipes.first(where: { $0.name == detail }) {
            return exact
        }
        if detail.hasPrefix("Any ") {
            let baseFamily = String(detail.dropFirst(4))
            if let baseRecipe = dataManager.recipes.first(where: { $0.name == baseFamily }) {
                return baseRecipe
            }
            if let whiteVariant = dataManager.recipes.first(where: { $0.name == "White \(baseFamily)" }) {
                return whiteVariant
            }
        }
        return nil
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
            Text(
                selectedItem == .output
                    ? "The item produced by this recipe."
                    : (detail.hasPrefix("Any ")
                        ? "Any color variant of \(detail.dropFirst(4).lowercased()) can be dyed in this recipe."
                        : "An item required in the crafting layout.")
            )
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
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard !ingredient.isEmpty else { return }
            HapticFeedback.impact()
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ingredient.isEmpty ? [] : .isButton)
        .accessibilityLabel(ingredient.isEmpty ? "Empty crafting slot" : "Ingredient: \(ingredient)")
        .accessibilityHint(ingredient.isEmpty ? "" : "Shows ingredient details")
    }
}
