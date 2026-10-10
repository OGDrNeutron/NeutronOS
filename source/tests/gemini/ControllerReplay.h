#pragma once
#include <QObject>
#include <memory>
class ControllerReplay final: public QObject {
    Q_OBJECT
public:
    explicit ControllerReplay(QObject *parent=nullptr);
    ~ControllerReplay() override;
    Q_INVOKABLE void event(int code,int value);
    Q_INVOKABLE void tap(int code);
signals:
    void pressed(QString action);
    void released(QString action);
private:
    class Impl;
    std::unique_ptr<Impl> impl;
};
