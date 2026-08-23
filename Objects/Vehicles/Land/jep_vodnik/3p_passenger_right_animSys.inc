
rem *** Animations ***
animationSystem.createAnimation Objects/Vehicles/Land/JEP_Vodnik/Animations/3p/3p_vodnik_rear_right.baf

rem *** Bundles ***
animationSystem.createBundle still
animationBundle.fadeInTime 0
animationBundle.fadeOutTime 0
animationBundle.addAnimation Objects/Vehicles/Land/JEP_Vodnik/Animations/3p/3p_vodnik_rear_right.baf


rem *** Triggers ***
animationSystem.createTrigger Trigger root
animationTrigger.addBundle still

