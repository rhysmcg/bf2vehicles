
rem *** Animations ***
animationSystem.createAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_uh60_passenger_chair.baf

rem *** Bundles ***
animationSystem.createBundle still
animationBundle.fadeInTime 0
animationBundle.fadeOutTime 0
animationBundle.addAnimation Objects/Vehicles/Air/USTHE_UH60/Animations/3p/3p_uh60_passenger_chair.baf


rem *** Triggers ***
animationSystem.createTrigger Trigger root
animationTrigger.addBundle still

