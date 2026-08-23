
rem *** Animations ***
animationSystem.createAnimation Objects/staticobjects/military/objects/air_repairstation/Animations/wind_cone_idle.baf

rem *** Bundles ***
animationSystem.createBundle cone_idle
animationBundle.fadeInTime 0.1
animationBundle.fadeOutTime 0.2
animationBundle.addAnimation Objects/staticobjects/military/objects/air_repairstation/Animations/wind_cone_idle.baf

rem *** Triggers ***
animationSystem.createTrigger Trigger root
animationTrigger.addBundle cone_idle



