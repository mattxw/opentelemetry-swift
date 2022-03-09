/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

public class TracerProviderSdk: TracerProvider {
    internal var tracerProvider = [InstrumentationLibraryInfo: TracerSdk]()
    internal var sharedState: TracerSharedState
    internal static let emptyName = "unknown"

    /// Returns a new TracerProviderSdk with default Clock, IdGenerator and Resource.
    public init(clock: Clock = MillisClock(),
                idGenerator: IdGenerator = RandomIdGenerator(),
                resource: Resource = EnvVarResource.resource,
                spanLimits: SpanLimits = SpanLimits(),
                sampler: Sampler = Samplers.parentBased(root: Samplers.alwaysOn),
                spanProcessors: [SpanProcessor] = [])
    {
        sharedState = TracerSharedState(clock: clock,
                                        idGenerator: idGenerator,
                                        resource: resource,
                                        spanLimits: spanLimits,
                                        sampler: sampler,
                                        spanProcessors: spanProcessors)
    }

    public func get(instrumentationName: String, instrumentationVersion: String? = nil) -> Tracer {
        if sharedState.hasBeenShutdown {
            return DefaultTracer.instance
        }

        var instrumentationName = instrumentationName
        if instrumentationName.isEmpty {
            // Per the spec, empty is "invalid"
            print("Tracer requested without instrumentation name.")
            instrumentationName = TracerProviderSdk.emptyName
        }
        let instrumentationLibraryInfo = InstrumentationLibraryInfo(name: instrumentationName, version: instrumentationVersion ?? "")
        if let tracer = tracerProvider[instrumentationLibraryInfo] {
            return tracer
        } else {
            // Re-check if the value was added since the previous check, this can happen if multiple
            // threads try to access the same named tracer during the same time. This way we ensure that
            // we create only one TracerSdk per name.
            if let tracer = tracerProvider[instrumentationLibraryInfo] {
                // A different thread already added the named Tracer, just reuse.
                return tracer
            }
            let tracer = TracerSdk(sharedState: sharedState, instrumentationLibraryInfo: instrumentationLibraryInfo)
            tracerProvider[instrumentationLibraryInfo] = tracer
            return tracer
        }
    }

    /// Returns the active Clock.
    public func getActiveClock() -> Clock {
        return sharedState.clock
    }

    /// Updates the active Clock.
    public func updateActiveClock(_ newClock: Clock) {
        sharedState.clock = newClock
    }

    /// Returns the active IdGenerator.
    public func getActiveIdGenerator() -> IdGenerator {
        return sharedState.idGenerator
    }

    /// Updates the active IdGenerator.
    public func updateActiveIdGenerator(_ newGenerator: IdGenerator) {
        sharedState.idGenerator = newGenerator
    }

    /// Returns the active Resource.
    public func getActiveResource() -> Resource {
        return sharedState.resource
    }

    /// Updates the active Resource.
    public func updateActiveResource(_ newResource: Resource) {
        sharedState.resource = newResource
    }

    /// Returns the active SpanLimits.
    public func getActiveSpanLimits() -> SpanLimits {
        return sharedState.activeSpanLimits
    }

    /// Updates the active SpanLimits.
    public func updateActiveSpanLimits(_ spanLimits: SpanLimits) {
        sharedState.setActiveSpanLimits(spanLimits)
    }

    /// Returns the active Sampler.
    public func getActiveSampler() -> Sampler {
        return sharedState.sampler
    }

    /// Updates the active Sampler.
    public func updateActiveSampler(_ newSampler: Sampler) {
        sharedState.setSampler(newSampler)
    }

    /// Returns the active SpanProcessors.
    public func getActiveSpanProcessors() -> [SpanProcessor] {
        if let processor = sharedState.activeSpanProcessor as? MultiSpanProcessor {
            return processor.spanProcessorsAll
        } else {
            return [sharedState.activeSpanProcessor]
        }
    }

    /// Adds a new SpanProcessor to this TracerProvider.
    /// Any registered processor cause overhead, consider to use an async/batch processor especially
    /// for span exporting, and export to multiple backends using the MultiSpanExporter
    /// - Parameter spanProcessor: the new SpanProcessor to be added.
    public func addSpanProcessor(_ spanProcessor: SpanProcessor) {
        sharedState.addSpanProcessor(spanProcessor)
    }

    /// Removes all SpanProcessors from this provider
    public func resetSpanProcessors() {
        sharedState.activeSpanProcessor = NoopSpanProcessor()
    }

    /// Attempts to stop all the activity for this Tracer. Calls SpanProcessor.shutdown()
    /// for all registered SpanProcessors.
    /// This operation may block until all the Spans are processed. Must be called before turning
    /// off the main application to ensure all data are processed and exported.
    /// After this is called all the newly created Spanss will be no-op.
    public func shutdown() {
        if sharedState.hasBeenShutdown {
            return
        }
        sharedState.stop()
    }

    /// Requests the active span processor to process all span events that have not yet been processed.
    public func forceFlush(timeout: TimeInterval? = nil) {
        sharedState.activeSpanProcessor.forceFlush(timeout: timeout)
    }
}

public class InterceptedTracerProviderSdk: TracerProviderSdk {
	
	public var parentSpan: Span? {
		didSet {
			tracerProvider.values.forEach({
				($0 as? InterceptedTracerSdk)?.parentSpan = parentSpan
			})
		}
	}
	
	public override init(clock: Clock = MillisClock(), idGenerator: IdGenerator = RandomIdGenerator(), resource: Resource = EnvVarResource.resource, spanLimits: SpanLimits = SpanLimits(), sampler: Sampler = Samplers.parentBased(root: Samplers.alwaysOn), spanProcessors: [SpanProcessor] = []) {
		super.init(clock: clock, idGenerator: idGenerator, resource: resource, spanLimits: spanLimits, sampler: sampler, spanProcessors: spanProcessors)
	}
	
	public override func get(instrumentationName: String, instrumentationVersion: String? = nil) -> Tracer {
		if sharedState.hasBeenShutdown {
			return DefaultTracer.instance
		}

		var instrumentationName = instrumentationName
		if instrumentationName.isEmpty {
			// Per the spec, empty is "invalid"
			print("Tracer requested without instrumentation name.")
			instrumentationName = TracerProviderSdk.emptyName
		}
		let instrumentationLibraryInfo = InstrumentationLibraryInfo(name: instrumentationName, version: instrumentationVersion ?? "")
		if let tracer = tracerProvider[instrumentationLibraryInfo] {
			return tracer
		} else {
			// Re-check if the value was added since the previous check, this can happen if multiple
			// threads try to access the same named tracer during the same time. This way we ensure that
			// we create only one TracerSdk per name.
			if let tracer = tracerProvider[instrumentationLibraryInfo] {
				// A different thread already added the named Tracer, just reuse.
				return tracer
			}
			let tracer = InterceptedTracerSdk(sharedState: sharedState, instrumentationLibraryInfo: instrumentationLibraryInfo)
			tracer.parentSpan = parentSpan
			tracerProvider[instrumentationLibraryInfo] = tracer
			return tracer
		}
	}

}
