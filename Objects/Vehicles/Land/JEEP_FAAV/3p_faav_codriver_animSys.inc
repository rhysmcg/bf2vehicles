
rem *** Animations ***
animationSystem.createAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_codriver_die.baf
animationSystem.createAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_codriver_static.baf

rem *** Bundles ***
animationSystem.createBundle die
animationBundle.fadeInTime 0.4
animationBundle.fadeOutTime 0
animationBundle.addAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_codriver_die.baf

animationSystem.createBundle still
animationBundle.fadeInTime 0
animationBundle.fadeOutTime 0
animationBundle.addAnimation Objects/Vehicles/Land/JEEP_FAAV/Animations/3p/3p_faav_codriver_static.baf


rem *** Triggers ***
animationSystem.createTrigger Trigger root
animationTrigger.addBundle still

animationSystem.createTrigger Trigger die
animationTrigger.addBundle die

animationSystem.createTrigger Trigger completeTree
animationTrigger.addChild root
animationTrigger.addChild die

