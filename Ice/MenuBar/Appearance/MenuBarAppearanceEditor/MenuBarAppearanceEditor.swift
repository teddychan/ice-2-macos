//
//  MenuBarAppearanceEditor.swift
//  Ice
//

import DragonKit
import SwiftUI

struct MenuBarAppearanceEditor: View {
    enum Location {
        case settings
        case panel
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var appearanceManager: MenuBarAppearanceManager
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isResetPromptPresented = false

    let location: Location

    var body: some View {
        bodyContent
            .safeAreaBar(edge: .bottom, spacing: 0) {
                bottomBar
            }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotEdit
        } else {
            mainForm
                .scrollEdgeEffectStyle(.hard, for: .vertical)
        }
    }

    @ViewBuilder
    private var cannotEdit: some View {
        Text(L("app.appearance.cannotEdit"))
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var mainForm: some View {
        DragonForm {
            if
                case .settings = location,
                appState.settings.advanced.enableSecondaryContextMenu
            {
                CalloutBox(
                    L("app.appearance.tip.callout"),
                    systemImage: "lightbulb"
                )
            }
            if case .settings = location, appState.settings.general.showIceIcon {
                MenuBarIconSettings(settings: appState.settings.general)
            }
            DragonSection {
                isDynamicToggle
                removesMenuBarBackgroundToggle
                roundsScreenCornersToggle
            }
            if appearanceManager.configuration.isDynamic {
                LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .light)
                LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .dark)
            } else {
                StaticPartialEditor(configuration: $appearanceManager.configuration)
            }
            DragonSection {
                Text(L("app.appearance.section.menuBarShape"))
            } content: {
                shapePicker
                isInset
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if case .panel = location {
                Button(L("app.common.done")) {
                    dismissWindow()
                }
            }

            Spacer()

            if
                !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                appearanceManager.configuration != .defaultConfiguration
            {
                Button(L("app.common.reset")) {
                    isResetPromptPresented = true
                }
                .alert(L("app.appearance.reset.title"), isPresented: $isResetPromptPresented) {
                    Button(L("DragonKit.cancel"), role: .cancel) {
                        isResetPromptPresented = false
                    }
                    Button(L("app.common.reset"), role: .destructive) {
                        appearanceManager.configuration = .defaultConfiguration
                        isResetPromptPresented = false
                    }
                } message: {
                    Text(L("app.appearance.reset.message"))
                }
            }
        }
        .buttonBorderShape(.capsule)
        .padding(10)
    }

    @ViewBuilder
    private var isDynamicToggle: some View {
        Toggle(L("app.appearance.useDynamic"), isOn: $appearanceManager.configuration.isDynamic)
            .dragonAnnotation { Text(L("app.appearance.useDynamic.note")) }
    }

    @ViewBuilder
    private var removesMenuBarBackgroundToggle: some View {
        if NativeMenuBarManager.usesNativeBackend {
            Text(L("app.appearance.removeBackground.native"))
        } else {
            Toggle(L("app.appearance.removeBackground"), isOn: $appearanceManager.configuration.removesMenuBarBackground)
        }
    }

    @ViewBuilder
    private var roundsScreenCornersToggle: some View {
        Toggle(L("app.appearance.roundCorners"), isOn: $appearanceManager.configuration.roundsScreenCorners)
    }

    @ViewBuilder
    private var shapePicker: some View {
        MenuBarShapePicker(configuration: $appearanceManager.configuration)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var isInset: some View {
        if appearanceManager.configuration.shapeKind != .noShape {
            Toggle(
                L("app.appearance.insetShape"),
                isOn: $appearanceManager.configuration.isInset
            )
        }
    }
}

/// The "Menu Bar Icon" chooser, shown in the Appearance settings pane when the Ice 2 icon is visible.
private struct MenuBarIconSettings: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: GeneralSettings
    @State private var isImportingCustomIceIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?

    var body: some View {
        DragonSection {
            Text(L("app.appearance.section.menuBarIcon"))
        } content: {
            iceIconPicker
        }
    }

    @ViewBuilder
    private var iceIconPicker: some View {
        let label = L("app.appearance.iceIcon")

        IceMenu(label) {
            Picker(label, selection: $settings.iceIcon) {
                ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                    Button {
                        settings.iceIcon = imageSet
                    } label: {
                        iceIconMenuItem(for: imageSet)
                    }
                    .tag(imageSet)
                }
                if let lastCustomIceIcon = settings.lastCustomIceIcon {
                    Button {
                        settings.iceIcon = lastCustomIceIcon
                    } label: {
                        iceIconMenuItem(for: lastCustomIceIcon)
                    }
                    .tag(lastCustomIceIcon)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button(L("app.appearance.chooseImage")) {
                isImportingCustomIceIcon = true
            }
        } title: {
            iceIconMenuItem(for: settings.iceIcon)
        }
        .dragonAnnotation { Text(L("app.appearance.iceIcon.note")) }
        .fileImporter(
            isPresented: $isImportingCustomIceIcon,
            allowedContentTypes: [.image]
        ) { result in
            do {
                let url = try result.get()
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    settings.iceIcon = ControlItemImageSet(name: .custom, image: .data(data))
                }
            } catch {
                presentedError = LocalizedErrorWrapper(error)
                isPresentingError = true
            }
        }
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button(L("DragonKit.ok")) {
                presentedError = nil
                isPresentingError = false
            }
        }

        if case .custom = settings.iceIcon.name {
            Toggle(L("app.appearance.customIconDynamic"), isOn: $settings.customIceIconIsTemplate)
                .dragonAnnotation {
                    Text(L("app.appearance.customIconDynamic.note"))
                        .padding(.trailing, 50)
                }
        }
    }

    @ViewBuilder
    private func iceIconMenuItem(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.localized)
        } icon: {
            if let nsImage = imageSet.hidden.nsImage(for: appState) {
                switch imageSet.name {
                case .custom:
                    Image(size: CGSize(width: 18, height: 18)) { context in
                        context.draw(Image(nsImage: nsImage), in: context.clipBoundingRect)
                    }
                default:
                    Image(nsImage: nsImage)
                }
            }
        }
    }
}

private struct UnlabeledPartialEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration

    var body: some View {
        DragonSection {
            tintPicker
            shadowToggle
        }
        DragonSection {
            borderToggle
            borderColor
            borderWidth
        }
    }

    @ViewBuilder
    private var tintPicker: some View {
        LabeledContent(L("app.appearance.tint")) {
            HStack {
                IcePicker(L("app.appearance.tint"), selection: $configuration.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch configuration.tintKind {
                case .noTint:
                    EmptyView()
                case .solid:
                    ColorPicker(
                        configuration.tintKind.localized,
                        selection: $configuration.tintColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                case .gradient:
                    IceGradientPicker(
                        configuration.tintKind.localized,
                        gradient: $configuration.tintGradient,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var shadowToggle: some View {
        Toggle(L("app.appearance.shadow"), isOn: $configuration.hasShadow)
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle(L("app.appearance.border"), isOn: $configuration.hasBorder)
    }

    @ViewBuilder
    private var borderColor: some View {
        if configuration.hasBorder {
            ColorPicker(
                L("app.appearance.borderColor"),
                selection: $configuration.borderColor,
                supportsOpacity: true
            )
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if configuration.hasBorder {
            IcePicker(
                L("app.appearance.borderWidth"),
                selection: $configuration.borderWidth
            ) {
                Text("1").tag(1.0)
                Text("2").tag(2.0)
                Text("3").tag(3.0)
            }
        }
    }
}

private struct LabeledPartialEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2
    @State private var currentAppearance = SystemAppearance.current
    @State private var textFrame = CGRect.zero

    let appearance: SystemAppearance

    var body: some View {
        DragonSection {
            labelStack
        } content: {
            partialEditor
        }
        .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in
            currentAppearance = .current
        }
    }

    @ViewBuilder
    private var labelStack: some View {
        HStack {
            Text(appearance.localized)
                .font(.headline)
                .onFrameChange(update: $textFrame)

            if currentAppearance != appearance {
                PreviewButton(appearance: appearance)
            }
        }
        .frame(height: textFrame.height)
    }

    @ViewBuilder
    private var partialEditor: some View {
        switch appearance {
        case .light:
            UnlabeledPartialEditor(configuration: $configuration.lightModeConfiguration)
        case .dark:
            UnlabeledPartialEditor(configuration: $configuration.darkModeConfiguration)
        }
    }
}

private struct StaticPartialEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        UnlabeledPartialEditor(configuration: $configuration.staticConfiguration)
    }
}

private struct PreviewButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPressed = false

    let appearance: SystemAppearance

    private var manager: MenuBarAppearanceManager {
        appState.appearanceManager
    }

    private var previewConfiguration: MenuBarAppearancePartialConfiguration {
        switch appearance {
        case .light:
            manager.configuration.lightModeConfiguration
        case .dark:
            manager.configuration.darkModeConfiguration
        }
    }

    var body: some View {
        Button(L("app.appearance.holdToPreview")) { }
            .buttonStyle(PreviewButtonStyle(isPressed: $isPressed))
            .onChange(of: isPressed) {
                manager.previewConfiguration = isPressed ? previewConfiguration : nil
            }
    }
}

private struct PreviewButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    private var borderShape: some InsettableShape {
        AnyInsettableShape(Capsule(style: .continuous))
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(configuration.isPressed ? 0.5 : 0.75)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
