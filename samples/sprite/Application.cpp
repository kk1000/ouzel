//
//  Application.cpp
//  ouzel
//
//  Created by Elviss Strazdins on 20/12/15.
//  Copyright © 2015 Bool Games. All rights reserved.
//

#include "Application.h"

namespace ouzel
{
    Application::Application()
    {
        _eventHandler = new EventHandler();
        
        _eventHandler->keyDownHandler = std::bind(&Application::handleKeyDown, this, std::placeholders::_1, std::placeholders::_2);
        _eventHandler->mouseMoveHandler = std::bind(&Application::handleMouseMove, this, std::placeholders::_1, std::placeholders::_2);
        _eventHandler->touchBeginHandler = std::bind(&Application::handleTouch, this, std::placeholders::_1, std::placeholders::_2);
        _eventHandler->touchMoveHandler = std::bind(&Application::handleTouch, this, std::placeholders::_1, std::placeholders::_2);
        _eventHandler->touchEndHandler = std::bind(&Application::handleTouch, this, std::placeholders::_1, std::placeholders::_2);
        
        EventDispatcher::getInstance()->addEventHandler(_eventHandler);
        
        Renderer::getInstance()->setClearColor(Color(64, 0, 0));
        
        Scene* scene = new Scene();
        SceneManager::getInstance()->setScene(scene);
        
        _layer = new Layer();
        scene->addLayer(_layer);

        _sprite = new Sprite();
        _sprite->initFromFile("run.json");
        _sprite->play(true);
        _layer->addChild(_sprite);
        
        Sprite* fire = new Sprite();
        fire->initFromFile("fire.json");
        fire->play(true);
        fire->setPosition(Vector2(-100.0f, -100.0f));
        _layer->addChild(fire);
        
        ParticleSystem* flame = new ParticleSystem();
        flame->initFromFile("flame.json");
        _layer->addChild(flame);
        
        _witch = new Sprite();
        _witch->initFromFile("witch.png");
        _witch->setPosition(Vector2(100.0f, 100.0f));
        _witch->setColor(Color(128, 0, 255, 255));
        _layer->addChild(_witch);
    }
    
    Application::~Application()
    {
        if (EventDispatcher::getInstance()) EventDispatcher::getInstance()->removeEventHandler(_eventHandler);
    }
    
    void Application::handleKeyDown(const KeyboardEvent& event, ReferenceCounted* sender) const
    {
        Vector2 position = _sprite->getPosition();
        
        switch (event.key)
        {
            case KeyboardKey::UP:
                position.y += 10.0f;
                break;
            case KeyboardKey::DOWN:
                position.y -= 10.0f;
                break;
            case KeyboardKey::LEFT:
                position.x -= 10.0f;
                break;
            case KeyboardKey::RIGHT:
                position.x += 10.0f;
                break;
            default:
                break;
        }
        
        _sprite->setPosition(position);
    }
    
    void Application::handleMouseMove(const MouseEvent& event, ReferenceCounted* sender) const
    {
        Vector2 worldLocation = _layer->screenToWorldLocation(event.position);
        _witch->setPosition(worldLocation);
    }
    
    void Application::handleTouch(const TouchEvent& event, ReferenceCounted* sender) const
    {
        Vector2 worldLocation = _layer->screenToWorldLocation(event.position);
        _witch->setPosition(worldLocation);
    }
}
