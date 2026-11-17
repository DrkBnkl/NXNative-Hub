import Foundation
import GameController
import Combine
import AppKit

// MARK: - Gamepad / Controller Support for NXNative Hub
//
// Supports navigation and game control via Nintendo Switch Pro Controller,
// Joy-Cons, Xbox, PlayStation DualShock/DualSense and MFi controllers using
// Apple's GameController framework.

enum GamepadDirection: String {
    case up
    case down
    case left
    case right
}

enum GamepadButton: String {
    case a             // Primary / Launch game
    case b             // Back / Cancel / Dismiss sheet
    case x             // Secondary / Game Settings
    case y             // Tertiary / Game Status & Recompile
    case leftShoulder  // LB / L1: Previous filter / size
    case rightShoulder // RB / R1: Next filter / size
    case leftTrigger   // LT / L2: Toggle view mode
    case rightTrigger  // RT / R2: Toggle view mode
    case menu          // Menu / Options / Pause
}

final class GamepadManager: ObservableObject {
    static let shared = GamepadManager()

    @Published var isConnected: Bool = false
    @Published var controllerName: String = ""

    /// Stream of direction presses (including debounced repeats).
    let directionSubject = PassthroughSubject<GamepadDirection, Never>()

    /// Stream of button presses.
    let buttonSubject = PassthroughSubject<GamepadButton, Never>()

    private var activeDirection: GamepadDirection?
    private var repeatTimer: Timer?
    private var stickDirection: GamepadDirection?
    private var dpadDirection: GamepadDirection?

    init() {
        setupNotifications()
        refreshControllers()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let controller = note.object as? GCController {
                self?.handleControllerConnected(controller)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleControllerDisconnected()
        }
    }

    func refreshControllers() {
        let controllers = GCController.controllers()
        for controller in controllers {
            configure(controller: controller)
        }
        updateConnectionState(controllers)
    }

    private func handleControllerConnected(_ controller: GCController) {
        configure(controller: controller)
        updateConnectionState(GCController.controllers())
    }

    private func handleControllerDisconnected() {
        updateConnectionState(GCController.controllers())
    }

    private func updateConnectionState(_ controllers: [GCController]) {
        let connected = !controllers.isEmpty
        self.isConnected = connected
        if let first = controllers.first {
            self.controllerName = first.vendorName ?? tr("Gamepad", "Gamepad")
        } else {
            self.controllerName = ""
        }
    }

    private func configure(controller: GCController) {
        controller.handlerQueue = .main

        if let extended = controller.extendedGamepad {
            // Direction Pad
            extended.dpad.valueChangedHandler = { [weak self] _, x, y in
                self?.handleDpadInput(x: x, y: y)
            }

            // Left Stick
            extended.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
                self?.handleStickInput(x: x, y: y)
            }

            // Buttons
            extended.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.a) }
            }
            extended.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.b) }
            }
            extended.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.x) }
            }
            extended.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.y) }
            }

            // Shoulders & Triggers
            extended.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.leftShoulder) }
            }
            extended.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.rightShoulder) }
            }
            extended.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.leftTrigger) }
            }
            extended.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.rightTrigger) }
            }

            // Menu / Options
            extended.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.menu) }
            }
            extended.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.menu) }
            }
        } else if let micro = controller.microGamepad {
            micro.dpad.valueChangedHandler = { [weak self] _, x, y in
                self?.handleDpadInput(x: x, y: y)
            }
            micro.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.a) }
            }
            micro.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.triggerButton(.x) }
            }
        }
    }

    private func handleDpadInput(x: Float, y: Float) {
        dpadDirection = resolveDirection(x: x, y: y)
        updateCombinedDirection()
    }

    private func handleStickInput(x: Float, y: Float) {
        stickDirection = resolveDirection(x: x, y: y)
        updateCombinedDirection()
    }

    private func resolveDirection(x: Float, y: Float) -> GamepadDirection? {
        let deadzone: Float = 0.45
        if abs(x) < deadzone && abs(y) < deadzone {
            return nil
        }
        if abs(x) >= abs(y) {
            return x > 0 ? .right : .left
        } else {
            return y > 0 ? .up : .down
        }
    }

    private func updateCombinedDirection() {
        let newDirection = dpadDirection ?? stickDirection
        guard newDirection != activeDirection else { return }

        activeDirection = newDirection
        repeatTimer?.invalidate()
        repeatTimer = nil

        guard let dir = newDirection else { return }

        // Trigger immediately on press
        triggerDirection(dir)

        // Schedule repeat (initial delay 0.35s, then every 0.12s)
        let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self = self, self.activeDirection == dir else { return }
            self.triggerDirection(dir)
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                guard let self = self, self.activeDirection == dir else {
                    self?.repeatTimer?.invalidate()
                    self?.repeatTimer = nil
                    return
                }
                self.triggerDirection(dir)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func triggerDirection(_ direction: GamepadDirection) {
        // Do not process gamepad navigation while NXNative Hub is in the background
        // (e.g. while a launched game is running and frontmost).
        guard NSApplication.shared.isActive else { return }
        directionSubject.send(direction)
    }

    private func triggerButton(_ button: GamepadButton) {
        guard NSApplication.shared.isActive else { return }
        buttonSubject.send(button)
    }
}
