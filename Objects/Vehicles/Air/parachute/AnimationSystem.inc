
rem *** Animations ***
animationSystem.createAnimation Objects/Vehicles/Air/parachute/Animations/parachute_idle.baf
animationSystem.createAnimation Objects/Vehicles/Air/parachute/Animations/parachute_deploy.baf
animationSystem.createAnimation Objects/Vehicles/Air/parachute/Animations/parachute_colaps.baf
animationManager.looping 0

rem *** Bundles ***
animationSystem.createBundle parachute_idle
animationBundle.fadeInTime 0.1
animationBundle.fadeOutTime 0.2
animationBundle.addAnimation Objects/Vehicles/Air/parachute/Animations/parachute_idle.baf

animationSystem.createBundle parachute_deploy
animationBundle.fadeInTime 0.1
animationBundle.fadeOutTime 0.2
animationBundle.isLooping 0
animationBundle.addAnimation Objects/Vehicles/Air/parachute/Animations/parachute_deploy.baf

animationSystem.createBundle parachute_collapse
animationBundle.fadeInTime 0.1
animationBundle.fadeOutTime 0.2
animationBundle.isLooping 0
animationBundle.addAnimation Objects/Vehicles/Air/parachute/Animations/parachute_colaps.baf

rem *** Triggers ***
animationSystem.createTrigger MessageTrigger collapse
animationTrigger.addBundle parachute_collapse
animationTrigger.message 4

animationSystem.createTrigger Trigger root
animationTrigger.addChild collapse
animationTrigger.addBundle parachute_idle

animationSystem.createTrigger Trigger startup
animationTrigger.addBundle parachute_deploy

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root
animationTrigger.addChild startup


