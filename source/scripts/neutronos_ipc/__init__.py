"""Shared authenticated local IPC primitives for privileged NeutronOS services."""

from .client import IpcClient
from .protocol import PROTOCOL_NAME, PROTOCOL_VERSION, ProtocolError, make_request
from .server import AuthorizationGrant, IpcServer, PeerCredentials, RequestContext

__all__ = [
    "IpcClient",
    "IpcServer",
    "AuthorizationGrant",
    "PeerCredentials",
    "PROTOCOL_NAME",
    "PROTOCOL_VERSION",
    "ProtocolError",
    "RequestContext",
    "make_request",
]
