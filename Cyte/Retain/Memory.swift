//
//  Index.swift
//  Cyte
//
//  Tracks active application context (driven by external caller)
//
//  Created by Shaun Narayan on 3/03/23.
//

import Foundation
import AVKit
import OSLog
import Combine

@MainActor
class Memory {
    static let shared = Memory()
    
    private var assetWriter : AVAssetWriter? = nil
    private var assetWriterInput : AVAssetWriterInput? = nil
    private var assetWriterAdaptor : AVAssetWriterInputPixelBufferAdaptor? = nil
    private var frameCount = 0
    private var currentContext : String = "Startup"
    private var currentStart: Date = Date()
    private var episode: Episode?
    
    init() {
        let unclosedFetch : NSFetchRequest<Episode> = Episode.fetchRequest()
        unclosedFetch.predicate = NSPredicate(format: "start == end")
        do {
            let fetched = try PersistenceController.shared.container.viewContext.fetch(unclosedFetch)
            for unclosed in fetched {
                PersistenceController.shared.container.viewContext.delete(unclosed)
            }
        } catch {
            
        }
    }
    //
    // Check the currently active app, if different since last check
    // then close the current episode and start a new one
    //
    func updateActiveContext() -> String {
        guard let front = NSWorkspace.shared.frontmostApplication else { return "" }
        let context = front.bundleIdentifier ?? "Unnamed"
        if front.isActive && currentContext != context {
            if assetWriter != nil {
                closeEpisode()
            }
            currentContext = context
            if currentContext != "shoplex.Cyte" {
                openEpisode()
            } else {
                print("Skip Cyte")
            }
        }
        return currentContext
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    //
    // Sets up a stream to disk
    //
    func openEpisode() {
        Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                self.update()
            }
        }
        .store(in: &subscriptions)
        
        currentStart = Date()
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        //generate a file url to store the video. some_image.jpg becomes some_image.mov
        let outputMovieURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("\(front.localizedName!) \(currentStart.formatted(date: .abbreviated, time: .standard)).mov".replacingOccurrences(of: ":", with: "."))
        //create an assetwriter instance
        do {
            try assetWriter = AVAssetWriter(outputURL: outputMovieURL!, fileType: .mov)
        } catch {
            abort()
        }
        //generate 1080p settings
        let settingsAssistant = AVOutputSettingsAssistant(preset: .preset1920x1080)?.videoSettings
        //create a single video input
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: settingsAssistant)
        //create an adaptor for the pixel buffer
        assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput!, sourcePixelBufferAttributes: nil)
        //add the input to the asset writer
        assetWriter!.add(assetWriterInput!)
        //begin the session
        assetWriter!.startWriting()
        assetWriter!.startSession(atSourceTime: CMTime.zero)
        
        episode = Episode(context: PersistenceController.shared.container.viewContext)
        episode!.start = currentStart
        episode!.bundle = currentContext
        episode!.title = assetWriter?.outputURL.deletingPathExtension().lastPathComponent
        episode!.end = currentStart
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    //
    // Save out the current file, create a DB entry and reset streams
    //
    func closeEpisode() {
        if assetWriter == nil {
            return
        }
        for sub in subscriptions {
            sub.cancel()
        }
        subscriptions.removeAll()
                
        //close everything
        assetWriterInput!.markAsFinished()
        self.update(force_close: true)
        
        // Delete episodes < 10s
        if frameCount < 5 || currentContext.starts(with:"shoplex.Cyte") {
            assetWriter!.cancelWriting()
            PersistenceController.shared.container.viewContext.delete(episode!)
            Logger().info("Supressed small episode for \(self.currentContext)")
        } else {
            assetWriter!.finishWriting {
                //outputMovieURL now has the video
                Logger().info("Finished video")
            }
            episode!.title = assetWriter?.outputURL.deletingPathExtension().lastPathComponent
            episode!.end = Date()
            do {
                try PersistenceController.shared.container.viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }

        assetWriterInput = nil
        assetWriter = nil
        assetWriterAdaptor = nil
        frameCount = 0
        episode = nil
    }
    
    //
    // Push frame to encoder, run OCR
    //
    func addFrame(frame: CapturedFrame) {
        if assetWriter != nil {
            //            fatalError("Can't add a frame to an unopened episode")
            if assetWriterInput!.isReadyForMoreMediaData {
                let frameTime = CMTimeMake(value: Int64(frameCount), timescale: 1)
                //append the contents of the pixelBuffer at the correct time
                assetWriterAdaptor!.append(frame.data!, withPresentationTime: frameTime)
                frameCount += 1
            }
        }
    }
    
    func getOrCreateConcept(name: String) -> Concept {
        let conceptFetch : NSFetchRequest<Concept> = Concept.fetchRequest()
        conceptFetch.predicate = NSPredicate(format: "name == %@", name)
        do {
            let fetched = try PersistenceController.shared.container.viewContext.fetch(conceptFetch)
            if fetched.count > 0 {
                return fetched.first!
            }
        } catch {
            //failed, fallback to create
        }
        let concept = Concept(context: PersistenceController.shared.container.viewContext)
        concept.name = name
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return concept
    }
    
    private var concepts: Set<String> = Set()
    private var conceptTimes: Dictionary<String, DateInterval> = Dictionary()
    
    func update(force_close: Bool = false) {
        // debounce concepts with a 5s tail to allow frame-frame overlap, reducing rate of outflow
        let current_time = Date()
        var closed_concepts = Set<String>()
        for concept in concepts {
            let this_concept_time = conceptTimes[concept]!
            let diff = current_time.timeIntervalSince(this_concept_time.end)
            if diff > 5.0 || force_close {
                // close the concept interval
                let concept_data = getOrCreateConcept(name: concept)
                let newItem = Interval(context: PersistenceController.shared.container.viewContext)
                newItem.from = this_concept_time.start
                newItem.to = this_concept_time.end
                newItem.concept = concept_data
                newItem.episode = episode

                do {
                    try PersistenceController.shared.container.viewContext.save()
                } catch {
                    let nsError = error as NSError
                    fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
                }
                
                closed_concepts.insert(concept)
            }
        }
        for concept in closed_concepts {
            conceptTimes.removeValue(forKey: concept)
            concepts.remove(concept)
        }
//        print(concepts)
    }

    func observe(what: String) {
        if !concepts.contains(what) {
            conceptTimes[what] = DateInterval(start: Date(), end: Date())
            concepts.insert(what)
        } else {
            conceptTimes[what]!.end = Date()
        }
    }

//    private func forget(when: CMTimeRange) {
//        offsets.map { items[$0] }.forEach(PersistenceController.shared.container.viewContext.delete)
//
//        do {
//            try PersistenceController.shared.container.viewContext.save()
//        } catch {
//            // Replace this implementation with code to handle the error appropriately.
//            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//            let nsError = error as NSError
//            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//        }
//    }
}
