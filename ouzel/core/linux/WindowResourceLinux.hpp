// Copyright (C) 2018 Elviss Strazdins
// This file is part of the Ouzel engine.

#pragma once

#include <cstdint>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "core/WindowResource.hpp"

namespace ouzel
{
    class Window;
    class EngineLinux;

    class WindowResourceLinux: public WindowResource
    {
        friend Window;
        friend EngineLinux;
    public:
        virtual ~WindowResourceLinux();

        virtual void close() override;

        virtual void setSize(const Size2& newSize) override;
        virtual void setFullscreen(bool newFullscreen) override;
        virtual void setTitle(const std::string& newTitle) override;

        inline Display* getDisplay() const { return display; }
        inline ::Window getNativeWindow() const { return window; }
        inline XVisualInfo* getVisualInfo() const { return visualInfo; }
        inline Atom getProtocolsAtom() const { return protocolsAtom; }
        inline Atom getDeleteAtom() const { return deleteAtom; }
        inline Atom getExecuteAtom() const { return executeAtom; }

    protected:
        WindowResourceLinux();
        virtual bool init(const Size2& newSize,
                          bool newResizable,
                          bool newFullscreen,
                          bool newExclusiveFullscreen,
                          const std::string& newTitle,
                          bool newHighDpi,
                          bool depth) override;
        virtual bool toggleFullscreen();
        void handleResize(const Size2& newSize);

        XVisualInfo* visualInfo = nullptr;
        Display* display = nullptr;
        ::Window window = 0;
        Atom deleteAtom;
        Atom protocolsAtom;
        Atom stateAtom;
        Atom stateFullscreenAtom;
        Atom executeAtom;
    };
}
