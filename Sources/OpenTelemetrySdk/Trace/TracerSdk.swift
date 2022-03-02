/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetryApi

/// TracerSdk is SDK implementation of Tracer.
public class TracerSdk: Tracer {
    public let instrumentationLibraryInfo: InstrumentationLibraryInfo
    var sharedState: TracerSharedState

    init(sharedState: TracerSharedState, instrumentationLibraryInfo: InstrumentationLibraryInfo) {
        self.sharedState = sharedState
        self.instrumentationLibraryInfo = instrumentationLibraryInfo
    }

    public func spanBuilder(spanName: String) -> SpanBuilder {
        if sharedState.hasBeenShutdown {
            return DefaultTracer.instance.spanBuilder(spanName: spanName)
        }
        return SpanBuilderSdk(spanName: spanName,
                              instrumentationLibraryInfo: instrumentationLibraryInfo,
                              tracerSharedState: sharedState,
                              spanLimits: sharedState.activeSpanLimits)
    }
}

public class InterceptedTracerSdk: TracerSdk {
	
	public var parentSpan: Span?
	
	public override func spanBuilder(spanName: String) -> SpanBuilder {
		var builder = super.spanBuilder(spanName: spanName)

		if let parentSpan = parentSpan {
			builder = builder.setParent(parentSpan)
		}

		return builder
	}
}
