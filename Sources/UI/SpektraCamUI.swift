//
//  SpektraCamUI.swift
//  SpektraCam
//
//  Native Darkroom UI & ProMotion MetalKit Viewfinder for iPhone 13 Pro Max (6.7" 428x926 pt)
//  - Responsive Portrait & Landscape Cinema Layout (`GeometryReader` adaptive `VStack` vs side-by-side `HStack`)
//  - High-Resolution Video Controls: Resolution (720p / 1080p / 4K), Frame Rate (24 / 30 / 60 fps), Codec (HEVC / H.264 / ProRes 422)
//  - Interactive Tap-to-Focus & Exposure Reticle + Hardware Voice-Coil Manual Focus (0.00 Macro to 1.00 Infinity)
//  - Hong Kong Cinema Master Darkroom Recipes (Wong Kar-wai & Johnnie To)
//

import SwiftUI
import MetalKit
import CoreVideo
import CoreMedia
import AVFoundation
import UIKit

public struct MetalFilmViewfinder: UIViewRepresentable {
    public let cameraService: CameraCaptureService

    public init(cameraService: CameraCaptureService) {
        self.cameraService = cameraService
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(cameraService: cameraService)
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = cameraService.metalRenderer?.device
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 120
        mtkView.contentScaleFactor = 2.0
        mtkView.presentsWithTransaction = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.autoResizeDrawable = true
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
        mtkView.delegate = context.coordinator
        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {}

    public final class Coordinator: NSObject, MTKViewDelegate {
        let cameraService: CameraCaptureService
        private var lastRenderedRevision: UInt64 = 0

        init(cameraService: CameraCaptureService) {
            self.cameraService = cameraService
            super.init()
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            lastRenderedRevision = 0
        }

        public func draw(in view: MTKView) {
            let snapshot = cameraService.latestFrameSnapshot()
            guard let pb = snapshot.pixelBuffer,
                  snapshot.combinedRevision != lastRenderedRevision,
                  let renderer = cameraService.metalRenderer else {
                return
            }

            guard renderer.tryAcquireViewfinderSlot() else {
                return
            }

            guard let drawable = view.currentDrawable else {
                renderer.releaseViewfinderSlot()
                return
            }

            let liveParams = cameraService.activeParameters
            let liveLogCurve = cameraService.logTransferCurve
            let recTarget = cameraService.isRecordingVideo
                ? cameraService.dequeueVideoRecordingBufferIfNeeded(cameraFrameID: snapshot.frameID)
                : nil
            let workEdge = (recTarget != nil) ? cameraService.videoResolution.metalWorkLongEdge : 840

            let framePTS = snapshot.pts
            let serviceRef = self.cameraService

            let didRender = renderer.renderViewfinderDrawable(
                pixelBuffer: pb,
                params: liveParams,
                logCurve: liveLogCurve,
                drawable: drawable,
                recordingPixelBuffer: recTarget?.pixelBuffer,
                recordBakedFilm: recTarget?.bakeFilm ?? true,
                maxWorkLongEdge: workEdge,
                onRecordingFrameCompleted: recTarget.map { validRec in
                    return {
                        serviceRef.appendRecordedVideoFrame(validRec.pixelBuffer, pts: framePTS)
                    }
                }
            )

            if didRender {
                lastRenderedRevision = snapshot.combinedRevision
            }
        }
    }
}

private struct FilmStockCarouselStrip: View {
    @Binding var selectedNegID: String
    @Binding var selectedPrintID: String
    @Binding var activeRecipeID: String
    let onSelectRecipe: (HKCinemaRecipe) -> Void

    var body: some View {
        VStack(spacing: 4) {
            hkCinemaStrip
            cameraStocksStrip
            printStocksStrip
        }
    }

    private var hkCinemaStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HKCinemaRecipeDatabase.recipes) { recipe in
                    let isSelected = (activeRecipeID == recipe.id)
                    Button {
                        onSelectRecipe(recipe)
                    } label: {
                        HStack(spacing: 4) {
                            Text(recipe.title)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(isSelected ? .black : .yellow)
                                .lineLimit(1)
                            Text("· \(recipe.stockSummary)")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundColor(isSelected ? .black.opacity(0.85) : .gray)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.yellow : Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.yellow : Color.yellow.opacity(0.35), lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cameraStocksStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FilmStockDatabase.cameraStocks) { stock in
                        let isSelected = (selectedNegID == stock.id)
                        Button {
                            activeRecipeID = "standard_lab_neutral"
                            selectedNegID = stock.id
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stock.name)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(isSelected ? .black : .white)
                                    .lineLimit(1)
                                Text("\(Int(stock.isoSpeed)) ISO · \(Int(stock.referenceKelvin))K")
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(isSelected ? .black.opacity(0.8) : .gray)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.orange : Color(white: 0.14))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .id(stock.id)
                    }
                }
            }
            .onChange(of: selectedNegID) { newID in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var printStocksStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FilmStockDatabase.printStocks) { paper in
                        let isSelected = (selectedPrintID == paper.id)
                        Button {
                            selectedPrintID = paper.id
                        } label: {
                            Text("Print: \(paper.name)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(isSelected ? .orange : .gray)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(white: 0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .id(paper.id)
                    }
                }
            }
            .onChange(of: selectedPrintID) { newID in
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

public enum DarkroomInspectorTab: String, CaseIterable, Identifiable {
    case cinemaFX = "★ Cinema Master"
    case exposure = "① Exposure & Focus"
    case optics   = "② Bloom"
    case couplers = "③ DIR & Push"
    case halation = "④ Halation"
    case grain    = "⑤ Grain"
    case enlarger = "⑥ Enlarger CMY"
    case scanner  = "⑦ Scanner"

    public var id: String { rawValue }
}

public struct SpektraCamMainView: View {
    @StateObject private var cameraService = CameraCaptureService()
    @State private var params = FilmSimulationParameters()
    @State private var activeRecipeID: String = "standard_lab_neutral"
    @State private var isApplyingRecipe: Bool = false
    @State private var selectedTab: DarkroomInspectorTab = .exposure
    @State private var showDarkroomDrawer: Bool = true

    // Tap-to-Focus Reticle Animation State
    @State private var focusReticlePoint: CGPoint? = nil
    @State private var showFocusReticle: Bool = false

    public init() {}

    public var body: some View {
        GeometryReader { rootGeo in
            let isLandscape = rootGeo.size.width > rootGeo.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if isLandscape {
                    landscapeBody(totalSize: rootGeo.size)
                } else {
                    portraitBody
                }
            }
            .onChange(of: isLandscape) { _ in
                syncInterfaceOrientation()
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.medium)
        .onAppear {
            cameraService.activeParameters = params
            cameraService.requestPermissionsAndSetup()
            syncInterfaceOrientation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            syncInterfaceOrientation()
        }
        .onChange(of: params.negativeStockID) { newNegID in
            guard !isApplyingRecipe else { return }
            let neg = FilmStockDatabase.cameraStock(withID: newNegID)
            if neg.isMonochrome {
                if params.printStockID != "ilford_multigrade_fb" {
                    params.printStockID = "ilford_multigrade_fb"
                }
            } else if neg.processType == "ECN-2" {
                if params.printStockID == "ilford_multigrade_fb" || params.printStockID == "kodak_endura_premier" {
                    params.printStockID = "kodak_vision_2383"
                }
            } else if !neg.isReversal {
                if params.printStockID == "ilford_multigrade_fb" || params.printStockID == "kodak_premier_2393" {
                    params.printStockID = "kodak_endura_premier"
                }
            }
        }
        .onChange(of: params) { newValue in
            cameraService.activeParameters = newValue
        }
    }

    private func syncInterfaceOrientation() {
        let scenes = UIApplication.shared.connectedScenes
        if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? (scenes.first as? UIWindowScene) {
            cameraService.updateInterfaceOrientation(windowScene.interfaceOrientation)
        }
    }

    // MARK: - Portrait Layout (Classic Vertical Darkroom)
    private var portraitBody: some View {
        VStack(spacing: 5) {
            topTelemetryHeader

            GeometryReader { geo in
                let vfWidth = geo.size.width
                let vfHeight = max(min(geo.size.height, vfWidth * (4.0 / 3.0)), 120.0)
                viewfinderContainer(vfWidth: vfWidth, vfHeight: vfHeight, isLandscape: false)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            stockCarouselView

            if showDarkroomDrawer {
                darkroomParameterDrawer(height: 136)
            }

            bottomShutterDeck(compact: false)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Landscape Cinema Layout (Side-by-Side 4:3 Viewfinder + Right Control Deck)
    private func landscapeBody(totalSize: CGSize) -> some View {
        let rightPanelWidth = min(max(totalSize.width * 0.40, 270), 340)

        return HStack(spacing: 8) {
            GeometryReader { geo in
                let vfHeight = geo.size.height
                let vfWidth = max(min(geo.size.width, vfHeight * (4.0 / 3.0)), 160.0)
                viewfinderContainer(vfWidth: vfWidth, vfHeight: vfHeight, isLandscape: true)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            VStack(spacing: 5) {
                topTelemetryHeader
                stockCarouselView

                if showDarkroomDrawer {
                    darkroomParameterDrawer(height: max(84, totalSize.height - 235))
                } else {
                    Spacer(minLength: 0)
                }

                bottomShutterDeck(compact: true)
            }
            .frame(width: rightPanelWidth)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var stockCarouselView: some View {
        FilmStockCarouselStrip(
            selectedNegID: $params.negativeStockID,
            selectedPrintID: $params.printStockID,
            activeRecipeID: $activeRecipeID,
            onSelectRecipe: { recipe in
                isApplyingRecipe = true
                activeRecipeID = recipe.id
                var updated = params
                updated.applyHKCinemaRecipe(recipe)
                updated.lensFocalLengthMM = cameraService.activeLens.nominalFocalMM
                params = updated
                cameraService.activeParameters = updated
                cameraService.statusBannerText = "HK Cinema: \(recipe.title) (\(recipe.stockSummary))"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isApplyingRecipe = false
                }
            }
        )
    }

    private func viewfinderContainer(vfWidth: CGFloat, vfHeight: CGFloat, isLandscape: Bool) -> some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topLeading) {
                MetalFilmViewfinder(cameraService: cameraService)
                    .frame(width: vfWidth, height: vfHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(cameraService.isRecordingVideo ? Color.red : Color.orange.opacity(0.45), lineWidth: cameraService.isRecordingVideo ? 2 : 1)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let loc = value.location
                                let clampedX = max(24.0, min(vfWidth - 24.0, loc.x))
                                let clampedY = max(24.0, min(vfHeight - 24.0, loc.y))
                                focusReticlePoint = CGPoint(x: clampedX, y: clampedY)
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.68)) {
                                    showFocusReticle = true
                                }
                                let nx = clampedX / max(vfWidth, 1.0)
                                let ny = clampedY / max(vfHeight, 1.0)
                                let devicePt: CGPoint
                                switch cameraService.currentVideoOrientation {
                                case .landscapeRight:
                                    devicePt = CGPoint(x: 1.0 - nx, y: 1.0 - ny)
                                case .landscapeLeft:
                                    devicePt = CGPoint(x: nx, y: ny)
                                default:
                                    devicePt = CGPoint(x: ny, y: 1.0 - nx)
                                }
                                cameraService.focusAndExpose(at: devicePt)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        showFocusReticle = false
                                    }
                                }
                            }
                    )

                if showFocusReticle, let pt = focusReticlePoint {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: 1.8)
                            .frame(width: 58, height: 58)
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 5, height: 5)
                    }
                    .position(x: pt.x, y: pt.y)
                }
            }

            VStack(spacing: 5) {
                if cameraService.isManualFocusMode {
                    HStack(spacing: 6) {
                        Text("MF")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                        Text("Macro")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                        Slider(
                            value: Binding(
                                get: { cameraService.manualFocusLensPosition },
                                set: { newVal in cameraService.setManualFocusLensPosition(newVal) }
                            ),
                            in: 0.0...1.0
                        )
                        .tint(.yellow)
                        Text("∞")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f", cameraService.manualFocusLensPosition))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                            .frame(width: 32, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(10)
                    .padding(.horizontal, 8)
                }

                HStack(spacing: 5) {
                    lensSelectorPill
                    Spacer(minLength: 2)

                    Button {
                        if cameraService.isManualFocusMode {
                            cameraService.resetToContinuousAutoFocus()
                        } else {
                            cameraService.setManualFocusLensPosition(cameraService.manualFocusLensPosition)
                        }
                    } label: {
                        Text(cameraService.isManualFocusMode ? String(format: "MF %.2f", cameraService.manualFocusLensPosition) : "AF-C")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraService.isManualFocusMode ? .black : .yellow)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(cameraService.isManualFocusMode ? Color.yellow : Color.black.opacity(0.68))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Button {
                        let currentNeg = params.negativeStockID
                        let currentPrt = params.printStockID
                        var fresh = FilmSimulationParameters()
                        fresh.negativeStockID = currentNeg
                        fresh.printStockID = currentPrt
                        fresh.lensFocalLengthMM = cameraService.activeLens.nominalFocalMM
                        activeRecipeID = "standard_lab_neutral"
                        params = fresh
                        cameraService.activeParameters = fresh
                        cameraService.resetToContinuousAutoFocus()
                    } label: {
                        Text("RESET")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.68))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: vfWidth, height: vfHeight)
    }

    private var topTelemetryHeader: some View {
        let neg = FilmStockDatabase.cameraStock(withID: params.negativeStockID)
        let prt = FilmStockDatabase.printStock(withID: params.printStockID)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(neg.name) → \(prt.name)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(cameraService.statusBannerText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(cameraService.isProcessing12MPPhoto ? .yellow : (cameraService.isRecordingVideo ? .red : .gray))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            Text(params.filmFormatGate.shortBadge)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
        }
    }

    private var lensSelectorPill: some View {
        HStack(spacing: 4) {
            ForEach(iPhone13ProMaxLens.allCases) { lens in
                Button {
                    cameraService.switchLens(to: lens)
                } label: {
                    Text(lens.focalLengthLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(cameraService.activeLens == lens ? .black : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(cameraService.activeLens == lens ? Color.orange : Color.black.opacity(0.68))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func darkroomParameterDrawer(height: CGFloat) -> some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DarkroomInspectorTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(selectedTab == tab ? .black : .white)
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(selectedTab == tab ? Color.yellow : Color(white: 0.16))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 7) {
                    switch selectedTab {
                    case .cinemaFX:
                        paramSlider(title: "Shadow Mercury Green / Magenta", value: $params.shadowSplitGreenMagenta, range: -1.0...1.0, unit: "")
                        paramSlider(title: "Shadow Electric Blue / Crimson", value: $params.shadowSplitTealRed, range: -1.0...1.0, unit: "")
                        paramSlider(title: "Highlight Tungsten Amber Gold", value: $params.highlightWarmthGold, range: -1.0...1.0, unit: "")
                        paramSlider(title: "Milkyway Chiaroscuro Noir Toe", value: $params.chiaroscuroContrast, range: 0.0...1.0, unit: "")
                        paramSlider(title: "E-6/ECN-2 Cross-Process Warp", value: $params.crossProcessAmount, range: 0.0...1.0, unit: "")
                        paramSlider(title: "Kinoptik 9.8mm Barrel Distortion", value: $params.wideAngleDistortion, range: 0.0...1.0, unit: "")
                        paramSlider(title: "Doyle Step-Printing Trail (8fps)", value: $params.stepPrintTrail, range: 0.0...1.0, unit: "")

                    case .exposure:
                        HStack(spacing: 8) {
                            Text("Focus Mode")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            Button {
                                cameraService.resetToContinuousAutoFocus()
                            } label: {
                                Text("AF-C (Tap VF)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(!cameraService.isManualFocusMode ? .black : .white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(!cameraService.isManualFocusMode ? Color.yellow : Color(white: 0.22))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button {
                                cameraService.setManualFocusLensPosition(cameraService.manualFocusLensPosition)
                            } label: {
                                Text("Manual (MF)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(cameraService.isManualFocusMode ? .black : .white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(cameraService.isManualFocusMode ? Color.yellow : Color(white: 0.22))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }

                        if cameraService.isManualFocusMode {
                            paramSlider(
                                title: "Manual Focus Position (Macro ↔ ∞)",
                                value: Binding(
                                    get: { cameraService.manualFocusLensPosition },
                                    set: { newVal in cameraService.setManualFocusLensPosition(newVal) }
                                ),
                                range: 0.0...1.0,
                                unit: ""
                            )
                        }
                        paramSlider(title: "Negative Exposure EV", value: $params.exposureCompensationEV, range: -4.0...4.0, unit: "EV")
                        Toggle("Auto Print EV Compensation", isOn: $params.autoPrintExposureComp)
                            .font(.system(size: 11, design: .monospaced))
                        paramSlider(title: "Optical Vignetting (cos⁴θ)", value: $params.opticalVignettingStrength, range: 0.0...1.0, unit: "")
                        paramSlider(title: "Scene Color Temp", value: $params.sceneIlluminantKelvin, range: 2800...9000, unit: "K")

                    case .optics:
                        Picker("Optical Diffusion Filter", selection: $params.diffusionModel) {
                            ForEach(OpticalDiffusionModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        paramSlider(title: "Bloom / Mist Strength", value: $params.bloomStrength, range: 0.0...1.0, unit: "")
                        paramSlider(title: "Bloom Highlight Cutoff", value: $params.bloomHighlightThreshold, range: 0.15...1.2, unit: "")
                        paramSlider(title: "Scatter Radius", value: $params.bloomRadiusMicrometers, range: 30.0...450.0, unit: "µm")

                    case .couplers:
                        paramSlider(title: "Push / Pull Process", value: $params.pushPullStops, range: -2.0...3.0, unit: "Stops")
                        paramSlider(title: "DIR Coupler Interlayer Inhibition", value: $params.dirCouplerAmount, range: 0.0...2.0, unit: "")
                        paramSlider(title: "DIR Eberhard Edge Radius", value: $params.dirDiffusionRadiusMicrometers, range: 2.0...60.0, unit: "µm")
                        paramSlider(title: "Developer Exhaustion", value: $params.developerExhaustion, range: 0.0...0.8, unit: "")
                        paramSlider(title: "Bleach Bypass (Silver Retention)", value: $params.bleachBypassAmount, range: 0.0...1.0, unit: "")

                    case .halation:
                        Toggle("Anti-Halation Base Scatter", isOn: $params.halationEnabled)
                            .font(.system(size: 11, design: .monospaced))
                        paramSlider(title: "Red Layer Halation Strength", value: $params.halationStrengthRGB.x, range: 0.0...0.25, unit: "")
                        paramSlider(title: "Green Layer Halation Strength", value: $params.halationStrengthRGB.y, range: 0.0...0.10, unit: "")
                        paramSlider(title: "Red Halation Scatter Sigma", value: $params.halationRadiusMicrometers.x, range: 40.0...500.0, unit: "µm")
                        paramSlider(title: "Frieser Emulsion Scatter", value: $params.inEmulsionScatterMicrometers, range: 0.0...25.0, unit: "µm")

                    case .grain:
                        Picker("Film Format Gate Size", selection: $params.filmFormatGate) {
                            ForEach(FilmFormatGate.allCases) { gate in
                                Text(gate.displayName).tag(gate)
                            }
                        }
                        .pickerStyle(.menu)
                        paramSlider(title: "Silver Halide Grain Density", value: $params.grainStrength, range: 0.0...2.5, unit: "×")
                        paramSlider(title: "High-Density Grain Uniformity", value: $params.grainUniformity, range: 0.5...1.5, unit: "")

                    case .enlarger:
                        Picker("Print Stage Mode", selection: $params.printPipelineMode) {
                            ForEach(DarkroomPrintPipelineMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Picker("Enlarger Head", selection: $params.enlargerLightSource) {
                            ForEach(EnlargerLightSourceType.allCases) { src in
                                Text(src.displayName).tag(src)
                            }
                        }
                        .pickerStyle(.menu)
                        paramSlider(title: "Dichroic Yellow Filter (Warm/Cold)", value: $params.dichroicYellowCC, range: -60.0...60.0, unit: "CC")
                        paramSlider(title: "Dichroic Magenta Filter (Green/Mag)", value: $params.dichroicMagentaCC, range: -60.0...60.0, unit: "CC")
                        paramSlider(title: "Dichroic Cyan Filter", value: $params.dichroicCyanCC, range: -60.0...60.0, unit: "CC")
                        paramSlider(title: "Enlarger Print Exposure", value: $params.printExposureEV, range: -2.5...2.5, unit: "EV")
                        paramSlider(title: "Print Paper Contrast Gamma", value: $params.printGammaContrast, range: 0.65...1.45, unit: "×")
                        paramSlider(title: "Paper Pre-Flashing (Highlight Save)", value: $params.preflashExposureEV, range: -6.0...(-1.0), unit: "EV")
                        paramSlider(title: "Ilford Multigrade Contrast (00–5)", value: $params.bwMultigradeFilterGrade, range: 0.0...5.0, unit: "G")

                    case .scanner:
                        Picker("Target Display Space", selection: $params.outputColorSpace) {
                            ForEach(TargetDisplayColorSpace.allCases) { space in
                                Text(space.displayName).tag(space)
                            }
                        }
                        .pickerStyle(.segmented)
                        paramSlider(title: "Scanner Veiling Glare", value: $params.scannerVeilingGlare, range: 0.0...0.05, unit: "")
                        paramSlider(title: "Scanner Black Point Offset", value: $params.blackPointOffset, range: -0.08...0.08, unit: "")
                        paramSlider(title: "Scanner White Point Gain", value: $params.whitePointOffset, range: -0.15...0.15, unit: "")
                    }
                }
                .padding(8)
            }
            .frame(height: height)
            .background(Color(white: 0.09))
            .cornerRadius(10)
        }
    }

    private func paramSlider(title: String, value: Binding<Float>, range: ClosedRange<Float>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.2f %@", value.wrappedValue, unit))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
            Slider(value: value, in: range)
                .tint(.orange)
        }
    }

    private func bottomShutterDeck(compact: Bool) -> some View {
        VStack(spacing: 5) {
            if cameraService.isCaptureModeVideo {
                VStack(spacing: 4) {
                    // Resolution (720p / 1080p / 4K), FPS (24 / 30 / 60), Codec (HEVC / H.264 / ProRes 422)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Picker("Resolution", selection: $cameraService.videoResolution) {
                                ForEach(VideoResolutionPreset.allCases) { res in
                                    Text(res.rawValue).tag(res)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(cameraService.isRecordingVideo)

                            Picker("FPS", selection: $cameraService.videoFrameRate) {
                                ForEach(VideoFrameRateOption.allCases) { fps in
                                    Text(fps.label).tag(fps)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(cameraService.isRecordingVideo)

                            Picker("Codec", selection: $cameraService.videoCodec) {
                                ForEach(VideoCodecSelection.allCases) { codec in
                                    Text(codec.rawValue).tag(codec)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(cameraService.isRecordingVideo)
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Picker("Video Mode", selection: $cameraService.videoPipelineMode) {
                            ForEach(VideoRecordingPipelineMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Log Curve", selection: $cameraService.logTransferCurve) {
                            ForEach(LogEncodingTransferFunction.allCases) { curve in
                                Text(curve.displayName).tag(curve)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            HStack(spacing: compact ? 12 : 24) {
                Button {
                    cameraService.isCaptureModeVideo.toggle()
                } label: {
                    Text(cameraService.isCaptureModeVideo ? "LOG VIDEO" : "12MP FILM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .padding(.horizontal, compact ? 9 : 12)
                        .padding(.vertical, 8)
                        .background(cameraService.isCaptureModeVideo ? Color.red : Color.orange)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    if cameraService.isCaptureModeVideo {
                        cameraService.toggleVideoRecording()
                    } else {
                        cameraService.captureRAWPhoto()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: compact ? 50 : 60, height: compact ? 50 : 60)
                        Circle()
                            .fill(cameraService.isCaptureModeVideo ? Color.red : Color.orange)
                            .frame(width: cameraService.isRecordingVideo ? (compact ? 22 : 28) : (compact ? 38 : 48),
                                   height: cameraService.isRecordingVideo ? (compact ? 22 : 28) : (compact ? 38 : 48))
                            .opacity(cameraService.isProcessing12MPPhoto ? 0.65 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: cameraService.isRecordingVideo)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showDarkroomDrawer.toggle()
                } label: {
                    Text(showDarkroomDrawer ? "HIDE LAB" : "DARKROOM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, compact ? 9 : 12)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}