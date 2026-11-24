//
//  MenuBarIconSettings.swift
//  Ice
//

import DragonKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarIconSettings: View {
    @Bindable var model: SettingsModel
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("app.icon.title"), selection: $model.menuBarIconChoice) {
                ForEach(MenuBarIconChoice.allCases.filter {
                    $0 != .custom || model.settings.menuBarIcon.customPNG != nil
                }, id: \.self) { choice in
                    HStack {
                        icon(choice: choice)
                        Text(L(choice.titleKey))
                    }
                    .tag(choice)
                }
            }
            if model.menuBarIconChoice.supportsColor {
                Picker(L("app.icon.appearance"), selection: $model.menuBarIconUsesOriginalColors) {
                    Text(L("app.icon.automatic")).tag(false)
                    Text(L("app.icon.original")).tag(true)
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text(L("app.icon.preview"))
                Spacer()
                preview(dark: false)
                preview(dark: true)
                Button(L("app.icon.import")) { importing = true }
            }
            Text(L("app.icon.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try model.importMenuBarIcon(from: url)
            } catch let error as MenuBarIconImportError {
                importError = L(error.messageKey)
            } catch {
                importError = L("app.icon.error.read")
            }
        }
        .alert(L("app.icon.error.title"), isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button(L("DragonKit.ok"), role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func icon(choice: MenuBarIconChoice) -> some View {
        var configuration = model.settings.menuBarIcon
        configuration.selection = choice.rawValue
        let image = MenuBarIconRenderer.image(for: configuration)
        return Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    private func preview(dark: Bool) -> some View {
        icon(choice: model.menuBarIconChoice)
            .foregroundStyle(dark ? Color.white : Color.black)
            .frame(width: 40, height: 28)
            .background(dark ? Color(white: 0.12) : Color(white: 0.95), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.gray.opacity(0.3)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L(dark ? "app.icon.preview.dark" : "app.icon.preview.light"))
    }
}
