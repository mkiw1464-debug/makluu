import UIKit
import AVKit
import AVFoundation
import CoreMotion

// MARK: - FOVOverlayManager
//
// FOV circle overlay using Picture-in-Picture (PiP).
// Works on NON-JAILBREAK device — iOS 16/17/18/26.
// PiP window is managed by iOS WindowServer, floats above ALL apps including Free Fire.
// No jailbreak needed. Works with TrollStore / sideloaded IPA.
//
// Approach:
//   1. Create a silent 1x1 AVPlayerLayer (required to activate PiP)
//   2. Layer a custom FOVCircleView on top of the PiP window
//      via AVPictureInPictureVideoCallViewController (iOS 15+)
//   3. PiP window floats above Free Fire, fully interactive pass-through
//   4. Shake device to toggle visibility

final class FOVOverlayManager: NSObject {

    // MARK: - Shared
    static let shared = FOVOverlayManager()

    // MARK: - State
    private var pipController:    AVPictureInPictureController?
    private var pipViewController: AVPictureInPictureVideoCallViewController?
    private var circleHostVC:     CircleHostViewController?
    private var bgTaskID:         UIBackgroundTaskIdentifier = .invalid
    private let motionManager     = CMMotionManager()
    private(set) var isActive     = false
    private(set) var radius:      Int = 100

    // MARK: - Start

    func start(radius: Int, settings: CheatSettings) {
        self.radius = max(0, min(200, radius))
        setupPiP()
        keepAlive()
        listenForShake()
        isActive = true
        log("FOVOverlay: started via PiP — radius=\(self.radius)")
    }

    // MARK: - Stop

    func stop() {
        pipController?.stopPictureInPicture()
        pipController    = nil
        pipViewController = nil
        circleHostVC     = nil
        motionManager.stopAccelerometerUpdates()
        endKeepAlive()
        isActive = false
        log("FOVOverlay: stopped")
    }

    // MARK: - Update radius (live — while Lo is in-game)

    func setRadius(_ newRadius: Int, settings: CheatSettings, game: FFGame) {
        radius = max(0, min(200, newRadius))
        DispatchQueue.main.async { [weak self] in
            self?.circleHostVC?.setRadius(CGFloat(newRadius))
        }
        // Rewrite localConfig.json in FF container so __q17 updates live
        Task {
            guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: game.bundleID)
            else { return }
            let handle = ContainerStore.grantContainerAccess(containerPath)
            defer { if handle >= 0 { bad_query_release(handle) } }
            let docsURL = URL(fileURLWithPath: containerPath).appendingPathComponent("Documents")
            let lcURL   = docsURL.appendingPathComponent("localConfig.json")
            guard let lcData = SecurityBind.generateLocalConfig(settings: settings) else { return }
            let tmp = docsURL.appendingPathComponent(".\(UUID().uuidString)")
            FileManager.default.createFile(atPath: tmp.path, contents: lcData)
            rename(tmp.path, lcURL.path)
        }
    }

    // MARK: - PiP Setup

    private func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            log("FOVOverlay: PiP not supported — fallback to UIWindow")
            fallbackUIWindow()
            return
        }

        // iOS 15+ VideoCallViewController approach
        // Lets us put ANY view inside PiP window
        let callVC = AVPictureInPictureVideoCallViewController()
        callVC.preferredContentSize = CGSize(width: 240, height: 240)

        let circleVC = CircleHostViewController()
        circleVC.setRadius(CGFloat(radius))
        callVC.addChild(circleVC)
        callVC.view.addSubview(circleVC.view)
        circleVC.view.frame = callVC.view.bounds
        circleVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        circleVC.didMove(toParent: callVC)

        self.pipViewController = callVC
        self.circleHostVC      = circleVC

        // Create controller
        let controller = AVPictureInPictureController(contentSource:
            AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: circleVC.view,
                contentViewController:    callVC
            )
        )
        controller.delegate                   = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller

        // Start PiP
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            controller.startPictureInPicture()
        }
    }

    // MARK: - Fallback (jailbreak / TrollStore with elevated WindowLevel)

    private func fallbackUIWindow() {
        let screen = UIScreen.main.bounds
        let win    = UIWindow(frame: screen)
        win.windowLevel              = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 999)
        win.backgroundColor          = .clear
        win.isUserInteractionEnabled = false
        win.isHidden                 = false

        let vc        = UIViewController()
        vc.view.frame = screen
        vc.view.backgroundColor = .clear
        win.rootViewController = vc

        let circleVC = CircleHostViewController()
        circleVC.setRadius(CGFloat(radius))
        vc.addChild(circleVC)
        vc.view.addSubview(circleVC.view)
        circleVC.view.frame = screen
        circleVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        circleVC.didMove(toParent: vc)

        self.circleHostVC = circleVC
        win.makeKeyAndVisible()

        // Store window reference to prevent dealloc
        objc_setAssociatedObject(self, &AssociatedKeys.fallbackWindow, win, .OBJC_ASSOCIATION_RETAIN)
    }

    // MARK: - Keep alive

    private func keepAlive() {
        endKeepAlive()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "FFExtFOVKeepAlive") {
            [weak self] in self?.keepAlive()
        }
    }

    private func endKeepAlive() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
    }

    // MARK: - Shake to toggle

    private func listenForShake() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.08
        var lastShake = Date.distantPast

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let d = data else { return }
            let magnitude = abs(d.acceleration.x) + abs(d.acceleration.y) + abs(d.acceleration.z)
            if magnitude > 2.8 && Date().timeIntervalSince(lastShake) > 1.0 {
                lastShake = Date()
                self?.toggleVisibility()
            }
        }
    }

    private func toggleVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let newAlpha: CGFloat = (self.circleHostVC?.view.alpha ?? 1.0) > 0.5 ? 0.0 : 1.0
            UIView.animate(withDuration: 0.2) {
                self.circleHostVC?.view.alpha = newAlpha
            }
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension FOVOverlayManager: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        log("FOVOverlay: PiP starting")
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        log("FOVOverlay: PiP active ✓")
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        log("FOVOverlay: PiP failed (\(error.localizedDescription)) — trying fallback")
        fallbackUIWindow()
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        // Auto restart if Lo closed it manually
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isActive else { return }
            controller.startPictureInPicture()
        }
    }
}

// MARK: - Associated Keys

private enum AssociatedKeys {
    static var fallbackWindow = "fallbackWindow"
}

// MARK: - CircleHostViewController

final class CircleHostViewController: UIViewController {

    private let shapeLayer  = CAShapeLayer()
    private let dotLayer    = CAShapeLayer()
    private var currentR:   CGFloat = 100

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque        = false
        view.isUserInteractionEnabled = false
        setupLayers()
        setRadius(currentR)
    }

    private func setupLayers() {
        // Main dashed circle
        shapeLayer.fillColor       = UIColor.clear.cgColor
        shapeLayer.strokeColor     = UIColor.white.withAlphaComponent(0.90).cgColor
        shapeLayer.lineWidth       = 1.8
        shapeLayer.lineDashPattern = [7, 5]
        shapeLayer.shadowColor     = UIColor.black.cgColor
        shapeLayer.shadowRadius    = 4
        shapeLayer.shadowOpacity   = 0.70
        shapeLayer.shadowOffset    = .zero
        view.layer.addSublayer(shapeLayer)

        // Center dot
        dotLayer.fillColor   = UIColor.white.withAlphaComponent(0.95).cgColor
        dotLayer.strokeColor = UIColor(white: 0, alpha: 0.4).cgColor
        dotLayer.lineWidth   = 0.8
        view.layer.addSublayer(dotLayer)
    }

    func setRadius(_ r: CGFloat) {
        currentR = max(4, r)
        guard isViewLoaded else { return }
        redraw()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)

        // Simple solid circle — nothing else
        let path = UIBezierPath(
            arcCenter: center,
            radius:    currentR,
            startAngle: 0,
            endAngle:   .pi * 2,
            clockwise:  true
        )
        shapeLayer.path  = path.cgPath
        shapeLayer.frame = view.bounds

        CATransaction.commit()
    }
}
