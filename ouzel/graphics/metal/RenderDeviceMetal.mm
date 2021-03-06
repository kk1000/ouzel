// Copyright (C) 2018 Elviss Strazdins
// This file is part of the Ouzel engine.

#include "core/Setup.h"

#include <cassert>

#if OUZEL_COMPILE_METAL

#include "RenderDeviceMetal.hpp"
#include "TextureResourceMetal.hpp"
#include "ShaderResourceMetal.hpp"
#include "BufferResourceMetal.hpp"
#include "BlendStateResourceMetal.hpp"
#include "events/EventDispatcher.hpp"

#if OUZEL_PLATFORM_MACOS
#include "metal/ColorPSMacOS.h"
#include "metal/ColorVSMacOS.h"
#include "metal/TexturePSMacOS.h"
#include "metal/TextureVSMacOS.h"
#define COLOR_PIXEL_SHADER_METAL ColorPSMacOS_metallib
#define COLOR_VERTEX_SHADER_METAL ColorVSMacOS_metallib
#define TEXTURE_PIXEL_SHADER_METAL TexturePSMacOS_metallib
#define TEXTURE_VERTEX_SHADER_METAL TextureVSMacOS_metallib

#elif OUZEL_PLATFORM_TVOS
#include "metal/ColorPSTVOS.h"
#include "metal/ColorVSTVOS.h"
#include "metal/TexturePSTVOS.h"
#include "metal/TextureVSTVOS.h"
#define COLOR_PIXEL_SHADER_METAL ColorPSTVOS_metallib
#define COLOR_VERTEX_SHADER_METAL ColorVSTVOS_metallib
#define TEXTURE_PIXEL_SHADER_METAL TexturePSTVOS_metallib
#define TEXTURE_VERTEX_SHADER_METAL TextureVSTVOS_metallib

#elif OUZEL_PLATFORM_IOS
#include "metal/ColorPSIOS.h"
#include "metal/ColorVSIOS.h"
#include "metal/TexturePSIOS.h"
#include "metal/TextureVSIOS.h"
#define COLOR_PIXEL_SHADER_METAL ColorPSIOS_metallib
#define COLOR_VERTEX_SHADER_METAL ColorVSIOS_metallib
#define TEXTURE_PIXEL_SHADER_METAL TexturePSIOS_metallib
#define TEXTURE_VERTEX_SHADER_METAL TextureVSIOS_metallib
#endif

#include "core/Engine.hpp"
#include "assets/Cache.hpp"
#include "thread/Lock.hpp"
#include "utils/Log.hpp"
#include "utils/Utils.hpp"
#include "stb_image_write.h"

static const size_t BUFFER_SIZE = 1024 * 1024; // size of shader constant buffer
static const size_t BUFFER_COUNT = 3; // allow encoding up to 3 command buffers simultaneously

namespace ouzel
{
    namespace graphics
    {
        bool RenderDeviceMetal::available()
        {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();

            if (device)
            {
                [device release];
                return true;
            }

            return false;
        }

        RenderDeviceMetal::RenderDeviceMetal():
            RenderDevice(Renderer::Driver::METAL)
        {
            apiMajorVersion = 1;
            apiMinorVersion = 0;

            std::fill(std::begin(depthStencilStates), std::end(depthStencilStates), nil);
        }

        RenderDeviceMetal::~RenderDeviceMetal()
        {
            resourceDeleteSet.clear();
            resources.clear();

            for (const ShaderConstantBuffer& shaderConstantBuffer : shaderConstantBuffers)
            {
                [shaderConstantBuffer.buffer release];
            }

            for (id<MTLDepthStencilState> depthStencilState : depthStencilStates)
            {
                if (depthStencilState) [depthStencilState release];
            }

            for (const auto& samplerState : samplerStates)
            {
                [samplerState.second release];
            }

            if (depthTexture) [depthTexture release];

            if (msaaTexture) [msaaTexture release];

            for (const auto& pipelineState : pipelineStates)
            {
                [pipelineState.second release];
            }

            if (commandQueue) [commandQueue release];

            if (renderPassDescriptor) [renderPassDescriptor release];

            if (device) [device release];

            if (currentMetalTexture) [currentMetalTexture release];
        }

        bool RenderDeviceMetal::init(Window* newWindow,
                                     const Size2& newSize,
                                     uint32_t newSampleCount,
                                     Texture::Filter newTextureFilter,
                                     uint32_t newMaxAnisotropy,
                                     bool newVerticalSync,
                                     bool newDepth,
                                     bool newDebugRenderer)
        {
            if (!RenderDevice::init(newWindow,
                                    newSize,
                                    newSampleCount,
                                    newTextureFilter,
                                    newMaxAnisotropy,
                                    newVerticalSync,
                                    newDepth,
                                    newDebugRenderer))
            {
                return false;
            }

            inflightSemaphore = dispatch_semaphore_create(BUFFER_COUNT);

            device = MTLCreateSystemDefaultDevice();

            if (!device)
            {
                Log(Log::Level::ERR) << "Failed to create Metal device";
                return false;
            }

            if (device.name)
                Log(Log::Level::INFO) << "Using " << [device.name cStringUsingEncoding:NSUTF8StringEncoding] << " for rendering";

            commandQueue = [device newCommandQueue];

            if (!commandQueue)
            {
                Log(Log::Level::ERR) << "Failed to create Metal command queue";
                return false;
            }

            if (depth) depthFormat = MTLPixelFormatDepth32Float;

            uint32_t depthStencilStateIndex = 0;

            for (uint32_t depthEnable = 0; depthEnable < 2; ++depthEnable)
            {
                for (uint32_t depthWriteMask = 0; depthWriteMask < 2; ++depthWriteMask)
                {
                    MTLDepthStencilDescriptor* depthStencilDescriptor = [MTLDepthStencilDescriptor new];

                    depthStencilDescriptor.depthCompareFunction = (depthEnable == 0) ? MTLCompareFunctionAlways : MTLCompareFunctionLessEqual; // depth read
                    depthStencilDescriptor.depthWriteEnabled = (depthWriteMask == 0) ? NO : YES; // depth write
                    depthStencilStates[depthStencilStateIndex] = [device newDepthStencilStateWithDescriptor:depthStencilDescriptor];
                    [depthStencilDescriptor release];

                    ++depthStencilStateIndex;
                }
            }

            renderPassDescriptor = [[MTLRenderPassDescriptor renderPassDescriptor] retain];

            if (!renderPassDescriptor)
            {
                Log(Log::Level::ERR) << "Failed to create Metal render pass descriptor";
                return false;
            }

            renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(clearColor.normR(),
                                                                                    clearColor.normG(),
                                                                                    clearColor.normB(),
                                                                                    clearColor.normA());
            renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
            renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
            renderPassDescriptor.depthAttachment.clearDepth = clearDepth;
            renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionStore;

            std::shared_ptr<Shader> textureShader = std::make_shared<Shader>();
            textureShader->init(std::vector<uint8_t>(std::begin(TEXTURE_PIXEL_SHADER_METAL), std::end(TEXTURE_PIXEL_SHADER_METAL)),
                                std::vector<uint8_t>(std::begin(TEXTURE_VERTEX_SHADER_METAL), std::end(TEXTURE_VERTEX_SHADER_METAL)),
                                {Vertex::Attribute::Usage::POSITION, Vertex::Attribute::Usage::COLOR, Vertex::Attribute::Usage::TEXTURE_COORDINATES0},
                                {{"color", DataType::FLOAT_VECTOR4}},
                                {{"modelViewProj", DataType::FLOAT_MATRIX4}},
                                256, 256,
                                "mainPS", "mainVS");

            engine->getCache()->setShader(SHADER_TEXTURE, textureShader);

            std::shared_ptr<Shader> colorShader = std::make_shared<Shader>();
            colorShader->init(std::vector<uint8_t>(std::begin(COLOR_PIXEL_SHADER_METAL), std::end(COLOR_PIXEL_SHADER_METAL)),
                              std::vector<uint8_t>(std::begin(COLOR_VERTEX_SHADER_METAL), std::end(COLOR_VERTEX_SHADER_METAL)),
                              {Vertex::Attribute::Usage::POSITION, Vertex::Attribute::Usage::COLOR},
                              {{"color", DataType::FLOAT_VECTOR4}},
                              {{"modelViewProj", DataType::FLOAT_MATRIX4}},
                              256, 256,
                              "mainPS", "mainVS");

            engine->getCache()->setShader(SHADER_COLOR, colorShader);

            for (uint32_t i = 0; i < BUFFER_COUNT; ++i)
            {
                ShaderConstantBuffer shaderConstantBuffer;

                shaderConstantBuffer.buffer = [device newBufferWithLength:BUFFER_SIZE
                                                                  options:MTLResourceCPUCacheModeWriteCombined];

                if (!shaderConstantBuffer.buffer)
                {
                    Log(Log::Level::ERR) << "Failed to create Metal buffer";
                    return false;
                }

                shaderConstantBuffers.push_back(shaderConstantBuffer);
            }

            return true;
        }

        void RenderDeviceMetal::setClearColorBuffer(bool clear)
        {
            RenderDevice::setClearColorBuffer(clear);

            colorBufferLoadAction = clearColorBuffer ? MTLLoadActionClear : MTLLoadActionDontCare;
        }

        void RenderDeviceMetal::setClearDepthBuffer(bool clear)
        {
            RenderDevice::setClearDepthBuffer(clear);

            depthBufferLoadAction = clearDepthBuffer ? MTLLoadActionClear : MTLLoadActionDontCare;
        }

        void RenderDeviceMetal::setClearColor(Color color)
        {
            RenderDevice::setClearColor(color);

            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(clearColor.normR(),
                                                                                    clearColor.normG(),
                                                                                    clearColor.normB(),
                                                                                    clearColor.normA());
        }

        void RenderDeviceMetal::setClearDepth(float newClearDepth)
        {
            RenderDevice::setClearDepth(newClearDepth);

            renderPassDescriptor.depthAttachment.clearDepth = clearDepth;
        }

        void RenderDeviceMetal::setSize(const Size2& newSize)
        {
            RenderDevice::setSize(newSize);

            CGSize drawableSize = CGSizeMake(size.width, size.height);
            metalLayer.drawableSize = drawableSize;
        }

        bool RenderDeviceMetal::processCommands(CommandBuffer& commands)
        {
            id<CAMetalDrawable> currentMetalDrawable = [metalLayer nextDrawable];

            if (!currentMetalDrawable)
            {
                Log(Log::Level::ERR) << "Failed to get Metal drawable";
                return false;
            }

            if (currentMetalTexture) [currentMetalTexture release];

            currentMetalTexture = [currentMetalDrawable.texture retain];

            NSUInteger frameBufferWidth = currentMetalTexture.width;
            NSUInteger frameBufferHeight = currentMetalTexture.height;

            if (sampleCount > 1)
            {
                if (!msaaTexture ||
                    frameBufferWidth != msaaTexture.width ||
                    frameBufferHeight != msaaTexture.height)
                {
                    if (msaaTexture) [msaaTexture release];

                    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm
                                                                                                    width: frameBufferWidth
                                                                                                   height: frameBufferHeight
                                                                                                mipmapped: NO];
                    desc.textureType = MTLTextureType2DMultisample;
                    desc.storageMode = MTLStorageModePrivate;
                    desc.sampleCount = sampleCount;
                    desc.usage = MTLTextureUsageRenderTarget;

                    msaaTexture = [device newTextureWithDescriptor: desc];

                    if (!msaaTexture)
                    {
                        Log(Log::Level::ERR) << "Failed to create MSAA texture";
                        return false;
                    }

                    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
                    renderPassDescriptor.colorAttachments[0].texture = msaaTexture;
                }

                renderPassDescriptor.colorAttachments[0].resolveTexture = currentMetalTexture;
            }
            else
            {
                renderPassDescriptor.colorAttachments[0].texture = currentMetalTexture;
            }

            if (depth)
            {
                if (!depthTexture ||
                    frameBufferWidth != depthTexture.width ||
                    frameBufferHeight != depthTexture.height)
                {
                    if (depthTexture) [depthTexture release];

                    MTLTextureDescriptor* desc = [MTLTextureDescriptor
                                                  texture2DDescriptorWithPixelFormat:static_cast<MTLPixelFormat>(depthFormat)
                                                  width:frameBufferWidth height:frameBufferHeight mipmapped:NO];

                    desc.textureType = (sampleCount > 1) ? MTLTextureType2DMultisample : MTLTextureType2D;
                    desc.storageMode = MTLStorageModePrivate;
                    desc.sampleCount = sampleCount;
                    desc.usage = MTLTextureUsageRenderTarget;

                    depthTexture = [device newTextureWithDescriptor:desc];

                    if (!depthTexture)
                    {
                        Log(Log::Level::ERR) << "Failed to create depth texture";
                        return false;
                    }

                    renderPassDescriptor.depthAttachment.texture = depthTexture;
                }
            }
            else
            {
                renderPassDescriptor.depthAttachment.texture = nil;
            }

            dispatch_semaphore_wait(inflightSemaphore, DISPATCH_TIME_FOREVER);

            id<MTLCommandBuffer> currentCommandBuffer = [commandQueue commandBuffer];

            if (!currentCommandBuffer)
            {
                Log(Log::Level::ERR) << "Failed to create Metal command buffer";
                return false;
            }

            __block dispatch_semaphore_t blockSemaphore = inflightSemaphore;
            [currentCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer>)
             {
                 dispatch_semaphore_signal(blockSemaphore);
             }];

            MTLRenderPassDescriptorPtr currentRenderPassDescriptor = nil;
            id<MTLRenderCommandEncoder> currentRenderCommandEncoder = nil;
            PipelineStateDesc currentPipelineStateDesc;
            MTLTexturePtr currentRenderTarget = nil;

            std::vector<float> shaderData;

            MTLViewport viewport;
            viewport.znear = 0.0;
            viewport.zfar = 1.0;

            if (++shaderConstantBufferIndex >= shaderConstantBuffers.size()) shaderConstantBufferIndex = 0;

            ShaderConstantBuffer& shaderConstantBuffer = shaderConstantBuffers[shaderConstantBufferIndex];
            ShaderResourceMetal* currentShader = nullptr;

            while (Command* command = commands.front())
            {
                switch (command->type)
                {
                    case Command::Type::SET_RENDER_TARGET:
                    {
                        const SetRenderTargetCommand* setRenderTargetCommand = static_cast<const SetRenderTargetCommand*>(command);

                        MTLRenderPassDescriptorPtr newRenderPassDescriptor;

                        if (setRenderTargetCommand->renderTarget)
                        {
                            TextureResourceMetal* renderTargetMetal = static_cast<TextureResourceMetal*>(setRenderTargetCommand->renderTarget);

                            currentRenderTarget = renderTargetMetal->getTexture();
                            newRenderPassDescriptor = renderTargetMetal->getRenderPassDescriptor();
                            if (!newRenderPassDescriptor) continue;

                            currentPipelineStateDesc.sampleCount = renderTargetMetal->getSampleCount();
                            currentPipelineStateDesc.colorFormat = renderTargetMetal->getColorFormat();
                            currentPipelineStateDesc.depthFormat = renderTargetMetal->getDepthFormat();

                        }
                        else
                        {
                            currentRenderTarget = currentMetalTexture;
                            newRenderPassDescriptor = renderPassDescriptor;
                            currentPipelineStateDesc.sampleCount = sampleCount;
                            currentPipelineStateDesc.colorFormat = colorFormat;
                            currentPipelineStateDesc.depthFormat = depthFormat;
                        }

                        if (currentRenderPassDescriptor != newRenderPassDescriptor ||
                            !currentRenderCommandEncoder)
                        {
                            if (currentRenderCommandEncoder)
                                [currentRenderCommandEncoder endEncoding];

                            currentRenderPassDescriptor = newRenderPassDescriptor;
                            currentRenderCommandEncoder = [currentCommandBuffer renderCommandEncoderWithDescriptor:currentRenderPassDescriptor];

                            if (!currentRenderCommandEncoder)
                            {
                                Log(Log::Level::ERR) << "Failed to create Metal render command encoder";
                                return false;
                            }

                            currentRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
                            currentRenderPassDescriptor.depthAttachment.loadAction = MTLLoadActionLoad;
                        }

                        break;
                    }

                    case Command::Type::CLEAR:
                    {
                        const ClearCommand* clearCommand = static_cast<const ClearCommand*>(command);

                        MTLRenderPassDescriptorPtr newRenderPassDescriptor;
                        MTLLoadAction newColorBufferLoadAction = MTLLoadActionLoad;
                        MTLLoadAction newDepthBufferLoadAction = MTLLoadActionLoad;

                        NSUInteger renderTargetWidth = 0;
                        NSUInteger renderTargetHeight = 0;

                        // render target
                        if (clearCommand->renderTarget)
                        {
                            TextureResourceMetal* renderTargetMetal = static_cast<TextureResourceMetal*>(clearCommand->renderTarget);

                            newRenderPassDescriptor = renderTargetMetal->getRenderPassDescriptor();
                            if (!newRenderPassDescriptor) continue;

                            currentRenderTarget = renderTargetMetal->getTexture();
                            currentPipelineStateDesc.sampleCount = renderTargetMetal->getSampleCount();
                            currentPipelineStateDesc.colorFormat = renderTargetMetal->getColorFormat();
                            currentPipelineStateDesc.depthFormat = renderTargetMetal->getDepthFormat();

                            renderTargetWidth = renderTargetMetal->getWidth();
                            renderTargetHeight = renderTargetMetal->getHeight();

                            newColorBufferLoadAction = renderTargetMetal->getColorBufferLoadAction();
                            newDepthBufferLoadAction = renderTargetMetal->getDepthBufferLoadAction();
                        }
                        else
                        {
                            currentRenderTarget = currentMetalTexture;
                            newRenderPassDescriptor = renderPassDescriptor;
                            currentPipelineStateDesc.sampleCount = sampleCount;
                            currentPipelineStateDesc.colorFormat = colorFormat;
                            currentPipelineStateDesc.depthFormat = depthFormat;

                            renderTargetWidth = frameBufferWidth;
                            renderTargetHeight = frameBufferHeight;

                            newColorBufferLoadAction = colorBufferLoadAction;
                            newDepthBufferLoadAction = depthBufferLoadAction;
                        }

                        if (currentRenderCommandEncoder)
                            [currentRenderCommandEncoder endEncoding];

                        currentRenderPassDescriptor = newRenderPassDescriptor;
                        currentRenderCommandEncoder = [currentCommandBuffer renderCommandEncoderWithDescriptor:currentRenderPassDescriptor];

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Failed to create Metal render command encoder";
                            return false;
                        }

                        viewport.originX = viewport.originY = 0.0;
                        viewport.width = static_cast<double>(renderTargetWidth);
                        viewport.height = static_cast<double>(renderTargetHeight);

                        [currentRenderCommandEncoder setViewport: viewport];
                        [currentRenderCommandEncoder setDepthStencilState:depthStencilStates[1]]; // enable depth write

                        currentRenderPassDescriptor.colorAttachments[0].loadAction = newColorBufferLoadAction;
                        currentRenderPassDescriptor.depthAttachment.loadAction = newDepthBufferLoadAction;

                        break;
                    }

                    case Command::Type::SET_CULL_MODE:
                    {
                        const SetCullModeCommad* setCullModeCommad = static_cast<const SetCullModeCommad*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        MTLCullMode cullMode;

                        switch (setCullModeCommad->cullMode)
                        {
                            case Renderer::CullMode::NONE: cullMode = MTLCullModeNone; break;
                            case Renderer::CullMode::FRONT: cullMode = MTLCullModeFront; break;
                            case Renderer::CullMode::BACK: cullMode = MTLCullModeBack; break;
                            default: Log(Log::Level::ERR) << "Invalid cull mode"; return false;
                        }

                        [currentRenderCommandEncoder setCullMode:cullMode];

                        break;
                    }

                    case Command::Type::SET_FILL_MODE:
                    {
                        const SetFillModeCommad* setFillModeCommad = static_cast<const SetFillModeCommad*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        MTLTriangleFillMode fillMode;

                        switch (setFillModeCommad->fillMode)
                        {
                            case Renderer::FillMode::SOLID: fillMode = MTLTriangleFillModeFill; break;
                            case Renderer::FillMode::WIREFRAME: fillMode = MTLTriangleFillModeLines; break;
                            default: Log(Log::Level::ERR) << "Invalid fill mode"; return false;
                        }

                        [currentRenderCommandEncoder setTriangleFillMode:fillMode];

                        break;
                    }

                    case Command::Type::SET_SCISSOR_TEST:
                    {
                        const SetScissorTestCommand* setScissorTestCommand = static_cast<const SetScissorTestCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        MTLScissorRect scissorRect;

                        if (setScissorTestCommand->enabled)
                        {
                            scissorRect.x = static_cast<NSUInteger>(setScissorTestCommand->rectangle.position.x);
                            scissorRect.y = static_cast<NSUInteger>(setScissorTestCommand->rectangle.position.y);
                            scissorRect.width = static_cast<NSUInteger>(setScissorTestCommand->rectangle.size.width);
                            scissorRect.height = static_cast<NSUInteger>(setScissorTestCommand->rectangle.size.height);
                            if (scissorRect.x >= currentRenderTarget.width) scissorRect.x = currentRenderTarget.width - 1;
                            if (scissorRect.y >= currentRenderTarget.height) scissorRect.y = currentRenderTarget.height - 1;
                            if (scissorRect.width > currentRenderTarget.width - scissorRect.x) scissorRect.width = currentRenderTarget.width - scissorRect.x;
                            if (scissorRect.height > currentRenderTarget.height - scissorRect.y) scissorRect.height = currentRenderTarget.height - scissorRect.y;
                        }
                        else
                        {
                            scissorRect.x = scissorRect.y = 0;
                            scissorRect.width = currentRenderTarget.width;
                            scissorRect.height = currentRenderTarget.height;
                        }

                        [currentRenderCommandEncoder setScissorRect: scissorRect];

                        break;
                    }

                    case Command::Type::SET_VIEWPORT:
                    {
                        const SetViewportCommand* setViewportCommand = static_cast<const SetViewportCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        viewport.originX = static_cast<double>(setViewportCommand->viewport.position.x);
                        viewport.originY = static_cast<double>(setViewportCommand->viewport.position.y);
                        viewport.width = static_cast<double>(setViewportCommand->viewport.size.width);
                        viewport.height = static_cast<double>(setViewportCommand->viewport.size.height);

                        [currentRenderCommandEncoder setViewport: viewport];

                        break;
                    }

                    case Command::Type::SET_DEPTH_STATE:
                    {
                        const SetDepthStateCommand* setDepthStateCommand = static_cast<const SetDepthStateCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        uint32_t depthTestIndex = setDepthStateCommand->depthTest ? 1 : 0;
                        uint32_t depthWriteIndex = setDepthStateCommand->depthWrite ? 1 : 0;
                        uint32_t depthStencilStateIndex = depthTestIndex * 2 + depthWriteIndex;

                        [currentRenderCommandEncoder setDepthStencilState:depthStencilStates[depthStencilStateIndex]];

                        break;
                    }

                    case Command::Type::SET_PIPELINE_STATE:
                    {
                        const SetPipelineStateCommand* setPipelineStateCommand = static_cast<const SetPipelineStateCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        BlendStateResourceMetal* blendStateMetal = static_cast<BlendStateResourceMetal*>(setPipelineStateCommand->blendState);
                        ShaderResourceMetal* shaderMetal = static_cast<ShaderResourceMetal*>(setPipelineStateCommand->shader);
                        currentShader = shaderMetal;

                        currentPipelineStateDesc.blendState = blendStateMetal;
                        currentPipelineStateDesc.shader = shaderMetal;

                        MTLRenderPipelineStatePtr pipelineState = getPipelineState(currentPipelineStateDesc);
                        if (pipelineState) [currentRenderCommandEncoder setRenderPipelineState:pipelineState];

                        break;
                    }

                    case Command::Type::DRAW:
                    {
                        const DrawCommand* drawCommand = static_cast<const DrawCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        // mesh buffer
                        BufferResourceMetal* indexBufferMetal = static_cast<BufferResourceMetal*>(drawCommand->indexBuffer);
                        BufferResourceMetal* vertexBufferMetal = static_cast<BufferResourceMetal*>(drawCommand->vertexBuffer);

                        assert(indexBufferMetal);
                        assert(indexBufferMetal->getBuffer());
                        assert(vertexBufferMetal);
                        assert(vertexBufferMetal->getBuffer());

                        [currentRenderCommandEncoder setVertexBuffer:vertexBufferMetal->getBuffer() offset:0 atIndex:0];

                        // draw
                        MTLPrimitiveType primitiveType;

                        switch (drawCommand->drawMode)
                        {
                            case Renderer::DrawMode::POINT_LIST: primitiveType = MTLPrimitiveTypePoint; break;
                            case Renderer::DrawMode::LINE_LIST: primitiveType = MTLPrimitiveTypeLine; break;
                            case Renderer::DrawMode::LINE_STRIP: primitiveType = MTLPrimitiveTypeLineStrip; break;
                            case Renderer::DrawMode::TRIANGLE_LIST: primitiveType = MTLPrimitiveTypeTriangle; break;
                            case Renderer::DrawMode::TRIANGLE_STRIP: primitiveType = MTLPrimitiveTypeTriangleStrip; break;
                            default: Log(Log::Level::ERR) << "Invalid draw mode"; return false;
                        }

                        assert(drawCommand->indexCount);
                        assert(indexBufferMetal->getSize());
                        assert(vertexBufferMetal->getSize());

                        MTLIndexType indexType;

                        switch (drawCommand->indexSize)
                        {
                            case 2: indexType = MTLIndexTypeUInt16; break;
                            case 4: indexType = MTLIndexTypeUInt32; break;
                            default:
                                Log(Log::Level::ERR) << "Invalid index size";
                                return false;
                        }


                        [currentRenderCommandEncoder drawIndexedPrimitives:primitiveType
                                                                indexCount:drawCommand->indexCount
                                                                 indexType:indexType
                                                               indexBuffer:indexBufferMetal->getBuffer()
                                                         indexBufferOffset:drawCommand->startIndex * drawCommand->indexSize];

                        break;
                    }

                    case Command::Type::PUSH_DEBUG_MARKER:
                    {
                        const PushDebugMarkerCommand* pushDebugMarkerCommand = static_cast<const PushDebugMarkerCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        [currentRenderCommandEncoder pushDebugGroup:static_cast<NSString* _Nonnull>([NSString stringWithUTF8String:pushDebugMarkerCommand->name.c_str()])];
                        break;
                    }

                    case Command::Type::POP_DEBUG_MARKER:
                    {
                        const PopDebugMarkerCommand* popDebugMarkerCommand = static_cast<const PopDebugMarkerCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        [currentRenderCommandEncoder popDebugGroup];
                        break;
                    }

                    case Command::Type::INIT_BLEND_STATE:
                    {
                        const InitBlendStateCommand* initBlendStateCommand = static_cast<const InitBlendStateCommand*>(command);

                        initBlendStateCommand->blendState->init(initBlendStateCommand->enableBlending,
                                                                initBlendStateCommand->colorBlendSource,
                                                                initBlendStateCommand->colorBlendDest,
                                                                initBlendStateCommand->colorOperation,
                                                                initBlendStateCommand->alphaBlendSource,
                                                                initBlendStateCommand->alphaBlendDest,
                                                                initBlendStateCommand->alphaOperation,
                                                                initBlendStateCommand->colorMask);
                        break;
                    }

                    case Command::Type::INIT_BUFFER:
                    {
                        const InitBufferCommand* initBufferCommand = static_cast<const InitBufferCommand*>(command);

                        initBufferCommand->buffer->init(initBufferCommand->usage,
                                                        initBufferCommand->flags,
                                                        initBufferCommand->data,
                                                        initBufferCommand->size);
                        break;
                    }

                    case Command::Type::SET_BUFFER_DATA:
                    {
                        const SetBufferDataCommand* setBufferDataCommand = static_cast<const SetBufferDataCommand*>(command);

                        setBufferDataCommand->buffer->setData(setBufferDataCommand->data);
                        break;
                    }

                    case Command::Type::INIT_SHADER:
                    {
                        const InitShaderCommand* initShaderCommand = static_cast<const InitShaderCommand*>(command);

                        initShaderCommand->shader->init(initShaderCommand->pixelShader,
                                                        initShaderCommand->vertexShader,
                                                        initShaderCommand->vertexAttributes,
                                                        initShaderCommand->pixelShaderConstantInfo,
                                                        initShaderCommand->vertexShaderConstantInfo,
                                                        initShaderCommand->pixelShaderDataAlignment,
                                                        initShaderCommand->vertexShaderDataAlignment,
                                                        initShaderCommand->pixelShaderFunction,
                                                        initShaderCommand->vertexShaderFunction);

                        break;
                    }

                    case Command::Type::SET_SHADER_CONSTANTS:
                    {
                        const SetShaderConstantsCommand* setShaderConstantsCommand = static_cast<const SetShaderConstantsCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        if (!currentShader)
                        {
                            Log(Log::Level::ERR) << "No shader set";
                            return false;
                        }

                        // pixel shader constants
                        const std::vector<ShaderResourceMetal::Location>& pixelShaderConstantLocations = currentShader->getPixelShaderConstantLocations();

                        if (setShaderConstantsCommand->pixelShaderConstants.size() > pixelShaderConstantLocations.size())
                        {
                            Log(Log::Level::ERR) << "Invalid pixel shader constant size";
                            return false;
                        }

                        shaderData.clear();

                        for (size_t i = 0; i < setShaderConstantsCommand->pixelShaderConstants.size(); ++i)
                        {
                            const ShaderResourceMetal::Location& pixelShaderConstantLocation = pixelShaderConstantLocations[i];
                            const std::vector<float>& pixelShaderConstant = setShaderConstantsCommand->pixelShaderConstants[i];

                            if (sizeof(float) * pixelShaderConstant.size() != pixelShaderConstantLocation.size)
                            {
                                Log(Log::Level::ERR) << "Invalid pixel shader constant size";
                                return false;
                            }

                            shaderData.insert(shaderData.end(), pixelShaderConstant.begin(), pixelShaderConstant.end());
                        }

                        shaderConstantBuffer.offset = ((shaderConstantBuffer.offset + currentShader->getPixelShaderAlignment() - 1) /
                                                       currentShader->getPixelShaderAlignment()) * currentShader->getPixelShaderAlignment(); // round up to nearest aligned pointer

                        if (shaderConstantBuffer.offset + getVectorSize(shaderData) > BUFFER_SIZE)
                            shaderConstantBuffer.offset = 0;

                        std::copy(reinterpret_cast<const char*>(shaderData.data()),
                                  reinterpret_cast<const char*>(shaderData.data()) + static_cast<uint32_t>(sizeof(float) * shaderData.size()),
                                  static_cast<char*>([shaderConstantBuffer.buffer contents]) + shaderConstantBuffer.offset);

                        [currentRenderCommandEncoder setFragmentBuffer:shaderConstantBuffer.buffer
                                                                offset:shaderConstantBuffer.offset
                                                               atIndex:1];

                        shaderConstantBuffer.offset += static_cast<uint32_t>(getVectorSize(shaderData));

                        // vertex shader constants
                        const std::vector<ShaderResourceMetal::Location>& vertexShaderConstantLocations = currentShader->getVertexShaderConstantLocations();

                        if (setShaderConstantsCommand->vertexShaderConstants.size() > vertexShaderConstantLocations.size())
                        {
                            Log(Log::Level::ERR) << "Invalid vertex shader constant size";
                            return false;
                        }

                        shaderData.clear();

                        for (size_t i = 0; i < setShaderConstantsCommand->vertexShaderConstants.size(); ++i)
                        {
                            const ShaderResourceMetal::Location& vertexShaderConstantLocation = vertexShaderConstantLocations[i];
                            const std::vector<float>& vertexShaderConstant = setShaderConstantsCommand->vertexShaderConstants[i];

                            if (sizeof(float) * vertexShaderConstant.size() != vertexShaderConstantLocation.size)
                            {
                                Log(Log::Level::ERR) << "Invalid vertex shader constant size";
                                return false;
                            }

                            shaderData.insert(shaderData.end(), vertexShaderConstant.begin(), vertexShaderConstant.end());
                        }

                        shaderConstantBuffer.offset = ((shaderConstantBuffer.offset + currentShader->getVertexShaderAlignment() - 1) /
                                                       currentShader->getVertexShaderAlignment()) * currentShader->getVertexShaderAlignment(); // round up to nearest aligned pointer

                        if (shaderConstantBuffer.offset + getVectorSize(shaderData) > BUFFER_SIZE)
                        {
                            shaderConstantBuffer.offset = 0;
                        }

                        std::copy(reinterpret_cast<const char*>(shaderData.data()),
                                  reinterpret_cast<const char*>(shaderData.data()) + static_cast<uint32_t>(sizeof(float) * shaderData.size()),
                                  static_cast<char*>([shaderConstantBuffer.buffer contents]) + shaderConstantBuffer.offset);

                        [currentRenderCommandEncoder setVertexBuffer:shaderConstantBuffer.buffer
                                                              offset:shaderConstantBuffer.offset
                                                             atIndex:1];

                        shaderConstantBuffer.offset += static_cast<uint32_t>(getVectorSize(shaderData));

                        break;
                    }

                    case Command::Type::SET_TEXTURES:
                    {
                        const SetTexturesCommand* setTexturesCommand = static_cast<const SetTexturesCommand*>(command);

                        if (!currentRenderCommandEncoder)
                        {
                            Log(Log::Level::ERR) << "Metal render command encoder not initialized";
                            return false;
                        }

                        for (uint32_t layer = 0; layer < Texture::LAYERS; ++layer)
                        {
                            TextureResourceMetal* textureMetal = static_cast<TextureResourceMetal*>(setTexturesCommand->textures[layer]);

                            if (textureMetal)
                            {
                                if (!textureMetal->getTexture())
                                    return false;

                                [currentRenderCommandEncoder setFragmentTexture:textureMetal->getTexture() atIndex:layer];
                                [currentRenderCommandEncoder setFragmentSamplerState:textureMetal->getSamplerState() atIndex:layer];
                            }
                            else
                            {
                                [currentRenderCommandEncoder setFragmentTexture:nil atIndex:layer];
                            }
                        }

                        break;
                    }

                    default: return false;
                }

                commands.pop();
            }

            if (currentRenderCommandEncoder)
                [currentRenderCommandEncoder endEncoding];

            if (currentCommandBuffer)
            {
                [currentCommandBuffer presentDrawable:currentMetalDrawable];
                [currentCommandBuffer commit];
            }

            return true;
        }

        bool RenderDeviceMetal::generateScreenshot(const std::string& filename)
        {
            if (!currentMetalTexture)
            {
                return false;
            }

            NSUInteger width = static_cast<NSUInteger>(currentMetalTexture.width);
            NSUInteger height = static_cast<NSUInteger>(currentMetalTexture.height);

            std::shared_ptr<uint8_t> data(new uint8_t[width * height * 4]);
            [currentMetalTexture getBytes:data.get() bytesPerRow:width * 4 fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];

            uint8_t temp;
            for (uint32_t y = 0; y < height; ++y)
            {
                for (uint32_t x = 0; x < width; ++x)
                {
                    temp = data.get()[((y * width + x) * 4)];
                    data.get()[((y * width + x) * 4)] = data.get()[((y * width + x) * 4) + 2];
                    data.get()[((y * width + x) * 4) + 2] = temp;
                    data.get()[((y * width + x) * 4) + 3] = 255;
                }
            }

            if (!stbi_write_png(filename.c_str(), static_cast<int>(width), static_cast<int>(height), 4, data.get(), static_cast<int>(width * 4)))
            {
                Log(Log::Level::ERR) << "Failed to save image to file";
                return false;
            }

            return true;
        }

        BlendStateResource* RenderDeviceMetal::createBlendState()
        {
            Lock lock(resourceMutex);

            BlendStateResource* blendState = new BlendStateResourceMetal();
            resources.push_back(std::unique_ptr<RenderResource>(blendState));
            return blendState;
        }

        TextureResource* RenderDeviceMetal::createTexture()
        {
            Lock lock(resourceMutex);

            TextureResource* texture = new TextureResourceMetal(*this);
            resources.push_back(std::unique_ptr<RenderResource>(texture));
            return texture;
        }

        ShaderResource* RenderDeviceMetal::createShader()
        {
            Lock lock(resourceMutex);

            ShaderResource* shader = new ShaderResourceMetal(*this);
            resources.push_back(std::unique_ptr<RenderResource>(shader));
            return shader;
        }

        BufferResource* RenderDeviceMetal::createBuffer()
        {
            Lock lock(resourceMutex);

            BufferResource* buffer = new BufferResourceMetal(*this);
            resources.push_back(std::unique_ptr<RenderResource>(buffer));
            return buffer;
        }

        MTLRenderPipelineStatePtr RenderDeviceMetal::getPipelineState(const PipelineStateDesc& desc)
        {
            if (!desc.blendState || !desc.shader || !desc.sampleCount) return nil;

            auto pipelineStateIterator = pipelineStates.find(desc);

            if (pipelineStateIterator != pipelineStates.end())
            {
                return pipelineStateIterator->second;
            }
            else
            {
                MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
                pipelineStateDescriptor.sampleCount = desc.sampleCount;

                if (desc.shader)
                {
                    assert(desc.shader->getPixelShader());
                    assert(desc.shader->getVertexShader());
                    assert(desc.shader->getVertexDescriptor());

                    pipelineStateDescriptor.vertexFunction = desc.shader->getVertexShader();
                    pipelineStateDescriptor.fragmentFunction = desc.shader->getPixelShader();
                    pipelineStateDescriptor.vertexDescriptor = desc.shader->getVertexDescriptor();
                }

                pipelineStateDescriptor.colorAttachments[0].pixelFormat = desc.colorFormat;
                pipelineStateDescriptor.depthAttachmentPixelFormat = desc.depthFormat;
                pipelineStateDescriptor.stencilAttachmentPixelFormat = MTLPixelFormatInvalid;

                if (desc.blendState)
                {
                    // blending
                    pipelineStateDescriptor.colorAttachments[0].blendingEnabled = desc.blendState->isMetalBlendingEnabled() ? YES : NO;

                    pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = desc.blendState->getSourceRGBBlendFactor();
                    pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = desc.blendState->getDestinationRGBBlendFactor();
                    pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = desc.blendState->getRGBBlendOperation();

                    pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = desc.blendState->getSourceAlphaBlendFactor();
                    pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = desc.blendState->getDestinationAlphaBlendFactor();
                    pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = desc.blendState->getAlphaBlendOperation();

                    pipelineStateDescriptor.colorAttachments[0].writeMask = desc.blendState->getColorWriteMask();
                }

                NSError* error;
                id<MTLRenderPipelineState> pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
                [pipelineStateDescriptor release];
                if (error || !pipelineState)
                {
                    if (pipelineState) [pipelineState release];

                    Log(Log::Level::ERR) << "Failed to created Metal pipeline state";
                    return nil;
                }

                pipelineStates[desc] = pipelineState;

                return pipelineState;
            }
        }

        MTLSamplerStatePtr RenderDeviceMetal::getSamplerState(const SamplerStateDescriptor& descriptor)
        {
            auto samplerStatesIterator = samplerStates.find(descriptor);

            if (samplerStatesIterator != samplerStates.end())
            {
                return samplerStatesIterator->second;
            }
            else
            {
                MTLSamplerDescriptor* samplerDescriptor = [MTLSamplerDescriptor new];
                switch (descriptor.filter)
                {
                    case Texture::Filter::DEFAULT:
                    case Texture::Filter::POINT:
                        samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
                        samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
                        samplerDescriptor.mipFilter = MTLSamplerMipFilterNearest;
                        break;
                    case Texture::Filter::LINEAR:
                        samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
                        samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
                        samplerDescriptor.mipFilter = MTLSamplerMipFilterNearest;
                        break;
                    case Texture::Filter::BILINEAR:
                        samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
                        samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
                        samplerDescriptor.mipFilter = MTLSamplerMipFilterNearest;
                        break;
                    case Texture::Filter::TRILINEAR:
                        samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
                        samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
                        samplerDescriptor.mipFilter = MTLSamplerMipFilterLinear;
                        break;
                }

                switch (descriptor.addressX)
                {
                    case Texture::Address::CLAMP:
                        samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
                        break;
                    case Texture::Address::REPEAT:
                        samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
                        break;
                    case Texture::Address::MIRROR_REPEAT:
                        samplerDescriptor.sAddressMode = MTLSamplerAddressModeMirrorRepeat;
                        break;
                }

                switch (descriptor.addressY)
                {
                    case Texture::Address::CLAMP:
                        samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
                        break;
                    case Texture::Address::REPEAT:
                        samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
                        break;
                    case Texture::Address::MIRROR_REPEAT:
                        samplerDescriptor.tAddressMode = MTLSamplerAddressModeMirrorRepeat;
                        break;
                }

                samplerDescriptor.maxAnisotropy = descriptor.maxAnisotropy;

                MTLSamplerStatePtr samplerState = [device newSamplerStateWithDescriptor:samplerDescriptor];
                [samplerDescriptor release];

                if (!samplerState)
                {
                    Log(Log::Level::ERR) << "Failed to create Metal sampler state";
                    return nil;
                }

                samplerStates[descriptor] = samplerState;

                return samplerState;
            }
        }
    } // namespace graphics
} // namespace ouzel

#endif
