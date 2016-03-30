// Copyright (C) 2016 Elviss Strazdins
// This file is part of the Ouzel engine.

#include "DrawNode.h"
#include "CompileConfig.h"
#include "Engine.h"
#include "Renderer.h"
#include "Cache.h"
#include "Layer.h"
#include "Camera.h"
#include "MathUtils.h"

namespace ouzel
{
    namespace scene
    {
        DrawNode::DrawNode()
        {
            _shader = sharedEngine->getCache()->getShader(video::SHADER_COLOR);

#ifdef OUZEL_PLATFORM_WINDOWS
            _uniModelViewProj = 0;
#else
            _uniModelViewProj = _shader->getVertexShaderConstantId("modelViewProj");
#endif
        }

        void DrawNode::draw()
        {
            Node::draw();

            LayerPtr layer = _layer.lock();

            if (_shader && layer)
            {
                sharedEngine->getRenderer()->activateShader(_shader);

                Matrix4 modelViewProj = layer->getCamera()->getViewProjection() * _transform;

                _shader->setVertexShaderConstant(_uniModelViewProj, { modelViewProj });

                for (const DrawCommand& drawCommand : _drawCommands)
                {
                    sharedEngine->getRenderer()->drawMeshBuffer(drawCommand.mesh, 0, drawCommand.mode);
                }
            }
        }

        void DrawNode::clear()
        {
            _boundingBox = AABB2();

            _drawCommands.clear();
        }

        void DrawNode::point(const Vector2& position, const video::Color& color)
        {
            std::vector<uint16_t> indices = {0};

            std::vector<video::VertexPC> vertices = {
                video::VertexPC(Vector3(position), color)
            };

            DrawCommand command;

            command.mode = video::Renderer::DrawMode::POINT_LIST;
            command.mesh = sharedEngine->getRenderer()->createMeshBuffer(indices.data(), sizeof(uint16_t),
                                                                                  static_cast<uint32_t>(indices.size()), false,
                                                                                  vertices.data(), sizeof(video::VertexPC),
                                                                                  static_cast<uint32_t>(vertices.size()), false,
                                                                                  video::VertexPC::ATTRIBUTES);

            _drawCommands.push_back(command);

            _boundingBox.insertPoint(position);
        }

        void DrawNode::line(const Vector2& start, const Vector2& finish, const video::Color& color)
        {
            std::vector<uint16_t> indices = {0, 1};

            std::vector<video::VertexPC> vertices = {
                video::VertexPC(Vector3(start), color),
                video::VertexPC(Vector3(finish), color)
            };

            DrawCommand command;

            command.mode = video::Renderer::DrawMode::LINE_STRIP;
            command.mesh = sharedEngine->getRenderer()->createMeshBuffer(indices.data(), sizeof(uint16_t),
                                                                                  static_cast<uint32_t>(indices.size()), false,
                                                                                  vertices.data(), sizeof(video::VertexPC),
                                                                                  static_cast<uint32_t>(vertices.size()), false,
                                                                                  video::VertexPC::ATTRIBUTES);

            _drawCommands.push_back(command);

            _boundingBox.insertPoint(start);
            _boundingBox.insertPoint(finish);
        }

        void DrawNode::circle(const Vector2& position, float radius, const video::Color& color, bool fill, uint32_t segments)
        {
            if (segments < 3)
            {
                return;
            }

            std::vector<uint16_t> indices;
            std::vector<video::VertexPC> vertices;

            if (fill)
            {
                vertices.push_back(video::VertexPC(Vector3(position), color));
            }

            for(uint32_t i = 0; i <= segments; ++i)
            {
                vertices.push_back(video::VertexPC(Vector3((position.x + radius * cosf(i * TAU / static_cast<float>(segments))),
                                                    (position.y + radius * sinf(i * TAU / static_cast<float>(segments))),
                                                    0.0f), color));
            }

            DrawCommand command;

            if (fill)
            {
                command.mode = video::Renderer::DrawMode::TRIANGLE_STRIP;

                for(uint16_t i = 1; i <= segments; ++i)
                {
                    indices.push_back(i);

                    if (i & 1)
                    {
                        indices.push_back(0); // center
                    }
                }

                indices.push_back(1);
            }
            else
            {
                command.mode = video::Renderer::DrawMode::LINE_STRIP;

                for(uint16_t i = 0; i <= segments; ++i)
                {
                    indices.push_back(i);
                }
            }

            command.mesh = sharedEngine->getRenderer()->createMeshBuffer(indices.data(), sizeof(uint16_t),
                                                                                  static_cast<uint32_t>(indices.size()), false,
                                                                                  vertices.data(), sizeof(video::VertexPC),
                                                                                  static_cast<uint32_t>(vertices.size()), false,
                                                                                  video::VertexPC::ATTRIBUTES);

            _drawCommands.push_back(command);

            _boundingBox.insertPoint(Vector2(position.x - radius, position.y - radius));
            _boundingBox.insertPoint(Vector2(position.x + radius, position.y + radius));
        }

        void DrawNode::rectangle(const Rectangle& rectangle, const video::Color& color, bool fill)
        {
            std::vector<uint16_t> indices;

            std::vector<video::VertexPC> vertices = {
                video::VertexPC(Vector3(rectangle.left(), rectangle.bottom(), 0.0f), color),
                video::VertexPC(Vector3(rectangle.right(), rectangle.bottom(), 0.0f), color),
                video::VertexPC(Vector3(rectangle.left(), rectangle.top(), 0.0f),  color),
                video::VertexPC(Vector3(rectangle.right(), rectangle.top(), 0.0f),  color)
            };

            DrawCommand command;

            if (fill)
            {
                command.mode = video::Renderer::DrawMode::TRIANGLE_LIST;
                indices.assign({0, 1, 2, 1, 3, 2});
            }
            else
            {
                command.mode = video::Renderer::DrawMode::LINE_STRIP;
                indices.assign({0, 1, 3, 2, 0});
            }

            command.mesh = sharedEngine->getRenderer()->createMeshBuffer(indices.data(), sizeof(uint16_t),
                                                                                  static_cast<uint32_t>(indices.size()), false,
                                                                                  vertices.data(), sizeof(video::VertexPC),
                                                                                  static_cast<uint32_t>(vertices.size()), false,
                                                                                  video::VertexPC::ATTRIBUTES);

            _drawCommands.push_back(command);

            _boundingBox.insertPoint(Vector2(rectangle.x, rectangle.y));
            _boundingBox.insertPoint(Vector2(rectangle.x + rectangle.width, rectangle.y + rectangle.height));
        }
    } // namespace scene
} // namespace ouzel
