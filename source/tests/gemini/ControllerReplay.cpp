#include <QtCore>
// Test-only access; this translation unit never ships in NeutronShell.
#define private public
#include "ControllerManager.h"
#undef private
#include "ControllerReplay.h"
#include <fcntl.h>
#include <linux/input.h>
#include <unistd.h>
class ControllerReplay::Impl {
public:
    ControllerManager manager;
    int fds[2]{-1,-1};
    explicit Impl(ControllerReplay *owner):manager(owner) {
        manager.m_deviceScanTimer.stop();manager.m_batteryRefreshTimer.stop();
        manager.setLowLatencyInputMode(true);
        if(::pipe2(fds,O_NONBLOCK|O_CLOEXEC)!=0)qFatal("evdev replay pipe failed");
        ControllerManager::InputDevice device;device.fd=fds[0];device.path="evdev-regression-pipe";device.name="Linux gamepad replay";device.kind=ControllerManager::InputDeviceKind::GamepadInput;
        manager.configureMappings(device);manager.m_inputDevices.append(device);
        QObject::connect(&manager,&ControllerManager::buttonPressed,owner,&ControllerReplay::pressed);
        QObject::connect(&manager,&ControllerManager::buttonReleased,owner,&ControllerReplay::released);
    }
    ~Impl(){::close(fds[1]);}
};
ControllerReplay::ControllerReplay(QObject *parent):QObject(parent),impl(new Impl(this)){}
ControllerReplay::~ControllerReplay()=default;
void ControllerReplay::event(int code,int value){input_event input{};input.type=EV_KEY;input.code=code;input.value=value;if(::write(impl->fds[1],&input,sizeof(input))!=sizeof(input))qFatal("evdev replay write failed");impl->manager.drainInputDevice("evdev-regression-pipe");}
void ControllerReplay::tap(int code){event(code,1);event(code,0);}
