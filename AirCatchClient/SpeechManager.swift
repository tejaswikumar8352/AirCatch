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
    
    // Session ID to safely invalidate stale callbacks
    private var currentSessionID: UUID?

    // MARK: - Incremental emission state

    /// Text we have already emitted (typed on the Mac) for the current recording session.
    /// We ONLY append to this - never delete from it during a session.
    private var emittedText: String = ""

    /// The last full transcription we observed from SFSpeechRecognizer.
    /// Used to detect when we need to flush remaining text on stop.
    private var lastObservedFullText: String = ""
    
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
           
        // Start new session
        let sessionID = UUID()
        self.currentSessionID = sessionID
        
        // Cancel existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        self.onTextCallback = onText
        resetIncrementalState()
        
        // Configure audio session for speech recognition
        let audioSession = AVAudioSession.sharedInstance()
        // Use playAndRecord with spokenAudio mode for optimal speech recognition
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.setupFailed
        }
        
        // Monitor intermediate results
        recognitionRequest.shouldReportPartialResults = true
        
        // Check input node
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            // Strictly enforce session validity
            // If the user stopped/restarted, this callback refers to a dead session.
            guard self.currentSessionID == sessionID else {
                return
            }

            if let result {
                self.handleRecognitionResult(result)
                if result.isFinal {
                    self.stopRecording()
                    return
                }
            }

            if let error {
                AirCatchLog.error("Speech recognition error: \(error.localizedDescription)", category: .input)
                self.stopRecording()
            }
        }
        
        // Setup audio engine input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // Use larger buffer (4096) for smoother recognition - less choppy than 1024
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { (buffer, when) in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isListening = true
        AirCatchLog.info("Speech recognition started", category: .input)
    }
    
    func stopRecording() {
        if !isListening { return }
        
        // CRITICAL: Capture and then IMMEDIATELY nil the callback
        // This is the ultimate safeguard - even if zombie callbacks fire,
        // they cannot send text because onTextCallback is nil
        let callbackToUse = onTextCallback
        onTextCallback = nil
        
        // Invalidate session ID as secondary protection
        currentSessionID = nil
        
        // Now flush remaining text using the captured callback (not the nil'd instance var)
        if !lastObservedFullText.isEmpty && lastObservedFullText != emittedText {
            if lastObservedFullText.hasPrefix(emittedText) {
                let remainingText = String(lastObservedFullText.dropFirst(emittedText.count))
                if !remainingText.isEmpty {
                    callbackToUse?(remainingText)
                    #if DEBUG
                    print("🎤 Final flush: '\(remainingText)'")
                    #endif
                }
            }
        }
        
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // End recognition
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
        resetIncrementalState()
        
        // Restore session to playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        
        AirCatchLog.info("Speech recognition stopped", category: .input)
    }

    // MARK: - Recognition handling

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult) {
        // IMPORTANT: Skip final results entirely - we handle everything via partials + flush
        // The final result often duplicates what we already sent from partials
        if result.isFinal {
            return
        }
        
        let fullText = result.bestTranscription.formattedString
        
        // Store for flush on stop
        lastObservedFullText = fullText
        
        // SIMPLE APPROACH: Only emit text that EXTENDS what we've already typed.
        // Use exact string prefix matching (case-sensitive) to avoid any ambiguity.
        
        if fullText.hasPrefix(emittedText) {
            // The new text extends what we already typed - emit the suffix
            let newText = String(fullText.dropFirst(emittedText.count))
            
            if !newText.isEmpty {
                onTextCallback?(newText)
                emittedText = fullText
                
                #if DEBUG
                print("🎤 Partial Emit: '\(newText)' | Total Emitted: \(emittedText.count)")
                #endif
            }
        }
    }

    /// Called when recording stops - emit any text we haven't sent yet.
    /// This is the ONLY place we might send remaining text, and we're very careful.
    private func flushRemainingText() {
        guard !lastObservedFullText.isEmpty else { return }
        
        #if DEBUG
        print("🎤 Flush Check: LastObserved='\(lastObservedFullText)' Emitted='\(emittedText)'")
        #endif
        
        // Safety: If we've already emitted the EXACT text, do nothing.
        // This catches the case where flush runs but we're already up to date.
        if lastObservedFullText == emittedText {
            return
        }

        // Only emit if the final text extends what we already sent
        if lastObservedFullText.hasPrefix(emittedText) {
            let remainingText = String(lastObservedFullText.dropFirst(emittedText.count))
            
            if !remainingText.isEmpty {
                onTextCallback?(remainingText)
                emittedText = lastObservedFullText
                #if DEBUG
                print("🎤 Flush Emit: '\(remainingText)'")
                #endif
            }
        } 
        
        // DANGEROUS BRANCH REMOVED:
        // The "else if emittedText.isEmpty" branch was likely the cause of full duplication.
        // If we somehow missed all partials (rare), we might miss one phrase here,
        // but that's better than duplicating the entire paragraph.
    }

    private func resetIncrementalState() {
        emittedText = ""
        lastObservedFullText = ""
    }
}

enum SpeechError: Error {
    case setupFailed
}
