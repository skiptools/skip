// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

package org.swift.test;

// Calls the generated JNI harness without instrumentation. Its class name must match the JNI
// entry point. Supply the MainActor fixture's native libraries and libSkipBridge.so, but no Skip
// Kotlin classes: the harness must reject the incomplete runtime before executing any test.
public final class SwiftTestRunner {
    private native int runTests();

    public void reportTestOutput(String line) {
        throw new AssertionError("Swift Testing started without its bridge prerequisites: " + line);
    }

    public static void main(String[] args) {
        System.load(args[0]);
        try {
            int result = new SwiftTestRunner().runTests();
            throw new AssertionError("Expected a missing-bridge exception, got result " + result);
        } catch (IllegalStateException error) {
            if (!error.getMessage().contains("Skip bridge Kotlin classes are missing")
                    || !error.getMessage().contains("connectedAndroidTest")) {
                throw new AssertionError("Expected the actionable bridge diagnostic", error);
            }
            System.out.println("PASS: missing bridge rejected before Swift Testing starts");
        }
    }
}
