//
//  RecipeExtractorView.swift
//  Craftify
//
//  Created by Dave Van Cauwenberghe on 07/02/2025.
//  macOS / iOS interactive UI for extracting recipes from Minecraft server.jar
//

import SwiftUI
import UniformTypeIdentifiers

struct RecipeExtractorView: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.craftifyAccentColor) private var accent
    @ObservedObject private var extractor = RecipeExtractorService.shared
    @ObservedObject private var versionManager = RecipeVersionManager.shared

    @State private var selectedJarURL: URL?
    @State private var showingFilePicker = false
    @State private var customVersion: String = ""
    @State private var useDataGenerator: Bool = true
    @State private var importStatus: String?
    @State private var showingDuplicateDialog = false
    @State private var pendingPackage: RecipePackage?
    @State private var pendingRawData: Data?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                CraftifyHero(
                    eyebrow: "macOS Extraction Tool",
                    title: "Recipe Extractor",
                    detail: "Extract full Minecraft recipes directly from server.jar using Java data generator (\"net.minecraft.data.Main --reports --all\") or direct jar extraction.",
                    symbol: "hammer.fill"
                )

                configurationCard

                if extractor.isExtracting || !extractor.consoleLogs.isEmpty {
                    consoleCard
                }

                if let pkg = extractor.generatedRecipePackage {
                    resultCard(pkg)
                }
            }
            .craftifyContentWidth()
            .padding(.horizontal, CraftifyLayout.pagePadding(for: horizontalSizeClass))
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .navigationTitle("Recipe Extractor")
        .navigationBarTitleDisplayMode(.large)
        .craftifyPage()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "jar") ?? .data,
                .data
            ],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedJarURL = url
                if customVersion.isEmpty {
                    customVersion = detectVersion(from: url.lastPathComponent)
                }
            }
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
            if let ver = pendingPackage?.gameVersion {
                Text("Version \"\(ver)\" already exists in Craftify. Choose an action:\n版本号「\(ver)」已存在，请选择操作：")
            }
        }
    }

    // MARK: - Configuration Card

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CraftifySectionHeader(
                title: "Minecraft Jar Source",
                detail: "Choose a server.jar or client jar to extract recipes from."
            )

            // Jar Picker
            Button {
                showingFilePicker = true
            } label: {
                HStack(spacing: 12) {
                    CraftifyIconTile(symbol: "doc.zipper", size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedJarURL?.lastPathComponent ?? "Select server.jar")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(selectedJarURL?.path ?? "Click to browse local files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.title3)
                        .foregroundStyle(accent)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Version Name field
            VStack(alignment: .leading, spacing: 6) {
                Text("Minecraft Version Identifier:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. 1.21.4", text: $customVersion)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            // Data Generator Toggle
            Toggle(isOn: $useDataGenerator) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run Official Data Generator")
                        .font(.subheadline.weight(.semibold))
                    Text("Executes \"java -DbundlerRepoDir=. -cp server.jar net.minecraft.data.Main --reports --all\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(accent)

            // Java info pill
            if let javaPath = extractor.findJavaExecutable() {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Detected Java: \(URL(fileURLWithPath: javaPath).deletingLastPathComponent().deletingLastPathComponent().lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Java runtime not found. Built-in direct extraction will be used.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Extract Button
            Button {
                startExtraction()
            } label: {
                Label(
                    extractor.isExtracting ? "Extracting Recipes…" : "Extract Recipes & Create .recipe",
                    systemImage: extractor.isExtracting ? "hourglass" : "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .craftifyButtonBorder(cornerRadius: 16)
            .disabled(selectedJarURL == nil || extractor.isExtracting)
        }
        .padding(18)
        .craftifyCard(cornerRadius: 22)
    }

    // MARK: - Console Log Card

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Extraction Console", systemImage: "terminal.fill")
                    .font(.headline)
                Spacer()
                if extractor.isExtracting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if extractor.isExtracting {
                ProgressView(value: extractor.progress, total: 1.0)
                    .tint(accent)
                Text(extractor.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(extractor.consoleLogs)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 160)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .craftifyCard(cornerRadius: 20)
    }

    // MARK: - Result Card

    private func resultCard(_ pkg: RecipePackage) -> some View {
        let bundledIcons = pkg.iconCount ?? pkg.icons?.count ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CraftifyIconTile(symbol: "checkmark.seal.fill", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Package Created: Minecraft \(pkg.gameVersion)")
                        .font(.headline)
                    Text("\(pkg.recipeCount.formatted()) recipes • \(bundledIcons.formatted()) version-isolated icons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CraftifyStatusPill(title: "Ready", symbol: "sparkles", tint: .green)
            }

            HStack(spacing: 12) {
                Button {
                    importIntoCraftify(pkg)
                } label: {
                    Label("Import into Craftify", systemImage: "arrow.down.doc.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .craftifyButtonBorder(cornerRadius: 14)

                if let outURL = extractor.outputFileURL {
                    ShareLink(item: outURL) {
                        Label("Share / Save", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .craftifyButtonBorder(cornerRadius: 14)
                }
            }

            if let status = importStatus {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(accent)
            }
        }
        .padding(18)
        .craftifyCard(cornerRadius: 22)
    }

    // MARK: - Actions

    private func startExtraction() {
        guard let url = selectedJarURL else { return }
        HapticFeedback.selection()
        importStatus = nil
        Task {
            await extractor.extractRecipes(
                from: url,
                customVersion: customVersion.isEmpty ? nil : customVersion,
                useDataGenerator: useDataGenerator
            )
        }
    }

    private func importIntoCraftify(_ pkg: RecipePackage) {
        guard let outURL = extractor.outputFileURL else { return }
        let outcome = versionManager.prepareImport(from: outURL)
        switch outcome {
        case .success(let info):
            HapticFeedback.notification(.success)
            importStatus = "Successfully imported Minecraft \(info.version)!"
            dataManager.reloadRecipesFromActiveVersion()

        case .duplicate(_, let package, let rawData):
            HapticFeedback.notification(.warning)
            pendingPackage = package
            pendingRawData = rawData
            showingDuplicateDialog = true

        case .failure(let error):
            importStatus = "Import failed: \(error)"
        }
    }

    private func resolveDuplicate(with resolution: DuplicateResolution) {
        guard let pkg = pendingPackage, let data = pendingRawData else { return }
        let outcome = versionManager.resolveDuplicate(
            package: pkg,
            rawData: data,
            resolution: resolution
        )
        switch outcome {
        case .success(let info):
            HapticFeedback.notification(.success)
            importStatus = "Imported Minecraft \(info.version) (\(resolution.title))!"
            dataManager.reloadRecipesFromActiveVersion()
        case .duplicate, .failure:
            break
        }
        pendingPackage = nil
        pendingRawData = nil
    }

    private func detectVersion(from filename: String) -> String {
        let range = NSRange(location: 0, length: filename.utf16.count)
        let regex = try? NSRegularExpression(pattern: #"(\d+\.\d+(\.\d+)?)"#)
        if let match = regex?.firstMatch(in: filename, options: [], range: range),
           let r = Range(match.range(at: 1), in: filename) {
            return String(filename[r])
        }
        return "1.21.1"
    }
}
