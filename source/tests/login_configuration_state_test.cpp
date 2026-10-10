#include "LoginConfigurationState.h"

#include <QCoreApplication>
#include <iostream>

namespace {
bool expect(bool condition, const char *message)
{
    if (condition)
        return true;
    std::cerr << message << '\n';
    return false;
}
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    using LoginConfiguration::State;
    using LoginConfiguration::allowsFirstRunSetup;
    using LoginConfiguration::fromLocalEvidence;

    bool ok = true;
    ok &= expect(fromLocalEvidence(true, true, true, true) == State::Configured,
                 "existing valid controller state must be configured");
    ok &= expect(fromLocalEvidence(false, true, true, true) == State::LoadingUnknown,
                 "delayed loading must remain unknown");
    ok &= expect(!allowsFirstRunSetup(State::LoadingUnknown),
                 "loading must never open first-run setup");
    ok &= expect(!allowsFirstRunSetup(State::SecurityUnavailable),
                 "Security unavailable must never open first-run setup");
    ok &= expect(!allowsFirstRunSetup(State::AuthorizationDenied),
                 "authorization denial must never open first-run setup");
    ok &= expect(!allowsFirstRunSetup(State::IpcFailure),
                 "IPC failure must never open first-run setup");
    ok &= expect(!allowsFirstRunSetup(State::StateCorrupt),
                 "corrupt state must never open first-run setup");
    ok &= expect(allowsFirstRunSetup(State::Unconfigured),
                 "only positively unconfigured state may open setup");
    ok &= expect(fromLocalEvidence(true, false, true, false) == State::Unconfigured,
                 "a true fresh install must be unconfigured");
    ok &= expect(fromLocalEvidence(true, true, false, true) == State::StateCorrupt,
                 "untrusted existing state must be corrupt, not fresh");
    return ok ? 0 : 1;
}
