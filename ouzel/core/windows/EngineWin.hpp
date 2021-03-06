// Copyright (C) 2018 Elviss Strazdins
// This file is part of the Ouzel engine.

#pragma once

#include "core/Engine.hpp"

namespace ouzel
{
    class EngineWin : public Engine
    {
    public:
        EngineWin(int initArgc, LPWSTR* initArgv);
        virtual ~EngineWin();

        virtual int run() override;

        virtual void executeOnMainThread(const std::function<void(void)>& func) override;
        virtual bool openURL(const std::string& url) override;

        void executeAll();

    protected:
        std::queue<std::function<void(void)>> executeQueue;
        Mutex executeMutex;
    };
}
