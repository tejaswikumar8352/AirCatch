//
//  SpeechManager.swift
//  AirCatchClient
//
//  Handles speech recognition for Voice Typing.
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechManager: ObservableObject {
    static let shared = SpeechManager()
    
    @Published var isListening = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var onTextCallback: ((String) -> Void)?
    
    private init() {
        requestAuthorization()
    }
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.authorizationStatus = status
            }
        }
    }
    
    func startRecording(onText: @escaping (String) -> Void) throws {
        if isListening {
            stopRecording()
        }
        
        // Cancel existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        self.onTextCallback = onText
        
        // update audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        // Use playAndRecord to allow playback (AudioPlayer) to continue working if active
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.setupFailed
        }
        
        // Monitor intermediate results
        recognitionRequest.shouldReportPartialResults = true
        
        // Check input node
        let inputNode = audioEngine.inputNode
        
        // Prevent audio feedback loop (?) - usually unnecessary for input-only tap but good practice
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                // We want to send *updates* or *final* text?
                // For "Live Typing", sending partials is tricky (backspacing?).
                // Simplest approach: Send ONLY the *new* part? 
                // OR: Send the Best Transcription.
                // Replicating "Type what I say":
                // If I say "Hello", it types "Hello".
                // If I then say " World", it types " World".
                // Result.bestTranscription.formattedString is the WHOLE text since start of session.
                // We need to diff it, or just reset session on pauses?
                // Diffing is safer.
                
                let currentText = result.bestTranscription.formattedString
                self.processTextUpdate(currentText)
                
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                self.stopRecording()
            }
        }
        
        // Setup audio engine input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isListening = true
        AirCatchLog.info("Speech recognition started", category: .input)
    }
    
    func stopRecording() {
        if !isListening { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
        lastProcessedText = "" // Reset for next session
        
        // Restore session to playback if needed?
        // Ideally AudioPlayer handles its own session state or we leave it.
        // Let's reset to default playback to be nice to system audio
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
        AirCatchLog.info("Speech recognition stopped", category: .input)
    }
    
    // MARK: - Diffing Logic
    
    private var lastProcessedText = ""
    
    private func processTextUpdate(_ fullText: String) {
        // If fullText starts with lastProcessed, send the suffix.
        if fullText.hasPrefix(lastProcessedText) {
            let newText = String(fullText.dropFirst(lastProcessedText.count))
            if !newText.isEmpty {
                onTextCallback?(newText)
                lastProcessedText = fullText
            }
        } else {
            // Text changed radically (correction?), maybe send backspaces?
            // For now, simpliest is to ignore corrections or just send new text.
            // Complex diffing is out of scope.
            // Reset logic:
            lastProcessedText = fullText
        }
    }
}

enum SpeechError: Error {
    case setupFailed
}
