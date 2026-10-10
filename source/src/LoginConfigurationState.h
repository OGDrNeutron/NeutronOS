#pragma once

#include <QString>

namespace LoginConfiguration
{
enum class State {
    LoadingUnknown,
    Configured,
    Unconfigured,
    SecurityUnavailable,
    AuthorizationDenied,
    IpcFailure,
    StateCorrupt
};

inline State fromLocalEvidence(bool loadComplete,
                               bool recordExists,
                               bool ownerTrusted,
                               bool recordValid,
                               bool setupCompleted = false)
{
    if (!loadComplete)
        return State::LoadingUnknown;
    if (!recordExists)
        return setupCompleted ? State::StateCorrupt : State::Unconfigured;
    if (!ownerTrusted || !recordValid)
        return State::StateCorrupt;
    return State::Configured;
}

inline bool allowsFirstRunSetup(State state)
{
    return state == State::Unconfigured;
}

inline QString name(State state)
{
    switch (state) {
    case State::LoadingUnknown: return QStringLiteral("LOADING_UNKNOWN");
    case State::Configured: return QStringLiteral("CONFIGURED");
    case State::Unconfigured: return QStringLiteral("UNCONFIGURED");
    case State::SecurityUnavailable: return QStringLiteral("SECURITY_UNAVAILABLE");
    case State::AuthorizationDenied: return QStringLiteral("AUTHORIZATION_DENIED");
    case State::IpcFailure: return QStringLiteral("IPC_FAILURE");
    case State::StateCorrupt: return QStringLiteral("STATE_CORRUPT");
    }
    return QStringLiteral("LOADING_UNKNOWN");
}
}
