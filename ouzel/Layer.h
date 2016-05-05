// Copyright (C) 2016 Elviss Strazdins
// This file is part of the Ouzel engine.

#pragma once

#include <memory>
#include <set>
#include "Types.h"
#include "NodeContainer.h"
#include "Size2.h"
#include "Matrix4.h"
#include "Vector2.h"
#include "Rectangle.h"

namespace ouzel
{
    namespace scene
    {
        class Camera;
        class Scene;

        class Layer: public NodeContainer
        {
            friend Scene;
        public:
            Layer();
            virtual ~Layer();

            virtual void draw();

            virtual bool addChild(const NodePtr& node) override;

            void addToDrawQueue(const NodePtr& node);

            const CameraPtr& getCamera() const { return camera; }
            void setCamera(const CameraPtr& newCamera);

            NodePtr pickNode(const Vector2& position) const;
            std::set<NodePtr> pickNodes(const std::vector<Vector2>& edges) const;

            int32_t getOrder() const { return order; }
            void setOrder(int32_t newOrder);

            ScenePtr getScene() const { return scene.lock(); }

            void setRenderTarget(const graphics::RenderTargetPtr& newRenderTarget) { renderTarget = newRenderTarget; }
            const graphics::RenderTargetPtr& getRenderTarget() const { return renderTarget; }

        protected:
            virtual void addToScene(const ScenePtr& newScene);
            virtual void removeFromScene();

            CameraPtr camera;
            std::vector<NodePtr> drawQueue;

            SceneWeakPtr scene;
            int32_t order = 0;
            bool remove = false;

            graphics::RenderTargetPtr renderTarget;
        };
    } // namespace scene
} // namespace ouzel
