//
//  MenuBarAppearanceManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// A manager for the appearance of the menu bar.
@MainActor
final class MenuBarAppearanceManager: ObservableObject {
    /// The current menu bar appearance configuration.
    @Published var configuration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration

    /// The currently previewed partial configuration.
    @Published var previewConfiguration: MenuBarAppearancePartialConfiguration?

    /// The shared app state.
    private weak var appState: AppState?

    /// Encoder for UserDefaults values.
    private let encoder = JSONEncoder()

    /// Decoder for UserDefaults values.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The currently managed menu bar overlay panels.
    private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    /// The amount to inset the menu bar if called for by the configuration.
    let menuBarInsetAmount: CGFloat = 3.5

    /// Performs initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the initial values for the configuration.
    private func loadInitialState() {
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            }
        } catch {
            Logger.serialization.error("Error decoding menu bar appearance configuration: \(error)")
        }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                while let panel = overlayPanels.popFirst() {
                    panel.close()
                }
                configureOverlayPanels(with: configuration, previewConfiguration: previewConfiguration)
            }
            .store(in: &c)

        $configuration
            .encode(encoder: encoder)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.serialization.error("Error encoding menu bar appearance configuration: \(error)")
                }
            } receiveValue: { data in
                Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
            }
            .store(in: &c)

        Publishers.CombineLatest($configuration, $previewConfiguration)
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] configuration, previewConfiguration in
                self?.configureOverlayPanels(with: configuration, previewConfiguration: previewConfiguration)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Configures the manager's overlay panels, if required by the given configuration.
    private func configureOverlayPanels(
        with configuration: MenuBarAppearanceConfigurationV2,
        previewConfiguration: MenuBarAppearancePartialConfiguration? = nil
    ) {
        guard
            let appState,
            configuration.needsOverlayPanels(with: previewConfiguration)
        else {
            while let panel = overlayPanels.popFirst() {
                panel.close()
            }
            return
        }

        let screens = NSScreen.screens
        guard Set(overlayPanels.map(\.owningScreen)) != Set(screens) else {
            return
        }

        while let panel = overlayPanels.popFirst() {
            panel.close()
        }

        var overlayPanels = Set<MenuBarOverlayPanel>()
        for screen in screens {
            let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen)
            overlayPanels.insert(panel)
            panel.needsShow = true
        }

        self.overlayPanels = overlayPanels
    }
}
