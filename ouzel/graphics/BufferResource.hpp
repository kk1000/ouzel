// Copyright (C) 2018 Elviss Strazdins
// This file is part of the Ouzel engine.

#pragma once

#include <vector>
#include "graphics/RenderResource.hpp"
#include "graphics/Buffer.hpp"

namespace ouzel
{
    namespace graphics
    {
        class Renderer;

        class BufferResource: public RenderResource
        {
            friend Renderer;
        public:
            virtual ~BufferResource();

            virtual bool init(Buffer::Usage newUsage, uint32_t newFlags,
                              const std::vector<uint8_t>& newData,
                              uint32_t newSize);

            virtual bool setData(const std::vector<uint8_t>& newData);

            inline uint32_t getFlags() const { return flags; }
            inline Buffer::Usage getUsage() const { return usage; }
            inline uint32_t getSize() const { return static_cast<uint32_t>(data.size()); }

        protected:
            BufferResource();

            Buffer::Usage usage;
            uint32_t flags = 0;
            std::vector<uint8_t> data;
        };
    } // namespace graphics
} // namespace ouzel
