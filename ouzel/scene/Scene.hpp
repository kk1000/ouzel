// Copyright (C) 2018 Elviss Strazdins
// This file is part of the Ouzel engine.

#pragma once

#include <vector>
#include <unordered_map>
#include <cstdint>
#include "math/Vector2.hpp"
#include "events/EventHandler.hpp"

namespace ouzel
{
    namespace scene
    {
        class SceneManager;
        class Layer;

        class Scene
        {
            friend SceneManager;
        public:
            Scene();
            virtual ~Scene();

            Scene(const Scene&) = delete;
            Scene& operator=(const Scene&) = delete;

            Scene(Scene&&) = delete;
            Scene& operator=(Scene&&) = delete;

            virtual void draw();

            void addLayer(Layer* layer)
            {
                addChildLayer(layer);
            }
            template<class T> void addLayer(const UniquePtr<T>& layer)
            {
                addChildLayer(layer.get());
            }
            template<class T> void addLayer(UniquePtr<T>&& layer)
            {
                addChildLayer(layer.get());
                ownedLayers.push_back(std::move(layer));
            }

            bool removeLayer(Layer* layer)
            {
                return removeChildLayer(layer);
            }
            template<class T> bool removeLayer(const UniquePtr<T>& layer)
            {
                return removeChildLayer(layer.get());
            }
            void removeAllLayers();
            bool hasLayer(Layer* layer) const;
            inline const std::vector<Layer*>& getLayers() const { return layers; }

            virtual void recalculateProjection();

            std::pair<Actor*, ouzel::Vector3> pickActor(const Vector2& position, bool renderTargets = false) const;
            std::vector<std::pair<Actor*, ouzel::Vector3>> pickActors(const Vector2& position, bool renderTargets = false) const;
            std::vector<Actor*> pickActors(const std::vector<Vector2>& edges, bool renderTargets = false) const;

        protected:
            virtual void addChildLayer(Layer* layer);
            virtual bool removeChildLayer(Layer* layer);

            virtual void enter();
            virtual void leave();

            bool handleWindow(Event::Type type, const WindowEvent& event);
            bool handleMouse(Event::Type type, const MouseEvent& event);
            bool handleTouch(Event::Type type, const TouchEvent& event);

            void pointerEnterActor(uint64_t pointerId, Actor* actor, const Vector2& position);
            void pointerLeaveActor(uint64_t pointerId, Actor* actor, const Vector2& position);
            void pointerDownOnActor(uint64_t pointerId, Actor* actor, const Vector2& position, const Vector3& localPosition);
            void pointerUpOnActor(uint64_t pointerId, Actor* actor, const Vector2& position);
            void pointerDragActor(uint64_t pointerId, Actor* actor, const Vector2& position,
                                 const Vector2& difference, const ouzel::Vector3& localPosition);

            SceneManager* sceneManger = nullptr;

            std::vector<Layer*> layers;
            std::vector<UniquePtr<Layer>> ownedLayers;
            ouzel::EventHandler eventHandler;

            std::unordered_map<uint64_t, std::pair<Actor*, ouzel::Vector3>> pointerDownOnActors;

            bool entered = false;
        };
    } // namespace scene
} // namespace ouzel
