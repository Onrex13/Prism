import Cocoa
import MetalKit

extension NSScreen {
    /// The CoreGraphics display id backing this screen.
    var displayId: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Whether this display can render Extended Dynamic Range content (required
    /// for the brightness boost).
    var supportsEDR: Bool {
        maximumPotentialExtendedDynamicRangeColorComponentValue > 1.05
    }
}

/// A full-screen Metal view that multiply-composites an HDR white value over the
/// whole display. Because the value exceeds SDR white (1.0) in an extended-range
/// color space, the display drives those pixels into EDR headroom — brightening
/// everything proportionally while black stays black. A 1×1 drawable is stretched
/// to fill, so GPU cost is negligible.
final class BrightnessOverlayView: MTKView, MTKViewDelegate {
    private let edrColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    private var queue: MTLCommandQueue?

    init(frame: CGRect, value: Double) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        guard let device else { fatalError("No Metal device available") }
        queue = device.makeCommandQueue()
        delegate = self

        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        colorPixelFormat = .rgba16Float
        colorspace = edrColorSpace
        clearColor = MTLClearColorMake(value, value, value, 1.0)
        preferredFramesPerSecond = 5

        if let layer = layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.pixelFormat = .rgba16Float
            layer.compositingFilter = "multiply"
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    /// Updates the multiply value (1.0 = no boost).
    func setValue(_ value: Double) {
        clearColor = MTLClearColorMake(value, value, value, 1.0)
        draw()
    }

    func draw(in view: MTKView) {
        guard let queue,
              let descriptor = currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor),
              let drawable = currentDrawable else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

/// The click-through, shield-level window that hosts the boost overlay for one
/// display.
final class BrightnessOverlayWindow: NSWindow {
    init(screen: NSScreen, value: Double) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let overlay = BrightnessOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), value: value)
        overlay.autoresizingMask = [.width, .height]
        contentView = overlay
        setFrame(screen.frame, display: true)
    }

    var overlayView: BrightnessOverlayView? { contentView as? BrightnessOverlayView }
}
