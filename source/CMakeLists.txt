cmake_minimum_required(VERSION 3.21)

project(
    NeutronOS
    VERSION 0.5.9
    DESCRIPTION "NeutronOS Gemini Controller-First QML Shell"
    LANGUAGES CXX
)

# config/version.json is the canonical production release identity. CMake's
# numeric project version remains SemVer-core only; prerelease/build metadata
# is never inferred from Git at runtime.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/config/version.json" NEUTRONOS_VERSION_JSON)
string(JSON NEUTRONOS_RELEASE_VERSION GET "${NEUTRONOS_VERSION_JSON}" version)
string(JSON NEUTRONOS_RELEASE_ID GET "${NEUTRONOS_VERSION_JSON}" releaseId)
string(JSON NEUTRONOS_RELEASE_CHANNEL GET "${NEUTRONOS_VERSION_JSON}" channel)
string(JSON NEUTRONOS_RELEASE_BUILD GET "${NEUTRONOS_VERSION_JSON}" build)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC OFF)
set(CMAKE_AUTOUIC OFF)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
    set(
        CMAKE_BUILD_TYPE
        Release
        CACHE STRING "Build type"
        FORCE
    )
endif()

find_package(
    Qt6 6.2
    REQUIRED
    COMPONENTS
        Core
        Concurrent
        DBus
        Gui
        Network
        Qml
        Quick
        Quick3D
        WebSockets
        WebEngineQuick
)

find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)

pkg_check_modules(
    SODIUM
    REQUIRED
    IMPORTED_TARGET
    libsodium
)

find_library(
    PAM_LIBRARY
    NAMES pam
    REQUIRED
)

find_library(
    UTIL_LIBRARY
    NAMES util
)

set(NEUTRONOS_TARGET NeutronShell)

# Runtime paths are configurable so patch installers can compile in an
# isolated staging tree while producing a binary that resolves live assets
# from the installed NeutronOS root. Normal local builds keep the source tree
# as the runtime root.
set(
    NEUTRONOS_RUNTIME_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}"
    CACHE PATH
    "Installed NeutronOS runtime root"
)

set(
    NEUTRONOS_SOURCES

    src/main.cpp


    src/HumanAccountPolicy.h

    src/SetupWizardManager.cpp
    src/SetupWizardManager.h

    src/PersonalizationManager.cpp
    src/PersonalizationManager.h

    src/UserManager.cpp
    src/UserManager.h

    src/AssetManager.cpp
    src/AssetManager.h

    src/ControllerManager.cpp
    src/ControllerManager.h

    src/SecurityManager.cpp
    src/SecurityManager.h

    src/SecurityCoreManager.cpp
    src/SecurityCoreManager.h

    src/SecureIpcClient.cpp
    src/SecureIpcClient.h

    src/AppManager.cpp
    src/AppManager.h

    src/QuickActionManager.cpp
    src/QuickActionManager.h

    src/SystemMonitor.cpp
    src/SystemMonitor.h

    src/DashboardLayoutManager.cpp
    src/DashboardLayoutManager.h

    src/GeminiGeometry.cpp
    src/GeminiGeometry.h

    src/FractureEffect.cpp
    src/FractureEffect.h

    src/StorageManager.cpp
    src/StorageManager.h

    src/ScreensaverManager.cpp
    src/ScreensaverManager.h

    src/NetworkManager.cpp
    src/NetworkManager.h

    src/ClockSettingsManager.cpp
    src/ClockSettingsManager.h

    src/ClockExperienceManager.cpp
    src/ClockExperienceManager.h

    src/DockSecurityManager.cpp
    src/DockSecurityManager.h

    src/DeveloperModeManager.cpp
    src/DeveloperModeManager.h

    src/PrivilegeManager.cpp
    src/PrivilegeManager.h

    src/PowerModeManager.cpp
    src/PowerModeManager.h

    src/PerformanceManager.cpp
    src/PerformanceManager.h

    src/TerminalManager.cpp
    src/TerminalManager.h

    src/TerminalAssistManager.cpp
    src/TerminalAssistManager.h

    src/SettingsManager.cpp
    src/SettingsManager.h

    src/UpdateRecoveryManager.cpp
    src/UpdateRecoveryManager.h

    src/BackupRestoreManager.cpp
    src/BackupRestoreManager.h

    src/RecoveryModeManager.cpp
    src/RecoveryModeManager.h

    src/DiagnosticsManager.cpp
    src/DiagnosticsManager.h

    src/CoreCapabilitiesManager.cpp
    src/CoreCapabilitiesManager.h

    src/NotificationManager.cpp
    src/NotificationManager.h

    src/CaptureManager.cpp
    src/CaptureManager.h

    src/BrowserManager.cpp
    src/BrowserManager.h

    src/AppStoreManager.cpp
    src/AppStoreManager.h

    src/PackageAppBridgeManager.cpp
    src/PackageAppBridgeManager.h

    src/GalleryManager.cpp
    src/GalleryManager.h

    src/TextEditorManager.cpp
    src/TextEditorManager.h

    src/NeutronSyntaxHighlighter.cpp
    src/NeutronSyntaxHighlighter.h

    src/MusicPlayerManager.cpp
    src/MusicPlayerManager.h

    src/QBitTorrentManager.cpp
    src/QBitTorrentManager.h

    src/FileManager.cpp
    src/FileManager.h

    src/GamesManager.cpp
    src/GamesManager.h

    src/DockerManager.cpp
    src/DockerManager.h

    src/LogsManager.cpp
    src/LogsManager.h

    src/MediaOptimizerManager.cpp
    src/MediaOptimizerManager.h

    src/JellyfinManager.cpp
    src/JellyfinManager.h

    src/RemoteKeyboardManager.cpp
    src/RemoteKeyboardManager.h

    src/NeutronManagersQmlRegistration.cpp
)

# Application-native components ship precompiled in NAPPs; OS builds have a fixed source inventory.

foreach(NEUTRONOS_SOURCE IN LISTS NEUTRONOS_SOURCES)
    if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${NEUTRONOS_SOURCE}")
        message(
            FATAL_ERROR
            "Required NeutronOS source is missing: ${NEUTRONOS_SOURCE}"
        )
    endif()
endforeach()

qt_add_executable(
    ${NEUTRONOS_TARGET}
    MANUAL_FINALIZATION
    ${NEUTRONOS_SOURCES}
)

# NeutronOS loads QML directly from the filesystem at runtime and embeds no QML
# files in NeutronShell. Qt's automatic executable QML import scan recursively
# walks the whole source root, including legacy .patch-backups trees. Disable
# that scan so backup snapshots are never parsed as live application QML.
set_target_properties(
    ${NEUTRONOS_TARGET}
    PROPERTIES
        QT_QML_MODULE_NO_IMPORT_SCAN TRUE
)

target_include_directories(
    ${NEUTRONOS_TARGET}
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_compile_definitions(
    ${NEUTRONOS_TARGET}
    PRIVATE
        NEUTRONOS_NAME="NeutronOS"
        NEUTRONOS_CODENAME="Gemini"
        NEUTRONOS_VERSION="${NEUTRONOS_RELEASE_VERSION}"
        NEUTRONOS_RELEASE_ID="${NEUTRONOS_RELEASE_ID}"
        NEUTRONOS_RELEASE_CHANNEL="${NEUTRONOS_RELEASE_CHANNEL}"
        NEUTRONOS_RELEASE_BUILD=${NEUTRONOS_RELEASE_BUILD}

        NEUTRONOS_PROJECT_ROOT="${NEUTRONOS_RUNTIME_ROOT}"
        NEUTRONOS_QML_ROOT="${NEUTRONOS_RUNTIME_ROOT}/qml"
        NEUTRONOS_THEME_ROOT="${NEUTRONOS_RUNTIME_ROOT}/themes/Default"
        NEUTRONOS_CONFIG_ROOT="${NEUTRONOS_RUNTIME_ROOT}/config"

        NEUTRONOS_STATE_DIR="/var/lib/neutronos"
        NEUTRONOS_SECURITY_STATE_DIR="/var/lib/neutronos/security"
        NEUTRONOS_LOG_DIR="/var/log/neutronos"
)

target_compile_options(
    ${NEUTRONOS_TARGET}
    PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall>
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wextra>
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wpedantic>
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wno-unused-parameter>
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wno-missing-field-initializers>
)

target_link_libraries(
    ${NEUTRONOS_TARGET}
    PRIVATE
        Qt6::Core
        Qt6::Concurrent
        Qt6::DBus
        Qt6::Gui
        Qt6::Network
        Qt6::Qml
        Qt6::Quick
        Qt6::Quick3D
        Qt6::WebSockets

        Threads::Threads
        PkgConfig::SODIUM
        ${PAM_LIBRARY}
)

if(UTIL_LIBRARY)
    target_link_libraries(
        ${NEUTRONOS_TARGET}
        PRIVATE
            ${UTIL_LIBRARY}
    )
endif()

if(UNIX AND NOT APPLE)
    target_compile_definitions(
        ${NEUTRONOS_TARGET}
        PRIVATE
            NEUTRONOS_LINUX=1
    )
endif()

set_target_properties(
    ${NEUTRONOS_TARGET}
    PROPERTIES
        OUTPUT_NAME "NeutronShell"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

qt_finalize_executable(${NEUTRONOS_TARGET})

set(NEUTRON_BROWSER_TARGET NeutronBrowser)
qt_add_executable(
    ${NEUTRON_BROWSER_TARGET}
    MANUAL_FINALIZATION
    src/browser_main.cpp
    src/BrowserManager.cpp
    src/BrowserManager.h
    src/CaptureManager.cpp
    src/CaptureManager.h
    src/NotificationManager.cpp
    src/NotificationManager.h
    src/ControllerManager.cpp
    src/ControllerManager.h
    src/RemoteKeyboardManager.cpp
    src/RemoteKeyboardManager.h
    src/RemoteKeyboardQmlRegistration.cpp
)
set_target_properties(
    ${NEUTRON_BROWSER_TARGET}
    PROPERTIES
        QT_QML_MODULE_NO_IMPORT_SCAN TRUE
)
target_include_directories(${NEUTRON_BROWSER_TARGET} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_compile_definitions(
    ${NEUTRON_BROWSER_TARGET}
    PRIVATE
        NEUTRONOS_PROJECT_ROOT="${NEUTRONOS_RUNTIME_ROOT}"
        NEUTRONOS_LINUX=1
)
target_compile_options(
    ${NEUTRON_BROWSER_TARGET}
    PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall>
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wextra>
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wpedantic>
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wno-unused-parameter>
)
target_link_libraries(
    ${NEUTRON_BROWSER_TARGET}
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Network
        Qt6::Qml
        Qt6::Quick
        Qt6::WebEngineQuick
        Threads::Threads
)
set_target_properties(
    ${NEUTRON_BROWSER_TARGET}
    PROPERTIES
        OUTPUT_NAME "NeutronBrowser"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
qt_finalize_executable(${NEUTRON_BROWSER_TARGET})

include(CTest)
if(BUILD_TESTING)
    qt_add_executable(NeutronTelemetryMathTest tests/telemetry_math_test.cpp)
    target_include_directories(NeutronTelemetryMathTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(NeutronTelemetryMathTest PRIVATE Qt6::Core)
    add_test(NAME telemetry-math COMMAND NeutronTelemetryMathTest)
    qt_add_executable(NeutronLoginConfigurationStateTest tests/login_configuration_state_test.cpp)
    target_include_directories(NeutronLoginConfigurationStateTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(NeutronLoginConfigurationStateTest PRIVATE Qt6::Core)
    add_test(NAME login-configuration-state COMMAND NeutronLoginConfigurationStateTest)
    qt_add_executable(NeutronDashboardLayoutTest
        tests/dashboard_layout_manager_test.cpp
        src/DashboardLayoutManager.cpp
        src/DashboardLayoutManager.h)
    target_include_directories(NeutronDashboardLayoutTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(NeutronDashboardLayoutTest PRIVATE Qt6::Core)
    add_test(NAME dashboard-layout COMMAND NeutronDashboardLayoutTest)
    qt_add_executable(NeutronNotificationManagerTest
        tests/notification_manager_test.cpp
        src/NotificationManager.cpp
        src/NotificationManager.h)
    target_include_directories(NeutronNotificationManagerTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(NeutronNotificationManagerTest PRIVATE Qt6::Core)
    add_test(NAME notification-manager COMMAND NeutronNotificationManagerTest)
    qt_add_executable(NeutronAuthenticatedNotificationTest
        tests/authenticated_notification_test.cpp
        src/SecurityManager.cpp
        src/SecurityManager.h
        src/NotificationManager.cpp
        src/NotificationManager.h)
    target_include_directories(NeutronAuthenticatedNotificationTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_compile_definitions(NeutronAuthenticatedNotificationTest PRIVATE
        NEUTRONOS_STATE_DIR="/var/lib/neutronos"
        NEUTRONOS_SECURITY_STATE_DIR="/var/lib/neutronos/security")
    target_link_libraries(NeutronAuthenticatedNotificationTest PRIVATE
        Qt6::Core Qt6::Concurrent PkgConfig::SODIUM ${PAM_LIBRARY} Threads::Threads)

    qt_add_executable(NeutronUpdateRecoveryManagerTest
        tests/update_recovery_manager_test.cpp
        src/UpdateRecoveryManager.cpp
        src/UpdateRecoveryManager.h
        src/DeveloperModeManager.cpp
        src/DeveloperModeManager.h)
    target_include_directories(NeutronUpdateRecoveryManagerTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(NeutronUpdateRecoveryManagerTest PRIVATE Qt6::Core Qt6::Concurrent Qt6::Network PkgConfig::SODIUM)
    add_test(NAME update-recovery-manager COMMAND NeutronUpdateRecoveryManagerTest)

    qt_add_executable(NeutronRecoveryModeManagerTest
        tests/recovery_mode_manager_test.cpp
        src/RecoveryModeManager.cpp
        src/RecoveryModeManager.h)
    target_include_directories(NeutronRecoveryModeManagerTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
    target_link_libraries(NeutronRecoveryModeManagerTest PRIVATE Qt6::Core)
    add_test(NAME recovery-mode-manager COMMAND NeutronRecoveryModeManagerTest)
endif()


install(
    TARGETS ${NEUTRONOS_TARGET} ${NEUTRON_BROWSER_TARGET}
    RUNTIME DESTINATION bin
)

message(STATUS "NeutronOS target: ${NEUTRONOS_TARGET}")
message(STATUS "NeutronOS version: ${NEUTRONOS_RELEASE_VERSION}")
message(STATUS "NeutronOS release: ${NEUTRONOS_RELEASE_ID} (${NEUTRONOS_RELEASE_CHANNEL})")
message(STATUS "NeutronOS build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "NeutronOS runtime root: ${NEUTRONOS_RUNTIME_ROOT}")
message(STATUS "Terminal backend: TerminalManager + TerminalAssistManager")
message(STATUS "File Manager backend: FileManager")
message(STATUS "Browser: isolated unprivileged NeutronBrowser + Qt WebEngine Quick")
message(STATUS "App Store: signed packages + trusted repositories + transactional rollback")
message(STATUS "NeutronOS source root: ${CMAKE_CURRENT_SOURCE_DIR}")

message(STATUS "QML runtime mode: filesystem")
message(STATUS "QML root: ${CMAKE_CURRENT_SOURCE_DIR}/qml")
message(STATUS "Theme asset mode: filesystem")
message(STATUS "Theme root: ${CMAKE_CURRENT_SOURCE_DIR}/themes/Default")
message(STATUS "App loading mode: filesystem")

message(STATUS "Security state path: /var/lib/neutronos/security")
message(STATUS "Terminal state path: /var/lib/neutronos/terminal")
message(STATUS "NeutronOS log path: /var/log/neutronos")
message(STATUS "KDF backend: libsodium Argon2id")

message(STATUS "System Overview backends: SystemMonitor, NetworkManager, ClockSettingsManager, UserManager")
message(STATUS "Security backends: SecurityManager, DockSecurityManager, DeveloperModeManager")
message(STATUS "Terminal backend: TerminalManager + TerminalAssistManager")
message(STATUS "File Manager backend: FileManager")

message(STATUS "No QML files are embedded in this build.")
message(STATUS "No PNG/JPG/WebP/SVG theme assets are embedded in this build.")
message(STATUS "No app folders are embedded in this build.")

message(STATUS "Drop-in apps path: ~/NeutronOS/qml/apps/<appId>/")
message(STATUS "Theme icons path: ~/NeutronOS/themes/Default/apps/icons/")
message(STATUS "Theme posters path: ~/NeutronOS/themes/Default/apps/posters/")
message(STATUS "User assets path: ~/NeutronOS/themes/Default/users/")

message(STATUS "PAM library: ${PAM_LIBRARY}")
message(STATUS "libsodium include dirs: ${SODIUM_INCLUDE_DIRS}")
message(STATUS "libsodium libraries: ${SODIUM_LIBRARIES}")

if(UTIL_LIBRARY)
    message(STATUS "util library: ${UTIL_LIBRARY}")
else()
    message(STATUS "util library: not found; forkpty/openpty must be available through libc")
endif()

# Gemini uses standard Debian graphics; no Apollo renderer target exists.
target_compile_definitions(NeutronShell PRIVATE NEUTRONOS_PLATFORM_GEMINI=1)
target_compile_definitions(NeutronBrowser PRIVATE NEUTRONOS_PLATFORM_GEMINI=1)
