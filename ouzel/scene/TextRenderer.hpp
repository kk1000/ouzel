// Copyright (C) 2018 Elviss Strazdins
// This file is part of the Ouzel engine.

#pragma once

#include <string>
#include "scene/Component.hpp"
#include "math/Color.hpp"
#include "gui/BMFont.hpp"
#include "graphics/BlendState.hpp"
#include "graphics/Buffer.hpp"
#include "graphics/Shader.hpp"
#include "graphics/Texture.hpp"

namespace ouzel
{
    namespace scene
    {
        class TextRenderer: public Component
        {
        public:
            static const uint32_t CLASS = Component::TEXT_RENDERER;

            TextRenderer(const std::string& fontFile,
                         bool initMipmaps = true,
                         float initFontSize = 1.0F,
                         const std::string& initText = std::string(),
                         Color initColor = Color::WHITE,
                         const Vector2& initTextAnchor = Vector2(0.5F, 0.5F));

            virtual void draw(const Matrix4& transformMatrix,
                              float opacity,
                              const Matrix4& renderViewProjection,
                              bool wireframe) override;

            void setFont(const std::string& fontFile);

            inline float getFontSize() const { return fontSize; }
            void setFontSize(float newFontSize);

            inline const Vector2& getTextAnchor() const { return textAnchor; }
            void setTextAnchor(const Vector2& newTextAnchor);

            inline const std::string& getText() const { return text; }
            void setText(const std::string& newText);

            inline const Color& getColor() const { return color; }
            void setColor(const Color& newColor);

            inline const std::shared_ptr<graphics::Shader>& getShader() const { return shader; }
            inline void setShader(const std::shared_ptr<graphics::Shader>& newShader) { shader = newShader; }

            inline const std::shared_ptr<graphics::BlendState>& getBlendState() const { return blendState; }
            inline void setBlendState(const std::shared_ptr<graphics::BlendState>& newBlendState)  { blendState = newBlendState; }

        protected:
            void updateText();

            std::shared_ptr<graphics::Shader> shader;
            std::shared_ptr<graphics::BlendState> blendState;

            std::shared_ptr<graphics::Buffer> indexBuffer;
            std::shared_ptr<graphics::Buffer> vertexBuffer;

            std::shared_ptr<graphics::Texture> texture;
            std::shared_ptr<graphics::Texture> whitePixelTexture;

            std::shared_ptr<Font> font;
            std::string text;
            float fontSize = 1.0F;
            Vector2 textAnchor;

            std::vector<uint16_t> indices;
            std::vector<graphics::Vertex> vertices;

            Color color = Color::WHITE;

            bool mipmaps = true;
            bool needsMeshUpdate = false;
        };
    } // namespace scene
} // namespace ouzel
