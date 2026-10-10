import QtQuick
import QtTest
import "../../qml/gemini" as Gemini
TestCase {
    name:"GeminiQualitySampling";when:windowShown
    Gemini.GeminiRenderQuality{id:quality}
    function test_backend_pause_resets_measurement_without_changing_quality(){
        quality.level=2;quality.active=true;quality.sampleSeconds=2.8;quality.sampleFrames=100
        quality.active=false
        compare(quality.sampleSeconds,0);compare(quality.sampleFrames,0);compare(quality.level,2)
        verify(quality.discardResumeFrame)
        quality.active=true;compare(quality.sampleSeconds,0);compare(quality.sampleFrames,0);compare(quality.level,2)
        quality.active=false
    }
}
