//
//  SpektraCamUI.swift
//  SpektraCam
//
//  Native Darkroom UI & ProMotion MetalKit Viewfinder for iPhone 13 Pro Max (6.7" 428x926 pt)
//  - Zero-Lag Shutter & 12MP (3024x4032) Full-Resolution Output
//  - Optional "+DNG" toggle on the Exposure tab if the user also wants the raw 75MB DNG negative saved alongside the 12MP film print
//

import SwiftUI
import MetalKit
import CoreVideo

public struct MetalFilmViewfinder: UIViewRepresentable {
    @ObservedObject var cameraService: CameraCaptureService

    public func makeCoordinator() -> Coordinator {
        Coordinator(cameraService: cameraService)
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = cameraService.metalRenderer?.device
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60
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

        init(cameraService: CameraCaptureService) {
            self.cameraService = cameraService
            super.init()
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            guard let pb = cameraService.latestPixelBuffer,
                  let renderer = cameraService.metalRenderer else {
                if let cmdBuf = cameraService.metalRenderer?.commandQueue.makeCommandBuffer(),
                   let rpd = view.currentRenderPassDescriptor,
                   let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) {
                    enc.endEncoding()
                    cmdBuf.present(drawable)
                    cmdBuf.commit()
                }
                return
            }

            let liveParams = cameraService.activeParameters
            let liveLogCurve = cameraService.logTransferCurve

            if renderer.processVideoSampleBuffer(
                pixelBuffer: pb,
                params: liveParams,
                logCurve: liveLogCurve,
                outputDrawableTexture: drawable.texture
            ) != nil {
                drawable.present()
            }
        }
    }
}

public enum DarkroomInspectorTab: String, CaseIterable, Identifiable {
    case exposure = "① Exposure"
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
    @State private var selectedTab: DarkroomInspectorTab = .enlarger
    @State private var showDarkroomDrawer: Bool = true

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                topTelemetryHeader

                ZStack(alignment: .bottomLeading) {
                    MetalFilmViewfinder(cameraService: cameraService)
                        .aspectRatio(cameraService.isCaptureModeVideo ? (16.0 / 9.0) : (3.0 / 4.0), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                        )

                    HStack {
                        lensSelectorPill
                        Spacer()
                        Button {
                            let currentNeg = params.negativeStockID
                            let currentPrt = params.printStockID
                            var fresh = FilmSimulationParameters()
                            fresh.negativeStockID = currentNeg
                            fresh.printStockID = currentPrt
                            params = fresh
                            cameraService.activeParameters = fresh
                        } label: {
                            Text("RESET")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(12)
                        }
                    }
                    .padding(10)
                }

                filmAndPrintCarousel

                if showDarkroomDrawer {
                    darkroomParameterDrawer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                bottomShutterDeck
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            cameraService.activeParameters = params
            cameraService.requestPermissionsAndSetup()
        }
        .onChange(of: params) { newValue in
            cameraService.activeParameters = newValue
        }
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
                Text(cameraService.statusBannerText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(cameraService.isProcessing12MPPhoto ? .yellow : .gray)
                    .lineLimit(1)
            }
            Spacer()
            Text(params.filmFormatGate.displayName.components(separatedBy: " ").first ?? "35mm")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
        }
    }

    private var lensSelectorPill: some View {
        HStack(spacing: 6) {
            ForEach(iPhone13ProMaxLens.allCases) { lens in
                Button {
                    cameraService.switchLens(to: lens)
                } label: {
                    Text(lens.focalLengthLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(cameraService.activeLens == lens ? .black : .white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(cameraService.activeLens == lens ? Color.orange : Color.black.opacity(0.65))
                        .cornerRadius(14)
                }
            }
        }
    }

    private var filmAndPrintCarousel: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmStockDatabase.cameraStocks) { stock in
                        Button {
                            params.negativeStockID = stock.id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stock.name)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(params.negativeStockID == stock.id ? .black : .white)
                                Text("\(Int(stock.isoSpeed)) ISO · \(Int(stock.referenceKelvin))K")
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundColor(params.negativeStockID == stock.id ? .black.opacity(0.8) : .gray)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(params.negativeStockID == stock.id ? Color.orange : Color(white: 0.14))
                            .cornerRadius(8)
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmStockDatabase.printStocks) { paper in
                        Button {
                            params.printStockID = paper.id
                        } label: {
                            Text("Print: \(paper.name)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(params.printStockID == paper.id ? .orange : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(white: 0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(params.printStockID == paper.id ? Color.orange : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    private var darkroomParameterDrawer: some View {
        VStack(spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DarkroomInspectorTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(selectedTab == tab ? .black : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedTab == tab ? Color.yellow : Color(white: 0.16))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    switch selectedTab {
                    case .exposure:
                        paramSlider(title: "Negative Exposure EV", value: $params.exposureCompensationEV, range: -4.0...4.0, unit: "EV")
                        Toggle("Auto Print EV Compensation", isOn: $params.autoPrintExposureComp)
                            .font(.system(size: 11, design: .monospaced))
                        Toggle("Also Save Raw 12-Bit DNG Negative", isOn: $cameraService.alsoSaveRawDNG)
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
            .frame(height: 150)
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
                Spacer()
                Text(String(format: "%.2f %@", value.wrappedValue, unit))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Slider(value: value, in: range)
                .tint(.orange)
        }
    }

    private var bottomShutterDeck: some View {
        VStack(spacing: 6) {
            if cameraService.isCaptureModeVideo {
                HStack(spacing: 8) {
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

            HStack(spacing: 24) {
                Button {
                    cameraService.isCaptureModeVideo.toggle()
                } label: {
                    Text(cameraService.isCaptureModeVideo ? "LOG VIDEO" : "12MP FILM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(cameraService.isCaptureModeVideo ? Color.red : Color.orange)
                        .cornerRadius(8)
                }

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
                            .frame(width: 64, height: 64)
                        Circle()
                            .fill(cameraService.isCaptureModeVideo ? Color.red : Color.orange)
                            .frame(width: cameraService.isRecordingVideo ? 30 : 52,
                                   height: cameraService.isRecordingVideo ? 30 : 52)
                            .opacity(cameraService.isProcessing12MPPhoto ? 0.65 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: cameraService.isRecordingVideo)
                    }
                }

                Button {
                    withAnimation {
                        showDarkroomDrawer.toggle()
                    }
                } label: {
                    Text(showDarkroomDrawer ? "HIDE LAB" : "DARKROOM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.2))
                        .cornerRadius(8)
                }
            }
        }
    }
}
