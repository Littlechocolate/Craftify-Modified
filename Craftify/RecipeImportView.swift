//
//  RecipeImportView.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//  Multi-version recipe importer and selector with duplicate conflict resolution.
//

import SwiftUI
import UniformTypeIdentifiers

struct RecipeImportView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.craftifyAccentColor) private var accent
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var versionManager = RecipeVersionManager.shared

    @State private var showingFilePicker = false
    @State private var showingDuplicateDialog = false
    @State private var pendingDuplicatePackage: RecipePackage?
    @State private var pendingDuplicateRawData: Data?
    @State private var duplicateExistingInfo: RecipeVersionInfo?

    @State private var statusMessage: String?
    @State private var isErrorMessage = false
    @State private var exportURL: URL?
    @State private var showingExportSheet = false
    @State private var versionToDelete: String?
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                headerCard

                activeVersionCard

                importActionBar

                installedVersionsSection
            }
            .craftifyContentWidth()
            .padding(.horizontal, CraftifyLayout.pagePadding(for: horizontalSizeClass))
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .navigationTitle("Recipe Versions")
        .navigationBarTitleDisplayMode(.large)
        .craftifyPage()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "recipe") ?? .data,
                .json,
                .data
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .confirmationDialog(
            "Version Conflict / 版本冲突",
            isPresented: $showingDuplicateDialog,
            titleVisibility: .visible
        ) {
            Button("Replace Existing / 替换原有版本", role: .destructive) {
                resolveDuplicate(with: .replace)
            }
            Button("Keep Both / 同时保留两份") {
                resolveDuplicate(with: .keepBoth)
            }
            Button("Cancel / 取消", role: .cancel) {
                resolveDuplicate(with: .cancel)
            }
        } message: {
            if let ver = pendingDuplicatePackage?.gameVersion {
                Text("Version \"\(ver)\" is already installed. How would you like to resolve this?\n版本号「\(ver)」已存在，请选择操作：")
            } else {
                Text("A version with this identifier already exists. Please choose how to proceed.")
            }
        }
        .confirmationDialog(
            "Delete Recipe Version",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            if let ver = versionToDelete {
                Button("Delete \"\(ver)\"", role: .destructive) {
                    deleteVersion(ver)
                }
            }
            Button("Cancel", role: .cancel) {
                versionToDelete = nil
            }
        } message: {
            if let ver = versionToDelete {
                Text("Are you sure you want to delete Minecraft \(ver)? This cannot be undone.")
            }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        CraftifyHero(
            eyebrow: "Recipe Management",
            title: "Minecraft Versions",
            detail: "Import and manage .recipe packages for multiple Minecraft versions. Switch between versions seamlessly offline.",
            symbol: "square.stack.3d.up.fill"
        )
    }

    private var activeVersionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CraftifyIconTile(symbol: "checkmark.seal.fill", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active Recipe Version")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Recipes in the library reflect this version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CraftifyStatusPill(
                    title: "Active",
                    symbol: "sparkles",
                    tint: .green
                )
            }

            if let activeInfo = versionManager.installedVersions.first(where: { $0.version == versionManager.activeVersion }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Minecraft \(activeInfo.version)")
                            .font(.title2.bold())
                            .foregroundStyle(accent)
                        Spacer()
                        Text("\(activeInfo.recipeCount.formatted()) recipes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    // Categories tags
                    if !activeInfo.categories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(activeInfo.categories, id: \.self) { cat in
                                    Label(cat, systemImage: DataManager.categorySymbol(for: cat))
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(accent.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text("No active recipe version selected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Quick Version Picker if multiple versions installed
            if versionManager.installedVersions.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Switch Active Version:")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Active Version", selection: Binding(
                        get: { versionManager.activeVersion },
                        set: { newVersion in
                            switchActiveVersion(to: newVersion)
                        }
                    )) {
                        ForEach(versionManager.installedVersions) { info in
                            Text("Minecraft \(info.version) (\(info.recipeCount) recipes)").tag(info.version)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(accent)
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(18)
        .craftifyCard(cornerRadius: 22)
    }

    private var importActionBar: some View {
        VStack(spacing: 12) {
            Button {
                HapticFeedback.selection()
                showingFilePicker = true
            } label: {
                Label("Import .recipe File", systemImage: "square.and.arrow.down.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .craftifyButtonBorder(cornerRadius: 16)

            if let message = statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isErrorMessage ? Color.orange : Color.green)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(isErrorMessage ? Color.orange : Color.primary)
                    Spacer()
                }
                .padding(10)
                .background(
                    (isErrorMessage ? Color.orange : Color.green).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .transition(.opacity)
            }
        }
    }

    private var installedVersionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            CraftifySectionHeader(
                title: "Installed Versions (\(versionManager.installedVersions.count))",
                detail: "Tap any version to activate it or manage files."
            )

            ForEach(versionManager.installedVersions) { info in
                versionRow(info)
            }
        }
    }

    private func versionRow(_ info: RecipeVersionInfo) -> some View {
        let isActive = info.version == versionManager.activeVersion

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CraftifyIconTile(
                    symbol: isActive ? "checkmark.circle.fill" : "book.closed.fill",
                    size: 42
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Minecraft \(info.version)")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isActive {
                            CraftifyStatusPill(title: "Active", symbol: "checkmark", tint: .green)
                        } else if info.isDefault {
                            CraftifyStatusPill(title: "Default", symbol: "star.fill", tint: .secondary)
                        }
                    }

                    Text(info.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    if !isActive {
                        Button {
                            switchActiveVersion(to: info.version)
                        } label: {
                            Label("Set as Active", systemImage: "checkmark.circle")
                        }
                    }

                    if let exportURL = versionManager.exportFileURL(for: info.version) {
                        ShareLink(item: exportURL) {
                            Label("Share / Export .recipe", systemImage: "square.and.arrow.up")
                        }
                    }

                    if versionManager.installedVersions.count > 1 {
                        Button(role: .destructive) {
                            versionToDelete = info.version
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Version", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                        .padding(4)
                }
            }

            if !isActive {
                Button {
                    switchActiveVersion(to: info.version)
                } label: {
                    Text("Switch to this version")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .craftifyCard(cornerRadius: 18)
    }

    // MARK: - Actions

    private func switchActiveVersion(to newVersion: String) {
        HapticFeedback.selection()
        versionManager.activeVersion = newVersion
        dataManager.reloadRecipesFromActiveVersion()
        statusMessage = "Switched to Minecraft \(newVersion)."
        isErrorMessage = false
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let outcome = versionManager.prepareImport(from: url)
            switch outcome {
            case .success(let info):
                HapticFeedback.notification(.success)
                statusMessage = "Successfully imported Minecraft \(info.version) (\(info.recipeCount) recipes)!"
                isErrorMessage = false
                dataManager.reloadRecipesFromActiveVersion()

            case .duplicate(let existing, let package, let rawData):
                HapticFeedback.notification(.warning)
                duplicateExistingInfo = existing
                pendingDuplicatePackage = package
                pendingDuplicateRawData = rawData
                showingDuplicateDialog = true

            case .failure(let error):
                HapticFeedback.notification(.error)
                statusMessage = error
                isErrorMessage = true
            }

        case .failure(let error):
            statusMessage = "Import failed: \(error.localizedDescription)"
            isErrorMessage = true
        }
    }

    private func resolveDuplicate(with resolution: DuplicateResolution) {
        guard let package = pendingDuplicatePackage,
              let rawData = pendingDuplicateRawData else { return }

        let outcome = versionManager.resolveDuplicate(
            package: package,
            rawData: rawData,
            resolution: resolution
        )

        switch outcome {
        case .success(let info):
            HapticFeedback.notification(.success)
            statusMessage = "Imported Minecraft \(info.version) (\(resolution.title))!"
            isErrorMessage = false
            dataManager.reloadRecipesFromActiveVersion()

        case .duplicate:
            break

        case .failure(let error):
            statusMessage = error
            isErrorMessage = true
        }

        pendingDuplicatePackage = nil
        pendingDuplicateRawData = nil
        duplicateExistingInfo = nil
    }

    private func deleteVersion(_ ver: String) {
        HapticFeedback.notification(.success)
        versionManager.deleteVersion(ver)
        dataManager.reloadRecipesFromActiveVersion()
        statusMessage = "Deleted version \(ver)."
        isErrorMessage = false
        versionToDelete = nil
    }
}
