// Copyright (C) 2017 Elviss Strazdins
// This file is part of the Ouzel engine.

#include "RendererOGLMacOS.h"
#include "core/macos/WindowMacOS.h"
#include "utils/Log.h"

namespace ouzel
{
    namespace graphics
    {
        RendererOGLMacOS::~RendererOGLMacOS()
        {
            if (openGLContext)
            {
                [NSOpenGLContext clearCurrentContext];
                [openGLContext release];
            }

            if (pixelFormat)
            {
                [pixelFormat release];
            }
        }

        bool RendererOGLMacOS::init(Window* newWindow,
                                    const Size2& newSize,
                                    uint32_t newSampleCount,
                                    Texture::Filter newTextureFilter,
                                    uint32_t newMaxAnisotropy,
                                    PixelFormat newBackBufferFormat,
                                    bool newVerticalSync,
                                    bool newDepth)
        {
            // Create pixel format
            std::vector<NSOpenGLPixelFormatAttribute> openGL3Attributes =
            {
                NSOpenGLPFAAccelerated,
                NSOpenGLPFANoRecovery,
                NSOpenGLPFADoubleBuffer,
                NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
                NSOpenGLPFAColorSize, 24,
            };

            if (newDepth)
            {
                openGL3Attributes.push_back(NSOpenGLPFADepthSize);
                openGL3Attributes.push_back(static_cast<NSOpenGLPixelFormatAttribute>(newDepth ? 24 : 0));
            }

            if (newSampleCount)
            {
                openGL3Attributes.push_back(NSOpenGLPFAMultisample);
                openGL3Attributes.push_back(NSOpenGLPFASampleBuffers);
                openGL3Attributes.push_back(1);
                openGL3Attributes.push_back(NSOpenGLPFASamples);
                openGL3Attributes.push_back(newSampleCount);
            }

            openGL3Attributes.push_back(0);

            pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:openGL3Attributes.data()];

            if (pixelFormat)
            {
                apiMajorVersion = 3;
                apiMinorVersion = 2;
                Log(Log::Level::INFO) << "OpenGL 3.2 pixel format created";
            }
            else
            {
                std::vector<NSOpenGLPixelFormatAttribute> openGL2Attributes =
                {
                    NSOpenGLPFAAccelerated,
                    NSOpenGLPFANoRecovery,
                    NSOpenGLPFADoubleBuffer,
                    NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
                    NSOpenGLPFAColorSize, 24,
                };

                if (newDepth)
                {
                    openGL2Attributes.push_back(NSOpenGLPFADepthSize);
                    openGL2Attributes.push_back(static_cast<NSOpenGLPixelFormatAttribute>(newDepth ? 24 : 0));
                }

                if (newSampleCount)
                {
                    openGL2Attributes.push_back(NSOpenGLPFAMultisample);
                    openGL2Attributes.push_back(NSOpenGLPFASampleBuffers);
                    openGL2Attributes.push_back(1);
                    openGL2Attributes.push_back(NSOpenGLPFASamples);
                    openGL2Attributes.push_back(newSampleCount);
                }

                openGL2Attributes.push_back(0);

                pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:openGL2Attributes.data()];

                if (pixelFormat)
                {
                    apiMajorVersion = 2;
                    apiMinorVersion = 0;
                    Log(Log::Level::INFO) << "OpenGL 2 pixel format created";
                }
            }

            if (!pixelFormat)
            {
                Log(Log::Level::ERR) << "Failed to crete OpenGL pixel format";
                return Nil;
            }

            // Create OpenGL context
            openGLContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:NULL];
            [openGLContext makeCurrentContext];

            WindowMacOS* windowMacOS = static_cast<WindowMacOS*>(newWindow);
            [openGLContext setView:windowMacOS->getNativeView()];

            GLint swapInt = newVerticalSync ? 1 : 0;
            [openGLContext setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];

            return RendererOGL::init(newWindow,
                                     newSize,
                                     newSampleCount,
                                     newTextureFilter,
                                     newMaxAnisotropy,
                                     newBackBufferFormat,
                                     newVerticalSync,
                                     newDepth);
        }

        bool RendererOGLMacOS::lockContext()
        {
            [openGLContext makeCurrentContext];

            return true;
        }

        bool RendererOGLMacOS::swapBuffers()
        {
            [openGLContext flushBuffer];

            return true;
        }

        bool RendererOGLMacOS::upload()
        {
            [openGLContext update];

            return RendererOGL::upload();
        }
    } // namespace graphics
} // namespace ouzel
