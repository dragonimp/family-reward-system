import AgentIdentity
import AVFoundation
import UIKit
import Vision
import CoreLocation
import ImageIO
import UniformTypeIdentifiers

private enum DearCompositionAdvice: Equatable {
    case looking, clipped, groupBalance, portraitHeight, subjectPlacement, ready

    var text: String {
        switch self {
        case .looking:
            return String(localized: "寻找主体中，可参考九宫格构图", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .clipped:
            return String(localized: "主体太靠边，稍退一步或移动镜头", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .groupBalance:
            return String(localized: "让大家靠近画面中间，两侧留空", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .portraitHeight:
            return String(localized: "移动镜头，让脸部靠近上方三分线", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .subjectPlacement:
            return String(localized: "试着让主体靠近一个九宫格交点", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        case .ready:
            return String(localized: "构图合适，可以拍摄", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        }
    }
}

private struct DearCompositionFrame {
    let boxes: [CGRect]
    let advice: DearCompositionAdvice

    // Coordinates are upright, normalized to the image, with the origin at the top left.
    static func evaluate(people: [CGRect], faces: [CGRect], subject: CGRect?) -> Self {
        let standaloneFaces = faces.filter { face in
            !people.contains { $0.insetBy(dx: -0.02, dy: -0.03).contains(CGPoint(x: face.midX, y: face.midY)) }
        }
        let portraits = people + standaloneFaces
        let boxes = portraits.isEmpty ? subject.map { [$0] } ?? [] : portraits
        guard let first = boxes.first else { return Self(boxes: [], advice: .looking) }
        let bounds = boxes.dropFirst().reduce(first) { $0.union($1) }
        let top = min(bounds.minY, faces.map(\.minY).min() ?? 1)
        let isAtEdge = bounds.minX < 0.035 || bounds.maxX > 0.965 || top < 0.035
        let advice: DearCompositionAdvice
        if isAtEdge || ((portraits.isEmpty || people.isEmpty) && bounds.maxY > 0.965) {
            advice = .clipped
        } else if portraits.count > 1 || faces.count > 1 {
            advice = abs(bounds.midX - 0.5) <= 0.14 ? .ready : .groupBalance
        } else if let face = faces.first {
            advice = abs(face.midY - 1 / 3) <= 0.14 ? .ready : .portraitHeight
        } else {
            // The upper-body box usually extends below the face. Its upper portion is
            // a better framing anchor than the box center when the person faces away.
            let anchorY = portraits.isEmpty ? bounds.midY : bounds.minY + bounds.height * 0.22
            let nearX = min(abs(bounds.midX - 1 / 3), abs(bounds.midX - 2 / 3)) <= 0.13
            let nearY = min(abs(anchorY - 1 / 3), abs(anchorY - 2 / 3)) <= 0.13
            advice = nearX && nearY ? .ready : .subjectPlacement
        }
        return Self(boxes: boxes, advice: advice)
    }
}

private final class DearPhotoCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "moment.activity.camera", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let humans = VNDetectHumanRectanglesRequest()
    private let faces = VNDetectFaceRectanglesRequest()
    private let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
    private var input: AVCaptureDeviceInput?
    private var generation = 0
    private var lastAnalysis: CFTimeInterval = 0
    private var photoCompletion: ((Data?) -> Void)?
    private var photoData: Data?
    var onFrame: ((Int, DearCompositionFrame) -> Void)?

    func prepare(_ completion: @escaping (Bool) -> Void) {
        queue.async {
            let prepared = self.configure()
            DispatchQueue.main.async { completion(prepared) }
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canSetSessionPreset(.photo), session.canAddInput(input) else { return false }
        session.sessionPreset = .photo
        session.addInput(input)
        self.input = input
        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)
        guard session.canAddOutput(videoOutput) else { return false }
        humans.upperBodyOnly = true
        videoOutput.alwaysDiscardsLateVideoFrames = true
        session.addOutput(videoOutput)
        return true
    }

    func run(_ running: Bool) {
        queue.async {
            if running, !self.session.isRunning { self.session.startRunning() }
            if !running, self.session.isRunning { self.session.stopRunning() }
        }
    }

    func update(angle: CGFloat, captureAngle: CGFloat, mirrored: Bool, analyze: Bool, generation: Int) {
        queue.async {
            self.generation = generation
            self.lastAnalysis = CACurrentMediaTime()
            self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            for output in [self.videoOutput as AVCaptureOutput, self.photoOutput] {
                guard let connection = output.connection(with: .video) else { continue }
                let rotation = output === self.photoOutput ? captureAngle : angle
                if connection.isVideoRotationAngleSupported(rotation) { connection.videoRotationAngle = rotation }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                }
            }
            if analyze { self.videoOutput.setSampleBufferDelegate(self, queue: self.queue) }
        }
    }

    func switchCamera(_ completion: @escaping (Bool) -> Void) {
        queue.async {
            self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            if let previous = self.input {
                let next: AVCaptureDevice.Position = previous.device.position == .front ? .back : .front
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
                   let replacement = try? AVCaptureDeviceInput(device: device) {
                    self.session.beginConfiguration()
                    self.session.removeInput(previous)
                    if self.session.canAddInput(replacement) {
                        self.session.addInput(replacement)
                        self.input = replacement
                    } else {
                        self.session.addInput(previous)
                    }
                    self.session.commitConfiguration()
                }
            }
            let mirrored = self.input?.device.position == .front
            DispatchQueue.main.async { completion(mirrored) }
        }
    }

    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.input?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
        }
    }

    func zoom(by scale: CGFloat) {
        queue.async {
            guard let device = self.input?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            let limit = min(device.maxAvailableVideoZoomFactor, 8)
            device.videoZoomFactor = min(max(device.videoZoomFactor * scale, device.minAvailableVideoZoomFactor), limit)
        }
    }

    func takePhoto(flash: AVCaptureDevice.FlashMode, _ completion: @escaping (Data?) -> Void) {
        queue.async {
            guard self.session.isRunning, !self.session.isInterrupted,
                  self.photoOutput.connection(with: .video)?.isActive == true else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.photoCompletion = completion
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            if self.photoOutput.supportedFlashModes.contains(flash) { settings.flashMode = flash }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { self.photoData = data }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async {
            let completion = self.photoCompletion
            let data = error == nil ? self.photoData : nil
            self.photoCompletion = nil
            self.photoData = nil
            DispatchQueue.main.async { completion?(data) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastAnalysis >= 0.33, let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastAnalysis = now
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([humans, faces])) != nil else { return }

        let people = (humans.results ?? []).filter { $0.confidence >= 0.5 }.map { Self.imageRect($0.boundingBox) }
        let faceBoxes = (faces.results ?? []).filter { $0.confidence >= 0.5 }.map { Self.imageRect($0.boundingBox) }
        var subject: CGRect?
        if people.isEmpty, faceBoxes.isEmpty, (try? handler.perform([saliency])) != nil,
           let objects = saliency.results?.first?.salientObjects, objects.count == 1, let object = objects.first {
            let rect = Self.imageRect(object.boundingBox)
            if rect.width * rect.height < 0.65 { subject = rect }
        }
        let frame = DearCompositionFrame.evaluate(people: people, faces: faceBoxes, subject: subject)
        let generation = self.generation
        DispatchQueue.main.async { [weak self] in self?.onFrame?(generation, frame) }
    }

    private static func imageRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}

enum DearCaptureGeography {
    static func valid(_ location: CLLocation, at date: Date = Date()) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate) && location.horizontalAccuracy >= 0 &&
            location.horizontalAccuracy <= 100 && abs(location.timestamp.timeIntervalSince(date)) <= 15
    }

    static func tag(_ data: Data, location: CLLocation?) throws -> Data {
        guard let location else { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw CocoaError(.fileReadCorruptFile) }
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude < 0 ? "S" : "N",
            kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude < 0 ? "W" : "E",
            kCGImagePropertyGPSHPositioningError as String: location.horizontalAccuracy
        ]
        if location.verticalAccuracy >= 0, location.altitude.isFinite, (-12000...100000).contains(location.altitude) {
            gps[kCGImagePropertyGPSAltitude as String] = abs(location.altitude)
            gps[kCGImagePropertyGPSAltitudeRef as String] = location.altitude < 0 ? 1 : 0
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd"
        gps[kCGImagePropertyGPSDateStamp as String] = formatter.string(from: location.timestamp)
        formatter.dateFormat = "HH:mm:ss.SSS"
        gps[kCGImagePropertyGPSTimeStamp as String] = formatter.string(from: location.timestamp)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }

    static func location(in url: URL) -> CLLocation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let latitude = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude as String] as? Double else { return nil }
        let lat = gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "S" ? -latitude : latitude
        let lon = gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "W" ? -longitude : longitude
        let altitude = gps[kCGImagePropertyGPSAltitude as String] as? Double
        let signedAltitude = gps[kCGImagePropertyGPSAltitudeRef as String] as? Int == 1 ? -(altitude ?? 0) : altitude ?? 0
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: signedAltitude,
                          horizontalAccuracy: gps[kCGImagePropertyGPSHPositioningError as String] as? Double ?? 100,
                          verticalAccuracy: altitude == nil ? -1 : 0, timestamp: Date())
    }
}

private final class DearCameraLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?
    private var active = false
    var denied: Bool { manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted }
    var changed: (() -> Void)?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }
    func start() {
        active = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: location = nil
        }
        changed?()
    }
    func stop() { active = false; manager.stopUpdatingLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if active { start() } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active else { return }
        location = locations.last(where: { DearCaptureGeography.valid($0) })
        changed?()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        location = nil
        changed?()
    }
}

final class DearPhotoCameraController: UIViewController {
    private let completion: (Result<(URL, Bool)?, Error>) -> Void
    private let recordLocation: Bool
    private let locator = DearCameraLocation()
    private let locationLabel = UILabel()
    private let camera = DearPhotoCapture()
    private lazy var preview = AVCaptureVideoPreviewLayer(session: camera.session)
    private let grid = CAShapeLayer()
    private let outlines = CAShapeLayer()
    private let review = UIImageView()
    private let adviceLabel = UILabel()
    private let shutter = UIButton(type: .system)
    private let switchLens = UIButton(type: .system)
    private let guide = UIButton(type: .system)
    private let flash = UIButton(type: .system)
    private let retake = UIButton(type: .system)
    private let usePhoto = UIButton(type: .system)
    private var ready = false
    private var takingPhoto = false
    private var switching = false
    private var mirrored = false
    private var guideEnabled = true
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private var finished = false
    private var angle: CGFloat = 90
    private var captureAngle: CGFloat = 90
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?
    private var generation = 0
    private var data: Data?
    private var boxes: [CGRect] = []
    private var advice: DearCompositionAdvice = .looking
    private var pendingAdvice: DearCompositionAdvice?
    private var clearStaleFrame: DispatchWorkItem?

    init(recordLocation: Bool = false, completion: @escaping (Result<(URL, Bool)?, Error>) -> Void) {
        self.recordLocation = recordLocation
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.videoGravity = .resizeAspect
        for layer in [preview, grid, outlines] { view.layer.addSublayer(layer) }
        grid.fillColor = nil
        grid.strokeColor = UIColor.white.withAlphaComponent(0.45).cgColor
        grid.lineWidth = 1
        outlines.fillColor = nil
        outlines.lineWidth = 2
        outlines.shadowColor = UIColor.black.cgColor
        outlines.shadowOpacity = 0.75
        outlines.shadowRadius = 2
        outlines.shadowOffset = .zero

        review.contentMode = .scaleAspectFit
        review.backgroundColor = .black
        review.isHidden = true
        view.addSubview(review)
        review.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            review.topAnchor.constraint(equalTo: view.topAnchor), review.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            review.leadingAnchor.constraint(equalTo: view.leadingAnchor), review.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let cancel = UIButton(type: .system)
        configure(cancel, String(localized: "取消", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), icon: "xmark", action: #selector(close))
        let guideTitle = String(localized: "构图建议", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current))
        configure(guide, guideTitle, icon: "viewfinder", action: #selector(toggleGuide))
        guide.configuration?.title = guideTitle
        guide.configuration?.imagePadding = 6
        configure(shutter, String(localized: "拍照", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), icon: "circle.inset.filled", action: #selector(takePhoto))
        configure(switchLens, String(localized: "切换相机", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), icon: "camera.rotate", action: #selector(switchCamera))
        configure(retake, String(localized: "重拍", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), icon: nil, action: #selector(retakePhoto))
        configure(usePhoto, String(localized: "使用照片", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), icon: nil, action: #selector(acceptPhoto))
        configure(flash, String(localized: "闪光灯", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), icon: "bolt.badge.automatic", action: nil)
        flash.showsMenuAsPrimaryAction = true
        updateFlashMenu()
        var shutterStyle = shutter.configuration
        shutterStyle?.preferredSymbolConfigurationForImage = .init(pointSize: 50)
        shutterStyle?.contentInsets = .zero
        shutter.configuration = shutterStyle

        adviceLabel.font = .preferredFont(forTextStyle: .subheadline)
        adviceLabel.adjustsFontForContentSizeCategory = true
        adviceLabel.textColor = .white
        adviceLabel.textAlignment = .center
        adviceLabel.numberOfLines = 0
        adviceLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        adviceLabel.layer.cornerRadius = 10
        adviceLabel.clipsToBounds = true
        adviceLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(adviceLabel)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            cancel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            cancel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            guide.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            guide.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
            shutter.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8),
            shutter.widthAnchor.constraint(equalToConstant: 64),
            shutter.heightAnchor.constraint(equalToConstant: 64),
            switchLens.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            switchLens.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            flash.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            flash.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            retake.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            retake.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            usePhoto.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            usePhoto.centerYAnchor.constraint(equalTo: shutter.centerYAnchor),
            adviceLabel.bottomAnchor.constraint(equalTo: shutter.topAnchor, constant: -8),
            adviceLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 32),
            adviceLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -32),
            adviceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])

        let focusGesture = UITapGestureRecognizer(target: self, action: #selector(focus(_:)))
        focusGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(focusGesture)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:))))
        camera.onFrame = { [weak self] in self?.display($1, generation: $0) }
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.didStartRunningNotification, AVCaptureSession.didStopRunningNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged),
                                                   name: name, object: camera.session)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(sessionFailed(_:)),
                                               name: AVCaptureSession.runtimeErrorNotification, object: camera.session)
        if recordLocation {
            locationLabel.font = .preferredFont(forTextStyle: .caption1)
            locationLabel.textColor = .white
            locationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            locationLabel.textAlignment = .center
            locationLabel.numberOfLines = 2
            locationLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(locationLabel)
            NSLayoutConstraint.activate([
                locationLabel.topAnchor.constraint(equalTo: guide.bottomAnchor, constant: 8),
                locationLabel.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
                locationLabel.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -32),
                locationLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
            ])
            locator.changed = { [weak self] in self?.updateLocationLabel() }
            updateLocationLabel()
        }
        updateControls()
        camera.prepare { [weak self] prepared in
            guard let self, !self.finished else { return }
            guard prepared else { self.finish(.failure(self.cameraError)); return }
            self.ready = true
            self.configureRotation()
            self.refreshAnalysis()
            self.camera.run(true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if recordLocation { locator.start() }
        if ready, data == nil, !finished { camera.run(true) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        locator.stop()
        camera.run(false)
        clearStaleFrame?.cancel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        updateRotation()
        drawGuide()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var shouldAutorotate: Bool { true }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.updateRotation()
            self?.drawGuide()
        })
    }

    private func configureRotation() {
        previewRotationObservation = nil
        captureRotationObservation = nil
        guard let input = camera.session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: input.device, previewLayer: preview)
        rotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
            self?.updateRotation()
        }
        captureRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, _ in
            self?.updateRotation()
        }
        updateRotation()
    }

    private func updateRotation() {
        guard let rotationCoordinator, !takingPhoto, data == nil else { return }
        let nextPreview = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        let nextCapture = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        guard angle != nextPreview || captureAngle != nextCapture else { return }
        angle = nextPreview
        captureAngle = nextCapture
        refreshAnalysis()
    }

    private func configure(_ button: UIButton, _ title: String, icon: String?, action: Selector?) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.75)
        configuration.baseForegroundColor = .white
        configuration.image = icon.flatMap { UIImage(systemName: $0) }
        if icon == nil { configuration.title = title }
        button.configuration = configuration
        button.accessibilityLabel = title
        if let action { button.addTarget(self, action: action, for: .touchUpInside) }
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    private func updateFlashMenu() {
        let options: [(AVCaptureDevice.FlashMode, String, String)] = [
            (.auto, String(localized: "自动", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "bolt.badge.automatic"),
            (.on, String(localized: "开启", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "bolt.fill"),
            (.off, String(localized: "关闭闪光灯", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), "bolt.slash")
        ]
        if let active = options.first(where: { $0.0 == flashMode }) {
            flash.configuration?.image = UIImage(systemName: active.2)
            flash.accessibilityValue = active.1
        }
        flash.menu = UIMenu(children: options.map { mode, title, icon in
            UIAction(title: title, image: UIImage(systemName: icon), state: mode == flashMode ? .on : .off) { [weak self] _ in
                self?.flashMode = mode
                self?.updateFlashMenu()
            }
        })
    }

    private var cameraError: APIError {
        .message(String(localized: "无法读取拍摄内容，请重试。", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)))
    }

    private var analyzing: Bool { ready && guideEnabled && !takingPhoto && !switching && data == nil && !finished }

    private func refreshAnalysis() {
        generation += 1
        clearStaleFrame?.cancel()
        boxes = []
        advice = .looking
        pendingAdvice = nil
        if ready, let connection = preview.connection {
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
        if ready {
            camera.update(angle: angle, captureAngle: captureAngle, mirrored: mirrored, analyze: analyzing, generation: generation)
        }
        updateControls()
        drawGuide()
    }

    private func updateControls() {
        let reviewing = data != nil
        shutter.isHidden = reviewing
        shutter.isEnabled = ready && camera.session.isRunning && !takingPhoto && !switching && !camera.session.isInterrupted
        switchLens.isHidden = reviewing
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) == nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) == nil
        switchLens.isEnabled = shutter.isEnabled
        flash.isHidden = reviewing || mirrored || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.hasFlash != true
        flash.isEnabled = shutter.isEnabled
        guide.isHidden = reviewing
        guide.isEnabled = ready
        guide.accessibilityTraits = guideEnabled ? [.button, .selected] : [.button]
        guide.configuration?.baseBackgroundColor = guideEnabled ? UIColor.systemBlue.withAlphaComponent(0.85) : UIColor.black.withAlphaComponent(0.75)
        retake.isHidden = !reviewing
        usePhoto.isHidden = !reviewing
        adviceLabel.isHidden = !analyzing
        adviceLabel.text = advice.text
        review.isHidden = !reviewing
    }

    private func display(_ frame: DearCompositionFrame, generation: Int) {
        guard generation == self.generation, analyzing, !camera.session.isInterrupted else { return }
        boxes = frame.boxes
        // Confirm a changed status on the next frame to reduce flicker near a threshold.
        if pendingAdvice == frame.advice || frame.boxes.isEmpty { advice = frame.advice }
        pendingAdvice = frame.advice
        adviceLabel.text = advice.text
        drawGuide()
        clearStaleFrame?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            guard let self, generation == self.generation else { return }
            self.boxes = []
            self.advice = .looking
            self.pendingAdvice = nil
            self.adviceLabel.text = self.advice.text
            self.drawGuide()
        }
        clearStaleFrame = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: reset)
    }

    private func drawGuide() {
        let image = preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let show = analyzing && !image.isEmpty && image.width.isFinite && image.height.isFinite
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grid.isHidden = !show
        outlines.isHidden = !show
        if show {
            let lines = UIBezierPath()
            for fraction: CGFloat in [1 / 3, 2 / 3] {
                let x = image.minX + image.width * fraction
                let y = image.minY + image.height * fraction
                lines.move(to: CGPoint(x: x, y: image.minY))
                lines.addLine(to: CGPoint(x: x, y: image.maxY))
                lines.move(to: CGPoint(x: image.minX, y: y))
                lines.addLine(to: CGPoint(x: image.maxX, y: y))
            }
            grid.path = lines.cgPath
            let paths = UIBezierPath()
            for box in boxes {
                let rect = CGRect(x: image.minX + box.minX * image.width, y: image.minY + box.minY * image.height,
                                  width: box.width * image.width, height: box.height * image.height)
                let visible = rect.intersection(image)
                if !visible.isEmpty { paths.append(UIBezierPath(roundedRect: visible, cornerRadius: 8)) }
            }
            outlines.path = paths.cgPath
            outlines.strokeColor = (advice == .ready ? UIColor.systemGreen : UIColor.systemYellow).cgColor
        }
        CATransaction.commit()
    }

    @objc private func sessionChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            self.refreshAnalysis()
        }
    }

    @objc private func sessionFailed(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished, self.data == nil else { return }
            if error?.code == .mediaServicesWereReset, !self.takingPhoto {
                self.camera.run(true)
            } else {
                self.finish(.failure(self.cameraError))
            }
        }
    }

    @objc private func close() { finish(.success(nil)) }

    @objc private func toggleGuide() {
        guideEnabled.toggle()
        refreshAnalysis()
    }

    @objc private func switchCamera() {
        guard !takingPhoto, !switching else { return }
        switching = true
        refreshAnalysis()
        camera.switchCamera { [weak self] mirrored in
            guard let self, !self.finished else { return }
            self.mirrored = mirrored
            self.switching = false
            self.configureRotation()
            self.refreshAnalysis()
        }
    }

    @objc private func focus(_ gesture: UITapGestureRecognizer) {
        guard ready, !takingPhoto, !switching, data == nil else { return }
        let point = gesture.location(in: view)
        guard view.hitTest(point, with: nil) === view,
              preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1)).contains(point) else { return }
        camera.focus(at: preview.captureDevicePointConverted(fromLayerPoint: point))
    }

    @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed, shutter.isEnabled else { return }
        camera.zoom(by: gesture.scale)
        gesture.scale = 1
    }

    private func updateLocationLabel() {
        if let location = locator.location, DearCaptureGeography.valid(location) {
            locationLabel.text = location.verticalAccuracy >= 0 && location.altitude.isFinite && (-12000...100000).contains(location.altitude)
                ? String(format: String(localized: "位置已获取 · 海拔 %.1f 米", bundle: AgentIdentityLanguage.appBundle()), location.altitude)
                : String(localized: "位置已获取 · 海拔暂未获取", bundle: AgentIdentityLanguage.appBundle())
        } else {
            locationLabel.text = locator.denied
                ? String(localized: "位置访问未获授权，请在系统设置中开启。", bundle: AgentIdentityLanguage.appBundle())
                : String(localized: "等待定位，请保持位置权限开启", bundle: AgentIdentityLanguage.appBundle())
        }
    }

    @objc private func takePhoto() { capturePhoto(allowMissingLocation: false) }

    private func capturePhoto(allowMissingLocation: Bool) {
        guard shutter.isEnabled, data == nil else { return }
        let location = recordLocation ? locator.location.flatMap { DearCaptureGeography.valid($0) ? $0 : nil } : nil
        if recordLocation, location == nil, !allowMissingLocation {
            let alert = UIAlertController(title: nil, message: String(localized: "尚未获取有效定位，可稍后重试或选择不记录位置拍摄。", bundle: AgentIdentityLanguage.appBundle()), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "取消", bundle: AgentIdentityLanguage.appBundle()), style: .cancel))
            alert.addAction(UIAlertAction(title: String(localized: "不记录位置拍摄", bundle: AgentIdentityLanguage.appBundle()), style: .default) { [weak self] _ in self?.capturePhoto(allowMissingLocation: true) })
            present(alert, animated: true)
            return
        }
        takingPhoto = true
        refreshAnalysis()
        camera.takePhoto(flash: flashMode) { [weak self] data in
            guard let self, !self.finished else { return }
            self.takingPhoto = false
            guard let data, let image = UIImage(data: data) else {
                self.refreshAnalysis()
                let alert = UIAlertController(title: nil, message: self.cameraError.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "知道了", bundle: AgentIdentityLanguage.appBundle(), locale: Locale(identifier: AgentIdentityLanguage.current)), style: .default))
                self.present(alert, animated: true)
                return
            }
            do { self.data = try DearCaptureGeography.tag(data, location: location) }
            catch { self.finish(.failure(error)); return }
            self.locationLabel.isHidden = true
            self.review.image = image
            self.camera.run(false)
            self.refreshAnalysis()
        }
    }

    @objc private func retakePhoto() {
        data = nil
        review.image = nil
        updateRotation()
        locationLabel.isHidden = !recordLocation
        updateLocationLabel()
        refreshAnalysis()
        camera.run(true)
    }

    @objc private func acceptPhoto() {
        guard let data else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: url, options: .atomic)
            finish(.success((url, false)))
        } catch {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<(URL, Bool)?, Error>) {
        guard !finished else { return }
        finished = true
        locator.stop()
        camera.run(false)
        clearStaleFrame?.cancel()
        completion(result)
    }
}
