// Copyright (C) 2018 Elviss Strazdins
// This file is part of the Ouzel engine.

#include <windows.h>
#include "EngineWin.hpp"

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int)
{
    UniquePtr<ouzel::EngineWin> engine(new ouzel::EngineWin());

    int result = engine->run();
    engine.reset(); // must release engine instance before exit on Windows

    return result;
}
